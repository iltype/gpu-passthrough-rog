# Example: Windows 11 VM with the passed-through GPU

Optional. The main scripts only switch the GPU to `vfio-pci`; what you do
with it afterwards is up to you. This folder is a working example for a
Windows 11 VM with libvirt/QEMU (OVMF UEFI + TPM).

| File | Destination |
|---|---|
| `win11-domain.xml` | `sudo virsh define win11-domain.xml` |
| `kvm-ignore-msrs.conf` | `/etc/modprobe.d/kvm-ignore-msrs.conf` (avoids Windows crashes on unsupported MSRs) |
| `acpitable.bin` | `/var/lib/libvirt/images/acpitable.bin` (owner `libvirt-qemu`), a fake ACPI battery: the NVIDIA laptop driver expects one |

Before defining the VM, adapt `win11-domain.xml`:

- **PCI addresses**: the two `hostdev` blocks use `01:00.0` and `01:00.1`.
  Use the addresses in your `/etc/gpu-passthrough.conf`.
- **Disk**: the image path is `/var/lib/libvirt/images/win11.qcow2`; create
  or point to your own disk.
- **Machine type**: `pc-q35-11.0` needs a recent QEMU. If `virsh define`
  complains, use `pc-q35-9.2` or one listed by `qemu-system-x86_64 -machine help`.
- **CPU and RAM**: 8 vCPUs and the memory size are the ones I use.
- **Anti error 43**: the Hyper-V `vendor_id` value is set on purpose, so the
  NVIDIA driver works inside the guest.

Usage: switch the GPU with `~/gpu-switch.sh start` (it reboots), then start
the VM with `virsh start win11` or from virt-manager. To give the GPU back:
shut the VM down and run `~/gpu-switch.sh release`.
