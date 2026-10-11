#!/usr/bin/env bash
# set-locale.sh - langue, clavier (console + GDM/GNOME) et fuseau, Gentoo/OpenRC.
# Usage : sudo ./set-locale.sh --lang fr_CH [--tz Europe/Zurich] [--kbd ch:fr --console fr_CH] [--dry-run]
# Facultatif, hors install.sh. Sauvegarde chaque fichier modifié dans /root/set-locale-bak/<date>/.
set -euo pipefail

LANG_ID="" TZ_ID="" KBD="" CON="" DRY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --lang) LANG_ID="$2"; shift 2 ;;
        --tz)   TZ_ID="$2"; shift 2 ;;
        --kbd)  KBD="$2"; shift 2 ;;      # ex: ch:fr (disposition[:variante])
        --console) CON="$2"; shift 2 ;;   # ex: fr_CH (keymap console)
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
        *) echo "Option inconnue : $1" >&2; exit 1 ;;
    esac
done
[[ $LANG_ID =~ ^[a-z]{2}_[A-Z]{2}$ ]] || { echo "Il faut --lang xx_YY (ex: fr_CH)" >&2; exit 1; }
[[ $EUID -eq 0 || $DRY -eq 1 ]] || { echo "À lancer en root (ou --dry-run)" >&2; exit 1; }

# langue -> "disposition_X11 variante keymap_console"
case "$LANG_ID" in
    fr_CH) MAP="ch fr fr_CH" ;;   de_CH) MAP="ch - de_CH" ;;
    fr_FR) MAP="fr - fr" ;;       fr_BE) MAP="be - be-latin1" ;;
    de_DE) MAP="de - de" ;;       it_IT) MAP="it - it" ;;
    es_ES) MAP="es - es" ;;       en_GB) MAP="gb - uk" ;;
    en_US) MAP="us - us" ;;       pt_BR) MAP="br - br-abnt2" ;;
    *) c="${LANG_ID#*_}"; MAP="${c,,} - -" ;;
esac
read -r XLAYOUT XVARIANT KEYMAP <<<"$MAP"
[[ $XVARIANT == "-" ]] && XVARIANT=""
if [[ -n $KBD ]]; then   # clavier indépendant de la langue
    XLAYOUT="${KBD%%:*}"; XVARIANT=""; [[ $KBD == *:* ]] && XVARIANT="${KBD#*:}"
    KEYMAP="${CON:--}"
fi

STAMP=$(date +%Y%m%d-%H%M%S)
run()    { if ((DRY)); then echo "[dry-run] $*"; else "$@"; fi; }
BK="/root/set-locale-bak/$STAMP"   # hors de /etc : env-update lit tout fichier 0Xxxx de env.d, y compris *.bak-date
backup() { [[ -e $1 ]] || return 0; run mkdir -p "$BK$(dirname "$1")"; run cp -a "$1" "$BK$1"; }

echo "== Langue ${LANG_ID}.UTF-8 | X11 ${XLAYOUT}${XVARIANT:+/$XVARIANT} | console ${KEYMAP} | tz ${TZ_ID:-inchangé}"

# 1. locale
if ! grep -qE "^${LANG_ID}\.UTF-8 UTF-8" /etc/locale.gen 2>/dev/null; then
    backup /etc/locale.gen
    run bash -c "echo '${LANG_ID}.UTF-8 UTF-8' >> /etc/locale.gen"
fi
backup /etc/env.d/02locale
run locale-gen
run eselect locale set "${LANG_ID}.utf8"
run env-update

# 2. console
if [[ $KEYMAP != "-" ]] && find /usr/share/keymaps -name "${KEYMAP}.map*" 2>/dev/null | grep -q .; then
    backup /etc/conf.d/keymaps
    run sed -i -E "s|^#?keymap=.*|keymap=\"${KEYMAP}\"|" /etc/conf.d/keymaps
else
    echo "Keymap console '${KEYMAP}' introuvable : étape ignorée"
fi

# 3. X11/Wayland + GDM (via openrc-settingsd / locale1)
#    Note : SetX11Keyboard échoue si 30-keyboard.conf n'existe pas -> on l'écrit nous-mêmes.
KBD=/etc/X11/xorg.conf.d/30-keyboard.conf
backup "$KBD"
run mkdir -p /etc/X11/xorg.conf.d
{
    echo 'Section "InputClass"'
    echo '        Identifier "system-keyboard"'
    echo '        MatchIsKeyboard "on"'
    echo "        Option \"XkbLayout\" \"${XLAYOUT}\""
    [[ -n $XVARIANT ]] && echo "        Option \"XkbVariant\" \"${XVARIANT}\""
    echo 'EndSection'
} > "/tmp/kbd.$$"
run install -m 644 "/tmp/kbd.$$" "$KBD"; rm -f "/tmp/kbd.$$"
run pkill -f openrc-settingsd || true   # relu au prochain appel D-Bus

# 4. fuseau (optionnel)
if [[ -n $TZ_ID ]]; then
    [[ -f /usr/share/zoneinfo/$TZ_ID ]] || { echo "Fuseau inconnu : $TZ_ID" >&2; exit 1; }
    backup /etc/timezone
    run bash -c "echo '$TZ_ID' > /etc/timezone"
    run ln -sf "/usr/share/zoneinfo/$TZ_ID" /etc/localtime
fi

echo "Terminé. REDÉMARRE la machine (sudo reboot) pour appliquer langue et clavier."
echo "Un simple redémarrage de GDM ne suffit pas et peut figer l'affichage."
echo "Session GNOME : si la langue du compte reste l'ancienne, Paramètres > Région et langue."
