#!/bin/bash
# =============================================================================
# install.sh — Installation kernel Sky1 OrangePi 6 Plus
# BOOKWORM Sky1 Kernel Builder v1.2
#
# Usage: ./install.sh [--kernel-dir <path>] [--no-grub] [--no-initramfs]
# =============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KERNEL_BUILD_DIR=""
DO_GRUB=true
DO_INITRAMFS=true
DO_FIRMWARE=true

usage() {
    echo "Usage: $0 [options]"
    echo "  --kernel-dir <path>   Repertoire build kernel"
    echo "  --no-grub             Ne pas mettre a jour GRUB"
    echo "  --no-initramfs        Ne pas recreer l'initramfs"
    echo "  --no-firmware         Ne pas installer le firmware"
    exit 0
}

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
    echo -e "${RED}ERREUR: board.conf introuvable${NC}"; exit 1
}

# Utiliser KERNEL_FULL_VERSION passe en environnement depuis bookworm-sky1-build.sh
# sinon chercher le premier .conf teste
if [[ -z "$KERNEL_FULL_VERSION" ]]; then
    for conf in "$PROJECT_DIR/config/kernels/"*.conf; do
        source "$conf"
        [[ "$TESTED" == "yes" ]] && break
    done
fi

# Auto-detecter le repertoire build
if [[ -z "$KERNEL_BUILD_DIR" ]]; then
    for candidate in \
        "/root/build/sky1-kernel/linux-${KERNEL_FULL_VERSION}" \
        "/root/build/sky1-kernel/linux-${KERNEL_VERSION}" \
        "/usr/src/linux-${KERNEL_FULL_VERSION}" \
        "/usr/src/linux"; do
        if [[ -f "$candidate/arch/arm64/boot/Image" ]]; then
            KERNEL_BUILD_DIR="$candidate"
            break
        fi
    done
fi

[[ -z "$KERNEL_BUILD_DIR" ]] && {
    echo -e "${RED}ERREUR: Repertoire build kernel non trouve${NC}"
    echo "  Specifie avec: --kernel-dir /path/to/linux-${KERNEL_FULL_VERSION}"
    exit 1
}

# =============================================================================
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   BOOKWORM Sky1 Kernel Installer v1.2          ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""
echo -e "Board        : ${CYAN}${BOARD_NAME}${NC}"
echo -e "Kernel       : ${CYAN}${KERNEL_FULL_VERSION}${KERNEL_LOCALVERSION}${NC}"
echo -e "Build dir    : ${CYAN}${KERNEL_BUILD_DIR}${NC}"
echo ""

[[ $EUID -ne 0 ]] && { echo -e "${RED}ERREUR: Lance en root (sudo)${NC}"; exit 1; }

# =============================================================================
# ETAPE 1 — Kernel Image
# =============================================================================
echo -e "${YELLOW}--- Etape 1: Installation kernel ---${NC}"

KERNEL_SRC="$KERNEL_BUILD_DIR/arch/arm64/boot/Image"
KERNEL_DST="/boot/vmlinuz-${KERNEL_FULL_VERSION}-sky1-custom"

[[ ! -f "$KERNEL_SRC" ]] && {
    echo -e "${RED}ERREUR: $KERNEL_SRC introuvable — compile d'abord !${NC}"; exit 1
}

cp -v "$KERNEL_SRC" "$KERNEL_DST"
echo -e "${GREEN}OK${NC} Kernel: $KERNEL_DST ($(du -h $KERNEL_DST | cut -f1))"

# =============================================================================
# ETAPE 2 — DTB
# =============================================================================
echo ""
echo -e "${YELLOW}--- Etape 2: Installation DTB ---${NC}"

DTB_SRC="$KERNEL_BUILD_DIR/arch/arm64/boot/dts/cix/${DTB_NAME}"
mkdir -p /boot/dtb

[[ ! -f "$DTB_SRC" ]] && { echo -e "${RED}ERREUR: $DTB_SRC introuvable${NC}"; exit 1; }

