#!/bin/bash

# TE annotation pipeline

# TO DO
# add help message
# add vm mode for softwares running in docker
# change docker with singularity

# Usage for a complete run (consensi discovery, automatic curation, genome annotation):
# ./script.sh --species Drosophila_melanogaster --output ~/TEannotation_pipeline/TEannotation_benchmarking/results --threads 6 --run-dnapt2x --reads ~/TEannotation_pipeline/Drosophila_pectinifera_sample.fastq.gz --genome-size 1000000 --run-rm2 --run-edta --assembly ~/TEannotation_pipeline/GCA_000001215.4_sample.fa --run-mchelper --busco-lineage diptera --vc-mode

#############################
# TO EDIT
# Fill up the variables with programs full paths. If a program is in $PATH or running in Docker replace the path with ""

RM2_PATH=${HOME}/softwares/RepeatModeler-2.0.4/
DNAPT_PATH=${HOME}/bin/pipeline_dnapipe/
RM_PATH=${HOME}/softwares/RepeatMasker-4.1.5/
EDTA_PATH=${HOME}/bin/EDTA/
MCHELPER_PATH=${HOME}/bin/mchelper/
CONDA_PATH=${HOME}/miniconda3/
#############################
# DO NOT EDIT BELOW THIS LINE

set -e

THREADS=1
SAMPLING_SIZE="0.25"

while [[ $# -gt 0 ]]; do
	case $1 in
		--use-rm2-output) # use previous RM2 result instead of running RM2 from scratch (optional) - supply RM2 output directory previously generated
		RM2_OUTPUT="$2"
		shift # past argument
		shift # past value
		;;
		--species) # MANDATORY argument for species name: used to name the parent directory with all the analyses outputs and as files prefix
		SPECIES="$2"
		shift
		shift
		;;
		--assembly) # MANDATORY argument for assembly name
		ASSEMBLY="$2"
		shift
		shift
		;;
		--reads) # fastq file (mandatory if --run-dnapt2x is used)
		READS="$2"
		shift
		shift
		;;
		--output) # MANDATORY argument for main output directory
		OUT="$2"
		shift
		shift
		;;
		--threads) # number of threads to use (optional; default 1)
		THREADS="$2"
		shift
		shift
		;;
		--run-rm2) # run RM2 from scratch (optional)
		RUN_RM2="1"
		shift
		;;
		--use-dnapt2x-output) # use previous dnaPT contigs instead of running dnaPT2x from scratch (optional) - supply dnaPipeTE directory previously generated
		DNAPT2X_OUTPUT="$2"
		shift
		shift
		;;
		--run-dnapt2x) # run dnaPT2X form scratch (optional)
		RUN_DNAPT2X="1"
		shift
		;;
		--genome-size)
		GENOME_SIZE="$2" # supply genome size for dnaPT (mandatory if --run-dnapt2x is used)
		shift
		shift
		;;
		--sampling-size) # coverage used by dnaPT (optional)
		SAMPLING_SIZE="$2"
		shift
		shift
		;;
		--run-edta) # run EDTA from scratch (optional)
		RUN_EDTA="1"
		shift
		;;
		--use-edta-output) # use previous EDTA result instead of running it from scratch (optional) - supply EDTA directory previously generated
		EDTA_OUTPUT="1"
		shift
		;;
		--run-mchelper) # run automated curation of all produced libraries altogether (optional)
		RUN_MCHELPER="1"
		shift
		;;
		--busco-lineage) # choose the busco dataset (all lowercase) used by MCHelper for false positive detection (mandatory if --run-mchelper is used) - see https://busco-data.ezlab.org/v5/data/lineages/ for available lineages
		BUSCO_LINEAGE="$2"
		shift
		shift
		;;
		--run-mask) # run RepeatMasker with the final library (optional)
		RUN_MASK="1"
		shift
		;;
		--container-mode) # use this option if RepeatModeler2 and RepeatMasker are used in the te-tools docker image
		CONTAINER_MODE="1"
		shift
		;;
	esac
