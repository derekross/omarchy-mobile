#!/bin/bash
# SPDX-License-Identifier: MIT
# Keyboard layouts for the Settings app. The hardware keyboard's layouts live in Omarchy's user file
# ~/.config/hypr/input.lua (kb_layout, kb_variant); the on-screen keyboard's list is gsettings
# org.gnome.desktop.input-sources sources, and a layouts change adds new ones there too.
# The switch key is a Hyprland bind, not an xkb grp: option (on the phone, Hyprland 0.57.0, 2026-11-17, a
# grp: option never switched; a bind running switchxkblayout did). It is kept in a generated file,
# ~/.config/hypr/omamobile-keyboard.lua, that phone.lua loads: its "-- switch-key: NAME" line is the
# choice. Every switch key is bound once (both key orders, on every keyboard but squeekboard's, to
# `omamobile-keyboard-switch next`) and only the chosen one is enabled; Alt+Shift and Ctrl+Shift fire
# on release. With no file, phone.lua binds the same set with Alt+Shift on, so "get" reports
# alt_shift then. The same Lua is applied live with `hyprctl eval`. Any grp: option left in
# kb_options from earlier versions is removed on the next set.
# Prints one line of JSON.
#   keyboard.sh get                         {"layouts":[{"layout":"us","variant":""}],"switchKey":"alt_shift","active":0}
#   keyboard.sh list                        {"layouts":[{"layout":"us","name":"English (US)"}],"switchKeys":[...]}
#   keyboard.sh set layouts us,gr[:variant] 1 to 4 layouts, each a name (and variant) in the xkb rules list
#   keyboard.sh set switch-key NAME         alt_shift, ctrl_shift, caps or none (default alt_shift)
# "active" is the index Hyprland reports for the main real keyboard, or null without one. Real = not
# hl-virtual-keyboard* and not a pseudo-keyboard (consumer-control, power-button, video-bus, radio-control,
# gpio-keys); main = the real one Hyprland marks main, else the first real one with more than one layout,
# else the first real one (the same rule as omamobile-keyboard-switch and the bar). A layouts list whose
# first entry is not a Latin layout is refused (passwords on the lock screen are typed in layout 1).
# input.lua is edited in place: only the last live kb_layout, kb_variant and kb_options strings inside an
# `input = { }` table change (per-device blocks and variables are left alone), comments and every other
# option but grp: (grp_led:caps, compose:...) stay, a copy of the old
# file goes to input.lua.bak-omamobile first, and the write is dropped if the file changed meanwhile.
# A file with no live kb_layout (Omarchy's stock one has them only in comments) gets one hl.config() block
# appended at the end; get then reports Hyprland's effective values.
# A symlinked input.lua stays a link: its target is written. gsettings is written first, then the change
# is applied live without `hyprctl reload` (a reload sets the configured refresh rate again and re-runs
# phone.lua). gsettings is merged, not replaced: the
# OSK's own languages and its current (first) entry stay; new hardware layouts are added at the end
# (only ones squeekboard has a layout file for, when that directory exists); removed ones are dropped.
# A switch-key change does not touch gsettings. Switching layouts never writes gsettings either (that made
# squeekboard send its keymap again, and the app got Latin letters while Hyprland said Greek).
# Test hooks (nothing in the environment sets them): OMAMOBILE_KBD_INPUT is the input.lua path,
# OMAMOBILE_KBD_BINDS the generated bind file,
# OMAMOBILE_KBD_RULES the xkb rules .lst file, OMAMOBILE_KEYBOARDS_DIR squeekboard's layout files; the test puts a fake hyprctl and gsettings first on PATH.
set -euo pipefail
set +x
fail() { printf '{"error":"%s"}\n' "$1"; exit 2; }

find_hypr() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && return 0
  local d best='' sig
  for d in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/; do
    [[ -S $d.socket.sock ]] || continue
    if [[ -z $best || $d.socket.sock -nt $best.socket.sock ]]; then best=$d; fi
  done
  [[ -n $best ]] || return 0
  sig=${best%/}; sig=${sig##*/}
  export HYPRLAND_INSTANCE_SIGNATURE=$sig
}
find_hypr

input=${OMAMOBILE_KBD_INPUT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/input.lua}
rules=${OMAMOBILE_KBD_RULES:-}
if [[ -z $rules ]]; then
  for f in /usr/share/X11/xkb/rules/base.lst /usr/share/X11/xkb/rules/evdev.lst; do
    [[ -r $f ]] && { rules=$f; break; }
  done
