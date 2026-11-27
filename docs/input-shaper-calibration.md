# Input shaper calibration with an accelerometer

> **Status: experimental.** The app side (options, firmware build, profile
> file) is tested in containers and in Klipper's batch mode. It has not yet
> been run on a printer by this project.

Klipper's `SHAPER_CALIBRATE` measures the printer's resonances with an
ADXL345 accelerometer and picks the input shaper type and frequency for each
axis. It is more precise than a ringing tower print, and it is worth
repeating after anything that changes the moving mass, such as new part
cooling fans on the toolhead.

The Home Assistant host has no SPI pins for an accelerometer, so the
ADXL345 needs a small MCU of its own, connected by USB and running Klipper.
Klipper uses it as a second MCU, `[mcu adxl]`. This guide uses the
**Mellow FLY ADXL345 USB** (RP2040 and ADXL345 on one USB-C board). Other
RP2040 boards are covered under [Other boards](#other-boards).

## What it costs

numpy is the extra piece Klipper needs for the calculation. It is part of
the image for everyone (numpy 2.5.5, without its test suite), but Klipper
only sees it when the option `numpy` is on. Measured on amd64 against the
image without numpy:

| | Option `numpy` off | Option `numpy` on |
|---|---|---|
| Download (compressed image) | +16 MB (130.4 → 146.7 MB) | same |
| Disk (unpacked) | +51 MB (`/opt/numpy`) | same |
| Memory while idle or printing | no change | no change: Klipper imports numpy only when a resonance test runs |
| Memory after the first resonance test | n/a | Klipper's process grows by about 22 MiB until Klipper restarts |
| Memory during the calculation | n/a | a short-lived worker process, up to about 170 MiB per axis, for about a second |

The calculation figure is the peak of Klipper's own calibration code
(`calc_freq_response` and `find_best_shaper`) in the app image, on a
synthetic data set the size of one `SHAPER_CALIBRATE AXIS=X` run
(5–135 Hz at 1 Hz/s, 3200 samples/s, 416,000 samples). About half of it is
the samples themselves. It found the synthetic 55 Hz resonance (mzv
55.6 Hz) in about one second on a desktop CPU. On the target Celeron, with
about 2 GB free, this fits easily. Numbers from the real printer will be
added to the [test report](test-report.md).

## 1. Build the firmware

The firmware must come from the same Klipper version as the app. Otherwise
Klipper refuses the board with a protocol error. Either download
`fly-adxl345-usb-<version>-klipper.uf2` from the GitHub release that matches
your app version (check it against the `SHA256SUMS` file next to it), or
build it with Docker:

```
bash tools/build-firmware.sh fly-adxl345-usb
```

The result is `firmware/out/fly-adxl345-usb/klipper.uf2` and its
`klipper.uf2.sha256`. The settings are in
`firmware/fly-adxl345-usb/klipper.config`: RP2040, no bootloader, USB
serial. These are the choices from Mellow's documentation.

## 2. Flash the board (manual, on a PC)

The app cannot flash the board: it has no raw USB access, by design. Use
any PC. The RP2040's UF2 boot loader is in ROM, so a failed copy cannot
brick the board; you can repeat these steps.

1. Unplug the board.
2. Hold the board's **BOOT** button, plug the board into the PC, then
   release the button.
3. A USB drive named `RPI-RP2` appears.
4. Copy `klipper.uf2` onto that drive. The board restarts with Klipper
   and the drive disappears. That is expected.

Repeat this after an app update that changes the Klipper version. The
changelog says when it does.

## 3. Connect it and find its serial path

Plug the board into the Home Assistant host. Use a USB **data** cable, the
same as for the printer. Then find its stable path:

* In the app's **Configuration** tab, the *Accelerometer serial device*
  picker lists it, **or**
* restart the app and read the **Log** tab, which lists every
  *Serial devices visible to the app (by-id)*.

Klipper firmware on an RP2040 names itself
`/dev/serial/by-id/usb-Klipper_rp2040_<board serial>-if00`. Pick that
one. Do not pick the printer (`usb-1a86_...`) or any other device on the
host, such as a Zigbee or Z-Wave stick. The app rejects the printer's own
device for this option.

## 4. App options

In the app's **Configuration** tab:

* `numpy`: on.
* `adxl_serial_device`: the `usb-Klipper_rp2040_...` path from step 3.

Save and restart the app. The log shows
`Accelerometer serial device: ... -> /dev/ttyACM...` and
`numpy is available to Klipper`. `klipper-haos/generated.cfg` now has an
`[mcu adxl]` section with that port.

## 5. Include the profile file

`profiles/ender3-v3-se/adxl.cfg` (installed with the profile) has the
board's pins and the test point: the bed centre, X 117 Y 117 Z 20. Add the
include to `/config/printer.cfg`, below the profile include:

```
[include klipper-haos/generated.cfg]
[include profiles/ender3-v3-se/printer.cfg]
[include profiles/ender3-v3-se/adxl.cfg]
```

Restart Klipper (*FIRMWARE_RESTART*). Mainsail shows a second MCU, `adxl`.

Profile copies installed by app 0.2.2 or earlier do not have `adxl.cfg`.
The app copies the new file in at the next start, because it is missing;
it never changes your existing files.

## 6. Check the sensor

Fix the board firmly on the toolhead. A loose board measures its own
rattle. Then run:

```
ACCELEROMETER_QUERY
```

Expected: one line with three values, one of them about ±9800 (gravity),
for example `adxl345 values (x, y, z): 470.7, 941.4, 9728.2`.
`Invalid adxl345 id (got 00 vs e5)`: run it once more; if it stays, the
firmware or the board is the problem (see [Troubleshooting](#troubleshooting)).

```
MEASURE_AXES_NOISE
```

Expected: noise values of about 1–100 per axis. Values in the thousands
usually mean an unbalanced fan or a loose mount.

### Axis orientation

`SHAPER_CALIBRATE` fits the shaper to the sum of all three chip axes. The
board's orientation, and so `axes_map`, does not change its result. It
only matters if you graph the per-axis columns of the CSV files. Klipper's
[Measuring Resonances](https://www.klipper3d.org/Measuring_Resonances.html)
documentation describes `axes_map`.

## 7. Calibrate

The Ender 3 V3 SE is a bed slinger. The toolhead moves in X and the bed
moves in Y. Measure each axis with the board on the part that moves:

1. Home: `G28`.
2. **X:** board on the toolhead.

   ```
   SHAPER_CALIBRATE AXIS=X
   ```

   Stay at the printer. The test vibrates the axis through 5–135 Hz for
   about two minutes. If it gets violent, stop it with `M112` and lower
   `accel_per_hz` in `adxl.cfg`. When it finishes, the console lists each
   shaper and ends with
   `Recommended shaper_type_x = ..., shaper_freq_x = ... Hz`.

3. `SAVE_CONFIG`. Klipper writes `shaper_type_x` and `shaper_freq_x` into
   the `SAVE_CONFIG` block at the end of `/config/printer.cfg` and
   restarts.
4. **Y:** move the board to the bed (firmly, for example with a printed
   clip or a screw into the bed carriage), then `G28` and

   ```
   SHAPER_CALIBRATE AXIS=Y
   ```

5. `SAVE_CONFIG` again.

If your `/config/printer.cfg` already has `shaper_freq_x` / `shaper_freq_y`
in an `[input_shaper]` section, for example from a ringing tower,
`SAVE_CONFIG` comments those lines out and the new values apply. The
profile only sets `shaper_type: mzv`; the saved `shaper_type_x` and
`shaper_type_y` take precedence over it.

`SHAPER_CALIBRATE` also prints a suggested `max_accel` per shaper. It does
not change `[printer] max_accel` itself. Raise that by hand in
`/config/printer.cfg` if you want to, staying at or below the suggestion.
Slicers that send their own acceleration (`M204`, `SET_VELOCITY_LIMIT`)
override it while printing.

Do not run the calibration often. The vibrations near resonance are hard
on the printer. After a run, check that every screw is still tight.

Klipper also writes the measured data to `/tmp/calibration_data_*.csv`
inside the app. Those files are not reachable from Mainsail and are gone
after an app restart. The console output has everything needed.

## 8. Afterwards

Klipper waits at start-up until every configured MCU answers. With the
board unplugged it would not become ready. So when you are done:

1. Remove (or comment out) the `adxl.cfg` include line.
2. Clear `adxl_serial_device`. You can also turn `numpy` off.
3. Restart the app, then unplug the board.

The calibration results stay in `/config/printer.cfg`.

## Troubleshooting

| Message | Cause / fix |
|---|---|
| ``Failed to import `numpy` module`` | The option `numpy` is off. Turn it on and restart the app. |
| `Option 'serial' in section 'mcu adxl' must be specified` | `adxl.cfg` is included but `adxl_serial_device` is empty. Set it (step 4) or remove the include. |
| Klipper does not become ready: `mcu 'adxl': Unable to connect` (`klippy.log`: `Unable to open serial port`) | The board is unplugged, has no Klipper firmware, or a different device was picked. Plug it in or clear the option (step 8). The app log warns *Accelerometer serial device ... is not present*. |
| `MCU 'adxl' Protocol error` / version mismatch | The board's firmware was built from a different Klipper version. Reflash it with the matching build (steps 1–2). |
| `Invalid adxl345 id (got 00 vs e5)` | Retry once. If it stays: wrong firmware or pins (this file is for the FLY ADXL345 USB), or a faulty board. |
| `adxl_serial_device must be the accelerometer board, not the printer's serial_device` | The same path was picked for both options. |

## Other boards

`adxl.cfg` is written for the Mellow FLY ADXL345 USB. The same firmware
build (RP2040, no bootloader, USB) also suits:

* **Raspberry Pi Pico + a bare ADXL345 module (GY-291)**, wired as in
  Klipper's [Measuring Resonances](https://www.klipper3d.org/Measuring_Resonances.html#using-raspberry-pi-pico)
  guide. In `adxl.cfg`, replace the four `spi_software_*`/`cs_pin` lines
  with `cs_pin: adxl:gpio1` and `spi_bus: spi0a`.
* **Other RP2040 USB ADXL345 boards:** use the pins from the board's own
  documentation.

These variants have not been tested by this project.
