#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Automatic screen brightness from the ambient light sensor.

A client of iio-sensor-proxy's D-Bus API (net.hadess.SensorProxy, served on
cheetah by omamobile-sensor-proxy from the AoC). While the screen is on it
claims the light sensor and sets the panel's backlight from the lux it reads.
While the screen is off (the backlight's bl_power is not 0, or the DSI
connector's DPMS is off) it releases the claim, so the sensor stops.

The curve (Curve). The target luminance in nits is interpolated in log-log
space between (lux, nits) points (CURVE), so equal ratios of light give
equal steps of perceived brightness. It becomes a backlight level through
the panel's range (Panel; on cheetah's panel, levels 4-2047 run from about
2 to 600 nits, DISPLAY-PLAN 2.4).

Smoothing and hysteresis (AmbientFilter). The lux (about a reading a
second, more while the light changes) goes through a median of three,
which drops a reading that stands alone, and an average in the log domain.
The brightness follows only once the average and the median have both left
a band around the level it last followed: 26 % brighter for 1.5 s, or 29 %
darker for 10 s. The AoC's lux wanders a few percent from second to second
in a steady room, which never moves the screen. The sensor is under the
panel, where a hand in use shades it for several seconds at a time, so
darker light has to last before the screen follows it.

Ramps (Ramp). The backlight moves in steps of perceived brightness: quickly
when it brightens (half the range in a second), slowly when it dims (a
sixteenth of the range a second), so dimming is hard to notice. The first
reading after a wake applies quickly in either direction.

A manual change is a preference, not a fight. A level this daemon didn't
write (the quick-settings slider, brightnessctl) pauses it. Once the level
has held for SETTLE_S, it becomes the user's point on the curve at the
current light, as Android's adjustment does it: the curve is bent by a
gamma (1/3 to 3) on the panel's perceptual range so it passes through that
point, and where the gamma's range isn't enough, the curve is blended into
the point over a decade of lux on each side. The curve stays monotonic, the
slider's choice holds at this light, a brighter or dimmer preference
carries over to other light, and the panel's ends (its minimum in the dark,
its maximum in daylight) stay where they are. Changes to or from 0, changes
while the panel is off and changes in the first second after a wake come
from the power key, the lock or the wake, not from the user, and teach
nothing. A write that fails teaches nothing either: the level stays what
the panel has, and the daemon tries again later. The point is kept in $XDG_STATE_HOME/omamobile/autobrightness.json;
--reset forgets it.

The panel's range comes from the board (PANELS); the curve and the range
can be set in ~/.config/omamobile/autobrightness.json:
  {"curve": [[1, 3], [10, 25], [100, 110], [1000, 300], [10000, 600]],
   "panel": {"min_level": 4, "max_level": 2047, "min_nits": 2, "max_nits": 600}}

  omamobile-autobrightness [--dry-run] [--verbose] [--backlight PATH]
  omamobile-autobrightness --print-curve | --status | --reset
