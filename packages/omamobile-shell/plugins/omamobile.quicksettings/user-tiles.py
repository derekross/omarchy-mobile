#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""The user's own quick-settings tiles (TILES.md).

A tile is one JSON file, ~/.config/omamobile/tiles/<id>.json, whose commands
say what the tile shows and does. Quick settings runs this helper with
`python3 -I` and never runs a tile's commands itself:

  user-tiles.py list            JSON: every tile file, read and its commands run
  user-tiles.py run ID [VALUE]  a tap: the tile's choose command with VALUE
                                (one of its choices), or its action; exits
                                with the command's code (124 on a timeout)

Every command is an argv array run as the session user, with no shell unless
the array itself starts one, and with a timeout. A chosen value only ever
replaces a "{}" element of the choose array, and only once the choices
command has listed it. A broken file is listed with an `error` and never
stops the others.
"""
import concurrent.futures
import json
import os
import re
import signal
import subprocess
import sys
import unicodedata

ID_RE = re.compile(r"^[a-z0-9-]+$")
FIELDS = ("label", "icon", "status", "active", "choices", "choose", "action")
DEFAULT_ICON = "\U000F0D2A"  # nf-md-tune_variant
PROBE_TIMEOUT = 3    # status, active, choices
RUN_TIMEOUT = 15     # choose, action
MAX_FILE = 64 * 1024
MAX_ARGS = 64
MAX_ARG = 4096
MAX_OUTPUT = 64 * 1024
MAX_CHOICES = 200
MAX_LABEL = 60
MAX_STATUS = 120
MAX_VALUE = 256


def tiles_dir():
    # HOME, not XDG_CONFIG_HOME: the same place QuickSettings.qml keeps
    # quicksettings.json.
    return os.path.join(os.path.expanduser("~"), ".config", "omamobile", "tiles")


class Invalid(Exception):
    pass


def check_argv(spec, name):
    value = spec.get(name)
    if value is None:
        return None
    if not isinstance(value, list) or not value:
        raise Invalid(f"{name} must be a list of strings (a command and its arguments)")
    if len(value) > MAX_ARGS:
        raise Invalid(f"{name} has more than {MAX_ARGS} arguments")
    for arg in value:
        if not isinstance(arg, str):
            raise Invalid(f"{name} must be a list of strings (a command and its arguments)")
        if "\0" in arg or len(arg) > MAX_ARG:
            raise Invalid(f"{name} has an argument that can't be used")
    if not value[0]:
        raise Invalid(f"{name} names no command")
    return list(value)


# Control characters, line and paragraph separators and lone surrogates.
# Not "not printable": Nerd Font glyphs are private-use characters, which
# Python counts as unprintable.
BAD_CATEGORIES = ("Cc", "Cs", "Zl", "Zp")


def plain(text):
    return not any(unicodedata.category(ch) in BAD_CATEGORIES for ch in text)


def one_line(text, limit):
    """Text on one line with no control characters, cut to `limit`."""
    text = "".join(" " if unicodedata.category(ch) in BAD_CATEGORIES else ch for ch in str(text))
    return " ".join(text.split())[:limit]


def validate(spec):
    """A tile file's object -> its clean form; raises Invalid with the reason."""
    if not isinstance(spec, dict):
        raise Invalid("the file holds no JSON object")
    unknown = sorted(key for key in spec if key not in FIELDS)
    if unknown:
        raise Invalid("unknown field " + ", ".join(unknown))
    label = spec.get("label")
    if not isinstance(label, str) or not one_line(label, MAX_LABEL):
        raise Invalid("label is missing")
    icon = spec.get("icon", DEFAULT_ICON)
    if not isinstance(icon, str) or not 1 <= len(icon) <= 2 or not icon.strip() or not plain(icon):
        raise Invalid("icon must be one glyph")
    tile = {
        "label": one_line(label, MAX_LABEL),
        "icon": icon,
        "status": check_argv(spec, "status"),
        "active": check_argv(spec, "active"),
        "choices": check_argv(spec, "choices"),
        "choose": check_argv(spec, "choose"),
        "action": check_argv(spec, "action"),
    }
    if tile["choices"] and not tile["choose"]:
        raise Invalid("choices needs a choose command")
    if tile["choose"] and not tile["choices"]:
        raise Invalid("choose needs a choices command")
    if tile["choose"] and "{}" not in tile["choose"]:
        raise Invalid('choose has no "{}" for the chosen value')
    if tile["choices"] and tile["action"]:
        raise Invalid("a tile has choices or an action, not both")
    return tile


def load(path):
    """One tile file -> its clean form; raises Invalid with the reason."""
    try:
        if not os.path.isfile(path):
            raise Invalid("not a file")
        if os.path.getsize(path) > MAX_FILE:
            raise Invalid("the file is too large")
        with open(path, encoding="utf-8") as f:
            spec = json.load(f)
    except Invalid:
        raise
    except UnicodeDecodeError:
        raise Invalid("the file is not UTF-8")
    except OSError as error:
        raise Invalid("can't read the file: " + (error.strerror or str(error)))
    except ValueError as error:
        raise Invalid(f"not valid JSON (line {getattr(error, 'lineno', '?')})")
    return validate(spec)