cp -v "$DTB_SRC" "$DTB_PATH"
echo -e "${GREEN}OK${NC} DTB: $DTB_PATH ($(du -h $DTB_PATH | cut -f1))"

# =============================================================================
# ETAPE 3 — Modules
# =============================================================================
echo ""
echo -e "${YELLOW}--- Etape 3: Installation modules ---${NC}"

cd "$KERNEL_BUILD_DIR"
make ARCH=arm64 modules_install
echo -e "${GREEN}OK${NC} Modules installes dans /lib/modules/"

# =============================================================================
# ETAPE 4 — Firmware Mali
# =============================================================================
if $DO_FIRMWARE; then
    echo ""
    echo -e "${YELLOW}--- Etape 4: Firmware ---${NC}"

    FIRMWARE_SRC="$PROJECT_DIR/firmware"
    MALI_FW="/lib/firmware/arm/mali/arch12.8/mali_csffw.bin"
    MALI_FW_SYMLINK="/lib/firmware/mali_csffw.bin"

    if [[ -f "$FIRMWARE_SRC/arm/mali/arch12.8/mali_csffw.bin" ]]; then
        mkdir -p /lib/firmware/arm/mali/arch12.8/
        cp -r "$FIRMWARE_SRC/arm/" /lib/firmware/
        echo -e "${GREEN}OK${NC} Firmware Mali installe depuis le repo"
    elif [[ -f "$MALI_FW" ]]; then
        echo -e "${GREEN}OK${NC} Firmware Mali deja present: $MALI_FW"
    else
        echo -e "${YELLOW}WARN${NC} Firmware Mali absent"
        echo "  Telecharge depuis: https://github.com/Sky1-Linux/sky1-firmware"
    fi

    if [[ -f "$MALI_FW" && ! -f "$MALI_FW_SYMLINK" ]]; then
        ln -sf "$MALI_FW" "$MALI_FW_SYMLINK"
        echo -e "${GREEN}OK${NC} Symlink Mali cree"
    fi
fi

# =============================================================================
# ETAPE 5 — Dracut config + Initramfs
# =============================================================================
if $DO_INITRAMFS; then
    echo ""
    echo -e "${YELLOW}--- Etape 5: Initramfs ---${NC}"

    mkdir -p /etc/dracut.conf.d
    cp -v "$PROJECT_DIR/dracut/sky1.conf" /etc/dracut.conf.d/sky1.conf
    echo -e "${GREEN}OK${NC} Config dracut installee"

    # Detecter le vrai kver depuis /lib/modules
    # Ex: KERNEL_FULL_VERSION=7.0 → kver=7.0.0-gentoo-dist
    KVER=$(ls /lib/modules/ | grep "^${KERNEL_FULL_VERSION}" | grep "gentoo-dist" | head -1)
    if [[ -z "$KVER" ]]; then
        KVER="${KERNEL_FULL_VERSION}-gentoo-dist"
    fi
    INITRD="/boot/initrd.img-${KVER}-sky1-custom"

    echo "Creation initramfs pour $KVER ..."
    dracut --force --kver "$KVER" "$INITRD"
    echo -e "${GREEN}OK${NC} Initramfs: $INITRD ($(du -h $INITRD | cut -f1))"
fi

# =============================================================================
# ETAPE 6 — GRUB
# =============================================================================
if $DO_GRUB; then
    echo ""
    echo -e "${YELLOW}--- Etape 6: Configuration GRUB ---${NC}"

    # Determiner le fichier GRUB selon le track
    # 6.19-latest → 06_sky1 | autres → 07_sky1_KFULLVERSION
    if [[ "$SKY1_TRACK" == "latest" && "$KERNEL_VERSION" == "6.19" ]]; then
        GRUB_SCRIPT="/etc/grub.d/06_sky1"
    else
        TRACK_SAFE=$(echo "${KERNEL_FULL_VERSION}" | tr '.' '_')
        GRUB_SCRIPT="/etc/grub.d/07_sky1_${TRACK_SAFE}"
    fi

    # Generer l'entree GRUB avec TOUS les parametres corrects
    cat > "$GRUB_SCRIPT" << GRUBEOF
