#!/bin/bash
# GPU passthrough manager: check, install, uninstall and day-to-day actions
# in one script.
#
# Usage: ./install.sh              interactive menu
#        ./install.sh check        check if this computer is compatible (also: --check)
#        ./install.sh install      check, then install
#        ./install.sh uninstall    remove everything and restore backups
#        ./install.sh iommu        list IOMMU groups
#        ./install.sh status       show which driver the GPU is using
#        ./install.sh start        switch the GPU to passthrough (reboots)
#        ./install.sh release      give the GPU back to the host
#        ./install.sh backup       save the active system config into this repo
#
# Run as a normal user: sudo is used where needed.
set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CONF="/etc/gpu-passthrough.conf"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this script as a normal user, not as root." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# GPU detection (sets PCI, GPU_VIDEO, GPU_AUDIO, NV_VIDEO_LINE)
# ---------------------------------------------------------------------------
detect_gpu() {
  PCI="$(lspci -D -nn 2>/dev/null)"
  NV_VIDEO_LINE="$(echo "$PCI" | grep -E '\[(0300|0302)\]' | grep -i '\[10de:' | head -1 || true)"
  GPU_VIDEO="${NV_VIDEO_LINE%% *}"
  GPU_AUDIO=""
  if [ -n "$GPU_VIDEO" ]; then
    local prefix audio_line
    prefix="${GPU_VIDEO%.*}"
    audio_line="$(echo "$PCI" | grep "^$prefix\." | grep '\[0403\]' | head -1 || true)"
    GPU_AUDIO="${audio_line%% *}"
  fi
}

