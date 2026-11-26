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
import re
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


def rate_path():
    # a fixed path, the same one Settings writes: a user service may not see a session-only XDG_CONFIG_HOME
    return os.path.join(os.path.expanduser('~'), '.config', 'omamobile', 'refresh-rate')


# A device package's default rate (husky ships 60), used while the user has chosen none; the same file
# Settings' display.sh reads
# (OMAMOBILE_RATE_DEFAULT_FILE redirects it, for the tests only)
DEFAULT_RATE_PATH = os.environ.get('OMAMOBILE_RATE_DEFAULT_FILE', '/usr/share/omamobile/refresh-rate-default')


def saved_mode(m):
    """The exact mode token (without "Hz") for the rate the user chose in Settings, else the device
    default rate, else None.

    Only a rate the monitor lists is used, in the panel's own orientation or the turned one (hyprctl may
    report the size either way); a missing, odd or unlisted rate falls through to the next one, so the
    screen never ends on a mode it lacks."""
    for path in (rate_path(), DEFAULT_RATE_PATH):
        mode = _listed_mode(m, path)
        if mode:
            return mode
    return None


def current_mode(m):
    """The monitor's current mode as the exact listed token, so a turn keeps the rate it has; "preferred" only
    if hyprctl gave no usable current rate (then the mode is left to Hyprland as before)."""
    try:
        return _token(m, int(round(float(m['refreshRate'])))) or 'preferred'
    except (KeyError, ValueError, TypeError):
        return 'preferred'


def _read_rate(path):
    """A bare number of 1 to 3 digits, no leading zero, with at most one trailing newline, else None; the same
    rule as read_rate in omamobile-settings' display.sh."""
    # bytes, not text: text mode would turn "120\r\n" into "120\n" and fail on bytes that are not UTF-8
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except OSError:
        return None
    if data.endswith(b'\n'):
        data = data[:-1]
    return int(data) if re.fullmatch(rb'[1-9][0-9]{0,2}', data) else None


def _token(m, want):
    """The exact mode token for the rate WANT at the monitor's size (as reported, then turned), else None."""
    try:
        w, h = int(m['width']), int(m['height'])
        for wanted in (f'{w}x{h}', f'{h}x{w}'):  # the size as reported first, then the swapped one
            for mode in m.get('availableModes', []):
                size, _, hz = mode.partition('@')
                hz = hz.removesuffix('Hz')
                try:
                    ok = size == wanted and round(float(hz)) == want
                except ValueError:
                    continue  # a mode this parser does not know is skipped
                if ok and re.fullmatch(r'\d{1,5}x\d{1,5}@\d{1,4}(\.\d{1,6})?', size + '@' + hz):
                    return size + '@' + hz
    except (KeyError, ValueError, TypeError):
        pass
    return None


def _listed_mode(m, path):
    want = _read_rate(path)
    return None if want is None else _token(m, want)


def monitor(name=None):
    """(name, scale, mode) of the given monitor, or of the first one."""
    try:
        mons = json.loads(hyprctl('-j', 'monitors').stdout or '[]')
    except json.JSONDecodeError:
        mons = []
    for m in mons:
        if name is None or m.get('name') == name:
            return m.get('name'), m.get('scale', 1.0), saved_mode(m) or current_mode(m)
    return None, None, 'preferred'


def apply(transform, name=None, dry_run=False):
    mon, scale, mode = (name or 'DSI-1', 1.0, saved_mode({}) or 'preferred') if dry_run else monitor(name)
    if mon is None:
        log('no monitor')
        return
    lua = (f'hl.monitor({{ output = "{mon}", mode = "{mode}", position = "auto", '
           f'scale = {scale:g}, transform = {transform} }}); '
           f'hl.config({{ input = {{ touchdevice = {{ transform = {transform}, output = "{mon}" }} }} }})')
    if dry_run:
        log(f'would run: hyprctl eval {lua!r}')
        return
    r = hyprctl('eval', lua)
    if r.returncode != 0 or 'error' in (r.stdout + r.stderr).lower():
        # Older Hyprland: the keyword interface
        hyprctl('keyword', 'monitor', f'{mon},{mode},auto,{scale:g},transform,{transform}')
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
