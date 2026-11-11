# SPDX-License-Identifier: MIT
"""Bounded AoC telephony tuning upload, using the owner's tegu protobufs.

Only the APMg3 telephony component on audio_output_tuning is addressed.
The GPL AoC interface defines CMD_HDR / SET_PARAMETER_BULK; the route
adapter adds an envelope with tag 2 around each unchanged protobuf. No
vendor executable, shared memory mapping, or arbitrary command API.
"""
import os
from pathlib import Path
import select
import struct

from paths import RUN

ROOT = Path('/usr/lib/firmware/updates/omamobile/tegu/aoc')
BULK_SIZE = 16384
HEADER = struct.Struct('<BBHHh')
SET_BULK = 210
UNCERTAIN = RUN / 'aoc-voice-tuning-uncertain'


class TuningError(RuntimeError):
    """Tuning could not be confirmed; keep the call sink muted."""


def package(data, operation):
    if operation not in (19, 20) or not 0 < len(data) <= BULK_SIZE - 12:
        raise TuningError('Invalid AoC telephony tuning package')
    return struct.pack('<HHII', 2, len(data) + 12, operation, len(data)) + data


class VoiceTuning:
    def __init__(self, route, *, root=ROOT):
        if route not in ('speaker', 'earpiece'):
            raise ValueError('Unsupported tegu tuning route')
        device = 'speaker' if route == 'speaker' else 'handset'
        # Load all three before touching any service. An off package is
        # required for cleanup even if the on package is the only big one.
        self.on = self.read(root / f'uplink_{device}_aec_on_config.pb', 19)
        self.off = self.read(root / f'uplink_{device}_aec_off_config.pb', 19)
        self.downlink = self.read(root / f'downlink_{device}_config.pb', 20)
        self.command_fd = self.bulk_fd = None
        self.counter = 0
        self.touched = False
        self.uncertain = False

    @staticmethod
    def read(path, operation):
        with path.open('rb') as source:
            data = source.read(BULK_SIZE + 1)
        return package(data, operation)

    @staticmethod
    def write(fd, packet):
        if not select.select([], [fd], [], 1)[1]:
            raise TuningError('AoC tuning write deadline exceeded')
        # These are service records, not a byte stream: a short write has
        # an unknown outcome, so never send its tail or repeat the record.
        if os.write(fd, packet) != len(packet):
            raise TuningError('Short AoC tuning write')

    def upload(self, data):
        self.counter = (self.counter + 1) & 0xff
        command = HEADER.pack(0, self.counter, 22, SET_BULK, 0)
        command += struct.pack('<BBIII', 19, 24, 0, 0, len(data))
        # Stock stages a full 16 KiB output block; tx_size selects the
        # actual envelope. Never stream a partially written block.
        # Mark before either write. An unknown outcome must not lead to
        # another call replaying or cleaning up on this service blindly.
        self.uncertain = True
        UNCERTAIN.write_text('AoC voice tuning needs attended recovery\n')
        UNCERTAIN.chmod(0o600)
        self.write(self.bulk_fd, data.ljust(BULK_SIZE, b'\0'))
        self.write(self.command_fd, command)
        if not select.select([self.command_fd], [], [], 1)[0]:
            raise TuningError('AoC tuning acknowledgement deadline exceeded')
        reply = os.read(self.command_fd, 4096)
        if len(reply) != len(command) or reply[:6] != command[:6]:
            raise TuningError('Unexpected AoC tuning acknowledgement')
        self.uncertain = False
        UNCERTAIN.unlink()
        if HEADER.unpack_from(reply)[4] != 0:
            raise TuningError('AoC refused telephony tuning')

    def start(self):
        if self.command_fd is not None or self.bulk_fd is not None:
            raise TuningError('AoC tuning session already open')
        if UNCERTAIN.exists():
            self.uncertain = True
            raise TuningError('Previous AoC tuning outcome is unknown; attended recovery required')
        flags = os.O_NONBLOCK | os.O_CLOEXEC
        try:
            self.command_fd = os.open('/dev/acd-audio_output_tuning', os.O_RDWR | flags)
            self.bulk_fd = os.open('/dev/acd-audio_bulk_tx', os.O_WRONLY | flags)
            # Refuse stale responses rather than associating them with a
            # new call's upload. Opening these services is exclusive in ACD.
            if select.select([self.command_fd], [], [], 0)[0]:
                raise TuningError('AoC tuning channel has a pending response')
            self.touched = True
            self.upload(self.on)
            self.upload(self.downlink)
        except BaseException:
            self.close()
            raise

    def close(self):
        try:
            if self.uncertain:
                raise TuningError('AoC tuning outcome unknown; keeping call audio muted')
            if self.touched:
                self.touched = False
                # The telephony component gets the same route's AEC-off
                # package. This is not a restore of an unknown old blob.
                self.upload(self.off)
        finally:
            for name in ('bulk_fd', 'command_fd'):
                fd = getattr(self, name)
                if fd is not None:
                    setattr(self, name, None)
                    os.close(fd)
