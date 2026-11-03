# SPDX-License-Identifier: MIT
"""The IMS P-CSCF from the ISIM's EF_PCSCF (3GPP TS 31.103 4.2.8), for
networks whose IMS bearer carries none in its PCO: stock's IMS service does
the same (addPcscfFromSim, getIsimPcscf).

Read-only and limited to that one file: SIM_IO GET RESPONSE (for the record
size) and READ RECORD on EF_PCSCF (6F09) under the ISIM's ADF (path
3F007FFF). sit.check refuses every other SIM_IO request, at the transport.
No other ISIM file is read (never IMPI, IMPU or the domain), and the AID is
never logged.

SIM_IO request (stock ProtocolSimBuilder::BuildSimIO, 560 bytes after the
12-byte header): +0 u8 command, +1 u8 application type (RIL_AppType; ISIM
5), +2 u16 file ID (little-endian), +4 u8 path length in bytes, +5 path (12
bytes; each 16-bit file ID stored little-endian, so 3F00 7FFF is 00 3F FF
7F), +17 P1, +18 P2, +19 P3, +20 u16 data length, +22 data (512), +534 u8
PIN2 length, +535 PIN2 (8), +543 u8 AID length, +544 AID (16). Response
(ProtocolSimIOAdapter): +0 SW1, +1 SW2, +2 s16 response length (at most
512), +4 response.
"""
import ipaddress
import os
import re
import socket
import struct
import threading

SIM_IO = 0x0208
READ_RECORD, GET_RESPONSE = 0xB2, 0xC0
APP_ISIM = 5
EF_PCSCF = 0x6F09
PATH = bytes([0x00, 0x3F, 0xFF, 0x7F])     # 3F00 7FFF, as BuildSimIO stores it
# 3GPP's RID and the ISIM application code (TS 31.103 annex, ETSI TS 101 220).
ISIM_AID_PREFIX = bytes.fromhex('A0000000871004')
REQUEST_LENGTH = 560
MAX_RECORDS = 8
FQDN = re.compile(r'(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*'
                  r'[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.?')


def request(command, aid, p1, p2, p3):
    """A SIM_IO request on EF_PCSCF; check_request decides whether it may go."""
    if not 1 <= len(aid) <= 16:
        raise ValueError('ISIM AID length')
    body = bytearray(REQUEST_LENGTH)
    body[0], body[1] = command, APP_ISIM
    struct.pack_into('<H', body, 2, EF_PCSCF)
    body[4] = len(PATH)
    body[5:5 + len(PATH)] = PATH
    body[17:20] = bytes([p1, p2, p3])
    body[543] = len(aid)
    body[544:544 + len(aid)] = aid
    return bytes(body)


def check_request(payload):
    """The only SIM_IO this stack sends: GET RESPONSE or READ RECORD (absolute
    record, P2 4) on the ISIM's EF_PCSCF, with no data and no PIN2. Raises
    ValueError for anything else."""
    p = bytes(payload)
    if len(p) != REQUEST_LENGTH:
        raise ValueError('SIM_IO: unexpected request length')
    command, app = p[0], p[1]
    if app != APP_ISIM or struct.unpack_from('<H', p, 2)[0] != EF_PCSCF:
        raise ValueError('SIM_IO: only the ISIM\'s EF_PCSCF')
    if p[4] != len(PATH) or p[5:9] != PATH or any(p[9:17]):
        raise ValueError('SIM_IO: only the path 3F007FFF')
    p1, p2, p3 = p[17:20]
    if command == GET_RESPONSE:
        if p1 or p2 or not 1 <= p3 <= 255:
            raise ValueError('SIM_IO: GET RESPONSE parameters')
    elif command == READ_RECORD:
        if not 1 <= p1 <= 254 or p2 != 4 or not 1 <= p3 <= 255:
            raise ValueError('SIM_IO: READ RECORD parameters')
    else:
        raise ValueError('SIM_IO: only GET RESPONSE and READ RECORD (read-only)')
    if struct.unpack_from('<H', p, 20)[0] or any(p[22:534]):
        raise ValueError('SIM_IO: no data may be sent')
    if p[534] or any(p[535:543]):
        raise ValueError('SIM_IO: no PIN2')
    n = p[543]
    if not len(ISIM_AID_PREFIX) <= n <= 16 or not p[544:544 + n].startswith(ISIM_AID_PREFIX) \
            or any(p[544 + n:]):
        raise ValueError('SIM_IO: only the ISIM application')


