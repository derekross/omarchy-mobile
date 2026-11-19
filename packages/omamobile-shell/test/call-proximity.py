#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Tests for bin/omamobile-call-proximity: which call states want the
guard, the proximity switch found by its capabilities in a fake /sys, the
blanking steps (panel off on near, back on far, a panel lit by hand left
alone) with the commands and the clock stubbed, the marker's lock, and the
whole tool in a child process stopped by SIGTERM or SIGHUP, or killed,
while the panel is off."""

import fcntl
import importlib.machinery
import importlib.util
import os
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "bin", "omamobile-call-proximity")
failures = 0


def check(name, condition, detail=""):
    global failures
    print("%s - call-proximity: %s%s" % ("ok" if condition else "not ok", name, "" if condition else "  # " + str(detail)))
    if not condition:
        failures += 1


loader = importlib.machinery.SourceFileLoader("call_proximity", TOOL)
spec = importlib.util.spec_from_loader("call_proximity", loader)
cp = importlib.util.module_from_spec(spec)
loader.exec_module(cp)


def state(*calls, route="earpiece", agent=True):
    return {"agent": agent, "route": route, "calls": [{"state": c} for c in calls]}


check("an active call on the earpiece wants it", cp.wanted(state("active")))
check("dialling and ringing out want it", cp.wanted(state("dialing")) and cp.wanted(state("ringing-out")))
check("a ringing incoming call doesn't", not cp.wanted(state("ringing-in")))
check("a held call alone doesn't", not cp.wanted(state("held")))
check("one active call among others does", cp.wanted(state("held", "active")))
check("the speaker doesn't", not cp.wanted(state("active", route="speaker")))
check("Bluetooth doesn't", not cp.wanted(state("active", route="bluetooth")))
check("no agent, no call", not cp.wanted(state("active", agent=False)))
check("no calls, nothing", not cp.wanted(state()))

with tempfile.TemporaryDirectory() as root:
    def device(n, sw):
        d = os.path.join(root, "class/input/input%d" % n)
        os.makedirs(d + "/capabilities")
        os.makedirs(d + "/event%d" % (n + 3))
        with open(d + "/capabilities/sw", "w") as f:
            f.write(sw + "\n")
    device(4, "0")            # a device without switches
    device(2, "10")           # bit 4 only: SW_MICROPHONE_INSERT
    device(9, "800")          # bit 11: SW_FRONT_PROXIMITY
    check("the proximity switch is found by its capability",
          cp.find_proximity_switch(root) == "/dev/input/event12", cp.find_proximity_switch(root))

def lockable(path):
    """Whether a shared lock on the marker can be had now, as
    omamobile-keys dark-unlocked tries it: yes means no owner holds it."""
    fd = os.open(path, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
        return True
    except BlockingIOError:
        return False
    finally:
        os.close(fd)


with tempfile.TemporaryDirectory() as run:
    os.environ["XDG_RUNTIME_DIR"] = run
    flag = os.path.join(run, "omamobile-call-proximity")
    check("no marker, nothing stale", not cp.clear_stale())
    with open(flag, "w") as f:
        f.write("4242\n")
    check("a marker no one holds is stale and removed", cp.clear_stale() and not os.path.exists(flag))

with tempfile.TemporaryDirectory() as run:
    os.environ["XDG_RUNTIME_DIR"] = run
    cp.find_touchscreen = lambda sysfs="/sys": None     # nothing to grab here
    ran, now = [], [100.0]
    b = cp.Blank(run=lambda argv, check=False: ran.append(argv[-1]), clock=lambda: now[0])
    flag = os.path.join(run, "omamobile-call-proximity")

    b.follow(False, False)
    check("far on a lit screen does nothing", ran == [] and not b.on)
    b.follow(True, False)
    check("near turns the panel off and marks it", ran == ["off"] and b.on and os.path.exists(flag), ran)
    check("the marker names its owner", open(flag).read() == "%d\n" % os.getpid())
    check("and its owner holds the lock on it", not lockable(flag))
    check("a held marker is not stale", not cp.clear_stale() and os.path.exists(flag))
    now[0] += 0.3
    b.follow(True, False)
    check("a panel still reading lit just after does not count as lit by hand", b.on and ran == ["off"])
    b.follow(False, True)
    check("far turns it back on and clears the mark", ran == ["off", "on"] and not b.on and not os.path.exists(flag), ran)

    ran.clear()
    b.follow(True, True)
    check("near on a panel already dark (the power key) leaves it", ran == [] and not b.on)

    ran.clear()
    b.follow(True, False)
    now[0] += 2
    b.follow(True, False)
    check("lit by hand while near: kept lit, mark gone", ran == ["off"] and not b.on and not os.path.exists(flag), ran)
    b.follow(True, False)
    check("and not turned off again while still near", ran == ["off"] and not b.on, ran)
    b.follow(False, False)
    b.follow(True, False)
    check("after far, near turns it off again", ran == ["off", "off"] and b.on, ran)
    b.stop()

with tempfile.TemporaryDirectory() as d:
    check("off without the device's opt-in file", not cp.enabled(os.path.join(d, "call-proximity")))
    open(os.path.join(d, "call-proximity"), "w").close()
    check("on with it", cp.enabled(os.path.join(d, "call-proximity")))
check("the unit runs only with the opt-in file",
      "ConditionPathExists=/usr/share/omamobile/call-proximity\n" in
      open(os.path.join(os.path.dirname(TOOL), "..", "systemd/user/omamobile-call-proximity.service")).read())

# The whole tool in a child process: a call on the earpiece and the proximity
# near, so it turns the panel off and grabs the touchscreen (a FIFO here, the
# grab ioctl recorded); then a signal or a kill. Stand-ins on PATH record the
# panel commands and omamobile-keys.
CHILD = r"""
import importlib.machinery, importlib.util, os, sys, fcntl as real_fcntl
tool, d = sys.argv[1], sys.argv[2]
loader = importlib.machinery.SourceFileLoader("call_proximity", tool)
spec = importlib.util.spec_from_loader("call_proximity", loader)
cp = importlib.util.module_from_spec(spec)
loader.exec_module(cp)
def log(line):
    with open(d + "/log", "a") as f:
        f.write(line + "\n")
