# =============================================================================
# dts-add-cpu-thermal-zones.py
# Ajouter les zones thermiques CPU dans le DTS OrangePi 6 Plus
#
# Contexte:
#   Le DTS sky1-orangepi-6-plus.dts n'a pas de zones thermiques CPU
#   contrairement au DTS Radxa Orion O6 qui les définit.
#   Le hardware est identique (même SoC CIX CD8180) donc les mêmes
#   capteurs SCMI sont disponibles.
#
#   Zones ajoutées:
#     tz-cpu-4-5   — CPU_M0 (A720 cpu4-5)   — sustainable 5000mW
#     tz-cpu-6-7   — CPU_M1 (A720 cpu6-7)   — sustainable 4500mW
#     tz-cpu-8-9   — CPU_B0 (A720 cpu8-9)   — sustainable 5500mW
#     tz-cpu-10-11 — CPU_B1 (A720 cpu10-11) — sustainable 6000mW
#
#   Trip points: 60°C passive, 85°C passive, 98°C critical
#
# Fichier: arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts
# Utilisé par: bookworm-sky1-build.sh Phase DTS fixes
# =============================================================================

import sys

TARGET = "arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts"

# Bloc thermal zones CPU à ajouter à la fin du fichier
THERMAL_ZONES = """
/* CPU Thermal Zones — ported from sky1-orion-o6.dts
 * Same CIX CD8180 SoC — SCMI sensors available on OrangePi 6 Plus
 * Added by BOOKWORM Sky1 Kernel Builder
 */
&thermal_zones {
\ttz-cpu-6-7 {
\t\tpolling-delay-passive = <100>;
\t\tpolling-delay = <1000>;
\t\tthermal-sensors = <&scmi_sensor CPU_M1_TEMP_SENSOR_ID>;
\t\tsustainable-power = <4500>;
\t\ttrips {
\t\t\tm1_trip0: trip-point-0 {
\t\t\t\ttemperature = <60000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "passive";
\t\t\t};
\t\t\tm1_trip1: trip-point-1 {
\t\t\t\ttemperature = <85000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "passive";
\t\t\t};
\t\t\tm1_trip2: trip-point-2 {
\t\t\t\ttemperature = <98000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "critical";
\t\t\t};
\t\t};
\t\tcooling-maps {
\t\t\tmap0 {
\t\t\t\ttrip = <&m1_trip0>;
\t\t\t\tcooling-device = <&cpu6 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>;
\t\t\t};
\t\t\tmap1 {
\t\t\t\ttrip = <&m1_trip1>;
\t\t\t\tcooling-device = <&cpu6 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>;
\t\t\t};
\t\t};
\t};
\ttz-cpu-10-11 {
\t\tpolling-delay-passive = <100>;
\t\tpolling-delay = <1000>;
\t\tthermal-sensors = <&scmi_sensor CPU_B1_TEMP_SENSOR_ID>;
\t\tsustainable-power = <6000>;
\t\ttrips {
\t\t\tb1_trip0: trip-point-0 {
\t\t\t\ttemperature = <60000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "passive";
\t\t\t};
\t\t\tb1_trip1: trip-point-1 {
\t\t\t\ttemperature = <85000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "passive";
\t\t\t};
\t\t\tb1_trip2: trip-point-2 {
\t\t\t\ttemperature = <98000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "critical";
\t\t\t};
\t\t};
\t\tcooling-maps {
\t\t\tmap0 {
\t\t\t\ttrip = <&b1_trip0>;
\t\t\t\tcooling-device = <&cpu10 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>;
\t\t\t};
\t\t\tmap1 {
\t\t\t\ttrip = <&b1_trip1>;
\t\t\t\tcooling-device = <&cpu10 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>;
\t\t\t};
\t\t};
\t};
\ttz-cpu-4-5 {
\t\tpolling-delay-passive = <100>;
\t\tpolling-delay = <1000>;
\t\tthermal-sensors = <&scmi_sensor CPU_M0_TEMP_SENSOR_ID>;
\t\tsustainable-power = <5000>;
\t\ttrips {
\t\t\tm0_trip0: trip-point-0 {
\t\t\t\ttemperature = <60000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "passive";
\t\t\t};
\t\t\tm0_trip1: trip-point-1 {
\t\t\t\ttemperature = <85000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "passive";
\t\t\t};
\t\t\tm0_trip2: trip-point-2 {
\t\t\t\ttemperature = <98000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "critical";
\t\t\t};
\t\t};
\t\tcooling-maps {
\t\t\tmap0 {
\t\t\t\ttrip = <&m0_trip0>;
\t\t\t\tcooling-device = <&cpu4 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>;
\t\t\t};
\t\t\tmap1 {
\t\t\t\ttrip = <&m0_trip1>;
\t\t\t\tcooling-device = <&cpu4 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>;
\t\t\t};
\t\t};
\t};
\ttz-cpu-8-9 {
\t\tpolling-delay-passive = <100>;
\t\tpolling-delay = <1000>;
\t\tthermal-sensors = <&scmi_sensor CPU_B0_TEMP_SENSOR_ID>;
\t\tsustainable-power = <5500>;
\t\ttrips {
\t\t\tb0_trip0: trip-point-0 {
\t\t\t\ttemperature = <60000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "passive";
\t\t\t};
\t\t\tb0_trip1: trip-point-1 {
\t\t\t\ttemperature = <85000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "passive";
\t\t\t};
\t\t\tb0_trip2: trip-point-2 {
\t\t\t\ttemperature = <98000>;
\t\t\t\thysteresis = <1000>;
\t\t\t\ttype = "critical";
\t\t\t};
\t\t};
\t\tcooling-maps {
\t\t\tmap0 {
\t\t\t\ttrip = <&b0_trip0>;
\t\t\t\tcooling-device = <&cpu8 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>;
\t\t\t};
\t\t\tmap1 {
\t\t\t\ttrip = <&b0_trip1>;
\t\t\t\tcooling-device = <&cpu8 THERMAL_NO_LIMIT THERMAL_NO_LIMIT>;
\t\t\t};
\t\t};
\t};
};
"""

def apply_fix():
    try:
        with open(TARGET, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"ERREUR: {TARGET} introuvable")
        sys.exit(1)

    # Vérifier si déjà appliqué
    if "tz-cpu-4-5" in content or "CPU_M0_TEMP_SENSOR_ID" in content:
        print("SKIP — Zones thermiques CPU déjà présentes")
        sys.exit(0)

    # Vérifier que le DTS a bien thermal_zones dans le dtsi (hérité)
    # On ajoute à la fin du fichier
    content = content.rstrip() + "\n" + THERMAL_ZONES

    with open(TARGET, 'w') as f:
        f.write(content)

    print("OK — 4 zones thermiques CPU ajoutées:")
    print("  tz-cpu-4-5   (A720 cpu4-5  — CPU_M0)")
    print("  tz-cpu-6-7   (A720 cpu6-7  — CPU_M1)")
    print("  tz-cpu-8-9   (A720 cpu8-9  — CPU_B0)")
    print("  tz-cpu-10-11 (A720 cpu10-11 — CPU_B1)")
    print(f"Fichier mis à jour: {TARGET}")

if __name__ == "__main__":
    apply_fix()
