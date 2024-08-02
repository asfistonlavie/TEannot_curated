#!/usr/bin/env -S bash -e

# Use this script to generate consistent apptainer / docker definition files.

NAME="TEannot_curated" # Project name.
WORKDIR="/home/teac" # Workding directory name.
ENTRY="${WORKDIR}/entry.bash" # Entry script name.
DOWNLOADS="${WORKDIR}/Downloads"

# Files can either be copied from local context `.`,
# or they will be downloaded from the given url.
if [[ -z "$1" ]]; then
    CONTEXT='.'
else
    CONTEXT="$1"
fi

# Collect dependencies in these temporary variables.
newline=$'\\\n    '
deps() {
    if [[ -z ${DEPS} ]]; then
        DEPS=${newline}"$@"
    else
        DEPS="${DEPS} "${newline}"$@"
    fi
}

# "Build" dependencies are removed after compilation.
bdeps() {
    if [[ -z ${BUILD_DEPS} ]]; then
        BUILD_DEPS=${newline}"$@"
    else
        BUILD_DEPS="${BUILD_DEPS} "${newline}"$@"
    fi
}

# "Container" dependencies are just collected/installed
# to ease the container ergonomics.
# These are installed in late layers
# so they can be tweaked without requiring a whole rebuild.
cdeps() {
    if [[ -z ${CONTAINER_DEPS} ]]; then
        CONTAINER_DEPS=${newline}"$@"
    else
        CONTAINER_DEPS="${CONTAINER_DEPS} "${newline}"$@"
    fi
}

# Intermediate layers.
LAYNAMES=()
LAYERS=()
new_layer() {
    NAME="$1"
    LAYNAMES+=( "${NAME}" )
    FOLDER="$2"
    # Dedent one level tabs, no more.
    BODY=$(cat - | dedent)
    n=$'\n'
    HEADER="# ${NAME}.$n" # To display layer name on build.
    LAYER="${HEADER}set -e$n" # To stop build on error.
    if [[ -n "${FOLDER}" ]]; then
        LAYER="${LAYER}mkdir -p ${FOLDER}$n"
        LAYER="${LAYER}cd ${FOLDER}$n"
    fi
    LAYER="${LAYER}${BODY}"
    LAYERS+=( "${LAYER}" )
}
dedent() {
    perl -pe 's/\t(\t)*/$1/g' </dev/stdin
}

#==== Dependencies =============================================================
# Build-time only dependencies.
bdeps base-devel cpio unzip
bdeps pacman-contrib
bdeps boost

# Runtime dependencies.
deps git wget
deps python python-h5py
deps libpng mariadb util-linux-libs rsync # For UCSC? Not sure whether it's bdep.
deps perl-json perl-file-which perl-uri # For RepeatModeler.
deps which libxcrypt-compat # For EDTA.
deps libglvnd python-pandas # For MCHelper.

# Container ergonomics.
cdeps zsh
#=== Recipe layers. ============================================================

# Shallow clone.
glones="git clone --recursive --depth 1"

new_layer "Packaged dependencies" ${WORKDIR} <<EOF
	echo 'Server = https://mirrors.kernel.org/archlinux/\$repo/os/\$arch' \\
	     > /etc/pacman.d/mirrorlist
	pacman -Syu --noconfirm
	pacman -Sy --noconfirm ${BUILD_DEPS} ${DEPS}

	# https://wiki.archlinux.org/title/MariaDB
	mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql

	# Non-packaged perl modules.
	source /etc/profile # (run perl profile to have cpan available)
	echo "yes" | cpan Devel::Size LWP::UserAgent
EOF

new_layer "Miniforge" ${DOWNLOADS} <<EOF
	file="Miniforge3-Linux-x86_64.sh"
	wget https://github.com/conda-forge/miniforge/releases/latest/download/\${file}
	prefix="/opt/miniforge"
	bash \${file} -b -p "\${prefix}"
	echo "auto_activate_base: false" >> ~/.condarc
	\${prefix}/bin/mamba init
EOF

mamba="/opt/miniforge/bin/mamba"
# Necessary before executing `mamba activate / deactivate` in layers.
sbash="source /root/.bashrc"

