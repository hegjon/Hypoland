#!/usr/bin/env bash
# Runs on the X200 as root, started by profile-x200.sh or bench-x200.sh. Puts the compositor under a few
# workloads and reports what it costs.
#
# Usage: profile-remote.sh [seconds per workload] [perf|bench] [rounds]
#   perf   records every workload with perf and prints where the CPU time goes (default)
#   bench  measures CPU time and memory only, on the normal build. Lines starting with "@" are the
#          values: "@ <round> <key> <value>"

SECONDS_PER_RUN=${1:-12}
MODE=${2:-perf}
ROUNDS=${3:-1}
TESTUSER=a
RUNTIME=/run/user/$(id -u $TESTUSER)
STATE=/home/$TESTUSER/.local/state/omarchy
OUT=/tmp/hypoland-profile
FPSLOG=/tmp/hypoland-bench-fps.log
ROUND=1

P=$(pgrep -x Hypoland) || { echo "Hypoland is not running"; exit 1; }
SIG=$(ls -1t $RUNTIME/hypr | head -1)

asuser() {
    sudo -u $TESTUSER env HOME=/home/$TESTUSER XDG_RUNTIME_DIR=$RUNTIME WAYLAND_DISPLAY=wayland-1 DISPLAY=:0 HYPRLAND_INSTANCE_SIGNATURE=$SIG \
        OMARCHY_PATH=/usr/share/omarchy PATH=/home/$TESTUSER/hypoland/bin:/usr/bin "$@"
}
H() { asuser timeout 8 hyprctl "$@"; }
# clients are started by the compositor, like a keybinding would
start() { H dispatch "hl.dsp.exec_cmd([[$*]])" >/dev/null; }
stop() { asuser pkill "$@" 2>/dev/null; }

# The Omarchy shell starts a screensaver after 150 s and locks after 300 s without input. Both are
# switched off for the run with the flag files its own toggles use, and put back afterwards.
HAD_AWAKE=0 HAD_SAVER_OFF=0 GOVERNOR="" INHIBIT=""
[ -e $STATE/indicators/stay-awake ] && HAD_AWAKE=1
[ -e $STATE/toggles/screensaver-off ] && HAD_SAVER_OFF=1
set_governor() { for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "$1" >"$g"; done; }
restore() {
    [ $HAD_AWAKE = 1 ] || rm -f $STATE/indicators/stay-awake
    [ $HAD_SAVER_OFF = 1 ] || rm -f $STATE/toggles/screensaver-off
    [ -n "$GOVERNOR" ] && set_governor "$GOVERNOR"
    [ -n "$INHIBIT" ] && kill "$INHIBIT" 2>/dev/null
    stop -x foot
    stop -f weston-simple
    stop chromium
    H dispatch "hl.dsp.focus({workspace=1})" >/dev/null
}
trap restore EXIT
asuser mkdir -p $STATE/indicators $STATE/toggles
asuser touch $STATE/indicators/stay-awake $STATE/toggles/screensaver-off
stop -f "[o]rg.omarchy.screensaver"
H dispatch 'hl.dsp.dpms({action=[[on]]})' >/dev/null

rm -rf $OUT; mkdir -p $OUT
echo "clocksource: $(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)"

in_the_way() {
    H clients | grep -q "org.omarchy.screensaver" && echo " SCREENSAVER-RUNNING"
    H monitors | grep -q "solitaryBlockedBy:.*lock" && echo " SESSION-LOCKED"
}

clients() { H clients | awk '/class:/ {print $2}' | sort | uniq -c | awk '{printf "%sx %s, ", $1, $2}'; }

