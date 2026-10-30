# SPDX-License-Identifier: MIT
"""Minimal cellular IMS registration using an already owned IMS bearer.

Wire fields follow the stock IMS stack's registration adaptor, hidden-menu
builder and ADD_PDN_INFO request. No host SIM authentication or APDUs: the
modem's own IMS stack registers. This announces ordinary voice/SMS
capability; it does not originate a call.
"""
import configparser
from dataclasses import dataclass
import json
from pathlib import Path
import re
import struct
import time

from data_call import paths, call_ids, private_write
from paths import RUN

REGISTRATION = RUN / 'ims-registration.json'

# The values that registered IMS on a T-Mobile-network MVNO (MODEM-CLIENT
# 1.4). [ims] in modem-sit.conf, or a per-network profile, can replace them;
# these defaults must stay byte-identical (test_ims.py holds their digests).
DEFAULT_HIDDEN_MENU = '523:30 527:30 529:30 531:30 533:30'
# ADD_PDN_INFO flags: hdInternet=17, operator automatic=0, normal
# registration=0, new PDN=1, no auto-configuration (0, 0), voice|SMS|mobile
# offering=35 (16 bits), then 0, 0, 1.
DEFAULT_PDN_FLAGS = '17 0 0 1 0 0 35 0 0 1'
IDENTITY = ((772, 'Google'), (773, 'Pixel 7 Pro'), (775, 'Omarchy Mobile'), (776, 'Linux'),
            (519, 'Google Pixel 7 Pro / Omarchy Mobile'))


@dataclass(frozen=True)
class ImsValues:
    hidden_menu: tuple      # (tag, u32 value) pairs, sent in this order
    pdn_flags: tuple        # the ten ADD_PDN_INFO flag fields
    source: str = 'defaults'


def parse_hidden_menu(text):
    items = []
    for word in text.split():
        match = re.fullmatch(r'(\d{1,5}):(\d{1,10})', word)
        if not match:
            raise ValueError('[ims] hidden_menu: items are TAG:VALUE')
        tag, value = int(match[1]), int(match[2])
        if not 1 <= tag <= 0xffff or value > 0xffffffff:
            raise ValueError('[ims] hidden_menu: tag or value out of range')
        if tag in {t for t, _ in IDENTITY} or tag in {t for t, _ in items}:
            raise ValueError('[ims] hidden_menu: tag repeated or reserved for the identity strings')
        items.append((tag, value))
    if len(items) > 64:
        raise ValueError('[ims] hidden_menu: at most 64 items')
    return tuple(items)


def parse_pdn_flags(text):
    words = text.split()
    if len(words) != 10 or not all(w.isdigit() for w in words):
        raise ValueError('[ims] add_pdn_flags: ten numbers')
    flags = tuple(int(w) for w in words)
    if any(f > 255 for i, f in enumerate(flags) if i != 6) or flags[6] > 0xffff:
        raise ValueError('[ims] add_pdn_flags: value out of range')
    return flags


def values(settings=None, plmn=''):
    """The IMS values to send: [ims] from the config (defaults: the proven
    ones), then, if the registered network has one, its profile
    <profile_dir>/<MCCMNC>.conf ([ims] section, same keys). Profiles stay
    on the phone: they name a network."""
    section = settings['ims'] if settings is not None and settings.has_section('ims') else {}
    hidden = section.get('hidden_menu', DEFAULT_HIDDEN_MENU)
    flags = section.get('add_pdn_flags', DEFAULT_PDN_FLAGS)
    source = 'defaults' if (hidden, flags) == (DEFAULT_HIDDEN_MENU, DEFAULT_PDN_FLAGS) else 'config'
    directory = section.get('profile_dir', '')
    if directory and re.fullmatch(r'\d{5,6}', plmn or ''):
        profile = Path(directory) / f'{plmn}.conf'
        if profile.is_file():
            parser = configparser.ConfigParser(interpolation=None)
            parser.read(profile)
            if parser.has_section('ims'):
                hidden = parser['ims'].get('hidden_menu', hidden)
                flags = parser['ims'].get('add_pdn_flags', flags)
                source = 'network profile'
    return ImsValues(parse_hidden_menu(hidden), parse_pdn_flags(flags), source)


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


def hidden_menu(ims=None):
    # One complete segment. Keep CP's existing carrier/audio defaults;
    # video/RCS and device identifiers are not part of this configuration.
    ims = ims or values()
    items = b''.join(struct.pack('<HI', tag, value) for tag, value in ims.hidden_menu)
    for tag, value in IDENTITY:
        items += struct.pack('<H', tag) + value.encode('ascii') + b'##'
    return struct.pack('<BH', 0, len(items)) + items


def add_pdn_payload(response, ims=None):
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
    # DEFAULT_PDN_FLAGS above says what the proven values mean.
    body += struct.pack('<6BH3B', *(ims or values()).pdn_flags)
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


def register(client, ims=None):
    state_path, response_path = paths(2)
    owned = json.loads(state_path.read_text())
    if owned.get('cid') != 2 or not 1 <= owned.get('session', 0) <= 15:
        raise RuntimeError('IMS bearer ownership missing')
    if 2 not in call_ids(client.request(0x0602)):
        raise RuntimeError('IMS bearer no longer listed')
    ims = ims or values()
    body = add_pdn_payload(response_path.read_bytes(), ims)
    if REGISTRATION.exists():
        raise RuntimeError('IMS registration already attempted; inspect before retry')
    print('IMS values:', ims.source, flush=True)
    client.request(0x0d07, hidden_menu(ims), timeout=30)
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
