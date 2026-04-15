# =============================================================================
# npu-sky1-pm-runtime-fix.py
# Fix driver NPU ArmChina Sky1 pour Linux 7.0
#
# Contexte:
#   Dans Linux 7.0, pm_runtime_put() retourne void au lieu de int.
#   Le driver NPU Sky1 (armchina-npu/sky1/sky1.c) utilise la valeur
#   de retour — ce qui cause des erreurs de compilation.
#
#   Corrections:
#     1. sky1_npu_pm_runtime_put(): supprimer ret = pm_runtime_put()
#     2. sky1_npu_attach_pd(): supprimer vérification ret après pm_runtime_put()
#     3. Désactiver CHROMEOS_PRIVACY_SCREEN (symboles DRM manquants)
#
# Fichier: drivers/misc/armchina-npu/sky1/sky1.c
# =============================================================================

import sys
import os
import subprocess

NPU_FILE = "drivers/misc/armchina-npu/sky1/sky1.c"
CONFIG_FILE = ".config"

def fix_npu_pm_runtime():
    try:
        with open(NPU_FILE, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"SKIP — {NPU_FILE} introuvable")
        return True

    # Vérifier si déjà appliqué
    content = ''.join(lines)
    if 'pm_runtime_put(dev);\n\treturn 0;' in content.replace('\n\n', '\n'):
        print("SKIP — NPU pm_runtime fix déjà appliqué")
        return True

    # Trouver et corriger la fonction sky1_npu_pm_runtime_put
    # Chercher le pattern: int ret = 0; \n\n\t ret = pm_runtime_put(dev);
    fixed = False
    i = 0
    while i < len(lines):
        # Détecter le bloc à corriger dans sky1_npu_pm_runtime_put
        if (i + 5 < len(lines) and
            '\tint ret = 0;\n' in lines[i] and
            'pm_runtime_put(dev)' in lines[i+1] or
            (lines[i].strip() == 'int ret = 0;' and
             i + 2 < len(lines) and 'pm_runtime_put(dev)' in lines[i+2])):

            # Trouver les lignes exactes
            start = i
            end = start
            while end < len(lines) and 'return ret;' not in lines[end]:
                end += 1

            if end < len(lines):
                # Remplacer tout le bloc par version void
                new_block = [
                    '\tpm_runtime_put(dev);\n',
                    '\n',
                    '\treturn 0;\n'
                ]
                lines[start:end+1] = new_block
                fixed = True
                break
        i += 1

    # Fix 2 — boucle for avec pm_runtime_put sur pd_core
    i = 0
    while i < len(lines):
        if ('ret = pm_runtime_put(cix_aipu_priv->pd_core' in lines[i]):
            # Trouver le début du for
            for_start = i - 1
            while for_start >= 0 and 'for (int i = 0' not in lines[for_start]:
                for_start -= 1

            # Trouver la fin du bloc if
            end = i + 1
            while end < len(lines) and lines[end].strip() not in ['}', '']:
                end += 1
            # Avancer jusqu'à la fermeture du for
            while end < len(lines) and '\t\t}' not in lines[end]:
                end += 1

            if for_start >= 0:
                new_for = [
                    lines[for_start],  # garder la ligne for
                    f'\t\t\tpm_runtime_put(cix_aipu_priv->pd_core[i]);\n',
                    '\t\t}\n'
                ]
                lines[for_start:end+1] = new_for
                fixed = True
                break
        i += 1

    with open(NPU_FILE, 'w') as f:
        f.writelines(lines)

    if fixed:
        print("OK — NPU pm_runtime_put fixes appliqués")
    else:
        print("WARN — Pattern non trouvé, fix manuel peut être nécessaire")

    return True

def fix_chromeos_privacy_screen():
    if not os.path.exists(CONFIG_FILE):
        print(f"SKIP — {CONFIG_FILE} introuvable")
        return True

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
    else:
        print("SKIP — CHROMEOS_PRIVACY_SCREEN déjà désactivé ou absent")

    return True

if __name__ == "__main__":
    fix_npu_pm_runtime()
    fix_chromeos_privacy_screen()
