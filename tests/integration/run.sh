#!/usr/bin/env bash
# =============================================================================
# Container integration tests for the Klipper HAOS app (no printer needed).
#
#   tests/integration/run.sh [image]          (default image: klipper-haos:test)
#
# Starts the app on a Docker network that mirrors the Home Assistant internal
# network (172.30.32.0/23) together with a fake Supervisor ingress proxy at
# 172.30.32.2, then checks start-up order, ingress, authentication, uploads,
# WebSockets, persistence, crash-loop protection and graceful shutdown.
#
# Environment: KEEP=1 leaves the containers running for manual inspection.
# =============================================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1 # Git Bash on Windows: do not mangle /paths

IMAGE="${1:-klipper-haos:test}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NET=khaos-test-net
APP=khaos-app
PROXY=khaos-ingress
INGRESS_PORT="${INGRESS_PORT:-18123}"
DIRECT_PORT="${DIRECT_PORT:-17125}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/khaos-it.XXXXXX")"
INGRESS="http://127.0.0.1:${INGRESS_PORT}/api/hassio_ingress/testtoken"
DIRECT="http://127.0.0.1:${DIRECT_PORT}"
# Native Windows curl (Git Bash) cannot write to /dev/null once path
# conversion is disabled; use NUL there.
if command -v cygpath > /dev/null 2>&1; then DEVNULL=NUL; else DEVNULL=/dev/null; fi

passed=0
failed=0
pass() { echo "  PASS  $*"; passed=$((passed + 1)); }
fail() { echo "  FAIL  $*"; failed=$((failed + 1)); }
check() { # check <description> <command...>
    local desc="$1"; shift
    if "$@" > /dev/null 2>&1; then pass "${desc}"; else fail "${desc}"; fi
}

