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
# A printer directory may contain an "overlay" file naming a source overlay
# (for example the Ender 3 V3 SE display serial bridge). Its pinned, checksum
# verified source files and its build patch are added on top of upstream
# Klipper and committed with a fixed author and date, so the build stays
# reproducible and the firmware version names the exact source tree.
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
OVERLAY=""
if [[ -f "${ROOT}/firmware/${PRINTER}/overlay" ]]; then
    OVERLAY="$(grep -v -E '^[[:space:]]*(#|$)' "${ROOT}/firmware/${PRINTER}/overlay" | head -1)"
    [[ "${OVERLAY}" =~ ^[a-z0-9-]+$ ]] || { echo "Invalid overlay name: ${OVERLAY}" >&2; exit 1; }
    for f in "klipper/requirements/${OVERLAY}.lock" "firmware/overlays/${OVERLAY}.patch"; do
        [[ -f "${ROOT}/${f}" ]] || { echo "Overlay file missing: ${f}" >&2; exit 1; }
    done
fi
KLIPPER_COMMIT="$(sed -n 's/^ARG KLIPPER_COMMIT=//p' "${ROOT}/klipper/Dockerfile")"
[[ -n "${KLIPPER_COMMIT}" ]] || { echo "KLIPPER_COMMIT not found" >&2; exit 1; }

host_path() {
    if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

mkdir -p "${OUT}"
# docker run -v treats a relative source as a volume name (exit 125), so
# always pass an absolute path.
OUT="$(cd "${OUT}" && pwd)"
echo "Building ${PRINTER} firmware for Klipper ${KLIPPER_COMMIT}${OVERLAY:+ with overlay ${OVERLAY}}"
overlay_mounts=()
if [[ -n "${OVERLAY}" ]]; then
    overlay_mounts=(
        -v "$(host_path "${ROOT}/klipper/requirements/${OVERLAY}.lock"):/in/overlay.lock:ro"
        -v "$(host_path "${ROOT}/firmware/overlays/${OVERLAY}.patch"):/in/overlay.patch:ro"
        -v "$(host_path "${ROOT}/klipper/build/fetch-e3v3se-display.sh"):/in/fetch-overlay.sh:ro"
    )
fi
docker run --rm \
    -e KLIPPER_COMMIT="${KLIPPER_COMMIT}" \
    -e OVERLAY="${OVERLAY}" \
    -v "$(host_path "${CONFIG}"):/in/klipper.config:ro" \
    "${overlay_mounts[@]}" \
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
        if [ -n "${OVERLAY}" ]; then
            sh /in/fetch-overlay.sh /in/overlay.lock /klipper src
            git apply /in/overlay.patch
            git add -A src
            # Fixed identity and date: the commit hash (and so the firmware
            # version string) depends only on the source tree.
            GIT_AUTHOR_DATE="2000-01-01T00:00:00Z" GIT_COMMITTER_DATE="2000-01-01T00:00:00Z" \
                git -c user.name="klipper-haos build" -c user.email="build@klipper-haos.invalid" \
                commit -q -m "klipper-haos overlay: ${OVERLAY}"
        fi
        cp /in/klipper.config .config
        make olddefconfig > /dev/null
        # olddefconfig silently drops options whose dependencies are not
        # met (for example after a Klipper update). Fail instead.
        while IFS= read -r line; do
            case "${line}" in
                CONFIG_*) grep -qxF "${line}" .config \
                    || { echo "Kconfig dropped or changed: ${line}" >&2; exit 1; } ;;
            esac
        done < /in/klipper.config
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
