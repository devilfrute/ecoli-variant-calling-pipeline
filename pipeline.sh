#!/bin/bash
# ================================================================
#  NGS VARIANT CALLING PIPELINE
#  Author  : Vamsi Krishna Seerla
#  GitHub  : https://github.com/devilfrute
#  Version : 2.0
#  Organism: E. coli K-12 (adaptable to any organism)
# ================================================================

# ── COLORS ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── CONDA ENV CHECK ─────────────────────────────────────────────
if [[ "${CONDA_DEFAULT_ENV}" != "ngs" ]]; then
    echo -e "${RED}  ERROR  ${NC}ngs conda environment is not active."
    echo -e "${DIM}         Run: conda activate ngs${NC}"
    echo -e "${DIM}         Then rerun: bash pipeline.sh${NC}"
    exit 1
fi

# ── HELPER FUNCTIONS ────────────────────────────────────────────

print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
  ╔══════════════════════════════════════════════════════════════╗
  ║            NGS VARIANT CALLING PIPELINE  v2.0                ║
  ║          FASTQ  →  QC  →  TRIM  →  ALIGN  →  VCF             ║
  ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${DIM}  Author : Vamsi Krishna Seerla${NC}"
    echo -e "${DIM}  GitHub : https://github.com/devilfrute${NC}"
    echo -e "${DIM}  Tools  : GATK4 HaplotypeCaller | BWA MEM | fastp | FastQC${NC}"
    echo ""
}

section() {
    local num=$1
    local title=$2
    local desc=$3
    echo ""
    echo -e "${BOLD}${BLUE}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${BLUE}  │  STEP ${num} — ${title}${NC}"
    echo -e "${BOLD}${BLUE}  └─────────────────────────────────────────────────────┘${NC}"
    echo -e "${DIM}  ${desc}${NC}"
    echo ""
}

tip()  { echo -e "${YELLOW}  NOTE  ${NC}$1"; }
ok()   { echo -e "${GREEN}  PASS  ${NC}$1"; }
warn() { echo -e "${YELLOW}  WARN  ${NC}$1"; }
fail() { echo -e "${RED}  FAIL  ${NC}$1"; }

spinner() {
    local pid=$1
    local msg=$2
    local i=0
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${frames[$i]}${NC}  %s" "$msg"
        i=$(( (i+1) % 10 ))
        sleep 0.1
    done
    printf "\r  ${GREEN}done${NC}  %-50s\n" "$msg"
}

divider() {
    echo -e "${DIM}  ──────────────────────────────────────────────────────${NC}"
}

ask_continue() {
    local step=$1
    echo ""
    divider
    echo -e "  ${BOLD}Ready:${NC} $step"
    echo -e "  ${DIM}[ Enter ] Run    [ S ] Skip    [ Q ] Quit${NC}"
    read -r choice
    case $choice in
        [Ss]) warn "Skipping: $step"; return 1 ;;
        [Qq]) echo -e "\n${RED}  Pipeline terminated by user.${NC}\n"; exit 0 ;;
        *) return 0 ;;
    esac
}

metric() {
    printf "  ${CYAN}%-25s${NC} ${BOLD}%s${NC}\n" "$1" "$2"
}

assess_mapping() {
    local rate=$1
    if (( $(echo "$rate > 90" | bc -l) )); then
        ok "Mapping rate ${rate}% — Excellent"
    elif (( $(echo "$rate > 80" | bc -l) )); then
        warn "Mapping rate ${rate}% — Acceptable, check for contamination"
    else
        fail "Mapping rate ${rate}% — Low, verify reference genome and sample quality"
    fi
}

assess_duplication() {
    local rate=$1
    local pct=$(echo "$rate * 100" | bc -l | xargs printf "%.2f")
    metric "Duplication rate" "${pct}%"
    if (( $(echo "$rate < 0.20" | bc -l) )); then
        ok "Low duplication — high quality library"
    elif (( $(echo "$rate < 0.40" | bc -l) )); then
        warn "Moderate duplication — acceptable"
    else
        fail "High duplication — check input DNA quantity and PCR cycles"
    fi
}

