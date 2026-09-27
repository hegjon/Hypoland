#!/usr/bin/env bash
# Build on the desktop, deploy to the X200, restart the compositor there and report pass/fail.
#
# Usage: ./test-x200.sh [--no-build] [--no-deploy] [--no-restart] [--reboot]
#
# Environment:
#   X200_HOST    ssh host (default: x200)
#   X200_PREFIX  install prefix on the X200, relative to $HOME (default: hypoland)
#   BUILD_DIR    cmake build dir (default: build)
#   JOBS         parallel build jobs (default: nproc)

set -u
cd "$(dirname "$(readlink -f "$0")")" || exit 1

X200_HOST=${X200_HOST:-x200}
X200_PREFIX=${X200_PREFIX:-hypoland}
BUILD_DIR=${BUILD_DIR:-build}
JOBS=${JOBS:-$(nproc)}
STAGE=$BUILD_DIR/stage
OUT=test-results/$(date +%Y%m%d-%H%M%S)

DO_BUILD=1 DO_DEPLOY=1 DO_RESTART=1 DO_REBOOT=0
for arg in "$@"; do
    case $arg in
        --no-build) DO_BUILD=0 ;;
        --no-deploy) DO_DEPLOY=0 ;;
        --no-restart) DO_RESTART=0 ;;
        --reboot)
            # the X200 disk is encrypted, a reboot needs the user at the keyboard
            [ "${X200_ALLOW_REBOOT:-0}" = 1 ] || { echo "--reboot needs X200_ALLOW_REBOOT=1, the X200 asks for a disk password at boot" >&2; exit 2; }
            DO_REBOOT=1
            ;;
        -h | --help) sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$X200_HOST")
RESULTS=()
FAILED=0

pass() { RESULTS+=("PASS  $1"); }
fail() { RESULTS+=("FAIL  $1"); FAILED=1; }
skip() { RESULTS+=("SKIP  $1"); }

# runs a shell snippet on the X200 with the session environment of the newest compositor instance
remote() {
    "${SSH[@]}" bash -s 2>&1 <<EOF
export XDG_RUNTIME_DIR=/run/user/\$(id -u)
export PATH=\$HOME/$X200_PREFIX/bin:\$PATH
INSTANCE=\$(ls -1t \$XDG_RUNTIME_DIR/hypr 2>/dev/null | head -1)
export HYPRLAND_INSTANCE_SIGNATURE=\$INSTANCE
WL=\$(ls -1t \$XDG_RUNTIME_DIR/hypr/\$INSTANCE/../../wayland-[0-9] 2>/dev/null | head -1)
export WAYLAND_DISPLAY=\$(basename "\${WL:-wayland-1}")
BIN=\$(ls \$HOME/$X200_PREFIX/bin/Hypoland \$HOME/$X200_PREFIX/bin/Hyprland 2>/dev/null | head -1)
BINNAME=\$(basename "\${BIN:-Hypoland}")
# nothing on the X200 may hang the test run
hyprctl() { timeout 10 \$HOME/$X200_PREFIX/bin/hyprctl "\$@"; }
grim() { timeout 20 /usr/bin/grim "\$@"; }
$1
EOF
}

