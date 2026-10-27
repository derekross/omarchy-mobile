#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Rotate Hyprland's screen and touch input with the phone.

A client of iio-sensor-proxy's D-Bus API (net.hadess.SensorProxy, served on
cheetah by omamobile-sensor-proxy): it claims the accelerometer and, on every
AccelerometerOrientation change, sets the monitor's and the touchscreen's
transform through hyprctl, the way iio-hyprland does (normal 0, left-up 1,
bottom-up 2, right-up 3).

Rotation lock: while $XDG_STATE_HOME/omamobile/rotation-lock exists, the
accelerometer is released and the screen stays as it is; removing the file
applies the current orientation again (the quick-settings tile can toggle
it).

The lock screen stays portrait: while the shell is locked (omarchy-shell
lock isLocked) the screen is held at transform 0 and the phone's orientation
is remembered; it is applied when the shell unlocks. Locking in landscape
turns the screen back to portrait for the same reason. The shell's lock
state is polled once a second only while the screen is not in plain
portrait or an orientation is waiting.

  omamobile-autorotate [--monitor NAME] [--dry-run]
"""
import argparse
import json
import os
import signal
import subprocess
import sys

import gi
gi.require_version('Gio', '2.0')
gi.require_version('GLibUnix', '2.0')
from gi.repository import Gio, GLib, GLibUnix  # noqa: E402

NAME = 'net.hadess.SensorProxy'
PATH = '/net/hadess/SensorProxy'
TRANSFORMS = {'normal': 0, 'left-up': 1, 'bottom-up': 2, 'right-up': 3}


def log(msg):
    print(f'omamobile-autorotate: {msg}', file=sys.stderr, flush=True)


def lock_path():
    state = os.environ.get('XDG_STATE_HOME') or os.path.expanduser('~/.local/state')
    return os.path.join(state, 'omamobile', 'rotation-lock')


def hyprctl(*args):
    return subprocess.run(['hyprctl', *args], capture_output=True, text=True)


def shell_locked(dry_run=False):
    """True while Omarchy's lock screen is up (the test sets OMAMOBILE_TEST_LOCKED)."""
    if dry_run:
        return os.environ.get('OMAMOBILE_TEST_LOCKED') == '1'
    try:
        r = subprocess.run(['omarchy-shell', 'lock', 'isLocked'], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return r.stdout.strip() == 'true'


def monitor(name=None):
    """(name, scale) of the given monitor, or of the first one."""
    try:
        mons = json.loads(hyprctl('-j', 'monitors').stdout or '[]')
    except json.JSONDecodeError:
        mons = []
    for m in mons:
        if name is None or m.get('name') == name:
            return m.get('name'), m.get('scale', 1.0)
    return None, None


def apply(transform, name=None, dry_run=False):
    mon, scale = (name or 'DSI-1', 1.0) if dry_run else monitor(name)
    if mon is None:
        log('no monitor')
        return
    lua = (f'hl.monitor({{ output = "{mon}", mode = "preferred", position = "auto", '
           f'scale = {scale:g}, transform = {transform} }}); '
           f'hl.config({{ input = {{ touchdevice = {{ transform = {transform}, output = "{mon}" }} }} }})')
    if dry_run:
        log(f'would run: hyprctl eval {lua!r}')
        return
    r = hyprctl('eval', lua)
    if r.returncode != 0 or 'error' in (r.stdout + r.stderr).lower():
        # Older Hyprland: the keyword interface
        hyprctl('keyword', 'monitor', f'{mon},preferred,auto,{scale:g},transform,{transform}')
        hyprctl('keyword', 'input:touchdevice:transform', str(transform))
        hyprctl('keyword', 'input:touchdevice:output', mon)
    log(f'{mon}: transform {transform}')


class Rotator:
    def __init__(self, args):
        self.args = args
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION if args.session else Gio.BusType.SYSTEM, None)
        self.claimed = False
        self.current = None
        self.wanted = None      # the phone's orientation, applied once the shell unlocks
        self.lock_poll = 0      # GLib source id of the lock poll, 0 while idle
        self.bus.signal_subscribe(NAME, 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
                                  PATH, None, Gio.DBusSignalFlags.NONE, self._changed)
        Gio.bus_watch_name_on_connection(self.bus, NAME, Gio.BusNameWatcherFlags.NONE,
                                         self._appeared, self._vanished)
        lock = Gio.File.new_for_path(lock_path())
        self.lock_monitor = lock.monitor_file(Gio.FileMonitorFlags.NONE, None)
        self.lock_monitor.connect('changed', lambda *a: self._update_claim())

    def _call(self, method):
        try:
            self.bus.call_sync(NAME, PATH, NAME, method, None, None,
                               Gio.DBusCallFlags.NONE, 5000, None)
            return True
        except GLib.Error as e:
            log(f'{method}: {e.message}')
            return False

    def _prop(self, prop):
        try:
            v = self.bus.call_sync(NAME, PATH, 'org.freedesktop.DBus.Properties', 'Get',
                                   GLib.Variant('(ss)', (NAME, prop)), GLib.VariantType.new('(v)'),
                                   Gio.DBusCallFlags.NONE, 5000, None)
            return v.unpack()[0]
        except GLib.Error:
            return None

    def _appeared(self, conn, name, owner):
        if not self._prop('HasAccelerometer'):
            log('the sensor proxy has no accelerometer')
            return
        self._update_claim()

    def _vanished(self, conn, name):
        self.claimed = False

    def _update_claim(self):
        locked = os.path.exists(lock_path())
        if locked and self.claimed:
            self.claimed = not self._call('ReleaseAccelerometer')
            log('rotation locked')
        elif not locked and not self.claimed:
            self.claimed = self._call('ClaimAccelerometer')
            if self.claimed:
                self._rotate(self._prop('AccelerometerOrientation'))

    def _changed(self, conn, sender, path, iface, signal_name, params):
        _iface, changed, _ = params.unpack()
        if 'AccelerometerOrientation' in changed and self.claimed:
            self._rotate(changed['AccelerometerOrientation'])

    def _rotate(self, orientation):
        t = TRANSFORMS.get(orientation)
        if t is None:
            return
        self.wanted = t
        if shell_locked(self.args.dry_run):
            if self.current != 0:
                log('portrait while locked')
                self._apply(0)
            self._poll_lock()
            return
        self._apply(t)
        if t != 0:
            self._poll_lock()

    def _apply(self, t):
        if t == self.current:
            return
        self.current = t
        apply(t, self.args.monitor, self.args.dry_run)

    def _poll_lock(self):
        if not self.lock_poll:
            self.lock_poll = GLib.timeout_add_seconds(1, self._lock_tick)

    def _lock_tick(self):
        locked = shell_locked(self.args.dry_run)
        if locked and self.current != 0:
            log('portrait while locked')
            self._apply(0)
        elif not locked and self.wanted is not None and self.wanted != self.current:
            self._apply(self.wanted)
        if locked or (self.wanted or 0) != 0:
            return True
        self.lock_poll = 0
        return False


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--monitor', help='the output to rotate (default: the first one)')
    ap.add_argument('--dry-run', action='store_true', help='log the hyprctl calls instead of making them')
    ap.add_argument('--session', action='store_true', help='use the session bus (testing)')
    a = ap.parse_args(argv)
    Rotator(a)
    loop = GLib.MainLoop()
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, loop.quit)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, loop.quit)
    loop.run()
    return 0


if __name__ == '__main__':
    sys.exit(main())
