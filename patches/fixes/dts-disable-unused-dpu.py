# =============================================================================
# dts-disable-unused-dpu.py
# Désactiver les contrôleurs display inutilisés dans le DTS OrangePi 6 Plus
#
# Contexte:
#   Le DTS active 5 paires DPU/DP (dpu0-4 / dp0-4). L'OrangePi 6 Plus n'a
#   que deux sorties utilisables : DP natif (dp3) et HDMI via le convertisseur
#   Parade PS185HDM (dp4 → hdmi-connector). Les autres dp sans écran provoquent
#   une boucle DRM infinie avec GDM.
#
#   Mapping:
#     dpu0/dp0 (14010000/14064000) — DISABLED
#     dpu1/dp1 (14080000/140d4000) — DISABLED
#     dpu2/dp2 (140f0000/14144000) — DISABLED
#     dpu3/dp3 (14160000/141b4000) — ACTIF (DP natif)
#     dpu4/dp4 (141d0000/14224000) — ACTIF (HDMI via ps185hdm, patch 9006)
#
#   Audio: les dai-links dptx0_audio / dptx1_audio pointent vers des DP
#   désactivés ; ils doivent l'être aussi, sinon la carte son (cix,sky1-sound-card)
#   reste en EPROBE_DEFER. dptx3_audio (DP) et dptx4_audio (HDMI) restent actifs.
#
# Fichier: arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts
# =============================================================================

import sys

TARGET = "arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts"

DPU_DISABLE = ["&dpu0 {", "&dpu1 {", "&dpu2 {"]

DP_DISABLE_BLOCK = """
/* Disable unused DP controllers and their audio links.
 * Kept: dp3 (native DP) and dp4 (HDMI via ps185hdm).
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

&dpu4 {
\tstatus = "okay";
};

&dp4 {
\tstatus = "okay";
};

&dptx0_audio {
\tstatus = "disabled";
};

&dptx1_audio {
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
    if "&dptx0_audio {" in content:
        print("SKIP — DP/audio déjà désactivés")
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
    print("DP désactivés: &dp0, &dp1, &dp2 ; audio: &dptx0_audio, &dptx1_audio")
    print("Conservés: dpu3+dp3 (DP natif), dpu4+dp4 (HDMI via ps185hdm)")

if __name__ == "__main__":
    apply_fix()
