# =============================================================================
# 0118-panthor-coherency-fix.py
# Fix pour le patch 0118 Sky1 — migration API coherency panthor_gpu.c
#
# Contexte:
#   Le patch 0118 (ACE-Lite coherency) migre ptdev->coherent vers
#   ptdev->coherency_mode dans panthor_gpu.c. Le hunk #1 échoue sur
#   kernel 6.19 car le contexte de panthor_gpu_coherency_set() a bougé.
#   On applique la correction manuellement avant le patch.
#
# Utilisé par: apply-sky1-patches.sh via case "0118-*"
# =============================================================================

import sys

TARGET = "drivers/gpu/drm/panthor/panthor_gpu.c"

def apply_fix():
    try:
        with open(TARGET, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"ERREUR: {TARGET} introuvable")
        sys.exit(1)

    # Chercher la ligne "u32 sta;" dans sky1_pcie_local_irq_handler
    # On cherche le pattern exact à corriger
    old_pattern = "\t\tptdev->coherent ? GPU_COHERENCY_PROT_BIT(ACE_LITE) : GPU_COHERENCY_NONE);"
    new_pattern = "\t\tptdev->coherency_mode == PANTHOR_COHERENCY_NONE ?\n\t\tGPU_COHERENCY_NONE : GPU_COHERENCY_PROT_BIT(ACE_LITE));"

    found = False
    for i, line in enumerate(lines):
        if old_pattern in line:
            lines[i] = line.replace(old_pattern, new_pattern)
            found = True
            print(f"OK — Ligne {i+1} corrigée : coherency API migration")
            break

    if not found:
        # Vérifier si déjà appliqué
        for line in lines:
            if "ptdev->coherency_mode == PANTHOR_COHERENCY_NONE" in line:
                print("SKIP — Fix déjà appliqué")
                sys.exit(0)
        print("ERREUR — Pattern non trouvé dans panthor_gpu.c")
        print("  Ce fix est peut-être inutile sur cette version du kernel")
        sys.exit(1)

    with open(TARGET, 'w') as f:
        f.writelines(lines)

    print(f"Fichier mis à jour: {TARGET}")

if __name__ == "__main__":
    apply_fix()
