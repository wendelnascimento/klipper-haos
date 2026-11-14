# Original Ender 3 V3 SE display (experimental)

> **Status: experimental, not yet validated on hardware by this project.**
> The firmware builds and the configuration loads in automated tests, but
> nobody has confirmed yet that the screen and knob work with this app.
> Read the whole page before flashing anything.

With stock Klipper the Ender 3 V3 SE's own screen stays blank, and you use
Mainsail instead. This optional feature brings the screen and knob back
with a Klipper menu: print a file, tune or pause a print, move and home
axes, set the Z offset, preheat, cool down, and run your own macros.

The display code is the work of the
[ender3-v3-se-klipper-with-display](https://github.com/jpcurti/ender3-v3-se-klipper-with-display)
project by jpcurti (GPL-3.0). Klipper HAOS bundles a pinned copy of the
parts it needs. It does **not** switch the app to that project's Klipper
fork.

## How it works

The screen is wired to the printer's mainboard, not to the computer. Its
serial lines go to the mainboard's second serial port (USART2, pins PA2 and
PA3), and the knob goes to three mainboard pins (PA12, PA11, PB1).

* A **firmware variant** adds a "serial bridge" to the printer's Klipper
  firmware. The mainboard then passes display messages through the USB
  connection that Klipper already uses. Everything else in the firmware is
  identical to the normal Klipper HAOS firmware.
* A **Klipper module** (`e3v3se_display`, already inside the app) draws the
  menus and reads the knob. It is inactive until you include `display.cfg`.

No wiring changes, no extra USB device and no extra app permissions are
needed.

## Requirements

1. **The display firmware variant** on the printer:
   `ender3-v3-se-display-<version>-klipper.bin` from the GitHub release of
   the app version you run, or `tools/build-firmware.sh ender3-v3-se-display`.
   The normal `ender3-v3-se` firmware lacks the serial bridge.
2. **Display firmware 1.0.6** on the screen itself. The menu draws icons
   that are stored inside the screen. The upstream project was built for
   display firmware 1.0.6 and warns that other versions may keep the icons
   at other positions. We found no documented way to read the screen's own
   version, least of all once Klipper runs on the mainboard. The practical
   check is checklist step D2: if the menu's icons look right, the screen
   is compatible. If they look wrong, update the screen as described on
   [Creality's download page](https://www.creality.com/pages/download-ender-3-v3-se),
   which the upstream project links to. Wrong icons do not affect printing
   or Mainsail.
3. The stock display cable, connected as delivered.

## Enable it

1. **Flash the variant.** Follow [printer setup](printer-setup.md) steps 4
   and 5 with `ender3-v3-se-display-<version>-klipper.bin` instead of the
   normal file. Give the file a new, unique name on the card. Flashing is
   always a manual step; the app never flashes anything.
2. **Check the MCU.** In Mainsail, *Machine* → system info shows the MCU
   version. The display variant reports a version one commit ahead of the
   host (for example host `v0.13.0-827-g29d4ec2d`, MCU
   `v0.13.0-828-ge4befa2e`). The extra commit is the serial bridge. The
   exact value for each release is in its `klipper-version.txt` file.
3. **Include the display configuration.** Add this line to
   `/config/printer.cfg`, below the profile include:

   ```ini
   [include klipper-haos/generated.cfg]
   [include profiles/ender3-v3-se/printer.cfg]
   [include profiles/ender3-v3-se/display.cfg]
   ```

   `profiles/ender3-v3-se/display.cfg` is installed by the app (also into
   an existing profile folder). It sets the language and lists the stock
   pins for reference.
4. **Restart Klipper** (`FIRMWARE_RESTART`). The screen should show the
   Klipper menu within a few seconds.

Then work through the display steps at the end of the
[hardware validation checklist](hardware-validation.md#optional-original-display).

## Turn it off or go back

* **Screen off, keep the variant:** remove the `display.cfg` include and
  restart Klipper. The variant works like the normal firmware.
* **Back to the normal firmware:** remove the include, then flash
  `ender3-v3-se-<version>-klipper.bin` (new file name on the card).
* **Back to stock Creality firmware:** see
  [printer setup → recovery](printer-setup.md#7-recovery-and-reverting-to-stock-firmware).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Klipper stops with `MCU Protocol error` and `Unknown command: serial_bridge_send` | `display.cfg` is included but the printer runs the normal firmware. Flash the display variant, or remove the include. |
| Screen stays blank | Check the MCU version (step 2 above). Set `logging: True` in `display.cfg`, restart, and look for `e3v3se_display` and `Serial bridge` lines in `klippy.log`. |
| Wrong or garbled icons | Most likely the screen does not run display firmware 1.0.6. Update it as described on Creality's download page (see Requirements). |
| A menu entry shows a "not supported" pop-up | Expected for "Set max speed", "Set max acceleration" and "Set steps per-mm", which the upstream project does not support. |

When you report a problem, include `klippy.log` with `logging: True` and
the display firmware version.

## Limits and safety

* The upstream project describes itself as early work and warns that some
  menu commands may crash the printer. Watch the printer the first times
  you use each menu.
* Prints started from the screen run the same `START_PRINT` macro, and its
  hardware validation gate, as prints started from Mainsail or a slicer.
* Klipper's usual protections (thermal runaway checks, MCU timeouts) do not
  depend on the display.

## Custom menus

`display.cfg` can add entries to the screen's "Macros" menu, for example:

```ini
[e3v3se_display MACRO1]
label: Home all axes
gcode: G28
icon: 14
```

Run `ENDER_SE_DISPLAY_ICON_FINDER` in the Mainsail console to browse the
icon numbers stored in the screen.

## Updating the bundled display code

Maintainers: see
[development → updating the display support](development.md#updating-the-display-support).
