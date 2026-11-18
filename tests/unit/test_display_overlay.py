"""Consistency checks for the optional Ender 3 V3 SE display support.

The display code is fetched at build time from a pinned fork commit. These
tests keep the pin file, the firmware variant and the profile in step, so a
typo cannot silently drop a checksum or point a build at the wrong files.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "klipper" / "requirements" / "e3v3se-display.lock"
FW_BASE = ROOT / "firmware" / "ender3-v3-se" / "klipper.config"
FW_DISPLAY = ROOT / "firmware" / "ender3-v3-se-display"
PROFILE = ROOT / "klipper/rootfs/usr/share/klipper-haos/profiles/ender3-v3-se"


def parse_lock() -> tuple[str, str, dict[str, str]]:
    repo = commit = ""
    files: dict[str, str] = {}
    for line in LOCK.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        if line.startswith("repo "):
            repo = line[5:]
        elif line.startswith("commit "):
            commit = line[7:]
        else:
            m = re.fullmatch(r"([0-9a-f]{64})  ((?:klippy|src)/[A-Za-z0-9_./-]+)", line)
            assert m, f"malformed lock line: {line!r}"
            assert m.group(2) not in files, f"duplicate entry {m.group(2)}"
            files[m.group(2)] = m.group(1)
    return repo, commit, files


def config_lines(path: Path) -> list[str]:
    return [
        line for line in path.read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    ]


def test_lock_pins_https_repo_and_full_commit():
    repo, commit, _ = parse_lock()
    assert repo.startswith("https://github.com/")
    assert re.fullmatch(r"[0-9a-f]{40}", commit), "commit must be a full SHA-1"


def test_lock_lists_host_modules_and_firmware_sources():
    _, _, files = parse_lock()
    assert {
        "klippy/extras/e3v3se_display.py",
        "klippy/extras/TJC3224.py",
        "klippy/extras/printerInterface.py",
        "klippy/extras/serial_bridge.py",
    } <= files.keys()
    assert {
        "src/serial_bridge.c",
        "src/generic/serial_bridge_irq.c",
        "src/stm32/serial_bridge.c",
    } <= files.keys()
    # Only new extras and new firmware sources: nothing that would replace
    # upstream Klipper core files (the fetch script also refuses that).
    for path in files:
        assert path.startswith(("klippy/extras/", "src/")), path


def test_display_firmware_is_base_plus_serial_bridge():
    base = config_lines(FW_BASE)
    display = config_lines(FW_DISPLAY / "klipper.config")
    assert display[: len(base)] == base
    assert display[len(base):] == [
        "CONFIG_LOW_LEVEL_OPTIONS=y",
        # Only visible with low-level options; the same 8 MHz default the
        # base firmware gets implicitly.
        "CONFIG_STM32_CLOCK_REF_8M=y",
        "CONFIG_SERIAL_BRIDGE=y",
        "CONFIG_ENABLE_SERIAL_BRIDGE_USART2=y",
    ]


def test_overlay_names_existing_lock_and_patch():
    names = config_lines(FW_DISPLAY / "overlay")
    assert names == ["e3v3se-display"]
    assert (ROOT / "klipper" / "requirements" / f"{names[0]}.lock") == LOCK
    patch = ROOT / "firmware" / "overlays" / f"{names[0]}.patch"
    text = patch.read_text(encoding="utf-8")
    touched = re.findall(r"^\+\+\+ b/(\S+)", text, flags=re.M)
    assert sorted(touched) == ["src/Makefile", "src/stm32/Kconfig", "src/stm32/Makefile"]
    # Only additions: the overlay never removes upstream build rules.
    removed = [
        line for line in text.splitlines()
        if line.startswith("-") and not line.startswith("---")
    ]
    assert removed == []


def test_host_patches_only_touch_pinned_display_modules():
    _, _, files = parse_lock()
    patches = sorted((ROOT / "klipper" / "e3v3se-display" / "patches").glob("*.patch"))
    assert patches, "no display patches found"
    for patch in patches:
        text = patch.read_text(encoding="utf-8")
        assert "GPL-3.0 section 5a" in text.split("diff --git", 1)[0], patch.name
        for path in re.findall(r"^\+\+\+ b/(\S+)", text, flags=re.M):
            assert path in files and path.startswith("klippy/extras/"), (patch.name, path)
    # Applied after the verified files are fetched, and before compileall.
    dockerfile = (ROOT / "klipper" / "Dockerfile").read_text(encoding="utf-8")
    fetch = dockerfile.index("RUN sh /tmp/build/fetch-e3v3se-display.sh")
    apply = dockerfile.index("git -C /opt/klipper apply --check")
    assert fetch < apply < dockerfile.index("compileall -q /opt/klipper/klippy")


def test_mcu_error_handler_accepts_event_arguments():
    # Upstream: send_event("klippy:notify_mcu_error", msg, {"error": ...}).
    patch = ROOT / "klipper/e3v3se-display/patches/0001-notify-mcu-error-args.patch"
    added = [
        line[1:].strip() for line in patch.read_text(encoding="utf-8").splitlines()
        if line.startswith("+") and not line.startswith("+++")
    ]
    assert "def handle_mcu_error(self, *args):" in added
    assert "except Exception as e:" in added


def test_display_profile_is_optional_and_matches_firmware_bridge():
    text = (PROFILE / "display.cfg").read_text(encoding="utf-8")
    assert "[e3v3se_display]" in text
    # Not included by the main profile: users opt in from their printer.cfg.
    assert "display.cfg" not in (PROFILE / "printer.cfg").read_text(encoding="utf-8")
    # USART2 on PA2/PA3 is bridge config 3 in the firmware (USART2_PA3,PA2).
    assert "#config: 3" in text and "#tx_pin: PA2" in text and "#rx_pin: PA3" in text
