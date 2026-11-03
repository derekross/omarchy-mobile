# SPDX-License-Identifier: MIT
"""Data-call layouts (the stock 983-byte version-2 setup request) and an
owned bearer lifecycle: CID 1 (internet) and CID 2 (IMS). Stock names a
bearer's device rmnet<CID - 1>; data_network.find_device checks which device
really carries the internet bearer (it differed when the attach bearer was on
another APN).

A bearer the modem brings up on its own (the attach bearer, with attach_apn
= none) is recorded in MODEM_OWNED only: sitd never sets up, claims or
releases its CID.

The APN comes from /etc/omamobile/modem-sit.conf. Ownership is recorded in
RAM before a setup is sent: a setup or release with an unknown outcome
keeps its record, and nothing is retried blindly.

A cellular setup carries no PDU session ID (0), as stock's does: Android's
data stack reserves one (ALLOC_PDU_SESSION) only for a bearer carried over
Wi-Fi (IWLAN), and stock's builder copies the framework's value into the
request unchanged, so on LTE and NR the modem picks the ID itself. Records
from 0.3.4 and earlier hold an allocated ID, which deactivate() still
releases.
"""
import json
import os
from pathlib import Path
import re
import struct
import time

from paths import RUN
from sit_names import NAMES

STATE = RUN / 'data-session.json'
RESPONSE = RUN / 'data-call-response.bin'
# IP types in SETUP_DATA_CALL and the data profile.
IP_TYPES = {'ipv4': 1, 'ipv6': 2, 'ipv4v6': 3}


def paths(cid):
    if cid == 1:
        return STATE, RESPONSE
    if cid == 2:
        return STATE.with_name('ims-session.json'), RESPONSE.with_name('ims-response.bin')
    raise ValueError('unsupported bearer CID')


def pcscf_addresses(response):
    """The P-CSCF addresses of a setup response or data-call item, as stock's
    ProtocolPsSetupDataCallAdapter reads them: the base item's family byte at
    0x42 (1 IPv4, 2 IPv6, 3 both), three IPv4 at 0x43 and three IPv6 at 0x4f;
    then, when the item is longer than the 132-byte base and its extension
    version byte at 0x84 is 2 or more, five IPv4 at 0x86 and five IPv6 at
    0x9a (the 234-byte item). Empty slots are skipped, duplicates dropped.
    Returns (IPv4 list, IPv6 list) of raw addresses; never log the values."""
    v4, v6 = [], []
    if len(response) >= 132:
        family = response[0x42]
        if family in (1, 3):
            v4 += [bytes(response[i:i + 4]) for i in (0x43, 0x47, 0x4b)]
        if family in (2, 3):
            v6 += [bytes(response[i:i + 16]) for i in (0x4f, 0x5f, 0x6f)]
    if len(response) >= 0xea and response[0x84] >= 2:
        v4 += [bytes(response[i:i + 4]) for i in range(0x86, 0x9a, 4)]
        v6 += [bytes(response[i:i + 16]) for i in range(0x9a, 0xea, 16)]
    return ([a for a in dict.fromkeys(v4) if any(a)],
            [a for a in dict.fromkeys(v6) if any(a)])


def check_apn(apn):
    """An APN as a carrier publishes it: labels of letters, digits and '-',
    joined by dots, at most 99 characters (the request's field is 100 bytes)."""
    if not isinstance(apn, str) or not re.fullmatch(r'[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*', apn) \
            or len(apn) > 99:
        raise ValueError('APN missing or not a plain carrier APN; set [network] apn')
    return apn


def entries(payload):
    """The items of a GET_DATA_CALL_LIST response or IND_DATA_CALL_LIST_CHANGED
    payload: a count byte, then that many items of one size, each laid out as
    a SETUP_DATA_CALL response (status u16, CID, active, PDP type, addresses,
    DNS, P-CSCF; pcscf_addresses). Stock DataCallUtil::DetermineDCTypeBySize.
    Reject variable traffic-descriptor records until their full framing is
    implemented."""
    if not payload or payload[0] > 15:
        raise RuntimeError('invalid data-call list')
    count = payload[0]
    if count == 0:
        if len(payload) != 1:
            raise RuntimeError('unexpected empty data-call list')
        return []
    size, remainder = divmod(len(payload) - 1, count)
    if remainder or size not in (132, 234, 239, 246, 280, 292):
        raise RuntimeError('unsupported data-call list layout')
    items = [bytes(payload[1 + index * size:1 + (index + 1) * size]) for index in range(count)]
    cids = [item[2] for item in items]
    if len(set(cids)) != count or any(not 1 <= cid <= 15 for cid in cids):
        raise RuntimeError('invalid or duplicate data-call CID')
    return items


