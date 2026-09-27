#!/usr/bin/env bash
# Measures CPU time and memory of the compositor on the X200 with the normal build, to compare a change
# against a baseline. Builds, deploys and restarts through test-x200.sh, which has to pass, then runs the
# workloads of scripts/x200/profile-remote.sh without perf.
#
# Usage: ./bench-x200.sh [--no-build] [--rounds N] [--seconds S] [label]
#        ./bench-x200.sh --compare <baseline dir> <candidate dir>
#
# Writes test-results/bench-<time>-<label>/values.txt with "<key> <median> <min> <max>" per line.

set -u
cd "$(dirname "$(readlink -f "$0")")" || exit 1

X200_HOST=${X200_HOST:-x200}

compare() {
    [ -f "$1/values.txt" ] && [ -f "$2/values.txt" ] || { echo "no values.txt in $1 or $2" >&2; exit 2; }
    awk '
        NR == FNR {base[$1] = $2; lo[$1] = $3; hi[$1] = $4; next}
        !($1 in base) {next}
        {
            d = $2 - base[$1]
            # a change inside the spread of the rounds of either run is noise
            noise = (hi[$1] - lo[$1] > $4 - $3) ? hi[$1] - lo[$1] : $4 - $3
            # two starts of the same build differ by up to 1.2 MiB and 0.2 points of CPU time
            floor = ($1 ~ /^mem\./) ? 1500 : 0.3
            if (noise < floor)
                noise = floor
            mark = ""
            if ($1 ~ /^(cpu\..*\.percent|mem\..*_kB)$/ && (d > noise || d < -noise) && d != 0)
                mark = (d < 0) ? "better" : "WORSE"
            if ($1 ~ /^fps\./ && d < -1)
                mark = "WORSE"
            printf "%-38s %10s %10s %+10.2f  %s\n", $1, base[$1], $2, d, mark
        }
    ' "$1/values.txt" "$2/values.txt"
    grep -h "^invalid" "$1/values.txt" "$2/values.txt" | sed 's/^/NOT VALID: /'
}

TEST_ARGS=()
ROUNDS=3 SECONDS_PER_RUN=20 LABEL=""
while [ $# -gt 0 ]; do
    case $1 in
        --compare) [ $# -eq 3 ] || { sed -n '5,7p' "$0"; exit 2; }; compare "$2" "$3"; exit 0 ;;
        --no-build) TEST_ARGS+=(--no-build) ;;
        --rounds) ROUNDS=$2; shift ;;
        --seconds) SECONDS_PER_RUN=$2; shift ;;
        -h | --help) sed -n '2,9p' "$0"; exit 0 ;;
        -*) echo "unknown argument: $1" >&2; exit 2 ;;
        *) LABEL=-$1 ;;
    esac
    shift
done

OUT=test-results/bench-$(date +%Y%m%d-%H%M%S)$LABEL
mkdir -p "$OUT"
{ git rev-parse HEAD; git status --short; } >"$OUT/source.txt" 2>&1
git diff HEAD >"$OUT/source.diff" 2>&1

if ! ./test-x200.sh "${TEST_ARGS[@]}" >"$OUT/test.log" 2>&1; then
    echo "test-x200.sh failed, nothing was measured:"
    grep -E "^(PASS|FAIL)" "$OUT/test.log"
    exit 1
fi

stat -c '%s' build/stage/bin/Hypoland 2>/dev/null | awk '{print "@ 1 binary.size_kB " int($1 / 1024)}' >"$OUT/bench.txt"
ssh -o BatchMode=yes -o ConnectTimeout=10 "root@$X200_HOST" "bash -s $SECONDS_PER_RUN bench $ROUNDS" <scripts/x200/profile-remote.sh 2>&1 |
    grep --line-buffered -v "^Pseudo-terminal" | tee -a "$OUT/bench.txt" | grep --line-buffered -v "^@"

# median, min and max over the rounds
grep "^@" "$OUT/bench.txt" | sort -k3,3 -k4,4g | awk '
    function flush() {
        if (n) printf "%s %s %s %s\n", key, v[int((n + 1) / 2)], v[1], v[n]
        n = 0
    }
    $3 != key {flush(); key = $3}
    {v[++n] = $4}
    END {flush()}
' >"$OUT/values.txt"

echo
column -t -N key,median,min,max "$OUT/values.txt"
grep -q "^invalid" "$OUT/values.txt" && echo "NOT VALID: a screensaver, a lock or a compositor restart got in the way"
echo "values: $OUT/values.txt"