fi
binds=${OMAMOBILE_KBD_BINDS:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/omamobile-keyboard.lua}
export KBD_INPUT=$input KBD_RULES=$rules KBD_BINDS=$binds

/usr/bin/python3 -I - "$@" <<'PY' || exit 2
import fcntl, hashlib, json, os, re, shutil, subprocess, sys

KEYS = ("kb_layout", "kb_variant", "kb_options")
NAME_RE = re.compile(r"[a-z][a-z0-9_-]{0,31}")
# Switch keys: each name binds these key strings (both orders, so either key can go down first).
# Modifier pairs fire on RELEASE and do not consume the key (release = true, non_consuming = true), so
# Alt+Shift+Tab, Ctrl+Shift+C/V and the like reach their own bind or the app and do not switch: in
# Hyprland's KeybindManager (a 0.5x source copy, version not identified) a release bind is shadowed once
# another key is pressed and released or another bind fires while it is held, and the mods are matched
# at release time, when the released modifier is still in them (as in the documented
# `bindr = SUPER, SUPER_L`), hence "ALT + SHIFT + SHIFT_L". UNVERIFIED on the phone (0.57.0): that the
# release binds fire for a lone Alt+Shift and stay quiet for Alt+Shift+Tab; ctrl_shift and caps.
# "caps" binds the key by its code (66) on press, as compose:caps may give it another keysym.
SWITCH_KEYS = {"alt_shift": ("ALT + SHIFT + SHIFT_L", "SHIFT + ALT + ALT_L"),
               "ctrl_shift": ("CTRL + SHIFT + SHIFT_L", "SHIFT + CTRL + CTRL_L"),
               "caps": ("code:66",), "none": ()}
RELEASE = {"alt_shift": True, "ctrl_shift": True, "caps": False, "none": False}
SWITCH_NAMES = [("alt_shift", "Alt+Shift"), ("ctrl_shift", "Ctrl+Shift"), ("caps", "Caps Lock"), ("none", "None")]
DESC = "Keyboard: next layout"
DEFAULT_KEY = "alt_shift"
BINDS = os.environ["KBD_BINDS"]
OPTION_RE = re.compile(r"[a-z0-9_]{1,32}:[A-Za-z0-9_]{1,48}")
LATIN = {"us", "gb", "de", "fr", "es", "it", "pt", "nl", "be", "ch", "at", "se", "no", "dk", "fi",
         "is", "ie", "pl", "cz", "sk", "hu", "ro", "hr", "si", "ee", "lv", "lt", "tr", "br", "latam",
         "ca", "au", "nz", "za", "epo"}
MAX = 4
path = os.path.realpath(os.environ["KBD_INPUT"])  # write a symlink's target, keep the link
KEYBOARDS = os.environ.get("OMAMOBILE_KEYBOARDS_DIR", "/usr/share/omamobile/squeekboard/keyboards")
PSEUDO_RE = re.compile(r"hl-virtual-keyboard|.*(consumer-control|power-button|video-bus|radio-control|gpio-keys)")

def out(obj):
    print(json.dumps(obj, separators=(",", ":")))

def fail(msg):
    out({"error": msg})
    sys.exit(2)

# Lua tokens, enough to see live `key = "string"` assignments: comments and long strings are skipped,
# so an assignment inside `-- ...` or `--[[ ... ]]` is invisible (the same rules as the desktop plugin).
def tokens(text):
    i, n = 0, len(text)
    while i < n:
        m = re.compile(r"--\[(=*)\[").match(text, i)
        if m:
            e = text.find("]" + m.group(1) + "]", m.end())
            i = n if e < 0 else e + len(m.group(1)) + 2
            continue
        if text.startswith("--", i):
            e = text.find("\n", i)
            i = n if e < 0 else e
            continue
        c = text[i]
        if c.isspace():
            i += 1
            continue
        if c in "\"'":
            m = re.compile(r"(?:\\.|[^\\\n%s])*" % c, re.S).match(text, i + 1)
            e = m.end()
            closed = e < n and text[e] == c
            yield ("string", text[i + 1:e], i, e + 1 if closed else e, not closed)
            i = e + 1 if closed else e
            continue
        m = re.compile(r"\[(=*)\[").match(text, i)
        if m:
            e = text.find("]" + m.group(1) + "]", m.end())
            stop = n if e < 0 else e + len(m.group(1)) + 2
            yield ("long", "", i, stop, True)
            i = stop
            continue
        m = re.compile(r"[A-Za-z_][A-Za-z0-9_]*").match(text, i)
        if m:
            yield ("ident", m.group(0), i, m.end(), False)
            i = m.end()
            continue
        if text.startswith("==", i):
            yield ("other", "==", i, i + 2, False)
            i += 2
            continue
        yield ("eq" if c == "=" else "other", c, i, i + 1, False)
        i += 1

