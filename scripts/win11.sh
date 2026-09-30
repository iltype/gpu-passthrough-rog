#!/bin/bash
set -uo pipefail

GPU_VIDEO="0000:01:00.0"
GPU_AUDIO="0000:01:00.1"
VM_NAME="win11"
STATE_FILE="/etc/gpu-vfio-mode"

get_driver() {
  local dev="$1"
  if [ -L "/sys/bus/pci/devices/$dev/driver" ]; then
    basename "$(readlink -f "/sys/bus/pci/devices/$dev/driver")" 2>/dev/null
  fi
}

print_status() {
  local vdriver adriver vmstate
  vdriver="$(get_driver "$GPU_VIDEO")"
  adriver="$(get_driver "$GPU_AUDIO")"
  vmstate="$(sudo virsh domstate "$VM_NAME" 2>/dev/null)"
  [ "$vmstate" = "running" ] || vmstate="not running"
  if [ "$vdriver" = "vfio-pci" ]; then
    echo "VFIO status: ACTIVE (video: $vdriver, audio: ${adriver:-none})"
  else
    echo "VFIO status: NOT active (video driver: ${vdriver:-none}, audio driver: ${adriver:-none})"
  fi
  echo "VM '$VM_NAME': $vmstate"
}

ACTION="${1:-}"
if [ -z "$ACTION" ]; then
  echo "Usage: ~/win11.sh [start|stop|release|hybrid|status]"
  exit 1
fi

if [ "$ACTION" = "status" ]; then
  print_status
  exit 0
fi

case "$ACTION" in
start)
  print_status
  vdriver="$(get_driver "$GPU_VIDEO")"
  if [ "$vdriver" = "vfio-pci" ]; then
    echo "Already on vfio-pci."
  else
    echo "The GPU switch to vfio-pci is only reliable when done at boot, before Hyprland ever touches the GPU."
    echo "This will request that switch and reboot the system."
    read -rp "Continue? [y/N] " proceed
    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
    echo "Stopping known GPU-heavy services so they don't auto-restart mid-boot..."
    sudo systemctl stop ollama 2>/dev/null
    docker stop open-webui 2>/dev/null
    echo "vfio" | sudo tee "$STATE_FILE" >/dev/null
    echo "Requested. Rebooting now..."
    sudo reboot
    exit 0
  fi

  read -rp "Start Windows 11? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    if sudo virsh start "$VM_NAME"; then
      virt-manager --connect qemu:///system --show-domain-console "$VM_NAME"
    else
      echo "virsh start failed, the VM did not start." >&2
      exit 1
    fi
  else
    echo "vfio-pci active. Start the VM manually whenever you want."
  fi
  ;;

hybrid)
  STATE=$(sudo virsh domstate "$VM_NAME" 2>/dev/null)
  if [ "$STATE" = "running" ]; then
    echo "Shutting down $VM_NAME (graceful) first..."
    sudo virsh shutdown "$VM_NAME"
    waited=0
    while [ "$(sudo virsh domstate "$VM_NAME" 2>/dev/null)" = "running" ]; do
      sleep 2
      waited=$((waited + 2))
      if [ "$waited" -ge 30 ]; then
        echo "Shutdown too slow, forcing with virsh destroy..."
        sudo virsh destroy "$VM_NAME"
        break
      fi
    done
  fi
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

stop)
  STATE=$(sudo virsh domstate "$VM_NAME" 2>/dev/null)
  if [ "$STATE" = "running" ]; then
    echo "Shutting down $VM_NAME (graceful)..."
    sudo virsh shutdown "$VM_NAME"
    waited=0
    while [ "$(sudo virsh domstate "$VM_NAME" 2>/dev/null)" = "running" ]; do
      sleep 2
      waited=$((waited + 2))
      if [ "$waited" -ge 30 ]; then
        echo "Shutdown too slow, forcing with virsh destroy..."
        sudo virsh destroy "$VM_NAME"
        break
      fi
    done
    echo "VM stopped. GPU stays on vfio-pci (no driver switch). Run ~/win11.sh release or ~/win11.sh hybrid if you also want the GPU back for native Linux use."
  else
    echo "VM was not running."
  fi
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
  echo "Usage: ~/win11.sh [start|stop|release|hybrid|status]"
  ;;
esac
