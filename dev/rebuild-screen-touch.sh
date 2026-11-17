#!/usr/bin/env bash
# Apply device fixes to the SD image that already booted on the CutiePi.
set -euo pipefail
base="$HOME/cutiepi"
source_dir="$base/build/known-good"
images="$base/images"
name=${1:-cutiepi-ut-mainline-power-key}.img
[[ "$name" =~ ^cutiepi-ut-[a-z0-9-]+\.img$ ]]
test ! -e "$images/$name.gz"
(cd "$source_dir" && sha256sum -c SHA256SUMS)

umask 077
pending=$(mktemp -d "$images/.cutiepi-screen-touch.XXXXXX")
root="$pending/root"
image="$pending/$name"
mkdir "$root"
loop=''
cleanup() {
  if mountpoint -q "$root/boot/firmware"; then sudo umount "$root/boot/firmware"; fi
  if mountpoint -q "$root"; then sudo umount "$root"; fi
  if [[ -n "$loop" ]]; then sudo losetup -d "$loop"; fi
  rm -f "$pending/$name" "$pending/$name.gz" "$pending/$name.gz.sha256"
  rmdir "$root" "$pending"
}
trap cleanup EXIT

gzip -dc "$source_dir/cutiepi-ut-mainline-dev.img.gz" | dd of="$image" bs=4M iflag=fullblock conv=sparse status=none
loop=$(sudo losetup --find --show --partscan "$image")
sudo udevadm settle
sudo mount "${loop}p2" "$root"
sudo mount "${loop}p1" "$root/boot/firmware"
boot="$root/boot/firmware"

sudo bash /mnt/project/dev/install-native-session.sh "$root"
sudo install -m 644 /mnt/project/dev/cutiepi-deviceinfo.yaml "$root/etc/deviceinfo/devices/cutiepi.yaml"
sudo install -m 755 /mnt/project/dev/cutiepi-boot-report.sh "$root/usr/local/sbin/cutiepi-boot-report"
sudo install -m 755 /mnt/project/dev/cutiepi-power-button.py "$root/usr/local/sbin/cutiepi-power-button"
sudo install -m 644 /mnt/project/dev/cutiepi-power-button.service "$root/etc/systemd/system/cutiepi-power-button.service"
sudo chroot "$root" python3 -c 'import dbus.lowlevel, dbus.service'
sudo systemctl --root="$root" enable cutiepi-power-button.service

# Stop HDMI mode injection by the firmware and give the first touch test a
# single display. Lowercase :d is DRM's forced-off connector option.
printf '\ndisable_fw_kms_setup=1\n' | sudo tee -a "$boot/config.txt" >/dev/null
cmdline=$(sudo cat "$boot/cmdline.txt")
case " $cmdline " in
  *' video='*) echo 'Unexpected video override in the original image' >&2; exit 1 ;;
esac
printf '%s video=HDMI-A-1:d video=HDMI-A-2:d\n' "$cmdline" | sudo tee "$boot/cmdline.txt" >/dev/null
sudo bash /mnt/project/dev/install-cutiepi-imu.sh "$root"
partuuid=$(sudo blkid -s PARTUUID -o value "${loop}p2")
grep -Fq "root=PARTUUID=$partuuid " "$boot/cmdline.txt"

sudo chroot "$root" sh -n /usr/local/bin/cutiepi-session
sudo chroot "$root" sh -n /usr/local/bin/cutiepi-lomiri-wrapper
sudo grep -Fxq '    exec /usr/share/ubuntu-touch-session/run-systemd-session ubuntu-touch-session-unencrypted.target' "$root/usr/local/bin/cutiepi-session"
sudo test -s "$root/home/phablet/.ssh/authorized_keys"
sudo test -s "$root/etc/NetworkManager/system-connections/cutiepi-bootstrap.nmconnection"
sudo chroot "$root" /usr/sbin/lightdm --show-config
sudo sync
sudo umount "$boot"
sudo umount "$root"
sudo fsck.vfat -n "${loop}p1"
sudo e2fsck -fn "${loop}p2"
sudo losetup -d "$loop"
loop=''

cd "$pending"
gzip -1 "$name"
sha256sum "$name.gz" > "$name.gz.sha256"
mv "$name.gz" "$name.gz.sha256" "$images/"
cd "$images"
echo "Created SD image: $images/$name.gz"