def call_ids(payload):
    return {item[2] for item in entries(payload)}


def dns_count(item):
    """The DNS servers an item carries (IPv4 at 0x1a and 0x2e, IPv6 at 0x1e
    and 0x32): a count only, for the log."""
    return sum(1 for at, size in ((0x1a, 4), (0x2e, 4), (0x1e, 16), (0x32, 16))
               if any(item[at:at + size]))


def summary(item):
    """One data-call item for the log: CID, PDP type, active, P-CSCF and DNS
    counts. Never an address."""
    v4, v6 = pcscf_addresses(item)
    pdp = {1: 'IPv4', 2: 'IPv6', 3: 'IPv4v6'}.get(item[4], f'type {item[4]}')
    return (f'CID {item[2]} {pdp} status {struct.unpack_from("<H", item)[0]} active {item[3]} '
            f'P-CSCF {len(v4) + len(v6)} DNS {dns_count(item)}')


# The bearers the modem brought up on its own (the attach bearer with the
# carrier profile's settings): recorded so that sitd's ownership checks know
# them, and never deactivated or claimed (no ownership record, no release).
MODEM_OWNED = RUN / 'modem-owned-bearers.json'


def modem_owned_ids():
    if not MODEM_OWNED.exists():
        return set()
    cids = json.loads(MODEM_OWNED.read_text()).get('modem-owned', [])
    if not isinstance(cids, list) or any(not isinstance(c, int) or not 1 <= c <= 15 for c in cids):
        raise RuntimeError('invalid modem-owned bearer record')
    return set(cids)


def record_modem_owned(cids):
    """Add CIDs to the modem-owned record. A CID sitd owns is refused."""
    cids = set(cids)
    if cids & owned_ids():
        raise RuntimeError('a bearer sitd owns cannot be recorded as modem-owned')
    known = modem_owned_ids()
    if cids - known:
        private_write(MODEM_OWNED, json.dumps({'modem-owned': sorted(known | cids)}).encode())
        for cid in sorted(cids - known):
            print(f'data bearer CID {cid} recorded as modem-owned (never released by sitd)', flush=True)


def ims_capable(item):
    """An active IPv6 or IPv4v6 bearer with its IPv6 address and at least one
    P-CSCF address: what stock's IMS service announced from the attach bearer."""
    status, _, active, pdp = struct.unpack_from('<HBBB', item)
    return (not status and active in (1, 2) and pdp in (2, 3) and any(item[9:25])
            and any(pcscf_addresses(item)))


def attach_bearer(items, owned=None):
    """The first IMS-capable item sitd didn't set up (its CID has no
    ownership record), or None."""
    owned = owned_ids() if owned is None else owned
    return next((item for item in items if item[2] not in owned and ims_capable(item)), None)


def owned_ids():
    result = set()
    for cid in (1, 2):
        state, _ = paths(cid)
        if state.exists():
            owned = json.loads(state.read_text())
            # session 0: no PDU session ID was sent (the modem chose one).
            if owned.get('cid') != cid or not 0 <= owned.get('session', -1) <= 15:
                raise RuntimeError('invalid bearer ownership record')
            result.add(cid)
    return result


def private_write(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_CLOEXEC, 0o600)
    with os.fdopen(fd, 'wb') as out:
        out.write(data)


