# Changelog

All notable changes to this project are listed here.
Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- `scripts/check-compat.sh`: checks if the computer is compatible (NVIDIA
  dGPU, host GPU, IOMMU, IOMMU group, cardwire, initramfs tool). Also run
  by `install.sh` before installing; `./install.sh --check` runs only it.
- `scripts/check-iommu.sh`: lists IOMMU groups and highlights the NVIDIA one.
- `uninstall.sh`: removes what `install.sh` installed and restores backups.
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
