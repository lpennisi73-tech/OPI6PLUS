## Fix KVM DP HPD bounce

Symptôme: écran noir après switch KVM sur port DisplayPort
Cause: driver Trilin DP détecte HPD Unplug/Plug et Wayland ne reprend pas

Fix:
1. /etc/udev/rules.d/99-dp-hotplug.rules
2. /usr/local/bin/dp-recover.sh

Voir patches/fixes/ pour les détails.

## Fix NVMe Crucial — reboots sauvages

Symptôme: reboots aléatoires même au repos
Cause: power management NVMe Crucial (CT1000T500SSD8)
       watchdog hardware déclenche sur freeze NVMe

Fix permanent:
echo "options nvme_core default_ps_max_latency_us=0" > \
    /etc/modprobe.d/nvme-fix.conf

Testé sur: OrangePi 6 Plus — Linux 6.18/6.19/7.0
