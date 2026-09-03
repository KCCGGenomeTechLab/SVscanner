#!/bin/bash

# set -x
die() { echo -e "$1" >&2 ; echo ; exit 1 ; } # terminate script

# Repository root, resolved from this script's own location so the workflow can be
# invoked from any working directory (e.g. via a module that puts it on $PATH).
SVSCANNER_HOME=$(cd -- "$(dirname -- "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd) || die "could not resolve SVscanner root"

# The VERSION file at the repository root is the single source of truth for the
# release number - never hardcode it here. scripts/check_version.sh enforces that
# this script, the README and the git tag all agree with that file.
VERSION="SVscanner v$(cat "${SVSCANNER_HOME}/VERSION" 2>/dev/null || echo unknown)"

# Input/Output (change)
#REF=$(realpath "/g/data/te53/ontsv/references/hg38_reference_files/hg38.analysisSet.fa")
#REF="/g/data/te53/variantcall/referenceresource/genome/pipeface/chm13XX.fasta"
#REF=$(realpath "/genome/hg38.analysisSet.fa")
STR_BED="${SVSCANNER_HOME}/test/databases/STRchive-disease-loci.bed"

# Repeat Masker species (change)
# SPECIES="mammalia"
SPECIES="human"

TRF_BINARY=""
REPEAT_MASKER=""
BCFTOOLS=""
BGZIP=""

# Dfam FamDB partitions (dfam*.h5) to use on top of the RepeatMasker install's own.
# Set with --dfam_dir or $SVSCANNER_DFAM_DIR (the flag wins); see setup_dfam_library.
DFAM_DIR="${SVSCANNER_DFAM_DIR:-}"

NSPLIT_FILES=500
# Under a scheduler, use the allocation rather than the whole node. Plain `nproc`
# (unlike `nproc --all`) honours the cpuset/affinity mask, so it is already
# correct on a shared node; $PBS_NCPUS is preferred where set to make it explicit.
NTHREADS=${PBS_NCPUS:-$(nproc)}
MAX_JOBS=""          # Max number of RepeatMasker processes to run in parallel (default: NTHREADS)
THREADS_PER_JOB=1    # Threads per RepeatMasker job; derived in resolve_thread_counts

# Parameters (change if necessary)
MIN_SV_COVERAGE=0.05 #The minimum intersection between a repeat element and SV (aka sv_coverage) e.g. 0.05 (5%) (0 < min_sv_coverage < 1)
MIN_CLASS_SV_COVERAGE=0.25 #The minimum class sv coverage by repeat elements to be considered repetitive
MIN_TOTAL_SV_COVERAGE=0.75 #The minimum total sv coverage by repeat elements to be considered repetitive
MAX_TRF_OVERLAP=0.1 #The maximum TRF element overlap to be considered non-overlapping (0 < max_trf_overlap < 1)
INTERVAL=0.05
DIAGRAM_LEN=100

FLAG_DELETE_TMP_FILES=1 # Flag to delete temporary files (1 = yes, 0 = no)
FLAG_OVERWRITE=0 # Flag to overwrite existing output files (1 = yes, 0 = no)
RESUME=0 # Flag to resume from existing TRF/RepeatMasker outputs (1 = yes, 0 = no)
PREFIX="" # Prefix for output files (default: None)

# Python and bash scripts (keep as it is)
CHECK_REQUIRED="${SVSCANNER_HOME}/scripts/check_required_python.sh"
EXTRACT_SV_FLANKINGS="${SVSCANNER_HOME}/src/extract_sv.py"
ANNOTATION="${SVSCANNER_HOME}/src/repeat_annotation.py"
PLOT="${SVSCANNER_HOME}/src/generate_plots.py"
TRACEBACK_PLOT="${SVSCANNER_HOME}/src/generate_traceback_plots.py"
VCF_ANNOTATE="${SVSCANNER_HOME}/src/annotate_vcf.py"

