#!/bin/bash
# =============================================================================
# fix-gnome49-openrc.sh — correctifs GNOME 49 sous OpenRC (BOOKWORM)
#  1) gnome-shell-wayland : start_pre() recopie l'env du leader (gdm-wayland-session)
#     et écrase DBUS_SESSION_BUS_ADDRESS par le bus privé /tmp -> on force le bus OpenRC
#  2) services son (pipewire, wireplumber, pipewire-pulse) dans le runlevel utilisateur
#  3) /etc/skel pour les futurs utilisateurs
#  4) service utilisateur bookworm-activation-env : pousse l'env GNOME dans l'activation
#     D-Bus (sinon gnome-control-center & co ne démarrent pas depuis le dash)
# Usage : sudo ./fix-gnome49-openrc.sh [--check] [--user NOM]... [--all-users] [--skel]
# Voir tips-gnome-49-openrc.md. Relancer après une mise à jour de gnome-session-openrc.
# =============================================================================
set -euo pipefail

INITD=/etc/user/init.d
SERVICES=(pipewire wireplumber pipewire-pulse bookworm-activation-env)
CHECK=0; SKEL=0; ALL=0; GREETER=0; USERS=()

ok()   { echo " [ok]   $*"; }
warn() { echo " [!]    $*"; }
die()  { echo " [ERR]  $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --check) CHECK=1 ;;
    --skel) SKEL=1 ;;
    --greeter) GREETER=1 ;;   # aussi l'ecran de connexion (gnome-shell-wayland.gnome-login)
    --all-users) ALL=1 ;;
    --user) shift; USERS+=("${1:?--user demande un nom}") ;;
    *) die "option inconnue : $1" ;;
  esac; shift
done
[[ $CHECK -eq 1 || $EUID -eq 0 ]] || die "à lancer en root (ou --check)"
[[ -d $INITD ]] || die "$INITD absent : gnome-session-openrc n'est pas installé"

patch_shell() {
  local f real; local -A seen=()
  for f in "$INITD"/gnome-shell-wayland*; do
    [[ -e $f ]] || continue
    [[ $GREETER -eq 0 && $f != "$INITD/gnome-shell-wayland" ]] && continue
    real=$(readlink -f "$f")
    [[ -n ${seen[$real]:-} ]] && continue; seen[$real]=1
    [[ -f $real ]] || continue
    if grep -qE 'export DBUS_SESSION_BUS_ADDRESS="unix' "$real"; then ok "bus déjà forcé : $real"; continue; fi
    if ! grep -qE 'done < /proc/.*_gsl_file.*/environ' "$real"; then
      warn "motif start_pre introuvable dans $real (paquet modifié ? peut-être corrigé en amont) : rien changé"; continue
    fi
    if [[ $CHECK -eq 1 ]]; then warn "à corriger : $real"; continue; fi
    [[ -e $real.bookworm.orig ]] || cp -a "$real" "$real.bookworm.orig"
    awk '{print}
      /done < \/proc\/.*_gsl_file.*\/environ/ && !d {
        print ""
        print "\t# bookworm: forcer le bus OpenRC (le leader gdm-wayland-session expose un bus prive /tmp)"
        print "\texport DBUS_SESSION_BUS_ADDRESS=\"unix:path=${XDG_RUNTIME_DIR}/bus\""
        d=1 }' "$real.bookworm.orig" > "$real.tmp"
    cat "$real.tmp" > "$real"; rm -f "$real.tmp"
    ok "corrigé : $real (sauvegarde : $real.bookworm.orig)"
  done
}

link_services() {  # $1 = dossier runlevels/gnome-session, $2 = utilisateur (vide = root/skel)
  local d=$1 u=${2:-} s run=()
  [[ -n $u ]] && run=(runuser -u "$u" --)
  for s in "${SERVICES[@]}"; do
    [[ -e $INITD/$s ]] || { warn "service absent : $INITD/$s"; continue; }
    if [[ -L $d/$s ]]; then ok "$s déjà activé ($d)"; continue; fi
    if [[ $CHECK -eq 1 ]]; then warn "manque : $s ($d)"; continue; fi
    "${run[@]}" mkdir -p "$d"
    "${run[@]}" ln -sf "$INITD/$s" "$d/$s"
    ok "$s activé ($d)"
  done
}

install_activation_env() {
  local f=$INITD/bookworm-activation-env tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF_SVC'
#!/sbin/openrc-run
description="bookworm: env GNOME -> activation D-Bus (gnome-control-center & co)"

start() {
	(
		i=0
		while [ $i -lt 60 ]; do
			pid=$(pgrep -u "$(id -u)" -n -f 'bin/gnome-shell --wayland')
			sock=$(ls "${XDG_RUNTIME_DIR}" 2>/dev/null | grep -m1 -E '^wayland-[0-9]+$')
			[ -n "$pid" ] && [ -n "$sock" ] && break
			sleep 1; i=$((i+1))
		done
		[ -n "$pid" ] || exit 0
		while read -r -d '' l; do
			case "$l" in XDG_*|DESKTOP_SESSION=*|GDMSESSION=*) export "$l";; esac
		done < /proc/$pid/environ
		export WAYLAND_DISPLAY="$sock"
		dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE \
			XDG_SESSION_DESKTOP XDG_SESSION_ID DESKTOP_SESSION XDG_DATA_DIRS XDG_CONFIG_DIRS
	) >/dev/null 2>&1 &
	return 0
}
EOF_SVC
  if cmp -s "$tmp" "$f" 2>/dev/null; then ok "service déjà à jour : $f"; rm -f "$tmp"; return 0; fi
  if [[ $CHECK -eq 1 ]]; then warn "à créer/mettre à jour : $f"; rm -f "$tmp"; return 0; fi
  install -m 755 "$tmp" "$f"; rm -f "$tmp"
  ok "service installé : $f"
}

if [[ $ALL -eq 1 ]]; then
  mapfile -t USERS < <(getent passwd | awk -F: '$3>=1000 && $3<60000 && $7 !~ /nologin|false/ {print $1}')
fi

install_activation_env
patch_shell
for u in "${USERS[@]}"; do
  home=$(getent passwd "$u" | cut -d: -f6)
  [[ -n $home && -d $home ]] || { warn "utilisateur ou home introuvable : $u"; continue; }
  link_services "$home/.config/rc/runlevels/gnome-session" "$u"
done
[[ $SKEL -eq 1 ]] && link_services /etc/skel/.config/rc/runlevels/gnome-session
echo "Terminé. Reconnexion nécessaire pour appliquer (déconnexion/reconnexion GNOME)."
