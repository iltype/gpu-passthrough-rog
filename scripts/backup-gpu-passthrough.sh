#!/bin/bash
# Saves the active system config into this repository.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

sudo cp /usr/local/bin/gpu-vfio-boot.sh "$REPO/scripts/" 2>/dev/null
sudo cp /etc/systemd/system/gpu-vfio-boot.service "$REPO/systemd/" 2>/dev/null
sudo cp /etc/systemd/system/cardwire-integrated-on-shutdown.service "$REPO/systemd/" 2>/dev/null
sudo cp /etc/cardwire/cardwire.toml "$REPO/config/" 2>/dev/null
sudo cp /etc/modprobe.d/nvidia.conf "$REPO/config/" 2>/dev/null
sudo cp /etc/gpu-vfio-mode "$REPO/config/" 2>/dev/null
sudo cp /etc/gpu-passthrough.conf "$REPO/config/" 2>/dev/null

sudo chown -R "$USER:$USER" "$REPO"
echo "Backup completato in: $REPO"
