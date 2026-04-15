#!/bin/bash
# =============================================================================
# distcc-env.sh — Configuration distcc pour BOOKWORM Sky1 Kernel Builder
# Usage: source distcc-env.sh && ./bookworm-sky1-build.sh --kernel 7.0-next
# =============================================================================

# Adresse du Mac UTM (adapter selon ton réseau)
DISTCC_HOST="192.168.0.XX"
DISTCC_HOST_JOBS=8      # Nombre de jobs sur le Mac
DISTCC_LOCAL_JOBS=4     # Jobs locaux OrangePi

export DISTCC_HOSTS="${DISTCC_HOST}/${DISTCC_HOST_JOBS} localhost/${DISTCC_LOCAL_JOBS}"
export CC="distcc aarch64-linux-gnu-gcc"
export CXX="distcc aarch64-linux-gnu-g++"
export MAKEFLAGS="-j$((DISTCC_HOST_JOBS + DISTCC_LOCAL_JOBS))"

echo "✓ distcc configuré:"
echo "  Hosts : $DISTCC_HOSTS"
echo "  Jobs  : $((DISTCC_HOST_JOBS + DISTCC_LOCAL_JOBS))"
echo ""
echo "Lance maintenant:"
echo "  ./bookworm-sky1-build.sh --kernel 7.0-next --install"
