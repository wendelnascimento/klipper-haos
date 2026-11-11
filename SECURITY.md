# Security policy

## Supported versions

Only the latest release receives security fixes while the project is below
v1.0.0.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Use GitHub's private vulnerability reporting: open the repository's
**Security** tab and choose **Report a vulnerability**. Include:

* affected version(s) and configuration (which ports and options are
  enabled);
* steps to reproduce, and the impact you observed or expect;
* whether the issue is in this project or in an upstream component
  (Klipper, Moonraker, Mainsail, the Home Assistant base image).

You can expect an acknowledgement within 7 days. Upstream issues will be
coordinated with the upstream project.

Never include real API keys, passwords or tokens in a report.

## Security model (summary)

A 3D printer host controls heaters and motors. Treat API access as physical
access to the printer. The full model is in
[docs/security.md](docs/security.md).