def tile_ids(directory):
    try:
        names = os.listdir(directory)
    except OSError:
        return []
    ids = []
    for name in names:
        if name.startswith(".") or not name.endswith(".json"):
            continue
        tile_id = name[:-len(".json")]
        if ID_RE.match(tile_id):
            ids.append(tile_id)
    return sorted(ids)


def run(argv, timeout, capture):
    """Run argv in its own process group with no stdin; kill the whole group
    on a timeout, so a shell's children can't hold it (or its output) open.
    Returns (exit code, stdout bytes); 124 on a timeout, 127 when the
    command can't start."""
    try:
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE if capture else None,
                                stderr=subprocess.DEVNULL if capture else None,
                                cwd=os.path.expanduser("~"), start_new_session=True)
    except OSError:
        return 127, b""
    try:
        out, _ = proc.communicate(timeout=timeout)
        return proc.returncode, (out or b"")[:MAX_OUTPUT]
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.communicate()
        return 124, b""


def parse_choices(data):
    """`value<TAB>label` lines -> [{value, label}]; a line without a label
    is its own label. Empty, unprintable and repeated values are skipped."""
    out = []
    seen = set()
    for line in data.decode("utf-8", "replace").splitlines():
        value, _, label = line.partition("\t")
        value = value.strip()
        if not value or len(value) > MAX_VALUE or not plain(value) or value in seen:
            continue
        seen.add(value)
        out.append({"value": value, "label": one_line(label, MAX_LABEL) or one_line(value, MAX_LABEL)})
        if len(out) >= MAX_CHOICES:
            break
    return out


def first_line(data):
    lines = data.decode("utf-8", "replace").splitlines()
    return one_line(lines[0], MAX_STATUS) if lines else ""


def broken(tile_id, reason):
    return {"id": tile_id, "label": tile_id, "icon": DEFAULT_ICON, "status": "", "active": False,
            "choices": [], "hasChoices": False, "hasAction": False, "error": reason}


def cmd_list():
    directory = tiles_dir()
    loaded = []
    for tile_id in tile_ids(directory):
        try:
            loaded.append((tile_id, load(os.path.join(directory, tile_id + ".json")), None))
        except Invalid as error:
            loaded.append((tile_id, None, str(error)))
    # Every tile's commands at once, so the list takes one timeout at most.
    tiles = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=32) as pool:
        jobs = [{name: pool.submit(run, tile[name], PROBE_TIMEOUT, True)
                 for name in ("status", "active", "choices") if tile[name]} if tile else {}
                for _, tile, _ in loaded]
        for (tile_id, tile, error), job in zip(loaded, jobs):
            if error:
                tiles.append(broken(tile_id, error))
                continue
            status, active, choices = "", False, []
            if "status" in job:
                code, out = job["status"].result()
                status = first_line(out) if code == 0 else ""
            if "active" in job:
                active = job["active"].result()[0] == 0
            if "choices" in job:
                code, out = job["choices"].result()
                choices = parse_choices(out) if code == 0 else []
            tiles.append({"id": tile_id, "label": tile["label"], "icon": tile["icon"], "status": status,
                          "active": active, "choices": choices, "hasChoices": bool(tile["choices"]),
                          "hasAction": bool(tile["action"]), "error": ""})
    json.dump(tiles, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def cmd_run(tile_id, value):
    if not ID_RE.match(tile_id):
        print(f"user-tiles: not a tile id: {tile_id}", file=sys.stderr)
        return 2
    try:
        tile = load(os.path.join(tiles_dir(), tile_id + ".json"))
    except Invalid as error:
        print(f"user-tiles: {tile_id}: {error}", file=sys.stderr)
        return 2
    if tile["choices"]:
        if value is None:
            print(f"user-tiles: {tile_id}: choose one of its choices", file=sys.stderr)
            return 2
        code, out = run(tile["choices"], PROBE_TIMEOUT, True)
        listed = [choice["value"] for choice in parse_choices(out)] if code == 0 else []
        if value not in listed:
            print(f"user-tiles: {tile_id}: {value!r} is not one of its choices", file=sys.stderr)
            return 2
        argv = [value if arg == "{}" else arg for arg in tile["choose"]]
    elif tile["action"]:
        if value is not None:
            print(f"user-tiles: {tile_id}: has no choices", file=sys.stderr)
            return 2
        argv = tile["action"]
    else:
        print(f"user-tiles: {tile_id}: has nothing to run", file=sys.stderr)
        return 2
    return run(argv, RUN_TIMEOUT, False)[0]


def main(argv):
    if len(argv) == 1 and argv[0] == "list":
        return cmd_list()
    if len(argv) in (2, 3) and argv[0] == "run":
        return cmd_run(argv[1], argv[2] if len(argv) == 3 else None)
    print("Usage:\n" + __doc__.strip().split("\n\n")[2], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
