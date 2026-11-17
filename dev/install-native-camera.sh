#!/usr/bin/env bash
set -euo pipefail
root=$(realpath "$1")
dev=$(cd "$(dirname "$0")" && pwd)
if ! chroot "$root" dpkg-query -W -f='${db:Status-Abbrev}' gstreamer1.0-libcamera 2>/dev/null | grep -q '^ii '; then
    (
        saved=$(mktemp -d "$root/etc/.camera-resolver.XXXXXX")
        mv "$root/etc/resolv.conf" "$saved/resolv.conf"
        trap 'rm -f "$root/etc/resolv.conf"; mv "$saved/resolv.conf" "$root/etc/resolv.conf"; rmdir "$saved"' EXIT
        install -m 644 /etc/resolv.conf "$root/etc/resolv.conf"
        systemd-nspawn -q --register=no --resolv-conf=off --timezone=off --console=pipe -D "$root" \
            /bin/sh -ec 'apt-get update -o APT::Update::Error-Mode=any && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libcamera-ipa gstreamer1.0-libcamera && apt-get clean'
    )
fi
install -D -m 644 "$dev/cutiepi-camera.apparmor" "$root/etc/apparmor.d/abstractions/cutiepi-camera"
printf 'SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"\n' > "$root/etc/udev/rules.d/80-cutiepi-camera.rules"
# The template's explicit deny overrides even a camera policy group's allow.
# Other apps retain an implicit deny; only camera apps receive the allow.
python3 - "$root" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
base = root / 'usr/share/apparmor/easyprof'
template = base / 'templates/ubuntu/2604.1/ubuntu-sdk'
s = template.read_text()
s = '\n'.join(line for line in s.splitlines() if line.strip() != 'deny /run/udev/data/** r,') + '\n'
template.write_text(s)
group = base / 'policygroups/ubuntu/2604.1/camera'
s = group.read_text()
rule = '#include <abstractions/cutiepi-camera>'
if rule not in s:
    group.write_text(s + '\n' + rule + '\n')
PY
session="$root/etc/profile.d/cutiepi-camera.sh"
printf 'export QT_GSTREAMER_CAMERABIN_VIDEOSRC=libcamerasrc\nexport ORC_CODE=backup\n' > "$session"

install -D -m 644 "$dev/cutiepi-camera-policy.service" "$root/etc/systemd/system/cutiepi-camera-policy.service"
systemctl --root="$root" enable cutiepi-camera-policy.service

python3 "$dev/patch-native-camera.py" "$root"
