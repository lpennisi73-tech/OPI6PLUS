# =============================================================================
# dts-add-cpu-thermal-zones.py
# Ajouter les zones thermiques CPU dans le DTS OrangePi 6 Plus
#
# Contexte:
#   Le DTS sky1-orangepi-6-plus.dts n'a pas de zones thermiques CPU.
#   On les ajoute depuis le DTS Radxa Orion O6 — meme SoC CIX CD8180.
#
#   Note: les cooling-maps sont omises car les labels CPU (cpu4, cpu6...)
#   ne sont pas definis dans le DTS OrangePi. Les temperatures sont
#   visibles via scmi-hwmon sans throttling automatique.
#   Labels corrects dans sky1.dtsi: CPU4, CPU6, CPU8, CPU10
#
# Fichier: arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts
# =============================================================================

import sys

TARGET = "arch/arm64/boot/dts/cix/sky1-orangepi-6-plus.dts"

THERMAL_ZONES = """
/* CPU Thermal Zones — ported from sky1-orion-o6.dts
 * Same CIX CD8180 SoC — SCMI sensors available on OrangePi 6 Plus
 * Note: cooling-maps omitted — use scmi-hwmon for temperature monitoring
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

    # Verifier si deja applique
    if "tz-cpu-4-5" in content or "CPU_M0_TEMP_SENSOR_ID" in content:
        print("SKIP — Zones thermiques CPU deja presentes")
        sys.exit(0)

    content = content.rstrip() + "\n" + THERMAL_ZONES

    with open(TARGET, 'w') as f:
        f.write(content)

    print("OK — 4 zones thermiques CPU ajoutees:")
    print("  tz-cpu-4-5   (CPU_M0)")
    print("  tz-cpu-6-7   (CPU_M1)")
    print("  tz-cpu-8-9   (CPU_B0)")
    print("  tz-cpu-10-11 (CPU_B1)")

if __name__ == "__main__":
    apply_fix()
