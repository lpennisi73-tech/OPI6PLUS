# GNOME 49 + OpenRC (Gentoo) : fixes validés du 2026-10-08 au 2026-10-10

Contexte : après l'upgrade @world du 2026-10-07 (gnome-session-openrc 49.2-r1, gdm 49.2-r4, pipewire 1.6.8, wireplumber 0.5.15, elogind 255.24, openrc 0.63.3, sysvinit 3.15). Noyau 6.18.14 inchangé. Symptômes : plus de son, pas de curseur de volume ni d'« Éteindre » dans le menu GNOME, arrêt/reboot depuis GNOME qui échoue, gnome-control-center qui ne démarre pas depuis le dash. `poweroff -f` marchait (donc noyau/BIOS OK).

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

## 4. gnome-control-center (et apps D-Bus-activables) ne démarrent pas depuis le dash
Cause : le dash lance l'appli par activation D-Bus (DBusActivatable=true) ; l'environnement d'activation du bus OpenRC est vide (pas de WAYLAND_DISPLAY, XDG_CURRENT_DESKTOP…), le processus sort avec le statut 1. Depuis un terminal ça marche (env hérité).
Diagnostic :
    gdbus call --session --dest org.gnome.Settings --object-path /org/gnome/Settings --method org.freedesktop.Application.Activate '{}'
    -> « Process org.gnome.Settings exited with status 1 »
    dbus-update-activation-environment WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_CURRENT_DESKTOP="$XDG_CURRENT_DESKTOP" XDG_SESSION_TYPE=wayland   (puis ça marche)
