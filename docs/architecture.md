# Architecture

## Goals and constraints

* Run on an unmodified Home Assistant OS host, managed only by the
  Supervisor. No VM, no unmanaged containers, no host changes.
* Keep Home Assistant safe and healthy when the app fails.
* Fit low-power hardware (initial target: Celeron, 4 GB RAM, about 1.7 GB in
  use).
* Secure defaults. Reproducible, pinned builds.

## One container, three services

```
┌──────────────────────────── app container (s6-overlay, PID 1) ────────────────────────────┐
│                                                                                            │
│  init-khaos (oneshot)  validate options → seed/regenerate configs → diagnostics            │
│        │                                                                                   │
│        ├──► klipper   (longrun)  klippy.py /config/printer.cfg                             │
│        │        API: /run/klipper-haos/klippy.sock     MCU: /dev/serial/by-id/...          │
│        │                                                                                   │
│        ├──► moonraker (longrun)  127.0.0.1:7126 + /data/printer_data/comms/moonraker.sock  │
│        │        depends on klipper (start order only; Moonraker reconnects on its own)     │
│        │                                                                                   │
│        ├──► nginx     (longrun)  :8099 ingress (172.30.32.2 only) · :7125 direct port     │
│        │        serves /opt/mainsail, proxies API + WebSocket to Moonraker                 │
│        │                                                                                   │
│        └──► khaos-apikey (run-once longrun) optional API key export                       │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

* **Why s6-overlay:** it is the process supervisor in the official Home
  Assistant base images. It gives ordered start-up (s6-rc dependencies),
  restarts, logging to the app log, and clean shutdown on `SIGTERM`. Docker
  Compose and similar tools are not available inside an app.
* **Why one app instead of three:** Klipper and Moonraker communicate over a
  Unix socket and share the configuration directory, and Mainsail is only
  static files. Separate apps would need shared volumes that the Supervisor
  does not offer, and would use more memory.
* **Why nginx:** it is the single network entry point. It serves Mainsail,
  proxies Moonraker, enforces the ingress source address, always overwrites
  client address headers, and streams uploads without temporary files.

## Supervision and failure handling

| Event | Behaviour |
|---|---|
| Invalid printer.cfg / missing MCU | Klipper keeps running in an error state and reports it through the API. No restart loop. |
| Klipper process crashes | Restarted with back-off (0, 2, 4, 8, 16 s). After 5 crashes within 5 minutes it stays down (`exit 125`); Moonraker and Mainsail stay available to fix the config. |
| Moonraker or nginx crash repeatedly | Back-off restarts. After 5 crashes the app stops cleanly, and Home Assistant shows it as stopped with the log. |
| Invalid / unsafe app options | `init-khaos` fails, the app does not start, and the log names the bad option. |
| nginx or Moonraker stop answering | The Docker `HEALTHCHECK` (`/access/info`) marks the app unhealthy; with the app's *Watchdog* toggle on, the Supervisor restarts it. Klipper's state is not part of the health check, so a printer.cfg error or a switched-off printer never causes restarts. |
| App stop (update, restart, host shutdown) | s6 sends `SIGTERM` in reverse dependency order. Klipper closes the MCU connection. The stop takes about 4 s in tests (timeout 30 s). |
| Host stops responding while printing | The MCU's own timeouts shut down heaters and motors (Klipper safety design). The print is lost. |

Home Assistant itself is isolated from all of this: the app is an ordinary
unprivileged container.

## Networking and authentication

```
Browser → Home Assistant (login) → Core ingress → Supervisor 172.30.32.2 → nginx :8099
Slicer  → <host>:7125 (only if the user maps the port) ───────────────────→ nginx :7125
                                                       nginx → Moonraker 127.0.0.1:7126
