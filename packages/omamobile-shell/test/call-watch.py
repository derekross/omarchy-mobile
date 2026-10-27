#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Tests for bin/omamobile-call-watch: its helpers, then the watcher on a
private session bus (test/all runs it under dbus-run-session) against a
fake omatel agent: the first line, a call that rings, is answered and ends,
mute, the agent going away and coming back, the quick replies from
omatel's settings, and the CallCard name it holds."""

import importlib.machinery
import importlib.util
import json
import os
import select
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "bin", "omamobile-call-watch")
failures = 0


def check(name, condition, detail=""):
    global failures
    print("%s - call watch: %s%s" % ("ok" if condition else "not ok", name, "" if condition else "  # " + str(detail)))
    if not condition:
        failures += 1


loader = importlib.machinery.SourceFileLoader("call_watch", TOOL)
spec = importlib.util.spec_from_loader("call_watch", loader)
cw = importlib.util.module_from_spec(spec)
loader.exec_module(cw)

# ---------------------------------------------------------------- helpers

with tempfile.TemporaryDirectory() as d:
    p = os.path.join(d, "settings.toml")
    with open(p, "w") as f:
        f.write('quick_replies = ["Driving", "", "Call me later"]\n')
    check("replies come from omatel's settings, blanks dropped", cw.quick_replies(p) == ["Driving", "Call me later"], cw.quick_replies(p))
    check("no settings file: omatel's defaults", cw.quick_replies(os.path.join(d, "none.toml")) == cw.DEFAULT_REPLIES)
    with open(p, "w") as f:
        f.write("quick_replies = 3\n")
    check("a malformed setting: the defaults", cw.quick_replies(p) == cw.DEFAULT_REPLIES)

line = json.loads(cw.state_line(True, [("/c/1", "+12025550123", "Ada", "incoming", "ringing-in", 10, 0)],
                                {"Muted": True, "Route": "speaker"}, ["x"]))
check("a state line carries the calls, mute, route and replies",
      line["calls"][0]["number"] == "+12025550123" and line["muted"] and line["route"] == "speaker" and line["replies"] == ["x"], line)
check("no agent, no calls", json.loads(cw.state_line(False, [("a", "", "", "", "", 0, 0)], {}, []))["calls"] == [])

# The sleep inhibitor: held once while wanted, released once, and a
# failure to take it leaves the phone unheld and retries later.
events = []
hold = cw.SleepHold(take=lambda: events.append("take") or 7, close=lambda fd: events.append(("close", fd)))
hold.update(True); hold.update(True); hold.update(False); hold.update(False)
check("a sleep hold is taken once and released once", events == ["take", ("close", 7)], events)
tries = []
def refuse():
    tries.append(1)
    raise RuntimeError("polkit said no")
hold = cw.SleepHold(take=refuse, close=lambda fd: None)
check("a refused hold leaves the phone unheld", hold.update(True) is False and hold.fd is None)
hold.update(True)
check("and is tried again at the next update", len(tries) == 2, tries)

# ---------------------------------------------------------------- on a bus


