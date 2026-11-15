# Test report

This report lists **only tests that were actually executed**, with their
real results. Anything not listed here has not been tested.

## Real printer: Ender 3 V3 SE on Home Assistant OS — 2026-11-14 to 2026-11-15

Environment: the target host from the runs below (HAOS 18.2, 2 CPU cores,
3.7 GiB RAM), apps 0.1.1 to 0.1.3, and the maintainer's Creality Ender 3
V3 SE (MCU `stm32f103xe`), stock wiring and stock display, over USB. The
app's `serial_device` is the printer's `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`,
not the host's Zigbee coordinator.

Two kinds of evidence, kept apart below:

* **Observed:** read from the running system through the Moonraker and
  Supervisor APIs: Klipper status, saved configuration, the Moonraker job
  history and the Klipper logs (`klippy.log` and the 2026-11-14 rotation).
* **Reported:** what the maintainer saw at the printer and told us. Not
  checked by a second person.

### Firmware, connection and calibration

| Check | Evidence | Result |
|---|---|---|
| Standard firmware flashed (SD card, as in [printer setup](printer-setup.md)) | Observed: MCU `v0.13.0-827-g29d4ec2d`, the release build, matching the host | **Pass** |
| Display variant flashed later | Observed: MCU `v0.13.0-828-ge4befa2e` (146 MCU commands instead of 143), Klipper *ready* | **Pass** |
| USB serial connection through `uart: true` and the by-id path | Observed: Klipper *ready* on every start in the logs | **Pass** |
| Reconnect after the printer was switched off | Observed: "Lost communication with MCU" at the time the printer was switched off to flash the variant (reported), then a normal start with the new firmware | **Pass** (USB unplug and replug while on: not tested) |
| Stepper drivers over UART as TMC2208 | Observed: the three `tmc2208` sections load and Klipper reaches *ready*; it stops at start-up if a driver does not answer | **Pass** on this board (revision not recorded) |
| Z-offset, PID, bed mesh | Observed in the `SAVE_CONFIG` block: `z_offset` 1.820, PID for extruder and bed, a 5 × 5 mesh with a range of 0.63 mm | **Done** (calibrated by the maintainer) |
| `MARK_HARDWARE_VALIDATED CONFIRM=YES` | Observed: `khaos_hw_validated` is `true` | Set by the maintainer. The individual checklist steps were not recorded for this report |

**Profile problem found:** `SAVE_CONFIG` cannot store the Z-offset or PID
values while the profile sets them. Klipper refuses to save an option that
an included file defines (`_disallow_include_conflicts` in
`klippy/configfile.py`). The maintainer commented out `control`, `pid_Kp`,
`pid_Ki`, `pid_Kd` and `z_offset` in their copy of the profile's
`printer.cfg`. That works for them only because the saved block already
holds those values; on a fresh install Klipper would not start without
them. The shipped profile is unchanged so far.

### Prints

Source: the Moonraker job history (observed). The file metadata shows
OrcaSlicer 2.5.0 for every job; the maintainer sent the jobs from
OrcaSlicer through the direct port (reported).

| Job | Print time (Moonraker) | Slicer estimate | Filament | Result |
|---|---|---|---|---|
| Calibration cube | 2 min | 2 min | 0.1 m | **Completed** |
| Large part, `…tool bases…` | **18 h 0 min** (18 h 4 min including heating) | 16 h 20 min | 114 m | **Completed**; reported flawless |
| Pressure advance pattern (2 runs) | 10 and 8 min | 9 and 7 min | 0.6 and 0.5 m | **Completed** |

From the Klipper logs (observed) for these prints:

* No MCU shutdown, `Timer too close` or lost communication while printing.
* `bytes_invalid=0` throughout, and at most 9 retransmitted bytes over
  about 195 MB sent.
* `print_stall=0` for the 18-hour print. One stall (`print_stall=1`)
  during the second pressure advance pattern, right after Klipper dropped
  a G-code response line it could not write (`BlockingIOError` on its
  pseudo-terminal). The print completed.
* The original display was active from the 18-hour print on. Klipper
  reported its update loop holding the main loop for up to 0.125 s (733
  "Reactor busy" reports in the current log), with no print stall during
  the 18-hour print.

### Resource use on the target host

Supervisor statistics, three samples 10 s apart, with a print running and
the display active (0.1.3): **66.8 to 67.1 MiB RAM**, **2.3 to 2.8 % CPU**.
At idle on the same host without a printer: 55.5 MiB and 0.2 % (0.1.1, see
below).

