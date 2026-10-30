# SPDX-License-Identifier: MIT
"""omamobile-sitd's status as ModemManager objects, and MM's methods as
sitd requests.

One modem, /org/freedesktop/ModemManager1/Modem/<n>, exists while the
subscription to sitd is up. Its state follows MM's rules for what sitd
reports (derive() below): no SIM is FAILED (sim-missing) with only the
Modem, 3GPP, Voice and Location interfaces left and Voice.EmergencyOnly
set, as MM does; a ready SIM with the radio off is DISABLED; with the radio
on it is ENABLED, SEARCHING, REGISTERED or, with the internet bearer up,
CONNECTED. Paths count up as MM's do: a modem that comes back is a new one.

Calls, SMS, the SIM and the bearer are separate objects as in MM. Received
SMS come from sitd's store and are deleted there when a client deletes them
(Chatty's pattern); a WAP push (an MMS notification) is an Sms with Text
empty and Data set, which is what mmsd-tng looks for. Sent SMS carry a
send ID that sitd keeps, so a repeated Send never sends twice.

Identifiers stay empty (owner's decision Q9): the IMEI, the IMSI, the
ICCID and own numbers. Numbers and message texts are served to clients but
never logged.
"""
import hashlib
import itertools
import re
import uuid

from gi.repository import GLib

import mm_api as mm
from mm_api import MMError, unsupported

BASE_INTERFACES = (mm.MODEM, mm.MODEM_3GPP, mm.VOICE, mm.LOCATION)
FULL_INTERFACES = BASE_INTERFACES + (mm.MESSAGING, mm.SIGNAL, mm.SIMPLE)
REGISTRATION = {'not-registered': mm.REG_IDLE, 'home': mm.REG_HOME, 'searching': mm.REG_SEARCHING,
                'denied': mm.REG_DENIED, 'roaming': mm.REG_ROAMING}
CALL_STATES = {'dialing': mm.CALL_DIALING, 'ringing-out': mm.CALL_RINGING_OUT,
               'ringing-in': mm.CALL_RINGING_IN, 'active': mm.CALL_ACTIVE, 'held': mm.CALL_HELD,
               'waiting': mm.CALL_WAITING, 'terminated': mm.CALL_TERMINATED}
CALL_STATE_NAMES = {v: k for k, v in CALL_STATES.items()} | {mm.CALL_UNKNOWN: 'unknown'}
IP_TYPES = {'ipv4': mm.IP_V4, 'ipv6': mm.IP_V6, 'ipv4v6': mm.IP_V4V6}
LOCKS = {'pin': mm.LOCK_SIM_PIN, 'puk': mm.LOCK_SIM_PUK, 'network-locked': mm.LOCK_PH_NET_PIN}
DEVICE = '/sys/devices/platform/cpif'
LIVE = (mm.CALL_DIALING, mm.CALL_RINGING_OUT, mm.CALL_RINGING_IN, mm.CALL_ACTIVE, mm.CALL_HELD,
        mm.CALL_WAITING)
NOT_YET = {
    'data': 'Mobile data through ModemManager (T3); omamobile-sit-data owns rmnet0 for now',
    'pin': 'Only SendPin is supported; PUK and PIN changes belong in another phone',
    'emergency': 'Emergency calls on this phone (they are untested; keep another phone for emergencies)',
}


