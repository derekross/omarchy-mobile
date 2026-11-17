#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Tests for plugins/omamobile.quicksettings/user-tiles.py, the helper that
# reads the user's own quick-settings tiles (TILES.md) and runs their
# commands: validation, the list, the run, timeouts and that a chosen value
# never reaches a shell. Run by test/all; needs nothing but python3 and sh.
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
HELPER = os.path.join(os.path.dirname(HERE), "plugins/omamobile.quicksettings/user-tiles.py")

loader = importlib.machinery.SourceFileLoader("user_tiles", HELPER)
spec = importlib.util.spec_from_loader("user_tiles", loader)
T = importlib.util.module_from_spec(spec)
loader.exec_module(T)

failed = 0
tests = []


def test(fn):
    tests.append(fn)
    return fn


class Home:
    """A throwaway HOME with a tiles folder."""

    def __enter__(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="user-tiles-")
        self.home = self.tmp.name
        self.tiles = os.path.join(self.home, ".config/omamobile/tiles")
        os.makedirs(self.tiles)
        return self

    def __exit__(self, *exc):
        self.tmp.cleanup()

    def write(self, name, value):
        with open(os.path.join(self.tiles, name), "w", encoding="utf-8") as f:
            f.write(value if isinstance(value, str) else json.dumps(value))

    def helper(self, *args, timeout=30):
        env = dict(os.environ, HOME=self.home)
        return subprocess.run([sys.executable, "-I", HELPER, *args], env=env, capture_output=True,
                              text=True, timeout=timeout)

    def listed(self):
        result = self.helper("list")
        assert result.returncode == 0, result.stderr
        return {t["id"]: t for t in json.loads(result.stdout)}


def invalid(spec, reason):
    try:
        T.validate(spec)
    except T.Invalid as error:
        assert reason in str(error), f"{spec!r}: {error}"
        return
    raise AssertionError(f"{spec!r} was accepted")


@test
def validation_names_what_is_wrong():
    invalid([], "no JSON object")
    invalid({}, "label is missing")
    invalid({"label": "   "}, "label is missing")
    invalid({"label": 3}, "label is missing")
    invalid({"label": "x", "colour": "red"}, "unknown field colour")
    invalid({"label": "x", "icon": "abc"}, "one glyph")
    invalid({"label": "x", "icon": ""}, "one glyph")
    invalid({"label": "x", "icon": "\n"}, "one glyph")
    invalid({"label": "x", "status": "date"}, "status must be a list")
    invalid({"label": "x", "status": []}, "status must be a list")
    invalid({"label": "x", "status": ["date", 3]}, "status must be a list")
    invalid({"label": "x", "status": [""]}, "names no command")
    invalid({"label": "x", "action": ["a\0b"]}, "can't be used")
    invalid({"label": "x", "action": ["a"] * 65}, "more than 64")
    invalid({"label": "x", "choices": ["ls"]}, "needs a choose command")
    invalid({"label": "x", "choose": ["x", "{}"]}, "needs a choices command")
    invalid({"label": "x", "choices": ["ls"], "choose": ["echo", "{} "]}, 'no "{}"')
    invalid({"label": "x", "choices": ["ls"], "choose": ["echo", "{}"], "action": ["true"]}, "not both")
    tile = T.validate({"label": "  Solar \n time ", "status": ["date"]})
    assert tile["label"] == "Solar time", tile
    assert tile["icon"] == T.DEFAULT_ICON
    assert tile["choices"] is None and tile["action"] is None
    # A Nerd Font glyph is a private-use character: still one glyph.
    assert T.validate({"label": "x", "icon": "\U000F0599"})["icon"] == "\U000F0599"


@test
def choices_lines_are_value_tab_label():
    out = "a\tAlpha\nb\n\n  \t nothing\nc\tC\x07 one\na\tAgain\n" + " x\n"
    assert T.parse_choices(out.encode()) == [
        {"value": "a", "label": "Alpha"}, {"value": "b", "label": "b"}, {"value": "c", "label": "C one"},
        {"value": "x", "label": "x"}], T.parse_choices(out.encode())
    many = "".join(f"v{i}\n" for i in range(500)).encode()
    assert len(T.parse_choices(many)) == T.MAX_CHOICES


