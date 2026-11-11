#!/usr/bin/env python3
"""Static checks for the s6-overlay service tree and security-relevant files.

Checks:
  * every service has a valid 'type' and the files that type requires
  * dependencies and bundle contents refer to services that exist
  * service scripts have a shebang and LF line endings
  * the dependency graph has no cycles
  * no obvious secrets are committed
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
S6 = ROOT / "klipper" / "rootfs" / "etc" / "s6-overlay"
BASE_SERVICES = {"base", "legacy-cont-init", "legacy-services", "fix-attrs"}

errors: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def check_script(path: Path) -> None:
    data = path.read_bytes()
    if b"\r\n" in data:
        err(f"{path.relative_to(ROOT)}: CRLF line endings")
    if not data.startswith(b"#!"):
        err(f"{path.relative_to(ROOT)}: missing shebang")


services: dict[str, str] = {}
for svc in sorted((S6 / "s6-rc.d").iterdir()):
    type_file = svc / "type"
    if not type_file.is_file():
        err(f"{svc.name}: missing 'type'")
        continue
    stype = type_file.read_text().strip()
    services[svc.name] = stype
    if stype == "longrun":
        if not (svc / "run").is_file():
            err(f"{svc.name}: longrun without 'run'")
        else:
            check_script(svc / "run")
        if (svc / "finish").is_file():
            check_script(svc / "finish")
    elif stype == "oneshot":
        up = svc / "up"
        if not up.is_file():
            err(f"{svc.name}: oneshot without 'up'")
        else:
            target = up.read_text().strip()
            script = ROOT / "klipper" / "rootfs" / target.lstrip("/")
            if not script.is_file():
                err(f"{svc.name}: 'up' points to missing {target}")
            else:
                check_script(script)
    else:
        err(f"{svc.name}: unsupported type {stype!r}")

known = set(services) | BASE_SERVICES
graph: dict[str, set[str]] = {}
for name in services:
    deps_dir = S6 / "s6-rc.d" / name / "dependencies.d"
    deps = {d.name for d in deps_dir.iterdir()} if deps_dir.is_dir() else set()
    for dep in deps - known:
        err(f"{name}: depends on unknown service {dep!r}")
    graph[name] = deps & set(services)

bundle = S6 / "user-bundles.d" / "user"
if (bundle / "type").read_text().strip() != "bundle":
    err("user bundle: type must be 'bundle'")
contents = {p.name for p in (bundle / "contents.d").iterdir()}
for name in contents - set(services):
    err(f"user bundle: unknown service {name!r}")
for name in set(services) - contents:
    err(f"service {name!r} is not in the user bundle (never started)")

# Cycle detection
visiting: set[str] = set()
done: set[str] = set()


def visit(node: str, path: list[str]) -> None:
    if node in done:
        return
    if node in visiting:
        err("dependency cycle: " + " -> ".join(path + [node]))
        return
    visiting.add(node)
    for dep in graph.get(node, ()):
        visit(dep, path + [node])
    visiting.discard(node)
    done.add(node)


for name in graph:
    visit(name, [])

# Shared scripts
for script in [
    *(ROOT / "klipper" / "rootfs" / "usr" / "local" / "bin").iterdir(),
    *(S6 / "scripts").iterdir(),
]:
    check_script(script)

# Secrets: long hex strings or token-like assignments in tracked text files.
SECRET_RE = re.compile(
    r"(api[_-]?key|token|password|secret)\s*[:=]\s*['\"]?[A-Za-z0-9+/_-]{20,}", re.I
)
for path in ROOT.rglob("*"):
    if not path.is_file() or ".git" in path.parts or "out" in path.parts:
        continue
    if path.suffix in {".png", ".jpg", ".bin", ".dict"}:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for match in SECRET_RE.finditer(text):
        err(f"{path.relative_to(ROOT)}: possible secret: {match.group(0)[:40]}...")

if errors:
    print("s6/static checks FAILED:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)
print(f"s6/static checks passed ({len(services)} services)")
