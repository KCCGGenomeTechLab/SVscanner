# SVscanner container

Published to the GitHub Container Registry on every release tag:

```
ghcr.io/gentechgp/svscanner:0.7.0     # a specific release
ghcr.io/gentechgp/svscanner:0.7       # latest patch of a minor series
ghcr.io/gentechgp/svscanner:latest    # latest release
```

Pin an exact version for anything whose results you intend to keep.

## What is in it

Built on [`dfam/tetools`](https://github.com/Dfam-consortium/TETools), the container image
maintained by the Dfam consortium, which supplies a correctly configured RepeatMasker.

| Component | Version | Source |
|---|---|---|
| RepeatMasker | 4.2.3 | `dfam/tetools:1.99` |
| TRF | 4.09.1 | `dfam/tetools:1.99` |
| RMBlast (default search engine) | 2.17.0 | `dfam/tetools:1.99` |
| HMMER | 3.4 | `dfam/tetools:1.99` |
| Dfam **root** partition (`dfam39_full.0.h5`) | Dfam 3.9 / FamDB 2.0 | `dfam/tetools:1.99` |
| bcftools, bgzip, tabix | 1.21 | built from source |
| GNU parallel, Python 3.11 + dependencies | Debian 12 | apt / pip |

The resolved Python package versions for a given image are recorded inside it at
`/opt/svscanner-venv/requirements.lock`.

The image is around 5.5 GB unpacked, nearly all of it the `dfam/tetools` base — which also
carries RepeatModeler, MAFFT, genometools and other tools SVscanner does not use. Building
RepeatMasker directly would produce a smaller image at the cost of maintaining that build;
the base is Dfam-maintained and correctly configured, which was judged the better trade.

## The database is not included

**The image cannot annotate human SVs on its own.** It ships only the Dfam *root*
partition, which contains no human families; `-species human` needs the **Mammalia**
partition, `dfam39_full.7.h5`, which is ~57 GB unpacked. Baking that into a public image
is not practical, so it is supplied at runtime.

Download it once, from [Dfam 3.9 FamDB](https://www.dfam.org/releases/Dfam_3.9/families/FamDB/)
(8.3 GB compressed):

```
wget https://www.dfam.org/releases/Dfam_3.9/families/FamDB/dfam39_full.7.h5.gz
gunzip dfam39_full.7.h5.gz
```

Put it in a directory of its own and point SVscanner at that directory with `--dfam_dir`
or `$SVSCANNER_DFAM_DIR`. Only the `.h5` files are needed — SVscanner combines them with
the image's own libraries at the start of each run. See
[External Dfam databases](Commands.md#external-dfam-databases) for the mechanics.

Use the Dfam **3.9** partitions: the image's RepeatMasker reads the FamDB 2.0 format, and
Dfam 4.0 files will not load.

Each run spends about 30 seconds preparing the library before annotating: RepeatMasker
derives its search library from the partition, and the image has nowhere persistent to keep
the result. It is reported in the log as `Library preparation took N seconds`, and is a
fixed cost per run rather than per variant. (The same build takes ~4 minutes under HMMER,
which is what the NCI module uses; RMBlast is markedly faster at it.)

## Docker

```
docker run --rm \
  -v /path/to/dfam:/dfam:ro \
  -v /path/to/reference:/ref:ro \
  -v "$PWD":/data \
  -e SVSCANNER_DFAM_DIR=/dfam \
  ghcr.io/gentechgp/svscanner:0.7.0 \
  svscanner --vcf /data/input.vcf.gz --ref /ref/hg38.fa --out /data/svscanner_out
```

The image's working directory is `/data`. Outputs are written as the container's user, so
add `--user "$(id -u):$(id -g)"` if you want them owned by you.

## Singularity / Apptainer

```
singularity exec \
  --bind /path/to/dfam:/dfam \
  --bind /path/to/reference:/ref \
  docker://ghcr.io/gentechgp/svscanner:0.7.0 \
  svscanner --dfam_dir /dfam --vcf input.vcf.gz --ref /ref/hg38.fa --out svscanner_out
```

The container filesystem is read only under Singularity. Nothing in SVscanner writes back
into the image — the assembled library directory lives under `--out` — so this is fine, but
it is why the Dfam database cannot simply be copied into the RepeatMasker installation.

## Nextflow

Declare the image on the process:

```groovy
process {
    withName: 'svscanner' {
        container = 'ghcr.io/gentechgp/svscanner:0.7.0'
        cpus = 32
        memory = '128GB'
        time = '16h'
    }
}
```

Two things are worth getting right in the process itself.

**Stage the Dfam directory as an input path** rather than hand-binding it per site.
Nextflow then mounts it for you, under Docker and Singularity alike:

```groovy
process svscanner {
    input:
      tuple path(vcf), path(ref), path(dfam_dir)

    script:
      """
      svscanner --dfam_dir ${dfam_dir} \\
                --vcf ${vcf} --ref ${ref} --out svscanner_out \\
                --nthread ${task.cpus}
      """
}
```

**Pass `--nthread ${task.cpus}` explicitly.** SVscanner sizes itself from `$PBS_NCPUS`, or
from `nproc` when that is unset. `nproc` honours a cpuset but not a CPU *quota*, so inside a
container limited with `--cpus` it can report the whole host and oversubscribe badly. There
is no `$PBS_NCPUS` inside the container even on a PBS cluster, because the process is not a
direct child of the job script.

## Differences from the NCI Gadi module

The if89 module and the container are not identical, and annotations can differ slightly:

| | NCI if89 module | Container |
|---|---|---|
| RepeatMasker | 4.2.0 | 4.2.3 |
| Search engine | HMMER | RMBlast |
| Dfam | 3.9, partition 7 | whatever you mount (3.9 partition 7 recommended) |

Use the module on Gadi and the container elsewhere; do not mix the two within a single
analysis without checking concordance first.

## Building locally

```
docker build -t svscanner:dev .
```

The build runs its own checks — Python dependencies, every required binary, and that
RepeatMasker's `famdb.py` can read the bundled root partition — so a build that succeeds is
one where the tooling is wired up correctly. It does not prove the annotation is correct;
that needs a real run with a real database.

The base image tag is pinned in the [Dockerfile](../Dockerfile). Read the comment there
before changing it: `dfam/tetools:2.00` and later move to Dfam 4.0 / FamDB 3.0 and will not
read Dfam 3.9 partitions.
