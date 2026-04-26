#!/bin/bash
# =============================================================================
# distcc-env.sh — Configuration distcc pour BOOKWORM Sky1 Kernel Builder
# Usage: source distcc-env.sh && ./bookworm-sky1-build.sh --kernel 7.0-next
# =============================================================================

DISTCC_HOST="192.168.0.58"
DISTCC_HOST_JOBS=12
DISTCC_LOCAL_JOBS=8

export DISTCC_HOSTS="${DISTCC_HOST}/${DISTCC_HOST_JOBS} localhost/${DISTCC_LOCAL_JOBS}"

# Sur OrangePi (ARM natif) — utiliser gcc directement avec distcc
export CC="distcc gcc"
export CXX="distcc g++"
export MAKEFLAGS="-j$((DISTCC_HOST_JOBS + DISTCC_LOCAL_JOBS))"

echo "✓ distcc configuré:"
echo "  Hosts : $DISTCC_HOSTS"
echo "  Jobs  : $((DISTCC_HOST_JOBS + DISTCC_LOCAL_JOBS))"
echo ""
echo "Lance maintenant:"
echo "  ./bookworm-sky1-build.sh --kernel 7.0-next --install"
