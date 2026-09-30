#!/bin/bash
# Checks whether this computer is compatible with the GPU passthrough setup.
# Usage: check-compat.sh                 human readable report
#        check-compat.sh --print-config  print only GPU_VIDEO/GPU_AUDIO lines
# Exit code: 0 = compatible (warnings allowed), 1 = not compatible.
set -uo pipefail

MODE="${1:-report}"
FAILS=0
WARNS=0

say()  { [ "$MODE" = "report" ] && echo "$@"; return 0; }
ok()   { say "  [ OK ]  $*"; }
warn() { say "  [WARN]  $*"; WARNS=$((WARNS + 1)); }
fail() { say "  [FAIL]  $*"; FAILS=$((FAILS + 1)); }
info() { say "  [INFO]  $*"; }

say "GPU passthrough compatibility check"
say ""

# --- Basics -----------------------------------------------------------------
if [ -d /run/systemd/system ]; then ok "systemd is running"; else fail "systemd is required (the boot service is a systemd unit)"; fi

if command -v lspci >/dev/null 2>&1; then
  ok "lspci found"
else
  fail "lspci not found (install pciutils)"
  if [ "$MODE" = "--print-config" ]; then exit 1; fi
  say ""; say "Result: NOT compatible ($FAILS problem(s))."; exit 1
fi

# --- CPU --------------------------------------------------------------------
if grep -qi genuineintel /proc/cpuinfo; then
  CPU="intel"; info "CPU vendor: Intel (IOMMU parameter: intel_iommu=on)"
elif grep -qi authenticamd /proc/cpuinfo; then
  CPU="amd"; info "CPU vendor: AMD (IOMMU parameter: amd_iommu=on, usually already on)"
else
  CPU="unknown"; warn "unknown CPU vendor"
fi

# --- GPUs ---------------------------------------------------------------------
PCI="$(lspci -D -nn)"
NV_VIDEO_LINE="$(echo "$PCI" | grep -E '\[(0300|0302)\]' | grep -i '\[10de:' | head -1 || true)"
GPU_VIDEO="${NV_VIDEO_LINE%% *}"
GPU_AUDIO=""
if [ -n "$GPU_VIDEO" ]; then
  PREFIX="${GPU_VIDEO%.*}"
  AUDIO_LINE="$(echo "$PCI" | grep "^$PREFIX\." | grep '\[0403\]' | head -1 || true)"
  GPU_AUDIO="${AUDIO_LINE%% *}"
fi

if [ "$MODE" = "--print-config" ]; then
  [ -n "$GPU_VIDEO" ] || exit 1
  echo "GPU_VIDEO=\"$GPU_VIDEO\""
  echo "GPU_AUDIO=\"${GPU_AUDIO:-}\""
  exit 0
fi

if [ -n "$GPU_VIDEO" ]; then
  NAME="$(echo "$NV_VIDEO_LINE" | sed -e 's/^[^ ]* //' -e 's/^[^:]*: //' -e 's/ (rev.*//')"
  ok "NVIDIA GPU found: $NAME"
  info "video function: $GPU_VIDEO"
else
  fail "no NVIDIA GPU found (this setup only supports an NVIDIA dGPU)"
fi
if [ -n "$GPU_VIDEO" ]; then
  if [ -n "$GPU_AUDIO" ]; then info "audio function: $GPU_AUDIO"; else warn "no HDMI audio function found next to the GPU (the scripts expect one)"; fi
fi

HOST_LINE="$(echo "$PCI" | grep -E '\[(0300|0302|0380)\]' | grep -vi '\[10de:' | head -1 || true)"
if [ -n "$HOST_LINE" ]; then
  HOST_NAME="$(echo "$HOST_LINE" | sed -e 's/^[^ ]* //' -e 's/^[^:]*: //' -e 's/ (rev.*//')"
  ok "another GPU is available for the host: $HOST_NAME"
else
  fail "no integrated GPU found: the host would be left without a display"
fi

if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
  info "battery found: this looks like a laptop"
else
  info "no battery found: this looks like a desktop"
fi

# --- IOMMU --------------------------------------------------------------------
if [ -d /sys/kernel/iommu_groups ] && [ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
  ok "IOMMU is active"
  if [ -n "$GPU_VIDEO" ] && [ -e "/sys/bus/pci/devices/$GPU_VIDEO/iommu_group" ]; then
    OTHERS=""
    for d in /sys/bus/pci/devices/$GPU_VIDEO/iommu_group/devices/*; do
      addr="$(basename "$d")"
      [ "$addr" = "$GPU_VIDEO" ] && continue
      [ -n "$GPU_AUDIO" ] && [ "$addr" = "$GPU_AUDIO" ] && continue
      class="$(cat "/sys/bus/pci/devices/$addr/class" 2>/dev/null || echo 0)"
      case "$class" in 0x0604*|0x0600*) continue ;; esac   # bridges are fine
      OTHERS="$OTHERS $addr"
    done
    if [ -z "$OTHERS" ]; then
      ok "the GPU is isolated in its IOMMU group"
    else
      warn "the GPU shares its IOMMU group with:$OTHERS (see scripts/check-iommu.sh)"
    fi
  fi
else
  if [ "$CPU" = "amd" ]; then P="amd_iommu=on iommu=pt"; else P="intel_iommu=on iommu=pt"; fi
  warn "IOMMU is not active: add '$P' to the kernel command line and enable VT-d/AMD-Vi in the BIOS"
fi

# --- Tools --------------------------------------------------------------------
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

say ""
if [ "$FAILS" -gt 0 ]; then
  say "Result: NOT compatible ($FAILS problem(s), $WARNS warning(s))."
  exit 1
fi
if [ "$WARNS" -gt 0 ]; then
  say "Result: compatible, with $WARNS warning(s) to look at."
else
  say "Result: compatible."
fi
exit 0
