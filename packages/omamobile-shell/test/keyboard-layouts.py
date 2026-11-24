#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""squeekboard/keyboards/*.yaml as squeekboard 1.43.1 reads them (its
src/data/parsing.rs): known top-level keys, every button with one of text,
keysym, modifier or action and only known fields, keysyms that xkbcommon
knows (when libxkbcommon is there), every key in a view defined or a single
character, rows that line up, the action row in every view, its keys
sending the keysyms hypr/phone.lua binds, and the globe key sending
XF86MediaLanguageMenu (the shell's language sheet) instead of opening
squeekboard's popover (show_prefs). The terminal layout is ours by
hand and gets the strict checks; every other layout is made by
squeekboard/generate from squeekboard's own (its --check, also in test/all,
proves the rest of each file is upstream's, which may type a multi-character
name as text or name an outline it never defines). Run by test/all from the
package directory; exits 77 without PyYAML."""

import ctypes
import ctypes.util
import glob
import sys

try:
    import yaml
except ImportError:
    print("skip: no PyYAML")
    sys.exit(77)

ACTION_ROW = "Mic Paste Emoji Hide"
ACTION_KEYSYMS = {"Mic": "XF86Dictate", "Paste": "XF86Paste",
                  "Emoji": "XF86EmojiPicker", "Hide": "XF86Keyboard"}
GLOBE_KEYSYM = "XF86MediaLanguageMenu"
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


HAND_MADE = {"squeekboard/keyboards/terminal/us.yaml", "squeekboard/keyboards/terminal/us_wide.yaml",
             "squeekboard/keyboards/terminal/gr.yaml", "squeekboard/keyboards/terminal/gr_wide.yaml"}
GENERATED = "# squeekboard/generate (change the generator, not this file)."
paths = sorted(glob.glob("squeekboard/keyboards/**/*.yaml", recursive=True))
names = {p[len("squeekboard/keyboards/"):] for p in paths}
for must in ("us.yaml", "us_wide.yaml", "terminal/us.yaml", "terminal/us_wide.yaml",
             "de.yaml", "fr_wide.yaml", "jp+kana.yaml", "url/us.yaml", "terminal/de.yaml"):
    if must not in names:
        fail("squeekboard/keyboards", "carries %s" % must)
for skipped in ("emoji/", "number/", "pin/"):
    if any(n.startswith(skipped) for n in names):
        fail("squeekboard/keyboards", "no action row on the %s layouts" % skipped.rstrip("/"))
if len(paths) < 100:
    fail("squeekboard/keyboards", "every language's layout, found only %d" % len(paths))
for path in paths:
    strict = path in HAND_MADE
    with open(path) as f:
        text = f.read()
    if not text.startswith("# SPDX-License-Identifier: GPL-3.0-or-later\n"):
        fail(path, "carries squeekboard's licence")
    if not strict and GENERATED not in text:
        fail(path, "is made by squeekboard/generate")
    data = yaml.safe_load(text)
    extra = set(data) - {"outlines", "views", "buttons", "margins"}
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
        if strict and b.get("outline", "default") not in outlines:
            fail(path, "button %s: outline %r is defined" % (bname, b.get("outline")))
    if buttons.get("preferences", {}).get("keysym") != GLOBE_KEYSYM:
        fail(path, "the globe key (preferences) sends %s" % GLOBE_KEYSYM)
    if any(b.get("action") == "show_prefs" for b in buttons.values()):
        fail(path, "no key opens squeekboard's popover (show_prefs)")
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
                if strict and b is None and len(key) != 1:
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
    if strict:
        print("ok - %s" % path)
print("ok - %d layouts carry the action row" % len(paths))

# Greek: a row of accented vowels under the action row, one key each. Plain
# keys that type their letter (dead keys for the tonos do not work: squeekboard
# sends them as the characters, the app never composes them).
GREEK_ACCENT_ROWS = {"base": "ά έ ή ί ό ύ ώ ϊ ϋ ΐ ΰ", "upper": "Ά Έ Ή Ί Ό Ύ Ώ Ϊ Ϋ « »"}


def row_width(data, row):
    return sum(data["outlines"][(data["buttons"].get(k) or {}).get("outline", "default")]["width"] for k in row.split())


for rel in ("gr.yaml", "gr_wide.yaml"):
    path = "squeekboard/keyboards/" + rel
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    views, buttons = data["views"], data["buttons"]
    if "accent" not in data["outlines"]:
        fail(path, "the accent outline is defined")
        continue
    for view, letters in GREEK_ACCENT_ROWS.items():
        want = " ".join(c + "-accent" for c in letters.split())
        if len(views[view]) < 3 or views[view][0] != ACTION_ROW or views[view][1] != want:
            fail(path, "view %s: the second row, under the action row, is the accent row" % view)
        for c in letters.split():
            b = buttons.get(c + "-accent") or {}
            if b.get("text") != c or b.get("outline") != "accent":
                fail(path, "%s-accent types %s with the accent outline" % (c, c))
        if abs(row_width(data, want) - row_width(data, ACTION_ROW)) > 0.1:
            fail(path, "view %s: the accent row is as wide as the action row" % view)
    for vname, rows in views.items():
        if vname not in GREEK_ACCENT_ROWS and any("-accent" in r for r in rows):
            fail(path, "view %s has no accent row" % vname)
    if "accented" not in views or "show_accented" not in buttons:
        fail(path, "the accents view and its key are still there")
    if not any("show_accented" in r for r in views["base"]):
        fail(path, "the base view still opens the accents view")
print("ok - the Greek layouts have the accent row, 1 key per vowel, in the base and shift views")

# Greek in a terminal: terminal/gr and terminal/gr_wide, written by hand from
# terminal/us with the Greek letter rows, the terminal row kept in every view
for rel in ("terminal/gr.yaml", "terminal/gr_wide.yaml"):
    path = "squeekboard/keyboards/" + rel
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    views, buttons = data["views"], data["buttons"]
    base, upper = views["base"], views["upper"]
    if base[2:5] != ["; ς ε ρ τ υ θ ι ο π", ".-thin α σ δ φ γ η ξ κ λ --thin", "show_upper ζ χ ψ ω β ν μ BackSpace"]:
        fail(path, "the base view has the Greek letter rows, with . and - like terminal/us")
    if buttons.get(".-thin", {}).get("text") != "." or buttons.get("--thin", {}).get("text") != "-":
        fail(path, ".-thin types . and --thin types -")
    used = {k for rows in views.values() for r in rows for k in r.split()}
    for unused in sorted(k for k in buttons if k.endswith("-thin") and k not in used):
        fail(path, "the %s button is used" % unused)
    if views.get("accented", [])[2:6] != ["ά έ ή ί ϊ ΐ ό ύ ϋ ώ", "Ά Έ Ή Ί Ϊ Ό Ύ Ϋ Ώ show_accented",
                                          "Ϗ ϐ ϑ ϗ ϖ ΰ ϕ – BackSpace",
                                          "show_numbers preferences space show_actions Return"]:
        fail(path, "the accents view has the accented letters, the rare ones and the en dash")
    if upper[2:5] != [": ! Ε Ρ Τ Υ Θ Ι Ο Π", "Α Σ Δ Φ Γ Η Ξ Κ Λ show_accented", "show_upper Ζ Χ Ψ Ω Β Ν Μ BackSpace"]:
        fail(path, "the shift view has the Greek capitals")
    for vname, rows in views.items():
        if not rows[1].startswith("Esc-small Tab-small Ctrl Alt"):
            fail(path, "view %s keeps the terminal row under the action row" % vname)
    if "accented" not in views or buttons.get("show_accented", {}).get("action", {}).get("locking", {}).get("lock_view") != "accented":
        fail(path, "show_accented opens the accents view")
    if any(b.get("label") == "ABC" for b in buttons.values()):
        fail(path, "no key is still labelled ABC")
    if not any(b.get("label") == "ΑΒΓ" for b in buttons.values()):
        fail(path, "the way back to the letters is labelled ΑΒΓ")
    # foot sends Ctrl+ψ as CSI 27;5;<keysym>~, so Ctrl combos need Latin letters
    if views.get("latin", [])[2:5] != ["q w e r t y u i o p", ".-thin a s d f g h j k l --thin",
                                       "show_greek z x c v b n m BackSpace"]:
        fail(path, "the latin view has the Latin letters for Ctrl and Alt combos")
    lock = buttons.get("show_latin", {}).get("action", {}).get("locking", {})
    if (lock.get("lock_view"), lock.get("unlock_view")) != ("latin", "base"):
        fail(path, "the abc key latches the latin view and unlocks to base")
    # a second tap locks only when the same key is on the latin view too
    for vname in ("base", "latin"):
        if views.get(vname, ["", ""])[1].split()[5:6] != ["show_latin"]:
            fail(path, "the abc key is in the same place in the %s view" % vname)
    if not any(buttons.get(k, {}).get("text", k) == "~" for k in used):
        fail(path, "~ can still be typed in some view")
    if buttons.get("show_greek", {}).get("action", {}).get("set_view") != "base":
        fail(path, "show_greek goes back to the Greek letters")
print("ok - the Greek terminal layouts have the Greek letters, the terminal row and a Latin view")

for line in failures:
    print("not ok - " + line)
sys.exit(1 if failures else 0)