def setup_payload(cid, radio_technology, pdu_session, apn, *, ims=False, ip_type=None):
    # Absolute request offsets below include the 12-byte request header.
    # ip_type None: IPv6 for IMS (what every IMS setup used until 0.3.19),
    # IPv4v6 otherwise. For IMS, stock takes the PDP type from the IMS APN's
    # protocol and the P-CSCF request from it (GetPcscfReqType).
    if ip_type is None:
        ip_type = 'ipv6' if ims else 'ipv4v6'
    check_apn(apn)
    full = bytearray(983)
    full[12] = cid
    full[13] = radio_technology
    full[14] = 0  # stock converter: only tethering maps to 1
    full[15] = 1 if ims else 0  # IMS/default APN type
    encoded = apn.encode('ascii')
    full[16:16 + len(encoded)] = encoded
    full[0xd9] = 0  # no authentication
    full[0xda] = IP_TYPES[ip_type]
    full[0xdb] = PCSCF_REQUEST[ip_type] if ims else 0  # P-CSCF request (IPv6 2, both 3)
    # No handover addresses, roaming override or slice.
    # 0xf1 (u32): the APN-type bitmap, as stock's builder copies it from
    # ApnSetting's supported types (vendor.radio.base
    # ApnSetting::SetSupportedTypesBitmask, member +0x160; the 983-byte
    # builder writes it at 0xf1). DEFAULT for the internet bearer, IMS for
    # the IMS one. Until 0.3.6 this was sent as 0 (taken for an MTU), and
    # the 9a's modem answered every internet setup with status 36.
    struct.pack_into('<I', full, 0xf1, 0x40 if ims else 1)
    full[0xf5] = 2  # stock caller selects the v3/983-byte form
    # 0 on cellular: no PDU session ID, the modem picks one (module docstring).
    struct.pack_into('<i', full, 0xf6, pdu_session)
    # No requested network slice: SST 0, SD -1, mapped SST 0, mapped SD -1.
    struct.pack_into('<i', full, 0xfc, -1)
    struct.pack_into('<i', full, 0x101, -1)
    full[0x105] = 1  # match-all rule allowed, no traffic descriptor supplied
    return bytes(full[12:])


# The P-CSCF request type, as stock's GetPcscfReqType maps the APN protocol:
# IP 1, IPV6 2, IPV4V6 3.
PCSCF_REQUEST = {'ipv4': 1, 'ipv6': 2, 'ipv4v6': 3}


def initial_attach(client, apn, ip_type='ipv4v6', *, ims=False):
    """SET_INITIAL_ATTACH_APN (251 bytes). Without it, setup requests on this
    phone returned status 36 and no bearer.

    ims: the attach APN is the IMS APN (a network that attaches only there).
    Stock's builder then writes the APN type at 0x0f and asks for the P-CSCF
    at 0xdb (home) and 0xf9 (roaming) with GetPcscfReqType, so the network
    returns its P-CSCF addresses in the attach bearer's PCO; without the
    request, IMS on that bearer has none."""
    attach = bytearray(251)
    attach[12:245] = setup_payload(1, 14, 0, apn, ip_type=ip_type)[:233]
    # Stock's attach builder leaves 0xf1-0xf4 zero: no APN-type bitmap here.
    attach[0xf1:0xf5] = bytes(4)
    attach[0xf8] = IP_TYPES[ip_type]  # the roaming PDP type (the home type is 0xda)
    if ims:
        attach[0x0f] = 1  # IMS APN type, as in the IMS setup request
        attach[0xdb] = attach[0xf9] = PCSCF_REQUEST[ip_type]
    client.request(0x0603, bytes(attach[12:]), timeout=30)


def allow_data(client):
    previous = client.request(0x0711)
    print('PS service permission before', previous[0] if len(previous) == 1 else 'unexpected', flush=True)
    client.request(0x0625, b'\x01\x00')
    client.request(0x0710, b'\x01')
    if client.request(0x0711) != b'\x01':
        raise RuntimeError('PS service permission is not enabled')
    print('PS service permission enabled', flush=True)


# SET_DATA_PROFILE's APN-type bitmask (Android's ApnSetting TYPE_*_BITMASK).
APN_TYPES = {'default': 1, 'mms': 2, 'supl': 4, 'dun': 8, 'hipri': 16, 'fota': 32,
             'ims': 64, 'cbs': 128, 'ia': 256, 'emergency': 512, 'mcx': 1024, 'xcap': 2048}
# Android's profile IDs: 0 default (internet), 1 tethered, 2 IMS, 3 FOTA,
# 4 CBS; OEM profiles start at 1000.
PROFILE_IDS = 'a profile ID 0-4, or 1000 and up'
PROFILE_KEYS = ('types', 'ip', 'roaming_ip')


