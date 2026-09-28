#!/usr/bin/env bash
# Profiles the compositor on the machine under test: builds with frame pointers, deploys, records the
# compositor with perf under the workloads of scripts/bench/measure.sh and puts the normal build back.
# With --no-deploy or --host local it profiles the compositor that is running; call stacks are only
# complete when that one was built with frame pointers.
#
# Usage: ./profile.sh [options] [seconds per workload]
#
#   --keep             leave the profiling build on the machine under test
#   --stages REGEX     functions whose inclusive time is printed
# TARGET_HELP

set -u
cd "$(dirname "$(readlink -f "$0")")" || exit 1
. scripts/bench/target.sh

usage() {
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' | while IFS= read -r line; do
        if [ "$line" = TARGET_HELP ]; then echo "$TARGET_HELP"; else echo "$line"; fi
    done
}

KEEP=0
while [ $# -gt 0 ]; do
    case $1 in
        --keep) KEEP=1 ;;
        -h | --help) usage; exit 0 ;;
        -*)
            target_option "$@" || { echo "unknown argument: $1" >&2; exit 2; }
            shift $((TARGET_SHIFT - 1))
            ;;
        *[!0-9]*) echo "unknown argument: $1" >&2; exit 2 ;;
        *) MEASURE_ARGS+=(--seconds "$1") ;;
    esac
    shift
done
target_is_local && DEPLOY=0

FLAGS="-march=x86-64 -mtune=core2 -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -g1"
OUT=test-results/profile-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"

if [ $DEPLOY = 1 ]; then
    echo "building with frame pointers..."
    cmake -S . -B build-prof -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$FLAGS" -DCMAKE_CXX_FLAGS="$FLAGS" >"$OUT/configure.log" 2>&1 &&
        cmake --build build-prof -j"$(nproc)" >"$OUT/build.log" 2>&1 || { echo "build failed, see $OUT"; exit 1; }

    BUILD_DIR=build-prof target_deploy "$OUT/deploy.log" --no-build || { echo "deploy or test failed:"; grep -E "^(PASS|FAIL)" "$OUT/deploy.log"; exit 1; }
fi

target_run scripts/bench/measure.sh --mode perf "${MEASURE_ARGS[@]}" | tee "$OUT/profile.txt"

if [ $DEPLOY = 1 ] && [ $KEEP -eq 0 ]; then
    echo
    echo "putting the normal build back..."
    target_deploy "$OUT/restore.log"
    grep -E "^RESULT" "$OUT/restore.log"
fi
echo "report: $OUT/profile.txt"