# The last live assignment of each key wins, as a later hl.config() overrides an earlier one. Only
# assignments whose innermost table was opened by `input = {` count: a per-device block or a variable
# with the same key name is not the global setting.
def scan(text):
    t = list(tokens(text))
    found, stack = {}, []
    for i, a in enumerate(t):
        if a[0] == "other" and a[1] == "{":
            stack.append(i >= 2 and t[i - 2][:2] == ("ident", "input") and t[i - 1][0] == "eq")
        elif a[0] == "other" and a[1] == "}":
            if stack:
                stack.pop()
        elif (a[0] == "ident" and a[1] in KEYS and stack and stack[-1] and i + 2 < len(t)
              and t[i + 1][0] == "eq" and t[i + 2][0] in ("string", "long")):
            found[a[1]] = t[i + 2]
    return found

def fields(raw):
    return [x.strip() for x in raw.split(",")] if raw.strip() else []

def parse(text):
    found = scan(text)
    vals = {}
    for k, tok in found.items():
        if tok[0] == "long" or tok[4]:
            fail("input.lua: %s is not a plain string" % k)
        if re.search(r"[\x00-\x1f\x7f\\\"]", tok[1]) or len(tok[1]) > 512:
            fail("input.lua: %s has characters this editor does not handle" % k)
        vals[k] = tok[1]
    layouts = fields(vals.get("kb_layout", ""))
    variants = fields(vals.get("kb_variant", ""))
    variants = (variants + [""] * len(layouts))[:len(layouts)]
    options = [o for o in fields(vals.get("kb_options", "")) if o]
    return found, layouts, variants, options

def read_file():
    try:
        with open(path, "rb") as f:
            data = f.read(1 << 20)
            st = os.fstat(f.fileno())
    except FileNotFoundError:
        fail("input.lua is missing")
    except OSError:
        fail("cannot read input.lua")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        fail("input.lua is not UTF-8")
    return data, st, text