# ── WELCOME ─────────────────────────────────────────────────────

print_banner

echo -e "${BOLD}  PIPELINE CONFIGURATION${NC}"
divider
echo ""

echo -ne "  SRA Accession       [default: SRR2584863] : "
read -r USER_SAMPLE
SAMPLE=${USER_SAMPLE:-SRR2584863}

echo -ne "  CPU Threads         [default: 10]         : "
read -r USER_THREADS
THREADS=${USER_THREADS:-10}

echo -ne "  Min Base Quality    [default: 20]         : "
read -r USER_QUAL
MIN_QUAL=${USER_QUAL:-20}

echo -ne "  Min Read Length     [default: 50]         : "
read -r USER_LEN
MIN_LEN=${USER_LEN:-50}

echo ""
divider
echo ""
echo -e "${BOLD}  Run Configuration:${NC}"
metric "Sample"          "$SAMPLE"
metric "Threads"         "$THREADS"
metric "Min Quality"     "Q${MIN_QUAL}"
metric "Min Read Length" "${MIN_LEN}bp"
metric "Reference"       "E. coli K-12 (GCF_000005845.2)"
echo ""
divider
echo ""
echo -ne "  Confirm and start pipeline? [ Enter / Q ] : "
read -r confirm
[[ $confirm =~ [Qq] ]] && echo -e "${RED}  Cancelled.${NC}" && exit 0

# ── DIRECTORIES ─────────────────────────────────────────────────
BASE_DIR=~/ngs_pipeline
RAW_DIR=${BASE_DIR}/data/raw
TRIM_DIR=${BASE_DIR}/data/trimmed
QC_DIR=${BASE_DIR}/data/qc
REF_DIR=${BASE_DIR}/reference
ALIGNED_DIR=${BASE_DIR}/aligned
VARIANTS_DIR=${BASE_DIR}/variants
LOG_DIR=${BASE_DIR}/logs
REF=${REF_DIR}/ecoli_k12.fasta

mkdir -p "${RAW_DIR}" "${TRIM_DIR}" "${QC_DIR}" \
         "${REF_DIR}" "${ALIGNED_DIR}" \
         "${VARIANTS_DIR}" "${LOG_DIR}"

START_TIME=$(date +%s)
PIPELINE_DATE=$(date "+%Y-%m-%d %H:%M:%S")

echo ""
echo -e "${DIM}  Started : ${PIPELINE_DATE}${NC}"
echo -e "${DIM}  Log dir : ${LOG_DIR}${NC}"

# ════════════════════════════════════════════════════════════════
# STEP 1 — DOWNLOAD REFERENCE GENOME
# ════════════════════════════════════════════════════════════════
section "1" "Download Reference Genome" \
"Downloading E. coli K-12 reference (GCF_000005845.2) from NCBI FTP."
tip "The reference genome is the gold standard sequence. Variants are positions where your sample differs from it."

if ask_continue "Download E. coli K-12 reference genome"; then
    if [ ! -f "${REF}" ]; then
        wget -q --show-progress \
            "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz" \
            -O "${REF_DIR}/ecoli_k12.fasta.gz" 2>&1 | tee "${LOG_DIR}/download_ref.log"
        gunzip "${REF_DIR}/ecoli_k12.fasta.gz"
        [ -f "${REF_DIR}/GCF_000005845.2_ASM584v2_genomic.fna" ] && \
            mv "${REF_DIR}/GCF_000005845.2_ASM584v2_genomic.fna" "${REF}"
        ok "Reference downloaded: ${REF}"
        metric "Reference size" "$(ls -lh "${REF}" | awk '{print $5}')"
    else
        ok "Reference already exists — skipping download"
    fi
fi

