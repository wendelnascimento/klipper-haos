#!/usr/bin/env python3
"""Minimal JSON-RPC client for Moonraker's Unix domain socket.

The socket lives inside the container only, so it is never reachable from
the network. Used by the app's own maintenance hooks (API key export,
pre-backup database snapshot). Never prints secrets unless asked to write
them to a file.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import time
from pathlib import Path

ETX = b"\x03"


def call(sock_path: str, method: str, params: dict | None = None,
         timeout: float = 10.0) -> object:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(sock_path)
        request = {"jsonrpc": "2.0", "method": method, "id": 1}
        if params:
            request["params"] = params
        sock.sendall(json.dumps(request).encode() + ETX)
        buf = b""
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                raise ConnectionError("Moonraker closed the connection")
            buf += chunk
            while ETX in buf:
                raw, buf = buf.split(ETX, 1)
                msg = json.loads(raw)
                if msg.get("id") != 1:
                    continue  # notification, ignore
                if "error" in msg:
                    raise RuntimeError(msg["error"].get("message", msg["error"]))
                return msg.get("result")


def wait_for_socket(sock_path: str, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            call(sock_path, "server.info", timeout=2.0)
            return True
        except (OSError, ConnectionError, RuntimeError, ValueError):
            time.sleep(1.0)
    return False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--socket", default="/data/printer_data/comms/moonraker.sock")
    parser.add_argument("--wait", type=float, default=0.0,
                        help="seconds to wait for Moonraker to come up")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("info")
    key = sub.add_parser("export-api-key")
    key.add_argument("path")
    sub.add_parser("backup-database")
    args = parser.parse_args(argv)

    if args.wait and not wait_for_socket(args.socket, args.wait):
        print("ERROR: Moonraker did not become ready", file=sys.stderr)
        return 2

    try:
        if args.command == "info":
            print(json.dumps(call(args.socket, "server.info"), indent=2))
        elif args.command == "export-api-key":
            api_key = call(args.socket, "access.get_api_key")
            if not isinstance(api_key, str) or not api_key:
                raise RuntimeError("unexpected API key response")
            path = Path(args.path)
            tmp = path.with_name(path.name + ".tmp")
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(api_key + "\n")
            os.replace(tmp, path)
            print(f"API key written to {path}")
        elif args.command == "backup-database":
            result = call(args.socket, "server.database.post_backup",
                          {"filename": "klipper-haos-pre-backup.db"},
                          timeout=120.0)
            print(f"Database snapshot: {result}")
    except (OSError, ConnectionError, RuntimeError, ValueError) as err:
        print(f"ERROR: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