new_layer "RMBlast" "${DOWNLOADS}" <<EOF
	# From instructions at https://www.repeatmasker.org/rmblast/.

	# Download sources.
	wget https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.14.1/ncbi-blast-2.14.1+-src.tar.gz
	wget https://www.repeatmasker.org/rmblast/isb-2.14.1+-rmblast.patch.gz

	# Unzip.
	tar zxvf ncbi-blast-2.14.1+-src.tar.gz
	gunzip isb-2.14.1+-rmblast.patch.gz

	# Patch.
	cd ncbi-blast-2.14.1+-src
	patch -p1 < ../isb-2.14.1+-rmblast.patch

	# Compile.
	cd c++
	./configure \\
	    --with-mt \\
	    --without-debug \\
	    --without-krb5 \\
	    --without-openssl \\
	    --with-projects=scripts/projects/rmblastn/project.lst \\
	    --prefix=/opt/rmblast
	make -j \$(nproc)

	# Install.
	make install
EOF

new_layer "HMMER" "${DOWNLOADS}" <<EOF
	# From instructions at http://hmmer.org/documentation.html.
	wget http://eddylab.org/software/hmmer/hmmer.tar.gz
	tar zxf hmmer.tar.gz
	cd hmmer-3.4
	./configure --prefix /opt/hmmer
	make -j \$(nproc)
	make check -j \$(nproc)
	make install
EOF

new_layer "TRF" "${DOWNLOADS}" <<EOF
	${glones} https://github.com/Benson-Genomics-Lab/TRF
	cd TRF
	# Archlinux build tools are more recent than where TRF stopped -_-"
	# Re-run the autotools:
	autoreconf
	automake
	aclocal
	mkdir build
	cd build
	../configure --prefix /opt/trf
	make -j \$(nproc)
	make install
EOF

new_layer "RepeatMasker" "${DOWNLOADS}" <<EOF
	file="RepeatMasker-4.1.6.tar.gz"
	wget https://www.repeatmasker.org/RepeatMasker/\${file}
	gunzip \${file}
	tar xvf \${file%.gz}
	mv RepeatMasker /opt
EOF

new_layer "Recon" "${DOWNLOADS}" <<EOF
	file="RECON-1.08.tar.gz"
	wget https://www.repeatmasker.org/RepeatModeler/\${file}
	gunzip \${file}
	tar xvf \${file%.gz}
	cd \${file%.tar.gz}
	cd src
	# This used to be allowed but is a hard error now. Recon should be upgraded.
	newflag="-Wno-implicit-function-declaration"
	sed -i 's/^CFLAGS = \\(.*\\)/CFLAGS = \\1 '\${newflag}'/' Makefile
	make -j \$(nproc)
	# Unusual install procedure.
	make install
	cd ../..
	mv \${file%.tar.gz} /opt/recon
	sed -i "s|\\"\\"|\\"/opt/recon/bin\\"|" /opt/recon/scripts/recon.pl
EOF

new_layer "RepeatScout" "${DOWNLOADS}" <<EOF
	file="RepeatScout-1.0.6.tar.gz"
	wget https://www.repeatmasker.org/\${file}
	gunzip \${file}
	tar xvf \${file%.gz}
	cd \${file%.tar.gz}
	make -j \$(nproc)
	mkdir -p /opt/RepeatScout/bin
	cp build_lmer_table RepeatScout /opt/RepeatScout/bin
EOF

new_layer "UCSC" "${DOWNLOADS}" <<EOF
	version="461"
	file="userApps.v\${version}.src.tgz"
	wget http://hgdownload.soe.ucsc.edu/admin/exe/userApps.archive/\${file}
	tar xzf \${file}
	cd userApps
	make -j \$(nproc)
	mkdir -p /opt/ucsc
	cp -r bin /opt/ucsc
EOF

new_layer "GenomeTools" "${DOWNLOADS}" <<EOF
	version="1.6.2"
	file="genometools-\${version}.tar.gz"
	wget https://genometools.org/pub/\${file}
	tar xzf \${file}
	cd \${file%.tar.gz}
	make threads=yes cairo=no errorcheck=no -j \$(nproc)
	make threads=yes cairo=no prefix=/opt/genometools install
EOF

new_layer "LTR_retriever" "${DOWNLOADS}" <<EOF
	${glones} --branch v2.9.8 \\
	    https://github.com/oushujun/LTR_retriever
	cp -r LTR_retriever /opt
	sed -i \\
	    -e 's#BLAST+=#BLAST+=/opt/rmblast/bin#' \\
	    -e 's#RepeatMasker=#RepeatMasker=/opt/RepeatMasker#' \\
	    -e 's#HMMER=#HMMER=/opt/hmmer/bin#' \\
	    -e 's#CDHIT=#CDHIT=/opt/cd-hit#' \\
	    /opt/LTR_retriever/paths