# ════════════════════════════════════════════════════════════════
# STEP 2 — INDEX REFERENCE
# ════════════════════════════════════════════════════════════════
section "2" "Index Reference Genome" \
"Building BWA, SAMtools and GATK indexes for the reference genome."
tip "Indexing is a one-time operation. BWA uses Burrows-Wheeler Transform to enable fast read alignment."

if ask_continue "Index reference (BWA + samtools faidx + GATK dict)"; then
    if [ ! -f "${REF}.bwt" ]; then
        bwa index "${REF}" > "${LOG_DIR}/bwa_index.log" 2>&1 &
        spinner $! "BWA indexing reference genome"

        samtools faidx "${REF}"
        ok "samtools faidx complete"

        gatk CreateSequenceDictionary \
            -R "${REF}" \
            -O "${REF_DIR}/ecoli_k12.dict" \
            > "${LOG_DIR}/dict.log" 2>&1
        ok "GATK sequence dictionary created"

        ok "All index files ready"
    else
        ok "Index files already exist — skipping"
    fi
fi

# ════════════════════════════════════════════════════════════════
# STEP 3 — DOWNLOAD SAMPLE DATA
# ════════════════════════════════════════════════════════════════
section "3" "Download Sample: ${SAMPLE}" \
"Downloading raw Illumina paired-end reads from NCBI SRA."
tip "SRA (Sequence Read Archive) is the world's largest public repository of sequencing data. fasterq-dump converts .sra format to FASTQ automatically."

if ask_continue "Download ${SAMPLE} from NCBI SRA"; then
    if [ ! -f "${RAW_DIR}/${SAMPLE}_1.fastq" ]; then
        fasterq-dump "${SAMPLE}" \
            --split-files \
            -p \
            -e "${THREADS}" \
            -O "${RAW_DIR}/" 2>&1 | tee "${LOG_DIR}/fasterq.log"
        ok "Download complete"
        metric "R1 size" "$(ls -lh "${RAW_DIR}/${SAMPLE}_1.fastq" | awk '{print $5}')"
        metric "R2 size" "$(ls -lh "${RAW_DIR}/${SAMPLE}_2.fastq" | awk '{print $5}')"
    else
        ok "FASTQ files already exist — skipping download"
    fi
fi

# ════════════════════════════════════════════════════════════════
# STEP 4 — FASTQC ON RAW READS
# ════════════════════════════════════════════════════════════════
section "4" "Quality Control — Raw Reads (FastQC)" \
"Assessing raw read quality: per-base quality, adapter content, GC distribution, duplication."
tip "Always QC before and after trimming. Raw data commonly shows adapter contamination and quality drop at read 3-prime ends — both expected for Illumina data."

if ask_continue "Run FastQC on raw reads"; then
    mkdir -p "${QC_DIR}/fastqc_raw"
    fastqc "${RAW_DIR}/${SAMPLE}_1.fastq" \
           "${RAW_DIR}/${SAMPLE}_2.fastq" \
           -t "${THREADS}" \
           -o "${QC_DIR}/fastqc_raw/" \
           > "${LOG_DIR}/fastqc_raw.log" 2>&1 &
    spinner $! "FastQC processing raw reads"
    ok "FastQC reports saved to: ${QC_DIR}/fastqc_raw/"
    tip "Open ${QC_DIR}/fastqc_raw/${SAMPLE}_1_fastqc.html in browser to review quality."

    echo ""
    echo -ne "  Open FastQC report in browser now? [ Y / N ] : "
    read -r open_qc
    [[ $open_qc =~ [Yy] ]] && \
        xdg-open "${QC_DIR}/fastqc_raw/${SAMPLE}_1_fastqc.html" > /dev/null 2>&1 || true
fi

# ════════════════════════════════════════════════════════════════
# STEP 5 — ADAPTER TRIMMING WITH FASTP
# ════════════════════════════════════════════════════════════════
section "5" "Adapter Trimming — fastp" \
"Removing Illumina adapter sequences and low-quality bases from read ends."
tip "fastp auto-detects TruSeq adapters in paired-end mode. Reads shorter than ${MIN_LEN}bp after trimming are discarded — too short to align uniquely."

