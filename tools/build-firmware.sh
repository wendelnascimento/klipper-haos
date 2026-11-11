#!/usr/bin/env bash
# =============================================================================
# Build Klipper MCU firmware for a supported printer, inside Docker.
#
#   tools/build-firmware.sh [printer] [output-dir]
#       printer     directory under firmware/ (default: ender3-v3-se)
#       output-dir  default: firmware/out/<printer>
#
# Uses the exact Klipper commit pinned in klipper/Dockerfile, so the MCU
# firmware matches the Klipper host software shipped in the app.
#
# This script only BUILDS firmware. It never flashes anything. Flashing is a
# separate, manual step described in docs/printer-setup.md.
# =============================================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRINTER="${1:-ender3-v3-se}"
OUT="${2:-${ROOT}/firmware/out/${PRINTER}}"
CONFIG="${ROOT}/firmware/${PRINTER}/klipper.config"
# Debian 13 (trixie) ships gcc-arm-none-eabi 14.x.
BUILDER_IMAGE="${BUILDER_IMAGE:-debian:trixie-slim}"

[[ -f "${CONFIG}" ]] || { echo "No firmware config: ${CONFIG}" >&2; exit 1; }
KLIPPER_COMMIT="$(sed -n 's/^ARG KLIPPER_COMMIT=//p' "${ROOT}/klipper/Dockerfile")"
[[ -n "${KLIPPER_COMMIT}" ]] || { echo "KLIPPER_COMMIT not found" >&2; exit 1; }

host_path() {
    if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

mkdir -p "${OUT}"
echo "Building ${PRINTER} firmware for Klipper ${KLIPPER_COMMIT}"
docker run --rm \
    -e KLIPPER_COMMIT="${KLIPPER_COMMIT}" \
    -v "$(host_path "${CONFIG}"):/in/klipper.config:ro" \
    -v "$(host_path "${OUT}"):/out" \
    "${BUILDER_IMAGE}" bash -euo pipefail -c '
        # Large plain-HTTP downloads can be altered by transparent proxies on
        # some networks (apt then rejects them with "Hash Sum mismatch").
        # Fetch only ca-certificates over HTTP (still hash-verified by apt),
        # then switch the mirrors to HTTPS for everything else.
        printf "Acquire::Retries \"5\";\n" > /etc/apt/apt.conf.d/80-retries
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
            ca-certificates > /dev/null
        sed -i "s#http://deb.debian.org#https://deb.debian.org#g" \
            /etc/apt/sources.list.d/debian.sources
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
            binutils ca-certificates cpp git make python3 gcc-arm-none-eabi binutils-arm-none-eabi \
            libnewlib-arm-none-eabi > /dev/null
        git clone -q --filter=blob:none https://github.com/Klipper3d/klipper.git /klipper
        cd /klipper
        git checkout -q "${KLIPPER_COMMIT}"
        cp /in/klipper.config .config
        make olddefconfig > /dev/null
        make -j"$(nproc)" > /dev/null
        cp out/klipper.bin out/klipper.dict .config /out/
        mv /out/.config /out/klipper.config.full
        git describe --tags --always --long > /out/klipper-version.txt
        cd /out && sha256sum klipper.bin > klipper.bin.sha256
        chown -R "$(stat -c %u:%g /out)" /out
    '
echo "Firmware written to ${OUT}:"
ls -l "${OUT}"
cat "${OUT}/klipper.bin.sha256"
