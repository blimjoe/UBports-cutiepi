#!/usr/bin/env bash
# Assemble a file-backed SD image in the Linux VM. Never opens a physical disk.
set -euo pipefail
test "$(uname -s)" = Linux
base="$HOME/cutiepi"
kernel="$base/images/kernel-ab4372076bb840600e522ae776887ae2bc488fa6"
firmware="$base/src/rpi-firmware-896fc67d292bfde6d9889d4c585bb685758dc1ad"
rootfs_dir="$base/build/rootfs"
rootfs="$rootfs_dir/cutiepi-ut-mainline-rootfs.tar.gz"
images="$base/images"
name=${1:-cutiepi-ut-mainline-dev}.img
[[ "$name" =~ ^cutiepi-ut-[a-z0-9-]+\.img$ ]]
image="$images/$name"
test -f "$rootfs"
test -f "$kernel/SHA256SUMS"
test -f "$firmware/SHA256SUMS"
test -s /mnt/project/artifacts/wifi.nmconnection
(cd "$kernel" && sha256sum -c SHA256SUMS)
(cd "$firmware" && sha256sum -c SHA256SUMS)
(cd "$rootfs_dir" && sha256sum -c SHA256SUMS)
# Do not truncate an existing image on a rerun.
test ! -e "$image" && test ! -e "$image.gz"
umask 077
work=$(mktemp -d "$base/build/image-mount.XXXXXX")
pending=$(mktemp -d "$images/.cutiepi-image.XXXXXX")
draft="$pending/$name"
loop=""
cleanup() {
  if mountpoint -q "$work/boot/firmware"; then sudo umount "$work/boot/firmware"; fi
  if mountpoint -q "$work"; then sudo umount "$work"; fi
  if [ -n "$loop" ]; then sudo losetup -d "$loop"; fi
  rmdir "$work"
  rm -f "$pending/$name" "$pending/$name.gz" "$pending/$name.sha256" "$pending/$name.gz.sha256"
  rmdir "$pending"
}
trap cleanup EXIT
truncate -s 8G "$draft"
parted -s "$draft" mklabel msdos
parted -s "$draft" mkpart primary fat32 1MiB 513MiB
parted -s "$draft" set 1 boot on
parted -s "$draft" mkpart primary ext4 513MiB 100%
loop=$(sudo losetup --find --show --partscan "$draft")
sudo udevadm settle
sudo mkfs.vfat -F 32 -n CUTIEPIBOOT "${loop}p1"
sudo mkfs.ext4 -F -L CUTIEPIROOT "${loop}p2"
sudo mount "${loop}p2" "$work"
sudo tar --numeric-owner --xattrs --xattrs-include='*.*' --acls -xzf "$rootfs" -C "$work"
sudo bash /mnt/project/dev/install-native-session.sh "$work"
sudo install -D -m 644 /mnt/project/dev/cutiepi-deviceinfo.yaml "$work/etc/deviceinfo/devices/cutiepi.yaml"
for package in ubuntu-touch ubuntu-touch-core-mainline lomiri-qt5-mir2 ubuntu-touch-session-wayland mir-platform-graphics-gbm-kms; do
  version=$(sudo chroot "$work" dpkg-query -W -f='${db:Status-Abbrev} ${Version}' "$package")
  [[ "$version" == 'ii  '* ]]
  printf '%s: %s\n' "$package" "${version#ii  }"
done
# The Raspberry Pi baseline does not enable loading compressed firmware.
# Preserve the packaged originals and provide the three CM4 Wi-Fi files
# uncompressed so brcmfmac can bring up the device before SSH is available.
brcm="$work/usr/lib/firmware/brcm"
for blob in brcmfmac43455-sdio.bin brcmfmac43455-sdio.clm_blob brcmfmac43455-sdio.raspberrypi,4-compute-module.txt; do
  if ! sudo test -s "$brcm/$blob"; then
    sudo zstd -q -dfc "$brcm/$blob.zst" | sudo tee "$brcm/$blob" >/dev/null
  fi
  sudo test -s "$brcm/$blob"
done
sudo install -D -m 755 /mnt/project/dev/cutiepi-boot-report.sh "$work/usr/local/sbin/cutiepi-boot-report"
sudo install -D -m 755 /mnt/project/dev/cutiepi-power-button.py "$work/usr/local/sbin/cutiepi-power-button"
for unit in cutiepi-boot-report.service cutiepi-boot-report.timer cutiepi-power-button.service; do
  sudo install -D -m 644 "/mnt/project/dev/$unit" "$work/etc/systemd/system/$unit"