@test
def list_reads_every_file_and_never_crashes_on_a_broken_one():
    with Home() as h:
        h.write("solar.json", {
            "label": "Solar time", "icon": "\U000F0599",
            "status": ["sh", "-c", "printf 'Tempus_Solaris_Bashley_Safe_House\\nsecond\\n' | sed 's/^Tempus_Solaris_//; s/_/ /g'"],
            "choices": ["sh", "-c", "for n in Tempus_Solaris_Rustica Tempus_Solaris_Bashley_Safe_House; do "
                        "printf '%s\\t%s\\n' \"$n\" \"$(echo ${n#Tempus_Solaris_} | tr _ ' ')\"; done"],
            "choose": ["echo", "{}"]})
        h.write("lamp.json", {"label": "Lamp", "active": ["true"], "action": ["true"], "status": ["sh", "-c", "exit 3"]})
        h.write("off.json", {"label": "Off", "active": ["false"]})
        h.write("gone.json", {"label": "Gone", "status": ["/nonexistent/command"], "active": ["/nonexistent/command"]})
        h.write("broken.json", "{")
        h.write("unknown.json", {"label": "x", "bogus": 1})
        with open(os.path.join(h.tiles, "latin1.json"), "wb") as f:
            f.write(b'{"label": "\xff"}')
        h.write("Upper.json", {"label": "skipped"})
        h.write(".hidden.json", {"label": "skipped"})
        h.write("notes.txt", "skipped")
        os.mkdir(os.path.join(h.tiles, "dir.json"))
        tiles = h.listed()
        assert sorted(tiles) == ["broken", "dir", "gone", "lamp", "latin1", "off", "solar", "unknown"], sorted(tiles)
        assert tiles["dir"]["error"] == "not a file"
        solar = tiles["solar"]
        assert solar == {"id": "solar", "label": "Solar time", "icon": "\U000F0599", "status": "Bashley Safe House",
                         "active": False, "choices": [
                             {"value": "Tempus_Solaris_Rustica", "label": "Rustica"},
                             {"value": "Tempus_Solaris_Bashley_Safe_House", "label": "Bashley Safe House"}],
                         "hasChoices": True, "hasAction": False, "error": ""}, solar
        assert tiles["lamp"]["active"] is True and tiles["lamp"]["hasAction"] is True
        assert tiles["lamp"]["status"] == "", "a failing status command shows nothing"
        assert tiles["off"]["active"] is False
        assert tiles["gone"]["status"] == "" and tiles["gone"]["active"] is False and not tiles["gone"]["error"]
        assert "not valid JSON" in tiles["broken"]["error"]
        assert tiles["unknown"]["error"] == "unknown field bogus"
        assert "UTF-8" in tiles["latin1"]["error"]
        for t in tiles.values():
            assert set(t) == {"id", "label", "icon", "status", "active", "choices", "hasChoices", "hasAction", "error"}, t


@test
def list_with_no_folder_is_empty():
    with tempfile.TemporaryDirectory() as home:
        result = subprocess.run([sys.executable, "-I", HELPER, "list"], env=dict(os.environ, HOME=home),
                                capture_output=True, text=True, timeout=10)
        assert result.returncode == 0 and json.loads(result.stdout) == [], result


@test
def a_slow_command_is_cut_off_with_its_children():
    with Home() as h:
        marker = os.path.join(h.home, "late")
        # The child holds stdout open past the timeout; the group is killed.
        h.write("slow.json", {"label": "Slow", "status": ["sh", "-c", f"(sleep 6; touch {marker}) & echo early; sleep 6"]})
        h.write("quick.json", {"label": "Quick", "status": ["echo", "fine"]})
        start = time.monotonic()
        tiles = h.listed()
        took = time.monotonic() - start
        assert took < T.PROBE_TIMEOUT + 2, took
        assert tiles["slow"]["status"] == "" and tiles["quick"]["status"] == "fine", tiles
        time.sleep(0.2)
        assert not os.path.exists(marker)
        code, _ = T.run(["sh", "-c", "sleep 5"], 0.3, False)
        assert code == 124


@test
def run_hands_the_value_over_as_one_argument_never_to_a_shell():
    with Home() as h:
        out = os.path.join(h.home, "got")
        pwned = os.path.join(h.home, "pwned")
        nasty = f"x; touch {pwned} $(touch {pwned})"
        h.write("pick.json", {
            "label": "Pick",
            "choices": ["printf", "%s\\t%s\\n", "plain", "Plain", nasty, "Nasty", "-n", "Option-like"],
            "choose": ["sh", "-c", 'printf "%s|" "$@" > "$0"', out, "before", "{}", "after"]})
        for value in ("plain", nasty, "-n"):
            result = h.helper("run", "pick", value)
            assert result.returncode == 0, result.stderr
            with open(out) as f:
                assert f.read() == f"before|{value}|after|", value
        assert not os.path.exists(pwned)
        # A value the choices don't list never runs.
        os.remove(out)
        for args in (("run", "pick", "unlisted"), ("run", "pick", "plain\n"), ("run", "pick")):
            result = h.helper(*args)
            assert result.returncode == 2 and not os.path.exists(out), (args, result)


@test
def run_runs_the_action_and_returns_its_code():
    with Home() as h:
        h.write("ok.json", {"label": "Ok", "action": ["sh", "-c", "exit 0"]})
        h.write("fails.json", {"label": "Fails", "action": ["sh", "-c", "exit 7"]})
        h.write("missing.json", {"label": "Missing", "action": ["/nonexistent/command"]})
        h.write("show.json", {"label": "Show", "status": ["date"]})
        h.write("broken.json", "[")
        assert h.helper("run", "ok").returncode == 0
        assert h.helper("run", "fails").returncode == 7
        assert h.helper("run", "missing").returncode == 127
        assert h.helper("run", "ok", "value").returncode == 2, "an action takes no value"
        assert h.helper("run", "show").returncode == 2, "nothing to run"
        result = h.helper("run", "broken")
        assert result.returncode == 2 and "not valid JSON" in result.stderr, result
        assert h.helper("run", "absent").returncode == 2
        for bad in ("../ok", "OK", "ok.json", ""):
            assert h.helper("run", bad).returncode == 2, bad
        assert h.helper().returncode == 2
        assert h.helper("list", "extra").returncode == 2


@test
def the_helper_needs_only_the_standard_library():
    with open(HELPER) as f:
        imports = {line.split()[1].split(".")[0] for line in f if line.startswith(("import ", "from "))}
    assert imports <= {"concurrent", "json", "os", "re", "signal", "subprocess", "sys", "unicodedata"}, imports


for fn in tests:
    try:
        fn()
        print(f"ok - user tiles: {fn.__name__.replace('_', ' ')}")
    except Exception as error:  # noqa: BLE001 - report every test
        failed += 1
        print(f"not ok - user tiles: {fn.__name__.replace('_', ' ')}\n  {type(error).__name__}: {error}")
sys.exit(1 if failed else 0)