echo ""
metric "Quality threshold"  "Q${MIN_QUAL} (Phred)"
metric "Min read length"    "${MIN_LEN}bp"
metric "Adapter detection"  "Auto (paired-end mode)"
metric "Trimming mode"      "3-prime cut_tail"
echo ""

if ask_continue "Trim adapters and low-quality bases with fastp"; then
    fastp \
        -i "${RAW_DIR}/${SAMPLE}_1.fastq" \
        -I "${RAW_DIR}/${SAMPLE}_2.fastq" \
        -o "${TRIM_DIR}/${SAMPLE}_1_trimmed.fastq" \
        -O "${TRIM_DIR}/${SAMPLE}_2_trimmed.fastq" \
        -h "${QC_DIR}/fastp_report.html" \
        -j "${QC_DIR}/fastp_report.json" \
        --thread "${THREADS}" \
        --detect_adapter_for_pe \
        --qualified_quality_phred "${MIN_QUAL}" \
        --length_required "${MIN_LEN}" \
        --cut_tail \
        -w "${THREADS}" \
        > "${LOG_DIR}/fastp.log" 2>&1 &
    spinner $! "Trimming adapters and low-quality bases"
    ok "Trimming complete"
    metric "Trimmed R1"   "${TRIM_DIR}/${SAMPLE}_1_trimmed.fastq"
    metric "Trimmed R2"   "${TRIM_DIR}/${SAMPLE}_2_trimmed.fastq"
    metric "fastp report" "${QC_DIR}/fastp_report.html"
fi

# ════════════════════════════════════════════════════════════════
# STEP 6 — FASTQC ON TRIMMED READS
# ════════════════════════════════════════════════════════════════
section "6" "Quality Control — Trimmed Reads (FastQC)" \
"Verifying adapter removal and quality improvement post-trimming."
tip "Adapter content should now be green. Per-base quality should show improvement at 3-prime ends."

if ask_continue "Run FastQC on trimmed reads"; then
    mkdir -p "${QC_DIR}/fastqc_trimmed"
    fastqc "${TRIM_DIR}/${SAMPLE}_1_trimmed.fastq" \
           "${TRIM_DIR}/${SAMPLE}_2_trimmed.fastq" \
           -t "${THREADS}" \
           -o "${QC_DIR}/fastqc_trimmed/" \
           > "${LOG_DIR}/fastqc_trimmed.log" 2>&1 &
    spinner $! "FastQC processing trimmed reads"
    ok "Post-trim QC saved to: ${QC_DIR}/fastqc_trimmed/"
fi

# ════════════════════════════════════════════════════════════════
# STEP 7 — READ ALIGNMENT WITH BWA MEM
# ════════════════════════════════════════════════════════════════
section "7" "Read Alignment — BWA MEM" \
"Aligning trimmed reads to reference genome. Output: coordinate-sorted, indexed BAM."
tip "BWA MEM is the standard aligner for Illumina reads >70bp. Read groups are mandatory for GATK downstream processing."

echo ""
metric "Algorithm"   "BWA MEM"
metric "Read groups" "ID:${SAMPLE} SM:${SAMPLE} PL:ILLUMINA LB:lib1"
metric "Threads"     "${THREADS}"
echo ""

