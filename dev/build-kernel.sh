#!/usr/bin/env bash
# Build a stock Raspberry Pi CM4 baseline, not yet a complete UT kernel.
set -euo pipefail
test "$(uname -s)" = Linux
test "$(uname -m)" = aarch64
revision=ab4372076bb840600e522ae776887ae2bc488fa6
root="$HOME/cutiepi"
src="$root/src/linux-rpi-6.12"
out="$root/build/linux-rpi-6.12"
stage="$root/images/kernel-$revision"
mkdir -p "$src" "$out" "$stage"
if [ ! -d "$src/.git" ]; then
  git -C "$src" init
  git -C "$src" remote add origin https://github.com/raspberrypi/linux.git
fi
if ! git -C "$src" cat-file -e "$revision^{commit}" 2>/dev/null; then
  git -C "$src" fetch --depth=1 origin "$revision"
fi
git -C "$src" checkout --detach "$revision"
test "$(git -C "$src" rev-parse HEAD)" = "$revision"
if [ -n "$(git -C "$src" status --porcelain)" ]; then
  echo 'Kernel source has local changes; refusing to build.' >&2
  exit 1
fi
make -C "$src" O="$out" ARCH=arm64 bcm2711_defconfig
make -C "$src" O="$out" ARCH=arm64 -j6 Image modules dtbs
make -C "$src" O="$out" ARCH=arm64 INSTALL_MOD_PATH="$stage" modules_install
install -m 644 "$out/arch/arm64/boot/Image" "$stage/kernel8.img"
mkdir -p "$stage/boot/overlays"
install -m 644 "$out/arch/arm64/boot/dts/broadcom/bcm2711-rpi-cm4.dtb" "$stage/boot/"
install -m 644 "$out/arch/arm64/boot/dts/overlays/"*.dtbo "$stage/boot/overlays/"
install -m 644 "$out/arch/arm64/boot/dts/overlays/overlay_map.dtb" "$stage/boot/overlays/"
install -m 644 "$out/.config" "$stage/kernel.config"
printf '%s\n' "$revision" > "$stage/source-revision.txt"
make -s -C "$src" O="$out" ARCH=arm64 kernelrelease > "$stage/kernelrelease.txt"
release=$(cat "$stage/kernelrelease.txt")
rm -f "$stage/lib/modules/$release/build" "$stage/lib/modules/$release/source"
install -m 644 "$src/COPYING" "$stage/COPYING"
printf '%s\n' "https://github.com/raspberrypi/linux/tree/$revision" > "$stage/source-url.txt"
cd "$stage"
sha256sum kernel8.img boot/bcm2711-rpi-cm4.dtb boot/overlays/cutiepi-panel.dtbo > SHA256SUMS
echo "Kernel baseline staged at: $stage"
