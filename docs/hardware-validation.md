# Hardware validation checklist

Run these steps **in order** after loading a printer profile. Each step
assumes that all previous steps passed. Stay at the printer with your hand
near the power switch during every step that moves motors or heats anything.

Record your results. When you have completed the checklist on a real
printer, please submit them with the "Printer profile report" issue
template. **Only report a step as passed if you actually performed it.**

| # | Step | How | Pass criteria | Result |
|---|---|---|---|---|
| 1 | Identify the controller board | [printer-setup.md §1](printer-setup.md#1-identify-the-controller-board) | Board, MCU and driver chips recorded and match the profile | ☐ |
| 2 | MCU firmware compatibility | Mainsail → Machine → system info | MCU version equals host version; MCU `stm32f103xe` | ☐ |
| 3 | Serial communication | Restart Klipper several times; unplug and replug USB, then `FIRMWARE_RESTART` | Klipper becomes *Ready* every time | ☐ |
| 4 | Thermistor readings | Dashboard temperatures at room temperature | Extruder and bed read close to room temperature (±3 °C) and stable | ☐ |
| 5 | Fans | `M106 S255` / `M107`; heat the extruder to 60 °C, then `M104 S0` | Part fan spins and stops. Hotend fan starts above 50 °C. Correct fan for each command | ☐ |
| 6 | Endstops | `QUERY_ENDSTOPS` released, then again while pressing each switch by hand | `open` when released, `TRIGGERED` when pressed, for X and Y. Z (probe) shows the probe state | ☐ |
| 7 | Limited axis movements | Position the toolhead mid-bed by hand. Then `SET_KINEMATIC_POSITION X=100 Y=100 Z=20` and `G91`, `G1 X10 F600`, `G1 Y10 F600`, `G1 Z5 F300`, `G90`. Repeat with negative values | Every axis moves the commanded distance in the right direction. Fix `dir_pin` if not | ☐ |
| 8 | Homing | `G28 X`, then `G28 Y`, then `G28` | X and Y move toward their endstops and stop. Z homes with the probe at the bed centre | ☐ |
| 9 | CR Touch | `BLTOUCH_DEBUG COMMAND=pin_down` / `pin_up`, `QUERY_PROBE`, then `PROBE_ACCURACY` | Pin deploys and retracts; probe state changes; range ≤ 0.025 mm | ☐ |
| 10 | Z-offset and bed mesh | `PROBE_CALIBRATE` (paper test) → `ACCEPT` → `SAVE_CONFIG`; then `BED_MESH_CALIBRATE` → `SAVE_CONFIG` | Paper drags slightly at Z=0. Mesh range plausible (< 1 mm) | ☐ |
| 11 | Heating and thermal protection | `M104 S200`, `M140 S60`; watch the graphs; then turn the heaters off | Both heaters reach target without overshooting by more than 10 °C. No `verify_heater` error. Heaters stop when turned off | ☐ |
| 12 | PID calibration | `PID_CALIBRATE HEATER=extruder TARGET=210`, `PID_CALIBRATE HEATER=heater_bed TARGET=60`, `SAVE_CONFIG` | Completes without errors; temperatures hold ±1 °C | ☐ |
| 13 | Supervised first print | `MARK_HARDWARE_VALIDATED CONFIRM=YES`, then print a small calibration cube with the slicer start G-code `START_PRINT ...` | Print completes; first layer adheres; you watched the whole print | ☐ |

Additional checks recommended before unattended use:

* Rotation distance of the extruder (extrude 100 mm, measure).
* Filament macros: `UNLOAD_FILAMENT`, then `LOAD_FILAMENT`, then `PURGE`
  with the head homed and mid-bed. The filament comes out of the gears,
  goes back in without grinding, and new filament flows from the nozzle.
  Then a test print with one `M600` colour change that you resume.
* `SCREWS_TILT_CALCULATE` for bed levelling.
* Input shaper tuning (ringing tower) before raising speed limits.
* Restart Home Assistant while the printer is idle and confirm Klipper
  reconnects by itself.

If a step fails, **stop** and fix the cause before continuing. A failing
step 4, 6, 9 or 11 means the profile does not match your hardware: report
it.

## Optional: original display

Only if you use the experimental [original display support](display.md).
Complete steps 1 to 3 above first.

| # | Step | How | Pass criteria | Result |
|---|---|---|---|---|
| D1 | Display firmware variant | Mainsail → Machine → system info | MCU version matches the display variant's `klipper-version.txt` for your app release | ☐ |
| D2 | Screen starts | Add the `display.cfg` include, `FIRMWARE_RESTART` | Klipper becomes *Ready*; the screen shows the Klipper menu with correct icons | ☐ |
| D3 | Knob | Turn the knob both ways, short press, long press | The selection moves in the turning direction; press opens the entry | ☐ |
| D4 | Live values | Heat the bed to 40 °C from Mainsail, watch the screen | The screen shows the same temperatures as Mainsail | ☐ |
| D5 | Control from the screen | Home all, move each axis 10 mm, preheat, cool down, from the screen | Each action matches what the screen says; nothing moves or heats unexpectedly | ☐ |
| D6 | Print from the screen | Start the calibration cube from the screen's file list (after step 13 above) | `START_PRINT` runs; pause, resume and stop from the screen work | ☐ |
| D7 | Reconnect | Unplug and replug USB, then `FIRMWARE_RESTART` | Klipper and the screen come back | ☐ |

Report results for D1 to D7 in the "Printer profile report" issue, with the
display firmware version.
