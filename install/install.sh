#!/bin/bash
# =============================================================================
# install.sh — Installation kernel Sky1 OrangePi 6 Plus
# BOOKWORM Sky1 Kernel Builder
#
# Usage: ./install.sh [--kernel-dir <path>] [--no-grub] [--no-initramfs]
#
# Ce script installe:
#   1. Le kernel Image → /boot/vmlinuz-X.Y-sky1-custom
#   2. Le DTB         → /boot/dtb/sky1-orangepi-6-plus.dtb
#   3. Les modules    → /lib/modules/X.Y.0-gentoo-dist/
#   4. Le firmware    → /lib/firmware/
#   5. L'initramfs    → /boot/initrd.img-X.Y.0-sky1-custom
#   6. L'entrée GRUB  → /etc/grub.d/06_sky1
# =============================================================================

set -e

# --- Couleurs ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# --- Defaults ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KERNEL_BUILD_DIR=""
DO_GRUB=true
DO_INITRAMFS=true
DO_FIRMWARE=true

# --- Aide ---
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --kernel-dir <path>   Répertoire build kernel (défaut: auto-détecté)"
    echo "  --no-grub             Ne pas mettre à jour GRUB"
    echo "  --no-initramfs        Ne pas recréer l'initramfs"
    echo "  --no-firmware         Ne pas installer le firmware"
    echo "  --help                Afficher cette aide"
    exit 0
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel-dir) KERNEL_BUILD_DIR="$2"; shift 2 ;;
        --no-grub) DO_GRUB=false; shift ;;
        --no-initramfs) DO_INITRAMFS=false; shift ;;
        --no-firmware) DO_FIRMWARE=false; shift ;;
        --help) usage ;;
        *) echo "Option inconnue: $1"; usage ;;
    esac
done

# --- Charger la config ---
source "$PROJECT_DIR/config/board.conf" 2>/dev/null || {
    echo -e "${RED}ERREUR: board.conf introuvable${NC}"
    exit 1
}

# Trouver le fichier kernel-version actif
KERNEL_CONF=$(ls "$PROJECT_DIR/config/kernels/"*.conf 2>/dev/null | head -1)
[[ -z "$KERNEL_CONF" ]] && { echo -e "${RED}ERREUR: Aucun fichier kernel .conf trouvé${NC}"; exit 1; }

# Charger le kernel actif (chercher le plus récent testé)
for conf in "$PROJECT_DIR/config/kernels/"*.conf; do
    source "$conf"
    [[ "$TESTED" == "yes" ]] && KERNEL_CONF="$conf" && break
done
source "$KERNEL_CONF"

# --- Auto-détecter le répertoire build ---
if [[ -z "$KERNEL_BUILD_DIR" ]]; then
    # Chercher dans les emplacements courants
    for candidate in \
        "/root/build/sky1-kernel/linux-${KERNEL_VERSION}" \
        "/usr/src/linux-${KERNEL_VERSION}" \
        "/usr/src/linux"; do
        if [[ -f "$candidate/arch/arm64/boot/Image" ]]; then
            KERNEL_BUILD_DIR="$candidate"
            break
        fi
    done
fi

[[ -z "$KERNEL_BUILD_DIR" ]] && {
    echo -e "${RED}ERREUR: Répertoire build kernel non trouvé${NC}"
    echo "  Spécifie avec: --kernel-dir /path/to/linux-${KERNEL_VERSION}"
    exit 1
}

# =============================================================================
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   BOOKWORM Sky1 Kernel Installer               ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""
echo -e "Board        : ${CYAN}${BOARD_NAME}${NC}"
echo -e "Kernel       : ${CYAN}${KERNEL_FULL_VERSION}${KERNEL_LOCALVERSION}${NC}"
echo -e "Build dir    : ${CYAN}${KERNEL_BUILD_DIR}${NC}"
echo -e "GRUB update  : ${CYAN}${DO_GRUB}${NC}"
echo -e "Initramfs    : ${CYAN}${DO_INITRAMFS}${NC}"
echo ""

# Vérification root
[[ $EUID -ne 0 ]] && { echo -e "${RED}ERREUR: Lance en root (sudo)${NC}"; exit 1; }

# =============================================================================
# ÉTAPE 1 — Kernel Image
# =============================================================================
echo -e "${YELLOW}--- Étape 1: Installation kernel ---${NC}"

KERNEL_SRC="$KERNEL_BUILD_DIR/arch/arm64/boot/Image"
KERNEL_DST="/boot/vmlinuz-${KERNEL_VERSION}-sky1-custom"

[[ ! -f "$KERNEL_SRC" ]] && {
    echo -e "${RED}ERREUR: $KERNEL_SRC introuvable — compile d'abord !${NC}"
    exit 1
}

cp -v "$KERNEL_SRC" "$KERNEL_DST"
echo -e "${GREEN}OK${NC} Kernel installé: $KERNEL_DST ($(du -h $KERNEL_DST | cut -f1))"

