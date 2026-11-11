# Printer setup: Creality Ender 3 V3 SE

> **Status: experimental.** This guide and the profile have been checked for
> consistency (syntax, pins against the compiled firmware dictionary), but
> **not on a physical printer by this project yet**. Read every step. You
> are responsible for verifying your hardware. If you complete these steps,
> please report your results in a GitHub issue ("Printer profile report").

Order of work:

1. [Identify the controller board](#1-identify-the-controller-board)
2. [Determine the MCU firmware configuration](#2-determine-the-mcu-firmware-configuration)
3. [Build the Klipper firmware](#3-build-the-klipper-firmware)
4. [Prepare the firmware file](#4-prepare-the-firmware-file)
5. [Flash the printer](#5-flash-the-printer) (manual, explicit step)
6. [Confirm MCU communication](#6-confirm-mcu-communication)
7. [Recovery and reverting to stock firmware](#7-recovery-and-reverting-to-stock-firmware)
8. [Load the profile and run the hardware validation checklist](#8-load-the-profile-and-validate-the-hardware)

**The app never flashes firmware.** Flashing is always a separate, manual
action that you decide to do.

## 1. Identify the controller board

Do not assume every Ender 3 V3 SE has the same board.

1. Switch the printer off and **unplug it from mains power**.
2. Remove the electronics cover (under the printer, screws on the bottom).
3. Photograph the board and note:
   * the board label. The profile targets **CR4NS200320C13**.
   * the **MCU chip** marking. The profile targets **GD32F303RET6**.
   * the **stepper driver chip** markings. Both TMC2208-compatible and
     **MS35774** chips have been reported for this printer.
   * the USB-to-serial chip (expected: CH340, USB ID `1a86:7523`).

If your board or MCU differs, **stop**: the firmware configuration and pins
in this guide may be wrong for your printer. Open a "Printer profile report"
issue with photos.

## 2. Determine the MCU firmware configuration

For CR4NS200320C13 / GD32F303RET6 the Klipper firmware configuration is:

| `make menuconfig` option | Value |
|---|---|
| Micro-controller architecture | STMicroelectronics STM32 |
| Processor model | STM32F103 |
| Bootloader offset | 28KiB bootloader |
| Clock reference | 8 MHz crystal |
| Communication interface | Serial (on USART1 PA10/PA9), wired to the USB-C port |
| Baud rate | 250000 |

The GD32F303 is not an STM32F103, but it is register-compatible for
Klipper's purposes; both community references below use this
configuration. The configuration is stored in
[`firmware/ender3-v3-se/klipper.config`](../firmware/ender3-v3-se/klipper.config).

## 3. Build the Klipper firmware

The firmware **must match the Klipper host version in the app**. Use one of:

* **Release download (recommended):** every GitHub release has
  `ender3-v3-se-<version>-klipper.bin` and a `SHA256SUMS` file, built from
  exactly the Klipper commit inside that app release.
* **Build it yourself** on any computer with Docker:

  ```bash
  tools/build-firmware.sh ender3-v3-se
  ```

  The output goes to `firmware/out/ender3-v3-se/`: `klipper.bin`,
  `klipper.bin.sha256`, the full `.config` and `klipper.dict`. The build is
  reproducible, so two builds of the same commit give the same SHA-256.

Never compile firmware on the Home Assistant machine.

## 4. Prepare the firmware file

1. Use a microSD card of 32 GB or smaller, formatted **FAT32**.
2. Copy `klipper.bin` to the **root** of the card and give it a **new,
   unique name ending in `.bin`**, for example `klipper-20261110.bin`. The
   bootloader skips a file whose name matches the last flashed file.
3. Verify the checksum before copying (`sha256sum -c` or
   `Get-FileHash` on Windows).

## 5. Flash the printer

This is the only step that changes the printer. Only do it when you are
ready to run the printer with Klipper.

1. Switch the printer off. Insert the microSD card.
2. Switch the printer on. The bootloader flashes the file; wait about one
   minute.
3. **The original display stays blank or frozen.** This is expected: it is
   not supported by Klipper.
4. Switch the printer off, remove the card, and keep it as proof of what was
   flashed.

If nothing seems to happen, check the card format and the file name, then
try again with a new file name.

## 6. Confirm MCU communication

1. Connect the printer to the Home Assistant machine with a USB data cable.
2. In Home Assistant, open the app's **Configuration** tab and select the
   `serial_device`. Expect something like
   `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`.
3. Restart the app. Keep the starter `printer.cfg` (inert, no motion) for
   this test.
4. In Mainsail, Klipper should become **Ready**. The *Machine* page shows
   the MCU and its firmware version, which must match the host version.

If you see *"mcu 'mcu': Unable to connect"*, check the cable, the selected
device and that flashing succeeded. If you see
*"Serial connection closed"* repeatedly, try another USB port or cable.

## 7. Recovery and reverting to stock firmware

The Creality bootloader is not overwritten by flashing Klipper, so you can
go back:

1. Download the stock firmware for the Ender 3 V3 SE from Creality's
   official support site. Check that it is for your exact model and board.
2. Copy it to the root of a FAT32 microSD card under a **new unique `.bin`
   name** and flash it as in step 5.
3. The original display works again with the stock firmware.

If the bootloader does not accept the file, use a different card, reformat
it as FAT32, and rename the file again. If the printer does not boot at all,
contact Creality support. Recovering a damaged bootloader needs an SWD
programmer and is outside the scope of this project.

## 8. Load the profile and validate the hardware

Replace your `printer.cfg` (via Mainsail → *Machine*) with:

```ini
[include klipper-haos/generated.cfg]
[include profiles/ender3-v3-se/printer.cfg]
```

Restart Klipper, then work through the
[hardware validation checklist](hardware-validation.md) **in order**. Do not
skip ahead to homing or heating.

Things the profile deliberately leaves unsafe-to-print until you calibrate:

* `z_offset: 0.0` keeps the nozzle **above** the bed. Calibrate it with
  `PROBE_CALIBRATE`.
* PID values are community starting points. Run `PID_CALIBRATE`.
* `START_PRINT` is blocked until you run
  `MARK_HARDWARE_VALIDATED CONFIRM=YES`.
* Motion limits are below the stock firmware's limits (200 mm/s,
  2000 mm/s²).

### Stepper drivers

`profiles/ender3-v3-se/drivers-tmc2208.cfg` configures the X, Y and Z
drivers over UART as TMC2208. If Klipper reports
*"Unable to read tmc uart 'stepper_x' register IFCNT"*, your board's driver
chips do not answer in that mode, for example MS35774 variants. In that
case comment out the `[include drivers-tmc2208.cfg]` line in
`profiles/ender3-v3-se/printer.cfg` and report your board in an issue.

### Not supported in this profile

* **Original display:** not supported. Use Mainsail.
* **Pressure sensor (strain gauge) automatic Z-offset:** not supported in
  v1.0 and needs a forked Klipper. Use the CR Touch and manual Z-offset.
* **Filament runout sensor:** not configured. Contributions are welcome
  once the pin is verified.

## References

Pin assignments were cross-checked against these community configurations.
Both agree on all pins, but they are references, not guarantees. They are
published without a license, so no text was copied from them.

* <https://github.com/0xD34D/ender3-v3-se-klipper-config>
* <https://github.com/bootuz-dinamon/ender3-v3-se-full-klipper>
* Klipper documentation: <https://www.klipper3d.org/>