#!/bin/sh
# BOOKWORM Sky1 — Kernel ${KERNEL_FULL_VERSION} track ${SKY1_TRACK}
# Genere automatiquement par install.sh v1.2
exec tail -n +3 \$0

menuentry "Sky1 ${BOARD_NAME} - ${KERNEL_FULL_VERSION} ${SKY1_TRACK} (GPU+NPU)" \\
    --class debian --class gnu-linux --class gnu --class os {

    load_video
    insmod gzio
    insmod part_gpt
    insmod ext2

    search --no-floppy --fs-uuid --set=root ${ROOT_UUID}

    echo "Loading Sky1 Linux ${KERNEL_FULL_VERSION}-sky1-custom ..."
    linux /boot/vmlinuz-${KERNEL_FULL_VERSION}-sky1-custom \\
        root=UUID=${ROOT_UUID} ro \\
        loglevel=7 \\
        console=tty0 \\
        console=ttyAMA2,115200 \\
        efi=noruntime \\
        acpi=off \\
        clk_ignore_unused \\
        linlon_dp.enable_fb=1 \\
        linlon_dp.enable_render=0 \\
        fbcon=map:01111111 \\
        plymouth.enable=0 \\
        rd.plymouth=0 \\
        rootwait

    echo "Loading initial ramdisk ..."
    initrd /boot/initrd.img-${KERNEL_FULL_VERSION}.0-sky1-custom

    echo "Loading device tree ..."
    devicetree ${DTB_PATH}
}

menuentry "Sky1 ${BOARD_NAME} - ${KERNEL_FULL_VERSION} ${SKY1_TRACK} (Recovery)" \\
    --class debian --class gnu-linux --class gnu --class os {

    load_video
    insmod gzio
    insmod part_gpt
    insmod ext2

    search --no-floppy --fs-uuid --set=root ${ROOT_UUID}

    echo "Loading Sky1 Linux ${KERNEL_FULL_VERSION} Recovery ..."
    linux /boot/vmlinuz-${KERNEL_FULL_VERSION}-sky1-custom \\
        root=UUID=${ROOT_UUID} ro \\
        loglevel=8 \\
        console=tty0 \\
        console=ttyAMA2,115200 \\
        efi=noruntime \\
        acpi=off \\
        clk_ignore_unused \\
        plymouth.enable=0 \\
        rd.plymouth=0 \\
        systemd.unit=rescue.target \\
        rootwait

    echo "Loading initial ramdisk ..."
    initrd /boot/initrd.img-${KERNEL_FULL_VERSION}.0-sky1-custom

    echo "Loading device tree ..."
    devicetree ${DTB_PATH}
}
GRUBEOF

    chmod +x "$GRUB_SCRIPT"
    echo -e "${GREEN}OK${NC} GRUB script: $GRUB_SCRIPT"

    # S'assurer que GRUB_DEFAULT=0 est actif
    if ! grep -q "^GRUB_DEFAULT=0" /etc/default/grub; then
        sed -i 's/^#\?GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
        echo -e "${GREEN}OK${NC} GRUB_DEFAULT=0 configure"
    fi

    grub-mkconfig -o /boot/grub/grub.cfg
    echo -e "${GREEN}OK${NC} grub.cfg regenere"
fi

# =============================================================================
# RESUME FINAL
# =============================================================================
echo ""
echo -e "${BLUE}=== Installation terminee ===${NC}"
echo ""
echo -e "  Kernel  : ${GREEN}/boot/vmlinuz-${KERNEL_FULL_VERSION}-sky1-custom${NC}"
echo -e "  DTB     : ${GREEN}${DTB_PATH}${NC}"
echo -e "  Initrd  : ${GREEN}/boot/initrd.img-${KERNEL_FULL_VERSION}.0-sky1-custom${NC}"
echo -e "  GRUB    : ${GREEN}${GRUB_SCRIPT}${NC}"
echo ""
echo -e "${YELLOW}Prochaine etape:${NC}"
echo "  reboot"
echo ""
echo -e "${CYAN}Post-boot:${NC}"
echo "  ../diagnostics/check-system.sh"
