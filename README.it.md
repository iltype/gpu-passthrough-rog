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

1. `win11.sh start` (o `gpu-switch.sh vfio`) scrive `vfio` in `/etc/gpu-vfio-mode` e riavvia.
2. Al boot, `gpu-vfio-boot.service` (prima del display manager e di
   `cardwired`) esegue `gpu-vfio-boot.sh`, che legge il file di stato,
   scarica i moduli `nvidia*` e associa GPU e audio HDMI a `vfio-pci`
   tramite `driver_override` + `drivers_probe`.
3. L'host resta sulla iGPU Intel; la dGPU e' pronta per essere assegnata.
4. `win11.sh release` (o `gpu-switch.sh release`) rimette la GPU a `nvidia` senza riavviare e
   riporta cardwire in modalita' `hybrid`.

Indirizzi PCI usati (da adattare al proprio sistema con `lspci -nn`):

- GPU video: `0000:01:00.0`
- GPU audio: `0000:01:00.1`

## Lo script `win11.sh`

`win11.sh` e' lo script di controllo completo. Presuppone una VM libvirt
chiamata `win11` e i due indirizzi PCI indicati sopra (sono variabili in
cima al file). `gpu-switch.sh` contiene la stessa logica GPU senza nulla
che riguardi la VM.

| Comando | Cosa fa |
|---|---|
| `status` | mostra il driver associato a GPU e audio, e se la VM e' in esecuzione |
| `start` | se la GPU non e' ancora su `vfio-pci`: chiede conferma, ferma `ollama` e il container `open-webui` (tengono occupata la GPU), scrive `vfio` nel file di stato e riavvia. Se la GPU e' gia' su `vfio-pci`: chiede se avviare la VM, esegue `virsh start` e apre la console di virt-manager |
| `stop` | `virsh shutdown` pulito, attende fino a 30 s, poi forza con `virsh destroy`. La GPU resta su `vfio-pci`, quindi la VM si puo' riavviare subito |
| `release` | scrive `nvidia` nel file di stato, stacca le due funzioni da `vfio-pci`, azzera `driver_override`, ricarica i moduli nvidia e `snd_hda_intel`, riscansiona il bus PCI e rimette cardwire su `hybrid`. Non serve riavviare |
| `hybrid` | come `release`, ma prima spegne la VM se e' in esecuzione |

Lo script prepara solo il passaggio: il bind effettivo a `vfio-pci` lo fa
`gpu-vfio-boot.sh` al boot successivo, leggendo il file di stato
`/etc/gpu-vfio-mode`. Modifica le righe `ollama` / `open-webui` in `start`
in base ai servizi che usano la tua GPU.

## Struttura del repository

```
install.sh                         installa tutto e abilita i servizi
scripts/
  win11.sh                         controllo completo: switch GPU + VM Windows 11
  gpu-switch.sh                    solo switch GPU, senza VM (vfio, release, status)
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
| `scripts/win11.sh` | dove preferisci (es. `~/win11.sh`) |
| `scripts/gpu-switch.sh` | opzionale, come sopra senza la parte VM |
| `scripts/gpu-vfio-boot.sh` | `/usr/local/bin/gpu-vfio-boot.sh` (chmod +x) |
| `systemd/*.service` | `/etc/systemd/system/` |
| `config/cardwire.toml` | `/etc/cardwire/cardwire.toml` |
| `config/nvidia.conf` | `/etc/modprobe.d/nvidia.conf` |
| `config/gpu-vfio-mode` | `/etc/gpu-vfio-mode` |

Il modo rapido e' `./install.sh`: copia ogni file nella destinazione
indicata (tenendo backup numerati di cio' che sostituisce), installa
`win11.sh` nella tua home, esegue `daemon-reload` e abilita i due servizi.
Non tocca un eventuale `/etc/gpu-vfio-mode` gia' presente. Poi riavvia e
lancia `~/win11.sh start`.

Per farlo a mano: copia i file come in tabella, poi
`sudo systemctl daemon-reload`, abilita i due servizi con
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
