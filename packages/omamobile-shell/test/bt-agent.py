# SPDX-License-Identifier: MIT
# Tests for bin/omamobile-bt-agent's pure helpers; no D-Bus needed. Run by test/all.
import importlib.machinery
import importlib.util
import io
import json
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("bt_agent", os.path.join(here, "..", "bin", "omamobile-bt-agent"))
spec = importlib.util.spec_from_loader("bt_agent", loader)
agent = importlib.util.module_from_spec(spec)
loader.exec_module(agent)

failed = 0


def check(name, fn):
    global failed
    try:
        fn()
        print("ok - bt agent: " + name)
    except AssertionError as error:
        failed += 1
        print("not ok - bt agent: %s\n  %s" % (name, error), file=sys.stderr)


def commands():
    assert agent.parse_command('{"cmd": "pair", "address": "AA"}') == {"cmd": "pair", "address": "AA"}
    assert agent.parse_command("not json") is None
    assert agent.parse_command('{"event": "ready"}') is None
    assert agent.parse_command("[1, 2]") is None


def replies():
    assert agent.reply_value("pin", "0000") == "0000"
    assert agent.reply_value("pin", "") is None
    assert agent.reply_value("pin", "x" * 17) is None
    assert agent.reply_value("passkey", "012345") == 12345
    assert agent.reply_value("passkey", "1234567") is None
    assert agent.reply_value("passkey", "12a") is None
    assert agent.reply_value("passkey", None) is None
    assert agent.reply_value("confirm", None) is True


def extras():
    event = agent.device_extras("AA:BB", {"RSSI": -61, "Class": 0x240418})
    assert event == {"event": "device", "address": "AA:BB", "rssi": -61, "appearance": None, "class": 0x240418}, event


def errors():
    class Fake(Exception):
        def get_dbus_name(self):
            return "org.bluez.Error.AuthenticationFailed"

        def get_dbus_message(self):
            return "Authentication Failed"
    event = agent.error_event("pair", "AA", "pair", Fake())
    assert event["ok"] is False and event["error"] == "org.bluez.Error.AuthenticationFailed", event


def emits_json_lines():
    out = io.StringIO()
    real, sys.stdout = sys.stdout, out
    try:
        agent.emit({"event": "cancel"})
    finally:
        sys.stdout = real
    assert json.loads(out.getvalue()) == {"event": "cancel"}
    assert out.getvalue().endswith("\n")


def arguments():
    assert agent.parse_args([]) is None
    assert agent.parse_args(["--pairable-window", "120"]) == 120
    for bad in (["--pairable-window"], ["--pairable-window", "0"], ["--pairable-window", "-5"],
                ["--pairable-window", "x"], ["--pairable-window", "3601"], ["--other", "120"]):
        try:
            agent.parse_args(bad)
        except ValueError:
            continue
        raise AssertionError("accepted %r" % bad)


def pairable_window():
    plan = agent.pairable_plan
    # Without the window the helper never touches Pairable.
    for event in ("start", "request", "changed", "exit"):
        assert plan(None, event, True, True) == [] and plan(None, event, False, True) == [], event
    # Registering turned it on: off again, with BlueZ's own limit in place.
    assert plan(120, "start") == [("PairableTimeout", 120), ("Pairable", False)], plan(120, "start")
    # On only when asked, timeout first (it restarts BlueZ's timer), off when asked.
    assert plan(120, "request", True) == [("PairableTimeout", 120), ("Pairable", True)]
    assert plan(120, "request", False) == [("Pairable", False)]
    # Back on unasked (an agent registering): off; on while wanted, or off: left.
    assert plan(120, "changed", False, True) == [("Pairable", False)]
    assert plan(120, "changed", True, True) == []
    assert plan(120, "changed", False, False) == []
    # BlueZ's timeout ended it while still wanted: it stays off.
    assert plan(120, "changed", True, False) == []
    assert plan(120, "exit", True, True) == [("Pairable", False)]
    assert plan(120, "exit") == [("Pairable", False)]


check("stdin commands parse, junk doesn't", commands)
check("the command line takes only --pairable-window 1-3600", arguments)
check("Pairable: off at start and exit, on only on request with BlueZ's timeout", pairable_window)
check("PINs are 1-16 characters, passkeys 0-999999", replies)
check("device extras carry RSSI, appearance and class", extras)
check("D-Bus errors become result events", errors)
check("events are one JSON object per line", emits_json_lines)
sys.exit(1 if failed else 0)
