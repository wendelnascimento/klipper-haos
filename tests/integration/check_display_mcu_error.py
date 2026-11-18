"""Regression check for the bundled Ender 3 V3 SE display module.

Runs inside the app image with Klipper's own Python (see run.sh). Upstream
Klipper sends "klippy:notify_mcu_error" with (msg, details); the fork's
handler took no arguments, so an MCU error during connect became a TypeError
and Klipper shut down ("Unhandled exception during run"). This drives the
patched handler through Klipper's real Printer.send_event.
"""

import sys

sys.path.insert(0, "/opt/klipper/klippy")

import klippy  # noqa: E402
from extras import e3v3se_display  # noqa: E402

EVENT = "klippy:notify_mcu_error"
MSG = "MCU error during connect"
DETAILS = {"error": "Unable to connect"}


class FakePrinter:
    """Only the Printer parts the handler path uses, with Klipper's own
    event registration and dispatch."""

    register_event_handler = klippy.Printer.register_event_handler
    send_event = klippy.Printer.send_event

    def __init__(self):
        self.event_handlers = {}

    def get_state_message(self):
        return MSG, "error"


def make_display(printer, show_popup):
    display = e3v3se_display.E3v3seDisplay.__new__(e3v3se_display.E3v3seDisplay)
    display.printer = printer
    display.show_popup = show_popup
    printer.register_event_handler(EVENT, display.handle_mcu_error)
    return display


# 1. The call Klipper's _connect() makes: shows the message, does not raise.
shown = []
printer = FakePrinter()
display = make_display(printer, shown.append)
printer.send_event(EVENT, MSG, DETAILS)
assert shown == [MSG], shown

# 2. Without arguments it falls back to the message text, not the tuple.
shown.clear()
display.handle_mcu_error()
assert shown == [MSG], shown


# 3. A failing display (e.g. no serial bridge yet) must not raise into Klipper.
def broken_popup(message):
    raise RuntimeError("display not reachable")


printer = FakePrinter()
make_display(printer, broken_popup)
printer.send_event(EVENT, MSG, DETAILS)

print("ok")