if ask_continue "Align reads with BWA MEM and sort BAM"; then
    echo -e "  ${DIM}Aligning reads to reference genome...${NC}"
    bwa mem \
        -t "${THREADS}" \
        -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tPL:ILLUMINA\tLB:lib1" \
        "${REF}" \
        "${TRIM_DIR}/${SAMPLE}_1_trimmed.fastq" \
        "${TRIM_DIR}/${SAMPLE}_2_trimmed.fastq" \
        > "${ALIGNED_DIR}/${SAMPLE}.sam" \
        2> "${LOG_DIR}/bwa_mem.log"
    ok "Alignment complete"

    echo -e "  ${DIM}Converting SAM to BAM...${NC}"
    samtools view -@ "${THREADS}" -bS "${ALIGNED_DIR}/${SAMPLE}.sam" \
        -o "${ALIGNED_DIR}/${SAMPLE}.bam" 2>/dev/null
    ok "SAM converted to BAM"

    samtools sort -@ "${THREADS}" "${ALIGNED_DIR}/${SAMPLE}.bam" \
        -o "${ALIGNED_DIR}/${SAMPLE}_sorted.bam" 2>/dev/null &
    spinner $! "Sorting BAM by genomic coordinate"

    samtools index "${ALIGNED_DIR}/${SAMPLE}_sorted.bam" 2>/dev/null
    ok "BAM indexed"

    rm -f "${ALIGNED_DIR}/${SAMPLE}.sam" "${ALIGNED_DIR}/${SAMPLE}.bam"

    echo ""
    echo -e "${BOLD}  Alignment Statistics:${NC}"
    divider
    FLAGSTAT=$(samtools flagstat "${ALIGNED_DIR}/${SAMPLE}_sorted.bam" 2>/dev/null)
    TOTAL=$(echo "$FLAGSTAT"      | grep "primary$"       | awk '{print $1}')
    MAPPED=$(echo "$FLAGSTAT"     | grep "primary mapped"  | awk '{print $1}')
    PAIRED=$(echo "$FLAGSTAT"     | grep "properly paired" | awk '{print $1}')
    MAP_PCT=$(echo "$FLAGSTAT"    | grep "primary mapped"  | grep -oP '\(\K[^%]+')
    SINGLETONS=$(echo "$FLAGSTAT" | grep "singletons"      | awk '{print $1}')

    metric "Total primary reads" "${TOTAL}"
    metric "Mapped reads"        "${MAPPED}"
    metric "Mapping rate"        "${MAP_PCT}%"
    metric "Properly paired"     "${PAIRED}"
    metric "Singletons"          "${SINGLETONS}"
    echo ""
    assess_mapping "${MAP_PCT}"
fi

# ════════════════════════════════════════════════════════════════
# STEP 8 — MARK DUPLICATES
# ════════════════════════════════════════════════════════════════
section "8" "Mark PCR Duplicates — GATK MarkDuplicates" \
"Flagging PCR duplicate reads so GATK HaplotypeCaller ignores them during variant calling."
tip "Duplicates are flagged (bit 1024 in FLAG), not deleted. GATK skips them automatically. High duplication suggests low input DNA or excessive PCR amplification."

if ask_continue "Mark duplicates with GATK MarkDuplicates"; then
    gatk MarkDuplicates \
        -I "${ALIGNED_DIR}/${SAMPLE}_sorted.bam" \
        -O "${ALIGNED_DIR}/${SAMPLE}_markdup.bam" \
        -M "${ALIGNED_DIR}/${SAMPLE}_dup_metrics.txt" \
        --VALIDATION_STRINGENCY LENIENT \
        --CREATE_INDEX true \
        > "${LOG_DIR}/markdup.log" 2>&1 &
    spinner $! "Marking PCR duplicates"

    echo ""
    echo -e "${BOLD}  Duplication Metrics:${NC}"
    divider
    DUP_LINE=$(grep -A2 "PERCENT_DUPLICATION" \
        "${ALIGNED_DIR}/${SAMPLE}_dup_metrics.txt" 2>/dev/null | tail -1)
    DUP_RATE=$(echo "$DUP_LINE"       | awk '{print $9}')
    LIB_SIZE=$(echo "$DUP_LINE"       | awk '{print $10}')
    READ_PAIR_DUPS=$(echo "$DUP_LINE" | awk '{print $7}')
    metric "Read pair duplicates"   "${READ_PAIR_DUPS}"
    metric "Estimated library size" "${LIB_SIZE}"
    assess_duplication "${DUP_RATE}"
fi