# Function to show usage
usage() {
    echo "Usage: $0 --out DIR --vcf FILE --ref FILE [options]"
    echo "Required arguments:"
    echo "  --out DIR      Path to output directory"
    echo "  --vcf FILE     Path to SV VCF file"
    echo "  --ref FILE     Path to reference FASTA file"
    echo "Optional arguments:"
    echo "  --prefix NAME           Prefix for output files (default: None; e.g. Project_, Project.)"
    echo "  --str_bed FILE          Path to STR BED file (default: $STR_BED)"
    echo "  --species NAME          Species name for RepeatMasker (default: $SPECIES)"
    echo "  --dfam_dir DIR          Directory of Dfam FamDB partition files (dfam*.h5) for RepeatMasker to use"
    echo "                          in addition to those bundled with the RepeatMasker install."
    echo "                          Defaults to \$SVSCANNER_DFAM_DIR; unset means use the install's own libraries."
    echo "  --min_sv_coverage VAL   Minimum intersection between a repeat element and SV (aka sv_coverage) (default: $MIN_SV_COVERAGE)"
    echo "  --min_class_sv_coverage VAL Minimum class sv coverage by repeat elements to be considered repetitive (default: $MIN_CLASS_SV_COVERAGE)"
    echo "  --min_total_sv_coverage VAL Minimum total sv coverage by repeat elements to be considered repetitive (default: $MIN_TOTAL_SV_COVERAGE)"
    echo "  --max_trf_overlap VAL   Maximum TRF element overlap to be considered non-overlapping (default: $MAX_TRF_OVERLAP)"
    echo "  --interval VAL          Interval value (default: $INTERVAL)"
    echo "  --diagram_len VAL       Diagram length (default: $DIAGRAM_LEN)"
    echo "  --nsplit_files INT      Number of split files (default: $NSPLIT_FILES)"
    echo "  --keep_tmp_files        Keep temporary files (default: delete)"
    echo "  --overwrite             Overwrite existing output files (default: no overwrite)"
    echo "  --resume                Reuse existing info/rm/trf .tab files and skip TRF + RepeatMasker (default: full run)"
    echo "  --nthread INT           Number of threads to use (default: \$PBS_NCPUS if set, else all threads available to this process)"
    echo "  --njob INT              Number of parallel jobs for RepeatMasker (default: same as --nthread)"
    echo "  --help                  Show this help message"
    echo "  --version               Show version information"
    echo "Version: $VERSION"
    exit 0
}

# Function to parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --out)
                OUTPUT_DIR=$(realpath "$2"); shift 2;;
            --vcf)
                VCF=$(realpath -e "$2" 2>/dev/null) || die "VCF file not found: $2"; shift 2;;
            --ref)
                REF=$(realpath -e "$2" 2>/dev/null) || die "Reference file not found: $2"; shift 2;;
            --prefix)
                PREFIX="$2"; shift 2;;
            --str_bed)
                STR_BED=$(realpath -e "$2" 2>/dev/null) || die "STR BED file not found: $2"; shift 2;;
            --species)
                SPECIES="$2"; shift 2;;
            --dfam_dir)
                DFAM_DIR=$(realpath -e "$2" 2>/dev/null) || die "Dfam directory not found: $2"; shift 2;;
            --min_sv_coverage)
                MIN_SV_COVERAGE="$2"; shift 2;;
            --min_class_sv_coverage)
                MIN_CLASS_SV_COVERAGE="$2"; shift 2;;
            --min_total_sv_coverage)
                MIN_TOTAL_SV_COVERAGE="$2"; shift 2;;
            --max_trf_overlap)
                MAX_TRF_OVERLAP="$2"; shift 2;;
            --interval)
                INTERVAL="$2"; shift 2;;
            --diagram_len)
                DIAGRAM_LEN="$2"; shift 2;;
            --nsplit_files)
                NSPLIT_FILES="$2"; shift 2;;
            --keep_tmp_files)
                FLAG_DELETE_TMP_FILES=0; shift;;
            --overwrite)
                FLAG_OVERWRITE=1; shift;;
            --resume)
                RESUME=1; shift;;
            --nthread)
                NTHREADS="$2"; shift 2;;
            --njob)
                MAX_JOBS="$2"; shift 2;;
            --help)
                usage;;
            --version)
                echo "$VERSION"; exit 0;;
            *)
                echo "Unknown argument: $1"; usage;;
        esac
    done

    # Check required arguments. --ref is only used to extract flanking regions, which --resume skips.
    if [[ -z "$OUTPUT_DIR" || -z "$VCF" ]]; then
        echo "Error: --out and --vcf are required."
        usage
    fi
    if [[ ${RESUME} -ne 1 && -z "$REF" ]]; then
        echo "Error: --ref is required for a full run."
        usage
    fi

    # --resume reuses the existing output dir; --overwrite would delete it. Disallow both.
    if [[ ${RESUME} -eq 1 && ${FLAG_OVERWRITE} -eq 1 ]]; then
        die "Error: --resume and --overwrite are mutually exclusive (--overwrite deletes the .tab files --resume needs)."
    fi

    # Internal directories (keep as it is)
    EXTRACT_SV_FLANKS_OUT=${OUTPUT_DIR}/${PREFIX}extract_sv_flanks_out
    ANNOTATIONS_OUT=${OUTPUT_DIR}/${PREFIX}annotations_out
    RM_TMP=${OUTPUT_DIR}/RMtmp
    # Assembled RepeatMasker Libraries directory; only created when --dfam_dir is in use.
    RM_LIBDIR=${OUTPUT_DIR}/${PREFIX}rm_libraries
    # File Intermediates (keep as it is)
    INFO_FILE=${OUTPUT_DIR}/${PREFIX}info.tab
    RM_FILE=${OUTPUT_DIR}/${PREFIX}rm.tab
    TRF_FILE=${OUTPUT_DIR}/${PREFIX}trf.tab

    # Final Outputs (change if necessary)
    ANNOTATED_VCF=${OUTPUT_DIR}/${PREFIX}annotated.vcf
}

