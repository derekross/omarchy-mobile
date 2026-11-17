#!/bin/bash
# SPDX-License-Identifier: MIT
# Screen lock settings for the Settings app's Display page. Prints one line of JSON.
#   lock.sh get                 {"lock":60,"keyboardAwake":false,"keyboard":false,"effective":60}
#   lock.sh set lock N          N is 30, 60, 120, 180, 300 or 0 (never)
#   lock.sh set keyboard on|off stay unlocked while a Bluetooth or USB keyboard is connected
#   lock.sh apply               write the value in force now (omamobile-lock-keyboard, on each input change)
#   lock.sh restore             write the user's choice, keyboard or not (the watcher's ExecStopPost)
# How the phone locks: Omarchy's idle service locks after shell.json's idle.lock seconds (0 = never, the
# phone profile's value is 60), and the lock turns the screen off a few seconds later. So this one value
# is both "lock after" and "screen off after"; there is no separate screen-off timer.
# The choice is kept in ~/.config/omamobile/lock.json: {lock, keyboardAwake, applied, override}. "applied" is
# the value last written to shell.json's idle.lock, and "override" says that value is the keyboard's 0, not
# the user's choice. lock.json is always saved before shell.json, so after a crash or a failed write the
# keyboard's 0 is never taken for the user's "Never". If idle.lock holds something else than "applied" and
# it is not our override, it was changed elsewhere (Omarchy's own settings) and becomes the choice.
# Nothing is written before the user picks something here. The keyboard's 0 is only written while the
# watcher unit runs (it puts the choice back when it stops). If the user's shell.json exists but does not
# parse or has another version, nothing is written: only a missing or empty one starts from the defaults.
# Both files are changed under one flock, through unique temp files.
# A keyboard is an input device udev marks ID_INPUT_KEYBOARD=1 on the Bluetooth bus (0005, uhid included)
# or on USB (0003) outside /devices/virtual/input (uinput devices can claim USB), that also has the letter
# keys and space, and a name that is not empty and not a known security token or barcode scanner. The
# built-in keys, the on-screen keyboard and virtual devices are left out.
# Test hooks: OMAMOBILE_LOCK_SYSFS and OMAMOBILE_LOCK_UDEVDATA stand in for /sys and /run/udev/data;
# OMAMOBILE_LOCK_WATCHER=1/0 stands in for "is the watcher unit active".
set -euo pipefail
set +x
verb=${1:-}; key=${2:-}; value=${3:-}
sys=${OMAMOBILE_LOCK_SYSFS:-/sys}
udev=${OMAMOBILE_LOCK_UDEVDATA:-/run/udev/data}
prefs=${XDG_CONFIG_HOME:-$HOME/.config}/omamobile/lock.json
shell=$HOME/.config/omarchy/shell.json
defaults=${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json
watcher=${OMAMOBILE_LOCK_WATCHER:-}
if [[ -z $watcher ]]; then
  watcher=0
  if [[ $verb == apply || $verb == set ]] &&
    systemctl --user is-active --quiet omamobile-lock-keyboard.service 2>/dev/null; then watcher=1; fi
fi

# All work in one place: finds keyboards, reads prefs and shell.json, applies the verb, writes both.
markdir=$(mktemp -d); trap 'rm -rf "$markdir"' EXIT; mark=$markdir/written
rc=0
res=$(LOCK_WRITTEN_MARK=$mark /usr/bin/python3 -I - "$prefs" "$shell" "$defaults" "$sys" "$udev" "$watcher" "$verb" "$key" "$value" <<'PY'
import fcntl, json, os, re, struct, sys, tempfile
prefs_path, shell_path, defaults_path, sysfs, udev, watcher, verb, key, value = sys.argv[1:]
CHOICES = (30, 60, 120, 180, 300, 0)
def out(d): print(json.dumps(d, separators=(",", ":"))); sys.exit(0)
def fail(m): print(json.dumps({"error": m}, separators=(",", ":"))); sys.exit(2)

# --- keyboards
LONG_BITS = struct.calcsize("l") * 8
NEEDED = list(range(16, 26)) + list(range(30, 39)) + list(range(44, 51)) + [57]  # Q..P, A..L, Z..M, space
NOT_KEYBOARDS = re.compile(r"yubikey|yubico|nitrokey|solokey|onlykey|token|barcode|scanner", re.I)
def read(p):
    try:
        with open(p) as f: return f.read().strip()
    except OSError: return None
def keyboard_connected():
    base = os.path.join(sysfs, "class/input")
    try: names = sorted(os.listdir(base))
    except OSError: return False
    for ev in names:
        if not ev.startswith("event"): continue
        d = os.path.join(base, ev)
        dev, bus = read(d + "/dev"), read(d + "/device/id/bustype")
        if not dev or not bus: continue
        data = read(os.path.join(udev, "c" + dev)) or ""
        if "E:ID_INPUT_KEYBOARD=1" not in data.splitlines(): continue
        path = os.path.realpath(d + "/device")
        if bus == "0005": pass
        elif bus == "0003" and "/devices/virtual/input/" not in path + "/": pass
        else: continue
        name = read(d + "/device/name")
        if not name or NOT_KEYBOARDS.search(name): continue
        caps = (read(d + "/device/capabilities/key") or "").split()
        try: bits = sum(int(w, 16) << (i * LONG_BITS) for i, w in enumerate(reversed(caps)))
        except ValueError: continue
        if all(bits >> k & 1 for k in NEEDED): return True
    return False
kb = keyboard_connected()

# --- files
class Unreadable(Exception): pass
def load(p, missing_ok=True):
    try:
        with open(p) as f: text = f.read()
    except FileNotFoundError:
        if missing_ok: return None
        raise Unreadable()
    except OSError: raise Unreadable()
    if not text.strip(): return None  # empty: as missing, like Omarchy's source_file
    try: d = json.loads(text)
    except ValueError: raise Unreadable()
    if not isinstance(d, dict): raise Unreadable()
    return d
def save(p, d, indent=None):
    target = os.path.realpath(p)  # a symlinked shell.json (dotfiles) stays a symlink
    os.makedirs(os.path.dirname(target), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target), prefix="." + os.path.basename(target) + ".")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(d, f, indent=indent, ensure_ascii=False); f.write("\n")
            f.flush(); os.fsync(f.fileno())
        if os.path.exists(target): os.chmod(tmp, os.stat(target).st_mode & 0o7777)
        else: os.chmod(tmp, 0o644)
        os.replace(tmp, target)
    except BaseException:
        try: os.unlink(tmp)
        except OSError: pass
        raise
def secs(v, fallback):  # as Omarchy's IdleModel.secondsFromConfig
    try: n = float(v)
    except (TypeError, ValueError): return fallback
    return int(n) if n >= 0 and n == n and n != float("inf") else fallback
def user_shell():
    """The user's shell.json, None when missing or empty. Unparseable or another version: Unreadable."""
    s = load(shell_path)
    if s is not None and s.get("version") != 1: raise Unreadable()
    return s

try:
    os.makedirs(os.path.dirname(prefs_path), exist_ok=True)
    lockf = open(prefs_path + ".lock", "a")
    fcntl.flock(lockf, fcntl.LOCK_EX)
except OSError:
    fail("cannot lock the setting")

try: shell = user_shell()
except Unreadable: fail("shell.json is not readable")
try: defaults = load(defaults_path) if shell is None else None
except Unreadable: defaults = None
current = secs(((shell or defaults or {}).get("idle") or {}).get("lock"), 300)
try: prefs = load(prefs_path)
except Unreadable: prefs = None  # our own file: start again from what is in force (below)
if prefs is not None:
    applied, override = prefs.get("applied"), bool(prefs.get("override"))
    if isinstance(applied, int) and applied != current and not (override and current == 0):
        prefs["lock"] = current  # changed outside this page
    if not isinstance(prefs.get("lock"), int) or prefs["lock"] < 0: prefs["lock"] = current
    prefs["keyboardAwake"] = bool(prefs.get("keyboardAwake"))
    prefs["override"] = override

if verb == "get":
    p = prefs or {"lock": current, "keyboardAwake": False}
    out({"lock": p["lock"], "keyboardAwake": p["keyboardAwake"], "keyboard": kb, "effective": current})
elif verb == "set":
    p = prefs or {"lock": current, "keyboardAwake": False, "override": False}
    if key == "lock":
        if not value.isdigit() or int(value) not in CHOICES: fail("bad value")
        p["lock"] = int(value)
    elif key == "keyboard":
        if value not in ("on", "off"): fail("bad value")
        p["keyboardAwake"] = value == "on"
    else: fail("unknown key")
    prefs = p
elif verb in ("apply", "restore"):
    if prefs is None: out({"applied": None})  # never set here: leave Omarchy's value alone
else:
    fail("usage: get|set|apply|restore")

override = verb != "restore" and watcher == "1" and prefs["keyboardAwake"] and kb and prefs["lock"] != 0
want = 0 if override else prefs["lock"]
# 1. lock.json first: if we die before shell.json, the next run knows a 0 there is ours
prefs["applied"], prefs["override"] = want, override
try: save(prefs_path, prefs)
except OSError: fail("cannot save the setting")
# 2. shell.json, read again just before the write so a concurrent Omarchy change to other keys is kept
written = False
if want != current:
    try: shell = user_shell()
    except Unreadable: fail("shell.json is not readable")
    if shell is None:
        shell = defaults  # Omarchy never merges: start from its defaults, as omarchy-shell-config does
        if shell is None: fail("cannot read shell.json")
    idle = shell.get("idle") if isinstance(shell.get("idle"), dict) else {}
    idle["lock"] = want; shell["idle"] = idle
    try: save(shell_path, shell, indent=2)
    except OSError: fail("cannot write shell.json")
    written = True
    mark = os.environ.get("LOCK_WRITTEN_MARK")
    if mark: open(mark, "w").close()
out({"lock": prefs["lock"], "keyboardAwake": prefs["keyboardAwake"], "keyboard": kb, "effective": want})
PY
) || rc=$?
printf '%s\n' "$res"
[[ $rc -eq 0 ]] || exit "$rc"

# Omarchy's idle service keeps the timeout its idle monitor started with: a new idle.lock only takes
# effect after the shell restarts. Switch idle off and on through its own IPC so the monitor is made
# again with the new value. Only when idle is on and stay-awake is off, so neither is changed.
idle_status() { timeout 5 omarchy-shell idle status 2>/dev/null | tail -n1 || true; }
idle_on() { local st; st=$(idle_status); [[ $st == *'"enabled":true'* && $st == *'"stayAwake":false'* ]]; }
# Only when shell.json really changed: a re-arm restarts the idle countdown, and the keyboard watcher
# calls apply after every input change.
if [[ -e $mark && -z ${OMAMOBILE_LOCK_NO_REARM:-} ]] && command -v omarchy-shell >/dev/null 2>&1 && idle_on; then
  timeout 5 omarchy-shell idle disable >/dev/null 2>&1 || true
  # Never leave idle off: enable until the status says so.
  for _ in 1 2 3; do
    timeout 5 omarchy-shell idle enable >/dev/null 2>&1 || true
    [[ $(idle_status) == *'"enabled":true'* ]] && exit 0
    sleep 1
  done
  echo "lock.sh: could not switch Omarchy's idle back on" >&2
  exit 3
fi
