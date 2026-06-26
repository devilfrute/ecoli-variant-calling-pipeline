#!/bin/bash
# ================================================
# E. coli K-12 NGS Variant Calling Pipeline
# Author: Vamsi Krishna Seerla
# GitHub: https://github.com/devilfrute
# Date: June 2026
# ================================================

set -e  # Stop on any error
set -u  # Stop on undefined variables

echo "========================================="
echo "  NGS VARIANT CALLING PIPELINE"
echo "  E. coli K-12 | SRR2584863"
echo "========================================="

# ── VARIABLES ──────────────────────────────────
SAMPLE="SRR2584863"
BASE_DIR=~/ngs_practice
RAW_DIR=${BASE_DIR}/day1
REF_DIR=${BASE_DIR}/reference
ALIGNED_DIR=${BASE_DIR}/aligned
VARIANTS_DIR=${BASE_DIR}/variants
REF=${REF_DIR}/ecoli_k12.fasta
THREADS=4

# ── CREATE DIRECTORIES ─────────────────────────
echo "[SETUP] Creating project directories..."
mkdir -p ${RAW_DIR} ${REF_DIR} ${ALIGNED_DIR} ${VARIANTS_DIR}

# ── STEP 1: Download Reference Genome ──────────
echo "[1/10] Downloading E. coli K-12 reference genome..."
if [ ! -f ${REF} ]; then
    wget -q --show-progress \
        "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz" \
        -O ${REF_DIR}/ecoli_k12.fasta.gz
    gunzip ${REF_DIR}/ecoli_k12.fasta.gz
    mv ${REF_DIR}/GCF_000005845.2_ASM584v2_genomic.fna ${REF} 2>/dev/null || true
    echo "    Reference downloaded."
else
    echo "    Reference already exists. Skipping."
fi

# ── STEP 2: Index Reference ────────────────────
echo "[2/10] Indexing reference genome..."
if [ ! -f ${REF}.bwt ]; then
    bwa index ${REF}
    samtools faidx ${REF}
    gatk CreateSequenceDictionary -R ${REF} -O ${REF_DIR}/ecoli_k12.dict
    echo "    Indexing done."
else
    echo "    Index already exists. Skipping."
fi

# ── STEP 3: Download Sample Data ───────────────
echo "[3/10] Downloading sample SRR2584863 from NCBI SRA..."
if [ ! -f ${RAW_DIR}/${SAMPLE}_1.fastq ]; then
    fasterq-dump ${SAMPLE} \
        --split-files \
        -p \
        -e ${THREADS} \
        -O ${RAW_DIR}/
    echo "    Download complete."
else
    echo "    FASTQ files already exist. Skipping."
fi

# ── STEP 4: FastQC on Raw Reads ────────────────
echo "[4/10] Running FastQC on raw reads..."
mkdir -p ${RAW_DIR}/fastqc_raw
fastqc ${RAW_DIR}/${SAMPLE}_1.fastq \
       ${RAW_DIR}/${SAMPLE}_2.fastq \
       -t ${THREADS} \
       -o ${RAW_DIR}/fastqc_raw/
echo "    FastQC raw done."

# ── STEP 5: Trim with fastp ────────────────────
echo "[5/10] Trimming adapters with fastp..."
fastp \
  -i ${RAW_DIR}/${SAMPLE}_1.fastq \
  -I ${RAW_DIR}/${SAMPLE}_2.fastq \
  -o ${RAW_DIR}/${SAMPLE}_1_trimmed.fastq \
  -O ${RAW_DIR}/${SAMPLE}_2_trimmed.fastq \
  -h ${RAW_DIR}/fastp_report.html \
  -j ${RAW_DIR}/fastp_report.json \
  --thread ${THREADS} \
  --detect_adapter_for_pe \
  --qualified_quality_phred 20 \
  --length_required 50 \
  --cut_tail \
  -w ${THREADS}
echo "    Trimming done."

# ── STEP 6: FastQC on Trimmed Reads ───────────
echo "[6/10] Running FastQC on trimmed reads..."
mkdir -p ${RAW_DIR}/fastqc_trimmed
fastqc ${RAW_DIR}/${SAMPLE}_1_trimmed.fastq \
       ${RAW_DIR}/${SAMPLE}_2_trimmed.fastq \
       -t ${THREADS} \
       -o ${RAW_DIR}/fastqc_trimmed/
echo "    FastQC trimmed done."

