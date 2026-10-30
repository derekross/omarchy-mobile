# SPDX-License-Identifier: MIT
"""A scrubbed record of the SIT traffic, for turning a run on the phone into
offline fixtures (MODEM-PLAN, the first SIM test). Off by default
([trace] record = no).

Each record is one message: its direction and kind, ID and name, total
length, a response's error code and time since its request, and for a few
messages the status codes the RIL already logs (registration and data-call
states, SIM card and application states, IMS registration state, call
state). Never a payload value: no bytes, numbers, text, addresses, AIDs,
APNs or PLMNs. Messages listed in SHAPED, whose bytes carry no identifier,
address, location or user content, also get their shape: one character per
byte, "0" for a zero byte and "x" for any other. That shows which offsets a
firmware fills, which is what an unconfirmed layout (signal strength) needs.

The file stays on the phone: /var/lib/omamobile-sit/trace (root, 0700) by
default, size-capped, and nothing copies it anywhere. Read it there; before
quoting any of it, grep it as MODEM-PLAN says for every log.
"""
import json
import os
from pathlib import Path
import struct
import time

from sit_names import NAMES

# Shapes only for these: radio and NR mode state, PS permission, signal
# strength (request, indication), IMS stack/hidden-menu/PDN acknowledgements
# (empty), screen state and indication filter acknowledgements (empty).
SHAPED = frozenset({0x0801, 0x0802, 0x0749, 0x0748, 0x0711, 0x0710, 0x0625, 0x0900, 0x0906,
                    0x0d39, 0x0d07, 0x0d08, 0x0d38, 0x0902, 0x0928, 0x061b})
MAX_SHAPE = 1024


def shape(params):
    return ''.join('0' if b == 0 else 'x' for b in params[:MAX_SHAPE])


def codes(ident, kind, params):
    """The status codes of a few responses and indications, as the RIL logs
    them anyway. Each reads fixed small fields only."""
    try:
        if ident == 0x0701 and kind == 'resp' and len(params) >= 4:
            return dict(reg=params[0], reject=params[1], rat=params[3])
        if ident == 0x0600 and kind == 'resp' and len(params) >= 5:
            status, cid, active, pdp = struct.unpack_from('<HBBB', params)
            return dict(status=status, cid=cid, active=active, pdp=pdp)
        if ident == 0x0200 and kind == 'resp' and len(params) >= 3 and params[2] <= 8 \
                and len(params) >= 3 + params[2] * 63:
            return dict(card=params[0], apps=[[params[i], params[i + 1]]
                                              for i in range(3, 3 + params[2] * 63, 63)])
        if ident == 0x0d05 and kind == 'ind' and len(params) >= 2:
            return dict(state=params[0], features=params[1])
        if ident == 0x0d04 and kind == 'ind' and len(params) >= 7:
            return dict(state=params[3], cause=params[6])
        if ident == 0x0802 and kind == 'ind' and len(params) >= 4:
            return dict(radio=struct.unpack_from('<I', params)[0])
    except struct.error:
        pass
    return None


class Tracer:
    def __init__(self, directory, max_bytes=4 << 20):
        directory = Path(directory)
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        directory.chmod(0o700)
        name = time.strftime('sit-trace-%Y%m%d-%H%M%S.jsonl')
        fd = os.open(directory / name, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_CLOEXEC, 0o600)
        self.out = os.fdopen(fd, 'a', buffering=1)
        self.path = directory / name
        self.start = time.monotonic()
        self.left = max_bytes
        self.sent = {}

    def write(self, record):
        if self.left <= 0:
            return
        record['t'] = round(time.monotonic() - self.start, 3)
        line = json.dumps(record, separators=(',', ':')) + '\n'
        if len(line) > self.left:
            line = json.dumps(dict(t=record['t'], note='trace size limit reached')) + '\n'
            self.left = 0
        else:
            self.left -= len(line)
        self.out.write(line)

    def request(self, ident, token, length):
        self.sent[token] = time.monotonic()
        self.write(dict(dir='out', kind='req', id=f'{ident:04x}', name=NAMES.get(ident, ''), len=length))

    def incoming(self, packet):
        kind, _, ident, length = struct.unpack_from('<BBHH', packet)
        record = dict(dir='in', kind='resp' if kind == 1 else 'ind', id=f'{ident:04x}',
                      name=NAMES.get(ident, ''), len=length)
        if kind == 1:
            params = packet[12:]
            record['error'] = packet[10]
            sent = self.sent.pop(struct.unpack_from('<I', packet, 6)[0], None)
            if sent is not None:
                record['ms'] = round((time.monotonic() - sent) * 1000)
        else:
            params = packet[8:]
        found = codes(ident, record['kind'], params)
        if found:
            record['codes'] = found
        if ident in SHAPED:
            record['shape'] = shape(params)
        self.write(record)

    def close(self):
        self.out.close()
