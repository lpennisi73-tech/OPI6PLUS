# =============================================================================
# pci-sky1-link-down-guard.py
# Fix pour sky1_pcie_local_irq_handler — guard slot PCIe vide
#
# Contexte:
#   Le driver sky1_pcie tente d'accéder aux registres PCIe même quand
#   le lien est down (slot vide). Sur ARM64 cela génère un SError fatal
#   (Asynchronous SError Interrupt) qui provoque un kernel panic.
#
#   Fix: ajouter une vérification sky1_pcie_link_up() avant tout accès
#   registre dans sky1_pcie_local_irq_handler().
#
#   Affecte: OrangePi 6 Plus avec slots PCIe X4 et/ou X1_0 vides
#   Fichier:  drivers/pci/controller/cadence/pci-sky1.c
#
# Utilisé par: apply-sky1-patches.sh Phase fixes
# =============================================================================

import sys

TARGET = "drivers/pci/controller/cadence/pci-sky1.c"

GUARD = [
    '\n',
    '\t/* Guard: do not access registers if PCIe link is down —\n',
    '\t * accessing registers on an empty slot causes ARM64 SError fatal.\n',
    '\t * Fix by BOOKWORM/Kenny for OrangePi 6 Plus Sky1 kernel.\n',
    '\t */\n',
    '\tif (!sky1_pcie_link_up(pcie->cdns_pcie)) {\n',
    '\t\tdev_dbg(pcie->dev, "IRQ on link-down slot, ignoring\\n");\n',
    '\t\treturn IRQ_HANDLED;\n',
    '\t}\n',
    '\n',
]

def apply_fix():
    try:
        with open(TARGET, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"ERREUR: {TARGET} introuvable")
        sys.exit(1)

    # Vérifier si déjà appliqué
    for line in lines:
        if "Guard: do not access registers if PCIe link is down" in line:
            print("SKIP — Fix déjà appliqué")
            sys.exit(0)

    # Trouver la fonction sky1_pcie_local_irq_handler
    irq_handler_line = -1
    u32_sta_line = -1

    for i, line in enumerate(lines):
        if "static irqreturn_t sky1_pcie_local_irq_handler" in line:
            irq_handler_line = i
        if irq_handler_line > 0 and "\tu32 sta;" in line:
            u32_sta_line = i
            break

    if irq_handler_line < 0:
        print("ERREUR — Fonction sky1_pcie_local_irq_handler non trouvée")
        sys.exit(1)

    if u32_sta_line < 0:
        print("ERREUR — Variable u32 sta; non trouvée dans la fonction")
        sys.exit(1)

    print(f"  Fonction trouvée ligne {irq_handler_line+1}")
    print(f"  Insertion guard après ligne {u32_sta_line+1}: {lines[u32_sta_line].rstrip()}")

    # Insérer le guard après "u32 sta;"
    lines = lines[:u32_sta_line+1] + GUARD + lines[u32_sta_line+1:]

    with open(TARGET, 'w') as f:
        f.writelines(lines)

    print(f"OK — Guard inséré dans {TARGET}")

if __name__ == "__main__":
    apply_fix()
