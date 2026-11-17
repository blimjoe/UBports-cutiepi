#!/usr/bin/env bash
set -euo pipefail
root=${1:-/}
dev=$(cd "$(dirname "$0")" && pwd)
install -D -m 755 "$dev/cutiepi-user-activity.py" "$root/usr/local/sbin/cutiepi-user-activity"
install -D -m 644 "$dev/cutiepi-user-activity.service" "$root/etc/systemd/system/cutiepi-user-activity.service"
if [[ "$root" == / ]]; then
    systemctl daemon-reload
    systemctl enable --now cutiepi-user-activity.service
else
    systemctl --root="$root" enable cutiepi-user-activity.service
fi
