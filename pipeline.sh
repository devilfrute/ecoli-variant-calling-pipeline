#!/bin/bash
# ================================================
# E. coli K-12 NGS Variant Calling Pipeline
# Author: Vamsi Krishna Seerla
# GitHub: https://github.com/devilfrute
# ================================================

set -e
set -u

# ── COLORS ─────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── HELPER FUNCTIONS ───────────────────────────

print_banner() {
echo -e "${CYAN}"
cat << 'EOF'
 ███╗   ██╗ ██████╗ ███████╗    ██████╗ ██╗██████╗ ███████╗██╗     ██╗███╗   ██╗███████╗
 ████╗  ██║██╔════╝ ██╔════╝    ██╔══██╗██║██╔══██╗██╔════╝██║     ██║████╗  ██║██╔════╝
 ██╔██╗ ██║██║  ███╗███████╗    ██████╔╝██║██████╔╝█████╗  ██║     ██║██╔██╗ ██║█████╗
 ██║╚██╗██║██║   ██║╚════██║    ██╔═══╝ ██║██╔═══╝ ██╔══╝  ██║     ██║██║╚██╗██║██╔══╝
 ██║ ╚████║╚██████╔╝███████║    ██║     ██║██║     ███████╗███████╗██║██║ ╚████║███████╗
 ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝    ╚═╝     ╚═╝╚═╝     ╚══════╝╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝
EOF
echo -e "${NC}"
echo -e "${BOLD}${GREEN}         E. coli K-12 Variant Calling Pipeline | by devilfrute${NC}"
echo -e "${YELLOW}         From raw FASTQ to clean VCF — one script to rule them all${NC}"
echo ""
}

