# SPDX-License-Identifier: MIT
"""USF sensor backend for omamobile-sensor-proxy: the AoC's sensors over
/dev/acd-com.google.usf (device/cheetah/AOC-PLAN.md, USF-PROTOCOL.md).

On start it makes sure the AoC's sensor registry is loaded, as Android's sensor
HAL does once per AoC boot (see usf.load_registry): the stock registry scripts
(Google's files, installed from the phone's own vendor partition, never
shipped), then this phone's factory calibration from persist:/sensors/registry,
read with debugfs (read-only; persist is never mounted or written). The AoC
then probes its physical sensors, which needs their supplies on
(gs201_aoc_rails, loaded by omamobile-aoc-start before the firmware).

A claim starts sampling on the AoC; the last release stops it.

Streams (the gyroscope) differ from the UI sensors: every sample goes to the
proxy, with its timestamp moved from the AoC's clock to CLOCK_MONOTONIC
(AocClock), so that a camera can line the samples up with its frames.
"""
import glob
import os
import subprocess
import sys
import tempfile
import time

from gi.repository import GLib

import usf

REGISTRY_DIRS = ('/usr/share/omamobile/sensors/registry',
                 '/usr/share/omamobile/sensors/registry/append')
PERSIST_REGISTRY = '/sensors/registry'
# The AoC probes its physical sensors once, when the registry is loaded. On a
# boot where the registry was loaded about a second after the AoC came up, the
# LSM6DSV accelerometer (I3C) never appeared while the I2C sensors did; loaded
# minutes later, all of them appeared. Give the AoC this long after its
# firmware load (omamobile-aoc-start's marker) before loading the registry.
AOC_LOADED_MARKER = '/run/omamobile/aoc-firmware-loaded'
AOC_SETTLE_S = float(os.environ.get('OMAMOBILE_AOC_SETTLE_S', '15'))
SENSOR_ORIENTATION = 24      # fused azimuth, pitch, roll in degrees
# Google's lux for automatic brightness, from the TMD3719 under the panel: a
# reading a second, which follows the room and not the panel's own light.
SENSOR_AUTO_BRIGHTNESS = 48
# kind -> (USF sensor type, sampling period ns, reporting mode, physical)
KINDS = {
    'accel': (usf.SENSOR_ACCEL, 66_666_666, usf.RPT_CONTINUOUS, True),   # 15 Hz
    'light': (SENSOR_AUTO_BRIGHTNESS, 1_000_000_000, usf.RPT_CONTINUOUS, False),
    'proximity': (usf.SENSOR_PROX, 200_000_000, usf.RPT_ON_CHANGE, True),
    'compass': (SENSOR_ORIENTATION, 200_000_000, usf.RPT_CONTINUOUS, False),  # 5 Hz
}
# kind -> USF sensor type, for the sample streams (all physical sensors).
STREAMS = {'gyro': usf.SENSOR_GYRO}
CLIENT_ID = 0x4F4D5350   # "OMSP"
# The AoC's clock and the kernel's boottime, read together by the kernel
# (aoc.c: arch_timer_read_counter(), then ktime_get_boottime()).
AOC_CLOCK_GLOB = '/sys/bus/platform/devices/*.aoc/aoc_clock_and_kernel_boottime'
# Re-read the pairing this often while a stream runs: CLOCK_MONOTONIC is
# slewed by time synchronisation and stops in suspend; the AoC's clock is not.
AOC_CLOCK_RESYNC_S = 1.0
# The TMD3719 under the panel times its conversions to the display: without
# the display state Android's HAL sends (usf.display_info) it never converts,
# for light or proximity. Read from the panel's DRM connector and backlight
# when they exist; until the panel driver does, the panel counts as on at
# 60 Hz. On the Pixel 8 Pro the rate must be the panel's real one: its
# panel switches between 60 and 120 Hz, and told 60 while it runs at 120
# the TMD3719 reports no light (-1) and no proximity. With
# OMAMOBILE_PANEL_HZ=drm (set by that phone's device package) the rate comes
# from the mode of the CRTC that drives the DSI panel, in DRM's debugfs
# state (needs root, as the proxy runs); a number sets it; unset keeps 60.
PANEL_DPMS_GLOB = '/sys/class/drm'
PANEL_DBV_DIR = '/sys/class/backlight'
DRM_STATE_GLOB = '/sys/kernel/debug/dri/*/state'
DISPLAY_SYNCED = ('light', 'proximity')


