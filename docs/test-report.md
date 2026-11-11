# Test report

This report lists **only tests that were actually executed**, with their
real results. Anything not listed here has not been tested.

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
| App appears in the HAOS app store and installs | Needs a published image and a test HAOS host | v0.1.0 |
| Ingress through the real Home Assistant frontend and Supervisor (including remote access) | Tested only against a simulated Supervisor proxy | v0.3.0 |
| Large uploads through real ingress | As above | v0.3.0 |
| Supervisor `uart` mapping, `/dev/serial/by-id`, USB re-plug | Needs HAOS and a USB serial device | v0.2.0 |
| HA backup → restore cycle, app update and rollback | Needs HAOS | v0.3.0 |
| Client IP preservation on the published port (`trusted_networks`) | Depends on the HAOS Docker configuration | v0.3.0 |
| Supervisor watchdog restarting an unhealthy app | Needs HAOS | v0.3.0 |
| Resource usage on the target Celeron host, idle and printing | Needs the target hardware | v0.2.0 |
| Every step of the [hardware validation checklist](hardware-validation.md) | Needs the printer | v0.2.0 |
| Firmware flashing and recovery on an Ender 3 V3 SE | Needs the printer | v0.2.0 |
| GitHub Actions workflows and GHCR publishing | Need a GitHub repository; the workflows have not run yet | v0.1.0 |
| `frenck/action-addon-linter` | Runs in CI only. Locally the manifest was validated against the linter's JSON schema (0 errors), and its extra rules were reviewed (the obsolete `watchdog` key was removed) | v0.1.0 |
