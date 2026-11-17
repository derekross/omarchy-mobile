#!/bin/bash
# SPDX-License-Identifier: MIT
# Keyboard layouts for the Settings app. The hardware keyboard's layouts live in Omarchy's user file
# ~/.config/hypr/input.lua (kb_layout, kb_variant and the grp: switch key in kb_options); the on-screen
# keyboard's list is gsettings org.gnome.desktop.input-sources sources. This keeps both the same.
# Prints one line of JSON.
#   keyboard.sh get                         {"layouts":[{"layout":"us","variant":""}],"switchKey":"","active":0}
#   keyboard.sh list                        {"layouts":[{"layout":"us","name":"English (US)"}],"switchKeys":[...]}
#   keyboard.sh set layouts us,gr[:variant] 1 to 4 layouts, each a name (and variant) in the xkb rules list
#   keyboard.sh set switch-key grp:OPTION   or "none"; one layout left always drops the switch key
# "active" is the index Hyprland reports for the first real keyboard, or null without one. A set answer
# carries "warn" when the first layout is not a Latin one (a password typed on the lock screen would be
# typed in it). input.lua is edited in place: only the last live kb_layout, kb_variant and kb_options
# strings change, comments and every other option (grp_led:caps, compose:...) stay, a copy of the old
# file goes to input.lua.bak-omamobile first, and the write is dropped if the file changed meanwhile.
# A file with no live kb_layout is an error: nothing is appended, so a second input table never appears.
# The change is applied live without `hyprctl reload` (a reload sets the configured refresh rate again and
# re-runs phone.lua), then written to gsettings in the same order.
# Test hooks (nothing in the environment sets them): OMAMOBILE_KBD_INPUT is the input.lua path,
# OMAMOBILE_KBD_RULES the xkb rules .lst file; the test puts a fake hyprctl and gsettings first on PATH.
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
export KBD_INPUT=$input KBD_RULES=$rules

/usr/bin/python3 -I - "$@" <<'PY' || exit 2
import fcntl, hashlib, json, os, re, shutil, subprocess, sys

KEYS = ("kb_layout", "kb_variant", "kb_options")
NAME_RE = re.compile(r"[a-z][a-z0-9_-]{0,31}")
SWITCH_RE = re.compile(r"grp:[a-z0-9_]{1,48}")
OPTION_RE = re.compile(r"[a-z0-9_]{1,32}:[A-Za-z0-9_]{1,48}")
LATIN = {"us", "gb", "de", "fr", "es", "it", "pt", "nl", "be", "ch", "at", "se", "no", "dk", "fi",
         "is", "ie", "pl", "cz", "sk", "hu", "ro", "hr", "si", "ee", "lv", "lt", "tr", "br", "latam",
         "ca", "au", "nz", "za", "epo"}
MAX = 4
path = os.environ["KBD_INPUT"]

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

# The last live assignment of each key wins, as a later hl.config() overrides an earlier one.
def scan(text):
    t = list(tokens(text))
    found = {}
    for a, b, c in zip(t, t[1:], t[2:]):
        if a[0] == "ident" and a[1] in KEYS and b[0] == "eq" and c[0] in ("string", "long"):
            found[a[1]] = c
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
    real = [k for k in kbs if not re.match(r"hl-virtual-keyboard|.*(consumer-control|power-button|video-bus)",
                                           str(k.get("name", "")))]
    pick = [k for k in real if k.get("main")] or real
    if not pick:
        return None
    i = pick[0].get("active_layout_index")
    return i if isinstance(i, int) and i >= 0 else None

def state(layouts, variants, options):
    sw = next((o for o in options if o.startswith("grp:")), "")
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
    ok = True
    for k in ("kb_variant", "kb_options", "kb_layout"):
        r = run(["hyprctl", "keyword", "input:" + k, kv[k]])
        ok = ok and r is not None and "error" not in r.lower()
    return ok

def sync_osk(layouts, variants):
    src = ", ".join("('xkb', '%s')" % (l + ("+" + v if v else "")) for l, v in zip(layouts, variants))
    return run(["gsettings", "set", "org.gnome.desktop.input-sources", "sources", "[%s]" % src]) is not None

def effective_options():
    s = run(["hyprctl", "-j", "getoption", "input:kb_options"]) or ""
    try:
        v = json.loads(s).get("str", "")
    except (ValueError, AttributeError):
        v = ""
    return [o for o in fields(v) if OPTION_RE.fullmatch(o)]

args = sys.argv[1:]
verb = args[0] if args else ""
if verb == "get":
    _, _, text = read_file()
    found, layouts, variants, options = parse(text)
    if "kb_layout" not in found:
        fail("input.lua has no kb_layout")
    out(state(layouts, variants, options))
    sys.exit(0)
if verb == "list":
    names = []
    rules(names)
    out({"layouts": [{"layout": n, "name": d} for s, n, d in names if s == "layout" and NAME_RE.fullmatch(n)],
         "switchKeys": [{"option": n, "name": d} for s, n, d in names if s == "option" and SWITCH_RE.fullmatch(n)]})
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
else:
    if value != "none" and (not SWITCH_RE.fullmatch(value) or value not in opt):
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
    fail("input.lua has no kb_layout")
if "kb_options" not in found:
    options = effective_options()  # keep Omarchy's defaults when input.lua does not set kb_options
if key == "layouts":
    layouts, variants = new_l, new_v
    sw = [o for o in options if o.startswith("grp:")]
else:
    sw = [] if value == "none" else [value]
if len(layouts) < 2:
    sw = []
options = [o for o in options if not o.startswith("grp:")] + sw[:1]
new = {"kb_layout": ",".join(layouts), "kb_options": ",".join(options)}
if "kb_options" not in found and not options:
    del new["kb_options"]
if any(variants) or "kb_variant" in found:
    new["kb_variant"] = ",".join(variants) if any(variants) else ""
write(data, st, text, found, new)
if not apply_live(layouts, variants, options):
    fail("saved to input.lua, but Hyprland did not take it live")
if not sync_osk(layouts, variants):
    fail("saved and applied, but the on-screen keyboard list was not updated")
res = state(layouts, variants, options)
if layouts[0] not in LATIN:
    res["warn"] = "the first layout is not a Latin one: passwords on the lock screen are typed in it"
out(res)
PY
