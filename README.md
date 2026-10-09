# BOOKWORM Sky1 Kernel Builder
### OrangePi 6 Plus — CIX CD8180 — Gentoo ARM64

[![Kernel](https://img.shields.io/badge/Kernel-6.19--sky1-blue)](https://github.com/Sky1-Linux/linux-sky1)
[![GPU](https://img.shields.io/badge/GPU-Mali--G720%20Panthor-green)](https://github.com/visorcraft/orange-pi-6-plus-gpu)
[![Board](https://img.shields.io/badge/Board-OrangePi%206%20Plus-orange)](http://www.orangepi.org)
[![Status](https://img.shields.io/badge/Status-Booting%20✓-brightgreen)]()

> Compilez un kernel Linux complet avec GPU Mali-G720 opérationnel sur OrangePi 6 Plus.  
> Premier kernel Gentoo 6.19 Sky1 au monde sur ce hardware — BOOKWORM/Kenny — Avril 2026.

---

## 🎯 Résultat

```
panthor 15000000.gpu: [drm] Mali-G720-Immortalis id 0xc870
panthor 15000000.gpu: [drm] shader_present=0x550555 l2_present=0x1
panthor 15000000.gpu: [drm] Using ACE-Lite bus coherency (Sky1)
panthor 15000000.gpu: [drm] CSF FW using interface v3.13.0
[drm] Initialized panthor 1.5.0 for 15000000.gpu on minor 1
```

---

## 📋 Prérequis

### Hardware
| Composant | Détail |
|-----------|--------|
| Board | Orange Pi 6 Plus |
| SoC | CIX CD8180 (Sky1) |
| CPU | 4× Cortex-A520 + 8× Cortex-A720 |
| RAM | 32 GB LPDDR5 |
| GPU | Mali-G720 Immortalis MC10 |
| Storage | NVMe SSD (slot PCIe X8) |



## ⚠️ Limitations connues

### ✅ RÉSOLU — CPU Fréquences (anciennement limitées par firmware)
| Cluster | Fréquences disponibles | Fréquence réelle |
|---------|----------------------|------------------|
| A520 (cpu0-3) | 800/1200/1500 MHz | max théorique 1.8GHz |
| A720 (cpu4-11) | 800/1800/**2600** MHz | **2.6GHz atteint et stable** |

Les OPP CPU boost sont fournies dynamiquement par le firmware SCMI (BIOS 1.4),
mais le firmware ne les active pas par défaut. Le patch local `9004-cpufreq-scmi-boost-param-from-init`
(issu de la PR #42 Sky1-Linux, patch 0149) force l'activation des OPP boost au
démarrage du driver `scmi-cpufreq` — plus besoin d'attendre un BIOS update CIX.
Validé stable sous charge compile complète (12 cores) : 2.6GHz maintenu sans
throttling jusqu'à ~73°C.

Appliqué sur tous les tracks (`6.18.14-lts`, `6.18-lts`, `6.19-latest`, `7.0-next`) via `PATCHES_EXTRA`.

### cpufreq — chargement et options automatisés
`scmi-cpufreq` est en `=m`. Le chargement au boot et l'activation du boost
(`scmi_cpufreq.boost=1`) sont maintenant gérés automatiquement par `install.sh`
à partir de `board.conf` (variables `MODULES_AUTOLOAD` et `MODPROBE_OPTIONS`) —
voir Bug #6 ci-dessous. Plus besoin de commande manuelle.

### USB-C — ports de données (corrigé sur 6.18.14-lts)
Avant correction (constaté sur `6.18.14-lts` et `6.19-latest`) :

- au boot, un `Oops` (NULL pointer dereference) dans `cdns_role_stop()` était déclenché
  par `rts5453` (contrôleur USB-PD) via `usb_role_switch_set_role()`
- les contrôleurs `cdns-usbssp` (`9010000`, `9080000`) échouaient avec
  `Device initialization failed with -6`

**Correctif appliqué sur `6.18.14-lts`** : option `USB_CDNSP_GADGET` forcée en built-in
(`FORCE_BUILTIN`) + patch local `9005-usb-cdns3-guard-null-role-in-cdns_role_stop`
(ignore un rôle USB pas encore initialisé au lieu de planter). Résultat : plus d'`Oops`,
`rts5453` termine son initialisation, les deux contrôleurs ont leur bus USB, et une clé
USB branchée via un hub USB 2 sur un port USB-C est détectée et montée (liaison du hub
à 480M). La voie SuperSpeed (USB 3) des ports USB-C n'a pas encore été testée.

Limites connues :
- un disque branché directement en USB-C n'a pas été détecté lors d'un test (cause non
  identifiée : alimentation du disque ou négociation Type-C) — à retester
- `6.19-latest` et `7.0-next` n'ont pas encore été retestés avec ce correctif
- l'alimentation de la carte par USB-C n'est pas concernée


### USB-C : stockage 10 Gbps (testé sur 6.18.14-lts)
- Port USB-C avec un **hub USB 3** : détecté en SuperSpeed (5 Gbps), clé USB lue à ~135 MB/s, stable plus de 15 minutes.
- Port USB-C avec un **boîtier disque ASMedia 10 Gbps** (Ugreen, 174c:235c, disque 2,5" auto-alimenté) : le partenaire Type-C est enregistré (`rts5453 ... role=host pwr=source orient=reverse`) mais **aucun périphérique n'apparaît**, même pas en USB 2. Désactiver la veille du contrôleur (`power/control=on`) ne change rien.
- Le même boîtier sur un port **USB-A** fonctionne en SuperSpeed+ 10 Gbps (~120 MB/s avec un disque mécanique) : le disque et le boîtier ne sont pas en cause.
- Piste : routage/orientation du PHY (`cix-usbdp-phy`, `sky1_udphy_init: typec dir=0x2`). À creuser (test de l'autre orientation et de l'autre port USB-C non encore faits).

### USB : contrôleur du port branché au KVM (bus USB 2, adresse 9290000)
- Après une bascule du KVM (cycle DP débranché/rebranché), le contrôleur xHCI peut ne plus voir clavier et souris. Contournement : ré-initialiser le contrôleur par son adresse (les numéros `xhci-hcd.N.auto` changent d'un boot à l'autre) :
  `echo xhci-hcd.<N>.auto > /sys/bus/platform/drivers/xhci-hcd/{unbind,bind}`
- Cause racine non encore identifiée.

### GNOME 49 / OpenRC
- Voir `scripts-addons/tips-gnome-49-openrc.md` et `scripts-addons/fix-gnome49-openrc.sh`.


### Logiciel
```bash
# Gentoo — outils requis
emerge dev-vcs/git sys-devel/bc app-arch/xz-utils \
       sys-devel/flex sys-devel/bison dev-lang/python
```

### Firmware Mali (requis pour le GPU)
```bash
# Télécharger depuis Sky1-Linux
git clone https://github.com/Sky1-Linux/sky1-firmware.git
mkdir -p /lib/firmware/arm/mali/arch12.8/
cp sky1-firmware/mali_csffw.bin /lib/firmware/arm/mali/arch12.8/
```

---

## 🚀 Utilisation rapide

```bash
# Cloner le projet (Gitea BOOKWORM — dépôt principal)
git clone https://git-srv.bookworm.ddns.net/BOOKWORM/bookworm-sky1-kernel.git
cd bookworm-sky1-kernel

# OU depuis GitHub (miroir public)
git clone https://github.com/lpennisi73-tech/OPI6PLUS.git
cd OPI6PLUS

# Éditer votre UUID root dans board.conf
nano config/board.conf  # → ROOT_UUID="votre-uuid"

# Build complet kernel 6.18.14 LTS (track recommandé — stable et fiable)
./bookworm-sky1-build.sh --kernel 6.18.14-lts

# Build complet avec installation

./bookworm-sky1-build.sh --kernel 6.18.14-lts --jobs 8 --install

# Installer
sudo ./install/install.sh --kernel-dir ~/build/sky1-kernel/linux-6.18.14

# Reboot
reboot

# Vérification post-boot
./diagnostics/check-system.sh
```

---

## 📁 Structure du projet

```
bookworm-sky1-kernel/
│
├── bookworm-sky1-build.sh        # Script principal — point d'entrée
│
├── config/
│   ├── board.conf                # Config hardware OrangePi 6 Plus
│   ├── inject-sky1-config.sh     # Injection options Sky1 dans config Gentoo
│   └── kernels/
│       ├── 6.18.14-lts.conf      # ✅ Track RECOMMANDÉ — LTS 6.18.14 (correctifs de sécurité)
│       ├── 6.18-lts.conf         # LTS 6.18.9 (version précédente)
│       ├── 6.19-latest.conf      # ✅ Testé et fonctionnel
│       └── 7.0-next.conf         # ✅ Testé — track next, partiellement upstream
│
├── patches/
│   ├── apply-sky1-patches.sh     # Application patches avec gestion conflits
│   └── fixes/                   # Corrections spécifiques découvertes
│       ├── 0118-panthor-coherency-fix.py    # Fix ACE-Lite coherency API
│       ├── pci-sky1-link-down-guard.py      # Fix SError slot PCIe vide
│       └── dts-disable-empty-pcie-slots.py  # Désactiver slots PCIe vides
│
├── firmware/
│   └── README.md                 # Instructions firmware Mali CSF
│
├── grub/
│   └── 06_sky1                   # Template entrée GRUB
│
├── dracut/
│   └── sky1.conf                 # Config initramfs dracut
│
├── install/
│   └── install.sh                # Installation kernel + GRUB + initramfs
│
├── diagnostics/
│   └── check-system.sh           # Vérification post-boot
│
└── logs/                         # Logs de compilation (gitignored)
```

---

## 🔧 Bugs corrigés

Ces corrections ont été découvertes lors du premier build Gentoo sur ce hardware
et sont appliquées automatiquement par le script.

### 1. Patch panthor ACE-Lite — hunk #1 de `panthor_gpu.c`
**Fichier:** `drivers/gpu/drm/panthor/panthor_gpu.c`  
**Problème:** le patch panthor « add ACE-Lite coherency » (numéro 0117 sur 6.18.x, 0118 sur 6.19)
modifie `panthor_gpu_coherency_set()`. Sur 6.18.x il s'applique tel quel. Sur 6.19, la base
utilise déjà `ptdev->coherency_mode` et le hunk #1 de `panthor_gpu.c` ne s'applique pas.  
**Fix:** géré dans `patches/apply-sky1-patches.sh`, qui reconnaît le patch par son nom : si le patch
s'applique tel quel, rien n'est corrigé ; sinon le hunk #1 est ignoré et les autres hunks sont
appliqués. Limite connue : sur 6.19, le bit `SHAREABLE_CACHE` du hunk n'est donc pas programmé
(le GPU démarre et fonctionne normalement).

### 2. PCIe Sky1 — SError sur slot vide
**Fichier:** `drivers/pci/controller/cadence/pci-sky1.c`  
**Problème:** `sky1_pcie_local_irq_handler()` tente d'accéder aux registres
PCIe même quand le lien est down (slot vide). Sur ARM64 cela génère un
SError fatal → kernel panic.  
**Fix:** `patches/fixes/pci-sky1-link-down-guard.py`

### 3. DTS — Slots PCIe vides activés
**Fichier:** `arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts`  
**Problème:** Le DTS active avec `status = "okay"` les slots PCIe X4 et X1_0
qui sont vides sur l'OrangePi 6 Plus standard (pas de WiFi monté).  
**Fix:** `patches/fixes/dts-disable-empty-pcie-slots.py`

### 4. Config — Options incompatibles avec patches Sky1
**Problème:** Une config Gentoo complète active `CONFIG_PCIE_CADENCE_PLAT=y`
qui entre en conflit avec la restructuration des drivers PCIe Cadence par
les patches Sky1 → erreur de compilation.  
**Fix:** Désactivation automatique dans `config/kernels/*.conf` via `FORCE_DISABLED`

### 5. Boot — Options critiques en module au lieu de built-in
**Problème:** `CONFIG_NVME_CORE=m`, `CONFIG_GPIO_CADENCE=m`, `CONFIG_TYPEC=m`
→ drivers non disponibles au boot → NVMe inaccessible → timeout initramfs.  
**Fix:** Forçage en `=y` via `FORCE_BUILTIN` dans `config/kernels/*.conf`

### 6. GRUB — `KERNEL_CMDLINE` de `board.conf` ignoré à l'install
**Fichier:** `install/install.sh`  
**Problème:** `install.sh` générait le `menuentry` GRUB avec les paramètres
kernel codés en dur dans le heredoc, sans jamais référencer la variable
`KERNEL_CMDLINE` de `board.conf`. Résultat : modifier `board.conf` (par exemple
pour ajouter `scmi_cpufreq.boost=1`) n'avait strictement aucun effet, même
après un `--install` complet, puisque GRUB réécrivait toujours la même ligne figée.  
**Fix:** Les deux `menuentry` (normal + recovery) référencent maintenant
`${KERNEL_CMDLINE}` — `board.conf` redevient la seule source de vérité pour
la ligne de commande kernel, cohérent avec le reste du pipeline.

De plus, `install.sh` génère désormais automatiquement `/etc/modules-load.d/`
et `/etc/modprobe.d/` à partir de deux nouvelles variables `board.conf` :
```bash
MODULES_AUTOLOAD="
scmi-cpufreq
"
MODPROBE_OPTIONS="
scmi_cpufreq:boost=1
"
```
Plus besoin de configuration manuelle post-install pour ces modules.

---

## 🖥️ Tracks kernel disponibles

| Track | Base | Statut | Notes |
|-------|------|--------|-------|
| `6.18.14-lts` | Linux 6.18.14 LTS | ✅ **Recommandé — fiable** | Dernière stable de la série LTS 6.18 testée (correctifs de sécurité et de bugs), boot stable |
| `6.18-lts` | Linux 6.18.9 LTS | ✅ Testé | Version précédente de la série LTS, conservée pour comparaison |
| `6.19-latest` | Linux 6.19 | ✅ Testé | Boot confirmé, GPU + boost 2.6GHz opérationnels |
| `7.0-next` | Linux 7.0 | 🧪 Testé — expérimental | Boot confirmé, Sky1 partiellement upstream |

👉 Pour un usage stable au quotidien, partez du track `6.18.14-lts` : la série LTS 6.18.x
reçoit des correctifs de sécurité réguliers, mieux vaut suivre le dernier point release. Les tracks
`6.19-latest` et `7.0-next` suivent de plus près l'upstream Sky1-Linux et sont
davantage destinés aux tests / contributions.

### Ajouter un nouveau track
```bash
# Copier un template existant
cp config/kernels/6.19-latest.conf config/kernels/8.0-next.conf

# Éditer la version et les paramètres
nano config/kernels/8.0-next.conf

# Builder
./bookworm-sky1-build.sh --kernel 8.0-next
```

---

## ⚙️ Options avancées

```bash
# Builder avec sa propre config kernel de base
./bookworm-sky1-build.sh --kernel 6.18-lts \
    --base-config /boot/config-$(uname -r)

# Builder sans re-télécharger (sources déjà présentes)
./bookworm-sky1-build.sh --kernel 6.18-lts --skip-download

# Re-compiler seulement (patches et config déjà appliqués)
./bookworm-sky1-build.sh --kernel 6.18-lts \
    --skip-download --skip-patches --skip-config

# Build + installation automatique
./bookworm-sky1-build.sh --kernel 6.18-lts --install

# Voir ce qui serait fait sans exécuter
./bookworm-sky1-build.sh --kernel 6.18-lts --dry-run

# Utiliser plus de cores
./bookworm-sky1-build.sh --kernel 6.18-lts --jobs 16
```

---

## 🔍 Diagnostic post-boot

```bash
# Vérification complète
./diagnostics/check-system.sh

# GPU uniquement
./diagnostics/check-system.sh --gpu

# CPU fréquences
./diagnostics/check-system.sh --cpu

# PCIe / NVMe / Ethernet
./diagnostics/check-system.sh --pcie
```

---

## 📊 Performances GPU

Testé sur OrangePi 6 Plus avec kernel 6.19-sky1 — Mesa 25.x — 1920×1080

| Test | Résultat |
|------|----------|
| glmark2-es2-drm | ~3079 score |
| Vulkan Buffer Fill (256MB) | 37.4 GB/s |
| Vulkan Buffer Copy (256MB) | 21.4 GB/s |
| kmscube | ~60 fps (vsync) |

---

## 🙏 Crédits

| Projet | Contribution |
|--------|-------------|
| [Sky1-Linux](https://github.com/Sky1-Linux/) | Patches kernel CIX CD8180 |
| [visorcraft/orange-pi-6-plus-gpu](https://github.com/visorcraft/orange-pi-6-plus-gpu) | Reverse engineering GPU power |
| [ARM Ltd](https://developer.arm.com) | Firmware Mali CSF |
| [CIX Technology](https://www.cixtech.com) | SoC CD8180 |

---


## Remerciements

Ce projet a été développé en collaboration avec Claude (Anthropic) 
qui a participé activement au développement du pipeline, 
aux corrections des patches kernel, aux fixes DTS et drivers, 
et à la validation du portage Linux 7.0 sur OrangePi 6 Plus.

Un grand merci à l'équipe Sky1-Linux pour leur travail 
de portage vers le mainline Linux !

## 📺 BOOKWORM

Ce projet fait partie de la chaîne **BOOKWORM** — rendre les technologies
open-source complexes accessibles à tous.

- 🎬 YouTube: [@kennyTech73]

---

*Premier boot Gentoo 6.19 Sky1 sur OrangePi 6 Plus — 13 Avril 2026* 🚀
*Premier boot Gentoo7.0 Sky1 sur OrangePi 6 Plus — 19 Avril 2026* 🚀