def log(msg):
    print(f'omamobile-sensor-proxy: {msg}', file=sys.stderr, flush=True)


def read_text(path, default=''):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def panel_paths():
    dpms = next((os.path.join(PANEL_DPMS_GLOB, d, 'dpms') for d in sorted(os.listdir(PANEL_DPMS_GLOB))
                 if '-DSI-' in d), None) if os.path.isdir(PANEL_DPMS_GLOB) else None
    dbv = next((os.path.join(PANEL_DBV_DIR, d, 'brightness') for d in sorted(os.listdir(PANEL_DBV_DIR))),
               None) if os.path.isdir(PANEL_DBV_DIR) else None
    return dpms, dbv


_drm_fallback_logged = False


def drm_panel_hz(text):
    """The refresh rate of the CRTC driving a DSI connector in one DRM state
    dump (drm_atomic_print_new_state), or None."""
    crtcs, panel_crtc = {}, None
    block = name = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith(('crtc[', 'connector[', 'plane[')):
            block = line.split('[', 1)[0]
            name = line.split(': ', 1)[1] if ': ' in line else None
            if block == 'crtc':
                crtcs[name] = {'active': False, 'hz': 0}
        elif block == 'crtc' and line == 'active=1':
            crtcs[name]['active'] = True
        elif block == 'crtc' and line.startswith('mode:'):
            # mode: "name": vrefresh clock hdisplay ... (DRM_MODE_FMT)
            try:
                crtcs[name]['hz'] = int(line.rsplit('":', 1)[1].split()[0])
            except (IndexError, ValueError):
                pass
        elif block == 'connector' and name and '-DSI-' in f'-{name}' and line.startswith('crtc='):
            panel_crtc = line.split('=', 1)[1]
    c = crtcs.get(panel_crtc)
    return c['hz'] if c and c['active'] and c['hz'] > 0 else None


def panel_refresh_hz():
    """The refresh rate to tell the AoC: OMAMOBILE_PANEL_HZ (a number, or
    'drm' for the panel's mode), else 60."""
    global _drm_fallback_logged
    want = os.environ.get('OMAMOBILE_PANEL_HZ', '')
    if want.isdigit() and int(want) > 0:
        return int(want)
    if want != 'drm':
        return 60
    for path in sorted(glob.glob(DRM_STATE_GLOB)):
        hz = drm_panel_hz(read_text(path))
        if hz:
            return hz
    if not _drm_fallback_logged:
        log('no active DSI panel mode in DRM debugfs state: telling the AoC 60 Hz')
        _drm_fallback_logged = True
    return 60


def display_state():
    """(status, refresh rate, DBV) as the stock HAL reports them: off is 0 Hz."""
    dpms, dbv_path = panel_paths()
    if dpms and read_text(dpms, 'On') != 'On':
        return usf.DISP_OFF, 0, 0
    try:
        dbv = int(read_text(dbv_path, '0')) if dbv_path else 0
    except ValueError:
        dbv = 0
    return usf.DISP_ON, panel_refresh_hz(), dbv


def aoc_settle(marker=AOC_LOADED_MARKER, settle=AOC_SETTLE_S, now=time.time, sleep=time.sleep):
    """Wait until the AoC's firmware was loaded at least `settle` seconds ago.
    Returns the seconds waited (0 without the marker: a start by hand)."""
    try:
        age = now() - os.stat(marker).st_mtime
    except OSError:
        return 0.0
    wait = max(0.0, min(settle - age, settle))
    if wait > 0:
        log(f'waiting {wait:.1f} s for the AoC to settle before loading the sensor registry')
        sleep(wait)
    return wait


