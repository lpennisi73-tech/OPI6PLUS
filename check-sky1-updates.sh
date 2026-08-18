#!/bin/bash
# =============================================================================
# check-sky1-updates.sh — Veille BOOKWORM Sky1 Kernel Builder
#
# Surveille:
#   1. Nouveaux commits sur le repo Sky1-Linux (linux-sky1)
#   2. Changements du CHANGELOG (nouvelle version rebasee ?)
#   3. Nombre de patches par track (next/latest/rc)
#   4. Base kernel visee par le patch 0001 de chaque track
#   5. Nouvelles versions kernel stables sur cdn.kernel.org
#
# Compare avec l'etat du dernier check et affiche les nouveautes.
#
# Usage:
#   ./check-sky1-updates.sh              # check manuel
#   ./check-sky1-updates.sh --quiet      # sortie minimale (pour cron)
#   ./check-sky1-updates.sh --reset      # reinitialise l'etat sauvegarde
#
# Cron (1x/jour a 9h):
#   0 9 * * * /usr/src/bookworm-sky1-kernel/check-sky1-updates.sh --quiet
# =============================================================================

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$SCRIPT_DIR/.check-state"
STATE_FILE="$STATE_DIR/last-check.txt"

QUIET=false
RESET=false
for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=true ;;
        --reset) RESET=true ;;
        --help)
            echo "Usage: $0 [--quiet] [--reset]"
            exit 0 ;;
    esac
done

# --- Charger la config board pour trouver BUILD_DIR ---
# set +u temporaire: board.conf reference des vars ($KERNEL_VERSION) non definies ici
set +u
source "$SCRIPT_DIR/config/board.conf" 2>/dev/null || {
    echo -e "${RED}ERREUR: board.conf introuvable${NC}"; set -u; exit 1
}
set -u

# BUILD_DIR n'est pas dans board.conf — valeur par defaut
BUILD_DIR="${BUILD_DIR:-/usr/src/build/sky1-kernel}"

SKY1_DIR="${BUILD_DIR}/linux-sky1"

say() { $QUIET || echo -e "$@"; }
alert() { echo -e "$@"; }  # toujours affiche, meme en quiet

mkdir -p "$STATE_DIR"

if $RESET; then
    rm -f "$STATE_FILE"
    echo -e "${GREEN}Etat reinitialise${NC}"
    exit 0
fi

# =============================================================================
say "${BLUE}${BOLD}╔════════════════════════════════════════════════╗${NC}"
say "${BLUE}${BOLD}║   BOOKWORM — Veille Sky1-Linux + kernel.org    ║${NC}"
say "${BLUE}${BOLD}╚════════════════════════════════════════════════╝${NC}"
say ""
say "  Date  : $(date '+%Y-%m-%d %H:%M')"
say "  Repo  : ${CYAN}${SKY1_DIR}${NC}"
say ""

# --- Etat courant (collecte) ---
declare -A CUR

