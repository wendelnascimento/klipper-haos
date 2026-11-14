#!/usr/bin/env bash
# =============================================================================
# Validate a printer profile without hardware, using Klipper's batch mode.
#
#   tests/profile/check-profile.sh <image> <printer> <firmware-dir> \
#       [extra-includes] [firmware-dir-without-extras]
#
#   extra-includes   space-separated files in the profile directory that are
#                    included after printer.cfg (for example "display.cfg")
#   firmware-dir-without-extras
#                    a firmware build that lacks what the extras need; the
#                    script then also checks that Klipper refuses to start
#                    with it and names the missing MCU command
#
# Klipper's batch mode ("-d <dict> -o <out>") loads printer.cfg, checks every
# section and pin name against the MCU data dictionary produced by the
# firmware build, and runs a test G-code file against a simulated MCU. This
# is the same mechanism Klipper's own test suite uses.
#
# This proves the profile is syntactically valid and consistent with the
# compiled firmware. It does NOT prove the pins match your physical board.
# =============================================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1

IMAGE="${1:-klipper-haos:test}"
PRINTER="${2:-ender3-v3-se}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FW_DIR="${3:-${ROOT}/firmware/out/${PRINTER}}"
PROFILES="${ROOT}/klipper/rootfs/usr/share/klipper-haos/profiles"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRAS="${4:-}"
NEG_FW_DIR="${5:-}"
includes=""
for extra in ${EXTRAS}; do
    [[ "${extra}" =~ ^[A-Za-z0-9_.-]+\.cfg$ ]] || { echo "Invalid include: ${extra}" >&2; exit 1; }
    [[ -f "${PROFILES}/${PRINTER}/${extra}" ]] || { echo "Missing ${PRINTER}/${extra}" >&2; exit 1; }
    includes+="[include profiles/${PRINTER}/${extra}]"$'\n'
done

host_path() {
    if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

[[ -f "${FW_DIR}/klipper.dict" ]] || {
    echo "Missing ${FW_DIR}/klipper.dict - run tools/build-firmware.sh ${PRINTER} first" >&2
    exit 1
}
# docker run -v treats a relative source as a volume name, so use absolute
# paths for the firmware directories.
FW_DIR="$(cd "${FW_DIR}" && pwd)"
if [[ -n "${NEG_FW_DIR}" ]]; then
    [[ -f "${NEG_FW_DIR}/klipper.dict" ]] || { echo "Missing ${NEG_FW_DIR}/klipper.dict" >&2; exit 1; }
    NEG_FW_DIR="$(cd "${NEG_FW_DIR}" && pwd)"
fi

run_case() { # run_case <name> <gcode-file> <expect: ok|error> [grep-pattern] [firmware-dir]
    local name="$1" gcode="$2" expect="$3" pattern="${4:-}" fw="${5:-${FW_DIR}}" output rc
    set +e
    output=$(docker run --rm --entrypoint sh \
        -v "$(host_path "${PROFILES}"):/profiles:ro" \
        -v "$(host_path "${fw}"):/fw:ro" \
        -v "$(host_path "${HERE}"):/tests:ro" \
        "${IMAGE}" -c "
            set -e
            mkdir -p /config /tmp/gcodes
            cp -r /profiles /config/profiles
            cat > /config/printer.cfg <<'EOF'
[include /opt/mainsail-config/client.cfg]
[virtual_sdcard]
path: /tmp/gcodes
[include profiles/${PRINTER}/printer.cfg]
${includes}[mcu]
serial: /dev/null
EOF
            rc=0
            /opt/venv/klippy/bin/python /opt/klipper/klippy/klippy.py \
                /config/printer.cfg -i /tests/${gcode} -o /dev/null \
                -d /fw/klipper.dict -l /tmp/klippy.log || rc=\$?
            cat /tmp/klippy.log
            exit \$rc
        " 2>&1)
    rc=$?
    set -e
    local ok=0
    if [[ "${expect}" == "ok" ]]; then
        [[ ${rc} -eq 0 ]] && ok=1
    elif [[ ${rc} -ne 0 ]] && grep -qF -- "${pattern}" <<< "${output}"; then
        ok=1
    fi
    if (( ok )); then
        echo "  PASS  ${name}"
        return 0
    fi
    echo "  FAIL  ${name} (exit ${rc})"
    echo "${output}" | tail -30
    return 1
}

echo "== Profile ${PRINTER}${EXTRAS:+ + ${EXTRAS}} (Klipper batch mode, firmware $(cat "${FW_DIR}/klipper-version.txt"))"
failed=0
run_case "config loads and basic motion/heater G-code runs" basic.gcode ok || failed=1
run_case "START_PRINT is blocked before hardware validation" start-print-gate.gcode error \
    "Error evaluating 'gcode_macro START_PRINT:gcode': gcode.CommandError: START_PRINT blocked" || failed=1
run_case "START_PRINT runs after MARK_HARDWARE_VALIDATED" start-print-validated.gcode ok || failed=1
if [[ -n "${NEG_FW_DIR}" ]]; then
    [[ -f "${NEG_FW_DIR}/klipper.dict" ]] || { echo "Missing ${NEG_FW_DIR}/klipper.dict" >&2; exit 1; }
    run_case "Klipper refuses to start with firmware $(cat "${NEG_FW_DIR}/klipper-version.txt") (no serial bridge)" \
        basic.gcode error "Unknown command: serial_bridge_send" "${NEG_FW_DIR}" || failed=1
fi
exit ${failed}
