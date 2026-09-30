#!/bin/bash
set -uo pipefail

STATE_FILE="/etc/gpu-vfio-mode"
GPU_VIDEO="0000:01:00.0"
GPU_AUDIO="0000:01:00.1"
LOG="/var/log/gpu-vfio-boot.log"

exec > "$LOG" 2>&1
echo "$(date): gpu-vfio-boot starting"

if [ ! -f "$STATE_FILE" ] || [ "$(cat "$STATE_FILE")" != "vfio" ]; then
  echo "No vfio switch requested, exiting."
  exit 0
fi

echo "vfio mode requested - binding GPU to vfio-pci before display manager starts..."

echo -n "$GPU_VIDEO" > /sys/bus/pci/drivers/nvidia/unbind 2>/dev/null || true
echo -n "$GPU_AUDIO" > /sys/bus/pci/drivers/snd_hda_intel/unbind 2>/dev/null || true

for i in 1 2 3 4 5 6 7 8 9 10; do
  rmmod nvidia_uvm 2>/dev/null
  rmmod nvidia_drm 2>/dev/null
  rmmod nvidia_modeset 2>/dev/null
  rmmod nvidia 2>/dev/null
  if ! lsmod | grep -q '^nvidia '; then
    echo "nvidia modules unloaded after $i attempt(s)."
    break
  fi
  sleep 1
done

if lsmod | grep -q '^nvidia '; then
  echo "WARNING: nvidia module still loaded, aborting vfio-pci bind."
  exit 1
fi

modprobe vfio-pci
modprobe vfio
modprobe vfio_iommu_type1

echo "vfio-pci" > "/sys/bus/pci/devices/$GPU_VIDEO/driver_override"
echo "vfio-pci" > "/sys/bus/pci/devices/$GPU_AUDIO/driver_override"
echo "$GPU_VIDEO" > /sys/bus/pci/drivers_probe
echo "$GPU_AUDIO" > /sys/bus/pci/drivers_probe

sleep 1
echo "Done. Video driver: $(basename "$(readlink -f "/sys/bus/pci/devices/$GPU_VIDEO/driver" 2>/dev/null)" 2>/dev/null)"
echo "Done. Audio driver: $(basename "$(readlink -f "/sys/bus/pci/devices/$GPU_AUDIO/driver" 2>/dev/null)" 2>/dev/null)"
