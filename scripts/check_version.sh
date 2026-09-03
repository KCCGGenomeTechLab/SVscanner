#!/bin/bash
# Verify the SVscanner release number against everywhere else it is written.
#
# The VERSION file at the repository root is the single source of truth. Edit it by
# hand when cutting a release; this script checks that nothing else contradicts it.
#
# Hard errors (a push carrying these is refused):
#   - VERSION missing, or not of the form X.Y.Z
#   - scripts/run_workflow.sh hardcoding a version instead of reading VERSION
#   - a release tag vX.Y.Z whose commit does not say X.Y.Z
#
# Warnings only (printed, never blocking), because the if89 module is not built for
# every tag and so the documented module version may legitimately lag VERSION:
#   - README.md `module load SVscanner/<version>` differing from VERSION
#   - a container image tag pinned in README.md or docs/docker.md differing from VERSION
#
# Usage:
#   scripts/check_version.sh                  # check the working tree
#   scripts/check_version.sh --rev <commit>   # check a commit without checking it out
#   scripts/check_version.sh --expect X.Y.Z   # additionally require this version

set -u

SEMVER='^[0-9]+\.[0-9]+\.[0-9]+$'
REPO_ROOT=$(cd -- "$(dirname -- "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd) || exit 1

REV=""
EXPECT=""
while (($#)); do
    case "$1" in
        --rev)    REV="${2:-}"; shift 2 ;;
        --expect) EXPECT="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        *) echo "check_version.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

if [[ -n $REV ]]; then
    WHERE=" at ${REV:0:12}"
else
    WHERE=""
fi

FAILED=0
err()  { echo "version mismatch: $*" >&2; FAILED=1; }
warn() { echo "version warning: $*" >&2; }

# Read a repository file either from the working tree or from a revision, so the
# same checks can run against a commit that is not checked out (e.g. in a hook).
read_file() {
    if [[ -n $REV ]]; then
        git -C "$REPO_ROOT" show "${REV}:$1" 2>/dev/null
    else
        cat "${REPO_ROOT}/$1" 2>/dev/null
    fi
}

# 1. The VERSION file itself.
VERSION=$(read_file VERSION | head -n1 | tr -d '[:space:]')
if [[ -z $VERSION ]]; then
    # History from before the VERSION file existed has nothing to check, so pushing
    # it must not be blocked. In the working tree the file is always required.
    if [[ -n $REV ]]; then
        echo "version check skipped: no VERSION file${WHERE}" >&2
        exit 0
    fi
    echo "version mismatch: VERSION file is missing or empty" >&2
    exit 1
fi
[[ $VERSION =~ $SEMVER ]] || err "VERSION file${WHERE} contains '${VERSION}', expected X.Y.Z"

# 2. run_workflow.sh must not carry its own copy of the number.
if read_file scripts/run_workflow.sh | grep -qE '^VERSION="SVscanner v[0-9]'; then
    err "scripts/run_workflow.sh${WHERE} hardcodes a version - it must read the VERSION file"
fi

# In the working tree the script can actually be run, which also catches a broken
# VERSION lookup rather than just a hardcoded string.
if [[ -z $REV ]]; then
    reported=$("${REPO_ROOT}/scripts/run_workflow.sh" --version 2>/dev/null)
    [[ $reported == "SVscanner v${VERSION}" ]] ||
        err "run_workflow.sh --version reports '${reported}', expected 'SVscanner v${VERSION}'"
fi

# 3. The documented module version - a reminder, not a rule. Only `module load` lines
#    are looked at, so prose that deliberately names an older release is left alone.
readme_versions=$(read_file README.md |
    grep -oE 'module load SVscanner/[0-9]+\.[0-9]+\.[0-9]+' | sed 's#.*/##' | sort -u)
while read -r v; do
    [[ -z $v || $v == "$VERSION" ]] ||
        warn "README.md${WHERE} says 'module load SVscanner/${v}' but VERSION is ${VERSION}" \
             "- update it if ${VERSION} is now the module installed on if89"
done <<<"$readme_versions"

# 3b. Container image tags named in the documentation. Unlike the if89 module, an image
#     is published for every release tag, so a pinned example naming an older release is
#     simply stale. Still a warning and not an error: the docs are not what a release is
#     for, and this check necessarily runs before the image it names exists.
for doc in README.md docs/docker.md; do
    image_versions=$(read_file "$doc" |
        grep -oE 'ghcr\.io/[A-Za-z0-9._-]+/svscanner:[0-9]+\.[0-9]+\.[0-9]+' | sed 's#.*:##' | sort -u)
    while read -r v; do
        [[ -z $v || $v == "$VERSION" ]] ||
            warn "${doc}${WHERE} pins the container image at ${v} but VERSION is ${VERSION}" \
                 "- update the examples when releasing ${VERSION}"
    done <<<"$image_versions"
done

# 4. The release tag.
if [[ -n $EXPECT ]]; then
    [[ $EXPECT == "$VERSION" ]] ||
        err "tag v${EXPECT} is being published but VERSION${WHERE} is ${VERSION}" \
            "- set VERSION to ${EXPECT}, commit, and tag that commit"
elif [[ -z $REV ]]; then
    head_tag=$(git -C "$REPO_ROOT" tag --points-at HEAD 2>/dev/null |
        grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)
    if [[ -n $head_tag && ${head_tag#v} != "$VERSION" ]]; then
        err "tag ${head_tag} points at HEAD but VERSION is ${VERSION}"
    fi
fi

((FAILED)) && exit 1

echo "version check passed: SVscanner v${VERSION}${WHERE}"
