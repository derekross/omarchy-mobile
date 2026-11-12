#!/usr/bin/env python3
# On the palmtop: watch the AoC through a phone call, read-only. For D seconds it reads
# the call's mixer controls every half second and prints one line whenever a value
# changes, and it reads the AoC's own log (/dev/acd-logging) and prints its text as it
# arrives, every line stamped with the seconds since the start and the wall clock. Start
# it, place the call, hang up, and read where the lines change about 2 s into the call.
# Nothing is written to the mixer or the AoC. CTL=0 leaves the controls unread (the log
# alone), in case reading them changes what the call does.
#   python3 call-audio-watch.py [D s, default 120] > /run/call-audio-watch.txt
import os, re, subprocess, sys, threading, time

D = float(sys.argv[1]) if len(sys.argv) > 1 else 120
CARD = "0"
CTLS = ["Audio DSP Mode", "AoC Modem Mixer ASP Mode", "AoC Speaker Mixer ASP Mode",
        "AoC Modem Downlink ASRC Mode", "AoC Modem Sink Channel Bitmap", "Incall Mic Gain (dB)",
        "Incall Mic Mute", "Incall Sink Mute", "MIC HW Gain (cB)", "BUILTIN MIC Process Mode",
        "FT AEC Reference Source", "Audio Capture Mic Source", "BUILDIN MIC POWER STATE",
        "Incall Capture Stream0", "Incall Playback Stream0"]
t0 = time.monotonic()
lock = threading.Lock()


def say(kind, text):
    with lock:
        print("%7.2f %s %s %s" % (time.monotonic() - t0, time.strftime("%H:%M:%S"), kind, text), flush=True)


def get(name):
    r = subprocess.run(["amixer", "-c", CARD, "cget", "name=" + name], capture_output=True, text=True)
    m = re.search(r": values=(.*)", r.stdout)
    return m.group(1).strip() if m else "?"


def aoclog():
    try:
        fd = os.open("/dev/acd-logging", os.O_RDONLY)
    except OSError as e:
        say("log", "can't open /dev/acd-logging: %s" % e); return
    while time.monotonic() - t0 < D:
        try:
            b = os.read(fd, 65536)
        except OSError as e:
            say("log", "read failed: %s" % e); return
        for s in re.findall(rb"[\x20-\x7e]{6,}", b):
            say("log", s.decode())


threading.Thread(target=aoclog, daemon=True).start()
say("start", open("/proc/sys/kernel/osrelease").read().strip())
last = {}
while time.monotonic() - t0 < D:
    if os.environ.get("CTL", "1") != "0":
        for c in CTLS:
            v = get(c)
            if last.get(c) != v:
                say("ctl", "%s: %s%s" % (c, v, "" if c not in last else " (was %s)" % last[c]))
                last[c] = v
    time.sleep(0.5)
say("end", "")
