#!/bin/bash
# =============================================================================
# check-system.sh — Diagnostic post-boot kernel Sky1 OrangePi 6 Plus
# BOOKWORM Sky1 Kernel Builder
#
# Usage: ./check-system.sh [--full] [--gpu] [--pcie] [--cpu]
#
# Vérifie:
#   - GPU Mali-G720 (Panthor)
#   - CPU fréquences (SCMI cpufreq)
#   - PCIe (NVMe, Ethernet)
#   - Mémoire
#   - Température
# =============================================================================

set -e

# --- Couleurs ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

CHECK_GPU=true
CHECK_CPU=true
CHECK_PCIE=true
CHECK_MEM=true
CHECK_TEMP=true
CHECK_FULL=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)     CHECK_FULL=true; shift ;;
        --gpu)      CHECK_GPU=true; CHECK_CPU=false; CHECK_PCIE=false; shift ;;
        --cpu)      CHECK_CPU=true; CHECK_GPU=false; CHECK_PCIE=false; shift ;;
        --pcie)     CHECK_PCIE=true; CHECK_GPU=false; CHECK_CPU=false; shift ;;
        *) shift ;;
    esac
done

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1"; }
info() { echo -e "  ${CYAN}→${NC}  $1"; }

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   BOOKWORM Sky1 System Diagnostic              ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# Kernel version
KVER=$(uname -r)
echo -e "Kernel : ${CYAN}${KVER}${NC}"
echo -e "Board  : ${CYAN}$(cat /sys/firmware/devicetree/base/model 2>/dev/null || echo 'inconnu')${NC}"
echo ""

# =============================================================================
# GPU — Mali-G720 Panthor
# =============================================================================
if $CHECK_GPU; then
    echo -e "${YELLOW}--- GPU Mali-G720 Panthor ---${NC}"

    # Driver chargé ?
    if dmesg | grep -q "Mali-G720-Immortalis"; then
        GPU_ID=$(dmesg | grep "Mali-G720-Immortalis" | head -1 | grep -o "id 0x[0-9a-f]*")
        ok "Mali-G720-Immortalis détecté ($GPU_ID)"
    else
        fail "Mali-G720 non détecté dans dmesg"
    fi

    # Render node
    if [[ -e /dev/dri/renderD128 ]]; then
        ok "Render node: /dev/dri/renderD128"
    else
        # Chercher autre renderD*
        RENDER=$(ls /dev/dri/renderD* 2>/dev/null | head -1)
        if [[ -n "$RENDER" ]]; then
            ok "Render node: $RENDER"
        else
            fail "Aucun render node /dev/dri/renderD* trouvé"
        fi
    fi

    # Card nodes
    CARDS=$(ls /dev/dri/card* 2>/dev/null | wc -l)
    if [[ $CARDS -gt 0 ]]; then
        ok "DRM card nodes: $CARDS trouvé(s) ($(ls /dev/dri/card* 2>/dev/null | tr '\n' ' '))"
    else
        warn "Aucun DRM card node trouvé"
    fi

    # ACE-Lite coherency
    if dmesg | grep -q "ACE-Lite bus coherency"; then
        ok "ACE-Lite bus coherency activé"
    else
        warn "ACE-Lite coherency non confirmé"
    fi

    # Firmware CSF
    if dmesg | grep -q "CSF FW"; then
        CSF_VER=$(dmesg | grep "CSF FW" | head -1 | grep -o "v[0-9.]*")
        ok "Firmware CSF chargé ($CSF_VER)"
    else
        fail "Firmware CSF non chargé — vérifier /lib/firmware/arm/mali/"
    fi

    # Panthor version
    if dmesg | grep -q "Initialized panthor"; then
        PANTHOR_VER=$(dmesg | grep "Initialized panthor" | grep -o "panthor [0-9.]*" | head -1)
        ok "Driver $PANTHOR_VER initialisé"
    fi

    # Test Vulkan si disponible
    if command -v vulkaninfo &>/dev/null; then
        VULKAN_DEV=$(vulkaninfo --summary 2>/dev/null | grep deviceName | head -1 | awk '{print $3}')
        if [[ -n "$VULKAN_DEV" ]]; then
            ok "Vulkan: $VULKAN_DEV"
        else
            warn "Vulkan: vulkaninfo disponible mais pas de device"
        fi
    else
        info "vulkaninfo non installé (optionnel)"
    fi

    echo ""
fi