EOF

new_layer "MAFFT" "${DOWNLOADS}" <<EOF
	version="7.471"
	file="mafft-\${version}-without-extensions-src.tgz"
	wget https://mafft.cbrc.jp/alignment/software/\${file}
	tar xzf \${file}
	cd \${file%-src.tgz}
	cd core
	sed -i 's#^PREFIX =.*#PREFIX = /opt/mafft#' Makefile
	make -j \$(nproc)
	make install
EOF

new_layer "Cd-Hit" "${DOWNLOADS}" <<EOF
	version="v4.8.1-2019-0228"
	file="cd-hit-\${version}.tar.gz"
	wget https://github.com/weizhongli/cdhit/releases/download/V4.8.1/\${file}
	tar xzf \${file}
	cd \${file%.tar.gz}
	make -j \$(nproc)
	mkdir -p /opt/cd-hit
	PREFIX=/opt/cd-hit make install
EOF

new_layer "Ninja" "${DOWNLOADS}" <<EOF
	version="0.99"
	${glones} --branch \${version}-cluster_only \\
	    https://github.com/TravisWheelerLab/NINJA
	cd NINJA
	make build -j \${nproc}
	cp -r NINJA /opt/ninja
EOF

new_layer "RepeatModeler" "${DOWNLOADS}" <<EOF
	version="2.0.5"
	${glones} --branch \${version} \\
	    https://github.com/Dfam-consortium/RepeatModeler
	cd RepeatModeler
	perl configure                            \\
	    -cdhit_dir=/opt/cd-hit                \\
	    -genometools_dir=/opt/genometools/bin \\
	    -ltr_retriever_dir=/opt/LTR_retriever \\
	    -mafft_dir=/opt/mafft/bin             \\
	    -ninja_dir=/opt/ninja                 \\
	    -recon_dir=/opt/recon/bin             \\
	    -repeatmasker_dir=/opt/RepeatMasker   \\
	    -rmblast_dir=/opt/rmblast/bin         \\
	    -rscout_dir=/opt/RepeatScout/bin      \\
	    -trf_dir=/opt/trf/bin                 \\
	    -ucsctools_dir=/opt/ucsc
	cd ..
	mv RepeatModeler /opt
EOF

# EDTA.
new_layer "EDTA" "${DOWNLOADS}" <<EOF
	git clone --recursive --depth 1 https://github.com/oushujun/EDTA.git
	cd EDTA
	${mamba} env create --name EDTA -f EDTA*.yml
	cd ..
	mv EDTA /opt
EOF

# MCHelper.
new_layer "MCHelper" "${DOWNLOADS}" <<EOF
	${glones} https://github.com/gonzalezlab/MCHelper.git
	cd MCHelper
	${mamba} env create -f ./MCHelper.yml
	cd db
	unzip '*.zip'
	${sbash}
	mamba activate  MCHelper
	makeblastdb -in allDatabases.clustered_rename.fa -dbtype nucl
	file="ProfilesBankForREPET_Pfam35.0_GypsyDB.hmm.tar.gz"
	wget https://urgi.versailles.inrae.fr/download/repet/profiles/\${file}
	tar xvf \${file}
	mv \${file%.tar.gz} Pfam35.0.hmm
	mamba deactivate
	cd ../..
	mv MCHelper /opt
EOF

# Not strictly needed for analysis but makes the container more comfortable.
new_layer "Container ergonomics." <<EOF
	pacman -Sy --noconfirm ${CONTAINER_DEPS}
	sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
	sed -i 's/\\(ZSH_THEME="\\).*"/\\1bira"/' ~/.zshrc
	${mamba} init zsh
	source /opt/miniforge/etc/profile.d/mamba.sh
EOF

