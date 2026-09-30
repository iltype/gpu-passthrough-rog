# GPU passthrough on an ASUS ROG laptop (RTX 4070)

[Versione italiana](README.it.md)

A working setup to detach the dedicated NVIDIA GPU of a hybrid laptop from
the host and bind it to `vfio-pci`, while the host keeps running on the Intel
iGPU. It includes the scripts to switch between "host" mode (nvidia driver)
and "passthrough" mode (vfio-pci) and back.

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

PCI addresses used (adapt them to your system with `lspci -nn`):

- GPU video: `0000:01:00.0`
- GPU audio: `0000:01:00.1`

## The `gpu-switch.sh` script

`gpu-switch.sh` only switches the GPU: it does not create, start or stop any VM.
The two PCI addresses above are variables at the top of the script. What you
do with the GPU once it is on `vfio-pci` (VM, container...) is up to you.

| Command | What it does |
|---|---|
| `status` | shows the driver bound to the GPU and audio functions |
| `start` | if the GPU is not on `vfio-pci` yet: asks for confirmation, stops `ollama` and the `open-webui` container (they hold the GPU), writes `vfio` to the state file and reboots. If it is already on `vfio-pci`, it does nothing |
| `release` | writes `nvidia` to the state file, unbinds both functions from `vfio-pci`, clears `driver_override`, reloads the nvidia modules and `snd_hda_intel`, rescans the PCI bus and sets cardwire back to `hybrid`. No reboot needed |

The script only prepares the switch: the actual bind to `vfio-pci` is done
by `gpu-vfio-boot.sh` at the next boot, reading the state file
`/etc/gpu-vfio-mode`. Edit the `ollama` / `open-webui` lines in `start` to
match the services that use your GPU.

## Repository layout

```
install.sh                         installs everything and enables the services
scripts/
  gpu-switch.sh                         GPU switch (start, release, status)
  gpu-vfio-boot.sh                 bind to vfio-pci at boot
  backup-gpu-passthrough.sh        saves the active config into the repo
systemd/
  gpu-vfio-boot.service
  cardwire-integrated-on-shutdown.service
config/
  cardwire.toml
  nvidia.conf
  gpu-vfio-mode
```

## Installation

| File | Destination on the system |
|---|---|
| `scripts/gpu-switch.sh` | wherever you like (e.g. `~/gpu-switch.sh`) |
| `scripts/gpu-vfio-boot.sh` | `/usr/local/bin/gpu-vfio-boot.sh` (chmod +x) |
| `systemd/*.service` | `/etc/systemd/system/` |
| `config/cardwire.toml` | `/etc/cardwire/cardwire.toml` |
| `config/nvidia.conf` | `/etc/modprobe.d/nvidia.conf` |
| `config/gpu-vfio-mode` | `/etc/gpu-vfio-mode` |

The quick way is `./install.sh`: it copies every file to the destination
above (keeping numbered backups of anything it replaces), installs
`gpu-switch.sh` in your home, runs `daemon-reload` and enables both services.
It leaves an existing `/etc/gpu-vfio-mode` untouched. It also detects your
bootloader (limine, GRUB, systemd-boot) and initramfs tool (`limine-mkinitcpio`,
`mkinitcpio`, `dracut`, `update-initramfs`), offers to rebuild the initramfs,
and checks whether IOMMU is active, printing the exact kernel parameter and
where to put it for your bootloader if it is not (it never edits the
bootloader config by itself). Then reboot and run
`~/gpu-switch.sh start` to switch the GPU to passthrough.

To do it by hand instead: copy the files as in the table, then
`sudo systemctl daemon-reload`, enable the two services with
`systemctl enable`, and reboot.

## Notes

- **Bootloader**: the switch does not depend on the bootloader. The bind to
  `vfio-pci` is done by a systemd service at boot, not by kernel parameters
  such as `vfio-pci.ids=`, so it should work the same with GRUB,
  systemd-boot or others. The bootloader only matters for two things: the
  command to regenerate the initramfs (here `limine-mkinitcpio -P`; on
  GRUB systems typically `mkinitcpio -P` or `dracut`, depending on the
  distro) and, if IOMMU is not already active on your kernel, adding the
  IOMMU parameter to the kernel command line (in `/etc/default/grub` plus
  `grub-mkconfig` on GRUB). Check with `dmesg | grep -i iommu`.
- **Modprobe**: `nvidia_drm modeset=1 fbdev=1`.
- **cardwire**: `experimental_nvidia_block = true`; a systemd unit forces
  `cardwire set integrated` before shutdown/reboot, so the compositor does
  not keep hold of the GPU.
- **cardwire updates**: cardwire is a young, actively developed project and
  `experimental_nvidia_block` is still experimental. After every package
  update, re-check `cardwire.toml`, the
  `cardwire-integrated-on-shutdown.service` unit and the
  `cardwire set hybrid|integrated` commands used in the scripts, since
  options and behaviour may change. After updating, run
  `backup-gpu-passthrough.sh` again to save the working config.
- **Services that block the switch**: any service using the GPU (e.g.
  Ollama, CUDA-based containers, `nvidia-powerd`) prevents the `nvidia`
  module from unloading: stop them before rebooting.
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
