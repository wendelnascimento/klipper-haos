# Backup and restore

## What is backed up

A Home Assistant backup that includes the *Klipper* app contains:

* the app config folder: `printer.cfg`, `moonraker.conf`, `profiles/`,
  calibration results saved by `SAVE_CONFIG`, and
  `klipper-haos-variables.cfg`;
* `/data`: G-code files and thumbnails, the Moonraker database (print
  history, Mainsail settings, API key) and database snapshots;
* the app options.

Excluded on purpose: `printer_data/logs/*`, `printer_data/comms/*` (sockets)
and `*.tmp` files.

## How it works

* `backup: hot`: Home Assistant does **not** stop the app for a backup, so
  scheduled backups do not interrupt prints.
* `backup_pre`: before the copy, the app asks Moonraker (through its local
  Unix socket) to write a consistent SQLite snapshot to
  `printer_data/backup/database/klipper-haos-pre-backup.db`. If the live
  database file was mid-write during the copy, this snapshot is still
  consistent.
* Moonraker refuses to snapshot **while printing**. The hook then logs a
  warning and the backup continues with the live database. The hook never
  fails the Home Assistant backup.
* Backup compression costs CPU on low-power hosts. Avoid scheduling backups
  during long prints if you see `Timer too close` errors.

## Restore

1. **Settings → System → Backups**, choose the backup, and restore the
   *Klipper* app (a partial restore is enough).
2. Start the app. Configuration, profiles, G-code files and history are
   back.
3. If the Moonraker database is damaged, use Moonraker's database restore
   endpoint (`POST /server/database/restore` with
   `filename=klipper-haos-pre-backup.db`, see the
   [Moonraker API docs](https://moonraker.readthedocs.io)) to restore the
   snapshot.

## Verified so far

The pre-backup hook and the database snapshot are tested automatically
(`tests/integration/run.sh`). A full Home Assistant backup → restore cycle on
a real HAOS installation has **not been tested yet**. It is part of the
v0.3.0 milestone.
