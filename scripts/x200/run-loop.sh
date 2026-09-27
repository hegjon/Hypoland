#!/usr/bin/env bash
# Runs on the X200 from tty1 autologin: starts the compositor and restarts it whenever it exits.
# Installed as ~/hypoland/run-loop.sh. Restart the compositor with `pkill Hypoland`.
# Create ~/hypoland/stop to leave the loop and drop to a shell.
# If ~/hypoland/env exists it is sourced before every start (exported variables, e.g. HYPOLAND_PROFILE_PASS=1).
# If ~/hypoland/test.lua exists it is used as the config instead of ~/.config/hypr/hyprland.lua.

PREFIX=$HOME/hypoland
LOG=$PREFIX/loop.log

export PATH=$PREFIX/bin:$PATH
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland

FAST_EXITS=0
while [ ! -e "$PREFIX/stop" ]; do
    BIN=$(ls "$PREFIX/bin/Hypoland" "$PREFIX/bin/Hyprland" 2>/dev/null | head -1)
    if [ -z "$BIN" ]; then
        echo "$(date -Is) no compositor binary in $PREFIX/bin, waiting" >>"$LOG"
        sleep 5
        continue
    fi

    START=$(date +%s)
    echo "$(date -Is) starting $BIN" >>"$LOG"
    ARGS=()
    [ -e "$PREFIX/test.lua" ] && ARGS=(--config "$PREFIX/test.lua")
    # in a subshell, so variables from a removed env file do not stick to the loop
    (
        if [ -e "$PREFIX/env" ]; then
            set -a
            . "$PREFIX/env"
            set +a
        fi
        exec "$BIN" "${ARGS[@]}"
    ) >>"$LOG" 2>&1
    echo "$(date -Is) exited with $?" >>"$LOG"

    # back off when it dies immediately, so a broken build doesn't spin the CPU
    if [ $(($(date +%s) - START)) -lt 5 ]; then
        FAST_EXITS=$((FAST_EXITS + 1))
        [ $FAST_EXITS -ge 3 ] && sleep 10
    else
        FAST_EXITS=0
    fi
    sleep 1
    tail -n 2000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
done
