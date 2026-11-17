# syntax=docker/dockerfile:1
#
# Klipper HAOS app image.
#
# Three stages:
#   1. mainsail      - builds the Mainsail web UI from a pinned source tag
#   2. python-build  - fetches Klipper/Moonraker at pinned commits and the
#                      Spoolman release archive by SHA-256, and builds their
#                      Python virtual environments (incl. C extensions)
#   3. runtime       - the final image: no compilers, no git, no node
#
# All upstream versions are pinned by tag *and* verified by commit hash.
# See docs/development.md ("Updating upstream components") before bumping.

ARG BUILD_FROM=ghcr.io/home-assistant/base-python:3.13-alpine3.23@sha256:22f6f64892d442518cc02dfb7df1ba00442af299bdeab4b1acf7eaa715d012ef
ARG NODE_IMAGE=node:22.23.4-alpine3.23@sha256:2cfe8c19bd3df0192ad5dfd2e13e86567743ffa1eb614e750a706891f19606af

# Upstream pins ---------------------------------------------------------------
# Klipper tags releases rarely; upstream recommends tracking master. We pin an
# exact master commit that has been tested with the Moonraker release below.
ARG KLIPPER_COMMIT=29d4ec2d6d840ee839333306003a400da186d41d
ARG MOONRAKER_VERSION=v0.11.0
ARG MOONRAKER_COMMIT=985c1d0bbeb90bc057d34a232c9dc3b05e0c6c8d
ARG MAINSAIL_VERSION=v2.19.0
ARG MAINSAIL_COMMIT=5fb9e77fb9f4e60cf0725d9dc7f57cf7b84bbd70
ARG MAINSAIL_CONFIG_VERSION=v1.2.1
ARG MAINSAIL_CONFIG_COMMIT=e57810d51b5c634aadaca4db923bfcba269ae4b3
# Spoolman (optional, off by default): the upstream release archive, which
# already contains the built web client. Verified by SHA-256.
ARG SPOOLMAN_VERSION=v0.27.1
ARG SPOOLMAN_SHA256=77ba10fa505a42cef606eabec1a7c9a5b93c51dc40067456a29a7d9480ef27d6

###############################################################################
# Stage 1: Mainsail
###############################################################################
FROM ${NODE_IMAGE} AS mainsail
ARG MAINSAIL_VERSION
ARG MAINSAIL_COMMIT

RUN apk add --no-cache git

WORKDIR /src
RUN git clone --depth 1 --branch "${MAINSAIL_VERSION}" \
        https://github.com/mainsail-crew/mainsail.git . \
    && test "$(git rev-parse HEAD)" = "${MAINSAIL_COMMIT}"

