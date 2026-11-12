#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Tests for bin/omamobile-portal-access. Run by test/all.

The pure parts always; the D-Bus service when a session bus is there (test/all
runs this under dbus-run-session): AccessDialog in, the sheet's request out to
a fake omarchy-shell, Answer back, and the response the portal gets. A real
shell and a real portal are never touched.
"""

import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "bin", "omamobile-portal-access")

loader = importlib.machinery.SourceFileLoader("portal_access", TOOL)
spec = importlib.util.spec_from_loader("portal_access", loader)
pa = importlib.util.module_from_spec(spec)
loader.exec_module(pa)

failures = []


def check(name, condition, detail=""):
    if condition:
        print("ok - %s" % name)
    else:
        print("not ok - %s %s" % (name, detail))
        failures.append(name)


# ---------------------------------------------------------------- pure parts

# The portal's own titles (xdg-desktop-portal 1.22), as a phone says them.
titles = [
    ("Allow Camera to Use the Camera?", "Camera", "Allow Camera to use the camera?"),
    ("Allow Apps to Use the Camera?", "", "Allow apps to use the camera?"),
    ("Allow GNOME Maps to Access Your Location?", "GNOME Maps", "Allow GNOME Maps to access your location?"),
    ("Allow Fractal to Run in the Background?", "Fractal", "Allow Fractal to run in the background?"),
    ("Allow Shotwell to Take Screenshots?", "Shotwell", "Allow Shotwell to take screenshots?"),
    ("Allow to Take a Screenshot?", "", "Allow an app to take a screenshot?"),
    ("Allow Wallpapers to Set Backgrounds?", "Wallpapers", "Allow Wallpapers to set backgrounds?"),
]
for title, app, want in titles:
    got = pa.phone_title(title, app)
    check("title %r" % title, got == want, "got %r" % got)
check("an empty title still asks", pa.phone_title("", "Camera") == "Allow Camera?")

body = pa.phone_body("Camera wants to access the camera",
                     "This permission can be changed at any time from the privacy settings")
check("subtitle becomes a sentence; no privacy settings page is promised",
      body == "Camera wants to access the camera.\nYour choice is remembered for this app.", repr(body))
check("other body text is kept", pa.phone_body("", "Something else") == "Something else.")
check("labels default to Don't allow / Allow", pa.labels({}) == ("Don't allow", "Allow"))
check("the caller's labels are kept, in sentence case",
      pa.labels({"deny_label": "Deny Access", "grant_label": "Grant Access"}) == ("Deny access", "Grant access"))
check("camera glyph", pa.glyph_for("camera-web-symbolic") == "󰄀")
check("unknown icon gets the shield", pa.glyph_for("weird-symbolic") == pa.DEFAULT_GLYPH)
check("allow is response 0", pa.answer_reply("allow", []) == (0, {}))
check("deny is response 1", pa.answer_reply("deny", []) == (1, {}))
check("anything else is no response", pa.answer_reply("maybe", []) is None and pa.answer_reply(None, []) is None)
check("choices go back with their initial values",
      pa.answer_reply("allow", [("c1", "Remember", [], "true"), ("bad",)]) == (0, {"choices": [("c1", "true")]}))

data = tempfile.mkdtemp()
os.makedirs(os.path.join(data, "applications"))
with open(os.path.join(data, "applications", "org.example.Cam.desktop"), "w") as f:
    f.write("[Desktop Entry]\nType=Application\nName=Test Camera\nName[de]=Testkamera\nIcon=org.example.Cam\nExec=cam %U\n")
os.environ["XDG_DATA_HOME"] = os.path.join(data, "none")
os.environ["XDG_DATA_DIRS"] = data
check("name and icon from the .desktop file", pa.app_info("org.example.Cam") == ("Test Camera", "org.example.Cam"))
check("no .desktop file", pa.app_info("org.example.Missing") == ("", ""))
check("an app id can't walk the filesystem", pa.app_info("../../etc/passwd") == ("", ""))
req = pa.sheet_request("ab12cd34ef56ab78", "org.example.Cam", "Allow Test Camera to Use the Camera?",
                       "Test Camera wants to access the camera", "", {"icon": "camera-web-symbolic"})
check("sheet request", req["appName"] == "Test Camera" and req["title"] == "Allow Test Camera to use the camera?"
      and req["glyph"] == "󰄀" and req["denyLabel"] == "Don't allow", json.dumps(req))
req = pa.sheet_request("ab12cd34ef56ab78", "", "Allow Apps to Use the Camera?", "", "", {})
check("an app without an id is 'An app'", req["appName"] == "An app")


# ---------------------------------------------------------------- the service

def service_tests():
    import dbus

    work = tempfile.mkdtemp()
    fake = os.path.join(work, "omarchy-shell")
    log = os.path.join(work, "log")
    with open(fake, "w") as f:
        f.write("""#!/bin/bash
