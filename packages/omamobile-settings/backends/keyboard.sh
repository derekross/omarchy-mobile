#!/bin/bash
# SPDX-License-Identifier: MIT
# Keyboard layouts for the Settings app. The hardware keyboard's layouts live in Omarchy's user file
# ~/.config/hypr/input.lua (kb_layout, kb_variant); the on-screen keyboard's list is gsettings
# org.gnome.desktop.input-sources sources, and a layouts change adds new ones there too.
# The switch key is pure xkb, a grp: option in kb_options, never a Hyprland bind (measured on the phone,
# Hyprland 0.57.0-3.2, Dell KB7120W over Bluetooth): alt_shift = grp:alt_shift_toggle (20/20 on 2026-11-18,
# both key orders, 1-2 ms after the second key), ctrl_shift = grp:ctrl_shift_toggle (19/19, both orders),
# caps = grp:caps_toggle,grp_led:caps (12/12, 1-3 ms, 2026-11-17), none = no grp: option. Press binds on
# top of the xkb option switched twice per press, so phone.lua binds nothing. "get" reads the choice from
# the effective kb_options; any other grp: option (Omarchy's grp:alts_toggle for a non-Latin layout, say)
# reports none, and only a switch-key save replaces it. On a fresh phone nothing switches the hardware
# layout until a key is picked here, unless Omarchy's input.lua already sets a grp: option (it does not
# with Latin layouts only). omamobile-keyboard-switch exists but nothing calls it yet (not the
# quick-settings card either).
# Prints one line of JSON.
#   keyboard.sh get                         {"layouts":[{"layout":"us","variant":""}],"switchKey":"alt_shift","active":0}
#   keyboard.sh list                        {"layouts":[{"layout":"us","name":"English (US)"}],"switchKeys":[...]}
#   keyboard.sh set layouts us,gr[:variant] 1 to 4 layouts, each a name (and variant) in the xkb rules list
#   keyboard.sh set switch-key NAME         alt_shift, ctrl_shift, caps or none
# "active" is the index Hyprland reports for the main real keyboard, or null without one. Real = not
# hl-virtual-keyboard* and not a pseudo-keyboard (consumer-control, power-button, video-bus, radio-control,
# gpio-keys); main = the real one Hyprland marks main, else the first real one with more than one layout,
# else the first real one (the same rule as omamobile-keyboard-switch and the bar). A layouts list whose
# first entry is not a Latin layout is refused (passwords on the lock screen are typed in layout 1).
# input.lua is edited in place: only the last live kb_layout, kb_variant and kb_options strings inside an
# `input = { }` table change (per-device blocks and variables are left alone), comments and every other
# option stays but, on a switch-key save, grp:, grp_led:caps (set only with caps) and compose:caps or omarchy:shift_caps_compose with caps
# (put back when caps lets go, only if it was there: "-- compose-caps: restore" in a small state file,
# ~/.config/hypr/omamobile-keyboard.lua, which nothing loads; it is removed when not needed), a copy of the old
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
# Known limits: xkb keeps a layout per keyboard, so with two real keyboards the switch key moves only the
# one it was pressed on (UNVERIFIED on the phone, only one keyboard tested).
# A bind file from earlier unreleased commits of this branch ("-- switch-key: alt_shift" or ctrl_shift)
# is no longer loaded. While kb_options has no grp: option, get reports its choice and the next save
# writes the matching grp: option and removes the file. Binds it registered stay in Hyprland until
# `hyprctl reload` (or a new login).
# When input.lua has no live kb_layout or kb_options, a save needs Hyprland's effective value; if
# `hyprctl getoption` fails, nothing is written.
# Test hooks (nothing in the environment sets them): OMAMOBILE_KBD_INPUT is the input.lua path,
# OMAMOBILE_KBD_BINDS the state file,
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
# Switch keys as xkb options (see the header). caps takes the key, so compose:caps goes with it. Shift+Caps
# gives real Caps Lock, but 2 of 4 Shift+Caps presses switched the layout instead on the phone (it also
# had shift:both_capslock_cancel): cause unknown.
SWITCH_OPTS = {"alt_shift": ["grp:alt_shift_toggle"], "ctrl_shift": ["grp:ctrl_shift_toggle"],
               "caps": ["grp:caps_toggle", "grp_led:caps"], "none": []}