def bus_tests():
    import dbus
    import dbus.service
    import dbus.mainloop.glib

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    agent_src = r'''
import sys, dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
IFACE = "org.omamobile.Phone1"
class Phone(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, "/org/omamobile/Phone1")
        self.calls, self.muted, self.silenced = [], False, []
    @dbus.service.method(IFACE, out_signature="a(sssssxx)")
    def ListCalls(self):
        return dbus.Array(self.calls, signature="(sssssxx)")
    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return {"Muted": dbus.Boolean(self.muted), "Route": "earpiece", "AudioRouting": dbus.Boolean(False),
                "SilencedCalls": dbus.Array(self.silenced, signature="s")}
    @dbus.service.signal(IFACE, signature="sss")
    def IncomingCall(self, i, n, m): pass
    @dbus.service.signal(IFACE, signature="(sssssxx)")
    def CallStateChanged(self, c): pass
    @dbus.service.signal(dbus.PROPERTIES_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, i, c, x): pass
    # Test control, over the same bus.
    @dbus.service.method("org.test.Control", in_signature="s")
    def Do(self, what):
        if what == "ring":
            c = ("/c/1", "+12025550123", "Ada Lovelace", "incoming", "ringing-in", 1000, 0)
            self.calls = [c]; self.IncomingCall(c[0], c[1], c[2]); self.CallStateChanged(c)
        elif what == "answer":
            c = ("/c/1", "+12025550123", "Ada Lovelace", "incoming", "active", 1000, 2000)
            self.calls = [c]; self.CallStateChanged(c)
        elif what == "mute":
            self.muted = True; self.PropertiesChanged(IFACE, {"Muted": dbus.Boolean(True)}, [])
        elif what == "quiet":
            c = ("/c/9", "+12025550199", "", "incoming", "ringing-in", 3000, 0)
            self.calls = [c]; self.silenced = ["/c/9"]; self.IncomingCall(c[0], c[1], c[2]); self.CallStateChanged(c)
        elif what == "end":
            c = ("/c/1", "+12025550123", "Ada Lovelace", "incoming", "terminated", 1000, 2000)
            self.calls = []; self.CallStateChanged(c)
bus = dbus.SessionBus()
name = dbus.service.BusName(IFACE, bus)
phone = Phone(bus)
print("ready", flush=True)
GLib.MainLoop().run()
'''

    def start_agent():
        p = subprocess.Popen([sys.executable, "-c", agent_src], stdout=subprocess.PIPE, text=True)
        assert p.stdout.readline().strip() == "ready"
        return p

    def control(what):
        dbus.SessionBus().get_object("org.omamobile.Phone1", "/org/omamobile/Phone1").Do(what, dbus_interface="org.test.Control")

    with tempfile.TemporaryDirectory() as home:
        hold_log = os.path.join(home, "hold.log")
        env = dict(os.environ, XDG_CONFIG_HOME=home, OMAMOBILE_CALL_WATCH_HOLD_LOG=hold_log)

        def holds():
            try:
                with open(hold_log) as f:
                    return f.read().split()
            except FileNotFoundError:
                return []
        os.makedirs(os.path.join(home, "omatel"))
        with open(os.path.join(home, "omatel", "settings.toml"), "w") as f:
            f.write('quick_replies = ["Driving"]\n')
        watcher = subprocess.Popen([sys.executable, "-B", TOOL, "--no-wake"], stdout=subprocess.PIPE, text=True, env=env)

        def next_line(timeout=5):
            r, _, _ = select.select([watcher.stdout], [], [], timeout)
            return json.loads(watcher.stdout.readline()) if r else None

        def until(pred, timeout=5):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                v = next_line(deadline - time.monotonic())
                if v is None:
                    return None
                if pred(v):
                    return v
            return None

        try:
            first = next_line()
            check("starts with a line, no agent yet", first is not None and first["agent"] is False and first["replies"] == ["Driving"], first)
            bus = dbus.SessionBus()
            deadline = time.monotonic() + 5
            while not bus.name_has_owner("org.omamobile.CallCard") and time.monotonic() < deadline:
                time.sleep(0.05)
            check("holds org.omamobile.CallCard", bus.name_has_owner("org.omamobile.CallCard"))

            agent = start_agent()
            try:
                up = until(lambda v: v["agent"])
                check("sees the agent arrive", up is not None and up["calls"] == [], up)
                control("ring")
                ringing = until(lambda v: v["calls"] and v["calls"][0]["state"] == "ringing-in")
                check("a ringing call is reported with its caller",
                      ringing is not None and ringing["calls"][0]["name"] == "Ada Lovelace", ringing)
                check("a ringing call holds sleep off", holds() == ["hold"], holds())
                control("answer")
                active = until(lambda v: v["calls"] and v["calls"][0]["state"] == "active")
                check("the answered call is reported", active is not None and active["calls"][0]["answeredMs"] == 2000, active)
                control("mute")
                muted = until(lambda v: v["muted"])
                check("mute is followed", muted is not None)
                control("end")
                ended = until(lambda v: v["calls"] == [])
                check("the ended call goes away", ended is not None)
                check("the hold lasts the call and ends with it", holds() == ["hold", "release"], holds())
                control("quiet")
                quiet = until(lambda v: v["calls"] and v["calls"][0]["id"] == "/c/9")
                check("a silenced call is marked silenced", quiet is not None and quiet["calls"][0]["silenced"] is True, quiet)
            finally:
                agent.terminate()
                agent.wait(timeout=5)
            gone = until(lambda v: not v["agent"])
            check("sees the agent go away", gone is not None)
            check("an agent gone with a call ringing releases the hold", holds() == ["hold", "release", "hold", "release"], holds())
            agent = start_agent()
            back = until(lambda v: v["agent"])
            check("and come back", back is not None)
            agent.terminate()
            agent.wait(timeout=5)
        finally:
            watcher.terminate()
            watcher.wait(timeout=5)


def observe_test():
    import dbus
    d = tempfile.mkdtemp()
    hold_log = os.path.join(d, "hold.log")
    w = subprocess.Popen([sys.executable, "-B", TOOL, "--observe"], stdout=subprocess.PIPE, text=True,
                         env=dict(os.environ, OMAMOBILE_CALL_WATCH_HOLD_LOG=hold_log))
    try:
        r, _, _ = select.select([w.stdout], [], [], 5)
        first = json.loads(w.stdout.readline()) if r else None
        check("--observe still reports", first is not None and "calls" in first, first)
        check("--observe never takes the card's name", not dbus.SessionBus().name_has_owner("org.omamobile.CallCard"))
        check("--observe never holds sleep off", not os.path.exists(hold_log))
    finally:
        w.terminate()
        w.wait(timeout=5)
        import shutil
        shutil.rmtree(d, ignore_errors=True)


if os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
    bus_tests()
    observe_test()
else:
    print("ok - call watch: on a bus # SKIP no session bus (run under dbus-run-session)")

sys.exit(1 if failures else 0)
