#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Tests for bin/omamobile-cell-watch: the state mapping, then the watcher
on a private session bus (--session; test/all runs it under
dbus-run-session) against a fake ModemManager: no modem, no SIM,
searching, registered on LTE with and without a signal reading, mobile
data, roaming, and the modem going away."""

import importlib.machinery
import importlib.util
import json
import os
import select
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "bin", "omamobile-cell-watch")
failures = 0


def check(name, condition, detail=""):
    global failures
    print("%s - cell watch: %s%s" % ("ok" if condition else "not ok", name, "" if condition else "  # " + str(detail)))
    if not condition:
        failures += 1


loader = importlib.machinery.SourceFileLoader("cell_watch", TOOL)
spec = importlib.util.spec_from_loader("cell_watch", loader)
cw = importlib.util.module_from_spec(spec)
loader.exec_module(cw)

d = cw.describe
check("no modem", d(None, None) == {"modem": False, "state": "none", "strength": -1, "tech": "", "roaming": False})
check("a missing SIM", d({"State": -1, "StateFailedReason": 2}, {})["state"] == "no-sim")
check("another failure", d({"State": -1, "StateFailedReason": 1}, {})["state"] == "failed")
check("a SIM PIN", d({"State": 2}, {})["state"] == "locked")
check("radio off", d({"State": 3}, {})["state"] == "off")
check("searching, no strength or tech",
      d({"State": 7, "AccessTechnologies": 1 << 14, "SignalQuality": (60, True)}, {}) ==
      {"modem": True, "state": "searching", "strength": -1, "tech": "", "roaming": False})
lte = d({"State": 8, "AccessTechnologies": 1 << 14, "SignalQuality": (71, True)}, {"RegistrationState": 1})
check("registered on LTE with a recent reading", lte["state"] == "registered" and lte["tech"] == "LTE" and lte["strength"] == 71, lte)
check("an old reading isn't shown", d({"State": 8, "AccessTechnologies": 1 << 14, "SignalQuality": (71, False)}, {})["strength"] == -1)
check("best technology wins", cw.tech_label((1 << 15) | (1 << 14)) == "5G" and cw.tech_label(1 << 9) == "H+" and cw.tech_label(1 << 5) == "3G")
check("mobile data", d({"State": 11, "AccessTechnologies": 1 << 14}, {})["state"] == "connected")
check("roaming", d({"State": 8}, {"RegistrationState": 5})["roaming"] is True)
check("no identifiers in the line", set(lte) == {"modem", "state", "strength", "tech", "roaming"})


def bus_tests():
    import dbus

    fake = r'''
import dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
MM = "org.freedesktop.ModemManager1"
MODEM = MM + ".Modem"
GPP = MODEM + ".Modem3gpp"
OM = "org.freedesktop.DBus.ObjectManager"
PATH = "/org/freedesktop/ModemManager1/Modem/0"
class Manager(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, "/org/freedesktop/ModemManager1")
        self.modem = {"State": dbus.Int32(-1), "StateFailedReason": dbus.UInt32(2),
                      "AccessTechnologies": dbus.UInt32(0), "SignalQuality": dbus.Struct((dbus.UInt32(0), False), signature="ub")}
        self.gpp = {"RegistrationState": dbus.UInt32(0)}
        self.present = True
    @dbus.service.method(OM, out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        if not self.present:
            return dbus.Dictionary({}, signature="oa{sa{sv}}")
        return {dbus.ObjectPath(PATH): {MODEM: dbus.Dictionary(self.modem, signature="sv"),
                                        GPP: dbus.Dictionary(self.gpp, signature="sv")}}
    @dbus.service.signal(dbus.PROPERTIES_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, i, c, x): pass
    @dbus.service.signal(OM, signature="oas")
    def InterfacesRemoved(self, p, i): pass
    @dbus.service.method("org.test.Control", in_signature="s")
    def Do(self, what):
        if what == "search":
            self.modem["State"] = dbus.Int32(7); self.modem["StateFailedReason"] = dbus.UInt32(0)
        elif what == "lte":
            self.modem["State"] = dbus.Int32(8); self.modem["AccessTechnologies"] = dbus.UInt32(1 << 14)
            self.gpp["RegistrationState"] = dbus.UInt32(1)
        elif what == "signal":
            self.modem["SignalQuality"] = dbus.Struct((dbus.UInt32(64), True), signature="ub")
        elif what == "data":
            self.modem["State"] = dbus.Int32(11)
        elif what == "remove":
            self.present = False
            self.InterfacesRemoved(dbus.ObjectPath(PATH), [MODEM, GPP]); return
        elif what == "bad":
            # A broken property, without a signal: the watcher must keep going.
            self.modem["State"] = dbus.String("bogus"); return
        elif what.startswith("quiet-"):
            # Registered on LTE at this strength, without a signal.
            self.registered(int(what[6:])); return
        self.PropertiesChanged(MODEM, {}, [])
    def registered(self, strength):
        self.modem.update(State=dbus.Int32(8), StateFailedReason=dbus.UInt32(0),
                          AccessTechnologies=dbus.UInt32(1 << 14),
                          SignalQuality=dbus.Struct((dbus.UInt32(strength), True), signature="ub"))
        self.gpp["RegistrationState"] = dbus.UInt32(1)
import sys
mode = sys.argv[1] if len(sys.argv) > 1 else "nosim"
bus = dbus.SessionBus()
name = dbus.service.BusName(MM, bus)
m = Manager(bus)
if mode == "offfix":
    # As omamobile-mmd once did: power off / disabled at first, fixed a
    # moment later with no PropertiesChanged and no InterfacesAdded.
    m.modem.update(State=dbus.Int32(3), StateFailedReason=dbus.UInt32(0))
    GLib.timeout_add(1500, lambda: (m.registered(58), False)[1])
elif mode == "lte":
    m.registered(80)
print("ready", flush=True)
GLib.MainLoop().run()
'''
    def start_watcher(interval):
        # A long interval leaves the signals and the owner-change re-reads
        # alone to keep the line right; a short one tests the safety net.
        env = dict(os.environ, OMAMOBILE_CELL_WATCH_INTERVAL=str(interval))
        return subprocess.Popen([sys.executable, "-B", TOOL, "--session"], stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True, env=env)

    def start_mm(mode="nosim"):
        mm = subprocess.Popen([sys.executable, "-c", fake, mode], stdout=subprocess.PIPE, text=True)
        assert mm.stdout.readline().strip() == "ready"
        return mm

    def stop(proc):
        proc.terminate()
        proc.wait(timeout=5)

    def until(pred, timeout=5, w=None):
        w = w or watcher
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            r, _, _ = select.select([w.stdout], [], [], max(0, deadline - time.monotonic()))
            if not r:
                return None
            v = json.loads(w.stdout.readline())
            if pred(v):
                return v
        return None

    def do(what):
        dbus.SessionBus().get_object("org.freedesktop.ModemManager1", "/org/freedesktop/ModemManager1").Do(
            what, dbus_interface="org.test.Control")

    watcher = start_watcher(600)
    try:
        check("on a bus: starts with no modem", until(lambda v: v["state"] == "none") is not None)
        mm = start_mm()
        try:
            check("on a bus: a modem with no SIM", until(lambda v: v["state"] == "no-sim") is not None)
            do("search")
            check("on a bus: searching", until(lambda v: v["state"] == "searching") is not None)
            do("lte")
            v = until(lambda v: v["state"] == "registered")
            check("on a bus: registered on LTE, strength unknown", v is not None and v["tech"] == "LTE" and v["strength"] == -1, v)
            do("signal")
            check("on a bus: a signal reading", until(lambda v: v["strength"] == 64) is not None)
            do("data")
            check("on a bus: mobile data", until(lambda v: v["state"] == "connected") is not None)
            do("remove")
            check("on a bus: the modem goes away", until(lambda v: v["state"] == "none") is not None)
        finally:
            stop(mm)

        # The service starts again, exports "off" first and fixes it a
        # moment later without a signal: the owner change's re-reads catch it.
        mm = start_mm("offfix")
        try:
            v = until(lambda v: v["state"] == "registered", timeout=8)
            check("on a bus: a new owner's silent fix is read", v is not None and v["strength"] == 58 and v["tech"] == "LTE", v)
        finally:
            stop(mm)
        check("on a bus: the service stops", until(lambda v: v["state"] == "none") is not None)
        mm = start_mm("lte")
        try:
            v = until(lambda v: v["state"] == "registered")
            check("on a bus: the service starts again, registered", v is not None and v["strength"] == 80, v)

            # The periodic re-read: survives a broken property and picks up
            # a change that came with no signal.
            quick = start_watcher(1)
            try:
                check("on a bus: a second watcher reads the modem",
                      until(lambda v: v["state"] == "registered", w=quick) is not None)
                do("bad")
                time.sleep(2.5)
                do("quiet-33")
                v = until(lambda v: v["strength"] == 33, timeout=5, w=quick)
                check("on a bus: the periodic re-read outlives a bad read and sees a silent change", v is not None, v)
            finally:
                stop(quick)
        finally:
            stop(mm)
    finally:
        stop(watcher)


if os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
    bus_tests()
else:
    print("ok - cell watch: on a bus # SKIP no session bus (run under dbus-run-session)")
sys.exit(1 if failures else 0)
