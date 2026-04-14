#!/bin/bash
# =============================================================================
# inject-sky1-config.sh
# Injecte les options Sky1 manquantes dans une config kernel Gentoo existante
# Usage: ./inject-sky1-config.sh [chemin/vers/.config] [chemin/vers/config.sky1-latest]
# =============================================================================

set -e

KERNEL_CONFIG="${1:-.config}"
SKY1_CONFIG="${2:-config.sky1-latest}"
SCRIPTS_CONFIG="./scripts/config"

# --- Couleurs ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}=== Sky1 Config Injector ===${NC}"
echo "Config cible  : $KERNEL_CONFIG"
echo "Config Sky1   : $SKY1_CONFIG"
echo ""

# Vérifications
[[ ! -f "$KERNEL_CONFIG" ]] && { echo -e "${RED}ERREUR: $KERNEL_CONFIG introuvable${NC}"; exit 1; }
[[ ! -f "$SKY1_CONFIG"   ]] && { echo -e "${RED}ERREUR: $SKY1_CONFIG introuvable${NC}"; exit 1; }
[[ ! -f "$SCRIPTS_CONFIG" ]] && { echo -e "${RED}ERREUR: scripts/config introuvable — lance ce script depuis la racine du kernel${NC}"; exit 1; }

# Backup
BACKUP="${KERNEL_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
cp "$KERNEL_CONFIG" "$BACKUP"
echo -e "${GREEN}Backup créé : $BACKUP${NC}"
echo ""

# =============================================================================
# PHASE 1 — OPTIONS REQUIRED (boot critique, à forcer en priorité absolue)
# =============================================================================
echo -e "${YELLOW}--- PHASE 1 : Options REQUIRED (Platform/SoC/USB/Storage) ---${NC}"

REQUIRED_OPTIONS=(
    # Platform / SoC
    "CONFIG_ARCH_CIX=y"
    "CONFIG_PCI_SKY1=y"
    "CONFIG_PINCTRL_SKY1_BASE=y"
    "CONFIG_PINCTRL_SKY1=y"
    "CONFIG_RESET_SKY1=y"
    "CONFIG_CLK_SKY1_AUDSS=y"
    "CONFIG_HWSPINLOCK_SKY1=y"
    "CONFIG_CIX_MBOX=y"
    # USB
    "CONFIG_USB_CDNSP=m"
    "CONFIG_USB_CDNSP_HOST=y"
    "CONFIG_USB_CDNSP_SKY1=m"
    "CONFIG_PHY_CIX_USB2=y"
    "CONFIG_PHY_CIX_USB3=y"
    "CONFIG_PHY_CIX_USBDP=y"
    # Storage / PCIe
    "CONFIG_PHY_CIX_PCIE=y"
)

for opt in "${REQUIRED_OPTIONS[@]}"; do
    key="${opt%%=*}"
    val="${opt##*=}"
    key_bare="${key#CONFIG_}"

    if [[ "$val" == "y" ]]; then
        $SCRIPTS_CONFIG --file "$KERNEL_CONFIG" --enable "$key_bare"
    elif [[ "$val" == "m" ]]; then
        $SCRIPTS_CONFIG --file "$KERNEL_CONFIG" --module "$key_bare"
    elif [[ "$val" == "n" ]]; then
        $SCRIPTS_CONFIG --file "$KERNEL_CONFIG" --disable "$key_bare"
    else
        # Valeur string ou int
        $SCRIPTS_CONFIG --file "$KERNEL_CONFIG" --set-val "$key_bare" "$val"
    fi
    echo -e "  ${GREEN}SET${NC} $key=$val"
done

# =============================================================================
# PHASE 2 — OPTIONS RECOMMENDED (GPU/Display/Audio/Périphériques)
# =============================================================================
echo ""
echo -e "${YELLOW}--- PHASE 2 : Options RECOMMENDED (GPU/Display/Audio/Periph) ---${NC}"

RECOMMENDED_OPTIONS=(
    # GPU Panthor (Mali-G720)
    "CONFIG_DRM_PANTHOR=m"
    # Display stack CIX
    "CONFIG_DRM_CIX=m"
    "CONFIG_DRM_LINLONDP=m"
    "CONFIG_DRM_TRILIN_DPSUB=m"
    "CONFIG_DRM_TRILIN_DP_CIX=m"
    # Audio
    "CONFIG_SND_HDA_CIX_IPBLOQ=m"
    "CONFIG_SND_SOC_CIX=m"
    "CONFIG_SND_SOC_SKY1_SOUND_CARD=m"
    # Périphériques Sky1
    "CONFIG_PWM_SKY1=y"
    "CONFIG_SKY1_WATCHDOG=y"
    "CONFIG_NVMEM_SKY1=y"
    "CONFIG_CIX_SKY1_SOCINFO=y"
)