summary() {
    echo
    echo "==== log tail ===="
    remote 'tail -n 30 $XDG_RUNTIME_DIR/hypr/$INSTANCE/hyprland.log 2>/dev/null || echo "(no log)"'
    echo
    echo "==== summary ===="
    printf '%s\n' "${RESULTS[@]}"
    [ -d "$OUT" ] && echo "artifacts: $OUT"
    if [ $FAILED -eq 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL"; fi
    exit $FAILED
}

# ---- build

if [ $DO_BUILD -eq 1 ]; then
    if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
        cmake -S . -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_FLAGS="-march=x86-64 -mtune=core2" \
            -DCMAKE_CXX_FLAGS="-march=x86-64 -mtune=core2" >"$BUILD_DIR.configure.log" 2>&1 ||
            { fail "configure (see $BUILD_DIR.configure.log)"; tail -n 20 "$BUILD_DIR.configure.log"; summary; }
    fi
    # the embedded shader sources are generated at configure time
    cmake -S . -B "$BUILD_DIR" >"$BUILD_DIR.configure.log" 2>&1 ||
        { fail "configure (see $BUILD_DIR.configure.log)"; tail -n 20 "$BUILD_DIR.configure.log"; summary; }
    if grep -q -- '-march=native' "$BUILD_DIR/CMakeCache.txt"; then
        fail "build uses -march=native"
        summary
    fi
    if cmake --build "$BUILD_DIR" -j"$JOBS" >"$BUILD_DIR.build.log" 2>&1; then
        pass "build"
    else
        fail "build (see $BUILD_DIR.build.log)"
        grep -E 'error|Error' "$BUILD_DIR.build.log" | head -n 20
        summary
    fi
else
    skip "build"
fi

# ---- deploy

if ! "${SSH[@]}" true 2>/dev/null; then
    fail "ssh $X200_HOST"
    RESULTS+=("      X200 unreachable, nothing else was run")
    printf '%s\n' "${RESULTS[@]}"
    echo "RESULT: FAIL"
    exit 1
fi

if [ $DO_DEPLOY -eq 1 ]; then
    rm -rf "$STAGE"
    if cmake --install "$BUILD_DIR" --prefix "$PWD/$STAGE" >"$BUILD_DIR.install.log" 2>&1 &&
        rsync -a --delete --exclude='/run-loop.sh' --exclude='/test.lua' --exclude='/env' --exclude='/setup-root.sh' --exclude='/loop.log' --exclude='/stop' "$STAGE/" "$X200_HOST:$X200_PREFIX/"; then
        pass "deploy to $X200_HOST:~/$X200_PREFIX"
    else
        fail "deploy (see $BUILD_DIR.install.log)"
        summary
    fi
else
    skip "deploy"
fi

# ---- restart

if [ $DO_REBOOT -eq 1 ]; then
    "${SSH[@]}" sudo -n reboot
    echo "rebooting, waiting for ssh..."
    sleep 20
    for _ in $(seq 1 40); do "${SSH[@]}" true 2>/dev/null && break; sleep 5; done
    sleep 10
elif [ $DO_RESTART -eq 1 ]; then
    # a hung compositor ignores SIGTERM, it gets SIGKILL after 5 seconds
    remote 'OLD=$(pgrep -x "$BINNAME"); pkill -x "$BINNAME"; for i in 1 2 3 4 5; do sleep 1; [ "$(pgrep -x "$BINNAME")" != "$OLD" ] && exit 0; done; pkill -9 -x "$BINNAME"; true' >/dev/null
    sleep 1
fi

# wait for the loop script to bring up an instance that answers on the socket
UP=0
for _ in $(seq 1 20); do
    if remote 'pgrep -x "$BINNAME" >/dev/null && hyprctl version >/dev/null 2>&1 && echo up' | grep -q '^up$'; then
        UP=1
        break
    fi
    sleep 1
done

if [ $UP -eq 1 ]; then
    pass "compositor running, hyprctl responds"
else
    fail "compositor not running (is the tty1 loop set up? see scripts/x200/)"
    remote 'ls -1t ~/.cache/hyprland/ 2>/dev/null | head -n 3; tail -n 20 ~/'"$X200_PREFIX"'/loop.log 2>/dev/null'
    summary
fi

# ---- checks

mkdir -p "$OUT"

remote 'hyprctl version; hyprctl systeminfo' >"$OUT/systeminfo.txt"
grep -iE 'render|GLES|OpenGL' "$OUT/systeminfo.txt" | head -n 5

CONFIGERRORS=$(remote 'hyprctl configerrors')
if [ -z "$(echo "$CONFIGERRORS" | tr -d '[:space:]')" ]; then
    pass "config loads without errors"
else
    fail "config errors"
    echo "$CONFIGERRORS" | head -n 20
fi

# with a Lua config, options are set through eval instead of keyword
KEYWORD=$(remote 'hyprctl eval "hl.config({decoration={blur={enabled=true}}})"')
if [ "$KEYWORD" = "ok" ]; then pass "setting a blur option returns ok"; else fail "setting a blur option: $KEYWORD"; fi

# an idle X200 turns its panel off, and with the panel off nothing is rendered and grim blocks
remote 'hyprctl dispatch "hl.dsp.dpms({action=[[on]]})" >/dev/null; sleep 1'
DPMS=$(remote 'hyprctl monitors | grep -m1 dpmsStatus')
RESULTS+=("INFO  $(echo $DPMS)")

# Omarchy starts a fullscreen screensaver after 150 s without input and locks after 300 s.
# Both cover the windows under test and distort every measurement.
IDLE=$(remote 'pkill -f "[o]rg.omarchy.screensaver" && echo screensaver; hyprctl monitors | grep -q "solitaryBlockedBy:.*lock" && echo locked; true')
case $IDLE in
    *locked*) fail "session is locked, results are not valid (restart the compositor to clear it)" ;;
    *screensaver*) RESULTS+=("INFO  a running screensaver was closed") ;;
    *) pass "no screensaver or lock in the way" ;;
