#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""omamobile-sitd: the single owner of the S5300's SIT channel (umts_ipc0).

Starts on a CP that the modem unit (omamobile-modem.service) has brought
ONLINE; --bringup registers it first (bringup.py). Then it serves calls, SMS
and status on a Unix socket, /run/omamobile-sit/socket: one JSON request per
line, one JSON reply per line. Root and members of [control] group may use
it. No radio, NV, SIM or raw-request command is exposed.

  {"action": "status"}                      modem, calls, audio
  {"action": "dial", "number": "+1..."}     an IMS voice call
  {"action": "accept"|"hangup"|"delete-call", "id": "..."}
  {"action": "dtmf", "id": "...", "keys": "12#"}
  {"action": "audio", "what": "mute", "value": "on"|"off"}
  {"action": "sms-send", "request_id": <32 hex>, "number": "...", "text": "..."}
  {"action": "sms-status", "request_id": ...} | {"action": "sms-list"}
  {"action": "sms-delete", "id": "..."}
  {"action": "screen-state", "on": true|false}
  {"action": "radio", "on": true|false}      AT+CFUN, the rollback short of a reboot
  {"action": "subscribe"}                    keep the connection: one
      {"event": "status", "status": {...}} line now and after every change
      (the full private status, with the received SMS IDs). A subscriber
      that can't keep up is dropped and resynchronises by reconnecting.

