#!/usr/bin/env bash
# One-time root setup on the X200. Run there as: sudo ./setup-root.sh [user]
# Undo with: sudo ./setup-root.sh --undo
#
# - autologin on tty1 instead of SDDM
# - passwordless `sudo reboot` for recovery from GPU hangs
# - test clients and tools

set -eu
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }

DROPIN=/etc/systemd/system/getty@tty1.service.d/hypoland-autologin.conf
SUDOERS=/etc/sudoers.d/hypoland-reboot

if [ "${1:-}" = "--undo" ]; then
    rm -f "$DROPIN" "$SUDOERS"
    systemctl daemon-reload
    systemctl enable sddm.service
    echo "restored SDDM, reboot to apply"
    exit 0
fi

TESTUSER=${1:-${SUDO_USER:-a}}

pacman -S --needed --noconfirm waybar sysstat glmark2 weston mesa-utils

mkdir -p "$(dirname "$DROPIN")"
cat >"$DROPIN" <<CONF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $TESTUSER --noclear %I \$TERM
CONF

echo "$TESTUSER ALL=(root) NOPASSWD: /usr/bin/reboot" >"$SUDOERS"
chmod 440 "$SUDOERS"
visudo -cf "$SUDOERS"

systemctl daemon-reload
systemctl disable sddm.service
systemctl enable getty@tty1.service
echo "done, reboot to apply"