# ── STEP 7: Align with BWA MEM ─────────────────
echo "[7/10] Aligning reads with BWA MEM..."
bwa mem \
  -t ${THREADS} \
  -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tPL:ILLUMINA\tLB:lib1" \
  ${REF} \
  ${RAW_DIR}/${SAMPLE}_1_trimmed.fastq \
  ${RAW_DIR}/${SAMPLE}_2_trimmed.fastq \
  > ${ALIGNED_DIR}/${SAMPLE}.sam

# SAM → sorted BAM → index
samtools view -@ ${THREADS} -bS ${ALIGNED_DIR}/${SAMPLE}.sam \
  -o ${ALIGNED_DIR}/${SAMPLE}.bam
samtools sort -@ ${THREADS} ${ALIGNED_DIR}/${SAMPLE}.bam \
  -o ${ALIGNED_DIR}/${SAMPLE}_sorted.bam
samtools index ${ALIGNED_DIR}/${SAMPLE}_sorted.bam
rm ${ALIGNED_DIR}/${SAMPLE}.sam ${ALIGNED_DIR}/${SAMPLE}.bam

echo "    Alignment stats:"
samtools flagstat ${ALIGNED_DIR}/${SAMPLE}_sorted.bam

# ── STEP 8: Mark Duplicates ────────────────────
echo "[8/10] Marking duplicates..."
gatk MarkDuplicates \
  -I ${ALIGNED_DIR}/${SAMPLE}_sorted.bam \
  -O ${ALIGNED_DIR}/${SAMPLE}_markdup.bam \
  -M ${ALIGNED_DIR}/${SAMPLE}_dup_metrics.txt \
  --VALIDATION_STRINGENCY LENIENT \
  --CREATE_INDEX true
echo "    Duplicates marked."

# ── STEP 9: HaplotypeCaller ────────────────────
echo "[9/10] Calling variants with GATK HaplotypeCaller..."
gatk HaplotypeCaller \
  -R ${REF} \
  -I ${ALIGNED_DIR}/${SAMPLE}_markdup.bam \
  -O ${VARIANTS_DIR}/${SAMPLE}_raw.vcf \
  --sample-name ${SAMPLE}
echo "    Raw variants: $(grep -v '^#' ${VARIANTS_DIR}/${SAMPLE}_raw.vcf | wc -l)"

# ── STEP 10: Filter Variants ───────────────────
echo "[10/10] Filtering variants..."

# Separate SNPs and INDELs
gatk SelectVariants -R ${REF} \
  -V ${VARIANTS_DIR}/${SAMPLE}_raw.vcf \
  --select-type-to-include SNP \
  -O ${VARIANTS_DIR}/${SAMPLE}_snps.vcf

gatk SelectVariants -R ${REF} \
  -V ${VARIANTS_DIR}/${SAMPLE}_raw.vcf \
  --select-type-to-include INDEL \
  -O ${VARIANTS_DIR}/${SAMPLE}_indels.vcf

# Filter SNPs
gatk VariantFiltration -R ${REF} \
  -V ${VARIANTS_DIR}/${SAMPLE}_snps.vcf \
  -O ${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf \
  --filter-expression "QD < 2.0"  --filter-name "QD2" \
  --filter-expression "FS > 60.0" --filter-name "FS60" \
  --filter-expression "MQ < 40.0" --filter-name "MQ40" \
  --filter-expression "SOR > 3.0" --filter-name "SOR3"

# Filter INDELs
gatk VariantFiltration -R ${REF} \
  -V ${VARIANTS_DIR}/${SAMPLE}_indels.vcf \
  -O ${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf \
  --filter-expression "QD < 2.0"   --filter-name "QD2" \
  --filter-expression "FS > 200.0" --filter-name "FS200" \
  --filter-expression "SOR > 10.0" --filter-name "SOR10"

# Merge final VCF
gatk MergeVcfs \
  -I ${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf \
  -I ${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf \
  -O ${VARIANTS_DIR}/${SAMPLE}_final.vcf

# ── FINAL SUMMARY ──────────────────────────────
echo ""
echo "========================================="
echo "  PIPELINE COMPLETE!"
echo "========================================="
echo "  Total reads:      $(grep -v '^#' ${VARIANTS_DIR}/${SAMPLE}_raw.vcf | wc -l) raw variants"
echo "  PASS SNPs:        $(grep -v '^#' ${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf | grep 'PASS' | wc -l)"
echo "  PASS INDELs:      $(grep -v '^#' ${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf | grep 'PASS' | wc -l)"
echo "  Final variants:   $(grep -v '^#' ${VARIANTS_DIR}/${SAMPLE}
