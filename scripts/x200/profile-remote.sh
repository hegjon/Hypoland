#!/usr/bin/env bash
# Runs on the X200 as root, started by profile-x200.sh. Records the compositor with perf under a few
# workloads and prints where the CPU time goes. Usage: profile-remote.sh [seconds per workload]

SECONDS_PER_RUN=${1:-12}
TESTUSER=a
RUNTIME=/run/user/$(id -u $TESTUSER)
STATE=/home/$TESTUSER/.local/state/omarchy
OUT=/tmp/hypoland-profile

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
HAD_AWAKE=0 HAD_SAVER_OFF=0
[ -e $STATE/indicators/stay-awake ] && HAD_AWAKE=1
[ -e $STATE/toggles/screensaver-off ] && HAD_SAVER_OFF=1
restore() {
    [ $HAD_AWAKE = 1 ] || rm -f $STATE/indicators/stay-awake
    [ $HAD_SAVER_OFF = 1 ] || rm -f $STATE/toggles/screensaver-off
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

rec() { # name
    local name=$1
    pidstat -u -p $P 1 $SECONDS_PER_RUN | awk '/Average/ {print $4" "$5" "$8}' >$OUT/$name.cpu &
    perf record -q -F 999 --call-graph fp -p $P -o $OUT/$name.data -- sleep $SECONDS_PER_RUN >/dev/null 2>&1
    wait
    read -r usr sys tot <$OUT/$name.cpu
    local clients
    clients=$(H clients | awk '/class:/ {print $2}' | sort | uniq -c | awk '{printf "%sx %s, ", $1, $2}')
    echo
    echo "################ $name"
    echo "compositor cpu ${tot}% (user ${usr}%, kernel ${sys}%); clients: ${clients:-none}$(in_the_way)"
    echo "--- self time by library"
    perf report -i $OUT/$name.data --no-children --sort dso --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" | head -6
    echo "--- self time by function"
    perf report -i $OUT/$name.data --no-children --sort symbol --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" | head -10 | sed -E 's/ +- +- +$//' | cut -c1-140
    echo "--- inclusive time of the main stages"
    perf report -i $OUT/$name.data --children --sort symbol --stdio -g none 2>/dev/null | grep -E "^ +[0-9]" |
        grep -E "\] (Render::IHyprRenderer::renderMonitor|Render::GL::CHyprGLRenderer::endRender|Render::GL::CHyprGLRenderer::beginRenderInternal|Render::GL::CEGLSync::create|Render::CRenderPass::render|Render::GL::CHyprOpenGLImpl::end\(\)|Render::GL::CGLFramebuffer::internalAlloc|Render::GL::CGLTexture::update|Aquamarine::CDRMOutput::commitState|drmModeAtomicCommit|Aquamarine::getDRMProp|Aquamarine::getDRMPropBlob|__x64_sys_ioctl|clock_gettime|read_hpet|_CWlSurfaceCommit|shmem_alloc_and_add_folio|drm_clflush_sg|Render::IHyprRenderer::renderLayer|Render::IHyprRenderer::renderAllClientsForWorkspace|Monitor::CMonitor::scheduleFrame|CInputManager::[A-Za-z]+|CPointerManager::[A-Za-z]+)" |
        awk '{k=$0; sub(/^ +[0-9.]+% +[0-9.]+% +\[.\] /,"",k); sub(/\(.*/,"",k); sub(/[ \t-]+$/,"",k); if(!(k in s)){s[k]=1; printf "  %7s  %s\n",$1,k}}' | head -24
}

echo "=== 1 idle desktop"
sleep 2
rec idle

echo "=== 2 GPU client at 60 fps"
start timeout $((SECONDS_PER_RUN + 10)) weston-simple-egl
sleep 4
rec gpu-client
stop -f weston-simple; sleep 1

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
rec workspace-switch
wait

echo
echo "perf data: $OUT on the X200"
