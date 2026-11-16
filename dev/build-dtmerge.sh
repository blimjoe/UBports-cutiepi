#!/usr/bin/env bash
set -euo pipefail
revision=eac8944a8f30a8365ea57e4d20d268baadd0eb67
src="$HOME/cutiepi/src/raspberrypi-utils"
if [ ! -d "$src/.git" ]; then
  mkdir -p "$src"
  git -C "$src" init
  git -C "$src" remote add origin https://github.com/raspberrypi/utils.git
fi
if ! git -C "$src" cat-file -e "$revision^{commit}" 2>/dev/null; then
  git -C "$src" fetch --depth=1 origin "$revision"
fi
git -C "$src" checkout --detach "$revision"
test -z "$(git -C "$src" status --porcelain)"
cmake -S "$src/dtmerge" -B "$HOME/cutiepi/build/dtmerge"
cmake --build "$HOME/cutiepi/build/dtmerge" -j2
