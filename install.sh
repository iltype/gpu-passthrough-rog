#!/bin/bash
# Installs the GPU passthrough setup and enables the services.
# Usage: ./install.sh          check the system, then install
#        ./install.sh --check  only check if the system is compatible
# Works with limine, GRUB, systemd-boot and other bootloaders: it detects
# the initramfs tool and the bootloader, and explains what is left to do.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this script as a normal user, not as root." >&2
  exit 1
fi

# --- Compatibility check ----------------------------------------------------
if [ "${1:-}" = "--check" ]; then
  exec bash "$REPO/scripts/check-compat.sh"
fi

if ! bash "$REPO/scripts/check-compat.sh"; then
  echo ""
  read -rp "This system does not look compatible. Install anyway? [y/N] " force
  [[ "$force" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi
echo ""
read -rp "Continue with the installation? [Y/n] " go
[[ "$go" =~ ^[Nn]$ ]] && { echo "Aborted."; exit 0; }

# Copy with a numbered backup if the destination already exists.
inst() {
  local mode="$1" src="$2" dst="$3"
  sudo install -D -m "$mode" --backup=numbered "$REPO/$src" "$dst"
  echo "  $src -> $dst"
}

echo "Installing scripts..."
inst 755 scripts/gpu-vfio-boot.sh /usr/local/bin/gpu-vfio-boot.sh
install -m 755 "$REPO/scripts/gpu-switch.sh" "$HOME/gpu-switch.sh"
echo "  scripts/gpu-switch.sh -> $HOME/gpu-switch.sh"

echo "Installing systemd units..."
inst 644 systemd/gpu-vfio-boot.service /etc/systemd/system/gpu-vfio-boot.service
inst 644 systemd/cardwire-integrated-on-shutdown.service /etc/systemd/system/cardwire-integrated-on-shutdown.service

echo "Installing config..."
inst 644 config/cardwire.toml /etc/cardwire/cardwire.toml
inst 644 config/nvidia.conf /etc/modprobe.d/nvidia.conf

# GPU addresses: detected on this machine, never overwrite an existing file.
if [ ! -f /etc/gpu-passthrough.conf ]; then
  if DETECTED="$(bash "$REPO/scripts/check-compat.sh" --print-config)"; then
    { echo "# PCI addresses of the NVIDIA GPU (detected by install.sh)."; echo "$DETECTED"; } \
      | sudo tee /etc/gpu-passthrough.conf >/dev/null
    echo "  detected GPU addresses -> /etc/gpu-passthrough.conf"
  else
    sudo install -D -m 644 "$REPO/config/gpu-passthrough.conf" /etc/gpu-passthrough.conf
    echo "  GPU not detected: default addresses written, edit /etc/gpu-passthrough.conf"
  fi
else
  echo "  /etc/gpu-passthrough.conf exists, left untouched"
fi

# Never overwrite an existing state file.
if [ ! -f /etc/gpu-vfio-mode ]; then
  sudo install -D -m 644 "$REPO/config/gpu-vfio-mode" /etc/gpu-vfio-mode
  echo "  config/gpu-vfio-mode -> /etc/gpu-vfio-mode"
else
  echo "  /etc/gpu-vfio-mode exists, left untouched"
fi

echo "Enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable gpu-vfio-boot.service
sudo systemctl enable cardwire-integrated-on-shutdown.service

# --- Bootloader detection -------------------------------------------------
BOOTLOADER="unknown"
if command -v limine-mkinitcpio >/dev/null 2>&1 || [ -f /boot/limine.conf ] \
   || [ -f /boot/limine/limine.conf ] || [ -f /boot/EFI/limine/limine.conf ]; then
  BOOTLOADER="limine"
elif [ -f /etc/default/grub ] || command -v grub-mkconfig >/dev/null 2>&1 \
     || command -v grub2-mkconfig >/dev/null 2>&1; then
  BOOTLOADER="grub"
elif [ -d /boot/loader ] || [ -d /efi/loader ] || [ -d /boot/efi/loader ]; then
  BOOTLOADER="systemd-boot"
fi
echo "Detected bootloader: $BOOTLOADER"

# --- Initramfs --------------------------------------------------------------
REBUILD=""
if command -v limine-mkinitcpio >/dev/null 2>&1; then
  REBUILD="sudo limine-mkinitcpio -P"
elif command -v mkinitcpio >/dev/null 2>&1; then
  REBUILD="sudo mkinitcpio -P"
elif command -v dracut >/dev/null 2>&1; then
  REBUILD="sudo dracut --force --regenerate-all"
elif command -v update-initramfs >/dev/null 2>&1; then
  REBUILD="sudo update-initramfs -u -k all"
fi

if [ -n "$REBUILD" ]; then
  echo "The nvidia modprobe options may be embedded in the initramfs."
  read -rp "Rebuild it now with '$REBUILD'? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    $REBUILD
  else
    echo "Skipped. Run it later: $REBUILD"
  fi
else
  echo "No known initramfs tool found: rebuild your initramfs manually if needed."
fi

# --- IOMMU ------------------------------------------------------------------
if [ -d /sys/kernel/iommu_groups ] && [ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
  echo "IOMMU is active (groups found)."
else
  if grep -qi amd /proc/cpuinfo; then PARAM="amd_iommu=on iommu=pt"; else PARAM="intel_iommu=on iommu=pt"; fi
  echo "IOMMU does not look active. Add this to the kernel command line: $PARAM"
  case "$BOOTLOADER" in
    limine)       echo "  limine: add it to the cmdline in limine.conf (or KERNEL_CMDLINE in /etc/default/limine), then rebuild." ;;
    grub)         echo "  GRUB: add it to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub, then run grub-mkconfig -o /boot/grub/grub.cfg (or grub2-mkconfig)." ;;
    systemd-boot) echo "  systemd-boot: add it to the 'options' line of your entry in loader/entries/*.conf." ;;
    *)            echo "  Add it to the kernel command line of your bootloader." ;;
  esac
fi

cat << 'MSG'

Done. Next steps:
  1. Reboot.
  2. Switch the GPU to passthrough: ~/gpu-switch.sh start (it reboots by itself)
  3. To give the GPU back to the host: ~/gpu-switch.sh release
MSG
