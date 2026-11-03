# SPDX-License-Identifier: MIT
"""Minimal cellular IMS registration using an already owned IMS bearer.

Wire fields follow the stock IMS stack's registration adaptor, hidden-menu
builder and ADD_PDN_INFO request. No host SIM authentication or APDUs: the
modem's own IMS stack registers. This announces ordinary voice/SMS
capability; it does not originate a call.
"""
import re
import json
import struct
import time

from data_call import paths, call_ids, pcscf_addresses, private_write
from paths import RUN

REGISTRATION = RUN / 'ims-registration.json'


def record_registration(packet):
    if len(packet) < 20:
        raise ValueError('short IMS registration indication')
    state, features, mask, status, uri_len, reason_len = struct.unpack_from('<BBIHHH', packet, 8)
    if uri_len > 1000 or reason_len > 256 or len(packet) < 20 + uri_len + reason_len:
        raise ValueError('truncated IMS registration indication')
    # The reason is the IMS stack's own words (a SIP or stack failure); the
    # URI before it is the subscriber's identity and is never logged.
    reason = packet[20 + uri_len:20 + uri_len + reason_len].decode('ascii', 'replace').strip('\0 ')
    reason = re.sub(r'\d{7,}', '<n>', re.sub(r'(sip|tel):\S+', '<uri>', reason))
    print(f'IMS registration indication: state {state}, features {features}, status {status}'
          + (f', reason "{reason}"' if reason else ''), flush=True)
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


def add_pdn_payload(response, *, pcscf_required=True, fallback=()):
    if len(response) < 132:
        raise ValueError('short IMS bearer response')
    status, cid, active, pdp = struct.unpack_from('<HBBB', response)
    # IPv6 (2) or IPv4v6 (3) with an IPv6 address: the registration below
    # announces the IPv6 address only.
    if status or cid != 2 or active not in (1, 2) or pdp not in (2, 3) or not any(response[9:25]):
        raise ValueError('active IPv6 IMS bearer required')
    # The base item's three slots, then the 234-byte item's extension (five
    # more): some networks deliver theirs only there. At most three are
    # announced, the count the registration has carried so far.
    pcscf = pcscf_addresses(response)[1][:3]
    # None in the PCO: the ISIM's EF_PCSCF (IPv6, resolved), as stock's
    # addPcscfFromSim. Only used when the PCO has none.
    if not pcscf:
        pcscf = [bytes(a) for a in dict.fromkeys(fallback) if len(a) == 16 and any(a)][:3]
    # Some networks put no P-CSCF in the bearer's PCO (cheetah, 2026-11-02:
    # none in the base slots or the extension, also with the P-CSCF asked
    # for in the attach). Stock's IMS service then takes it from the ISIM
    # (addPcscfFromSim) and doesn't block the PDN on that carrier
    # (BLOCK_PDN_BY_INVALID_PCSCF 0). pcscf_required = no sends ADD_PDN with
    # an empty list and leaves discovery to the modem's IMS stack.
    if not pcscf and pcscf_required:
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


def register(client, *, pcscf_required=True, pcscf_fallback=None):
    """pcscf_fallback(bearer response) -> IPv6 P-CSCF addresses, called only
    when the bearer's PCO has none (isim.ipv6_pcscf)."""
    state_path, response_path = paths(2)
    owned = json.loads(state_path.read_text())
    if owned.get('cid') != 2 or not 0 <= owned.get('session', -1) <= 15:
        raise RuntimeError('IMS bearer ownership missing')
    if 2 not in call_ids(client.request(0x0602)):
        raise RuntimeError('IMS bearer no longer listed')
    response = response_path.read_bytes()
    fallback = ()
    if pcscf_fallback is not None and len(response) >= 132 and not pcscf_addresses(response)[1]:
        print('IMS bearer PCO carries no IPv6 P-CSCF; reading the ISIM\'s EF_PCSCF', flush=True)
        try:
            fallback = pcscf_fallback(response)
        except (RuntimeError, TimeoutError, ValueError) as error:
            # ModemError is a RuntimeError: a card that refuses the read.
            print('P-CSCF from ISIM unavailable:', type(error).__name__, error, flush=True)
    body = add_pdn_payload(response, pcscf_required=pcscf_required, fallback=fallback)
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
