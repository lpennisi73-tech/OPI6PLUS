#!/bin/bash
# =============================================================================
# bookworm-sky1-build.sh — Script principal BOOKWORM Sky1 Kernel Builder
# OrangePi 6 Plus / CIX CD8180 — Gentoo ARM64
#
# Usage: ./bookworm-sky1-build.sh [options]
#
# Options:
#   --kernel <version>    Version kernel à compiler (ex: 6.19-latest)
#   --base-config <path>  Config kernel de base (défaut: config Gentoo courante)
#   --build-dir <path>    Répertoire de build (défaut: ~/build/sky1-kernel)
#   --jobs <n>            Nombre de jobs parallèles (défaut: nproc)
#   --skip-download       Ne pas re-télécharger si déjà présent
#   --skip-patches        Ne pas re-appliquer les patches
#   --skip-config         Ne pas re-injecter la config
#   --skip-build          Ne pas recompiler
#   --install             Installer automatiquement après build
#   --dry-run             Afficher ce qui serait fait sans exécuter
#   --help                Afficher cette aide
#
# Exemple:
#   ./bookworm-sky1-build.sh --kernel 6.19-latest
#   ./bookworm-sky1-build.sh --kernel 7.0-latest --install
#   ./bookworm-sky1-build.sh --kernel 6.18-lts --skip-download
#
# BOOKWORM — Kenny — OrangePi 6 Plus Sky1 Gentoo
# =============================================================================

set -e

# =============================================================================
# COULEURS ET HELPERS
# =============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/build-$(date +%Y%m%d_%H%M%S).log"

step()    { echo -e "\n${BLUE}${BOLD}[STEP]${NC} $1" | tee -a "$LOG_FILE"; }
ok()      { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"; }
fail()    { echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"; }
info()    { echo -e "${CYAN}→${NC} $1" | tee -a "$LOG_FILE"; }
die()     { echo -e "${RED}FATAL: $1${NC}" | tee -a "$LOG_FILE"; exit 1; }

# =============================================================================
# VALEURS PAR DÉFAUT
# =============================================================================
KERNEL_TRACK="6.19-latest"
BASE_CONFIG=""
BUILD_DIR="$HOME/build/sky1-kernel"
JOBS=$(nproc)
SKIP_DOWNLOAD=false
SKIP_PATCHES=false
SKIP_CONFIG=false
SKIP_BUILD=false
DO_INSTALL=false
DRY_RUN=false

# =============================================================================
# PARSE ARGUMENTS
# =============================================================================
usage() {
    grep "^#" "$0" | grep -E "Usage:|Options:|Exemple:" -A 100 | \
        sed 's/^# //' | sed 's/^#//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel)       KERNEL_TRACK="$2"; shift 2 ;;
        --base-config)  BASE_CONFIG="$2"; shift 2 ;;
        --build-dir)    BUILD_DIR="$2"; shift 2 ;;
        --jobs)         JOBS="$2"; shift 2 ;;
        --skip-download) SKIP_DOWNLOAD=true; shift ;;
        --skip-patches)  SKIP_PATCHES=true; shift ;;
        --skip-config)   SKIP_CONFIG=true; shift ;;
        --skip-build)    SKIP_BUILD=true; shift ;;
        --install)       DO_INSTALL=true; shift ;;
        --dry-run)       DRY_RUN=true; shift ;;
        --help)          usage ;;
        *) die "Option inconnue: $1 (--help pour l'aide)" ;;
    esac
done

# =============================================================================
# CHARGER LA CONFIG
# =============================================================================
mkdir -p "$LOG_DIR"

BOARD_CONF="$SCRIPT_DIR/config/board.conf"
KERNEL_CONF="$SCRIPT_DIR/config/kernels/${KERNEL_TRACK}.conf"

[[ ! -f "$BOARD_CONF" ]]  && die "board.conf introuvable: $BOARD_CONF"
[[ ! -f "$KERNEL_CONF" ]] && die "Kernel config introuvable: $KERNEL_CONF"

source "$BOARD_CONF"
source "$KERNEL_CONF"

# Répertoires de build
KERNEL_SRC_DIR="$BUILD_DIR/linux-${KERNEL_FULL_VERSION}"
SKY1_DIR="$BUILD_DIR/linux-sky1"
TARBALL="$BUILD_DIR/${KERNEL_TARBALL}"

