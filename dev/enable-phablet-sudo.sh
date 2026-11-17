#!/usr/bin/env bash
# Explicit opt-in for the development device; not enabled in distributed images.
set -euo pipefail
[[ $(id -u) == 0 ]]
getent passwd phablet >/dev/null
pending=$(mktemp /etc/sudoers.d/.cutiepi-phablet.XXXXXX)
trap 'rm -f "$pending"' EXIT
printf 'phablet ALL=(ALL:ALL) NOPASSWD: ALL\n' > "$pending"
chmod 440 "$pending"
visudo -cf "$pending"
install -o root -g root -m 440 "$pending" /etc/sudoers.d/99-cutiepi-phablet
visudo -c
