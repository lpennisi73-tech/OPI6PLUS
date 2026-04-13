#!/bin/bash
# =============================================================================
# check-system.sh — Diagnostic post-boot kernel Sky1 OrangePi 6 Plus
# BOOKWORM Sky1 Kernel Builder v1.1
#
# Usage: ./check-system.sh [--gpu] [--cpu] [--pcie] [--temp]
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

CHECK_GPU=true; CHECK_CPU=true; CHECK_PCIE=true; CHECK_MEM=true; CHECK_TEMP=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpu)  CHECK_GPU=true;  CHECK_CPU=false; CHECK_PCIE=false; CHECK_MEM=false; CHECK_TEMP=false; shift ;;
        --cpu)  CHECK_CPU=true;  CHECK_GPU=false; CHECK_PCIE=false; CHECK_MEM=false; CHECK_TEMP=false; shift ;;
        --pcie) CHECK_PCIE=true; CHECK_GPU=false; CHECK_CPU=false;  CHECK_MEM=false; CHECK_TEMP=false; shift ;;
        --temp) CHECK_TEMP=true; CHECK_GPU=false; CHECK_CPU=false;  CHECK_PCIE=false; CHECK_MEM=false; shift ;;
        *) shift ;;
    esac
done

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1"; }
info() { echo -e "  ${CYAN}→${NC}  $1"; }

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   BOOKWORM Sky1 System Diagnostic v1.1         ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""
echo -e "Kernel : ${CYAN}$(uname -r)${NC}"
echo -e "Board  : ${CYAN}$(cat /sys/firmware/devicetree/base/model 2>/dev/null | tr -d '\0' || echo 'inconnu')${NC}"
echo ""

# =============================================================================
# GPU
# =============================================================================
if $CHECK_GPU; then
    echo -e "${YELLOW}--- GPU Mali-G720 Panthor ---${NC}"
    dmesg | grep -q "Mali-G720-Immortalis" && \
        ok "Mali-G720-Immortalis détecté ($(dmesg | grep 'Mali-G720-Immortalis' | grep -o 'id 0x[0-9a-f]*' | head -1))" || \
        fail "Mali-G720 non détecté"
    RENDER=$(ls /dev/dri/renderD* 2>/dev/null | head -1)
    [[ -n "$RENDER" ]] && ok "Render node: $RENDER" || fail "Aucun render node"
    CARDS=$(ls /dev/dri/card* 2>/dev/null | wc -l)
    [[ $CARDS -gt 0 ]] && ok "DRM cards: $CARDS ($(ls /dev/dri/card* 2>/dev/null | tr '\n' ' '))"
    dmesg | grep -q "ACE-Lite bus coherency" && ok "ACE-Lite bus coherency" || warn "ACE-Lite non confirmé"
    dmesg | grep -q "CSF FW" && ok "Firmware CSF: $(dmesg | grep 'CSF FW' | grep -o 'v[0-9.]*' | head -1)" || \
        fail "Firmware CSF absent — vérifier /lib/firmware/arm/mali/"
    dmesg | grep -q "Initialized panthor" && \
        ok "$(dmesg | grep 'Initialized panthor' | grep -o 'panthor [0-9.]*' | head -1) initialisé"
    command -v vulkaninfo &>/dev/null && \
        ok "Vulkan: $(vulkaninfo --summary 2>/dev/null | grep deviceName | head -1 | awk '{print $3}')" || \
        info "vulkaninfo non installé (optionnel)"
    echo ""
fi

# =============================================================================
# CPU
# =============================================================================
if $CHECK_CPU; then
    echo -e "${YELLOW}--- CPU CIX CD8180 (Sky1) ---${NC}"
    ok "CPUs: $(nproc) (4× Cortex-A520 + 8× Cortex-A720)"
    CPU_OK=false
    for cpu in 0 4; do
        F="/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_cur_freq"
        [[ -f "$F" ]] && FREQ=$(cat "$F") && [[ $FREQ -gt 0 ]] && {
            GOV=$(cat /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor 2>/dev/null)
            ok "cpu${cpu}: $((FREQ/1000)) MHz ($GOV)"
            CPU_OK=true
        }
    done
    $CPU_OK || { warn "cpufreq non disponible"; info "modprobe scmi-cpufreq"; }
    echo ""
fi

