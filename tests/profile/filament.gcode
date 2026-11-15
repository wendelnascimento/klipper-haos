; Filament macros: load, purge, unload and an M600 change with RESUME.
; _TEST_ASSERT_* macros are defined by check-profile.sh. E is the
; cumulative extruder position in mm.
G28
_TEST_ASSERT_E E=0
; Load: 40 feed + 30 purge - 1 retract.
LOAD_FILAMENT TEMP=210
_TEST_ASSERT_E E=69
; Purge: 30 - 1.
PURGE
_TEST_ASSERT_E E=98
; Unload: +5 - 10 - 50.
UNLOAD_FILAMENT
_TEST_ASSERT_E E=43
; PURGE raises a homed nozzle that is close to the bed.
G90
G1 X100 Y100 Z1 F3000
PURGE LENGTH=10
_TEST_ASSERT_Z_MIN Z=10
_TEST_ASSERT_E E=52
; M600: PAUSE (1 mm retract, park at least 50 mm up) and unload (-55).
M104 S200
M600
_TEST_ASSERT_PAUSED VALUE=1
_TEST_ASSERT_Z_MIN Z=50
_TEST_ASSERT_E E=-4
LOAD_FILAMENT
_TEST_ASSERT_E E=65
; RESUME pushes back the 1 mm and returns to the print position.
RESUME
_TEST_ASSERT_PAUSED VALUE=0
_TEST_ASSERT_E E=66
M600 X10 Y10 Z60
_TEST_ASSERT_Z_MIN Z=60
LOAD_FILAMENT PURGE=0
RESUME
_TEST_ASSERT_PAUSED VALUE=0
M104 S0
M84