# on-CPU time of all threads of the compositor in ns, the 1% steps of pidstat are too coarse for small changes
cputime() { cat /proc/$P/task/*/schedstat 2>/dev/null | awk '{s += $1} END {printf "%.0f\n", s}'; }

value() { echo "@ $ROUND $1 $2"; } # key value

memory() { # name
    awk -v r=$ROUND -v n="$1" '
        /^(Rss|Pss|Pss_Anon|Pss_File|Anonymous|AnonHugePages|Private_Clean|Private_Dirty):/ {sub(":", "", $1); printf "@ %s mem.%s.%s_kB %s\n", r, n, $1, $2}
    ' /proc/$P/smaps_rollup
    value "mem.$1.heap_kB" "$(awk '/\[heap\]/ {h = 1; next} h && /^Rss:/ {print $2; exit}' /proc/$P/smaps)"
    value "mem.$1.threads" "$(awk '/^Threads:/ {print $2}' /proc/$P/status)"
}

bench() { # name
    local name=$1 t0 t1 c0 c1
    pidstat -u -p $P 1 $SECONDS_PER_RUN >$OUT/$name.pidstat &
    c0=$(cputime) t0=$(date +%s%N)
    sleep $SECONDS_PER_RUN
    c1=$(cputime) t1=$(date +%s%N)
    wait $!
    echo "--- $name; clients: $(clients)$(in_the_way)"
    [ -n "$(in_the_way)" ] && value "invalid.$name" 1
    value "cpu.$name.percent" "$(awk -v c=$((c1 - c0)) -v t=$((t1 - t0)) 'BEGIN {printf "%.2f", 100 * c / t}')"
    awk -v r=$ROUND -v n="$name" '
        $1 == "Average:" {printf "@ %s cpu.%s.user %s\n@ %s cpu.%s.kernel %s\n", r, n, $4, r, n, $5; next}
        $NF == "Hypoland" {v = $(NF - 2); s += v; q += v * v; c++}
        END {if (c > 1) printf "@ %s cpu.%s.stddev %.2f\n", r, n, sqrt((q - s * s / c) / (c - 1))}
    ' $OUT/$name.pidstat
}

perf_rec() { # name
    local name=$1
    pidstat -u -p $P 1 $SECONDS_PER_RUN | awk '/Average/ {print $4" "$5" "$8}' >$OUT/$name.cpu &
    perf record -q -F 999 --call-graph fp -p $P -o $OUT/$name.data -- sleep $SECONDS_PER_RUN >/dev/null 2>&1
    wait $!
    read -r usr sys tot <$OUT/$name.cpu
    local list
    list=$(clients)
    echo
    echo "################ $name"
    echo "compositor cpu ${tot}% (user ${usr}%, kernel ${sys}%); clients: ${list:-none}$(in_the_way)"
    echo "--- self time by library"
    perf report -i $OUT/$name.data --no-children --sort dso --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" | head -6
    echo "--- self time by function"
    perf report -i $OUT/$name.data --no-children --sort symbol --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" | head -10 | sed -E 's/ +- +- +$//' | cut -c1-140
    echo "--- inclusive time of the main stages"
    perf report -i $OUT/$name.data --children --sort symbol --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" |
        grep -E "\] (Render::IHyprRenderer::renderMonitor|Render::GL::CHyprGLRenderer::endRender|Render::GL::CHyprGLRenderer::beginRenderInternal|Render::GL::CEGLSync::create|Render::CRenderPass::render|Render::GL::CHyprOpenGLImpl::end\(\)|Render::GL::CGLFramebuffer::internalAlloc|Render::GL::CGLTexture::update|Aquamarine::CDRMOutput::commitState|drmModeAtomicCommit|Aquamarine::getDRMProp|Aquamarine::getDRMPropBlob|__x64_sys_ioctl|clock_gettime|read_hpet|_CWlSurfaceCommit|shmem_alloc_and_add_folio|drm_clflush_sg|Render::IHyprRenderer::renderLayer|Render::IHyprRenderer::renderAllClientsForWorkspace|Monitor::CMonitor::scheduleFrame|CInputManager::[A-Za-z]+|CPointerManager::[A-Za-z]+)" |
        awk '{k=$0; sub(/^ +[0-9.]+% +[0-9.]+% +\[.\] /,"",k); sub(/\(.*/,"",k); sub(/[ \t-]+$/,"",k); if(!(k in s)){s[k]=1; printf "  %7s  %s\n",$1,k}}' | head -24
}

