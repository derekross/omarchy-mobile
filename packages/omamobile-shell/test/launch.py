#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Tests for bin/omamobile-launch (one app per screen) against a fake hyprctl
# that records every call and answers queries from files. Every Lua string the
# helper sends is also run under a stub `hl` table when a Lua interpreter is
# there, to check it parses and passes what Hyprland 0.56 expects. Run by
# test/all; needs nothing but python3.
import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(os.path.dirname(HERE), "bin/omamobile-launch")
LUA = shutil.which("lua") or shutil.which("lua5.4") or shutil.which("luajit")

loader = importlib.machinery.SourceFileLoader("omamobile_launch", TOOL)
spec = importlib.util.spec_from_loader("omamobile_launch", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

failed = 0
tests = []


def test(fn):
    tests.append(fn)
    return fn


FAKE_HYPRCTL = r'''#!/usr/bin/python3
import json, os, sys
root = os.environ["FAKE_ROOT"]
args = sys.argv[1:]
with open(os.path.join(root, "hyprctl.log"), "a") as log:
    log.write(json.dumps(args) + "\n")
if args[:1] == ["-j"]:
    path = os.path.join(root, args[1] + ".json")
    sys.stdout.write(open(path).read() if os.path.exists(path) else "null")
    sys.exit(0)
if os.path.exists(os.path.join(root, "fail-" + args[0])):
    print("error: no such function")
    sys.exit(1)
print("ok")
'''

# Logs its name and argv, one JSON line each.
FAKE_LOGGER = r'''#!/usr/bin/python3
import json, os, sys
with open(os.path.join(os.environ["FAKE_ROOT"], "spawned.log"), "a") as log:
    log.write(json.dumps([os.path.basename(sys.argv[0])] + sys.argv[1:]) + "\n")
'''


class Sandbox:
    def __init__(self, clients=None, active_windows=0, browser=""):
        self.clients = clients or []
        self.active_windows = active_windows
        self.browser = browser

    def __enter__(self):
        self.root = tempfile.mkdtemp(prefix="omamobile-launch-test-")
        self.bin = os.path.join(self.root, "bin")
        self.apps = os.path.join(self.root, "data/applications")
        os.makedirs(self.bin)
        os.makedirs(self.apps)
        self.write_exe("hyprctl", FAKE_HYPRCTL)
        for name in ("uwsm-app", "xdg-open", "omarchy-agent-prompt"):
            self.write_exe(name, FAKE_LOGGER)
        self.write_exe("xdg-settings", "#!/bin/sh\n[ -n \"$FAKE_BROWSER\" ] && echo \"$FAKE_BROWSER\"\nexit 0\n")
        self.write_exe("xdg-mime", "#!/bin/sh\nexit 0\n")
        self.set_clients(self.clients)
        json.dump({"id": 1, "windows": self.active_windows}, open(os.path.join(self.root, "activeworkspace.json"), "w"))
        self.env = dict(os.environ)
        self.env.update({
            "FAKE_ROOT": self.root,
            "FAKE_BROWSER": self.browser,
            "OMAMOBILE_HYPRCTL": os.path.join(self.bin, "hyprctl"),
            "PATH": self.bin + ":" + os.environ.get("PATH", "/usr/bin:/bin"),
            "XDG_DATA_HOME": os.path.join(self.root, "data"),
            "XDG_DATA_DIRS": os.path.join(self.root, "none"),
        })
        return self

    def __exit__(self, *exc):
        shutil.rmtree(self.root, ignore_errors=True)

    def write_exe(self, name, body):
        path = os.path.join(self.bin, name)
        with open(path, "w") as f:
            f.write(body)
        os.chmod(path, 0o755)

    def set_clients(self, clients):
        json.dump(clients, open(os.path.join(self.root, "clients.json"), "w"))

    def desktop(self, app_id, **keys):
        lines = ["[Desktop Entry]", "Type=Application", "Name=" + app_id]
        lines += ["%s=%s" % (k, v) for k, v in keys.items()]
        lines += ["", "[Desktop Action new]", "Exec=nothing-to-see"]
        with open(os.path.join(self.apps, app_id + ".desktop"), "w") as f:
            f.write("\n".join(lines) + "\n")

    def fail(self, what):
        open(os.path.join(self.root, "fail-" + what), "w").close()

    def run(self, *args):
        return subprocess.run([sys.executable, "-B", TOOL] + list(args), env=self.env, cwd=self.root,
                              capture_output=True, text=True, timeout=30)

    def calls(self):
        try:
            return [json.loads(line) for line in open(os.path.join(self.root, "hyprctl.log"))]
        except OSError:
            return []

    def actions(self):
        """The dispatch and eval calls, as (verb, lua)."""
        return [(c[0], c[1]) for c in self.calls() if c and c[0] in ("dispatch", "eval")]

    def spawned(self):
        try:
            return [json.loads(line) for line in open(os.path.join(self.root, "spawned.log"))]
        except OSError:
            return []

    def wait_spawned(self, count=1):
        for _ in range(100):
            if len(self.spawned()) >= count:
                break
            subprocess.run(["sleep", "0.05"])
        return self.spawned()


def client(address, cls, workspace=1, history=0, title="t", initial=None):
    return {"address": address, "class": cls, "initialClass": initial or cls, "title": title, "mapped": True,
            "workspace": {"id": workspace, "name": str(workspace)}, "focusHistoryID": history}


# ---------------------------------------------------------------- Lua


LUA_STUB = r'''
local calls = {}
local function record(name)
  return function(arg, rules)
    local parts = { name }
    if type(arg) == "table" then
      local keys = {}
      for k in pairs(arg) do keys[#keys + 1] = k end
      table.sort(keys)
      for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(arg[k]) end
    else
      parts[#parts + 1] = "cmd=" .. tostring(arg)
    end
    if rules ~= nil then
      for k, v in pairs(rules) do parts[#parts + 1] = "rule." .. k .. "=" .. tostring(v) end
    end
    io.write(table.concat(parts, "\t"), "\n")
    return name
  end
end
hl = {
  exec_cmd = record("exec_cmd"),
  dsp = {
    focus = record("focus"),
    window = { move = record("window.move"), fullscreen_state = record("window.fullscreen_state") },
  },
}
'''


def lua_run(verb, code):
    """What the stub saw for one dispatch (an expression) or eval (a chunk)."""
    chunk = LUA_STUB + ("local _ = " + code if verb == "dispatch" else code)
    proc = subprocess.run([LUA, "-"], input=chunk, capture_output=True, text=True, timeout=10)
    assert proc.returncode == 0, (code, proc.stderr)
    out = proc.stdout
    assert out.endswith("\n"), (code, out)
    fields = out[:-1].split("\t")
    return fields[0], dict(f.split("=", 1) for f in fields[1:])


# ---------------------------------------------------------------- pure parts


@test
def lua_strings_hold_anything():
    for text in ["plain", "a]]b", "x]=]y]==]", "ends with ]", "ends ]=", "\nleading newline", "", "q'\"$`\\"]:
        literal = mod.lua_string(text)
        if LUA:
            proc = subprocess.run([LUA, "-e", "io.write(" + literal + ")"], capture_output=True, text=True)
            assert proc.returncode == 0 and proc.stdout == text, (text, literal, proc.stdout, proc.stderr)


@test
def addresses_are_normalised():
    assert mod.norm_address("55aa01") == "0x55aa01"
    assert mod.norm_address("0x55AA01") == "0x55aa01"
    assert mod.norm_address("address:0x1f") == "0x1f"
    for bad in ("", "zz", "0x", "1f; rm", None, "0x" + "f" * 17):
        assert mod.norm_address(bad) is None, bad


@test
def matchers_read_the_desktop_entry():
    classes, host = mod.matchers("org.gnome.Nautilus", {"Exec": "nautilus --new-window %U", "StartupWMClass": "Nautilus"})
    assert {"org.gnome.nautilus", "nautilus"} <= classes and host is None, classes
    classes, host = mod.matchers("chromium", {"Exec": "/usr/bin/chromium %U"})
    assert classes == {"chromium"}, classes
    _, host = mod.matchers("WhatsApp", {"Exec": "omarchy-launch-webapp https://web.whatsapp.com/"})
    assert host == "web.whatsapp.com", host
    classes, _ = mod.matchers("Docker", {"Exec": "xdg-terminal-exec --app-id=TUI.tile -e omarchy-launch-docker-tui"})
    assert classes == {"docker"}, classes
    classes, _ = mod.matchers("btop", {"Exec": "omarchy-launch-tui --app-id=org.omarchy.btop btop"})
    assert "org.omarchy.btop" in classes, classes
    classes, _ = mod.matchers("org.telegram.desktop", {"Exec": "env QT_QPA_PLATFORM=wayland Telegram -- %u"})
    assert "desktop" not in classes and "telegram" in classes and "org.telegram.desktop" in classes, classes
    classes, _ = mod.matchers("x", {"Exec": "flatpak run --branch=stable org.example.App"})
    assert "org.example.app" in classes, classes


@test
def web_apps_match_their_own_window_only():
    wa = client("0x1", "chrome-web.whatsapp.com__-Default")
    browser = client("0x2", "chromium")
    assert mod.find_window([wa, browser], set(), "web.whatsapp.com") is wa
    assert mod.find_window([wa, browser], {"chromium"}, None) is browser
    assert mod.find_window([wa], {"chromium"}, None) is None


# ---------------------------------------------------------------- app


@test
def an_open_app_is_focused_not_started_again():
    windows = [client("0xa1", "Nautilus", workspace=2, history=3), client("0xa2", "Nautilus", workspace=4, history=1),
               client("0xb", "chromium", workspace=1, history=0)]
    with Sandbox(windows, active_windows=1) as s:
        s.desktop("org.gnome.Nautilus", Exec="nautilus --new-window", StartupWMClass="org.gnome.Nautilus")
        out = s.run("app", "org.gnome.Nautilus.desktop")
        assert out.returncode == 0, out.stderr
        assert s.actions() == [("dispatch", 'hl.dsp.focus({ window = "address:0xa2" })')], s.actions()
        assert s.spawned() == []


@test
def agent_shortcut_matches_and_focuses_the_most_recent_agent_session():
    # Use the shipped entry so its StartupWMClass and Terminal setting are
    # part of this contract. A widget-building session uses the same class.
    windows = [client("0xa1", "org.omarchy.agent", workspace=2, history=3),
               client("0xa2", "org.omarchy.agent", workspace=4, history=0, title="Widget builder"),
               client("0xb", "foot", workspace=1, history=1)]
    with Sandbox(windows, active_windows=1) as s:
        shutil.copyfile(os.path.join(os.path.dirname(HERE), "applications/omamobile-agent.desktop"),
                        os.path.join(s.apps, "omamobile-agent.desktop"))
        out = s.run("match", "omamobile-agent")
        assert out.returncode == 0 and out.stdout.strip() == "0xa2 org.omarchy.agent", (out.stdout, out.stderr)
        assert s.actions() == [] and s.spawned() == []
        out = s.run("app", "omamobile-agent")
        assert out.returncode == 0, out.stderr
        assert s.actions() == [("dispatch", 'hl.dsp.focus({ window = "address:0xa2" })')], s.actions()
        assert s.spawned() == []


@test
def a_new_app_gets_an_empty_workspace_through_an_exec_rule():
    with Sandbox([client("0xb", "chromium")], active_windows=1) as s:
        s.desktop("org.gnome.Nautilus", Exec="nautilus")
        out = s.run("app", "org.gnome.Nautilus")
        assert out.returncode == 0, out.stderr
        acts = s.actions()
        assert acts[0] == ("dispatch", 'hl.dsp.focus({ workspace = "empty" })'), acts
        assert acts[1][0] == "eval" and len(acts) == 2, acts
        assert acts[1][1].startswith("hl.exec_cmd(") and acts[1][1].endswith(', { workspace = "empty" })'), acts
        assert "exec env -- " in acts[1][1] and "uwsm-app -- gtk-launch org.gnome.Nautilus.desktop" in acts[1][1], acts
        if LUA:
            name, args = lua_run("eval", acts[1][1])
            assert name == "exec_cmd" and args["rule.workspace"] == "empty", args
            # The command Hyprland's sh -c would run starts Omarchy's launch path.
            subprocess.run(["sh", "-c", args["cmd"]], env=s.env, check=True)
            assert s.wait_spawned() == [["uwsm-app", "--", "gtk-launch", "org.gnome.Nautilus.desktop"]], s.spawned()


@test
def ids_ending_in_desktop_keep_their_suffix():
    with Sandbox([]) as s:
        s.desktop("org.telegram.desktop", Exec="Telegram -- %u")
        assert s.run("app", "org.telegram.desktop").returncode == 0
        (verb, lua), = s.actions()
        assert "gtk-launch org.telegram.desktop.desktop" in lua, lua


@test
def from_an_empty_workspace_there_is_no_switch_first():
    with Sandbox([], active_windows=0) as s:
        assert s.run("app", "foo").returncode == 0
        assert [a[0] for a in s.actions()] == ["eval"], s.actions()


@test
def terminals_and_new_always_start_a_window():
    windows = [client("0x1", "foot"), client("0x2", "org.gnome.Nautilus")]
    with Sandbox(windows) as s:
        s.desktop("foot", Exec="foot", Categories="System;TerminalEmulator;")
        s.desktop("org.gnome.Nautilus", Exec="nautilus")
        assert s.run("app", "foot").returncode == 0
        assert s.run("app", "--new", "org.gnome.Nautilus").returncode == 0
        evals = [a for a in s.actions() if a[0] == "eval"]
        assert len(evals) == 2 and "gtk-launch foot.desktop" in evals[0][1], s.actions()
        assert not any("focus({ window" in a[1] for a in s.actions()), s.actions()


@test
def without_hyprland_the_app_still_starts():
    with Sandbox([]) as s:
        s.fail("eval")
        out = s.run("app", "foo")
        assert out.returncode == 0, out.stderr
        assert s.wait_spawned() == [["uwsm-app", "--", "gtk-launch", "foo.desktop"]], s.spawned()


@test
def bad_arguments_are_refused():
    with Sandbox([]) as s:
        assert s.run().returncode == 2
        assert s.run("app").returncode == 2
        assert s.run("cmd", "--").returncode == 2
        assert s.run("show-with", "nothex", "0x1").returncode == 2
        assert s.actions() == []


# ---------------------------------------------------------------- cmd and url


NASTY = 'moon; $(touch "$FAKE_ROOT/pwned") `id` "q" \'s\' & | > x\nline two ]] ]=] -- --inline'


@test
def commands_keep_their_argv_directory_and_path():
    with Sandbox([]) as s:
        workdir = os.path.join(s.root, "work dir")
        os.makedirs(workdir)
        proc = subprocess.run([sys.executable, "-B", TOOL, "cmd", "--", "omarchy-agent-prompt", NASTY],
                              env=s.env, cwd=workdir, capture_output=True, text=True)
        assert proc.returncode == 0, proc.stderr
        (verb, lua), = s.actions()
        assert verb == "eval", s.actions()
        if LUA:
            name, args = lua_run("eval", lua)
            assert name == "exec_cmd" and args["rule.workspace"] == "empty", args
            # Run it the way Hyprland would: sh -c, from elsewhere, with a bare PATH.
            env = {"FAKE_ROOT": s.root, "PATH": "/usr/bin:/bin"}
            subprocess.run(["sh", "-c", args["cmd"]], env=env, cwd="/", check=True)
            assert s.wait_spawned() == [["omarchy-agent-prompt", NASTY]], s.spawned()
            assert not os.path.exists(os.path.join(s.root, "pwned"))
            assert "cd -- " in args["cmd"] and "work dir" in args["cmd"], args


@test
def links_go_to_the_running_browser():
    with Sandbox([client("0xc1", "chrome-x.com__-Default"), client("0xc2", "chromium", history=2)],
                 active_windows=1, browser="chromium.desktop") as s:
        s.desktop("chromium", Exec="/usr/bin/chromium %U")
        assert s.run("url", "https://example.com/a?b=c").returncode == 0
        assert s.actions() == [("dispatch", 'hl.dsp.focus({ window = "address:0xc2" })')], s.actions()
        assert s.wait_spawned() == [["xdg-open", "https://example.com/a?b=c"]], s.spawned()


@test
def links_start_the_browser_on_its_own_screen():
    with Sandbox([client("0x9", "foot")], active_windows=1, browser="chromium.desktop") as s:
        s.desktop("chromium", Exec="/usr/bin/chromium %U")
        assert s.run("url", "https://example.com").returncode == 0
        acts = s.actions()
        assert acts[0][1] == 'hl.dsp.focus({ workspace = "empty" })', acts
        assert acts[1][0] == "eval" and "xdg-open https://example.com" in acts[1][1], acts


# ---------------------------------------------------------------- the switcher's actions


@test
def show_with_moves_by_address_and_tiles_both():
    windows = [client("0xa", "foot", workspace=1), client("0xb", "chromium", workspace=3)]
    with Sandbox(windows) as s:
        out = s.run("show-with", "a", "0xB")
        assert out.returncode == 0, out.stderr
        assert s.actions() == [
            ("dispatch", 'hl.dsp.window.move({ window = "address:0xa", workspace = [[3]] })'),
            ("dispatch", 'hl.dsp.focus({ window = "address:0xb" })'),
            ("dispatch", "hl.dsp.window.fullscreen_state({ internal = 0, client = 0 })"),
            ("dispatch", 'hl.dsp.focus({ window = "address:0xa" })'),
            ("dispatch", "hl.dsp.window.fullscreen_state({ internal = 0, client = 0 })"),
        ], s.actions()
        if LUA:
            name, args = lua_run("dispatch", s.actions()[0][1])
            assert name == "window.move" and args == {"window": "address:0xa", "workspace": "3"}, args
            name, args = lua_run("dispatch", s.actions()[2][1])
            assert name == "window.fullscreen_state" and args == {"internal": "0", "client": "0"}, args


@test
def show_with_an_unknown_window_does_nothing():
    with Sandbox([client("0xa", "foot")]) as s:
        assert s.run("show-with", "0xa", "0xdead").returncode == 1
        assert s.actions() == []


@test
def own_screen_moves_to_an_empty_workspace_and_maximizes_both():
    windows = [client("0xa", "foot", workspace=2), client("0xb", "chromium", workspace=2)]
    with Sandbox(windows) as s:
        assert s.run("own-screen", "0xa").returncode == 0
        assert s.actions() == [
            ("dispatch", 'hl.dsp.focus({ window = "address:0xb" })'),
            ("dispatch", "hl.dsp.window.fullscreen_state({ internal = 1, client = 0 })"),
            ("dispatch", 'hl.dsp.window.move({ window = "address:0xa", workspace = "empty" })'),
            ("dispatch", 'hl.dsp.focus({ window = "address:0xa" })'),
            ("dispatch", "hl.dsp.window.fullscreen_state({ internal = 1, client = 0 })"),
        ], s.actions()
        if LUA:
            for verb, lua in s.actions():
                lua_run(verb, lua)


@test
def own_screen_for_a_window_already_alone_only_focuses_it():
    with Sandbox([client("0xa", "foot", workspace=2), client("0xb", "x", workspace=5)]) as s:
        assert s.run("own-screen", "0xa").returncode == 0
        assert s.actions() == [("dispatch", 'hl.dsp.focus({ window = "address:0xa" })')], s.actions()


def main():
    global failed
    if not LUA:
        print("ok - launch: Lua checks # SKIP no lua")
    for fn in tests:
        name = fn.__name__.replace("_", " ")
        try:
            fn()
            print("ok - launch: " + name)
        except AssertionError as error:
            failed += 1
            print("not ok - launch: %s\n  %r" % (name, error), file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
