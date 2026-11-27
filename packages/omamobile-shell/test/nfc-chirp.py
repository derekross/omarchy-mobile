#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Tests for bin/omamobile-nfc-chirp (which signals chirp, the rate limit,
nfc.json, the player's command line) and sounds/make-nfc-chirp (length,
format, level, same bytes every run). No bus and no sound card needed."""
import hashlib
import importlib.machinery
import importlib.util
import os
import subprocess
import sys
import tempfile
import types
import wave

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
gi = types.ModuleType("gi"); gi.require_version = lambda *a: None
repo = types.ModuleType("gi.repository"); repo.Gio = repo.GLib = types.SimpleNamespace()
sys.modules.update({"gi": gi, "gi.repository": repo})
loader = importlib.machinery.SourceFileLoader("nfc_chirp", os.path.join(HERE, "..", "bin", "omamobile-nfc-chirp"))
chirp = importlib.util.module_from_spec(importlib.util.spec_from_loader("nfc_chirp", loader))
loader.exec_module(chirp)

CHIRP_SHA256 = "9de02030302fca57b974468c4d06f062e4afb71699b62b0c43baa545fdc96a21"
failures = 0


def check(name, condition, detail=""):
    global failures
    print("%s - nfc-chirp: %s%s" % ("ok" if condition else "not ok", name, "" if condition else "  # " + str(detail)))
    failures += not condition


# which signals chirp
check("a tag chirps", chirp.detected({"org.neard.Tag": {}}))
check("a peer device chirps", chirp.detected({"org.neard.Device": {}}))
check("a record doesn't", not chirp.detected({"org.neard.Record": {}}))
check("an adapter doesn't", not chirp.detected({"org.neard.Adapter": {}}))
check("nothing doesn't", not chirp.detected({}))

# one chirp per tap: again only after 3 s with no tag found (over all tags)
now = [100.0]
lim = chirp.Limiter(3.0, clock=lambda: now[0])
got = []
for t in (100.0, 102.9, 105.8, 108.7, 111.8, 112.0, 115.0):
    now[0] = t
    got.append(lim.allow())
check("a card found every 2.9 s chirps once; after 3 s quiet, again",
      got == [True, False, False, False, True, False, True], got)

# nfc.json
with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "nfc.json")
    custom = os.path.join(d, "beep.ogg")
    with open(custom, "w") as f:
        f.write("x")
    default = (True, chirp.DEFAULT_SOUND)

    def with_json(text):
        with open(path, "w") as f:
            f.write(text)
        return chirp.settings(path)

    check("no file: sound on, built-in chirp", chirp.settings(path) == default)
    check("broken JSON: defaults", with_json("{sound:") == default)
    check("not an object: defaults", with_json("[1]") == default)
    check("sound off", with_json('{"sound": false}') == (False, chirp.DEFAULT_SOUND))
    check("a non-bool sound: on", with_json('{"sound": "no"}') == default)
    check("a custom file", with_json('{"sound": true, "file": "%s"}' % custom) == (True, custom))
    check("a missing custom file: built-in",
          with_json('{"file": "%s"}' % os.path.join(d, "gone.ogg")) == default)
    check("a relative file: built-in", with_json('{"file": "beep.ogg"}') == default)
    check("a directory: built-in", with_json('{"file": "%s"}' % d) == default)
    check("a non-string file: built-in", with_json('{"file": 7}') == default)
    check("deep nesting: defaults", with_json("[" * 100000 + "]" * 100000) == default)
    fifo = os.path.join(d, "fifo")
    os.mkfifo(fifo)
    check("a FIFO: built-in", with_json('{"file": "%s"}' % fifo) == default)

check("config under XDG_CONFIG_HOME",
      chirp.config_path({"XDG_CONFIG_HOME": "/x", "HOME": "/h"}) == "/x/omamobile/nfc.json")
check("config under HOME",
      chirp.config_path({"HOME": "/h"}) == "/h/.config/omamobile/nfc.json")
check("plays with pw-play, the file after --",
      chirp.command("-odd.wav") == ["pw-play", "--media-role", "Notification", "--", "-odd.wav"])

# the generated chirp
gen = os.path.join(HERE, "..", "sounds", "make-nfc-chirp")
with tempfile.TemporaryDirectory() as d:
    a, b = os.path.join(d, "a.wav"), os.path.join(d, "b.wav")
    for out in (a, b):
        subprocess.run([sys.executable, "-B", gen, out], check=True)
    with wave.open(a) as w:
        frames = w.readframes(w.getnframes())
        check("mono 16-bit 48 kHz",
              (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 48000))
        seconds = w.getnframes() / w.getframerate()
    check("at most 0.5 s", 0.1 < seconds <= 0.5, seconds)
    peak = max(abs(int.from_bytes(frames[i:i + 2], "little", signed=True))
               for i in range(0, len(frames), 2))
    check("peak about -6 dBFS", 15000 < peak <= 16500, peak)
    check("same bytes every run",
          hashlib.sha256(open(a, "rb").read()).digest() == hashlib.sha256(open(b, "rb").read()).digest())
    # pinned so two builds of one version can't drift apart; a change to the
    # generator updates this on purpose (math.sin is libm, so another
    # architecture that rounds differently would show up here first)
    digest = hashlib.sha256(open(a, "rb").read()).hexdigest()
    check("the pinned sha256", digest == CHIRP_SHA256, digest)

sys.exit(1 if failures else 0)
