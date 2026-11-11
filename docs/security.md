# Security

Anyone who can send G-code can heat the hotend and bed and move the
machine. The app therefore treats access to Moonraker as equivalent to
physical access to the printer.

## Defaults

| Setting | Default | Why |
|---|---|---|
| Direct port `7125/tcp` | **not published** (`null`) | No network exposure unless the user enables it. |
| Moonraker listen address | `127.0.0.1:7126` | Only nginx inside the container can reach it. |
| Ingress server | accepts only `172.30.32.2` | Home Assistant ingress requirement. Users are authenticated by HA. |
| Ingress panel | admin users only (`panel_admin: true`) | Printer control is an admin action. |
| Trusted clients | nginx (`127.0.0.1`) and the ingress proxy only | No LAN-wide trust by default. |
| Authentication on the direct port | Moonraker API key or Moonraker login | No hardcoded credentials, no embedded tokens. |
| CORS | none | Only the built-in Mainsail (same origin). |
| Container privileges | no `privileged`, no `full_access`, no host network, `uart` only | Least privilege for serial access. |
| Moonraker update manager | disabled | No code is downloaded or changed at runtime. |
| Firmware flashing | never automatic | Flashing is a manual, documented step. |

## Requirements from the project brief and how they are met

* **No hardcoded credentials or embedded tokens.** Moonraker generates its
  API key at first start and stores it in its database. The key only leaves
  the container when the user enables `export_api_key`; it is then written
  to a file with mode 600 and never logged (tested).
* **No accidental public exposure.** The direct port is unmapped by default.
  Even when mapped, every request needs the API key unless the client's
  address is in `trusted_networks`.
* **No unrestricted trust.** `trusted_networks` rejects:
  * ranges broader than /16 (IPv4) or /48 (IPv6);
  * anything overlapping `172.30.32.0/23`, Home Assistant's internal network
    (that would trust Core and every other app);
  * loopback, unspecified and multicast addresses.
  An invalid value stops the app with an explanatory log message (tested).
* **Address spoofing.** nginx always replaces `X-Real-IP` and
  `X-Forwarded-For` with the TCP peer address before proxying. A client
  sending `X-Real-IP: 172.30.32.2` to the direct port is still rejected
  (tested). All `proxy_set_header` directives live at one level so they
  cannot be lost through nginx's inheritance rules.
* **Injection through options.** Every option value written into a config
  file is validated against a strict pattern. A newline in
  `serial_device`, for example, is rejected (unit tested), so options cannot
  add Klipper sections or G-code macros.
* **Ingress header handling.** The `X-Ingress-Path` value used to rewrite
  Mainsail's base path must match `^/api/hassio_ingress/[A-Za-z0-9_-]+$`.
  Anything else is ignored.

## Trade-offs (documented decisions)

* **Origin check on the ingress port.** Moonraker rejects WebSockets whose
  `Origin` differs from `Host`. Behind the Home Assistant → Supervisor proxy
  chain these legitimately differ, so on the ingress port nginx passes the
  `Origin` host as `Host`. The ingress port is reachable only through the
  Supervisor, which only forwards requests carrying a valid Home Assistant
  ingress session. The direct port keeps Moonraker's full origin and CORS
  checks (tested: cross-origin WebSocket → 403).
* **`127.0.0.1` in trusted clients.** Moonraker requires the reverse proxy
  itself to be trusted. Trust for proxied requests is still decided on the
  real client address. Processes inside the container can use Moonraker
  directly, but they already run with the app's full permissions.
* **Root inside the container.** Services run as root in the container, as
  most Home Assistant apps do. Running Klipper and Moonraker as an
  unprivileged user (with serial group mapping) is on the roadmap.
* **AppArmor.** The Supervisor's default AppArmor profile applies. A custom,
  tighter profile needs an audit on real HAOS and is on the roadmap.
* **Security overrides.** Moonraker v0.11.0 caps Tornado at 6.5.8 and Pillow
  at 12.3.0, versions with known HIGH/CRITICAL vulnerabilities. The image
  installs Tornado 6.5.9 and Pillow 13.0.0 instead. The thumbnail
  processing that uses Pillow is covered by an integration test. See
  `klipper/requirements/moonraker-overrides.txt`.

## Vulnerability scanning

CI runs Trivy on every build (report only, HIGH/CRITICAL, fixed issues
only). At the time of v0.1.0 there are 0 CRITICAL and 31 HIGH findings,
all outside the app's runtime code paths:

* Go standard library CVEs in `/usr/bin/tempio`. This tool comes with the
  Home Assistant base image and this app does not use it. It is fixed when
  the base image is updated.
* Build tooling bundled inside the Python environments (pip's and
  setuptools' vendored packages such as `wheel`, `jaraco.context`,
  `msgpack`, and the base image's own `pip`/`setuptools`/`urllib3`). None of
  these are imported by Klipper or Moonraker at runtime.

Review the scan output in each CI run before releasing.

## Physical safety

Software security does not replace physical safety:

* Klipper's thermal runaway protection (`verify_heater`) stays enabled. The
  profile documents its values; do not loosen them.
* MCU-side timeouts turn heaters off if the host stops responding (host
  crash, reboot, app restart).
* `START_PRINT` in the bundled profile refuses to run until the hardware
  validation checklist has been confirmed.
* Do not leave a printer unattended, especially with a new configuration.
