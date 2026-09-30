#!/bin/bash
# Removes what install.sh installed and restores the backups it made.
# Usage: ./uninstall.sh   (as a normal user, uses sudo where needed)
set -uo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this script as a normal user, not as root." >&2
  exit 1
fi

CONF="/etc/gpu-passthrough.conf"
[ -f "$CONF" ] && . "$CONF"
GPU_VIDEO="${GPU_VIDEO:-0000:01:00.0}"

if [ -L "/sys/bus/pci/devices/$GPU_VIDEO/driver" ] \
   && [ "$(basename "$(readlink -f "/sys/bus/pci/devices/$GPU_VIDEO/driver")")" = "vfio-pci" ]; then
  echo "The GPU is currently bound to vfio-pci."
  echo "Run '~/gpu-switch.sh release' first to give it back to the host, then run this again."
  exit 1
fi

FILES=(
  /usr/local/bin/gpu-vfio-boot.sh
  /etc/systemd/system/gpu-vfio-boot.service
  /etc/systemd/system/cardwire-integrated-on-shutdown.service
  /etc/cardwire/cardwire.toml
  /etc/modprobe.d/nvidia.conf
  /etc/gpu-vfio-mode
  /etc/gpu-passthrough.conf
)

echo "This will remove or restore:"
printf '  %s\n' "${FILES[@]}" "$HOME/gpu-switch.sh"
read -rp "Continue? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo "Disabling services..."
sudo systemctl disable gpu-vfio-boot.service 2>/dev/null
sudo systemctl disable cardwire-integrated-on-shutdown.service 2>/dev/null

for f in "${FILES[@]}"; do
  # install.sh keeps numbered backups: file.~1~ is the original, if there was one.
  if [ -e "$f.~1~" ]; then
    sudo mv -f "$f.~1~" "$f"
    echo "  restored $f"
  elif [ -e "$f" ]; then
    sudo rm -f "$f"
    echo "  removed  $f"
  fi
  sudo rm -f "$f".~*~ 2>/dev/null
done
rm -f "$HOME/gpu-switch.sh"
echo "  removed  $HOME/gpu-switch.sh"

sudo systemctl daemon-reload
echo ""
echo "Done. If you rebuilt the initramfs during install, rebuild it again."
echo "cardwire and the nvidia driver are not touched. Reboot to finish."
