#!/usr/bin/env bash
# =============================================================================
# Report pinned vs. latest upstream versions. Changes nothing.
#
#   tools/check-upstream.sh
#
# Bumping is a deliberate maintainer action; see docs/development.md.
# =============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="${ROOT}/klipper/Dockerfile"

arg() { sed -n "s/^ARG $1=//p" "${DOCKERFILE}"; }
latest_tag() {
    git ls-remote --tags --refs --sort=-v:refname "https://github.com/$1.git" \
        | head -1 | sed 's#.*refs/tags/##'
}
head_commit() {
    git ls-remote "https://github.com/$1.git" HEAD | cut -c1-12
}

printf '%-16s %-44s %s\n' "Component" "Pinned" "Upstream"
printf '%-16s %-44s %s\n' "klipper" "$(arg KLIPPER_COMMIT | cut -c1-12) (master)" \
    "$(head_commit Klipper3d/klipper) (master), latest tag $(latest_tag Klipper3d/klipper)"
printf '%-16s %-44s %s\n' "moonraker" "$(arg MOONRAKER_VERSION)" "$(latest_tag Arksine/moonraker)"
printf '%-16s %-44s %s\n' "mainsail" "$(arg MAINSAIL_VERSION)" "$(latest_tag mainsail-crew/mainsail)"
printf '%-16s %-44s %s\n' "mainsail-config" "$(arg MAINSAIL_CONFIG_VERSION)" "$(latest_tag mainsail-crew/mainsail-config)"
printf '%-16s %-44s\n' "base image" "$(arg BUILD_FROM | cut -d@ -f1)"