host_path() { # Docker on Windows needs native paths for bind mounts
    if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

cleanup() {
    if [[ "${KEEP:-0}" == "1" ]]; then
        echo "KEEP=1: leaving ${APP} and ${PROXY} running (work dir ${WORK})"
        return
    fi
    docker rm -f "${APP}" "${PROXY}" > /dev/null 2>&1 || true
    docker network rm "${NET}" > /dev/null 2>&1 || true
    docker run --rm -v "$(host_path "${WORK}"):/w" alpine:3.23 rm -rf /w/data /w/config > /dev/null 2>&1 || true
    rm -rf "${WORK}"
}
trap cleanup EXIT

write_options() {
    cat > "${WORK}/data/options.json" <<EOF
{"log_level": "info", "trusted_networks": ${1:-[]}, "cors_domains": [], "export_api_key": ${2:-true}}
EOF
}

start_app() {
    docker run -d --name "${APP}" --network "${NET}" --ip 172.30.33.10 \
        --tmpfs /tmp \
        -v "$(host_path "${WORK}/data"):/data" \
        -v "$(host_path "${WORK}/config"):/config" \
        -p "127.0.0.1:${DIRECT_PORT}:7125" \
        "${IMAGE}" > /dev/null
}

wait_for() { # wait_for <seconds> <command...>
    local timeout="$1"; shift
    local end=$((SECONDS + timeout))
    while (( SECONDS < end )); do
        if "$@" > /dev/null 2>&1; then return 0; fi
        sleep 1
    done
    return 1
}

klippy_state() {
    curl -sf "${INGRESS}/server/info" | grep -o '"klippy_state": *"[a-z]*"' | grep -o '[a-z]*"$' | tr -d '"'
}

echo "== Setup (image ${IMAGE})"
mkdir -p "${WORK}/data" "${WORK}/config"
write_options
docker rm -f "${APP}" "${PROXY}" > /dev/null 2>&1 || true
docker network rm "${NET}" > /dev/null 2>&1 || true
docker network create --subnet 172.30.32.0/23 "${NET}" > /dev/null
start_app
docker run -d --name "${PROXY}" --network "${NET}" --ip 172.30.32.2 \
    -v "$(host_path "${HERE}/fake-ingress.conf"):/etc/nginx/conf.d/default.conf:ro" \
    -p "127.0.0.1:${INGRESS_PORT}:80" nginx:1.29-alpine > /dev/null

echo "== Start-up"
if wait_for 90 curl -sf "${INGRESS}/server/info"; then
    pass "Moonraker answers through ingress"
else
    fail "Moonraker answers through ingress"
    docker logs "${APP}" 2>&1 | tail -50
    exit 1
fi
check "Klipper connected to Moonraker (state reported)" wait_for 60 bash -c "[[ -n \"\$(curl -sf '${INGRESS}/server/info' | grep -o 'klippy_connected\": *true')\" ]]"
logs="$(docker logs "${APP}" 2>&1)"
order="$(grep -o -E 'service (init-khaos|klipper|moonraker|nginx) successfully started' <<< "${logs}" | awk '{print $2}' | tr '\n' ' ')"
if [[ "${order}" == "init-khaos klipper moonraker nginx " ]]; then
    pass "services started in order: ${order}"
else
    fail "service start order: '${order}'"
fi
health_is() { [[ "$(docker inspect -f '{{.State.Health.Status}}' "${APP}")" == "$1" ]]; }
check "container reports healthy (Docker HEALTHCHECK)" wait_for 90 health_is healthy
check "starter printer.cfg was seeded" test -f "${WORK}/config/printer.cfg"
check "moonraker.conf was seeded" test -f "${WORK}/config/moonraker.conf"
check "generated Klipper include exists" test -f "${WORK}/config/klipper-haos/generated.cfg"
check "Ender 3 V3 SE profile was installed" test -f "${WORK}/config/profiles/ender3-v3-se/printer.cfg"
check "Klipper reports the missing serial device" bash -c "curl -sf '${INGRESS}/printer/info' | grep -q \"Option 'serial' in section 'mcu' must be specified\""
check "no compiler in the runtime image" bash -c "! docker exec ${APP} sh -c 'command -v gcc'"

echo "== Ingress"
index="$(curl -sf "${INGRESS}/")"
if grep -q 'src="/api/hassio_ingress/testtoken/assets/' <<< "${index}"; then
    pass "Mainsail index uses the ingress base path"
else
    fail "Mainsail index uses the ingress base path"
fi
if grep -q '__KHAOS_BASE__' <<< "${index}"; then
    fail "placeholder base path left in ingress index"
else
    pass "no placeholder base path left in ingress index"
fi
asset="$(grep -o 'src="/api/hassio_ingress/testtoken/assets/[^"]*"' <<< "${index}" | head -1 | cut -d'"' -f2)"
asset_body="$(curl -sf "http://127.0.0.1:${INGRESS_PORT}${asset}" || true)"
# The backticks are literal: Mainsail's bundle uses a template string.
# shellcheck disable=SC2016
if [[ -n "${asset_body}" ]] && ! grep -q '__KHAOS_BASE__' <<< "${asset_body}" \
    && grep -q 'path:`/api/hassio_ingress/testtoken`' <<< "${asset_body}"; then
    pass "main bundle loads and points the WebSocket at the ingress path"
else
    fail "main bundle loads and points the WebSocket at the ingress path"
fi
check "deep link falls back to index.html" curl -sf "${INGRESS}/config"
ws_status() { # ws_status <url> [origin]
    local origin_args=()
    [[ -n "${2:-}" ]] && origin_args=(-H "Origin: $2")
    curl -s -o "${DEVNULL}" -w '%{http_code}' --http1.1 \
        -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
        -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
        "${origin_args[@]}" --max-time 3 "$1" || true
}
status=$(ws_status "${INGRESS}/websocket")
if [[ "${status}" == "101" ]]; then pass "WebSocket upgrade through ingress (101)"; else fail "WebSocket upgrade through ingress (got ${status})"; fi
# Browsers send the Home Assistant origin, which differs from the Host that
# reaches the app behind the Supervisor proxy.
status=$(ws_status "${INGRESS}/websocket" "http://homeassistant.local:8123")
if [[ "${status}" == "101" ]]; then pass "browser-style WebSocket (HA Origin) through ingress (101)"; else fail "browser-style WebSocket through ingress (got ${status})"; fi
check "ingress port rejects other source addresses (403)" bash -c "[[ \$(docker exec ${APP} curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8099/) == 403 ]]"

echo "== Authentication on the direct port"
code=$(curl -s -o "${DEVNULL}" -w '%{http_code}' "${DIRECT}/server/info")
if [[ "${code}" == "401" ]]; then pass "direct port requires authentication (401)"; else fail "direct port without credentials returned ${code}"; fi
code=$(curl -s -o "${DEVNULL}" -w '%{http_code}' -H 'X-Real-IP: 172.30.32.2' -H 'X-Forwarded-For: 172.30.32.2' "${DIRECT}/server/info")
if [[ "${code}" == "401" ]]; then pass "spoofed X-Real-IP/X-Forwarded-For is ignored (401)"; else fail "spoofed proxy headers returned ${code}"; fi
check "Mainsail is served on the direct port" bash -c "curl -sf '${DIRECT}/' | grep -q 'src=\"/assets/'"
if wait_for 60 test -s "${WORK}/config/moonraker.apikey"; then
    pass "API key exported when export_api_key is on"
    key="$(tr -d '\r\n' < "${WORK}/config/moonraker.apikey")"
    code=$(curl -s -o "${DEVNULL}" -w '%{http_code}' -H "X-Api-Key: ${key}" "${DIRECT}/server/info")
    if [[ "${code}" == "200" ]]; then pass "direct port accepts the API key (200)"; else fail "API key request returned ${code}"; fi
    perms=$(docker exec "${APP}" stat -c '%a' /config/moonraker.apikey)
    if [[ "${perms}" == "600" ]]; then pass "API key file is mode 600"; else fail "API key file mode is ${perms}"; fi
    check "API key is not written to the app log" bash -c "! docker logs ${APP} 2>&1 | grep -q '${key}'"
    status=$(curl -s -o "${DEVNULL}" -w '%{http_code}' --http1.1 \
        -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H "X-Api-Key: ${key}" \
        -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
        -H 'Origin: http://evil.example' --max-time 3 "${DIRECT}/websocket" || true)
    if [[ "${status}" == "403" ]]; then pass "direct port rejects cross-origin WebSocket (403)"; else fail "cross-origin WebSocket on direct port got ${status}"; fi
else
    fail "API key exported when export_api_key is on"
fi

echo "== G-code upload and persistence"
dd if=/dev/zero bs=1M count=24 2> /dev/null | tr '\0' ';' > "${WORK}/big.gcode"
code=$(curl -s -o "${DEVNULL}" -w '%{http_code}' -F "file=@$(host_path "${WORK}/big.gcode");filename=big.gcode" "${INGRESS}/server/files/upload")
if [[ "${code}" == "201" ]]; then pass "24 MiB G-code upload through ingress (201)"; else fail "upload returned ${code}"; fi
check "uploaded file stored in /data/printer_data/gcodes" test -f "${WORK}/data/printer_data/gcodes/big.gcode"
echo "# user edit marker" >> "${WORK}/config/printer.cfg"

# Thumbnails embedded in G-code are decoded and resized with Pillow (which
# the app upgrades beyond Moonraker's cap for security fixes).
PYTHON_BIN=""
for candidate in python3 python; do # skip stubs that do not run (Windows Store alias)
    if "${candidate}" --version > /dev/null 2>&1; then PYTHON_BIN="${candidate}"; break; fi
done
"${PYTHON_BIN}" "$(host_path "${HERE}/make_thumbnail_gcode.py")" "$(host_path "${WORK}/thumb.gcode")"
curl -s -o "${DEVNULL}" -F "file=@$(host_path "${WORK}/thumb.gcode");filename=thumb.gcode" "${INGRESS}/server/files/upload"
thumbs_ok() {
    local meta
    meta="$(curl -sf "${INGRESS}/server/files/metadata?filename=thumb.gcode")" || return 1
    grep -q '"width": *300' <<< "${meta}" && grep -q '"width": *32' <<< "${meta}"
}
check "G-code thumbnail extracted and downscaled (Pillow)" wait_for 30 thumbs_ok
check "thumbnail files written" bash -c "ls '${WORK}/data/printer_data/gcodes/.thumbs/' | grep -q 'thumb-32x32.png'"

echo "== Pre-backup hook"
check "backup_pre hook exits 0" docker exec "${APP}" /usr/local/bin/khaos-backup-pre
check "database snapshot written" bash -c "ls '${WORK}/data/printer_data/backup/database/' | grep -q klipper-haos-pre-backup"

echo "== Graceful shutdown and restart"
start=${SECONDS}
docker stop -t 30 "${APP}" > /dev/null
elapsed=$((SECONDS - start))
exit_code=$(docker inspect -f '{{.State.ExitCode}}' "${APP}")
if (( elapsed < 25 )); then pass "app stopped in ${elapsed}s (before the kill timeout)"; else fail "stop took ${elapsed}s"; fi
if [[ "${exit_code}" == "0" ]]; then pass "clean exit code (0)"; else fail "exit code ${exit_code}"; fi
check "Klipper logged a clean stop" bash -c "docker logs ${APP} 2>&1 | grep -q 'klipper stopped.'"
docker start "${APP}" > /dev/null
check "app comes back after restart" wait_for 90 curl -sf "${INGRESS}/server/info"
check "uploaded G-code survived the restart" test -f "${WORK}/data/printer_data/gcodes/big.gcode"
check "user edits to printer.cfg were preserved" grep -q "user edit marker" "${WORK}/config/printer.cfg"

echo "== Crash-loop protection"
wait_for 60 bash -c "docker exec ${APP} pgrep -f klippy.py" || true
for _ in 1 2 3 4 5; do
    wait_for 40 bash -c "docker exec ${APP} pgrep -f klippy.py" || true
    docker exec "${APP}" pkill -9 -f klippy.py > /dev/null 2>&1 || true
    sleep 2
done
sleep 5
if docker logs "${APP}" 2>&1 | grep -q 'klipper failed 5 times'; then
    pass "Klipper is not restarted after 5 crashes"
else
    fail "crash-loop protection did not trigger"
fi
check "Klipper stays down" bash -c "! docker exec ${APP} pgrep -f klippy.py"
check "Moonraker and Mainsail stay available" curl -sf "${INGRESS}/server/info"

echo "== Option validation"
docker rm -f "${APP}" > /dev/null
write_options '["0.0.0.0/0"]' false
start_app
wait_for 30 bash -c "[[ \$(docker inspect -f '{{.State.Running}}' ${APP}) == false ]]" || true
if [[ "$(docker inspect -f '{{.State.Running}}' "${APP}")" == "false" ]] \
    && docker logs "${APP}" 2>&1 | grep -q 'too broad'; then
    pass "unsafe trusted_networks value stops the app with a clear error"
else
    fail "unsafe trusted_networks value was not rejected"
fi

echo "== Resource usage"
docker rm -f "${APP}" > /dev/null
write_options '[]' false
start_app
wait_for 90 curl -sf "${INGRESS}/server/info" > /dev/null || true
sleep 20
echo "  INFO  idle memory/CPU: $(docker stats --no-stream --format '{{.MemUsage}} / CPU {{.CPUPerc}}' "${APP}")"

echo
echo "Result: ${passed} passed, ${failed} failed"
(( failed == 0 ))
