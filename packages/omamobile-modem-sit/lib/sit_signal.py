# SPDX-License-Identifier: MIT
"""Signal strength from IND_SIGNAL_STRENGTH (0x0906), read passively: no
request is sent for it (the modem reports about every 1.25 s while the
screen is on; GET_SIGNAL_STRENGTH stays off the allow-list).

Layout, from the stock codec's parsers (MODEM-SIT-RESEARCH 3.4): the
parameters start with a u16 RAT-presence mask, then a body of signed 32-bit
fields at fixed offsets, INT_MAX where a value is absent. Values are in
Android's convention: LTE RSRP and RSRQ as positive magnitudes (44-150,
3-20), RSSNR in 0.1 dB, the LTE "signal strength" as 0-31 (ASU); NR SS-RSRP
44-140, SS-RSRQ and SS-SINR signed.

**Unconfirmed on hardware:** stock picks the body layout from a version the
modem announces in its SET_DEVICE_INFO response (which our RIL never sends:
the stock default is V2); here it is chosen by the body's length, which the
stock parsers require as a minimum: 60+ bytes V1, 108+ V2, 196+ V4 (V5 is
V4 plus NR timing advance at 200). Which one this firmware sends, and that
its values land at these offsets, is MODEM-PLAN's read-only check A8
(the [trace] record shows the body length and which offsets are filled).
Anything outside the ranges stock accepts reads as absent.
"""
import struct

INT_MAX = 0x7fffffff
# layout: (minimum body length, LTE mask bits, LTE (ss, rsrp, rsrq, rssnr)
# offsets, NR mask bit, NR (ss-rsrp, ss-rsrq, ss-sinr) offsets or None)
LAYOUTS = (
    ('v4', 196, 0x84, (0x3c, 0x40, 0x44, 0x48), 0x40, (0x58, 0x5c, 0x60)),
    ('v2', 108, 0x04, (0x3c, 0x40, 0x44, 0x48), 0x40, (0x54, 0x58, 0x5c)),
    ('v1', 60, 0x08, (0x1c, 0x20, 0x24, 0x28), 0, None),
)


def field(body, offset):
    value = struct.unpack_from('<i', body, offset)[0]
    return None if value == INT_MAX else value


def within(value, low, high):
    return value if value is not None and low <= value <= high else None


def decode(params):
    """{'layout', 'lte': {...}, 'nr': {...}} in dBm/dB, or None when the
    message fits no known layout. Absent RATs and fields are left out."""
    if len(params) < 2:
        return None
    mask = struct.unpack_from('<H', params)[0]
    body = params[2:]
    for name, minimum, lte_bits, lte, nr_bit, nr in LAYOUTS:
        if len(body) < minimum:
            continue
        out = dict(layout=name)
        if mask & lte_bits:
            ss, rsrp, rsrq, snr = (field(body, o) for o in lte)
            values = dict(rssi=None if within(ss, 0, 31) is None else -113 + 2 * ss,
                          rsrp=None if within(rsrp, 44, 150) is None else -rsrp,
                          rsrq=None if within(rsrq, 3, 20) is None else -rsrq,
                          snr=None if snr is None or not -300 <= snr <= 500 else snr / 10)
            values = {k: v for k, v in values.items() if v is not None}
            if values:
                out['lte'] = values
        if nr and mask & nr_bit:
            rsrp, rsrq, sinr = (field(body, o) for o in nr)
            values = dict(rsrp=None if within(rsrp, 44, 140) is None else -rsrp,
                          rsrq=None if within(rsrq, -20, 43) is None else -rsrq,
                          snr=within(sinr, -23, 40))
            values = {k: v for k, v in values.items() if v is not None}
            if values:
                out['nr'] = values
        return out
    return None


def quality(decoded, tech=''):
    """MM's SignalQuality percentage: RSRP -125 dBm (0 %) to -75 dBm (100 %),
    NR's when registered on NR, else LTE's; 0 when unknown."""
    if not decoded:
        return 0
    order = ('nr', 'lte') if tech.startswith('NR') else ('lte', 'nr')
    for rat in order:
        rsrp = decoded.get(rat, {}).get('rsrp')
        if rsrp is not None:
            return max(0, min(100, round((rsrp + 125) * 2)))
    return 0
