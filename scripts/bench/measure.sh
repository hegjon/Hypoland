#!/usr/bin/env bash
# Runs on the machine under test, started by bench.sh or profile.sh (over ssh or locally). Puts the running
# compositor under workloads and reports what they cost. Nothing about the machine is fixed: the compositor,
# its user, its install prefix and its Wayland socket are taken from the running process.
#
# Usage: measure.sh [options]
#   --mode bench|perf   bench measures CPU time and memory (default), perf records with perf and prints
#                       where the CPU time goes
#   --seconds N         length of a workload (default 12)
#   --rounds N          how often the workloads are repeated, bench only (default 1)
#   --workloads LIST    comma separated, default: idle,gpu-client,terminal-scroll,shm-fullwindow,workspace-switch
#   --client NAME=CMD   one more workload: CMD is started as a client and measured as NAME, can be repeated
#   --process NAME      name of the compositor process (default: Hypoland, then Hyprland)
#   --settle N          age of the compositor in seconds before memory is measured (default 60)
#   --keep-governor     leave the CPU frequency governor alone
#   --stages REGEX      functions whose inclusive time perf mode prints
#   --out DIR           directory for raw data on this machine (default /tmp/hypoland-measure-<uid>)
#
# Lines starting with "@" are the values: "@ <round> <key> <value>". A workload whose client is not
# installed is skipped. As root the governor is set to performance and suspend is inhibited for the run;
# without root both are left alone and said so.

MODE=bench SECONDS_PER_RUN=12 ROUNDS=1 SETTLE=60 PROCESS="" KEEP_GOVERNOR=0 OUT=/tmp/hypoland-measure-$(id -u)
WORKLOADS=idle,gpu-client,terminal-scroll,shm-fullwindow,workspace-switch
STAGES='Render::IHyprRenderer::renderMonitor|Render::GL::CHyprGLRenderer::endRender|Render::GL::CHyprGLRenderer::beginRenderInternal|Render::GL::CEGLSync::create|Render::CRenderPass::render|Render::GL::CHyprOpenGLImpl::end\(\)|Render::GL::CGLFramebuffer::internalAlloc|Render::GL::CGLTexture::update|Aquamarine::CDRMOutput::commitState|drmModeAtomicCommit|Aquamarine::getDRMProp|Aquamarine::getDRMPropBlob|__x64_sys_ioctl|clock_gettime|read_hpet|_CWlSurfaceCommit|shmem_alloc_and_add_folio|drm_clflush_sg|Render::IHyprRenderer::renderLayer|Render::IHyprRenderer::renderAllClientsForWorkspace|Monitor::CMonitor::scheduleFrame|Animation::CHyprAnimationManager::tick|CInputManager::[A-Za-z]+|CPointerManager::[A-Za-z]+'
CLIENT_NAMES=() CLIENT_CMDS=()

while [ $# -gt 0 ]; do
    case $1 in
        --mode) MODE=$2; shift ;;
        --seconds) SECONDS_PER_RUN=$2; shift ;;
        --rounds) ROUNDS=$2; shift ;;
        --workloads) WORKLOADS=$2; shift ;;
        --client) CLIENT_NAMES+=("${2%%=*}"); CLIENT_CMDS+=("${2#*=}"); shift ;;
        --process) PROCESS=$2; shift ;;
        --settle) SETTLE=$2; shift ;;
        --keep-governor) KEEP_GOVERNOR=1 ;;
        --stages) STAGES=$2; shift ;;
        --out) OUT=$2; shift ;;
        *) echo "measure.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
case $MODE in bench | perf) ;; *) echo "measure.sh: unknown mode: $MODE" >&2; exit 2 ;; esac

# ---- the compositor and its session

for name in ${PROCESS:-Hypoland Hyprland}; do
    P=$(pgrep -n -x "$name" 2>/dev/null) && PROCESS=$name && break
done
[ -n "${P:-}" ] || { echo "no compositor is running (looked for ${PROCESS:-Hypoland, Hyprland})"; exit 1; }