step_banner() {
    local step=$1
    local title=$2
    local tip=$3
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  STEP ${step}: ${title}${NC}"
    echo -e "${YELLOW}  💡 TIP: ${tip}${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

fun_quote() {
    local quotes=(
        "Your reads are about to find their home on the genome 🏠"
        "Bases don't lie. Bad quality ones do though 🤥"
        "BWA MEM: speed dating for reads and genomes 💘"
        "Duplicates: the uninvited guests of library prep 🎉"
        "GATK HaplotypeCaller is doing the real detective work now 🔍"
        "Every SNP tells a story. Some are boring. Some get you published 📖"
        "If bioinformatics was easy, they wouldn't need you bro 😎"
        "The genome is just a very long boring book. We find the typos 📚"
        "Filtering variants: separating legends from impostors 🕵️"
        "Your future self will thank you for that README bro 🙏"
    )
    local idx=$(( RANDOM % ${#quotes[@]} ))
    echo -e "${MAGENTA}  🧬 ${quotes[$idx]}${NC}"
    echo ""
}

dna_spinner() {
    local pid=$1
    local msg=$2
    local frames=("🧬 Running... " "🔬 Running... " "⚗️  Running... " "🧪 Running... ")
    local i=0
    while kill -0 $pid 2>/dev/null; do
        printf "\r${CYAN}  ${frames[$i]}${msg}${NC}"
        i=$(( (i+1) % 4 ))
        sleep 0.5
    done
    printf "\r${GREEN}  ✅ Done: ${msg}${NC}\n"
}

ask_continue() {
    local step=$1
    echo ""
    echo -e "${YELLOW}  ▶  Ready to run: ${BOLD}${step}${NC}"
    echo -e "${CYAN}  Press ${BOLD}Enter${NC}${CYAN} to continue, ${BOLD}S${NC}${CYAN} to skip, ${BOLD}Q${NC}${CYAN} to quit${NC}"
    read -r choice
    case $choice in
        [Ss]) echo -e "${YELLOW}  ⏭  Skipping ${step}...${NC}"; return 1 ;;
        [Qq]) echo -e "${RED}  ❌ Pipeline quit by user.${NC}"; exit 0 ;;
        *) return 0 ;;
    esac
}

show_result() {
    local label=$1
    local value=$2
    echo -e "${GREEN}  ✔  ${label}: ${BOLD}${value}${NC}"
}

# ── WELCOME + USER INPUTS ──────────────────────

clear
print_banner

echo -e "${BOLD}  Welcome bro! Let's call some variants 🔥${NC}"
echo -e "${CYAN}  Answer a few questions and the pipeline runs itself.${NC}"
echo ""

# Sample accession
echo -e "${YELLOW}  Enter SRA accession number ${BOLD}[default: SRR2584863]${NC}${YELLOW}:${NC} "
read -r USER_SAMPLE
SAMPLE=${USER_SAMPLE:-SRR2584863}

# Threads
echo -e "${YELLOW}  Enter number of CPU threads ${BOLD}[default: 10]${NC}${YELLOW}:${NC} "
read -r USER_THREADS
THREADS=${USER_THREADS:-10}

# Quality threshold
echo -e "${YELLOW}  Minimum base quality for trimming ${BOLD}[default: 20]${NC}${YELLOW}:${NC} "
read -r USER_QUAL
MIN_QUAL=${USER_QUAL:-20}

# Min read length
echo -e "${YELLOW}  Minimum read length after trimming ${BOLD}[default: 50]${NC}${YELLOW}:${NC} "
read -r USER_LEN
MIN_LEN=${USER_LEN:-50}

echo ""
echo -e "${BOLD}${GREEN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Pipeline will run with:${NC}"
echo -e "${CYAN}    Sample:       ${BOLD}${SAMPLE}${NC}"
echo -e "${CYAN}    Threads:      ${BOLD}${THREADS}${NC}"
echo -e "${CYAN}    Min Quality:  ${BOLD}Q${MIN_QUAL}${NC}"
echo -e "${CYAN}    Min Length:   ${BOLD}${MIN_LEN}bp${NC}"
echo -e "${BOLD}${GREEN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}  Confirm and start? [Enter=Yes / Q=Quit]${NC}"
read -r confirm
[[ $confirm =~ [Qq] ]] && echo -e "${RED}  Cancelled.${NC}" && exit 0

# ── DIRECTORIES ────────────────────────────────
BASE_DIR=~/ngs_practice
RAW_DIR=${BASE_DIR}/day1
REF_DIR=${BASE_DIR}/reference
ALIGNED_DIR=${BASE_DIR}/aligned
VARIANTS_DIR=${BASE_DIR}/variants
REF=${REF_DIR}/ecoli_k12.fasta
mkdir -p ${RAW_DIR} ${REF_DIR} ${ALIGNED_DIR} ${VARIANTS_DIR}

START_TIME=$(date +%s)

# ══════════════════════════════════════════════
# STEP 1 — DOWNLOAD REFERENCE
# ══════════════════════════════════════════════
step_banner "1" "Download Reference Genome" \
"The reference is the 'correct' genome. We compare your sample against it to find variants."
fun_quote

if ask_continue "Download E. coli K-12 Reference"; then
    if [ ! -f ${REF} ]; then
        wget -q --show-progress \
            "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz" \
            -O ${REF_DIR}/ecoli_k12.fasta.gz
        gunzip ${REF_DIR}/ecoli_k12.fasta.gz
        mv ${REF_DIR}/GCF_000005845.2_ASM584v2_genomic.fna ${REF} 2>/dev/null || true
        show_result "Reference downloaded" "${REF}"
    else
        echo -e "${CYAN}  ℹ  Reference already exists. Skipping download.${NC}"
    fi
fi

# ══════════════════════════════════════════════
# STEP 2 — INDEX REFERENCE
# ══════════════════════════════════════════════
step_banner "2" "Index Reference Genome" \
"Indexing lets BWA search the genome in milliseconds. Without it, alignment would take forever."
fun_quote

if ask_continue "Index Reference (BWA + SAMtools + GATK dict)"; then
    if [ ! -f ${REF}.bwt ]; then
        bwa index ${REF} &
        dna_spinner $! "BWA indexing..."
        samtools faidx ${REF}
        gatk CreateSequenceDictionary -R ${REF} -O ${REF_DIR}/ecoli_k12.dict --quiet
        show_result "Index files created" "${REF}.bwt .fai .dict"
    else
        echo -e "${CYAN}  ℹ  Index already exists. Skipping.${NC}"
    fi
fi

# ══════════════════════════════════════════════
# STEP 3 — DOWNLOAD SAMPLE
# ══════════════════════════════════════════════
step_banner "3" "Download Sample: ${SAMPLE}" \
"SRA = Sequence Read Archive. Every public sequencing dataset lives here. Free to download."
fun_quote

if ask_continue "Download ${SAMPLE} from NCBI SRA"; then
    if [ ! -f ${RAW_DIR}/${SAMPLE}_1.fastq ]; then
        fasterq-dump ${SAMPLE} \
            --split-files \
            -p \
            -e ${THREADS} \
            -O ${RAW_DIR}/
        show_result "FASTQ files downloaded" "${RAW_DIR}/${SAMPLE}_1.fastq"
        show_result "File sizes" "$(ls -lh ${RAW_DIR}/${SAMPLE}_1.fastq | awk '{print $5}')"
    else
        echo -e "${CYAN}  ℹ  FASTQ already exists. Skipping.${NC}"
    fi
fi

# ══════════════════════════════════════════════
# STEP 4 — FASTQC RAW
# ══════════════════════════════════════════════
step_banner "4" "FastQC on Raw Reads" \
"Always QC before AND after trimming. If raw QC is terrible, something went wrong in the lab."
fun_quote

echo -e "${CYAN}  📊 FastQC checks: sequence quality, GC content, adapter contamination,${NC}"
echo -e "${CYAN}     duplication levels, per-base quality, overrepresented sequences.${NC}"
echo ""

if ask_continue "FastQC on raw reads"; then
    mkdir -p ${RAW_DIR}/fastqc_raw
    fastqc ${RAW_DIR}/${SAMPLE}_1.fastq \
           ${RAW_DIR}/${SAMPLE}_2.fastq \
           -t ${THREADS} \
           -o ${RAW_DIR}/fastqc_raw/ 2>/dev/null
    show_result "FastQC reports" "${RAW_DIR}/fastqc_raw/"
    echo -e "${YELLOW}  💡 Open the HTML report in your browser to check quality before trimming!${NC}"
    echo -e "${CYAN}  Open report? [Y/N]${NC}"
    read -r open_qc
    [[ $open_qc =~ [Yy] ]] && xdg-open ${RAW_DIR}/fastqc_raw/${SAMPLE}_1_fastqc.html 2>/dev/null || true
fi

# ══════════════════════════════════════════════
# STEP 5 — FASTP TRIMMING
# ══════════════════════════════════════════════
step_banner "5" "Adapter Trimming with fastp" \
"Adapters are lab chemicals that got sequenced by mistake. Remove them or get garbage alignments."
fun_quote

echo -e "${CYAN}  ⚙  Settings: Q${MIN_QUAL} quality threshold | ${MIN_LEN}bp minimum length | auto adapter detection${NC}"
echo ""

if ask_continue "Trim adapters with fastp"; then
    fastp \
      -i ${RAW_DIR}/${SAMPLE}_1.fastq \
      -I ${RAW_DIR}/${SAMPLE}_2.fastq \
      -o ${RAW_DIR}/${SAMPLE}_1_trimmed.fastq \
      -O ${RAW_DIR}/${SAMPLE}_2_trimmed.fastq \
      -h ${RAW_DIR}/fastp_report.html \
      -j ${RAW_DIR}/fastp_report.json \
      --thread ${THREADS} \
      --detect_adapter_for_pe \
      --qualified_quality_phred ${MIN_QUAL} \
      --length_required ${MIN_LEN} \
      --cut_tail \
      -w ${THREADS} 2>/dev/null
    show_result "Trimmed R1" "${RAW_DIR}/${SAMPLE}_1_trimmed.fastq"
    show_result "Trimmed R2" "${RAW_DIR}/${SAMPLE}_2_trimmed.fastq"
    echo -e "${YELLOW}  💡 fastp auto-detected Illumina TruSeq adapters — no need to specify them manually!${NC}"
fi

# ══════════════════════════════════════════════
# STEP 6 — FASTQC TRIMMED
# ══════════════════════════════════════════════
step_banner "6" "FastQC on Trimmed Reads" \
"Adapter content should now be GREEN. If it's still red after trimming, something is wrong."
fun_quote

if ask_continue "FastQC on trimmed reads"; then
    mkdir -p ${RAW_DIR}/fastqc_trimmed
    fastqc ${RAW_DIR}/${SAMPLE}_1_trimmed.fastq \
           ${RAW_DIR}/${SAMPLE}_2_trimmed.fastq \
           -t ${THREADS} \
           -o ${RAW_DIR}/fastqc_trimmed/ 2>/dev/null
    show_result "Post-trim QC reports" "${RAW_DIR}/fastqc_trimmed/"
    echo -e "${YELLOW}  💡 Compare this report with the raw FastQC — adapter warning should be gone!${NC}"
fi

# ══════════════════════════════════════════════
# STEP 7 — BWA MEM ALIGNMENT
# ══════════════════════════════════════════════
step_banner "7" "Read Alignment with BWA MEM" \
"BWA MEM finds where each read belongs on the genome. 94%+ mapping rate = good data."
fun_quote

echo -e "${CYAN}  🗺  Each of your ~2.7 million reads is about to find its place on the genome.${NC}"
echo -e "${CYAN}     Read groups are mandatory for GATK — they tag reads with sample metadata.${NC}"
echo ""

if ask_continue "Align with BWA MEM"; then
    echo -e "${CYAN}  ⏳ Aligning... this is the longest step.${NC}"
    bwa mem \
      -t ${THREADS} \
      -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tPL:ILLUMINA\tLB:lib1" \
      ${REF} \
      ${RAW_DIR}/${SAMPLE}_1_trimmed.fastq \
      ${RAW_DIR}/${SAMPLE}_2_trimmed.fastq \
      > ${ALIGNED_DIR}/${SAMPLE}.sam

    echo -e "${CYAN}  ⏳ Converting SAM → BAM → sorting → indexing...${NC}"
    samtools view -@ ${THREADS} -bS ${ALIGNED_DIR}/${SAMPLE}.sam \
      -o ${ALIGNED_DIR}/${SAMPLE}.bam
    samtools sort -@ ${THREADS} ${ALIGNED_DIR}/${SAMPLE}.bam \
      -o ${ALIGNED_DIR}/${SAMPLE}_sorted.bam
    samtools index ${ALIGNED_DIR}/${SAMPLE}_sorted.bam
    rm ${ALIGNED_DIR}/${SAMPLE}.sam ${ALIGNED_DIR}/${SAMPLE}.bam

    echo ""
    echo -e "${BOLD}${GREEN}  📊 ALIGNMENT STATISTICS:${NC}"
    FLAGSTAT=$(samtools flagstat ${ALIGNED_DIR}/${SAMPLE}_sorted.bam)
    TOTAL=$(echo "$FLAGSTAT" | grep "primary$" | awk '{print $1}')
    MAPPED=$(echo "$FLAGSTAT" | grep "primary mapped" | awk '{print $1}')
    PAIRED=$(echo "$FLAGSTAT" | grep "properly paired" | awk '{print $1}')
    MAP_RATE=$(echo "$FLAGSTAT" | grep "primary mapped" | grep -oP '\(\K[^%]+')
    show_result "Total reads" "${TOTAL}"
    show_result "Mapped reads" "${MAPPED}"
    show_result "Mapping rate" "${MAP_RATE}%"
    show_result "Properly paired" "${PAIRED}"

    if (( $(echo "$MAP_RATE > 90" | bc -l) )); then
        echo -e "${GREEN}  🎉 Excellent mapping rate! Your data is clean.${NC}"
    elif (( $(echo "$MAP_RATE > 80" | bc -l) )); then
        echo -e "${YELLOW}  ⚠  Acceptable mapping rate. Check for contamination.${NC}"
    else
        echo -e "${RED}  ❌ Low mapping rate! Check reference genome or sample quality.${NC}"
    fi
fi

# ══════════════════════════════════════════════
# STEP 8 — MARK DUPLICATES
# ══════════════════════════════════════════════
step_banner "8" "Mark Duplicates with GATK" \
"PCR duplicates are fake reads — same molecule counted multiple times. Mark them so GATK ignores them."
fun_quote

echo -e "${CYAN}  🔁 PCR amplification during library prep creates exact copies of fragments.${NC}"
echo -e "${CYAN}     We flag them — not delete — so GATK ignores them during variant calling.${NC}"
echo ""

if ask_continue "Mark duplicates with GATK MarkDuplicates"; then
    gatk MarkDuplicates \
      -I ${ALIGNED_DIR}/${SAMPLE}_sorted.bam \
      -O ${ALIGNED_DIR}/${SAMPLE}_markdup.bam \
      -M ${ALIGNED_DIR}/${SAMPLE}_dup_metrics.txt \
      --VALIDATION_STRINGENCY LENIENT \
      --CREATE_INDEX true \
      --quiet 2>/dev/null

    DUP_RATE=$(grep -A2 "PERCENT" ${ALIGNED_DIR}/${SAMPLE}_dup_metrics.txt | tail -1 | awk '{print $9}')
    DUP_PCT=$(echo "${DUP_RATE} * 100" | bc -l | xargs printf "%.2f")
    show_result "Duplication rate" "${DUP_PCT}%"

    if (( $(echo "$DUP_RATE < 0.20" | bc -l) )); then
        echo -e "${GREEN}  🎉 Low duplication — high quality library prep!${NC}"
    elif (( $(echo "$DUP_RATE < 0.40" | bc -l) )); then
        echo -e "${YELLOW}  ⚠  Moderate duplication — acceptable but not ideal.${NC}"
    else
        echo -e "${RED}  ❌ High duplication! Low input DNA or too many PCR cycles.${NC}"
    fi
fi

# ══════════════════════════════════════════════
# STEP 9 — HAPLOTYPECALLER
# ══════════════════════════════════════════════
step_banner "9" "Variant Calling — GATK HaplotypeCaller" \
"HaplotypeCaller does local de-novo assembly. This is why it's better than simple pileup callers."
fun_quote

echo -e "${CYAN}  🔍 HaplotypeCaller will:${NC}"
echo -e "${CYAN}     1. Find active regions where reads differ from reference${NC}"
echo -e "${CYAN}     2. Locally reassemble haplotypes in those regions${NC}"
echo -e "${CYAN}     3. Score each variant using Bayesian statistics${NC}"
echo -e "${CYAN}     4. Output raw VCF with ALL candidate variants${NC}"
echo ""

if ask_continue "Run GATK HaplotypeCaller"; then
    echo -e "${CYAN}  ⏳ This takes a few minutes. Perfect time for chai ☕${NC}"
    gatk HaplotypeCaller \
      -R ${REF} \
      -I ${ALIGNED_DIR}/${SAMPLE}_markdup.bam \
      -O ${VARIANTS_DIR}/${SAMPLE}_raw.vcf \
      --sample-name ${SAMPLE} \
      --quiet 2>/dev/null

    RAW_COUNT=$(grep -v "^#" ${VARIANTS_DIR}/${SAMPLE}_raw.vcf | wc -l)
    show_result "Raw variants called" "${RAW_COUNT}"
    echo -e "${YELLOW}  💡 Raw VCF contains false positives — filtering is next!${NC}"
fi

# ══════════════════════════════════════════════
# STEP 10 — VARIANT FILTERING
# ══════════════════════════════════════════════
step_banner "10" "Variant Filtering" \
"Filter SNPs and INDELs separately — they have different error profiles and thresholds."
fun_quote

echo -e "${CYAN}  🧹 SNP filters:   QD<2 | FS>60 | MQ<40 | SOR>3${NC}"
echo -e "${CYAN}  🧹 INDEL filters: QD<2 | FS>200 | SOR>10${NC}"
echo ""

if ask_continue "Filter variants (SNPs + INDELs separately)"; then
    # Select SNPs
    gatk SelectVariants -R ${REF} \
      -V ${VARIANTS_DIR}/${SAMPLE}_raw.vcf \
      --select-type-to-include SNP \
      -O ${VARIANTS_DIR}/${SAMPLE}_snps.vcf --quiet 2>/dev/null

    # Select INDELs
    gatk SelectVariants -R ${REF} \
      -V ${VARIANTS_DIR}/${SAMPLE}_raw.vcf \
      --select-type-to-include INDEL \
      -O ${VARIANTS_DIR}/${SAMPLE}_indels.vcf --quiet 2>/dev/null

    # Filter SNPs
    gatk VariantFiltration -R ${REF} \
      -V ${VARIANTS_DIR}/${SAMPLE}_snps.vcf \
      -O ${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf \
      --filter-expression "QD < 2.0"  --filter-name "QD2" \
      --filter-expression "FS > 60.0" --filter-name "FS60" \
      --filter-expression "MQ < 40.0" --filter-name "MQ40" \
      --filter-expression "SOR > 3.0" --filter-name "SOR3" \
      --quiet 2>/dev/null

    # Filter INDELs
    gatk VariantFiltration -R ${REF} \
      -V ${VARIANTS_DIR}/${SAMPLE}_indels.vcf \
      -O ${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf \
      --filter-expression "QD < 2.0"   --filter-name "QD2" \
      --filter-expression "FS > 200.0" --filter-name "FS200" \
      --filter-expression "SOR > 10.0" --filter-name "SOR10" \
      --quiet 2>/dev/null

    # Merge
    gatk MergeVcfs \
      -I ${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf \
      -I ${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf \
      -O ${VARIANTS_DIR}/${SAMPLE}_final.vcf --quiet 2>/dev/null

    PASS_SNPS=$(grep -v "^#" ${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf | grep "PASS" | wc -l)
    PASS_INDELS=$(grep -v "^#" ${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf | grep "PASS" | wc -l)
    FINAL=$(grep -v "^#" ${VARIANTS_DIR}/${SAMPLE}_final.vcf | grep "PASS" | wc -l)

    show_result "PASS SNPs" "${PASS_SNPS}"
    show_result "PASS INDELs" "${PASS_INDELS}"
    show_result "Final clean variants" "${FINAL}"
fi

# ══════════════════════════════════════════════
# FINAL SUMMARY
# ══════════════════════════════════════════════
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo ""
echo -e "${BOLD}${CYAN}"
cat << 'EOF'
  ██████╗  ██████╗ ███╗   ██╗███████╗██╗
  ██╔══██╗██╔═══██╗████╗  ██║██╔════╝██║
  ██║  ██║██║   ██║██╔██╗ ██║█████╗  ██║
  ██║  ██║██║   ██║██║╚██╗██║██╔══╝  ╚═╝
  ██████╔╝╚██████╔╝██║ ╚████║███████╗██╗
  ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚══════╝╚═╝
EOF
echo -e "${NC}"
echo -e "${BOLD}${GREEN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PIPELINE COMPLETE — FINAL SUMMARY${NC}"
echo -e "${BOLD}${GREEN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Sample:          ${BOLD}${SAMPLE}${NC}"
echo -e "${CYAN}  Threads used:    ${BOLD}${THREADS}${NC}"
echo -e "${CYAN}  Time elapsed:    ${BOLD}${MINS}m ${SECS}s${NC}"
echo -e "${CYAN}  Final VCF:       ${BOLD}${VARIANTS_DIR}/${SAMPLE}_final.vcf${NC}"
echo -e "${GREEN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${MAGENTA}  🧬 You just went from raw FASTQ to clean variants.${NC}"
echo -e "${MAGENTA}  📁 Push to GitHub. Add to your resume. You earned it.${NC}"
echo -e "${MAGENTA}  🔥 github.com/devilfrute${NC}"
echo ""
