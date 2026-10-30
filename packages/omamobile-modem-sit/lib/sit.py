#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Single-owner SIT IPC0 transport for the S5300 (CPIF /dev/umts_ipc0).

Every request goes through two guards: a fixed allow-list of the requests
this stack sends (each one used on this phone with its stock layout), and
the do-not-send list of device/cheetah/MODEM-SIT-RESEARCH.md section 5 (NV,
identity, carrier lock, AT forwarding, VSIM and satellite), so an edit to
the allow-list can't let one of those through. Dial and outgoing SMS are
refused unless the owner was opened for them.
"""
from collections import deque
import fcntl
import os
import select
import struct
import time

from paths import IPC, RUN, open_channel, private_dir
from sit_names import NAMES

# Data/radio/IMS lifecycle, display state, read-only status, and incoming SMS
# ACK. No SIM I/O, PIN, subscription, APDU or vendor NV requests.
ALLOWED = {0x0000, 0x0102, 0x0108, 0x0200, 0x0600, 0x0601, 0x0602, 0x0603, 0x0613,
           0x061a, 0x061b, 0x0625, 0x0700, 0x0701, 0x0702, 0x0703, 0x0704, 0x070a,
           0x070b, 0x0710, 0x0711, 0x0800, 0x0801, 0x0748, 0x0749, 0x0750, 0x0902,
           0x091b, 0x0928, 0x0930, 0x0953, 0x0956, 0x0957, 0x0d07, 0x0d08, 0x0d1d,
           0x0d38, 0x0d39, 0x0d3a}
SMS = {0x0d1b}                              # AIMS_SEND_SMS
CALLS = {0x0d00, 0x0d02, 0x0d03, 0x0d0a}    # AIMS_DIAL, _ANSWER, _HANGUP, _SEND_DTMF
# VERIFY_SIM_PIN only: never PUK, PIN2, PIN change or the lock itself
# (CHG_SIM_PIN* and SET_FACILITY_LOCK are on the do-not-send list).
PIN = {0x0201}

# The research note's do-not-send list, by name, plus the VSIM (0x0e) and
# satellite (0x13) families.
DENIED_NAMES = frozenset({
    'SET_RADIO_NODE_VALUE', 'SET_RADIO_NODE', 'EXEC_RADIO_NODE', 'SET_CFG_DEFAULT',
    'SET_ENG_MODE', 'SET_ENG_STRING_INPUT', 'SET_SELFLOG', 'SET_SELFLOG_PROFILE',
    'SET_MODEM_LOG_DUMP', 'SET_CARRIER_INFO_IMSI_ENCRYPTION', 'SET_CARRIER_RESTRICTIONS',
    'SET_CARRIER_RESTRICTIONS_V2', 'OEM_SET_CARRIER_CONFIG_MANIFEST', 'SET_SIM_CARD_POWER',
    'SET_FACILITY_LOCK', 'CHG_SIM_PIN', 'CHG_SIM_PIN2', 'VERIFY_NETWORK_LOCK',
    'SET_FORWARDING_AT_COMMAND', 'SET_SATELLITE_MODE_SERVICE', 'SET_SATELLITE_PLMN_LIST',
})
DENIED_FAMILIES = (0x0e, 0x13)
DENIED = frozenset(i for i, n in NAMES.items()
                   if n in DENIED_NAMES or (i >> 8) in DENIED_FAMILIES)


def name(ident):
    return NAMES.get(ident, f'0x{ident:04x}')


class ModemError(RuntimeError):
    def __init__(self, error, payload):
        super().__init__('modem rejected request with error ' + str(error))
        self.error = error
        self.payload = payload  # private; never include payload in str/repr


def check(ident, *, sms=False, calls=False, pin=False):
    if ident in DENIED or (ident >> 8) in DENIED_FAMILIES:
        raise ValueError('request on the do-not-send list')
    if not (ident in ALLOWED or (sms and ident in SMS) or (calls and ident in CALLS) or (pin and ident in PIN)):
        raise ValueError('request outside the allow-list')


class Sit:
    tracer = None   # see __init__

    def __init__(self, *, allow_sms=False, allow_calls=False, allow_pin=False, device=None):
        self.allow_sms = allow_sms
        self.allow_calls = allow_calls
        self.allow_pin = allow_pin
        private_dir(RUN)
        self.lock = os.open(RUN / 'ipc0.lock', os.O_CREAT | os.O_RDWR | os.O_CLOEXEC, 0o600)
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.fd = open_channel(device or IPC)
        except BaseException:
            os.close(self.lock)
            raise
        self.token = int.from_bytes(os.urandom(4), 'little') & 0x7fffffff
        self.buffer = bytearray()
        self.indications = deque()
        # sit_trace.Tracer when [trace] record = yes: IDs, lengths and codes only.
        self.tracer = None

    def close(self):
        if self.tracer is not None:
            self.tracer.close()
        os.close(self.fd)
        os.close(self.lock)

    def read_packet(self, timeout):
        deadline = time.monotonic() + timeout
        while True:
            if len(self.buffer) >= 6:
                kind, _, _, length = struct.unpack_from('<BBHH', self.buffer)
                if kind not in (1, 2) or not (8 if kind == 2 else 12) <= length <= 32768:
                    raise RuntimeError('invalid SIT framing')
                if len(self.buffer) >= length:
                    packet = bytes(self.buffer[:length])
                    del self.buffer[:length]
                    if self.tracer is not None:
                        self.tracer.incoming(packet)
                    return packet
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            ready, _, _ = select.select([self.fd], [], [], remaining)
            if not ready:
                return None
            try:
                chunk = os.read(self.fd, 65536)
            except BlockingIOError:
                continue
            if not chunk:
                raise EOFError('SIT channel closed')
            self.buffer.extend(chunk)
            if len(self.buffer) > 65536:
                raise RuntimeError('SIT receive limit exceeded')

    def request(self, ident, payload=b'', timeout=8):
        check(ident, sms=getattr(self, 'allow_sms', False),
              calls=getattr(self, 'allow_calls', False), pin=getattr(self, 'allow_pin', False))
        self.token = (self.token + 1) & 0xffffffff
        data = struct.pack('<BBHHIBB', 0, 0, ident, 12 + len(payload), self.token, 0, 0) + payload
        if self.tracer is not None:
            self.tracer.request(ident, self.token, len(data))
        if os.write(self.fd, data) != len(data):
            raise RuntimeError('short SIT write')
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            packet = self.read_packet(deadline - time.monotonic())
            if packet is None:
                break
            kind, _, message, length = struct.unpack_from('<BBHH', packet)
            if kind == 2:
                # Physical-channel and signal-strength reports are snapshots.
                # Retain the latest of each during long requests so frequent
                # telemetry cannot exhaust the queue ahead of an SMS reply.
                # SMS, calls, registration and all other events keep FIFO order.
                if message in (0x0742, 0x0906):
                    for old in self.indications:
                        if struct.unpack_from('<H', old, 2)[0] == message:
                            self.indications.remove(old)
                            break
                if len(self.indications) >= 256:
                    raise RuntimeError('unprocessed indication limit exceeded')
                self.indications.append(packet)
            elif message == ident and struct.unpack_from('<I', packet, 6)[0] == self.token:
                print(f'SIT {name(ident)}: error={packet[10]} length={length}', flush=True)
                if packet[10]:
                    raise ModemError(packet[10], packet[12:])
                return packet[12:]
        raise TimeoutError(f'SIT {name(ident)}')

    def next_indication(self, timeout=1):
        if self.indications:
            return self.indications.popleft()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            packet = self.read_packet(deadline - time.monotonic())
            if packet is None or packet[0] == 2:
                return packet
        return None