resolve_thread_counts() {
    # One RepeatMasker process per available thread by default, matching the
    # previous behaviour on a full node (48 jobs x 1 thread).
    [[ -z "${MAX_JOBS}" ]] && MAX_JOBS=${NTHREADS}

    # Never run more parallel jobs than we have threads, and never hand
    # RepeatMasker '-pa 0', which integer division would otherwise produce
    # whenever MAX_JOBS exceeds NTHREADS.
    (( MAX_JOBS < 1 )) && MAX_JOBS=1
    (( MAX_JOBS > NTHREADS )) && MAX_JOBS=${NTHREADS}

    THREADS_PER_JOB=$(( NTHREADS / MAX_JOBS ))
    (( THREADS_PER_JOB < 1 )) && THREADS_PER_JOB=1
}

check_binary() {
    local name=$1
    shift
    local candidates=("$@")

    for cmd in "${candidates[@]}"; do
        if [[ -f "$cmd" && -x "$cmd" ]]; then
            echo "$(realpath "$cmd")"
            return 0
        fi

        local full_path
        full_path=$(command -v "$cmd" 2>/dev/null)
        if [[ -n "$full_path" ]]; then
            echo "$full_path"
            return 0
        fi
    done

    die "$name binary not found in any of: ${candidates[*]}"
}

check_required() {
    # 1. Check Python version
    ${CHECK_REQUIRED} || die "Python version check failed"

    [ -z "$OUTPUT_DIR" ] && die "OUTPUT_DIR is not set"
    [[ ${RESUME} -ne 1 && -z "$REF" ]] && die "REF is not set"
    [ -z "$VCF" ] && die "VCF is not set"
    [ -z "$STR_BED" ] && die "STR_BED is not set"

    echo "Output dir: ${OUTPUT_DIR}"
    echo "Reference: ${REF}"
    echo "Input SV VCF: ${VCF}"
    echo "Input BED: ${STR_BED}"

    echo "Number of Threads: ${NTHREADS}"
    echo "Number of RepeatMasker jobs: ${MAX_JOBS} (${THREADS_PER_JOB} thread(s) each)"

    # TRF and RepeatMasker are only needed for a full run; --resume reuses their .tab outputs.
    if [[ ${RESUME} -ne 1 ]]; then
        TRF_BINARY=$(check_binary "TRF" "trf" "trf409.linux64") || exit 1
        REPEAT_MASKER=$(check_binary "RepeatMasker" "RepeatMasker" "RepeatMasker/RepeatMasker") || exit 1
        parallel=$(command -v parallel) || die "parallel not found"
        echo "REPEAT_MASKER: ${REPEAT_MASKER}"
        echo "TRF_BINARY: ${TRF_BINARY}"
        echo "parallel: ${parallel}"

        # Fail on a bad --dfam_dir before doing any work, not after the extraction step.
        if [[ -n "${DFAM_DIR}" ]]; then
            [[ -d "${DFAM_DIR}" ]] || die "Dfam directory not found: ${DFAM_DIR}"
            local h5_count
            h5_count=$(find "${DFAM_DIR}" -maxdepth 1 -name '*.h5' | wc -l)
            (( h5_count > 0 )) || die "No FamDB partition files (*.h5) in ${DFAM_DIR}.\nDownload them from https://www.dfam.org/releases/ - '-species human' needs the Mammalia partition (dfam39_full.7.h5) as well as the root partition."
            echo "DFAM_DIR: ${DFAM_DIR} (${h5_count} partition file(s))"
        fi
    else
        echo "Resume mode: skipping TRF + RepeatMasker (reusing existing .tab files)"
    fi

    BCFTOOLS=$(check_binary "bcftools" "bcftools" "bcftools-1.21/bcftools") || exit 1
    BGZIP=$(check_binary "bgzip" "bgzip" "htslib-1.21/bgzip") || exit 1
    echo "BCFTOOLS: ${BCFTOOLS}"
    echo "BGZIP: ${BGZIP}"

}

