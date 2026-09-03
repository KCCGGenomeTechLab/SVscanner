# SVscanner container
#
# Built on the Dfam TE Tools image, which already supplies a correctly configured
# RepeatMasker together with TRF, RMBlast and HMMER. The tag is pinned deliberately:
#
#   dfam/tetools:1.99 -> RepeatMasker 4.2.3, TRF 4.09.1, RMBlast 2.17.0, HMMER 3.4
#                        and the Dfam 3.9 root partition (FamDB 2.0 format).
#
# Do not move to dfam/tetools:2.00 without testing: it switches to Dfam 4.0 / FamDB
# 3.0, which does not read the Dfam 3.9 partitions SVscanner is deployed against on
# NCI Gadi (dfam39_full.7.h5).
#
# The image ships no clade database. RepeatMasker's bundled root partition alone has
# no human families, so `-species human` needs the Mammalia partition (~57 GB)
# supplied at runtime via --dfam_dir / $SVSCANNER_DFAM_DIR. See docs/docker.md.
FROM dfam/tetools:1.99

LABEL org.opencontainers.image.title="SVscanner" \
      org.opencontainers.image.description="Annotate tandem repeats and mobile elements within structural variants using TRF and RepeatMasker" \
      org.opencontainers.image.source="https://github.com/GenTechGp/SVscanner" \
      org.opencontainers.image.base.name="docker.io/dfam/tetools:1.99" \
      org.opencontainers.image.licenses="MIT"

ARG HTSLIB_VERSION=1.21
ARG BCFTOOLS_VERSION=1.21

# GNU parallel drives the TRF and RepeatMasker fan-out; python3-venv is needed
# because Debian 12 marks its system Python as externally managed (PEP 668).
RUN apt-get -y update && apt-get -y install --no-install-recommends \
        parallel \
        python3-venv \
        libbz2-dev \
        liblzma-dev \
        libcurl4-openssl-dev \
        libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# bcftools, bgzip and tabix. Built from source rather than taken from Debian 12
# (which has 1.16) to match the 1.21 that scripts/install_tools.sh installs and the
# NCI if89 module loads. htslib's lib directory has to go on the loader path: bcftools
# links libhts dynamically without an rpath, so without ldconfig it builds fine and
# then fails to start.
RUN cd /tmp \
    && curl -fsSL -o htslib.tar.bz2 "https://github.com/samtools/htslib/releases/download/${HTSLIB_VERSION}/htslib-${HTSLIB_VERSION}.tar.bz2" \
    && tar -xf htslib.tar.bz2 \
    && cd "htslib-${HTSLIB_VERSION}" \
    && ./configure --prefix=/opt/htslib \
    && make -j"$(nproc)" && make install \
    && cd /tmp && rm -rf htslib.tar.bz2 "htslib-${HTSLIB_VERSION}" \
    && echo /opt/htslib/lib > /etc/ld.so.conf.d/htslib.conf && ldconfig

RUN cd /tmp \
    && curl -fsSL -o bcftools.tar.bz2 "https://github.com/samtools/bcftools/releases/download/${BCFTOOLS_VERSION}/bcftools-${BCFTOOLS_VERSION}.tar.bz2" \
    && tar -xf bcftools.tar.bz2 \
    && cd "bcftools-${BCFTOOLS_VERSION}" \
    && ./configure --prefix=/opt/bcftools --with-htslib=/opt/htslib \
    && make -j"$(nproc)" && make install \
    && cd /tmp && rm -rf bcftools.tar.bz2 "bcftools-${BCFTOOLS_VERSION}"

# Python dependencies, in their own layer so source changes do not reinstall them.
# The resolved versions are recorded in the image: requirements.txt is deliberately
# loose, so this is the only record of what a given image tag actually contains.
COPY requirements.txt /opt/svscanner/requirements.txt
RUN python3 -m venv /opt/svscanner-venv \
    && /opt/svscanner-venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/svscanner-venv/bin/pip install --no-cache-dir -r /opt/svscanner/requirements.txt \
    && /opt/svscanner-venv/bin/pip freeze > /opt/svscanner-venv/requirements.lock \
    && cat /opt/svscanner-venv/requirements.lock

COPY . /opt/svscanner

# `svscanner` on $PATH mirrors the NCI if89 module, so the same command line works in
# both places. Nextflow overrides a container's ENTRYPOINT, so nothing may depend on
# one: every path below is set through ENV instead.
RUN printf '#!/bin/bash\nexec /opt/svscanner/scripts/run_workflow.sh "$@"\n' > /usr/local/bin/svscanner \
    && chmod +x /usr/local/bin/svscanner

# Putting the venv ahead of /usr/bin also makes it the `python3` that RepeatMasker's
# famdb.py resolves to. That is fine because requirements.txt includes h5py, which is
# all famdb.py needs, and the smoke test below fails the build if that ever stops
# being true.
ENV PATH=/opt/svscanner-venv/bin:/opt/bcftools/bin:/opt/htslib/bin:$PATH \
    SVSCANNER_TESTDATA=/opt/svscanner/test \
    MPLCONFIGDIR=/tmp/matplotlib

# Fail the build rather than the pipeline. Covers the two things most likely to break on
# a base image bump: a missing tool, and famdb.py losing the h5py it resolves through the
# venv.
#
# Two things this has to get right, both learned the hard way:
#   - one `command -v` per tool. It accepts several names but reports success if any one
#     of them resolves, which waves through a half-broken image.
#   - no pipes. This runs under dash, which has no `set -o pipefail`, so `cmd | head -1`
#     reports head's exit status and hides a tool that cannot even start.
RUN set -eu; \
    for tool in trf RepeatMasker parallel bcftools bgzip tabix python3; do \
        command -v "$tool" > /dev/null || { echo "missing from PATH: $tool" >&2; exit 1; }; \
    done; \
    /opt/svscanner/scripts/check_required_python.sh; \
    bcftools --version; \
    bgzip --version; \
    tabix --version; \
    RepeatMasker -v; \
    python3 /opt/RepeatMasker/famdb.py -i /opt/RepeatMasker/Libraries/famdb info; \
    svscanner --version

WORKDIR /data
