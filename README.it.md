# GPU passthrough su laptop ASUS ROG (RTX 4070)

[English version](README.md)

Italiano | [English](README.en.md)

Configurazione funzionante per staccare la GPU NVIDIA dedicata di un laptop
ibrido dal sistema host e associarla a `vfio-pci`, mantenendo l'host sulla
iGPU Intel. Include gli script per passare da modalita' "host" (driver
nvidia) a modalita' "passthrough" (vfio-pci) e viceversa.

## Il mio laptop

| Componente | Dettaglio |
|---|---|
| Modello | ASUS ROG Zephyrus M16 (2023), GU604VI |
| CPU | Intel Core i9-13900H |
| GPU integrata | Intel Iris Xe (host) |
| GPU dedicata | NVIDIA GeForce RTX 4070 Laptop, 8 GB VRAM |
| RAM | 48 GB |
| Display | 2560x1600, 240 Hz |

## Software

- CachyOS (Arch based)

## Come funziona

Il passaggio della dGPU a `vfio-pci` e' affidabile solo se fatto **al boot**,
prima che il display manager o il compositor tocchino la GPU. Il flusso e':

1. `gpu-switch.sh vfio` scrive `vfio` in `/etc/gpu-vfio-mode` e riavvia.
2. Al boot, `gpu-vfio-boot.service` (prima del display manager e di
   `cardwired`) esegue `gpu-vfio-boot.sh`, che legge il file di stato,
   scarica i moduli `nvidia*` e associa GPU e audio HDMI a `vfio-pci`
   tramite `driver_override` + `drivers_probe`.
3. L'host resta sulla iGPU Intel; la dGPU e' pronta per essere assegnata.
4. `gpu-switch.sh release` rimette la GPU a `nvidia` senza riavviare e
   riporta cardwire in modalita' `hybrid`.

Indirizzi PCI usati (da adattare al proprio sistema con `lspci -nn`):

- GPU video: `0000:01:00.0`
- GPU audio: `0000:01:00.1`

## Struttura del repository

```
scripts/
  gpu-switch.sh                    controllo (vfio, release, status)
  gpu-vfio-boot.sh                 bind a vfio-pci al boot
  backup-gpu-passthrough.sh        salva la config attiva nel repository
systemd/
  gpu-vfio-boot.service
  cardwire-integrated-on-shutdown.service
config/
  cardwire.toml
  nvidia.conf
  gpu-vfio-mode
```

## Installazione

| File | Destinazione sul sistema |
|---|---|
| `scripts/gpu-switch.sh` | dove preferisci (es. `~/gpu-switch.sh`) |
| `scripts/gpu-vfio-boot.sh` | `/usr/local/bin/gpu-vfio-boot.sh` (chmod +x) |
| `systemd/*.service` | `/etc/systemd/system/` |
| `config/cardwire.toml` | `/etc/cardwire/cardwire.toml` |
| `config/nvidia.conf` | `/etc/modprobe.d/nvidia.conf` |
| `config/gpu-vfio-mode` | `/etc/gpu-vfio-mode` |

Poi: `sudo systemctl daemon-reload`, abilita i due servizi con
`systemctl enable` e riavvia.

## Note

- **Modprobe**: `nvidia_drm modeset=1 fbdev=1`.
- **cardwire**: `experimental_nvidia_block = true`; un'unita' systemd forza
  `cardwire set integrated` prima di spegnimento/riavvio, per evitare che il
  compositor trattenga la GPU.
- **Servizi che bloccano il passaggio**: qualunque servizio che usi la GPU
  (es. Ollama, container con immagine CUDA, `nvidia-powerd`) impedisce lo
  scaricamento del modulo `nvidia`: vanno fermati prima del riavvio.
- **Aggiornamenti di cardwire**: cardwire e' un progetto giovane e in
  sviluppo attivo, con `experimental_nvidia_block` ancora sperimentale.
  Dopo ogni aggiornamento del pacchetto vanno ricontrollati `cardwire.toml`,
  l'unita' `cardwire-integrated-on-shutdown.service` e i comandi
  `cardwire set hybrid|integrated` usati negli script, perche' opzioni e
  comportamento potrebbero cambiare. Dopo l'aggiornamento riesegui
  `backup-gpu-passthrough.sh` per salvare la config funzionante.
- **supergfxctl** e' deprecato e il rilevamento del logout via logind non
  funziona su questo sistema: per questo e' stato sostituito da cardwire.
- Il modo `integrated` di cardwire nasconde il dispositivo PCI e interferisce
  con l'unbind manuale: si usa `hybrid` prima del passaggio a vfio.
- Lo scaricamento di `nvidia` puo' richiedere piu' tentativi: lo script ne fa
  fino a 10 prima di rinunciare.

## Avvertenze

Configurazione pensata per il mio hardware. Su un altro portatile cambiano
indirizzi PCI, gruppi IOMMU e con tutta probabilita' il comportamento del MUX.
Usala come riferimento, non come ricetta da copiare alla cieca, e tieni sempre
uno snapshot btrfs prima di provare.
