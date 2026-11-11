# Roadmap and milestones

These are planned milestones, not claims of completed functionality. Items
are checked only when they are done **and** verified as described.

## v0.1.0 — Experimental

- [x] Container builds reproducibly (amd64), pinned upstream versions
- [x] Klipper, Moonraker and Mainsail operate together (container tests)
- [x] Basic Supervisor integration: manifest, options, ingress, ports, backups
- [x] Mainsail through a simulated ingress proxy (UI, API, WebSocket, upload)
- [x] Static, unit, profile (batch mode) and integration tests in CI
- [ ] First install from the app store on a real HAOS test machine

## v0.2.0 — Hardware validation

- [ ] Printer USB connectivity on real HAOS (`uart` mapping, by-id path, re-plug)
- [ ] Ender 3 V3 SE: complete the [hardware validation checklist](hardware-validation.md)
- [ ] Determine driver chip variants (TMC2208 / MS35774) and adjust the profile
- [ ] Measured CPU and RAM usage on the target Celeron, idle and printing
- [ ] Verified firmware flashing and recovery procedure

## v0.3.0 — Integration and reliability

- [ ] Ingress through the real Home Assistant frontend (local and remote access)
- [x] Large uploads through real ingress
- [ ] Home Assistant backup → restore cycle verified (backup contents checked)
- [ ] App update and rollback verified; data persists (update 0.1.0 → 0.1.1
  verified with data kept; rollback pending)
- [ ] Client IP preservation on the published port (for `trusted_networks`)
- [ ] Custom AppArmor profile (complain-mode audit on real HAOS)
- [ ] Optional non-root service user

## v1.0.0 — Stable

- [ ] Verified installation experience by several users
- [ ] Documented hardware compatibility list
- [ ] Security review and stability (long prints, host load)
- [ ] Reliable update and rollback procedures

## Later / ideas

* aarch64 builds (Raspberry Pi, Home Assistant Green/Yellow)
* More printer profiles (community contributions)
* Ender 3 V3 SE pressure sensor (strain gauge) Z-offset, if upstream Klipper
  support becomes available
* Original display support (community projects)
* Optional numpy for accelerometer-based input shaper calibration
* Webcam support (resource impact must be measured first)
