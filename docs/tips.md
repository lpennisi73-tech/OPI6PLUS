## Fix KVM DP HPD bounce

Symptôme: écran noir après switch KVM sur port DisplayPort
Cause: driver Trilin DP détecte HPD Unplug/Plug et Wayland ne reprend pas

Fix:
1. /etc/udev/rules.d/99-dp-hotplug.rules
2. /usr/local/bin/dp-recover.sh

Voir patches/fixes/ pour les détails.
