# shellcheck shell=bash
# Shared paths and helpers for the Klipper HAOS service scripts.
# Sourced by s6 run/finish scripts; never executed directly.

export KHAOS_CONFIG_DIR="${KHAOS_CONFIG_DIR:-/config}"
export KHAOS_DATA_DIR="${KHAOS_DATA_DIR:-/data/printer_data}"
export KHAOS_RUN_DIR="${KHAOS_RUN_DIR:-/run/klipper-haos}"
export KHAOS_SHARE_DIR="${KHAOS_SHARE_DIR:-/usr/share/klipper-haos}"
export KHAOS_LIB_DIR="/usr/local/lib/klipper-haos"

export KLIPPY_PYTHON="/opt/venv/klippy/bin/python"
export MOONRAKER_PYTHON="/opt/venv/moonraker/bin/python"

export KHAOS_LOG_DIR="${KHAOS_DATA_DIR}/logs"
export KHAOS_MOONRAKER_SOCK="${KHAOS_DATA_DIR}/comms/moonraker.sock"

# Crash-loop protection: a service that fails this many times within the
# window is not restarted again (see khaos-finish).
export KHAOS_CRASH_MAX="${KHAOS_CRASH_MAX:-5}"
export KHAOS_CRASH_WINDOW="${KHAOS_CRASH_WINDOW:-300}"

export KHAOS_OPTIONS_FILE="${KHAOS_OPTIONS_FILE:-/data/options.json}"

# Read an app option from /data/options.json (the Supervisor storage
# contract). Deliberately does not use bashio::config, which queries the
# Supervisor API: reading the file needs no API access and also works in
# local container tests.
#   khaos::option <key> [default]
khaos::option() {
    local key="$1" default="${2:-}" value
    value=$(jq -r --arg k "${key}" \
        'if has($k) and .[$k] != null then .[$k] | tostring else empty end' \
        "${KHAOS_OPTIONS_FILE}" 2>/dev/null) || value=""
    if [[ -z "${value}" ]]; then
        printf '%s' "${default}"
    else
        printf '%s' "${value}"
    fi
}

# Seconds to wait before (re)starting a service that has crashed recently.
# Grows with the number of recent crashes: 0, 2, 4, 8, 16 ...
#   khaos::restart_delay <service>
khaos::restart_delay() {
    local count=0 file="${KHAOS_RUN_DIR}/crashes-${1}"
    if [[ -f "${file}" ]]; then
        count=$(wc -l < "${file}")
    fi
    if (( count == 0 )); then
        echo 0
    else
        echo $(( 2 ** count > 30 ? 30 : 2 ** count ))
    fi
}