for opt in "${RECOMMENDED_OPTIONS[@]}"; do
    key="${opt%%=*}"
    val="${opt##*=}"
    key_bare="${key#CONFIG_}"

    if [[ "$val" == "y" ]]; then
        $SCRIPTS_CONFIG --file "$KERNEL_CONFIG" --enable "$key_bare"
    elif [[ "$val" == "m" ]]; then
        $SCRIPTS_CONFIG --file "$KERNEL_CONFIG" --module "$key_bare"
    fi
    echo -e "  ${GREEN}SET${NC} $key=$val"
done

# =============================================================================
# PHASE 3 — INJECTION INTELLIGENTE des 990 options manquantes depuis config Sky1
#           (seulement celles qui n'existent PAS du tout dans ta config)
# =============================================================================
echo ""
echo -e "${YELLOW}--- PHASE 3 : Injection des options Sky1 manquantes (hors REQUIRED/RECOMMENDED) ---${NC}"

injected=0
skipped=0

while IFS= read -r line; do
    # Ignorer commentaires, lignes vides, et "# CONFIG_xxx is not set"
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    [[ "$line" =~ ^CONFIG_.*=.*$ ]] || continue

    key="${line%%=*}"
    val="${line##*=}"
    key_bare="${key#CONFIG_}"

    # Vérifier si l'option existe déjà dans la config cible
    if grep -q "^${key}=" "$KERNEL_CONFIG" || grep -q "^# ${key} is not set" "$KERNEL_CONFIG"; then
        ((skipped++)) || true
        continue
    fi

    # Option vraiment absente → on l'injecte
    if [[ "$val" == "y" ]]; then
        $SCRIPTS_CONFIG --file "$KERNEL_CONFIG" --enable "$key_bare" 2>/dev/null && ((injected++)) || true
    elif [[ "$val" == "m" ]]; then
        $SCRIPTS_CONFIG --file "$KERNEL_CONFIG" --module "$key_bare" 2>/dev/null && ((injected++)) || true
    elif [[ "$val" == "n" ]]; then
        : # ne pas désactiver des options que tu as activées intentionnellement
    else
        $SCRIPTS_CONFIG --file "$KERNEL_CONFIG" --set-val "$key_bare" "$val" 2>/dev/null && ((injected++)) || true
    fi

done < "$SKY1_CONFIG"

echo -e "  Injectées : ${GREEN}$injected${NC}  |  Déjà présentes (skippées) : ${YELLOW}$skipped${NC}"

# =============================================================================
# PHASE 4 — RÉSOLUTION DES DÉPENDANCES
# =============================================================================
echo ""
echo -e "${YELLOW}--- PHASE 4 : olddefconfig (résolution des dépendances Kconfig) ---${NC}"
make ARCH=arm64 olddefconfig
echo -e "${GREEN}olddefconfig terminé.${NC}"

# =============================================================================
# VÉRIFICATION FINALE
# =============================================================================
echo ""
echo -e "${YELLOW}--- VÉRIFICATION FINALE des REQUIRED options ---${NC}"
all_ok=true
for opt in "${REQUIRED_OPTIONS[@]}"; do
    key="${opt%%=*}"
    val="${opt##*=}"
    if grep -q "^${key}=${val}" "$KERNEL_CONFIG"; then
        echo -e "  ${GREEN}OK${NC}  $key=$val"
    else
        echo -e "  ${RED}KO${NC}  $key=$val  ← PROBLÈME !"
        all_ok=false
    fi
done

echo ""
if $all_ok; then
    echo -e "${GREEN}✓ Toutes les options REQUIRED sont en place. Tu peux compiler.${NC}"
    echo ""
    echo "Prochaine étape :"
    echo "  make ARCH=arm64 -j\$(nproc) Image modules dtbs"
else
    echo -e "${RED}⚠ Certaines options REQUIRED manquent encore.${NC}"
    echo "  Vérifie les dépendances Kconfig manquantes (ex: CONFIG_ARCH_CIX doit être =y avant les autres)."
    echo "  Lance: make ARCH=arm64 menuconfig  → cherche l'option et active son parent si nécessaire."
fi

echo ""
echo "Backup disponible : $BACKUP"
echo "Pour comparer : diff $BACKUP $KERNEL_CONFIG | grep '^[<>]' | head -50"
