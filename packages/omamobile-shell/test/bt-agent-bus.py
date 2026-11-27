# SPDX-License-Identifier: MIT
"""omamobile-bt-agent's pairing window against test/fake-bluez.py on a
private D-Bus daemon (never the machine's system bus). Run by test/all;
exits 77 when dbus-daemon or python-dbus is missing."""
import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
AGENT = os.path.join(HERE, "..", "bin", "omamobile-bt-agent")
FAKE = os.path.join(HERE, "fake-bluez.py")
BUS_CONFIG = """<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>omamobile-bt-agent-test</type>
  <listen>unix:path={path}</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow user="*"/>
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
  </policy>
</busconfig>
"""

try:
    import dbus  # noqa: F401
    from gi.repository import GLib  # noqa: F401
except ImportError:
    sys.exit(77)
if not shutil.which("dbus-daemon") or not shutil.which("dbus-send"):
    sys.exit(77)

failed = 0


def wait_for(predicate, seconds=6):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


class Run:
    """A private bus, the fake BlueZ and the helper with ARGS."""

    def __init__(self, args, quiet=False):
        self.dir = tempfile.mkdtemp(prefix="bt-agent-bus.")
        path = os.path.join(self.dir, "bus")
        config = os.path.join(self.dir, "bus.conf")
        with open(config, "w") as f:
            f.write(BUS_CONFIG.format(path=path))
        self.log = os.path.join(self.dir, "bluez.log")
        self.procs = []
        self.bus = self.start(["dbus-daemon", "--nofork", "--config-file=" + config])
        assert wait_for(lambda: os.path.exists(path)), "the private bus started"
        # The helper's timed unblock goes to a recorder, never the laptop's own systemd
        self.timers = os.path.join(self.dir, "timers.log")
        recorder = os.path.join(self.dir, "systemd-run")
        with open(recorder, "w") as f:
            f.write('#!/bin/sh\nprintf "%%s\\n" "$*" >> %s\n' % self.timers)
        os.chmod(recorder, 0o755)
        self.env = env = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS="unix:path=" + path, PYTHONDONTWRITEBYTECODE="1",
                   FAKE_BLUEZ_QUIET="1" if quiet else "", OMAMOBILE_BT_SYSTEMD_RUN=recorder)
        self.start([sys.executable, "-I", FAKE, self.log], env=env)
        assert wait_for(lambda: any(e.get("call") == "ready" for e in self.entries())), "the fake BlueZ started"
        self.agent = self.start([sys.executable, "-I", AGENT] + args, env=env,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.lines = []
        self.pending = b""
        assert wait_for(lambda: self.read() and any(e.get("event") == "ready" for e in self.lines)), \
            "the helper is ready (%r)" % self.lines

    def start(self, argv, **kwargs):
        kwargs.setdefault("stdout", subprocess.DEVNULL)
        proc = subprocess.Popen(argv, stderr=subprocess.DEVNULL, **kwargs)
        self.procs.append(proc)
        return proc

    def read(self):
        # Raw reads: a buffered readline can take several lines at once and
        # leave select() with nothing to report for the rest.
        fd = self.agent.stdout.fileno()
        while select.select([fd], [], [], 0)[0]:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            self.pending += chunk
        *whole, self.pending = self.pending.split(b"\n")
        self.lines += [json.loads(line) for line in whole if line.strip()]
        return True

    def send(self, command):
        self.agent.stdin.write((json.dumps(command) + "\n").encode())
        self.agent.stdin.flush()

    def bluez_set_pairable(self, value):
        subprocess.run(["dbus-send", "--system", "--print-reply", "--dest=org.bluez", "/org/bluez/hci0",
                        "org.freedesktop.DBus.Properties.Set", "string:org.bluez.Adapter1", "string:Pairable",
                        "variant:boolean:" + ("true" if value else "false")],
                       env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=10)

    def test_call(self, method):
        subprocess.run(["dbus-send", "--system", "--print-reply", "--dest=org.bluez",
                        "/org/bluez/hci0/dev_00_11_22_33_44_55", "org.omamobile.Test." + method],
                       env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=10)

    def entries(self):
        try:
            with open(self.log) as f:
                return [json.loads(line) for line in f]
        except FileNotFoundError:
            return []

    def sets(self, name="Pairable"):
        """The values set, a repeat of the one before folded in (a retried
        off and the off for BlueZ's own change can both land)."""
        values = []
        for e in self.entries():
            if e.get("set") == name and (name != "Pairable" or not values or values[-1] != e["value"]):
                values.append(e["value"])
        return values

    def pairable(self):
        """Pairable as the fake BlueZ holds it, from the log: the last change."""
        state = False
        for e in self.entries():
            if e.get("call") == "RegisterAgent":
                state = "pending"
            if e.get("set") == "Pairable":
                state = e["value"]
            if e.get("call") == "UnregisterAgent":
                state = False
        return state

    def close(self):
        self.agent.stdin.close()
        try:
            self.agent.wait(10)
        except subprocess.TimeoutExpired:
            pass

    def end(self):
        for proc in reversed(self.procs):
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(5)
                except subprocess.TimeoutExpired:
                    proc.kill()
        shutil.rmtree(self.dir, ignore_errors=True)


def check(name, args, body, quiet=False):
    global failed
    run = None
    try:
        run = Run(args, quiet)
        body(run)
        print("ok - bt agent on a bus: " + name)
    except AssertionError as error:
        failed += 1
        log = run.entries() if run else []
        print("not ok - bt agent on a bus: %s\n  %s\n  BlueZ log: %s" % (name, error, log), file=sys.stderr)
    finally:
        if run:
            run.end()


def window(run):
    # Registering turned Pairable on (pending); the helper's off waited out
    # BlueZ's Busy and landed, with BlueZ's own timeout set first.
    assert wait_for(lambda: run.sets() == [False]), "Pairable set off after registering: %r" % run.sets()
    entries = run.entries()
    assert any(e.get("busy") == "Pairable" for e in entries), "the first off met Busy and was retried"
    assert run.sets("PairableTimeout") == [120], run.sets("PairableTimeout")
    assert wait_for(lambda: run.pairable() is False), "off at rest"
    time.sleep(0.6)  # nothing turns it back on by itself
    assert run.sets() == [False], run.sets()
    # Someone else turns it on (bluetoothctl, another agent): off again.
    run.bluez_set_pairable(True)
    assert wait_for(lambda: run.sets() == [False, True, False]), "back off: %r" % run.sets()
    sets_before = len(run.sets())
    # On when asked, with the timeout again (it restarts BlueZ's timer).
    run.send({"cmd": "pairable", "on": True})
    assert wait_for(lambda: run.sets()[sets_before:] == [True]), run.sets()
    assert run.sets("PairableTimeout") == [120, 120], run.sets("PairableTimeout")
    run.send({"cmd": "pairable", "on": False})
    assert wait_for(lambda: run.sets()[sets_before:] == [True, False]), run.sets()
    # On again, then the panel closes: off before the agent leaves.
    run.send({"cmd": "pairable", "on": True})
    assert wait_for(lambda: run.sets()[sets_before:] == [True, False, True]), run.sets()
    run.close()
    entries = run.entries()
    assert run.agent.returncode == 0, "exit %r" % run.agent.returncode
    unregister = [i for i, e in enumerate(entries) if e.get("call") == "UnregisterAgent"]
    assert unregister, "the agent unregistered: %r" % entries
    before = [e["value"] for e in entries[:unregister[0]] if e.get("set") == "Pairable"]
    assert before and before[-1] is False, "Pairable set off after the last on, before UnregisterAgent: %r" % entries
    assert run.pairable() is False


def missed_signal(run):
    # BlueZ's change for our registration landed before the helper listened
    # (FAKE_BLUEZ_QUIET): only the retry after Busy turns Pairable off.
    assert wait_for(lambda: run.sets() == [False]), "Pairable set off after Busy: %r" % run.entries()
    run.close()


def leaves_alone(run):
    # No window: the helper never sets Pairable (the owner's own setting).
    run.send({"cmd": "pairable", "on": True})
    run.send({"cmd": "pairable", "on": False})
    time.sleep(1)
    run.close()
    assert run.sets() == [] and run.sets("PairableTimeout") == [], run.entries()


def disconnect_holds(run):
    # The panel's disconnect: Blocked before the Disconnect, and the
    # device's own reconnect is then refused.
    run.send({"cmd": "disconnect", "address": "02:00:00:00:00:01"})
    assert wait_for(lambda: run.read() and any(e.get("op") == "disconnect" for e in run.lines)), run.lines
    assert [e for e in run.lines if e.get("op") == "disconnect"][-1]["ok"], run.lines
    calls = [e for e in run.entries() if "device_set" in e or "device_call" in e]
    assert calls[:2] == [{"device_set": "Blocked", "value": True}, {"device_call": "Disconnect", "trusted": True}], calls
    # The block is only for a while: two minutes on, the user's manager lifts it
    timers = open(run.timers).read() if os.path.exists(run.timers) else ""
    assert timers.strip() == "--user --quiet --collect --on-active=120 bluetoothctl unblock 02:00:00:00:00:01", timers
    run.test_call("Reconnect")
    assert wait_for(lambda: any(e.get("reconnect") for e in run.entries())), run.entries()
    assert [e for e in run.entries() if e.get("reconnect")][-1]["reconnect"] == "rejected", \
        "a paired device the owner disconnected is not let back: %r" % run.entries()
    # The panel's connect lifts the block and marks it Trusted, then connects; its own reconnects are welcome again.
    run.send({"cmd": "connect", "address": "02:00:00:00:00:01"})
    assert wait_for(lambda: run.read() and any(e.get("op") == "connect" for e in run.lines)), run.lines
    calls = [e for e in run.entries() if "device_set" in e or "device_call" in e]
    assert calls[2:5] == [{"device_set": "Blocked", "value": False}, {"device_set": "Trusted", "value": True},
                          {"device_call": "Connect", "trusted": True}], calls
    run.close()


def accepted_pairing_trusted(run):
    # A car pairs to the phone: the owner says yes to its code, and once it
    # has paired it is Trusted, so its calls and audio are let in.
    run.test_call("IncomingPair")
    assert wait_for(lambda: run.read() and any(e.get("event") == "request" for e in run.lines)), run.lines
    request = [e for e in run.lines if e.get("event") == "request"][-1]
    assert request["type"] == "confirm" and request["passkey"] == 123456, request
    assert request["address"] == "02:00:00:00:00:01", request
    run.send({"cmd": "reply", "id": request["id"], "accept": True})
    assert wait_for(lambda: any(e.get("incoming") == "paired" for e in run.entries())), run.entries()
    assert wait_for(lambda: {"device_set": "Trusted", "value": True} in run.entries()), run.entries()
    run.test_call("Reconnect")
    assert wait_for(lambda: any(e.get("reconnect") for e in run.entries())), run.entries()
    assert [e for e in run.entries() if e.get("reconnect")][-1]["reconnect"] == "trusted", run.entries()
    run.close()


def refused_pairing_untrusted(run):
    # The owner says no: the pairing is refused and nothing is trusted.
    run.test_call("IncomingPair")
    assert wait_for(lambda: run.read() and any(e.get("event") == "request" for e in run.lines)), run.lines
    request = [e for e in run.lines if e.get("event") == "request"][-1]
    run.send({"cmd": "reply", "id": request["id"], "accept": False})
    assert wait_for(lambda: any(e.get("incoming") == "rejected" for e in run.entries())), run.entries()
    time.sleep(0.5)
    assert not any(e.get("device_set") == "Trusted" for e in run.entries()), run.entries()
    run.close()


check("disconnect: Blocked first (for two minutes), the device's own reconnect refused; connect lifts it", [], disconnect_holds)
check("a pairing the owner accepted is Trusted once paired", [], accepted_pairing_trusted)
check("a pairing the owner refused stays untrusted", [], refused_pairing_untrusted)
check("--pairable-window: off after registering, on only when asked, off at exit", ["--pairable-window", "120"], window)
check("--pairable-window: a Busy off is tried again when no change signal follows",
      ["--pairable-window", "120"], missed_signal, quiet=True)
check("without --pairable-window it never touches Pairable", [], leaves_alone)
sys.exit(1 if failed else 0)