esac

BEFORE=$(remote 'hyprctl clients -j | grep -c "\"address\""')
# the test terminal fills itself with magenta, so the screenshot can prove that the window is drawn
cat >"$OUT/magenta.sh" <<'MAGENTA'
#!/bin/sh
i=0
while [ $i -lt 120 ]; do
    printf '\033[48;2;255;0;255m%400s' ''
    i=$((i + 1))
done
sleep 30
MAGENTA
scp -q "$OUT/magenta.sh" "$X200_HOST:/tmp/hypoland-magenta.sh"
remote 'chmod +x /tmp/hypoland-magenta.sh; hyprctl dispatch "hl.dsp.exec_cmd([[foot -e /tmp/hypoland-magenta.sh]])" >/dev/null; sleep 4'
AFTER=$(remote 'hyprctl clients -j | grep -c "\"address\""')
if [ "${AFTER:-0}" -gt "${BEFORE:-0}" ]; then pass "foot window mapped"; else fail "foot window did not map"; fi

if remote 'grim /tmp/hypoland-shot.png' >"$OUT/grim.log" && scp -q "$X200_HOST:/tmp/hypoland-shot.png" "$OUT/screenshot.png"; then
    pass "screenshot: $OUT/screenshot.png"
else
    fail "screenshot (see $OUT/grim.log)"
fi

# a mapped window is not necessarily a drawn one
if [ -f "$OUT/screenshot.png" ] && command -v magick >/dev/null; then
    PERCENT=$(magick "$OUT/screenshot.png" -fuzz 12% -fill white -opaque '#ff00ff' -fill black +opaque white -format '%[fx:int(mean*100)]' info:)
    if [ "${PERCENT:-0}" -ge 10 ]; then pass "window is drawn ($PERCENT% of the screen is the test color)"; else fail "window is not drawn ($PERCENT% of the screen is the test color)"; fi
else
    skip "window drawn check (no screenshot or no ImageMagick)"
fi

remote 'pkill -n -x foot; true' >/dev/null

remote 'ps -o pid,rss,pcpu,etime,args -C "$BINNAME"' | tee "$OUT/resources.txt"
RSS=$(awk 'NR==2 {print int($2/1024)}' "$OUT/resources.txt")
RESULTS+=("INFO  compositor RSS: ${RSS:-?} MiB")

GLERRORS=$(remote 'grep -ciE "GL_INVALID|GLES error|shader.*fail" $XDG_RUNTIME_DIR/hypr/$INSTANCE/hyprland.log')
if [ "${GLERRORS:-0}" -eq 0 ]; then pass "no GL errors in log"; else fail "$GLERRORS GL error lines in log"; fi

remote 'cat $XDG_RUNTIME_DIR/hypr/$INSTANCE/hyprland.log' >"$OUT/hyprland.log"

summary
