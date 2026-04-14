# =============================================================================
# dts-disable-unused-dpu.py
# Désactiver les contrôleurs display inutilisés dans le DTS OrangePi 6 Plus
#
# Contexte:
#   Le DTS active 5 paires DPU/DP (dpu0-4 / dp0-4) mais l'OrangePi 6 Plus
#   n'a qu'un seul écran connecté sur dp3 (141b4000) — hpd=1.
#   Les autres dp sans écran provoquent une boucle DRM infinie avec GDM.
#
#   Mapping:
#     dpu0/dp0 (14010000/14064000) — hpd=0 → DISABLED
#     dpu1/dp1 (14080000/140d4000) — hpd=0 → DISABLED
#     dpu2/dp2 (140f0000/14144000) — hpd=0 → DISABLED
#     dpu3/dp3 (14160000/141b4000) — hpd=1 → ACTIF ✅
#     dpu4/dp4 (141d0000/14224000) — hpd=0 → DISABLED
#
# Fichier: arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts
# =============================================================================

import sys

TARGET = "arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts"

DPU_DISABLE = ["&dpu0 {", "&dpu1 {", "&dpu2 {", "&dpu4 {"]

DP_DISABLE_BLOCK = """
/* Disable unused DP controllers — only dp3 (141b4000) has display connected
 * hpd=1 only on dp3 — others cause DRM probe loop with GDM
 * Added by BOOKWORM Sky1 Kernel Builder
 */
&dp0 {
\tstatus = "disabled";
};

&dp1 {
\tstatus = "disabled";
};

&dp2 {
\tstatus = "disabled";
};

&dp4 {
\tstatus = "disabled";
};
"""

def apply_fix():
    try:
        with open(TARGET, 'r') as f:
            lines = f.readlines()
            content = ''.join(lines)
    except FileNotFoundError:
        print(f"ERREUR: {TARGET} introuvable")
        sys.exit(1)

    # Vérifier si déjà appliqué
    if "&dp0 {" in content and "disabled" in content.split("&dp0 {")[-1][:80]:
        print("SKIP — DP déjà désactivés")
        sys.exit(0)

    changed_dpu = []
    in_block = False
    current = ""

    for i, line in enumerate(lines):
        stripped = line.strip()
        for node in DPU_DISABLE:
            if stripped == node:
                in_block = True
                current = node
                break
        if in_block and 'status = "okay"' in line:
            lines[i] = line.replace('status = "okay"', 'status = "disabled"')
            changed_dpu.append(f"  ligne {i+1}: {current} → disabled")
            in_block = False
            current = ""
        elif in_block and stripped == "};":
            in_block = False
            current = ""

    content_new = ''.join(lines).rstrip() + "\n" + DP_DISABLE_BLOCK

    with open(TARGET, 'w') as f:
        f.write(content_new)

    print("DPU désactivés:")
    for c in changed_dpu:
        print(c)
    print("DP désactivés: &dp0, &dp1, &dp2, &dp4")
    print("Conservé: dpu3 + dp3 (141b4000) — hpd=1 HDMI ✅")

if __name__ == "__main__":
    apply_fix()
