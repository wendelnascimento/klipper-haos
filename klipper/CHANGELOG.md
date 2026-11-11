# Changelog

All notable changes to this app are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- The Supervisor no longer logs an "Invalid app config" warning when it
  scans the repository (the Mainsail settings file was named `config.json`).
- The release workflow now builds the firmware assets (the firmware build
  script failed on a relative output directory).

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
