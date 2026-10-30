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
  {"action": "sim-pin", "pin": "1234"}      VERIFY_SIM_PIN once, only while the
      SIM asks for its PIN and has at least two tries left; never retried
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
import time

import cp
import paths
from at import radio
from calls import call_status, dial_payload, ring
from data_call import paths as bearer_paths
from ims import REGISTRATION, record_registration
from inbox import persist_sms
from sit import Sit, ModemError
import sit_signal
from sms_codec import submit, received_pdu, number
from voice_audio import VoiceAudio, aoc_card

STATES = {0: 'active', 1: 'held', 2: 'dialing', 3: 'ringing-out', 4: 'ringing-in', 5: 'waiting',
          6: 'terminated', 7: 'held', 8: 'active'}
RATS = {0: '', 1: 'GPRS', 2: 'EDGE', 3: 'UMTS', 9: 'HSDPA', 10: 'HSUPA', 11: 'HSPA',
        14: 'LTE', 15: 'HSPA+', 16: 'GSM', 20: 'LTE-CA', 21: 'NR', 22: 'NR'}
SOCKET = paths.RUN / 'socket'
# GET_RADIO_POWER / IND_RADIO_STATE_CHANGED (MODEM-SIT-RESEARCH 3.1):
# INITIALIZED and STOP_NETWORK are off, START_NETWORK on, POWER_OFF is the
# state without a SIM (M4.1i), RESET is unavailable.
RADIO = {0: 'off', 1: 'off', 2: 'on', 3: 'off', 4: 'unavailable'}
# GET_SIM_STATUS application states, as AOSP's RIL_AppState (the bring-up's
# "(2, 5)" is a USIM, READY; "state 2" is PIN, M4.1).
APP_STATES = {0: 'unknown', 1: 'detected', 2: 'pin', 3: 'puk', 4: 'network-locked', 5: 'ready'}
# 3GPP TS 22.101 10.1.1: 112 and 911 always, and these too without a SIM.
EMERGENCY = ('112', '911')
EMERGENCY_NO_SIM = ('000', '08', '110', '118', '119', '999')
SUBSCRIBERS = 8
SIGNAL_REFRESH = 10


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
        status.update(pin_retries=app[59], puk_retries=app[60])
    return status


def bearer_ip():
    try:
        record = json.loads((paths.RUN / 'bearer-ip.json').read_text())
    except (OSError, ValueError):
        return None
    return record if isinstance(record, dict) else None


def pin_payload(status_payload, pin):
    """VERIFY_SIM_PIN (MODEM-SIT-RESEARCH 3.2, len 38): PIN length, the PIN
    as ASCII digits in 8 bytes, the USIM's AID length and AID in 16. The AID
    is read here and sent back only; never logged or published."""
    if not isinstance(pin, str) or not re.fullmatch(r'[0-9]{4,8}', pin):
        raise ValueError('A SIM PIN is 4 to 8 digits')
    apps = [status_payload[i:i + 63] for i in range(3, 3 + status_payload[2] * 63, 63)]
    usim = next((a for a in apps if a[0] == 2), None)
    if usim is None or not 1 <= usim[3] <= 16:
        raise RuntimeError('No USIM application to unlock')
    return (bytes([len(pin)]) + pin.encode('ascii').ljust(8, b'\0') +
            bytes([usim[3]]) + bytes(usim[4:4 + usim[3]]).ljust(16, b'\0'))


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


def operator_name(payload):
    """GET_OPERATOR, best effort for display only (layout from the research
    note, not yet seen on hardware): PLMN digits, then short and long names."""
    plmn = payload[0:6].decode('ascii', 'replace').replace('#', '').strip('\0')
    names = [payload[a:b].split(b'\0', 1)[0].decode('utf-8', 'replace').strip()
             for a, b in ((6, 38), (38, 102))]
    good = [n for n in names if n and n.isprintable()]
    return dict(plmn=plmn if plmn.isdigit() else '', name=good[0] if good else '')


