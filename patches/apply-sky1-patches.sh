#!/bin/bash
# =============================================================================
# apply-sky1-patches.sh
# Applique les patches Sky1-Linux avec résolution automatique des conflits connus
#
# Usage: ./apply-sky1-patches.sh [chemin/vers/patches-latest/] 
#        Par défaut: ../linux-sky1/patches-latest/
#
# Conflits connus gérés automatiquement:
#   - Patch 0118: panthor_gpu.c hunk #1 (ACE-Lite coherency API migration)
#     ptdev->coherent → ptdev->coherency_mode == PANTHOR_COHERENCY_NONE
#
# Kenny / BOOKWORM — OrangePi 6 Plus / CIX CD8180 — Gentoo ARM64
# =============================================================================

set -e

PATCHES_DIR="${1:-../linux-sky1/patches-latest}"

# --- Couleurs ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   Sky1-Linux Patch Applier — OrangePi 6 Plus   ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# Vérifications préliminaires
[[ ! -d "$PATCHES_DIR" ]] && { echo -e "${RED}ERREUR: Dossier patches introuvable: $PATCHES_DIR${NC}"; exit 1; }
[[ ! -f "Makefile" ]] && { echo -e "${RED}ERREUR: Lance ce script depuis la racine du kernel source${NC}"; exit 1; }

