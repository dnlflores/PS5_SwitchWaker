#!/usr/bin/env bash
# Wind Waker for the PlayStation 5 - build the title in Docker, from macOS.
#
#   ps5/docker/run.sh                build this fork's main into ../PS5_SwitchWaker-ps5build/dist
#   ps5/docker/run.sh shell          a shell in the build environment
#
# An alternative to ps5/tools/vm.sh (a Lima VM) for a Mac with Docker Desktop.
# The sources and build trees stay in the Docker volume ps5ww-work, so later
# runs only rebuild what changed; the title folder and the logs come out in
# $OUT (default ../PS5_SwitchWaker-ps5build, beside this repository).
#
#   JOBS=8      parallel compile jobs; lower it if the build runs out of memory
#   REPO_REF    which revision of this fork to build (default origin/main)
#
# SPDX-License-Identifier: MIT
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$here/../.." && pwd)
out=${OUT:-$(dirname "$root")/PS5_SwitchWaker-ps5build}
image=ps5-switchwaker-build
mkdir -p "$out/logs"

docker build -q -t "$image" "$here" >/dev/null
docker volume create ps5ww-work >/dev/null
args=(--rm -v ps5ww-work:/work -v "$here:/scripts:ro" -v "$out:/out"
      -e JOBS="${JOBS:-8}" -e REPO_REF="${REPO_REF:-origin/main}")
[[ -n ${VULKAN_REF:-} ]] && args+=(-e VULKAN_REF="$VULKAN_REF")
if [[ ${1:-} == shell ]]; then
    exec docker run -it "${args[@]}" "$image" bash
fi
log="$out/logs/build-$(date +%Y%m%d-%H%M%S).log"
echo "logging to $log"
docker run "${args[@]}" "$image" bash /scripts/build-in-docker.sh 2>&1 | tee "$log"
exit "${PIPESTATUS[0]}"
