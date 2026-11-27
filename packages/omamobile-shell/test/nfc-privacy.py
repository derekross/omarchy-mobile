# SPDX-License-Identifier: MIT
# omamobile-nfc-open with NFC off totally: the privacy file, the rfkill switch
# and neard, against a temporary file and recorded commands (nothing runs).
import importlib.machinery, importlib.util, os, sys, tempfile, types
sys.dont_write_bytecode = True  # never a __pycache__ next to bin/omamobile-nfc-open

gi = types.ModuleType("gi"); gi.require_version = lambda *a: None
repo = types.ModuleType("gi.repository"); repo.Gio = repo.GLib = types.SimpleNamespace()
sys.modules.update({"gi": gi, "gi.repository": repo})
loader = importlib.machinery.SourceFileLoader("nfc_open", os.path.join(os.path.dirname(__file__), "..", "bin", "omamobile-nfc-open"))
nfc = importlib.util.module_from_spec(importlib.util.spec_from_loader("nfc_open", loader)); loader.exec_module(nfc)

fails = 0
def check(name, ok):
    global fails
    print(("ok" if ok else "not ok") + f" - {name}")
    fails += not ok

tmp = tempfile.mkdtemp()
path = os.path.join(tmp, "nfc")
nfc.PRIVACY_FILE = path
nfc.nfc_off.__defaults__ = (path,)
radio = {"blocked": False}
ran = []
def run(cmd, check=False):
    ran.append(cmd)
    if cmd == ["rfkill", "block", "nfc"]:
        radio["blocked"] = True
nfc.subprocess = types.SimpleNamespace(run=run)
nfc.nfc_blocked = lambda: radio["blocked"]
nfc.log = lambda m: None
polls = []
nfc.start_polling = lambda bus: polls.append(1) or False
nfc.GLib = types.SimpleNamespace(timeout_add_seconds=lambda s, f, *a: polls.append(1))
def write(text):
    with open(path, "w") as f:
        f.write(text)
def reset(blocked):
    ran.clear(); polls.clear(); radio["blocked"] = blocked
    nfc.rfkill["blocked"] = blocked; nfc.privacy["off"] = False

# no file: on, as before
check("no file is on", nfc.nfc_off() is False)
write("off\n"); check("\"off\" is off", nfc.nfc_off() is True)
write("on\n"); check("anything else is on", nfc.nfc_off() is False)
os.chmod(path, 0)
if os.geteuid() != 0:
    check("an unreadable file is off", nfc.nfc_off() is True)
os.chmod(path, 0o644); os.remove(path)

# off: stops neard once, blocks, never restarts neard or polls
reset(False); write("off\n")
nfc.follow_rfkill(None)
check("off blocks the switch", radio["blocked"] and ["rfkill", "block", "nfc"] in ran)
check("off stops neard", ran.count(["systemctl", "stop", "neard.service"]) == 1)
nfc.follow_rfkill(None)
check("neard is stopped once", ran.count(["systemctl", "stop", "neard.service"]) == 1)
# something in the session unblocks the switch: blocked again, no neard restart
radio["blocked"] = False; ran.clear()
nfc.follow_rfkill(None)
check("an unblock while off is blocked again", radio["blocked"] and ran == [["rfkill", "block", "nfc"]])
check("no neard restart while off", not any(c[:2] == ["systemctl", "restart"] for c in ran))
nfc.restart_neard(None)
check("restart_neard does nothing while off", not any(c[:2] == ["systemctl", "restart"] for c in ran))
# the screen comes on: no polling
nfc.screen.update(lit=False, dark_for=10, start=False)
nfc.screen_lit = lambda: True
polls.clear(); nfc.follow_screen(None)
check("the screen on doesn't poll while off", polls == [])

# on, the helper's order: file removed, then unblocked
os.remove(path); ran.clear()
nfc.follow_rfkill(None)   # file gone, switch still blocked
check("file gone, still blocked: nothing yet", ran == [] and nfc.privacy["off"] is False)
radio["blocked"] = False
nfc.follow_rfkill(None)
check("the unblock restarts neard", ["systemctl", "restart", "neard"] in ran)
# both at once (one tick sees the file gone and the switch unblocked)
reset(True); write("off\n"); nfc.follow_rfkill(None)
os.remove(path); radio["blocked"] = False; ran.clear()
nfc.follow_rfkill(None)
check("file gone and unblocked in one tick restarts neard", ran == [["systemctl", "restart", "neard"]])

# nfc-on lands while a tick is blocking: the tick undoes its own block
reset(False); write("off\n")
real = run
def racing(cmd, check=False):
    real(cmd, check)
    if cmd == ["rfkill", "block", "nfc"] and os.path.exists(path):
        os.remove(path)  # the helper's nfc-on: file removed (it then unblocks)
        radio["blocked"] = False
    if cmd == ["rfkill", "unblock", "nfc"]:
        radio["blocked"] = False
nfc.subprocess = types.SimpleNamespace(run=racing)
nfc.follow_rfkill(None)
nfc.follow_rfkill(None)
check("an on during an off's tick ends on, neard restarted", not radio["blocked"]
      and ["systemctl", "restart", "neard"] in ran and nfc.privacy["off"] is False)
nfc.subprocess = types.SimpleNamespace(run=run)

# boot with the file: main()'s first step stops neard and keeps the switch blocked
reset(False); write("off\n")
check("boot while off", nfc.follow_privacy() is True and radio["blocked"]
      and ["systemctl", "stop", "neard.service"] in ran)
os.remove(path); os.rmdir(tmp)
sys.exit(1 if fails else 0)
