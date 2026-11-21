#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Tests for bin/omamobile-keyboards with a stand-in /sys and udev data."""
import os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "bin", "omamobile-keyboards")
LETTERS = list(range(16, 26)) + list(range(30, 39)) + list(range(44, 51)) + [57]


def caps(keys):
    bits = sum(1 << k for k in keys)
    words = []
    while bits:
        words.append("%x" % (bits & 0xFFFFFFFFFFFFFFFF))
        bits >>= 64
    return " ".join(reversed(words)) or "0"


def add(root, ev, name, bus, keys, kb=True, virtual=False, devno=None):
    devno = devno or "13:%d" % (64 + int(ev[5:]))
    real = os.path.join(root, "devices", "virtual" if virtual else "platform", "input", ev + "-dev")
    os.makedirs(os.path.join(real, "id"))
    os.makedirs(os.path.join(real, "capabilities"))
    open(os.path.join(real, "id", "bustype"), "w").write(bus + "\n")
    open(os.path.join(real, "name"), "w").write(name + "\n")
    open(os.path.join(real, "capabilities", "key"), "w").write(caps(keys) + "\n")
    d = os.path.join(root, "sys", "class", "input", ev)
    os.makedirs(d)
    open(os.path.join(d, "dev"), "w").write(devno + "\n")
    os.symlink(real, os.path.join(d, "device"))
    os.makedirs(os.path.join(root, "udev"), exist_ok=True)
    open(os.path.join(root, "udev", "c" + devno), "w").write("E:ID_INPUT_KEYBOARD=%d\n" % (1 if kb else 0))


def run(root):
    env = dict(os.environ, OMAMOBILE_KEYBOARDS_SYSFS=os.path.join(root, "sys"),
               OMAMOBILE_KEYBOARDS_UDEVDATA=os.path.join(root, "udev"))
    return subprocess.run([sys.executable, "-I", TOOL], env=env, capture_output=True, text=True, check=True).stdout


with tempfile.TemporaryDirectory() as root:
    assert run(root) == "", "no input class: nothing"
    add(root, "event0", "gpio-keys", "0019", [114, 115, 116])  # the phone's keys
    add(root, "event1", "max77759 pmic keys", "0000", LETTERS)  # not BT/USB
    add(root, "event2", "squeekboard", "0003", LETTERS, virtual=True)  # uinput claiming USB
    assert run(root) == "", "the 8 Pro with no keyboard attached"
    add(root, "event3", "Keychron K2 Keyboard", "0005", LETTERS + [1, 28])
    add(root, "event4", "YubiKey OTP+FIDO", "0003", LETTERS)
    add(root, "event5", "Some Mouse Keys", "0005", [272, 273])
    add(root, "event6", "Dell USB Keyboard", "0003", LETTERS)
    add(root, "event7", "Not marked", "0005", LETTERS, kb=False)
    assert run(root) == "Keychron K2 Keyboard\nDell USB Keyboard\n", run(root)
print("ok - omamobile-keyboards: #866's bus/key rule")