def persist_device():
    for entry in os.listdir('/sys/class/block'):
        try:
            with open(f'/sys/class/block/{entry}/uevent') as f:
                if 'PARTNAME=persist\n' in f.read():
                    return f'/dev/{entry}'
        except OSError:
            continue
    return None


def factory_calibration(target):
    """Copy persist's sensor calibration scripts into target, read-only."""
    dev = persist_device()
    if not dev:
        return
    try:
        listing = subprocess.run(['debugfs', '-R', f'ls {PERSIST_REGISTRY}', dev],
                                 capture_output=True, text=True).stdout
    except OSError:
        log('no debugfs (e2fsprogs): factory sensor calibration not loaded')
        return
    for name in listing.split():
        if not name.endswith('.reg'):
            continue
        data = subprocess.run(['debugfs', '-R', f'cat {PERSIST_REGISTRY}/{name}', dev],
                              capture_output=True).stdout
        if data:
            with open(os.path.join(target, name), 'wb') as f:
                f.write(data)


def aoc_ticks_to_ns(ticks):
    """The AoC firmware's own conversion of its 24.576 MHz ticks to ns
    (aoc_ticks_to_nanoseconds, USF-PROTOCOL.md section 1c)."""
    return (ticks * 2666667 + 0x8000) >> 16


def clock_ns(clock):
    return time.clock_gettime_ns(clock)


class AocClock:
    """Maps the AoC's sensor-core time (ns, the sample timestamps) to
    CLOCK_MONOTONIC ns.

    The kernel pairs the AoC's tick counter with CLOCK_BOOTTIME in one sysfs
    read; CLOCK_BOOTTIME minus CLOCK_MONOTONIC (the time spent suspended) is
    measured here around a CLOCK_MONOTONIC read. Both the AoC counter and the
    kernel's clocks run from the SoC's arch timer, so the offset only moves by
    time-sync slewing and suspend; sync() is cheap and is repeated while a
    stream runs. Without the sysfs file, fall back to the USF time server
    (the midpoint of the request, which costs the round trip's error)."""

    def __init__(self, path=None, read=read_text, now=clock_ns, get_time=None):
        if path is None:
            path = next(iter(sorted(glob.glob(AOC_CLOCK_GLOB))), None)
        self.path = path
        self.read = read
        self.now = now
        self.get_time = get_time    # () -> AoC ns, for the fallback
        self.offset = None          # monotonic ns minus AoC ns
        self.synced = None          # CLOCK_MONOTONIC s of the last sync

    def _boot_minus_mono(self):
        b0 = self.now(time.CLOCK_BOOTTIME)
        m = self.now(time.CLOCK_MONOTONIC)
        b1 = self.now(time.CLOCK_BOOTTIME)
        return (b0 + b1) // 2 - m

    def sync(self):
        boot_minus_mono = self._boot_minus_mono()
        pair = self.read(self.path, '').split() if self.path else []
        if len(pair) == 2 and pair[0] != '0':
            aoc_ns = aoc_ticks_to_ns(int(pair[0]))
            self.offset = int(pair[1]) - boot_minus_mono - aoc_ns
        elif self.get_time is not None:
            m0 = self.now(time.CLOCK_MONOTONIC)
            aoc_ns = self.get_time()
            m1 = self.now(time.CLOCK_MONOTONIC)
            self.offset = (m0 + m1) // 2 - aoc_ns
        else:
            raise usf.UsfError('no AoC clock: neither aoc_clock_and_kernel_boottime nor a time server')
        self.synced = self.now(time.CLOCK_MONOTONIC) / 1e9
        return self.offset

    def to_monotonic(self, aoc_ns):
        if self.offset is None or self.now(time.CLOCK_MONOTONIC) / 1e9 - self.synced >= AOC_CLOCK_RESYNC_S:
            self.sync()
        return aoc_ns + self.offset