class Profile:
    """One modem-managed data profile, as stock's BuildSetDataProfile sends it.
    The defaults are stock's: 20 connections in 300 s, no wait, enabled, any
    bearer, no authentication."""

    def __init__(self, ident, apn, types, ip='ipv4v6', roaming_ip=None, *,
                 max_conns=20, max_conns_time=300, wait_time=0):
        if not (0 <= ident <= 4 or 1000 <= ident <= 0x7fffffff):
            raise ValueError(f'profile ID {ident}: not {PROFILE_IDS}')
        if not types or types & ~sum(APN_TYPES.values()):
            raise ValueError(f'profile {ident}: invalid APN types')
        roaming_ip = roaming_ip or ip
        for value in (ip, roaming_ip):
            if value not in IP_TYPES:
                raise ValueError(f'profile {ident}: IP type {value!r} is not ipv4, ipv6 or ipv4v6')
        self.ident, self.apn, self.types = ident, check_apn(apn), types
        self.ip, self.roaming_ip = ip, roaming_ip
        self.max_conns, self.max_conns_time, self.wait_time = max_conns, max_conns_time, wait_time

    def __eq__(self, other):
        return isinstance(other, Profile) and vars(self) == vars(other)

    def __repr__(self):
        return f'Profile({self.ident}, {self.apn!r}, types=0x{self.types:x})'

    def type_names(self):
        return ','.join(n for n, bit in APN_TYPES.items() if self.types & bit)


def default_profile(apn, ip_type='ipv4v6'):
    """Profile 0 from [network] apn, byte for byte what 0.3.14 and earlier
    sent (the connection limits and wait left 0): the default profile that
    registered and carried data on both phones."""
    return Profile(0, apn, APN_TYPES['default'], ip_type, max_conns=0, max_conns_time=0)


def parse_profile(key, value):
    """A [profiles] line: "ID = APN; types=a,b; ip=TYPE; roaming_ip=TYPE".
    types is required; ip defaults to ipv4v6 and roaming_ip to ip."""
    try:
        ident = int(key.strip(), 10)
    except ValueError:
        raise ValueError(f'profile {key!r}: the key must be {PROFILE_IDS}') from None
    apn, *fields = [part.strip() for part in value.split(';')]
    options = {}
    for field in fields:
        name, sep, item = (x.strip() for x in field.partition('='))
        name = name.lower()
        if not sep or name not in PROFILE_KEYS or not item:
            raise ValueError(f'profile {ident}: {field!r} is not one of '
                             + ', '.join(k + '=...' for k in PROFILE_KEYS))
        if name in options:
            raise ValueError(f'profile {ident}: {name} given twice')
        options[name] = item.lower()
    if 'types' not in options:
        raise ValueError(f'profile {ident}: types=... is required')
    types = 0
    for name in options.pop('types').split(','):
        name = name.strip()
        if name not in APN_TYPES:
            raise ValueError(f'profile {ident}: unknown APN type {name!r}')
        types |= APN_TYPES[name]
    try:
        check_apn(apn)
    except ValueError:
        raise ValueError(f'profile {ident}: the APN is missing or not a plain carrier APN') from None
    return Profile(ident, apn, types, **options)


def configured_profiles(settings):
    """The profiles to send, in profile ID order: [profiles] as written, and
    profile 0 from [network] apn unless [profiles] has its own 0. Raises
    ValueError on any bad line (start-up then stops before the radio)."""
    net = settings['network']
    found = {}
    if settings.has_section('profiles'):
        for key, value in settings.items('profiles', raw=True):
            if key in settings.defaults():
                continue
            profile = parse_profile(key, value)
            if profile.ident in found:
                raise ValueError(f'profile {profile.ident} given twice')
            found[profile.ident] = profile
    if 0 not in found:
        found[0] = default_profile(net.get('apn', ''), net.get('ip_type', 'ipv4v6'))
    return [found[i] for i in sorted(found)]


def profile_payload(profile):
    """Stock BuildSetDataProfile (V2_0), the 246-byte request. Offsets below
    include the 12-byte request header. This configures a network APN
    profile, not a SIM subscription or UICC operation."""
    full = bytearray(246)
    struct.pack_into('<I', full, 0x0c, profile.ident)
    encoded = profile.apn.encode('ascii')
    full[0x10:0x10 + len(encoded)] = encoded                       # 100 bytes
    full[0x75] = IP_TYPES[profile.ip]                              # home PDP type
    full[0x76] = IP_TYPES[profile.roaming_ip]                      # roaming PDP type
    full[0x77] = 0                                                 # no authentication
    # 0x78 user and 0xaa password (49 bytes each): empty.
    struct.pack_into('<I', full, 0xdd, profile.max_conns_time)
    struct.pack_into('<I', full, 0xe1, profile.max_conns)
    struct.pack_into('<I', full, 0xe5, profile.wait_time)
    full[0xe9] = 1                                                 # enabled
    struct.pack_into('<I', full, 0xea, profile.types)              # APN-type bitmask
    struct.pack_into('<I', full, 0xee, 0)                          # any bearer
    return bytes(full[12:])