"""
import argparse
import glob
import json
import math
import os
import signal
import sys
import time

NAME = 'net.hadess.SensorProxy'
PATH = '/net/hadess/SensorProxy'

LUX_FLOOR = 1.0          # lux below this reads as this (the curve is flat there)
# (lux, nits): a dark room, a dim room, a living room, an office or an
# overcast window, daylight. Above the last point: the panel's maximum.
CURVE = ((1.0, 3.0), (10.0, 25.0), (100.0, 110.0), (1000.0, 300.0), (10000.0, 600.0))
MAX_GAMMA = 3.0          # Android's limit on how far a user point bends the curve
BLEND_DECADES = 1.0      # where the gamma can't reach the user's point
SETTLE_S = 2.0           # a manual level has to hold this long to count
WAKE_GRACE_S = 1.0       # after the screen comes on, changes are the wake's
RETRY_S = 5.0            # after a write that failed
STEP_S = 0.05            # ramp step (20 Hz while a ramp runs)
SCREEN_POLL_S = 1        # bl_power and DPMS: nothing signals a change
NOT_HERE = 78            # exit status with no backlight: systemd doesn't restart it
# Each board's panel: levels against luminance, the lowest level that lights
# it and the highest the curve uses. cheetah: DISPLAY-PLAN 2.4 (4-2047 for
# about 2-600 nits; 2900-4095 is HBM, which the curve leaves alone if a
# kernel ever offers it). Another board takes the same nits over its whole
# range from level 1 until it has an entry here or a "panel" in the
# configuration file.
PANELS = {
    'google,gs201-cheetah': {'min_level': 4, 'max_level': 2047, 'min_nits': 2.0, 'max_nits': 600.0},
}
CLAIM_CHECK_S = 2.5      # no reading yet after a claim: read the property


def log(msg):
    print(f'omamobile-autobrightness: {msg}', file=sys.stderr, flush=True)


def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


class Panel:
    """Backlight levels against luminance, linear from (min_level, min_nits)
    to (max_level, max_nits). Level 0 turns the panel's pixels off, so the
    lowest level used is min_level. Perceived brightness (u, 0 at 1 nit, 1 at
    max_nits) is the log of luminance on that scale."""

    def __init__(self, max_level=2047, min_level=4, min_nits=2.0, max_nits=600.0):
        if not (0 < min_level < max_level and 1.0 <= min_nits < max_nits):
            raise ValueError('panel range')
        self.max_level, self.min_level = int(max_level), int(min_level)
        self.min_nits, self.max_nits = float(min_nits), float(max_nits)

    def level(self, nits):
        nits = clamp(nits, self.min_nits, self.max_nits)
        span = (self.max_level - self.min_level) / (self.max_nits - self.min_nits)
        return int(round(self.min_level + (nits - self.min_nits) * span))

    def nits(self, level):
        level = clamp(level, self.min_level, self.max_level)
        span = (self.max_nits - self.min_nits) / (self.max_level - self.min_level)
        return self.min_nits + (level - self.min_level) * span

    def u(self, nits):
        return math.log(max(nits, 1.0)) / math.log(self.max_nits)

    def from_u(self, u):
        return self.max_nits ** u

    def level_u(self, level):
        return self.u(self.nits(level))


def _log_lux(lux):
    return math.log10(max(float(lux), LUX_FLOOR))


def interp_loglog(points, lux):
    """nits at lux, linear in (log lux, log nits) between points, flat outside."""
    x = _log_lux(lux)
    pts = [(_log_lux(lx), math.log10(n)) for lx, n in points]
    if x <= pts[0][0]:
        return 10 ** pts[0][1]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x <= x1:
            return 10 ** (y0 + (y1 - y0) * (x - x0) / (x1 - x0))
    return 10 ** pts[-1][1]


def check_points(points):
    pts = [(float(lx), float(n)) for lx, n in points]
    if len(pts) < 2:
        raise ValueError('the curve needs two points')
    for (l0, n0), (l1, n1) in zip(pts, pts[1:]):
        if not (LUX_FLOOR <= l0 < l1 and 0 < n0 <= n1):
            raise ValueError('curve points rise in lux (from 1) and never fall in nits')
    return tuple(pts)


class Curve:
    """The lux to brightness curve: the base points, bent by gamma, through
    the user's point (lux, nits) if there is one."""

    def __init__(self, panel, points=CURVE, gamma=1.0, user=None):
        self.panel = panel
        self.points = check_points(points)
        self.gamma = float(gamma)
        self.user = None
        if user is not None:
            lux, nits = user
            self.user = (max(float(lux), LUX_FLOOR), clamp(float(nits), panel.min_nits, panel.max_nits))

    def base(self, lux):
        return clamp(interp_loglog(self.points, lux), self.panel.min_nits, self.panel.max_nits)

    # The gamma works on the panel's own range, perceptually: v is 0 at the
    # panel's minimum and 1 at its maximum, on a log scale, so both ends
    # stay where they are and the bend is gentlest at the dark end.
    def _v(self, nits):
        p = self.panel
        return math.log(clamp(nits, p.min_nits, p.max_nits) / p.min_nits) / math.log(p.max_nits / p.min_nits)

    def _from_v(self, v):
        p = self.panel
        return p.min_nits * (p.max_nits / p.min_nits) ** v

    def shaped(self, lux):
        n = self.base(lux)
        if self.gamma == 1.0:
            return n
        return self._from_v(self._v(n) ** self.gamma)

    def nits(self, lux):
        g = self.shaped(lux)
        if self.user is not None:
            l0, n0 = self.user
            g0 = self.shaped(l0)
            d = _log_lux(lux) - _log_lux(l0)
            if g0 > n0 * 1.0001:
                # Too bright at the point even bent: hold the darker side at
                # the point, and rise from it to the curve over a decade.
                if d <= 0:
                    g = min(g, n0)
                else:
                    s = min(1.0, d / BLEND_DECADES)
                    g = n0 * (max(g, n0) / n0) ** s
            elif g0 < n0 / 1.0001:
                if d >= 0:
                    g = max(g, n0)
                else:
                    s = min(1.0, -d / BLEND_DECADES)
                    g = n0 * (min(g, n0) / n0) ** s
        return clamp(g, self.panel.min_nits, self.panel.max_nits)

    def level(self, lux):
        return self.panel.level(self.nits(lux))

    def adjusted(self, lux, nits):
        """The base curve through the user's point (lux, nits)."""
        vb, vt = self._v(self.base(lux)), self._v(nits)
        gamma = 1.0
        if 1e-9 < vb < 1.0 - 1e-9:
            # At either end of the panel's range no gamma moves the curve;
            # the blend in nits() reaches the point there.
            gamma = MAX_GAMMA if vt <= 1e-9 else math.log(vt) / math.log(vb)
            gamma = clamp(gamma, 1.0 / MAX_GAMMA, MAX_GAMMA)
        return Curve(self.panel, self.points, gamma, (lux, nits))

    def plain(self):
        return Curve(self.panel, self.points)

    def state(self):
        if self.user is None:
            return {'version': 1}
        return {'version': 1, 'gamma': round(self.gamma, 6),
                'lux': round(self.user[0], 3), 'nits': round(self.user[1], 3)}

    def with_state(self, state):
        """This curve's points with a saved state's user point (or none). A
        file edited by hand can say anything: the gamma is held to its range."""
        try:
            if state and 'lux' in state and 'nits' in state:
                gamma, lux, nits = (float(state.get('gamma', 1.0)), float(state['lux']),
                                    float(state['nits']))
                if all(map(math.isfinite, (gamma, lux, nits))):
                    return Curve(self.panel, self.points, clamp(gamma, 1.0 / MAX_GAMMA, MAX_GAMMA),
                                 (lux, nits))
        except (TypeError, ValueError):
            pass
        return self.plain()


