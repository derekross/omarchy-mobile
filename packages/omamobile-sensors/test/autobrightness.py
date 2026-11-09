#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Unit tests for lib/autobrightness.py: the curve and the user's point, the
ambient filter's smoothing and hysteresis, the ramps, and the controller
(manual changes, the screen going off and on) on a fake clock. Run by
test/all; needs no D-Bus, GLib or phone."""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
import autobrightness as ab  # noqa: E402

TESTS = []


def test(fn):
    TESTS.append(fn)
    return fn


PANEL = ab.Panel()
BASE = ab.Curve(PANEL)
GRID = [10 ** (e / 20) for e in range(-20, 101)]   # 0.1 to 100000 lux


def monotonic(curve):
    levels = [curve.level(lux) for lux in GRID]
    return all(a <= b for a, b in zip(levels, levels[1:]))


# ---------------------------------------------------------------- the curve

@test
def panel_levels_round_trip():
    for level in range(PANEL.min_level, PANEL.max_level + 1):
        assert PANEL.level(PANEL.nits(level)) == level, level
    assert PANEL.level(0) == 4 and PANEL.level(1e6) == 2047
    assert PANEL.nits(0) == 2.0     # level 0 (pixels off) is never a target
    assert abs(PANEL.level_u(2047) - 1.0) < 1e-12


@test
def curve_shape():
    assert monotonic(BASE)
    assert BASE.level(0) == BASE.level(1) == BASE.level(0.5)    # flat below 1 lux
    assert BASE.level(10000) == BASE.level(100000) == 2047      # daylight: the maximum
    assert 3.0 <= BASE.nits(0) <= 5.0                           # a dark room
    assert 80 <= BASE.nits(85) <= 130                           # the reference room
    assert BASE.level(85) < 0.25 * 2047                         # not 85 % any more
    # log-log: each decade between the points is a straight line
    mid = math.sqrt(10 * 100)
    assert abs(math.log10(BASE.nits(mid)) - (math.log10(25) + math.log10(110)) / 2) < 1e-9


@test
def curve_rejects_bad_points():
    for bad in ([(1, 3)], [(10, 3), (1, 5)], [(1, 5), (10, 3)], [(0, 3), (10, 5)], [(1, 0), (10, 5)]):
        try:
            ab.Curve(PANEL, bad)
        except ValueError:
            continue
        raise AssertionError(bad)


@test
def user_point_is_exact_and_the_curve_stays_monotonic():
    for lux in (0, 1, 5, 30, 85, 300, 2000, 10000, 50000):
        for level in (4, 7, 20, 60, 150, 336, 700, 1400, 2047):
            c = BASE.adjusted(lux, PANEL.nits(level))
            assert c.level(lux) == level, (lux, level, c.level(lux))
            assert 1 / ab.MAX_GAMMA - 1e-9 <= c.gamma <= ab.MAX_GAMMA + 1e-9
            assert monotonic(c), (lux, level)


@test
def a_preference_carries_over_and_daylight_stays_readable():
    base85, base1 = BASE.level(85), BASE.level(1)
    # brighter at night: brighter indoors too, daylight still the maximum
    c = BASE.adjusted(1, PANEL.nits(30))
    assert c.level(1) == 30 and c.level(85) > base85 and c.level(10000) == 2047
    # dimmer indoors: dimmer at night, daylight still the maximum
    c = BASE.adjusted(85, PANEL.nits(150))
    assert c.level(85) == 150 and c.level(1) <= base1 and c.level(10000) == 2047
    assert c.gamma > 1
    # brighter indoors
    c = BASE.adjusted(85, PANEL.nits(800))
    assert c.level(85) == 800 and c.level(1) > base1 and c.gamma < 1
    # dimmer in sunlight (the gamma can't move the maximum): holds there,
    # leaves indoor light alone, and a decade brighter is back at the top
    c = BASE.adjusted(20000, PANEL.nits(1400))
    assert c.level(20000) == 1400 and c.level(85) == base85 and c.level(200000) == 2047


@test
def an_extreme_point_blends_over_a_decade():
    # far dimmer than any gamma reaches at 85 lux
    c = BASE.adjusted(85, PANEL.nits(5))
    assert c.gamma == ab.MAX_GAMMA and c.level(85) == 5
    assert c.level(850) > c.level(300) > c.level(85)                 # rises back, smoothly
    bent = ab.Curve(PANEL, gamma=ab.MAX_GAMMA)
    assert c.level(850) == bent.level(850) and c.level(5000) == bent.level(5000)  # a decade on: the bent curve
    assert all(c.level(x) <= 5 for x in (0, 1, 10, 50, 85))           # never brighter below


@test
def saved_state_round_trips():
    for lux, level in ((85, 800), (3, 40), (20000, 1400), (85, 5)):
        c = BASE.adjusted(lux, PANEL.nits(level))
        back = BASE.with_state(c.state())
        assert back.level(lux) == level
        assert all(abs(back.level(x) - c.level(x)) <= 1 for x in GRID)
    assert BASE.with_state({}).user is None
    assert BASE.with_state({'lux': 'x', 'nits': 3}).user is None
    # edited by hand: the gamma is held to its range, nonsense is dropped
    assert BASE.with_state({'gamma': 0, 'lux': 85, 'nits': 100}).gamma == 1 / ab.MAX_GAMMA
    assert BASE.with_state({'gamma': -2, 'lux': 85, 'nits': 100}).gamma == 1 / ab.MAX_GAMMA
    assert BASE.with_state({'gamma': 50, 'lux': 85, 'nits': 100}).gamma == ab.MAX_GAMMA
    assert BASE.with_state({'gamma': 'nan', 'lux': 85, 'nits': 100}).user is None
    assert BASE.adjusted(85, 200).plain().user is None


@test
def config_file():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        config_in(d)


def config_in(d):
    p = os.path.join(d, 'c.json')
    with open(p, 'w') as f:
        f.write('{"curve": [[1, 5], [1000, 500]], "panel": {"max_nits": 500}}')
    c = ab.load_curve(2047, p)
    assert c.level(1) == c.panel.level(5) and c.level(1000) == 2047 and c.panel.max_nits == 500
    with open(p, 'w') as f:
        f.write('{"curve": [[10, 5], [1, 500]]}')                     # bad: the defaults
    assert ab.load_curve(2047, p).points == ab.CURVE
    with open(p, 'w') as f:
        f.write('not json')
    assert ab.load_curve(2047, p).points == ab.CURVE
    none = os.path.join(d, 'none')
    # the board's own range: cheetah's, which leaves HBM alone if a kernel
    # offers levels above 2047; another board, its whole range from 1
    for top in (2047, 4095):
        c = ab.load_curve(top, none, 'google,gs201-cheetah')
        assert (c.panel.min_level, c.panel.max_level) == (4, 2047) and c.level(100000) == 2047
    c = ab.load_curve(255, none, 'acme,phone')
    assert (c.panel.min_level, c.panel.max_level) == (1, 255)
    with open(p, 'w') as f:
        f.write('{"panel": {"min_level": 10, "max_level": 3000}}')
    c = ab.load_curve(4095, p, 'google,gs201-cheetah')
    assert (c.panel.min_level, c.panel.max_level) == (10, 3000)


# ---------------------------------------------------------------- the filter

def feed(filt, samples, t0=0.0, step=1.0):
    """Feed one sample a second; the times the accepted level moved."""
    moves = []
    t = t0
    for lux in samples:
        if filt.update(t, lux):
            moves.append(t)
        t += step
    return moves


@test
def noise_in_a_steady_room_never_moves_it():
    rnd = random.Random(7)
    f = ab.AmbientFilter()
    moves = feed(f, [85 * (1 + rnd.uniform(-0.07, 0.07)) for _ in range(600)])
    assert moves == [0.0], moves


@test
def brighter_light_is_followed_within_seconds():
    f = ab.AmbientFilter()
    moves = feed(f, [85] * 10 + [1000] * 20)
    assert moves[0] == 0.0 and len(moves) >= 2
    assert 10 < moves[1] <= 13.5, moves
    assert abs(math.log10(f.lux / 1000)) < 0.1


@test
def darker_light_is_followed_later_than_brighter():
    f = ab.AmbientFilter()
    moves = feed(f, [85] * 10 + [5] * 30)
    assert len(moves) >= 2 and 20 <= moves[1] <= 25, moves
    assert abs(math.log10(f.lux / 5)) < 0.16


@test
def a_spike_for_a_second_or_a_shadow_for_three_is_ignored():
    f = ab.AmbientFilter()
    assert feed(f, [85] * 10 + [5000] + [85] * 20) == [0.0]
    f = ab.AmbientFilter()
    assert feed(f, [85] * 10 + [2, 2, 2] + [85] * 20) == [0.0]


@test
def a_brightening_that_went_away_moves_nothing():
    # From the phone (2026-11-09, a dry run): following 12.8 lux, a burst
    # of 22 lux lifted the average over the band, then the room went back
    # to 11-13 lux. The lagging average still read "brighter" when the
    # debounce ran out, and the level then followed the reading of the
    # moment, 11 lux: a move down on a decision to brighten.
    # The same shape, clear of the band's edge: readings come in bursts
    # there, so the median turns well before the average does.
    f = ab.AmbientFilter()
    for t in range(20):
        f.update(float(t), 12.8)
    trace = [(20.0, 30.0), (20.1, 30.0), (20.2, 30.0), (20.3, 30.0), (21.3, 11.0), (21.4, 11.0), (21.5, 11.0)]
    for t, lux in trace:
        f.update(t, lux)
    assert 10 ** f.smooth > 12.8 * 10 ** f.brighten, 'the average still says brighter'
    t = trace[-1][0]
    while t < 30:
        t = f.next_due() or t + 1.0
        f.update(t)
    assert abs(math.log10(f.lux / 12.8)) < 1e-9, f.lux


# Readings from the phone (2026-11-09, a dry run in a dim room, the phone in
# use): (seconds, lux). About 14 lux, with a hand over the sensor under the
# panel for 7-8 s at a time (1-7 lux), a few seconds apart.
SHADED = [
    (0.21, 13.5), (0.46, 14.9), (1.47, 11.4), (1.77, 10.8), (2.77, 16.0), (3.76, 9.2), (4.04, 8.4),
    (5.06, 8.3), (6.09, 6.4), (6.64, 11.8), (7.48, 6.8), (7.66, 6.8), (8.19, 10.5), (8.99, 11.5),
    (9.31, 6.8), (9.44, 7.5), (9.97, 14.1), (10.2, 16.4), (11.22, 13.8), (12.23, 12.7),
    (13.26, 14.2), (13.68, 9.4), (13.83, 6.7), (13.93, 6.2), (14.03, 6.6), (14.58, 13.7),
    (14.78, 14.5), (15.53, 16.6), (16.55, 12.8), (17.58, 14.6), (18.6, 7.0), (18.68, 6.2),
    (18.78, 5.9), (18.88, 6.2), (19.89, 6.5), (20.06, 5.2), (20.24, 6.9), (21.26, 7.2),
    (21.49, 4.5), (21.59, 3.8), (21.67, 3.4), (21.77, 3.2), (21.91, 2.3), (22.04, 2.1),
    (22.29, 3.0), (23.07, 6.4), (23.44, 7.9), (24.37, 2.6), (24.44, 1.6), (24.51, 1.4),
    (24.57, 1.4), (24.64, 1.9), (25.17, 4.9), (25.56, 3.2), (25.76, 3.6), (26.14, 9.3),
    (26.27, 11.9), (26.38, 13.4), (26.56, 14.1), (26.84, 13.7), (27.42, 11.9), (27.89, 16.5),
    (28.92, 14.0), (29.87, 11.9), (30.18, 8.1), (30.33, 6.9), (30.5, 8.4), (31.33, 4.3),
    (31.43, 4.3), (32.44, 5.4), (33.14, 9.0), (33.55, 4.8), (33.65, 4.3), (33.77, 4.3),
    (34.79, 5.0), (35.27, 3.8), (35.6, 3.0), (35.85, 3.0), (36.63, 5.8), (37.35, 2.6),
    (37.47, 3.8), (37.86, 9.2), (38.04, 11.7), (38.18, 13.0), (38.39, 13.4), (39.41, 17.9),
    (39.75, 14.4), (40.14, 12.6), (41.15, 14.7), (42.02, 12.0), (43.03, 10.9), (43.65, 17.1),
    (44.33, 10.4), (44.53, 9.8), (44.92, 7.7), (45.66, 10.7), (45.99, 8.5), (46.24, 8.0),
    (47.27, 11.7), (48.28, 12.1), (48.53, 14.6), (49.08, 9.2), (49.95, 6.1), (50.1, 4.7),
    (50.21, 4.2), (50.31, 3.9), (51.34, 5.4), (52.16, 9.8), (52.5, 10.3), (53.14, 14.0),
    (53.65, 15.4), (54.5, 12.5), (55.53, 14.0), (55.88, 10.1), (56.08, 12.4), (57.08, 14.2),
    (57.3, 15.3), (58.33, 12.8), (59.36, 14.3), (60.33, 11.7), (61.35, 16.1), (62.36, 13.6),
    (62.89, 18.5), (63.36, 18.1), (64.01, 19.7), (64.37, 16.4)
]


@test
def a_hand_over_the_sensor_doesnt_pump_the_screen():
    f = ab.AmbientFilter()
    moves = []
    i = 0
    while i < len(SHADED):
        due = f.next_due()
        if due is not None and due < SHADED[i][0]:
            if f.update(due):
                moves.append(due)
            continue
        if f.update(*SHADED[i]):
            moves.append(SHADED[i][0])
        i += 1
    assert moves == [SHADED[0][0]], moves
    # what 5 s before dimming did with the same readings: down and up again
    f, again = ab.AmbientFilter(debounce_down=5.0), 0
    for t, lux in SHADED:
        again += f.update(t, lux)
    assert again >= 3, again


@test
def flicker_settles_once():
    f = ab.AmbientFilter()
    assert len(feed(f, [85, 200] * 60)) <= 2


@test
def time_passing_on_one_reading_converges():
    # The proxy signals only changes: one reading of 0 lux, then silence.
    f = ab.AmbientFilter()
    f.update(0.0, 85)
    f.update(1.0, 0)
    t, moves = 1.0, []
    while f.next_due() is not None and t < 60:
        t = f.next_due()
        if f.update(t):
            moves.append(t)
    assert moves and f.lux < 1.5 and f.next_due() is None, (moves, f.lux)


# ---------------------------------------------------------------- the ramp

def ramp_time(level, target, fast=False):
    r = ab.Ramp(PANEL)
    u, t, seen = PANEL.level_u(level), 0.0, [level]
    while u != PANEL.level_u(target):
        u = r.advance(u, target, ab.STEP_S, fast)
        seen.append(PANEL.level(PANEL.from_u(u)))
        t += ab.STEP_S
        assert t < 60
    direction = 1 if target > level else -1
    assert all((b - a) * direction >= 0 for a, b in zip(seen, seen[1:])), 'monotonic, no overshoot'
    assert seen[-1] == target
    return t


@test
def ramps_up_quickly_and_down_slowly():
    up, down = ramp_time(336, 1022), ramp_time(1022, 336)
    assert up < 0.6 and down > 2.0 and down > 4 * up, (up, down)
    assert ramp_time(1022, 336, fast=True) < 0.4


# ---------------------------------------------------------------- the controller

class FakeBacklight:
    def __init__(self, level):
        self.value = level
        self.writes = []

    def read(self):
        return self.value

    def write(self, level):
        self.value = level
        self.writes.append(level)
        return True


class FailingBacklight(FakeBacklight):
    """A write that fails (logind refused it, or a timeout); with lands=True
    it still reaches the panel, late, as a timed-out call can."""

    def __init__(self, level, lands=False):
        super().__init__(level)
        self.fail, self.lands, self.tries = True, lands, 0

    def write(self, level):
        self.tries += 1
        if not self.fail:
            return super().write(level)
        if self.lands:
            self.value = level
        return False


class FakeSensor:
    def __init__(self):
        self.claimed = False
        self.log = []

    def claim(self):
        self.claimed = True
        self.log.append('claim')

    def release(self):
        self.claimed = False
        self.log.append('release')


class FakeStore:
    def __init__(self):
        self.saved = []

    def save(self, state):
        self.saved.append(state)


class Sim:
    """A controller on a fake clock: a reading a second while the sensor is
    claimed, and step() whenever it asks for one."""

    def __init__(self, level=716, curve=BASE, backlight=None):
        self.bl = backlight or FakeBacklight(level)
        self.sensor = FakeSensor()
        self.store = FakeStore()
        self.ctl = ab.Controller(curve, self.bl, self.sensor, self.store, logger=lambda m: None)
        self.t = 0.0
        self.next_sample = 0.0
        self.next_step = None

    def screen(self, on):
        self.ctl.screen(self.t, on)
        self.next_sample = self.t + 0.5
        self._step()

    def user_sets(self, level):
        self.bl.value = level
        self.ctl.backlight_changed(self.t)
        self._step()

    def _step(self):
        w = self.ctl.step(self.t)
        self.next_step = None if w is None else self.t + w

    def run(self, seconds, lux):
        end = self.t + seconds
        while True:
            t = min(self.next_sample, self.next_step if self.next_step is not None else math.inf)
            if t > end:
                break
            self.t = t
            if t == self.next_sample:
                if self.sensor.claimed:
                    self.ctl.lux(t, lux(t) if callable(lux) else lux)
                self.next_sample += 1.0
            self._step()
        self.t = end


@test
def screen_on_follows_the_room_and_then_holds():
    s = Sim(level=716)
    s.screen(True)
    assert s.sensor.claimed
    s.run(3, 85)
    target = BASE.level(85)
    assert s.bl.value == target, (s.bl.value, target)
    assert all(a >= b for a, b in zip([716] + s.bl.writes, s.bl.writes)), 'down only'
    n = len(s.bl.writes)
    rnd = random.Random(3)
    s.run(300, lambda t: 85 * (1 + rnd.uniform(-0.07, 0.07)))
    assert len(s.bl.writes) == n, 'no flicker in a steady room'
    assert not s.store.saved


@test
def brightens_faster_than_it_dims():
    def settle_time(start, to):
        s = Sim(level=BASE.level(start))
        s.screen(True)
        s.run(30, start)
        t0, target = s.t, BASE.level(to)
        while s.bl.value != target:
            s.run(0.25, to)
            assert s.t - t0 < 60
        return s.t - t0
    up, down = settle_time(85, 1000), settle_time(1000, 85)
    assert up < 4.0 and down > up + 3.0, (up, down)


@test
def a_manual_level_becomes_the_users_point():
    s = Sim(level=BASE.level(85))
    s.screen(True)
    s.run(10, 85)
    s.user_sets(800)
    n = len(s.bl.writes)
    s.run(1.0, 85)
    assert s.bl.value == 800 and len(s.bl.writes) == n, 'no writes while it settles'
    s.run(2.0, 85)
    assert s.store.saved and s.store.saved[-1]['nits'] == round(PANEL.nits(800), 3)
    assert abs(math.log10(s.store.saved[-1]['lux'] / 85)) < 0.05
    rnd = random.Random(5)
    s.run(300, lambda t: 85 * (1 + rnd.uniform(-0.07, 0.07)))
    assert s.bl.value == 800 and len(s.bl.writes) == n, 'no fight afterwards'
    # brighter light: brighter than the plain curve would be there
    s.run(10, 1000)
    assert s.bl.value > BASE.level(1000), (s.bl.value, BASE.level(1000))
    # a dragged slider (several levels in a row) teaches its last one
    s.run(10, 85)
    for level in (700, 600, 500, 450):
        s.user_sets(level)
        s.run(0.3, 85)
    s.run(3, 85)
    assert s.store.saved[-1]['nits'] == round(PANEL.nits(450), 3) and s.bl.value == 450


@test
def the_slider_during_a_ramp_wins_at_once():
    s = Sim(level=BASE.level(1000))
    s.screen(True)
    s.run(10, 1000)
    while s.bl.value == BASE.level(1000):   # until the slow ramp down starts
        s.run(0.25, 85)
        assert s.t < 40
    s.run(0.5, 85)
    assert BASE.level(85) < s.bl.value < BASE.level(1000), s.bl.value
    s.user_sets(1500)
    n = len(s.bl.writes)
    s.run(5, 85)
    assert len(s.bl.writes) == n and s.bl.value == 1500
    assert s.store.saved


@test
def a_write_that_fails_teaches_nothing():
    # Every write refused: the panel keeps its level, nothing is learned,
    # and the daemon tries again now and then rather than at 20 Hz.
    bl = FailingBacklight(716)
    s = Sim(backlight=bl)
    s.screen(True)
    s.run(60, 85)
    assert bl.value == 716 and not s.store.saved, s.store.saved
    assert 5 <= bl.tries <= 20, bl.tries
    # logind answers again: the next try gets there, still nothing learned
    bl.fail = False
    s.run(10, 85)
    assert bl.value == BASE.level(85) and not s.store.saved
    # a timed-out write that lands late is ours, not the user's
    bl = FailingBacklight(716, lands=True)
    s = Sim(backlight=bl)
    s.screen(True)
    s.run(30, 85)
    assert not s.store.saved, s.store.saved


@test
def a_level_changed_without_a_notice_is_still_the_users():
    # The check before each write: a change the daemon wasn't told about
    # (the notice still on its way) stops the ramp, and the level is kept.
    s = Sim(level=BASE.level(1000))
    s.screen(True)
    s.run(10, 1000)
    while s.bl.value == BASE.level(1000):
        s.run(0.25, 85)
        assert s.t < 40
    s.bl.value = 1600                   # no backlight_changed() call
    n = len(s.bl.writes)
    s.run(5, 85)
    assert len(s.bl.writes) == n and s.bl.value == 1600
    assert s.store.saved and s.store.saved[-1]['nits'] == round(PANEL.nits(1600), 3)


@test
def the_slider_soon_after_a_wake_is_kept():
    s = Sim(level=716)
    s.screen(True)
    s.run(1.5, 85)
    s.user_sets(1500)
    s.run(5, 85)
    assert s.bl.value == 1500 and s.store.saved


@test
def screen_off_releases_the_sensor_and_teaches_nothing():
    s = Sim(level=716)
    s.screen(True)
    s.run(5, 85)
    level = s.bl.value
    # the power key: brightness 0, then the panel off, then the saved level back
    s.user_sets(0)
    s.run(1, 85)
    assert s.bl.value == 0 and not s.store.saved
    s.screen(False)
    assert s.sensor.log[-1] == 'release' and not s.sensor.claimed
    s.user_sets(level)
    n = len(s.bl.writes)
    s.run(60, 85)
    assert len(s.bl.writes) == n and not s.store.saved
    # the wake, from a dark pocket into daylight: claimed again, follows fast
    s.screen(True)
    assert s.sensor.claimed and s.sensor.log.count('claim') == 2
    s.run(2, 10000)
    assert s.bl.value == 2047 and not s.store.saved


@test
def a_wake_from_level_0_is_not_a_preference():
    s = Sim(level=0)
    s.screen(True)
    s.run(1, 85)
    assert s.bl.writes == []                 # a dark panel stays dark
    s.user_sets(int(0.4 * 2047))             # omamobile-keys' 40 % for a black wake
    s.run(5, 85)
    assert s.bl.value == BASE.level(85) and not s.store.saved


@test
def a_saved_point_comes_back():
    s = Sim(level=BASE.level(85))
    s.screen(True)
    s.run(5, 85)
    s.user_sets(900)
    s.run(3, 85)
    again = Sim(level=300, curve=BASE.with_state(s.store.saved[-1]))
    again.screen(True)
    again.run(3, 85)
    assert again.bl.value == 900


def main():
    failed = 0
    for fn in TESTS:
        try:
            fn()
            print(f'ok - {fn.__name__}')
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f'not ok - {fn.__name__}: {type(e).__name__}: {e}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
