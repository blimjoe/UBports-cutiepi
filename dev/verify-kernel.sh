#!/usr/bin/env bash
# Offline checks only; successful results do not establish hardware support.
set -euo pipefail
stage=${1:?Usage: verify-kernel.sh KERNEL_STAGE_DIRECTORY}
stage=$(realpath "$stage")
release=$(cat "$stage/kernelrelease.txt")
cd "$stage"
sha256sum -c SHA256SUMS
file kernel8.img
for module in vc4 v3d panel_ilitek_ili9881c goodix_ts pwm_bl inv_mpu6050_i2c brcmfmac; do
  vermagic=$(modinfo -b "$stage" -k "$release" -F vermagic "$module")
  test "${vermagic%% *}" = "$release"
  printf '%s: %s\n' "$module" "$vermagic"
done
dtmerge=${DTMERGE:-$HOME/cutiepi/build/dtmerge/dtmerge}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Raspberry Pi overlays use __dormant__ fragments, which generic fdtoverlay
# does not preprocess. Use the Pi tool and the BCM2711 mapping in overlay_map.
mapped=$(fdtget -t s boot/overlays/overlay_map.dtb /vc4-kms-v3d bcm2711)
test "$mapped" = vc4-kms-v3d-pi4
"$dtmerge" boot/bcm2711-rpi-cm4.dtb "$work/1.dtb" "boot/overlays/$mapped.dtbo"
"$dtmerge" "$work/1.dtb" "$work/2.dtb" boot/overlays/cutiepi-panel.dtbo
"$dtmerge" "$work/2.dtb" "$work/3.dtb" boot/overlays/uart1.dtbo
test "$(fdtget -t s "$work/3.dtb" / compatible | cut -d ' ' -f 1)" = raspberrypi,4-compute-module
echo "CM4 + KMS + CutiePi panel/touch + UART1 overlays applied successfully."
echo "Kernel release: $release"
echo "Offline checks passed; boot firmware and rootfs are not included."
