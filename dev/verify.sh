#!/usr/bin/env bash
# Exercise the tools needed by a native ARM64 kernel/image build.
set -euo pipefail
test "$(uname -s)" = Linux
test "$(dpkg --print-architecture)" = arm64
work=$(mktemp -d "$HOME/cutiepi/build/env-check.XXXXXX")
cleanup() {
  if mountpoint -q "$work/mnt"; then sudo umount "$work/mnt"; fi
  rm -rf "$work"
}
trap cleanup EXIT
printf '#include <stdio.h>\nint main(void) { puts("ARM64 compiler OK"); return 0; }\n' > "$work/hello.c"
cc -Wall -Wextra -Werror "$work/hello.c" -o "$work/hello"
file "$work/hello"
"$work/hello"
printf '/dts-v1/;\n/ { compatible = "cutiepi,build-host-check"; };\n' > "$work/check.dts"
dtc -I dts -O dtb -o "$work/check.dtb" "$work/check.dts"
dtc -I dtb -O dts "$work/check.dtb" > /dev/null
truncate -s 32M "$work/check.ext4"
mkfs.ext4 -q -F "$work/check.ext4"
mkdir "$work/mnt"
sudo mount -o loop "$work/check.ext4" "$work/mnt"
printf 'image filesystem OK\n' | sudo tee "$work/mnt/check.txt"
sudo umount "$work/mnt"
e2fsck -fn "$work/check.ext4"
printf '\nEnvironment checks passed.\n'
uname -a
cat /etc/os-release
df -h "$HOME/cutiepi"
