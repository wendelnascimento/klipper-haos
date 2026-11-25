# Changelog

All notable changes to this app are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- With the `spoolman` option on, the Ender 3 V3 SE filament macros work
  with Spoolman: `UNLOAD_FILAMENT` (and so `M600`) clears the active spool
  once the filament is out, and `LOAD_FILAMENT` opens Mainsail's spool
  picker before it heats, so the new spool is counted from the first
  millimetre. `EJECT_SPOOL=0` / `SELECT_SPOOL=0` skip that. This includes
  loading from the printer's own display. The picker opens through a
  second Mainsail patch (a macro sends `action:khaos_spoolman_select`).
  The app also defines `SET_ACTIVE_SPOOL ID=` and `CLEAR_ACTIVE_SPOOL` for
  slicer start G-code. Existing profile copies need the new `filament.cfg`
  (see `docs/printer-setup.md`). Not yet tested on the printer.

### Documentation

- How to send print notifications (started, paused, resumed, finished,
  failed, cancelled) to the Home Assistant mobile app with Moonraker's
  notifier and a webhook automation, without extra app permissions or
  tokens (`docs/installation.md`). Tested on real Home Assistant OS.

## [0.2.0] - 2026-11-17

### Added

- Optional bundled [Spoolman](https://github.com/Donkie/Spoolman) v0.27.1
  for filament inventory (new option `spoolman`, off by default). Moonraker
  is connected to it automatically, so Mainsail's Spoolman panel works and
  each print's filament use is subtracted from the active spool. Spoolman's
  web UI is served through Home Assistant ingress only (it has no login);
  the direct port does not serve it. Its database lives in
  `/data/spoolman` and is included in backups, with a consistent snapshot
  taken before each backup. Mainsail's "Open Spoolman" button is patched
  to open this bundled instance. Not yet tested on Home Assistant OS.

### Fixed

- `SAVE_CONFIG` can now store the Ender 3 V3 SE's PID and Z-offset
  calibration. The profile set those values itself, and Klipper refuses to
  save options set in an included file ("conflicts with included value").
  The starting values now go into the user's own `printer.cfg` (shown in
  the profile header and `docs/printer-setup.md`). The profile also no
  longer sets `shaper_freq_x/y` (they default to 0). Existing copies of the
  profile are not changed; `docs/printer-setup.md` explains the fix.

## [0.1.3] - 2026-11-15

### Added

- Ender 3 V3 SE profile: `LOAD_FILAMENT`, `UNLOAD_FILAMENT`, `PURGE` and
  `M600` (filament change during a print) in the new
  `profiles/ender3-v3-se/filament.cfg`. Not yet tested on hardware.
  Existing installs get the file but must add `[include filament.cfg]` to
  their copy of the profile's `printer.cfg` (see `docs/printer-setup.md`).
- `display.cfg` now fills the screen's macros menu with load, unload and
  purge entries; before, the menu showed "No macros".

### Documentation

- Why the screen's remaining time differs from Mainsail's.

## [0.1.2] - 2026-11-14

### Added

- Experimental, optional support for the Ender 3 V3 SE's original display
  and knob, based on the ender3-v3-se-klipper-with-display project by
  jpcurti. The app bundles its display modules (inactive unless
  `profiles/ender3-v3-se/display.cfg` is included), and each release adds
  an `ender3-v3-se-display` firmware variant: the normal firmware plus a
  serial bridge to the screen. Klipper itself stays at the same upstream
  commit. Not yet tested on hardware. See `docs/display.md`.

### Changed

- Firmware builds now fail if Klipper's configuration step drops a
  requested option. The standard `ender3-v3-se` firmware is byte-for-byte
  the same as in 0.1.1.

## [0.1.1] - 2026-11-11

Installed and run on a real Home Assistant OS host for the first time (no
printer connected). Still not validated with printer hardware.

### Fixed

- The Supervisor no longer logs an "Invalid app config" warning when it
  scans the repository (the Mainsail settings file was named `config.json`).
- The release workflow now builds the firmware assets (the firmware build
  script failed on a relative output directory). v0.1.0 has no GitHub
  release; this is the first one with firmware assets.

### Changed

- The documentation and test report now include the results of the first
  run on real Home Assistant OS, including ingress through the real
  Supervisor.

## [0.1.0] - 2026-11-11

First experimental release. Not yet validated on real Home Assistant OS or
printer hardware.

### Added

- Klipper (`v0.13.0-827-g29d4ec2d`), Moonraker `v0.11.0`, Mainsail `v2.19.0`
  and mainsail-config `v1.2.1` in a single app, supervised by s6-overlay
  with ordered start-up, crash-loop protection and graceful shutdown.
- Mainsail through Home Assistant Ingress, with request streaming for large
  uploads.
- Optional direct port 7125 (disabled by default), protected by the
  Moonraker API key. There is optional API key export and a validated
  `trusted_networks` option.
- Persistent configuration in the app config folder. G-code files and the
  database are stored in `/data`. Hot backups use a pre-backup database
  snapshot.
- An inert starter `printer.cfg`: no motion and no heaters until a profile
  is loaded.
- Experimental Creality Ender 3 V3 SE profile with a `START_PRINT` safety
  gate and a hardware validation checklist.
- Reproducible Klipper MCU firmware build for the Ender 3 V3 SE (never
  flashed automatically).

### Security

- Moonraker listens on localhost only. nginx always overwrites client
  address headers.
- Tornado upgraded to 6.5.9 and Pillow to 13.0.0, beyond Moonraker's
  version caps, to fix known HIGH/CRITICAL vulnerabilities.
