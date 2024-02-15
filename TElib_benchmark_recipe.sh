#!/bin/bash

# TE_library_benchmark recipe

echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
mkdir bin && cd bin
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
source /var/lib/miniforge/etc/profile.d/conda.sh

## RepeatModeler2 and RepeatMasker

docker pull dfam/tetools:latest

## dnaPipeTE-looped pipeline and contamination database: https://github.com/sigau/pipeline_dnapipe

git clone https://github.com/sigau/pipeline_dnapipe.git
#conda install -n base -c conda-forge mamba
mamba create -n bit -c conda-forge -c bioconda -c defaults -c astrobiomike bit
conda activate bit
esearch -db assembly -query '(Bacteria[orgn] OR Archaea[orgn] OR Fungi[orgn]) AND (reference_genome[filter] OR representative_genome[filter])' | esummary | xtract -pattern DocumentSummary -element AssemblyAccession > listtodownload.txt
bit-dl-ncbi-assemblies -w listtodownload.txt -f fasta
echo -n "" > pipeline_dnapipe/database_mito_conta/conta_sequence_refseq.fasta.gz
for fagz in $(ls *fa.gz); do cat $fagz >> pipeline_dnapipe/database_mito_conta/conta_sequence_refseq.fasta.gz && rm $fagz; done
conda deactivate

### pipeline dependencies
pip3 install nsdpy
sudo apt-get update && sudo apt-get install -y build-essential libssl-dev uuid-dev libgpgme11-dev squashfs-tools libseccomp-dev wget pkg-config git libgtk2.0-dev libfuse3-dev libgl1
wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
sudo tar -C /usr/local -xzvf go1.21.5.linux-amd64.tar.gz
rm go1.21.5.linux-amd64.tar.gz
echo 'export GOPATH=${HOME}/go' >> ~/.bashrc && echo 'export PATH=/usr/local/go/bin:${PATH}:${GOPATH}/bin' >> ~/.bashrc && source ~/.bashrc
wget https://github.com/sylabs/singularity/releases/download/v4.0.2/singularity-ce-4.0.2.tar.gz
tar -xzf singularity-ce-4.0.2.tar.gz && cd singularity-ce-4.0.2
./mconfig
cd builddir/
make
sudo make install

### EDTA: https://github.com/oushujun/EDTA

cd ~/bin
git clone https://github.com/oushujun/EDTA.git
cd EDTA
conda env create -f EDTA/EDTA.yml
		

### MCHelper: https://github.com/GonzalezLab/MCHelper

sudo apt install unzip
git clone https://github.com/gonzalezlab/MCHelper.git
conda env create -f MCHelper/MCHelper.yml # in some OS might be mchelper/MCHelper.yml
cd MCHelper/db
unzip '*.zip'
conda activate MCHelper
# unzip/download databases needed by MCHelper
makeblastdb -in allDatabases.clustered_rename.fa -dbtype nucl
wget https://urgi.versailles.inrae.fr/download/repet/profiles/ProfilesBankForREPET_Pfam35.0_GypsyDB.hmm.tar.gz
tar xvf ProfilesBankForREPET_Pfam35.0_GypsyDB.hmm.tar.gz
mv ProfilesBankForREPET_Pfam35.0_GypsyDB.hmm Pfam35.0.hmm
conda deactivate