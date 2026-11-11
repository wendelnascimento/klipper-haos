# Contributing to Klipper HAOS

Thank you for helping! Contributions of every size are welcome, especially:

* **hardware reports:** running the
  [hardware validation checklist](docs/hardware-validation.md) on a real
  printer and reporting the results;
* **printer profiles** for other printers;
* **architecture support**, for example aarch64;
* fixes, tests and documentation.

By participating you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

* For anything larger than a small fix, open an issue first to discuss the
  approach.
* Security issues: please follow [SECURITY.md](SECURITY.md) instead of
  opening a public issue.

## Development workflow

1. Fork the repository and create a branch from `main`.
2. Make your change. Keep it focused, with one topic per pull request.
3. Run the test layers that apply (see [docs/development.md](docs/development.md)):

   ```bash
   bash tests/static/run.sh
   docker build -t klipper-haos:test klipper
   bash tests/integration/run.sh klipper-haos:test
   ```

   For profile changes also run `tools/build-firmware.sh <printer>` and
   `tests/profile/check-profile.sh klipper-haos:test <printer>`.
4. Update documentation and `klipper/CHANGELOG.md` (under an
   `Unreleased` heading) for user-visible changes.
5. Open a pull request using the template. CI must pass.

## Rules that keep the project safe

* **Never report a hardware test as passed unless you performed it.** Say
  what you tested and on which hardware.
* Do not add automatic firmware flashing or anything that changes the
  printer without an explicit user action.
* Do not weaken thermal protection, authentication defaults or option
  validation without a documented security discussion.
* Do not add privileged container options (`full_access`, `privileged`,
  `host_network`, ...) unless strictly required and documented.
* Respect licenses: only copy code or configuration whose license allows it,
  and credit sources. Pin new upstream components by version **and**
  commit, and list them in `THIRD_PARTY_NOTICES.md`.

## Commit messages

* Write in English, in the imperative mood ("Add ...", "Fix ...").
* First line ≤ 72 characters; explain the *why* in the body.
* One logical change per commit.

## Printer profile contributions

A new profile needs:

* `klipper/rootfs/usr/share/klipper-haos/profiles/<printer>/` (your own
  text, with values marked `VERIFY` where they depend on the unit);
* `firmware/<printer>/klipper.config`;
* a profile test in `tests/profile/` and the CI wiring;
* documentation: board identification, flashing, recovery;
* the label **experimental** until a validation report exists.

## License

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE) of this project.
