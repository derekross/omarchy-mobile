# SPDX-License-Identifier: MIT
# Tests for bin/omamobile-voice-preview: its pure parts, then the whole loop
# against a fake voxtype with a generated WAV (no microphone, no model).
# Run by test/all.
import array
import importlib.machinery
import importlib.util
import json
import math
import os
import signal
import subprocess
import sys
import tempfile
import time

here = os.path.dirname(os.path.abspath(__file__))
tool = os.path.join(here, "..", "bin", "omamobile-voice-preview")
loader = importlib.machinery.SourceFileLoader("voice_preview", tool)
spec = importlib.util.spec_from_loader("voice_preview", loader)
vp = importlib.util.module_from_spec(spec)
loader.exec_module(vp)

failed = 0
RATE = vp.RATE


def check(name, fn):
    global failed
    try:
        fn()
        print("ok - voice preview: " + name)
    except AssertionError as error:
        failed += 1
        print("not ok - voice preview: %s\n  %s" % (name, error), file=sys.stderr)


def tone(secs, amp=6000, freq=220):
    a = array.array("h", (int(amp * math.sin(2 * math.pi * freq * i / RATE)) for i in range(int(secs * RATE))))
    if sys.byteorder == "big":
        a.byteswap()
    return a.tobytes()


def silence(secs):
    return b"\0\0" * int(secs * RATE)


def models():
    cfg = '[audio]\nmodel = "x"\n\n[whisper]\nmodel = "small.en"\n'
    assert vp.daemon_model(cfg) == "small.en"
    assert vp.daemon_model("") == "base.en", "Omarchy's default when the config says nothing"
    assert vp.pick_model(["tiny.en", "base.en"], cfg) == ("tiny.en", 1.2), "tiny.en whenever it is there"
    assert vp.pick_model(["base.en"], '[whisper]\nmodel = "base.en"\n') == ("base.en", 2.5), "else base.en, half as often"
    assert vp.pick_model(["small.en"], cfg) is None, "small.en would lag behind the speech"
    assert vp.pick_model(["base.en"], cfg) is None, "only the daemon's own base.en (it is on disk for that)"
    assert vp.pick_model([], "") is None


def planning():
    step = 1.2
    assert vp.plan(int(0.5 * RATE), 0, 0, step) is None, "under a second: wait"
    assert vp.plan(int(1.0 * RATE), 0, 0, step) is None, "not a step of new audio yet"
    assert vp.plan(int(1.3 * RATE), 0, 0, step) == ("partial", 0, int(1.3 * RATE))
    t = int(5 * RATE)
    assert vp.plan(t, 0, t - int(0.5 * RATE), step) is None, "half a second since the last pass: wait"
    t = int(9 * RATE)
    p = vp.plan(t, 0, 0, step)
    assert p[0] == "commit" and p[2] == t - int(2.5 * RATE) and p[3] == t - int(0.5 * RATE), p
    assert vp.plan(t, int(4 * RATE), 0, step)[0] == "partial", "the chunk since the last commit counts, not the recording"
    assert vp.pass_timeout(1.2) > 2 and vp.pass_timeout(2.5) > 5


def audio():
    pcm = tone(1) + silence(0.3) + tone(1)
    cut = vp.quietest_cut(pcm, int(0.5 * RATE), int(2.2 * RATE))
    assert int(1.0 * RATE) <= cut <= int(1.3 * RATE), "the cut lands in the pause: %d" % cut
    assert vp.rms(silence(1)) == 0 and vp.rms(tone(1)) > vp.SILENCE_RMS
    assert vp.rms(tone(1, amp=50)) < vp.SILENCE_RMS, "a quiet room is silence"
    wav = vp.wav_bytes(tone(0.5))
    assert wav[:4] == b"RIFF" and wav[8:12] == b"WAVE" and len(wav) == 44 + int(0.5 * RATE) * 2


def text():
    assert vp.clean(" [BLANK_AUDIO] hello (music)  *cough* world\n") == "hello world"
    assert vp.join("one two", "three") == "one two three" and vp.join("", "three") == "three" and vp.join("a", "") == "a"
    out = 'Loading audio file: "/dev/stdin"\nAudio format: 16000 Hz, 1 channel(s), Int\nProcessing 48000 samples (3.00s)...\n\nor open the voice plan check.\n'
    assert vp.transcript_from(out) == "or open the voice plan check."
    assert vp.transcript_from("Processing 1 samples\n\n[BLANK_AUDIO]\n") == ""


