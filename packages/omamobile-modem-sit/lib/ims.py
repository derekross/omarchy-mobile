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

from data_call import paths, call_ids, entries, ims_capable, modem_owned_ids, pcscf_addresses, private_write
from paths import RUN

REGISTRATION = RUN / 'ims-registration.json'

# IND_AIMS_REGISTRATION's state byte and status code, as the stock IMS
# service names them (RilIndRegistration.RegState, RegistrationReason's CP
# reason). Status 5 is a permanent failure: stock tears the IMS PDN down
# after it (isNeedPdnDeactivationReason) and doesn't retry on that PDN.
REG_STATES = {1: 'VoLTE not registered', 2: 'VoLTE registered', 3: 'VoLTE limited',
              4: 'E911 not registered', 5: 'E911 registered', 6: 'RCS not registered',
              7: 'RCS registered', 8: 'E911 pseudo-registered'}
REG_STATUS = {0: 'success', 1: 'feature mismatch', 2: 'network-triggered deregistration',
              3: 'no response from the network', 4: 'internal deregistration',
              5: 'registration failed', 6: 'failed with 500', 7: 'failed with 403',
              8: 'failed, CP retrying', 9: 'limited registration', 10: 'failed, retry after cell change',
              11: 'PLMN barred', 12: 'fresh registration starting', 13: 'deregistration failed, call ongoing',
              14: 'failed, start timer', 15: 'failed, retry after Wi-Fi reassociation',
              16: 'failed, retry after RAT change', 18: 'failed, silent retry for a call',
              254: 'no valid SIM', 255: 'unspecified', 512: 'retry after PLMN change'}


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
    print(f'IMS registration indication: state {state} ({REG_STATES.get(state, "unknown")}), '
          f'features {features}, status {status} ({REG_STATUS.get(status, "unknown")})'
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


def oma_dm_menu():
    """Stock's OMA-DM hidden menu (RegistrationAdaptor.sendHiddenMenuOmaDm),
    sent once before the first ADD_PDN_INFO after the SIM loads, on every
    carrier: tag 777 (is-OMA-DM-update) = 1, then the provisioned SVCCFG
    values (tags 778-788). With nothing provisioned the integers are -1 and
    skipped, and the domain's default "IMS" is skipped too; stock's empty
    AMR mode sets (tags 782, 783) are left out here, so the CP keeps its own."""
    items = struct.pack('<HI', 777, 1)
    return struct.pack('<BH', 0, len(items)) + items


def add_pdn_payload(response, *, pcscf_required=True, fallback=(), cid=2):
    """cid: the bearer's CID, 2 for sitd's own IMS bearer, else the CID of the
    modem-owned attach bearer it announces."""
    if len(response) < 132:
        raise ValueError('short IMS bearer response')
    status, bearer_cid, active, pdp = struct.unpack_from('<HBBB', response)
    v4_addr, v6_addr = bytes(response[5:9]), bytes(response[9:25])
    # Stock's ApnEntity.getIpType: IPv4 (1) and IPv6 (2) bits for the
    # addresses the bearer has, so an IPv4v6 bearer (Verizon's IMS APN is
    # IPv4v6 at home) is announced with both. An IPv6 bearer gives 2, as before.
    ip_type = (1 if pdp in (1, 3) and any(v4_addr) else 0) | (2 if pdp in (2, 3) and any(v6_addr) else 0)
    if status or bearer_cid != cid or active not in (1, 2) or pdp not in (1, 2, 3) or not ip_type:
        raise ValueError('active IMS bearer with an address required')
    # The base item's three slots, then the 234-byte item's extension (five
    # more): some networks deliver theirs only there. At most three per
    # family are announced, the count the registration has carried so far
    # (stock allows eight).
    pcscf4, pcscf6 = (lst[:3] for lst in pcscf_addresses(response))
    if not ip_type & 1:
        pcscf4 = []
    if not ip_type & 2:
        pcscf6 = []
    # None in the PCO: the ISIM's EF_PCSCF (IPv6, resolved), as stock's
    # addPcscfFromSim. Only used when the PCO has none.
    if not pcscf4 and not pcscf6 and ip_type & 2:
        pcscf6 = [bytes(a) for a in dict.fromkeys(fallback) if len(a) == 16 and any(a)][:3]
    # Stock never sends ADD_PDN for IMS without a P-CSCF: ApnEntity's
    # handleNetworkAvailable stops the registration ("stop registration for
    # invalid pcscf", NO_PCSCF) whatever BLOCK_PDN_BY_INVALID_PCSCF says (that
    # key only decides whether the PDN is also blocked). Sent with an empty
    # list (pcscf_required = no), cheetah's CP answered at once with state 1,
    # status 5 (2026-11-02). Kept as an explicit opt-in for experiments.
    if not pcscf4 and not pcscf6 and pcscf_required:
        raise ValueError('missing P-CSCF')
    # PDN category IMS=2, then the IP type and the bearer's own addresses.
    body = bytes([2, ip_type]) + (v4_addr if ip_type & 1 else bytes(4)) \
        + (v6_addr if ip_type & 2 else bytes(16))
    # hdInternet=17, operator automatic=0, normal registration=0, new PDN=1,
    # no auto-configuration; voice|SMS|mobile offering=35.
    body += struct.pack('<6BH3B', 17, 0, 0, 1, 0, 0, 35, 0, 0, 1)
    body += bytes(6) + bytes([len(pcscf4)]) + b''.join(pcscf4)
    body += bytes([len(pcscf6)]) + b''.join(pcscf6)
    # Primary then secondary DNS, each IPv4 then IPv6 (base item: IPv4 at
    # 0x1a and 0x2e, IPv6 at 0x1e and 0x32), only for the families in use.
    for v4_at, v6_at in ((0x1a, 0x1e), (0x2e, 0x32)):
        body += bytes(response[v4_at:v4_at + 4]) if ip_type & 1 else bytes(4)
        body += bytes(response[v6_at:v6_at + 16]) if ip_type & 2 else bytes(16)
    # Wi-Fi-only location fields and emergency timer stay zero on cellular.
    body += bytes(23 + 4 + 10 + 4 + 2 + 4 + 1 + 32)
    # The stock encoder always appends a fixed 500-byte extension buffer.
    body += struct.pack('<H', 12) + struct.pack('<HHQ', 1, 8, 0) + bytes(488)
    return body


def start_stack(client):
    # Stock stack control: physical slot 0 -> stack 1, SIM ready -> 1.
    client.request(0x0d39, b'\x01\x01', timeout=30)


def attach_bearer_item(client, found):
    """The modem-owned attach bearer found by start-up, checked against the
    data-call list right before ADD_PDN_INFO: still listed, active and with
    the same IPv6 address. The listed item is used when it carries the
    P-CSCF itself, else the one found (an IND_DATA_CALL_LIST_CHANGED item).
    Nothing about the bearer is claimed."""
    cid = found[2]
    if cid not in modem_owned_ids():
        raise RuntimeError('the attach bearer is not recorded as modem-owned')
    item = next((i for i in entries(client.request(0x0602)) if i[2] == cid), None)
    if item is None or item[3] not in (1, 2) or item[9:25] != found[9:25]:
        raise RuntimeError('the modem-owned attach bearer is no longer listed as found')
    return item if ims_capable(item) else found


def register(client, *, pcscf_required=True, pcscf_fallback=None, attach=None):
    """pcscf_fallback(bearer response) -> IPv6 P-CSCF addresses, called only
    when the bearer's PCO has none (isim.ipv6_pcscf).

    attach: the data-call item of the modem-owned attach bearer
    (bringup.find_attach_bearer), announced instead of sitd's own CID 2, as
    stock's IMS service announced the attach bearer the carrier profile
    brought up. It is checked against the data-call list first."""
    if attach is not None:
        response = attach_bearer_item(client, attach)
        cid = response[2]
        print('IMS on the modem-owned attach bearer CID', cid, flush=True)
    else:
        state_path, response_path = paths(2)
        owned = json.loads(state_path.read_text())
        if owned.get('cid') != 2 or not 0 <= owned.get('session', -1) <= 15:
            raise RuntimeError('IMS bearer ownership missing')
        if 2 not in call_ids(client.request(0x0602)):
            raise RuntimeError('IMS bearer no longer listed')
        response, cid = response_path.read_bytes(), 2
    fallback = ()
    if pcscf_fallback is not None and len(response) >= 132 and not any(pcscf_addresses(response)):
        print('IMS bearer PCO carries no P-CSCF; reading the ISIM\'s EF_PCSCF', flush=True)
        try:
            fallback = pcscf_fallback(response)
        except (RuntimeError, TimeoutError, ValueError) as error:
            # ModemError is a RuntimeError: a card that refuses the read.
            print('P-CSCF from ISIM unavailable:', type(error).__name__, error, flush=True)
    body = add_pdn_payload(response, pcscf_required=pcscf_required, fallback=fallback, cid=cid)
    if REGISTRATION.exists():
        raise RuntimeError('IMS registration already attempted; inspect before retry')
    client.request(0x0d07, hidden_menu(), timeout=30)
    time.sleep(0.05)
    # Stock: the OMA-DM menu right before the first ADD_PDN after SIM load.
    client.request(0x0d07, oma_dm_menu(), timeout=30)
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
