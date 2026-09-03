# Commands
1. [run_workflow.sh](#run_workflowsh)
2. [extract_sv.py](#extract_svpy)
3. [repeat_annotatoin.py](#repeat_annotatoinpy)
4. [generate_plot.py](#generate_plotpy)
5. [simulate_sv.py](#simulate_svpy)

## run_workflow.sh

---

**Required Arguments**

| Argument       | Type   | Description                                                        |
|----------------|--------|--------------------------------------------------------------------|
| `--out`        | `str`  | **Path to the output directory**.                                 |
| `--vcf`        | `str`  | **Path to the structural variant (SV) VCF file**.                 |
| `--ref`        | `str`  | **Path to the reference FASTA file**.                             |

---

**Optional Arguments**

| Argument                        | Type           | Default                 | Description                                                                 |
|---------------------------------|----------------|-------------------------|-----------------------------------------------------------------------------|
| `--prefix`                      | `str`          | `None`                  | Prefix for output files.                                                    |
| `--str_bed`                     | `str`          | `None`              | Path to BED file containing STR (short tandem repeat) elements.            |
| `--species`                     | `str`          | `human`              | Species name used by RepeatMasker.                                         |
| `--dfam_dir`                    | `str`          | `$SVSCANNER_DFAM_DIR` | Directory of Dfam FamDB partition files (`dfam*.h5`) for RepeatMasker to use in addition to the ones bundled with the RepeatMasker install. See [External Dfam databases](#external-dfam-databases). |
| `--min_sv_coverage`             | `float`        | `0.05`      | Minimum intersection between a repeat element and SV.                      |
| `--min_class_sv_coverage`       | `float`        | `0.25`| Minimum class-level SV coverage to be considered repetitive.               |
| `--min_total_sv_coverage`       | `float`        | `0.75`| Minimum total SV coverage by repeats to be considered repetitive.          |
| `--max_trf_overlap`             | `float`        | `0.1`      | Maximum TRF element overlap to be considered non-overlapping.              |
| `--interval`                    | `int`          | `0.05`             | Interval value for binning or windowing.                                   |
| `--diagram_len`                 | `int`          | `100`          | Length of the diagram generated for visualization.                         |
| `--nsplit_files`                | `int`          | `500`         | Number of files to split sequences into.                                   |
| `--keep_tmp_files`             | flag           |                         | Keep intermediate files (default: delete after run).                       |
| `--overwrite`                  | flag           |                         | Overwrite existing output files if present.                                |
| `--nthread`                    | `int`          | all available threads   | Number of threads to use.                                                  |
| `--njob`                       | `int`          | `48`             | Number of parallel jobs for RepeatMasker.                                  |
| `--help`                       | flag           |                         | Show help message and exit.                                                |
| `--version`                    | flag           |                         | Show version information and exit.                                         |

---

### External Dfam databases

RepeatMasker reads its Dfam families from FamDB partition files (`dfam*.h5`) in the
`Libraries/famdb` directory of its own installation. `--dfam_dir` (or the
`SVSCANNER_DFAM_DIR` environment variable, which the flag overrides) lets you keep those
partitions somewhere else — useful when the RepeatMasker installation is read-only, shared,
or inside a container, and the database is not.

Point it at a directory containing the `.h5` files themselves; nothing else is required:

```
export SVSCANNER_DFAM_DIR=/path/to/dfam
./scripts/run_workflow.sh --vcf [vcf] --ref [ref] --out [out]
```

SVscanner assembles a valid RepeatMasker `Libraries` directory under the output directory,
symlinking the installation's own files and overlaying your partitions on top, then exports
`LIBDIR` so RepeatMasker picks it up. The partitions are never copied, so a 57 GB file costs
nothing, and the assembled directory is removed with the other temporary files at the end of
the run. Files in `--dfam_dir` take precedence over same-named files in the installation.

RepeatMasker derives a search library from the partitions the first time it is asked for a
given species, and caches it. With `--dfam_dir` that cache is built inside the assembled
directory, so it is **rebuilt on every run**. For `-species human` against the Dfam 3.9
Mammalia partition that was measured at ~30 seconds with RMBlast and ~4 minutes with HMMER.
The run log reports it as `Library preparation took N seconds`.

The installation's own cache directories are deliberately *not* reused. Their names record
the database title and version but not which partitions were present when they were built,
and `--dfam_dir` exists precisely to add partitions the installation lacks — so an
inherited cache would be stale, and RepeatMasker would reuse it without complaint.

`-species human` needs the **Mammalia** partition (`dfam39_full.7.h5` for Dfam 3.9, ~57 GB)
in addition to the root partition. RepeatMasker ships the root partition, so in practice only
the clade partition needs to be downloaded — see the
[Dfam releases](https://www.dfam.org/releases/) page. Make sure the partitions match the
FamDB format your RepeatMasker version expects (Dfam 3.9 / FamDB 2.0 for RepeatMasker
4.1.8–4.2.3).

## extract_sv.py

---

**Required Arguments**

| Argument              | Type   | Description                                                                 |
|-----------------------|--------|-----------------------------------------------------------------------------|
| `-v`, `--vcf`         | `str`  | **Path to the input VCF file** (can be compressed or uncompressed).        |
| `-r`, `--ref`         | `str`  | **Path to the reference FASTA file**.                                      |
| `-o`, `--out`         | `str`  | **Output directory** to write the resulting FASTA and other files.         |
| `-i`, `--info`        | `str`  | **Path to write the info file** describing processed SVs.                  |

---

**Optional Arguments**

| Argument               | Type           | Default | Description                                                                                       |
|------------------------|----------------|---------|---------------------------------------------------------------------------------------------------|
| `--min`                | `positive int` | `50`    | Minimum SV length to include.                                                                     |
| `--max`                | `positive int` | `50000` | Maximum SV length to include.                                                                     |
| `--flen`               | `positive int` | `2000`  | Max detectable period size supported by TRF (used to determine flanking sequence length).         |
| `--ffac`               | `positive int` | `10`    | Multiplication factor for `SVLEN` to determine flanking sequence length.                          |
| `-n`                   | `positive int` | `1`     | Number of output FASTA files to split sequences evenly into.                                      |
| `--debug`              | flag           |         | Enable debug mode. Prints extra information for troubleshooting.                                  |
| `--warning_count`      | `positive int` | `10`    | Maximum number of warnings to show for each type of warning.                                      |
| `-h`, `--help`         | flag           |         | Show help message and exit.                                                                       |

---

*The `flen` and `ffac` arguments control how much **flanking sequence** is extracted around each SV.

## repeat_annotatoin.py

**Required Arguments**

| Argument      | Type | Required | Description |
|---------------|------|----------|-------------|
| `-v`, `--vcf` | str  | Yes      | Path to the input VCF file (compressed or uncompressed) |
| `--rm`        | str  | Yes      | Path to the RepeatMasker `.out` file |
| `--trf`       | str  | Yes      | Path to the TRF `.dat` file |
| `-i`, `--info`| str  | Yes      | Path to the SV info file |
| `--str`       | str  | Yes      | Path to the STRchive BED file |
| `-o`, `--out` | str  | Yes      | Path to the output directory |

**Optional Arguments**

| Argument                 | Type   | Default | Description |
|--------------------------|--------|---------|-------------|
| `--min_sv_coverage`      | float  | 0.05    | Minimum intersection between a repeat element and a structural variant (0 < value < 1) |
| `--min_class_sv_coverage`| float  | 0.25    | Minimum class-level coverage to consider SV repetitive |
| `--min_total_sv_coverage`| float  | 0.75    | Minimum total repeat coverage for an SV to be considered repetitive |
| `--max_trf_overlap`      | float  | 0.1     | Maximum allowed TRF element overlap (0 < value < 1) |
| `--div`                  | float  | 0.05    | Divisor used to prioritize period size over intersection (0 < value < 1) |
| `-l`, `--len`            | int    | 100     | Diagram length (must be > 0) |
| `--debug`                | flag   | False   | Enable debug mode |
| `-h`, `--help`           | flag   | -       | Show help message and exit |


## generate_plot.py

| Argument      | Required | Description                 |
|---------------|----------|-----------------------------|
| `--tsv`       | Yes      | Path to input TSV file      |
| `--out`       | Yes      | Output directory            |

## simulate_sv.py

**Required Arguments**

| Argument        | Type   | Description                                 | Default |
|-----------------|--------|---------------------------------------------|---------|
| `-m`, `--mob`   | str    | Path to the Mobile Elements file            | —       |
| `-r`, `--rep`   | str    | Path to the Repeats file                    | —       |
| `-o`, `--out`   | str    | Path to the output directory                | —       |

**Optional Arguments**

| Argument           | Type          | Description                                                                                   | Default     |
|--------------------|---------------|-----------------------------------------------------------------------------------------------|-------------|
| `--seed`           | positive int  | The seed for random generator                                                                 | 42          |
| `--len`            | positive int  | The length of the simulated base reference (before editing with SVs)                         | 100000000   |
| `-n`               | positive int  | Number of SVs to simulate                                                                     | 100         |
| `--min`            | positive int  | Minimum length of SV                                                                          | 50          |
| `--max`            | positive int  | Maximum length of SV. Not applicable to TRE and TRC. See `--read_len`                        | 50000       |
| `--flen`           | positive int  | Max detectable period size supported by TRF to determine the length of flanking sequences    | 2000        |
| `--read_len`       | positive int  | Useful to simulate TRE and TRCs that can be correctly read mapped                             | 4000        |
| `--svtypes`        | str           | File with SV types to simulate. If not provided, all types are used. See `docs/SV_simulation.md` | ""      |
| `--frac`           | flag          | Simulate SVs with fractional lengths (0.25, 0.5, 0.75) of the mobile element                  | False       |
| `--simple`         | flag          | Random pick without replacement of mobile elements and repeats                                | False       |
| `--split`          | positive int  | Distribute the BED records to n files                                                         | 1           |
| `--debug`          | flag          | Debug mode                                                                                    | False       |
| `-h`, `--help`     | flag          | Show help message and exit     