def provision_profile(client, profile):
    client.request(0x0613, profile_payload(profile), timeout=30)
    print(f'data profile {profile.ident} accepted (types {profile.type_names()}, '
          f'IP {profile.ip}/{profile.roaming_ip})', flush=True)


def provision_profiles(client, profiles):
    for profile in profiles:
        provision_profile(client, profile)


def provision_default_profile(client, apn, ip_type='ipv4v6'):
    provision_profile(client, default_profile(apn, ip_type))


# After the data permission is switched on, the modem is given time to settle
# before the setup goes out: on 2026-11-02 every setup was answered 36 within
# 150 ms and was followed within a second by three IND_REG_FAILED (LTE cause
# 10, implicitly detached) and two IND_NTW_STATE_CHANGED; with this wait the
# same indications came and went before the setup, and it succeeded. The wait ends after SETTLE_QUIET seconds without an
# indication, or at SETTLE_LIMIT.
SETTLE_QUIET = 3
SETTLE_LIMIT = 20


def keep_packet(packet):
    """Append a raw indication to a private file in RAM (it may carry the
    PLMN or cell identity), length-prefixed, for decoding later."""
    path = RESPONSE.with_name('indications.bin')
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, struct.pack('<H', len(packet)) + packet)
    finally:
        os.close(fd)


def describe(packet):
    message, length = struct.unpack_from('<HH', packet, 2)
    payload = packet[8:]
    line = f'{NAMES.get(message, hex(message))} ({length} bytes)'
    if message == 0x0604 and payload and 1 <= payload[0] <= 15 and len(payload) > 1:
        count = payload[0]
        size = (len(payload) - 1) // count
        records = []
        for index in range(count):
            record = payload[1 + index * size:1 + (index + 1) * size]
            if len(record) >= 5:
                records.append(struct.unpack_from('<HBBB', record))
        line += f' data calls {count}: status, CID, active, PDP type {records}'
    return line


def settle(client, label, on_event=None):
    deadline = time.monotonic() + SETTLE_LIMIT
    last = time.monotonic()
    seen = 0
    while True:
        now = time.monotonic()
        if now >= deadline or now - last >= SETTLE_QUIET:
            break
        packet = client.next_indication(min(.5, deadline - now))
        if packet is None:
            continue
        seen += 1
        last = time.monotonic()
        keep_packet(packet)
        print(f'{label}: {describe(packet)}', flush=True)
        if on_event:
            # Handled as the service handles any indication (an SMS arriving
            # now is stored and acknowledged), not only recorded.
            on_event(packet)
    print(f'{label}: {seen} indication(s), then quiet' if seen else f'{label}: quiet', flush=True)

def listen_after_failure(client, seconds=5, on_event=None):
    """After a refused setup, keep the channel open a few seconds and log
    what the modem sends next: on 2026-11-02 two or three messages arrived
    about a second after each status 36 and were dropped because the channel
    had already closed. Message names and lengths only; for a data-call list
    change, the per-record status, CID, active and PDP type, nothing else."""
    deadline = time.monotonic() + seconds
    seen = 0
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        packet = client.next_indication(min(1, remaining))
        if packet is None:
            continue
        seen += 1
        keep_packet(packet)
        print(f'after the failure: {describe(packet)}', flush=True)
        if on_event:
            on_event(packet)
    print(f'after the failure: {seen} indication(s) in {seconds} s', flush=True)

