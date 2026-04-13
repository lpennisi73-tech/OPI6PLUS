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
# Cloner le projet
git clone https://git-srv.bookworm.ddns.net/BOOKWORM/bookworm-sky1-kernel.git
cd bookworm-sky1-kernel

# Éditer votre UUID root dans board.conf
nano config/board.conf  # → ROOT_UUID="votre-uuid"

# Build complet kernel 6.19
./bookworm-sky1-build.sh --kernel 6.19-latest

# Installer
sudo ./install/install.sh --kernel-dir ~/build/sky1-kernel/linux-6.19

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
│       ├── 6.19-latest.conf      # ✅ Testé et fonctionnel
│       ├── 6.18-lts.conf         # Track LTS stable
│       └── 7.0-latest.conf       # Template pour kernel 7.0
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

### 1. Patch 0118 — Panthor ACE-Lite coherency API
**Fichier:** `drivers/gpu/drm/panthor/panthor_gpu.c`  
**Problème:** Le hunk #1 du patch 0118 échoue sur kernel 6.19 car
`panthor_gpu_coherency_set()` utilise encore l'ancienne API `ptdev->coherent`
au lieu de `ptdev->coherency_mode`.  
**Fix:** `patches/fixes/0118-panthor-coherency-fix.py`

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

---

## 🖥️ Tracks kernel disponibles

| Track | Base | Statut | Notes |
|-------|------|--------|-------|
| `6.19-latest` | Linux 6.19 | ✅ **Testé** | Premier boot confirmé |
| `6.18-lts` | Linux 6.18 | 🔄 Non testé | Track LTS — plus stable |
| `7.0-latest` | Linux 7.0 | 📋 Template | Prêt quand 7.0 disponible |

### Ajouter un nouveau track
```bash
# Copier un template existant
cp config/kernels/6.19-latest.conf config/kernels/7.0-latest.conf

# Éditer la version et les paramètres
nano config/kernels/7.0-latest.conf

# Builder
./bookworm-sky1-build.sh --kernel 7.0-latest
```

---

## ⚙️ Options avancées

```bash
# Builder avec sa propre config kernel de base
./bookworm-sky1-build.sh --kernel 6.19-latest \
    --base-config /boot/config-$(uname -r)

# Builder sans re-télécharger (sources déjà présentes)
./bookworm-sky1-build.sh --kernel 6.19-latest --skip-download

# Re-compiler seulement (patches et config déjà appliqués)
./bookworm-sky1-build.sh --kernel 6.19-latest \
    --skip-download --skip-patches --skip-config

# Build + installation automatique
./bookworm-sky1-build.sh --kernel 6.19-latest --install

# Voir ce qui serait fait sans exécuter
./bookworm-sky1-build.sh --kernel 6.19-latest --dry-run

# Utiliser plus de cores
./bookworm-sky1-build.sh --kernel 6.19-latest --jobs 16
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

## 📺 BOOKWORM

Ce projet fait partie de la chaîne **BOOKWORM** — rendre les technologies
open-source complexes accessibles à tous.

- 🎬 YouTube: [BOOKWORM Channel]
- 🐙 Gitea: [git-srv.bookworm.ddns.net](https://git-srv.bookworm.ddns.net)

---

*Premier boot Gentoo 6.19 Sky1 sur OrangePi 6 Plus — 13 Avril 2026* 🚀