TESTUSER=$(stat -c %U /proc/$P)
USERHOME=$(getent passwd "$TESTUSER" | cut -d: -f6)
RUNTIME=/run/user/$(id -u "$TESTUSER")
BINARY=$(readlink -f /proc/$P/exe)
BINDIR=$(dirname "$BINARY")
ROOT=0
[ "$(id -u)" = 0 ] && ROOT=1
if [ $ROOT = 0 ] && [ "$(id -un)" != "$TESTUSER" ]; then
    echo "the compositor runs as $TESTUSER, run this as $TESTUSER or as root"
    exit 1
fi

# every instance writes its pid and its Wayland socket into a lock file
LOCK=$(grep -l -x "$P" "$RUNTIME"/hypr/*/hyprland.lock 2>/dev/null | head -1)
[ -n "$LOCK" ] || { echo "no instance directory of pid $P in $RUNTIME/hypr"; exit 1; }
SIG=$(basename "$(dirname "$LOCK")")
SOCKET=$(sed -n 2p "$LOCK")

# clients get the environment the compositor was started with (locale, PATH, XDG variables), plus what the
# compositor sets for its children
mapfile -d '' SESSIONENV </proc/$P/environ
SESSIONENV+=(HOME="$USERHOME" XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="${SOCKET:-wayland-1}" HYPRLAND_INSTANCE_SIGNATURE="$SIG")
[ -d /usr/share/omarchy ] && SESSIONENV+=(OMARCHY_PATH=/usr/share/omarchy)

# runs a command in the session of the compositor. The script itself may arrive on stdin, nothing may read from it
asuser() {
    if [ $ROOT = 1 ]; then
        runuser -u "$TESTUSER" -- env -i -C "$USERHOME" "${SESSIONENV[@]}" "$@" </dev/null
    else
        env -i -C "$USERHOME" "${SESSIONENV[@]}" "$@" </dev/null
    fi
}
H() { asuser timeout 8 "$BINDIR/hyprctl" "$@"; }

# the dispatchers are Lua in this version and plain words before it
dispatch() { # lua, legacy
    [ "$(H dispatch "$1" 2>/dev/null)" = ok ] || H dispatch $2 >/dev/null 2>&1
}

# Clients are started as leaders of their own process group and stopped through it, so stopping one takes
# its children along and never hits a window of the user.
CLIENTS=0
client() { # seconds to live, command
    local ttl=$1 pidfile
    shift
    CLIENTS=$((CLIENTS + 1))
    pidfile=$OUT/client.$CLIENTS.pid
    rm -f "$pidfile"
    asuser setsid sh -c 'echo $$ >"$0"; exec timeout "$1" sh -c "$2"' "$pidfile" "$ttl" "$*" >/dev/null 2>&1 &
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -s "$pidfile" ] && break
        sleep 0.1
    done
}
stop_clients() {
    local pidfile
    for pidfile in "$OUT"/client.*.pid; do
        [ -s "$pidfile" ] && kill -- "-$(cat "$pidfile")" 2>/dev/null
        rm -f "$pidfile"
    done
}

# ---- what would spoil the numbers

# The Omarchy shell starts a screensaver after 150 s and locks after 300 s without input. Both are
# switched off for the run with the flag files its own toggles use, and put back afterwards.
OMARCHY=$USERHOME/.local/state/omarchy
HAD_AWAKE=0 HAD_SAVER_OFF=0 GOVERNOR="" INHIBIT=""
[ -d "$OMARCHY" ] || OMARCHY=""
[ -n "$OMARCHY" ] && [ -e "$OMARCHY/indicators/stay-awake" ] && HAD_AWAKE=1
[ -n "$OMARCHY" ] && [ -e "$OMARCHY/toggles/screensaver-off" ] && HAD_SAVER_OFF=1

set_governor() { for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "$1" >"$g"; done; }
restore() {
    trap - EXIT
    stop_clients
    if [ -n "$OMARCHY" ]; then
        [ $HAD_AWAKE = 1 ] || rm -f "$OMARCHY/indicators/stay-awake"
        [ $HAD_SAVER_OFF = 1 ] || rm -f "$OMARCHY/toggles/screensaver-off"
    fi
    [ -n "$GOVERNOR" ] && set_governor "$GOVERNOR"
    [ -n "$INHIBIT" ] && kill "$INHIBIT" 2>/dev/null
    dispatch "hl.dsp.focus({workspace=1})" "workspace 1"
}
trap restore EXIT
# a lost connection must not leave the machine with the settings of the run
trap 'exit 1' HUP INT TERM PIPE

if [ -n "$OMARCHY" ]; then
    asuser mkdir -p "$OMARCHY/indicators" "$OMARCHY/toggles"
    asuser touch "$OMARCHY/indicators/stay-awake" "$OMARCHY/toggles/screensaver-off"
    asuser pkill -f "[o]rg.omarchy.screensaver"
fi
dispatch 'hl.dsp.dpms({action=[[on]]})' "dpms on"

rm -rf "$OUT"
mkdir -p "$OUT"
chmod 777 "$OUT"

echo "machine: $(uname -n), $(uname -r), $(nproc) cores, $(awk '/MemTotal/ {printf "%d MiB", $2 / 1024}' /proc/meminfo)"
echo "compositor: $BINARY, pid $P, user $TESTUSER, instance $SIG"
echo "clocksource: $(cat /sys/devices/system/clocksource/clocksource0/current_clocksource 2>/dev/null)"

in_the_way() {
    H clients | grep -q "org.omarchy.screensaver" && echo " SCREENSAVER-RUNNING"
    H monitors | grep -q "solitaryBlockedBy:.*lock" && echo " SESSION-LOCKED"
}

clients() { H clients | awk '/class:/ {print $2}' | sort | uniq -c | awk '{printf "%sx %s, ", $1, $2}'; }

# ---- measuring

ROUND=1
value() { echo "@ $ROUND $1 $2"; } # key value

# on-CPU time of all threads of the compositor in ns, the 1% steps of pidstat are too coarse for small changes
cputime() { cat /proc/$P/task/*/schedstat 2>/dev/null | awk '{s += $1} END {printf "%.0f\n", s}'; }

