#!/usr/bin/env bash
# Profiles Hypoland on the X200: builds with frame pointers, deploys, records the compositor with perf
# under a few workloads and puts the normal build back. The screensaver and the idle lock of the
# Omarchy shell are switched off while it runs.
#
# Usage: ./profile-x200.sh [--keep] [seconds per workload]
#   --keep   leave the profiling build on the X200

set -u
cd "$(dirname "$(readlink -f "$0")")" || exit 1

X200_HOST=${X200_HOST:-x200}
KEEP=0
SECONDS_PER_RUN=12
for arg in "$@"; do
    case $arg in
        --keep) KEEP=1 ;;
        -h | --help) sed -n '2,8p' "$0"; exit 0 ;;
        *[!0-9]*) echo "unknown argument: $arg" >&2; exit 2 ;;
        *) SECONDS_PER_RUN=$arg ;;
    esac
done

FLAGS="-march=x86-64 -mtune=core2 -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -g1"
OUT=test-results/profile-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"

echo "building with frame pointers..."
cmake -S . -B build-prof -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$FLAGS" -DCMAKE_CXX_FLAGS="$FLAGS" >"$OUT/configure.log" 2>&1 &&
    cmake --build build-prof -j"$(nproc)" >"$OUT/build.log" 2>&1 || { echo "build failed, see $OUT"; exit 1; }

BUILD_DIR=build-prof ./test-x200.sh --no-build >"$OUT/deploy.log" 2>&1 || { echo "deploy or test failed:"; grep -E "^(PASS|FAIL)" "$OUT/deploy.log"; exit 1; }

ssh -o BatchMode=yes -o ConnectTimeout=10 "root@$X200_HOST" "bash -s $SECONDS_PER_RUN" <scripts/x200/profile-remote.sh 2>&1 | grep -v "^Pseudo-terminal" | tee "$OUT/profile.txt"

if [ $KEEP -eq 0 ]; then
    echo
    echo "putting the normal build back..."
    ./test-x200.sh >"$OUT/restore.log" 2>&1
    grep -E "^RESULT" "$OUT/restore.log"
fi
echo "report: $OUT/profile.txt"
