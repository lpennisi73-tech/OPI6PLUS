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
Image : la sortie HDMI passe par le convertisseur DP→HDMI Parade PS185HDM (dp4/dpu4). Le noyau 6.18 ne connaît pas `parade,ps185hdm` dans simple-bridge : patch local 9006 (6.18-lts et 6.18.14-lts uniquement ; 6.19 et 7.0 l'ont déjà en amont). `dts-disable-unused-dpu.py` garde dpu3/dp3 (DP natif) et dpu4/dp4 (HDMI), désactive dp0/1/2 et les liens audio dptx0/1_audio (sinon la carte son reste en EPROBE_DEFER).
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
Correctif : `9007-trilin-dp-recover-stale-crtc` — à la fin du travail HPD, si le connecteur a un CRTC actif et `active_stream_cnt == 0`, on appelle `drm_atomic_helper_reset_crtc()` (log : « HPD bounce: CRTC active but link torn down, forcing modeset »). Validé sur 6.18.14-lts, 6.19-latest et 7.0-next (HDMI), y compris sur arbre propre (2 déclenchements du log en ~580 s d'idle, image revenue) ; déclaré dans les 4 pistes (dry-run OK sur 6.19 et 7.0, test réel à faire).
Contournement sans patch : `echo off | sudo tee /sys/class/drm/card2-HDMI-A-1/status; sleep 3; echo detect | sudo tee /sys/class/drm/card2-HDMI-A-1/status`.
Diagnostic utile : `sudo dmesg | grep -a -E 'hpd event|encoder_(enable|disable)'` ; un Unplugged/Plugged sans encoder_disable/enable entre les deux est le signe du bug.

### 7c. Oops USB cdns3 au chargement des modules : patch 9008
Symptôme : Oops au boot (NULL deref dans `usb_hcd_is_primary_hcd`, appelé depuis `cdns_host_resume`) pendant le probe de `xhci_plat`.
Cause : le PM runtime resume appelle `cdns_host_resume()` avant que `host_dev` / le drvdata du hcd existent (course au chargement des modules).
Correctif : `9008-usb-cdns3-guard-null-hcd-in-cdns_host_resume` — retour anticipé si `cdns->host_dev` ou le hcd est NULL. Dans les 4 pistes (PATCHES_EXTRA, après 9007) ; 9005 ajouté aussi à `6.18-lts` (oubli). Validé sur 6.18.14-lts arbre propre : 0 Oops sur les boots testés (une course : confirmer sur plusieurs boots) ; dry-run OK sur 6.19 et 7.0.
Autre Oops encore non identifié : corruption de liste (hlist) dans finit_module/idempotent_init_module, `Code: b4000140 f9400be1 f9000001 b4000041 (f9000420)` ; il faut le bloc complet (pc, lr, Call trace, /var/log/messages).

### 7d. Pas de carte son DP/HDMI sur 7.0-next : patch 9009
Symptôme : seule la carte HDA (ALC269) existe, sinks « DisplayPort » / « HDMI » absents, `dmesg` : `platform sound: deferred probe pending: (reason unknown)` et `sky1-asoc-card sound: dai-link name:dptx3_audio` en boucle ; `/sys/kernel/debug/asoc/components` sans `hdmi-audio-codec`.
Cause : 9001 copie l'`of_node` du DP sur le pdev `hdmi-audio-codec.N.auto`. Ce nœud porte la compatible `cix,sky1-dptx`, donc si `snd-soc-hdmi-codec` n'est pas encore chargé à la création du pdev, `trilin-dptx-cix` réclame ce pdev (uevent : `DRIVER=trilin-dptx-cix`, `bind` du vrai pilote : EBUSY). Course au chargement des modules.
Correctif : `9009-trilin-dp-softdep-hdmi-codec` — `MODULE_SOFTDEP("pre: snd-soc-hdmi-codec");` dans `trilin_dptx_cix.c`, hors du `#if IS_ENABLED(CONFIG_DRM_CIX_COMPONENT_BIND_BYPASSED)` (option désactivée : le `softdep` existant `pre: linlon_dp` n'est pas compilé). Contrôle : `modinfo trilin_dpsub | grep softdep`. Déclaré dans les 4 pistes ; validé sur 7.0 (carte `cix_sky1` liée, sinks, son OK sur 5 boots de suite) et sur 6.18.14 arbre propre. Un boot silencieux inexpliqué juste après l'installation, non reproduit.
Contournement sans patch : `echo 'softdep trilin_dpsub pre: snd-soc-hdmi-codec' > /etc/modprobe.d/sky1-hdmi-codec.conf` puis `depmod -a`.
Pièges de diagnostic :
- `/tmp` est vidé au reboot (recréer `tone.wav`) ; `> /root/x` échoue sans root, utiliser `| sudo tee`.
- Le bloc audio du contrôleur (registres `0x908`–`0x95c`, canaux `0x954 = 0x87654321`, compteur de paquets `0x95c`) est programmé quand le son marche ; tout à 0 = rien n'est émis. `0x868`/`0xa68` passent à 0x8 à chaque lecture de `register_info` (artefact).
- Sur 7.0 l'ELD (`amixer -c 0 contents`) était nul pendant le boot silencieux ; non établi comme cause (le chemin `drm_get_edid` + `drm_add_edid_modes` ne le construit peut-être dans aucun noyau).
- Numéro de carte : il dépend de l'ordre de chargement (`cix_sky1` était la carte 1 sur un ancien boot 6.18.14, la carte 0 sur 7.0 et sur 6.18.14 avec 9009). Ne jamais le coder en dur : `grep cix_sky1 /proc/asound/cards`.

## 8. Une application n'a pas de son (Totem, apps ALSA) alors que GNOME joue
Symptôme : le son marche dans le navigateur ou avec `pw-play`, mais pas dans Totem. `GST_DEBUG=2 totem fichier` montre `alsalib error: Unknown PCM default:{AES0 ...}` ; `wpctl status` ne montre aucun flux de l'application ; `aplay -L` ne liste que `null` et `default:CARD=cixsky1` / `sysdefault:CARD=cixsky1`.
Cause : les liens ALSA→PipeWire sont absents de `/etc/alsa/conf.d/`. Toute application qui passe par ALSA ouvre alors directement `cix_sky1` périphérique 0 (le DisplayPort), que PipeWire tient déjà en profil Pro Audio : périphérique occupé, pas de son. Le USE `pipewire-alsa` installe les fichiers mais ne les active pas.
Correctif :
```
sudo mkdir -p /etc/alsa/conf.d
sudo ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf /etc/alsa/conf.d/50-pipewire.conf
sudo ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d/99-pipewire-default.conf
aplay -L | grep -E '^(pipewire|default)$'
speaker-test -D pipewire -c 2 -t sine -l 1
```
Validé le 2026-10-11 (Totem rejoue le son après correction). Les liens avaient disparu, probablement lors d'un nettoyage ; à intégrer à `install.sh` (étape 5b) pour les nouveaux utilisateurs.
Diagnostic rapide : `gst-launch-1.0 playbin uri=file://... video-sink=fakesink audio-sink=pipewiresink` (puis `pulsesink`, `alsasink`) pour isoler le sink fautif.

## Bruit sans conséquence
- RealtimeKit1 absent (rtkit non installé), bolt.enroll non enregistré (bolt non installé), geolocation portal NotFound.
- « Failed to open gpu /dev/dri/card0 » : GPU Panthor sans affichage, mutter utilise card1 (linlondp).
- « Couldn't set runlevel stack / File exists » et « Session termination requested » du gnome-session-init-worker : normaux.
- 7.0-next : ~389 warnings dtc « CIX_PAD_GPIOxxx redéfini » (sky1-pinfunc.h vs dt-bindings/pinctrl/pads-sky1.h), build non bloquée.

## À faire
- Hang GPU panthor : 2 occurrences (12 et 14 octobre), non reproduit ; si ça revient, blackbox + dmesg complet ; envisager un rapport à dri-devel avec les deux piles.
- Envoyer les PR 0152/0153/0154 après réaction sur #43 ; 9006 : crédit Maud Spierings avant tout PR.
- HDMI/DP : réveil du DP natif avec un écran DP, tests DP + HDMI simultanés.
- Boot silencieux inexpliqué sur 7.0 juste après l'installation (non reproduit sur 5 boots) : si ça revient, garder `~/audio-check.log` et ne rien toucher.
- Oops hlist (finit_module/idempotent_init_module), `Code: b4000140 f9400be1 f9000001 b4000041 (f9000420)` : non identifié, il faut le bloc complet (pc, lr, Call trace).
- Avant le tag v1.9 : ménage (utilisateurs de test, `/boot/dtb/*hdmitest*`, arbres `.old`, fichiers `/root`), README « Limites connues ».
- Intégrer les liens ALSA→PipeWire (section 8) à install.sh, étape 5b.
- Signaler le défaut à Gentoo (gnome-base/gnome-session-openrc).
- Appel optionnel du script depuis install.sh (--all-users --skel).
- USB-C 10 Gbps (retourner le connecteur, autre port), KVM (rebind via usb-rebind-bus10).

## État des pistes (2026-10-11)
- 6.18.14-lts (défaut du script, stable) : HDMI + son + réveil + 0 Oops, validé avec 9004–9009 sur arbre propre.
- 6.19-latest : build, HDMI (sans 9006, amont), son, réveil, 0 Oops validés.
- 7.0-next : build, HDMI, son (9009), réveil (9007), 0 Oops validés (1 boot silencieux inexpliqué juste après l'installation, non reproduit).
- 6.18-lts (6.18.9) : supprimée, doublon périmé.
- 6.18.14-lts (2026-10-14) : conf stable = 9004-9009 + 9002/9003 ; conf de test (6.18.14-lts-hotschmoe) = stable + 9010-9012.

## 9. Langue et clavier : GDM en en_US malgré fr_CH (OpenRC)
- Le greeter lit la disposition via `org.freedesktop.locale1`, fourni sous OpenRC par `openrc-settingsd`, qui lit `/etc/X11/xorg.conf.d/30-keyboard.conf`. Fichier absent : `X11Layout` vide, repli sur `us` (un dconf `gdm.d` n'a aucun effet). `SetX11Keyboard` échoue tant que ce fichier n'existe pas : le créer (`XkbLayout`/`XkbVariant`), puis `pkill -f openrc-settingsd` (cache).
- Contrôle : `gdbus call --system --dest org.freedesktop.locale1 --object-path /org/freedesktop/locale1 --method org.freedesktop.DBus.Properties.Get org.freedesktop.locale1 X11Layout`
- Automatisé : `scripts-addons/set-locale.sh --lang fr_CH [--tz Europe/Zurich] [--kbd ch:fr --console fr_CH] [--dry-run]`, puis `sudo reboot`.
- Piège : `env-update` lit tout fichier de `/etc/env.d/` commençant par deux chiffres, y compris `02locale.bak-<date>` (la dernière sauvegarde écrasait `LANG` dans `/etc/profile.env`). Sauvegardes du script : `/root/set-locale-bak/<date>/`. Contrôle : `grep '^export LANG' /etc/profile.env`.
- Un `rc-service display-manager restart` après changement de langue a figé l'affichage une fois (6.18.14, SSH vivant, cause non établie, rien dans les logs) : consigne = reboot.
- `pkill`/`pgrep` sans `-f` ne trouvent pas les noms de plus de 15 caractères ; les `LC_*` suivent le réglage « Formats » de GNOME.

### 7e. Double écran DP natif + HDMI (validé le 2026-10-11 sur 6.18.14-lts)
- Image sur les deux écrans en même temps (`card0-DP-1` = DP natif, `card2-HDMI-A-1` = HDMI ; la numérotation des cartes DRM peut varier), son sur les deux (`alsa_output.platform-sound.pro-output-0` = DP, `pro-output-1` = HDMI) et réveil des deux écrans OK.
- Au réveil, seul le HDMI fait un Unplugged/Plugged (rattrapé par 9007 : « HPD bounce ... forcing modeset ») ; le DP natif se réveille sans HPD.
- À valider sur 6.19-latest et 7.0-next. glmark2 : 3117 (6.18.14-lts, double écran).

## 10. Hang GPU Mali (panthor) sous Firefox : gnome-shell perdu, rendu llvmpipe jusqu'au reboot (2026-10-12, 6.18.14-lts)
- Symptôme : après ~10 h d'uptime, deux pubs vidéo (Firefox) laguent, puis la session Wayland redémarre ; ensuite rendu logiciel (`glxinfo -B` : llvmpipe, mutter « Not hardware accelerated »).
- Chronologie : UBSAN amvx (décodeur V4L2) -> `panthor: job timeout pid=<firefox-bin>` (2x) -> `CSG 0..6 update request timedout`, `Failed to stop MCU`, `AS_ACTIVE bit stuck` -> reset GPU échoué -> gnome-shell : `Could not import pending buffer: Out of memory`, mort puis relancé.
- Les WARNING `panthor_vm_destroy` / `panthor_gpuva_sm_step_unmap` sont collatéraux (unmap en -110 ETIMEDOUT, `AS_ACTIVE` bloqué).
- Récupération : reboot (renderer Mali-G720 MC10 / Panfrost, Mesa 26.1.8).
- Firmware vérifié : le GPU (id 0xc870, G720) charge `arm/mali/arch12.8/mali_csffw.bin` (git sha 95a25d71…, CSF v3.13.0), identique à celui du dépôt et à `linux-firmware-20260622` (sha256 718f6224…). Piste firmware écartée.
- Non reproduit ; cause non établie (WebGL/canvas des pubs, driver panthor 6.18.14, DVFS/SCMI, BIOS 1.4 ?). Contournement : désactiver l'accélération de Firefox, bloquer les pubs. Pistes : 6.19/7.0, fréquence GPU fixe (gouverneur `userspace` + `set_freq` ; `performance` disponible avec le noyau de test (9012, testé le 2026-10-14, voir la mise à jour ci-dessous) ; fréquences 72/216/350/600/800/1000 MHz), rapport drm/panthor.
- Diagnostic : `glxinfo -B | grep renderer` (pas llvmpipe) ; `sudo dmesg | grep -a -E 'panthor|job timeout|AS_ACTIVE'`.
- Bruit associé : UBSAN `array-index-out-of-bounds` dans `amvx` (`mvx_mmu.c:443` et `:812`), non fatal.

### Mise à jour 2026-10-14 : deuxième occurrence, noyau de test 6.18.14 + #37/#40/#41
Deuxième blocage MCU panthor, cette fois sans Firefox : ~8 min après le boot, pendant une compilation distcc -j20 (noyau 6.18.14-lts-hotschmoe : stable + 9002/9003 + 9010-9012). Chronologie : à 325 s `scmi_protocol scmi_dev.5: Received valid OoO Delayed Response for 124` puis `scmi_dev.4: Message for 124 type 0 is not expected!` ; à 483 s `CSG 4/5/0 update request timedout`, `CSG suspend failed`, `Failed to stop MCU`, `AS_ACTIVE bit stuck`, `Soft reset timeout`, WARNING `panthor_mmu.c:2186` (panthor_gpuva_sm_step_unmap via group_release_work). Wayland tombé.
Autre boot, même charge : `scmi_dev.4: Invalid message type:0 for 713 - HDR:0xB245005 state:2` (en-tête décodé : protocole 0x14 clock, message 0x05 CLOCK_RATE_SET, token 713, état SENT_OK).
Non reproduit ensuite, sur le même noyau :
- gouverneur GPU `performance` : 34 min de charge, 0 erreur ; puis retour à `simple_ondemand` : 0 erreur ;
- stress alterné stress-ng (CPU) + glmark2-es2-wayland (rafales GPU), 44 min, 200 cycles : 0 erreur ;
- 10 bascules de /sys/devices/system/cpu/cpufreq/boost sous charge : 0 erreur ;
- nouvelle compilation distcc -j20 avec ~/blackbox.sh actif : 0 erreur.
Noyau 7.0 non modifié, compilation distcc -j20 : pas de reboot.
Conclusion : déclencheur inconnu ; le blocage n'est pas propre à Firefox (voir ci-dessus) ni prouvé lié à #41. Repli si ça revient : `echo performance | sudo tee /sys/class/devfreq/15000000.gpu/governor` (disponible avec 9012 ; fréquence max fixe). Diagnostic : `sudo dmesg | grep -a -E 'scmi|panthor'`, sauver `dmesg` avant tout reboot.

## 11. amvx (9002/9003) et état des PR (2026-10-14)
- 9002 (`pages[0]` -> `pages[]` dans `struct mvx_mmu_pages`, mvx_mmu.h) supprime les UBSAN `array-index-out-of-bounds` de `mvx_mmu.c` ; 9003 (`q->lock = &vport->vsession->mutex` dans `setup_vb2_queue`) est du durcissement sans symptôme connu. Validés sur arbre neuf avec la conf de test : encode hevc_v4l2m2m 313 fps (13,1x), plus aucune ligne UBSAN/mvx_mmu/vb2 dans dmesg. Ajoutés à `config/kernels/6.18.14-lts.conf` après 9009 (commit 6039c6f). Le `Firmware rsp: Error code=7` de la section 10 n'est pas traité par 9002/9003.
- PR #43 (Sky1-Linux/linux-sky1) : 0150/0151 (9005/9008, garde NULL cdns3), en attente de réaction.
- Prêts, non envoyés : 0152/0153 (amvx, 9002/9003), 0154 (trilin DP HPD, 9007). Envoyer après la première réaction du mainteneur sur #43 (conflit possible sur `patches/series`).
- Tested-by postés le 2026-10-14 sur les PR de hotschmoe #37, #40, #41 : encode VPU à 1200 MHz, glmark2-es2-wayland 2982, trafic SCMI CLOCK_RATE_GET ~0,5/s, stress 44 min sans erreur ; événement de la section 10 signalé dans #41.
- Audio 9001/9009 : utiles seulement sur 7.0-next (le son marche sur 6.18.14 sans 9001) ; à réécrire sur `patches-next/` et tester sur 7.0 avant tout PR. 9006 = rétroportage de Maud Spierings (amont >= 6.19) : citer l'auteur et les hashes avant tout PR.

## 12. Reboots à chaud pendant la compilation (2026-10-13/14, non élucidé)
Deux redémarrages brutaux de suite pendant la compilation d'un noyau 6.18.56 (distcc -j20, boot sur 6.18.14 modifié). Écartés : pas de panic (`kernel.panic=0` figerait la carte), watchdog `sky1-wdt` inactif, pstore vide, températures au repos 41-45 °C (seuils 85/95/98 °C), rien dans /var/log/messages. Restent : alimentation (bloc USB-C PD 20 V 5 A, 100 W, câble ?) ou protection thermique du firmware. Non reproduit depuis. Outil : `~/blackbox.sh` (écrit mémoire, swap, charge, températures, fréquence et lignes scmi/panthor/WARNING toutes les 3 s avec sync dans ~/blackbox-*.log) ; à lancer avant toute grosse compilation. Si ça revient : `tail -30` du dernier blackbox, comparer avec 7.0 non modifié, tester un autre câble USB-C marqué 5 A.
