# SPDX-License-Identifier: MIT
"""omamobile-hotdog-call-audio against a fake amixer and no sound card:
call mode sets the voice routes and the earpiece, the speaker and mute
switch what they should, and the end of the call puts every control back."""
import importlib.machinery
import importlib.util
import os
import stat
import sys
import tempfile

sys.dont_write_bytecode = True  # no __pycache__ beside libexec

here = os.path.dirname(os.path.abspath(__file__))
tmp = tempfile.mkdtemp()
state = os.path.join(tmp, "state")
with open(state, "w") as f:
    f.write("AMIC MUX0=ZERO\nTop Amp Switch=1\nBottom Amp Switch=1\nDEC0 Volume=0\n"
            "VoiceMMode1 TX Topology=69489\nAMIC MUX1=ZERO\nAIF1_CAP Mixer SLIM TX1=0\n")
amixer = os.path.join(tmp, "amixer")
with open(amixer, "w") as f:
    f.write(f"""#!/usr/bin/env python3
import sys
args = [a for a in sys.argv[1:] if a not in ("-q",)]
assert args[0] == "-c" and args[2] in ("cget", "cset"), args
name = args[3].removeprefix("name=")
st = dict(l.rstrip("\\n").split("=", 1) for l in open({state!r}) if "=" in l)
if args[2] == "cget":
    if name not in st:
        sys.exit(1)
    v = st[name]
    if v.isdigit():
        print("  : values=" + ("on" if name.endswith("Switch") and v == "1" else "off" if name.endswith("Switch") else v))
    else:
        print("  ; Item #0 'ZERO'\\n  ; Item #1 '" + v + "'\\n  : values=1")
else:
    st[name] = args[4]
    open({state!r}, "w").write("".join(k + "=" + v + "\\n" for k, v in st.items()))
""")
os.chmod(amixer, os.stat(amixer).st_mode | stat.S_IEXEC)
os.environ["PATH"] = tmp + os.pathsep + os.environ["PATH"]

# No D-Bus here: a stand-in for gi, which only main() and signals use
import types
gi = types.ModuleType("gi")
gi.repository = types.ModuleType("gi.repository")
gi.repository.Gio = gi.repository.GLib = None
sys.modules["gi"], sys.modules["gi.repository"] = gi, gi.repository

path = os.path.join(here, "..", "libexec", "omamobile-hotdog-call-audio")
loader = importlib.machinery.SourceFileLoader("call_audio", path)
spec = importlib.util.spec_from_loader("call_audio", loader)
ca = importlib.util.module_from_spec(spec)
loader.exec_module(ca)

opened = []


class FakePcm:
    def __init__(self, card, device, capture):
        self.capture = capture
        opened.append(capture)

    def run(self):
        pass

    def close(self):
        opened.remove(self.capture)


ca.Pcm = FakePcm
ca.CONFIG = os.path.join(tmp, "call-audio.conf")  # absent: the defaults


def st():
    return dict(l.rstrip("\n").split("=", 1) for l in open(state) if "=" in l)


before = st()
a = ca.CallAudio(0, 4)
assert a.select_mode(1) and a.mode == 1
s = st()
assert s["QUAT_MI2S_RX Voice Mixer VoiceMMode1"] == "1", s
assert s["VoiceMMode1 Capture Mixer SLIMBUS_0_TX"] == "1", s
assert (s["Top Amp Switch"], s["Bottom Amp Switch"]) == ("1", "0"), "earpiece"
assert s["AMIC MUX0"] == "ADC4", s
assert s["VoiceMMode1 TX Topology"] == "69488", s
assert sorted(opened) == [False, True], opened
assert a.enable_speaker(True) and (st()["Top Amp Switch"], st()["Bottom Amp Switch"]) == ("0", "1")
assert a.mute_mic(True) and st()["AMIC MUX0"] == "ZERO" and a.mic == 0
assert a.select_mode(0) and a.mode == 0 and opened == []
after = st()
for k, v in before.items():
    assert after[k] == v, (k, v, after[k])
assert a.speaker == 0 and a.mic == 1

# A kernel without the optional controls: none of them is set
assert "Top Speaker Gain" not in after and "VoiceMMode1 TX Channels" not in after, after

# The config: two mics, another topology, and a kernel with the gain and
# channel controls
with open(state, "a") as f:
    f.write("Top Speaker Gain=4\nVoiceMMode1 TX Channels=1\n")
with open(ca.CONFIG, "w") as f:
    f.write("# test\ntx_topology = 0x10F72\nmics = 2\nearpiece_gain = 11\nbogus = 1\n")
before = st()
a = ca.CallAudio(0, 4)
a.mixer._have.clear()
assert a.select_mode(1)
s = st()
assert s["VoiceMMode1 TX Topology"] == str(0x10F72), s
assert s["VoiceMMode1 TX Channels"] == "2", s
assert (s["AIF1_CAP Mixer SLIM TX1"], s["AMIC MUX1"]) == ("1", "ADC3"), s
assert s["Top Speaker Gain"] == "11", s
assert a.mute_mic(True) and (st()["AMIC MUX0"], st()["AMIC MUX1"]) == ("ZERO", "ZERO")
assert a.mute_mic(False) and (st()["AMIC MUX0"], st()["AMIC MUX1"]) == ("ADC4", "ADC3")
assert a.enable_speaker(True) and a.enable_speaker(False) and st()["Top Speaker Gain"] == "11"
assert a.select_mode(0)
after = st()
for k, v in before.items():
    assert after[k] == v, (k, v, after[k])

# A bad mic count falls back to one
with open(ca.CONFIG, "w") as f:
    f.write("mics = 3\n")
assert ca.read_config()["mics"] == 1
print("call-audio: ok")
