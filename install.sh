#!/bin/bash
# Installa la configurazione GPU passthrough sul sistema.
# Uso: ./install.sh   (da utente normale, usa sudo dove serve)
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -eq 0 ]; then
  echo "Esegui lo script come utente normale, non come root." >&2
  exit 1
fi

if ! command -v cardwire >/dev/null 2>&1; then
  echo "ATTENZIONE: cardwire non e' installato (AUR: cardwire). Gli script lo richiedono." >&2
fi

# Copia con backup numerato se il file di destinazione esiste gia'.
inst() {
  local mode="$1" src="$2" dst="$3"
  sudo install -D -m "$mode" --backup=numbered "$REPO/$src" "$dst"
  echo "  $src -> $dst"
}

echo "Installing scripts..."
inst 755 scripts/gpu-vfio-boot.sh /usr/local/bin/gpu-vfio-boot.sh
install -m 755 "$REPO/scripts/win11.sh" "$HOME/win11.sh"
echo "  scripts/win11.sh -> $HOME/win11.sh"

echo "Installing systemd units..."
inst 644 systemd/gpu-vfio-boot.service /etc/systemd/system/gpu-vfio-boot.service
inst 644 systemd/cardwire-integrated-on-shutdown.service /etc/systemd/system/cardwire-integrated-on-shutdown.service

echo "Installing config..."
inst 644 config/cardwire.toml /etc/cardwire/cardwire.toml
inst 644 config/nvidia.conf /etc/modprobe.d/nvidia.conf

# Il file di stato non va sovrascritto se esiste gia'.
if [ ! -f /etc/gpu-vfio-mode ]; then
  sudo install -D -m 644 "$REPO/config/gpu-vfio-mode" /etc/gpu-vfio-mode
  echo "  config/gpu-vfio-mode -> /etc/gpu-vfio-mode"
else
  echo "  /etc/gpu-vfio-mode exists, left untouched"
fi

echo "Enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable gpu-vfio-boot.service
sudo systemctl enable cardwire-integrated-on-shutdown.service

cat << 'MSG'

Fatto. Prossimi passi:
  1. Se i moduli nvidia sono nell'initramfs: sudo limine-mkinitcpio -P
  2. Riavvia.
  3. Passa la GPU al passthrough con: ~/win11.sh start (riavvia da solo)
  4. Per tornare alla GPU sull'host: ~/win11.sh release
MSG
