#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# omamobile-text-size against fake config files: each target gets the step's
# value, a second run changes nothing, Default puts everything back, and a
# re-fit by omamobile-browser-setup keeps the chosen step. gsettings, pkill
# and hyprctl are fakes on PATH; the screen is a fake DRM mode with the
# numeric scale in monitors.lua.
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
BIN = Path(__file__).resolve().parents[1] / "bin"
COMMAND = BIN / "omamobile-text-size"

loader = importlib.machinery.SourceFileLoader("browser_setup", str(BIN / "omamobile-browser-setup"))
spec = importlib.util.spec_from_loader(loader.name, loader)
B = importlib.util.module_from_spec(spec)
loader.exec_module(B)

FAKE_GSETTINGS = r'''#!/bin/sh
d=$FAKE_GS; mkdir -p "$d"
case $1 in
  get) if [ -f "$d/$3" ]; then cat "$d/$3"; elif [ "$3" = font-name ]; then echo "'Adwaita Sans 11'"; else echo 1.0; fi ;;
  set) echo "gsettings $*" >>"$FAKE_LOG"; echo "$4" >"$d/$3" ;;
  reset) echo "gsettings $*" >>"$FAKE_LOG"; rm -f "$d/$3" ;;
  *) exit 1 ;;
esac
'''


class TextSizeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.home = root / "home"
        self.config = self.home / ".config"
        self.fake = root / "fake"
        self.drm = root / "drm"
        self.gs = root / "gs"
        self.log = root / "log"
        for d in (self.config / "foot", self.config / "hypr", self.config / "omarchy", self.config / "alacritty",
                  self.fake, self.drm / "card0-DSI-1", self.home / ".local/state/omarchy/done"):
            d.mkdir(parents=True)
        (self.drm / "card0-DSI-1/modes").write_text("1080x2424\n")
        (self.config / "hypr/monitors.lua").write_text("local omarchy_monitor_scale = 3\n")
        self.files = {
            "foot": (self.config / "foot/foot.ini", "[main]\nfont=JetBrainsMono Nerd Font:size=9\npad=6x6\n\n[scrollback]\nmultiplier=3.0\n"),
            "alacritty": (self.config / "alacritty/alacritty.toml", "[font]\nnormal = { family = \"JetBrainsMono Nerd Font\" }\nsize = 9\n"),
            "shell": (self.config / "omarchy/shell.toml", "[bar]\nsize-horizontal = 30\n"),
            "chromium": (self.config / "chromium-flags.conf",
                         "--no-first-run\n# --force-device-scale-factor=0.5\n--force-device-scale-factor=0.62\n'--user-agent=Mozilla/5.0 (Linux; Android 14) Mobile'\n"),
        }
        for path, text in self.files.values():
            path.write_text(text)
        (self.fake / "gsettings").write_text(FAKE_GSETTINGS)
        (self.fake / "pkill").write_text('#!/bin/sh\necho "pkill $*" >>"$FAKE_LOG"\n')
        (self.fake / "hyprctl").write_text("#!/bin/sh\nexit 1\n")
        for f in self.fake.iterdir():
            f.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), OMAMOBILE_DRM=str(self.drm), FAKE_GS=str(self.gs),
                        FAKE_LOG=str(self.log), PATH=f"{self.fake}:{os.environ['PATH']}")
        self.env.pop("XDG_CONFIG_HOME", None)

    def run_command(self, *args, code=0):
        result = subprocess.run([sys.executable, "-B", str(COMMAND), *args], env=self.env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout

    def snapshot(self):
        files = {}
        for path in sorted(self.home.rglob("*")):
            if path.is_file():
                files[str(path)] = (path.read_bytes(), path.stat().st_mtime_ns)
        return files

    def gsetting(self, key):
        path = self.gs / key
        return path.read_text().strip() if path.exists() else None

    def flags(self, name):
        return [f for f in shlex.split((self.config / name).read_text(), comments=True) if f.startswith("--force-device-scale-factor=")]

    def test_each_target_gets_the_step(self):
        out = self.run_command("set", "larger")
        self.assertIn("Larger", out)
        self.assertEqual((self.config / "omarchy/shell.toml").read_text(), "[bar]\nsize-horizontal = 30\n\n[font]\nbase-size = 16\n")
        self.assertEqual(self.gsetting("text-scaling-factor"), "1.3636")  # 15 pt of the 11 pt font
        foot = (self.config / "foot/foot.ini").read_text()
        self.assertIn("font=JetBrainsMono Nerd Font:size=12\n", foot)
        self.assertIn("multiplier=3.0\n", foot)
        self.assertIn("\nsize = 12\n", (self.config / "alacritty/alacritty.toml").read_text())
        # 1080 px at scale 3 is 360 px: fitted 0.62, times 4/3
        self.assertEqual(self.flags("chromium-flags.conf"), ["--force-device-scale-factor=0.83"])
        self.assertEqual(self.flags("grok-bot-flags.conf"), ["--force-device-scale-factor=0.83"])
        chromium = (self.config / "chromium-flags.conf").read_text()
        self.assertIn("--no-first-run\n# --force-device-scale-factor=0.5\n", chromium)
        self.assertIn("'--user-agent=Mozilla/5.0 (Linux; Android 14) Mobile'\n", chromium)
        state = (self.config / "omamobile/text-size").read_text()
        self.assertIn("step=larger\nscale=1.3333\n", state)
        self.assertEqual(self.run_command("get"), "larger\n")
        data = json.loads(self.run_command("get", "--json"))
        self.assertEqual(data["step"], "larger")
        self.assertTrue(data["chosen"])
        self.assertEqual([s["name"] for s in data["steps"]], ["smaller", "default", "large", "larger", "largest"])
        self.assertEqual([s["px"] for s in data["steps"]], [11, 12, 14, 16, 18])

    def test_second_run_changes_nothing(self):
        self.run_command("set", "large")
        before = self.snapshot()
        self.log.write_text("")
        self.run_command("set", "large")
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.log.read_text(), "", "no gsettings write or signal on a second run")

    def test_default_puts_everything_back(self):
        self.run_command("set", "largest")
        self.assertEqual(self.flags("chromium-flags.conf"), ["--force-device-scale-factor=0.93"])
        self.run_command("set", "default")
        self.assertEqual((self.config / "omarchy/shell.toml").read_text(), self.files["shell"][1])
        self.assertIsNone(self.gsetting("text-scaling-factor"))
        self.assertIn("reset org.gnome.desktop.interface text-scaling-factor", self.log.read_text())
        self.assertEqual((self.config / "foot/foot.ini").read_text(), self.files["foot"][1])
        self.assertEqual((self.config / "alacritty/alacritty.toml").read_text(), self.files["alacritty"][1])
        self.assertEqual(self.flags("chromium-flags.conf"), ["--force-device-scale-factor=0.62"])
        self.assertEqual(self.run_command("get"), "default\n")

    def test_smaller_and_no_step_yet(self):
        self.assertEqual(self.run_command("get"), "default\n")
        self.assertFalse(json.loads(self.run_command("get", "--json"))["chosen"])
        self.run_command("set", "smaller")
        self.assertIn("base-size = 11\n", (self.config / "omarchy/shell.toml").read_text())
        self.assertEqual(self.gsetting("text-scaling-factor"), "0.9091")
        self.assertIn(":size=8\n", (self.config / "foot/foot.ini").read_text())
        self.assertEqual(self.flags("chromium-flags.conf"), ["--force-device-scale-factor=0.57"])

    def test_unknown_step_writes_nothing(self):
        before = self.snapshot()
        self.run_command("set", "huge", code=2)
        self.run_command("bigger", code=2)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.log.exists())

    def test_links_stay_links(self):
        real = self.home / "dotfiles/foot.ini"
        real.parent.mkdir()
        real.write_text(self.files["foot"][1])
        foot = self.config / "foot/foot.ini"
        foot.unlink()
        foot.symlink_to(real)
        self.run_command("set", "large")
        self.assertTrue(foot.is_symlink())
        self.assertIn(":size=11\n", real.read_text())

    def test_unknown_screen_leaves_browsers_for_the_next_fit(self):
        (self.drm / "card0-DSI-1/modes").unlink()
        out = self.run_command("set", "larger")
        self.assertIn("next login", out)
        self.assertEqual(self.flags("chromium-flags.conf"), ["--force-device-scale-factor=0.62"])
        self.assertFalse((self.config / "grok-bot-flags.conf").exists())

    def test_refit_keeps_the_step(self):
        # The fit and the old 0.83 migration have run; the owner picks Larger.
        done = self.home / ".local/state/omarchy/done"
        for name in ("browser-fit-chromium", "browser-fit-grok-bot", "browser-defaults-chromium", "chromium-scale-3", "grok-bot-fit"):
            (done / ("omamobile-" + name)).touch()
        self.run_command("set", "larger")
        env = {"HOME": str(self.home), "OMAMOBILE_DRM": str(self.drm)}
        with patch.dict(os.environ, env), patch.object(B.subprocess, "run", side_effect=OSError):
            # A later login: the fit runs again and keeps fit x Larger, not
            # the bare fit (the 0.83 -> 0.62 surprise).
            B.main()
            self.assertEqual(self.flags("chromium-flags.conf"), ["--force-device-scale-factor=0.83"])
            self.assertEqual(self.flags("grok-bot-flags.conf"), ["--force-device-scale-factor=0.83"])
            # The screen's scale changes to 8/3 (405 px, fitted 0.70): the
            # step follows the new fit.
            (self.config / "hypr/monitors.lua").write_text("local omarchy_monitor_scale = 8 / 3\n")
            B.main()
            self.assertEqual(self.flags("chromium-flags.conf"), ["--force-device-scale-factor=0.93"])
            before = self.snapshot()
            B.main()
            self.assertEqual(self.snapshot(), before)
        self.assertIn("step=larger\n", (self.config / "omamobile/text-size").read_text())

    def test_first_fit_with_a_step_chosen(self):
        # A step chosen before the browsers were ever fitted (no geometry
        # then): the first fit writes fit x step, and once only one flag.
        (self.drm / "card0-DSI-1/modes").unlink()
        (self.config / "chromium-flags.conf").unlink()
        self.run_command("set", "large")
        (self.drm / "card0-DSI-1/modes").write_text("1080x2424\n")
        env = {"HOME": str(self.home), "OMAMOBILE_DRM": str(self.drm)}
        with patch.dict(os.environ, env), patch.object(B.subprocess, "run", side_effect=OSError):
            B.main()
        self.assertEqual(self.flags("chromium-flags.conf"), ["--force-device-scale-factor=0.72"])
        self.assertIn("--no-first-run", (self.config / "chromium-flags.conf").read_text())
        self.assertEqual(self.flags("grok-bot-flags.conf"), ["--force-device-scale-factor=0.72"])

    def test_scale_flag_helpers(self):
        self.assertEqual(B.scaled("0.62", "1.3333"), "0.83")
        self.assertEqual(B.scaled("0.83", "1.5000"), "1.25")
        self.assertEqual(B.scaled("0.62", "1.0000"), "0.62")
        path = self.config / "x-flags.conf"
        path.write_text("--a \"--force-device-scale-factor=0.5\"\n")
        self.assertTrue(B.set_scale_flag(path, "0.70"))
        self.assertEqual(path.read_text(), "--a \"--force-device-scale-factor=0.70\"\n")
        self.assertFalse(B.set_scale_flag(path, "0.70"))
        for bad in ("scale=9\n", "scale=x\n", "step=larger\n", ""):
            (self.config / "omamobile").mkdir(exist_ok=True)
            (self.config / "omamobile/text-size").write_text(bad)
            self.assertIsNone(B.text_scale(self.home))


if __name__ == "__main__":
    unittest.main(verbosity=1)
