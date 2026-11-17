#!/usr/bin/env bash
set -euo pipefail

root=$1
boot="$root/boot/firmware"
dev=$(dirname "$(realpath "$0")")

test -s "$boot/overlays/i2c5.dtbo"
dtc -@ -I dts -O dtb -o "$boot/overlays/cutiepi-mpu6050.dtbo" "$dev/cutiepi-mpu6050-overlay.dts"
if ! grep -Fxq 'dtoverlay=cutiepi-mpu6050' "$boot/config.txt"; then
    cat >> "$boot/config.txt" <<'EOF'

[cm4]
dtoverlay=i2c5,pins_10_11
dtoverlay=cutiepi-mpu6050
[all]
EOF
fi

if ! chroot "$root" dpkg-query -W -f='${db:Status-Abbrev}' iio-sensor-proxy 2>/dev/null | grep -q '^ii '; then
    # The image resolver points into /run and is only usable after boot.
    # Copy the build VM's resolver into the image for this install.
    (
        resolver="$root/etc/resolv.conf"
        saved=$(mktemp -d "$root/etc/.cutiepi-resolver.XXXXXX")
        if [[ -e "$resolver" || -L "$resolver" ]]; then
            mv "$resolver" "$saved/resolv.conf"
        fi
        restore_resolver() {
            rm -f "$resolver"
            if [[ -e "$saved/resolv.conf" || -L "$saved/resolv.conf" ]]; then
                mv "$saved/resolv.conf" "$resolver"
            fi
            rmdir "$saved"
        }
        trap restore_resolver EXIT
        install -m 644 /etc/resolv.conf "$resolver"
        systemd-nspawn -q --register=no --resolv-conf=off --timezone=off --console=pipe -D "$root" \
            /bin/sh -ec 'apt-get update -o APT::Update::Error-Mode=any &&
                         DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends iio-sensor-proxy &&
                         apt-get clean'
    )
fi

install -D -m 644 "$dev/cutiepi-imu.rules" "$root/etc/udev/rules.d/81-cutiepi-imu.rules"
install -D -m 644 "$dev/cutiepi-sensorfw.conf" "$root/etc/sensorfw/sensord.conf.d/60-cutiepi.conf"
qt_config="$root/etc/xdg/QtProject/Sensors.conf"
grep -Eq '^QOrientationSensor[[:space:]]*=' "$qt_config"
sed -i -E 's/^QOrientationSensor[[:space:]]*=.*/QOrientationSensor=iio-sensor-proxy.orientationsensor/' "$qt_config"

grep -Fxq 'QGyroscope=sensorfw.gyroscope' "$qt_config"
test -s "$root/usr/lib/aarch64-linux-gnu/sensord-qt5/libiiosensorsadaptor-qt5.so"
test -s "$root/usr/lib/aarch64-linux-gnu/qt5/plugins/sensors/libqtsensors_iio-sensor-proxy.so"
