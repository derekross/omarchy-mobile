# SPDX-License-Identifier: MIT
# omamobile-nfc-open's screen_lit() against temporary sysfs trees: connected
# and disconnected connectors, DPMS On and Off, and no connectors at all.
import importlib.machinery, importlib.util, os, sys, tempfile, types
sys.dont_write_bytecode = True  # never a __pycache__ next to bin/omamobile-nfc-open

gi = types.ModuleType("gi"); gi.require_version = lambda *a: None
repo = types.ModuleType("gi.repository"); repo.Gio = repo.GLib = types.SimpleNamespace()
sys.modules.update({"gi": gi, "gi.repository": repo})
loader = importlib.machinery.SourceFileLoader("nfc_open", os.path.join(os.path.dirname(__file__), "..", "bin", "omamobile-nfc-open"))
nfc = importlib.util.module_from_spec(importlib.util.spec_from_loader("nfc_open", loader)); loader.exec_module(nfc)

fails = 0
def case(name, connectors, want):
    global fails
    with tempfile.TemporaryDirectory() as drm:
        for conn, (status, dpms) in connectors.items():
            os.makedirs(f"{drm}/{conn}")
            open(f"{drm}/{conn}/status", "w").write(status + "\n")
            open(f"{drm}/{conn}/dpms", "w").write(dpms + "\n")
        got = nfc.screen_lit(drm)
    print(("ok" if got == want else "not ok") + f" - {name}")
    fails += got != want

case("panel on", {"card1-DSI-1": ("connected", "On")}, True)
case("panel off", {"card1-DSI-1": ("connected", "Off")}, False)
case("panel off, a disconnected output on", {"card1-DSI-1": ("connected", "Off"), "card1-DP-1": ("disconnected", "On")}, False)
case("two connected, one on", {"card1-DSI-1": ("connected", "Off"), "card1-HDMI-A-1": ("connected", "On")}, True)
case("only a disconnected output", {"card1-DP-1": ("disconnected", "Off")}, True)
case("no connectors at all", {}, True)
sys.exit(1 if fails else 0)