```

* Moonraker listens on **127.0.0.1 only**. nginx sets `X-Real-IP` and
  `X-Forwarded-For` to the TCP peer address, so clients cannot inject them.
  The integration tests check this.
* Moonraker `trusted_clients` contains only:
  * `127.0.0.1/32`: nginx inside the container. Moonraker requires the
    reverse proxy itself to be trusted; it still makes the trust decision
    on the forwarded client address.
  * `172.30.32.2/32`: the Supervisor ingress proxy. These users were already
    authenticated by Home Assistant.
  * the user's `trusted_networks`, validated: no catch-all ranges, nothing
    inside `172.30.32.0/23`.
* Everything else needs the Moonraker API key or a Moonraker user login.
* The ingress server presents the request's `Origin` host to Moonraker as
  `Host`. Behind the Home Assistant and Supervisor proxy chain these headers
  no longer match, and Moonraker would otherwise reject the WebSocket. This
  relaxes Moonraker's same-origin check **on the ingress port only**. Only
  the Supervisor can reach that port, and only for authenticated Home
  Assistant sessions. The direct port keeps Moonraker's full origin and
  CORS checks (tested).

### Mainsail under the ingress prefix

The Home Assistant ingress URL is
`/api/hassio_ingress/<token>/`, and the token differs per installation.
Mainsail's release build assumes it is served from `/`. Its `config.json`
`path` setting does not change the WebSocket path (Mainsail v2.19 stores it
under an unused key). The app therefore:

1. builds Mainsail from source with the placeholder base path
   `/__KHAOS_BASE__/` (`vite build --base` and `VUE_APP_PATH`);
2. lets nginx replace the placeholder in HTML, JS, CSS and the manifest
   (`sub_filter`) with:
   * the `X-Ingress-Path` header on the ingress server, only if it has the
     exact shape `/api/hassio_ingress/<token>`;
   * an empty string on the direct port.

One build serves both entry points, and no Supervisor API access is needed.

## Storage

| Path in container | Backed by | Contents | In backups |
|---|---|---|---|
| `/config` | app config folder (`app_config`, rw) | `printer.cfg`, `moonraker.conf`, `profiles/`, generated includes, variables | yes |
| `/data/printer_data/gcodes` | `/data` | G-code files and thumbnails | yes |
| `/data/printer_data/database` | `/data` | Moonraker SQLite database (history, Mainsail settings) | yes, plus a pre-backup snapshot |
| `/data/printer_data/backup` | `/data` | Moonraker database snapshots | yes |
| `/data/printer_data/logs` | `/data` | `klippy.log`, `moonraker.log` (rotated) | **no** |
| `/data/printer_data/config` | symlink → `/config` | Moonraker's view of the config root | n/a |
| `/run/klipper-haos` | tmpfs | Klipper API socket, virtual printer tty, crash counters | n/a |
| `/tmp` | tmpfs (`tmpfs: true`) | nginx temp paths | n/a |

User-owned files are created once and never overwritten. App-owned files
(`/config/klipper-haos/*`) are regenerated at every start, and only written
when their content changes, to avoid needless disk writes.

## Devices

`uart: true` lets the Supervisor give the container access to serial
devices; the host `/dev` (including `/dev/serial/by-id`) is visible. No
privileged mode, no raw USB (`usb: false`), no extra Linux capabilities.
The serial device is chosen with a `device(subsystem=tty)` option, which
gives a device picker in the Home Assistant UI. The app never hardcodes a
device path.

## Build

`klipper/Dockerfile` has three stages:

1. **mainsail**: Node 22 (digest-pinned) builds Mainsail from a pinned tag
   and verifies the commit hash.
2. **python-build**: on the Home Assistant Python base image, clones
   Klipper and Moonraker at pinned commits, creates virtual environments
   with exact constraints, applies the documented security overrides, and
   pre-compiles Klipper's C helper and Python bytecode.
3. **runtime**: the base image plus nginx and runtime libraries. It contains
   no compiler, git or node.

The Home Assistant builder no longer uses `build.yaml` (retired April
2026); the Dockerfile `FROM` is the single source of truth.

## Resource use

Measured in the integration test container on a desktop machine, idle, no
printer: **about 55 MiB RAM** for all services, under 1 % CPU. This has not
been measured on the target Celeron yet. Klipper's CPU use while printing
depends on the printer and move complexity. Numbers from the target
hardware will be added to the test report.

Not included, to save resources: numpy (only needed for accelerometer
input-shaper calibration), webcam streaming, timelapse, and Moonraker's
update manager.