# Compose on Caps Lock: Omarchy 4.0 sets compose:caps, later Omarchy omarchy:shift_caps_compose (Shift+Caps
# is Compose). Both take the Caps key, so a Caps switch key would not switch with either left in.
COMPOSE_OPTS = ("compose:caps", "omarchy:shift_caps_compose")
SWITCH_NAMES = [("alt_shift", "Alt+Shift"), ("ctrl_shift", "Ctrl+Shift"), ("caps", "Caps Lock"), ("none", "None")]
BINDS = os.environ["KBD_BINDS"]
# xkb option names as in base.lst: group:name, the name may hold "-" (compose:caps-altgr, fkeys:basic_13-24)
OPTION_RE = re.compile(r"[a-z0-9_]{1,32}:[A-Za-z0-9_][A-Za-z0-9_-]{0,47}")
LATIN = {"us", "gb", "de", "fr", "es", "it", "pt", "nl", "be", "ch", "at", "se", "no", "dk", "fi",
         "is", "ie", "pl", "cz", "sk", "hu", "ro", "hr", "si", "ee", "lv", "lt", "tr", "br", "latam",
         "ca", "au", "nz", "za", "epo"}
MAX = 4
path = os.path.realpath(os.environ["KBD_INPUT"])  # write a symlink's target, keep the link
KEYBOARDS = os.environ.get("OMAMOBILE_KEYBOARDS_DIR", "/usr/share/omamobile/squeekboard/keyboards")
PSEUDO_RE = re.compile(r"hl-virtual-keyboard|.*(consumer-control|power-button|video-bus|radio-control|gpio-keys)")

def out(obj):
    print(json.dumps(obj, separators=(",", ":")))

MARKER_NEW = False  # True while a marker this run wrote has no input.lua write behind it yet

def fail(msg):
    if MARKER_NEW:
        try:
            os.unlink(BINDS)  # input.lua still has compose:caps, so the marker would be stale
        except OSError:
            pass
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