/run/omamobile-sit/state.json (0644) is the same status without numbers,
for pollers such as the shell's quick settings.
"""
import argparse
import grp
import hashlib
import json
import os
import re
import select
import signal
import socket
import sqlite3
import struct
import subprocess
import time

import cp
import paths
from at import radio
from calls import call_status, dial_payload, ring
import data_call
from data_call import paths as bearer_paths
from ims import REGISTRATION, record_registration
from inbox import persist_sms
from sit import Sit, ModemError
from sms_codec import submit, received_pdu, number
import carrier_manifest
from voice_audio import AudioRefused, VoiceAudio, aoc_card

STATES = {0: 'active', 1: 'held', 2: 'dialing', 3: 'ringing-out', 4: 'ringing-in', 5: 'waiting',
          6: 'terminated', 7: 'held', 8: 'active'}
RATS = {0: '', 1: 'GPRS', 2: 'EDGE', 3: 'UMTS', 9: 'HSDPA', 10: 'HSUPA', 11: 'HSPA',
        14: 'LTE', 15: 'HSPA+', 16: 'GSM', 20: 'LTE-CA', 21: 'NR', 22: 'NR'}
SOCKET = paths.RUN / 'socket'
# GET_RADIO_POWER / IND_RADIO_STATE_CHANGED (MODEM-SIT-RESEARCH 3.1):
# INITIALIZED and STOP_NETWORK are off, START_NETWORK on, POWER_OFF is the
# state without a SIM (M4.1i), RESET is unavailable. GET_RADIO_POWER answers
# 10 with the radio on (cheetah and tegu, 2026-11-02): Android's RadioState
# ON (OFF 0, UNAVAILABLE 1, ON 10).
RADIO = {0: 'off', 1: 'off', 2: 'on', 3: 'off', 4: 'unavailable', 10: 'on'}


def lte_rsrp(payload):
    """LTE RSRP in dBm from a GET_SIGNAL_STRENGTH or IND_SIGNAL_STRENGTH
    payload, or None. Stock's SignalStrengthParserV4: a u16 RAT mask (bit 2
    LTE), then a 196-byte block whose LTE part starts at +0x3c (signal
    strength, RSRP, RSRQ, RSSNR as u32); RSRP is positive (110 is -110 dBm),
    valid 44-140, INT_MAX when unknown."""
    if len(payload) < 2 + 0xc4 or not struct.unpack_from('<H', payload)[0] & 4:
        return None
    rsrp = struct.unpack_from('<I', payload, 2 + 0x40)[0]
    return -rsrp if 44 <= rsrp <= 140 else None


def signal_percent(rsrp):
    """-140..-44 dBm onto 0..100 (ModemManager's SignalQuality), 0 unknown."""
    if rsrp is None:
        return 0
    return max(0, min(100, round((rsrp + 140) * 100 / 96)))
# GET_SIM_STATUS application states, as AOSP's RIL_AppState (the bring-up's
# "(2, 5)" is a USIM, READY; "state 2" is PIN, M4.1).
APP_STATES = {0: 'unknown', 1: 'detected', 2: 'pin', 3: 'puk', 4: 'network-locked', 5: 'ready'}
# 3GPP TS 22.101 10.1.1: 112 and 911 always, and these too without a SIM.
EMERGENCY = ('112', '911')
EMERGENCY_NO_SIM = ('000', '08', '110', '118', '119', '999')
SUBSCRIBERS = 8


class UnconfirmedRelease(RuntimeError):
    """Fatal call ownership failure; never turn this into a socket reply."""


def unconfirmed_release(client, reason):
    """Stop serving an uncertain call without power-cycling the CP.

    In-place modem stops have reset tegu. Radio-off is best effort: even
    an accepted command does not establish that the call was released.
    Keep call ownership and the modem/NV server for an attended reboot.
    """
    print('Call release not confirmed:', reason, flush=True)
    try:
        radio(False)
        print('Recovery radio-off command accepted', flush=True)
    except (OSError, RuntimeError, ValueError) as error:
        print('Recovery radio-off failed:', type(error).__name__, flush=True)
    try:
        payload = client.request(0x0801, timeout=5)
        state = RADIO.get(struct.unpack('<I', payload)[0], 'unknown') if len(payload) == 4 else 'unexpected'
    except (OSError, RuntimeError, ValueError) as error:
        state = 'unavailable (' + type(error).__name__ + ')'
    try:
        modem = cp.STATES.get(cp.state(), 'unknown')
    except OSError:
        modem = 'unavailable'
    print('Unconfirmed release recovery: radio', state, 'CP', modem,
          '; leaving the modem running for an attended reboot', flush=True)
    raise UnconfirmedRelease('Call release was not confirmed; stopping sitd; attended reboot required')


def sim_status(payload):
    """GET_SIM_STATUS without identifiers: the card state, and the USIM's
    (else the first application's) state and PIN/PUK retries. AIDs and
    labels are never read."""
    if len(payload) < 3 or payload[2] > 8 or len(payload) < 3 + payload[2] * 63:
        raise ValueError('Unexpected SIM status layout')
    apps = [payload[i:i + 63] for i in range(3, 3 + payload[2] * 63, 63)]
    app = next((a for a in apps if a[0] == 2), next((a for a in apps if a[0] == 1), apps[0] if apps else None))
    card = payload[0]
    if card == 0:
        return dict(state='absent')
    if card != 1:
        return dict(state='error' if card == 2 else 'unknown')
    if app is None:
        return dict(state='detected')
    status = dict(state=APP_STATES.get(app[1], 'unknown'))
    if status['state'] in ('pin', 'puk', 'ready'):
        # PIN1 state (+57, AOSP RIL_PinState): whether the SIM asks for its
        # PIN at power-on. The RIL has no PIN entry, so "on" means the SIM
        # works here only once the lock is turned off in another phone.
        status.update(pin_retries=app[59], puk_retries=app[60],
                      pin_lock={1: 'on', 2: 'on', 3: 'off', 4: 'on', 5: 'on'}.get(app[57], 'unknown'))
    return status


def database(path):
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA journal_mode=WAL')
    db.execute('PRAGMA synchronous=FULL')
    db.executescript('''
      CREATE TABLE IF NOT EXISTS received (id TEXT PRIMARY KEY, number TEXT, text TEXT, timestamp TEXT, consumed INTEGER DEFAULT 0);
      CREATE TABLE IF NOT EXISTS imported (id TEXT PRIMARY KEY);
      CREATE TABLE IF NOT EXISTS parts (id TEXT PRIMARY KEY, sender TEXT, reference INTEGER, total INTEGER, seq INTEGER, text TEXT, timestamp TEXT, received REAL);
      CREATE TABLE IF NOT EXISTS outgoing (id TEXT PRIMARY KEY, digest TEXT, state TEXT, error TEXT, completed INTEGER DEFAULT 0);
    ''')
    # WAP pushes (MMS notifications) keep their bytes, as hex.
    for table in ('received', 'parts'):
        if 'data' not in {c[1] for c in db.execute(f'PRAGMA table_info({table})')}:
            db.execute(f"ALTER TABLE {table} ADD COLUMN data TEXT NOT NULL DEFAULT ''")
    # A request interrupted by a process restart must never be retried blindly.
    db.execute("UPDATE outgoing SET state='unknown', error='Delivery uncertain after service restart; check with the recipient' WHERE state='sending'")
    db.commit()
    return db


# IND_REG_FAILED (stock ProtocolRegistrationFailedAdapter): 0x08 PLMN (6
# bytes, never logged), 0x0e domain (SIT 1 CS+PS, 2 CS, 3 PS), 0x0f cause and
# 0x10 additional cause (0xff: none), then the cell identity (never logged).
REG_FAILED_DOMAINS = {1: 'CS+PS', 2: 'CS', 3: 'PS'}


def registration_failure(packet):
    """(domain, cause, additional cause) of an IND_REG_FAILED, codes only."""
    if len(packet) < 0x11:
        raise ValueError('short IND_REG_FAILED')
    domain = REG_FAILED_DOMAINS.get(packet[0x0e], f'unknown {packet[0x0e]}')
    cause, additional = (None if b == 0xff else b for b in packet[0x0f:0x11])
    return domain, cause, additional


def operator_name(payload):
    """GET_OPERATOR, best effort for display only (layout from the research
    note, not yet seen on hardware): PLMN digits, then short and long names."""
    plmn = payload[0:6].decode('ascii', 'replace').replace('#', '').strip('\0')
    names = [payload[a:b].split(b'\0', 1)[0].decode('utf-8', 'replace').strip()
             for a, b in ((6, 38), (38, 102))]
    good = [n for n in names if n and n.isprintable()]
    return dict(plmn=plmn if plmn.isdigit() else '', name=good[0] if good else '')


def reset_indication(packet):
    """The log line for IND_PHONE_RESET (0x0804): the payload length and the
    first four payload bytes (packet offsets 0x08-0x0b) in hex. Stock's
    PhoneResetHandler reads a reset type and cause from the payload; which
    of these bytes they are isn't confirmed, so they are shown raw (reset
    codes, no identifiers)."""
    raw = packet[8:12]
    span = f'bytes 0x08..0x{7 + len(raw):02x} = ' + ' '.join(f'{b:02x}' for b in raw) if raw else 'no payload'
    return (f'Modem reset indication (IND_PHONE_RESET, {max(len(packet) - 8, 0)} payload bytes): '
            f'{span} (reset type and cause somewhere here, offsets unconfirmed); not acted on')


class Service:
    def __init__(self, client, db, settings=None):
        self.client = client
        self.db = db
        self.settings = settings or paths.config()
        self.calls = {}
        self.audio = None
        self.audio_error = ''
        self.muted = False
        self.pending = None
        self.hangup_deadline = None
        self.release_unconfirmed = False
        self.screen_on = None
        self.indication_counts = {}
        self.net = dict(reg='unknown', rat='', operator='', plmn='')
        self.last_registration = None
        self.signal = 0
        # The carrier profile: the configured manifest ID ('' off), whether
        # the one reply went out, and the modem's 0x4601 (status, cause).
        self.manifest_setting = self.settings['network'].get('carrier_manifest', '').strip()
        self.manifest_sent = False
        self.carrier_status = None
        # The payload of the latest IND_DATA_CALL_LIST_CHANGED (the modem's
        # own attach bearer shows up there); read by start-up, never logged raw.
        self.data_call_list = None
        self.sim = dict(state='unknown')
        self.radio = 'unknown'
        self.current_stage = 'starting'
        # IMS as start-up left it: unknown (no start-up), off, pending, failed, registered.
        self.ims_state = 'unknown'
        # The internet APN start-up used and where it came from (manual,
        # override, carrier-database or none), and the attach APN (attach;
        # attach_source "same" when it is the internet APN). Empty before
        # start-up.
        self.apn = dict(value='', source='', attach='', attach_source='')
        self.next_poll = 0
        self.published = None
        self.subscribers = []
        self.broadcast_line = None

    def stage(self, name):
        self.current_stage = name
        self.publish()

    def registration(self):
        try:
            return json.loads(REGISTRATION.read_text())
        except (OSError, ValueError):
            return {}

    def ready(self, feature):
        reg = self.registration()
        if reg.get('state') != 2 or not reg.get('features', 0) & feature:
            raise RuntimeError('Cellular service is not registered yet')

    def audio_start(self):
        if self.audio is None:
            audio = self.settings['audio']
            card = aoc_card(audio.get('card', 'none'))
            if card is None:
                print('Call audio routing is off ([audio] card = none)', flush=True)
                return
            # A refused route (protection not running, levels above the
            # earpiece ceilings, earpiece mode refused) never stops the
            # call: it goes on without audio, the reason in the log and
            # in the status's audio error, as with [audio] card = none.
            try:
                self.audio = VoiceAudio(mic_boost_db=audio.getint('mic_boost_db', 6), card=card,
                                        earpiece=audio.getboolean('earpiece', True))
                self.audio.__enter__()
            except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
                self.audio = None
                self.audio_error = str(error)
                print('Call audio refused, the call goes on without audio:', error, flush=True)
                return
            self.audio_error = ''
            self.muted = False

    def audio_stop(self):
        if self.audio is not None:
            audio, self.audio = self.audio, None
            try:
                audio.__exit__(None, None, None)
            except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
                # A cleanup that failed (a control that wouldn't restore,
                # earpiece mode off refused) is logged, never fatal: the
                # service and its calls go on, and the protection service's
                # watchdog keeps the amplifiers safe.
                self.audio_error = str(error)
                print('Call audio cleanup failed (the service goes on):', error, flush=True)
        self.muted = False

    def live(self):
        return [c for c in self.calls.values() if c['state'] != 'terminated']

    def save_calls(self):
        # A restart must not silently abandon a possibly connected call.
        path = paths.RUN / 'active.json'
        tmp = path.with_suffix('.tmp')
        tmp.write_text(json.dumps(self.live()))
        tmp.replace(path)
        self.publish()

    def new_call(self, number, direction, state, modem_id=None):
        call = dict(id=str(time.time_ns()), number=number, direction=direction, state=state,
                    reason='', multiparty=False, modem_id=modem_id, since=time.time())
        self.calls[call['id']] = call
        self.save_calls()
        return call

    def ingest(self, path):
        key = path.stem
        if self.db.execute('SELECT 1 FROM imported WHERE id=?', (key,)).fetchone():
            return
        packet = path.read_bytes()
        ident = struct.unpack_from('<H', packet, 2)[0]
        if ident in (0x010c, 0x0d1e):
            try:
                sms = received_pdu(packet[10:10+packet[9]])
            except (ValueError, IndexError, UnicodeError):
                print('Stored SMS could not be decoded; original retained privately', flush=True)
                return
            concat = sms.pop('concat')
            data = sms.pop('data').hex()
            sms.pop('port')
            if concat:
                ref, total, seq = concat
                self.db.execute('INSERT OR IGNORE INTO parts(id,sender,reference,total,seq,text,timestamp,received,data) VALUES (?,?,?,?,?,?,?,?,?)',
                                (key, sms['number'], ref, total, seq, sms['text'], sms['timestamp'], time.time(), data))
                parts = self.db.execute('SELECT * FROM parts WHERE sender=? AND reference=? AND total=? AND received>? ORDER BY received',
                                        (sms['number'], ref, total, time.time()-86400)).fetchall()
                by_seq = {p['seq']: p for p in parts}
                if len(by_seq) == total:
                    sms['text'] = ''.join(by_seq[i]['text'] for i in range(1, total+1))
                    data = ''.join(by_seq[i]['data'] for i in range(1, total+1))
                    sms['timestamp'] = by_seq[1]['timestamp']
                    self.db.execute('INSERT OR IGNORE INTO received(id,number,text,timestamp,data) VALUES (?,?,?,?,?)',
                                    (key, sms['number'], sms['text'], sms['timestamp'], data))
                    self.db.execute('DELETE FROM parts WHERE sender=? AND reference=? AND total=?', (sms['number'], ref, total))
            else:
                self.db.execute('INSERT OR IGNORE INTO received(id,number,text,timestamp,data) VALUES (?,?,?,?,?)',
                                (key, sms['number'], sms['text'], sms['timestamp'], data))
        self.db.execute('INSERT OR IGNORE INTO imported VALUES (?)', (key,))
        self.db.commit()

    def event(self, packet):
        ident = struct.unpack_from('<H', packet, 2)[0]
        key = f'{ident:04x}'
        self.indication_counts[key] = self.indication_counts.get(key, 0) + 1
        if ident in (0x010c, 0x010d, 0x0d1e, 0x0d20):
            reference = persist_sms(packet)
            self.client.request(0x0d1d if ident >= 0x0d00 else 0x0102, struct.pack('<IBI', 1, reference, 0))
            print('SMS stored and acknowledged', flush=True)
            for path in paths.INBOX.glob('*.sit'):
                self.ingest(path)
            self.publish()
        elif ident == 0x0d05:
            record_registration(packet)
            self.publish()
        elif ident == 0x0802:
            # IND_RADIO_STATE_CHANGED: u32 at 0x08. Re-read the network too.
            if len(packet) >= 12:
                self.radio = RADIO.get(struct.unpack_from('<I', packet, 8)[0], 'unknown')
            self.next_poll = 0
            self.publish()
        elif ident == 0x0804:
            # IND_PHONE_RESET: the CP asks for a reset (after a carrier
            # profile changed its NV, among stock's reasons). Logged only;
            # nothing resets the CP in place.
            print(reset_indication(packet), flush=True)
        elif ident == 0x0210:
            # IND_SIM_STATUS_CHANGED carries nothing we read: poll again.
            self.next_poll = 0
        elif ident == 0x0906:
            # IND_SIGNAL_STRENGTH, every second or two: publish on a change only.
            signal = signal_percent(lte_rsrp(packet[8:]))
            if signal != self.signal:
                self.signal = signal
                self.publish()
        elif ident == 0x4601:
            # OEM_IND_CARRIER_CONFIG_STATUS: codes only.
            self.carrier_status = carrier_manifest.status(packet)
            print('Carrier config status from the modem:', self.carrier_status[0],
                  'cause', self.carrier_status[1], flush=True)
        elif ident == 0x4602:
            # OEM_IND_CARRIER_CONFIG_SIM_INFO: the modem asks for a carrier
            # manifest. Only a trigger: its payload (SIM identities) is never read.
            self.answer_carrier_request()
        elif ident == 0x0604:
            # IND_DATA_CALL_LIST_CHANGED: kept for start-up's search for the
            # modem's attach bearer (bringup.find_attach_bearer).
            self.data_call_list = bytes(packet[8:])
        elif ident == 0x070e:
            # IND_NTW_STATE_CHANGED: read the registration again soon (it
            # can come every second or two while the modem searches).
            self.next_poll = min(self.next_poll, time.monotonic() + 5)
        elif ident == 0x074a:
            domain, cause, additional = registration_failure(packet)
            print('Registration failed: domain', domain, 'cause', cause,
                  'additional cause', additional, flush=True)
            self.next_poll = 0
        elif ident == 0x0d01:
            if len(packet) < 13:
                raise ValueError('Truncated incoming call')
            found = ring(packet)
            if found is None or found[0] != 1:
                return
            _, mid, caller = found
            if any(c['modem_id'] == mid for c in self.live()):
                return
            # No auto-answer: a client presents the call and the user answers.
            self.new_call(caller, 'incoming', 'ringing-in', mid)
            print('Incoming call ringing', flush=True)
        elif ident == 0x0d04:
            kind, mid, state, cause = call_status(packet)
            if kind != 1:
                return
            call = next((c for c in self.live() if c['modem_id'] == mid), None)
            if call is None and self.pending:
                call = self.calls[self.pending]
                call['modem_id'] = mid
                self.pending = None
            if call is None:
                return
            call['state'] = STATES[state]
            call['since'] = time.time()
            if state == 6:
                call['reason'] = 'terminated' if cause == 16 else 'error'
                if not self.live():
                    self.audio_stop()
                    self.hangup_deadline = None
            self.save_calls()

    def answer_carrier_request(self):
        if not self.manifest_setting:
            print('The modem asked for a carrier config; not answered (carrier_manifest is empty)', flush=True)
            return
        if self.manifest_sent:
            print('The modem asked for a carrier config again; answered once already', flush=True)
            return
        try:
            ident = carrier_manifest.manifest_id(self.manifest_setting)
        except ValueError as error:
            print('The modem asked for a carrier config; not answered:', error, flush=True)
            return
        self.manifest_sent = True
        try:
            self.client.request(0x4600, carrier_manifest.request_payload(ident), timeout=10,
                                manifest_reply=True)
            print('Carrier manifest', ident.hex()[:8], 'sent in answer to the modem', flush=True)
        except (ModemError, TimeoutError) as error:
            # Not resent: the modem's own status (0x4601) or a reboot decides.
            print('Carrier manifest not accepted:', error, flush=True)

    def poll(self):
        """Read-only network status every 30 s (and at once after a change)."""
        if time.monotonic() < self.next_poll:
            return
        self.next_poll = time.monotonic() + 30
        # GET_SIM_STATUS and GET_RADIO_POWER: the probe's read-only requests.
        try:
            self.sim = sim_status(self.client.request(0x0200, timeout=5))
        except (ModemError, TimeoutError, ValueError) as error:
            print('SIM status poll failed:', type(error).__name__, flush=True)
        try:
            value = self.client.request(0x0801, timeout=5)
            if len(value) >= 4:
                self.radio = RADIO.get(struct.unpack_from('<I', value)[0], 'unknown')
        except (ModemError, TimeoutError) as error:
            print('Radio state poll failed:', type(error).__name__, flush=True)
        try:
            ps = self.client.request(0x0701, timeout=5)
            if len(ps) >= 4:
                self.net['reg'] = {0: 'not-registered', 1: 'home', 2: 'searching', 3: 'denied',
                                   5: 'roaming'}.get(ps[0], 'unknown')
                self.net['rat'] = RATS.get(ps[3], str(ps[3]))
                # Each change of state, reject cause or RAT, codes only.
                if (ps[0], ps[1], ps[3]) != self.last_registration:
                    self.last_registration = (ps[0], ps[1], ps[3])
                    print('Packet registration:', f"{self.net['reg']} (state {ps[0]}), reject {ps[1]}, RAT {ps[3]}",
                          flush=True)
            if ps and ps[0] in (1, 5):
                self.net.update(operator_name(self.client.request(0x0702, timeout=5)))
            elif len(ps) >= 4:
                # Not registered: no operator to show (not the last one seen).
                self.net.update(operator='', plmn='')
        except (ModemError, TimeoutError, ValueError) as error:
            print('Status poll failed:', type(error).__name__, flush=True)
        self.publish()

    def pump(self):
        for _ in range(256):
            packet = self.client.next_indication(0)
            if packet is None:
                break
            self.event(packet)
        if self.hangup_deadline and time.monotonic() > self.hangup_deadline:
            self.release_unconfirmed = True
            unconfirmed_release(self.client, 'hangup deadline expired')

    def send_sms(self, request):
        key = request.get('request_id', '')
        if not isinstance(key, str) or len(key) != 32 or any(c not in '0123456789abcdef' for c in key):
            raise ValueError('Invalid send request identifier')
        destination = number(request['number'])
        text = request['text']
        pdus = submit(destination, text)
        digest = hashlib.sha256(json.dumps([destination, text]).encode()).hexdigest()
        prior = self.db.execute('SELECT * FROM outgoing WHERE id=?', (key,)).fetchone()
        if prior:
            if prior['digest'] != digest:
                raise ValueError('Send request identifier was reused')
            return dict(prior)
        self.ready(2)
        smsc = self.client.request(0x0108)
        if len(smsc) != 13 or not 1 <= smsc[0] <= 12:
            raise RuntimeError('Carrier SMS configuration is unavailable')
        self.db.execute('INSERT INTO outgoing VALUES (?,?,?,?,?)', (key, digest, 'sending', '', 0))
        self.db.commit()
        completed = 0
        state = 'sent'
        error = ''
        try:
            for pdu in pdus:
                payload = bytearray(260)
                payload[:13] = smsc
                payload[13] = len(pdu)
                payload[14:14+len(pdu)] = pdu
                result = self.client.request(0x0d1b, bytes(payload), timeout=90)
                if len(result) < 253:
                    raise TimeoutError('Unknown SMS response')
                cause = struct.unpack_from('<I', result, 249)[0]
                if cause:
                    raise ModemError(cause, b'')
                completed += 1
                self.db.execute('UPDATE outgoing SET completed=? WHERE id=?', (completed, key))
                self.db.commit()
                self.pump()
        except ModemError:
            state = 'unknown' if completed else 'failed'
            error = ('Some message parts were sent; check with the recipient before sending again'
                     if completed else 'The carrier rejected this message')
        except (OSError, RuntimeError, TimeoutError):
            state = 'unknown'
            error = 'Delivery uncertain; check with the recipient before sending again'
        self.db.execute('UPDATE outgoing SET state=?,error=? WHERE id=?', (state, error, key))
        self.db.commit()
        return dict(state=state, error=error, completed=completed)

    def status(self, *, public=False):
        reg = self.registration()
        voice = reg.get('state') == 2 and reg.get('features', 0) & 1 != 0
        sms = reg.get('state') == 2 and reg.get('features', 0) & 2 != 0
        data = bearer_paths(data_call.INTERNET_CID)[0].exists()
        modem = dict(present=True, stage=self.current_stage, ready=voice,
                     state='registered' if self.net['reg'] in ('home', 'roaming') else 'searching',
                     registration=self.net['reg'], tech=self.net['rat'],
                     operator=self.net['operator'] or self.net['plmn'],
                     plmn=self.net['plmn'], operator_name=self.net['operator'],
                     voice=voice, sms=sms, data=data,
                     signal=self.signal if self.net['reg'] in ('home', 'roaming') else 0, audio=True,
                     radio=self.radio, sim=dict(self.sim),
                     ims='registered' if voice or sms else self.ims_state,
                     apn=dict(self.apn), data_available=self.apn.get('source') != 'none',
                     emergency_numbers=list(EMERGENCY + (EMERGENCY_NO_SIM if self.sim['state'] == 'absent' else ())))
        calls = [{k: v for k, v in c.items() if k != 'modem_id'} for c in self.calls.values()]
        if public:
            # No numbers in the world-readable copy.
            calls = [dict(state=c['state'], direction=c['direction']) for c in calls]
            unread = self.db.execute('SELECT COUNT(*) FROM received WHERE consumed=0').fetchone()[0]
            return dict(modem=modem, calls=calls, sms=dict(unread=unread), updated=int(time.time()))
        received = [r[0] for r in self.db.execute('SELECT id FROM received WHERE consumed=0 ORDER BY rowid')]
        return dict(modem=modem, calls=calls, sms=dict(received=['sit:' + i for i in received]),
                    audio=dict(available=True, running=self.audio is not None, mute=self.muted,
                               speaker=getattr(self.audio, 'tegu', False) is True, speaker_available=False, error=self.audio_error))

    def subscribe(self, connection):
        """Keep an authorised connection for status events; refuse beyond
        SUBSCRIBERS. The caller has already sent the request's reply."""
        if len(self.subscribers) >= SUBSCRIBERS:
            raise RuntimeError('Too many subscribers')
        connection.setblocking(False)
        self.subscribers.append(connection)
        self.broadcast(force=connection)

    def broadcast(self, force=None):
        """Send the private status to every subscriber when it changed (and
        to a new one at once). A subscriber whose buffer is full or that hung
        up is dropped: it reconnects and gets a full status again."""
        if not self.subscribers:
            self.broadcast_line = None
            return
        line = (json.dumps(dict(event='status', status=self.status())) + '\n').encode()
        if line == self.broadcast_line and force is None:
            return
        targets = self.subscribers if line != self.broadcast_line else [force]
        self.broadcast_line = line
        for connection in list(targets):
            try:
                if connection.send(line) != len(line):
                    raise BlockingIOError
            except OSError:
                self.drop(connection)

    def drop(self, connection):
        if connection in self.subscribers:
            self.subscribers.remove(connection)
        connection.close()

    def reap(self):
        """Drop subscribers that hung up (they never send after subscribing)."""
        if not self.subscribers:
            return
        readable, _, _ = select.select(self.subscribers, [], [], 0)
        for connection in readable:
            try:
                data = connection.recv(4096)
            except BlockingIOError:
                continue
            except OSError:
                data = b''
            if not data:
                self.drop(connection)

    def publish(self):
        state = self.status(public=True)
        compare = {k: v for k, v in state.items() if k != 'updated'}
        if compare == self.published:
            return
        self.published = compare
        path = paths.RUN / 'state.json'
        tmp = path.with_suffix('.tmp')
        tmp.write_text(json.dumps(state))
        tmp.chmod(0o644)
        tmp.replace(path)

    def dispatch(self, request):
        action = request.get('action')
        if action == 'screen-state':
            on = request.get('on')
            if type(on) is not bool:
                raise ValueError('Screen state must be boolean')
            if not on and self.live():
                raise RuntimeError('Call in progress')
            if on != self.screen_on:
                # Stock SetScreenState: SIT 0902, uint32 (off=0, on=1).
                self.screen_on = None
                self.client.request(0x0902, struct.pack('<I', int(on)), timeout=5)
                # Stock unsolicited-response filter: the AOSP IndicationFilter
                # mask in SIT 0928 (uint32). NONE suppresses optional
                # signal/dormancy reports, not calls, SMS or significant
                # registration/data changes. ALL restores foreground
                # reporting. Cache only after both replies succeed.
                self.client.request(0x0928, struct.pack('<I', 0xffffffff if on else 0), timeout=5)
                self.screen_on = on
            return dict(screen_on=self.screen_on)
        if action == 'radio':
            # The rollback for a running registration short of a reboot:
            # AT+CFUN, as the start-up uses. Bearers and IMS go with it.
            on = request.get('on')
            if type(on) is not bool:
                raise ValueError('Radio state must be boolean')
            if not on and self.live():
                raise RuntimeError('Call in progress')
            radio(on)
            self.next_poll = 0
            return dict(radio='on' if on else 'off')
        if action == 'power-status':
            return dict(screen_on=self.screen_on, indications=dict(self.indication_counts))
        if action == 'status':
            return self.status()
        if action == 'sms-list':
            return [dict(id='sit:'+r['id'], number=r['number'], text=r['text'], timestamp=r['timestamp'],
                         data=r['data'], state='received')
                    for r in self.db.execute('SELECT * FROM received WHERE consumed=0')]
        if action == 'sms-delete':
            self.db.execute('UPDATE received SET consumed=1 WHERE id=?', (request['id'].removeprefix('sit:'),))
            self.db.commit()
            self.publish()
            return {}
        if action == 'sms-send':
            return self.send_sms(request)
        if action == 'sms-status':
            row = self.db.execute('SELECT state,error,completed FROM outgoing WHERE id=?',
                                  (request.get('request_id'),)).fetchone()
            return dict(row) if row else dict(state='unknown', error='Send outcome has not been confirmed')
        if action == 'dial':
            self.ready(1)
            if self.live():
                raise RuntimeError('End the current call before placing another')
            destination = number(request['number'], voice=True)
            calls = self.client.request(0x0000)
            if calls != bytes(4):
                raise RuntimeError('The modem already has a call')
            self.audio_start()
            call = self.new_call(destination, 'outgoing', 'dialing')
            self.pending = call['id']
            try:
                self.client.request(0x0d00, dial_payload(destination), timeout=8)
            except ModemError:
                call['state'] = 'terminated'
                call['reason'] = 'error'
                self.pending = None
                self.audio_stop()
                self.save_calls()
                raise RuntimeError('The carrier rejected the call')
            except (TimeoutError, OSError):
                # Keep ownership and resolve queued status before any repeat.
                self.hangup_deadline = time.monotonic() + 12
                raise RuntimeError('Call setup is uncertain; checking the modem')
            self.pump()
            return dict(call=call['id'], number=destination)
        if action in ('accept', 'hangup', 'delete-call'):
            call = self.calls.get(str(request.get('id')))
            if call is None:
                raise ValueError('This call is no longer available')
            if action == 'delete-call':
                if call['state'] != 'terminated':
                    raise RuntimeError('Call has not ended')
                del self.calls[call['id']]
                self.publish()
                return {}
            if call['state'] == 'terminated':
                return {}
            if call['modem_id'] is None:
                raise RuntimeError('Call setup is still pending')
            if action == 'accept':
                if call['state'] not in ('ringing-in', 'waiting'):
                    raise RuntimeError('Call is not ringing')
                if len(self.live()) != 1:
                    raise RuntimeError('Call waiting is not supported yet')
                self.audio_start()
                try:
                    # Ordinary voice, audio send/receive, no video.
                    self.client.request(0x0d02, struct.pack('<HHH', 1, 1, 0))
                except BaseException:
                    self.hangup_deadline = time.monotonic() + 12
                    raise
            else:
                self.hangup_deadline = time.monotonic() + 12
                self.client.request(0x0d03, bytes([call['modem_id'], 1, 0]))
            self.pump()
            return {}
        if action == 'audio':
            if self.audio is None:
                raise RuntimeError('No call audio is running')
            if request.get('what') == 'speaker':
                raise RuntimeError('Speakerphone routing is not configured yet')
            if request.get('what') != 'mute' or request.get('value') not in ('on', 'off'):
                raise ValueError('Invalid audio command')
            self.muted = request['value'] == 'on'
            self.audio.mixer('cset', 'Incall Mic Mute', '1' if self.muted else '0')
            return self.status()['audio']
        if action == 'dtmf':
            call = self.calls.get(str(request.get('id')))
            keys = request.get('keys', '')
            if call is None or call['state'] != 'active' or call['modem_id'] is None:
                raise RuntimeError('Touch tones require an active call')
            if not isinstance(keys, str) or not re.fullmatch(r'[0-9*#]{1,32}', keys):
                raise ValueError('Invalid touch tones')
            # Stock SendDtmf: call ID, one-shot type=0, ASCII digit.
            for key in keys:
                self.client.request(0x0d0a, bytes([call['modem_id'], 0, ord(key)]))
            return {}
        raise ValueError('Unsupported phone action')


def allowed_uids(group):
    """Root and the members of the control group (by membership or as their
    primary group)."""
    uids = {0, os.getuid()}
    try:
        entry = grp.getgrnam(group)
    except KeyError:
        return uids, None
    import pwd
    for account in pwd.getpwall():
        if account.pw_gid == entry.gr_gid or account.pw_name in entry.gr_mem:
            uids.add(account.pw_uid)
    return uids, entry.gr_gid


def notify(message):
    """sd_notify without libsystemd."""
    target = os.environ.get('NOTIFY_SOCKET')
    if not target:
        return
    if target.startswith('@'):
        target = '\0' + target[1:]
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
        sock.connect(target)
        sock.sendall(message.encode())


def serve_one(service, connection, clients):
    """One request on one connection. True if the connection became a
    subscriber (the caller then keeps it open)."""
    connection.settimeout(2)
    try:
        _, uid, _ = struct.unpack('3i', connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
        if uid not in clients:
            raise PermissionError('Phone service access denied')
        body = b''
        while b'\n' not in body:
            chunk = connection.recv(4096)
            if not chunk:
                raise ValueError('Incomplete phone request')
            body += chunk
            if len(body) > 32768:
                raise ValueError('Phone request too large')
        request = json.loads(body.split(b'\n', 1)[0])
        if isinstance(request, dict) and request.get('action') == 'subscribe':
            if len(service.subscribers) >= SUBSCRIBERS:
                raise RuntimeError('Too many subscribers')
            connection.sendall(json.dumps(dict(ok=True, result=dict(subscribed=True))).encode() + b'\n')
            service.subscribe(connection)
            return True
        result = service.dispatch(request)
        response = dict(ok=True, result=result)
    except UnconfirmedRelease:
        connection.close()
        raise
    except (ValueError, KeyError, TypeError, RuntimeError, OSError) as error:
        # Errors from wire data must never expose raw values.
        response = dict(ok=False, error=str(error) if isinstance(error, RuntimeError)
                        else 'Invalid or unavailable phone request')
    try:
        connection.sendall(json.dumps(response).encode() + b'\n')
    except OSError:
        pass  # Durable send IDs prevent uncertain retries.
    return False


def probe():
    """Read-only first contact (MODEM-PLAN M4.1): SIM card and application
    states, radio state, packet registration, NR mode, whether an SMSC is
    set. No identifiers are printed; nothing is changed.

    A failed/empty SMSC reply with a present SIM leaves SMS configuration
    unverified; SMSC error 11 is expected only when no SIM is present.
    """
    client = Sit()
    failed = False
    try:
        # The CP answered the first request 9.4 s after ONLINE on 2026-11-02.
        sim = client.request(0x0200, timeout=20)
        if len(sim) >= 3 and sim[2] <= 8 and len(sim) >= 3 + sim[2] * 63:
            print('SIM card state', sim[0], 'applications',
                  [(sim[i], sim[i + 1]) for i in range(3, 3 + sim[2] * 63, 63)], flush=True)
        else:
            print('SIM status layout unexpected, length', len(sim), flush=True)
            raise SystemExit(1)
        for ident, label in ((0x0801, 'radio state'), (0x0701, 'packet registration'),
                             (0x0749, 'NR mode'), (0x0711, 'PS service')):
            try:
                value = client.request(ident)
                if ident == 0x0801 and len(value) == 4:
                    print(label, struct.unpack('<I', value)[0], flush=True)
                elif ident == 0x0701 and len(value) >= 4:
                    print(label, 'state', value[0], 'reject', value[1], 'RAT', value[3], flush=True)
                else:
                    print(label, list(value[:4]), flush=True)
                    if ident in (0x0801, 0x0701) or not value:
                        failed = True
            except (ModemError, TimeoutError) as error:
                print(label, 'unavailable:', error, flush=True)
                failed = True
        try:
            smsc = client.request(0x0108)
            print('SMSC present', bool(smsc and smsc[0]), flush=True)
            if not smsc:
                failed = True
        except (ModemError, TimeoutError) as error:
            print('SMSC unavailable:', error, flush=True)
            # Without a SIM the CP legitimately rejects the SMSC request.
            if not (sim[0] == 0 and isinstance(error, ModemError) and error.error == 11):
                failed = True
    finally:
        client.close()

    if failed:
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description='Omarchy Mobile SIT RIL: calls, SMS and data registration')
    parser.add_argument('--bringup', action='store_true', help='register a freshly booted CP first')
    parser.add_argument('--probe', action='store_true', help='read-only status queries, then exit')
    args = parser.parse_args()
    os.umask(0o077)
    settings = paths.config()
    paths.private_dir(paths.RUN)
    paths.private_dir(paths.STATE)
    if not cp.online():
        raise SystemExit('CP is not ONLINE: start omamobile-modem.service first')
    if args.probe:
        return probe()
    client = Sit(allow_sms=True, allow_calls=True,
                 allow_manifest=bool(settings['network'].get('carrier_manifest', '').strip()),
                 allow_isim_pcscf=settings['network'].getboolean('ims_pcscf_from_isim', True))
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    service = None
    stopping = False

    def stop(*_):
        nonlocal stopping
        stopping = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        marker = paths.RUN / 'active.json'
        if marker.exists() and json.loads(marker.read_text()):
            unconfirmed_release(client, 'a call from the previous service run was never released')
        service = Service(client, database(paths.STATE / 'apps.db'), settings)
        service.publish()
        for sms in paths.INBOX.glob('*.sit'):
            service.ingest(sms)
        if args.bringup:
            from bringup import start
            start(service, settings, lambda: stopping)
        service.stage('running')
        SOCKET.unlink(missing_ok=True)
        server.bind(str(SOCKET))
        server.listen(16)
        server.settimeout(.1)
        # The control group reaches the socket through the directory's group
        # bit; the rest of /run/omamobile-sit stays root's (0600 files).
        clients, gid = allowed_uids(settings['control'].get('group', 'wheel'))
        if gid is not None and os.getuid() == 0:
            os.chown(paths.RUN, 0, gid)
            paths.RUN.chmod(0o710)
            os.chown(SOCKET, 0, gid)
            SOCKET.chmod(0o660)
        notify('READY=1\nSTATUS=registered')
        print('Calls and SMS service ready', flush=True)
        # Set by a device whose modem sends signal reports only after it's
        # told the screen is on (the Pixel 9a's drop-in), while nothing else
        # sends the screen state yet. Never set on the 7 Pro.
        if args.bringup and os.environ.get('OMAMOBILE_SIT_SCREEN_ON_AT_START') == '1' \
                and service.screen_on is None:
            service.dispatch(dict(action='screen-state', on=True))
        next_cp_check = 0
        while not stopping:
            service.pump()
            service.poll()
            if time.monotonic() >= next_cp_check:
                if not cp.online():
                    raise RuntimeError('CP left ONLINE; the modem unit keeps its crash record')
                next_cp_check = time.monotonic() + 2
            # next_indication(0) drains queued packets, but a positive timeout
            # is needed to read newly arrived device bytes.
            packet = client.next_indication(.05)
            if packet:
                service.event(packet)
            service.reap()
            service.broadcast()
            try:
                connection, _ = server.accept()
            except socket.timeout:
                continue
            if not serve_one(service, connection, clients):
                connection.close()
            service.broadcast()
    finally:
        try:
            if service and service.live() and not service.release_unconfirmed:
                for call in service.live():
                    if call['modem_id'] is not None:
                        try:
                            client.request(0x0d03, bytes([call['modem_id'], 1, 0]))
                        except (OSError, RuntimeError):
                            pass
                end = time.monotonic() + 8
                while service.live() and time.monotonic() < end:
                    packet = client.next_indication(.25)
                    if packet:
                        service.event(packet)
                if service.live():
                    service.release_unconfirmed = True
                    unconfirmed_release(client, 'a call release was not confirmed at service stop')
        finally:
            try:
                if service:
                    service.audio_stop()
            finally:
                if service:
                    for connection in list(service.subscribers):
                        service.drop(connection)
                client.close()
                server.close()
                SOCKET.unlink(missing_ok=True)
                (paths.RUN / 'state.json').unlink(missing_ok=True)


if __name__ == '__main__':
    main()
