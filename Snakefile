# Snakefile, Copyright 2018, 2019 Florian G. Pflug
#
# This file is part of the iPool-Seq Analysis Pipeline
#
# The iPool-Seq Analysis Pipeline is free software: you can redistribute it
# and/or modify it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the License,
# or (at your option) any later version.
#
# The iPool-Seq Analysis Pipeline is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with the iPool-Seq Analysis Pipeline.  If not, see
# <http://www.gnu.org/licenses/

include: "scripts/snakemake.inc"

configfile: "cfg/config.yaml"

with open("VERSION") as f:
	VERSION = f.read().strip()

rule help:
	"""
	"""
	run:
		print("This is the iPool-Seq analysis pipeline version %s\n" % VERSION +
		      "Copyright 2017 - 2019 Florian G. Pflug\n"
		      "\n"
		      "Necessary input files\n"
		      "---------------------\n"
		      "\n"
		      "  cfg/your_design/reference.fa                reference genome\n"
		      "  cfg/your_design/cassette.fa                 cassette end sequences\n"
		      "  cfg/your_design/knockouts.gff               knockout cassette locations\n"
		      "\n"
		      "and for each replicate either\n"
		      "\n"
		      "  data/your_design/your_replicate-in.bam      sequenced input pool (both reads)\n"
		      "  data/your_design/your_replicate-out.bam     sequenced output pool (both reads)\n"
		      "\n"
		      "or\n"
		      "\n"
		      "  data/your_design/your_replicate-in.1.fq.gz  sequenced input pool (read 1)\n"
		      "  data/your_design/your_replicate-in.2.fq.gz  sequenced input pool (read 2)\n"
		      "  data/your_design/your_replicate-out.1.fq.gz sequenced output pool (read 1)\n"
		      "  data/your_design/your_replicate-out.2.fq.gz sequenced output pool (read 2)\n"
		      "\n"
		      "Computing abundance tables for your_replicate or your_design\n"
		      "------------------------------------------------------------\n"
		      "\n"
		      "  snakemake data/your_design/your_replicate-in.count.tab\n"
		      "  snakemake data/your_design/your_replicate-out.count.tab\n"
		      "\n"
		      "Running a differential virulence analysis for your_replicate of your_design\n"
		      "---------------------------------------------------------------------------\n"
		      "\n"
		      "  snakemake data/your_design/your_replicate.dv.tab\n"
		      "\n"
		      "This additionally generates the report data/your_design/your_replicate.dv.html\n"
		      "\n"
		      "Additional information\n"
		      "----------------------\n"
		      "\n"
		      "See README.md\n"
		      "\n"
		      "License\n"
		      "-------\n"
		      "This program is distributed in the hope that it will be useful, but WITHOUT ANY\n"
		      "WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A\n"
		      "PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.\n",
		      file=sys.stderr)

rule simulate_trumicount_output:
	"""Simulates TRUmiCount-generated count tables
	"""
	input:
		gff=config_input_file('knockouts', "data/Simulation/sim-in.count.tab")
	output:
		pool_in="data/Simulation/sim-in.count.tab",
		pool_out="data/Simulation/sim-out.count.tab",
		truth="data/Simulation/sim.truth.tab"
	script:	"scripts/ipoolseq.simulate.umicounts.R"

rule download_uhse_et_al:
	output:	"data/Uhse_et_al.2018/exp{experiment}.r{replicate}-{pool}.bam"
	params:
		pool="{pool}",
		experiment="{experiment}",
		replicate="{replicate}"
	wildcard_constraints:
		experiment="A|B",
		replicate="1|2|3",
		pool="in|out"
	shell:
		"if   [[ '{params.pool}' == 'in'  && '{params.experiment}' == 'A' ]]; then ERRID=2190337; FILE='r4896/in{params.replicate}';\n"
		"elif [[ '{params.pool}' == 'in'  && '{params.experiment}' == 'B' ]]; then ERRID=2190343; FILE='r5157/in{params.replicate}';\n"
		"elif [[ '{params.pool}' == 'out' && '{params.experiment}' == 'A' ]]; then ERRID=2190334; FILE='r4896/egb73r{params.replicate}';\n"
		"elif [[ '{params.pool}' == 'out' && '{params.experiment}' == 'B' ]]; then ERRID=2190340; FILE='r5157/od3r{params.replicate}';\n"
		"fi;\n"
		"URL='ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR219/ERR'$[$ERRID+{params.replicate}-1]/\"$FILE\"'.bam';\n"
		"echo \"Downloading $URL into {output}\";\n"
		"curl -o {output:q}\\\n"
		"  --continue -\\\n"
		"  --retry 999\\\n"
		"  --retry-max-time 0\\\n"
		"  \"$URL\""

