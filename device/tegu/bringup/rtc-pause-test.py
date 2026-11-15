#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# On the palmtop, awake: does an RTC read after a pause return an old time?
# N rounds of "wait P s, read twice", each read compared with the system clock. With a third
# argument A, each round also waits on until the RTC is A seconds past a minute, so the first
# read comes just after a minute rolls over (a read that mixes the old and the new time shows
# there as a minute off).
# It is not read-only: every third round arms a wake alarm an hour ahead before the pause
# (rtcwake -m no -s 3600) and clears it after the reads (rtcwake -m disable), which clears
# whatever alarm is armed at that moment. So it refuses to start when an alarm is armed, and it
# holds a block sleep inhibitor of its own from start to end, so that nothing sleeps under it
# with the alarm gone. Never run it beside a sleep series: the series arms the alarm its
# sleeps end on. A dropped SSH session ends it without its cleanup, so an alarm up to an hour
# ahead can stay armed; that only wakes the palmtop.
#   python3 rtc-pause-test.py [rounds, default 60] [pause s, default 20] [A s past the minute]
import subprocess, sys, time
f = "/sys/class/rtc/rtc0/since_epoch"
N = int(sys.argv[1]) if len(sys.argv) > 1 else 60
P = float(sys.argv[2]) if len(sys.argv) > 2 else 20
A = float(sys.argv[3]) if len(sys.argv) > 3 else None

if open("/sys/class/rtc/rtc0/wakealarm").read().strip():
    sys.exit("a wake alarm is armed (/sys/class/rtc/rtc0/wakealarm isn't empty): something is counting on it, stop")
hold = subprocess.Popen(["systemd-inhibit", "--what=sleep", "--who=rtc-pause-test", "--why=arms and clears the wake alarm",
                         "--mode=block", "sleep", "infinity"])
time.sleep(1)
if hold.poll() is not None:
    sys.exit("could not take a sleep inhibitor: stop")


def rd():
    a = time.time(); r = int(open(f).read()); b = time.time(); return r - (a + b) / 2


try:
    base = sorted(rd() for _ in range(50))[25]
    print("%s %s; base offset %.2f s" % (open("/sys/class/rtc/rtc0/name").read().strip(), open("/proc/sys/kernel/osrelease").read().strip(), base), flush=True)
    bad = 0
    for i in range(N):
        mode = i % 3
        if mode == 1: subprocess.run(["rtcwake", "-m", "no", "-s", "3600"], capture_output=True)
        try:
            time.sleep(P)
            if A is not None:
                # the RTC's whole seconds are the system clock plus base, floored
                time.sleep((A - (time.time() + base)) % 60)
            o1 = rd() - base; o2 = rd() - base
        finally:
            if mode == 1: subprocess.run(["rtcwake", "-m", "disable"], capture_output=True)
        if abs(o1) >= 1.5 or abs(o2) >= 1.5:
            bad += 1; print("round %d%s: first read after the pause %+.1f s, the next %+.1f s" % (i, " (alarm armed)" if mode == 1 else "", o1, o2), flush=True)
    print("rounds %d of %.0f s%s (%d with an alarm armed before the pause), old or odd reads: %d" % (N, P, "" if A is None else ", read %.1f s past the minute" % A, (N + 1) // 3, bad))
finally:
    hold.terminate()
