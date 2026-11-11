# Test report

This report lists **only tests that were actually executed**, with their
real results. Anything not listed here has not been tested.

## v0.1.0 on real Home Assistant OS — 2026-11-11

Environment: the maintainer's Home Assistant OS host. HAOS 18.2
(`generic-x86-64`), Supervisor 2026.10.5, Home Assistant Core 2026.7.4,
amd64, 2 CPU cores, 3.7 GiB RAM (1.9 GiB available before the app
started). **No printer connected.** The only USB serial device on the host
is a Zigbee coordinator used by another app; `serial_device` was left
empty, so the app never opened it.

The app was installed from the published repository and the released
`ghcr.io/wendelnascimento/klipper-haos:0.1.0` image. Steps were driven
through the Supervisor API (the same calls the UI makes), and ingress was
tested with a real ingress session through Home Assistant Core.

| Check | Result |
|---|---|
| CI on GitHub Actions (static, app linter, unit, image, firmware, profile, integration) | **Pass** (after fixing two CI-only problems, see below) |
| Release workflow: metadata check, full test suite, amd64 image build and push, multi-arch manifest | **Pass**. Image pulled anonymously from GHCR |
| Release workflow: GitHub release with firmware | **Fail** in v0.1.0 (relative output path passed to `docker run -v`). Fixed after the release; v0.1.0 has no GitHub release or firmware assets |
| Repository added to the app store; app listed as experimental | **Pass**. The Supervisor logged a warning because it read `klipper/mainsail/config.json` as an app manifest (fixed after the release: file renamed, static check added) |
| Install (image pull 12 s), first start | **Pass**. Services start in order; starter configs and the Ender 3 V3 SE profile are seeded in the app config folder |
| `uart: true` mapping and `/dev/serial/by-id` | **Pass** (the app sees the host's serial device by id). No printer, so no Klipper connection |
| Klipper with no serial device | **Pass**: reports "Option 'serial' in section 'mcu' must be specified" |
| Security settings reported by the Supervisor | not privileged, no full access, no host network, AppArmor default profile, protection mode on, direct port unmapped |
| Real ingress (HA Core → Supervisor → app), 11 checks | **Pass**: Mainsail index and JS bundle use the real ingress path, no placeholder left, `config.json`, Moonraker API (200), request without an ingress session rejected (401), WebSocket upgrade with the HA `Origin` (101), 24 MiB G-code upload in 2 s (201), test file deleted |
| Idle resource use on this host | **56.5 MiB** RAM, about **0.4 %** CPU (three samples) |

CI-only problems found by the first GitHub run (both passed locally):

* The app linter rejects manifest keys set to their default value.
* The integration test read a root-owned, mode 600 file from the host;
  GitHub runners are not root. Reproduced with an unprivileged user in an
  Ubuntu container and fixed.

Observed but not changed: Moonraker downloads the public `usb.ids` file at
start-up (`machine.py: Fetching latest usb.ids file`). This is device-name
data, not code.

Not covered by this run: the Mainsail panel viewed in a browser inside the
Home Assistant frontend, backup and restore, update and rollback, the
watchdog, the direct port from another LAN host, and everything that needs
the printer.

## v0.1.0 (pre-release) — 2026-11-10

Environment: Windows 11 development PC, Docker Desktop (Engine 29.2.0,
WSL2, amd64). **Not** Home Assistant OS, **no** printer connected.

Command: `tools/verify-all.sh --no-cache` (the same layers as the CI
pipeline). Two layers failed on the first run, and both were fixed and
re-run:

* ShellCheck flagged an unguarded `cd` in the new `verify-all.sh` (fixed).
* The firmware build failed with an apt "Hash Sum mismatch". The developer
  network altered a 58 MB plain-HTTP package download, and apt correctly
  rejected it. `build-firmware.sh` now uses HTTPS mirrors with retries.
  The profile check failed only because it depends on the firmware.

| Layer | Result |
|---|---|
| Clean image build (`--no-cache --pull`, amd64) | **Pass**: 389 MB image, no compiler in runtime image |
| Static validation: ShellCheck (18 files), Hadolint, yamllint, s6 tree (5 services, no cycles), secret scan | **Pass** |
| Manifest vs. `frenck/action-addon-linter` JSON schema | **Pass**: 0 errors |
| Unit tests (pytest, Python 3.13 on Alpine): option validation, injection, config generation, idempotency, manifest consistency | **Pass**: 44 passed |
| MCU firmware build, Ender 3 V3 SE (STM32F103, 28 KiB bootloader, USART1, 250000) | **Pass**: reproducible, three builds gave identical SHA-256 `7cf49e4cdca3a6a7d49dd1e7a6e6377922dee88476e6b7f8c63ad07c8aecfe69` |
| Profile validation in Klipper batch mode against the compiled MCU dictionary | **Pass**: 3/3 (config and pins load, motion and heater G-code runs, START_PRINT gate blocks then allows) |
| Container integration tests against a simulated Supervisor ingress proxy | **Pass**: 41/41 (details below) |
| Vulnerability scan (Trivy 0.76.2, HIGH/CRITICAL, fixed-only) | 0 CRITICAL. 31 HIGH remain, all outside the app's runtime code paths: 24 in the base image's unused `tempio` binary, 7 in vendored build tooling (`pip`/`setuptools`/`wheel` internals). Tornado and Pillow findings were removed by the overrides |

### Integration test details (41 checks)

* **Start-up:** Moonraker reachable through ingress; Klipper connected;
  service order `init-khaos → klipper → moonraker → nginx`; Docker
  HEALTHCHECK reports *healthy*; starter `printer.cfg`, `moonraker.conf`,
  generated includes and the Ender 3 V3 SE profile seeded; Klipper reports
  the missing serial device; no compiler in the image.
* **Ingress:** Mainsail HTML and the main JS bundle use the ingress base
  path, with no placeholder left; deep links work; WebSocket upgrade works,
  also with a foreign (Home Assistant) `Origin`; the ingress port rejects
  other source addresses (403).
* **Direct port and security:** 401 without credentials; spoofed
  `X-Real-IP`/`X-Forwarded-For` ignored (401); Mainsail served; API key
  export works (file mode 600, key not in log); API key accepted (200);
  cross-origin WebSocket rejected (403).
* **Uploads:** a 24 MiB G-code upload through ingress (201) is stored in
  `/data`; an embedded thumbnail is extracted and downscaled (Pillow 13).
* **Backup hook:** `khaos-backup-pre` exits 0 and writes a database
  snapshot.
* **Lifecycle:** graceful stop in 4 s (timeout 30 s), exit code 0, clean
  Klipper stop logged; after a restart, uploads and user edits to
  `printer.cfg` are preserved.
* **Crash-loop protection:** after 5 forced Klipper crashes, Klipper stays
  down while Moonraker and Mainsail stay available.
* **Option validation:** `trusted_networks: ["0.0.0.0/0"]` stops the app
  with a clear error.
* **Resources (informational):** idle **55.6 MiB RAM**, about 0.2 % CPU for
  all services together, on the development PC (not the target Celeron).

### Manual check

Mainsail opened in a real browser through the simulated ingress path
(`/api/hassio_ingress/testtoken/`). All assets loaded, the WebSocket
connected, Klipper's live status was shown, and the config file browser
listed the seeded files. See the screenshot in the README.

## Not tested yet (requires real hardware or real HAOS)

| Requirement | Why not yet | Milestone |
|---|---|---|
| Mainsail panel in a browser inside the Home Assistant frontend (including remote access) | Real ingress was tested by script only (see the 2026-11-11 run) | v0.3.0 |
| Printer serial connection, USB re-plug | Needs the printer (`uart` and by-id were confirmed on HAOS) | v0.2.0 |
| HA backup → restore cycle, app update and rollback | Needs HAOS | v0.3.0 |
| Client IP preservation on the published port (`trusted_networks`) | Depends on the HAOS Docker configuration | v0.3.0 |
| Supervisor watchdog restarting an unhealthy app | Needs HAOS | v0.3.0 |
| Resource usage on the target Celeron host, idle and printing | Needs the target hardware | v0.2.0 |
| Every step of the [hardware validation checklist](hardware-validation.md) | Needs the printer | v0.2.0 |
| Firmware flashing and recovery on an Ender 3 V3 SE | Needs the printer | v0.2.0 |
| GitHub release with firmware assets | Failed in v0.1.0; fixed, first runs with the next release | v0.1.1 |