### Original display

| Step | Evidence | Result |
|---|---|---|
| D1 display firmware variant | Observed (see above) | **Pass** |
| D2 screen starts | Reported: the screen is functional | **Pass** (reported) |
| Remaining time during a print | Reported: it differs from Mainsail's | Expected with the upstream module; see [display.md](display.md#remaining-time-on-the-screen) |
| Macros menu | Reported: it showed "No macros" | No menu entries were configured. 0.1.3 adds three; Klipper loads them (observed). Not yet confirmed on the screen |
| D3 to D7 (knob, live values, control, print from the screen, reconnect) | Not reported individually | **Not recorded** |

### OrcaSlicer and the direct port

| Check | Evidence | Result |
|---|---|---|
| Port 7125 mapped; upload and print from OrcaSlicer | Observed (job history) and reported | **Pass** |
| Host name `homeassistant.local` from the Windows PC | Observed: it resolves to an IPv6 link-local address first, which OrcaSlicer cannot connect to | **Fail**: use the IP address |
| Real client address on the published port | Observed: Moonraker sees the PC's LAN address (192.168.68.65), not a Docker address | **Pass**, so `trusted_networks` works on HAOS |
| `trusted_networks: ["192.168.68.65/32"]` | Observed from that PC: HTTP API (200), Mainsail (200) and the WebSocket (`printer.info`: ready) without a key | **Pass** |
| OrcaSlicer's *Device* tab (embedded Mainsail) | Observed in the Moonraker log: with only the API key its WebSocket is not authorised; with `trusted_networks` it connects (reported) | Needs `trusted_networks` |

### Not tested in this run

The filament macros added in 0.1.3 (`LOAD_FILAMENT`, `UNLOAD_FILAMENT`,
`PURGE`, `M600`) are loaded but have not been run on the printer. Also not
tested: USB unplug and replug while the printer is on, recovery to the
stock Creality firmware, input shaper, and the individual steps of the
hardware validation checklist (see above).

## Original display support (unreleased) — 2026-11-14

Environment: Windows 11 development PC, Docker Desktop (Engine 29.9.3,
amd64). **No printer and no display connected.** Command:
`tools/verify-all.sh`, plus the release workflow's firmware step run as an
unprivileged user (uid 1001) in an Ubuntu container, as on a CI runner.

| Check | Result |
|---|---|
| All test layers (`tools/verify-all.sh`) | **Pass**: image build, static validation, 49 unit tests, both firmware builds, both profile checks, integration tests 43/43 |
| Display files fetched from the pinned fork commit, SHA-256 verified | **Pass**: 4 host modules in the image, 5 firmware sources in the variant; no upstream file replaced |
| `ender3-v3-se-display` firmware build | **Pass**: version `v0.13.0-828-ge4befa2e`; dictionary contains `serial_bridge_send`, `serial_bridge_response` and `SERIAL_BRIDGE_CONFIG_USART2_PA3,PA2=3`. Reproducible: two builds gave the same SHA-256 `0df7b38e9a7c604a2069ed967b4d8a862c0ff517ac02be1de5e9aa323682eafb` |
| Standard firmware unchanged | **Pass**: SHA-256 still `7cf49e4cdca3a6a7d49dd1e7a6e6377922dee88476e6b7f8c63ad07c8aecfe69` |
| Profile + `display.cfg` with the display firmware dictionary (Klipper batch mode) | **Pass**: config loads, motion/heater G-code runs, `START_PRINT` gate blocks and then allows |
| Commands Klipper sends to the simulated MCU (decoded with `klippy/parsedump.py`) | **Pass**: serial bridge configured with `config=3 baud=115200`; knob buttons on PA12, PA11, PB1 with pull-ups |
| Profile + `display.cfg` with the standard firmware | **Pass** (expected failure): Klipper stops with `Unknown command: serial_bridge_send` |
| Default install: `display.cfg` installed but not included; modules present | **Pass** (integration test) |

Not covered: anything with the real display or printer. The simulated MCU
never answers, so no drawing commands were exercised. Whether the screen
shows the menu, the knob works and the display firmware version matches is
unknown until the hardware checklist's display steps are done.

## v0.1.1 release — 2026-11-11

The v0.1.1 tag ran the release workflow on GitHub Actions. Before tagging,
the workflow's firmware step was run locally as an unprivileged user in an
Ubuntu container, the same setup as the CI runner.

