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

greeter="$units/lomiri-full-greeter.service.d"
session="$units/ubuntu-touch-session.target.d"
mkdir -p "$(dirname "$wrapper")" "$greeter" "$session"

# Keep the upstream Wayland and logind setup. Mir 2 rejects the old Mir
# server environment options and has no legacy Mir socket to initialize.
sed -e '/^export MIR_SERVER_/d' \
    -e '/^rm -f .*MIR_SERVER_FILE/d' \
    -e '/^dbus-update-activation-environment --systemd MIR_SOCKET=/d' \
    "$upstream" > "$wrapper"
chmod 755 "$wrapper"

cat > "$greeter/60-cutiepi.conf" <<EOF
[Service]
Environment=__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
Environment=GLIBC_TUNABLES=glibc.rtld.optional_static_tls=8192
ExecStart=
ExecStart=$exec_path --mode=full-greeter
EOF

cat > "$session/60-cutiepi.conf" <<'EOF'
[Unit]
Wants=lomiri-full-greeter.service
EOF
