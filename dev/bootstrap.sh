#!/usr/bin/env bash
set -euo pipefail
test "$(uname -s)" = Linux
test "$(dpkg --print-architecture)" = arm64
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git ca-certificates curl wget rsync file jq ripgrep \
  bc bison flex libssl-dev libelf-dev libncurses-dev dwarves \
  device-tree-compiler libfdt-dev kmod cpio xz-utils zstd unzip zip \
  python3 python3-venv python3-yaml pkg-config cmake ninja-build \
  debootstrap dosfstools e2fsprogs parted gdisk qemu-utils \
  squashfs-tools fakeroot debhelper devscripts
mkdir -p "$HOME/cutiepi/src" "$HOME/cutiepi/build" "$HOME/cutiepi/images"