create_output_dir() {
    if [[ -d "${OUTPUT_DIR}" ]]; then
        if [[ ${FLAG_OVERWRITE} -eq 1 ]]; then
            echo "Output directory ${OUTPUT_DIR} already exists. Overwriting..."
            rm -rf "${OUTPUT_DIR}" || die "Failed to remove existing output directory ${OUTPUT_DIR}"
        else
            die "Output directory ${OUTPUT_DIR} already exists. Please choose a different output directory or delete the existing one."
        fi
    fi
	mkdir -p "${OUTPUT_DIR}" || die "Failed creating ${OUTPUT_DIR}"
}

setup_dfam_library() {
    # Let RepeatMasker read partitions that do not live inside its installation.
    # RepeatMasker takes its FamDB from $LIBDIR/famdb and honours LIBDIR from the
    # environment (RepeatMaskerConfig.pm, 4.1.6 through 4.2.x). $LIBDIR must also hold
    # RepeatPeps.lib and friends, which nobody who just downloaded a partition has, so
    # assemble one out of symlinks - instant even for the 57 GB Mammalia partition.
    [[ -z "${DFAM_DIR}" ]] && return 0

    local stock_libdir rm_install
    rm_install=$(dirname "$(realpath "${REPEAT_MASKER}")")
    stock_libdir="${rm_install}/Libraries"
    [[ -d "${stock_libdir}" ]] || die "Could not find the RepeatMasker Libraries directory at ${stock_libdir}.\nExpected it alongside ${REPEAT_MASKER}. Unset --dfam_dir/\$SVSCANNER_DFAM_DIR to use RepeatMasker's own configuration."

    echo "Assembling RepeatMasker library directory in ${RM_LIBDIR}..."
    rm -rf "${RM_LIBDIR}" || die "failed to clear ${RM_LIBDIR}"
    mkdir -p "${RM_LIBDIR}/famdb" || die "failed to create ${RM_LIBDIR}/famdb"

    # Regular files only. Besides famdb, rebuilt below, the only directories RepeatMasker
    # keeps here are its library caches ('general', '<engine>-Dfam_<version>'), and those
    # are unsafe to inherit: the name records the database version but not which
    # partitions built the cache. Since --dfam_dir exists to add partitions the install
    # lacks, an inherited cache is stale by construction and RepeatMasker reuses it
    # silently. Rebuilding for human against Dfam 3.9 Mammalia costs ~30s under RMBlast,
    # ~4 min under HMMER.
    local entry name skipped=()
    for entry in "${stock_libdir}"/*; do
        [[ -e "${entry}" ]] || continue
        name=$(basename "${entry}")
        [[ "${name}" == "famdb" ]] && continue
        # -f follows symlinks, so a symlinked file is still linked through.
        if [[ ! -f "${entry}" ]]; then
            skipped+=("${name}")
            continue
        fi
        ln -sfn "${entry}" "${RM_LIBDIR}/${name}" || die "failed to link ${entry}"
    done
    # Logged rather than silent: if an installation ever keeps something here that
    # RepeatMasker actually needs, this is what makes that visible.
    (( ${#skipped[@]} )) && echo "  not inherited from the installation (rebuilt per run): ${skipped[*]}"

    # The install's own partitions first - RepeatMasker ships the Dfam root partition,
    # which is required and which users downloading a clade partition rarely have.
    local h5
    for h5 in "${stock_libdir}"/famdb/*; do
        [[ -e "${h5}" ]] || continue
        ln -sfn "${h5}" "${RM_LIBDIR}/famdb/$(basename "${h5}")" || die "failed to link ${h5}"
    done

    # Then --dfam_dir, which overrides same-named files from the install.
    for h5 in "${DFAM_DIR}"/*.h5; do
        [[ -e "${h5}" ]] || continue
        ln -sfn "$(realpath "${h5}")" "${RM_LIBDIR}/famdb/$(basename "${h5}")" || die "failed to link ${h5}"
    done

    # Exported so the RepeatMasker processes spawned by parallel inherit it.
    export LIBDIR="${RM_LIBDIR}"
    echo "LIBDIR: ${LIBDIR}"
    echo "FamDB partitions in use:"
    for h5 in "${RM_LIBDIR}"/famdb/*.h5; do
        [[ -e "${h5}" ]] || continue
        echo "  $(basename "${h5}") -> $(realpath "${h5}")"
    done
    echo "done"
}

check_resume_inputs() {
    # Verify the checkpoint files from a previous run are present so we can skip TRF + RepeatMasker.
    echo "Resume mode: validating existing checkpoint files in ${OUTPUT_DIR}..."

    [[ -d "${OUTPUT_DIR}" ]] || die "Cannot resume: output directory ${OUTPUT_DIR} does not exist."

    local missing=0
    for f in "${INFO_FILE}" "${RM_FILE}" "${TRF_FILE}"; do
        if [[ ! -s "$f" ]]; then
            echo "  missing or empty: $f" >&2
            missing=1
        fi
    done

    if [[ ${missing} -eq 1 ]]; then
        die "Cannot resume: required checkpoint file(s) above are missing or empty.\nThese are produced by a previous full run and must use the same --prefix ('${PREFIX}')."
    fi

    echo "  found: ${INFO_FILE}"
    echo "  found: ${RM_FILE}"
    echo "  found: ${TRF_FILE}"
    echo "done"
}

extract_flanking_regions() {
    # 1) Extract sequence and flanking regions for variants
    echo "Extracting structural variant sequences from VCF..."
    python3 ${EXTRACT_SV_FLANKINGS} --vcf ${VCF} --ref ${REF} --out ${EXTRACT_SV_FLANKS_OUT} --min 10 -n ${NSPLIT_FILES} --info ${INFO_FILE} || die "failed"
    echo "done"
}

run_trf() {
    # set -x
    # 3) Run Tandem Repeat Finder and RepeatMasker - wait for both to complete
    echo "Running Tandem Repeat Finder..."
    T4=$(date +%s)
    find "${EXTRACT_SV_FLANKS_OUT}" -name "*.fa" | parallel -j ${NTHREADS} "${TRF_BINARY} {} 2 7 7 80 10 50 500 -h -ngs > {.}.dat" || die "failed"
    T5=$(date +%s) || die "failed to get T3"
    TRF_TIME=$((T5 - T4)) || die "failed to calculate time"
    echo "done. Tandem Repeat Finder took ${TRF_TIME} seconds"
}

warm_repeatmasker_cache() {
    # RepeatMasker derives a per-species library from FamDB on first use and caches it
    # under $LIBDIR. That build is NOT concurrency-safe: run in parallel the processes
    # clobber each other's .working dirs and makeblastdb then fails on a missing file.
    # Build it once, single process, so the fan-out finds it ready. docs/install_rm.md
    # step 4 does this by hand at install time, but a new species or database - or a
    # container image built without either - still has to build one on the first run.
    local warm_dir="${OUTPUT_DIR}/${PREFIX}rm_warmup"
    local warm_fa="${warm_dir}/warmup.fa"
    local warm_log="${warm_dir}/warmup.log"

    rm -rf "${warm_dir}" || die "failed to clear ${warm_dir}"
    mkdir -p "${warm_dir}" || die "failed to create ${warm_dir}"

    # Content is irrelevant - the point is to make RepeatMasker build the library.
    {
        echo ">svscanner_library_warmup"
        echo "ACGTTGCAAGCTTAGCCATGGATCCGTAAGCTTGGATCCAAGCTTGCATGCCTGCAGGTCG"
        echo "TTACGGCATTCAGGCCTAAGCTTGGCCTAGGCATTAGCCGTAAGGCTTAACCGGATTCCAG"
        echo "GGCATTAACCGGTTAAGCCTTAAGGCCATTAACCGGTTAACCGGAATTCCGGTTAACCGGA"
        echo "CCTTAAGGCCTTAAGGCCTTAAGGAATTCCGGAATTCCGGTTAACCGGTTAACCGGAATTC"
    } > "${warm_fa}" || die "failed to write ${warm_fa}"

    echo "Preparing RepeatMasker libraries for species '${SPECIES}' (single process)..."
    local T_WARM_START T_WARM_END
    T_WARM_START=$(date +%s)
    # Run from inside warm_dir: createTempDir uses cwd(), not -dir, so RepeatMasker would
    # otherwise scatter RM_<pid> directories through the caller's directory. Same reason
    # run_repeatmasker cds into RM_TMP before the fan-out.
    if ! ( cd "${warm_dir}" && ${REPEAT_MASKER} "${warm_fa}" -pa 1 -dir "${warm_dir}" -species "${SPECIES}" > "${warm_log}" 2>&1 ); then
        echo "RepeatMasker reported (${warm_log}):" >&2
        tail -n 20 "${warm_log}" | sed 's/^/  /' >&2
        die "RepeatMasker could not build its libraries for species '${SPECIES}'"
    fi
    T_WARM_END=$(date +%s)

    # RepeatMasker reports the database it opened and the families it resolved only into
    # its per-chunk logs, which cleanup deletes - so a successful run leaves no record of
    # what it annotated against. This warm-up used the same library, so lift its summary
    # into the main log. 'Families' is the number to watch: 237 for the Dfam 3.9 root
    # partition alone, 272,503 once Mammalia is added.
    echo "RepeatMasker library summary:"
    grep -E 'RepeatMasker version|Search Engine|Master RepeatMasker Database|Title[[:space:]]*:|Version[[:space:]]*:|Date[[:space:]]*:|Families[[:space:]]*:|Taxonomy ID|families in ancestor taxa|Building (general|species) libraries|partition' \
        "${warm_log}" | head -n 20 | sed 's/^/  /'

    # Two ways to end up with a library that annotates nothing, both of which
    # RepeatMasker exits 0 on: famdb.py raising when a clade's descendants live in an
    # uninstalled partition (RepeatMasker ignores its exit status and carries on), and a
    # species that resolves to no families. Reporting success there is worse than
    # stopping. Both trigger on positive evidence only, so a change in RepeatMasker's
    # wording can never block a working run.
    if grep -q 'Traceback (most recent call last)' "${warm_log}"; then
        echo "RepeatMasker's famdb.py failed while resolving species '${SPECIES}':" >&2
        grep -hE '^[A-Za-z_.]*(Error|Exception):' "${warm_log}" | sort -u | head -n 3 | sed 's/^/  /' >&2
        die "Cannot trust the RepeatMasker library for species '${SPECIES}'.\nThis usually means '${SPECIES}' has descendant taxa in a FamDB partition that is not installed - RepeatMasker would carry on and annotate against an empty library.\nInstall the partitions covering '${SPECIES}' (see --dfam_dir) or choose a species your partitions cover.\nFull log kept at: ${warm_log}"
    fi
    if grep -q '0 families in ancestor taxa; 0 lineage-specific families' "${warm_log}"; then
        die "RepeatMasker resolved no families for species '${SPECIES}' - every repeat annotation would be empty.\nInstall the FamDB partitions covering '${SPECIES}' (see --dfam_dir).\nFull log kept at: ${warm_log}"
    fi

    rm -rf "${warm_dir}" || die "failed to remove ${warm_dir}"
    echo "done. Library preparation took $((T_WARM_END - T_WARM_START)) seconds"
}

run_repeatmasker() {
    mkdir -p ${RM_TMP}
    echo "Running RepeatMasker..."
    T2=$(date +%s)
    cd ${RM_TMP}

    shopt -s nullglob
    fa_files=(${EXTRACT_SV_FLANKS_OUT}/*.fa)
    (( ${#fa_files[@]} == 0 )) && die "No FASTA files found in ${EXTRACT_SV_FLANKS_OUT}"
    shopt -u nullglob

    # Run RepeatMasker in parallel with error sensitivity.
    # MAX_JOBS and THREADS_PER_JOB are set by resolve_thread_counts.
    if ! find ${EXTRACT_SV_FLANKS_OUT} -name "*.fa" | parallel --halt now,fail=1 -j "${MAX_JOBS}" "${REPEAT_MASKER} {} -pa ${THREADS_PER_JOB} -html -gff -dir ${EXTRACT_SV_FLANKS_OUT} -species ${SPECIES} > {}.log 2>&1"; then
        # parallel reports only the failing command line; the reason is in that job's own
        # log. Surface it - most often a FamDB partition that does not cover --species.
        local last_log
        last_log=$(find "${EXTRACT_SV_FLANKS_OUT}" -name '*.fa.log' -printf '%T@ %p\n' 2>/dev/null |
            sort -rn | head -n1 | cut -d' ' -f2-)
        if [[ -n "${last_log}" ]]; then
            echo "RepeatMasker reported (${last_log}):" >&2
            tail -n 20 "${last_log}" | sed 's/^/  /' >&2
        fi
        echo "Remaining RepeatMasker logs: ${EXTRACT_SV_FLANKS_OUT}/*.fa.log" >&2
        die "RepeatMasker failed"
    fi

    cd - || die "cd - failed"
    T3=$(date +%s) || die "failed to get T3"
    RM_TIME=$((T3 - T2)) || die "failed to calculate time"
    rm -r ${RM_TMP} || die "failed to remove ${RM_TMP}"
    echo "done. RepeatMasker took ${RM_TIME} seconds"
}

process_trf_repeatmasker_output() {
    # Process the RepeatMasker files (remove the header and 16th column)
    echo "Process the RepeatMasker files (remove the header and 16th column)..."
    for rm_output in "${EXTRACT_SV_FLANKS_OUT}"/*.fa.out; do
        tail -n +4 "${rm_output}" | awk '{
            $16 = "";
            print $0
        }' OFS='\t' > "${rm_output}.tab" || die "failed"
    done
    # rm -rf "${EXTRACT_SV_FLANKS_OUT}/*.fa.out"

    cat ${EXTRACT_SV_FLANKS_OUT}/*.dat > ${TRF_FILE}
    cat ${EXTRACT_SV_FLANKS_OUT}/*.out.tab > ${RM_FILE}
    echo "done"
}

annotation() {
    echo "Annotating..."
    test -d "${ANNOTATIONS_OUT}" && rm -r "${ANNOTATIONS_OUT}"
    python3 ${ANNOTATION} \
        --vcf ${VCF}\
        --rm ${RM_FILE}\
        --trf ${TRF_FILE}\
        --info ${INFO_FILE}\
        --str ${STR_BED}\
        --out ${ANNOTATIONS_OUT}\
        --min_sv_coverage ${MIN_SV_COVERAGE}\
        --min_class_sv_coverage ${MIN_CLASS_SV_COVERAGE}\
        --min_total_sv_coverage ${MIN_TOTAL_SV_COVERAGE}\
        --max_trf_overlap ${MAX_TRF_OVERLAP}\
        --div ${INTERVAL}\
        --len ${DIAGRAM_LEN} || die "failed"
    echo "done"
}

plot_classifications() {
    echo "Plotting..."
    python3 ${PLOT} \
        --out ${ANNOTATIONS_OUT}/plots\
        --tsv ${ANNOTATIONS_OUT}/plot_annotate.tsv || die "failed"
    echo "done"
}

plot_tracebacks() {
    echo "Plotting tracebacks..."
    python3 ${TRACEBACK_PLOT} \
        --output ${ANNOTATIONS_OUT}/traceback_plots.pdf \
        --traceback ${ANNOTATIONS_OUT}/traceback.tsv || die "failed"
    echo "done"
}

apply_annotations() {
    # apply annotations to the VCF
    echo "Applying annotations to the VCF..."
    python3 ${VCF_ANNOTATE} \
        --vcf ${VCF} \
        --header ${ANNOTATIONS_OUT}/vcf_header.txt \
        --tsv ${ANNOTATIONS_OUT}/vcf_annotate.tsv \
        --mate ${ANNOTATIONS_OUT}/vcf_annotate_bnd_mate.tsv \
        --output ${ANNOTATED_VCF} || die "failed to annotate VCF"
    echo "done"
}

sort_and_index_vcf() {
    # Sort and Index the annotated VCF
    echo "Sort and Index the annotated VCF..."
    ${BCFTOOLS} sort -Oz -o ${ANNOTATED_VCF}.gz ${ANNOTATED_VCF} || die "${BCFTOOLS} sort failed"
    ${BCFTOOLS} index -t ${ANNOTATED_VCF}.gz || die "${BCFTOOLS} index failed"
    rm ${ANNOTATED_VCF}
    echo "done"
}

show_output_paths() {

    if [[ ${FLAG_DELETE_TMP_FILES} -eq 1 ]]; then
        echo "Deleting temporary files..."
        #if ${ANNOTATIONS_OUT}/plots/plots.pdf exists, move it to the output directory
        if [[ -f ${ANNOTATIONS_OUT}/plots/plots.pdf ]]; then
            mv ${ANNOTATIONS_OUT}/plots/plots.pdf ${OUTPUT_DIR}/${PREFIX}plots.pdf || die "failed to move plots to ${OUTPUT_DIR}"
        else
            mv ${ANNOTATIONS_OUT}/plots ${OUTPUT_DIR}/${PREFIX}plots || die "failed to move plots to ${OUTPUT_DIR}"
            echo "Plots dir: ${OUTPUT_DIR}/${PREFIX}plots"
        fi

        mv ${ANNOTATIONS_OUT}/diagram.txt ${OUTPUT_DIR}/${PREFIX}diagram.txt || die "failed to move diagram.txt to ${OUTPUT_DIR}"
        mv ${ANNOTATIONS_OUT}/rm_diagram.tsv ${OUTPUT_DIR}/${PREFIX}rm_diagram.tsv || die "failed to move rm_diagram.tsv to ${OUTPUT_DIR}"
        mv ${ANNOTATIONS_OUT}/trf_diagram.tsv ${OUTPUT_DIR}/${PREFIX}trf_diagram.tsv || die "failed to move trf_diagram.tsv to ${OUTPUT_DIR}"
        mv ${ANNOTATIONS_OUT}/traceback_plots.pdf ${OUTPUT_DIR}/${PREFIX}traceback_plots.pdf # only if generated
        mv ${ANNOTATIONS_OUT}/vcf_annotate.tsv ${OUTPUT_DIR}/${PREFIX}vcf_annotate.tsv || die "failed to move vcf_annotate.tsv to ${OUTPUT_DIR}"
        mv ${ANNOTATIONS_OUT}/vcf_annotate_bnd_mate.tsv ${OUTPUT_DIR}/${PREFIX}vcf_annotate_bnd_mate.tsv || die "failed to move vcf_annotate_bnd_mate.tsv to ${OUTPUT_DIR}"

        rm -rf ${ANNOTATIONS_OUT} || die "failed to remove ${ANNOTATIONS_OUT}"
        rm -rf ${EXTRACT_SV_FLANKS_OUT} || die "failed to remove ${EXTRACT_SV_FLANKS_OUT}"
        # Only ever a tree of symlinks (see setup_dfam_library); never the databases themselves.
        [[ -d ${RM_LIBDIR} ]] && { rm -rf ${RM_LIBDIR} || die "failed to remove ${RM_LIBDIR}"; }
        # rm -f ${INFO_FILE} || die "failed to remove ${INFO_FILE}"
        # rm -f ${RM_FILE} || die "failed to remove ${RM_FILE}"
        # rm -f ${TRF_FILE} || die "failed to remove ${TRF_FILE}"
        echo "Annotation outputs dir: ${OUTPUT_DIR}"
        echo "SV VCF with repeats annotated: ${ANNOTATED_VCF}.gz"
    else
        echo "Annotation outputs dir: ${ANNOTATIONS_OUT}"
        echo "Plots dir: ${ANNOTATIONS_OUT}/plots"
        echo "SV VCF with repeats annotated: ${ANNOTATED_VCF}.gz"
    fi

}

T0=$(date +%s)
# Banner after parse_args, so that --version and --help print only their own output.
parse_args "$@"
echo "SVscanner version: ${VERSION}"
resolve_thread_counts
check_required
if [[ ${RESUME} -eq 1 ]]; then
    check_resume_inputs
else
    create_output_dir
    setup_dfam_library
    # Before extraction: a species the installed partitions cannot cover is fatal, and
    # there is no point spending an extraction and a TRF pass to find that out.
    warm_repeatmasker_cache
    extract_flanking_regions
    run_trf
    run_repeatmasker
    process_trf_repeatmasker_output
fi
annotation
plot_classifications
plot_tracebacks
apply_annotations
sort_and_index_vcf
show_output_paths

T1=$(date +%s)
ELAPSED_TIME=$((T1 - T0))
echo "The SVscanner pipeline took ${ELAPSED_TIME} seconds"
echo "SVscanner version: ${VERSION}"
echo "$(date)"
echo "Success!"
exit 0
