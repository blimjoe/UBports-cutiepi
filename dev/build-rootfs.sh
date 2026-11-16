#!/usr/bin/env bash
set -euo pipefail
test "$(uname -s)" = Linux
test "$(uname -m)" = aarch64
revision=e0a2e4cc606b39d2afc5029e607ea29e3e1984b5
src="$HOME/cutiepi/src/rootfs-builder-debos"
out="$HOME/cutiepi/build/rootfs"
test "$(git -C "$src" rev-parse HEAD)" = "$revision"
mkdir -p "$out"
base_url=https://cdimage.ubuntu.com/ubuntu-base/releases/26.04/release
base_archive=ubuntu-base-26.04-base-arm64.tar.gz
mkdir -p "$out/base"
(
  cd "$out/base"
  if ! sha256sum --check --status --ignore-missing SHA256SUMS 2>/dev/null || ! test -s "$base_archive"; then
    for name in SHA256SUMS "$base_archive"; do
      curl -fsSL --retry 6 --retry-all-errors --connect-timeout 15 --max-time 180 \
        "$base_url/$name" -o "$name.part"
      mv "$name.part" "$name"
    done
  fi
  sha256sum --check --ignore-missing SHA256SUMS
)
# The upstream recipe assumes fakemachine's /scratch. In this VM's direct
# mode ROOTDIR points to the temporary build root; use its parent instead.
git -C "$src" show "$revision:ubuntu-touch/common-base.yaml" > "$out/common-base.upstream.yaml"
git -C "$src" show "$revision:common/download-and-extract-deb.yaml" > "$out/download-and-extract-deb.upstream.yaml"
python3 - "$out" "$src" <<'PY'
from pathlib import Path
import sys
cache = Path(sys.argv[1])
source = Path(sys.argv[2])
text = (cache / 'common-base.upstream.yaml').read_text()
start = text.index('  - action: download\n')
end = text.index('  # Instead of an unpack action', start)
text = text[:start] + text[end:]
old = 'tar --numeric-owner -xzf {{ $ubuntu_base }} -C root'
assert text.count(old) == 1
text = text.replace(old, 'tar --numeric-owner -xzf "$ARTIFACTDIR/base/{{ $ubuntu_base }}" -C "$ROOTDIR"')
(source / 'ubuntu-touch/common-base.yaml').write_text(text)

text = (cache / 'download-and-extract-deb.upstream.yaml').read_text()
assert text.count('/scratch/pkg.deb') == 2
text = text.replace('/scratch/pkg.deb', '"${ROOTDIR%/*}/pkg.deb"')
(source / 'common/download-and-extract-deb.yaml').write_text(text)
PY
cp /mnt/project/dev/cutiepi-rootfs.yaml "$src/cutiepi-rootfs.yaml"
rm -f "$src/ubuntu-touch/ubuntu-touch/hooks/99zz-cutiepi-mir2.chroot"
install -m 755 /mnt/project/dev/select-mir2.chroot "$src/select-mir2.chroot"
overlay="$src/cutiepi-overlay"
mkdir -p "$overlay/home/phablet/.ssh" "$overlay/etc/ssh/sshd_config.d" "$overlay/etc/ubuntu-touch-session.d"
mkdir -p "$overlay/etc/systemd/system/ssh.service.d"
mkdir -p "$overlay/etc/systemd/journald.conf.d"
mkdir -p "$overlay/etc/deviceinfo/devices"
cp /mnt/project/dev/cutiepi-deviceinfo.yaml "$overlay/etc/deviceinfo/devices/cutiepi.yaml"
printf '[Journal]\nStorage=persistent\nSystemMaxUse=64M\n' > "$overlay/etc/systemd/journald.conf.d/cutiepi.conf"
cat > "$overlay/etc/systemd/system/cutiepi-ssh-hostkeys.service" <<'EOF'
[Unit]
Description=Generate unique SSH host keys on first boot
Before=ssh.service
[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
[Install]
WantedBy=multi-user.target
EOF
printf '[Unit]\nRequires=cutiepi-ssh-hostkeys.service\nAfter=cutiepi-ssh-hostkeys.service\n' > "$overlay/etc/systemd/system/ssh.service.d/cutiepi.conf"
cp /mnt/project/artifacts/cutiepi-dev-key.pub "$overlay/home/phablet/.ssh/authorized_keys"
cat /mnt/project/dev/extra-authorized-keys >> "$overlay/home/phablet/.ssh/authorized_keys"
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' > "$overlay/etc/ssh/sshd_config.d/00-cutiepi-dev.conf"
printf 'GRID_UNIT_PX=12\nNATIVE_ORIENTATION=portrait\nFORM_FACTOR=tablet\n' > "$overlay/etc/ubuntu-touch-session.d/cutiepi.conf"
cd "$src"
# The dedicated Linux VM supplies mount/chroot support directly; no nested KVM.
sudo "$HOME/go/bin/debos" --disable-fakemachine --artifactdir="$out" cutiepi-rootfs.yaml
sudo chown "$(id -u):$(id -g)" "$out/cutiepi-ut-mainline-rootfs.tar.gz"
cd "$out"
sha256sum cutiepi-ut-mainline-rootfs.tar.gz > SHA256SUMS