memory() { # name
    awk -v r=$ROUND -v n="$1" '
        /^(Rss|Pss|Pss_Anon|Pss_File|Anonymous|AnonHugePages|Private_Clean|Private_Dirty):/ {sub(":", "", $1); printf "@ %s mem.%s.%s_kB %s\n", r, n, $1, $2}
    ' /proc/$P/smaps_rollup
    value "mem.$1.heap_kB" "$(awk '/\[heap\]/ {h = 1; next} h && /^Rss:/ {print $2; exit}' /proc/$P/smaps)"
    # GPU buffers are system memory on integrated graphics and in no process statistic
    # an open DRM file shows up once per file descriptor, a client id is counted once
    cat /proc/$P/fdinfo/* 2>/dev/null | awk -v r=$ROUND -v n="$1" '
        function kib(v, unit) {return unit == "MiB" ? v * 1024 : unit == "KiB" ? v : v / 1024}
        function commit() {
            if (id != "" && !(id in seen)) {
                total += t
                shared += s
                seen[id] = 1
            }
            t = s = 0
        }
        /^drm-client-id:/ {commit(); id = $2}
        /^drm-total-/ {t += kib($2, $3)}
        /^drm-shared-/ {s += kib($2, $3)}
        END {commit(); printf "@ %s mem.%s.gpu_kB %d\n@ %s mem.%s.gpu_private_kB %d\n", r, n, total, r, n, total - shared}'
    value "mem.$1.threads" "$(awk '/^Threads:/ {print $2}' /proc/$P/status)"
}

bench() { # name
    local name=$1 t0 t1 c0 c1 sampler=""
    if command -v pidstat >/dev/null; then
        pidstat -u -p $P 1 "$SECONDS_PER_RUN" >"$OUT/$name.pidstat" &
        sampler=$!
    fi
    c0=$(cputime) t0=$(date +%s%N)
    sleep "$SECONDS_PER_RUN"
    c1=$(cputime) t1=$(date +%s%N)
    [ -n "$sampler" ] && wait "$sampler"
    echo "--- $name; clients: $(clients)$(in_the_way)"
    [ -n "$(in_the_way)" ] && value "invalid.$name" 1
    value "cpu.$name.percent" "$(awk -v c=$((c1 - c0)) -v t=$((t1 - t0)) 'BEGIN {printf "%.2f", 100 * c / t}')"
    [ -n "$sampler" ] && awk -v r=$ROUND -v n="$name" -v p="$PROCESS" '
        $1 == "Average:" {printf "@ %s cpu.%s.user %s\n@ %s cpu.%s.kernel %s\n", r, n, $4, r, n, $5; next}
        $NF == p {v = $(NF - 2); s += v; q += v * v; c++}
        END {if (c > 1) printf "@ %s cpu.%s.stddev %.2f\n", r, n, sqrt((q - s * s / c) / (c - 1))}
    ' "$OUT/$name.pidstat"
}

perf_rec() { # name
    local name=$1 c0 c1 t0 t1
    c0=$(cputime) t0=$(date +%s%N)
    perf record -q -F 999 --call-graph fp -p $P -o "$OUT/$name.data" -- sleep "$SECONDS_PER_RUN" >/dev/null 2>&1
    c1=$(cputime) t1=$(date +%s%N)
    local list
    list=$(clients)
    echo
    echo "################ $name"
    echo "compositor cpu $(awk -v c=$((c1 - c0)) -v t=$((t1 - t0)) 'BEGIN {printf "%.2f", 100 * c / t}')%; clients: ${list:-none}$(in_the_way)"
    [ -s "$OUT/$name.data" ] || { echo "perf recorded nothing (kernel.perf_event_paranoid, or perf is not installed)"; return; }
    echo "--- self time by library"
    perf report -i "$OUT/$name.data" --no-children --sort dso --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" | head -6
    echo "--- self time by function"
    perf report -i "$OUT/$name.data" --no-children --sort symbol --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" | head -10 | sed -E 's/ +- +- +$//' | cut -c1-140
    echo "--- inclusive time of the main stages"
    perf report -i "$OUT/$name.data" --children --sort symbol --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" |
        grep -E "\] ($STAGES)" |
        awk '{k=$0; sub(/^ +[0-9.]+% +[0-9.]+% +\[.\] /,"",k); sub(/\(.*/,"",k); sub(/[ \t-]+$/,"",k); if(!(k in s)){s[k]=1; printf "  %7s  %s\n",$1,k}}' | head -24
}

