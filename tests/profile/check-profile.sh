#!/usr/bin/env bash
# =============================================================================
# Validate a printer profile without hardware, using Klipper's batch mode.
#
#   tests/profile/check-profile.sh <image> <printer> <firmware-dir>
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

host_path() {
    if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

[[ -f "${FW_DIR}/klipper.dict" ]] || {
    echo "Missing ${FW_DIR}/klipper.dict - run tools/build-firmware.sh ${PRINTER} first" >&2
    exit 1
}

run_case() { # run_case <name> <gcode-file> <expect: ok|error> [grep-pattern]
    local name="$1" gcode="$2" expect="$3" pattern="${4:-}" output rc
    set +e
    output=$(docker run --rm --entrypoint sh \
        -v "$(host_path "${PROFILES}"):/profiles:ro" \
        -v "$(host_path "${FW_DIR}"):/fw:ro" \
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
[mcu]
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

echo "== Profile ${PRINTER} (Klipper batch mode, firmware $(cat "${FW_DIR}/klipper-version.txt"))"
failed=0
run_case "config loads and basic motion/heater G-code runs" basic.gcode ok || failed=1
run_case "START_PRINT is blocked before hardware validation" start-print-gate.gcode error \
    "Error evaluating 'gcode_macro START_PRINT:gcode': gcode.CommandError: START_PRINT blocked" || failed=1
run_case "START_PRINT runs after MARK_HARDWARE_VALIDATED" start-print-validated.gcode ok || failed=1
exit ${failed}
