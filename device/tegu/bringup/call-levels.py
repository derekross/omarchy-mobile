#!/usr/bin/env python3
# Laptop: from a call-audio-watch log, the uplink (Tx) and downlink (Rx) sample values the
# AoC prints about three times a second, per session and in 5 s windows after its start:
# how many, the median and the largest magnitude of each. One sample per 0.32 s is a rough
# level, enough to tell a silent uplink from one that carries speech.
#   call-levels.py call-watch-N.txt
import re, sys, statistics
s = lambda h: (int(h, 16) ^ 0x8000) - 0x8000
rows = {}
for l in open(sys.argv[1]):
    m = re.match(r"\s*([\d.]+) \S+ log #### PCIe Session (\d+) .*Tx:\s*\d+ \(0x([0-9a-f]+)\), Rx:\s*\d+ \(0x([0-9a-f]+)\)", l)
    if m:
        rows.setdefault(m.group(2), []).append((float(m.group(1)), abs(s(m.group(3))), abs(s(m.group(4)))))
for sid, r in rows.items():
    t0 = r[0][0]
    print("session %s: %d samples over %.0f s from %.1f" % (sid, len(r), r[-1][0] - t0, t0))
    w = 0
    while True:
        x = [(a, b) for t, a, b in r if w <= t - t0 < w + 5]
        if not x:
            if w > r[-1][0] - t0: break
            w += 5; continue
        tx = [a for a, b in x]; rx = [b for a, b in x]
        print("  %3d-%3d s: n %2d  uplink median %5d max %6d over100 %2d | downlink median %5d max %6d over100 %2d" % (
            w, w + 5, len(x), statistics.median(tx), max(tx), sum(a > 100 for a in tx), statistics.median(rx), max(rx), sum(b > 100 for b in rx)))
        w += 5