PATCH_COUNT=$(ls "$PATCHES_DIR"/*.patch 2>/dev/null | wc -l)
echo -e "Dossier patches : ${CYAN}$PATCHES_DIR${NC}"
echo -e "Patches trouvés : ${CYAN}$PATCH_COUNT${NC}"
echo ""

applied=0
skipped=0
failed=0

# =============================================================================
# FONCTION: Appliquer un patch avec vérification
# =============================================================================
apply_patch() {
    local pfile="$1"
    local pname="$(basename $pfile)"

    # Dry-run d'abord
    if patch -p1 --dry-run < "$pfile" > /dev/null 2>&1; then
        patch -p1 < "$pfile" > /dev/null 2>&1
        echo -e "  ${GREEN}OK${NC}  $pname"
        ((applied++)) || true
        return 0
    fi

    # Dry-run avec fuzz=3
    if patch -p1 --dry-run --fuzz=3 < "$pfile" > /dev/null 2>&1; then
        patch -p1 --fuzz=3 < "$pfile" > /dev/null 2>&1
        echo -e "  ${YELLOW}OK(fuzz=3)${NC}  $pname"
        ((applied++)) || true
        return 0
    fi

    return 1
}

# =============================================================================
# FONCTION: Correction manuelle patch 0118 — panthor_gpu.c ACE-Lite
# Contexte: Le patch migre ptdev->coherent vers ptdev->coherency_mode
# Le hunk #1 échoue car le contexte de panthor_gpu_coherency_set() a bougé
# dans kernel 6.19 — on applique la modification directement puis on patch
# =============================================================================
fix_patch_0118() {
    local pfile="$1"
    local target="drivers/gpu/drm/panthor/panthor_gpu.c"

    echo -e "  ${YELLOW}FIX${NC}  Correction manuelle hunk #1 panthor_gpu.c (coherency API)..."

    # Vérifier que la ligne ancienne est bien présente
    if grep -q "ptdev->coherent ? GPU_COHERENCY_PROT_BIT(ACE_LITE) : GPU_COHERENCY_NONE" "$target"; then
        # Appliquer la correction manuelle
        sed -i 's/\t\tptdev->coherent ? GPU_COHERENCY_PROT_BIT(ACE_LITE) : GPU_COHERENCY_NONE);/\t\tptdev->coherency_mode == PANTHOR_COHERENCY_NONE ?\n\t\tGPU_COHERENCY_NONE : GPU_COHERENCY_PROT_BIT(ACE_LITE));/' "$target"
        echo -e "  ${GREEN}FIX OK${NC}  panthor_gpu.c ligne coherency corrigée manuellement"
    elif grep -q "ptdev->coherency_mode == PANTHOR_COHERENCY_NONE" "$target"; then
        echo -e "  ${CYAN}SKIP${NC}  panthor_gpu.c déjà corrigé"
    else
        echo -e "  ${RED}FIX IMPOSSIBLE${NC}  Contexte panthor_gpu.c inattendu — inspection manuelle requise"
        echo "  Ligne attendue: ptdev->coherent ? GPU_COHERENCY_PROT_BIT(ACE_LITE) : GPU_COHERENCY_NONE"
        grep -n "coherent\|coherency_mode" "$target" | head -10
        return 1
    fi

    # Appliquer le reste du patch avec --fuzz=5 --forward
    # Le hunk #1 va échouer (déjà corrigé) mais les autres doivent passer
    patch -p1 --fuzz=5 --forward < "$pfile" > /dev/null 2>&1 || true

    # Vérifier qu'il n'y a pas de vrais .rej (hors panthor_gpu.c.rej attendu)
    local bad_rej=0
    for rej in $(find drivers/gpu/drm/panthor/ -name "*.rej" 2>/dev/null); do
        if [[ "$rej" != *"panthor_gpu.c.rej" ]]; then
            echo -e "  ${RED}REJ inattendu: $rej${NC}"
            ((bad_rej++)) || true
        fi
    done

    # Supprimer le .rej attendu du hunk déjà corrigé
    rm -f drivers/gpu/drm/panthor/panthor_gpu.c.rej

    if [[ $bad_rej -eq 0 ]]; then
        echo -e "  ${GREEN}OK${NC}  $(basename $pfile) — tous les hunks appliqués"
        ((applied++)) || true
        return 0
    else
        echo -e "  ${RED}ÉCHEC${NC}  $(basename $pfile) — $bad_rej .rej inattendus"
        ((failed++)) || true
        return 1
    fi
}

# =============================================================================
# BOUCLE PRINCIPALE — application de tous les patches dans l'ordre
# =============================================================================
echo -e "${YELLOW}--- Application des patches ---${NC}"
echo ""

for pfile in $(ls "$PATCHES_DIR"/*.patch | sort); do
    pname="$(basename $pfile)"

    # Dispatch vers le handler approprié selon le patch
    case "$pname" in
        0118-*)
            # Conflit connu — correction manuelle du hunk panthor_gpu.c
            fix_patch_0118 "$pfile" || {
                echo -e "${RED}ARRÊT sur $pname${NC}"
                exit 1
            }
            ;;
        *)
            # Patch standard
            apply_patch "$pfile" || {
                echo -e "  ${RED}ÉCHEC${NC}  $pname"
                echo ""
                echo -e "${RED}=== ERREUR — Patch non applicable ===${NC}"
                echo "Patch: $pfile"
                echo ""
                echo "Détail du dry-run:"
                patch -p1 --dry-run < "$pfile" 2>&1 | head -20
                echo ""
                echo "Fichiers .rej créés:"
                find . -name "*.rej" 2>/dev/null
                echo ""
                echo -e "${YELLOW}Options:${NC}"
                echo "  1. Corriger manuellement et relancer avec: $0 $PATCHES_DIR"
                echo "  2. Ajouter un handler 'case' dans ce script pour ce patch"
                ((failed++)) || true
                exit 1
            }
            ;;
    esac
done

# =============================================================================
# VÉRIFICATION FINALE
# =============================================================================
echo ""
echo -e "${YELLOW}--- Vérification finale ---${NC}"

# Chercher tout .rej résiduel
remaining_rej=$(find . -name "*.rej" 2>/dev/null | wc -l)
if [[ $remaining_rej -gt 0 ]]; then
    echo -e "${RED}⚠ $remaining_rej fichier(s) .rej résiduels:${NC}"
    find . -name "*.rej" 2>/dev/null
else
    echo -e "${GREEN}✓ Aucun .rej résiduel${NC}"
fi

echo ""
echo -e "${BLUE}=== Résumé ===${NC}"
echo -e "  Appliqués  : ${GREEN}$applied${NC}"
echo -e "  Échoués    : ${RED}$failed${NC}"
echo -e "  Total      : $PATCH_COUNT"
echo ""

if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}✓ Tous les patches appliqués avec succès !${NC}"
    echo ""
    echo "Prochaine étape — injecter la config et compiler :"
    echo "  ./inject-sky1-config.sh .config config.sky1-latest"
    echo "  make ARCH=arm64 -j\$(nproc) Image modules dtbs 2>&1 | tee build.log"
else
    echo -e "${RED}⚠ $failed patch(es) en échec — inspection manuelle requise${NC}"
    exit 1
fi
