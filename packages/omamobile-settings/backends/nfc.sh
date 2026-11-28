#!/bin/bash
# SPDX-License-Identifier: MIT
# NFC for the Settings app's Connected devices > NFC page. Prints one line of JSON.
#   nfc.sh get           {"available":true,"on":true,"switchable":true,"sound":true,"custom":false}
#     available: the phone has an NFC rfkill switch (or NFC is off totally); on: not off totally and every NFC
#     switch unblocked; switchable: omamobile-shell's omamobile-privacy@.service is installed; sound and custom
#     come from ~/.config/omamobile/nfc.json, which omamobile-nfc-chirp reads at each tag.
#   nfc.sh set nfc on|off
#     omamobile-privacy@nfc-on|off.service as root (omamobile-shell's polkit rule 50-omamobile-privacy.rules asks for
#     the owner's PIN both ways through the shell's polkit prompt), then the get answer. A cancelled or unanswered
#     PIN gives {"error":"not changed: the PIN was not entered",...} with the state read again.
#   nfc.sh sound on|off  "sound" in nfc.json (true or false), the file's other keys kept
#   nfc.sh sound import  the file the page copied to ~/.config/omamobile/sounds/.import (the app copies what the
#                        file dialog picked; no path ever comes through here) becomes the tag sound if libsndfile
#                        reads it and it is 2 s or shorter: it is moved to sounds/nfc-tag and nfc.json's "file"
#                        names it. Anything else is refused and the staged copy removed.
#   nfc.sh sound default the built-in chirp again: "file" removed from nfc.json, sounds/nfc-tag deleted
#   nfc.sh sound test    plays the sound a tag would play (pw-play, cut at 3 s)
# nfc.json is written atomically (a temporary file renamed over it). It holds {"sound": bool, "file": "/abs/path"},
# the format omamobile-nfc-chirp reads; a missing or broken file means sound on, the built-in chirp.
# The test runs a copy of this script with FAKE set to a scratch root for /sys and /usr (and /var/lib), with stub
# systemctl and pw-play on PATH; `set` then also writes the scratch state the root helper would. Nothing in the
# environment sets it.
set -euo pipefail
exec /usr/bin/python3 -I - "$@" <<'PY'
import ctypes, ctypes.util, glob, json, os, stat, subprocess, sys, tempfile

FAKE = ''
STATE = FAKE + "/var/lib/omamobile/privacy/nfc"
UNIT = FAKE + "/usr/lib/systemd/system/omamobile-privacy@.service"
DEFAULT_SOUND = FAKE + "/usr/share/omamobile/sounds/nfc-detect.wav"
MAX_SECONDS = 2.0
MAX_BYTES = 2 * 1024 * 1024

home = os.environ.get("HOME", "")
base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
conf_dir = os.path.join(base, "omamobile")
conf = os.path.join(conf_dir, "nfc.json")
sounds = os.path.join(conf_dir, "sounds")
staged = os.path.join(sounds, ".import")
custom = os.path.join(sounds, "nfc-tag")


def out(obj, code=0):
    print(json.dumps(obj, separators=(",", ":")))
    sys.exit(code)


def fail(why):
    out({"error": why}, 2)


def read_conf():
    try:
        with open(conf) as f:
            data = json.load(f)
    except (OSError, ValueError, RecursionError):
        return {}
    return data if isinstance(data, dict) else {}


def write_conf(data):
    os.makedirs(conf_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=conf_dir, prefix=".nfc.json.")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f)
            f.write("\n")
        os.replace(tmp, conf)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def switches():
    """The soft state of every NFC rfkill switch: a list of True (blocked) / False."""
    found = []
    for path in glob.glob(FAKE + "/sys/class/rfkill/rfkill*"):
        try:
            with open(path + "/type") as f:
                if f.read().strip() != "nfc":
                    continue
            with open(path + "/soft") as f:
                found.append(f.read().strip() == "1")
        except OSError:
            continue
    return found


def off_totally():
    try:
        with open(STATE) as f:
            return f.read(16).strip() == "off"
    except FileNotFoundError:
        return False
    except OSError:
        return True


def sound_file(data):
    file = data.get("file")
    if isinstance(file, str) and os.path.isabs(file) and os.path.isfile(file) and os.access(file, os.R_OK):
        return file, True
    return DEFAULT_SOUND, False


def get():
    data = read_conf()
    sw, off = switches(), off_totally()
    sound = data.get("sound", True)
    return {"available": bool(sw) or off, "on": (not off) and bool(sw) and not any(sw),
            "switchable": os.path.isfile(UNIT), "sound": sound if isinstance(sound, bool) else True,
            "custom": sound_file(data)[1]}