def activate(client, apn, *, ims=False, ip_type=None, lte_access=False, on_event=None):
    requested_cid = 2 if ims else 1
    state_path, response_path = paths(requested_cid)
    state = client.request(0x0701)
    if len(state) < 4 or state[0] not in (1, 5):
        raise RuntimeError('PS network is not registered')
    calls = call_ids(client.request(0x0602))
    owned = owned_ids()
    # Bearers recorded as modem-owned are the modem's, not unresolved; a CID
    # they hold (or held) is never set up or claimed.
    modem = modem_owned_ids()
    if state_path.exists() or requested_cid in calls | modem or calls - modem != owned:
        raise RuntimeError('existing target or unresolved bearer ownership')
    allow_data(client)
    settle(client, 'after allowing data', on_event)
    # The registration as it stands now, not before the permission: the
    # modem may have re-attached meanwhile.
    for second in range(60):
        state = client.request(0x0701)
        if len(state) >= 4 and state[0] in (1, 5):
            break
        if second == 0:
            print('registration lost after allowing data; waiting for it', flush=True)
        time.sleep(1)
    else:
        raise RuntimeError('PS network is not registered after allowing data')
    print('registration before the setup: PS state, reject, RAT', (state[0], state[1], state[3]), flush=True)
    # No ALLOC_PDU_SESSION on cellular (module docstring): session 0.
    session = 0
    # Persist ownership before setup. A timeout has an unknown outcome: the
    # record stays while the modem may still be activating the bearer.
    private_write(state_path, json.dumps({'cid': requested_cid, 'session': session}).encode())
    released = False
    try:
        rat = 14 if lte_access else state[3]
        print('data setup access RAT', rat, 'registered RAT', state[3], 'PDU session ID', session, flush=True)
        result = client.request(0x0600, setup_payload(requested_cid, rat, session, apn,
                                                      ims=ims, ip_type=ip_type), timeout=45)
        if len(result) < 132:
            raise RuntimeError('unexpected data-call layout')
        status, cid, raw_active, pdp = struct.unpack_from('<HBBB', result)
        print('data-call status', status, 'CID', cid, 'active raw', raw_active, 'PDP type', pdp, flush=True)
        if cid == requested_cid and raw_active == 0:
            # Refused outright: nothing is held, so nothing stays owned.
            released = True
        if status or cid != requested_cid or raw_active not in (1, 2):
            # The whole record, kept privately in RAM for the record (it may
            # carry addresses or the APN), and the modem's next messages.
            failed_path = response_path.with_name(f'failed-setup-cid{requested_cid}.bin')
            private_write(failed_path, result)
            print(f'failed setup response kept privately: {len(result)} bytes', flush=True)
            listen_after_failure(client, on_event=on_event)
            raise RuntimeError('data call did not become active')
        private_write(response_path, result)
        print('owned data bearer active; private IP configuration retained in RAM', flush=True)
        if ims:
            # Base response layout: family then 3 v4 and 3 v6 P-CSCF
            # addresses. Report presence only, never their values.
            v4, v6 = pcscf_addresses(result)
            print('IMS IPv6 present', any(result[9:25]), 'PDP type', pdp, 'response length', len(result),
                  'P-CSCF family', result[0x42], 'extension version', result[0x84] if len(result) > 0x84 else None,
                  'P-CSCF count IPv4', len(v4), 'IPv6', len(v6), flush=True)
    finally:
        if released:
            state_path.unlink(missing_ok=True)
            response_path.unlink(missing_ok=True)


def deactivate(client, cid=1):
    if cid in modem_owned_ids():
        raise RuntimeError(f'bearer CID {cid} is modem-owned; sitd never releases it')
    state_path, response_path = paths(cid)
    if cid == 2 and state_path.with_name('ims-registration.json').exists():
        raise RuntimeError('unregister IMS before releasing its bearer')
    owned = json.loads(state_path.read_text())
    if owned.get('cid') != cid or not 0 <= owned.get('session', -1) <= 15:
        raise RuntimeError('invalid bearer ownership record')
    # rmnet<CID - 1>, and the device omamobile-sit-data found carrying it
    # (data_network.find_device), while that configuration exists.
    devices = {f"rmnet{owned['cid'] - 1}"}
    recorded = RUN / 'data-interface'
    if cid == 1 and recorded.exists():
        devices.add(recorded.read_text().strip())
    for dev in devices:
        flags = Path(f'/sys/class/net/{dev}/flags')
        if flags.exists() and int(flags.read_text(), 16) & 1:
            raise RuntimeError('remove host data configuration first')
    # Stock BuildDeactDataCall: CID and normal-release reason.
    client.request(0x0601, bytes([owned['cid'], 0]), timeout=30)
    calls = call_ids(client.request(0x0602))
    if cid in calls:
        raise RuntimeError('deactivated bearer still listed; retaining reservation')
    if owned['session']:
        # Only a record from 0.3.4 or earlier holds an allocated ID.
        client.request(0x061b, struct.pack('<i', owned['session']))
    state_path.unlink()
    response_path.unlink(missing_ok=True)
    if calls - modem_owned_ids() != owned_ids():
        raise RuntimeError('unexpected remaining data-call ownership')
    print('owned data bearer deactivated', flush=True)