def run(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None

def active():
    s = run(["hyprctl", "-j", "devices"])
    try:
        kbs = json.loads(s)["keyboards"]
    except (TypeError, ValueError, KeyError):
        return None
    real = [k for k in kbs if not PSEUDO_RE.match(str(k.get("name", "")))]
    multi = [k for k in real if len([l for l in str(k.get("layout", "")).split(",") if l]) > 1]
    pick = [k for k in real if k.get("main")] or multi or real
    if not pick:
        return None
    i = pick[0].get("active_layout_index")
    return i if isinstance(i, int) and i >= 0 else None

def stored_key():
    """The file's choice; with no file, phone.lua binds the default (Alt+Shift), so that is the truth."""
    try:
        with open(BINDS, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.fullmatch(r"-- switch-key: ([a-z_]+)\s*", line)
                if m and m.group(1) in SWITCH_KEYS:
                    return m.group(1)
    except OSError:
        pass
    return DEFAULT_KEY

# The binds as Lua, for the file and for hyprctl eval. Every switch key is bound once per Lua state
# (handles kept in the global omamobile_kbd_binds; phone.lua's default for a phone with no file is the
# same code) and only the chosen one is enabled. A disabled bind is skipped by Hyprland and consumes
# nothing. Nothing is ever hl.unbind-ed on a key string (that would take a user's own bind on the key
# too) or removed by handle (Superwhisper's generated config notes that removing a key's press and
# release handles one by one crashed Hyprland 0.56; set_enabled is what it uses live). The binds stay
# with one layout: omamobile-keyboard-switch does nothing then.
def bind_lua(name):
    lua = "if not omamobile_kbd_binds then\n  omamobile_kbd_binds = {}\n"
    for n, keys in SWITCH_KEYS.items():
        for k in keys:
            lua += ('  omamobile_kbd_binds[#omamobile_kbd_binds + 1] = { "%s", hl.bind("%s", '
                    'hl.dsp.exec_cmd("omamobile-keyboard-switch next"), { description = "%s", '
                    'device = { inclusive = false, list = { "hl-virtual-keyboard-squeekboard" } }%s }) }\n'
                    % (n, k, DESC, ", release = true, non_consuming = true" if RELEASE[n] else ""))
    lua += ('end\n'
            'for _, b in ipairs(omamobile_kbd_binds) do pcall(function() b[2]:set_enabled(b[1] == "%s") end) end\n'
            % name)
    return lua

def write_binds(name):
    text = ("-- Written by Omarchy Mobile Settings (Keyboard), loaded by phone.lua. Changes here are replaced.\n"
            "-- switch-key: %s\n" % name) + bind_lua(name)
    tmp = "%s.tmp-omamobile.%d" % (BINDS, os.getpid())
    try:
        os.makedirs(os.path.dirname(BINDS), exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, BINDS)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return False
    return True

MODBITS = {"SHIFT": 1, "CAPS": 2, "CTRL": 4, "CONTROL": 4, "ALT": 8, "MOD2": 16, "MOD3": 32, "SUPER": 64, "MOD5": 128}

def split_key(k):
    parts = [p.strip() for p in k.split("+")]
    return sum(MODBITS.get(p.upper(), 0) for p in parts[:-1]), parts[-1]

def ours_count():
    """How many of our binds Hyprland has, or None when it cannot be read."""
    try:
        binds = json.loads(run(["hyprctl", "-j", "binds"]) or "x")
    except ValueError:
        return None
    if not isinstance(binds, list):
        return None
    return sum(1 for b in binds if isinstance(b, dict) and b.get("description") == DESC), binds

ALL_KEYS = [k for ks in SWITCH_KEYS.values() for k in ks]

# Live. UNVERIFIED on the phone: that the omamobile_kbd_binds global survives between `hyprctl eval`
# calls and the config, and set_enabled through eval. When it does not (more of our binds than the
# one set afterwards), a key is hl.unbind-ed only when every bind Hyprland lists on it is ours, and
# the set is bound again; a key that also carries a user's bind is left alone and the save reports
# that it did not apply live (the file applies on the next config load).
def apply_binds(name):
    lua = bind_lua(name)
    r = run(["hyprctl", "eval", lua])
    if r is None or "error" in r.lower():
        return False
    got = ours_count()
    if got is None or got[0] == len(ALL_KEYS):
        return True
    clean = []
    for k in ALL_KEYS:
        mods, key = split_key(k)
        on = [b for b in got[1] if isinstance(b, dict) and (
              (key.startswith("code:") and b.get("keycode") == int(key[5:]) and not b.get("modmask"))
              or (str(b.get("key", "")).lower() == key.lower() and b.get("modmask") == mods))]
        if any(b.get("description") != DESC for b in on):
            return False
        clean.append(k)
    r = run(["hyprctl", "eval", "".join('pcall(hl.unbind, "%s")\n' % k for k in clean)
             + "omamobile_kbd_binds = nil\n" + lua])
    return r is not None and "error" not in r.lower()

def state(layouts, variants, options):
    sw = stored_key()
    return {"layouts": [{"layout": l, "variant": v} for l, v in zip(layouts, variants)],
            "switchKey": sw, "active": active()}

def rules(names=None):
    lay, var, opt, sec = set(), set(), set(), None
    p = os.environ.get("KBD_RULES") or ""
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith("!"):
                    sec = line[1:].strip()
                    continue
                w = line.split()
                if not w:
                    continue
                if names is not None and sec in ("layout", "option"):
                    names.append((sec, w[0], " ".join(w[1:])))
                if sec == "layout":
                    lay.add(w[0])
                elif sec == "variant" and len(w) > 1 and w[1].endswith(":"):
                    var.add((w[1][:-1], w[0]))
                elif sec == "option":
                    opt.add(w[0])
    except OSError:
        fail("cannot read the xkb layout list")
    return lay, var, opt

def write(data, st, text, found, new):
    edits = sorted(((found[k][2], found[k][3], v) for k, v in new.items() if k in found), reverse=True)
    for s, e, v in edits:
        text = text[:s] + '"' + v + '"' + text[e:]
    missing = [k for k in KEYS if k in new and k not in found]
    if missing and "kb_layout" not in found:
        # Omarchy's stock input.lua has its kb_* lines only in comments: add one hl.config() block at the
        # end, as the desktop plugin does (InputLua.pl), and leave the commented example as it is.
        if text and not text.endswith("\n"):
            text += "\n"
        text += "\nhl.config({\n  input = {\n" + "".join('    %s = "%s",\n' % (k, new[k]) for k in missing) + "  },\n})\n"
        missing = []
    if missing:
        # A missing key goes on its own line right after the live kb_layout, only when that line ends
        # with a comma, so it lands in the same `input = { }` table. Anything else is an error.
        anchor = scan(text)["kb_layout"]
        ls = text.rfind("\n", 0, anchor[2]) + 1
        indent = re.match(r"[ \t]*", text[ls:]).group(0)
        le = text.find("\n", anchor[3])
        le = len(text) if le < 0 else le
        if not re.fullmatch(r"[ \t]*,[ \t]*(--[^\n]*)?", text[anchor[3]:le]):
            fail("input.lua: cannot add %s next to kb_layout" % missing[0])
        text = text[:le] + "".join('\n%s%s = "%s",' % (indent, k, new[k]) for k in missing) + text[le:]
    updated = text.encode("utf-8")
    if updated == data:
        return
    bak = path + ".bak-omamobile"
    tmp = "%s.tmp-omamobile.%d" % (path, os.getpid())
    try:
        shutil.copyfile(path, bak)
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, st.st_mode & 0o777)
        with os.fdopen(fd, "wb") as f:
            f.write(updated)
            f.flush()
            os.fsync(f.fileno())
        with open(path, "rb") as f:
            now = f.read(1 << 20)
            nst = os.fstat(f.fileno())
        if (hashlib.sha256(now).digest() != hashlib.sha256(data).digest()
                or (nst.st_ino, nst.st_mtime_ns) != (st.st_ino, st.st_mtime_ns)):
            os.unlink(tmp)
            fail("input.lua changed while saving, nothing written")
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        fail("cannot write input.lua")

def lst_names(layouts, variants):
    return [l + ("+" + v if v else "") for l, v in zip(layouts, variants)]

# Merge into the OSK's list (see the header). UNVERIFIED on the phone: that squeekboard keeps its
# current language when the list changes but its first entry does not.
def sync_osk(old, new):
    s = run(["gsettings", "get", "org.gnome.desktop.input-sources", "sources"])
    if s is None:
        return False
    cur = re.findall(r"\(\s*'([^'\\]*)'\s*,\s*'([^'\\]*)'\s*\)", s)
    removed = set(old) - set(new)
    keep = [(k, n) for k, n in cur if not (k == "xkb" and n in removed)]
    have = {n for k, n in keep if k == "xkb"}
    carried = os.path.isdir(KEYBOARDS)
    add = [("xkb", n) for n in new
           if n not in have and (not carried or os.path.isfile(os.path.join(KEYBOARDS, n + ".yaml")))]
    merged = keep + add
    if merged == cur:
        return True
    src = ", ".join("('%s', '%s')" % kn for kn in merged) if merged else ""
    return run(["gsettings", "set", "org.gnome.desktop.input-sources", "sources",
                "[%s]" % src if merged else "@a(ss) []"]) is not None

# Live apply without `hyprctl reload`. UNVERIFIED on the phone: that Hyprland 0.57 takes
# `hyprctl eval 'hl.config({ input = {...} })'` for the keymap and re-applies it to keyboards already
# connected. The form is the one patch 0006 uses for other options; `hyprctl keyword` is the fallback.
def apply_live(layouts, variants, options):
    kv = {"kb_layout": ",".join(layouts), "kb_variant": ",".join(variants) if any(variants) else "",
          "kb_options": ",".join(options)}
    lua = "hl.config({ input = { %s } })" % ", ".join('%s = "%s"' % (k, kv[k]) for k in KEYS)
    r = run(["hyprctl", "eval", lua])
    if r is not None and "error" not in r.lower():
        return True
    # One batch, so Hyprland never builds a keymap from new variants with old layouts in between.
    # The values hold only names, commas and colons (checked above), never ";" or spaces.
    batch = "; ".join("keyword input:%s %s" % (k, kv[k]) for k in ("kb_variant", "kb_options", "kb_layout"))
    r = run(["hyprctl", "--batch", batch])
    return r is not None and "error" not in r.lower()

def effective(key):
    s = run(["hyprctl", "-j", "getoption", "input:" + key]) or ""
    try:
        v = json.loads(s).get("str", "")
    except (ValueError, AttributeError):
        v = ""
    return v if isinstance(v, str) else ""

def effective_options():
    return [o for o in fields(effective("kb_options")) if OPTION_RE.fullmatch(o)]

# No live kb_layout (the stock file): what Hyprland runs with now, "us" when it cannot say.
def effective_layouts():
    lay = [l for l in fields(effective("kb_layout")) if NAME_RE.fullmatch(l)] or ["us"]
    var = fields(effective("kb_variant"))
    var = [v if NAME_RE.fullmatch(v) else "" for v in var][:len(lay)]
    return lay, var + [""] * (len(lay) - len(var))

args = sys.argv[1:]
verb = args[0] if args else ""
if verb == "get":
    _, _, text = read_file()
    found, layouts, variants, options = parse(text)
    if "kb_layout" not in found:
        layouts, variants = effective_layouts()
    if "kb_options" not in found:
        options = effective_options()  # as set does, so get and set agree on the switch key
    out(state(layouts, variants, options))
    sys.exit(0)
if verb == "list":
    names = []
    rules(names)
    out({"layouts": [{"layout": n, "name": d} for s, n, d in names if s == "layout" and NAME_RE.fullmatch(n)],
         "switchKeys": [{"option": n, "name": d} for n, d in SWITCH_NAMES]})
    sys.exit(0)
if verb != "set":
    fail("usage: get|list|set")
key = args[1] if len(args) > 1 else ""
value = args[2] if len(args) > 2 else ""
if key not in ("layouts", "switch-key"):
    fail("unknown key")
lay, var, opt = rules()
if key == "layouts":
    items = value.split(",") if value else []
    if not 1 <= len(items) <= MAX:
        fail("give 1 to 4 layouts")
    new_l, new_v = [], []
    for it in items:
        l, _, v = it.partition(":")
        if not NAME_RE.fullmatch(l) or (v and not NAME_RE.fullmatch(v)):
            fail("bad layout name")
        if l not in lay or (v and (l, v) not in var):
            fail("unknown layout: " + it)
        if (l, v) in zip(new_l, new_v):
            fail("layout listed twice: " + it)
        new_l.append(l); new_v.append(v)
    if new_l[0] not in LATIN:
        fail("the first layout must be a Latin one (passwords on the lock screen are typed in it)")
else:
    if value not in SWITCH_KEYS:
        fail("unknown switch key")

lockpath = path + ".lock-omamobile"
try:
    lockf = open(lockpath, "a")
    fcntl.flock(lockf, fcntl.LOCK_EX)
except OSError:
    fail("cannot lock input.lua")
data, st, text = read_file()
found, layouts, variants, options = parse(text)
if "kb_layout" not in found:
    layouts, variants = effective_layouts()
old_names = lst_names(layouts, variants)
if "kb_options" not in found:
    options = effective_options()  # keep Omarchy's defaults when input.lua does not set kb_options
old_key = stored_key()
had_grp = any(o.startswith("grp:") for o in options)
options = [o for o in options if not o.startswith("grp:")]  # the switch key is a bind now
if key == "layouts":
    layouts, variants = new_l, new_v
    sw = old_key
else:
    sw = value
live_ok = osk_ok = True
if key == "layouts" or had_grp:
    new = {"kb_layout": ",".join(layouts), "kb_options": ",".join(options)}
    if "kb_options" not in found and not options:
        del new["kb_options"]
    if any(variants) or "kb_variant" in found:
        new["kb_variant"] = ",".join(variants) if any(variants) else ""
    write(data, st, text, found, new)
    osk_ok = key != "layouts" or sync_osk(old_names, lst_names(layouts, variants))
    live_ok = apply_live(layouts, variants, options)
if not write_binds(sw):
    fail("cannot write " + os.path.basename(BINDS))
live_ok = apply_binds(sw) and live_ok
if not live_ok:
    fail("saved, but Hyprland did not take it live"
         + ("" if osk_ok else ", and the on-screen keyboard list was not updated"))
if not osk_ok:
    fail("saved and applied, but the on-screen keyboard list was not updated")
out(state(layouts, variants, options))
PY
