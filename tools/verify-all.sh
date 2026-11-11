#!/usr/bin/env bash
# =============================================================================
# Run every automated test layer locally, in the same order as CI.
#
#   tools/verify-all.sh [--no-cache]
#
# Nothing here touches a Home Assistant installation or a printer.
# =============================================================================
set -uo pipefail
export MSYS_NO_PATHCONV=1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}" || exit 1
IMAGE=klipper-haos:test
SRC="${ROOT}"
if command -v cygpath > /dev/null 2>&1; then SRC="$(cygpath -w "${ROOT}")"; fi

results=()
run() { # run <name> <command...>
    local name="$1"; shift
    echo; echo "######## ${name}"
    if "$@"; then results+=("PASS  ${name}"); else results+=("FAIL  ${name}"); fi
}

version="$(sed -n 's/^version: "\(.*\)"/\1/p' klipper/config.yaml)"
# shellcheck disable=SC2086 # optional flag must stay unquoted when empty
if ! docker build ${1:-} --pull --build-arg BUILD_VERSION="${version}" -t "${IMAGE}" klipper; then
    # Never test a stale image left over from an earlier build.
    echo "Image build FAILED - aborting before tests"
    exit 1
fi
results+=("PASS  image build")
run "static validation" bash tests/static/run.sh
run "unit tests" docker run --rm -v "${SRC}:/src:ro" -w /src -e PYTHONDONTWRITEBYTECODE=1 \
    python:3.13-alpine sh -c 'pip install -q --root-user-action=ignore pytest==8.4.2 pyyaml==6.0.3 > /dev/null 2>&1 && python -m pytest -q -p no:cacheprovider tests/unit'
run "firmware build" bash tools/build-firmware.sh ender3-v3-se
run "profile validation" bash tests/profile/check-profile.sh "${IMAGE}" ender3-v3-se
run "integration tests" bash tests/integration/run.sh "${IMAGE}"

echo; echo "######## Summary"
printf '%s\n' "${results[@]}"
! printf '%s\n' "${results[@]}" | grep -q '^FAIL'
