#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Palmtop, root: log what the touchscreen reports, as bursts with wall-clock times, beside a sleep series:
does an early wake on the touchscreen's interrupt come with a touch, or with nothing?

  touch-log.py [OUT]     (a transient unit; stop it with systemctl stop)

One line per burst of frames (frames less than 0.5 s apart): its start and end (CLOCK_REALTIME, the series
log's clock), the number of frames, the most contacts at once, and any key codes (a wake gesture). No
positions are written. Read-only: no grab, so the compositor sees everything as before."""
import fcntl, glob, os, select, struct, sys, time

OUT = sys.argv[1] if len(sys.argv) > 1 else time.strftime('/var/log/omamobile/touch-%Y%m%d.log')
EVIOCSCLOCKID = 0x400445a0
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT, SYN_DROPPED = 0, 3
ABS_MT_SLOT, ABS_MT_TRACKING_ID = 0x2f, 0x39
BTN_TOUCH = 0x14a
FMT = 'qqHHi'
SIZE = struct.calcsize(FMT)


def find():
    for d in sorted(glob.glob('/sys/class/input/event*')):
        try:
            name = open(d + '/device/name').read().strip()
        except OSError:
            continue
        if 'touch' in name.lower() and 'finger' not in name.lower():
            return '/dev/input/' + os.path.basename(d), name
    return None, None


def stamp(t):
    return time.strftime('%H:%M:%S', time.localtime(t)) + ('%.3f' % (t % 1))[1:]


def main():
    path, name = find()
    with open(OUT, 'a', buffering=1) as out:
        if not path:
            out.write('no touchscreen found\n')
            return 1
        fd = os.open(path, os.O_RDONLY)
        fcntl.ioctl(fd, EVIOCSCLOCKID, struct.pack('i', 0))   # CLOCK_REALTIME
        out.write(f'start {stamp(time.time())}: {path} ({name})\n')
        burst = None   # [start, end, frames, max contacts, keys, dropped]
        active = set()
        slot = 0
        frame_had = False
        keys = []
        while True:
            ready, _, _ = select.select([fd], [], [], 1.0)
            data = os.read(fd, SIZE * 64) if ready else b''
            for i in range(0, len(data) - SIZE + 1, SIZE):
                sec, usec, typ, code, value = struct.unpack_from(FMT, data, i)
                t = sec + usec / 1e6
                if typ == EV_ABS:
                    frame_had = True
                    if code == ABS_MT_SLOT:
                        slot = value
                    elif code == ABS_MT_TRACKING_ID:
                        if value < 0:
                            active.discard(slot)
                        else:
                            active.add(slot)
                elif typ == EV_KEY:
                    frame_had = True
                    if code != BTN_TOUCH:
                        keys.append(f'{code}={value}')
                elif typ == EV_SYN and code == SYN_DROPPED:
                    if burst:
                        burst[5] += 1
                elif typ == EV_SYN and code == SYN_REPORT and frame_had:
                    frame_had = False
                    if burst and t - burst[1] > 0.5:
                        out.write(f'burst {stamp(burst[0])} to {stamp(burst[1])}: {burst[2]} frames, '
                                  f'up to {burst[3]} contacts, keys {burst[4] or "-"}, dropped {burst[5]}\n')
                        burst = None
                    if not burst:
                        burst = [t, t, 0, 0, [], 0]
                    burst[1] = t
                    burst[2] += 1
                    burst[3] = max(burst[3], len(active))
                    burst[4].extend(keys)
                    keys = []
            if burst and time.time() - burst[1] > 0.5:
                out.write(f'burst {stamp(burst[0])} to {stamp(burst[1])}: {burst[2]} frames, '
                          f'up to {burst[3]} contacts, keys {burst[4] or "-"}, dropped {burst[5]}\n')
                burst = None


sys.exit(main())
