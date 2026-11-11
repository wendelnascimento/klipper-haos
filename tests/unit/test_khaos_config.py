"""Unit tests for the option validation and config generation helper.

Run with:  python -m pytest tests/unit
(stdlib only; no container needed)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / "klipper" / "rootfs" / "usr" / "local" / "lib" / "klipper-haos"
SHARE = ROOT / "klipper" / "rootfs" / "usr" / "share" / "klipper-haos"
sys.path.insert(0, str(LIB))

import khaos_config as kc  # noqa: E402


# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    "value",
    [
        "/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0",
        "/dev/ttyUSB0",
        "/dev/ttyACM0",
        "/dev/serial/by-path/pci-0000:00:14.0-usb-0:2:1.0-port0",
    ],
)
def test_serial_accepts_device_paths(value):
    assert kc.validate_serial(value) == value


@pytest.mark.parametrize("value", [None, ""])
def test_serial_empty_is_none(value):
    assert kc.validate_serial(value) is None


@pytest.mark.parametrize(
    "value",
    [
        "ttyUSB0",
        "/etc/passwd",
        "/dev/ttyUSB0\n[gcode_macro EVIL]",
        "/dev/tty USB0",
        "/dev/../etc/shadow",
        "/dev/serial/..",
        123,
    ],
)
def test_serial_rejects_invalid_or_injection(value):
    with pytest.raises(kc.OptionsError):
        kc.validate_serial(value)


def test_trusted_networks_normalises_and_dedups():
    nets = kc.validate_trusted_networks(
        ["192.168.1.50/32", "192.168.1.7/24", "192.168.1.0/24", "fd00:1::/64"]
    )
    assert nets == ["192.168.1.50/32", "192.168.1.0/24", "fd00:1::/64"]


@pytest.mark.parametrize(
    "value",
    [
        "0.0.0.0/0",  # everything
        "10.0.0.0/8",  # too broad
        "::/0",
        "fd00::/16",  # too broad (v6)
        "172.30.32.0/23",  # Home Assistant internal network
        "172.30.32.1/32",  # Home Assistant Core
        "172.30.33.5/32",  # another app
        "172.30.0.0/16",  # contains the internal network
        "127.0.0.1/32",  # loopback
        "not-an-ip/24",
    ],
)
def test_trusted_networks_rejects_unsafe(value):
    with pytest.raises(kc.OptionsError):
        kc.validate_trusted_networks([value])


@pytest.mark.parametrize(
    "value", ["http://mainsail.local", "https://printer.example.com:8443", "http://*.lan.example"]
)
def test_cors_accepts(value):
    assert kc.validate_cors([value]) == [value]


@pytest.mark.parametrize(
    "value", ["*", "http://*", "http://example.*", "mainsail.local", "javascript:alert(1)", "http://a/b"]
)
def test_cors_rejects(value):
    with pytest.raises(kc.OptionsError):
        kc.validate_cors([value])


def test_parse_options_defaults():
    opts = kc.parse_options({})
    assert opts.serial_device is None
    assert opts.trusted_networks == []
    assert opts.cors_domains == []
    assert opts.export_api_key is False


def test_parse_options_rejects_bad_log_level():
    with pytest.raises(kc.OptionsError):
        kc.parse_options({"log_level": "chatty"})


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------


def _symlinks_supported(tmp_path) -> bool:
    try:
        (tmp_path / "_link").symlink_to(tmp_path, target_is_directory=True)
    except OSError:  # e.g. Windows without developer mode
        return False
    (tmp_path / "_link").unlink()
    return True


@pytest.fixture
def paths(tmp_path, request):
    if "generate" in request.node.name and not _symlinks_supported(tmp_path):
        pytest.skip("symlinks not supported on this host (the app runs on Linux)")
    mainsail = tmp_path / "mainsail-config"
    mainsail.mkdir()
    (mainsail / "client.cfg").write_text("[pause_resume]\n", encoding="utf-8")
    p = kc.Paths(
        config=tmp_path / "config",
        data=tmp_path / "data" / "printer_data",
        run=tmp_path / "run",
        share=SHARE,
        mainsail_config=mainsail,
    )
    p.config.mkdir()
    return p


def test_moonraker_trusts_only_proxies_by_default(paths):
    text = kc.render_moonraker_generated(kc.parse_options({}), paths)
    trusted = text.split("trusted_clients:")[1].split("\n\n")[0].split()
    assert trusted == ["127.0.0.1/32", "172.30.32.2/32"]
    assert "host: 127.0.0.1" in text
    assert "cors_domains" not in text


def test_moonraker_includes_user_networks_and_cors(paths):
    opts = kc.parse_options(
        {"trusted_networks": ["192.168.1.20/32"], "cors_domains": ["http://mainsail.local"]}
    )
    text = kc.render_moonraker_generated(opts, paths)
    assert "    192.168.1.20/32" in text
    assert "cors_domains:\n    http://mainsail.local" in text


def test_klipper_generated_with_and_without_serial(paths):
    with_serial = kc.render_klipper_generated(
        kc.parse_options({"serial_device": "/dev/ttyUSB0"}), paths
    )
    assert "[mcu]\n# From the app option 'serial_device'.\nserial: /dev/ttyUSB0" in with_serial
    without = kc.render_klipper_generated(kc.parse_options({}), paths)
    assert "\n[mcu]" not in without
    assert f"path: {paths.data / 'gcodes'}" in without


# --------------------------------------------------------------------------
# generate(): seeding and idempotency
# --------------------------------------------------------------------------


def test_generate_seeds_files_and_is_idempotent(paths):
    opts = kc.parse_options({"serial_device": "/dev/ttyUSB0"})
    msgs = kc.generate(opts, paths)
    assert any("starter printer.cfg" in m for m in msgs)
    assert (paths.config / "printer.cfg").is_file()
    assert (paths.config / "moonraker.conf").is_file()
    assert (paths.config / "profiles" / "ender3-v3-se" / "printer.cfg").is_file()
    assert (paths.managed / "dist" / "profiles" / "ender3-v3-se" / "printer.cfg").is_file()
    assert (paths.managed / "mainsail.cfg").is_file()
    assert (paths.data / "config").resolve() == paths.config.resolve()
    assert not any(m.startswith("WARNING") for m in msgs)

    # Second run: nothing to do, no warnings.
    assert kc.generate(opts, paths) == []


def test_generate_never_overwrites_user_files(paths):
    kc.generate(kc.parse_options({}), paths)
    printer = paths.config / "printer.cfg"
    profile = paths.config / "profiles" / "ender3-v3-se" / "printer.cfg"
    printer.write_text("[include klipper-haos/generated.cfg]\n# mine\n", encoding="utf-8")
    profile.write_text("# my tuned profile\n", encoding="utf-8")
    kc.generate(kc.parse_options({}), paths)
    assert printer.read_text(encoding="utf-8").endswith("# mine\n")
    assert profile.read_text(encoding="utf-8") == "# my tuned profile\n"


def test_generate_warns_when_include_missing(paths):
    (paths.config / "printer.cfg").write_text("[printer]\n", encoding="utf-8")
    msgs = kc.generate(kc.parse_options({}), paths)
    assert any(m.startswith("WARNING") and "printer.cfg" in m for m in msgs)


def test_generate_regenerates_on_option_change(paths):
    kc.generate(kc.parse_options({"serial_device": "/dev/ttyUSB0"}), paths)
    msgs = kc.generate(kc.parse_options({"serial_device": "/dev/ttyUSB1"}), paths)
    assert "Updated klipper-haos/generated.cfg" in msgs
    assert "serial: /dev/ttyUSB1" in (paths.managed / "generated.cfg").read_text()


def test_main_returns_error_for_invalid_options(tmp_path, capsys):
    options = tmp_path / "options.json"
    options.write_text(json.dumps({"trusted_networks": ["0.0.0.0/0"]}), encoding="utf-8")
    assert kc.main(["validate", "--options", str(options)]) == 1
    assert "too broad" in capsys.readouterr().err


# --------------------------------------------------------------------------
# Manifest consistency
# --------------------------------------------------------------------------


def test_manifest_schema_matches_generator_options():
    yaml = pytest.importorskip("yaml")
    manifest = yaml.safe_load((ROOT / "klipper" / "config.yaml").read_text(encoding="utf-8"))
    schema_keys = set(manifest["schema"])
    assert schema_keys == {
        "serial_device", "log_level", "trusted_networks", "cors_domains", "export_api_key",
    }
    # Every option with a default must also be in the schema.
    assert set(manifest["options"]) <= schema_keys
    translations = yaml.safe_load(
        (ROOT / "klipper" / "translations" / "en.yaml").read_text(encoding="utf-8")
    )
    assert set(translations["configuration"]) == schema_keys
    # Security-relevant manifest settings.
    assert manifest["ports"]["7125/tcp"] is None
    assert manifest["init"] is False
    assert manifest.get("full_access", False) is False
    assert not manifest.get("privileged")
    assert manifest.get("host_network", False) is False