# Config de base — utiliser la config Gentoo courante si non spécifiée
if [[ -z "$BASE_CONFIG" ]]; then
    # Chercher la config du kernel en cours
    RUNNING_KVER=$(uname -r)
    if [[ -f "/boot/config-${RUNNING_KVER}" ]]; then
        BASE_CONFIG="/boot/config-${RUNNING_KVER}"
    elif [[ -f "/proc/config.gz" ]]; then
        BASE_CONFIG="/proc/config.gz"
    else
        BASE_CONFIG=""
    fi
fi

# =============================================================================
# BANNER
# =============================================================================
echo ""
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║   BOOKWORM Sky1 Kernel Builder                 ║${NC}"
echo -e "${BLUE}${BOLD}║   OrangePi 6 Plus — CIX CD8180 — Gentoo ARM64  ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Board        : ${CYAN}${BOARD_NAME}${NC}"
echo -e "  Kernel track : ${CYAN}${KERNEL_TRACK}${NC}"
echo -e "  Version      : ${CYAN}${KERNEL_FULL_VERSION}${KERNEL_LOCALVERSION}${NC}"
echo -e "  Sky1 track   : ${CYAN}${SKY1_TRACK}${NC}"
echo -e "  Build dir    : ${CYAN}${BUILD_DIR}${NC}"
echo -e "  Jobs         : ${CYAN}${JOBS}${NC}"
echo -e "  Base config  : ${CYAN}${BASE_CONFIG:-Sky1 default}${NC}"
[[ "$STATUS" != "stable" ]] && \
    warn "Kernel track STATUS=${STATUS} — non testé !"
echo ""

$DRY_RUN && warn "MODE DRY-RUN — aucune modification effectuée"
echo "" | tee -a "$LOG_FILE"

# =============================================================================
# VÉRIFICATIONS PRÉLIMINAIRES
# =============================================================================
step "Vérifications préliminaires"

# Outils requis
REQUIRED_TOOLS="git wget patch python3 make gcc bc flex bison"
MISSING_TOOLS=""
for tool in $REQUIRED_TOOLS; do
    command -v "$tool" &>/dev/null || MISSING_TOOLS="$MISSING_TOOLS $tool"
done
[[ -n "$MISSING_TOOLS" ]] && die "Outils manquants:$MISSING_TOOLS"
ok "Outils de build présents"

# Architecture
[[ "$(uname -m)" != "aarch64" ]] && \
    warn "Non ARM64 — cross-compilation non supportée pour l'instant"