printf '%s\\n' "$*" >> "$FAKE_LOG"
case "$1 $2" in
  "lock isLocked") [[ -n ${FAKE_DOWN:-} ]] && exit 1; echo "${FAKE_LOCKED:-false}" ;;
  "shell call")
    [[ -n ${FAKE_FAIL:-} ]] && { echo unknown; exit 0; }
    [[ $4 == request ]] && printf '%s' "$5" > "$FAKE_DIR/request.json.tmp" && mv "$FAKE_DIR/request.json.tmp" "$FAKE_DIR/request.json"
    echo ok ;;
esac
""")
    os.chmod(fake, 0o755)

    def start(**extra):
        env = dict(os.environ, OMAMOBILE_ACCESS_SHELL=fake, OMAMOBILE_ACCESS_TIMEOUT="2",
                   FAKE_LOG=log, FAKE_DIR=work, **extra)
        proc = subprocess.Popen([sys.executable, "-B", TOOL], env=env, stderr=subprocess.PIPE)
        bus = dbus.SessionBus()
        for _ in range(100):
            if bus.name_has_owner(pa.BUS_NAME):
                return proc
            time.sleep(0.05)
        proc.kill()
        raise RuntimeError("the service never took its name: %s" % proc.stderr.read().decode())

    def stop(proc):
        proc.terminate()
        proc.wait(timeout=5)

    def ask(token, options="{'icon': <'camera-web-symbolic'>}", app="org.example.Cam"):
        handle = "/org/freedesktop/portal/desktop/request/1_1/" + token
        return subprocess.Popen(
            ["gdbus", "call", "--session", "--timeout", "20", "--dest", pa.BUS_NAME,
             "--object-path", pa.PORTAL_PATH, "--method", pa.ACCESS_IFACE + ".AccessDialog",
             handle, app, "", "Allow Test Camera to Use the Camera?", "Test Camera wants to access the camera",
             "This permission can be changed at any time from the privacy settings", options],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True), handle

    def wait_request():
        path = os.path.join(work, "request.json")
        for _ in range(100):
            if os.path.exists(path):
                with open(path) as f:
                    value = json.load(f)
                os.remove(path)
                return value
            time.sleep(0.05)
        return None

    def answer(request_id, what):
        sheet = dbus.SessionBus().get_object(pa.BUS_NAME, pa.SHEET_PATH)
        return bool(sheet.Answer(request_id, what, dbus_interface=pa.SHEET_IFACE))

    def logged():
        # Move the log aside, then read it: the fake shell opens the log by
        # name for every line, so nothing it writes meanwhile is lost (a
        # read followed by a truncate dropped a line written in between).
        taken = log + ".taken"
        try:
            os.rename(log, taken)
        except FileNotFoundError:
            return ""
        with open(taken) as f:
            text = f.read()
        os.remove(taken)
        return text

    def logged_soon(text, timeout=3.0):
        # The service tells the fake shell after it has answered the
        # caller, so the line can land a moment after the call returns.
        seen, deadline = "", time.monotonic() + timeout
        while True:
            seen += logged()
            if text in seen or time.monotonic() > deadline:
                return seen
            time.sleep(0.05)

    proc = start()
    try:
        call, _ = ask("t1")
        request = wait_request()
        check("the sheet gets the request", request is not None and request["title"] == "Allow Test Camera to use the camera?"
              and request["appIcon"] == "org.example.Cam", json.dumps(request))
        check("Allow answers", answer(request["id"], "allow"))
        out, err = call.communicate(timeout=10)
        check("Allow is response 0", out.strip() == "(uint32 0, @a{sv} {})", out + err)
        check("an answered request can't be answered again", not answer(request["id"], "deny"))

        call, _ = ask("t2")
        request = wait_request()
        check("a bad answer is refused", not answer(request["id"], "yes"))
        answer(request["id"], "deny")
        out, err = call.communicate(timeout=10)
        check("Don't allow is response 1", out.strip() == "(uint32 1, @a{sv} {})", out + err)

        call, _ = ask("t3", options="{'choices': <[('c1', 'Remember', @a(ss) [], 'true')]>}")
        request = wait_request()
        answer(request["id"], "allow")
        out, err = call.communicate(timeout=10)
        check("choices come back", out.strip() == "(uint32 0, {'choices': <[('c1', 'true')]>})", out + err)

        logged()
        started = time.monotonic()
        call, _ = ask("t4")
        request = wait_request()
        out, err = call.communicate(timeout=10)
        took = time.monotonic() - started
        check("no answer times out with an error, not a response",
              call.returncode != 0 and pa.ERROR in err and 1.5 < took < 6, "%s %s %.1fs" % (out, err, took))
        check("a timed-out sheet is taken back", '"id": "%s"' % request["id"] in logged_soon('"id": "%s"' % request["id"]))

        call, handle = ask("t5")
        request = wait_request()
        dbus.SessionBus().get_object(pa.BUS_NAME, handle).Close(dbus_interface=pa.REQUEST_IFACE)
        out, err = call.communicate(timeout=10)
        check("the app closing its request ends it with an error", call.returncode != 0 and pa.ERROR in err, out + err)
        check("a closed request's sheet is taken back", "dismiss" in logged_soon("dismiss"))
        check("an unknown id is refused", not answer("0123456789abcdef", "allow"))

        # Back on the sheet: no response (the portal stores nothing and the
        # app asks again), as a timeout, and at once.
        logged()
        started = time.monotonic()
        call, _ = ask("t6")
        request = wait_request()
        check("Back's dismiss is taken", answer(request["id"], "dismiss"))
        out, err = call.communicate(timeout=10)
        check("a dismissed request ends with an error, not a stored No",
              call.returncode != 0 and pa.ERROR in err and "uint32" not in out and time.monotonic() - started < 1.5, out + err)
        check("a dismissed request can't be answered afterwards", not answer(request["id"], "allow"))
        check("an unknown id can't be dismissed", not answer("0123456789abcdef", "dismiss"))
    finally:
        stop(proc)

    for name, env in (("locked", {"FAKE_LOCKED": "true"}), ("no shell", {"FAKE_DOWN": "1"}),
                      ("no plugin", {"FAKE_FAIL": "1"})):
        proc = start(**env)
        try:
            logged()
            started = time.monotonic()
            call, _ = ask("x" + name.replace(" ", ""))
            out, err = call.communicate(timeout=10)
            took = time.monotonic() - started
            check("%s: an error at once, nothing stored" % name,
                  call.returncode != 0 and pa.ERROR in err and took < 1.5, "%s %s %.1fs" % (out, err, took))
            if name == "locked":
                check("locked: no sheet is asked for", "shell call" not in logged())
        finally:
            stop(proc)

    proc = start()
    try:
        call, _ = ask("t6")
        wait_request()
        stop(proc)
        out, err = call.communicate(timeout=10)
        check("a stopping service answers with an error", call.returncode != 0, out + err)
    finally:
        if proc.poll() is None:
            stop(proc)
    shutil.rmtree(work, ignore_errors=True)


if os.environ.get("DBUS_SESSION_BUS_ADDRESS") and shutil.which("gdbus"):
    try:
        import dbus  # noqa: F401
        import gi  # noqa: F401
    except ImportError:
        print("ok - portal service # SKIP no python-dbus or python-gobject")
    else:
        service_tests()
else:
    print("ok - portal service # SKIP no session bus")

shutil.rmtree(data, ignore_errors=True)
sys.exit(1 if failures else 0)
