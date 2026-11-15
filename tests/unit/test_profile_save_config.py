"""SAVE_CONFIG must be able to store calibration results.

Klipper refuses SAVE_CONFIG when an option it wants to save is set in an
included file ("conflicts with included value"). The printer profile is
included from the user's printer.cfg, so it must not set any option that
Klipper's calibration commands save. Those values start in the user's own
printer.cfg instead (documented in the profile header).
"""

from __future__ import annotations

import configparser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "klipper/rootfs/usr/share/klipper-haos/profiles/ender3-v3-se"
MAIN_TEST_CFG = ROOT / "tests" / "profile" / "main-ender3-v3-se.cfg"

# Options written by SAVE_CONFIG after Klipper's calibration commands:
# PID_CALIBRATE, PROBE_CALIBRATE / Z_OFFSET_APPLY_PROBE, SHAPER_CALIBRATE.
SAVED = {
    "extruder": {"control", "pid_kp", "pid_ki", "pid_kd"},
    "heater_bed": {"control", "pid_kp", "pid_ki", "pid_kd"},
    "bltouch": {"z_offset"},
    "input_shaper": {"shaper_type_x", "shaper_freq_x", "shaper_type_y", "shaper_freq_y"},
}


def read_cfg(path: Path) -> configparser.RawConfigParser:
    parser = configparser.RawConfigParser(strict=False, inline_comment_prefixes=("#", ";"))
    parser.read_string(path.read_text(encoding="utf-8"))
    return parser


def test_profile_sets_no_option_that_save_config_writes() -> None:
    for cfg in sorted(PROFILE.glob("*.cfg")):
        parser = read_cfg(cfg)
        for section, options in SAVED.items():
            if parser.has_section(section):
                clash = options & set(parser.options(section))
                assert not clash, f"{cfg.name} [{section}] sets {sorted(clash)}"


def header_block() -> str:
    """The example /config/printer.cfg block from the profile header."""
    lines = (PROFILE / "printer.cfg").read_text(encoding="utf-8").splitlines()
    block = [line[6:] if line.startswith("#     ") else "" for line in lines
             if line.startswith("#     ") or line == "#"]
    text = "\n".join(block)
    start = text.index("# Starting values.")
    return text[start:].split("\n\n\n")[0].strip()


def test_header_example_matches_tested_main_config() -> None:
    tested = MAIN_TEST_CFG.read_text(encoding="utf-8").strip()
    assert header_block() == tested


def test_tested_main_config_starts_above_the_bed() -> None:
    parser = read_cfg(MAIN_TEST_CFG)
    assert parser.getfloat("bltouch", "z_offset") == 0.0
    for heater in ("extruder", "heater_bed"):
        assert parser.get(heater, "control") == "pid"