class Service:
    def __init__(self, client, db, settings=None):
        self.client = client
        self.db = db
        self.settings = settings or paths.config()
        self.calls = {}
        self.audio = None
        self.muted = False
        self.pending = None
        self.hangup_deadline = None
        self.screen_on = None
        self.indication_counts = {}
        self.net = dict(reg='unknown', rat='', operator='', plmn='')
        self.sim = dict(state='unknown')
        self.radio = 'unknown'
        self.current_stage = 'starting'
        # IMS as start-up left it: unknown (no start-up), off, pending, failed, registered.
        self.ims_state = 'unknown'
        self.next_poll = 0
        self.published = None
        self.subscribers = []
        self.broadcast_line = None
        # IND_SIGNAL_STRENGTH, decoded (sit_signal.py): MM's quality and the
        # LTE/NR values, refreshed at most every SIGNAL_REFRESH s.
        self.signal = dict(quality=0, detail=None, at=0)

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
            self.audio = VoiceAudio(mic_boost_db=audio.getint('mic_boost_db', 6), card=card)
            try:
                self.audio.__enter__()
            except BaseException:
                self.audio = None
                raise
            self.muted = False

    def audio_stop(self):
        if self.audio is not None:
            audio, self.audio = self.audio, None
            audio.__exit__(None, None, None)
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
        elif ident == 0x0906:
            decoded = sit_signal.decode(packet[8:])
            now = time.monotonic()
            quality = sit_signal.quality(decoded, self.net['rat'])
            if decoded is None:
                return
            detail = {rat: {k: round(v) for k, v in decoded[rat].items()} for rat in ('lte', 'nr')
                      if rat in decoded}
            changed = abs(quality - self.signal['quality']) >= 5 or self.signal['detail'] is None
            if changed or now - self.signal['at'] >= SIGNAL_REFRESH:
                self.signal = dict(quality=quality, detail=dict(detail, layout=decoded['layout']), at=now)
                self.publish()
            else:
                self.signal['seen'] = now
        elif ident == 0x0d05:
            record_registration(packet)
            self.publish()
        elif ident == 0x0802:
            # IND_RADIO_STATE_CHANGED: u32 at 0x08. Re-read the network too.
            if len(packet) >= 12:
                self.radio = RADIO.get(struct.unpack_from('<I', packet, 8)[0], 'unknown')
            self.next_poll = 0
            self.publish()
        elif ident == 0x0210:
            # IND_SIM_STATUS_CHANGED carries nothing we read: poll again.
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

    def poll(self):
        """Read-only network status every 30 s (and at once after a change)."""
        if time.monotonic() < self.next_poll:
            return
        self.next_poll = time.monotonic() + 30
        if self.signal['detail'] is not None and \
                time.monotonic() - self.signal.get('seen', self.signal['at']) > 90:
            # No report for 90 s (the screen-off filter, or no service).
            self.signal = dict(quality=0, detail=None, at=0)
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
            cp.stop_modem('a call release was not confirmed')
            raise RuntimeError('Call release was not confirmed; modem stopped')

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

    def verify_pin(self, pin):
        """One VERIFY_SIM_PIN, on the user's request only. Refused unless the
        SIM is asking for its PIN right now with two or more tries left: the
        last try (and a PUK) belongs in another phone, where a mistake can't
        cost the SIM. Nothing here retries; the PIN is never logged."""
        payload = self.client.request(0x0200, timeout=5)
        self.sim = sim_status(payload)
        self.publish()
        if self.sim['state'] != 'pin':
            raise RuntimeError('The SIM is not asking for its PIN')
        if self.sim.get('pin_retries', 0) < 2:
            raise RuntimeError('One PIN try left: enter it in another phone '
                               '(a wrong one locks the SIM to its PUK)')
        body = pin_payload(payload, pin)
        pin = None
        self.next_poll = 0
        try:
            result = self.client.request(0x0201, body, timeout=20)
        except ModemError as error:
            # Stock reads the tries left as a u32 at the start of the reply,
            # error 3 (RCM_E_PASSWORD_INCORRECT) meaning a wrong PIN.
            left = struct.unpack_from('<I', error.payload)[0] if len(error.payload) >= 4 else None
            if error.error == 3:
                print('SIM PIN rejected;', 'unknown' if left is None else left, 'tries left', flush=True)
                raise RuntimeError('Wrong SIM PIN' + ('' if left is None else f'; {left} tries left')) from None
            print('SIM PIN request failed with error', error.error, flush=True)
            raise RuntimeError('The SIM PIN request failed') from None
        except TimeoutError:
            raise RuntimeError('The SIM PIN result is unknown; check the SIM state before trying again') from None
        finally:
            body = None
        print('SIM PIN accepted', flush=True)
        return dict(accepted=True, tries_left=struct.unpack_from('<I', result)[0] if len(result) >= 4 else None)

    def status(self, *, public=False):
        reg = self.registration()
        voice = reg.get('state') == 2 and reg.get('features', 0) & 1 != 0
        sms = reg.get('state') == 2 and reg.get('features', 0) & 2 != 0
        data = bearer_paths(1)[0].exists()
        modem = dict(present=True, stage=self.current_stage, ready=voice,
                     state='registered' if self.net['reg'] in ('home', 'roaming') else 'searching',
                     registration=self.net['reg'], tech=self.net['rat'],
                     operator=self.net['operator'] or self.net['plmn'],
                     plmn=self.net['plmn'], operator_name=self.net['operator'],
                     voice=voice, sms=sms, data=data, signal=self.signal['quality'], audio=True,
                     signal_detail=self.signal['detail'],
                     radio=self.radio, sim=dict(self.sim),
                     ims='registered' if voice or sms else self.ims_state,
                     emergency_numbers=list(EMERGENCY + (EMERGENCY_NO_SIM if self.sim['state'] == 'absent' else ())))
        calls = [{k: v for k, v in c.items() if k != 'modem_id'} for c in self.calls.values()]
        if public:
            # No numbers in the world-readable copy.
            calls = [dict(state=c['state'], direction=c['direction']) for c in calls]
            unread = self.db.execute('SELECT COUNT(*) FROM received WHERE consumed=0').fetchone()[0]
            return dict(modem=modem, calls=calls, sms=dict(unread=unread), updated=int(time.time()))
        received = [r[0] for r in self.db.execute('SELECT id FROM received WHERE consumed=0 ORDER BY rowid')]
        # The addresses omamobile-sit-data configured (private: never in
        # state.json or a log); omamobile-mmd's bearer Ip4Config/Ip6Config.
        modem = dict(modem, bearer=bearer_ip() if data else None)
        return dict(modem=modem, calls=calls, sms=dict(received=['sit:' + i for i in received]),
                    audio=dict(available=True, running=self.audio is not None, mute=self.muted,
                               speaker=False, speaker_available=False, error=''))

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
        if action == 'sim-pin':
            return self.verify_pin(request.get('pin'))
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
    except (ValueError, KeyError, TypeError, RuntimeError, OSError) as error:
        # Errors from wire data must never expose raw values.
        response = dict(ok=False, error=str(error) if isinstance(error, RuntimeError)
                        else 'Invalid or unavailable phone request')
    try:
        connection.sendall(json.dumps(response).encode() + b'\n')
    except OSError:
        pass  # Durable send IDs prevent uncertain retries.
    return False