rule bam_to_fqgz_pe:
	"""Converts a BAM files contained paired-end reads into two (parallel) compressed FASTQ files
	
	From data/{lib}.bam, the two output files data/{lib}.1.fq.fz and data/{lib}.2.fq.gz are created
	"""
	input:
		"data/{dir}/{lib}.bam"
	output:
		r1=temporary("data/{dir}/{lib}.1.fq.gz"),
		r2=temporary("data/{dir}/{lib}.2.fq.gz")
	log:
		"data/{dir}/{lib}.bam2fqgz.log"
	shell:
		"exec > >(tee {log:q}) 2>&1;\n"
		"set -e; set -o pipefail;\n"
		"echo \"*** Splitting {input} into {output.r1} and {output.r2}\";\n"
		"samtools fastq -c1\\\n"
		"  -1 {output.r1:q}\\\n"
		"  -2 {output.r2:q}\\\n"
		"  {input:q};"

rule bam_idx:
	"""Creates an index for a BAM file
	"""
	input:	"data/{dir}/{lib}.bam"
	output:	"data/{dir}/{lib}.bai"
	shell:
		"samtools index\\\n"
		"  {input:q}\\\n"
		"  {output:q}"

rule adapter_readthrough_trim_pe:
	"""Trims read-throughs into the adapter on the other end using Trimmomatic
	
	The adapter sequences and the trimming options are set via cfg/config.yaml
	"""
	input:
		r1="data/{dir}/{lib}.1.fq.gz",
		r2="data/{dir}/{lib}.2.fq.gz"
	output:
		r1=temporary("data/{dir}/{lib}.tom.1.fq.gz"),
		r2=temporary("data/{dir}/{lib}.tom.2.fq.gz")
	params:
		opts=config_options('trimmomatic', required=True),
		scratch=default_scratch
	threads: 4
	log:
		"data/{dir}/{lib}.tom.log"
	shell:
		"exec > >(tee {log:q}) 2>&1;\n"
		"export SCRATCH={params.scratch:q}; export THREADS={threads};\n"
		"scripts/trimmomatic_pe.sh\\\n"
		"  {input.r1:q}\\\n"
		"  {input.r2:q}\\\n"
		"  {output.r1:q}\\\n"
		"  {output.r2:q}\\\n"
		"  {params.opts:q}"

ruleorder: adapter_readthrough_trim_pe > bam_to_fqgz_pe

rule ipoolseq_trim_pe:
	"""Trims the iPoolSeq-specific technical sequences (including UMIs), append the UMI to the read name
	
	The read names in the output FASTQ file carry the UMI as a suffic (separated with _), and contains
	only genomic sequences -- the parts overlapping the KO cassette are removed
	"""
	input:
		r1="data/{dir}/{lib}.tom.1.fq.gz",
		r2="data/{dir}/{lib}.tom.2.fq.gz",
		fa=config_input_file('cassette', "data/{dir}/{lib}.trim.1.fq.gz")
	output:
		r1="data/{dir}/{lib}.trim.1.fq.gz",
		r2="data/{dir}/{lib}.trim.2.fq.gz"
	priority: 1
	threads: 4
	log:
		"data/{dir}/{lib}.trim.log"
	shell:
		"exec > >(tee {log:q}) 2>&1;\n"
		"export THREADS={threads};\n"
		"scripts/ipoolseq.trim.py\\\n"
		"  {input.fa:q}\\\n"
		"  {input.r1:q}\\\n"
		"  {input.r2:q}\\\n"
		"  {output.r1:q}\\\n"
		"  {output.r2:q}"

rule fastqc_pe:
	input:	"data/{dir}/{lib}.trim.{ri}.fq.gz",
	output: "data/{dir}/{lib}.fastqc.{ri}.html",
	wildcard_constraints:
		ri="1|2"
	priority: 1
	threads: 4
	shell:
		"zcat {input:q}\\\n"
		"| fastqc\\\n"
		"  --threads {threads}\\\n"
		"  --format fastq\\\n"
		"  --outdir \"$(dirname {output:q})\"\\\n"
		"  stdin:\"$(basename {output:q})\";\n"
		"rm {output:q}_fastqc.zip;\n"
		"mv {output:q}_fastqc.html {output:q};\n"

ruleorder: ipoolseq_trim_pe > bam_to_fqgz_pe

rule map_pe:
	"""Maps the (trimmed) reads to the genome

	The reference genome is set via cfg/config.yaml
	"""
	input:
		r1="data/{dir}/{lib}.trim.1.fq.gz",
		r2="data/{dir}/{lib}.trim.2.fq.gz",
		ref=config_input_file('reference_genome', "data/{dir}/{lib}.map.bam")
	output:
		bam="data/{dir}/{lib}.map.bam",
		bai="data/{dir}/{lib}.map.bai"
	log:    "data/{dir}/{lib}.map.log"
	params:
		opts=config_options('ngm'),
		scratch=default_scratch
	threads: 8
	shell:
		"exec > >(tee {log:q}) 2>&1;\n"
		"export SCRATCH={params.scratch:q}; export THREADS={threads};\n"
		"scripts/ngm_pe.sh\\\n"
		"  {input.ref:q}\\\n"
		"  {input.r1:q}\\\n"
		"  {input.r2:q}\\\n"
		"  {output.bam:q}\\\n"
		"  {output.bai:q}\\\n"
		"  {params.opts:q}"

