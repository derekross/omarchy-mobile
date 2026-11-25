#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""The initramfs PIN pad (initramfs/pinpad, docs/SECURITY-PLAN.md §11.5), on
the laptop: built with the host's cc, drawing into a file instead of fb0,
reading scripted touches and keys from a FIFO, and unlocking through a fake
cryptsetup that accepts one PIN. No phone, no real disk.

Checks: the PIN that reaches the command (exact bytes, no newline), that
the trace, stdout and the screen file never carry it, delete, the volume-key
navigation, the back-off after five wrong PINs, the unlock from elsewhere
(--done), blanking and the idle power-off, the marker for the USB safety
net, no display, the built-in font, and the charging-boot waits.
"""
import os
import queue
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
W, H = 1080, 2400
PIN = "135790"
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
ABS_MT_SLOT, ABS_MT_TRACKING_ID, ABS_MT_POSITION_X, ABS_MT_POSITION_Y = 0x2f, 0x39, 0x35, 0x36
KEY_VOLUMEDOWN, KEY_VOLUMEUP, KEY_POWER = 114, 115, 116
failures = 0


def ok(cond, what):
    global failures
    print(("ok - " if cond else "not ok - ") + what)
    if not cond:
        failures += 1


class Pad:
    def __init__(self, tmp, args=None, env=None, expect_fifo=True):
        self.tmp = tmp
        self.fifo = tmp / "input"
        if self.fifo.exists():
            self.fifo.unlink()
        os.mkfifo(self.fifo)
        self.fb = tmp / "fb"
        self.got = tmp / "got"
        if self.got.exists():
            self.got.unlink()
        full_env = {
            "PATH": os.environ["PATH"], "PINPAD_TRACE": "1", "PINPAD_FB": str(self.fb),
            "PINPAD_FB_SIZE": f"{W}x{H}", "PINPAD_INPUT": str(self.fifo),
            "PINPAD_TOUCH_MAX": f"{W}x{H}", "PINPAD_BACKOFF_MS": "300", "GOT": str(self.got),
        }
        full_env.update(env or {})
        if args is None:
            args = ["--font", str(tmp / "nofont"), "--marker", str(tmp / "marker"), "--", str(tmp / "fake-cryptsetup")]
        self.p = subprocess.Popen([str(tmp / "pinpad")] + args, env=full_env,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.lines = []
        self.q = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.out = b""
        threading.Thread(target=self._read_out, daemon=True).start()
        self.f = open(self.fifo, "wb") if expect_fifo else None
        self.keys = {}

    def _read(self):
        for line in self.p.stderr:
            line = line.decode(errors="replace").rstrip("\n")
            self.lines.append(line)
            self.q.put(line)

    def _read_out(self):
        self.out = self.p.stdout.read()

    def wait_for(self, text, timeout=10):
        end = time.time() + timeout
        while time.time() < end:
            try:
                line = self.q.get(timeout=max(0.01, end - time.time()))
            except queue.Empty:
                break
            if text in line:
                return line
        raise AssertionError(f"no {text!r} in the trace: {self.lines[-8:]}")

    def layout(self):
        self.wait_for("ready")
        for line in self.lines:
            if line.startswith("pinpad: key "):
                i, x, y, w, h = map(int, line.split()[2:])
                self.keys[i] = (x + w // 2, y + h // 2)

    def ev(self, t, c, v):
        self.f.write(struct.pack("llHHi", 0, 0, t, c, v))

    def tap_at(self, x, y):
        self.ev(EV_ABS, ABS_MT_SLOT, 0)
        self.ev(EV_ABS, ABS_MT_TRACKING_ID, 7)
        self.ev(EV_ABS, ABS_MT_POSITION_X, x)
        self.ev(EV_ABS, ABS_MT_POSITION_Y, y)
        self.ev(EV_SYN, 0, 0)
        self.ev(EV_ABS, ABS_MT_TRACKING_ID, -1)
        self.ev(EV_SYN, 0, 0)
        self.f.flush()

    def tap(self, key):
        index = {"del": 9, "0": 10, "ok": 11}.get(key)
        if index is None:
            index = int(key) - 1
        self.tap_at(*self.keys[index])
        self.wait_for("press")

    def key(self, code):
        self.ev(EV_KEY, code, 1)
        self.ev(EV_SYN, 0, 0)
        self.ev(EV_KEY, code, 0)
        self.ev(EV_SYN, 0, 0)
        self.f.flush()

    def enter(self, pin):
        for d in pin:
            self.tap(d)
        self.tap("ok")

    def close(self, timeout=10):
        if self.f:
            try:
                self.f.close()
            except BrokenPipeError:
                pass
        try:
            return self.p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.p.kill()
            return None


def main():
    cc = shutil.which("cc") or shutil.which("gcc") or shutil.which("clang")
    if not cc:
        print("ok - # SKIP no C compiler")
        return 0
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        subprocess.run([cc, "-O2", "-Wall", "-Werror", "-o", str(tmp / "pinpad"),
                        str(repo / "initramfs/pinpad/pinpad.c"), "-lm"], check=True)
        fake = tmp / "fake-cryptsetup"
        fake.write_text("#!/bin/sh\ncat > \"$GOT\"\n"
                        f"[ \"$(cat \"$GOT\")\" = {PIN} ] && [ \"$(wc -c < \"$GOT\")\" -eq {len(PIN)} ] && exit 0\n"
                        "exit 2\n")
        fake.chmod(0o755)

        # The right PIN, typed with a mistake and a delete
        pad = Pad(tmp)
        pad.layout()
        ok((tmp / "marker").exists(), "the marker for the USB safety net exists once the pad is drawn")
        ok("font built-in" in pad.lines[0], "no font files: the built-in font")
        frame = (tmp / "fb").read_bytes()
        ok(len(frame) == W * H * 4 and frame[:4] == bytes([0x26, 0x1b, 0x1a, 0]),
           "the pad fills the screen in the theme's background")
        for d in "1354":
            pad.tap(d)
        pad.tap("del")
        pad.tap("7")
        pad.tap("9")
        pad.tap("0")
        pad.wait_for("dots=6")
        pad.tap("ok")
        pad.wait_for("submit")
        rc = pad.close()
        ok(rc == 0, "the right PIN unlocks (exit 0)")
        ok((tmp / "got").read_bytes() == PIN.encode(), "the command got exactly the PIN, with no newline")
        trace = "\n".join(pad.lines)
        ok(PIN not in trace and not any(d in line for line in pad.lines if "press" in line for d in "0123456789"),
           "the trace never shows the digits")
        ok(pad.out == b"", "nothing on stdout")
        screen = (tmp / "fb").read_bytes()
        ok(PIN.encode() not in screen, "the screen file doesn't hold the PIN as text")

        # A console that refuses KD_GRAPHICS (a pseudo-terminal here, a phone
        # with no virtual terminals there): the pad goes on without it
        master, slave = os.openpty()
        pad = Pad(tmp, env={"PINPAD_TTY": os.ttyname(slave)})
        pad.layout()
        ok(any(line.startswith("pinpad: KDSETMODE:") for line in pad.lines),
           "the pad asks the console for graphics mode (PINPAD_TTY)")
        pad.enter(PIN)
        ok(pad.close() == 0, "a console that refuses graphics mode doesn't stop the pad")
        os.close(master)
        os.close(slave)

        # Wrong PINs, then the back-off from the fifth
        pad = Pad(tmp)
        pad.layout()
        for n in range(1, 7):
            if n > 5:
                pad.wait_for("wait over", timeout=5)
            pad.enter("1111")
            line = pad.wait_for(f"wrong {n} ")
            want = 0 if n < 5 else 300 * 2 ** (n - 5)
            ok(line.endswith(f"wait {want}"), f"wrong PIN {n}: waits {want} ms")
        start = time.time()
        pad.tap_at(*pad.keys[0])  # ignored while waiting
        pad.wait_for("wait over", timeout=5)
        ok(time.time() - start >= 0.3, "taps during the wait do nothing until it ends")
        ok(not any("press" in line for line in pad.lines[-3:]), "the tap during the wait pressed nothing")
        pad.enter(PIN)
        ok(pad.close() == 0, "the right PIN still unlocks after the back-off")

        # Volume keys and Power alone
        pad = Pad(tmp)
        pad.layout()
        # Volume Down from nothing highlights key 0 ("1"), each further one moves on
        order = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "del", "0", "ok"]
        pos = -1
        for d in PIN + "!":
            target = order.index("ok") if d == "!" else order.index(d)
            if pos < 0:
                pad.key(KEY_VOLUMEDOWN)
                pad.wait_for("draw")
                pos = 0
            while pos != target:
                pad.key(KEY_VOLUMEDOWN)
                pad.wait_for("draw")
                pos = (pos + 1) % 12
            pad.key(KEY_POWER)
            pad.wait_for("press")
        pad.wait_for("submit")
        ok(pad.close() == 0, "Volume Down and Power alone enter the PIN and unlock")
        ok((tmp / "got").read_bytes() == PIN.encode(), "the keys entered the same PIN")

        # Unlocked elsewhere (SSH): the --done path appears
        done = tmp / "mapper-root"
        pad = Pad(tmp, args=["--font", str(tmp / "nofont"), "--done", str(done), "--", str(fake)])
        pad.layout()
        pad.tap("4")
        done.touch()
        pad.wait_for("unlocked elsewhere")
        ok(pad.close() == 0, "the pad exits 0 when the volume was opened another way")
        done.unlink()

        # Blank after the blank time; the waking tap presses nothing; power off when idle
        pad = Pad(tmp, env={"PINPAD_BLANK_MS": "300", "PINPAD_OFF_MS": "3000"})
        pad.layout()
        pad.wait_for("blank", timeout=3)
        frame = (tmp / "fb").read_bytes()
        ok(frame.count(0) == len(frame), "the blanked screen is black")
        pad.tap_at(*pad.keys[0])
        pad.wait_for("unblank")
        time.sleep(0.2)
        ok(not any("press" in line for line in pad.lines), "the tap that wakes the screen presses nothing")
        pad.wait_for("idle: power off", timeout=6)
        ok(pad.close() == 3, "no input for the power-off time: exit 3")

        # A command that fails for another reason: a message, and the pad stays
        bad = tmp / "fail-cryptsetup"
        bad.write_text("#!/bin/sh\ncat >/dev/null\nexit 4\n")
        bad.chmod(0o755)
        pad = Pad(tmp, args=["--font", str(tmp / "nofont"), "--", str(bad)])
        pad.layout()
        pad.enter("12")
        pad.wait_for("result 4")
        line = pad.wait_for("draw")
        ok("Unlock failed (4)" in line, "another failure is shown, not counted as a wrong PIN")
        ok(pad.close() == 4, "the pad keeps running after it (here until the input ends)")

        # No display
        p = subprocess.run([str(tmp / "pinpad"), "--", "true"], env={"PATH": os.environ["PATH"],
                           "PINPAD_FB": str(tmp / "fb")}, capture_output=True)
        ok(p.returncode == 5, "no usable display: exit 5, so the init leaves the SSH unlock")

        # A font from mkfont, when ImageMagick and a font are here
        font = subprocess.run(["fc-match", "-f", "%{file}", "sans"], capture_output=True, text=True).stdout \
            if shutil.which("fc-match") else ""
        if shutil.which("magick") and font:
            subprocess.run([str(repo / "initramfs/pinpad/mkfont"), font, str(W), str(tmp / "font")], check=True)
            pad = Pad(tmp, args=["--font", str(tmp / "font"), "--", str(fake)])
            pad.layout()
            ok("font loaded" in pad.lines[0], "mkfont's glyphs load")
            pad.close()
        else:
            print("ok - # SKIP mkfont: no magick or font")

        # Charging boot: the cable out for the unplug time; Power held
        sysfs = tmp / "sys"
        usb = sysfs / "class/power_supply/usb"
        usb.mkdir(parents=True)
        (usb / "type").write_text("USB\n")
        (usb / "online").write_text("1\n")
        bat = sysfs / "class/power_supply/battery"
        bat.mkdir(parents=True)
        (bat / "type").write_text("Battery\n")
        (bat / "online").write_text("1\n")
        env = {"PINPAD_SYSFS": str(sysfs), "PINPAD_UNPLUG_MS": "300", "PINPAD_HOLD_MS": "300"}
        pad = Pad(tmp, args=["--charger"], env=env)
        pad.wait_for("charger: waiting")
        time.sleep(0.5)
        ok(pad.p.poll() is None, "on the charger it waits")
        (usb / "online").write_text("0\n")
        pad.wait_for("cable out", timeout=3)
        ok(pad.close() == 11, "the cable out: exit 11 (power off)")
        (usb / "online").write_text("1\n")
        pad = Pad(tmp, args=["--charger"], env=env)
        pad.wait_for("charger: waiting")
        pad.ev(EV_KEY, KEY_POWER, 1)
        pad.ev(EV_SYN, 0, 0)
        pad.f.flush()
        pad.wait_for("power held", timeout=3)
        ok(pad.close() == 10, "Power held: exit 10 (start the phone)")
        shutil.rmtree(sysfs / "class/power_supply")
        udc = sysfs / "class/udc/a600000.usb"
        udc.mkdir(parents=True)
        (udc / "state").write_text("not attached\n")
        pad = Pad(tmp, args=["--charger"], env=env)
        pad.wait_for("cable out", timeout=3)
        ok(pad.close() == 11, "no charger driver: the USB controller's state tells the cable is out")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