done
sudo chroot "$work" nmcli --offline connection modify connection.autoconnect yes < /mnt/project/artifacts/wifi.nmconnection > /dev/null
sudo chroot "$work" sh -ec 'mkdir -p /etc/NetworkManager/system-connections; umask 077; cat > /etc/NetworkManager/system-connections/cutiepi-bootstrap.nmconnection; chown 0:0 /etc/NetworkManager/system-connections/cutiepi-bootstrap.nmconnection' < /mnt/project/artifacts/wifi.nmconnection
sudo mkdir -p "$work/boot/firmware" "$work/lib/modules"
sudo mount "${loop}p1" "$work/boot/firmware"
sudo cp "$firmware/start4.elf" "$firmware/fixup4.dat" "$firmware/LICENCE.broadcom" "$work/boot/firmware/"
sudo cp "$kernel/kernel8.img" "$kernel/boot/bcm2711-rpi-cm4.dtb" "$work/boot/firmware/"
sudo cp -R "$kernel/boot/overlays" "$work/boot/firmware/"
dtc -@ -I dts -O dtb -o "$base/build/cutiepi-deviceinfo.dtbo" /mnt/project/dev/cutiepi-deviceinfo-overlay.dts
sudo cp "$base/build/cutiepi-deviceinfo.dtbo" "$work/boot/firmware/overlays/"
sudo cp -a "$kernel/lib/modules/." "$work/lib/modules/"
cat <<'EOF' | sudo tee "$work/boot/firmware/config.txt" >/dev/null
arm_64bit=1
kernel=kernel8.img
device_tree=bcm2711-rpi-cm4.dtb
disable_overscan=1
disable_fw_kms_setup=1
display_auto_detect=0
camera_auto_detect=0
max_framebuffers=2
dtoverlay=vc4-kms-v3d,cma-256
dtparam=audio=on
[cm4]
otg_mode=1
dtparam=i2c_arm=on
dtoverlay=cutiepi-panel
dtoverlay=cutiepi-deviceinfo
enable_uart=1
dtoverlay=uart1
[all]
EOF
partuuid=$(sudo blkid -s PARTUUID -o value "${loop}p2")
printf 'console=tty1 root=PARTUUID=%s rootfstype=ext4 rootwait rw loglevel=7 video=HDMI-A-1:d video=HDMI-A-2:d\n' "$partuuid" | sudo tee "$work/boot/firmware/cmdline.txt" >/dev/null
printf 'LABEL=CUTIEPIROOT / ext4 defaults,noatime 0 1\nLABEL=CUTIEPIBOOT /boot/firmware vfat defaults 0 2\n' | sudo tee "$work/etc/fstab" >/dev/null
printf 'cutiepi\n' | sudo tee "$work/etc/writable/hostname" >/dev/null
sudo chroot "$work" depmod -a "$(cat "$kernel/kernelrelease.txt")"
sudo systemd-nspawn -q --register=no --resolv-conf=off --timezone=off --console=pipe -D "$work" \
  /bin/sh -ec 'mkdir -p /run/sshd; ssh-keygen -q -A; /usr/sbin/sshd -t; exec /usr/sbin/sshd -T' | awk '
  $1 == "passwordauthentication" && $2 == "no" {password=1}
  $1 == "kbdinteractiveauthentication" && $2 == "no" {interactive=1}
  $1 == "permitrootlogin" && $2 == "no" {root=1}
  $1 == "pubkeyauthentication" && $2 == "yes" {pubkey=1}
  END {exit !(password && interactive && root && pubkey)}
'
sudo find "$work/etc/ssh" -maxdepth 1 -name 'ssh_host_*' -type f -delete
sudo chroot "$work" test -x /usr/bin/lomiri
sudo chroot "$work" sh -n /usr/local/bin/cutiepi-session
sudo grep -Fq 'run-systemd-session ubuntu-touch-session-unencrypted.target' "$work/usr/local/bin/cutiepi-session"
sudo test -s "$work/home/phablet/.ssh/authorized_keys"
test "$(sudo stat -c '%a:%u:%g' "$work/etc/NetworkManager/system-connections/cutiepi-bootstrap.nmconnection")" = '600:0:0'
test "$(sudo stat -c '%a:%u:%g' "$work/home/phablet/.ssh/authorized_keys")" = '600:32011:32011'
sudo systemctl --root="$work" set-default graphical.target
sudo test -L "$work/etc/systemd/system/display-manager.service"
sudo chroot "$work" python3 -c 'import dbus.lowlevel, dbus.service'
sudo systemctl --root="$work" enable NetworkManager.service avahi-daemon.service cutiepi-boot-report.timer cutiepi-power-button.service
sudo sync
sudo umount "$work/boot/firmware"
sudo umount "$work"
sudo e2fsck -fn "${loop}p2"
sudo fsck.vfat -n "${loop}p1"
sudo losetup -d "$loop"
loop=""
cd "$pending"
sha256sum "$name" > "$name.sha256"
gzip -1 -k "$name"
sha256sum "$name.gz" > "$name.gz.sha256"
mv "$name" "$name.gz" "$name.sha256" "$name.gz.sha256" "$images/"
cd "$images"
echo "Unbooted development image created: $image.gz"