def isim_aid(status):
    """The AID of a ready ISIM (type 5, state 5) from GET_SIM_STATUS (63-byte
    application records: +0 type, +1 state, +3 AID length, +4 AID), or None.
    Never log it."""
    if len(status) < 3 or status[2] > 8 or len(status) < 3 + status[2] * 63:
        raise ValueError('Unexpected SIM status layout')
    for i in range(3, 3 + status[2] * 63, 63):
        app = status[i:i + 63]
        if app[0] == APP_ISIM and app[1] == 5 and 1 <= app[3] <= 16:
            aid = bytes(app[4:4 + app[3]])
            if aid.startswith(ISIM_AID_PREFIX):
                return aid
    return None


def response(payload):
    """(SW1, SW2, data) of a SIM_IO response."""
    if len(payload) < 4:
        raise ValueError('short SIM_IO response')
    length = struct.unpack_from('<h', payload, 2)[0]
    if not 0 <= length <= 512 or len(payload) < 4 + length:
        raise ValueError('truncated SIM_IO response')
    return payload[0], payload[1], bytes(payload[4:4 + length])


def ok(sw1):
    return sw1 in (0x90, 0x91)


def tlv(data, offset):
    """(tag, value, next offset) of one BER-TLV with a one- or two-byte length."""
    if offset + 2 > len(data):
        raise ValueError('truncated TLV')
    tag, length = data[offset], data[offset + 1]
    start = offset + 2
    if length == 0x81:
        if start >= len(data):
            raise ValueError('truncated TLV')
        length, start = data[start], start + 1
    elif length > 0x7f:
        raise ValueError('unsupported TLV length')
    if start + length > len(data):
        raise ValueError('truncated TLV')
    return tag, data[start:start + length], start + length


def record_layout(data):
    """(record length, record count) from a GET RESPONSE: a UICC FCP template
    (tag 62, file descriptor 82: descriptor, coding, u16 record length, count)
    or the 2G-style 15-byte answer Android's IccFileHandler reads (file size
    at 2, record length at 14)."""
    if data[:1] == b'\x62':
        _, fcp, _ = tlv(data, 0)
        offset = 0
        while offset < len(fcp):
            tag, value, offset = tlv(fcp, offset)
            if tag == 0x82 and len(value) >= 5:
                size, count = struct.unpack_from('>H', value, 2)[0], value[4]
                if 1 <= size <= 255 and count:
                    return size, count
                break
        raise ValueError('EF_PCSCF is not a linear fixed file')
    if len(data) >= 15 and data[14]:
        size = struct.unpack_from('>H', data, 2)[0]
        if size >= data[14]:
            return data[14], size // data[14]
    raise ValueError('unexpected GET RESPONSE layout')


def parse_record(record):
    """One EF_PCSCF record: tag 80, length, address type (00 FQDN, 01 IPv4,
    02 IPv6), address. Returns ('fqdn', str), ('ipv4', bytes4), ('ipv6',
    bytes16) or None for an empty (FF-filled) or unusable record. IPv4/IPv6
    are taken binary, or as a text literal (cards differ)."""
    record = bytes(record)
    if not record or record[0] == 0xFF or not record.strip(b'\xff'):
        return None
    try:
        tag, value, _ = tlv(record, 0)
    except ValueError:
        return None
    if tag != 0x80 or len(value) < 2:
        return None
    kind, address = value[0], value[1:]
    text = address.rstrip(b'\x00\xff').decode('ascii', 'replace')
    try:
        if kind == 0x01:
            return 'ipv4', (address if len(address) == 4 else ipaddress.IPv4Address(text).packed)
        if kind == 0x02:
            return 'ipv6', (address if len(address) == 16 else ipaddress.IPv6Address(text).packed)
    except ValueError:
        return None
    if kind == 0x00 and FQDN.fullmatch(text):
        return 'fqdn', text.rstrip('.').lower()
    return None


def read_pcscf(client, aid):
    """The EF_PCSCF entries, in record order, deduplicated."""
    sw1, sw2, data = response(client.request(SIM_IO, request(GET_RESPONSE, aid, 0, 0, 15), timeout=10))
    if not ok(sw1):
        raise RuntimeError(f'EF_PCSCF GET RESPONSE status {sw1:02X}{sw2:02X}')
    size, count = record_layout(data)
    entries = []
    for number in range(1, min(count, MAX_RECORDS) + 1):
        sw1, sw2, record = response(client.request(
            SIM_IO, request(READ_RECORD, aid, number, 4, size), timeout=10))
        if not ok(sw1):
            break
        entry = parse_record(record)
        if entry and entry not in entries:
            entries.append(entry)
    return entries


def dns_query(name, qtype=28):
    ident = int.from_bytes(os.urandom(2), 'big')
    labels = b''.join(bytes([len(l)]) + l.encode('ascii') for l in name.split('.') if l)
    return ident, struct.pack('>HHHHHH', ident, 0x0100, 1, 0, 0, 0) + labels + b'\0' \
        + struct.pack('>HH', qtype, 1)


