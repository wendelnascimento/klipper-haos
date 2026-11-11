# Development

## Repository layout

```
klipper-haos/
├── repository.yaml              Home Assistant app repository metadata
├── klipper/                     the app (slug: klipper)
│   ├── config.yaml              app manifest (options, ports, ingress, backup)
│   ├── Dockerfile               3-stage build; all upstream pins live here
│   ├── requirements/            exact Python constraints + security overrides
│   ├── mainsail/config.json     Mainsail runtime config
│   ├── rootfs/                  copied into the image
│   │   ├── etc/s6-overlay/      s6-rc services + user bundle
│   │   ├── etc/nginx/           ingress + direct port servers
│   │   ├── usr/local/lib/klipper-haos/  config generator, Moonraker RPC client
│   │   ├── usr/local/bin/       finish handler, backup hook
│   │   └── usr/share/klipper-haos/      default configs, printer profiles
│   ├── translations/en.yaml     option labels in the HA UI
│   ├── DOCS.md / README.md / CHANGELOG.md / icon.png / logo.png
├── firmware/<printer>/klipper.config   MCU firmware Kconfig fragments
├── tests/
│   ├── static/      ShellCheck, Hadolint, yamllint, s6 tree, secrets
│   ├── unit/        pytest for the option validator / config generator
│   ├── profile/     Klipper batch-mode validation of printer profiles
│   └── integration/ full container tests with a fake ingress proxy
├── tools/           build-firmware, check-upstream, update-locks, make-icons
└── docs/
```

`build.yaml` is intentionally absent: the Home Assistant builder retired it
in April 2026, and the Dockerfile's `FROM` is authoritative.

## Prerequisites

* Docker with BuildKit (Docker Desktop on Windows/macOS works; the scripts
  handle Git Bash path conversion).
* Bash, curl, Python 3 (only for the thumbnail fixture and unit tests).

Nothing in development or testing touches a real Home Assistant
installation or a printer.

## Build and test locally

```bash
docker build -t klipper-haos:test klipper          # ~3-5 min cold, seconds when cached
bash tests/static/run.sh                           # linters + s6 checks
docker run --rm -v "$PWD:/src:ro" -w /src python:3.13-alpine \
  sh -c 'pip install -q pytest pyyaml && python -m pytest -q -p no:cacheprovider tests/unit'
bash tools/build-firmware.sh ender3-v3-se          # MCU firmware + klipper.dict
bash tests/profile/check-profile.sh klipper-haos:test ender3-v3-se
bash tests/integration/run.sh klipper-haos:test    # needs free ports 17125, 18123
```

`KEEP=1 bash tests/integration/run.sh` leaves the containers running. Then
open `http://127.0.0.1:18123/api/hassio_ingress/testtoken/` to use Mainsail
through the simulated ingress proxy, or `http://127.0.0.1:17125/` for the
direct port. Clean up with
`docker rm -f khaos-app khaos-ingress && docker network rm khaos-test-net`.

The integration network uses `172.30.32.0/23` to mirror Home Assistant. If
that subnet collides with something on your machine, stop the other network
first.

## Testing on a real Home Assistant OS (development install)

Use a **test** installation, not your production Home Assistant.

1. Copy the `klipper/` folder to `/addons/klipper-dev/` on the test host
   (Samba or SSH app). Remove the `image:` line from `config.yaml` so the
   Supervisor builds locally, and change `slug` to `klipper_dev`.
2. **Settings → Apps → App store → ⋮ → Check for updates**. The app appears
   under *Local apps*.
3. Install, start, and work through the
   [v0.3 validation list](roadmap.md#v030--integration-and-reliability).

Local builds compile on the host and can be slow on a Celeron. That is fine
for development but never for users: released images are built in CI.

## Updating upstream components

Upstream projects release independently. Never auto-update them.

1. `bash tools/check-upstream.sh` shows pinned vs. latest versions.
2. Edit the `ARG` pins in `klipper/Dockerfile`: tag **and** commit hash.
   Get the hash with
   `git ls-remote https://github.com/<repo>.git refs/tags/<tag>`. For an
   annotated tag, use the `^{}` line.
3. `bash tools/update-locks.sh` regenerates the Python constraints.
4. Review `klipper/requirements/moonraker-overrides.txt`. Remove an override
   as soon as the new upstream allows the fixed version itself.
5. Rebuild, run **all** test layers, and update `THIRD_PARTY_NOTICES.md`
   and the changelog.
6. A Klipper bump requires new MCU firmware. Mention it prominently in the
   release notes.

Base images and GitHub Actions are proposed by Dependabot. These also need
a full test run before merging.

## Releasing

1. Update `version` in `klipper/config.yaml` and add a
   `## [X.Y.Z] - YYYY-MM-DD` section to `klipper/CHANGELOG.md`.
2. Merge to `main` with green CI.
3. Tag `vX.Y.Z` and push the tag. `.github/workflows/release.yaml`
   then:
   * checks that the tag matches `config.yaml` and that the changelog has
     an entry;
   * runs the full CI suite;
   * builds and pushes `ghcr.io/<owner>/<arch>-klipper-haos:X.Y.Z` and the
     multi-arch manifest `ghcr.io/<owner>/klipper-haos:X.Y.Z` with the
     official Home Assistant builder actions. Images are cosign-signed by
     the builder. There is no `latest` tag;
   * builds the matching Ender 3 V3 SE firmware and attaches it with
     checksums to a GitHub pre-release.
4. Make the GHCR package **public**: *Package settings → Change
   visibility*. This is needed once, for the first release.

Before the first release, replace `OWNER` in `repository.yaml`,
`klipper/config.yaml`, `klipper/Dockerfile`, `README.md` and
`docs/installation.md` with the GitHub account or organisation that hosts
the repository.

## Adding a printer profile

1. Add `klipper/rootfs/usr/share/klipper-haos/profiles/<printer>/`
   (`printer.cfg` plus includes). Write it yourself; only copy text from
   sources whose license allows it, and credit them.
2. Add `firmware/<printer>/klipper.config`.
3. Add the printer to `tests/profile/` and to CI (`ci.yaml`).
4. Add `docs/printers/<printer>.md` or extend `printer-setup.md` with board
   identification, flashing and recovery.
5. Mark it **experimental** until someone has completed the
   [hardware validation checklist](hardware-validation.md) on real
   hardware.

## Adding an architecture (aarch64)

1. Add `aarch64` to `arch:` in `klipper/config.yaml`. The base and Node
   images are multi-arch, so the Dockerfile needs no changes.
2. The release workflow builds per-arch images on native runners chosen by
   the builder's matrix action.
3. Test the build with `docker buildx build --platform linux/arm64 klipper`
   and run the integration suite on an arm64 machine.
4. Validate on real hardware before announcing support.
