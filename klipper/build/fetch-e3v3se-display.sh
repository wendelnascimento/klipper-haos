#!/bin/sh
# =============================================================================
# Add the pinned Ender 3 V3 SE display files to a Klipper source tree.
#
#   fetch-e3v3se-display.sh LOCKFILE KLIPPER_DIR PART
#       LOCKFILE     klipper/requirements/e3v3se-display.lock
#       KLIPPER_DIR  an upstream Klipper checkout
#       PART         klippy (host modules) or src (MCU serial bridge)
#
# Fetches the fork at the exact commit in LOCKFILE, verifies the SHA-256 of
# every listed file, and copies only those files. It never overwrites a file
# that already exists in KLIPPER_DIR, so upstream Klipper code cannot be
# replaced by accident. Used by klipper/Dockerfile and tools/build-firmware.sh.
# =============================================================================
set -eu

lock="$1"
dest="$2"
part="$3"

case "${part}" in
    klippy | src) ;;
    *) echo "PART must be 'klippy' or 'src'" >&2; exit 2 ;;
esac

repo="$(sed -n 's/^repo //p' "${lock}")"
commit="$(sed -n 's/^commit //p' "${lock}")"
[ -n "${repo}" ] && [ -n "${commit}" ] || { echo "repo/commit missing in ${lock}" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

git -C "${tmp}" init -q
# Retry: some networks corrupt large downloads ("invalid index-pack output").
# Git verifies every object, so a bad download fails instead of being used.
attempt=1
until git -C "${tmp}" fetch -q --depth 1 "${repo}" "${commit}"; do
    [ "${attempt}" -lt 3 ] || { echo "fetch failed after ${attempt} attempts" >&2; exit 1; }
    attempt=$((attempt + 1))
    echo "fetch failed, retrying (${attempt}/3)" >&2
    sleep 5
done
git -C "${tmp}" -c advice.detachedHead=false checkout -q FETCH_HEAD
[ "$(git -C "${tmp}" rev-parse HEAD)" = "${commit}" ] || { echo "commit mismatch" >&2; exit 1; }

grep -E "^[0-9a-f]{64}  ${part}/" "${lock}" > "${tmp}/.sums" || true
[ -s "${tmp}/.sums" ] || { echo "no '${part}' files listed in ${lock}" >&2; exit 1; }
if ! (cd "${tmp}" && sha256sum -c .sums > /dev/null); then
    echo "Checksum mismatch for files from ${repo} at ${commit}" >&2
    exit 1
fi

while read -r _sum path; do
    if [ -e "${dest}/${path}" ]; then
        echo "Refusing to overwrite existing ${path}" >&2
        exit 1
    fi
    mkdir -p "${dest}/$(dirname "${path}")"
    cp "${tmp}/${path}" "${dest}/${path}"
    echo "Added ${path} (${commit})"
done < "${tmp}/.sums"
