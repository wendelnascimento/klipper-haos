"""Accelerometer input shaper calibration: profile, firmware and numpy wiring.

The profile's adxl.cfg is also loaded by Klipper itself in batch mode against
the compiled RP2040 firmware (tests/profile/check-profile.sh); these tests
cover what batch mode cannot: geometry, and that the image, the run script
and the documentation agree with each other.
"""

from __future__ import annotations

import configparser
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "klipper/rootfs/usr/share/klipper-haos/profiles/ender3-v3-se"
FIRMWARE = ROOT / "firmware" / "fly-adxl345-usb" / "klipper.config"
DOCKERFILE = ROOT / "klipper" / "Dockerfile"
NUMPY_REQ = ROOT / "klipper" / "requirements" / "numpy.txt"
COMMON = ROOT / "klipper/rootfs/usr/local/lib/klipper-haos/common.sh"
KLIPPER_RUN = ROOT / "klipper/rootfs/etc/s6-overlay/s6-rc.d/klipper/run"
GUIDE = ROOT / "docs" / "input-shaper-calibration.md"


def read_cfg(path: Path) -> configparser.RawConfigParser:
    parser = configparser.RawConfigParser(strict=False, inline_comment_prefixes=("#", ";"))
    parser.read_string(path.read_text(encoding="utf-8"))
    return parser


def floats(value: str) -> list[float]:
    return [float(v) for v in value.replace("\n", ",").split(",") if v.strip()]


ADXL = read_cfg(PROFILE / "adxl.cfg")
PRINTER = read_cfg(PROFILE / "printer.cfg")


def test_adxl_mcu_gets_its_port_from_the_app():
    # The serial port comes from the app option (generated.cfg), never from
    # the profile: a hard-coded by-id path would be wrong for every board.
    assert ADXL.has_section("mcu adxl")
    assert not ADXL.has_option("mcu adxl", "serial")
    assert not ADXL.has_section("mcu")


def test_adxl345_uses_the_fly_usb_board_pins():
    # Mellow FLY ADXL345 USB: software SPI, CS gpio9, SCLK gpio10, MOSI gpio11,
    # MISO gpio12 (Mellow's board documentation).
    section = dict(ADXL.items("adxl345"))
    assert section["cs_pin"] == "adxl:gpio9"
    assert section["spi_software_sclk_pin"] == "adxl:gpio10"
    assert section["spi_software_mosi_pin"] == "adxl:gpio11"
    assert section["spi_software_miso_pin"] == "adxl:gpio12"
    assert "spi_bus" not in section
    assert sorted(a.strip().lstrip("-") for a in section["axes_map"].split(",")) == ["x", "y", "z"]


def test_resonance_tester_probe_point_is_the_bed_centre():
    assert ADXL.get("resonance_tester", "accel_chip") == "adxl345"
    points = floats(ADXL.get("resonance_tester", "probe_points"))
    assert len(points) == 3, "one probe point: x, y, z"
    x, y, z = points
    # The bed screw pattern (probe positions = screw position + probe offset)
    # is centred on the bed.
    dx = PRINTER.getfloat("bltouch", "x_offset")
    dy = PRINTER.getfloat("bltouch", "y_offset")
    screws = [floats(PRINTER.get("screws_tilt_adjust", f"screw{i}")) for i in range(1, 5)]
    cx = sum(s[0] + dx for s in screws) / 4
    cy = sum(s[1] + dy for s in screws) / 4
    assert abs(x - cx) <= 1.0 and abs(y - cy) <= 1.5, (cx, cy)
    # Reachable with margin for the test moves, and clear of the bed.
    for axis, value in (("x", x), ("y", y)):
        lo = PRINTER.getfloat(f"stepper_{axis}", "position_min")
        hi = PRINTER.getfloat(f"stepper_{axis}", "position_max")
        assert lo + 50 <= value <= hi - 50
    assert 10 <= z <= PRINTER.getfloat("stepper_z", "position_max") - 50


def test_adxl_cfg_sets_nothing_in_input_shaper():
    # SHAPER_CALIBRATE + SAVE_CONFIG must be able to store the results.
    assert not ADXL.has_section("input_shaper")
    assert PRINTER.has_section("input_shaper")


def test_firmware_config_is_rp2040_usb_without_bootloader():
    lines = {
        line.strip()
        for line in FIRMWARE.read_text(encoding="utf-8").splitlines()
        if line.startswith("CONFIG_")
    }
    assert lines == {
        "CONFIG_MACH_RPXXXX=y",
        "CONFIG_MACH_RP2040=y",
        "CONFIG_RPXXXX_FLASH_START_0100=y",
        "CONFIG_RPXXXX_USB=y",
    }


def test_numpy_is_hash_pinned_binary_only():
    reqs = [
        line for line in NUMPY_REQ.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ]
    assert len(reqs) == 1
    assert re.fullmatch(r"numpy==\d+\.\d+\.\d+ --hash=sha256:[0-9a-f]{64}", reqs[0])
    docker = DOCKERFILE.read_text(encoding="utf-8")
    install = docker.split("-r /tmp/requirements/numpy.txt")[0].rsplit("RUN ", 1)[1]
    for flag in ("--only-binary=:all:", "--require-hashes", "--no-deps", "--target /opt/numpy"):
        assert flag in install
    assert "COPY --from=python-build /opt/numpy /opt/numpy" in docker


def test_numpy_only_reaches_klipper_through_the_option():
    assert 'export KHAOS_NUMPY_DIR="/opt/numpy"' in COMMON.read_text(encoding="utf-8")
    run = KLIPPER_RUN.read_text(encoding="utf-8")
    block = run.split('if [[ "$(khaos::option numpy false)" == "true" ]]; then')[1].split("fi\n")[0]
    assert 'export PYTHONPATH="${KHAOS_NUMPY_DIR}"' in block
    assert "unset PYTHONPATH" in block
    # The image itself never puts numpy on Python's path.
    assert all("PYTHONPATH" not in env for env in dockerfile_env())


def dockerfile_env() -> list[str]:
    """The ENV instructions of the Dockerfile, with continuation lines joined."""
    text = DOCKERFILE.read_text(encoding="utf-8").replace("\\\n", " ")
    return [line for line in text.splitlines() if line.startswith("ENV ")]


def test_guide_documents_the_calibration_commands():
    text = GUIDE.read_text(encoding="utf-8")
    for needle in (
        "ACCELEROMETER_QUERY",
        "SHAPER_CALIBRATE AXIS=X",
        "SHAPER_CALIBRATE AXIS=Y",
        "SAVE_CONFIG",
        "/dev/serial/by-id/usb-Klipper_rp2040_",
        "tools/build-firmware.sh fly-adxl345-usb",
        "[include profiles/ender3-v3-se/adxl.cfg]",
        "adxl_serial_device",
    ):
        assert needle in text, needle
