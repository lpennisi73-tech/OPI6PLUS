# =============================================================================
# dts-disable-empty-pcie-slots.py
# Désactiver les slots PCIe vides dans le DTS OrangePi 6 Plus
#
# Contexte:
#   Le DTS sky1-orangepi-6-plus.dts active tous les slots PCIe avec
#   status = "okay" même ceux sans périphérique connecté.
#   Sur ARM64, accéder à un slot vide génère un SError fatal.
#
#   Slots à désactiver sur OrangePi 6 Plus standard:
#     pcie_x4_rc  (a070000) — slot X4 vide
#     pcie_x4_phy           — PHY du slot X4
#     pcie_x1_0_rc (a0d0000) — slot X1_0 WiFi (non monté)
#     pcie1_phy             — PHY associé
#
#   Slots à conserver actifs:
#     pcie_x8_rc  (a010000) — NVMe SSD ✅
#     pcie_x2_rc  (a0c0000) — RTL8126 5GbE eth0 ✅
#     pcie_x1_1_rc (a0e0000) — RTL8126 5GbE eth1 ✅
#
# Fichier: arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts
# Utilisé par: bookworm-sky1-build.sh Phase DTS fixes
# =============================================================================

import sys

TARGET = "arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts"

# Noeuds DTS à désactiver
DISABLE_NODES = [
    "&pcie_x4_rc {",
    "&pcie_x4_phy {",
    "&pcie_x1_0_rc {",
    "&pcie1_phy {",
]

def apply_fix():
    try:
        with open(TARGET, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"ERREUR: {TARGET} introuvable")
        sys.exit(1)

    changed = []
    in_block = False
    current_node = ""
    already_disabled = []

    for i, line in enumerate(lines):
        stripped = line.strip()

        # Détecter entrée dans un noeud cible
        for node in DISABLE_NODES:
            if stripped == node:
                in_block = True
                current_node = node
                break

        # Dans un bloc cible — chercher le status
        if in_block:
            if 'status = "disabled"' in line:
                already_disabled.append(current_node)
                in_block = False
                current_node = ""
            elif 'status = "okay"' in line:
                lines[i] = line.replace('status = "okay"', 'status = "disabled"')
                changed.append(f"  ligne {i+1}: {current_node} → disabled")
                in_block = False
                current_node = ""
            elif stripped == "};":
                # Fin de bloc sans status trouvé
                in_block = False
                current_node = ""

    if already_disabled:
        print("Déjà désactivés:")
        for n in already_disabled:
            print(f"  SKIP {n}")

    if changed:
        with open(TARGET, 'w') as f:
            f.writelines(lines)
        print("Modifiés:")
        for c in changed:
            print(c)
        print(f"OK — {len(changed)} slot(s) désactivé(s)")
    else:
        if not already_disabled:
            print("AVERTISSEMENT — Aucun noeud modifié")
            print("  Vérifier que le DTS correspond bien à l'OrangePi 6 Plus")
        else:
            print("OK — Tous les slots déjà désactivés")

if __name__ == "__main__":
    apply_fix()