rule ipoolseq_assign_to_knockouts_pe:
	"""Assign the mapped reads to the individual KO strains

	The output reads carry an XT tag that states the name of the KO strain (from the GFF files
	showing the positions of the KO cassette insertions) and the flank (3' or 5') of the KO
	cassette that the read belongs to, in the form '<Name>:{3,5}p'

	The GFF file listing the KO cassette insertion positions is set via cfg/config.yaml
	"""
	input:
		bam="data/{dir}/{lib}.map.bam",
		gff=config_input_file('knockouts', "data/{dir}/{lib}.assign.bam")
	output:	"data/{dir}/{lib}.assign.bam"
	log:	"data/{dir}/{lib}.assign.log"
	params:
		opts=config_options('knockout_assignment'),
	shell:
		"exec > >(tee {log:q}) 2>&1;\n"
		"scripts/ipoolseq.assign.to.knockouts.py\\\n"
		"  {params.opts}\\\n"
		"  {input.gff:q}\\\n"
		"  {input.bam:q}\\\n"
		"  {output:q}"

rule trumicount_pe:
	"""Computes the number of UMIs per flank (5' and 3') of each of the knockouts

	Uses TRUmiCount to count the raw number of UMIs (which the help of UMI-Tools), and
	to correct for UMIs that were not observed due to having too low sequencing coverage

	The TRUmiCount parameters are set via cfg/config.yaml
	"""
	input:
		bam="data/{dir}/{lib}.assign.bam",
		bai="data/{dir}/{lib}.assign.bai"
	output: counts="data/{dir}/{lib}.count.tab",
		plot="data/{dir}/{lib}.count.pdf"
	log:	"data/{dir}/{lib}.count.log"
	params:
		opts=config_options('trumicount')
	threads: 4
	shell:
		"exec > >(tee {log:q}) 2>&1;\n"
		"trumicount\\\n"
		"  --input-bam {input.bam:q}\\\n"
		"  --group-per gene\\\n"
		"  --include-filter-statistics\\\n"
		"  --output-counts {output.counts:q}\\\n"
		"  --output-plot {output.plot:q}\\\n"
		"  --umitools-option --per-gene\\\n"
		"  --umitools-option --gene-tag=XT\\\n"
                "  --molecules 1\\\n"
		"  {params.opts}\\\n" #params.opts can contain MULTPLE options, hence don't quote
		"  --cores {threads}"

rule read_stats:
	"""Collects statistics about the number of reads and UMIs remaing after each step
	"""
	input:
		raw="data/{dir}/{lib}.bam",
		map="data/{dir}/{lib}.map.bam",
		assign="data/{dir}/{lib}.assign.bam",
		count="data/{dir}/{lib}.count.tab"
	output:
		stats="data/{dir}/{lib}.stats.tab"
	threads: 4
	shell:
		"exec > >(tee {log:q}) 2>&1;\n"
		"export THREADS={threads};\n"
		"scripts/read_stats.sh\\\n"
		"  {input.raw:q}\\\n"
		"  {input.map:q}\\\n"
		"  {input.assign:q}\\\n"
		"  {input.count:q}\\\n"
		"  {output.stats:q}"

rule differential_virulence:
	"""Findes KO strains with higher a lower virulence than the wildtype
	
	Produces an HTML report and a table of log2 fold changes of knockout abundances in
	the output pool relative to a set of known-neutral knockouts (marked with 'Neutral'
	in the knockout GFF file), and normlized for differences in the knockout abundance
	in the input pool
	"""
	input:
		gff=config_input_file('knockouts', "data/{dir}/{exp}"),
		pool_in="data/{dir}/{exp}-in.count.tab",
		pool_out="data/{dir}/{exp}-out.count.tab",
		stats_in="data/{dir}/{exp}-in.stats.tab",
		stats_out="data/{dir}/{exp}-out.stats.tab",
		fastqc_html_in_r1="data/{dir}/{exp}-in.fastqc.1.html",
		fastqc_html_in_r2="data/{dir}/{exp}-in.fastqc.2.html",
		fastqc_html_out_r1="data/{dir}/{exp}-out.fastqc.1.html",
		fastqc_html_out_r2="data/{dir}/{exp}-out.fastqc.2.html",
		trumicount_pdf_in="data/{dir}/{exp}-in.count.pdf",
		trumicount_pdf_out="data/{dir}/{exp}-out.count.pdf",
		rmd="scripts/ipoolseq.differential.virulence.Rmd"
	output:
		table="data/{dir}/{exp}.dv.tab",
		html="data/{dir}/{exp}.dv.html"
	params:
		version=VERSION,
		dir="{dir}",
		exp="{exp}"
	script:	"scripts/rmarkdown.render.R"
