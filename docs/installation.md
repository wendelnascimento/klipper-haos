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
   `https://github.com/wendelnascimento/klipper-haos` → **Add**.
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
3. OrcaSlicer: *Printer settings → Physical printer*, host type
   *Octo/Klipper*, host `http://<home-assistant-ip>:7125`, and the API key.
   Use the IP address, not `homeassistant.local`: on Windows the name can
   resolve to an IPv6 link-local address first, and the connection fails.
4. In the printer's *Machine G-code*, set the start G-code to
   `START_PRINT BED_TEMP=[bed_temperature_initial_layer_single] EXTRUDER_TEMP=[nozzle_temperature_initial_layer]`
   and the end G-code to `END_PRINT`. Otherwise OrcaSlicer's own start code
   heats and homes as well.

The API key is enough to upload and start prints. OrcaSlicer's *Device*
tab shows Mainsail, and on real HAOS its WebSocket was not authorised with
the key alone. For that tab,
add your PC's address to `trusted_networks`, for example
`192.168.1.50/32`. Clients from that address need no key. Only do this on a
network you trust; give the PC a fixed address in your router.

Verified on real HAOS: the app sees the real LAN address of clients on the
published port, so `trusted_networks` works there.

## Home Assistant integration

Moonraker-based Home Assistant integrations (for example the community
"Moonraker" integration) can connect to `http://<home-assistant-ip>:7125`
with the API key once the direct port is enabled.

### Print notifications on your phone

Moonraker's notifier can tell Home Assistant when a print starts, pauses,
resumes, finishes, fails or is cancelled. Home Assistant then sends a push
notification through its mobile app. This needs no extra app permission,
no Home Assistant token and no open port: the app reaches Home Assistant
at `http://homeassistant:8123` on the internal app network.

1. **Create the automation** in Home Assistant (*Settings → Automations →
   Create → Edit in YAML*). Replace `<your-webhook-id>` with a long random
   string, and `notify.mobile_app_your_phone` with your phone's notify
   action (*Developer tools → Actions*, search for `mobile_app`).

   ```yaml
   alias: "3D printer: Klipper notifications"
   mode: queued
   triggers:
     - trigger: webhook
       webhook_id: <your-webhook-id>
       allowed_methods: [POST]
       local_only: true
   actions:
     - action: notify.mobile_app_your_phone
       data:
         title: "{{ trigger.json.title | default('3D printer', true) }}"
         message: "{{ trigger.json.message | default('Printer event', true) }}"
         data:
           group: 3d-printer
           push:
             # iPhone: failed and cancelled prints break through Focus modes.
             interruption-level: >-
               {{ 'time-sensitive' if (trigger.json.title | default(''))
                  is search('failed|cancelled', ignorecase=True) else 'active' }}
   ```

2. **Add the notifier** at the end of `moonraker.conf` (Mainsail →
   *Machine*), with the same webhook id:

   ```ini
   [notifier phone]
   url: json://homeassistant:8123/api/webhook/<your-webhook-id>
   events: started, paused, resumed, complete, error, cancelled
   title:
       {% if event_name == "complete" %}Print finished
       {% elif event_name == "error" %}Print failed
       {% elif event_name == "cancelled" %}Print cancelled
       {% elif event_name == "paused" %}Print paused
       {% elif event_name == "resumed" %}Print resumed
       {% else %}Print started{% endif %}
   body:
       {% set stats = event_args[1] %}
       {stats.filename.split("/")|last}
       {% if event_name in ["complete", "error", "cancelled"] %}Print time: {(stats.print_duration / 3600)|int} h {((stats.print_duration % 3600) / 60)|int} min.{% endif %}
       {% if event_name == "error" and stats.message %}{stats.message}{% endif %}
   ```

3. **Restart the app** while the printer is idle (*Settings → Apps →
   Klipper → Restart*). Moonraker reads `moonraker.conf` only at start.

The webhook id is the only secret. With `local_only: true`, only devices
on your local network can call it, but any of them that knows the id can
send you a notification. Do not use a short or guessable id.

Not covered: if the app or the whole Home Assistant host stops, nothing is
left to send a message. Home Assistant can alert on that separately, for
example when the app's *Running* entity turns off.

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