def skip_name(data, offset):
    while True:
        if offset >= len(data):
            raise ValueError('truncated DNS name')
        length = data[offset]
        if length & 0xc0 == 0xc0:
            return offset + 2
        if length == 0:
            return offset + 1
        offset += 1 + length


def dns_answers(data, ident, qtype=28):
    """The addresses of type qtype in a DNS reply (CNAMEs are followed by the
    server in the same answer section)."""
    if len(data) < 12:
        raise ValueError('short DNS reply')
    rid, flags, qd, an = struct.unpack_from('>HHHH', data)
    if rid != ident or not flags & 0x8000 or flags & 0xf:
        return []
    offset = 12
    for _ in range(qd):
        offset = skip_name(data, offset) + 4
    found = []
    for _ in range(an):
        offset = skip_name(data, offset)
        if offset + 10 > len(data):
            break
        rtype, _, _, length = struct.unpack_from('>HHIH', data, offset)
        offset += 10
        value = data[offset:offset + length]
        offset += length
        if rtype == qtype and len(value) == (16 if qtype == 28 else 4):
            found.append(bytes(value))
    return found


def resolve_on_bearer(name, source, servers, timeout=3):
    """AAAA over the IMS bearer: UDP from the bearer's own address to its DNS
    servers. Fails where the host has no such address (the modem's IMS stack
    owns the bearer)."""
    for server in servers:
        try:
            sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        except OSError:
            return []
        with sock:
            sock.settimeout(timeout)
            try:
                sock.bind((source, 0))
                ident, query = dns_query(name)
                sock.sendto(query, (server, 53))
                data, _ = sock.recvfrom(4096)
            except OSError:
                continue
            found = dns_answers(data, ident)
            if found:
                return found
    return []


def resolve_system(name, timeout=5):
    """AAAA through the host's resolver (the internet bearer or Wi-Fi), with a
    deadline: getaddrinfo has none of its own."""
    result = []

    def lookup():
        try:
            for info in socket.getaddrinfo(name, None, socket.AF_INET6, socket.SOCK_DGRAM):
                result.append(ipaddress.IPv6Address(info[4][0].split('%')[0]).packed)
        except (OSError, ValueError):
            pass
    worker = threading.Thread(target=lookup, daemon=True)
    worker.start()
    worker.join(timeout)
    return list(dict.fromkeys(result)) if not worker.is_alive() else []


def bearer_dns(bearer):
    """The IMS bearer's own IPv6 address and IPv6 DNS servers (setup response:
    address at 9, DNS at 0x1e and 0x32), as text."""
    source = str(ipaddress.IPv6Address(bytes(bearer[9:25])))
    servers = [str(ipaddress.IPv6Address(bytes(bearer[i:i + 16])))
               for i in (0x1e, 0x32) if any(bearer[i:i + 16])]
    return source, list(dict.fromkeys(servers))


def ipv6_pcscf(client, status, bearer, *, resolve_bearer=resolve_on_bearer,
               resolve_host=resolve_system):
    """IPv6 P-CSCF addresses from the ISIM, for ADD_PDN (its list is IPv6, as
    the IMS bearer). FQDNs are resolved (AAAA) over the IMS bearer first, then
    through the host's resolver. Returns [] when there is no ready ISIM or
    nothing usable; logs counts and the FQDNs (carrier server names), never
    the AID or any other ISIM content."""
    aid = isim_aid(status)
    if aid is None:
        print('P-CSCF from ISIM: no ready ISIM application', flush=True)
        return []
    entries = read_pcscf(client, aid)
    kinds = [kind for kind, _ in entries]
    print(f'P-CSCF from ISIM: {len(entries)} addresses ('
          + ', '.join(f'{kinds.count(k)} {label}' for k, label in
                      (('fqdn', 'FQDN'), ('ipv4', 'IPv4'), ('ipv6', 'IPv6')) if k in kinds)
          + ')', flush=True)
    addresses = [value for kind, value in entries if kind == 'ipv6']
    if 'ipv4' in kinds:
        print('P-CSCF from ISIM: IPv4 entries not used (the IMS bearer and ADD_PDN list are IPv6)',
              flush=True)
    names = [value for kind, value in entries if kind == 'fqdn']
    if names:
        source, servers = bearer_dns(bearer)
        for name in names:
            print(f'P-CSCF from ISIM: FQDN {name}', flush=True)
            try:
                found = resolve_bearer(name, source, servers) if servers else []
            except (OSError, ValueError):
                found = []
            how = 'over the IMS bearer'
            if not found:
                found = resolve_host(name)
                how = 'through the host resolver'
            if found:
                print(f'P-CSCF from ISIM: {name} resolved {how}: {len(found)} IPv6', flush=True)
            else:
                print(f'P-CSCF from ISIM: {name} did not resolve to IPv6', flush=True)
            addresses += found
    return list(dict.fromkeys(a for a in addresses if any(a)))
