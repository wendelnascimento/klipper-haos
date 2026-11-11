#!/usr/bin/env bash
# =============================================================================
# Regenerate the Python constraint files after bumping Klipper or Moonraker.
#
#   tools/update-locks.sh
#
# Builds the python-build stage WITHOUT the existing constraints (so pip
# resolves fresh versions within upstream's own ranges), then writes the
# resulting `pip freeze` output to klipper/requirements/*.txt.
# Review the diff, rebuild, and run the full test suite before committing.
# =============================================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ="${ROOT}/klipper/requirements"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

cp -r "${ROOT}/klipper/." "${TMP}/"
for f in klippy moonraker; do
    head -2 "${REQ}/${f}.txt" > "${TMP}/requirements/${f}.txt"
done

docker build --target python-build -t klipper-haos:locks "${TMP}"

for f in klippy moonraker; do
    {
        head -2 "${REQ}/${f}.txt"
        docker run --rm --entrypoint cat klipper-haos:locks "/opt/${f}-freeze.txt"
    } > "${TMP}/${f}.lock"
    mv "${TMP}/${f}.lock" "${REQ}/${f}.txt"
done
echo "Updated: $(cd "${ROOT}" && git diff --stat -- klipper/requirements | tail -1)"