def compose_marked():
    """The Compose option that was in kb_options before caps took the key, from the state file, else None.
    A bare "restore" line (written before the Omarchy 4.5 name was known) means compose:caps."""
    try:
        with open(BINDS, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.fullmatch(r"-- compose-caps: restore(?: (omarchy:shift_caps_compose))?\s*", line)
                if m:
                    return m.group(1) or "compose:caps"
    except OSError:
        pass
    return None

def old_key():
    """alt_shift or ctrl_shift from an earlier commit's bind file, else None."""
    try:
        with open(BINDS, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.fullmatch(r"-- switch-key: (alt_shift|ctrl_shift)\s*", line)
                if m:
                    return m.group(1)
    except OSError:
        pass
    return None

def write_state(compose):
    """The compose-caps marker for option compose on disk, else (compose falsy) no state file."""
    if not compose:
        try:
            os.unlink(BINDS)
        except FileNotFoundError:
            pass
        except OSError:
            return False
        return True
    text = ("-- Written by Omarchy Mobile Settings (Keyboard); nothing loads it. Changes here are replaced.\n"
            "-- compose-caps: restore%s\n" % ("" if compose == "compose:caps" else " " + compose))
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

def switch_key(options):
    """The choice, from kb_options alone; any other grp: option is none."""
    for name in ("alt_shift", "ctrl_shift", "caps"):
        if SWITCH_OPTS[name][0] in options:
            return name
    return "none"

def switch_options(options, sw):
    """kb_options for switch key sw: every grp: and grp_led:caps out, sw's own back in."""
    keep = [o for o in options if not o.startswith("grp:") and o != "grp_led:caps"]
    if sw == "caps":
        keep = [o for o in keep if o not in COMPOSE_OPTS]
    return keep + SWITCH_OPTS[sw]

def state(layouts, variants, options):
    sw = switch_key(options)
    if sw == "none" and not any(o.startswith("grp:") for o in options):
        sw = old_key() or sw
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
        if re.fullmatch(r"[ \t]*,[ \t]*(--[^\n]*)?", text[anchor[3]:le]):
            text = text[:le] + "".join('\n%s%s = "%s",' % (indent, k, new[k]) for k in missing) + text[le:]
        else:
            # kb_layout = "us" } on one line: the keys go right after the string, in the same table
            text = (text[:anchor[3]] + "".join(', %s = "%s"' % (k, new[k]) for k in missing)
                    + text[anchor[3]:])
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

def effective(key, need):
    """Hyprland's value; None when it cannot say (need: fail then, as a save must not guess)."""
    s = run(["hyprctl", "-j", "getoption", "input:" + key])
    try:
        v = json.loads(s).get("str", "")
    except (TypeError, ValueError, AttributeError):
        v = None
    if not isinstance(v, str):
        v = None
    if v is None and need:
        fail("cannot read Hyprland's input:%s, nothing written" % key)
    return v

def effective_options(need=False):
    return [o for o in fields(effective("kb_options", need) or "") if OPTION_RE.fullmatch(o)]

# No live kb_layout (the stock file): what Hyprland runs with now; get says "us" when it cannot say.
def effective_layouts(need=False):
    lay = [l for l in fields(effective("kb_layout", need) or "") if NAME_RE.fullmatch(l)] or ["us"]
    var = fields(effective("kb_variant", need) or "")
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
    if value not in SWITCH_OPTS:
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
    layouts, variants = effective_layouts(True)
old_names = lst_names(layouts, variants)
if "kb_options" not in found:
    options = effective_options(True)  # keep Omarchy's defaults when input.lua does not set kb_options
old_options = options
compose = None  # None: the state file is left as it is (a layouts save)
if key == "layouts":
    layouts, variants = new_l, new_v
    migrate = old_key()
    if migrate and not any(o.startswith("grp:") for o in options):
        options = switch_options(options, migrate)  # the earlier bind file's choice, now as xkb
        compose = False
else:
    sw = value
    # compose:caps goes while caps holds the key; the marker brings it back when caps lets go, and only then
    was_caps = "grp:caps_toggle" in options
    marked = compose_marked()
    present = next((o for o in COMPOSE_OPTS if o in options), None)
    compose = (present or (marked if was_caps else None) or False) if sw == "caps" else False
    options = switch_options(options, sw)
    if sw != "caps" and was_caps and marked and not any(o in options for o in COMPOSE_OPTS):
        options = options + [marked]
    # The marker goes to disk before input.lua loses compose:caps, so a failed write in between can't
    # lose it (harmless while caps is not on); leaving caps, input.lua gets compose:caps back first,
    # then the marker goes.
    if compose and compose != marked:
        if not write_state(compose):
            fail("cannot write " + os.path.basename(BINDS))
        MARKER_NEW = True
live_ok = osk_ok = True
if key == "layouts" or options != old_options:
    new = {"kb_layout": ",".join(layouts), "kb_options": ",".join(options)}
    if "kb_options" not in found and not options:
        del new["kb_options"]
    if any(variants) or "kb_variant" in found:
        new["kb_variant"] = ",".join(variants) if any(variants) else ""
    write(data, st, text, found, new)
    MARKER_NEW = False
    osk_ok = key != "layouts" or sync_osk(old_names, lst_names(layouts, variants))
    live_ok = apply_live(layouts, variants, options)
if compose is not None and not write_state(compose):
    fail("cannot write " + os.path.basename(BINDS))
if not live_ok:
    fail("saved, but Hyprland did not take it live"
         + ("" if osk_ok else ", and the on-screen keyboard list was not updated"))
if not osk_ok:
    fail("saved and applied, but the on-screen keyboard list was not updated")
out(state(layouts, variants, options))
PY
