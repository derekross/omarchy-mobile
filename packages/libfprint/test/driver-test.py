#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Offline test of libfprint's omamobile_udfps driver against a fake bridge.

    driver-test.py              (needs FPrint-2.0 from the libfprint build:
                                 GI_TYPELIB_PATH and LD_LIBRARY_PATH)

Starts a fake omamobile-fp-bridge on a Unix socket that speaks the bridge's
line protocol with scripted HAL answers, points the driver at it
(FP_OMAMOBILE_UDFPS), and runs enroll, list, verify (match and no match),
identify, cancel, a lockout, system sleep mid-verify and mid-enrollment,
delete and a bridge that goes away. No phone, no HAL: this checks the
driver's side of the protocol only.
"""
import os
import shutil
import socket
import sys
import tempfile
import threading
import time

import gi

gi.require_version("FPrint", "2.0")
from gi.repository import FPrint, GLib, Gio  # noqa: E402

ENROLL_ID = 123456789


class FakeBridge(threading.Thread):
    """One client at a time, as the real bridge. `script` maps a command to
    the lines to answer; "AUTH" answers come from `auth_answers` in turn."""

    def __init__(self, path):
        super().__init__(daemon=True)
        self.path = path
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind(path)
        self.sock.listen(2)
        self.enrolled = []
        self.auth_answers = []
        self.commands = []
        self.hold_auth = False
        self.hold_enroll = False
        self.conn = None
        self.drop_next = False
        self.mute_cancel = False

    def send(self, *lines):
        for line in lines:
            self.conn.sendall((line + "\n").encode())

    def run(self):
        while True:
            try:
                self.conn, _ = self.sock.accept()
            except OSError:
                return
            self.send("READY 720 2360 120")
            buf = b""
            while True:
                data = self.conn.recv(256)
                if not data:
                    break
                buf += data
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    self.handle(line.decode())
                if self.drop_next:
                    self.drop_next = False
                    self.conn.close()
                    break

    def handle(self, cmd):
        self.commands.append(cmd)
        if cmd == "ENROLL":
            if self.hold_enroll:
                self.send("FINGER NEEDED")
                return  # wait for CANCEL
            self.send("FINGER NEEDED", "FINGER DOWN", "ACQUIRED 1 0",
                      f"PROGRESS {ENROLL_ID} 38", "FINGER UP", "FINGER DOWN",
                      "ACQUIRED 2 0", "FINGER UP")
            for remaining in range(36, -1, -2):
                self.send("FINGER DOWN", f"PROGRESS {ENROLL_ID} {remaining}", "FINGER UP")
            self.enrolled.append(ENROLL_ID)
            self.send(f"ENROLLED {ENROLL_ID}")
        elif cmd == "AUTH":
            self.send("FINGER NEEDED")
            if self.hold_auth:
                return  # wait for CANCEL
            answer = self.auth_answers.pop(0) if self.auth_answers else "NOMATCH"
            self.send("FINGER DOWN", "ACQUIRED 1 0", answer, "FINGER UP")
        elif cmd == "CANCEL":
            if not self.mute_cancel:
                self.send("ERROR 5")
        elif cmd == "LIST":
            self.send("LIST" + "".join(f" {i}" for i in self.enrolled))
        elif cmd.startswith("DELETE "):
            i = int(cmd.split()[1])
            if i in self.enrolled:
                self.enrolled.remove(i)
                self.send(f"DELETED {i}")
            else:
                self.send("ERROR 6")
        else:
            self.send("ERROR 2")


failures = 0


def check(what, ok):
    global failures
    print(f"{'ok  ' if ok else 'FAIL'} {what}")
    if not ok:
        failures += 1


def main():
    tmp = tempfile.mkdtemp(prefix="omamobile-udfps-")
    orig_cwd = os.getcwd()
    os.chdir(tmp)
    try:
        return _run_driver_tests()
    finally:
        os.chdir(orig_cwd)
        shutil.rmtree(tmp, ignore_errors=True)


def _run_driver_tests():
    path = "bridge.sock"
    bridge = FakeBridge(path)
    bridge.start()
    os.environ["FP_OMAMOBILE_UDFPS"] = path

    ctx = FPrint.Context()
    devices = [d for d in ctx.get_devices() if d.get_driver() == "omamobile_udfps"]
    check("device found through FP_OMAMOBILE_UDFPS", len(devices) == 1)
    if not devices:
        return 1
    dev = devices[0]
    check("features: verify, identify, storage",
          dev.has_feature(FPrint.DeviceFeature.VERIFY)
          and dev.has_feature(FPrint.DeviceFeature.IDENTIFY)
          and dev.has_feature(FPrint.DeviceFeature.STORAGE))
    check("20 enroll stages", dev.get_nr_enroll_stages() == 20)

    dev.open_sync()

    template = FPrint.Print.new(dev)
    template.set_finger(FPrint.Finger.RIGHT_THUMB)
    template.set_username("tester")
    stages = []

    def progress(device, completed, print_, user_data, error):
        stages.append((completed, error.message if error else None))

    enrolled = dev.enroll_sync(template, None, progress, None)
    check("enroll completes", enrolled is not None)
    check("enroll reports a retry for PARTIAL", any(e for _, e in stages))
    check("enroll progress reaches 20", stages and stages[-1][0] == 20)
    data = enrolled.get_property("fpi-data")
    check("print carries the HAL id", data.unpack() == (ENROLL_ID,))
    check("print is device-stored", enrolled.props.device_stored)

    listed = dev.list_prints_sync()
    check("list returns the enrolled id",
          [p.get_property("fpi-data").unpack() for p in listed] == [(ENROLL_ID,)])

    bridge.auth_answers = [f"MATCH {ENROLL_ID}"]
    match, _ = dev.verify_sync(enrolled)
    check("verify: MATCH of the same id matches", match)

    bridge.auth_answers = ["MATCH 42"]
    match, _ = dev.verify_sync(enrolled)
    check("verify: MATCH of another id fails", not match)

    bridge.auth_answers = ["NOMATCH"]
    match, _ = dev.verify_sync(enrolled)
    check("verify: NOMATCH fails", not match)

    matched = []

    def on_match(device, match, print_, user_data, error):
        matched.append(match)

    bridge.auth_answers = [f"MATCH {ENROLL_ID}"]
    found, _ = dev.identify_sync([enrolled], None, on_match, None)
    check("identify: finds the enrolled print", found is not None and found.equal(enrolled))

    # fprintd's duplicate check before an enrollment: no match callback;
    # answered at once, without an AUTH (which would count toward lockout)
    auths = bridge.commands.count("AUTH")
    bridge.auth_answers = [f"MATCH {ENROLL_ID}"]
    found, _ = dev.identify_sync([enrolled])
    check("identify without a match callback: no match, no AUTH",
          found is None and bridge.commands.count("AUTH") == auths)
    bridge.auth_answers = []

    bridge.auth_answers = ["LOCKOUT 30000"]
    try:
        dev.verify_sync(enrolled)
        check("lockout is an error", False)
    except GLib.Error as e:
        check("lockout is an error", "Too many attempts" in e.message)

    # cancel: the bridge holds AUTH until CANCEL, then answers ERROR 5
    bridge.hold_auth = True
    cancellable = Gio.Cancellable()
    GLib.timeout_add(200, lambda: cancellable.cancel() and False)
    try:
        dev.verify_sync(enrolled, cancellable)
        check("cancel ends verify", False)
    except GLib.Error as e:
        check("cancel ends verify as cancelled",
              e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.CANCELLED))
    check("cancel sent CANCEL", "CANCEL" in bridge.commands)

    # a CANCEL the bridge never answers (it once swallowed the answer when a
    # match landed after the cancel): the driver still ends the action, so
    # fprintd can release the device, and the device works afterwards
    bridge.mute_cancel = True
    cancellable = Gio.Cancellable()
    GLib.timeout_add(200, lambda: cancellable.cancel() and False)
    try:
        dev.verify_sync(enrolled, cancellable)
        check("unanswered cancel ends verify", False)
    except GLib.Error as e:
        check("unanswered cancel ends verify as cancelled",
              e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.CANCELLED))
    bridge.mute_cancel = False
    bridge.hold_auth = False
    bridge.auth_answers = [f"MATCH {ENROLL_ID}"]
    check("verify works after an unanswered cancel", dev.verify_sync(enrolled)[0])

    # system sleep mid-verify (the lock screen's): the verify stays open, the
    # HAL's capture stops (CANCEL, its ERROR 5 swallowed) and starts again on
    # resume (AUTH); the client sees only the match
    ctx = GLib.MainContext.default()

    def spin(cond, ms=3000):
        end = time.monotonic() + ms / 1000
        while not cond() and time.monotonic() < end:
            ctx.iteration(False)
            time.sleep(0.005)

    def start_verify(cancellable=None):
        done = []
        dev.verify(enrolled, cancellable=cancellable, match_cb=None, match_data=None,
                   callback=lambda d, res, *_: done.append(res), user_data=None)
        return done

    bridge.hold_auth = True
    auths, cancels = bridge.commands.count("AUTH"), bridge.commands.count("CANCEL")
    done = start_verify()
    spin(lambda: bridge.commands.count("AUTH") == auths + 1)
    dev.suspend_sync()
    spin(lambda: False, 200)
    check("suspend mid-verify stops the capture",
          bridge.commands.count("CANCEL") == cancels + 1)
    check("the verify stays open across sleep", not done)
    bridge.hold_auth = False
    bridge.auth_answers = [f"MATCH {ENROLL_ID}"]
    dev.resume_sync()
    spin(lambda: done)
    check("resume starts the capture again", bridge.commands.count("AUTH") == auths + 2)
    check("the verify matches after resume", done and dev.verify_finish(done[0])[0])

    # cancelled while asleep (the client gave up): ends at once, and the
    # device works after resume
    bridge.hold_auth = True
    cancellable = Gio.Cancellable()
    done = start_verify(cancellable)
    spin(lambda: bridge.commands.count("AUTH") == auths + 3)
    dev.suspend_sync()
    cancellable.cancel()
    spin(lambda: done, 1000)
    try:
        dev.verify_finish(done[0]) if done else None
        check("cancel while asleep ends verify as cancelled", False)
    except GLib.Error as e:
        check("cancel while asleep ends verify as cancelled",
              e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.CANCELLED))
    dev.resume_sync()
    bridge.hold_auth = False
    bridge.auth_answers = [f"MATCH {ENROLL_ID}"]
    check("verify works after a sleep", dev.verify_sync(enrolled)[0])

    # sleep mid-enrollment: held across the sleep, then failed on resume (it
    # can't pick up midway), so the client's Release comes after the sleep
    bridge.hold_enroll = True
    enrolls, auths = bridge.commands.count("ENROLL"), bridge.commands.count("AUTH")
    second = FPrint.Print.new(dev)
    second.set_finger(FPrint.Finger.LEFT_THUMB)
    second.set_username("tester")
    done = []
    dev.enroll(second, cancellable=None, progress_cb=None, progress_data=None,
               callback=lambda d, res, *_: done.append(res), user_data=None)
    spin(lambda: bridge.commands.count("ENROLL") == enrolls + 1)
    dev.suspend_sync()
    spin(lambda: False, 200)
    check("the enrollment stays open across sleep", not done)
    dev.resume_sync()
    spin(lambda: done)
    try:
        dev.enroll_finish(done[0]) if done else None
        check("resume fails the interrupted enrollment", False)
    except GLib.Error as e:
        check("resume fails the interrupted enrollment", "interrupted by sleep" in e.message)
    check("resume starts no capture for it", bridge.commands.count("AUTH") == auths)
    bridge.hold_enroll = False
    bridge.auth_answers = [f"MATCH {ENROLL_ID}"]
    check("verify works after an interrupted enrollment", dev.verify_sync(enrolled)[0])

    dev.delete_print_sync(enrolled)
    check("delete removes it", bridge.enrolled == [])
    try:
        dev.delete_print_sync(enrolled)
        check("delete of a missing print fails", False)
    except GLib.Error as e:
        check("delete of a missing print fails as not found",
              e.matches(FPrint.device_error_quark(), FPrint.DeviceError.DATA_NOT_FOUND))

    # the bridge goes away mid-verify
    bridge.hold_auth = True
    bridge.drop_next = True
    try:
        dev.verify_sync(enrolled)
        check("lost bridge fails the action", False)
    except GLib.Error as e:
        check("lost bridge fails the action", True)
        print(f"     ({e.message})")

    dev.close_sync()
    bridge.sock.close()
    print(f"{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