# Assuming the databases have been mounted into the container
# at /opt/dfam,
# RepeatMasker needs to be configuder *before* running the main script.
# Create an actual entry point script to handle that.
new_layer "RepeatMasker configuration" "${WORKDIR}" <<EOF
	cat <<-'EOF' > ./entry.bash
		#!/usr/bin/env -S bash -e -x
		cd /opt/RepeatMasker
		for file in \$(ls /opt/dfam/*.h5); do
		    ln -s \$file ./Libraries/famdb
		done
		perl configure \\
		    -hmmer_dir=/opt/hmmer/bin \\
		    -rmblast_dir=/opt/rmblast/bin \\
		    -libdir=/opt/RepeatMasker/Libraries \\
		    -trf_prgm=/opt/trf/bin/trf \\
		    -default_search_engine=rmblast
		cd ${WORKDIR}
		./pipeline.bash \$@
	EOF
	chmod a+x ./entry.bash
EOF

new_layer "Cleanup" <<EOF
	# Remove the packages downloaded to image's Pacman cache dir.
	paccache -r -k0

	# Uninstall build-only dependencies.
	pacman -Rns --noconfirm ${BUILD_DEPS}

	# Cleanup heavy installation downloads.
	rm -rf ${DOWNLOADS}
EOF

read -r -d '' ENVIRONMENT <<EOF || true
	PATH=\$PATH:/opt/EDTA
EOF

# List files to copy in.
# TODO: whitespace in paths would break this.
read -r -d '' FILES <<EOF || true
	script.sh /home/teac/pipeline.bash
EOF

# If files must be downloaded, then add an extra layer to do so.
if [[ "${CONTEXT}" == '.' ]]; then
    # Either take files from the local context with COPY/%files commands.
    APTFILES="%files"$'\n    '"${FILES}"
    DOCKFILES=""
    while IFS= read -r line; do
        DOCKFILES=${DOCKFILES}$'\n'"COPY ${line}"
    done <<< "${FILES}"
else
    # Or add an extra layer to download them.
    DOWNLOADS=""
    while IFS= read -r line; do
        # TODO: whitespace breaks this implementation.
        src="${line% *}"
        tgt="${line#* }"
        DOWNLOADS=${DOWNLOADS}$'\n'"wget ${CONTEXT}/${src} -O ${tgt}"
        DOWNLOADS=${DOWNLOADS}$'\n'"chmod a+x ${tgt}"
    done <<< "${FILES}"

    new_layer "Download files" "${WORKDIR}" <<< "${DOWNLOADS}"
fi

#=== Generate Apptainer file =================================================

FILENAME="apptainer.def"

APTLAYERS=""
for (( i=0; i<${#LAYERS[@]}; ++i)); do
    layer=${LAYERS[i]}
    name=${LAYNAMES[i]}
    n=$'\n'
    sep="#-------------------------------------------------------------------"
    APTLAYERS="${APTLAYERS}$n$sep$n${layer}$n"
done

APTENV=$ENVIRONMENT

cat <<EOF > $FILENAME
BootStrap: docker
From: archlinux

# This file was generated from ./containerize.bash.

#===============================================================================
%post
echo "Building container.."

${APTLAYERS}

echo "export CONTAINER_BUILD_TIME=\\"\$(date)\\"" >> \${APPTAINER_ENVIRONMENT}
#===============================================================================

%environment
    ${ENVIRONMENT}

${APTFILES}

%runscript
    echo "Running ${NAME} container (created on \${CONTAINER_BUILD_TIME})"
    ${ENTRY} \$@
EOF
echo "Generated ${FILENAME}"

#=== Generate Docker file ======================================================

FILENAME="Dockerfile"

DOCKLAYERS=""
for (( i=0; i<${#LAYERS[@]}; ++i)); do
    layer=${LAYERS[i]}
    name=${LAYNAMES[i]}
    n=$'\n'
    # Re-indent to re-insert into a heredoc section.
    layer=$(sed 's/.\+/\t&/g' <<< $layer)
    DOCKLAYERS="${DOCKLAYERS}${n}RUN <<EOF$n${layer}${n}EOF$n"
done

DOCKENV=""
while IFS= read -r line; do
    DOCKENV=${DOCKENV}$'\n'"ENV ${line}"
done <<< "${ENVIRONMENT}"

cat <<DEOF > $FILENAME
# syntax=docker/dockerfile:1.3-labs
FROM archlinux

# This file was generated from ./containerize.bash.

$DOCKLAYERS
$DOCKENV
$DOCKFILES

# Now pick a folder to work within.
RUN mkdir -p ${WORKDIR}
WORKDIR ${WORKDIR}

ENTRYPOINT ["${ENTRY}"]
DEOF
echo "Generated $FILENAME"

exit 0