# ---------------------------------------------------------------------------
# 1. Check compatibility. Returns 0 if compatible, 1 if not. Changes nothing.
# ---------------------------------------------------------------------------
check_compat() {
  local fails=0 warns=0 cpu name host_line host_name p others addr class d
  ok()   { echo "  [ OK ]  $*"; }
  warn() { echo "  [WARN]  $*"; warns=$((warns + 1)); }
  fail() { echo "  [FAIL]  $*"; fails=$((fails + 1)); }
  info() { echo "  [INFO]  $*"; }

  echo "GPU passthrough compatibility check"
  echo ""

  if [ -d /run/systemd/system ]; then ok "systemd is running"; else fail "systemd is required (the boot service is a systemd unit)"; fi

  if command -v lspci >/dev/null 2>&1; then
    ok "lspci found"
  else
    fail "lspci not found (install pciutils)"
    echo ""; echo "Result: NOT compatible ($fails problem(s))."
    return 1
  fi

  if grep -qi genuineintel /proc/cpuinfo; then
    cpu="intel"; info "CPU vendor: Intel (IOMMU parameter: intel_iommu=on)"
  elif grep -qi authenticamd /proc/cpuinfo; then
    cpu="amd"; info "CPU vendor: AMD (IOMMU parameter: amd_iommu=on, usually already on)"
  else
    cpu="unknown"; warn "unknown CPU vendor"
  fi

  detect_gpu
  if [ -n "$GPU_VIDEO" ]; then
    name="$(echo "$NV_VIDEO_LINE" | sed -e 's/^[^ ]* //' -e 's/^[^:]*: //' -e 's/ (rev.*//')"
    ok "NVIDIA GPU found: $name"
    info "video function: $GPU_VIDEO"
    if [ -n "$GPU_AUDIO" ]; then info "audio function: $GPU_AUDIO"; else warn "no HDMI audio function found next to the GPU (the scripts expect one)"; fi
  else
    fail "no NVIDIA GPU found (this setup only supports an NVIDIA dGPU)"
  fi

  host_line="$(echo "$PCI" | grep -E '\[(0300|0302|0380)\]' | grep -vi '\[10de:' | head -1 || true)"
  if [ -n "$host_line" ]; then
    host_name="$(echo "$host_line" | sed -e 's/^[^ ]* //' -e 's/^[^:]*: //' -e 's/ (rev.*//')"
    ok "another GPU is available for the host: $host_name"
  else
    fail "no integrated GPU found: the host would be left without a display"
  fi

  if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    info "battery found: this looks like a laptop"
  else
    info "no battery found: this looks like a desktop"
  fi

  if [ -d /sys/kernel/iommu_groups ] && [ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
    ok "IOMMU is active"
    if [ -n "$GPU_VIDEO" ] && [ -e "/sys/bus/pci/devices/$GPU_VIDEO/iommu_group" ]; then
      others=""
      for d in /sys/bus/pci/devices/$GPU_VIDEO/iommu_group/devices/*; do
        addr="$(basename "$d")"
        [ "$addr" = "$GPU_VIDEO" ] && continue
        [ -n "$GPU_AUDIO" ] && [ "$addr" = "$GPU_AUDIO" ] && continue
        class="$(cat "/sys/bus/pci/devices/$addr/class" 2>/dev/null || echo 0)"
        case "$class" in 0x0604*|0x0600*) continue ;; esac   # bridges are fine
        others="$others $addr"
      done
      if [ -z "$others" ]; then
        ok "the GPU is isolated in its IOMMU group"
      else
        warn "the GPU shares its IOMMU group with:$others (see './install.sh iommu')"
      fi
    fi
  else
    if [ "$cpu" = "amd" ]; then p="amd_iommu=on iommu=pt"; else p="intel_iommu=on iommu=pt"; fi
    warn "IOMMU is not active: add '$p' to the kernel command line and enable VT-d/AMD-Vi in the BIOS"
  fi

  if command -v cardwire >/dev/null 2>&1; then ok "cardwire is installed"; else warn "cardwire is not installed (AUR: cardwire): the scripts need it"; fi

  if [ -n "$GPU_VIDEO" ] && [ -L "/sys/bus/pci/devices/$GPU_VIDEO/driver" ] \
     && [ "$(basename "$(readlink -f "/sys/bus/pci/devices/$GPU_VIDEO/driver")")" = "vfio-pci" ]; then
    info "the GPU is already bound to vfio-pci"
  elif command -v nvidia-smi >/dev/null 2>&1 || lsmod | grep -q '^nvidia '; then
    ok "nvidia driver found"
  else
    warn "nvidia driver not loaded"
  fi

  if command -v limine-mkinitcpio >/dev/null 2>&1; then info "bootloader/initramfs: limine (limine-mkinitcpio)"
  elif command -v mkinitcpio >/dev/null 2>&1; then info "initramfs tool: mkinitcpio"
  elif command -v dracut >/dev/null 2>&1; then info "initramfs tool: dracut"
  elif command -v update-initramfs >/dev/null 2>&1; then info "initramfs tool: update-initramfs"
  else warn "no known initramfs tool found"; fi

  echo ""
  if [ "$fails" -gt 0 ]; then
    echo "Result: NOT compatible ($fails problem(s), $warns warning(s))."
    return 1
  fi
  if [ "$warns" -gt 0 ]; then
    echo "Result: compatible, with $warns warning(s) to look at."
  else
    echo "Result: compatible."
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 2. Install
# ---------------------------------------------------------------------------
do_install() {
  local force go
  if ! check_compat; then
    echo ""
    read -rp "This system does not look compatible. Install anyway? [y/N] " force
    [[ "$force" =~ ^[Yy]$ ]] || { echo "Aborted."; return 1; }
  fi
  echo ""
  read -rp "Continue with the installation? [Y/n] " go
  if [[ "$go" =~ ^[Nn]$ ]]; then echo "Aborted."; return 0; fi

  (
    set -euo pipefail
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
    if [ ! -f "$CONF" ]; then
      detect_gpu
      if [ -n "${GPU_VIDEO:-}" ]; then
        { echo "# PCI addresses of the NVIDIA GPU (detected by install.sh)."
          echo "GPU_VIDEO=\"$GPU_VIDEO\""
          echo "GPU_AUDIO=\"${GPU_AUDIO:-}\""; } | sudo tee "$CONF" >/dev/null
        echo "  detected GPU addresses -> $CONF"
      else
        sudo install -D -m 644 "$REPO/config/gpu-passthrough.conf" "$CONF"
        echo "  GPU not detected: default addresses written, edit $CONF"
      fi
    else
      echo "  $CONF exists, left untouched"
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
  ) || { echo "Installation failed."; return 1; }

  # --- Bootloader detection ---
  local bootloader="unknown" rebuild="" ans param
  if command -v limine-mkinitcpio >/dev/null 2>&1 || [ -f /boot/limine.conf ] \
     || [ -f /boot/limine/limine.conf ] || [ -f /boot/EFI/limine/limine.conf ]; then
    bootloader="limine"
  elif [ -f /etc/default/grub ] || command -v grub-mkconfig >/dev/null 2>&1 \
       || command -v grub2-mkconfig >/dev/null 2>&1; then
    bootloader="grub"
  elif [ -d /boot/loader ] || [ -d /efi/loader ] || [ -d /boot/efi/loader ]; then
    bootloader="systemd-boot"
  fi
  echo "Detected bootloader: $bootloader"

  # --- Initramfs ---
  if command -v limine-mkinitcpio >/dev/null 2>&1; then
    rebuild="sudo limine-mkinitcpio -P"
  elif command -v mkinitcpio >/dev/null 2>&1; then
    rebuild="sudo mkinitcpio -P"
  elif command -v dracut >/dev/null 2>&1; then
    rebuild="sudo dracut --force --regenerate-all"
  elif command -v update-initramfs >/dev/null 2>&1; then
    rebuild="sudo update-initramfs -u -k all"
  fi
  if [ -n "$rebuild" ]; then
    echo "The nvidia modprobe options may be embedded in the initramfs."
    read -rp "Rebuild it now with '$rebuild'? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then $rebuild; else echo "Skipped. Run it later: $rebuild"; fi
  else
    echo "No known initramfs tool found: rebuild your initramfs manually if needed."
  fi

  # --- IOMMU ---
  if [ -d /sys/kernel/iommu_groups ] && [ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
    echo "IOMMU is active (groups found)."
  else
    if grep -qi amd /proc/cpuinfo; then param="amd_iommu=on iommu=pt"; else param="intel_iommu=on iommu=pt"; fi
    echo "IOMMU does not look active. Add this to the kernel command line: $param"
    case "$bootloader" in
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
  return 0
}

# ---------------------------------------------------------------------------
# 3. Uninstall
# ---------------------------------------------------------------------------
do_uninstall() {
  local video ans f
  local -a files=(
    /usr/local/bin/gpu-vfio-boot.sh
    /etc/systemd/system/gpu-vfio-boot.service
    /etc/systemd/system/cardwire-integrated-on-shutdown.service
    /etc/cardwire/cardwire.toml
    /etc/modprobe.d/nvidia.conf
    /etc/gpu-vfio-mode
    "$CONF"
  )

  video="0000:01:00.0"
  # shellcheck disable=SC1090
  if [ -f "$CONF" ]; then video="$( . "$CONF"; echo "${GPU_VIDEO:-0000:01:00.0}" )"; fi

  if [ -L "/sys/bus/pci/devices/$video/driver" ] \
     && [ "$(basename "$(readlink -f "/sys/bus/pci/devices/$video/driver")")" = "vfio-pci" ]; then
    echo "The GPU is currently bound to vfio-pci."
    echo "Run '$0 release' first to give it back to the host, then uninstall."
    return 1
  fi

  echo "This will remove or restore:"
  printf '  %s\n' "${files[@]}" "$HOME/gpu-switch.sh"
  read -rp "Continue? [y/N] " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then echo "Aborted."; return 0; fi

  echo "Disabling services..."
  sudo systemctl disable gpu-vfio-boot.service 2>/dev/null
  sudo systemctl disable cardwire-integrated-on-shutdown.service 2>/dev/null

  for f in "${files[@]}"; do
    # The installer keeps numbered backups: file.~1~ is the original, if there was one.
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
  return 0
}

# ---------------------------------------------------------------------------
# IOMMU groups
# ---------------------------------------------------------------------------
do_iommu() {
  local g devs mark d
  if [ ! -d /sys/kernel/iommu_groups ] || [ -z "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
    echo "IOMMU is not active. Enable VT-d / AMD-Vi in the BIOS and add"
    echo "intel_iommu=on iommu=pt (or amd_iommu=on iommu=pt) to the kernel command line."
    return 1
  fi
  if ! command -v lspci >/dev/null 2>&1; then
    echo "lspci not found (install pciutils)." >&2
    return 1
  fi
  echo "The NVIDIA GPU (and its audio function) should be alone in its group,"
  echo "except for PCI bridges, to be passed through cleanly."
  echo ""
  for g in $(ls /sys/kernel/iommu_groups | sort -n); do
    devs="/sys/kernel/iommu_groups/$g/devices"
    mark=""
    for d in "$devs"/*; do
      if lspci -nns "$(basename "$d")" | grep -qi '\[10de:'; then mark="   <-- NVIDIA"; fi
    done
    echo "IOMMU group $g$mark"
    for d in "$devs"/*; do
      echo "    $(lspci -nns "$(basename "$d")")"
    done
  done
  return 0
}

# ---------------------------------------------------------------------------
# GPU switch (delegates to gpu-switch.sh)
# ---------------------------------------------------------------------------
switch() {
  if [ -x "$HOME/gpu-switch.sh" ]; then
    "$HOME/gpu-switch.sh" "$1"
  else
    "$REPO/scripts/gpu-switch.sh" "$1"
  fi
}

# ---------------------------------------------------------------------------
# Backup: copy the active system config into this repository
# ---------------------------------------------------------------------------
do_backup() {
  sudo cp /usr/local/bin/gpu-vfio-boot.sh "$REPO/scripts/" 2>/dev/null
  sudo cp /etc/systemd/system/gpu-vfio-boot.service "$REPO/systemd/" 2>/dev/null
  sudo cp /etc/systemd/system/cardwire-integrated-on-shutdown.service "$REPO/systemd/" 2>/dev/null
  sudo cp /etc/cardwire/cardwire.toml "$REPO/config/" 2>/dev/null
  sudo cp /etc/modprobe.d/nvidia.conf "$REPO/config/" 2>/dev/null
  sudo cp /etc/gpu-vfio-mode "$REPO/config/" 2>/dev/null
  sudo cp "$CONF" "$REPO/config/" 2>/dev/null
  sudo chown -R "$USER:$USER" "$REPO"
  echo "Config saved in: $REPO"
  return 0
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
menu() {
  local choice
  while true; do
    cat << 'MENU'

GPU passthrough
  1) Check if this computer is compatible
  2) Install
  3) Uninstall
  4) Show IOMMU groups
  5) GPU status (host or passthrough)
  6) Switch the GPU to passthrough (reboots)
  7) Give the GPU back to the host
  8) Save the active system config into this repository
  0) Exit
MENU
    read -rp "Choose [0-8]: " choice || exit 0
    case "$choice" in
      1) check_compat ;;
      2) do_install ;;
      3) do_uninstall ;;
      4) do_iommu ;;
      5) switch status ;;
      6) switch start ;;
      7) switch release ;;
      8) do_backup ;;
      0|q|Q) exit 0 ;;
      *) echo "Invalid choice." ;;
    esac
  done
}

case "${1:-menu}" in
  menu)             menu ;;
  check|--check)    check_compat; exit $? ;;
  install)          do_install; exit $? ;;
  uninstall)        do_uninstall; exit $? ;;
  iommu)            do_iommu; exit $? ;;
  status)           switch status ;;
  start)            switch start ;;
  release)          switch release ;;
  backup)           do_backup ;;
  -h|--help|help)   sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)                echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
esac
