# Troubleshooting

Start with the app **Log** tab in Home Assistant. It shows the app's start-up
diagnostics (component versions, serial devices visible to the app, host
memory) and Moonraker's log. Klipper's own log is `klippy.log`. Download it
in Mainsail (*Machine* → log files) or find it in
`/data/printer_data/logs/`.

## The app does not start

| Log message | Cause / fix |
|---|---|
| `Invalid app configuration: trusted_networks entry ... is too broad` | Use a narrower CIDR, at least /16 for IPv4 or /48 for IPv6. A single PC is `/32`. |
| `... overlaps the Home Assistant internal network` | Remove `172.30.x.x` entries. The app never trusts Home Assistant's internal network. |
| `cors_domains entry ... is too permissive` | Wildcards are not allowed in the top-level domain, and `*` alone is not allowed. |
| `moonraker failed 5 times in 300s; giving up` | Moonraker cannot start. Check `moonraker.log` and your `moonraker.conf` changes. Remove your overrides and restart. |

## Klipper errors (shown in Mainsail)

| Message | Cause / fix |
|---|---|
| `Option 'serial' in section 'mcu' must be specified` | No `serial_device` selected. Pick it in the app Configuration and restart. |
| `mcu 'mcu': Unable to connect` | The printer is off, the cable is unplugged or charge-only, the wrong device is selected, or the board is not running Klipper firmware. See [printer-setup.md §6](printer-setup.md#6-confirm-mcu-communication). |
| `MCU Protocol error` / version mismatch | The MCU firmware was built from a different Klipper version. Reflash the firmware from the matching app release. |
| `Unable to read tmc uart 'stepper_x' register IFCNT` | Your driver chips don't answer as TMC2208. See [printer-setup.md → Stepper drivers](printer-setup.md#stepper-drivers). |
| `START_PRINT blocked: hardware validation not completed` | Intentional. Complete the [checklist](hardware-validation.md), then run `MARK_HARDWARE_VALIDATED CONFIRM=YES`. |
| `Timer too close` / `Lost communication with MCU` during prints | The host was too busy or the USB link dropped. Check host load (backups, other apps), use a different USB port or cable, and avoid USB hubs. |
| `Heater extruder not heating at expected rate` | Thermal protection triggered. **Do not loosen `verify_heater`.** Check the heater cartridge, thermistor and wiring, then run PID calibration. |
| Klipper missing in Mainsail after several crashes | Crash-loop protection stopped it after 5 crashes in 5 minutes. Fix the cause shown in `klippy.log` and restart the app. |

## The serial device is not listed

* Unplug and replug the printer, wait a few seconds, then reopen the app
  configuration.
* **Settings → System → Hardware → All hardware**: look for
  `ttyUSB*`/`ttyACM*` and a `/dev/serial/by-id/usb-1a86_...` entry (CH340).
* Use a USB **data** cable. Some cables only carry power.

## Mainsail through the sidebar

* **Blank page or "Cannot connect to Moonraker"**: reload the page. Then
  check the app log for errors. If it persists, enable the direct port and
  compare. Please report the issue with your browser, Home Assistant version
  and how you access Home Assistant (local, Nabu Casa, reverse proxy).
* **Large uploads fail**: try the direct port. Ingress upload behaviour
  with very large files has only been tested with a simulated Supervisor
  (24 MiB).

## Slicer cannot connect

* Is the direct port enabled in the app's **Network** section, and did you
  restart the app?
* Are you using the API key, or is your PC listed in `trusted_networks`?
* Test from a terminal:
  `curl -H "X-Api-Key: <key>" http://<ha-ip>:7125/server/info`.

## Collecting information for a bug report

* App log (Home Assistant → Klipper → Log), including the version lines at
  the top.
* `klippy.log` and `moonraker.log`.
* Your `printer.cfg` (remove nothing; it contains no secrets unless you
  added some).
* Host hardware, Home Assistant OS and Supervisor versions.

**Never post `moonraker.apikey` or other secrets in issues.**
