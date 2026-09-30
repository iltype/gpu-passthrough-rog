# GPU passthrough on an ASUS ROG laptop (RTX 4070)

![Last commit](https://img.shields.io/github/last-commit/iltype/gpu-passthrough-rog)
![Release](https://img.shields.io/github/v/release/iltype/gpu-passthrough-rog)
![License](https://img.shields.io/github/license/iltype/gpu-passthrough-rog)
![Tested on](https://img.shields.io/badge/tested%20on-CachyOS-blue)

[Versione italiana](README.it.md) | [Changelog](CHANGELOG.md)

A working setup to detach the dedicated NVIDIA GPU of a hybrid laptop from
the host and bind it to `vfio-pci`, while the host keeps running on the Intel
iGPU. It includes the scripts to switch between "host" mode (nvidia driver)
and "passthrough" mode (vfio-pci) and back, and a check that tells you if
your computer is compatible before installing anything.

## My laptop

| Component | Details |
|---|---|
| Model | ASUS ROG Zephyrus M16 (2023), GU604VI |
| CPU | Intel Core i9-13900H |
| Integrated GPU | Intel Iris Xe (host) |
| Dedicated GPU | NVIDIA GeForce RTX 4070 Laptop, 8 GB VRAM |
| RAM | 48 GB |
| Display | 2560x1600, 240 Hz |

## Software

- CachyOS (Arch based)
- Bootloader: limine

## Compatibility

Made for a **hybrid laptop with an Intel iGPU and an NVIDIA dGPU**.

- **Intel + NVIDIA** (my case): the setup this repository is built and
  tested for. The IOMMU parameter is `intel_iommu=on`.
- **AMD + NVIDIA**: should work almost the same, but the IOMMU parameter
  becomes `amd_iommu=on` (the installer detects it). Not tested.
- **AMD dedicated GPU**: not supported, the scripts unload the `nvidia*`
  modules and rely on cardwire's NVIDIA handling.
- **Desktop or laptop without an iGPU**: not supported, the host would be
  left without a display.
- **Requires cardwire**, an AUR package: on non-Arch distributions it has to
  be built manually.

To find out if your computer is compatible **before installing anything**:

```
./install.sh --check
```

It looks for an NVIDIA GPU, a second GPU for the host, IOMMU (and whether
the GPU sits alone in its IOMMU group), cardwire, the nvidia driver and your
initramfs tool, and prints `OK`, `WARN` or `FAIL` for each. Nothing is
changed on the system. To see all IOMMU groups: `./install.sh iommu`.

### Tested hardware

| Laptop | CPU | GPUs | Distribution | Result |
|---|---|---|---|---|
| ASUS ROG Zephyrus M16 (2023) GU604VI | Intel i9-13900H | Intel Iris Xe + RTX 4070 Laptop | CachyOS, limine | works |

Did you try it on your hardware? Run `./install.sh report` (menu entry 8),
then open an issue with the "Compatibility report" template and paste the
output: working or not, it helps others, and I will add it to this table.
The report contains no hostname, serial numbers or MAC addresses.

## How it works

Switching the dGPU to `vfio-pci` is only reliable **at boot**, before the
display manager or the compositor touch the GPU. The flow is:

1. `gpu-switch.sh start` writes `vfio` to `/etc/gpu-vfio-mode` and reboots.
2. At boot, `gpu-vfio-boot.service` (ordered before the display manager and
   `cardwired`) runs `gpu-vfio-boot.sh`, which reads the state file, unloads
   the `nvidia*` modules and binds the GPU and its HDMI audio function to
   `vfio-pci` via `driver_override` + `drivers_probe`.
3. The host stays on the Intel iGPU; the dGPU is ready to be assigned.
4. `gpu-switch.sh release` gives the GPU back to `nvidia` without rebooting
   and sets cardwire back to `hybrid`.

The PCI addresses of the GPU are read from `/etc/gpu-passthrough.conf`,
which `install.sh` fills with the addresses detected on your machine
(`lspci -D -nn | grep -i nvidia` to check them).

## The `gpu-switch.sh` script

`gpu-switch.sh` only switches the GPU: it does not create, start or stop any
VM. What you do with the GPU once it is on `vfio-pci` (VM, container...) is
up to you.

| Command | What it does |
|---|---|
| `status` | shows the driver bound to the GPU and audio functions |
| `start` | if the GPU is not on `vfio-pci` yet: lists the processes using the NVIDIA GPU, asks for confirmation, writes `vfio` to the state file and reboots. If it is already on `vfio-pci`, it does nothing |
| `release` | writes `nvidia` to the state file, unbinds both functions from `vfio-pci`, clears `driver_override`, reloads the nvidia modules and `snd_hda_intel`, rescans the PCI bus and sets cardwire back to `hybrid`. No reboot needed |

The script only prepares the switch: the actual bind to `vfio-pci` is done
by `gpu-vfio-boot.sh` at the next boot, reading the state file
`/etc/gpu-vfio-mode`. It does not stop any service by itself: close what
uses the GPU (games, AI tools, CUDA containers...) before `start`.

## Repository layout

```
install.sh                         one script: check, install, uninstall, IOMMU groups,
                                   GPU switch shortcuts, issue report (interactive menu)
scripts/
  gpu-switch.sh                    GPU switch (start, release, status)
  gpu-vfio-boot.sh                 bind to vfio-pci at boot
systemd/
  gpu-vfio-boot.service
  cardwire-integrated-on-shutdown.service
config/
  cardwire.toml
  nvidia.conf
  gpu-vfio-mode
  gpu-passthrough.conf             default GPU PCI addresses
examples/libvirt/                  optional Windows 11 VM example
.github/ISSUE_TEMPLATE/            compatibility report template
CHANGELOG.md
```

## Installation

```
git clone https://github.com/iltype/gpu-passthrough-rog.git
cd gpu-passthrough-rog
./install.sh
```

`install.sh` opens a menu:

```
1) Check if this computer is compatible
2) Install
3) Uninstall
4) Show IOMMU groups
5) GPU status (host or passthrough)
6) Switch the GPU to passthrough (reboots)
7) Give the GPU back to the host
8) Generate a report for a compatibility issue
0) Exit
```

Every entry is also available as a command, for example `./install.sh check`,
`./install.sh install`, `./install.sh uninstall` (`./install.sh --help` lists
them all).

**Install** first runs the compatibility check and asks before going on if
something is wrong. Then it copies every file to the destination below
(keeping numbered backups of anything it replaces), installs
`gpu-switch.sh` in your home, writes `/etc/gpu-passthrough.conf` with the
detected GPU addresses, runs `daemon-reload` and enables both services. It
leaves an existing `/etc/gpu-vfio-mode` untouched. It also detects your
bootloader (limine, GRUB, systemd-boot) and initramfs tool
(`limine-mkinitcpio`, `mkinitcpio`, `dracut`, `update-initramfs`), offers to
rebuild the initramfs, and checks whether IOMMU is active, printing the
exact kernel parameter and where to put it for your bootloader if it is not
(it never edits the bootloader config by itself). Then reboot and switch the
GPU to passthrough with entry 6 (or `~/gpu-switch.sh start`).

**Uninstall** removes everything and restores the files that install had
backed up. If the GPU is on `vfio-pci`, give it back to the host first
(entry 7).

| File | Destination on the system |
|---|---|
| `scripts/gpu-switch.sh` | wherever you like (e.g. `~/gpu-switch.sh`) |
| `scripts/gpu-vfio-boot.sh` | `/usr/local/bin/gpu-vfio-boot.sh` (chmod +x) |
| `systemd/*.service` | `/etc/systemd/system/` |
| `config/cardwire.toml` | `/etc/cardwire/cardwire.toml` |
| `config/nvidia.conf` | `/etc/modprobe.d/nvidia.conf` |
| `config/gpu-vfio-mode` | `/etc/gpu-vfio-mode` |
| `config/gpu-passthrough.conf` | `/etc/gpu-passthrough.conf` (edit the addresses) |

To do it by hand instead: copy the files as in the table, then
`sudo systemctl daemon-reload`, enable the two services with
`systemctl enable`, and reboot.

## Optional: Windows 11 VM

The scripts do not touch any VM. If you want to use the GPU in a Windows 11
VM with libvirt, `examples/libvirt/` has a working definition (without
UUID, MAC and personal paths) and the extra files it needs. See
`examples/libvirt/README.md`.

## Notes

- **Modprobe**: `nvidia_drm modeset=1 fbdev=1`.
- **cardwire**: `experimental_nvidia_block = true`; a systemd unit forces
  `cardwire set integrated` before shutdown/reboot, so the compositor does
  not keep hold of the GPU.
- **cardwire updates**: cardwire is a young, actively developed project and
  `experimental_nvidia_block` is still experimental. After every package
  update, re-check `cardwire.toml`, the
  `cardwire-integrated-on-shutdown.service` unit and the
  `cardwire set hybrid|integrated` commands used in the scripts, since
  options and behaviour may change.
- **Bootloader**: the switch does not depend on the bootloader. The bind to
  `vfio-pci` is done by a systemd service at boot, not by kernel parameters
  such as `vfio-pci.ids=`, so it should work the same with GRUB,
  systemd-boot or others. The bootloader only matters for two things: the
  command to regenerate the initramfs (here `limine-mkinitcpio -P`; on
  GRUB systems typically `mkinitcpio -P` or `dracut`, depending on the
  distro) and, if IOMMU is not already active on your kernel, adding the
  IOMMU parameter to the kernel command line (in `/etc/default/grub` plus
  `grub-mkconfig` on GRUB). Check with `dmesg | grep -i iommu`.
- **Services that block the switch**: any process using the GPU (e.g. AI
  tools, CUDA-based containers, `nvidia-powerd`) prevents the `nvidia`
  module from unloading. `gpu-switch.sh start` lists them before rebooting.
- **supergfxctl** is deprecated and logind-based logout detection does not
  work on this system, which is why it was replaced by cardwire.
- cardwire's `integrated` mode hides the PCI device and interferes with the
  manual unbind, so `hybrid` is used before switching to vfio.
- Unloading `nvidia` can take several attempts: the script retries up to 10
  times before giving up.

## Disclaimer

This setup is tailored to my hardware. On another laptop, PCI addresses,
IOMMU groups and most likely the MUX behaviour will differ. Use it as a
reference, not as a recipe to copy blindly, and always take a btrfs snapshot
before trying it.

## License

Released under the MIT License (see `LICENSE`): free to use, copy and modify.

## Credits

If you reuse or adapt this work, please credit the author and link back to
the original repository: https://github.com/iltype/gpu-passthrough-rog
(The MIT License already requires keeping the copyright notice in copies of
the code.)
