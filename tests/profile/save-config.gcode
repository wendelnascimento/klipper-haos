; SAVE_CONFIG must be able to store a probe Z-offset (no conflict
; with values set in the included profile).
G28
SET_GCODE_OFFSET Z=-0.1
Z_OFFSET_APPLY_PROBE
SAVE_CONFIG
