# =============================================================================
# npu-sky1-pm-runtime-fix.py
# Fix driver NPU ArmChina Sky1 pour Linux 7.0
#
# Contexte:
#   Dans Linux 7.0, pm_runtime_put() retourne void au lieu de int.
#   Le driver NPU Sky1 utilise la valeur de retour — erreur de compilation.
#
#   Fix 1 — sky1_npu_pm_runtime_put():
#     Remplacer: int ret = 0; ret = pm_runtime_put(dev); if (ret<0)... return ret;
#     Par:       pm_runtime_put(dev); return 0;
#
#   Fix 2 — sky1_npu_runtime_suspend() boucle for:
#     Remplacer: ret = pm_runtime_put(...); if (ret<0) { ... return ret; }
#     Par:       pm_runtime_put(...);
#
#   Fix 3 — Désactiver CHROMEOS_PRIVACY_SCREEN dans .config
#
# Fichier: drivers/misc/armchina-npu/sky1/sky1.c
# =============================================================================

import sys
import os

NPU_FILE = "drivers/misc/armchina-npu/sky1/sky1.c"
CONFIG_FILE = ".config"

# Contenu original exact (depuis patch 0016)
OLD_FIX1 = """\tint ret = 0;

\tret = pm_runtime_put(dev);
\tif (ret < 0)
\t\tdev_err(dev, "PM runtime put failed! ret=%d", ret);

\treturn ret;"""

NEW_FIX1 = """\tpm_runtime_put(dev);

\treturn 0;"""

OLD_FIX2 = """\t\tfor (int i = 0; i < CIX_NPU_PD_NUM; i++) {
\t\t\tret = pm_runtime_put(cix_aipu_priv->pd_core[i]);
\t\t\tif (ret < 0) {
\t\t\t\tdev_err(cix_aipu_priv->pd_core[i], "NPU core PM runtime put failed! ret=%d", ret);
\t\t\t\treturn ret;
\t\t\t}
\t\t}"""

NEW_FIX2 = """\t\tfor (int i = 0; i < CIX_NPU_PD_NUM; i++) {
\t\t\tpm_runtime_put(cix_aipu_priv->pd_core[i]);
\t\t}"""


def fix_npu_pm_runtime():
    if not os.path.exists(NPU_FILE):
        print(f"SKIP — {NPU_FILE} introuvable")
        return

    with open(NPU_FILE, 'r') as f:
        content = f.read()

    # Vérifier si déjà appliqué
    if OLD_FIX1 not in content and OLD_FIX2 not in content:
        print("SKIP — NPU pm_runtime fix déjà appliqué")
        return

    changed = []

    if OLD_FIX1 in content:
        content = content.replace(OLD_FIX1, NEW_FIX1, 1)
        changed.append("Fix 1 — sky1_npu_pm_runtime_put")

    if OLD_FIX2 in content:
        content = content.replace(OLD_FIX2, NEW_FIX2, 1)
        changed.append("Fix 2 — sky1_npu_runtime_suspend boucle for")

    with open(NPU_FILE, 'w') as f:
        f.write(content)

    print("OK — NPU pm_runtime_put fixes appliqués:")
    for c in changed:
        print(f"  {c}")


def fix_chromeos_privacy_screen():
    if not os.path.exists(CONFIG_FILE):
        print(f"SKIP — {CONFIG_FILE} introuvable")
        return

    with open(CONFIG_FILE, 'r') as f:
        content = f.read()

    if 'CHROMEOS_PRIVACY_SCREEN=m' in content:
        content = content.replace(
            'CHROMEOS_PRIVACY_SCREEN=m',
            '# CHROMEOS_PRIVACY_SCREEN is not set'
        )
        with open(CONFIG_FILE, 'w') as f:
            f.write(content)
        print("OK — CHROMEOS_PRIVACY_SCREEN désactivé")
    elif 'CHROMEOS_PRIVACY_SCREEN=y' in content:
        content = content.replace(
            'CHROMEOS_PRIVACY_SCREEN=y',
            '# CHROMEOS_PRIVACY_SCREEN is not set'
        )
        with open(CONFIG_FILE, 'w') as f:
            f.write(content)
        print("OK — CHROMEOS_PRIVACY_SCREEN désactivé")
    else:
        print("SKIP — CHROMEOS_PRIVACY_SCREEN déjà désactivé")


if __name__ == "__main__":
    fix_npu_pm_runtime()
    fix_chromeos_privacy_screen()
