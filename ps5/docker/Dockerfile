# Wind Waker for the PlayStation 5 - a Linux build environment in Docker, for macOS.
#
# Ubuntu 26.04 with LLVM 22 (the compiler RADV, the payload SDK's wrappers and
# the title are built with), meson and ninja, and Mesa's host-tool
# dependencies (libclc and the SPIR-V translator for mesa_clc). See
# ps5/docker/run.sh.
#
# SPDX-License-Identifier: MIT
FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git curl wget ca-certificates unzip zip xz-utils file patch \
        bsdextrautils util-linux \
        pkg-config cmake ninja-build meson rsync ccache bison flex \
        python3 python3-pip python3-setuptools python3-packaging python3-mako \
        python3-markupsafe python3-yaml python3-ply python3-pyelftools \
        clang-22 lld-22 llvm-22 llvm-22-dev llvm-22-tools libclang-22-dev libclang-cpp22-dev \
        libclang-common-22-dev libpolly-22-dev \
        libclc-22-dev llvm-spirv-22 libllvmspirvlib-22-dev spirv-tools spirv-tools-dev glslang-tools \
        zlib1g-dev libexpat1-dev libzstd-dev libelf-dev libdrm-dev \
    && rm -rf /var/lib/apt/lists/*

# LLVM 22's clang, clang++, ld.lld, llvm-ar and llvm-config first on PATH.
ENV PATH=/usr/lib/llvm-22/bin:$PATH

# The title links Clang's x86-64 builtins (PS5_Vulkan's tools/radv-link.sh takes
# <resource-dir>/lib/linux/libclang_rt.builtins-x86_64.a). An arm64 image's
# compiler-rt has only its own CPU's, so that one archive comes from the amd64
# build of the same package version.
RUN v=$(dpkg-query -W -f='${Version}' clang-22) && v=${v#*:} \
    && curl -fsSLo /tmp/rt.deb \
        "http://archive.ubuntu.com/ubuntu/pool/universe/l/llvm-toolchain-22/libclang-rt-22-dev_${v}_amd64.deb" \
    && dpkg-deb -x /tmp/rt.deb /tmp/rt \
    && dir=$(clang --print-resource-dir)/lib/linux && mkdir -p "$dir" \
    && cp /tmp/rt/usr/lib/llvm-22/lib/clang/22/lib/linux/libclang_rt.builtins-x86_64.a "$dir/" \
    && rm -rf /tmp/rt /tmp/rt.deb

# Docker Desktop gives the VM a few GB of memory: cap ninja's parallel jobs so a
# few heavy C++ files at once do not run it out (JOBS, default 8).
RUN printf '#!/bin/sh\nexec /usr/bin/ninja -j"${JOBS:-8}" "$@"\n' > /usr/local/bin/ninja \
    && chmod +x /usr/local/bin/ninja

ENV CCACHE_DIR=/work/.ccache
WORKDIR /work
