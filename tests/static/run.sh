#!/usr/bin/env bash
# =============================================================================
# Static validation: shell scripts, Dockerfile, YAML, s6 service tree,
# security-sensitive settings. Uses pinned linter containers so results are
# the same locally and in CI.
#
#   tests/static/run.sh
# =============================================================================
set -uo pipefail
export MSYS_NO_PATHCONV=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="${ROOT}"
if command -v cygpath > /dev/null 2>&1; then SRC="$(cygpath -w "${ROOT}")"; fi

SHELLCHECK_IMAGE="koalaman/shellcheck:v0.11.0"
HADOLINT_IMAGE="hadolint/hadolint:v2.14.0"
PYTHON_IMAGE="python:3.13-alpine"

failed=0
step() { echo; echo "== $*"; }

step "ShellCheck"
mapfile -t scripts < <(cd "${ROOT}" && grep -rl --include='*' -E '^#!.*(bash|bashio|/bin/sh)' \
    klipper/rootfs tests tools 2>/dev/null | sort)
scripts+=("klipper/rootfs/usr/local/lib/klipper-haos/common.sh")
if docker run --rm -v "${SRC}:/mnt:ro" -w /mnt "${SHELLCHECK_IMAGE}" \
    --shell=bash --external-sources --source-path=SCRIPTDIR "${scripts[@]}"; then
    echo "ShellCheck passed (${#scripts[@]} files)"
else
    failed=1
fi

step "Hadolint"
if docker run --rm -i -v "${SRC}:/mnt:ro" "${HADOLINT_IMAGE}" \
    hadolint --config /mnt/.hadolint.yaml /mnt/klipper/Dockerfile; then
    echo "Hadolint passed"
else
    failed=1
fi

step "yamllint + s6 tree + secrets"
if docker run --rm -v "${SRC}:/src:ro" -w /src -e PYTHONDONTWRITEBYTECODE=1 "${PYTHON_IMAGE}" sh -c '
        pip install -q --root-user-action=ignore yamllint==1.37.1 > /dev/null 2>&1 &&
        yamllint -s . && echo "yamllint passed" &&
        python3 tests/static/check-s6.py'; then
    :
else
    failed=1
fi

echo
if (( failed )); then echo "Static validation FAILED"; else echo "Static validation passed"; fi
exit ${failed}
