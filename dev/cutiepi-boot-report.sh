#!/bin/sh
set -eu

# Keep a short first-boot report on the FAT partition for offline diagnosis.
# Do not include network names, credentials, or the NetworkManager journal.
boot=/boot/firmware
mountpoint -q "$boot"
report="$boot/.cutiepi-boot-report.tmp"
{
    date -u
    uname -r
    printf '\nDevice model: '
    tr '\000' '\n' < /proc/device-tree/model
    printf '\nService status:\n'
    for service in NetworkManager ssh avahi-daemon lightdm; do
        printf '%s: ' "$service"
        systemctl is-active "$service" || :
    done
    printf '\nInterfaces:\n'
    nmcli -t -f DEVICE,TYPE,STATE device status || :
    printf '\nDisplay connectors:\n'
    for connector in /sys/class/drm/*/status; do
        [ -r "$connector" ] || continue
        printf '%s: ' "$(basename "$(dirname "$connector")")"
        cat "$connector"
    done
    printf '\nKernel hardware messages:\n'
    dmesg | grep -Ei 'brcmfmac|goodix|vc4|v3d|ili9881|nwe080|dsi' | tail -n 100 || :
} > "$report"
mv "$report" "$boot/cutiepi-boot-report.txt"
