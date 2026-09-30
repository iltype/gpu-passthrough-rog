# Changelog

All notable changes to this project are listed here.
Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- `install.sh` is now a menu with check, install, uninstall, IOMMU groups,
  GPU status, switch to passthrough, release, and a report for compatibility
  issues. Every entry is also a command (`./install.sh check`, `install`,
  `uninstall`, `iommu`, `status`, `start`, `release`, `report`).
- Compatibility check (NVIDIA dGPU, host GPU, IOMMU, IOMMU group, cardwire,
  initramfs tool), run before installing; `./install.sh check` runs only it.
- `/etc/gpu-passthrough.conf`: GPU PCI addresses, detected at install time
  and read by the scripts (no more hardcoded addresses).
- `examples/libvirt/`: optional Windows 11 VM example (libvirt XML,
  `kvm-ignore-msrs.conf`, fake battery ACPI table).
- Compatibility report issue template and a "Tested hardware" table.

### Changed
- `gpu-switch.sh` no longer stops any specific service. It now lists the
  processes using the NVIDIA GPU and asks for confirmation.

## [1.0.0]

### Added
- `gpu-switch.sh`: switch the dGPU between nvidia and vfio-pci
  (`start`, `release`, `status`).
- `gpu-vfio-boot.sh` and systemd service: bind the GPU to vfio-pci at boot.
- cardwire configuration and shutdown hook.
- `install.sh` with bootloader, initramfs and IOMMU detection.
- English and Italian README, MIT license.