# ════════════════════════════════════════════════════════════════
# STEP 9 — VARIANT CALLING WITH HAPLOTYPECALLER
# ════════════════════════════════════════════════════════════════
section "9" "Variant Calling — GATK HaplotypeCaller" \
"Calling SNPs and INDELs using local de-novo assembly of active regions."
tip "HaplotypeCaller reassembles reads in active regions before calling variants. Significantly more accurate than pileup-based callers, especially for INDELs."

echo ""
metric "Caller"  "GATK HaplotypeCaller"
metric "Mode"    "Germline (default)"
metric "Output"  "${SAMPLE}_raw.vcf"
echo ""

if ask_continue "Run GATK HaplotypeCaller"; then
    gatk HaplotypeCaller \
        -R "${REF}" \
        -I "${ALIGNED_DIR}/${SAMPLE}_markdup.bam" \
        -O "${VARIANTS_DIR}/${SAMPLE}_raw.vcf" \
        --sample-name "${SAMPLE}" \
        > "${LOG_DIR}/haplotypecaller.log" 2>&1 &
    spinner $! "HaplotypeCaller — calling variants (this takes a few minutes)"

    RAW_TOTAL=$(grep -v "^#" "${VARIANTS_DIR}/${SAMPLE}_raw.vcf" | wc -l)
    RAW_SNPS=$(grep -v "^#"  "${VARIANTS_DIR}/${SAMPLE}_raw.vcf" \
        | awk 'length($4)==1 && length($5)==1' | wc -l)
    RAW_INDELS=$(( RAW_TOTAL - RAW_SNPS ))

    echo ""
    echo -e "${BOLD}  Raw Variant Counts:${NC}"
    divider
    metric "Total raw variants" "${RAW_TOTAL}"
    metric "Estimated SNPs"     "${RAW_SNPS}"
    metric "Estimated INDELs"   "${RAW_INDELS}"
    tip "Raw VCF contains false positives. Hard filtering is applied in the next step."
fi

# ════════════════════════════════════════════════════════════════
# STEP 10 — VARIANT FILTERING
# ════════════════════════════════════════════════════════════════
section "10" "Variant Filtering — GATK VariantFiltration" \
"Applying GATK hard filters to separate high-confidence variants from likely false positives."
tip "SNPs and INDELs are filtered separately — they have different error profiles. Variants failing filters are MARKED not deleted, preserving data integrity."

echo ""
echo -e "  ${BOLD}SNP filters:${NC}"
metric "QD < 2.0"   "Quality by Depth — low confidence relative to coverage"
metric "FS > 60.0"  "Fisher Strand bias — variant seen on only one strand"
metric "MQ < 40.0"  "Mapping Quality — reads aligned poorly at this locus"
metric "SOR > 3.0"  "Strand Odds Ratio — additional strand bias check"
echo ""
echo -e "  ${BOLD}INDEL filters:${NC}"
metric "QD < 2.0"   "Quality by Depth"
metric "FS > 200.0" "Fisher Strand — more lenient, INDELs show natural strand bias"
metric "SOR > 10.0" "Strand Odds Ratio"
echo ""

