#!/usr/bin/env bash
# Install the CutiePi session override in a staged image or in phablet's home.
set -euo pipefail

if [[ $# -eq 1 ]]; then
  root=$(realpath "$1")
  wrapper="$root/usr/local/bin/cutiepi-lomiri-wrapper"
  upstream="$root/usr/libexec/lomiri-systemd-wrapper"
  units="$root/etc/systemd/user"
  exec_path=/usr/local/bin/cutiepi-lomiri-wrapper
else
  wrapper="$HOME/.local/bin/cutiepi-lomiri-wrapper"
  upstream=/usr/libexec/lomiri-systemd-wrapper
  units="$HOME/.config/systemd/user"
  exec_path='%h/.local/bin/cutiepi-lomiri-wrapper'
fi

keyboard="$units/maliit-server.service.d"
mkdir -p "$keyboard"
cat > "$keyboard/70-cutiepi-panel.conf" <<'EOF'
[Service]
Environment=QT_WAYLAND_SHELL_INTEGRATION=wl-shell
EOF

greeter="$units/lomiri-full-greeter.service.d"
mkdir -p "$(dirname "$wrapper")" "$greeter"

# Keep the upstream Wayland and logind setup. Mir 2 rejects the old Mir
# server environment options and has no legacy Mir socket to initialize.
# Publish the native EGL selection to D-Bus and systemd as well: applications
# and Maliit are separate units and do not inherit the compositor environment.
sed -e '/^export MIR_SERVER_/d' \
    -e '/^rm -f .*MIR_SERVER_FILE/d' \
    -e '/^dbus-update-activation-environment --systemd MIR_SOCKET=/d' \
    -e '/^export WAYLAND_DISPLAY=/a\
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json\
export GLIBC_TUNABLES=glibc.rtld.optional_static_tls=8192\
dbus-update-activation-environment --systemd __EGL_VENDOR_LIBRARY_FILENAMES GLIBC_TUNABLES' \
    "$upstream" > "$wrapper"
chmod 755 "$wrapper"

cat > "$greeter/60-cutiepi.conf" <<EOF
[Service]
Environment=__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
Environment=GLIBC_TUNABLES=glibc.rtld.optional_static_tls=8192
Environment=DEVICEINFO_DEVICE_NAME=cutiepi
ExecStart=
ExecStart=$exec_path --mode=full-greeter
EOF

if [[ $# -eq 0 ]]; then
  session="$units/ubuntu-touch-session.target.d"
  mkdir -p "$session"
  cat > "$session/60-cutiepi.conf" <<'EOF'
[Unit]
Wants=lomiri-full-greeter.service
EOF
  exit
fi

# Native input-method windows need a direct path into the shell on Mir 2.
python3 "$(dirname "$0")/patch-native-keyboard.py" "$root"

# Seed completed tutorials before AccountsService loads the new image.
python3 "$(dirname "$0")/complete-gesture-tutorial.py" "$root"

# Run the unencrypted session target from LightDM itself. The target brings
# up the shell and keeps both the compositor and the session alive.
session_source="$root/usr/bin/ubuntu-touch-session"
session_command='    exec /usr/share/ubuntu-touch-session/run-systemd-session '
grep -Fq "$session_command" "$session_source"
sed -e '1a export DEVICEINFO_DEVICE_NAME=cutiepi' \
    -e "s|^${session_command}.*|${session_command}ubuntu-touch-session-unencrypted.target|" \
    "$session_source" > "$root/usr/local/bin/cutiepi-session"
chmod 755 "$root/usr/local/bin/cutiepi-session"

session_desktop="$root/usr/share/lightdm/sessions/cutiepi.desktop"
sed -e 's|^Exec=.*|Exec=/usr/local/bin/cutiepi-session|' \
    -e 's|^TryExec=.*|TryExec=/usr/local/bin/cutiepi-session|' \
    "$root/usr/share/lightdm/sessions/ubuntu-touch.desktop" > "$session_desktop"

mkdir -p "$root/etc/lightdm/lightdm.conf.d" "$root/etc/systemd/system/repowerd.service.d"
cat > "$root/etc/lightdm/lightdm.conf.d/99-cutiepi.conf" <<'EOF'
[Seat:*]
user-session=cutiepi
autologin-session=cutiepi
EOF
cat > "$root/etc/systemd/system/repowerd.service.d/60-cutiepi.conf" <<'EOF'
[Service]
Environment=DEVICEINFO_DEVICE_NAME=cutiepi
EOF
