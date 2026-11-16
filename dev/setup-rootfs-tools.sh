#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  golang-go libglib2.0-dev libostree-dev systemd-container equivs zerofree
# Match the version used by the pinned UBports rootfs-builder Dockerfile.
go install github.com/go-debos/debos/cmd/debos@v1.1.5