Fix permanent : service utilisateur séparé /etc/user/init.d/bookworm-activation-env (attend le socket wayland-N et le process gnome-shell, relit son environ, appelle dbus-update-activation-environment ; en arrière-plan, ne bloque jamais la session), activé dans le runlevel gnome-session de chaque utilisateur et dans /etc/skel.
Échec : un start_post() ajouté dans gnome-shell-wayland a cassé la session (retour à l'original) — ne pas retoucher ce fichier pour ça.
Validé sur testgnome, orangepi et un nouvel utilisateur (/etc/skel) : Paramètres s'ouvre depuis le dash après relogin.

## 5. Console texte / services OpenRC invisibles à l'écran, VT1 noir
Cause : /dev/console = dernier console= de la cmdline (ttyAMA2), et fbcon=map:01111111 liait VT1 à fb0 (efifb, non affiché) au lieu de fb1 (linlondpdrmfb). linlon_dp.enable_fb / enable_render sont des paramètres inconnus (ignorés).
Fix : fbcon=map:1 et console=ttyAMA2,115200 console=tty0 (tty0 en dernier). Le login série reste assuré par l'agetty s2 de /etc/inittab sur ttyAMA2. Recovery : « single » remplace systemd.unit=rescue.target.
Contrôle : `cat /proc/consoles` doit finir par tty0. Le passage GDM <-> console (Ctrl+Alt+F2) est instantané. Validé sur 6.18.14, 6.19.0 et 7.0.0 (0 Oops).

## 6. Dossiers XDG absents (Documents, Téléchargements…) pour un nouvel utilisateur
Cause : xdg-user-dirs-update est normalement lancé par l'autostart de gnome-session via systemd ; sous OpenRC personne ne l'exécute (pas de ~/.config/user-dirs.dirs). Lancé à la main, il crée tout correctement en fr_FR.
Fix : service utilisateur /etc/user/init.d/bookworm-user-dirs (charge /etc/profile.env et /etc/locale.conf pour avoir LANG, puis xdg-user-dirs-update ; idempotent, n'écrase rien), activé dans le runlevel gnome-session et /etc/skel.
Installation : `sudo ./fix-gnome49-openrc.sh --all-users --skel` (scripts-addons). Validé avec un nouvel utilisateur.

## 7. HDMI et audio DP/HDMI (OrangePi 6 Plus, validé le 2026-10-10 sur 6.18.14-lts)
Image : la sortie HDMI passe par le convertisseur DP→HDMI Parade PS185HDM (dp4/dpu4). Le noyau 6.18 ne connaît pas `parade,ps185hdm` dans simple-bridge : patch local 9006 (6.18.14-lts uniquement ; 6.19 et 7.0 l'ont déjà en amont). `dts-disable-unused-dpu.py` garde dpu3/dp3 (DP natif) et dpu4/dp4 (HDMI), désactive dp0/1/2 et les liens audio dptx0/1_audio (sinon la carte son reste en EPROBE_DEFER).
Son : carte ALSA `cix_sky1`, périphérique 0 = DP natif, 1 = HDMI. Le profil par défaut (`output:stereo-fallback`) n'expose que le périphérique 0 ; il faut le profil `pro-audio` pour avoir le HDMI. Règles WirePlumber (config/wireplumber/, installées par install.sh, étape 5b) :
- 51-sky1-hdmi-profile.conf : profil pro-audio par défaut (device.profile.priority.rules). Un profil déjà mémorisé dans ~/.local/state/wireplumber/ passe avant la règle.
- 52-sky1-hdmi-buffer.conf : node.force-quantum = 4096 sur les deux sinks (à 1024 : des milliers de xruns, son haché ; api.alsa.period-size seul aggrave le problème) et noms « DisplayPort » / « HDMI ».
Pièges de test :
- `pw-play --target` attend le NOM du nœud (alsa_output.platform-sound.pro-output-1), pas l'ID de `wpctl status` ; un ID inconnu retombe sur le sink par défaut (faux « pas de son », faux « marche une seule fois »).
- Le bouton « Tester » de GNOME ne marche pas avec Pro Audio (pas de disposition de haut-parleurs) : tester avec pw-play ou une vidéo.
- `speaker-test -D pipewire` échoue sans le plugin ALSA pipewire ; inutile pour GNOME/Firefox.
- Le pilote DP audio est sain : en direct sur hw:<carte cix_sky1>,1 (S16 ou S32) tout fonctionne ; le défaut venait de PipeWire (cible et quantum).
- build-pipeline : PATCHES_EXTRA est réappliqué à chaque lancement avec `patch -p1` sans -N ; repartir d'un arbre kernel neuf (mv linux-X linux-X.old) pour un build propre.
Contrôle : `wpctl status` doit lister les sinks « DisplayPort » et « HDMI » sans réglage manuel pour un nouvel utilisateur (validé avec un utilisateur de test).

### 7b. Écran noir au réveil (HDMI, et probablement DP) : patch 9007
Symptôme : après l'extinction de l'écran par GNOME, souris et clavier ne rallument rien ; `Ctrl+Alt+F2` non plus. Pourtant `status=connected`, `enabled`, `dpms On`, et l'état atomique donne crtc `active=1`.
Cause : au réveil, le moniteur/convertisseur fait Unplugged puis Plugged en ~2,5 s, environ 2 s après le link training. `trilin_dp_handle_disconnect()` éteint le PHY et met `active_stream_cnt = 0`, mais mutter ne voit jamais l'état « déconnecté » (le connecteur est de nouveau connecté quand il relit) et ne refait pas de modeset : le CRTC reste actif sur un lien mort.
Correctif : `9007-trilin-dp-recover-stale-crtc` — à la fin du travail HPD, si le connecteur a un CRTC actif et `active_stream_cnt == 0`, on appelle `drm_atomic_helper_reset_crtc()` (log : « HPD bounce: CRTC active but link torn down, forcing modeset »). Validé sur 6.18.14-lts (HDMI), y compris sur arbre propre (2 déclenchements du log en ~580 s d'idle, image revenue) ; déclaré dans les 4 pistes (dry-run OK sur 6.19 et 7.0, test réel à faire).
Contournement sans patch : `echo off | sudo tee /sys/class/drm/card2-HDMI-A-1/status; sleep 3; echo detect | sudo tee /sys/class/drm/card2-HDMI-A-1/status`.
Diagnostic utile : `sudo dmesg | grep -a -E 'hpd event|encoder_(enable|disable)'` ; un Unplugged/Plugged sans encoder_disable/enable entre les deux est le signe du bug.

### 7c. Oops USB cdns3 au chargement des modules : patch 9008
Symptôme : Oops au boot (NULL deref dans `usb_hcd_is_primary_hcd`, appelé depuis `cdns_host_resume`) pendant le probe de `xhci_plat`.
Cause : le PM runtime resume appelle `cdns_host_resume()` avant que `host_dev` / le drvdata du hcd existent (course au chargement des modules).
Correctif : `9008-usb-cdns3-guard-null-hcd-in-cdns_host_resume` — retour anticipé si `cdns->host_dev` ou le hcd est NULL. Dans les 4 pistes (PATCHES_EXTRA, après 9007). Validé sur 6.18.14-lts arbre propre : 0 Oops sur les boots testés (une course : confirmer sur plusieurs boots) ; dry-run OK sur 6.19 et 7.0.
Autre Oops encore non identifié : corruption de liste (hlist) dans finit_module/idempotent_init_module, `Code: b4000140 f9400be1 f9000001 b4000041 (f9000420)` ; il faut le bloc complet (pc, lr, Call trace, /var/log/messages).

### 7d. Pas de carte son DP/HDMI sur 7.0-next : patch 9009
Symptôme : seule la carte HDA (ALC269) existe, sinks « DisplayPort » / « HDMI » absents, `dmesg` : `platform sound: deferred probe pending: (reason unknown)` et `sky1-asoc-card sound: dai-link name:dptx3_audio` en boucle ; `/sys/kernel/debug/asoc/components` sans `hdmi-audio-codec`.
Cause : 9001 copie l'`of_node` du DP sur le pdev `hdmi-audio-codec.N.auto`. Ce nœud porte la compatible `cix,sky1-dptx`, donc si `snd-soc-hdmi-codec` n'est pas encore chargé à la création du pdev, `trilin-dptx-cix` réclame ce pdev (uevent : `DRIVER=trilin-dptx-cix`, `bind` du vrai pilote : EBUSY). Course au chargement des modules.
Correctif : `9009-trilin-dp-softdep-hdmi-codec` — `MODULE_SOFTDEP("pre: snd-soc-hdmi-codec");` dans `trilin_dptx_cix.c`, hors du `#if IS_ENABLED(CONFIG_DRM_CIX_COMPONENT_BIND_BYPASSED)` (option désactivée : le `softdep` existant `pre: linlon_dp` n'est pas compilé). Contrôle : `modinfo trilin_dpsub | grep softdep`. Déclaré dans les 4 pistes ; validé sur 7.0 (carte `cix_sky1` liée, sinks, son OK sur 5 boots de suite). Un boot silencieux inexpliqué juste après l'installation, non reproduit.
Contournement sans patch : `echo 'softdep trilin_dpsub pre: snd-soc-hdmi-codec' > /etc/modprobe.d/sky1-hdmi-codec.conf` puis `depmod -a`.
Pièges de diagnostic :
- `/tmp` est vidé au reboot (recréer `tone.wav`) ; `> /root/x` échoue sans root, utiliser `| sudo tee`.
- Le bloc audio du contrôleur (registres `0x908`–`0x95c`, canaux `0x954 = 0x87654321`, compteur de paquets `0x95c`) est programmé quand le son marche ; tout à 0 = rien n'est émis. `0x868`/`0xa68` passent à 0x8 à chaque lecture de `register_info` (artefact).
- Sur 7.0 l'ELD (`amixer -c 0 contents`) était nul pendant le boot silencieux ; non établi comme cause (le chemin `drm_get_edid` + `drm_add_edid_modes` ne le construit peut-être dans aucun noyau).
- Numéro de carte : il dépend de l'ordre de chargement (`cix_sky1` était la carte 1 sur un ancien boot 6.18.14, la carte 0 sur 7.0 et sur 6.18.14 avec 9009). Ne jamais le coder en dur : `grep cix_sky1 /proc/asound/cards`.

## Bruit sans conséquence
- RealtimeKit1 absent (rtkit non installé), bolt.enroll non enregistré (bolt non installé), geolocation portal NotFound.
- « Failed to open gpu /dev/dri/card0 » : GPU Panthor sans affichage, mutter utilise card1 (linlondp).
- « Couldn't set runlevel stack / File exists » et « Session termination requested » du gnome-session-init-worker : normaux.
- 7.0-next : ~389 warnings dtc « CIX_PAD_GPIOxxx redéfini » (sky1-pinfunc.h vs dt-bindings/pinctrl/pads-sky1.h), build non bloquée.

## À faire
- HDMI/DP : réveil du DP natif après écran noir avec un écran DP (patch 9007 validé en HDMI seulement), test DP + HDMI simultanés, tests HDMI + 9007 sur 6.19 et 7.0 (support HDMI amont, sans patch 9006).
- Appel optionnel du script depuis install.sh (--all-users --skel).
- Signaler le défaut à Gentoo (gnome-base/gnome-session-openrc).
- Module-load race (idempotent_init_module), Oops hlist non identifié : surveiller `dmesg | grep -a -c -E 'Oops|soft lockup'` à chaque boot.
- USB-C 10 Gbps (retourner le connecteur, autre port), KVM (rebind via usb-rebind-bus10).

### 7d. Pas de carte son DP/HDMI sur 7.0-next : patch 9009
Symptôme : seule la carte HDA existe, sinks « DisplayPort » / « HDMI » absents, `dmesg` : `platform sound: deferred probe pending: (reason unknown)` ; `/sys/kernel/debug/asoc/components` sans `hdmi-audio-codec`.
Cause : 9001 copie l'`of_node` du DP sur le pdev `hdmi-audio-codec.N.auto`. Ce nœud porte la compatible `cix,sky1-dptx` ; si `snd-soc-hdmi-codec` n'est pas chargé à la création du pdev, `trilin-dptx-cix` réclame ce pdev (uevent : `DRIVER=trilin-dptx-cix`, `bind` : EBUSY).
Correctif : `9009-trilin-dp-softdep-hdmi-codec` — `MODULE_SOFTDEP("pre: snd-soc-hdmi-codec");` dans `trilin_dptx_cix.c`, hors du `#if CONFIG_DRM_CIX_COMPONENT_BIND_BYPASSED` (désactivé). Contrôle : `modinfo trilin_dpsub | grep softdep`. Validé sur 7.0 (5 boots, son OK ; un boot silencieux inexpliqué juste après l'installation, non reproduit).
Contournement sans patch : `echo 'softdep trilin_dpsub pre: snd-soc-hdmi-codec' | sudo tee /etc/modprobe.d/sky1-hdmi-codec.conf && sudo depmod -a`.