# =============================================================================
# CPU — Fréquences SCMI
# =============================================================================
if $CHECK_CPU; then
    echo -e "${YELLOW}--- CPU CIX CD8180 (Sky1) ---${NC}"

    # Nombre de CPUs
    CPU_COUNT=$(nproc)
    ok "CPUs détectés: $CPU_COUNT (4× A520 + 8× A720)"

    # Fréquences via sysfs
    CPU_FREQ_OK=false
    for cpu in /sys/devices/system/cpu/cpu{0,4}/cpufreq/scaling_cur_freq; do
        if [[ -f "$cpu" ]]; then
            FREQ=$(cat "$cpu" 2>/dev/null)
            if [[ -n "$FREQ" && "$FREQ" -gt 0 ]]; then
                CPU_NUM=$(echo "$cpu" | grep -o 'cpu[0-9]*' | head -1)
                FREQ_MHZ=$((FREQ / 1000))
                ok "cpufreq $CPU_NUM: ${FREQ_MHZ} MHz"
                CPU_FREQ_OK=true
            fi
        fi
    done

    if ! $CPU_FREQ_OK; then
        warn "cpufreq non disponible via sysfs"
        info "Vérifier: CONFIG_ARM_SCMI_CPUFREQ=y"
        info "Modules disponibles:"
        find /lib/modules/$(uname -r)/ -name "*scmi*cpufreq*" -o -name "*cpufreq*scmi*" 2>/dev/null | \
            while read f; do info "  $f"; done
    fi

    # Gouverneur
    GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
    if [[ "$GOV" != "N/A" ]]; then
        ok "Gouverneur: $GOV"
    else
        warn "Gouverneur cpufreq non disponible"
    fi

    echo ""
fi

# =============================================================================
# PCIe — NVMe + Ethernet
# =============================================================================
if $CHECK_PCIE; then
    echo -e "${YELLOW}--- PCIe / Storage / Network ---${NC}"

    # NVMe
    if ls /dev/nvme* &>/dev/null; then
        NVME_DEV=$(ls /dev/nvme*n* 2>/dev/null | head -1)
        NVME_SIZE=$(lsblk -d -o SIZE "$NVME_DEV" 2>/dev/null | tail -1 | tr -d ' ')
        ok "NVMe détecté: $NVME_DEV ($NVME_SIZE)"
    else
        fail "Aucun NVMe détecté — vérifier PCIe Sky1"
    fi

    # Ethernet RTL8126
    ETH_COUNT=$(ip link show 2>/dev/null | grep -c "enP\|enp" || echo 0)
    if [[ $ETH_COUNT -ge 2 ]]; then
        ok "Ethernet: $ETH_COUNT interface(s) RTL8126 détectée(s)"
        ip link show 2>/dev/null | grep -E "enP|enp" | awk '{print $2}' | \
            while read iface; do
                STATE=$(cat /sys/class/net/${iface%:}/operstate 2>/dev/null)
                info "$iface — $STATE"
            done
    else
        warn "Ethernet: moins de 2 interfaces détectées"
    fi

    # Slots PCIe vides — vérifier pas de SError
    if dmesg | grep -q "Asynchronous SError Interrupt"; then
        fail "SError détecté dans dmesg — slot PCIe vide non désactivé ?"
        info "Vérifier: patches/fixes/dts-disable-empty-pcie-slots.py"
    else
        ok "Pas de SError PCIe"
    fi

    echo ""
fi

# =============================================================================
# Mémoire
# =============================================================================
if $CHECK_MEM; then
    echo -e "${YELLOW}--- Mémoire ---${NC}"
    MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEM_GB=$((MEM_TOTAL / 1024 / 1024))
    ok "RAM totale: ${MEM_GB} GB ($(( MEM_TOTAL / 1024 )) MB)"

    MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    MEM_AVAIL_GB=$(echo "scale=1; $MEM_AVAIL / 1024 / 1024" | bc 2>/dev/null || echo "?")
    info "RAM disponible: ~${MEM_AVAIL_GB} GB"
    echo ""
fi

# =============================================================================
# Température
# =============================================================================
if $CHECK_TEMP; then
    echo -e "${YELLOW}--- Températures ---${NC}"
    TEMP_FOUND=false

    for zone in /sys/class/thermal/thermal_zone*/; do
        TYPE=$(cat "${zone}type" 2>/dev/null)
        TEMP=$(cat "${zone}temp" 2>/dev/null)
        if [[ -n "$TEMP" && "$TEMP" != "0" ]]; then
            TEMP_C=$((TEMP / 1000))
            if [[ $TEMP_C -gt 80 ]]; then
                warn "$TYPE: ${TEMP_C}°C ← CHAUD !"
            else
                ok "$TYPE: ${TEMP_C}°C"
            fi
            TEMP_FOUND=true
        fi
    done

    $TEMP_FOUND || warn "Capteurs de température non disponibles"
    echo ""
fi

# =============================================================================
# RÉSUMÉ
# =============================================================================
echo -e "${BLUE}=== Résumé ===${NC}"
ERRORS=$(dmesg | grep -c "error\|Error\|ERROR" 2>/dev/null || echo "?")
WARNINGS=$(dmesg | grep -c "warning\|Warning\|WARN" 2>/dev/null || echo "?")
info "Kernel messages: $ERRORS erreurs, $WARNINGS warnings"
echo ""
echo -e "${CYAN}Commandes utiles:${NC}"
echo "  dmesg | grep panthor     — Status GPU"
echo "  dmesg | grep sky1-pcie   — Status PCIe"
echo "  cat /proc/cpuinfo        — Info CPU"
echo "  lspci -v                 — Périphériques PCIe"
echo "  vulkaninfo --summary     — Test Vulkan GPU"
