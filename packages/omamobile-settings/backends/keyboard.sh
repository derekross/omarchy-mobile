#!/bin/bash
# SPDX-License-Identifier: MIT
# Keyboard layouts and the hardware switch key for the Settings app, on Omarchy 4.5's own store.
#   keyboard.sh get                  {"layouts":[{"layout":"us","variant":""}],"switchKey":"default","active":0,"override":""}
#   keyboard.sh list                 {"layouts":[{"layout":"us","name":"English (US)"}],"switchKeys":[...]}
#   keyboard.sh set layouts us,gr[:variant]   1 to 4 layouts from the xkb rules list
#   keyboard.sh set switch-key NAME           alt_shift, ctrl_shift, caps or default
# Layouts go to ~/.config/omarchy/keyboard-layouts as the two lines Omarchy's picker writes
# (XKBLAYOUT=, XKBVARIANT=; typing_setup.py save_keyboard). Omarchy's default/hypr/input.lua reads that
# file at config load. Nothing about layouts is written to ~/.config/hypr/input.lua.
# Latin rule: Omarchy's non-Latin list (NON_LATIN below, a copy of default/hypr/input.lua; the test
# compares it with the installed file). A non-Latin first layout gets us in front, as Omarchy does (an
# existing Latin us entry moves); a leading us:rus or us:chr counts as non-Latin too. The answer says
# what was saved. More than 4 after that is refused.
# Switch key: Omarchy has no store for it, so it is one marked block in the user's input.lua that sets
# only kb_options. A user kb_options replaces Omarchy's whole string, so the block carries it all:
# omarchy:shift_caps_compose plus the grp: option (Caps takes the key, so no compose with caps).
# "default" removes the block (Omarchy's own string, grp:alts_toggle with a non-Latin layout).
# A live kb_layout/kb_variant in input.lua outside the block overrides the store: get reports it in
# "override" and a layouts save writes nothing. A live kb_options outside the block: switchKey "custom"
# and a switch-key save writes nothing.
# Live apply: one `hyprctl eval` with kb_layout, kb_variant and kb_options, built the way Omarchy's
# input.lua builds them at load, then read back with getoption. Never `hyprctl reload` (it resets the
# refresh rate and re-runs phone.lua). A read-back that differs is an error; the files stay.
# On-screen keyboard: only ever add, through `omamobile-keyboard-languages add NAME` (one writer), for
# each new layout squeekboard has a file for.
# State (lock, the input.lua backup) lives in ${XDG_STATE_HOME:-~/.local/state}/omamobile.
# Prints one line of JSON. Test hooks: OMAMOBILE_KBD_RULES (xkb .lst), OMAMOBILE_KEYBOARDS_DIR,
# OMAMOBILE_KBD_LANGUAGES (the languages tool); the test puts a fake hyprctl first on PATH.
set -euo pipefail
set +x
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
cfg=${XDG_CONFIG_HOME:-$HOME/.config}
rules=${OMAMOBILE_KBD_RULES:-}
if [[ -z $rules ]]; then
  for f in /usr/share/X11/xkb/rules/base.lst /usr/share/X11/xkb/rules/evdev.lst; do
    [[ -r $f ]] && { rules=$f; break; }
  done
fi
export KBD_STORE="$cfg/omarchy/keyboard-layouts" KBD_INPUT="$cfg/hypr/input.lua" KBD_RULES=$rules
export KBD_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omamobile"
export KBD_LANGUAGES=${OMAMOBILE_KBD_LANGUAGES:-omamobile-keyboard-languages}

/usr/bin/python3 -I - "$@" <<'PY' || exit 2
import fcntl, hashlib, json, os, re, shutil, subprocess, sys

NON_LATIN = set("af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua".split())
NON_LATIN_US = {"chr", "rus"}
COMPOSE = "omarchy:shift_caps_compose"
SWITCH = {"alt_shift": COMPOSE + ",grp:alt_shift_toggle", "ctrl_shift": COMPOSE + ",grp:ctrl_shift_toggle",
          "caps": "grp:caps_toggle,grp_led:caps"}
