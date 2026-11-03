#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Tests for bin/omamobile-doubletap: the double-tap detector against
synthetic event streams, and the touchscreen found by its capabilities in a
fake /sys (a direct multi-touch device, whatever its name)."""

import importlib.machinery
import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "bin", "omamobile-doubletap")
failures = 0


def check(name, condition, detail=""):
    global failures
    print("%s - doubletap: %s%s" % ("ok" if condition else "not ok", name, "" if condition else "  # " + str(detail)))
    if not condition:
        failures += 1


loader = importlib.machinery.SourceFileLoader("doubletap", TOOL)
spec = importlib.util.spec_from_loader("doubletap", loader)
dt = importlib.util.module_from_spec(spec)
loader.exec_module(dt)


def tap(t, x, y, length=0.08):
    """A tap's events as a touchscreen with pointer emulation sends them."""
    return [(t, dt.EV_ABS, dt.ABS_MT_POSITION_X, x), (t, dt.EV_ABS, dt.ABS_MT_POSITION_Y, y),
            (t, dt.EV_KEY, dt.BTN_TOUCH, 1), (t + length, dt.EV_KEY, dt.BTN_TOUCH, 0)]


def wakes(*taps):
    d = dt.DoubleTap(150)
    events = [e for group in taps for e in group]
    return sum(1 for e in events if d.feed(*e))


check("two quick taps in one place wake", wakes(tap(10.0, 500, 1000), tap(10.25, 520, 1010)) == 1)
check("a single tap doesn't", wakes(tap(10.0, 500, 1000)) == 0)
check("taps further apart than 400 ms don't", wakes(tap(10.0, 500, 1000), tap(10.6, 500, 1000)) == 0)
check("taps far apart on the screen don't", wakes(tap(10.0, 100, 1000), tap(10.2, 700, 1000)) == 0)
check("a long press then a tap doesn't", wakes(tap(10.0, 500, 1000, length=0.6), tap(10.7, 500, 1000)) == 0)
check("a tap then a long press doesn't", wakes(tap(10.0, 500, 1000), tap(10.2, 500, 1000, length=0.6)) == 0)
check("three quick taps wake once", wakes(tap(10.0, 500, 1000), tap(10.2, 500, 1000), tap(10.4, 500, 1000)) == 1)
check("four quick taps wake twice", wakes(*(tap(10.0 + 0.2 * i, 500, 1000) for i in range(4))) == 2)
check("a swipe doesn't count as a tap", wakes(tap(10.0, 500, 1000, length=0.5), tap(10.6, 500, 1000)) == 0)

check("bitmask reads sysfs words, most significant first",
      dt.bitmask("1 0") == 1 << dt.LONG_BITS and dt.has(dt.bitmask("400 0 0 0 0"), 10 + 4 * dt.LONG_BITS))


def device(root, n, name, props, keys, abs_):
    d = os.path.join(root, "class/input/event%d/device" % n)
    os.makedirs(d + "/capabilities")
    for f, v in (("name", name), ("properties", props), ("capabilities/key", keys), ("capabilities/abs", abs_)):
        with open(os.path.join(d, f), "w") as fh:
            fh.write(v + "\n")


def keys_with(*bits):
    v = 0
    for b in bits:
        v |= 1 << b
    words = []
    while v:
        words.append("%x" % (v & ((1 << dt.LONG_BITS) - 1)))
        v >>= dt.LONG_BITS
    return " ".join(reversed(words)) or "0"


with tempfile.TemporaryDirectory() as root:
    check("no input devices: none", dt.find_touchscreen(root) is None)
    mt = keys_with(dt.ABS_MT_POSITION_X, dt.ABS_MT_POSITION_Y)
    # The power key, a touchpad (multi-touch but not direct), then the
    # touchscreen at event10 (sorted by number, not as text).
    device(root, 0, "gpio-keys", "0", keys_with(116), "0")
    device(root, 2, "touchpad", "1", keys_with(dt.BTN_TOUCH), mt)
    device(root, 10, "any_touch_driver", "2", keys_with(dt.BTN_TOUCH), mt)
    device(root, 11, "second_screen", "2", keys_with(dt.BTN_TOUCH), mt)
    check("the first direct multi-touch device, by number, whatever its name",
          dt.find_touchscreen(root) == "/dev/input/event10", dt.find_touchscreen(root))

with tempfile.TemporaryDirectory() as root:
    device(root, 3, "pen", "2", keys_with(dt.BTN_TOUCH), keys_with(0, 1))
    check("a direct device without multi-touch isn't taken", dt.find_touchscreen(root) is None)

sys.exit(1 if failures else 0)
