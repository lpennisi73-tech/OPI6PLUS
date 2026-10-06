#!/bin/bash
# =============================================================================
# apply-sky1-patches.sh
# Applique les patches Sky1-Linux avec résolution automatique des conflits connus
#
# Usage: ./apply-sky1-patches.sh [chemin/vers/patches-latest/] 
#        Par défaut: ../linux-sky1/patches-latest/
#
# Conflits connus gérés automatiquement:
#   - Patch panthor "add-ACE-Lite-coherency" (0117 sur 6.18.x, 0118 sur 6.19)
#     Hunk #1 de panthor_gpu.c: sur 6.19 la ligne d'origine utilise
#     GPU_COHERENCY_PROT_BIT(ACE_LITE) alors que le patch attend
#     GPU_COHERENCY_ACE_LITE. On ramène la ligne à la forme attendue, puis on
#     laisse patch appliquer le hunk RÉEL (y compris le bit SHAREABLE_CACHE).
#     Sur 6.18.x le patch s'applique tel quel, aucune correction n'est faite.
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
# FONCTION: Patch panthor ACE-Lite — panthor_gpu.c
# Le patch migre ptdev->coherent vers ptdev->coherency_mode et programme aussi
# le bit SHAREABLE_CACHE. Sur 6.19 son hunk #1 échoue car la ligne d'origine
# utilise GPU_COHERENCY_PROT_BIT(ACE_LITE) au lieu de GPU_COHERENCY_ACE_LITE.
# On normalise cette seule ligne, puis le patch complet est appliqué tel quel.
# =============================================================================
fix_patch_0118() {
    local pfile="$1"
    local pname
    pname="$(basename "$pfile")"
    local target="drivers/gpu/drm/panthor/panthor_gpu.c"
    local backup="${target}.sky1-bak"

    # Cas 1 — le patch s'applique tel quel (6.18.x) : aucune correction
    if patch -p1 --dry-run < "$pfile" > /dev/null 2>&1; then
        echo -e "  ${CYAN}SKIP${NC}  correction manuelle inutile — $pname s'applique tel quel"
        apply_patch "$pfile"
        return $?
    fi

    echo -e "  ${YELLOW}FIX${NC}  panthor_gpu.c : le hunk #1 ne s'applique pas tel quel..."

    # Cas 2 — patch déjà appliqué en entier (le bit SHAREABLE_CACHE est utilisé)
    if grep -q "GPU_COHERENCY_SHAREABLE_CACHE" "$target"; then
        echo -e "  ${CYAN}SKIP${NC}  $pname déjà appliqué (SHAREABLE_CACHE présent dans panthor_gpu.c)"
        ((skipped++)) || true
        return 0
    fi

    # Cas 3 — forme 6.19 d'origine : on la ramène à la forme attendue par le patch
    if grep -q "ptdev->coherent ? GPU_COHERENCY_PROT_BIT(ACE_LITE) : GPU_COHERENCY_NONE" "$target"; then
        cp "$target" "$backup"
        sed -i 's/ptdev->coherent ? GPU_COHERENCY_PROT_BIT(ACE_LITE) : GPU_COHERENCY_NONE/ptdev->coherent ? GPU_COHERENCY_ACE_LITE : GPU_COHERENCY_NONE/' "$target"

        if ! patch -p1 --dry-run < "$pfile" > /dev/null 2>&1; then
            mv "$backup" "$target"
            echo -e "  ${RED}FIX IMPOSSIBLE${NC}  le patch ne s'applique toujours pas après normalisation"
            echo "  panthor_gpu.c restauré. Détail du dry-run:"
            patch -p1 --dry-run < "$pfile" 2>&1 | head -20
            return 1
        fi

        if ! apply_patch "$pfile"; then
            mv "$backup" "$target"
            echo -e "  ${RED}ÉCHEC${NC}  $pname — panthor_gpu.c restauré"
            ((failed++)) || true
            return 1
        fi
        rm -f "$backup"
        echo -e "  ${GREEN}FIX OK${NC}  ligne normalisée, hunk #1 appliqué tel que défini par le patch"
    # Cas 4 — base 6.19 déjà migrée vers coherency_mode (présente dès les sources
    # propres + patches précédents) : le hunk #1 ne peut pas la remplacer, on
    # l'ignore et on applique les autres hunks du patch.
    elif grep -q "ptdev->coherency_mode == PANTHOR_COHERENCY_NONE" "$target"; then
        echo -e "  ${YELLOW}INFO${NC}  panthor_gpu.c utilise déjà coherency_mode (base 6.19) : hunk #1 ignoré"
        echo -e "  ${YELLOW}WARN${NC}  le bit SHAREABLE_CACHE du patch n'est donc PAS programmé dans panthor_gpu.c"

        patch -p1 --fuzz=5 --forward < "$pfile" > /dev/null 2>&1 || true

        local bad_rej=0
        for rej in $(find drivers/gpu/drm/panthor/ -name "*.rej" 2>/dev/null); do
            if [[ "$rej" != *"panthor_gpu.c.rej" ]]; then
                echo -e "  ${RED}REJ inattendu: $rej${NC}"
                ((bad_rej++)) || true
            fi
        done
        # Seul le .rej du hunk #1 de panthor_gpu.c est attendu ici
        rm -f drivers/gpu/drm/panthor/panthor_gpu.c.rej drivers/gpu/drm/panthor/panthor_gpu.c.orig

        if [[ $bad_rej -gt 0 ]]; then
            echo -e "  ${RED}ÉCHEC${NC}  $pname — $bad_rej .rej inattendus"
            ((failed++)) || true
            return 1
        fi
        echo -e "  ${GREEN}OK${NC}  $pname — autres hunks appliqués (hunk #1 ignoré)"
        ((applied++)) || true
        return 0
    # Cas 5 — contexte inconnu
    else
        echo -e "  ${RED}FIX IMPOSSIBLE${NC}  Contexte panthor_gpu.c inattendu — inspection manuelle requise"
        echo "  Lignes trouvées:"
        grep -n "coherent\|coherency_mode" "$target" | head -10
        return 1
    fi

    # Vérification : aucun .rej dans panthor, et le hunk SHAREABLE_CACHE est bien là
    local bad_rej=0
    for rej in $(find drivers/gpu/drm/panthor/ -name "*.rej" 2>/dev/null); do
        echo -e "  ${RED}REJ inattendu: $rej${NC}"
        ((bad_rej++)) || true
    done

    if [[ $bad_rej -gt 0 ]]; then
        echo -e "  ${RED}ÉCHEC${NC}  $pname — $bad_rej .rej"
        ((failed++)) || true
        return 1
    fi

    if ! grep -q "GPU_COHERENCY_SHAREABLE_CACHE" "$target"; then
        echo -e "  ${RED}ÉCHEC${NC}  $pname — SHAREABLE_CACHE absent de panthor_gpu.c après application"
        ((failed++)) || true
        return 1
    fi

    echo -e "  ${GREEN}OK${NC}  $pname — hunk panthor_gpu.c vérifié (SHAREABLE_CACHE présent)"
    return 0
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
        [0-9][0-9][0-9][0-9]-drm-panthor-add-ACE-Lite-coherency-*)
            # Conflit connu — hunk #1 de panthor_gpu.c (numéro variable selon le track)
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
echo -e "  Ignorés    : ${CYAN}$skipped${NC}"
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