class AmbientFilter:
    """Lux in the log domain: the median of the last three readings (a
    reading that stands alone is dropped), then an exponential average,
    quicker to rise than to fall, with hysteresis and a debounce: the
    accepted level moves only once the average has stayed beyond the band
    for the debounce time."""

    def __init__(self, brighten=0.1, darken=0.15, tau_up=1.0, tau_down=3.0,
                 debounce_up=1.5, debounce_down=10.0, tick=1.0):
        self.brighten, self.darken = brighten, darken
        self.tau_up, self.tau_down = tau_up, tau_down
        self.debounce_up, self.debounce_down = debounce_up, debounce_down
        self.tick = tick
        self.reset()

    def reset(self):
        self.accepted = self.smooth = self.x = self.t = None
        self.window = []
        self.pending = None
        self.since = None

    @property
    def lux(self):
        return None if self.accepted is None else 10 ** self.accepted

    def update(self, t, lux=None):
        """A reading at time t. With lux None, the last reading again: the
        proxy signals only changes, so silence is the same value. True when
        the accepted level moved."""
        if lux is not None:
            raw = _log_lux(lux)
        elif self.window:
            raw = self.window[-1]
        else:
            return False
        self.window = (self.window + [raw])[-3:]
        self.x = sorted(self.window)[len(self.window) // 2]
        if self.accepted is None:
            self.accepted = self.smooth = self.x
            self.t = t
            return True
        dt = max(0.0, t - self.t)
        self.t = t
        tau = self.tau_up if self.x > self.smooth else self.tau_down
        self.smooth += (self.x - self.smooth) * (1.0 - math.exp(-dt / tau))
        # Both the average and the reading of the moment (the median) have
        # to be beyond the band: the average lags, and a burst of light
        # that has gone lifts it for seconds after the room is back.
        hi, lo = self.accepted + self.brighten, self.accepted - self.darken
        if self.smooth > hi and self.x > hi:
            direction, wait = 1, self.debounce_up
        elif self.smooth < lo and self.x < lo:
            direction, wait = -1, self.debounce_down
        else:
            self.pending = None
            return False
        if self.pending != direction:
            self.pending, self.since = direction, t
        if t - self.since >= wait - 1e-6:
            # The average decided; the level is the reading now (the average
            # lags, and would leave the screen a band away from the room).
            self.accepted = self.smooth = self.x
            self.pending = None
            return True
        return False

    def next_due(self):
        """When the filter next needs time to pass (None: settled)."""
        if self.accepted is None:
            return None
        # A reading a second keeps moving t, so these come due only once the
        # readings stop (an unchanged value isn't signalled).
        quiet = self.t + 1.5 * self.tick
        if self.pending is not None:
            wait = self.debounce_up if self.pending > 0 else self.debounce_down
            return min(self.since + wait, quiet)
        if abs(self.x - self.smooth) > 0.005 or len(set(self.window)) > 1:
            return quiet
        return None


class Ramp:
    """Moves a level towards a target at a rate of perceived brightness
    (u per second): up quickly, down slowly, both quickly after a wake."""

    def __init__(self, panel, up=0.5, down=1.0 / 16, fast=2.0):
        self.panel = panel
        self.up, self.down, self.fast = up, down, fast

    def advance(self, u, target, dt, fast=False):
        """The new position on the u scale after dt seconds."""
        goal = self.panel.level_u(target)
        if goal > u:
            return min(goal, u + (self.fast if fast else self.up) * dt)
        return max(goal, u - (self.fast if fast else self.down) * dt)


class Controller:
    """The daemon's logic without GLib or D-Bus: the driver calls screen(),
    lux() and backlight_changed() as things happen and step() when it asks
    for one; step() returns the seconds until it wants the next call."""

    def __init__(self, curve, backlight, sensor, store=None, filt=None, ramp=None,
                 settle=SETTLE_S, grace=WAKE_GRACE_S, logger=log, trace=None):
        self.curve = curve
        self.panel = curve.panel
        self.backlight = backlight
        self.sensor = sensor
        self.store = store
        self.filter = filt or AmbientFilter()
        self.ramp = ramp or Ramp(self.panel)
        self.settle, self.grace = settle, grace
        self.log = logger
        self.trace = trace
        self.screen_on = False
        self.level = None        # the level we wrote last, or took as a starting point
        self.target = None
        self.ramp_u = None       # the ramp's position (u), None while no ramp runs
        self.ramp_t = None
        self.ramp_fast = False
        self.settle_at = None    # when a manual change is learned
        self.grace_until = 0.0
        self.fast_next = True
        self.maybe = None        # a level whose write failed, and may still land
        self.retry_at = None     # when to try again after a failed write

    # ------------------------------------------------------------ events
    def screen(self, now, on):
        if on == self.screen_on:
            return
        self.screen_on = on
        if self.trace:
            self.trace(f'screen {"on" if on else "off"} at level {self.backlight.read()}')
        if on:
            self.level = self.backlight.read()
            self.grace_until = now + self.grace
            self.fast_next = True
            self.sensor.claim()
        else:
            self.sensor.release()
            self.filter.reset()
            self._stop_ramp()
            self.settle_at = self.retry_at = self.maybe = None

    def lux(self, now, value):
        if not self.screen_on:
            return
        moved = self.filter.update(now, value)
        if self.trace:
            f = self.filter
            self.trace(f'{value:.1f} lux: median {10 ** f.x:.1f}, average {10 ** f.smooth:.1f}, '
                       f'following {f.lux:.1f}{" (moved)" if moved else ""}, level {self.level}')
        if moved:
            self._retarget(now)

    def backlight_changed(self, now, value=None):
        value = self.backlight.read() if value is None else value
        if value is None or value == self.level:
            return
        if value == self.maybe:
            # A write that reported a failure (a timeout) and landed after all.
            self.level, self.maybe = value, None
            return
        prev, self.level = self.level, value
        self._stop_ramp()
        self.retry_at = self.maybe = None
        if self.trace and prev is not None:
            self.trace(f'backlight {prev} -> {value}, not ours')
        if not self.screen_on or value <= 0 or not prev or now < self.grace_until:
            # The power key, the lock or a wake: a new starting point, never
            # a preference. A lit panel follows the curve again from here.
            self.settle_at = None
            if self.screen_on and value > 0:
                self._retarget(now, fast=True)
            return
        self.settle_at = now + self.settle

    def set_curve(self, now, curve):
        self.curve = curve
        self._retarget(now)

    # ------------------------------------------------------------ time
    def step(self, now):
        if not self.screen_on:
            return None
        waits = []
        if self.settle_at is not None:
            if now >= self.settle_at - 1e-6:
                self.settle_at = None
                self._learn(now)
            else:
                waits.append(self.settle_at - now)
        due = self.filter.next_due()
        if due is not None and now >= due - 1e-6:
            if self.filter.update(now):
                self._retarget(now)
            due = self.filter.next_due()
        if due is not None:
            waits.append(max(due - now, 0.01))
        if self.retry_at is not None:
            if now >= self.retry_at - 1e-6:
                self.retry_at = None
                self._retarget(now)
            else:
                waits.append(self.retry_at - now)
        if self.ramp_u is not None and self.settle_at is None:
            self._ramp_step(now)
            if self.ramp_u is not None:
                waits.append(STEP_S)
        return min(waits) if waits else None

    # ------------------------------------------------------------ internals
    def _stop_ramp(self):
        self.ramp_u = None

    def _retarget(self, now, fast=False):
        if (not self.screen_on or self.settle_at is not None or self.filter.lux is None
                or not self.level):
            return
        target = self.curve.level(self.filter.lux)
        fast = fast or self.fast_next
        self.fast_next = False
        if target != self.target:
            self.log(f'{self.filter.lux:.0f} lux: level {target} ({self.curve.nits(self.filter.lux):.0f} nits)')
        self.target = target
        if target == self.level:
            self._stop_ramp()
            return
        if self.ramp_u is None:
            self.ramp_u = self.panel.level_u(self.level)
            self.ramp_t = now
        self.ramp_fast = fast

    def _ramp_step(self, now):
        dt = max(0.0, now - self.ramp_t)
        self.ramp_t = now
        self.ramp_u = self.ramp.advance(self.ramp_u, self.target, dt, self.ramp_fast)
        done = self.ramp_u == self.panel.level_u(self.target)
        nxt = self.target if done else self.panel.level(self.panel.from_u(self.ramp_u))
        # Read before writing: the slider may have moved it since our last
        # write, and that is the user's level now.
        cur = self.backlight.read()
        if cur != self.level:
            self.backlight_changed(now, cur)
            return
        if nxt != self.level:
            if not self.backlight.write(nxt):
                # Not written (logind refused it, or timed out and may still
                # write it): the panel keeps its level, which is no one's
                # preference. Try again in a while.
                self.maybe = nxt
                self.retry_at = now + RETRY_S
                self._stop_ramp()
                return
            self.level, self.maybe = nxt, None
        if done:
            self._stop_ramp()

    def _learn(self, now):
        value = self.backlight.read()
        if not self.screen_on or not value or value <= 0:
            return
        self.level = value
        lux = self.filter.lux
        if lux is None:
            return
        nits = self.panel.nits(value)
        self.curve = self.curve.adjusted(lux, nits)
        self.target = value
        self.log(f'your level {value} ({nits:.0f} nits) at {lux:.0f} lux: '
                 f'gamma {self.curve.gamma:.2f}, now level {self.curve.level(lux)} here')
        if self.store is not None:
            self.store.save(self.curve.state())


# ---------------------------------------------------------------- the phone

def read_text(path, default=''):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def find_backlight(name=None):
    if name and os.path.isdir(name):
        return name
    base = '/sys/class/backlight'
    names = sorted(os.listdir(base)) if os.path.isdir(base) else []
    if name:
        names = [n for n in names if n == name]
    return os.path.join(base, names[0]) if names else None


def find_dpms():
    paths = sorted(glob.glob('/sys/class/drm/*-DSI-*/dpms'))
    return paths[0] if paths else None


def screen_on(backlight_dir, dpms_path):
    """Off when bl_power says so (Omarchy's display off writes 4 on this
    phone), or when the DSI connector's DPMS isn't On."""
    if read_text(os.path.join(backlight_dir, 'bl_power'), '0') not in ('', '0'):
        return False
    if dpms_path and read_text(dpms_path, 'On') != 'On':
        return False
    return True


class Backlight:
    """The panel's backlight: read from sysfs, written through logind's
    SetBrightness (the user may not write brightness itself) unless the
    file is writable."""

    def __init__(self, path, bus=None):
        self.path = path
        self.name = os.path.basename(path)
        self.bus = bus
        self.direct = os.access(os.path.join(path, 'brightness'), os.W_OK)
        self.error = None

    def max_level(self):
        return int(read_text(os.path.join(self.path, 'max_brightness'), '0') or 0)

    def read(self):
        try:
            return int(read_text(os.path.join(self.path, 'brightness'), ''))
        except ValueError:
            return None

    def _failed(self, level, why):
        if why != self.error:
            log(f'setting {level}: {why}')
        self.error = why
        return False

    def write(self, level):
        """True once the level is written."""
        if self.direct:
            try:
                with open(os.path.join(self.path, 'brightness'), 'w') as f:
                    f.write(f'{int(level)}\n')
            except OSError as e:
                return self._failed(level, e.strerror or str(e))
            self.error = None
            return True
        from gi.repository import Gio, GLib  # noqa: PLC0415
        # session/auto is the caller's session or, for a user service outside
        # one, the user's display session. The reply comes once it's written.
        try:
            self.bus.call_sync('org.freedesktop.login1', '/org/freedesktop/login1/session/auto',
                               'org.freedesktop.login1.Session', 'SetBrightness',
                               GLib.Variant('(ssu)', ('backlight', self.name, int(level))),
                               None, Gio.DBusCallFlags.NONE, 2000, None)
        except GLib.Error as e:
            return self._failed(level, f'SetBrightness: {e.message}')
        self.error = None
        return True


class DryRunBacklight(Backlight):
    """Writes nothing: keeps the level it would have set, and takes a change
    of the real backlight as the user's."""

    def __init__(self, path, bus=None):
        super().__init__(path, bus)
        self.real = super().read()
        self.value = self.real

    def read(self):
        real = super().read()
        if real != self.real:
            self.real = self.value = real
        return self.value

    def write(self, level):
        log(f'would set {level}')
        self.value = level
        return True


class Store:
    def __init__(self, path):
        self.path = path

    def load(self):
        try:
            with open(self.path) as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def save(self, state):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        tmp = f'{self.path}.tmp'
        with open(tmp, 'w') as f:
            json.dump(state, f)
            f.write('\n')
        os.replace(tmp, self.path)

    def reset(self):
        try:
            os.unlink(self.path)
        except FileNotFoundError:
            pass


def state_path():
    state = os.environ.get('XDG_STATE_HOME') or os.path.expanduser('~/.local/state')
    return os.path.join(state, 'omamobile', 'autobrightness.json')


def config_path():
    config = os.environ.get('XDG_CONFIG_HOME') or os.path.expanduser('~/.config')
    return os.path.join(config, 'omamobile', 'autobrightness.json')


def find_board():
    """The board's first compatible string (google,gs201-cheetah)."""
    return read_text('/proc/device-tree/compatible').split('\0')[0]


def load_curve(max_level, path=None, board=''):
    """The curve from the board's panel (PANELS), the defaults and the user's
    configuration file. max_level is the backlight's max_brightness."""
    cfg = {}
    path = path or config_path()
    if os.path.exists(path):
        try:
            with open(path) as f:
                cfg = json.load(f)
            if not isinstance(cfg, dict):
                raise ValueError('not an object')
        except (OSError, ValueError) as e:
            log(f'{path}: {e}; using the defaults')
            cfg = {}
    pan = cfg.get('panel') if isinstance(cfg.get('panel'), dict) else {}
    known = PANELS.get(board)
    if not known and not pan:
        log(f'no panel range for {board or "this board"}: 2-600 nits over levels 1-{max_level}; '
            f'set "panel" in {path}')
    base = dict(known or {'min_level': 1, 'max_level': max_level, 'min_nits': 2.0, 'max_nits': 600.0})
    base['max_level'] = min(base['max_level'], max_level) if max_level else base['max_level']

    def make(p):
        return Panel(max_level=p['max_level'], min_level=p['min_level'],
                     min_nits=p['min_nits'], max_nits=p['max_nits'])
    try:
        panel = make(dict(base, **{k: pan[k] for k in ('min_level', 'max_level', 'min_nits', 'max_nits')
                                   if k in pan}))
    except (TypeError, ValueError) as e:
        log(f'{path}: panel: {e}; using the defaults')
        panel = make(base)
    try:
        return Curve(panel, cfg.get('curve', CURVE))
    except (TypeError, ValueError) as e:
        log(f'{path}: curve: {e}; using the defaults')
        return Curve(panel)


# ---------------------------------------------------------------- the daemon

class Sensor:
    """The light claim on the proxy, kept while the screen is on."""

    def __init__(self, bus):
        self.bus = bus
        self.present = False
        self.wanted = False
        self.claimed = False

    def _call(self, method):
        from gi.repository import Gio, GLib  # noqa: PLC0415
        try:
            self.bus.call_sync(NAME, PATH, NAME, method, None, None, Gio.DBusCallFlags.NONE, 5000, None)
            return True
        except GLib.Error as e:
            log(f'{method}: {e.message}')
            return False

    def prop(self, prop):
        from gi.repository import Gio, GLib  # noqa: PLC0415
        try:
            v = self.bus.call_sync(NAME, PATH, 'org.freedesktop.DBus.Properties', 'Get',
                                   GLib.Variant('(ss)', (NAME, prop)), GLib.VariantType.new('(v)'),
                                   Gio.DBusCallFlags.NONE, 5000, None)
            return v.unpack()[0]
        except GLib.Error:
            return None

    def claim(self):
        self.wanted = True
        self._sync()

    def release(self):
        self.wanted = False
        self._sync()

    def appeared(self):
        self.present = bool(self.prop('HasAmbientLight'))
        if not self.present:
            log('the sensor proxy has no light sensor')
        self._sync()

    def vanished(self):
        self.present = self.claimed = False

    def _sync(self):
        if self.wanted and self.present and not self.claimed:
            self.claimed = self._call('ClaimLight')
            if self.claimed:
                log('claimed the light sensor')
        elif not self.wanted and self.claimed:
            self.claimed = False
            self._call('ReleaseLight')
            log('released the light sensor')


class Daemon:
    def __init__(self, args):
        from gi.repository import Gio, GLib  # noqa: PLC0415
        self.GLib = GLib
        self.args = args
        path = find_backlight(args.backlight)
        if path is None:
            log('no backlight')
            raise SystemExit(NOT_HERE)
        self.bl_path = path
        self.dpms = find_dpms() if args.dpms is None else (args.dpms or None)
        # The system bus for the proxy and for logind; a test on the session
        # bus with a writable backlight needs neither.
        direct = os.access(os.path.join(path, 'brightness'), os.W_OK)
        need_system = not args.session or not (direct or args.dry_run)
        self.system = Gio.bus_get_sync(Gio.BusType.SYSTEM, None) if need_system else None
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None) if args.session else self.system
        backlight = (DryRunBacklight if args.dry_run else Backlight)(path, self.system)
        self.store = Store(args.state or state_path())
        curve = load_curve(backlight.max_level(), args.config, find_board())
        curve = curve.with_state(self.store.load())
        self.sensor = Sensor(self.bus)
        self.ctl = Controller(curve, backlight, self.sensor, self.store,
                              trace=log if args.verbose else None)
        self.timer = 0
        self.claim_check = 0
        log(f'{path}: levels {curve.panel.min_level}-{curve.panel.max_level}'
            + (f', your point {curve.user[1]:.0f} nits at {curve.user[0]:.0f} lux' if curve.user else '')
            + (' (dry run)' if args.dry_run else ''))

        self.bus.signal_subscribe(NAME, 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
                                  PATH, None, Gio.DBusSignalFlags.NONE, self._changed)
        Gio.bus_watch_name_on_connection(self.bus, NAME, Gio.BusNameWatcherFlags.NONE,
                                         self._appeared, self._vanished)
        # Every write of the brightness (ours, logind's for the slider)
        # notifies actual_brightness (sysfs_notify): no polling for it.
        try:
            self.notify_fd = os.open(os.path.join(path, 'actual_brightness'), os.O_RDONLY)
            os.read(self.notify_fd, 64)
            GLib.io_add_watch(self.notify_fd, GLib.PRIORITY_DEFAULT, GLib.IO_PRI | GLib.IO_ERR, self._notified)
        except OSError:
            self.notify_fd = None
        os.makedirs(os.path.dirname(self.store.path), exist_ok=True)
        self.state_monitor = Gio.File.new_for_path(self.store.path).monitor_file(Gio.FileMonitorFlags.NONE, None)
        self.state_monitor.connect('changed', self._state_changed)
        # A whole-second timer, which GLib wakes together with the others.
        GLib.timeout_add_seconds(SCREEN_POLL_S, self._poll)
        self._poll()

    def now(self):
        return time.monotonic()

    def _reschedule(self):
        if self.timer:
            self.GLib.source_remove(self.timer)
            self.timer = 0
        wait = self.ctl.step(self.now())
        if wait is not None:
            self.timer = self.GLib.timeout_add(max(1, int(wait * 1000)), self._timer)

    def _timer(self):
        self.timer = 0
        self._reschedule()
        return False

    def _poll(self):
        was = self.ctl.screen_on
        self.ctl.screen(self.now(), screen_on(self.bl_path, self.dpms))
        if self.ctl.screen_on and not was:
            self._watch_claim()
        self.ctl.backlight_changed(self.now())
        self._reschedule()
        return True

    def _watch_claim(self):
        # The proxy signals a change only: in a dark room the first reading
        # after a claim can equal the last one it had, and never arrive.
        if self.claim_check:
            self.GLib.source_remove(self.claim_check)
        self.claim_check = self.GLib.timeout_add(int(CLAIM_CHECK_S * 1000), self._check_claim)

    def _check_claim(self):
        self.claim_check = 0
        if self.ctl.screen_on and self.sensor.claimed and self.ctl.filter.lux is None:
            v = self.sensor.prop('LightLevel')
            if v is not None:
                self.ctl.lux(self.now(), float(v))
                self._reschedule()
        return False

    def _notified(self, fd, cond):
        try:
            os.lseek(fd, 0, os.SEEK_SET)
            os.read(fd, 64)
        except OSError:
            pass
        self.ctl.backlight_changed(self.now())
        self._reschedule()
        return True

    def _changed(self, conn, sender, path, iface, signal_name, params):
        _iface, changed, _ = params.unpack()
        if 'LightLevel' in changed and self.sensor.claimed:
            self.ctl.lux(self.now(), float(changed['LightLevel']))
            self._reschedule()

    def _appeared(self, conn, name, owner):
        self.sensor.appeared()
        if self.sensor.claimed:
            self._watch_claim()

    def _vanished(self, conn, name):
        self.sensor.vanished()

    def _state_changed(self, monitor, file, other, event):
        from gi.repository import Gio  # noqa: PLC0415
        if event not in (Gio.FileMonitorEvent.CHANGES_DONE_HINT, Gio.FileMonitorEvent.DELETED,
                         Gio.FileMonitorEvent.CREATED, Gio.FileMonitorEvent.RENAMED,
                         Gio.FileMonitorEvent.MOVED_IN):
            return
        state = self.store.load()
        if state == self.ctl.curve.state():
            return
        self.ctl.set_curve(self.now(), self.ctl.curve.with_state(state))
        log('your point: ' + (f'{self.ctl.curve.user[1]:.0f} nits at {self.ctl.curve.user[0]:.0f} lux'
                              if self.ctl.curve.user else 'none (the default curve)'))
        self._reschedule()


