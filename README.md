# SVscanner
![Illustration](/images/svscanner_logo.png)

A workflow to annotate tandem repeats and mobile elements within structural variants (SVs) using [Tandem Repeat Finder (TRF)](https://github.com/Benson-Genomics-Lab/TRF) and [RepeatMasker (RM)](https://github.com/Dfam-consortium/RepeatMasker).

## Overview

### Inputs:
1. A structural variant (SV) file in VCF format
2. A reference genome
### Process:
1. Flanking sequences are extracted around each SV to form a query sequence (details about the [extraction process](docs/sv_extraction.md)):
    - query_sequence = left_flank + SV + right_flank
2. These query sequences are annotated using TRF and RM.

### Outputs:
1. A VCF file with repeat annotations embedded (details about [VCF INFO tags](docs/repeat_annotation_VCF_tags.md) and [annotation process](docs/repeat_annotation_steps.md)).
2. Diagrams visualizing Repeat/SV annotations (details about the [diagram file format](docs/Repeat-SV_diagram.md)).
3. Histograms and density plots summarizing Repeat/SV annotations.

![Illustration](/images/SVscanner_workflow.png)

### Notes:
1. STRchive dataset for genome (in extended BED format) is optional input for `repeat_annotation.py`([hg19](https://strchive.org/_astro/STRchive-disease-loci.hg19.DWACvaXd.bed), [hg38](https://strchive.org/_astro/STRchive-disease-loci.hg38.DR-UScgX.bed), [T2T-chm13](https://strchive.org/_astro/STRchive-disease-loci.T2T-chm13.Cm-HAugT.bed))
2. Usage of [run_workflow.sh](docs/Commands.md#run_workflowsh)
3. Usage of workflow components: [extract_sv.py](docs/Commands.md#extrract_svpy), [repeat_annotation.py](docs/Commands.md#repeat_annotatoinpy), [generate_plots.py](docs/Commands.md#generate_plotpy)

## Installation 

1. Clone the repository

```
git clone git@github.com:GenTechGp/SVscanner.git
```

2. Set up Virtual Environment and install required packages. Tested with `python 3.8` and should work with higher versions as well.

```
cd SVscanner
python3 -m venv svscanner
source svscanner/bin/activate 
pip install --upgrade pip
pip install -r requirements.txt
```

3. Follow instruction listed [here](docs/install_rm.md) to install `RepeatMasker` if not available already.

    If you already have Dfam FamDB partition files (`dfam*.h5`) elsewhere, or your RepeatMasker
    installation is read-only, point SVscanner at them instead of moving them into the install:

    ```
    export SVSCANNER_DFAM_DIR=/path/to/dfam   # or pass --dfam_dir
    ```

    See [External Dfam databases](docs/Commands.md#external-dfam-databases).

4. Check if the following tools are available. If not install them.
 - `bcftools` (v1.21 or above recommended)
 - `bgzip` (v1.21 or above recommended)
 - `tabix` (v1.21 or above recommended)
 - `trf`
 - `parallel`
 
```
./scripts/install_tools.sh [tools to be installed]
e.g. ./scripts/install_tools.sh bcftools htslib
```
*`htslib` installs both `bgzip` and `tabix`

5. Check if the workflow is working
```
./scripts/run_workflow.sh --help
```
`run_workflow.sh` resolves its own paths, so it can be invoked from any working directory — not just the repository root.

## Quick example run

The following example processes the `test/HG002_subset_mini/HG002_subset_mini.vcf.gz` dataset (100 records).

It will take about 10 minutes. The majority of time is taken by the RepeatMasker step. Please provide the path to human genome after `--ref` argument.

```
./scripts/run_workflow.sh --vcf test/HG002_subset_mini/HG002_subset_mini.vcf.gz --ref [human genome] --out test/output
```

## SVscanner in a container

A prebuilt image is published to the GitHub Container Registry on every release, so nothing
needs cloning or compiling:

```
docker run --rm -v /path/to/dfam:/dfam:ro -v "$PWD":/data \
  ghcr.io/gentechgp/svscanner:0.6.1 \
  svscanner --dfam_dir /dfam --vcf /data/[vcf] --ref /data/[ref] --out /data/[out]
```

The image carries RepeatMasker, TRF, bcftools and the Python environment, but **not** the
Dfam database — `-species human` needs the ~57 GB Mammalia partition, which you download
once and mount. Full details, including Singularity and Nextflow usage, are in
[docs/docker.md](docs/docker.md).

## SVscanner on NCI Gadi (project if89)

`SVscanner` is available as an `if89` module, so nothing needs to be cloned or installed. You need membership of project `if89`.

```
module use -a /g/data/if89/apps/modulefiles
module load SVscanner/0.5.2
svscanner --out [path_to_out] --vcf [path_to_vcf] --ref [path_to_ref]
```

`svscanner` wraps [run_workflow.sh](scripts/run_workflow.sh) and takes the same arguments — run `svscanner --help` for the full list, or `module avail SVscanner` to see the installed versions.

Example job script:

```bash
#!/bin/bash
#PBS -P [your_project]
#PBS -l storage=gdata/if89+gdata/[project_holding_your_data]
#PBS -l ncpus=48
#PBS -l mem=128GB
#PBS -l walltime=06:00:00
#PBS -l wd

module use -a /g/data/if89/apps/modulefiles
module load SVscanner/0.5.2

svscanner --out $OUT --vcf $VCF --ref $REF
```

```
qsub -N [job_name] -v OUT=[path_to_out],VCF=[path_to_vcf],REF=[path_to_ref] [job_script]
```

### Notes
1. **Thread and job allocation.** The workflow sizes itself from your PBS allocation automatically — `$PBS_NCPUS`, falling back to the CPUs available to the process — so neither flag is normally needed. RepeatMasker is then run as `--njob` parallel processes of `--nthread / --njob` threads each (`-pa`), defaulting to one process per thread. Examples for a job requesting `#PBS -l ncpus=48`:

    | flags | RepeatMasker processes | threads each (`-pa`) | total |
    |---|---|---|---|
    | *(none — default)* | 48 | 1 | 48 |
    | `--njob 24` | 24 | 2 | 48 |
    | `--njob 12` | 12 | 4 | 48 |
    | `--njob 8` | 8 | 6 | 48 |
    | `--nthread 24` | 24 | 1 | 24 |
    | `--nthread 24 --njob 6` | 6 | 4 | 24 |

    Fewer, wider processes (`--njob 12`) suit a small number of very long query sequences; the default suits many short ones. `--njob` is capped at `--nthread`, and each process always gets at least one thread, so the total never exceeds your allocation. **Versions before `0.5.2` sized themselves from the whole compute node**, so pass `--nthread` explicitly if you load an older module.
2. Your job needs `storage=gdata/if89` in addition to whichever projects hold your VCF and reference.
3. `TRF`, `RepeatMasker`, `bcftools`, `bgzip`, `tabix` and `GNU parallel` are loaded automatically as module dependencies, alongside a self-contained Python environment. Nothing needs installing.
4. Bundled test data and the STRchive BED live under `$SVSCANNER_TESTDATA`. To confirm your setup works (~10 minutes, 100 records):
```
svscanner --vcf $SVSCANNER_TESTDATA/HG002_subset_mini/HG002_subset_mini.vcf.gz \
          --ref [human genome] --out ./svscanner_test
```
5. Database Dfam `3.9`; FamDB Format `2.0`; Partition `7` [dfam39_full.7.h5]: Mammalia (57 GB) is used with RepeatMasker module (`4.2.0`) [more info](https://www.dfam.org/releases/Dfam_3.9/families/FamDB/README.txt) 
6. A simple workflow runtime benchmark done on NCI Gadi ([link](docs/nci_benchmark.md))
7. To run a development checkout on Gadi instead of the module, use [scripts/nci_gadi_if89.sh](scripts/nci_gadi_if89.sh), which loads the same dependencies as modules.

## Releasing

The version number lives only in the [VERSION](VERSION) file, which `run_workflow.sh` reads at startup. CI and a pre-push hook both reject a release tag `vX.Y.Z` published on a commit that does not say `X.Y.Z`. See [docs/releasing.md](docs/releasing.md).

## Bug Reports

Please report/request any issues/features via [GitHub Issues](https://github.com/GenTechGp/SVscanner/issues).