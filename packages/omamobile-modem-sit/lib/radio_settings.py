# SPDX-License-Identifier: MIT
"""Saved, reversible radio settings; the originals are kept in RAM only."""
import struct

from data_call import private_write
from paths import RUN

SAVED_USAGE = RUN / 'original-usage-setting.bin'
SAVED_NR = RUN / 'original-nr-mode.bin'


def nr_mode(client, restore=False):
    # SET_NR_MODE: one byte; GET_NR_MODE returns it. On this phone,
    # changing 3 to 0 returned NR (RAT 21) to LTE (RAT 14) and recovered
    # actual DNS/HTTPS traffic. Preserve the opaque original byte.
    current = client.request(0x0749)
    if len(current) != 1:
        raise RuntimeError('unexpected NR mode response')
    if restore:
        target = SAVED_NR.read_bytes()
        if len(target) != 1:
            raise RuntimeError('invalid saved NR mode')
    else:
        if SAVED_NR.exists():
            # An earlier start-up on this CP (sitd started again in the same
            # boot) already set mode 0 and kept the original: nothing to do.
            # Any other value after that change, or a damaged saved original,
            # is an unknown state: refuse.
            if current == b'\0' and len(SAVED_NR.read_bytes()) == 1:
                print('verified NR mode 0 (set by an earlier start-up this boot)', flush=True)
                return
            raise RuntimeError('NR experiment already active')
        private_write(SAVED_NR, current)
        target = b'\0'
    client.request(0x0748, target, timeout=30)
    if client.request(0x0749) != target:
        raise RuntimeError('NR mode did not reach requested value')
    if restore:
        SAVED_NR.unlink()
    print('verified NR mode', target[0], flush=True)


def usage_setting(client, restore=False):
    # Stock usage-setting handler accepts 1/2 unchanged; the builder sends
    # a u32. Android's UsageSetting defines voice=1, data=2.
    current = client.request(0x0957)
    valid = (struct.pack('<I', 1), struct.pack('<I', 2))
    if current not in valid:
        raise RuntimeError('unexpected usage setting')
    if restore:
        target = SAVED_USAGE.read_bytes()
        if target not in valid:
            raise RuntimeError('invalid saved usage setting')
    else:
        if SAVED_USAGE.exists():
            raise RuntimeError('usage experiment already active')
        private_write(SAVED_USAGE, current)
        target = valid[1]
    client.request(0x0956, target)
    if client.request(0x0957) != target:
        raise RuntimeError('usage setting did not reach requested value')
    if restore:
        SAVED_USAGE.unlink()
    print('verified usage setting', struct.unpack('<I', target)[0], flush=True)