if ask_continue "Filter SNPs and INDELs with GATK VariantFiltration"; then

    gatk SelectVariants -R "${REF}" \
        -V "${VARIANTS_DIR}/${SAMPLE}_raw.vcf" \
        --select-type-to-include SNP \
        -O "${VARIANTS_DIR}/${SAMPLE}_snps.vcf" \
        > "${LOG_DIR}/select_snps.log" 2>&1 &
    spinner $! "Selecting SNPs"

    gatk SelectVariants -R "${REF}" \
        -V "${VARIANTS_DIR}/${SAMPLE}_raw.vcf" \
        --select-type-to-include INDEL \
        -O "${VARIANTS_DIR}/${SAMPLE}_indels.vcf" \
        > "${LOG_DIR}/select_indels.log" 2>&1 &
    spinner $! "Selecting INDELs"

    gatk VariantFiltration -R "${REF}" \
        -V "${VARIANTS_DIR}/${SAMPLE}_snps.vcf" \
        -O "${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf" \
        --filter-expression "QD < 2.0"  --filter-name "QD2" \
        --filter-expression "FS > 60.0" --filter-name "FS60" \
        --filter-expression "MQ < 40.0" --filter-name "MQ40" \
        --filter-expression "SOR > 3.0" --filter-name "SOR3" \
        > "${LOG_DIR}/filter_snps.log" 2>&1 &
    spinner $! "Filtering SNPs"

    gatk VariantFiltration -R "${REF}" \
        -V "${VARIANTS_DIR}/${SAMPLE}_indels.vcf" \
        -O "${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf" \
        --filter-expression "QD < 2.0"   --filter-name "QD2" \
        --filter-expression "FS > 200.0" --filter-name "FS200" \
        --filter-expression "SOR > 10.0" --filter-name "SOR10" \
        > "${LOG_DIR}/filter_indels.log" 2>&1 &
    spinner $! "Filtering INDELs"

    gatk MergeVcfs \
        -I "${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf" \
        -I "${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf" \
        -O "${VARIANTS_DIR}/${SAMPLE}_final.vcf" \
        > "${LOG_DIR}/merge.log" 2>&1 &
    spinner $! "Merging filtered SNPs and INDELs into final VCF"

    PASS_SNPS=$(grep -v "^#"   "${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf"   \
        | grep "PASS" | wc -l)
    PASS_INDELS=$(grep -v "^#" "${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf" \
        | grep "PASS" | wc -l)
    FAIL_SNPS=$(grep -v "^#"   "${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf"   \
        | grep -v "PASS" | wc -l)
    FAIL_INDELS=$(grep -v "^#" "${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf" \
        | grep -v "PASS" | wc -l)
    FINAL_TOTAL=$(( PASS_SNPS + PASS_INDELS ))

    echo ""
    echo -e "${BOLD}  Filtering Results:${NC}"
    divider
    metric "PASS SNPs"             "${PASS_SNPS}"
    metric "PASS INDELs"           "${PASS_INDELS}"
    metric "Filtered out (SNPs)"   "${FAIL_SNPS}"
    metric "Filtered out (INDELs)" "${FAIL_INDELS}"
    metric "Final clean variants"  "${FINAL_TOTAL}"
fi

# ════════════════════════════════════════════════════════════════
# PIPELINE SUMMARY
# ════════════════════════════════════════════════════════════════

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo ""
echo -e "${BOLD}${CYAN}"
cat << 'EOF'
  ╔══════════════════════════════════════════════════════════════╗
  ║                     PIPELINE COMPLETE                        ║
  ╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${BOLD}  Run Summary:${NC}"
divider
metric "Sample"        "${SAMPLE}"
metric "Reference"     "E. coli K-12 (GCF_000005845.2)"
metric "Threads used"  "${THREADS}"
metric "Time elapsed"  "${MINS}m ${SECS}s"
metric "Pipeline date" "${PIPELINE_DATE}"
echo ""
echo -e "${BOLD}  Output Files:${NC}"
divider
metric "Final VCF"      "${VARIANTS_DIR}/${SAMPLE}_final.vcf"
metric "Aligned BAM"    "${ALIGNED_DIR}/${SAMPLE}_markdup.bam"
metric "FastQC raw"     "${QC_DIR}/fastqc_raw/"
metric "FastQC trimmed" "${QC_DIR}/fastqc_trimmed/"
metric "fastp report"   "${QC_DIR}/fastp_report.html"
metric "Log files"      "${LOG_DIR}/"
echo ""
divider
echo ""
echo -e "${DIM}  Pipeline by Vamsi Krishna Seerla${NC}"
echo -e "${DIM}  github.com/devilfrute/ecoli-variant-calling-pipeline${NC}"
echo ""

# ── COMPLETION SOUND ────────────────────────────────────────────
mpg123 -q ~/ngs_pipeline/assets/complete.mp3 2>/dev/null || true