rec() {
    if [ "$MODE" = bench ]; then bench "$1"; else perf_rec "$1"; fi
}

workloads() {
    echo "=== 1 idle desktop"
    sleep 2
    rec idle

    echo "=== 2 GPU client at 60 fps"
    rm -f $FPSLOG
    start "timeout $((SECONDS_PER_RUN + 10)) stdbuf -oL weston-simple-egl >$FPSLOG 2>&1"
    sleep 4
    rec gpu-client
    stop -f weston-simple; sleep 1
    # a lower CPU time only counts when the client still gets its frames
    [ "$MODE" = bench ] && value "fps.gpu-client" "$(awk '/frames in/ {s += $(NF - 1); c++} END {if (c) printf "%.1f", s / c; else print "nan"}' $FPSLOG 2>/dev/null)"

    echo "=== 3 terminal scrolling"
    cat >/tmp/hypoland-scroll.sh <<'SCROLL'
#!/bin/sh
while true; do ls -la /usr/lib; done
SCROLL
    chmod 755 /tmp/hypoland-scroll.sh
    start timeout $((SECONDS_PER_RUN + 10)) foot -e /tmp/hypoland-scroll.sh
    sleep 4
    rec terminal-scroll
    stop -x foot; sleep 1

    echo "=== 4 software rendered client redrawing a large window"
    (asuser setsid timeout $((SECONDS_PER_RUN + 40)) chromium --ozone-platform=wayland --no-first-run --user-data-dir=/tmp/hypoland-chromium \
        "data:text/html,<body style='background:linear-gradient(90deg,red,blue)'><marquee scrollamount=20 style='font:60px sans-serif;color:white'>Hypoland</marquee><div style='animation:s 2s linear infinite;width:200px;height:200px;background:lime'></div><style>@keyframes s{to{transform:translateX(900px) rotate(360deg)}}</style>" >/dev/null 2>&1 &)
    sleep 24
    rec shm-fullwindow
    stop chromium; sleep 2

    echo "=== 5 workspace switching with three windows"
    for i in 1 2 3; do start timeout $((SECONDS_PER_RUN + 15)) foot -e sleep 60; sleep 1; done
    (for i in $(seq 1 $SECONDS_PER_RUN); do
        H dispatch "hl.dsp.focus({workspace=2})" >/dev/null; sleep 0.5
        H dispatch "hl.dsp.focus({workspace=1})" >/dev/null; sleep 0.5
    done) &
    local switcher=$!
    rec workspace-switch
    wait $switcher
    stop -x foot; sleep 2
}

if [ "$MODE" != bench ]; then
    workloads
    echo
    echo "perf data: $OUT on the X200"
    exit 0
fi

# frequency scaling and a suspend would both spoil the numbers
GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
set_governor performance
systemd-inhibit --what=sleep:idle:handle-lid-switch --why="Hypoland benchmark" sleep infinity &
INHIBIT=$!
echo "governor: $GOVERNOR -> performance, AC online: $(cat /sys/class/power_supply/AC*/online 2>/dev/null)"

# memory is compared 60 s after the start, when the session has settled
AGE=$(ps -o etimes= -p $P)
[ "$AGE" -lt 60 ] && sleep $((60 - AGE))
value "compositor.age_s" "$(ps -o etimes= -p $P | tr -d ' ')"
memory start

for ROUND in $(seq 1 "$ROUNDS"); do
    echo "====== round $ROUND of $ROUNDS"
    workloads
done

# what the workloads left behind: leaks, caches and buffers that are never given back
sleep 10
memory end
pgrep -x Hypoland | grep -qx "$P" || value "invalid.compositor-restarted" 1
