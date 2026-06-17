#!/bin/bash
# E. coli K-12 Variant Calling Pipeline
# Author: Vamsi
# Date: June 2026

set -e  # Stop on any error
set -u  # Stop on undefined variables

echo "========================================="
echo "NGS VARIANT CALLING PIPELINE"
echo "========================================="

# ── VARIABLES ──────────────────────────────
SAMPLE="SRR2584863"
REF=~/ngs_practice/reference/ecoli_k12.fasta
RAW_DIR=~/ngs_practice/day1
ALIGNED_DIR=~/ngs_practice/aligned
VARIANTS_DIR=~/ngs_practice/variants
THREADS=4

# ── STEP 1: FastQC on raw reads ────────────
echo "[1/8] Running FastQC on raw reads..."
fastqc ${RAW_DIR}/${SAMPLE}_1.fastq \
       ${RAW_DIR}/${SAMPLE}_2.fastq \
       -t ${THREADS} \
       -o ${RAW_DIR}/

# ── STEP 2: Trim with fastp ────────────────
echo "[2/8] Trimming adapters with fastp..."
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
  --cut_tail

# ── STEP 3: Align with BWA MEM ─────────────
echo "[3/8] Aligning reads with BWA MEM..."
bwa mem \
  -t ${THREADS} \
  -R "@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tPL:ILLUMINA\tLB:lib1" \
  ${REF} \
  ${RAW_DIR}/${SAMPLE}_1_trimmed.fastq \
  ${RAW_DIR}/${SAMPLE}_2_trimmed.fastq \
  > ${ALIGNED_DIR}/${SAMPLE}.sam

# ── STEP 4: SAM to sorted BAM ──────────────
echo "[4/8] Converting and sorting BAM..."
samtools view -@ ${THREADS} -bS ${ALIGNED_DIR}/${SAMPLE}.sam \
  -o ${ALIGNED_DIR}/${SAMPLE}.bam
samtools sort -@ ${THREADS} ${ALIGNED_DIR}/${SAMPLE}.bam \
  -o ${ALIGNED_DIR}/${SAMPLE}_sorted.bam
samtools index ${ALIGNED_DIR}/${SAMPLE}_sorted.bam
rm ${ALIGNED_DIR}/${SAMPLE}.sam
rm ${ALIGNED_DIR}/${SAMPLE}.bam

# ── STEP 5: Mark Duplicates ────────────────
echo "[5/8] Marking duplicates..."
gatk MarkDuplicates \
  -I ${ALIGNED_DIR}/${SAMPLE}_sorted.bam \
  -O ${ALIGNED_DIR}/${SAMPLE}_markdup.bam \
  -M ${ALIGNED_DIR}/${SAMPLE}_dup_metrics.txt \
  --VALIDATION_STRINGENCY LENIENT \
  --CREATE_INDEX true

# ── STEP 6: HaplotypeCaller ────────────────
echo "[6/8] Calling variants with GATK HaplotypeCaller..."
gatk HaplotypeCaller \
  -R ${REF} \
  -I ${ALIGNED_DIR}/${SAMPLE}_markdup.bam \
  -O ${VARIANTS_DIR}/${SAMPLE}_raw.vcf \
  --sample-name ${SAMPLE}

# ── STEP 7: Filter Variants ────────────────
echo "[7/8] Filtering variants..."
gatk SelectVariants -R ${REF} -V ${VARIANTS_DIR}/${SAMPLE}_raw.vcf \
  --select-type-to-include SNP -O ${VARIANTS_DIR}/${SAMPLE}_snps.vcf

gatk SelectVariants -R ${REF} -V ${VARIANTS_DIR}/${SAMPLE}_raw.vcf \
  --select-type-to-include INDEL -O ${VARIANTS_DIR}/${SAMPLE}_indels.vcf

gatk VariantFiltration -R ${REF} -V ${VARIANTS_DIR}/${SAMPLE}_snps.vcf \
  -O ${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf \
  --filter-expression "QD < 2.0" --filter-name "QD2" \
  --filter-expression "FS > 60.0" --filter-name "FS60" \
  --filter-expression "MQ < 40.0" --filter-name "MQ40" \
  --filter-expression "SOR > 3.0" --filter-name "SOR3"

gatk VariantFiltration -R ${REF} -V ${VARIANTS_DIR}/${SAMPLE}_indels.vcf \
  -O ${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf \
  --filter-expression "QD < 2.0" --filter-name "QD2" \
  --filter-expression "FS > 200.0" --filter-name "FS200" \
  --filter-expression "SOR > 10.0" --filter-name "SOR10"

# ── STEP 8: Merge final VCF ────────────────
echo "[8/8] Merging filtered variants..."
gatk MergeVcfs \
  -I ${VARIANTS_DIR}/${SAMPLE}_snps_filtered.vcf \
  -I ${VARIANTS_DIR}/${SAMPLE}_indels_filtered.vcf \
  -O ${VARIANTS_DIR}/${SAMPLE}_final.vcf

echo "========================================="
echo "PIPELINE COMPLETE!"
echo "Final variants: $(grep -v '^#' ${VARIANTS_DIR}/${SAMPLE}_final.vcf | grep 'PASS' | wc -l)"
echo "========================================="
