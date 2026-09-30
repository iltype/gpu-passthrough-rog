# GPU passthrough su laptop ASUS ROG (RTX 4070)

![Last commit](https://img.shields.io/github/last-commit/iltype/gpu-passthrough-rog)
![Release](https://img.shields.io/github/v/release/iltype/gpu-passthrough-rog)
![License](https://img.shields.io/github/license/iltype/gpu-passthrough-rog)
![Tested on](https://img.shields.io/badge/tested%20on-CachyOS-blue)

[English version](README.md) | [Changelog](CHANGELOG.md)

Configurazione funzionante per staccare la GPU NVIDIA dedicata di un laptop
ibrido dal sistema host e associarla a `vfio-pci`, mantenendo l'host sulla
iGPU Intel. Include gli script per passare da modalita' "host" (driver
nvidia) a modalita' "passthrough" (vfio-pci) e viceversa, e un controllo che
dice se il tuo computer e' compatibile prima di installare qualsiasi cosa.

## Il mio laptop

| Componente | Dettaglio |
|---|---|
| Modello | ASUS ROG Zephyrus G16 (2023), GU603VI |
| CPU | Intel Core i9-13900H |
| GPU integrata | Intel Iris Xe (host) |
| GPU dedicata | NVIDIA GeForce RTX 4070 Laptop, 8 GB VRAM |
| RAM | 48 GB |
| Display | 2560x1600, 240 Hz |

## Software

- CachyOS (Arch based)
- Bootloader: limine

## Compatibilita'

Pensato per un **portatile ibrido con iGPU Intel e dGPU NVIDIA**.

- **Intel + NVIDIA** (il mio caso): la configurazione per cui e' costruito e
  testato questo repository. Il parametro IOMMU e' `intel_iommu=on`.
- **AMD + NVIDIA**: dovrebbe funzionare quasi uguale, ma il parametro IOMMU
  diventa `amd_iommu=on` (l'installer lo rileva). Non testato.
- **GPU dedicata AMD**: non supportata, gli script scaricano i moduli
  `nvidia*` e si appoggiano alla gestione NVIDIA di cardwire.
- **Desktop o portatile senza iGPU**: non supportato, l'host resterebbe senza
  schermo.
- **Richiede cardwire**, un pacchetto AUR: su distribuzioni non Arch va
  compilato a mano.

Per sapere se il tuo computer e' compatibile **prima di installare nulla**:

```
./install.sh --check
```

Cerca una GPU NVIDIA, una seconda GPU per l'host, l'IOMMU (e se la GPU e' da
sola nel suo gruppo IOMMU), cardwire, il driver nvidia e lo strumento per
l'initramfs, e stampa `OK`, `WARN` o `FAIL` per ognuno. Non cambia nulla sul
sistema. Per vedere tutti i gruppi IOMMU: `./install.sh iommu`.

### Hardware testato

| Laptop | CPU | GPU | Distribuzione | Risultato |
|---|---|---|---|---|
| ASUS ROG Zephyrus G16 (2023) GU603VI | Intel i9-13900H | Intel Iris Xe + RTX 4070 Laptop | CachyOS, limine | funziona |

Hai provato sul tuo hardware? Lancia `./install.sh report` (voce 8 del
menu), poi apri una issue con il modello "Compatibility report" e incolla
l'output: che funzioni o no, aiuta gli altri, e lo aggiungero' a questa
tabella. Il report non contiene hostname, numeri di serie o indirizzi MAC.

## Come funziona

Il passaggio della dGPU a `vfio-pci` e' affidabile solo se fatto **al boot**,
prima che il display manager o il compositor tocchino la GPU. Il flusso e':

1. `gpu-switch.sh start` scrive `vfio` in `/etc/gpu-vfio-mode` e riavvia.
2. Al boot, `gpu-vfio-boot.service` (prima del display manager e di
   `cardwired`) esegue `gpu-vfio-boot.sh`, che legge il file di stato,
   scarica i moduli `nvidia*` e associa GPU e audio HDMI a `vfio-pci`
   tramite `driver_override` + `drivers_probe`.
3. L'host resta sulla iGPU Intel; la dGPU e' pronta per essere assegnata.
4. `gpu-switch.sh release` rimette la GPU a `nvidia` senza riavviare e
   riporta cardwire in modalita' `hybrid`.

Gli indirizzi PCI della GPU sono letti da `/etc/gpu-passthrough.conf`, che
`install.sh` riempie con quelli rilevati sulla tua macchina
(`lspci -D -nn | grep -i nvidia` per controllarli).

## Lo script `gpu-switch.sh`

`gpu-switch.sh` si limita a spostare la GPU: non crea, avvia o ferma nessuna
VM. Cosa farci una volta che la GPU e' su `vfio-pci` (VM, container...)
dipende da te.

| Comando | Cosa fa |
|---|---|
| `status` | mostra il driver associato a GPU e audio |
| `start` | se la GPU non e' ancora su `vfio-pci`: elenca i processi che usano la GPU NVIDIA, chiede conferma, scrive `vfio` nel file di stato e riavvia. Se e' gia' su `vfio-pci`, non fa nulla |
| `release` | scrive `nvidia` nel file di stato, stacca le due funzioni da `vfio-pci`, azzera `driver_override`, ricarica i moduli nvidia e `snd_hda_intel`, riscansiona il bus PCI e rimette cardwire su `hybrid`. Non serve riavviare |

Lo script prepara solo il passaggio: il bind effettivo a `vfio-pci` lo fa
`gpu-vfio-boot.sh` al boot successivo, leggendo il file di stato
`/etc/gpu-vfio-mode`. Non ferma nessun servizio da solo: chiudi cio' che usa
la GPU (giochi, strumenti AI, container CUDA...) prima di `start`.

## Struttura del repository

```
install.sh                         un solo script: controllo, installazione, disinstallazione,
                                   gruppi IOMMU, scorciatoie per lo switch GPU, report (menu)
scripts/
  gpu-switch.sh                    switch GPU (start, release, status)
  gpu-vfio-boot.sh                 bind a vfio-pci al boot
systemd/
  gpu-vfio-boot.service
  cardwire-integrated-on-shutdown.service
config/
  cardwire.toml
  nvidia.conf
  gpu-vfio-mode
  gpu-passthrough.conf             indirizzi PCI della GPU (default)
examples/libvirt/                  esempio facoltativo di VM Windows 11
.github/ISSUE_TEMPLATE/            modello per le segnalazioni di compatibilita'
CHANGELOG.md
```

## Installazione

```
git clone https://github.com/iltype/gpu-passthrough-rog.git
cd gpu-passthrough-rog
./install.sh
```

`install.sh` apre un menu:

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

Ogni voce e' disponibile anche come comando, per esempio `./install.sh check`,
`./install.sh install`, `./install.sh uninstall` (`./install.sh --help` li
elenca tutti). Il menu e' in inglese.

Per vedere cosa farebbe l'installazione **senza cambiare nulla**, lancia
`./install.sh install --dry-run`: elenca ogni file come `NEW`, `REPLACE` o
`KEEP`, i servizi che abiliterebbe, e avvisa se sul sistema c'e' gia' un altro
impianto vfio al boot. Consigliato se il passthrough funziona gia' sul tuo
computer.

**Install** esegue prima il controllo di compatibilita' e, se qualcosa non
va, chiede prima di continuare (e, se trova un altro impianto vfio al boot,
chiede di nuovo con "no" come risposta predefinita). Poi copia ogni file nella destinazione
indicata sotto (tenendo backup numerati di cio' che sostituisce), installa
`gpu-switch.sh` nella tua home, scrive `/etc/gpu-passthrough.conf` con gli
indirizzi GPU rilevati, esegue `daemon-reload` e abilita i due servizi. Non
tocca un eventuale `/etc/gpu-vfio-mode` gia' presente. Riconosce anche il
bootloader (limine, GRUB, systemd-boot) e lo strumento per l'initramfs
(`limine-mkinitcpio`, `mkinitcpio`, `dracut`, `update-initramfs`), propone di
rigenerare l'initramfs e controlla se l'IOMMU e' attivo: se non lo e',
stampa il parametro kernel esatto e dove metterlo per il tuo bootloader (non
modifica mai da solo la configurazione del bootloader). Poi riavvia e passa
la GPU al passthrough con la voce 6 (o `~/gpu-switch.sh start`).

**Uninstall** rimuove tutto e ripristina i file di cui l'installazione aveva
fatto il backup. Se la GPU e' su `vfio-pci`, restituiscila prima all'host
(voce 7).

| File | Destinazione sul sistema |
|---|---|
| `scripts/gpu-switch.sh` | dove preferisci (es. `~/gpu-switch.sh`) |
| `scripts/gpu-vfio-boot.sh` | `/usr/local/bin/gpu-vfio-boot.sh` (chmod +x) |
| `systemd/*.service` | `/etc/systemd/system/` |
| `config/cardwire.toml` | `/etc/cardwire/cardwire.toml` |
| `config/nvidia.conf` | `/etc/modprobe.d/nvidia.conf` |
| `config/gpu-vfio-mode` | `/etc/gpu-vfio-mode` |
| `config/gpu-passthrough.conf` | `/etc/gpu-passthrough.conf` (modifica gli indirizzi) |

Per farlo a mano: copia i file come in tabella, poi
`sudo systemctl daemon-reload`, abilita i due servizi con
`systemctl enable` e riavvia.

## Facoltativo: VM Windows 11

Gli script non toccano nessuna VM. Se vuoi usare la GPU in una VM Windows 11
con libvirt, `examples/libvirt/` contiene una definizione funzionante (senza
UUID, MAC e percorsi personali) e i file extra necessari. Vedi
`examples/libvirt/README.md` (in inglese).

## Note

- **Modprobe**: `nvidia_drm modeset=1 fbdev=1`.
- **cardwire**: `experimental_nvidia_block = true`; un'unita' systemd forza
  `cardwire set integrated` prima di spegnimento/riavvio, per evitare che il
  compositor trattenga la GPU.
- **Aggiornamenti di cardwire**: cardwire e' un progetto giovane e in
  sviluppo attivo, con `experimental_nvidia_block` ancora sperimentale.
  Dopo ogni aggiornamento del pacchetto vanno ricontrollati `cardwire.toml`,
  l'unita' `cardwire-integrated-on-shutdown.service` e i comandi
  `cardwire set hybrid|integrated` usati negli script, perche' opzioni e
  comportamento potrebbero cambiare.
- **Bootloader**: lo switch non dipende dal bootloader. Il bind a
  `vfio-pci` lo fa un servizio systemd al boot, non parametri del kernel
  come `vfio-pci.ids=`, quindi dovrebbe funzionare uguale con GRUB,
  systemd-boot o altri. Il bootloader conta solo per due cose: il comando
  per rigenerare l'initramfs (qui `limine-mkinitcpio -P`; su sistemi GRUB
  di solito `mkinitcpio -P` o `dracut`, a seconda della distro) e, se
  l'IOMMU non e' gia' attivo sul tuo kernel, l'aggiunta del parametro IOMMU
  alla riga di comando del kernel (su GRUB in `/etc/default/grub` piu'
  `grub-mkconfig`). Verifica con `dmesg | grep -i iommu`.
- **Processi che bloccano il passaggio**: qualunque processo che usi la GPU
  (es. strumenti AI, container CUDA, `nvidia-powerd`) impedisce lo
  scaricamento del modulo `nvidia`. `gpu-switch.sh start` li elenca prima
  del riavvio.
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

## Licenza

Rilasciato con licenza MIT (vedi `LICENSE`): uso, copia e modifica liberi.

## Crediti

Se riusi o adatti questo lavoro, cita l'autore e linka il repository
originale: https://github.com/iltype/gpu-passthrough-rog
(La licenza MIT richiede gia' di mantenere l'avviso di copyright nelle copie
del codice.)