# One small change: Mainsail's "Open Spoolman" button points at the Spoolman
# bundled in this app, under the app's own base path (see the patch header and
# THIRD_PARTY_NOTICES.md). --check first, so an upstream change fails the build
# instead of silently skipping the patch.
COPY mainsail/patches /tmp/mainsail-patches
RUN for p in /tmp/mainsail-patches/*.patch; do \
        git apply --check "${p}" && git apply "${p}" || exit 1; \
    done

RUN npm ci --no-audit --no-fund

# Mainsail is built with a placeholder base path. At request time nginx
# replaces the placeholder with the Home Assistant ingress path (or with an
# empty string on the direct port), so one build serves both entry points.
RUN VUE_APP_PATH=/__KHAOS_BASE__ npx vite build --base=/__KHAOS_BASE__/ \
    && grep -rq "__KHAOS_BASE__" dist \
    && rm -f dist/*.zip

COPY mainsail/mainsail-settings.json dist/config.json

###############################################################################
# Stage 2: Klipper + Moonraker Python environments
###############################################################################
FROM ${BUILD_FROM} AS python-build
ARG KLIPPER_COMMIT
ARG MOONRAKER_VERSION
ARG MOONRAKER_COMMIT
ARG MAINSAIL_CONFIG_VERSION
ARG MAINSAIL_CONFIG_COMMIT
ARG SPOOLMAN_VERSION
ARG SPOOLMAN_SHA256

RUN apk add --no-cache \
        build-base \
        git \
        jpeg-dev \
        libffi-dev \
        libsodium-dev \
        zlib-dev

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

COPY requirements /tmp/requirements

# --- Klipper (host software only) --------------------------------------------
RUN git clone --filter=blob:none https://github.com/Klipper3d/klipper.git /opt/klipper \
    && cd /opt/klipper \
    && git checkout -q "${KLIPPER_COMMIT}" \
    && git describe --tags --always --long > klippy/.version \
    && echo "Klipper $(cat klippy/.version)" \
    # MCU sources, docs and tests are not needed on the host. Firmware is
    # built separately (see firmware/), never inside this image.
    && rm -rf .git .github lib src test out

# --- Ender 3 V3 SE display modules (experimental) -----------------------------
# Host modules for the original Creality display, from a pinned fork commit
# with per-file SHA-256 checks (see the lock file). They only add new files to
# klippy/extras and stay inactive unless printer.cfg has [e3v3se_display].
COPY build/fetch-e3v3se-display.sh /tmp/build/fetch-e3v3se-display.sh
RUN sh /tmp/build/fetch-e3v3se-display.sh \
        /tmp/requirements/e3v3se-display.lock /opt/klipper klippy

RUN python3 -m venv /opt/venv/klippy \
    && /opt/venv/klippy/bin/pip install \
        -r /opt/klipper/scripts/klippy-requirements.txt \
        -c /tmp/requirements/klippy.txt \
    # Pre-build Klipper's C helper so the runtime image never needs gcc.
    && /opt/venv/klippy/bin/python /opt/klipper/klippy/chelper/__init__.py \
    && test -f /opt/klipper/klippy/chelper/c_helper.so \
    && /opt/venv/klippy/bin/python -m compileall -q /opt/klipper/klippy

# --- Moonraker ---------------------------------------------------------------
RUN git clone --depth 1 --branch "${MOONRAKER_VERSION}" \
        https://github.com/Arksine/moonraker.git /opt/moonraker \
    && cd /opt/moonraker \
    && test "$(git rev-parse HEAD)" = "${MOONRAKER_COMMIT}" \
    && echo "${MOONRAKER_VERSION}" > moonraker/.version \
    && rm -rf .git .github docs tests

RUN python3 -m venv /opt/venv/moonraker \
    && cd /opt/moonraker/scripts \
    && /opt/venv/moonraker/bin/pip install \
        -r moonraker-requirements.txt \
        msgspec \
        -c /tmp/requirements/moonraker.txt \
    # Security fixes beyond Moonraker's version caps (see the file for why).
    && /opt/venv/moonraker/bin/pip install --no-deps \
        -r /tmp/requirements/moonraker-overrides.txt \
    && /opt/venv/moonraker/bin/python -m compileall -q /opt/moonraker/moonraker

# --- Mainsail client macros (mainsail-config) ---------------------------------
RUN git clone --depth 1 --branch "${MAINSAIL_CONFIG_VERSION}" \
        https://github.com/mainsail-crew/mainsail-config.git /opt/mainsail-config \
    && cd /opt/mainsail-config \
    && test "$(git rev-parse HEAD)" = "${MAINSAIL_CONFIG_COMMIT}" \
    && rm -rf .git .github

# --- Spoolman (filament inventory, optional) ---------------------------------
# Upstream's requirements.txt is an exact lock exported from its uv.lock, so
# it is used as is. Tests, dev scripts and the legacy React client are not
# shipped; the app always serves the current client.
RUN wget -q -O /tmp/spoolman.zip \
        "https://github.com/Donkie/Spoolman/releases/download/${SPOOLMAN_VERSION}/spoolman.zip" \
    && echo "${SPOOLMAN_SHA256}  /tmp/spoolman.zip" > /tmp/spoolman.zip.sha256 \
    && sha256sum -c /tmp/spoolman.zip.sha256 \
    && mkdir -p /opt/spoolman \
    && unzip -q /tmp/spoolman.zip -d /opt/spoolman \
    && rm /tmp/spoolman.zip /tmp/spoolman.zip.sha256 \
    && cd /opt/spoolman \
    && grep -q "\"version\": \"${SPOOLMAN_VERSION}\"" release_info.json \
    && test -f client_v2/build/200.html \
    && rm -rf .github client scripts tests tests_frontend tests_frontend_v2 \
        tests_integration Dockerfile entrypoint.sh lefthook.yml uv.lock

RUN python3 -m venv /opt/venv/spoolman \
    && /opt/venv/spoolman/bin/pip install -r /opt/spoolman/requirements.txt \
    && /opt/venv/spoolman/bin/python -m compileall -q /opt/spoolman/spoolman /opt/spoolman/migrations

# Record exact dependency versions for traceability (shown in the app log).
RUN { \
        echo "klipper=$(cat /opt/klipper/klippy/.version)"; \
        echo "moonraker=$(cat /opt/moonraker/moonraker/.version)"; \
        echo "mainsail_config=${MAINSAIL_CONFIG_VERSION}"; \
        echo "e3v3se_display=$(sed -n 's/^commit \(.\{12\}\).*/\1/p' /tmp/requirements/e3v3se-display.lock)"; \
        echo "spoolman=${SPOOLMAN_VERSION}"; \
        echo "python=$(python3 -c 'import platform; print(platform.python_version())')"; \
    } > /opt/versions.txt \
    && /opt/venv/klippy/bin/pip freeze > /opt/klippy-freeze.txt \
    && /opt/venv/moonraker/bin/pip freeze > /opt/moonraker-freeze.txt \
    && /opt/venv/spoolman/bin/pip freeze > /opt/spoolman-freeze.txt