class Fcntl:
    LOCK_EX, LOCK_SH, LOCK_NB = real_fcntl.LOCK_EX, real_fcntl.LOCK_SH, real_fcntl.LOCK_NB
    flock = staticmethod(real_fcntl.flock)
    @staticmethod
    def ioctl(fd, req, arg):
        if req == cp.EVIOCGRAB:
            log("grab %d" % arg)
cp.fcntl = Fcntl
release = cp.Blank._release_touch
def logged_release(self):
    if self.touch is not None:
        log("release")
    release(self)
cp.Blank._release_touch = logged_release
class Near:
    def fileno(self): return None
    def update(self): return True
    def close(self): pass
cp.open_source = lambda: Near()
cp.find_touchscreen = lambda sysfs="/sys": d + "/touch"
cp.screen_dark = lambda sysfs="/sys": open(d + "/panel").read().strip() == "off"
keep = os.open(d + "/touch", os.O_RDWR)   # a writer, so the FIFO never reads as ended
cp.main()
"""


def child_env(d, call):
    bin_ = os.path.join(d, "bin")
    os.makedirs(bin_, exist_ok=True)
    stubs = {
        "omamobile-call-watch": "echo '%s'\nexec sleep 600\n" % call,
        "omarchy-brightness-display": 'echo "panel $1" >>"%s/log"; echo "$1" >"%s/panel"\n' % (d, d),
        "omamobile-keys": 'echo "omamobile-keys $*" >>"%s/log"\n' % d,
    }
    for name, body in stubs.items():
        path = os.path.join(bin_, name)
        with open(path, "w") as f:
            f.write("#!/bin/bash\n" + body)
        os.chmod(path, 0o755)
    with open(os.path.join(d, "enable"), "w"):
        pass
    with open(os.path.join(d, "child.py"), "w") as f:
        f.write(CHILD)
    env = dict(os.environ, PATH=bin_ + os.pathsep + os.environ["PATH"], XDG_RUNTIME_DIR=os.path.join(d, "run"),
               OMAMOBILE_CALL_PROXIMITY_ENABLE=os.path.join(d, "enable"))
    return env


IN_CALL = '{"agent": true, "route": "earpiece", "calls": [{"state": "active"}]}'
NO_CALL = '{"agent": true, "route": "earpiece", "calls": []}'


def start_child(d, call):
    env = child_env(d, call)
    return subprocess.Popen([sys.executable, "-B", os.path.join(d, "child.py"), TOOL, d], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def logged(d):
    try:
        return open(os.path.join(d, "log")).read().split("\n")[:-1]
    except FileNotFoundError:
        return []


def wait_for(cond, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.05)
    return False


def blanked_child(d):
    os.makedirs(os.path.join(d, "run"))
    os.mkfifo(os.path.join(d, "touch"))
    with open(os.path.join(d, "panel"), "w") as f:
        f.write("on\n")
    p = start_child(d, IN_CALL)
    ok = wait_for(lambda: logged(d) == ["grab 1", "panel off"])
    return p, ok


for sig in (signal.SIGTERM, signal.SIGHUP):
    with tempfile.TemporaryDirectory() as d:
        flag = os.path.join(d, "run", "omamobile-call-proximity")
        p, ok = blanked_child(d)
        name = signal.Signals(sig).name
        check("%s: the child blanks the panel, grabs and holds the marker" % name,
              ok and os.path.exists(flag) and not lockable(flag), logged(d))
        p.send_signal(sig)
        try:
            out = p.communicate(timeout=10)[0]
        except subprocess.TimeoutExpired:
            p.kill()
            out = p.communicate()[0]
        check("%s while blanked: a clean exit" % name, p.returncode == 0, (p.returncode, out))
        check("%s while blanked: the panel on and the grab released" % name,
              logged(d) == ["grab 1", "panel off", "panel on", "release"], logged(d))
        check("%s while blanked: the marker removed" % name, not os.path.exists(flag))

with tempfile.TemporaryDirectory() as d:
    flag = os.path.join(d, "run", "omamobile-call-proximity")
    p, ok = blanked_child(d)
    check("SIGKILL: the child blanks the panel and holds the marker", ok and not lockable(flag), logged(d))
    p.kill()
    p.communicate()
    check("SIGKILL: the marker stays, but its lock died with its owner",
          os.path.exists(flag) and lockable(flag))
    os.unlink(os.path.join(d, "log"))
    # The next start, no call: the stale marker goes, and the screen still
    # dark (the killed run's "off") locks through omamobile-keys.
    p = start_child(d, NO_CALL)
    check("the next start removes the stale marker", wait_for(lambda: not os.path.exists(flag)))
    check("and asks omamobile-keys to lock the dark screen",
          wait_for(lambda: logged(d) == ["omamobile-keys dark-unlocked"]), logged(d))
    p.terminate()
    p.communicate(timeout=10)
    check("a stop with the panel lit runs nothing", logged(d) == ["omamobile-keys dark-unlocked"], logged(d))

with tempfile.TemporaryDirectory() as d:
    os.makedirs(os.path.join(d, "run"))
    os.mkfifo(os.path.join(d, "touch"))
    flag = os.path.join(d, "run", "omamobile-call-proximity")
    with open(flag, "w") as f:
        f.write("4242\n")
    with open(os.path.join(d, "panel"), "w") as f:
        f.write("on\n")
    p = start_child(d, NO_CALL)
    check("a stale marker with the screen lit: removed",
          wait_for(lambda: not os.path.exists(flag)))
    p.terminate()
    p.communicate(timeout=10)
    check("and nothing locked", logged(d) == [], logged(d))

sys.exit(1 if failures else 0)