# 1. Sky1-Linux repo
if [[ -d "$SKY1_DIR/.git" ]]; then
    cd "$SKY1_DIR"
    say "${YELLOW}--- Mise a jour linux-sky1 (git fetch) ---${NC}"
    git fetch origin --quiet 2>/dev/null

    CUR[local_commit]=$(git rev-parse HEAD 2>/dev/null)
    CUR[remote_commit]=$(git rev-parse origin/main 2>/dev/null)

    # Commits en retard
    BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
    CUR[behind]="$BEHIND"

    if [[ "$BEHIND" -gt 0 ]]; then
        alert "${GREEN}${BOLD}⇩ $BEHIND nouveaux commits disponibles sur origin/main !${NC}"
        say ""
        say "${CYAN}Derniers commits distants:${NC}"
        git log --oneline HEAD..origin/main 2>/dev/null | head -15 | sed 's/^/    /'
        say ""
    else
        say "  ${GREEN}✓${NC} A jour avec origin/main"
    fi

    # 2. Compter les patches par track
    for track in next latest rc; do
        pdir="$SKY1_DIR/patches-$track"
        if [[ -d "$pdir" ]]; then
            n=$(ls "$pdir"/*.patch 2>/dev/null | wc -l)
            CUR[patches_$track]="$n"
        else
            CUR[patches_$track]="0"
        fi
    done

    # 3. Base kernel visee par patch 0001 de chaque track
    #    On extrait le contexte du dtsi (nombre de lignes attendu au hunk)
    for track in next latest rc; do
        p0001=$(ls "$SKY1_DIR/patches-$track/"0001-*.patch 2>/dev/null | head -1)
        if [[ -n "$p0001" ]]; then
            # Signature = hash court du patch 0001 (detecte tout changement)
            CUR[p0001_$track]=$(md5sum "$p0001" 2>/dev/null | cut -c1-12)
        else
            CUR[p0001_$track]="none"
        fi
    done

    # 4. Derniere version du CHANGELOG
    if [[ -f "$SKY1_DIR/CHANGELOG.md" ]]; then
        CUR[changelog_ver]=$(grep -m1 '^## \[' "$SKY1_DIR/CHANGELOG.md" 2>/dev/null | \
            sed 's/## \[\(.*\)\].*/\1/')
    else
        CUR[changelog_ver]="?"
    fi
else
    alert "${RED}ATTENTION: $SKY1_DIR n'est pas un repo git${NC}"
    alert "  Lance d'abord un build pour cloner linux-sky1"
fi

# 5. Dernieres versions kernel sur cdn.kernel.org
say ""
say "${YELLOW}--- Versions kernel stables (kernel.org) ---${NC}"
KORG=$(curl -s --max-time 10 https://www.kernel.org/finger_banner 2>/dev/null)
if [[ -n "$KORG" ]]; then
    STABLE=$(echo "$KORG" | grep -i "latest stable" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    MAINLINE=$(echo "$KORG" | grep -i "mainline" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+|-rc[0-9]+)?' | head -1)
    CUR[korg_stable]="$STABLE"
    CUR[korg_mainline]="$MAINLINE"
    say "  Stable   : ${CYAN}${STABLE:-?}${NC}"
    say "  Mainline : ${CYAN}${MAINLINE:-?}${NC}"
else
    say "  ${YELLOW}(kernel.org injoignable)${NC}"
    CUR[korg_stable]="?"
    CUR[korg_mainline]="?"
fi

# =============================================================================
# COMPARAISON avec l'etat precedent
# =============================================================================
say ""
say "${YELLOW}--- Changements depuis le dernier check ---${NC}"

declare -A PREV
if [[ -f "$STATE_FILE" ]]; then
    while IFS='=' read -r k v; do
        [[ -n "$k" ]] && PREV[$k]="$v"
    done < "$STATE_FILE"
fi

CHANGES=0
report_change() {
    local key="$1" label="$2"
    local old="${PREV[$key]:-<absent>}"
    local new="${CUR[$key]:-<absent>}"
    if [[ "$old" != "$new" ]]; then
        alert "  ${GREEN}${BOLD}⇩ $label${NC}: ${RED}$old${NC} → ${GREEN}$new${NC}"
        CHANGES=$((CHANGES+1))
    fi
}

report_change changelog_ver     "CHANGELOG version"
report_change patches_next      "Patches track NEXT"
report_change patches_latest    "Patches track LATEST"
report_change patches_rc        "Patches track RC"
report_change p0001_next        "Patch 0001 NEXT (signature)"
report_change p0001_latest      "Patch 0001 LATEST (signature)"
report_change p0001_rc          "Patch 0001 RC (signature)"
report_change korg_stable       "Kernel stable (kernel.org)"
report_change korg_mainline     "Kernel mainline (kernel.org)"

if [[ "${CUR[behind]:-0}" -gt 0 ]]; then
    CHANGES=$((CHANGES+1))
fi

if [[ "$CHANGES" -eq 0 ]]; then
    say "  ${GREEN}✓ Rien de neuf — tout est stable${NC}"
else
    alert ""
    alert "${GREEN}${BOLD}  ⇒ $CHANGES changement(s) detecte(s) !${NC}"
    alert "${CYAN}  Actions possibles:${NC}"
    alert "    cd $SKY1_DIR && git pull   # recuperer les patches"
    alert "    Verifier si patches-next cible une nouvelle base kernel"
    alert "    Si oui: creer/tester le track correspondant (ex: 7.2-next)"
fi

# =============================================================================
# SAUVEGARDE de l'etat courant
# =============================================================================
> "$STATE_FILE"
for k in "${!CUR[@]}"; do
    echo "$k=${CUR[$k]}" >> "$STATE_FILE"
done
echo "last_check=$(date '+%Y-%m-%d %H:%M')" >> "$STATE_FILE"

say ""
say "${BLUE}Etat sauvegarde: $STATE_FILE${NC}"
say ""

# Code retour: 0 si rien, 10 si changements (utile pour cron/notif)
[[ "$CHANGES" -gt 0 ]] && exit 10 || exit 0