# Espace disque (minimum 20GB)
AVAIL=$(df -BG "$BUILD_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo 99)
[[ "${AVAIL:-99}" -lt 20 ]] && \
    warn "Espace disque faible: ${AVAIL}GB disponible (20GB recommandé)"
ok "Espace disque: ${AVAIL}GB disponible"

mkdir -p "$BUILD_DIR"
ok "Répertoire build: $BUILD_DIR"

# =============================================================================
# ÉTAPE 1 — TÉLÉCHARGEMENT SOURCES
# =============================================================================
step "Étape 1/6 — Sources kernel + Sky1 patches"

if ! $SKIP_DOWNLOAD; then

    # Cloner/mettre à jour linux-sky1
    if [[ -d "$SKY1_DIR/.git" ]]; then
        info "Mise à jour linux-sky1..."
        $DRY_RUN || (cd "$SKY1_DIR" && git pull --quiet)
        ok "linux-sky1 mis à jour"
    else
        info "Clonage linux-sky1..."
        $DRY_RUN || git clone --quiet "$SKY1_REPO" "$SKY1_DIR"
        ok "linux-sky1 cloné"
    fi

    # Télécharger le tarball kernel
    if [[ ! -f "$TARBALL" ]]; then
        info "Téléchargement ${KERNEL_TARBALL}..."
        $DRY_RUN || wget -q --show-progress -O "$TARBALL" "$KERNEL_URL" || \
            die "Échec téléchargement: $KERNEL_URL"
        ok "Kernel téléchargé: $TARBALL"
    else
        ok "Kernel déjà présent: $TARBALL"
    fi

    # Extraire si nécessaire
    if [[ ! -d "$KERNEL_SRC_DIR" ]]; then
        info "Extraction ${KERNEL_TARBALL}..."
        $DRY_RUN || tar xf "$TARBALL" -C "$BUILD_DIR"
        ok "Kernel extrait: $KERNEL_SRC_DIR"
    else
        ok "Sources déjà extraites: $KERNEL_SRC_DIR"
    fi

else
    ok "Download skippé (--skip-download)"
fi

[[ ! -d "$KERNEL_SRC_DIR" ]] && die "Sources kernel introuvables: $KERNEL_SRC_DIR"

# =============================================================================
# ÉTAPE 2 — FIXES PRÉ-PATCH
# =============================================================================
step "Étape 2/6 — Fixes pré-patch"

cd "$KERNEL_SRC_DIR"

FIXES_DIR="$SCRIPT_DIR/patches/fixes"

if ! $SKIP_PATCHES; then
    # Appliquer les fixes Python avant les patches Sky1
    # Seul le fix panthor coherency s'applique avant les patches
    for fix_name in $FIXES; do
        FIX_FILE="$FIXES_DIR/${fix_name}.py"
        if [[ -f "$FIX_FILE" && "$fix_name" == *"panthor"* ]]; then
            info "Fix pré-patch: $fix_name"
            if ! $DRY_RUN; then
                python3 "$FIX_FILE" 2>&1 | tee -a "$LOG_FILE" || \
                    warn "Fix $fix_name: SKIP (peut être normal)"
            fi
        fi
    done
    ok "Fixes pré-patch appliqués"
fi

# =============================================================================
# ÉTAPE 3 — APPLICATION PATCHES SKY1
# =============================================================================
step "Étape 3/6 — Patches Sky1 (${SKY1_TRACK})"

if ! $SKIP_PATCHES; then

    PATCHES_SRC="$SKY1_DIR/${SKY1_PATCHES_DIR}"
    APPLY_SCRIPT="$SCRIPT_DIR/patches/apply-sky1-patches.sh"

    [[ ! -d "$PATCHES_SRC" ]] && die "Patches introuvables: $PATCHES_SRC"

    # Vérifier si déjà patché
    if [[ -f "$KERNEL_SRC_DIR/.sky1-patched" ]]; then
        ok "Patches déjà appliqués (supprimer .sky1-patched pour re-appliquer)"
    else
        info "Application de $(ls $PATCHES_SRC/*.patch | wc -l) patches..."
        if ! $DRY_RUN; then
            bash "$APPLY_SCRIPT" "$PATCHES_SRC" 2>&1 | tee -a "$LOG_FILE"
            touch "$KERNEL_SRC_DIR/.sky1-patched"
        fi
        ok "Patches Sky1 appliqués"
    fi

else
    ok "Patches skippés (--skip-patches)"
fi

# =============================================================================
# ÉTAPE 4 — FIXES POST-PATCH (DTS, driver)
# =============================================================================
step "Étape 4/6 — Fixes post-patch (DTS + drivers)"

if ! $SKIP_PATCHES; then
    # Appliquer tous les fixes post-patch depuis FIXES (sauf panthor qui est pre-patch)
    for fix_name in $FIXES; do
        [[ "$fix_name" == *"panthor"* ]] && continue
        FIX_FILE="$FIXES_DIR/${fix_name}.py"
        if [[ -f "$FIX_FILE" ]]; then
            info "Fix post-patch: $fix_name"
            $DRY_RUN || python3 "$FIX_FILE" 2>&1 | tee -a "$LOG_FILE"
            ok "$fix_name applique"
        else
            warn "Fix non trouve: $FIX_FILE"
        fi
    done
fi

# =============================================================================
# ÉTAPE 5 — CONFIGURATION KERNEL
# =============================================================================
step "Étape 5/6 — Configuration kernel"

if ! $SKIP_CONFIG; then

    SKY1_CONFIG_FILE="$SKY1_DIR/${SKY1_CONFIG}"
    INJECT_SCRIPT="$SCRIPT_DIR/config/inject-sky1-config.sh"

    if [[ -n "$BASE_CONFIG" && -f "$BASE_CONFIG" ]]; then
        # Config personnalisée (Gentoo) + injection Sky1
        info "Config de base: $BASE_CONFIG"
        if [[ "$BASE_CONFIG" == *.gz ]]; then
            zcat "$BASE_CONFIG" > .config
        else
            cp "$BASE_CONFIG" .config
        fi

        info "Injection options Sky1..."
        $DRY_RUN || bash "$INJECT_SCRIPT" .config "$SKY1_CONFIG_FILE" \
            2>&1 | tee -a "$LOG_FILE"
    else
        # Config Sky1 pure
        info "Utilisation config Sky1 pure: $SKY1_CONFIG_FILE"
        cp "$SKY1_CONFIG_FILE" .config
        make ARCH=arm64 olddefconfig 2>&1 | tee -a "$LOG_FILE"
    fi

    # Forcer les options built-in critiques
    info "Application options built-in obligatoires..."
    for opt in $FORCE_BUILTIN; do
        $DRY_RUN || scripts/config --enable "$opt"
    done

    # Désactiver les options incompatibles
    info "Désactivation options incompatibles..."
    for opt in $FORCE_DISABLED; do
        $DRY_RUN || scripts/config --disable "$opt"
    done

    # Résolution finale des dépendances
    $DRY_RUN || make ARCH=arm64 olddefconfig 2>&1 | tee -a "$LOG_FILE"
    # Fix modules avec symboles manquants (ChromeOS privacy screen)
    info "Fix modules incompatibles..."
    $DRY_RUN || scripts/config --disable CHROMEOS_PRIVACY_SCREEN 2>/dev/null || true
    ok "Configuration kernel finalisée"

else
    ok "Config skippée (--skip-config)"
fi

# =============================================================================
# ÉTAPE 6 — COMPILATION
# =============================================================================
step "Étape 6/6 — Compilation (j${JOBS})"

if ! $SKIP_BUILD; then

    START_TIME=$(date +%s)
    info "Démarrage compilation — $(date)"
    info "Logs: $LOG_FILE"

    if ! $DRY_RUN; then
        make ARCH=arm64 -j${JOBS} ${CC:+CC="$CC"} ${CXX:+CXX="$CXX"} Image modules dtbs 2>&1 | tee -a "$LOG_FILE"
        BUILD_EXIT=${PIPESTATUS[0]}
        [[ $BUILD_EXIT -ne 0 ]] && die "Compilation échouée (code $BUILD_EXIT) — voir $LOG_FILE"
    fi

    END_TIME=$(date +%s)
    DURATION=$(( (END_TIME - START_TIME) / 60 ))
    ok "Compilation terminée en ${DURATION} minutes"

    # Vérifier les artefacts
    [[ -f "arch/arm64/boot/Image" ]] && \
        ok "Kernel: arch/arm64/boot/Image ($(du -h arch/arm64/boot/Image | cut -f1))"
    [[ -f "arch/arm64/boot/dts/cix/${DTB_NAME}" ]] && \
        ok "DTB: arch/arm64/boot/dts/cix/${DTB_NAME}"

else
    ok "Build skippé (--skip-build)"
fi

# =============================================================================
# INSTALLATION (optionnelle)
# =============================================================================
if $DO_INSTALL && ! $DRY_RUN; then
    step "Installation"
    KERNEL_FULL_VERSION="$KERNEL_FULL_VERSION" KERNEL_VERSION="$KERNEL_VERSION" SKY1_TRACK="$SKY1_TRACK" bash "$SCRIPT_DIR/install/install.sh" --kernel-dir "$KERNEL_SRC_DIR"
fi

# =============================================================================
# RÉSUMÉ FINAL
# =============================================================================
echo ""
echo -e "${BLUE}${BOLD}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║   Build terminé !                              ║${NC}"
echo -e "${BLUE}${BOLD}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Kernel  : ${GREEN}${KERNEL_SRC_DIR}/arch/arm64/boot/Image${NC}"
echo -e "  DTB     : ${GREEN}${KERNEL_SRC_DIR}/arch/arm64/boot/dts/cix/${DTB_NAME}${NC}"
echo -e "  Log     : ${CYAN}${LOG_FILE}${NC}"
echo ""

if ! $DO_INSTALL; then
    echo -e "${YELLOW}Prochaine étape — Installation:${NC}"
    echo "  sudo ./install/install.sh --kernel-dir ${KERNEL_SRC_DIR}"
    echo ""
    echo -e "${YELLOW}Ou tout en une fois:${NC}"
    echo "  ./bookworm-sky1-build.sh --kernel ${KERNEL_TRACK} --skip-download --skip-patches --skip-config --install"
fi

echo -e "${YELLOW}Post-boot:${NC}"
echo "  ./diagnostics/check-system.sh"
echo ""
echo -e "${CYAN}BOOKWORM — Kernel Sky1 OrangePi 6 Plus${NC} 🚀"
