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

## How it works

Switching the dGPU to `vfio-pci` is only reliable **at boot**, before the
display manager or the compositor touch the GPU. The flow is:

1. `gpu-switch.sh vfio` writes `vfio` to `/etc/gpu-vfio-mode` and reboots.
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

## Repository layout

```
scripts/
  gpu-switch.sh                    control (vfio, release, status)
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

Then: `sudo systemctl daemon-reload`, enable the two services with
`systemctl enable`, and reboot.

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
