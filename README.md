# E. coli K-12 NGS Variant Calling Pipeline

## Overview
End-to-end variant calling pipeline built from scratch using real Illumina WGS data (SRR2584863).

## Tools Used
| Tool | Version | Purpose |
|------|---------|---------|
| FastQC | 0.12.1 | Quality control |
| fastp | 1.3.3 | Adapter trimming |
| BWA MEM | 0.7.19 | Read alignment |
| SAMtools | 1.23.1 | BAM processing |
| GATK4 | 4.6.2.0 | Variant calling |

## Pipeline Steps
1. QC raw reads with FastQC
2. Trim adapters with fastp
3. Align to reference genome with BWA MEM
4. Sort and index BAM with SAMtools
5. Mark duplicates with GATK MarkDuplicates
6. Call variants with GATK HaplotypeCaller
7. Filter SNPs and INDELs separately
8. Merge final variant set

## Results
- Total reads: 2,774,962
- Mapping rate: 94.45%
- Duplication rate: 1.49%
- Raw variants: 35,406
- Final PASS variants: 34,201 (33,047 SNPs + 1,154 INDELs)

## Usage
```bash
conda activate ngs
bash pipeline.sh
```

## Dataset
- Sample: SRR2584863 (E. coli K-12)
- Source: NCBI SRA
- Read length: 150bp paired-end
- Reference: GCF_000005845.2 (E. coli K-12 ASM584v2)