done

# handle missing mandatory arguments

if [[ ! -v SPECIES ]] || [[ ! -v OUT ]]; then
	echo "Either --species or --output are missing"
	exit 1
fi

if [[ -v RUN_DNAPT2X ]] && [[ ! -v GENOME_SIZE ]]; then
	echo "Please supply --genome-size to run dnaPipeTE"
	exit 1
fi

if [[ -v RUN_DNAPT2X ]] && [[ ! -v READS ]]; then
	echo "Please supply --reads to run dnaPipeTE"
	exit 1
fi

if [[ -v RUN_RM2 ]] || [[ -v RUN_EDTA ]] || [[ -v RUN_MASK ]] && [[ ! -v ASSEMBLY ]]; then
	echo "Please supply --assembly for TE discovery, automated curation, and/or masking"
	exit 1
fi

if [[ -v RUN_MCHELPER ]] && [[ ! -v BUSCO_LINEAGE ]]; then
	echo "Please supply --busco-lineage to run MCHelper"
	exit 1
fi

# set environment variables

OUT_SP=${OUT}/${SPECIES}

if [[ -v ASSEMBLY ]]; then

	BASENAME_ASSEMBLY=$(basename ${ASSEMBLY})

fi

if [[ -v RUN_MCHELPER ]] || [[ -v RUN_EDTA ]]; then

	source ${CONDA_PATH}/etc/profile.d/conda.sh

fi

# Set up te-tools container if --vm-mode is on

#if [[ -v VM_MODE ]]; then

#	echo "Running RepeatModeler2 inside docker container"
#	docker stop $(docker ps -a -q) && docker rm $(docker ps -a -q)
#	docker run --name tetools -d -i -t dfam/tetools
#	docker cp $ASSEMBLY tetools:/opt/src/
#	docker exec -it tetools bash
#	BuildDatabase -name ${SPECIES} -engine ncbi $ASSEMBLY
#	RepeatModeler -engine ncbi -threads $THREADS -database ${RM2_OUTPUT}/${SPECIES}
#	RM2_LIB=$(readlink -f ${SPECIES}\-families.fa)
	
#fi

# TE discovery step

## RM2 submodule: obtain de novo families from RepeatModeler2

if [ "$RUN_RM2" = "1" ] && [ ! -v VM_MODE ]; then

	RM2_OUTPUT=${OUT_SP}/RepeatModeler2
	mkdir -p $RM2_OUTPUT
	echo "Running RepeatModeler2"
	"${RM2_PATH}"BuildDatabase -name ${RM2_OUTPUT}/${SPECIES} -engine ncbi $ASSEMBLY
	(
	cd $RM2_OUTPUT
	"${RM2_PATH}"RepeatModeler -engine ncbi -threads $THREADS -database ${RM2_OUTPUT}/${SPECIES}
	RM2_LIB=$(readlink -f ${SPECIES}\-families.fa)
	)

elif [ "$RUN_RM2" = "1" ] && [ -v VM_MODE ]; then

	echo "Running RepeatModeler2 in te-tools container"

# run RM2 in container

else

	echo "Skipping RepeatModeler2"

fi

# RM2 check: *families.fa should exist if one of the two arguments was used

if [[ -v RUN_RM2 ]] || [[ -v RM2_OUTPUT ]]; then

	if [[ ! -f ${RM2_OUTPUT}/${SPECIES}\-families.fa ]]; then

		echo "Could not find RepeatModeler2 families at ${RM2_OUTPUT}"
		exit 1

	else

		RM2_LIB=$(readlink -f ${RM2_OUTPUT}/${SPECIES}\-families.fa)
		
	fi
fi

## dnaPipeTE submodule: run 2rounds of dnaPipeTE and extract the dnaPipeTE contigs generated by the 2nd round ("quick & clean")