###############################################################################
# Stage 3: runtime
###############################################################################
FROM ${BUILD_FROM}
ARG BUILD_VERSION=dev
ARG BUILD_ARCH=amd64
ARG MAINSAIL_VERSION

RUN apk add --no-cache \
        # 'ip' is used by Moonraker to report network interfaces.
        iproute2-minimal \
        libjpeg-turbo \
        libsodium \
        nginx \
        zlib \
    # Use our own nginx configuration only.
    && rm -rf /etc/nginx/http.d /etc/nginx/nginx.conf

COPY --from=python-build /opt/klipper /opt/klipper
COPY --from=python-build /opt/moonraker /opt/moonraker
COPY --from=python-build /opt/venv /opt/venv
COPY --from=python-build /opt/mainsail-config /opt/mainsail-config
COPY --from=python-build /opt/spoolman /opt/spoolman
COPY --from=python-build /opt/versions.txt /opt/klippy-freeze.txt /opt/moonraker-freeze.txt /opt/spoolman-freeze.txt /opt/
COPY --from=mainsail /src/dist /opt/mainsail

RUN echo "mainsail=${MAINSAIL_VERSION}" >> /opt/versions.txt \
    && echo "app=${BUILD_VERSION}" >> /opt/versions.txt

COPY rootfs /
# Executable bits are not preserved when building from some checkouts
# (e.g. Windows); set them explicitly.
RUN chmod 0755 \
        /etc/s6-overlay/s6-rc.d/*/run \
        /etc/s6-overlay/s6-rc.d/*/finish \
        /etc/s6-overlay/scripts/* \
        /usr/local/bin/khaos-* \
    && mkdir -p /tmp/nginx && nginx -t -c /etc/nginx/nginx.conf && rm -rf /tmp/nginx

# Healthy = nginx and Moonraker answer. Klipper's state is deliberately not
# checked: a printer.cfg error or a switched-off printer must not cause app
# restarts. /access/info needs no authentication. With the app's Watchdog
# toggle enabled, the Supervisor restarts an unhealthy app.
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --start-interval=5s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1:7125/access/info || exit 1

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

LABEL \
    io.hass.type="app" \
    io.hass.name="Klipper" \
    io.hass.description="Klipper, Moonraker and Mainsail on Home Assistant OS" \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.title="Home Assistant App: Klipper" \
    org.opencontainers.image.description="Klipper, Moonraker and Mainsail on Home Assistant OS" \
    org.opencontainers.image.source="https://github.com/wendelnascimento/klipper-haos" \
    org.opencontainers.image.licenses="MIT AND GPL-3.0-only" \
    org.opencontainers.image.version="${BUILD_VERSION}"
