; Exercised by tests/profile/check-profile.sh in Klipper batch mode.
G28 X Y
G90
G1 X100 Y100 F3000
G1 X5 Y5 F6000
M104 S200
M140 S60
M106 S128
M107
SET_PIN PIN=beeper VALUE=0
M104 S0
M140 S0
M84