rec() {
    if [ "$MODE" = bench ]; then bench "$1"; else perf_rec "$1"; fi
}

# ---- workloads: needs_<name> lists the programs a workload starts, workload_<name> runs it

needs_idle=""
workload_idle() {
    sleep 2
    rec idle
}

needs_gpu_client="weston-simple-egl"
workload_gpu_client() {
    local log=$OUT/fps.log
    rm -f "$log"
    client $((SECONDS_PER_RUN + 10)) "exec stdbuf -oL weston-simple-egl >$log 2>&1"
    sleep 4
    rec gpu-client
    stop_clients
    # a lower CPU time only counts when the client still gets its frames
    [ "$MODE" = bench ] && value "fps.gpu-client" "$(awk '/frames in/ {s += $(NF - 1); c++} END {if (c) printf "%.1f", s / c; else print "nan"}' "$log" 2>/dev/null)"
}

needs_terminal_scroll="foot"
workload_terminal_scroll() {
    client $((SECONDS_PER_RUN + 10)) "exec foot -e sh -c 'while true; do ls -la /usr/lib; done'"
    sleep 4
    rec terminal-scroll
    stop_clients
}

needs_shm_fullwindow="chromium"
workload_shm_fullwindow() {
    local page="data:text/html,<body style='background:linear-gradient(90deg,red,blue)'><marquee scrollamount=20 style='font:60px sans-serif;color:white'>Hypoland</marquee><div style='animation:s 2s linear infinite;width:200px;height:200px;background:lime'></div><style>@keyframes s{to{transform:translateX(900px) rotate(360deg)}}</style>"
    client $((SECONDS_PER_RUN + 40)) "exec chromium --ozone-platform=wayland --no-first-run --user-data-dir=$OUT/chromium \"$page\""
    sleep 24
    rec shm-fullwindow
    stop_clients
    sleep 1
}