def stream_samples(batch, clock):
    """A compact gyroscope batch as [(monotonic ns, x, y, z)]."""
    return [(clock.to_monotonic(ts), vals[0], vals[1], vals[2])
            for ts, _acc, vals in batch['samples'] if len(vals) >= 3]


class UsfBackend:
    def __init__(self, device, report, clock=None, transport=None):
        self.report = report
        self.tr = transport or usf.ChannelTransport(device, device + usf.NWU_SUFFIX)
        self.client = usf.UsfClient(self.tr)
        self.mgr = self.client.get_server(usf.UUID_SENSOR_MGR)
        self.max_range = {}
        self._ensure_registry()
        self.handles = self._find_sensors()
        self.stream_info = {}  # stream kind -> (handle, min Hz, max Hz)
        self._find_streams()
        self.has = {kind: kind in self.handles for kind in KINDS}
        self.has.update({kind: kind in self.stream_info for kind in STREAMS})
        self.clock = clock or AocClock(get_time=self._aoc_time)
        self.sampling = {}     # kind -> sampling id
        self.kind_of = {}      # sampling id -> kind
        self.display = None    # last display state sent
        self.display_watch = None
        try:
            self.disp = self.client.get_server(usf.UUID_DISPLAY_INFO)
        except usf.UsfError as e:
            self.disp = None
            log(f'no display info server: {e}')
        self._send_display()
        for fd in self.tr.fds:
            GLib.io_add_watch(fd, GLib.IO_IN, self._readable)
        log('sensors: ' + ', '.join(f'{k} (handle {h})' for k, h in self.handles.items()) +
            ''.join(f', {k} (handle {h}, {lo:g}-{hi:g} Hz)' for k, (h, lo, hi) in self.stream_info.items()))

    def _aoc_time(self):
        th = self.client.get_server(usf.UUID_TIME)
        return self.client.get_time(th)

    def _find_streams(self):
        """The stream sensors, from the sensor list _find_sensors() waited for."""
        for h, info in sorted(self.infos.items()):
            for kind, stype in STREAMS.items():
                if info['type'] != stype or not info['registry_path'] or info['index'] != 0:
                    continue
                lo = 1e9 / info['max_period_ns'] if info.get('max_period_ns') else 1.0
                hi = 1e9 / info['min_period_ns'] if info.get('min_period_ns') else 1000.0
                self.stream_info[kind] = (h, lo, hi)

    def stream_range(self, kind):
        """(lowest, highest) rate in Hz the sensor takes."""
        _h, lo, hi = self.stream_info[kind]
        return lo, hi

    def start_stream(self, kind, period_ns):
        """Sample a stream sensor at period_ns (restarting it if it runs), with
        no batching: each sample is sent as soon as the AoC has it."""
        self.stop_stream(kind)
        handle = self.stream_info[kind][0]
        self.clock.sync()
        sid = self.client.start_sampling(handle, int(period_ns), 0, rpt_mode=usf.RPT_CONTINUOUS,
                                         client_id=CLIENT_ID, non_wakeup=True)
        self.sampling[kind] = sid
        self.kind_of[sid] = kind
        self._drain(self.client.events)
        self.client.events = []

    def stop_stream(self, kind):
        sid = self.sampling.pop(kind, None)
        if sid is None:
            return
        self.kind_of.pop(sid, None)
        try:
            self.client.stop_sampling(self.stream_info[kind][0], sid)
        except usf.UsfError as e:
            log(f'stop {kind}: {e}')
        self._drain(self.client.events)
        self.client.events = []

    def _ensure_registry(self):
        reg = self.client.get_server(usf.UUID_REGISTRY)
        if ('loaded', '1') in self.client.registry_get(reg, '/'):
            return
        aoc_settle()
        with tempfile.TemporaryDirectory() as cal:
            factory_calibration(cal)
            dirs = [d for d in REGISTRY_DIRS if os.path.isdir(d)] + [cal]
            if not any(os.path.isdir(d) for d in REGISTRY_DIRS):
                log('no sensor registry in /usr/share/omamobile/sensors/registry: only virtual sensors')
            usf.load_registry(self.client, dirs, usf.device_cdt(), out=sys.stderr)

    def _find_sensors(self):
        # The AoC probes its sensors asynchronously after the registry loads.
        deadline = time.monotonic() + 10
        while True:
            infos = {}
            for h in self.client.sensor_list(self.mgr):
                try:
                    infos[h] = self.client.sensor_info(h)
                except usf.UsfError:
                    continue
            handles = {}
            for kind, (stype, _, _, physical) in KINDS.items():
                # A physical sensor has a registry path; the fused ones do not.
                cands = sorted((i['index'], h) for h, i in infos.items()
                               if i['type'] == stype and bool(i['registry_path']) == physical)
                if cands:
                    handles[kind] = cands[0][1]
                    self.max_range[kind] = infos[cands[0][1]]['max_range']
            if len(handles) == len(KINDS) or time.monotonic() > deadline:
                self.infos = infos
                return handles
            time.sleep(0.5)

    def _send_display(self):
        state = display_state()
        if self.disp is None or state == self.display:
            return
        status, rate, dbv = state
        try:
            self.client.display_info(self.disp, brightness=dbv, status=status,
                                     refresh_rate=rate, op_hz=usf.DEFAULT_OP_HZ)
            self.display = state
        except usf.UsfError as e:
            log(f'display info: {e}')
        self._drain(self.client.events)
        self.client.events = []

    def _display_tick(self):
        self._send_display()
        if any(k in self.sampling for k in DISPLAY_SYNCED):
            return True
        self.display_watch = None
        return False

    def start(self, kind):
        stype, period, mode, _ = KINDS[kind]
        if kind in DISPLAY_SYNCED:
            self._send_display()
            if self.display_watch is None:
                self.display_watch = GLib.timeout_add_seconds(1, self._display_tick)
        # UI sensors must not wake the AP (a wakeup channel at 15 Hz keeps
        # renewing a wake lock and blocks suspend).
        sid = self.client.start_sampling(self.handles[kind], period, 0, rpt_mode=mode,
                                         client_id=CLIENT_ID, non_wakeup=True)
        self.sampling[kind] = sid
        self.kind_of[sid] = kind
        self._drain(self.client.events)
        self.client.events = []

    def stop(self, kind):
        sid = self.sampling.pop(kind, None)
        if sid is None:
            return
        self.kind_of.pop(sid, None)
        try:
            self.client.stop_sampling(self.handles[kind], sid)
        except usf.UsfError as e:
            log(f'stop {kind}: {e}')
        self._drain(self.client.events)
        self.client.events = []

    def _readable(self, fd, cond):
        self._drain(self.client.poll(0))
        return True

    def _drain(self, items):
        for item in items:
            if item[0] != 'compact':
                continue
            batch = item[1]
            kind = self.kind_of.get(batch['sampling_id'])
            if not kind or not batch['samples']:
                continue
            if kind in STREAMS:
                self.report(kind, stream_samples(batch, self.clock))
                continue
            _ts, _acc, vals = batch['samples'][-1]
            if kind == 'accel':
                self.report('accel', tuple(vals[:3]))
            elif kind == 'light':
                # vals[1] follows the room within seconds; vals[0] is slower.
                self.report('light', vals[1])
            elif kind == 'proximity':
                self.report('proximity', vals[0] < self.max_range['proximity'])
            elif kind == 'compass':
                self.report('compass', vals[0] % 360.0)
