# SPDX-License-Identifier: MIT
"""Minimal cellular IMS registration using an already owned IMS bearer.

Wire fields follow the stock IMS stack's registration adaptor, hidden-menu
builder and ADD_PDN_INFO request. No host SIM authentication or APDUs: the
modem's own IMS stack registers. This announces ordinary voice/SMS
capability; it does not originate a call.
"""
import json
import struct
import time

from data_call import paths, call_ids, private_write
from paths import RUN

REGISTRATION = RUN / 'ims-registration.json'


def record_registration(packet):
    if len(packet) < 20:
        raise ValueError('short IMS registration indication')
    state, features, mask, status, uri_len, reason_len = struct.unpack_from('<BBIHHH', packet, 8)
    if uri_len > 1000 or reason_len > 256 or len(packet) < 20 + uri_len + reason_len:
        raise ValueError('truncated IMS registration indication')
    if REGISTRATION.exists():
        private_write(REGISTRATION, json.dumps({'state': state, 'features': features,
                      'feature_mask': mask, 'status': status}).encode())
    return state, features, mask, status


def require_sms_registration():
    registration = json.loads(REGISTRATION.read_text())
    if registration.get('state') != 2 or not registration.get('features', 0) & 2:
        raise RuntimeError('ordinary IMS SMS registration has not been observed')


def hidden_menu():
    # One complete segment. Keep CP's existing carrier/audio defaults;
    # video/RCS and device identifiers are not part of this configuration.
    items = b''.join(struct.pack('<HI', tag, 30) for tag in (523, 527, 529, 531, 533))
    for tag, value in ((772, 'Google'), (773, 'Pixel 7 Pro'),
                       (775, 'Omarchy Mobile'), (776, 'Linux'),
                       (519, 'Google Pixel 7 Pro / Omarchy Mobile')):
        items += struct.pack('<H', tag) + value.encode('ascii') + b'##'
    return struct.pack('<BH', 0, len(items)) + items


def add_pdn_payload(response):
    if len(response) < 132:
        raise ValueError('short IMS bearer response')
    status, cid, active, pdp = struct.unpack_from('<HBBB', response)
    if status or cid != 2 or active not in (1, 2) or pdp != 2 or not any(response[9:25]):
        raise ValueError('active IPv6 IMS bearer required')
    if response[0x42] not in (2, 3):
        raise ValueError('IPv6 P-CSCF configuration required')
    pcscf = list(dict.fromkeys(bytes(response[i:i+16]) for i in (0x4f, 0x5f, 0x6f)
                              if any(response[i:i+16])))
    if not pcscf:
        raise ValueError('missing IPv6 P-CSCF')
    # PDN category IMS=2; IP type IPv6=2. Native CP uses its own SIM stack.
    body = bytes([2, 2]) + bytes(4) + bytes(response[9:25])
    # hdInternet=17, operator automatic=0, normal registration=0, new PDN=1,
    # no auto-configuration; voice|SMS|mobile offering=35.
    body += struct.pack('<6BH3B', 17, 0, 0, 1, 0, 0, 35, 0, 0, 1)
    body += bytes(6) + bytes([0, len(pcscf)]) + b''.join(pcscf)
    body += bytes(4) + bytes(response[0x1e:0x2e])
    body += bytes(4) + bytes(response[0x32:0x42])
    # Wi-Fi-only location fields and emergency timer stay zero on cellular.
    body += bytes(23 + 4 + 10 + 4 + 2 + 4 + 1 + 32)
    # The stock encoder always appends a fixed 500-byte extension buffer.
    body += struct.pack('<H', 12) + struct.pack('<HHQ', 1, 8, 0) + bytes(488)
    return body


def start_stack(client):
    # Stock stack control: physical slot 0 -> stack 1, SIM ready -> 1.
    client.request(0x0d39, b'\x01\x01', timeout=30)


def register(client):
    state_path, response_path = paths(2)
    owned = json.loads(state_path.read_text())
    if owned.get('cid') != 2 or not 0 <= owned.get('session', -1) <= 15:
        raise RuntimeError('IMS bearer ownership missing')
    if 2 not in call_ids(client.request(0x0602)):
        raise RuntimeError('IMS bearer no longer listed')
    body = add_pdn_payload(response_path.read_bytes())
    if REGISTRATION.exists():
        raise RuntimeError('IMS registration already attempted; inspect before retry')
    client.request(0x0d07, hidden_menu(), timeout=30)
    time.sleep(0.05)
    private_write(REGISTRATION, b'{"outcome":"pending or unknown"}')
    client.request(0x0d08, body, timeout=30)
    private_write(REGISTRATION, b'{"outcome":"ADD_PDN accepted; awaiting registration"}')
    print('IMS PDN information accepted; awaiting registration indication', flush=True)


def unregister(client):
    if not REGISTRATION.exists():
        raise RuntimeError('no owned IMS registration attempt')
    # Stock DelPdnInfo: cellular transport=1, IMS category=2, reason=0.
    client.request(0x0d38, bytes([1, 2, 0]), timeout=30)
    REGISTRATION.unlink()
    print('IMS PDN notification removed; bearer remains owned', flush=True)
