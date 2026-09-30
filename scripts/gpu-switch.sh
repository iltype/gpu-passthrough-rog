#!/bin/bash
# Passa la dGPU NVIDIA tra driver nvidia (host) e vfio-pci (passthrough).
set -uo pipefail

GPU_VIDEO="0000:01:00.0"
GPU_AUDIO="0000:01:00.1"
STATE_FILE="/etc/gpu-vfio-mode"

get_driver() {
  local dev="$1"
  if [ -L "/sys/bus/pci/devices/$dev/driver" ]; then
    basename "$(readlink -f "/sys/bus/pci/devices/$dev/driver")" 2>/dev/null
  fi
}

print_status() {
  local vdriver adriver
  vdriver="$(get_driver "$GPU_VIDEO")"
  adriver="$(get_driver "$GPU_AUDIO")"
  if [ "$vdriver" = "vfio-pci" ]; then
    echo "VFIO status: ACTIVE (video: $vdriver, audio: ${adriver:-none})"
  else
    echo "VFIO status: NOT active (video driver: ${vdriver:-none}, audio driver: ${adriver:-none})"
  fi
}

case "${1:-}" in
status)
  print_status
  ;;

vfio)
  if [ "$(get_driver "$GPU_VIDEO")" = "vfio-pci" ]; then
    echo "Already on vfio-pci."
    exit 0
  fi
  echo "The switch to vfio-pci is only reliable at boot, before the compositor touches the GPU."
  echo "This will request the switch and reboot."
  read -rp "Continue? [y/N] " proceed
  [[ "$proceed" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  echo "Stop any service using the GPU first (e.g. ollama, CUDA containers)."
  echo "vfio" | sudo tee "$STATE_FILE" >/dev/null
  sudo reboot
  ;;

release)
  echo "Clearing the vfio boot request..."
  echo "nvidia" | sudo tee "$STATE_FILE" >/dev/null
  echo "Unbinding vfio-pci and returning the GPU to nvidia..."
  echo "$GPU_VIDEO" | sudo tee /sys/bus/pci/drivers/vfio-pci/unbind >/dev/null 2>&1
  echo "$GPU_AUDIO" | sudo tee /sys/bus/pci/drivers/vfio-pci/unbind >/dev/null 2>&1
  echo "" | sudo tee "/sys/bus/pci/devices/$GPU_VIDEO/driver_override" >/dev/null
  echo "" | sudo tee "/sys/bus/pci/devices/$GPU_AUDIO/driver_override" >/dev/null
  sudo modprobe nvidia
  sudo modprobe nvidia_modeset
  sudo modprobe nvidia_drm
  sudo modprobe nvidia_uvm
  sudo modprobe snd_hda_intel
  echo "$GPU_AUDIO" | sudo tee /sys/bus/pci/drivers/snd_hda_intel/bind >/dev/null 2>&1
  echo 1 | sudo tee /sys/bus/pci/rescan >/dev/null
  sleep 2
  echo "Setting cardwire back to hybrid..."
  cardwire set hybrid
  print_status
  ;;

*)
  echo "Usage: $0 [vfio|release|status]"
  exit 1
  ;;
esac