# =============================================================================
# PCIe / Storage / Network
# =============================================================================
if $CHECK_PCIE; then
    echo -e "${YELLOW}--- PCIe / Storage / Network ---${NC}"
    ls /dev/nvme*n* &>/dev/null && {
        DEV=$(ls /dev/nvme*n* | head -1)
        SIZE=$(lsblk -d -o SIZE "$DEV" 2>/dev/null | tail -1 | tr -d ' ')
        ok "NVMe: $DEV ($SIZE)"
    } || fail "NVMe non détecté"
    ETH=$(ip link show 2>/dev/null | grep -c "enP\|enp" || echo 0)
    [[ $ETH -ge 2 ]] && ok "Ethernet: ${ETH}× RTL8126" || warn "Ethernet: $ETH interface(s)"
    ip link show 2>/dev/null | grep -E "enP|enp" | awk '{print $2}' | tr -d ':' | \
        while read i; do info "$i — $(cat /sys/class/net/$i/operstate 2>/dev/null)"; done
    dmesg | grep -q "Asynchronous SError" && fail "SError PCIe détecté !" || ok "Pas de SError PCIe"
    echo ""
fi

# =============================================================================
# Mémoire
# =============================================================================
if $CHECK_MEM; then
    echo -e "${YELLOW}--- Mémoire ---${NC}"
    MEM_T=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    MEM_A=$(($(grep MemAvailable /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    ok "RAM: ${MEM_T} GB total, ${MEM_A} GB disponible"
    echo ""
fi

# =============================================================================
# Températures — lecture hwmon SCMI
# Note: BIOS 1.4 ne supporte pas notify mode → polling via scmi-hwmon
# =============================================================================
if $CHECK_TEMP; then
    echo -e "${YELLOW}--- Températures (SCMI hwmon) ---${NC}"

    # Charger scmi-hwmon si absent
    lsmod | grep -q "scmi_hwmon" || modprobe scmi-hwmon 2>/dev/null || true

    # Trouver le hwmon scmi_sensors
    SCMI_HW=""
    for hw in /sys/class/hwmon/hwmon*/; do
        [[ "$(cat ${hw}name 2>/dev/null)" == "scmi_sensors" ]] && SCMI_HW="$hw" && break
    done

    if [[ -n "$SCMI_HW" ]]; then
        # Capteurs prioritaires CPU/GPU/SoC
        for inp in "${SCMI_HW}temp"*"_input"; do
            [[ ! -f "$inp" ]] && continue
            N=$(basename "$inp" | grep -o '[0-9]*')
            LBL=$(cat "${SCMI_HW}temp${N}_label" 2>/dev/null || echo "sensor${N}")
            TEMP=$(cat "$inp" 2>/dev/null); TC=$((TEMP/1000))
            case "$LBL" in
                CPU_M0|CPU_M1|CPU_B0|CPU_B1)
                    [[ $TC -gt 85 ]] && fail "$LBL: ${TC}°C ← CRITIQUE !" || \
                    [[ $TC -gt 70 ]] && warn "$LBL: ${TC}°C ← CHAUD" || \
                    ok "$LBL: ${TC}°C" ;;
                GPU_AVE|SOC_BRC|NPU|DDR_top)
                    ok "$LBL: ${TC}°C" ;;
                PCB_*)
                    info "$LBL: ${TC}°C" ;;
            esac
        done

        # NVMe
        for hw in /sys/class/hwmon/hwmon*/; do
            [[ "$(cat ${hw}name 2>/dev/null)" == "nvme" ]] || continue
            T=$(cat "${hw}temp1_input" 2>/dev/null)
            [[ -n "$T" ]] && ok "NVMe: $((T/1000))°C"
        done

        info "BIOS 1.4 — notify non supporté, lecture polling"
    else
        warn "scmi_sensors non disponible"
        info "Charger: modprobe scmi-hwmon"
        info "Boot auto: echo 'scmi-hwmon' >> /etc/modules-load.d/sky1.conf"
    fi
    echo ""
fi

# =============================================================================
# RÉSUMÉ
# =============================================================================
echo -e "${BLUE}=== Résumé ===${NC}"
info "Kernel messages: $(dmesg | grep -c 'error\|Error' 2>/dev/null) erreurs dans dmesg"
echo ""
echo -e "${CYAN}Commandes utiles:${NC}"
echo "  dmesg | grep panthor   — Status GPU"
echo "  vulkaninfo --summary   — Test Vulkan"
echo "  glmark2-es2-drm        — Benchmark OpenGL ES"