def derive(status):
    """What MM would show for one sitd status. Pure: tested on its own."""
    m = status.get('modem', {})
    sim = m.get('sim', {}).get('state', 'unknown')
    radio = m.get('radio', 'unknown')
    reg = m.get('registration', 'unknown')
    registered = reg in ('home', 'roaming')
    d = dict(sim=sim, radio=radio, failed=mm.FAILED_NONE, unlock=mm.LOCK_UNKNOWN, retries={},
             emergency_only=sim != 'ready', data=bool(m.get('data')) and sim == 'ready')
    if sim == 'absent':
        state, d['failed'] = mm.STATE_FAILED, mm.FAILED_SIM_MISSING
    elif sim == 'error':
        state, d['failed'] = mm.STATE_FAILED, mm.FAILED_SIM_ERROR
    elif sim in LOCKS:
        state, d['unlock'] = mm.STATE_LOCKED, LOCKS[sim]
    elif sim != 'ready':
        state = mm.STATE_INITIALIZING
    elif radio != 'on':
        state = mm.STATE_DISABLED
    elif registered:
        state = mm.STATE_CONNECTED if d['data'] else mm.STATE_REGISTERED
    elif reg == 'searching':
        state = mm.STATE_SEARCHING
    else:
        state = mm.STATE_ENABLED
    if sim == 'ready':
        d['unlock'] = mm.LOCK_NONE
    simdata = m.get('sim', {})
    if 'pin_retries' in simdata:
        d['retries'] = {mm.LOCK_SIM_PIN: simdata['pin_retries'], mm.LOCK_SIM_PUK: simdata['puk_retries']}
    d.update(
        state=state,
        interfaces=FULL_INTERFACES if sim == 'ready' else BASE_INTERFACES,
        sim_object=sim == 'ready' or sim in LOCKS,
        power={'on': mm.POWER_ON, 'off': mm.POWER_LOW}.get(radio, mm.POWER_UNKNOWN),
        registration=REGISTRATION.get(reg, mm.REG_UNKNOWN),
        access=mm.ACCESS.get(m.get('tech', ''), 0) if registered else 0,
        packet=(mm.PACKET_ATTACHED if registered else
                mm.PACKET_DETACHED if radio == 'on' and sim == 'ready' else mm.PACKET_UNKNOWN),
        plmn=m.get('plmn', '') if registered else '',
        operator_name=m.get('operator_name', '') if registered else '',
        home=reg == 'home',
        emergency_numbers=list(m.get('emergency_numbers') or ('112', '911')),
        bearer_ip=(m.get('bearer') or {}) if d['data'] else {},
        # sitd's decoded IND_SIGNAL_STRENGTH (its per-RAT layout is still to
        # be confirmed on hardware): MM's quality, recent while reports come.
        quality=(int(m.get('signal') or 0), bool(m.get('signal_detail'))) if registered else (0, False),
        signal_detail=(m.get('signal_detail') or {}) if registered else {},
    )
    return d


def signal_values(detail, rat, keys):
    """An MM Signal.Lte/Nr5g dictionary (doubles, dBm/dB)."""
    values = detail.get(rat) or {}
    return {k: GLib.Variant('d', float(values[k])) for k in keys if values.get(k) is not None}


def ip_config(config):
    """A Bearer.Ip4Config/Ip6Config dictionary from what omamobile-sit-data
    configured (sitd's private status): static, the address, its prefix and
    up to three DNS servers. Empty when the family isn't configured. The CLAT's
    IPv4 address is the phone's own, not the bearer's: not exported."""
    if not isinstance(config, dict) or not config.get('address') or config.get('clat'):
        return {}
    out = {'method': GLib.Variant('u', mm.IP_METHOD_STATIC),
           'address': GLib.Variant('s', str(config['address'])),
           'prefix': GLib.Variant('u', int(config.get('prefix', 0)))}
    for index, server in enumerate(list(config.get('dns') or [])[:3], 1):
        out[f'dns{index}'] = GLib.Variant('s', str(server))
    return out


def is_emergency(number, d):
    return re.sub(r'[\s().-]', '', number) in d['emergency_numbers']


