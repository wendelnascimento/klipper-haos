# Installation

## Requirements

* Home Assistant OS on an **amd64** machine, with a current Supervisor.
  The app uses the 2026 "apps" manifest keys.
* At least ~500 MB of free RAM is recommended. The app idles at about
  55 MiB in tests, but Home Assistant and other apps need headroom.
* About 400 MB of disk for the image, plus your G-code files.
* A USB data cable to the printer.

## Add the repository and install

1. **Settings → Apps → App store** (older versions: *Add-ons → Add-on
   store*).
2. Menu (⋮) → **Repositories** → add
   `https://github.com/OWNER/klipper-haos` → **Add**.
3. Find **Klipper** in the store and click **Install**. The image is
   downloaded from GHCR. Nothing is compiled on your machine.
4. Optionally enable **Show in sidebar**. Keep **Auto update** **off**
   (see "Updates" below).
5. Click **Start**, then open the app's **Log** tab. A healthy first start
   prints the component versions, *"Created starter printer.cfg (inert: no
   motion, no heaters)"*, and *"No printer serial device selected yet"*.
6. Open **Mainsail** from the sidebar or with **Open web UI**.

Then follow [printer-setup.md](printer-setup.md).

## Connecting a slicer

Slicers connect to Moonraker directly, not through Home Assistant.

1. App → **Configuration** → **Network**: set a host port for `7125/tcp`,
   for example `7125`. Save and restart the app.
2. Get an API key: enable `export_api_key`, restart the app, and open
   `moonraker.apikey` in the app config folder (Samba / File editor apps, or
   Mainsail → *Machine*). Then **disable `export_api_key` again** and
   restart; the file is removed.
3. OrcaSlicer: *Printer settings → Physical printer → Host type: Klipper
   (via Moonraker)*, host `http://<home-assistant-ip>:7125`, and the API key
   if the dialog has a field for it.

Alternatively, add your PC's address to `trusted_networks`, for example
`192.168.1.50/32`. Clients from that address need no key. Only do this on a
network you trust.

> Unverified on real HAOS: whether the client address seen by the app
> through the published port is the real LAN address. If it is not, the
> `trusted_networks` option has no effect (it fails closed, so clients still
> need the key). Please report your findings.

## Home Assistant integration

Moonraker-based Home Assistant integrations (for example the community
"Moonraker" integration) can connect to `http://<home-assistant-ip>:7125`
with the API key once the direct port is enabled.

## Updates

* App updates replace the container. **A running print stops** when the app
  restarts. Keep *Auto update* disabled and update between prints.
* Your `printer.cfg`, `moonraker.conf` and profile copies are never
  overwritten by updates. New profile versions appear in
  `klipper-haos/dist/profiles/` for comparison.
* After an update that changes the Klipper version, the MCU firmware should
  be rebuilt and reflashed. Klipper warns about version mismatches; the
  release notes say when an update is required.

### Rollback

1. Before updating, Home Assistant offers to back up the app. Leave this
   enabled.
2. To roll back, restore that app backup (**Settings → System → Backups**,
   select the backup, restore only the *Klipper* app). This restores the
   previous version together with its data.

## Uninstall

**Settings → Apps → Klipper → Uninstall.** The container and `/data`
(G-code files, history, database) are removed. The app config folder
(`/addon_configs/<id>_klipper`) remains until you delete it. Printer
firmware is not changed.