| Check | Result |
|---|---|
| Release workflow: metadata check, full test suite, amd64 image build and push, multi-arch manifest | **Pass** |
| Release workflow: GitHub release with firmware | **Pass**. Pre-release created, notes taken from the changelog |
| Firmware assets downloaded from the release | **Pass**: `klipper.bin`, `klipper.dict` and `klipper.config.full` match the published `SHA256SUMS`; the `klipper.bin` SHA-256 `7cf49e4cdca3a6a7d49dd1e7a6e6377922dee88476e6b7f8c63ad07c8aecfe69` is identical to the local builds |
| `ghcr.io/wendelnascimento/klipper-haos:0.1.1` pulled anonymously | **Pass**. Image label `io.hass.version` is `0.1.1` |

Not covered by the release run: anything that needs the printer.

## Update from v0.1.0 to v0.1.1 on real Home Assistant OS — 2026-11-11

Environment: the same host as the v0.1.0 run below (HAOS 18.2, Supervisor
2026.10.5, Core 2026.7.4), **no printer connected**, `serial_device` empty.
The update was started through the Supervisor API with "back up before
updating" turned on, the same call the UI makes. Before the update, a small
marker G-code file was uploaded through ingress. It was deleted afterwards.

| Check | Result |
|---|---|
| Store reload offers 0.1.1 | **Pass**. The "Invalid app config" warning for `klipper/mainsail/config.json` no longer appears |
| Update with backup first | **Pass** in 19 s: partial backup, image pull (8 s), stop (4 s), start of 0.1.1. The Supervisor removed the 0.1.0 image afterwards |
| Pre-update backup contents (backup downloaded and listed) | **Pass**: 0.3 MB. Contains the pre-backup database snapshot written by the hook (`backup/database/klipper-haos-pre-backup.db`), the live database, the marker file and the full app config folder. Logs are excluded |
| Data kept across the update | **Pass**: the 12 config files (sizes and modification times) and the marker file are unchanged, and the same 5 Moonraker database namespaces exist |
| Options and security settings after the update | **Pass**: unchanged (not privileged, no full access, no host network, AppArmor default, protection mode on, direct port unmapped, auto update off) |
| App start after the update | **Pass**: the log reports `app=0.1.1`; Klipper reports the missing serial device as expected |
| Real ingress, 11 checks (same as the v0.1.0 run) | **Pass**: 11/11, including WebSocket (101) and the 24 MiB upload in 2 s |
| Idle resource use | **55.5 MiB** RAM, about **0.2 %** CPU (one sample) |

The pre-backup hook's own log line is not in the app log: the Supervisor
runs the hook with `docker exec`, so its output does not reach the
container log. The snapshot file in the backup shows that it ran.

Not covered: restoring from the backup, rolling back to 0.1.0, the
watchdog, and anything that needs the printer.

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
| Release workflow: GitHub release with firmware | **Fail** in v0.1.0 (relative output path passed to `docker run -v`). Fixed after the release; v0.1.0 has no GitHub release or firmware assets. Passes in v0.1.1 |
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

## Not tested yet

| Requirement | Why not yet | Milestone |
|---|---|---|
| Mainsail panel in a browser inside the Home Assistant frontend (including remote access) | Real ingress was tested by script only (see the 2026-11-11 run) | v0.3.0 |
| USB unplug and replug while the printer is on | Not done yet (connection and reconnect after power-off: see the real printer run) | v0.2.0 |
| Restore from a Home Assistant backup, rollback to an older app version | Not run yet (update and backup creation were tested, see the update run) | v0.3.0 |
| Supervisor watchdog restarting an unhealthy app | Needs HAOS | v0.3.0 |
| Resource usage over a whole long print | One printing sample so far (67 MiB, under 3 % CPU) | v0.2.0 |
| Every step of the [hardware validation checklist](hardware-validation.md), recorded | `MARK_HARDWARE_VALIDATED` was run on one printer, but the step results were not recorded | v0.2.0 |
| Recovery to the stock Creality firmware | Flashing Klipper worked (both variants); going back to stock has not been tested | v0.2.0 |
| Filament macros (`LOAD_FILAMENT`, `UNLOAD_FILAMENT`, `PURGE`, `M600`) on the printer | Added in 0.1.3, batch-mode tests only | v0.2.0 |
| `SAVE_CONFIG` with the shipped profile | Klipper refuses to save Z-offset and PID while the profile sets them (see the real printer run) | v0.2.0 |
