#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""squeekboard/keyboards/*.yaml as squeekboard 1.43.1 reads them (its
src/data/parsing.rs): known top-level keys, every button with one of text,
keysym, modifier or action and only known fields, keysyms that xkbcommon
knows (when libxkbcommon is there), every key in a view defined or a single
character, rows that line up, and the action row in every view, its keys
sending the keysyms hypr/phone.lua binds. Run by test/all from the package
directory; exits 77 without PyYAML."""

import ctypes
import ctypes.util
import glob
import sys

try:
    import yaml
except ImportError:
    print("skip: no PyYAML")
    sys.exit(77)

ACTION_ROW = "Talk Ask Paste Emoji Hide"
ACTION_KEYSYMS = {"Talk": "XF86Dictate", "Ask": "XF86Assistant", "Paste": "XF86Paste",
                  "Emoji": "XF86EmojiPicker", "Hide": "XF86Keyboard"}
BUTTON_FIELDS = {"label", "icon", "outline", "text", "keysym", "action", "modifier"}
MODIFIERS = {"Control", "Shift", "Lock", "Alt", "Mod1", "Mod2", "Mod3", "Mod4", "Mod5"}

xkb = None
name = ctypes.util.find_library("xkbcommon")
if name:
    xkb = ctypes.CDLL(name)
    xkb.xkb_keysym_from_name.restype = ctypes.c_uint32
    xkb.xkb_keysym_from_name.argtypes = [ctypes.c_char_p, ctypes.c_int]

failures = []


def fail(path, what):
    failures.append("%s: %s" % (path, what))


def keysym_ok(sym):
    return xkb is None or xkb.xkb_keysym_from_name(sym.encode(), 0) != 0


paths = sorted(glob.glob("squeekboard/keyboards/**/*.yaml", recursive=True))
if len(paths) != 4:
    fail("squeekboard/keyboards", "four layouts (us, us_wide, terminal/us, terminal/us_wide), found %d" % len(paths))
for path in paths:
    with open(path) as f:
        text = f.read()
    if not text.startswith("# SPDX-License-Identifier: GPL-3.0-or-later\n"):
        fail(path, "carries squeekboard's licence")
    data = yaml.safe_load(text)
    extra = set(data) - {"outlines", "views", "buttons"}
    if extra:
        fail(path, "unknown top-level keys %s" % sorted(extra))
    outlines, views, buttons = data["outlines"], data["views"], data.get("buttons") or {}
    for oname, o in outlines.items():
        if set(o) != {"width", "height"}:
            fail(path, "outline %s has width and height only" % oname)
    for bname, b in buttons.items():
        if set(b) - BUTTON_FIELDS:
            fail(path, "button %s: unknown fields %s" % (bname, sorted(set(b) - BUTTON_FIELDS)))
        kinds = [k for k in ("text", "keysym", "modifier", "action") if k in b]
        if len(kinds) > 1:
            fail(path, "button %s has one of text, keysym, modifier, action (%s)" % (bname, kinds))
        if "keysym" in b and not keysym_ok(b["keysym"]):
            fail(path, "button %s: xkbcommon knows no keysym %r" % (bname, b["keysym"]))
        if "modifier" in b and b["modifier"] not in MODIFIERS:
            fail(path, "button %s: modifier %r" % (bname, b["modifier"]))
        if b.get("outline", "default") not in outlines:
            fail(path, "button %s: outline %r is defined" % (bname, b.get("outline")))
    for bname, sym in ACTION_KEYSYMS.items():
        if buttons.get(bname, {}).get("keysym") != sym:
            fail(path, "%s sends %s" % (bname, sym))
    widths = {}
    for vname, rows in views.items():
        if not rows or rows[0] != ACTION_ROW:
            fail(path, "view %s starts with the action row" % vname)
        for row in rows:
            total = 0.0
            for key in row.split():
                b = buttons.get(key)
                if b is None and len(key) != 1:
                    # squeekboard types a name with no button as text; only a
                    # single character is meant that way here
                    fail(path, "view %s: %r is a defined button" % (vname, key))
                outline = (b or {}).get("outline", "default")
                total += outlines.get(outline, outlines["default"])["width"]
            widths.setdefault(round(total, 1), []).append("%s: %s" % (vname, row))
    # squeekboard centres a narrower row (upstream's a-l row is one); the
    # action row and the terminal row are as wide as the widest, q-p
    widest = max(widths)
    for width, rows in widths.items():
        if width != widest and any(ACTION_ROW in r or "Esc-small" in r for r in rows):
            fail(path, "the action and terminal rows are %s wide: %s" % (widest, rows))
    print("ok - %s" % path)

for line in failures:
    print("not ok - " + line)
sys.exit(1 if failures else 0)
