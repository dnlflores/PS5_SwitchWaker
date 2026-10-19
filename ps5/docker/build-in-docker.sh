#!/usr/bin/env bash
# Wind Waker for the PlayStation 5 - the whole build, inside the Docker image.
#
# Run by ps5/docker/run.sh. Everything lives in the volume mounted at /work, the
# layout the build tools expect:
#
#   /work/PS5_PayloadSDK  /work/PS5_Mesa  /work/PS5_Vulkan    Mihawk's stack
#   /work/PS5_SwitchWaker                                     this repository
#   /work/build/game                                          the game's build tree
#
# Then dist/PPSA99309/ is copied to /out/dist. Each step is skipped when its
# result is already there, so a second run only rebuilds what changed.
#
#   REPO_URL, REPO_REF   which PS5_SwitchWaker to build (default this fork's main)
#   VULKAN_REF           which PS5_Vulkan (default 5b5e4fc, the revision PS5_Dusklight's
#                        v1.0.0 and this port's releases were built with; it pins
#                        the PS5_Mesa revision RADV is built from)
#   JOBS                 parallel compile jobs (default 8)
#
# SPDX-License-Identifier: MIT
set -euo pipefail
W=/work
repo_url=${REPO_URL:-https://github.com/dnlflores/PS5_SwitchWaker.git}
repo_ref=${REPO_REF:-origin/main}
vulkan_ref=${VULKAN_REF:-5b5e4fc2d80fdb67a4f61ba9e6a8a424026bb8a5}
step() { echo; echo "==> [$(date +%H:%M:%S)] $*"; }

clone() {
    local url=$1 dir=$W/$2
    if [[ ! -d $dir/.git ]]; then
        # Blobs are fetched when a revision is exported: the tools git-archive pinned
        # revisions, so the whole history's contents are never needed.
        git clone -q --filter=blob:none "$url" "$dir"
    else
        git -C "$dir" fetch -q origin
    fi
}

step "sources"
git config --global --add safe.directory '*'
clone https://github.com/mihawk-99/PS5_PayloadSDK.git PS5_PayloadSDK
clone https://github.com/mihawk-99/PS5_Mesa.git PS5_Mesa
clone https://github.com/mihawk-99/PS5_Vulkan.git PS5_Vulkan
clone "$repo_url" PS5_SwitchWaker
git -C $W/PS5_SwitchWaker checkout -q --detach "$repo_ref"
git -C $W/PS5_Vulkan checkout -q --detach "$vulkan_ref"
# The checkout is kept between builds with the patches applied. setup-source.sh
# skips a patch that is applied already but can't tell an older version of it, so
# SwitchWaker's tree starts clean each time, at the revision this one pins.
# (.deps/aurora is rebuilt by setup-source.sh when its patches change.)
switchwaker=$W/PS5_SwitchWaker/vendor/switchwaker
if [[ -e $switchwaker/.git ]]; then
    git -C "$switchwaker" reset -q --hard
    git -C "$switchwaker" clean -qfd
fi
git -C $W/PS5_SwitchWaker submodule update -q --init vendor/switchwaker
echo "RADV from PS5_Mesa $(sed -n 's/^mesa_revision=\${PS5_MESA_REVISION:-\([0-9a-f]*\)}/\1/p' $W/PS5_Vulkan/tools/build-radv.sh)"
echo "PS5_SwitchWaker at $(git -C $W/PS5_SwitchWaker log --oneline -1)"
echo "SwitchWaker at $(git -C "$switchwaker" log --oneline -1)"
for r in PS5_PayloadSDK PS5_Mesa PS5_Vulkan; do echo "$r at $(git -C $W/$r log --oneline -1)"; done

cd $W/PS5_Vulkan
step "PS5_Vulkan: the payload SDK at its pin, and zlib"
bash tools/setup-native-dependencies.sh

step "PS5_Vulkan: RADV, release build (the longest step)"
bash tools/build-radv.sh release

step "PS5_Vulkan: the runtime module (libc.prx) and the host tool"
[[ -f runtime/libc.prx ]] || bash tools/rebuild-libc.sh
(cd runtime && sha256sum -c libc.prx.sha256)
# The host tool (ELF -> the console's signed SELF), from this PS5_Vulkan revision.
zlib_root=.deps/native/zlib/root
mkdir -p build/host
clang++ -std=c++20 -O2 -Wall -Wextra -Werror -I "$zlib_root/usr/include" \
    tooling/native/native_app_builder.cpp tooling/native/self_container.cpp \
    tooling/native/elf_object.cpp tooling/native/sce_module_writer.cpp \
    "$(find "$zlib_root" -type f -name libz.a -print -quit)" -o build/host/ps5-native-tool
ls -la .deps/native/radv-release/lib/libvulkan_radeon.ps5.a build/host/ps5-native-tool runtime/libc.prx

cd $W/PS5_SwitchWaker
step "PS5_SwitchWaker: the game"
PS5_VULKAN_DIR=$W/PS5_Vulkan PS5_PAYLOAD_SDK_FORK=$W/PS5_PayloadSDK PS5_BUILD_DIR=$W/build/game \
    bash ps5/tools/build.sh switchwaker

step "the title folder"
title_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["titleId"])' ps5/sce_sys/param.json)
[[ -f dist/$title_id/eboot.bin ]] || { echo "no dist/$title_id/eboot.bin" >&2; exit 1; }
mkdir -p /out/dist
rsync -a --delete "dist/$title_id/" "/out/dist/$title_id/"
find "/out/dist/$title_id" -maxdepth 2 | sort | head -40
du -sh "/out/dist/$title_id"
step "done: dist/$title_id"
