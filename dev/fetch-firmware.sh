#!/usr/bin/env bash
set -euo pipefail
revision=896fc67d292bfde6d9889d4c585bb685758dc1ad
out="$HOME/cutiepi/src/rpi-firmware-$revision"
mkdir -p "$out"
for name in start4.elf fixup4.dat LICENCE.broadcom; do
  if [ ! -s "$out/$name" ]; then
    curl -fL --retry 3 "https://raw.githubusercontent.com/raspberrypi/firmware/$revision/boot/$name" -o "$out/$name"
  fi
done
printf '%s\n' "$revision" > "$out/source-revision.txt"
cd "$out"
sha256sum start4.elf fixup4.dat LICENCE.broadcom > SHA256SUMS