# =============================================================================
# ÉTAPE 2 — DTB
# =============================================================================
echo ""
echo -e "${YELLOW}--- Étape 2: Installation DTB ---${NC}"

DTB_SRC="$KERNEL_BUILD_DIR/arch/arm64/boot/dts/cix/${DTB_NAME}"
mkdir -p /boot/dtb

[[ ! -f "$DTB_SRC" ]] && {
    echo -e "${RED}ERREUR: $DTB_SRC introuvable${NC}"
    exit 1
}

cp -v "$DTB_SRC" "$DTB_PATH"
echo -e "${GREEN}OK${NC} DTB installé: $DTB_PATH ($(du -h $DTB_PATH | cut -f1))"

# =============================================================================
# ÉTAPE 3 — Modules
# =============================================================================
echo ""
echo -e "${YELLOW}--- Étape 3: Installation modules ---${NC}"

cd "$KERNEL_BUILD_DIR"
make ARCH=arm64 modules_install
echo -e "${GREEN}OK${NC} Modules installés dans /lib/modules/"

# =============================================================================
# ÉTAPE 4 — Firmware Mali
# =============================================================================
if $DO_FIRMWARE; then
    echo ""
    echo -e "${YELLOW}--- Étape 4: Firmware ---${NC}"

    FIRMWARE_SRC="$PROJECT_DIR/firmware"
    MALI_FW="/lib/firmware/arm/mali/arch12.8/mali_csffw.bin"

    if [[ -f "$MALI_FW" ]]; then
        echo -e "${GREEN}OK${NC} Firmware Mali déjà présent: $MALI_FW"
    else
        echo -e "${YELLOW}WARN${NC} Firmware Mali absent: $MALI_FW"
        echo "  → Télécharge depuis: https://github.com/Sky1-Linux/sky1-firmware"
        echo "  → Place dans: /lib/firmware/arm/mali/arch12.8/"
    fi
fi

# =============================================================================
# ÉTAPE 5 — Dracut config + Initramfs
# =============================================================================
if $DO_INITRAMFS; then
    echo ""
    echo -e "${YELLOW}--- Étape 5: Configuration dracut + Initramfs ---${NC}"

    # Installer la config dracut Sky1
    mkdir -p /etc/dracut.conf.d
    cp -v "$PROJECT_DIR/dracut/sky1.conf" /etc/dracut.conf.d/sky1.conf
    echo -e "${GREEN}OK${NC} Config dracut installée"

    # Créer l'initramfs
    INITRD="/boot/initrd.img-${KERNEL_FULL_VERSION}.0-sky1-custom"
    KVER="${KERNEL_FULL_VERSION}-gentoo-dist"

    echo "Création initramfs pour $KVER ..."
    dracut --force --kver "$KVER" "$INITRD"
    echo -e "${GREEN}OK${NC} Initramfs créé: $INITRD ($(du -h $INITRD | cut -f1))"
fi

# =============================================================================
# ÉTAPE 6 — GRUB
# =============================================================================
if $DO_GRUB; then
    echo ""
    echo -e "${YELLOW}--- Étape 6: Configuration GRUB ---${NC}"

    GRUB_TEMPLATE="$PROJECT_DIR/grub/06_sky1"
    GRUB_DST="/etc/grub.d/06_sky1"

    # Remplacer les variables dans le template
    sed \
        -e "s|@@KERNEL_VERSION@@|${KERNEL_VERSION}|g" \
        -e "s|@@KERNEL_FULL_VERSION@@|${KERNEL_FULL_VERSION}|g" \
        -e "s|@@ROOT_UUID@@|${ROOT_UUID}|g" \
        -e "s|@@BOARD_NAME@@|${BOARD_NAME}|g" \
        "$GRUB_TEMPLATE" > "$GRUB_DST"

    chmod +x "$GRUB_DST"
    echo -e "${GREEN}OK${NC} Entrée GRUB installée: $GRUB_DST"

    # Régénérer grub.cfg
    grub-mkconfig -o /boot/grub/grub.cfg
    echo -e "${GREEN}OK${NC} grub.cfg régénéré"
fi

# =============================================================================
# RÉSUMÉ FINAL
# =============================================================================
echo ""
echo -e "${BLUE}=== Installation terminée ===${NC}"
echo ""
echo -e "  Kernel  : ${GREEN}/boot/vmlinuz-${KERNEL_VERSION}-sky1-custom${NC}"
echo -e "  DTB     : ${GREEN}${DTB_PATH}${NC}"
echo -e "  Initrd  : ${GREEN}/boot/initrd.img-${KERNEL_FULL_VERSION}.0-sky1-custom${NC}"
echo -e "  Modules : ${GREEN}/lib/modules/${KERNEL_FULL_VERSION}-gentoo-dist/${NC}"
echo ""
echo -e "${YELLOW}Prochaine étape:${NC}"
echo "  reboot"
echo ""
echo -e "${CYAN}Post-boot verification:${NC}"
echo "  ../diagnostics/check-system.sh"