def print_curve(curve, out=sys.stdout):
    for lux in (0, 1, 3, 10, 30, 85, 100, 300, 1000, 3000, 10000, 30000):
        print(f'{lux:>6} lux  {curve.nits(lux):6.1f} nits  level {curve.level(lux):4d}', file=out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--backlight', help='the backlight (a name in /sys/class/backlight, or a directory)')
    ap.add_argument('--dpms', help='the DSI connector\'s dpms file ("" for none; default: found)')
    ap.add_argument('--config', help=f'the curve and panel range (default {config_path()})')
    ap.add_argument('--state', help=f'where your point is kept (default {state_path()})')
    ap.add_argument('--dry-run', action='store_true', help='log the levels instead of setting them')
    ap.add_argument('--verbose', action='store_true', help='log every reading and every change of the screen')
    ap.add_argument('--session', action='store_true', help='find the sensor proxy on the session bus (testing)')
    ap.add_argument('--print-curve', action='store_true', help='print the curve, with your point, and exit')
    ap.add_argument('--status', action='store_true', help='print your point as JSON and exit')
    ap.add_argument('--reset', action='store_true', help='forget your point (the running daemon follows)')
    a = ap.parse_args(argv)
    store = Store(a.state or state_path())
    if a.reset:
        store.reset()
        return 0
    if a.status:
        print(json.dumps(store.load() or {'version': 1}))
        return 0
    if a.print_curve:
        path = find_backlight(a.backlight)
        max_level = Backlight(path).max_level() if path else 2047
        print_curve(load_curve(max_level, a.config, find_board()).with_state(store.load()))
        return 0
    import gi  # noqa: PLC0415
    gi.require_version('Gio', '2.0')
    gi.require_version('GLibUnix', '2.0')
    from gi.repository import GLib, GLibUnix  # noqa: PLC0415
    daemon = Daemon(a)
    loop = GLib.MainLoop()
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, loop.quit)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, loop.quit)
    loop.run()
    daemon.sensor.release()
    return 0


if __name__ == '__main__':
    sys.exit(main())