if [ "$RUN_DNAPT2X" = "1" ]; then

	DNAPT2X_OUTPUT=${OUT_SP}/dnaPipeTE2x
	mkdir -p ${DNAPT2X_OUTPUT}
	echo "Running dnaPipeTE 2x module"

	(
		ABS_DNAPT2X_OUTPUT=$(readlink -f $DNAPT2X_OUTPUT)
		ABS_READS=$(readlink -f $READS)
		ACC_NUM=$(basename ${READS%fastq.gz})
		cd $DNAPT_PATH && snakemake all --use-conda -j $THREADS -C genome_size=$GENOME_SIZE sampling_size=$SAMPLING_SIZE out_dir=${ABS_DNAPT2X_OUTPUT} short_reads=$ABS_READS species=$SPECIES acc_num=${ACC_NUM}
	)

else

	echo "Skipping dnaPipeTE 2x module"

fi

## dnaPipeTE output check: a dnaPipeTE output should exist if one of the two arguments was used 

if [[ -v RUN_DNAPT2X ]] || [[ -v DNAPT2X_OUTPUT ]]; then

	if [[ ! -f ${DNAPT2X_OUTPUT}/final_dnapipete_output/Trinity.fasta ]]; then

		echo "Could not find dnaPipeTE contigs at ${DNAPT2X_OUTPUT}/final_dnapipete_output/"
		exit 1

	else

		DNAPT2X_LIB=$(readlink -f ${DNAPT2X_OUTPUT}/final_dnapipete_output/Trinity.fasta)

	fi
fi

## EDTA submodule

if [ "$RUN_EDTA" = "1" ]; then

	EDTA_OUTPUT=${OUT_SP}/EDTA
	mkdir -p ${EDTA_OUTPUT}
	echo "Running EDTA"
	conda activate EDTA
	(
		cd $EDTA_OUTPUT
		EDTA.pl --genome $ASSEMBLY --threads $THREADS
	)
	conda deactivate

else

	echo "Skipping EDTA module"
	
fi

## EDTA output check: a EDTA output should exist if one of the two arguments was used

if [[ -v RUN_EDTA ]] || [[ -v EDTA_OUTPUT ]]; then

	if [[ ! -f "${EDTA_OUTPUT}"/"${BASENAME_ASSEMBLY}".mod.EDTA.TElib.fa ]]; then

		echo "Could not find EDTA output at ${EDTA_OUTPUT}"
		exit 1

	else

		EDTA_LIB=$(readlink -f "${EDTA_OUTPUT}"/"${BASENAME_ASSEMBLY}".mod.EDTA.TElib.fa)
	fi
fi

# Concatenate libraries and handle consensi duplicates in case of pipeline rerun
# (output from one module is not added to mergelibs.fa if families from the same tool are already present

LIBS_OUTPUT=${OUT_SP}/mergedlibs_precuration
mkdir -p ${LIBS_OUTPUT}

if [[ -v RUN_RM2 ]] || [[ -v RM2_OUTPUT ]]; then

	if [[ -f ${LIBS_OUTPUT}/mergedlibs.fa ]] && grep -q "RM2_" ${LIBS_OUTPUT}/mergedlibs.fa; then
	
		echo -e "${RM2_LIB} is not being added to ${LIBS_OUTPUT}/mergedlibs.fa, as families from RepeatModeler2 are already in there.\n\nIf instead you want to replace them, remove sequences with 'RM2_' prefix from mergedlibs.fa and append ${RM2_LIB} to it, then delete ${MCHELPER_OUTPUT} if needed and rerun the pipeline with --run-mchelper option."

	else

		sed 's/>/>RM2_/g' $RM2_LIB >> ${LIBS_OUTPUT}/mergedlibs.fa # add tool prefix to seqid 
	fi
fi

