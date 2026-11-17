#!/usr/bin/env bash
set -euo pipefail
test "$(uname -s)" = Darwin

project=$(cd "$(dirname "$0")/.." && pwd)
cd "$project/artifacts"
image=${1:-cutiepi-ut-mainline-dev.img.gz}
[[ "$image" =~ ^cutiepi-ut-[a-z0-9-]+\.img\.gz$ ]]
shasum -a 256 -c "$image.sha256"

# Match only the external, removable USB card identified for this project.
target=$(python3 - <<'PY'
import plistlib
import subprocess

def diskutil(*args):
    return plistlib.loads(subprocess.check_output(("/usr/sbin/diskutil", *args)))

matches = []
for identifier in diskutil("list", "-plist", "external", "physical")["WholeDisks"]:
    info = diskutil("info", "-plist", identifier)
    if (info["Size"] == 31914983424
        and info.get("WholeDisk") and not info.get("Internal")
        and info.get("RemovableMedia") and info.get("WritableMedia")
        and info.get("BusProtocol") == "USB"):
        matches.append(identifier)
if len(matches) != 1:
    raise SystemExit("未能唯一识别 31.9 GB microSD 卡。请检查读卡器和磁盘。")
print(matches[0])
PY
)
[[ "$target" =~ ^disk[0-9]+$ ]]
diskutil list "/dev/$target"
printf '将覆盖上面列出的 31.9 GB microSD 卡。输入 %s 确认：' "$target"
read -r confirmation
test "$confirmation" = "$target"
sudo -v

# Recheck immediately before unmounting and opening the raw device.
info=$(diskutil info -plist "/dev/$target")
property() { printf '%s' "$info" | plutil -extract "$1" raw -; }
test "$(property Size)" = 31914983424
test "$(property RemovableMedia)" = true
test "$(property WritableMedia)" = true
test "$(property WholeDisk)" = true
test "$(property Internal)" = false
test "$(property BusProtocol)" = USB

diskutil unmountDisk "/dev/$target"
gzip -dc "$image" | sudo -n /bin/dd of="/dev/r$target" bs=4m iflag=fullblock status=progress
sync
diskutil eject "/dev/$target"
echo '写入完成。请把卡插入 CutiePi 并开机。'