SWITCH_NAMES = [("alt_shift", "Alt+Shift"), ("ctrl_shift", "Ctrl+Shift"), ("caps", "Caps Lock"),
                ("default", "Omarchy default")]
BEGIN = "-- omamobile-settings: switch key (begin, changed by Settings > Keyboard)"
END = "-- omamobile-settings: switch key (end)"
NAME_RE = re.compile(r"[a-z][a-z0-9_-]{0,31}")
MAX = 4
STORE, STATE = os.environ["KBD_STORE"], os.environ["KBD_STATE"]
INPUT = os.path.realpath(os.environ["KBD_INPUT"])  # a symlinked input.lua stays a link
KEYBOARDS = os.environ.get("OMAMOBILE_KEYBOARDS_DIR", "/usr/share/omamobile/squeekboard/keyboards")
PSEUDO_RE = re.compile(r"hl-virtual-keyboard|.*(consumer-control|power-button|video-bus|radio-control|gpio-keys)")

def out(obj):
    print(json.dumps(obj, separators=(",", ":")))

def fail(msg):
    out({"error": msg})
    sys.exit(2)

def run(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None

# Lua tokens, enough to see live `key = "string"` assignments; comments and long strings are skipped.
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
            i = m.end() + 1
            yield ("string", "")
            continue
        m = re.compile(r"[A-Za-z_][A-Za-z0-9_]*").match(text, i)
        if m:
            yield ("ident", m.group(0))
            i = m.end()
            continue
        yield ("eq" if c == "=" and not text.startswith("==", i) else "other", c)
        i += 2 if text.startswith("==", i) else 1

def live_keys(text):
    """The kb_* keys set inside an `input = { }` table (not per-device blocks or variables)."""
    t, found, stack = list(tokens(text)), set(), []
    for i, a in enumerate(t):
        if a == ("other", "{"):
            stack.append(i >= 2 and t[i - 2] == ("ident", "input") and t[i - 1][0] == "eq")
        elif a == ("other", "}"):
            if stack:
                stack.pop()
        elif a[0] == "ident" and a[1] in ("kb_layout", "kb_variant", "kb_options") and stack and stack[-1] \
                and i + 1 < len(t) and t[i + 1][0] == "eq":
            found.add(a[1])
    return found

def read_input():
    try:
        with open(INPUT, "rb") as f:
            data = f.read(1 << 20)
            st = os.fstat(f.fileno())
    except FileNotFoundError:
        return None, None, ""
    except OSError:
        fail("cannot read input.lua")
    try:
        return data, st, data.decode("utf-8")
    except UnicodeDecodeError:
        fail("input.lua is not UTF-8")

def split_block(text):
    """(text without our block, the block's kb_options or None)."""
    m = re.search(r"(?m)^%s\n(.*?)^%s\n?" % (re.escape(BEGIN), re.escape(END)), text, re.S)
    if not m:
        return text, None
    v = re.search(r'kb_options\s*=\s*"([^"\\]*)"', m.group(1))
    return text[:m.start()] + text[m.end():], (v.group(1) if v else "")

def read_store():
    """Omarchy's keyboard.lua rules: KEY=value, trailing # comment and quotes stripped."""
    vals = {}
    try:
        with open(STORE, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.match(r"^\s*([\w]+)\s*=\s*(.*?)\s*$", line)
                if m:
                    v = re.sub(r"\s+#.*$", "", m.group(2))
                    v = re.sub(r'^"(.*)"$', r"\1", v)
                    vals[m.group(1)] = re.sub(r"^'(.*)'$", r"\1", v)
    except OSError:
        pass
    return vals

def fields(raw):
    return [x.strip() for x in raw.split(",")] if raw.strip() else []

def getoption(key):
    try:
        v = json.loads(run(["hyprctl", "-j", "getoption", "input:" + key])).get("str")
    except (TypeError, ValueError, AttributeError):
        return None
    return v if isinstance(v, str) else None

def current_layouts():
    vals = read_store()
    raw_l, raw_v = vals.get("XKBLAYOUT"), vals.get("XKBVARIANT", "")
    if not raw_l:  # no store yet: what Hyprland runs with now (vconsole.conf on Omarchy), else us
        raw_l, raw_v = getoption("kb_layout") or "us", getoption("kb_variant") or ""
    lay = [l for l in fields(raw_l) if NAME_RE.fullmatch(l)] or ["us"]
    var = [v if NAME_RE.fullmatch(v) else "" for v in fields(raw_v)][:len(lay)]
    return lay, var + [""] * (len(lay) - len(var))

def non_latin(l, v):
    return l in NON_LATIN or (l == "us" and v in NON_LATIN_US)

def latin_first(lay, var):
    """Omarchy's input.lua rule, plus a leading us:rus / us:chr."""
    if not non_latin(lay[0], var[0]):
        return lay, var
    pairs = list(zip(lay, var))
    us = next((p for p in pairs if p[0] == "us" and p[1] not in NON_LATIN_US), ("us", ""))
    pairs = [us] + [p for p in pairs if p != us]
    return [p[0] for p in pairs], [p[1] for p in pairs]

def options_for(lay, var, block, custom):
    if block is not None:
        return block
    if custom:
        return getoption("kb_options")
    # Omarchy's input.lua at load: its compose option, plus grp:alts_toggle when any layout name is
    # non-Latin (it checks names only, so us:rus alone adds nothing there either)
    return COMPOSE + (",grp:alts_toggle" if any(l in NON_LATIN for l in lay) else "")

def switch_name(block, custom):
    if block is not None:
        return next((k for k, v in SWITCH.items() if v == block), "custom")
    return "custom" if custom else "default"

def active():
    try:
        kbs = json.loads(run(["hyprctl", "-j", "devices"]))["keyboards"]
    except (TypeError, ValueError, KeyError):
        return None
    real = [k for k in kbs if not PSEUDO_RE.match(str(k.get("name", "")))]
    multi = [k for k in real if len([l for l in str(k.get("layout", "")).split(",") if l]) > 1]
    pick = [k for k in real if k.get("main")] or multi or real
    i = pick[0].get("active_layout_index") if pick else None
    return i if isinstance(i, int) and i >= 0 else None

def rules(names=None):
    lay, var, sec = set(), set(), None
    try:
        with open(os.environ.get("KBD_RULES") or "", encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith("!"):
                    sec = line[1:].strip()
                    continue
                w = line.split()
                if not w:
                    continue
                if names is not None and sec == "layout":
                    names.append((w[0], " ".join(w[1:])))
                if sec == "layout":
                    lay.add(w[0])
                elif sec == "variant" and len(w) > 1 and w[1].endswith(":"):
                    var.add((w[1][:-1], w[0]))
    except OSError:
        fail("cannot read the xkb layout list")
    return lay, var

def atomic(path, data, mode=0o644):
    tmp = "%s.tmp-omamobile.%d" % (path, os.getpid())
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return False
    return True

def apply_live(lay, var, opts):
    kv = {"kb_layout": ",".join(lay), "kb_variant": ",".join(var) if any(var) else "", "kb_options": opts}
    r = run(["hyprctl", "eval", "hl.config({ input = { %s } })"
             % ", ".join('%s = "%s"' % (k, v) for k, v in kv.items())])
    if r is None or "error" in r.lower():
        return False
    return all(getoption(k) == v for k, v in kv.items())

def state(lay, var, block, custom, override):
    return {"layouts": [{"layout": l, "variant": v} for l, v in zip(lay, var)],
            "switchKey": switch_name(block, custom), "active": active(), "override": override}

def input_state(text):
    rest, block = split_block(text)
    keys = live_keys(rest)
    override = "input.lua sets its own layouts" if keys & {"kb_layout", "kb_variant"} else ""
    return rest, block, "kb_options" in keys, override

args = sys.argv[1:]
verb = args[0] if args else ""
if verb == "list":
    names = []
    rules(names)
    out({"layouts": [{"layout": n, "name": d} for n, d in names if NAME_RE.fullmatch(n)],
         "switchKeys": [{"option": n, "name": d} for n, d in SWITCH_NAMES]})
    sys.exit(0)
if verb == "get":
    _, _, text = read_input()
    _, block, custom, override = input_state(text)
    lay, var = current_layouts()
    out(state(lay, var, block, custom, override))
    sys.exit(0)
if verb != "set" or len(args) != 3 or args[1] not in ("layouts", "switch-key"):
    fail("usage: get|list|set layouts LIST|set switch-key NAME")
key, value = args[1], args[2]
if key == "layouts":
    lay_ok, var_ok = rules()
    items = value.split(",") if value else []
    if not 1 <= len(items) <= MAX:
        fail("give 1 to 4 layouts")
    new_l, new_v = [], []
    for it in items:
        l, _, v = it.partition(":")
        if not NAME_RE.fullmatch(l) or (v and not NAME_RE.fullmatch(v)):
            fail("bad layout name")
        if l not in lay_ok or (v and (l, v) not in var_ok):
            fail("unknown layout: " + it)
        if (l, v) in zip(new_l, new_v):
            fail("layout listed twice: " + it)
        new_l.append(l); new_v.append(v)
    new_l, new_v = latin_first(new_l, new_v)
    if len(new_l) > MAX:
        fail("4 non-Latin layouts leave no room for us in front; take one out")
elif value not in SWITCH and value != "default":
    fail("unknown switch key")

try:
    os.makedirs(STATE, exist_ok=True)
    lockf = open(os.path.join(STATE, "keyboard.lock"), "a")
    fcntl.flock(lockf, fcntl.LOCK_EX)
except OSError:
    fail("cannot lock the keyboard settings")
data, st, text = read_input()
rest, block, custom, override = input_state(text)
lay, var = current_layouts()
osk_ok = True
if key == "layouts":
    if override:
        fail(override + "; nothing written")
    old = {l + ("+" + v if v else "") for l, v in zip(lay, var)}
    store = "XKBLAYOUT=%s\nXKBVARIANT=%s\n" % (",".join(new_l), ",".join(new_v))
    if not atomic(STORE, store.encode()):
        fail("cannot write ~/.config/omarchy/keyboard-layouts")
    lay, var = new_l, new_v
    carried = os.path.isdir(KEYBOARDS)
    for l, v in zip(lay, var):
        n = l + ("+" + v if v else "")
        if n not in old and (not carried or os.path.isfile(os.path.join(KEYBOARDS, n + ".yaml"))):
            osk_ok = run([os.environ["KBD_LANGUAGES"], "add", n]) is not None and osk_ok
else:
    if custom:
        fail("input.lua sets its own kb_options; nothing written")
    if data is None:
        fail("input.lua is missing")
    new_block = SWITCH.get(value)
    if new_block != block:
        new = rest
        if new_block is not None:
            if new and not new.endswith("\n"):
                new += "\n"
            new += '%s\nhl.config({ input = { kb_options = "%s" } })\n%s\n' % (BEGIN, new_block, END)
        try:
            shutil.copyfile(INPUT, os.path.join(STATE, "keyboard-input.lua.bak"))
        except OSError:
            fail("cannot back up input.lua, nothing written")
        with open(INPUT, "rb") as f:
            now = f.read(1 << 20)
            nst = os.fstat(f.fileno())
        if hashlib.sha256(now).digest() != hashlib.sha256(data).digest() or nst.st_mtime_ns != st.st_mtime_ns:
            fail("input.lua changed while saving, nothing written")
        if not atomic(INPUT, new.encode("utf-8"), st.st_mode & 0o777):
            fail("cannot write input.lua")
        block = new_block
opts = options_for(lay, var, block, custom)
if opts is None or not apply_live(lay, var, opts):
    fail("saved, applies at next login (Hyprland did not take it live)"
         + ("" if osk_ok else ", and the on-screen keyboard list was not updated"))
if not osk_ok:
    fail("saved and applied, but the on-screen keyboard list was not updated")
res = state(lay, var, block, custom, override)
if key == "layouts" and [l + (":" + v if v else "") for l, v in zip(lay, var)] != items:
    res["note"] = "us goes first: passwords on the lock screen are typed in the first layout"
out(res)
PY