if [[ -v RUN_DNAPT2X ]] || [[ -v DNAPT2X_OUTPUT ]]; then

	if [[ -f ${LIBS_OUTPUT}/mergedlibs.fa ]] && grep -q "dnaPT_" ${LIBS_OUTPUT}/mergedlibs.fa; then
			
		echo -e "${DNAPT2X_LIB} is not being added to ${LIBS_OUTPUT}/mergedlibs.fa, as dnaPipeTE contigs are already in there.\n\nIf instead you want to replace them, remove sequences with 'dnaPT_' prefix from mergedlibs.fa and append ${DNAPT2X_LIB} to it, then delete ${MCHELPER_OUTPUT} if needed and rerun the pipeline with --run-mchelper option."

	else
		
		sed 's/>/>dnaPT_/g' $DNAPT2X_LIB >> ${LIBS_OUTPUT}/mergedlibs.fa
	fi
fi

if [[ -v RUN_EDTA ]] || [[ -v EDTA_OUTPUT ]]; then # output from module to develop yet

	if [[ -f ${LIBS_OUTPUT}/mergedlibs.fa ]] && grep -q "EDTA_" ${LIBS_OUTPUT}/mergedlibs.fa; then

		echo -e "${EDTA_LIB} is not being added to ${LIBS_OUTPUT}/mergedlibs.fa, as families from EDTA are already in there.\n\nIf instead you want to replace them, remove sequences with 'EDTA_' prefix from mergedlibs.fa and append ${EDTA_LIB} to it, then delete ${MCHELPER_OUTPUT} if needed and rerun the pipeline with --run-mchelper option."

	else

		sed 's/>/>EDTA_/g' $EDTA_LIB >> ${LIBS_OUTPUT}/mergedlibs.fa

	fi
fi


# Libraries curation step: run MCHelper

if [ "$RUN_MCHELPER" = "1" ]; then

	MCHELPER_OUTPUT=${OUT_SP}/MCHelper
	mkdir -p ${MCHELPER_OUTPUT}
	BUSCO_OUTPUT=${OUT_SP}/busco_profile
	mkdir -p ${BUSCO_OUTPUT}
	echo "Running MCHelper"
	conda activate MCHelper

## download busco hmm profiles

	wget -O ${BUSCO_OUTPUT}/lineages.html https://busco-data.ezlab.org/v5/data/lineages/
	TARNAME=$(grep $BUSCO_LINEAGE ${BUSCO_OUTPUT}/lineages.html | cut -d'"' -f2)
	ABS_BUSCO_PREF=${BUSCO_OUTPUT}/${BUSCO_LINEAGE}
	wget -O ${ABS_BUSCO_PREF}.tar.gz https://busco-data.ezlab.org/v5/data/lineages/${TARNAME} 
	tar -xf ${ABS_BUSCO_PREF}.tar.gz -C $BUSCO_OUTPUT
	cat ${ABS_BUSCO_PREF}_odb10/hmms/*hmm > ${ABS_BUSCO_PREF}.hmm && rm -r ${ABS_BUSCO_PREF}.tar.gz ${ABS_BUSCO_PREF}_odb10
	
	
	python3 "${MCHELPER_PATH}"MCHelper.py -r A -t $THREADS -l ${LIBS_OUTPUT}/mergedlibs.fa -o $MCHELPER_OUTPUT -g $ASSEMBLY --input_type fasta -b ${ABS_BUSCO_PREF}.hmm -a F

	conda deactivate

else

	echo "Skipping MCHelper module"
	
fi

# Masking step: use curated library to mask the genome assembly

if [ "$RUN_MASK" = "1" ]; then

	if [[ -f ${MCHELPER_OUTPUT}/curated_sequences_NR.fa ]]; then

		RM_OUTPUT=${OUT_SP}/RepeatMasker
		mkdir -p ${RM_OUTPUT}
		(
			cd $RM_OUTPUT
			echo "Running RepeatMasker with ${MCHELPER_OUTPUT}/curated_sequences_NR.fa"
			${RM_PATH}/RepeatMasker -lib ${MCHELPER_OUTPUT}/curated_sequences_NR.fa -a -gff -pa $THREADS $ASSEMBLY
		)
	else

		echo "No library to mask with at ${MCHELPER_OUTPUT}"
		exit 1

	fi

fi