needs_workspace_switch="foot"
workload_workspace_switch() {
    local i
    for i in 1 2 3; do
        client $((SECONDS_PER_RUN + 15)) "exec foot -e sleep 60"
        sleep 1
    done
    (for i in $(seq 1 "$SECONDS_PER_RUN"); do
        dispatch "hl.dsp.focus({workspace=2})" "workspace 2"; sleep 0.5
        dispatch "hl.dsp.focus({workspace=1})" "workspace 1"; sleep 0.5
    done) &
    local switcher=$!
    rec workspace-switch
    wait $switcher
    stop_clients
}

# a client given with --client
workload_custom() { # name, command
    client $((SECONDS_PER_RUN + 10)) "$2"
    sleep 4
    rec "$1"
    stop_clients
}

missing() { # programs
    local prog
    for prog in $1; do
        asuser sh -c "command -v $prog" >/dev/null 2>&1 || { echo "$prog"; return; }
    done
}

workloads() {
    local name fn needs lacking i n=0
    for name in ${WORKLOADS//,/ }; do
        fn=${name//-/_}
        n=$((n + 1))
        if ! declare -F "workload_$fn" >/dev/null || [ "$fn" = custom ]; then
            echo "=== $n $name: no such workload"
            continue
        fi
        needs=needs_$fn
        lacking=$(missing "${!needs}")
        if [ -n "$lacking" ]; then
            echo "=== $n $name: skipped, $lacking is not installed"
            continue
        fi
        echo "=== $n $name"
        "workload_$fn"
        sleep 1
    done
    for i in "${!CLIENT_NAMES[@]}"; do
        n=$((n + 1))
        echo "=== $n ${CLIENT_NAMES[$i]}: ${CLIENT_CMDS[$i]}"
        workload_custom "${CLIENT_NAMES[$i]}" "${CLIENT_CMDS[$i]}"
        sleep 1
    done
}

if [ "$MODE" = perf ]; then
    workloads
    echo
    echo "perf data: $OUT on $(uname -n)"
    exit 0
fi

# frequency scaling and a suspend would both spoil the numbers
if [ $ROOT = 1 ] && [ $KEEP_GOVERNOR = 0 ] && [ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    set_governor performance
    echo "governor: $GOVERNOR -> performance"
else
    echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo none), left alone"
fi
if [ $ROOT = 1 ] && command -v systemd-inhibit >/dev/null; then
    systemd-inhibit --what=sleep:idle:handle-lid-switch --why="compositor benchmark" sleep infinity </dev/null &
    INHIBIT=$!
fi
AC=$(cat /sys/class/power_supply/A*/online 2>/dev/null | head -1)
[ "$AC" = 0 ] && echo "WARNING: running on battery"

value "binary.size_kB" "$(($(stat -c %s "$BINARY") / 1024))"

# memory is compared when the session has settled
AGE=$(ps -o etimes= -p $P)
[ "$AGE" -lt "$SETTLE" ] && sleep $((SETTLE - AGE))
value "compositor.age_s" "$(ps -o etimes= -p $P | tr -d ' ')"
memory start

for ROUND in $(seq 1 "$ROUNDS"); do
    echo "====== round $ROUND of $ROUNDS"
    workloads
done

# what the workloads left behind: leaks, caches and buffers that are never given back
sleep 10
memory end
pgrep -x "$PROCESS" | grep -qx "$P" || value "invalid.compositor-restarted" 1
