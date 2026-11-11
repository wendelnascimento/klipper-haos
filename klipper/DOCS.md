# Klipper

This app runs three programs:

* **Klipper**, the printer host software. It plans motion and talks to the
  printer's controller board over USB.
* **Moonraker**, the API server used by Mainsail, slicers and other clients.
* **Mainsail**, the web interface, shown in the Home Assistant sidebar.

> **Experimental.** This app has passed automated container tests and runs
> on a real Home Assistant OS host, but it has not yet been validated with a
> real printer. Follow the hardware validation checklist before printing.

## First start

1. Start the app with the default options.
2. Open **Mainsail** from the sidebar. Klipper shows
   *"Option 'serial' in section 'mcu' must be specified"*. This is expected:
   no printer is configured yet.
3. The app created a starter `printer.cfg` that is **inert**: it defines no
   motors, heaters or fans, so nothing can move or heat up.

Then:

1. Flash Klipper firmware to the printer's controller board. **This app
   never flashes firmware.** See the project's printer setup guide.
2. Connect the printer by USB. Under **Configuration**, pick the printer's
   `serial_device`. Prefer the `/dev/serial/by-id/...` entry.
3. Restart the app. Mainsail should show Klipper as *ready*.
4. Load a printer profile (see *Printer profiles* below) and complete the
   hardware validation checklist before your first print.

## Options

### `serial_device`

The printer's serial port. The `/dev/serial/by-id/...` names stay the same
across reboots and re-plugging; `/dev/ttyUSB0` style names can change. The
app writes this value into `klipper-haos/generated.cfg`. Leave it empty
until the printer runs Klipper firmware.

### `log_level`

`debug`, `info`, `warning` or `error`. Controls the app's own messages.
`debug` also enables verbose Moonraker logging.

### `trusted_networks`

Addresses that may use the **direct port** without an API key, in CIDR
form, for example `192.168.1.50/32` for a single PC. Leave it empty to
require an API key from every client (recommended).

For safety the app refuses to start if an entry:

* is broader than /16 (IPv4) or /48 (IPv6), or
* overlaps the Home Assistant internal network `172.30.32.0/23`.

Allowing the internal network would trust Home Assistant Core and every
other app on the host.

### `cors_domains`

Extra browser origins, such as `http://my-other-mainsail.local`, that may
call Moonraker from JavaScript. The built-in Mainsail does not need this.

### `export_api_key`

When enabled, the app writes the Moonraker API key to `moonraker.apikey` in
the app config folder (file mode 600) at start-up. Copy the key into your
slicer, then **turn the option off again**: the file is deleted on the next
start. The key is never written to the log.

## Accessing Mainsail and the API

| Path | Who can use it | Authentication |
|---|---|---|
| Sidebar (Ingress) | Home Assistant administrators | Your Home Assistant login |
| Direct port `7125/tcp` (disabled by default) | Slicers, other Moonraker clients, other Mainsail instances | Moonraker API key, or `trusted_networks` |

To enable the direct port, open the app's **Network** section, enter a host
port for `7125/tcp` (for example `7125`) and restart the app. In OrcaSlicer
choose the *Klipper (via Moonraker)* host type, enter
`http://<home-assistant-ip>:7125` and, if your slicer asks for it, the API
key.

## Files and folders

The **app config folder** is mounted at `/config` inside the app. On the
host it is `/addon_configs/<id>_klipper`, which you can reach with the
Samba or File editor apps. You can also edit these files in Mainsail under
*Machine*.

| File | Owner | Notes |
|---|---|---|
| `printer.cfg` | **you** | Created once, never overwritten. Must start with `[include klipper-haos/generated.cfg]`. |
| `moonraker.conf` | **you** | Created once, never overwritten. Must start with `[include klipper-haos/moonraker-generated.conf]`. |
| `profiles/<printer>/` | **you** | Printer profiles, copied once. App updates never change your copy. |
| `klipper-haos/*` | app | Regenerated at every start. Do not edit. |
| `klipper-haos/dist/profiles/` | app | Pristine profile copies from the current app version, for comparison. |
| `klipper-haos-variables.cfg` | Klipper | `SAVE_VARIABLE` storage (validation flag). |

G-code files, the Moonraker database, history and logs are stored in the
app's private `/data/printer_data` folder.

## Printer profiles

### Creality Ender 3 V3 SE (experimental)

Replace the contents of `printer.cfg` with:

```ini
[include klipper-haos/generated.cfg]
[include profiles/ender3-v3-se/printer.cfg]

# Your own overrides go here. SAVE_CONFIG appends calibration results below.
```

Then complete the hardware validation checklist from the project
documentation. `START_PRINT` refuses to run until you confirm the checklist
with `MARK_HARDWARE_VALIDATED CONFIRM=YES`.

## Backups

The app supports hot backups: Home Assistant backups do not stop a running
print. Before each backup the app asks Moonraker for a consistent snapshot
of its database. Logs are excluded from backups.

## Important safety notes

* **Restarting or updating this app, or rebooting Home Assistant, ends a
  running print.** Klipper's MCU safety timeouts turn the heaters off.
  Printing cannot be resumed afterwards.
* Disable *Auto update* for this app, and don't update Home Assistant OS
  while printing.
* Klipper's thermal runaway protection (`verify_heater`) is active for every
  heater. Do not weaken it.
* Never leave a printer unattended until you have validated it.

## Troubleshooting

* **"mcu 'mcu': Unable to connect"**: the printer is off, the USB cable is
  unplugged, the wrong `serial_device` is selected, or the board is not
  running Klipper firmware.
* **Klipper shows an error after editing `printer.cfg`**: fix the file in
  Mainsail and press *Restart*. The app itself keeps running.
* **Klipper does not come back after crashes**: after 5 crashes within 5
  minutes the app stops restarting Klipper to avoid a restart loop. Check
  `klippy.log`, fix the cause, and restart the app.
* **The app does not start**: check the app log. Invalid options, such as an
  unsafe `trusted_networks` entry, stop the app with a clear message.

More help: see the troubleshooting guide in the project repository.
