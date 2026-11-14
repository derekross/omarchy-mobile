# SPDX-License-Identifier: MIT
"""Read only the ready USIM's EF_MSISDN; never write a SIM or log a number.

EF_MSISDN (3GPP TS 31.102 section 4.2.26) is an optional, linear-fixed
ADN-format file. Its contents are SIM-provided numbers, not proof of the
network's current assignment. Extension records are deliberately unsupported:
an EXT5 reference makes the result incomplete instead of exposing a prefix.

The SIM_IO layout is the same one used by isim.py. Every request has a
separate byte-level guard for USIM EF_MSISDN; no other SIM file, data or
PIN operation is permitted. The daemon's existing IPC0 owner makes the
requests, so this module never opens a modem device.
"""
import struct
import time

from isim import (GET_RESPONSE, PATH, READ_RECORD, REQUEST_LENGTH, SIM_IO,
                  record_layout, response, tlv)

GET_SIM_STATUS = 0x0200
APP_USIM = 2
EF_MSISDN = 0x6F40
USIM_AID_PREFIX = bytes.fromhex('A0000000871002')
MAX_RECORDS = 8
TOTAL_TIMEOUT = 5.0
REQUEST_TIMEOUT = 3.0


class IncompleteNumber(ValueError):
    """The complete SIM value needs an intentionally unsupported extension."""


class _Unavailable(Exception):
    pass


def request(command, aid, p1, p2, p3):
    """A guarded GET RESPONSE or READ RECORD on USIM EF_MSISDN."""
    aid = bytes(aid)
    if not len(USIM_AID_PREFIX) <= len(aid) <= 16:
        raise ValueError('MSISDN: USIM AID length')
    body = bytearray(REQUEST_LENGTH)
    body[0], body[1] = command, APP_USIM
    struct.pack_into('<H', body, 2, EF_MSISDN)
    body[4] = len(PATH)
    body[5:5 + len(PATH)] = PATH
    body[17:20] = bytes([p1, p2, p3])
    body[543] = len(aid)
    body[544:544 + len(aid)] = aid
    check_request(body)
    return bytes(body)


def check_request(payload):
    """Refuse every SIM_IO except bounded read-only USIM EF_MSISDN."""
    p = bytes(payload)
    if len(p) != REQUEST_LENGTH:
        raise ValueError('MSISDN: unexpected request length')
    if p[1] != APP_USIM or struct.unpack_from('<H', p, 2)[0] != EF_MSISDN:
        raise ValueError('MSISDN: only USIM EF_MSISDN')
    if p[4] != len(PATH) or p[5:9] != PATH or any(p[9:17]):
        raise ValueError('MSISDN: only the path 3F007FFF')
    command, (p1, p2, p3) = p[0], p[17:20]
    if command == GET_RESPONSE:
        if p1 or p2 or not 1 <= p3 <= 255:
            raise ValueError('MSISDN: GET RESPONSE parameters')
    elif command == READ_RECORD:
        if not 1 <= p1 <= MAX_RECORDS or p2 != 4 or not 14 <= p3 <= 255:
            raise ValueError('MSISDN: READ RECORD parameters')
    else:
        raise ValueError('MSISDN: only GET RESPONSE and READ RECORD')
    if struct.unpack_from('<H', p, 20)[0] or any(p[22:534]):
        raise ValueError('MSISDN: no data may be sent')
    if p[534] or any(p[535:543]):
        raise ValueError('MSISDN: no PIN2')
    n = p[543]
    if not len(USIM_AID_PREFIX) <= n <= 16 \
            or not p[544:544 + n].startswith(USIM_AID_PREFIX) \
            or any(p[544 + n:]):
        raise ValueError('MSISDN: only the USIM application')


def usim_aid(status):
    """A ready USIM's AID from GET_SIM_STATUS, or None; never log the AID."""
    p = bytes(status)
    if len(p) < 3 or p[2] > 8 or len(p) < 3 + p[2] * 63:
        raise ValueError('MSISDN: unexpected SIM status layout')
    if p[0] != 1:
        return None
    for offset in range(3, 3 + p[2] * 63, 63):
        app = p[offset:offset + 63]
        if app[0] == APP_USIM and app[1] == 5 \
                and len(USIM_AID_PREFIX) <= app[3] <= 16:
            aid = bytes(app[4:4 + app[3]])
            if aid.startswith(USIM_AID_PREFIX):
                return aid
    return None


