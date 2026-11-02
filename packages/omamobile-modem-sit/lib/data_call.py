# SPDX-License-Identifier: MIT
"""Data-call layouts (the stock 983-byte version-2 setup request) and an
owned bearer lifecycle: CID 1 (internet, rmnet0) and CID 2 (IMS, rmnet1).

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


def check_apn(apn):
    """An APN as a carrier publishes it: labels of letters, digits and '-',
    joined by dots, at most 99 characters (the request's field is 100 bytes)."""
    if not isinstance(apn, str) or not re.fullmatch(r'[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*', apn) \
            or len(apn) > 99:
        raise ValueError('APN missing or not a plain carrier APN; set [network] apn')
    return apn


def call_ids(payload):
    # Stock DataCallUtil::DetermineDCTypeBySize. Reject variable
    # traffic-descriptor records until their full framing is implemented.
    if not payload or payload[0] > 15:
        raise RuntimeError('invalid data-call list')
    count = payload[0]
    if count == 0:
        if len(payload) != 1:
            raise RuntimeError('unexpected empty data-call list')
        return set()
    size, remainder = divmod(len(payload) - 1, count)
    if remainder or size not in (132, 234, 239, 246, 280, 292):
        raise RuntimeError('unsupported data-call list layout')
    cids = [payload[1 + index * size + 2] for index in range(count)]
    if len(set(cids)) != count or any(not 1 <= cid <= 15 for cid in cids):
        raise RuntimeError('invalid or duplicate data-call CID')
    return set(cids)


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


def setup_payload(cid, radio_technology, pdu_session, apn, *, ims=False, ip_type='ipv4v6'):
    # Absolute request offsets below include the 12-byte request header.
    check_apn(apn)
    full = bytearray(983)
    full[12] = cid
    full[13] = radio_technology
    full[14] = 0  # stock converter: only tethering maps to 1
    full[15] = 1 if ims else 0  # IMS/default APN type
    encoded = apn.encode('ascii')
    full[16:16 + len(encoded)] = encoded
    full[0xd9] = 0  # no authentication
    full[0xda] = IP_TYPES['ipv6'] if ims else IP_TYPES[ip_type]
    full[0xdb] = 2 if ims else 0  # IPv6 P-CSCF request
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


def initial_attach(client, apn, ip_type='ipv4v6'):
    """SET_INITIAL_ATTACH_APN (251 bytes). Without it, setup requests on this
    phone returned status 36 and no bearer."""
    attach = bytearray(251)
    attach[12:245] = setup_payload(1, 14, 0, apn, ip_type=ip_type)[:233]
    # Stock's attach builder leaves 0xf1-0xf4 zero: no APN-type bitmap here.
    attach[0xf1:0xf5] = bytes(4)
    attach[0xf8] = 3  # the roaming PDP type, IPv4v6 (the home type is 0xda)
    client.request(0x0603, bytes(attach[12:]), timeout=30)


def allow_data(client):
    previous = client.request(0x0711)
    print('PS service permission before', previous[0] if len(previous) == 1 else 'unexpected', flush=True)
    client.request(0x0625, b'\x01\x00')
    client.request(0x0710, b'\x01')
    if client.request(0x0711) != b'\x01':
        raise RuntimeError('PS service permission is not enabled')
    print('PS service permission enabled', flush=True)


def provision_default_profile(client, apn, ip_type='ipv4v6'):
    # Stock BuildSetDataProfile, 246-byte request. This configures the
    # network APN profile, not a SIM subscription or UICC operation.
    encoded = check_apn(apn).encode('ascii')
    full = bytearray(246)
    struct.pack_into('<I', full, 12, 0)  # Android default profile ID
    full[16:16 + len(encoded)] = encoded
    full[0x75] = full[0x76] = IP_TYPES[ip_type]  # home/roaming IP type
    full[0xe9] = 1  # enabled
    struct.pack_into('<I', full, 0xea, 1)  # default APN-type bitmap
    client.request(0x0613, bytes(full[12:]), timeout=30)
    print('default data profile accepted', flush=True)




# After the data permission is switched on, the modem is given time to say
# what it does about it before the setup goes out: on 2026-11-02 every setup
# was answered 36 within 150 ms and was followed within a second by three
# IND_REG_FAILED and two IND_NTW_STATE_CHANGED, so the modem was re-attaching
# around the request. The wait ends after SETTLE_QUIET seconds without an
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


def settle(client, label):
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
    print(f'{label}: {seen} indication(s), then quiet' if seen else f'{label}: quiet', flush=True)

def listen_after_failure(client, seconds=5):
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
    print(f'after the failure: {seen} indication(s) in {seconds} s', flush=True)

def activate(client, apn, *, ims=False, ip_type='ipv4v6', lte_access=False):
    requested_cid = 2 if ims else 1
    state_path, response_path = paths(requested_cid)
    state = client.request(0x0701)
    if len(state) < 4 or state[0] not in (1, 5):
        raise RuntimeError('PS network is not registered')
    calls = call_ids(client.request(0x0602))
    owned = owned_ids()
    if state_path.exists() or requested_cid in calls or calls != owned:
        raise RuntimeError('existing target or unresolved bearer ownership')
    allow_data(client)
    settle(client, 'after allowing data')
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
            listen_after_failure(client)
            raise RuntimeError('data call did not become active')
        private_write(response_path, result)
        print('owned data bearer active; private IP configuration retained in RAM', flush=True)
        if ims:
            # Base response layout: family then 3 v4 and 3 v6 P-CSCF
            # addresses. Report presence only, never their values.
            print('IMS IPv6 present', any(result[9:25]),
                  'P-CSCF family', result[0x42],
                  'base IPv6 P-CSCF count', sum(bool(any(result[i:i+16])) for i in (0x4f, 0x5f, 0x6f)), flush=True)
    finally:
        if released:
            state_path.unlink(missing_ok=True)
            response_path.unlink(missing_ok=True)


def deactivate(client, cid=1):
    state_path, response_path = paths(cid)
    if cid == 2 and state_path.with_name('ims-registration.json').exists():
        raise RuntimeError('unregister IMS before releasing its bearer')
    owned = json.loads(state_path.read_text())
    if owned.get('cid') != cid or not 0 <= owned.get('session', -1) <= 15:
        raise RuntimeError('invalid bearer ownership record')
    flags = int(Path(f"/sys/class/net/rmnet{owned['cid'] - 1}/flags").read_text(), 16)
    if flags & 1:
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
    if calls != owned_ids():
        raise RuntimeError('unexpected remaining data-call ownership')
    print('owned data bearer deactivated', flush=True)