FAKE = r'''#!/usr/bin/env python3
# fake voxtype: logs its argv and config, answers "w<N>" for N seconds of audio
import os, sys, time, wave
args = sys.argv[1:]
log = os.environ["FAKE_LOG"]
cfg = open(args[args.index("-c") + 1]).read()
w = wave.open(sys.stdin.buffer, "rb")
secs = w.getnframes() / w.getframerate()
with open(log, "a") as f:
    f.write("%s|%s|%.2f\n" % (" ".join(a for a in args if not a.startswith("/dev/fd/")), cfg.replace("\n", ";"), secs))
time.sleep(float(os.environ.get("FAKE_SLEEP", "0")))
print('Loading audio file: "/dev/stdin"')
print("Processing %d samples (%.2fs)..." % (w.getnframes(), secs))
print()
print("w%d" % round(secs))
'''


def env_for(tmp, sleep="0"):
    home = os.path.join(tmp, "home")
    os.makedirs(os.path.join(home, ".local/share/voxtype/models"), exist_ok=True)
    os.makedirs(os.path.join(home, ".config/voxtype"), exist_ok=True)
    fake = os.path.join(tmp, "voxtype")
    with open(fake, "w") as f:
        f.write(FAKE)
    os.chmod(fake, 0o755)
    env = dict(os.environ, HOME=home, OMAMOBILE_VOXTYPE=fake, FAKE_LOG=os.path.join(tmp, "log"), FAKE_SLEEP=sleep)
    return env, home


def whole_loop():
    with tempfile.TemporaryDirectory() as tmp:
        env, home = env_for(tmp)
        r = subprocess.run([sys.executable, tool, "--from", "-"], input=vp.wav_bytes(tone(1)), env=env,
                           stdout=subprocess.PIPE, timeout=20)
        assert json.loads(r.stdout.decode().splitlines()[0]) == {"status": "no-model"}, "no model, no preview"
        open(os.path.join(home, ".local/share/voxtype/models/ggml-tiny.en.bin"), "w").close()
        # 10 s of "speech" with a pause at 6.9-7.4 s, then 2 s of silence, at 8x
        pcm = tone(6.9) + silence(0.5) + tone(2.6) + silence(2)
        r = subprocess.run([sys.executable, tool, "--from", "-", "--speed", "8"], input=vp.wav_bytes(pcm), env=env,
                           stdout=subprocess.PIPE, timeout=60)
        lines = [json.loads(l) for l in r.stdout.decode().splitlines()]
        assert lines and all(set(l) == {"text", "secs", "ms", "model"} for l in lines), lines
        assert all(l["model"] == "tiny.en" for l in lines)
        texts = [l["text"] for l in lines]
        assert texts[0] in ("w1", "w2"), "the first pass after about a second: %s" % texts
        commit = [t for t in texts if t.startswith("w7")]
        assert commit, "a commit cut at the pause near 7 s: %s" % texts
        assert texts[-1].startswith("w7 ") and len(texts[-1].split()) == 2, "the committed text, then the rest: %s" % texts
        log = open(env["FAKE_LOG"]).read().splitlines()
        argv, cfg, _ = log[0].split("|")
        assert argv.startswith("-q -c --model ") and argv.endswith("ggml-tiny.en.bin transcribe /dev/stdin"), argv
        assert "context_window_optimization = true" in cfg and 'language = "en"' in cfg, cfg
        assert all(float(l.split("|")[2]) <= vp.COMMIT + 0.1 for l in log), "no pass is longer than a chunk: %s" % log
        assert len(log) == len(lines), "silence is never transcribed: %d passes, %d lines" % (len(log), len(lines))


def stops_at_once():
    with tempfile.TemporaryDirectory() as tmp:
        env, home = env_for(tmp, sleep="30")
        open(os.path.join(home, ".local/share/voxtype/models/ggml-tiny.en.bin"), "w").close()
        p = subprocess.Popen([sys.executable, tool, "--from", "-"], stdin=subprocess.PIPE, env=env,
                             stdout=subprocess.PIPE)
        p.stdin.write(vp.wav_bytes(tone(5)))
        p.stdin.close()
        deadline = time.time() + 10
        while time.time() < deadline and not os.path.exists(env["FAKE_LOG"]):
            time.sleep(0.05)
        assert os.path.exists(env["FAKE_LOG"]), "a pass started"
        t0 = time.time()
        p.send_signal(signal.SIGTERM)
        p.wait(timeout=5)
        assert time.time() - t0 < 2, "SIGTERM ends the pass under way, not after it"
        assert p.returncode == 0


check("its model: tiny.en, else the daemon's base.en, else none", models)
check("the chunk plan: a pass per step of new audio, a commit past 8 s", planning)
check("audio: the cut in the pause, silence, the WAV", audio)
check("text: Whisper's tags out, the transcript from voxtype's output", text)
check("the whole loop against a fake voxtype", whole_loop)
check("SIGTERM stops a pass under way", stops_at_once)
sys.exit(1 if failed else 0)