def _layout(data):
    """Validate a linear-fixed EF header before reusing the common parser."""
    if data[:1] == b'\x62':
        _, fcp, end = tlv(data, 0)
        if data[end:].strip(b'\xff'):
            raise ValueError('MSISDN: trailing FCP data')
        offset, descriptor = 0, None
        while offset < len(fcp):
            tag, value, offset = tlv(fcp, offset)
            if tag == 0x82:
                if descriptor is not None or len(value) != 5 or value[0] & 7 != 2:
                    raise ValueError('MSISDN: not a linear-fixed file')
                descriptor = value
            elif tag == 0x83 and value != struct.pack('>H', EF_MSISDN):
                raise ValueError('MSISDN: unexpected file identifier')
        if descriptor is None:
            raise ValueError('MSISDN: no file descriptor')
    else:
        # Android's legacy GET RESPONSE: file type EF, structure linear-fixed.
        if len(data) != 15 or data[6] != 4 or data[13] != 1 \
                or data[4:6] != struct.pack('>H', EF_MSISDN) or not data[14] \
                or struct.unpack_from('>H', data, 2)[0] % data[14]:
            raise ValueError('MSISDN: unexpected legacy file header')
    size, count = record_layout(data)
    if not 14 <= size <= 255 or not 1 <= count <= 254:
        raise ValueError('MSISDN: invalid record layout')
    return size, count


def parse_record(record):
    """One complete ADN-style MSISDN, or None for an empty record.

    Alpha tags and capability records are unused. Only decimal telephone
    numbers (ISDN NPI) with unknown, national or international TON are
    exposed; other dialling strings are unavailable rather than guessed.
    """
    p = bytes(record)
    if not 14 <= len(p) <= 255:
        raise ValueError('MSISDN: invalid record length')
    footer = p[-14:]
    if footer[-1] != 0xff:
        raise IncompleteNumber('MSISDN: extension record required')
    length, ton_npi = footer[:2]
    if length in (0, 0xff):
        return None
    if not 2 <= length <= 11 or not ton_npi & 0x80 \
            or ton_npi & 15 != 1 or (ton_npi >> 4) & 7 not in (0, 1, 2):
        raise ValueError('MSISDN: invalid telephone number metadata')
    bcd = footer[2:2 + length - 1]
    if footer[2 + length - 1:12].strip(b'\xff'):
        raise ValueError('MSISDN: invalid unused number bytes')
    digits = []
    for index, value in enumerate(bcd):
        low, high = value & 15, value >> 4
        if low > 9 or high > 9 and not (high == 15 and index == len(bcd) - 1):
            raise ValueError('MSISDN: invalid BCD number')
        digits.append(str(low))
        if high != 15:
            digits.append(str(high))
    return ('+' if (ton_npi >> 4) & 7 == 1 else '') + ''.join(digits)


def _result(status, numbers=None, reason=None):
    value = dict(status=status, source='sim', numbers=list(numbers or []))
    if reason:
        value['reason'] = reason
    return value


def read_numbers(client):
    """Read at most eight records within a five-second SIM-read budget.

    Every failure is optional information missing: registration, calls and
    data must keep running. Reasons are fixed codes, never exception text,
    raw records, AIDs or phone numbers. Incomplete results expose no prefix
    or partial list. The supplied daemon-owned client enforces timeouts.
    """
    deadline = time.monotonic() + TOTAL_TIMEOUT

    def ask(ident, payload=b''):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError
        answer = client.request(ident, payload, timeout=min(REQUEST_TIMEOUT, remaining))
        if time.monotonic() > deadline:
            raise TimeoutError
        return answer

    def read(command, aid, p1, p2, p3, reason):
        sw1, sw2, data = response(ask(SIM_IO, request(command, aid, p1, p2, p3)))
        if not (sw1 == 0x90 and sw2 == 0 or sw1 == 0x91):
            raise _Unavailable(reason)
        return data

    try:
        aid = usim_aid(ask(GET_SIM_STATUS))
        if aid is None:
            return _result('unavailable', reason='sim-not-ready')
        size, count = _layout(read(GET_RESPONSE, aid, 0, 0, 15, 'file-unavailable'))
        if count > MAX_RECORDS:
            return _result('incomplete', reason='record-limit')
        numbers = []
        for number in range(1, count + 1):
            record = read(READ_RECORD, aid, number, 4, size, 'record-unavailable')
            if len(record) != size:
                raise ValueError('MSISDN: unexpected record size')
            value = parse_record(record)
            if value is not None and value not in numbers:
                numbers.append(value)
        return _result('available' if numbers else 'empty', numbers)
    except IncompleteNumber:
        return _result('incomplete', reason='extension-record')
    except _Unavailable as error:
        return _result('unavailable', reason=str(error))
    except TimeoutError:
        return _result('unavailable', reason='timeout')
    except (OSError, RuntimeError, EOFError):
        return _result('unavailable', reason='read-failed')
    except (ValueError, TypeError, struct.error):
        return _result('unavailable', reason='invalid-response')
