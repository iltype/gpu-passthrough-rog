#!/bin/bash
# Lists all IOMMU groups and highlights the one that contains the NVIDIA GPU.
# The GPU (and its audio function) should be alone in its group, except for
# PCI bridges, to be passed through cleanly.
set -uo pipefail

if [ ! -d /sys/kernel/iommu_groups ] || [ -z "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
  echo "IOMMU is not active. Enable VT-d / AMD-Vi in the BIOS and add"
  echo "intel_iommu=on iommu=pt (or amd_iommu=on iommu=pt) to the kernel command line."
  exit 1
fi
if ! command -v lspci >/dev/null 2>&1; then
  echo "lspci not found (install pciutils)." >&2
  exit 1
fi

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
