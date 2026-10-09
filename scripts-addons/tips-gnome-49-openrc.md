# GNOME 49 + OpenRC (Gentoo) : fixes validés le 2026-10-08

Contexte : après l'upgrade @world du 2026-10-07 (gnome-session-openrc 49.2-r1, gdm 49.2-r4, pipewire 1.6.8, wireplumber 0.5.15, elogind 255.24, openrc 0.63.3, sysvinit 3.15). Noyau 6.18.14 inchangé. Symptômes : plus de son, pas de curseur de volume ni d'« Éteindre » dans le menu GNOME, arrêt/reboot depuis GNOME qui échoue. `poweroff -f` marchait (donc noyau/BIOS OK).

## 1. Son absent
Les services OpenRC utilisateur existent dans /etc/user/init.d mais ne sont dans aucun runlevel (l'autostart pipewire.desktop est masqué par X-GNOME-HiddenUnderSystemd).
Fix, en utilisateur :
    rc-update -U add pipewire gnome-session
    rc-update -U add wireplumber gnome-session
    rc-update -U add pipewire-pulse gnome-session
(`rc-update -U add … default` est refusé : « default is not a valid runlevel ».)

## 2. Menu sans volume ni « Éteindre », arrêt/reboot GNOME en échec (cause racine)
gdm-wayland-session crée un bus D-Bus privé (/tmp/dbus-…). Dans /etc/user/init.d/gnome-shell-wayland, start_pre() recopie l'environnement du leader (/proc/<leader>/environ) et écrase DBUS_SESSION_BUS_ADDRESS=unix:path=${XDG_RUNTIME_DIR}/bus. Le shell et les applications sont alors sur un autre bus que gnome-session-service et les gsd-*, donc le shell ne voit pas org.gnome.SessionManager.
Fix : ajouter à la fin de start_pre() :
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
(sauvegarde de l'original : /root/gnome-shell-wayland.orig ; fichier sous /etc donc Portage proposera une fusion via etc-update).
Vérification :
    tr '\0' '\n' < /proc/$(pgrep -n -f 'bin/gnome-shell --wayland')/environ | grep '^DBUS_SESSION'
    gdbus call --session --dest org.gnome.SessionManager --object-path /org/gnome/SessionManager --method org.gnome.SessionManager.CanShutdown
Résultat : volume, « Éteindre » et « Redémarrer » depuis le menu fonctionnent (5 essais), sans contournement.

## 3. Contournement abandonné
/etc/local.d/10-stop-dm.stop (rc-service display-manager stop) n'est plus nécessaire.

## Bruit sans conséquence
- RealtimeKit1 absent (rtkit non installé), bolt.enroll non enregistré (bolt non installé).
- « Failed to open gpu /dev/dri/card0 » : GPU Panthor sans affichage, mutter utilise card1 (linlondp).
- « Couldn't set runlevel stack / File exists » et « Session termination requested » du gnome-session-init-worker : normaux.
- 7.0-next : ~389 warnings dtc « CIX_PAD_GPIOxxx redéfini » (sky1-pinfunc.h vs dt-bindings/pinctrl/pads-sky1.h), build non bloquée.

## À faire
- Nouveaux utilisateurs : liens rc-update -U dans /etc/skel/.config/rc/runlevels/gnome-session/ + correctif du script dans install.sh.
- Signaler le défaut à Gentoo (gnome-base/gnome-session-openrc).

## 4. gnome-control-center (et apps D-Bus-activables) ne démarrent pas depuis le dash
Cause : le dash lance l'appli par activation D-Bus (DBusActivatable=true) ; l'environnement d'activation du bus OpenRC est vide (pas de WAYLAND_DISPLAY, XDG_CURRENT_DESKTOP...), le processus sort avec le statut 1. Depuis un terminal ça marche (env hérité).
Diagnostic :
    gdbus call --session --dest org.gnome.Settings --object-path /org/gnome/Settings --method org.freedesktop.Application.Activate '{}'
    -> « Process org.gnome.Settings exited with status 1 »
Fix : service utilisateur /etc/user/init.d/bookworm-activation-env (créé par fix-gnome49-openrc.sh) qui attend le socket wayland-N et gnome-shell, relit son environ et appelle dbus-update-activation-environment, en arrière-plan. Activé dans le runlevel gnome-session de chaque utilisateur et dans /etc/skel :
    rc-update -U add bookworm-activation-env gnome-session
Ne pas ajouter de start_post() dans gnome-shell-wayland : ça a cassé la session.
