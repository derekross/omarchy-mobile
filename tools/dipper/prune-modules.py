#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Keep only the named modules and their dependencies in a staged module tree.

Reads modules.dep directly rather than asking modprobe: its -d/-b/-S flags are
easy to get wrong (-b is --use-blacklist, not a base directory), and a silent
mis-resolution deletes the whole tree.

    prune-modules.py <modules dir> <name> [name ...]
"""
import sys
from pathlib import Path


def basename(path: str) -> str:
    n = Path(path).name
    for suffix in (".ko.zst", ".ko.xz", ".ko.gz", ".ko"):
        if n.endswith(suffix):
            return n[: -len(suffix)]
    return n


def main() -> int:
    moddir = Path(sys.argv[1])
    wanted = {n.replace("-", "_") for n in sys.argv[2:]}
    dep = moddir / "modules.dep"
    if not dep.is_file():
        raise SystemExit(f"no {dep}")

    deps, by_name = {}, {}
    for line in dep.read_text().splitlines():
        if ":" not in line:
            continue
        target, rest = line.split(":", 1)
        target = target.strip()
        deps[target] = rest.split()
        by_name[basename(target).replace("-", "_")] = target

    missing = wanted - set(by_name)
    if missing:
        raise SystemExit(f"not in modules.dep: {', '.join(sorted(missing))}")

    keep, queue = set(), [by_name[n] for n in wanted]
    while queue:
        cur = queue.pop()
        if cur in keep:
            continue
        keep.add(cur)
        queue.extend(deps.get(cur, []))

    kept_paths = {(moddir / k).resolve() for k in keep}
    before = removed = 0
    for f in moddir.rglob("*"):
        if not f.is_file() or ".ko" not in f.name:
            continue
        before += 1
        if f.resolve() not in kept_paths:
            f.unlink()
            removed += 1
    for d in sorted(moddir.rglob("*"), key=lambda p: -len(p.parts)):
        if d.is_dir() and not any(d.iterdir()):
            d.rmdir()

    print(f"kept {len(keep)} of {before} modules: "
          f"{', '.join(sorted(basename(k) for k in keep))}")
    if len(keep) < len(wanted):
        raise SystemExit("fewer modules kept than asked for")
    return 0


if __name__ == "__main__":
    sys.exit(main())