def seconds(path):
    """The length of a sound file as libsndfile (what pw-play uses) reads it, or None."""
    name = ctypes.util.find_library("sndfile") or "libsndfile.so.1"
    try:
        lib = ctypes.CDLL(name)
    except OSError:
        # no libsndfile (a build container): WAV only, through Python's own reader
        import wave
        try:
            with wave.open(path, "rb") as w:
                rate, frames = w.getframerate(), w.getnframes()
        except (OSError, EOFError, wave.Error):
            return None
        return frames / rate if rate > 0 and frames > 0 else None

    class Info(ctypes.Structure):
        _fields_ = [("frames", ctypes.c_int64), ("samplerate", ctypes.c_int), ("channels", ctypes.c_int),
                    ("format", ctypes.c_int), ("sections", ctypes.c_int), ("seekable", ctypes.c_int)]
    lib.sf_open.restype = ctypes.c_void_p
    lib.sf_open.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.POINTER(Info)]
    lib.sf_close.argtypes = [ctypes.c_void_p]
    info = Info()
    handle = lib.sf_open(os.fsencode(path), 0x10, ctypes.byref(info))  # SFM_READ
    if not handle:
        return None
    lib.sf_close(handle)
    if info.samplerate <= 0 or info.frames <= 0 or info.channels <= 0:
        return None
    return info.frames / info.samplerate


def drop(path):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    except OSError:
        fail("cannot remove " + os.path.basename(path) + " in ~/.config/omamobile/sounds")


args = sys.argv[1:]
verb = args[0] if args else ""
if verb == "get" and len(args) == 1:
    out(get())
elif verb == "set" and len(args) == 3 and args[1] == "nfc":
    want = args[2]
    if want not in ("on", "off"):
        fail("bad value")
    state = get()
    if not state["available"]:
        fail("this phone has no NFC")
    if not state["switchable"]:
        fail("omamobile-shell has no NFC switch here")

    def setfail(why):
        out(dict(get(), error=why), 2)
    # systemctl may ask for the PIN: the polkit rule answers AUTH_ADMIN_KEEP, so systemctl asks the session's polkit
    # agent (the shell's PIN pad) and waits. The unit's own limit is 30 s once it starts, so 122 s is the backstop,
    # as on the firewall switch; the app's runner kills a set at 160 s.
    try:
        r = subprocess.run(["systemctl", "start", f"omamobile-privacy@nfc-{want}.service"],
                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                           text=True, timeout=122)
    except subprocess.TimeoutExpired:
        setfail("not changed: the PIN was not entered")
    if r.returncode != 0:
        if "Access denied" in r.stderr or "nteractive authentication" in r.stderr:
            setfail("not changed: the PIN was not entered")
        setfail(f"could not turn NFC {want}")
    if FAKE:  # what the root helper does, in the scratch root
        if want == "off":
            os.makedirs(os.path.dirname(STATE), exist_ok=True)
            open(STATE, "w").write("off\n")
        else:
            drop(STATE)
    state = get()
    if state["on"] != (want == "on"):
        setfail(f"NFC did not turn {want}")
    out(state)
elif verb == "sound" and len(args) == 2:
    what = args[1]
    data = read_conf()
    if what in ("on", "off"):
        data["sound"] = what == "on"
        write_conf(data)
        out(get())
    elif what == "import":
        try:
            st = os.lstat(staged)
        except FileNotFoundError:
            fail("no sound was picked")
        if not stat.S_ISREG(st.st_mode):
            drop(staged)
            fail("that file isn't a sound this phone can play")
        if st.st_size > MAX_BYTES:
            drop(staged)
            fail("that file is too big for a tag sound")
        length = seconds(staged)
        if length is None:
            drop(staged)
            fail("that file isn't a sound this phone can play")
        if length > MAX_SECONDS + 0.05:
            drop(staged)
            fail("that sound is longer than 2 seconds")
        try:
            os.replace(staged, custom)
        except OSError:
            drop(staged)
            fail("cannot keep the sound in ~/.config/omamobile/sounds")
        data["file"] = custom
        write_conf(data)
        out(get())
    elif what == "default":
        data.pop("file", None)
        write_conf(data)
        drop(custom)
        out(get())
    elif what == "test":
        file = sound_file(data)[0]
        if not os.path.isfile(file):
            fail("the built-in chirp is missing (it comes with omamobile-shell)")
        try:
            r = subprocess.run(["pw-play", "--media-role", "Notification", "--", file], stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
            if r.returncode != 0:
                fail("the sound could not be played")
        except subprocess.TimeoutExpired:
            pass  # a longer sound is cut at 3 s, as on a tag
        except OSError:
            fail("cannot play sounds (pw-play is missing)")
        out(get())
    else:
        fail("usage: sound on|off|import|default|test")
else:
    fail("usage: get|set nfc on|off|sound on|off|import|default|test")
PY
