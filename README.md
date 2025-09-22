Here is a containerized version of the `TEannot_curated` pipeline.
(I am not the author of the pipeline: more information to come ;)

## Use

### With docker

Ensure you have [docker] installed.

#### Get the image.

There are three possible options.

1. Either pull the existing image from this gitlab instance
  (built for `x86_64 GNU/Linux`).

   ```sh
   $ docker pull registry.gitlab.com/iago-lito/teannot_curated
   ```

2. Or build it yourself from the distributed recipe
   if the above doesn't work on your platform:

   ```sh
   $ wget -O Dockerfile https://gitlab.com/iago-lito/teannot_curated/-/jobs/artifacts/main/raw/Dockerfile?job=container-recipes
   $ docker buildx build -t teannot_curated .
   ```

3. Or build it yourself from your own repository clone.
   This is the best option if you want to modify/develop the pipeline.
   ```sh
   $ git clone https://gitlab.com/iago-lito/teannot_curated
   $ cd teannot_curated
   $ ./containerize.bash  # Generate recipe.
   $ # <modify script.sh if you wish>
   $ docker buildx build -t teannot_curated .
   ```

#### Run the container.

1. Make sure that at least the `0`-th partition of [DFAM] databases
   is available on your machine:
    ```
    path/to/dfam/partitions/
    ├─ dfam38_full.0.h5  ← At least this one is required.
    ├─ dfam38_full.1.h5
    └─ ..
    ```

2. Make your input data available within one dedicated workspace folder:
    ```
    path/to/workspace
    └─ chromosome.fasta
    ```
  This workspace will be populated during the pipeline execution.

3. Run the pipeline:
    ```sh
    $ docker run --rm -it                    \
        -v path/to/dfam/partitions:/opt/dfam \
        -v path/to/workspace:/home/teac/ws   \
        IMAGE_NAME                           \
        --assembly ./ws/chromosome.fasta     \
        --species Your_species               \
        --busco-lineage your_lineage         \
        --output ./ws/output                 \
        --threads 20                         \
        --run-rm2                            \
        --run-edta                           \
        --run-mchelper                       \
        --run-mask
    ```
  In the above, make sure to replace:
  - `path/to/dfam` by your actual path,
    but leave the path after `:` unchanged.
  - `path/to/workspace` by your actual path,
    but leave the path after `:` unchanged.
  - `IMAGE_NAME`
    by either `registry.gitlab.com/iago-lito/teannot_curated`
    or `teannot_curated`
    depending on the way you have obtained the docker image.
    If uncertain, have a look at your `$ docker images` list.
  - `chromosome.fasta` by your actual fasta filename,
    but leave the path before `/` unchanged.
  - `Your_species`/`your_lineage` by your species/lineage of interest.

  For documentation regarding the various other pipeline options,
  please refer to `<ORIGINAL PIPELINE DOC/AUTHORS>`.

### With Apptainer/Singularity

[NOT WORKING YET]

Ensure you have [Apptainer] installed (formerly named 'Singularity').

#### Build the image

Construct the image with:

```sh
# Get definition file.
curl -L \
  https://gitlab.com/iago-lito/teannot_curated/-/jobs/artifacts/main/raw/apptainer.def?job=container-recipes \
  > teac.def # (or download by hand)

# Build image (privileges needed to build, not to run).
sudo apptainer build teac.sif teac.def
```

#### Run the container

The procedure is the same as in the
__"Run the container"__
section for docker above,
except for the command line in step 3:

```sh
$ ./teac.sif # HERE: construct.
```

[docker]: https://www.docker.com/
[Apptainer]: https://apptainer.org/
[DFAM]: https://www.dfam.org/home