class Bridge:
    def __init__(self, exporter, link, settings):
        self.x = exporter
        self.link = link
        self.settings = settings
        self.ids = {kind: itertools.count() for kind in ('Modem', 'SIM', 'Bearer', 'SMS', 'Call')}
        self.reset()

    def reset(self):
        self.modem = None
        self.status = None
        self.derived = None
        self.sim = None
        self.bearer = None
        self.calls = {}              # path -> call record
        self.sitd_calls = {}         # sitd call id -> path
        self.forgotten = set()       # sitd call ids whose MM call a client deleted
        self.messages = {}           # path -> SMS record
        self.sitd_sms = {}           # sitd SMS id -> path
        self.fetching = False
        self.first_fetch = True
        self.starting = 0            # Call.Start requests waiting for sitd's call ID
        self.next_reason = mm.CHANGE_UNKNOWN
        self.location = dict(enabled=mm.LOCATION_NONE, signals=False)
        self.signal = dict(Rate=0, RssiThreshold=0, ErrorRateThreshold=False)

    def path(self, kind):
        return f'{mm.PATH}/{kind}/{next(self.ids[kind])}'

    # ---- the manager ---------------------------------------------------------

    def export_manager(self):
        self.x.add(mm.PATH, {mm.MM: dict(Version=mm.VERSION), mm.OBJECT_MANAGER: {}}, self.handle_manager)

    def handle_manager(self, interface, method, args, reply):
        if interface == mm.OBJECT_MANAGER and method == 'GetManagedObjects':
            return reply.ok(self.x.managed_objects())
        raise unsupported(method)

    # ---- sitd status -> objects -------------------------------------------

    def on_status(self, status):
        self.status = status
        d = derive(status)
        if self.modem is None:
            self.create_modem(d)
        else:
            self.update_modem(d)
        self.sync_calls()
        self.sync_messages()

    def on_lost(self):
        if self.modem is None:
            return
        for path in list(self.calls) + list(self.messages) + [self.sim, self.bearer]:
            if path:
                self.x.remove(path)
        self.x.remove(self.modem)
        print(f'Modem {self.modem} removed: omamobile-sitd went away', flush=True)
        self.reset()

    def create_modem(self, d):
        self.derived = d
        if d['sim_object']:
            self.create_sim(d)
        if d['data']:
            self.create_bearer(d)
        self.modem = self.path('Modem')
        self.x.add(self.modem, {name: self.interface_props(name, d) for name in d['interfaces']},
                   self.handle_modem, managed=True)
        print(f'Modem {self.modem} exported: state {d["state"]}, '
              f'failed reason {mm.FAILED_REASON_NAMES.get(d["failed"], d["failed"])}, '
              f'SIM {d["sim"]}, radio {d["radio"]}', flush=True)

    def update_modem(self, d):
        old, self.derived = self.derived, d
        if d['sim_object'] and not self.sim:
            self.create_sim(d)
        elif not d['sim_object'] and self.sim:
            self.x.remove(self.sim)
            self.sim = None
        if d['data'] and not self.bearer:
            self.create_bearer(d)
        if self.bearer:
            self.x.set(self.bearer, mm.BEARER, **self.bearer_dynamic(d))
        for name in d['interfaces']:
            if not self.x.has(self.modem, name):
                self.x.add_interface(self.modem, name, self.interface_props(name, d))
        for name in FULL_INTERFACES:
            if name not in d['interfaces']:
                self.x.remove_interface(self.modem, name)
        for name in d['interfaces']:
            self.x.set(self.modem, name, **self.dynamic_props(name, d))
        if self.sim:
            self.x.set(self.sim, mm.SIM, **self.sim_dynamic(d))
        if old['state'] != d['state']:
            reason, self.next_reason = self.next_reason, mm.CHANGE_UNKNOWN
            print(f'Modem state {old["state"]} -> {d["state"]}', flush=True)
            self.x.emit(self.modem, mm.MODEM, 'StateChanged', '(iiu)', (old['state'], d['state'], reason))

    def interface_props(self, name, d):
        return {**self.static_props(name), **self.dynamic_props(name, d)}

    def static_props(self, name):
        if name == mm.MODEM:
            return dict(
                Manufacturer='Samsung Electronics', Model='Exynos Modem 5300',
                DeviceIdentifier=hashlib.sha1(b'omamobile-mmd cpif umts_ipc0').hexdigest(),
                Device=DEVICE, Physdev=DEVICE, Drivers=['cpif'], Plugin='omamobile',
                PrimaryPort='umts_ipc0', Ports=[('umts_ipc0', mm.PORT_UNKNOWN), ('rmnet0', mm.PORT_NET)],
                SupportedCapabilities=[mm.CAP_GSM_UMTS | mm.CAP_LTE],
                CurrentCapabilities=mm.CAP_GSM_UMTS | mm.CAP_LTE, MaxBearers=1, MaxActiveBearers=1,
                SupportedModes=[(mm.MODE_4G, mm.MODE_NONE)], CurrentModes=(mm.MODE_4G, mm.MODE_NONE),
                SupportedBands=[mm.BAND_UNKNOWN], CurrentBands=[mm.BAND_UNKNOWN],
                SupportedIpFamilies=mm.IP_V4 | mm.IP_V6 | mm.IP_V4V6)
        if name == mm.MODEM_3GPP:
            apn, ip_type = self.settings.get('apn', ''), self.settings.get('ip_type', 'ipv4v6')
            settings = {'apn': GLib.Variant('s', apn),
                        'ip-type': GLib.Variant('u', IP_TYPES.get(ip_type, mm.IP_V4V6))} if apn else {}
            return dict(InitialEpsBearerSettings=settings)
        if name == mm.LOCATION:
            return dict(Capabilities=mm.LOCATION_3GPP_LAC_CI)
        if name == mm.MESSAGING:
            return dict(SupportedStorages=[mm.STORAGE_ME], DefaultStorage=mm.STORAGE_ME)
        return {}

    def dynamic_props(self, name, d):
        if name == mm.MODEM:
            return dict(Sim=self.sim or '/', Bearers=[self.bearer] if self.bearer else [],
                        State=d['state'], StateFailedReason=d['failed'], UnlockRequired=d['unlock'],
                        UnlockRetries=d['retries'], PowerState=d['power'],
                        AccessTechnologies=d['access'], SignalQuality=d['quality'])
        if name == mm.MODEM_3GPP:
            return dict(RegistrationState=d['registration'], OperatorCode=d['plmn'],
                        OperatorName=d['operator_name'], PacketServiceState=d['packet'])
        if name == mm.VOICE:
            return dict(Calls=list(self.calls), EmergencyOnly=d['emergency_only'])
        if name == mm.LOCATION:
            # MM reports a 3GPP location only with an area code and a cell
            # ID; sitd doesn't read those yet, so the location stays empty.
            return dict(Enabled=self.location['enabled'], SignalsLocation=self.location['signals'])
        if name == mm.MESSAGING:
            return dict(Messages=list(self.messages))
        if name == mm.SIGNAL:
            # As MM: the extended values only while a client asked for a rate.
            on = self.signal['Rate'] > 0
            return dict(self.signal,
                        Lte=signal_values(d['signal_detail'], 'lte', ('rssi', 'rsrp', 'rsrq', 'snr')) if on else {},
                        Nr5g=signal_values(d['signal_detail'], 'nr', ('rsrp', 'rsrq', 'snr')) if on else {})
        return {}

    def create_sim(self, d):
        self.sim = self.path('SIM')
        self.x.add(self.sim, {mm.SIM: dict(Active=True, SimType=mm.SIM_TYPE_PHYSICAL,
                                           Removability=mm.SIM_REMOVABLE, **self.sim_dynamic(d))},
                   self.handle_sim)

    def sim_dynamic(self, d):
        # The SIM's own operator is only known from the network while at home.
        return dict(EmergencyNumbers=d['emergency_numbers'],
                    OperatorIdentifier=d['plmn'] if d['home'] else '',
                    OperatorName=d['operator_name'] if d['home'] else '')

    def create_bearer(self, d):
        self.bearer = self.path('Bearer')
        apn, ip_type = self.settings.get('apn', ''), self.settings.get('ip_type', 'ipv4v6')
        self.x.add(self.bearer, {mm.BEARER: dict(
            Interface='rmnet0', IpTimeout=20, BearerType=mm.BEARER_DEFAULT,
            ProfileId=-1, Properties={'apn': GLib.Variant('s', apn),
                                      'ip-type': GLib.Variant('u', IP_TYPES.get(ip_type, mm.IP_V4V6))},
            **self.bearer_dynamic(d))},
            self.handle_bearer)

    def bearer_dynamic(self, d):
        return dict(Connected=d['data'], Ip4Config=ip_config(d['bearer_ip'].get('ipv4')),
                    Ip6Config=ip_config(d['bearer_ip'].get('ipv6')))

    # ---- calls ----------------------------------------------------------------

    def sync_calls(self):
        seen = set()
        for c in self.status.get('calls', []):
            sid = c['id']
            seen.add(sid)
            if sid in self.forgotten:
                continue
            path = self.sitd_calls.get(sid)
            if path is None:
                if c['state'] == 'terminated':
                    continue          # ended before we saw it
                if c['direction'] == 'outgoing' and self.starting:
                    continue          # ours: Call.Start's answer names it
                path = self.new_call(mm.DIRECTION_INCOMING if c['direction'] == 'incoming'
                                     else mm.DIRECTION_OUTGOING, c.get('number', ''),
                                     CALL_STATES.get(c['state'], mm.CALL_UNKNOWN), sid)
                continue
            self.calls[path]['seen'] = True
            self.call_state(path, CALL_STATES.get(c['state'], mm.CALL_UNKNOWN), c.get('reason', ''))
        for sid, path in list(self.sitd_calls.items()):
            if sid not in seen and path in self.calls and self.calls[path]['seen']:
                # sitd forgot it (another client deleted it): it has ended.
                self.call_state(path, mm.CALL_TERMINATED, '')
        self.forgotten &= seen

    def new_call(self, direction, number, state, sid=None):
        path = self.path('Call')
        reason = (mm.REASON_INCOMING_NEW if direction == mm.DIRECTION_INCOMING and state != mm.CALL_UNKNOWN
                  else mm.REASON_OUTGOING_STARTED if state != mm.CALL_UNKNOWN else mm.REASON_UNKNOWN)
        self.calls[path] = dict(sid=sid, direction=direction, number=number, state=state, busy=False,
                                seen=sid is not None)
        if sid:
            self.sitd_calls[sid] = path
        self.x.add(path, {mm.CALL: dict(State=state, StateReason=reason, Direction=direction,
                                        Number=number)},
                   lambda i, m, a, r, path=path: self.handle_call(path, i, m, a, r))
        self.x.set(self.modem, mm.VOICE, Calls=list(self.calls))
        self.x.emit(self.modem, mm.VOICE, 'CallAdded', '(o)', (path,))
        print(f'Call {path}: {"incoming" if direction == mm.DIRECTION_INCOMING else "outgoing"}, '
              f'{CALL_STATE_NAMES.get(state, state)}', flush=True)
        return path

    def call_state(self, path, state, sitd_reason):
        call = self.calls[path]
        old = call['state']
        if old == state or old == mm.CALL_TERMINATED:
            return
        if state == mm.CALL_TERMINATED:
            reason = mm.REASON_ERROR if sitd_reason == 'error' else (
                mm.REASON_REFUSED_OR_BUSY if old in (mm.CALL_DIALING, mm.CALL_RINGING_OUT)
                and sitd_reason != 'terminated' else mm.REASON_TERMINATED)
        elif state == mm.CALL_ACTIVE:
            reason = mm.REASON_ACCEPTED
        elif state in (mm.CALL_DIALING, mm.CALL_RINGING_OUT):
            reason = mm.REASON_OUTGOING_STARTED
        elif state == mm.CALL_RINGING_IN:
            reason = mm.REASON_INCOMING_NEW
        else:
            reason = mm.REASON_UNKNOWN
        call['state'] = state
        self.x.set(path, mm.CALL, State=state, StateReason=reason)
        self.x.emit(path, mm.CALL, 'StateChanged', '(iiu)', (old, state, reason))
        print(f'Call {path}: {CALL_STATE_NAMES.get(old, old)} -> {CALL_STATE_NAMES.get(state, state)}',
              flush=True)

    def delete_call(self, path):
        call = self.calls.pop(path)
        if call['sid']:
            self.sitd_calls.pop(call['sid'], None)
            self.forgotten.add(call['sid'])
        self.x.remove(path)
        self.x.set(self.modem, mm.VOICE, Calls=list(self.calls))
        self.x.emit(self.modem, mm.VOICE, 'CallDeleted', '(o)', (path,))

    # ---- messages ---------------------------------------------------------------

    def sync_messages(self):
        if not self.x.has(self.modem, mm.MESSAGING):
            return
        ids = self.status.get('sms', {}).get('received', [])
        for sid, path in list(self.sitd_sms.items()):
            if sid not in ids:
                self.drop_message(path)       # deleted through sitd by another client
        if any(i not in self.sitd_sms for i in ids) and not self.fetching:
            self.fetching = True
            self.link.request('sms-list', self.fetched)

    def fetched(self, result, error):
        self.fetching = False
        if self.modem is None or not self.x.has(self.modem, mm.MESSAGING):
            return
        if error:
            # Try again shortly: the messages stay in sitd's store meanwhile.
            print(f'SMS list failed: {type(error).__name__}; retrying', flush=True)
            modem = self.modem
            GLib.timeout_add_seconds(5, lambda: self.modem == modem and self.status and self.sync_messages()
                                     and False)
            return
        wanted = self.status.get('sms', {}).get('received', [])
        received = not self.first_fetch
        self.first_fetch = False
        for message in result or []:
            sid = message.get('id')
            if sid not in wanted or sid in self.sitd_sms:
                continue
            data = bytes.fromhex(message.get('data') or '')
            path = self.new_message(dict(
                sid=sid, State=mm.SMS_RECEIVED, PduType=mm.PDU_DELIVER, Number=message.get('number', ''),
                Text=message.get('text', ''), Data=data, Timestamp=message.get('timestamp', ''),
                Storage=mm.STORAGE_ME), received)
            print(f'SMS {path} received{" (binary data: a WAP push)" if data else ""}', flush=True)
        if any(i not in self.sitd_sms for i in self.status.get('sms', {}).get('received', [])):
            self.sync_messages()

    def new_message(self, fields, received):
        path = self.path('SMS')
        sid = fields.pop('sid', None)
        request_id = fields.pop('request_id', None)
        self.messages[path] = dict(sid=sid, request_id=request_id, busy=False)
        if sid:
            self.sitd_sms[sid] = path
        props = {'Class': -1, 'DeliveryState': mm.DELIVERY_UNKNOWN,
                 'Validity': (mm.VALIDITY_UNKNOWN, GLib.Variant('u', 0)), **fields}
        self.x.add(path, {mm.SMS: props}, lambda i, m, a, r, path=path: self.handle_sms(path, i, m, a, r))
        self.x.set(self.modem, mm.MESSAGING, Messages=list(self.messages))
        self.x.emit(self.modem, mm.MESSAGING, 'Added', '(ob)', (path, received))
        return path

    def drop_message(self, path):
        record = self.messages.pop(path)
        if record['sid']:
            self.sitd_sms.pop(record['sid'], None)
        self.x.remove(path)
        if self.modem and self.x.has(self.modem, mm.MESSAGING):
            self.x.set(self.modem, mm.MESSAGING, Messages=list(self.messages))
            self.x.emit(self.modem, mm.MESSAGING, 'Deleted', '(o)', (path,))

    # ---- method handlers ----------------------------------------------------------

    def answer(self, reply, then=None, error_nick='Failed'):
        """A sitd request's callback: reply OK (after then(result)) or MM's error."""
        def done(result, error):
            if error is not None:
                return reply.error(sitd_error(error, error_nick))
            try:
                if then is not None:
                    then(result)
                reply.ok()
            except MMError as failure:
                reply.error(failure)
        return done

    def handle_modem(self, interface, method, args, reply):
        d = self.derived
        if interface == mm.MODEM:
            if method == 'Enable':
                return self.enable(args[0], reply)
            if method == 'ListBearers':
                return reply.ok([self.bearer] if self.bearer else [])
            if method in ('CreateBearer', 'DeleteBearer'):
                raise unsupported(NOT_YET['data'])
            raise unsupported(method)
        if interface == mm.MODEM_3GPP:
            raise unsupported(method)
        if interface == mm.SIMPLE:
            if method == 'GetStatus':
                # As libmm-glib's MMSimpleStatus builds it: the state as a
                # uint32, the rest only once registered.
                status = {'state': GLib.Variant('u', d['state'] & 0xffffffff)}
                if d['state'] >= mm.STATE_REGISTERED:
                    status.update({'signal-quality': GLib.Variant('(ub)', d['quality']),
                                   'current-bands': GLib.Variant('au', [mm.BAND_UNKNOWN]),
                                   'access-technologies': GLib.Variant('u', d['access']),
                                   'm3gpp-registration-state': GLib.Variant('u', d['registration'])})
                    if d['plmn']:
                        status['m3gpp-operator-code'] = GLib.Variant('s', d['plmn'])
                    if d['operator_name']:
                        status['m3gpp-operator-name'] = GLib.Variant('s', d['operator_name'])
                return reply.ok(status)
            raise unsupported(NOT_YET['data'])
        if interface == mm.LOCATION:
            if method == 'Setup':
                sources, signals = args
                if sources & ~mm.LOCATION_3GPP_LAC_CI:
                    raise unsupported('That location source')
                if sources and d['state'] < mm.STATE_ENABLED:
                    raise MMError('WrongState', 'Modem not enabled')
                self.location.update(enabled=sources, signals=signals)
                self.x.set(self.modem, mm.LOCATION, Enabled=sources, SignalsLocation=signals)
                return reply.ok()
            if method == 'GetLocation':
                return reply.ok({})
            raise unsupported(method)
        if interface == mm.SIGNAL:
            if method == 'Setup':
                self.signal['Rate'] = args[0]
            else:
                settings = args[0]
                self.signal['RssiThreshold'] = int(settings.get('rssi-threshold', 0))
                self.signal['ErrorRateThreshold'] = bool(settings.get('error-rate-threshold', False))
            self.x.set(self.modem, mm.SIGNAL, **self.dynamic_props(mm.SIGNAL, d))
            return reply.ok()
        if interface == mm.VOICE:
            return self.handle_voice(method, args, reply)
        if interface == mm.MESSAGING:
            return self.handle_messaging(method, args, reply)
        raise unsupported(method)

    def enable(self, enable, reply):
        d = self.derived
        if d['state'] == mm.STATE_FAILED:
            raise MMError('WrongState', 'Modem in failed state: '
                          + mm.FAILED_REASON_NAMES.get(d['failed'], 'unknown'))
        if d['state'] == mm.STATE_LOCKED:
            raise MMError('WrongState', 'Modem is locked')
        if d['state'] == mm.STATE_INITIALIZING:
            raise MMError('WrongState', 'Modem is still initializing')
        if (d['radio'] == 'on') == enable:
            return reply.ok()
        # AT+CFUN through sitd: the radio goes on (it transmits) or off.
        print(f'Radio {"on" if enable else "off"} requested over D-Bus', flush=True)
        self.next_reason = mm.CHANGE_USER_REQUESTED
        self.link.request('radio', self.answer(reply), timeout=70, on=bool(enable))

    def handle_voice(self, method, args, reply):
        d = self.derived
        if method == 'ListCalls':
            return reply.ok(list(self.calls))
        if method == 'CreateCall':
            number = args[0].get('number')
            if not isinstance(number, str) or not number.strip():
                raise MMError('InvalidArgs', 'Missing number')
            if is_emergency(number, d):
                raise unsupported(NOT_YET['emergency'])
            if d['emergency_only']:
                raise MMError('Unauthorized', 'Only emergency calls are allowed')
            return reply.ok(self.new_call(mm.DIRECTION_OUTGOING, number.strip(), mm.CALL_UNKNOWN))
        if method == 'DeleteCall':
            path = args[0]
            if path not in self.calls:
                raise MMError('NotFound', 'No such call')
            call = self.calls[path]
            if call['sid'] and call['state'] in LIVE:
                # MM hangs up a call that is deleted while it lasts.
                def hung(result, error):
                    if path in self.calls:
                        self.delete_call(path)
                    reply.ok()
                return self.link.request('hangup', hung, id=call['sid'])
            if call['sid']:
                self.link.request('delete-call', lambda result, error: None, id=call['sid'])
            self.delete_call(path)
            return reply.ok()
        if method == 'HangupAll':
            live = [c['sid'] for c in self.calls.values() if c['sid'] and c['state'] in LIVE]
            for path, c in self.calls.items():
                if not c['sid'] and c['state'] == mm.CALL_UNKNOWN:
                    self.call_state(path, mm.CALL_TERMINATED, 'terminated')
            failures = []

            def next_hangup(result=None, error=None):
                if error is not None:
                    failures.append(error)
                if live:
                    return self.link.request('hangup', next_hangup, id=live.pop(0))
                if failures:
                    return reply.error(sitd_error(failures[0]))
                reply.ok()
            return next_hangup()
        raise unsupported(method)

    def handle_call(self, path, interface, method, args, reply):
        call = self.calls.get(path)
        if call is None:
            raise MMError('NotFound', 'No such call')
        if method == 'Start':
            if call['direction'] != mm.DIRECTION_OUTGOING or call['state'] != mm.CALL_UNKNOWN or call['busy']:
                raise MMError('WrongState', 'This call cannot be started')
            call['busy'] = True
            self.starting += 1

            def dialled(result, error):
                self.starting -= 1
                call['busy'] = False
                if path not in self.calls:
                    return reply.error(MMError('Failed', 'The call was deleted'))
                if error is not None:
                    self.call_state(path, mm.CALL_TERMINATED, 'error')
                    reply.error(sitd_error(error))
                else:
                    call['sid'] = str(result.get('call'))
                    self.sitd_calls[call['sid']] = path
                    self.call_state(path, mm.CALL_DIALING, '')
                    reply.ok()
                if self.status:
                    self.sync_calls()
            return self.link.request('dial', dialled, number=call['number'])
        if method == 'Accept':
            if call['direction'] != mm.DIRECTION_INCOMING or call['state'] not in (
                    mm.CALL_RINGING_IN, mm.CALL_WAITING) or not call['sid']:
                raise MMError('WrongState', 'This call is not ringing')
            return self.link.request('accept', self.answer(reply), id=call['sid'])
        if method == 'Hangup':
            if call['state'] == mm.CALL_TERMINATED:
                raise MMError('WrongState', 'This call has ended')
            if not call['sid']:
                if call['busy']:
                    raise MMError('InProgress', 'The call is being placed')
                self.call_state(path, mm.CALL_TERMINATED, 'terminated')
                return reply.ok()
            return self.link.request('hangup', self.answer(reply), id=call['sid'])
        if method == 'SendDtmf':
            keys = args[0]
            if not re.fullmatch(r'[0-9*#]{1,32}', keys or ''):
                raise MMError('InvalidArgs', 'Touch tones are 0-9, * and #')
            if call['state'] != mm.CALL_ACTIVE or not call['sid']:
                raise MMError('WrongState', 'Touch tones need an active call')
            return self.link.request('dtmf', self.answer(reply), id=call['sid'], keys=keys)
        raise unsupported(method)

    def handle_messaging(self, method, args, reply):
        if method == 'List':
            return reply.ok(list(self.messages))
        if method == 'SetDefaultStorage':
            if args[0] != mm.STORAGE_ME:
                raise unsupported('That storage')
            return reply.ok()
        if method == 'Create':
            props = args[0]
            number, text = props.get('number'), props.get('text')
            if 'data' in props:
                raise unsupported('Sending binary SMS')
            if not isinstance(number, str) or not number.strip():
                raise MMError('InvalidArgs', 'Missing number')
            if not isinstance(text, str) or not text:
                raise MMError('InvalidArgs', 'Missing text')
            validity = props.get('validity')
            fields = dict(State=mm.SMS_UNKNOWN, PduType=mm.PDU_SUBMIT, Number=number.strip(), Text=text,
                          DeliveryReportRequest=bool(props.get('delivery-report-request', False)),
                          request_id=uuid.uuid4().hex)
            if isinstance(validity, int):
                fields['Validity'] = (mm.VALIDITY_RELATIVE, GLib.Variant('u', validity))
            if isinstance(props.get('class'), int):
                fields['Class'] = props['class']
            return reply.ok(self.new_message(fields, False))
        if method == 'Delete':
            path = args[0]
            record = self.messages.get(path)
            if record is None:
                raise MMError('NotFound', 'No such SMS')
            if record['busy']:
                raise MMError('InProgress', 'This SMS is being sent')
            if record['sid']:
                def deleted(result, error):
                    if error is not None:
                        return reply.error(sitd_error(error))
                    if path in self.messages:
                        self.drop_message(path)
                    reply.ok()
                return self.link.request('sms-delete', deleted, id=record['sid'])
            self.drop_message(path)
            return reply.ok()
        raise unsupported(method)

    def handle_sms(self, path, interface, method, args, reply):
        record = self.messages.get(path)
        if record is None:
            raise MMError('NotFound', 'No such SMS')
        if method != 'Send':
            raise unsupported('Storing SMS')
        state = self.x.get(path, mm.SMS, 'State')
        if record['busy']:
            raise MMError('InProgress', 'This SMS is being sent')
        if state == mm.SMS_SENT:
            raise MMError('WrongState', 'This SMS was already sent')
        if not record['request_id']:
            raise MMError('WrongState', 'A received SMS cannot be sent')
        record['busy'] = True
        self.x.set(path, mm.SMS, State=mm.SMS_SENDING)

        def sent(result, error):
            record['busy'] = False
            if path not in self.messages:
                return reply.error(MMError('Failed', 'The SMS was deleted'))
            outcome = (result or {}).get('state')
            if error is None and outcome == 'sent':
                self.x.set(path, mm.SMS, State=mm.SMS_SENT)
                print(f'SMS {path} sent', flush=True)
                return reply.ok()
            # "failed" or "unknown": the same send ID never sends again.
            self.x.set(path, mm.SMS, State=mm.SMS_UNKNOWN)
            print(f'SMS {path} not sent: {outcome or type(error).__name__}', flush=True)
            reply.error(sitd_error(error) if error else MMError('Failed', (result or {}).get('error')
                                                                or 'The SMS was not sent'))
        self.link.request('sms-send', sent, timeout=400, request_id=record['request_id'],
                          number=self.x.get(path, mm.SMS, 'Number'), text=self.x.get(path, mm.SMS, 'Text'))

    def handle_sim(self, interface, method, args, reply):
        # SendPin only (sitd's one VERIFY_SIM_PIN, refused with fewer than two
        # tries left); PUK, PIN changes and the lock itself stay off.
        if method == 'SendPin':
            if self.derived['sim'] != 'pin':
                raise MMError('WrongState', 'The SIM is not asking for its PIN')
            return self.link.request('sim-pin', self.answer(reply), timeout=40, pin=args[0])
        raise unsupported(NOT_YET['pin'])

    def handle_bearer(self, interface, method, args, reply):
        raise unsupported(NOT_YET['data'])


def sitd_error(error, nick='Failed'):
    """sitd's own messages are written for users and carry no numbers;
    transport errors are named by type only."""
    from sitd_link import SitdError
    if isinstance(error, SitdError):
        message = str(error)
        if 'not registered' in message:
            nick = 'WrongState'
        return MMError(nick, message)
    return MMError(nick, f'omamobile-sitd unavailable ({type(error).__name__})')
