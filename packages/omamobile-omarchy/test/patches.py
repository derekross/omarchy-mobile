#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""omamobile-omarchy-patches against synthetic Omarchy trees, and against the
real aarch64 omarchy package when one is at hand (OMARCHY_PKG=path, or the
root image build's pacman cache, ~/.cache/omamobile-rootfs/pkg).

Each synthetic case builds a root with a fake pacman local database (desc and
a gzipped mtree) the way pacman leaves one."""
import glob
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
TOOL = os.path.join(PKG, "bin", "omamobile-omarchy-patches")
SERIES = os.path.join(PKG, "patches")
STATE = "var/lib/omamobile/omarchy-patches"

failures = 0


def ok(cond, what):
    global failures
    if cond:
        print("ok - " + what)
    else:
        failures += 1
        print("not ok - " + what)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(root, *args, series=None, env=None):
    cmd = [sys.executable, "-I", TOOL] + list(args) + ["--root", root]
    if series:
        cmd += ["--series", series]
    e = dict(os.environ)
    e.update(env or {})
    p = subprocess.run(cmd, capture_output=True, text=True, env=e)
    return p.returncode, p.stdout + p.stderr


# ---------------------------------------------------------------- synthetic Omarchy


A_V1 = "import QtQuick\nItem {\n  // palette\n  color: Color.text\n  width: 10\n  height: 20\n}\n"
A_QUALIFIED = A_V1.replace("color: Color.text", "color: Commons.Color.text")
A_PHONE = A_QUALIFIED.replace("  width: 10\n", "  width: 10\n  // phone\n  touch: true\n")
TOOL_V1 = "#!/bin/bash\necho one\necho two\necho three\n"
TOOL_PHONE = TOOL_V1.replace("echo two\n", "echo two\necho phone\n")
TOOL_V3 = "#!/bin/bash\necho one\necho TWO-CHANGED\necho three\n"
LUA_V1 = "-- settings\nlocal a = 1\n-- old comment\nlocal b = 2\nreturn a + b\n"
LUA_PHONE = LUA_V1.replace("-- old comment\n", "")
NEW_QML = "import QtQuick\nItem { id: keypad }\n"


def udiff(old, new, path, created=False):
    """A -p1 unified diff with git's i/ w/ prefixes."""
    with tempfile.TemporaryDirectory() as d:
        a, b = os.path.join(d, "a"), os.path.join(d, "b")
        with open(a, "w") as f:
            f.write(old)
        with open(b, "w") as f:
            f.write(new)
        out = subprocess.run(["diff", "-u", a, b], capture_output=True, text=True).stdout
    lines = out.splitlines(keepends=True)[2:]
    head = "--- %s\n+++ w/%s\n" % ("/dev/null" if created else "i/" + path, path)
    if created:
        lines = [l.replace("@@ -1,0 ", "@@ -0,0 ", 1) if l.startswith("@@") else l for l in lines]
    return head + "".join(lines)


def write_series(d, patches):
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    for name, text in patches.items():
        with open(os.path.join(d, name), "w") as f:
            f.write("# test patch %s\n%s" % (name, text))
    return d


def install_omarchy(root, version, files, links):
    """What pacman does on an install or upgrade: every file of the package
    written, the local database entry replaced. Files outside it stay."""
    for rel, text in files.items():
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if os.path.lexists(p):
            os.unlink(p)
        with open(p, "w") as f:
            f.write(text)
    for rel, target in links.items():
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if os.path.lexists(p):
            os.unlink(p)
        os.symlink(target, p)
    db = os.path.join(root, "var/lib/pacman/local")
    for old in glob.glob(os.path.join(db, "omarchy-*")):
        shutil.rmtree(old)
    entry = os.path.join(db, "omarchy-%s" % version)
    os.makedirs(entry)
    with open(os.path.join(entry, "desc"), "w") as f:
        f.write("%%NAME%%\nomarchy\n\n%%VERSION%%\n%s\n\n" % version)
    lines = ["#mtree", "/set type=file uid=0 gid=0 mode=644"]
    for rel, text in sorted(files.items()):
        lines.append("./%s time=1.0 size=%d sha256digest=%s" % (rel, len(text.encode()), sha(text.encode())))
    for rel, target in sorted(links.items()):
        lines.append("./%s time=1.0 type=link link=%s" % (rel, target))
    with gzip.open(os.path.join(entry, "mtree"), "wt") as f:
        f.write("\n".join(lines) + "\n")


def omarchy_files(a=A_V1, tool=TOOL_V1, lua=LUA_V1):
    return ({"usr/share/omarchy/shell/a.qml": a, "usr/bin/omarchy-tool": tool,
             "usr/share/omarchy/default/hypr/x.lua": lua, "usr/share/omarchy/shell/b.qml": "Item {}\n"},
            {"usr/share/omarchy/bin/omarchy-tool": "/usr/bin/omarchy-tool"})


SERIES_FULL = {
    "0000-backport-qualify.patch": udiff(A_V1, A_QUALIFIED, "shell/a.qml"),
    "0001-tool.patch": udiff(TOOL_V1, TOOL_PHONE, "bin/omarchy-tool"),
    "0002-new-keypad.patch": udiff("", NEW_QML, "shell/plugins/lock/Keypad.qml", created=True),
    "0003-phone-on-qualified.patch": udiff(A_QUALIFIED, A_PHONE, "shell/a.qml"),
    "0004-lua-drop-comment.patch": udiff(LUA_V1, LUA_PHONE, "default/hypr/x.lua"),
}


def read(root, rel):
    p = os.path.join(root, rel)
    return open(p).read() if os.path.isfile(p) else None


def omarchy_intact(root, files):
    return all(read(root, rel) == text for rel, text in files.items())


def synthetic(t):
    root = os.path.join(t, "root")
    series = write_series(os.path.join(t, "series"), SERIES_FULL)
    notified = os.path.join(t, "notified")
    notify = os.path.join(t, "notify")
    with open(notify, "w") as f:
        f.write("#!/bin/sh\nprintf '%%s|%%s\\n' \"$1\" \"$2\" >> %s\n" % notified)
    os.chmod(notify, 0o755)
    env = {"OMAMOBILE_NOTIFY_CMD": notify}
    files, links = omarchy_files()
    install_omarchy(root, "1.0-1", files, links)

    ok("-- old comment" in SERIES_FULL["0004-lua-drop-comment.patch"].split("@@", 2)[2]
       and "\n--- old comment\n" in SERIES_FULL["0004-lua-drop-comment.patch"],
       "fixture: a removed Lua comment shows as a '--- ' line in a hunk")

    # Apply on a fresh install
    rc, out = run(root, "apply", series=series, env=env)
    ok(rc == 0, "apply: exit 0 (%s)" % out.strip().splitlines()[-1:])
    ok(read(root, "usr/share/omarchy/shell/a.qml") == A_PHONE, "apply: patches in order (0003 on 0000)")
    ok(read(root, "usr/bin/omarchy-tool") == TOOL_PHONE, "apply: a bin/ link's target is patched")
    ok(os.path.islink(os.path.join(root, "usr/share/omarchy/bin/omarchy-tool")), "apply: the link stays a link")
    ok(read(root, "usr/share/omarchy/shell/plugins/lock/Keypad.qml") == NEW_QML, "apply: a new file is created")
    ok(read(root, "usr/share/omarchy/default/hypr/x.lua") == LUA_PHONE, "apply: a hunk removing '-- ...' lines is parsed as a hunk")
    status = json.load(open(os.path.join(root, STATE, "status.json")))
    ok(status["result"] == "ok" and len(status["applied"]) == 5 and not status["upstream"], "apply: status.json says 5 applied")
    ok(os.path.isfile(os.path.join(root, "var/log/omamobile/omarchy-patches.log")), "apply: logs to /var/log/omamobile")
    rc, out = run(root, "verify")
    ok(rc == 0, "verify: the series is in place")

    # Already applied: nothing written
    before = os.stat(os.path.join(root, "usr/share/omarchy/shell/a.qml")).st_mtime_ns
    rc, out = run(root, "apply", series=series, env=env)
    ok(rc == 0 and "already applied" in out, "apply again: already applied")
    ok(os.stat(os.path.join(root, "usr/share/omarchy/shell/a.qml")).st_mtime_ns == before, "apply again: nothing rewritten")

    # Omarchy upgrade that contains 0000: reported as upstream, the rest applied
    files, links = omarchy_files(a=A_QUALIFIED)
    install_omarchy(root, "1.1-1", files, links)
    rc, out = run(root, "apply", "--hook", series=series, env=env)
    status = json.load(open(os.path.join(root, STATE, "status.json")))
    ok(rc == 0, "upgrade with 0000 upstream: exit 0")
    ok(status["upstream"] == ["0000-backport-qualify.patch"] and len(status["applied"]) == 4,
       "upgrade with 0000 upstream: 0000 skipped and reported, 4 applied")
    ok("upstream  0000-backport-qualify.patch" in out, "upgrade with 0000 upstream: said in the output")
    ok(read(root, "usr/share/omarchy/shell/a.qml") == A_PHONE, "upgrade with 0000 upstream: 0003 still applies")
    ok(not os.path.exists(notified), "upgrade with 0000 upstream: no failure notification")

    # A patch that no longer applies: Omarchy's files left exactly as shipped
    files, links = omarchy_files(a=A_QUALIFIED, tool=TOOL_V3)
    install_omarchy(root, "1.2-1", files, links)
    rc, out = run(root, "apply", "--hook", series=series, env=env)
    status = json.load(open(os.path.join(root, STATE, "status.json")))
    ok(rc == 1, "failing patch: exit 1")
    ok(omarchy_intact(root, files), "failing patch: every Omarchy file is as the package shipped it")
    ok(status["result"] == "failed" and status["failed"]["patch"] == "0001-tool.patch", "failing patch: status names 0001")
    ok(os.path.exists(notified) and "PIN pad" in open(notified).read(), "failing patch: the user is notified")
    ok("FAILED" in open(os.path.join(root, "var/log/omamobile/omarchy-patches.log")).read(), "failing patch: logged")
    ok(not glob.glob(os.path.join(root, STATE, "omamobile-omarchy-patches-*")), "failing patch: no scratch left")
    os.unlink(notified)

    # The fixed series on the same Omarchy: applies, from the pristine files
    fixed = dict(SERIES_FULL)
    fixed["0001-tool.patch"] = udiff(TOOL_V3, TOOL_V3.replace("echo TWO-CHANGED\n", "echo TWO-CHANGED\necho phone\n"), "bin/omarchy-tool")
    series2 = write_series(os.path.join(t, "series2"), fixed)
    rc, out = run(root, "apply", series=series2, env=env)
    ok(rc == 0 and "echo phone" in read(root, "usr/bin/omarchy-tool"), "new series after a failure: applies")

    # A series that drops a patch: its file goes back to Omarchy's, a file it
    # created goes away
    dropped = dict(fixed)
    del dropped["0002-new-keypad.patch"]
    del dropped["0004-lua-drop-comment.patch"]
    series3 = write_series(os.path.join(t, "series3"), dropped)
    rc, out = run(root, "apply", series=series3, env=env)
    ok(rc == 0, "dropped patches: exit 0")
    ok(read(root, "usr/share/omarchy/shell/plugins/lock/Keypad.qml") is None, "dropped patches: the created file is removed")
    ok(read(root, "usr/share/omarchy/default/hypr/x.lua") == LUA_V1, "dropped patches: the file is Omarchy's again")
    ok(read(root, "usr/share/omarchy/shell/a.qml") == A_PHONE, "dropped patches: the rest stay applied")

    # A file changed by something else: refuse, touch nothing
    with open(os.path.join(root, "usr/share/omarchy/shell/a.qml"), "a") as f:
        f.write("// edited by hand\n")
    snapshot = {rel: read(root, rel) for rel in list(files) + ["usr/share/omarchy/shell/a.qml"]}
    rc, out = run(root, "apply", series=series2, env=env)
    ok(rc == 1 and "changed outside" in out, "hand-edited file: refused")
    ok(all(read(root, rel) == text for rel, text in snapshot.items()), "hand-edited file: nothing touched")
    if os.path.exists(notified):
        os.unlink(notified)

    # pacman -S omarchy puts Omarchy's files back; the hook then applies again
    install_omarchy(root, "1.2-1", files, links)
    rc, out = run(root, "apply", "--hook", series=series2, env=env)
    ok(rc == 0 and read(root, "usr/share/omarchy/shell/a.qml") == A_PHONE, "after a reinstall: applies again")

    # restore: Omarchy's files back, created ones removed
    rc, out = run(root, "restore")
    ok(rc == 0 and omarchy_intact(root, files) and read(root, "usr/share/omarchy/shell/plugins/lock/Keypad.qml") is None,
       "restore: Omarchy's own files are back")

    # A phone patched at image build (no state): recovered by reversing the series
    root2 = os.path.join(t, "root2")
    files, links = omarchy_files()
    install_omarchy(root2, "1.0-1", files, links)
    built = {"usr/share/omarchy/shell/a.qml": A_PHONE, "usr/bin/omarchy-tool": TOOL_PHONE,
             "usr/share/omarchy/default/hypr/x.lua": LUA_PHONE, "usr/share/omarchy/shell/plugins/lock/Keypad.qml": NEW_QML}
    for rel, text in built.items():
        os.makedirs(os.path.dirname(os.path.join(root2, rel)), exist_ok=True)
        with open(os.path.join(root2, rel), "w") as f:
            f.write(text)
    extra = dict(SERIES_FULL)
    extra["0005-more.patch"] = udiff("Item {}\n", "Item { id: more }\n", "shell/b.qml")
    series4 = write_series(os.path.join(t, "series4"), extra)
    rc, out = run(root2, "apply", series=series4, env=env)
    ok(rc == 0 and "reversing" in out, "image-patched files without state: Omarchy's copies recovered by reversing")
    ok(all(read(root2, rel) == text for rel, text in built.items()) and read(root2, "usr/share/omarchy/shell/b.qml") == "Item { id: more }\n",
       "image-patched files without state: the new series applied on top")

    # From the pacman cache when nothing else has Omarchy's copy
    root3 = os.path.join(t, "root3")
    files, links = omarchy_files()
    install_omarchy(root3, "1.0-1", files, links)
    if shutil.which("bsdtar"):
        stage = os.path.join(t, "pkgstage")
        for rel, text in files.items():
            os.makedirs(os.path.dirname(os.path.join(stage, rel)), exist_ok=True)
            with open(os.path.join(stage, rel), "w") as f:
                f.write(text)
        cache = os.path.join(root3, "var/cache/pacman/pkg")
        os.makedirs(cache)
        subprocess.run(["bsdtar", "-cf", os.path.join(cache, "omarchy-1.0-1-aarch64.pkg.tar.gz"), "-z", "-C", stage, "usr"], check=True)
        with open(os.path.join(root3, "usr/share/omarchy/shell/b.qml"), "w") as f:
            f.write("Item { id: unknown }\n")
        rc, out = run(root3, "apply", series=series4, env=env)
        ok(rc == 0 and "package cache" in out and read(root3, "usr/share/omarchy/shell/b.qml") == "Item { id: more }\n",
           "Omarchy's copy from the package cache")
    else:
        print("ok - Omarchy's copy from the package cache # SKIP no bsdtar")

    # No Omarchy: nothing to do
    root4 = os.path.join(t, "root4")
    os.makedirs(os.path.join(root4, "var/lib/pacman/local"))
    rc, out = run(root4, "apply", series=series, env=env)
    ok(rc == 0 and "not installed" in out, "no Omarchy installed: nothing to do")

    # The shipped series parses: every patch changes a file, with -p1 paths
    sys.path.insert(0, os.path.dirname(TOOL))
    import importlib.machinery
    import importlib.util
    loader = importlib.machinery.SourceFileLoader("patches_tool", TOOL)
    spec = importlib.util.spec_from_loader("patches_tool", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    empty = os.path.join(t, "empty")
    os.makedirs(empty)
    pats, digest = mod.load_series(SERIES, empty)
    ok(len(pats) == len(glob.glob(os.path.join(SERIES, "*.patch"))) and all(p.files for p in pats), "the shipped series parses (%d patches)" % len(pats))
    ok(all(f.startswith("usr/share/omarchy/") for p in pats for f in p.files), "shipped series: paths land in /usr/share/omarchy")


# ---------------------------------------------------------------- the real package


def real_package(t):
    pkg = os.environ.get("OMARCHY_PKG")
    if not pkg:
        cands = sorted(glob.glob(os.path.expanduser("~/.cache/omamobile-rootfs/pkg/omarchy-[0-9]*-aarch64.pkg.tar.*")))
        cands = [c for c in cands if not c.endswith(".sig")]
        pkg = cands[-1] if cands else ""
    if not pkg or not shutil.which("bsdtar"):
        print("ok - the real Omarchy package # SKIP no omarchy package (OMARCHY_PKG=...) or bsdtar")
        return
    ex = os.path.join(t, "pkg")
    os.makedirs(ex)
    subprocess.run(["bsdtar", "-xf", pkg, "-C", ex], check=True)
    info = dict(l.split(" = ", 1) for l in open(os.path.join(ex, ".PKGINFO")).read().splitlines() if " = " in l)
    version = info["pkgver"]

    def make_root(name, mtree_from):
        root = os.path.join(t, name)
        os.makedirs(root)
        shutil.copytree(os.path.join(ex, "usr"), os.path.join(root, "usr"), symlinks=True)
        entry = os.path.join(root, "var/lib/pacman/local/omarchy-%s" % version)
        os.makedirs(entry)
        with open(os.path.join(entry, "desc"), "w") as f:
            f.write("%%NAME%%\nomarchy\n\n%%VERSION%%\n%s\n\n" % version)
        if mtree_from:
            shutil.copy(mtree_from, os.path.join(entry, "mtree"))
        return root, entry

    root, _ = make_root("real", os.path.join(ex, ".MTREE"))
    rc, out = run(root, "apply", series=SERIES)
    ok(rc == 0, "real omarchy %s: the shipped series applies (%s)" % (version, out.strip().splitlines()[-1]))
    status = json.load(open(os.path.join(root, STATE, "status.json")))
    ok(not status["upstream"] and len(status["applied"]) == len(glob.glob(os.path.join(SERIES, "*.patch"))),
       "real omarchy %s: every patch applied, none upstream" % version)
    ok("omamobile-update" in read(root, "usr/bin/omarchy-update"), "real omarchy: omarchy-update hands over (0012)")
    ok(os.path.isfile(os.path.join(root, "usr/share/omarchy/shell/plugins/lock/Keypad.qml")), "real omarchy: the lock's keypad is there (0003)")
    notif = "usr/share/omarchy/shell/plugins/notifications/"
    ok("inlineReplySupported: true" in read(root, notif + "Service.qml")
       and "sendInlineReply" in read(root, notif + "Service.qml")
       and "notificationReplyField" in read(root, notif + "components/NotificationCard.qml"),
       "real omarchy: notifications take an inline reply (0015)")
    card = read(root, notif + "components/NotificationCard.qml")
    service = read(root, notif + "Service.qml")
    ok("DragHandler {\n    id: swipeHandler" in card and "yAxis.enabled: false" in card
       and "dragThreshold:" in card and "root.width * 0.35" in card
       and "root.closeRequested()" in card.split("function finishSwipe", 1)[1]
       and "!root.replying" in card.split("id: swipeHandler", 1)[1].split("}", 1)[0],
       "real omarchy: a toast swipes away past 35%, not while a reply is typed (0017)")
    ok('objectName: "notificationCloseButton"' in card and "width: Style.space(44)" in card
       and "height: Style.space(44)" in card and "visible: root.closeButtonShown" in card,
       "real omarchy: a 44 px close button on toasts (0017)")
    ok("acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus" in card
       and "mouse.button === Qt.RightButton" in card,
       "real omarchy: hover pauses for a mouse only; right-click still closes (0017)")
    ok("!card.held" in service and "closeButtonShown: service.touchScreen" in service
       and '["hyprctl", "-j", "devices"]' in service and "touchScreenProc.running = true" in service,
       "real omarchy: the close button shows when Hyprland lists a touch screen (0017)")
    forget = service.split("function forgetNotification(name) {", 1)
    ok(len(forget) == 2 and "function forget(name: string): string {\n      return service.forgetNotification(name)" in service
       and "/^[0-9]+-[0-9]+\\.json$/.test(file)" in forget[1].split("\n  }\n", 1)[0]
       and 'removePopup(i, "forget")' in forget[1].split("\n  }\n", 1)[0]
       and "enqueuePopupFileJob(" in forget[1].split("\n  }\n", 1)[0]
       and 'if (reason === "forget") deletePopupFileFor(entry)\n      else archivePopupFileFor(entry)' in service,
       "real omarchy: forget takes one notification away, toast or history, on the file queue (0019)")
    menu = read(root, "usr/share/omarchy/shell/plugins/menu/Menu.qml")
    back = menu.split("DragHandler {\n        id: backSwipe", 1)
    ok(len(back) == 2 and "yAxis.enabled: false" in back[1].split("}", 1)[0]
       and "!resultList.moving" in back[1].split("}", 1)[0] and "root.goBack()" in back[1].split("NumberAnimation", 1)[0],
       "real omarchy: a swipe right on the menu goes back, not while the list scrolls (0018)")
    ok('objectName: "menuBackButton"' in menu and "visible: card.canGoBack" in menu
       and 'root.activeMenu !== "root" && !root.dmenuActive' in menu
       and menu.split('objectName: "menuBackButton"', 1)[1].count("onClicked: root.goBack()") >= 1,
       "real omarchy: the menu's header has a back button below the top level (0018)")
    ok("(event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {\n            root.goBack()" in menu,
       "real omarchy: Backspace and Left still go back (0018)")
    ok("property bool cardSettled: false" in menu, "real omarchy: the menu-first-frame bridge applies after 0018")
    qml_parse(root)
    lock_glance(root)
    for name in ("omarchy-channel-set", "omarchy-refresh-pacman"):
        text = read(root, "usr/bin/" + name)
        guard = text.find("if [[ -x /usr/bin/omamobile-update ]]")
        ok(guard >= 0 and (text.find("sudo ") < 0 or guard < text.find("sudo ")),
           "real omarchy: %s refuses on a phone before it touches pacman (0016)" % name)
        ok("RELEASES.md section 5.4" in text, "real omarchy: %s points at RELEASES 5.4" % name)
    screensaver_launcher(t, os.path.join(root, "usr/bin/omarchy-launch-screensaver"))
    notification_phrasing(t, os.path.join(root, "usr/bin/omarchy-notification-send"),
                          os.path.join(ex, "usr/bin/omarchy-notification-send"))
    rc, out = run(root, "apply", series=SERIES)
    ok(rc == 0 and "already applied" in out, "real omarchy: already applied")
    rc, _ = run(root, "verify")
    ok(rc == 0, "real omarchy: verify")

    # An Omarchy that already contains one of the series (the first that
    # touches no symlinks): the package as shipped plus that patch, with an
    # mtree to match
    root2, entry = make_root("real-upstream", None)

    def touches_no_links(path):
        names = [l[6:].split("\t")[0].rstrip("\n") for l in open(path) if l.startswith("+++ w/")]
        return names and not any(os.path.islink(os.path.join(root2, "usr/share/omarchy", n)) for n in names)

    patch0000 = next(p for p in sorted(glob.glob(os.path.join(SERIES, "*.patch"))) if touches_no_links(p))
    p = mod_patch(root2, patch0000)
    subprocess.run(["patch", "-s", "-p1", "-d", root2, "-i", p], check=True)
    lines = ["#mtree", "/set type=file uid=0 gid=0 mode=644"]
    for dirpath, _dirs, names in os.walk(os.path.join(root2, "usr")):
        for n in names:
            full = os.path.join(dirpath, n)
            rel = os.path.relpath(full, root2)
            if os.path.islink(full):
                lines.append("./%s type=link link=%s" % (rel, os.readlink(full)))
            else:
                lines.append("./%s sha256digest=%s" % (rel, sha(open(full, "rb").read())))
    with gzip.open(os.path.join(entry, "mtree"), "wt") as f:
        f.write("\n".join(lines) + "\n")
    rc, out = run(root2, "apply", series=SERIES)
    status = json.load(open(os.path.join(root2, STATE, "status.json")))
    ok(rc == 0 and status["upstream"] == [os.path.basename(patch0000)],
       "real omarchy with %s upstream: skipped and reported, the rest applied" % os.path.basename(patch0000))
    ok(len(status["applied"]) == len(glob.glob(os.path.join(SERIES, "*.patch"))) - 1, "real omarchy with one patch upstream: the others apply on it")


def qml_parse(root):
    """Every QML file the series touches still parses, when qmlformat is at
    hand (it reports syntax errors without needing the shell's imports)."""
    tool = shutil.which("qmlformat") or ("/usr/lib/qt6/bin/qmlformat" if os.path.isfile("/usr/lib/qt6/bin/qmlformat") else "")
    if not tool:
        print("ok - real omarchy: the patched QML parses # SKIP no qmlformat")
        return
    files = set()
    for p in glob.glob(os.path.join(SERIES, "*.patch")):
        for line in open(p):
            if line.startswith("+++ w/") and line.rstrip().endswith(".qml"):
                files.add(line[6:].rstrip())
    bad = [f for f in sorted(files)
           if subprocess.run([tool, os.path.join(root, "usr/share/omarchy", f)], capture_output=True).returncode != 0]
    ok(files and not bad, "real omarchy: the %d patched QML files parse (qmlformat)%s" % (len(files), " " + str(bad) if bad else ""))


def lock_glance(root):
    """Patch 0023: the lock's glance view. Static checks on the patched
    files, then test/lock-glance (qmltestrunner, offscreen) against them."""
    lock = "usr/share/omarchy/shell/plugins/lock/"
    view = read(root, lock + "LockView.qml")
    service = read(root, lock + "Service.qml")
    card = read(root, "usr/share/omarchy/shell/plugins/notifications/components/NotificationCard.qml")
    ok(os.path.isfile(os.path.join(root, lock + "LockGlance.qml")) and os.path.isfile(os.path.join(root, lock + "LockGlance.js"))
       and "LockGlance {\n      id: glance" in view,
       "real omarchy: the lock has a glance view (0023)")
    ok(view.count("opacity: root.pinOpacity") == 4 and view.count("&& root.pinVisible") == 3 and "visible: root.pinVisible" in view,
       "real omarchy: every part of the PIN view hides under the glance (0023)")
    wake = service.split("function wake(): string {", 1)
    ok(len(wake) == 2 and "root.wakeSerial += 1" in wake[1].split("}", 1)[0]
       and "wakeSerial: root.wakeSerial" in service,
       "real omarchy: the wake call brings the glance back (0023)")
    blank = service.split("function runBlank() {", 1)
    dark = service.split("function dark(): string {", 1)
    run_wake = service.split("function runWake() {", 1)
    ok(len(blank) == 2 and "markDark()" in blank[1].split("}", 1)[0]
       and len(dark) == 2 and "root.markDark()" in dark[1].split("}", 1)[0]
       and len(run_wake) == 2 and "displayDark = false" in run_wake[1].split("}", 1)[0]
       and "blankSerial: root.blankSerial" in service and "displayDark: root.displayDark" in service,
       "real omarchy: the lock's blank and the dark call bring the glance back, a wake lights it (0023)")
    ok("maximumLineCount: root.summaryLines" in card and "maximumLineCount: root.bodyLines" in card
       and "property int summaryLines: 2" in card and "property int bodyLines: 3" in card,
       "real omarchy: notification toasts keep their line counts (0023)")
    glance = read(root, lock + "LockGlance.qml") + read(root, lock + "LockGlance.js")
    ok("XMLHttpRequest" not in glance and "curl" not in glance and "execDetached" not in glance
       and "call notifications forget" in glance and "invokeAction" not in glance,
       "real omarchy: the glance asks no network and runs no notification action, only the forget call (0023)")
    p = subprocess.run(["bash", os.path.join(HERE, "lock-glance"), os.path.join(root, "usr/share/omarchy/shell")],
                       capture_output=True, text=True)
    if p.returncode == 77:
        print("ok - real omarchy: the glance under qmltestrunner # SKIP no qmltestrunner")
        return
    out = p.stdout + p.stderr
    totals = [l for l in out.splitlines() if l.startswith("Totals:")]
    ok(p.returncode == 0, "real omarchy: the glance under qmltestrunner (0023: %s)" % (totals[-1] if totals else "no result"))
    if p.returncode != 0:
        print("\n".join(l for l in out.splitlines() if l.startswith(("FAIL", "   ", "QWARN")))[:4000])


def screensaver_launcher(t, launcher):
    """Patch 0006's launcher against fake commands: every way out of it puts
    the on-screen keyboard back unless a screensaver runs (TOUCH-PLAN 0.5)."""
    fakes = os.path.join(t, "ss-fakes")
    runtime = os.path.join(t, "ss-runtime")
    os.makedirs(fakes)
    os.makedirs(runtime)
    state = os.path.join(t, "ss-osk")
    log = os.path.join(t, "ss-log")

    def fake(name, body):
        path = os.path.join(fakes, name)
        with open(path, "w") as f:
            f.write("#!/bin/bash\n" + body + "\n")
        os.chmod(path, 0o755)

    fake("omarchy-cmd-missing", "exit 1")
    fake("pgrep", "exit 1")  # no screensaver running
    fake("omarchy-toggle-enabled", "exit 1")
    fake("omarchy-hyprland-monitor-focused", "echo DSI-1")
    fake("omarchy-shell", '[[ "$*" == "lock isLocked" ]] && echo "${FAKE_LOCKED:-false}"')
    fake("busctl", "exit 0")  # squeekboard is on the bus
    fake("gsettings", 'case $1 in get) cat "$FAKE_OSK" ;; set) echo "$4" > "$FAKE_OSK"; echo "set $4" >> "$FAKE_LOG" ;; esac')
    fake("xdg-terminal-exec", 'sleep "${FAKE_TERMINAL_DELAY:-0}"; echo xterm.desktop')
    fake("omarchy-notification-send", "exit 0")
    fake("hyprctl", "exit 0")

    def start(**extra):
        with open(state, "w") as f:
            f.write("true\n")
        open(log, "w").close()
        env = {"PATH": fakes + ":/usr/bin:/bin", "HOME": t, "XDG_RUNTIME_DIR": runtime,
               "FAKE_OSK": state, "FAKE_LOG": log}
        env.update(extra)
        return subprocess.Popen(["bash", launcher], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def osk():
        return open(state).read().strip()

    marker = os.path.join(runtime, "omarchy-screensaver-osk-off")
    p = start()
    p.wait(timeout=20)
    ok(open(log).read() == "set false\nset true\n" and osk() == "true" and not os.path.exists(marker),
       "0006: an early exit (no supported terminal) turns the keyboard back on")

    p = start(FAKE_LOCKED="true")
    p.wait(timeout=20)
    ok(open(log).read() == "" and osk() == "true", "0006: a locked session leaves the keyboard setting alone")

    p = start(FAKE_TERMINAL_DELAY="1")
    for _ in range(100):
        if osk() == "false":
            break
        subprocess.run(["sleep", "0.05"])
    p.terminate()
    p.wait(timeout=20)
    ok(osk() == "true" and not os.path.exists(marker), "0006: a launcher stopped by a signal turns the keyboard back on")


# Omarchy 4.0.6's notification texts (headline, body) and what a phone shows
# for each (patch 0020); None leaves the text as it is.
PHRASINGS = [
    (("Screenshot saved to clipboard and file", "Edit with Super + Alt + , (or click this)"), "Tap to edit"),
    (("Screen recording saved", "Open with Super + Alt + , (or click this)"), "Tap to open"),
    (("Update System", "Click to update the system."), "Tap to update the system."),
    (("Setup Wi-Fi", "Click to configure the wireless network."), "Tap to configure the wireless network."),
    (("Install Dictation with Voxtype", "Click to install voice dictation for Omarchy."),
     "Tap to install voice dictation for Omarchy."),
    (("Voxtype Dictation Ready", "Hold F9 to dictate (or toggle with Super + Ctrl + X)."),
     "Use the Dictation tile in quick settings."),
    (("Run Migrations", "Click to run 1 pending migration."), "Tap to run 1 pending migration."),
    (("Run Migrations", "Click to run 3 pending migrations."), "Tap to run 3 pending migrations."),
    (("Process crashed: foot", "Click to diagnose with AI"), "Tap to diagnose with AI"),
    (("Learn Keybindings", "Super + K for cheatsheet.\nSuper + Space for Omarchy Menu."), ""),
    (("Pong installed", "Start it with Super + Space"), ""),
    (("No saved width found for kitty on workspace 2", "Use Super + Alt + Home to save one for this workspace."), ""),
    (("Saved width for kitty on workspace 2", "Restore using Super + Home on this workspace."), ""),
    (("Copied", "Paste it anywhere (or press Super + Ctrl + V for history)."), "Paste it anywhere."),
    (("Reminder", "5 minutes are up (click the bar to snooze)"), None),
    (("Two lines", "Line one\nline two"), None),
    (("Battery low", ""), None),
]


def notification_phrasing(t, patched, original):
    """Patch 0020's phrasing, with a stub busctl that records the summary
    and body: a phone rewords each Omarchy text above, and a desktop sends
    exactly what the unpatched script sends."""
    fakes = os.path.join(t, "notify-fakes")
    os.makedirs(fakes)
    with open(os.path.join(fakes, "busctl"), "w") as f:
        # --user -- call DEST PATH IFACE Notify SIG app_name replaces_id app_icon summary body ...
        f.write('#!/bin/bash\nprintf "%s\\0" "$@" > "$FAKE_OUT"\necho "u 7"\n')
    os.chmod(os.path.join(fakes, "busctl"), 0o755)
    out = os.path.join(t, "notify-out")

    def send(script, args, phrasing):
        env = {"PATH": fakes + ":/usr/bin:/bin", "HOME": t, "FAKE_OUT": out}
        if phrasing:
            env["OMARCHY_NOTIFICATION_PHRASING"] = phrasing
        r = subprocess.run(["bash", script] + list(args), env=env, capture_output=True, text=True)
        return r.returncode, open(out).read().split("\0")[:-1] if r.returncode == 0 else r.stderr

    bad_phone, bad_desktop = [], []
    for (head, body), want in PHRASINGS:
        args = ["-u", "critical", "-g", "x", head, body, "--exec", "true"]
        rc, argv = send(patched, args, "touch")
        expect_head = head
        expect_body = body if want is None else want
        if rc != 0 or argv[11:13] != [expect_head, expect_body]:
            bad_phone.append((body, argv[11:13] if rc == 0 else argv))
        orig = send(original, args, None)
        # Unforced too, unless this runs on a phone (a build on the phone does)
        for mode in ("desktop",) + (() if os.path.exists("/usr/bin/omamobile-update") else (None,)):
            if send(patched, args, mode) != orig:
                bad_desktop.append((body, mode))
    ok(not bad_phone, "0020: a phone gets tap wording and no Super hints (%d texts)%s"
       % (len(PHRASINGS), " " + repr(bad_phone) if bad_phone else ""))
    ok(not bad_desktop, "0020: a desktop sends exactly what unpatched Omarchy sends%s"
       % (" " + repr(bad_desktop) if bad_desktop else ""))


def mod_patch(root, path):
    """A patch rewritten to real paths, for patch -d root (it touches no links)."""
    with open(path) as src, open(os.path.join(root, "p0000"), "w") as dst:
        for line in src:
            if line.startswith(("--- i/", "+++ w/", "--- a/", "+++ b/")):
                line = line[:4] + line[4] + "/usr/share/omarchy/" + line[6:]
            dst.write(line)
    return os.path.join(root, "p0000")


def main():
    with tempfile.TemporaryDirectory(prefix="omamobile-omarchy-test-") as t:
        synthetic(t)
        real_package(t)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