def start_trace(client, settings):
    """[trace] record = yes: the scrubbed SIT record (sit_trace.py), on the phone."""
    section = settings['trace']
    if section.getboolean('record', False):
        from sit_trace import Tracer
        client.tracer = Tracer(section.get('directory', str(paths.STATE / 'trace')),
                               section.getint('max_bytes', 4 << 20))
        print('Recording the scrubbed SIT trace (IDs, lengths and codes only)', flush=True)


def probe(settings=None):
    """Read-only first contact (MODEM-PLAN M4.1): SIM card and application
    states, radio state, packet registration, NR mode, whether an SMSC is
    set. No identifiers are printed; nothing is changed."""
    client = Sit()
    if settings is not None:
        start_trace(client, settings)
    try:
        sim = client.request(0x0200)
        if len(sim) >= 3 and sim[2] <= 8 and len(sim) >= 3 + sim[2] * 63:
            print('SIM card state', sim[0], 'applications',
                  [(sim[i], sim[i + 1]) for i in range(3, 3 + sim[2] * 63, 63)], flush=True)
        else:
            print('SIM status layout unexpected, length', len(sim), flush=True)
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
            except (ModemError, TimeoutError) as error:
                print(label, 'unavailable:', error, flush=True)
        try:
            smsc = client.request(0x0108)
            print('SMSC present', bool(smsc and smsc[0]), flush=True)
        except (ModemError, TimeoutError) as error:
            print('SMSC unavailable:', error, flush=True)
    finally:
        client.close()


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
        return probe(settings)
    client = Sit(allow_sms=True, allow_calls=True, allow_pin=True)
    start_trace(client, settings)
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
            cp.stop_modem('a call from the previous service run was never released')
            raise RuntimeError('Previous call ownership unresolved; modem stopped')
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
            if service and service.live():
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
                    cp.stop_modem('a call release was not confirmed at service stop')
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
