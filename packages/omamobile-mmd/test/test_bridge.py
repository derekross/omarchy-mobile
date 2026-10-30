# SPDX-License-Identifier: MIT
"""omamobile-mmd against a fake omamobile-sitd, on a private bus: what a
ModemManager client sees for each sitd state, and which sitd requests each
MM method makes."""
import env
from env import GLib, MM, ROOT, Client, FakeRefusal, FakeSitd, Mmd, PrivateBus, blank_status, \
    registered_status, spin, tempdir, wait_until
import os
import re
import unittest

import bridge
import mm_api as mm

MODEM0 = ROOT + '/Modem/0'
SENDER = '+12025550123'       # fictional
OTHER = '+12025550199'        # fictional


def call(sid, state, direction='incoming', number=SENDER, reason=''):
    return dict(id=sid, number=number, direction=direction, state=state, reason=reason,
                multiparty=False, since=0)


class Derive(unittest.TestCase):
    def test_states(self):
        cases = [
            (blank_status(), mm.STATE_FAILED, mm.FAILED_SIM_MISSING),
            (blank_status(sim='error'), mm.STATE_FAILED, mm.FAILED_SIM_ERROR),
            (blank_status(sim='pin'), mm.STATE_LOCKED, mm.FAILED_NONE),
            (blank_status(sim='unknown'), mm.STATE_INITIALIZING, mm.FAILED_NONE),
            (blank_status(sim='ready'), mm.STATE_DISABLED, mm.FAILED_NONE),
            (blank_status(sim='ready', radio='on'), mm.STATE_ENABLED, mm.FAILED_NONE),
            (blank_status(sim='ready', radio='on', registration='searching'), mm.STATE_SEARCHING, mm.FAILED_NONE),
            (registered_status(), mm.STATE_REGISTERED, mm.FAILED_NONE),
            (registered_status(registration='roaming'), mm.STATE_REGISTERED, mm.FAILED_NONE),
            (registered_status(data=True), mm.STATE_CONNECTED, mm.FAILED_NONE),
        ]
        for status, state, failed in cases:
            d = bridge.derive(status)
            self.assertEqual((d['state'], d['failed']), (state, failed), status['modem']['sim'])

    def test_details(self):
        d = bridge.derive(blank_status(sim='pin'))
        self.assertEqual((d['unlock'], d['emergency_only'], d['sim_object'], d['interfaces']),
                         (mm.LOCK_SIM_PIN, True, True, bridge.BASE_INTERFACES))
        d = bridge.derive(blank_status())
        self.assertEqual((d['unlock'], d['sim_object'], d['power'], d['registration']),
                         (mm.LOCK_UNKNOWN, False, mm.POWER_LOW, mm.REG_IDLE))
        d = bridge.derive(registered_status(tech='NR'))
        self.assertEqual((d['unlock'], d['retries'], d['power'], d['access'], d['packet'], d['plmn']),
                         (mm.LOCK_NONE, {mm.LOCK_SIM_PIN: 3, mm.LOCK_SIM_PUK: 10}, mm.POWER_ON,
                          mm.ACCESS['NR'], mm.PACKET_ATTACHED, '00101'))
        d = bridge.derive(registered_status(registration='searching'))
        self.assertEqual((d['access'], d['plmn'], d['packet']), (0, '', mm.PACKET_DETACHED))


class BridgeTests(unittest.TestCase):
    status = None

    def setUp(self):
        self.dir, cleanup = tempdir()
        self.addCleanup(cleanup)
        self.bus = PrivateBus(self.dir)
        self.addCleanup(self.bus.close)
        self.sitd = FakeSitd(os.path.join(self.dir, 'sitd.sock'))
        if self.status:
            self.sitd.status = self.status()
        self.client = Client(self.bus.connection)
        self.before_mmd()
        self.mmd = Mmd(self.bus, self.sitd.path, self.dir, *self.mmd_args)
        self.addCleanup(self.mmd.stop)
        wait_until(lambda: self.client.objects(), 10, 'the modem')

    mmd_args = ()

    def before_mmd(self):
        pass

    def tearDown(self):
        log = self.mmd.output()
        if os.environ.get('OMAMOBILE_MMD_DEBUG'):
            print(log)
        for secret in ('2025550', 'hello there', 'omamobile test text'):
            self.assertNotIn(secret, log, 'numbers and texts never reach the log')

    # helpers
    def push(self, status=None, **modem):
        if status is not None:
            self.sitd.status = status
        self.sitd.status['modem'].update(modem)
        self.sitd.push()

    def modem(self, name='State', interface=mm.MODEM):
        return self.client.prop(MODEM0, interface, name)

    def error_of(self, path, interface, method, signature=None, args=()):
        with self.assertRaises(GLib.Error) as caught:
            self.client.call(path, interface, method, signature, args)
        return re.sub(r'^GDBus\.Error:', '', caught.exception.message).split(':')[0]


class NoSim(BridgeTests):
    def test_failed_sim_missing_as_mm_shows_it(self):
        objects = self.client.objects()
        self.assertEqual(list(objects), [MODEM0])
        # Exactly MM's interfaces, never org.freedesktop.DBus.*: GNOME Calls
        # 51.1 crashed on those (libmm-glib gives them no interface info).
        self.assertEqual(set(objects[MODEM0]), {mm.MODEM, mm.MODEM_3GPP, mm.VOICE, mm.LOCATION})
        modem = objects[MODEM0][mm.MODEM]
        self.assertEqual((modem['State'], modem['StateFailedReason'], modem['PowerState'], modem['Sim'],
                          modem['UnlockRequired'], modem['EquipmentIdentifier'], modem['OwnNumbers']),
                         (mm.STATE_FAILED, mm.FAILED_SIM_MISSING, mm.POWER_LOW, '/', mm.LOCK_UNKNOWN, '', []))
        self.assertEqual((modem['Drivers'], modem['Plugin'], modem['PrimaryPort']), (['cpif'], 'omamobile', 'umts_ipc0'))
        gpp = objects[MODEM0][mm.MODEM_3GPP]
        self.assertEqual((gpp['Imei'], gpp['RegistrationState'], gpp['OperatorCode']), ('', mm.REG_IDLE, ''))
        self.assertEqual(objects[MODEM0][mm.VOICE], dict(Calls=[], EmergencyOnly=True))
        self.assertEqual(self.client.call(ROOT, 'org.freedesktop.DBus.Properties', 'Get', 'ss',
                                          (mm.MM, 'Version'))[0], '1.24.2')

    def test_nothing_reaches_the_modem(self):
        self.assertEqual(self.error_of(MODEM0, mm.MODEM, 'Enable', 'b', (True,)), mm.ERROR_PREFIX + 'WrongState')
        self.assertEqual(self.error_of(MODEM0, mm.VOICE, 'CreateCall', 'a{sv}',
                                       ({'number': GLib.Variant('s', OTHER)},)),
                         mm.ERROR_PREFIX + 'Unauthorized')
        for number in ('911', '112', '999'):
            self.assertEqual(self.error_of(MODEM0, mm.VOICE, 'CreateCall', 'a{sv}',
                                           ({'number': GLib.Variant('s', number)},)),
                             mm.ERROR_PREFIX + 'Unsupported')
        self.assertEqual(self.client.call(MODEM0, mm.VOICE, 'ListCalls')[0], [])
        self.assertEqual(self.sitd.actions(), [])

    def test_sim_appears_later(self):
        self.push(registered_status())
        wait_until(lambda: self.modem() == mm.STATE_REGISTERED, 5, 'registered')
        objects = self.client.objects()
        self.assertIn(mm.MESSAGING, objects[MODEM0])
        sim = objects[MODEM0][mm.MODEM]['Sim']
        self.assertEqual(sim, ROOT + '/SIM/0')
        added = [sorted(s[3][1]) for s in self.client.named('InterfacesAdded') if s[3][0] == MODEM0]
        self.assertEqual(added, [sorted(bridge.BASE_INTERFACES), [mm.MESSAGING], [mm.SIGNAL], [mm.SIMPLE]])
        changed = self.client.named('StateChanged')
        self.assertEqual(changed[-1][3], (mm.STATE_FAILED, mm.STATE_REGISTERED, mm.CHANGE_UNKNOWN))


class Registered(BridgeTests):
    status = staticmethod(registered_status)

    def test_objects_and_properties(self):
        objects = self.client.objects()
        self.assertEqual(set(objects[MODEM0]), set(bridge.FULL_INTERFACES))
        modem = objects[MODEM0][mm.MODEM]
        self.assertEqual((modem['State'], modem['UnlockRequired'], modem['UnlockRetries'], modem['PowerState'],
                          modem['AccessTechnologies'], modem['SignalQuality']),
                         (mm.STATE_REGISTERED, mm.LOCK_NONE, {2: 3, 4: 10}, mm.POWER_ON, mm.ACCESS['LTE'], (0, False)))
        gpp = objects[MODEM0][mm.MODEM_3GPP]
        self.assertEqual((gpp['RegistrationState'], gpp['OperatorCode'], gpp['OperatorName'],
                          gpp['PacketServiceState'], gpp['Imei']),
                         (mm.REG_HOME, '00101', 'Test Network', mm.PACKET_ATTACHED, ''))
        self.assertEqual(gpp['InitialEpsBearerSettings'], {'apn': 'internet.example', 'ip-type': mm.IP_V4V6})
        sim = self.client.props(modem['Sim'], mm.SIM)
        self.assertEqual((sim['Active'], sim['Imsi'], sim['SimIdentifier'], sim['EmergencyNumbers'],
                          sim['OperatorIdentifier'], sim['SimType']),
                         (True, '', '', ['112', '911'], '00101', mm.SIM_TYPE_PHYSICAL))
        self.assertEqual(objects[MODEM0][mm.MESSAGING],
                         dict(Messages=[], SupportedStorages=[mm.STORAGE_ME], DefaultStorage=mm.STORAGE_ME))
        status = self.client.call(MODEM0, mm.SIMPLE, 'GetStatus')[0]
        self.assertEqual((status['state'], status['m3gpp-registration-state'], status['m3gpp-operator-code']),
                         (mm.STATE_REGISTERED, mm.REG_HOME, '00101'))

    def test_registration_states_and_signals(self):
        for modem, state in ((dict(registration='searching'), mm.STATE_SEARCHING),
                             (dict(registration='not-registered'), mm.STATE_ENABLED),
                             (dict(radio='off'), mm.STATE_DISABLED),
                             (dict(radio='on', registration='roaming'), mm.STATE_REGISTERED),
                             (dict(data=True), mm.STATE_CONNECTED)):
            self.push(**modem)
            wait_until(lambda: self.modem() == state, 5, f'state {state}')
        spin(.2)
        transitions = [s[3][:2] for s in self.client.named('StateChanged')]
        self.assertEqual(transitions, [(8, 7), (7, 6), (6, 3), (3, 8), (8, 11)])
        self.assertEqual(self.modem('RegistrationState', mm.MODEM_3GPP), mm.REG_ROAMING)
        bearers = self.modem('Bearers')
        self.assertEqual(len(bearers), 1)
        bearer = self.client.props(bearers[0], mm.BEARER)
        self.assertEqual((bearer['Interface'], bearer['Connected'], bearer['Properties']['apn']),
                         ('rmnet0', True, 'internet.example'))
        changes = [s for s in self.client.named('PropertiesChanged') if s[0] == MODEM0 and s[3][0] == mm.MODEM]
        self.assertTrue(any('State' in s[3][1] for s in changes))
        self.assertEqual(self.sitd.actions(), [])

    def test_bearer_ip_configuration(self):
        # What omamobile-sit-data configured: IPv6 only with a CLAT, then
        # dual stack. The CLAT's IPv4 is the phone's own: no Ip4Config.
        v6 = dict(address='2001:db8:64::2', prefix=64, dns=['2001:db8:64::53', '2001:db8:64::54'])
        self.push(data=True, bearer=dict(pdp=2, ipv4=dict(address='192.0.0.1', prefix=29, dns=[], clat=True),
                                         ipv6=v6, clat=True))
        wait_until(lambda: self.modem() == mm.STATE_CONNECTED, 5, 'connected')
        path = self.modem('Bearers')[0]
        wait_until(lambda: self.client.props(path, mm.BEARER)['Ip6Config'], 5, 'Ip6Config')
        bearer = self.client.props(path, mm.BEARER)
        self.assertEqual(bearer['Ip4Config'], {})
        self.assertEqual(bearer['Ip6Config'], {'method': mm.IP_METHOD_STATIC, 'address': '2001:db8:64::2',
                                               'prefix': 64, 'dns1': '2001:db8:64::53',
                                               'dns2': '2001:db8:64::54'})
        self.push(bearer=dict(pdp=3, ipv4=dict(address='192.0.2.2', prefix=32, dns=['192.0.2.53']),
                              ipv6=v6, clat=False))
        wait_until(lambda: self.client.props(path, mm.BEARER)['Ip4Config'], 5, 'Ip4Config')
        self.assertEqual(self.client.props(path, mm.BEARER)['Ip4Config'],
                         {'method': mm.IP_METHOD_STATIC, 'address': '192.0.2.2', 'prefix': 32,
                          'dns1': '192.0.2.53'})
        self.push(data=False)
        wait_until(lambda: not self.client.props(path, mm.BEARER)['Connected'], 5, 'disconnected')
        bearer = self.client.props(path, mm.BEARER)
        self.assertEqual((bearer['Ip4Config'], bearer['Ip6Config']), ({}, {}))
        self.assertNotIn('2001:db8', self.mmd.output())

    def test_signal_quality_and_values(self):
        detail = dict(layout='v2', lte=dict(rssi=-73, rsrp=-95, rsrq=-10, snr=12))
        self.push(signal=60, signal_detail=detail)
        wait_until(lambda: tuple(self.modem('SignalQuality')) == (60, True), 5, 'quality')
        self.assertEqual(self.modem('Lte', mm.SIGNAL), {})          # no rate asked yet, as MM
        self.client.call(MODEM0, mm.SIGNAL, 'Setup', 'u', (5,))
        self.assertEqual(self.modem('Lte', mm.SIGNAL), dict(rssi=-73.0, rsrp=-95.0, rsrq=-10.0, snr=12.0))
        self.assertEqual(self.modem('Nr5g', mm.SIGNAL), {})
        status = self.client.call(MODEM0, mm.SIMPLE, 'GetStatus')[0]
        self.assertEqual(tuple(status['signal-quality']), (60, True))
        self.push(signal=0, signal_detail=None)
        wait_until(lambda: tuple(self.modem('SignalQuality')) == (0, False), 5, 'stale')
        self.assertEqual(self.modem('Lte', mm.SIGNAL), {})

    def test_signal_and_location_setup(self):
        self.client.call(MODEM0, mm.SIGNAL, 'Setup', 'u', (5,))
        self.assertEqual(self.modem('Rate', mm.SIGNAL), 5)
        self.assertEqual(self.modem('Lte', mm.SIGNAL), {})
        self.client.call(MODEM0, mm.LOCATION, 'Setup', 'ub', (mm.LOCATION_3GPP_LAC_CI, True))
        self.assertEqual((self.modem('Enabled', mm.LOCATION), self.modem('SignalsLocation', mm.LOCATION)), (1, True))
        self.assertEqual(self.client.call(MODEM0, mm.LOCATION, 'GetLocation')[0], {})
        self.assertEqual(self.error_of(MODEM0, mm.LOCATION, 'Setup', 'ub', (4, False)), mm.ERROR_PREFIX + 'Unsupported')

    def test_enable_goes_to_sitd_radio(self):
        self.sitd.handlers['radio'] = lambda r: dict(radio='on' if r['on'] else 'off')
        self.client.call(MODEM0, mm.MODEM, 'Enable', 'b', (True,))
        self.assertEqual(self.sitd.actions(), [])         # already on: nothing to do
        self.client.call(MODEM0, mm.MODEM, 'Enable', 'b', (False,))
        self.assertEqual(self.sitd.requests, [dict(action='radio', on=False)])
        self.push(radio='off', registration='not-registered')
        wait_until(lambda: self.modem() == mm.STATE_DISABLED, 5, 'disabled')
        self.assertEqual(self.client.named('StateChanged')[-1][3], (8, 3, mm.CHANGE_USER_REQUESTED))
        self.sitd.handlers['radio'] = lambda r: (_ for _ in ()).throw(FakeRefusal('Call in progress'))
        self.assertEqual(self.error_of(MODEM0, mm.MODEM, 'Enable', 'b', (True,)), mm.ERROR_PREFIX + 'Failed')

    def test_outgoing_call(self):
        def dial(request):
            self.sitd.status['calls'] = [call('100', 'dialing', 'outgoing', request['number'])]
            return dict(call='100', number=request['number'])
        self.sitd.handlers.update(dial=dial, dtmf=lambda r: {}, hangup=lambda r: {}, **{'delete-call': lambda r: {}})
        path = self.client.call(MODEM0, mm.VOICE, 'CreateCall', 'a{sv}', ({'number': GLib.Variant('s', OTHER)},))[0]
        self.assertEqual(path, ROOT + '/Call/0')
        props = self.client.props(path, mm.CALL)
        self.assertEqual((props['State'], props['Direction'], props['Number']),
                         (mm.CALL_UNKNOWN, mm.DIRECTION_OUTGOING, OTHER))
        self.assertEqual(wait_until(lambda: self.client.named('CallAdded'), 5, 'CallAdded')[-1][3], (path,))
        self.client.call(path, mm.CALL, 'Start')
        self.assertEqual(self.sitd.requests[-1], dict(action='dial', number=OTHER))
        self.push()
        for state, sitd_state in ((mm.CALL_RINGING_OUT, 'ringing-out'), (mm.CALL_ACTIVE, 'active')):
            self.sitd.status['calls'] = [call('100', sitd_state, 'outgoing', OTHER)]
            self.push()
            wait_until(lambda: self.client.prop(path, mm.CALL, 'State') == state, 5, sitd_state)
        self.client.call(path, mm.CALL, 'SendDtmf', 's', ('12#',))
        self.assertEqual(self.sitd.requests[-1], dict(action='dtmf', id='100', keys='12#'))
        self.client.call(path, mm.CALL, 'Hangup')
        self.assertEqual(self.sitd.requests[-1], dict(action='hangup', id='100'))
        self.sitd.status['calls'] = [call('100', 'terminated', 'outgoing', OTHER, 'terminated')]
        self.push()
        wait_until(lambda: self.client.prop(path, mm.CALL, 'State') == mm.CALL_TERMINATED, 5, 'terminated')
        spin(.2)
        steps = [s[3] for s in self.client.named('StateChanged') if s[0] == path]
        self.assertEqual(steps, [(mm.CALL_UNKNOWN, mm.CALL_DIALING, mm.REASON_OUTGOING_STARTED),
                                 (mm.CALL_DIALING, mm.CALL_RINGING_OUT, mm.REASON_OUTGOING_STARTED),
                                 (mm.CALL_RINGING_OUT, mm.CALL_ACTIVE, mm.REASON_ACCEPTED),
                                 (mm.CALL_ACTIVE, mm.CALL_TERMINATED, mm.REASON_TERMINATED)])
        self.assertEqual(len(self.client.named('CallAdded')), 1, 'sitd\'s call is the same MM call')
        self.client.call(MODEM0, mm.VOICE, 'DeleteCall', 'o', (path,))
        # The bridge forwards delete-call without waiting for sitd's reply.
        wait_until(lambda: self.sitd.requests[-1] == {'action': 'delete-call', 'id': '100'}, 5, 'delete-call')
        self.assertEqual(self.client.call(MODEM0, mm.VOICE, 'ListCalls')[0], [])
        spin(.1)
        self.assertEqual(self.client.named('CallDeleted')[-1][3], (path,))
        self.push()
        spin(.2)
        self.assertEqual(self.modem('Calls', mm.VOICE), [], 'a deleted call does not come back')

    def test_incoming_call(self):
        self.sitd.handlers.update(accept=lambda r: {})
        self.sitd.status['calls'] = [call('200', 'ringing-in')]
        self.push()
        added = wait_until(lambda: self.client.named('CallAdded'), 5, 'CallAdded')
        path = added[0][3][0]
        props = self.client.props(path, mm.CALL)
        self.assertEqual((props['State'], props['StateReason'], props['Direction'], props['Number']),
                         (mm.CALL_RINGING_IN, mm.REASON_INCOMING_NEW, mm.DIRECTION_INCOMING, SENDER))
        self.assertEqual(self.modem('Calls', mm.VOICE), [path])
        self.assertEqual(self.error_of(path, mm.CALL, 'Start'), mm.ERROR_PREFIX + 'WrongState')
        self.client.call(path, mm.CALL, 'Accept')
        self.assertEqual(self.sitd.requests[-1], dict(action='accept', id='200'))
        self.sitd.status['calls'] = [call('200', 'active')]
        self.push()
        wait_until(lambda: self.client.prop(path, mm.CALL, 'State') == mm.CALL_ACTIVE, 5, 'active')
        self.sitd.status['calls'] = [call('200', 'terminated', reason='terminated')]
        self.push()
        wait_until(lambda: self.client.prop(path, mm.CALL, 'State') == mm.CALL_TERMINATED, 5, 'ended')
        self.assertEqual(self.client.prop(path, mm.CALL, 'StateReason'), mm.REASON_TERMINATED)

    def test_call_errors(self):
        def refuse(request):
            raise FakeRefusal('Cellular service is not registered yet')
        self.sitd.handlers.update(dial=refuse)
        path = self.client.call(MODEM0, mm.VOICE, 'CreateCall', 'a{sv}', ({'number': GLib.Variant('s', OTHER)},))[0]
        self.assertEqual(self.error_of(path, mm.CALL, 'Start'), mm.ERROR_PREFIX + 'WrongState')
        wait_until(lambda: self.client.prop(path, mm.CALL, 'State') == mm.CALL_TERMINATED, 5, 'terminated')
        self.assertEqual(self.client.prop(path, mm.CALL, 'StateReason'), mm.REASON_ERROR)
        self.assertEqual(self.error_of(path, mm.CALL, 'SendDtmf', 's', ('x',)), mm.ERROR_PREFIX + 'InvalidArgs')
        self.assertEqual(self.error_of(path, mm.CALL, 'Accept'), mm.ERROR_PREFIX + 'WrongState')
        self.assertEqual(self.error_of(path, mm.CALL, 'JoinMultiparty'), mm.ERROR_PREFIX + 'Unsupported')
        self.assertEqual(self.error_of(MODEM0, mm.VOICE, 'DeleteCall', 'o', (ROOT + '/Call/99',)),
                         mm.ERROR_PREFIX + 'NotFound')
        self.assertEqual(self.error_of(MODEM0, mm.VOICE, 'CreateCall', 'a{sv}', ({},)), mm.ERROR_PREFIX + 'InvalidArgs')
        self.assertEqual(self.error_of(MODEM0, mm.VOICE, 'CreateCall', 'a{sv}',
                                       ({'number': GLib.Variant('s', '911')},)), mm.ERROR_PREFIX + 'Unsupported')
        for method in ('HoldAndAccept', 'HangupAndAccept', 'Transfer', 'CallWaitingQuery'):
            self.assertEqual(self.error_of(MODEM0, mm.VOICE, method), mm.ERROR_PREFIX + 'Unsupported')

    def test_receive_sms_and_mms_notification(self):
        wap = bytes.fromhex('0106226170706c69636174696f6e2f766e642e7761702e6d6d732d6d65737361676500') + b'x'
        messages = [dict(id='sit:a', number=SENDER, text='hello there', timestamp='2026-09-29T12:34:56+00:00',
                         data='', state='received'),
                    dict(id='sit:b', number=SENDER, text='', timestamp='2026-09-29T12:35:00+00:00',
                         data=wap.hex(), state='received')]
        self.sitd.handlers.update(**{'sms-list': lambda r: messages, 'sms-delete': lambda r: {}})
        self.sitd.status['sms'] = dict(received=['sit:a'])
        self.push()
        wait_until(lambda: len(self.client.named('Added')) == 1, 5, 'first SMS')
        self.sitd.status['sms'] = dict(received=['sit:a', 'sit:b'])
        self.push()
        wait_until(lambda: len(self.client.named('Added')) == 2, 5, 'WAP push')
        paths = self.modem('Messages', mm.MESSAGING)
        self.assertEqual(len(paths), 2)
        self.assertEqual([s[3][1] for s in self.client.named('Added')], [False, True])
        text, push = (self.client.props(p, mm.SMS) for p in paths)
        self.assertEqual((text['State'], text['PduType'], text['Number'], text['Text'], bytes(text['Data']),
                          text['Timestamp'], text['Storage'], text['DeliveryState']),
                         (mm.SMS_RECEIVED, mm.PDU_DELIVER, SENDER, 'hello there', b'',
                          '2026-09-29T12:34:56+00:00', mm.STORAGE_ME, mm.DELIVERY_UNKNOWN))
        # mmsd-tng's rule (plugins/modemmanager.c): Text empty, Data set.
        self.assertEqual((push['Text'], bytes(push['Data'])), ('', wap))
        self.client.call(MODEM0, mm.MESSAGING, 'Delete', 'o', (paths[0],))
        self.assertEqual(self.sitd.requests[-1], {'action': 'sms-delete', 'id': 'sit:a'})
        self.assertEqual(self.client.call(MODEM0, mm.MESSAGING, 'List')[0], [paths[1]])
        spin(.1)
        self.assertEqual(self.client.named('Deleted')[-1][3], (paths[0],))
        self.sitd.status['sms'] = dict(received=['sit:b'])
        self.push()
        spin(.3)
        self.assertEqual(self.modem('Messages', mm.MESSAGING), [paths[1]], 'no duplicate after the delete')

    def test_send_sms(self):
        outcomes = []

        def send(request):
            outcomes.append(request)
            return dict(state='sent', error='', completed=1)
        self.sitd.handlers['sms-send'] = send
        path = self.client.call(MODEM0, mm.MESSAGING, 'Create', 'a{sv}', ({
            'number': GLib.Variant('s', OTHER), 'text': GLib.Variant('s', 'omamobile test text'),
            'delivery-report-request': GLib.Variant('b', True), 'validity': GLib.Variant('u', 167)},))[0]
        props = self.client.props(path, mm.SMS)
        self.assertEqual((props['State'], props['PduType'], props['DeliveryReportRequest'], props['Validity']),
                         (mm.SMS_UNKNOWN, mm.PDU_SUBMIT, True, (mm.VALIDITY_RELATIVE, 167)))
        spin(.1)
        self.assertEqual(self.client.named('Added')[-1][3], (path, False))
        self.client.call(path, mm.SMS, 'Send')
        self.assertEqual(self.client.prop(path, mm.SMS, 'State'), mm.SMS_SENT)
        self.assertEqual((outcomes[0]['number'], outcomes[0]['text']), (OTHER, 'omamobile test text'))
        self.assertRegex(outcomes[0]['request_id'], r'^[0-9a-f]{32}$')
        self.assertEqual(self.error_of(path, mm.SMS, 'Send'), mm.ERROR_PREFIX + 'WrongState')
        self.assertEqual(len(outcomes), 1)

    def test_failed_sms_keeps_its_send_id(self):
        seen = []

        def send(request):
            seen.append(request['request_id'])
            return dict(state='unknown', error='Delivery uncertain; check with the recipient before sending again',
                        completed=0)
        self.sitd.handlers['sms-send'] = send
        path = self.client.call(MODEM0, mm.MESSAGING, 'Create', 'a{sv}', ({
            'number': GLib.Variant('s', OTHER), 'text': GLib.Variant('s', 'omamobile test text')},))[0]
        for _ in range(2):
            self.assertEqual(self.error_of(path, mm.SMS, 'Send'), mm.ERROR_PREFIX + 'Failed')
            self.assertEqual(self.client.prop(path, mm.SMS, 'State'), mm.SMS_UNKNOWN)
        self.assertEqual(len(set(seen)), 1, 'a retry reuses the send ID, so sitd never sends twice')
        self.assertEqual(self.error_of(MODEM0, mm.MESSAGING, 'Create', 'a{sv}', ({
            'number': GLib.Variant('s', OTHER), 'data': GLib.Variant('ay', b'12')},)), mm.ERROR_PREFIX + 'Unsupported')
        self.assertEqual(self.error_of(MODEM0, mm.MESSAGING, 'Create', 'a{sv}', ({
            'number': GLib.Variant('s', OTHER)},)), mm.ERROR_PREFIX + 'InvalidArgs')
        self.assertEqual(self.error_of(MODEM0, mm.MESSAGING, 'Delete', 'o', (ROOT + '/SMS/99',)),
                         mm.ERROR_PREFIX + 'NotFound')

    def test_not_yet_supported(self):
        sim = self.modem('Sim')
        for path, interface, method, signature, args in (
                (ROOT, mm.MM, 'ScanDevices', None, ()),
                (MODEM0, mm.MODEM, 'Command', 'su', ('AT', 1)),
                (MODEM0, mm.MODEM, 'CreateBearer', 'a{sv}', ({},)),
                (MODEM0, mm.MODEM_3GPP, 'Register', 's', ('',)),
                (MODEM0, mm.MODEM_3GPP, 'Scan', None, ()),
                (MODEM0, mm.SIMPLE, 'Connect', 'a{sv}', ({},)),
                (sim, mm.SIM, 'SendPuk', 'ss', ('00000000', '0000')),
                (sim, mm.SIM, 'ChangePin', 'ss', ('0000', '1111'))):
            self.assertEqual(self.error_of(path, interface, method, signature, args), mm.ERROR_PREFIX + 'Unsupported')
        # A ready SIM isn't asking for its PIN: nothing goes to sitd.
        self.assertEqual(self.error_of(sim, mm.SIM, 'SendPin', 's', ('0000',)), mm.ERROR_PREFIX + 'WrongState')
        self.assertEqual(self.sitd.actions(), [])

    def test_send_pin_goes_to_sitd_once(self):
        status = blank_status(sim='pin')
        status['modem']['sim'].update(pin_retries=3, puk_retries=10)
        self.push(status)
        wait_until(lambda: self.modem() == mm.STATE_LOCKED, 5, 'locked')
        sim = self.modem('Sim')
        self.sitd.handlers['sim-pin'] = lambda r: (_ for _ in ()).throw(FakeRefusal('Wrong SIM PIN; 2 tries left'))
        self.assertEqual(self.error_of(sim, mm.SIM, 'SendPin', 's', ('1357',)), mm.ERROR_PREFIX + 'Failed')
        self.sitd.handlers['sim-pin'] = lambda r: dict(accepted=True, tries_left=2)
        self.client.call(sim, mm.SIM, 'SendPin', 's', ('2468',))
        self.assertEqual(self.sitd.actions(), ['sim-pin', 'sim-pin'])
        self.assertEqual([r['pin'] for r in self.sitd.requests], ['1357', '2468'])
        self.assertNotIn('2468', self.mmd.output())

    def test_sitd_going_away_and_coming_back(self):
        self.sitd.status['calls'] = [call('200', 'ringing-in')]
        self.push()
        wait_until(lambda: self.client.named('CallAdded'), 5, 'call')
        self.sitd.stop()
        wait_until(lambda: self.client.objects() == {}, 10, 'the modem to go')
        removed = self.client.named('InterfacesRemoved')[-1][3]
        self.assertEqual(removed[0], MODEM0)
        self.assertEqual(sorted(removed[1]), sorted(bridge.FULL_INTERFACES))
        self.sitd.start()
        objects = wait_until(lambda: self.client.objects(), 15, 'a new modem')
        self.assertEqual(list(objects), [ROOT + '/Modem/1'])

    def test_introspection(self):
        xml = self.client.call(ROOT, 'org.freedesktop.DBus.Introspectable', 'Introspect')[0]
        self.assertIn('<node name="Modem"/>', xml.replace(' ', ' '))
        xml = self.client.call(MODEM0, 'org.freedesktop.DBus.Introspectable', 'Introspect')[0]
        for interface in bridge.FULL_INTERFACES:
            self.assertIn(f'<interface name="{interface}">', xml)


POLKIT_XML = '''<node><interface name="org.freedesktop.PolicyKit1.Authority">
<method name="CheckAuthorization"><arg type="(sa{sv})" direction="in"/><arg type="s" direction="in"/>
<arg type="a{ss}" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/>
<arg type="(bba{ss})" direction="out"/></method></interface></node>'''


class Polkit(BridgeTests):
    """The shipped behaviour: methods with an action go through polkit for
    a caller that isn't root (the test's own uid here). A fake authority on
    the private bus answers, as the real one would."""
    status = staticmethod(registered_status)
    mmd_args = ('--polkit',)

    def before_mmd(self):
        self.asked = []
        self.allow = set()
        info = env.Gio.DBusNodeInfo.new_for_xml(POLKIT_XML).interfaces[0]

        def check(connection, sender, path, interface, method, parameters, invocation):
            subject, action, details, flags, cancel = parameters.unpack()
            self.asked.append((subject[0], action, flags))
            invocation.return_value(GLib.Variant('((bba{ss}))', ((action in self.allow, False, {}),)))
        self.bus.connection.register_object('/org/freedesktop/PolicyKit1/Authority', info, check, None, None)
        self.bus.connection.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
                                      'RequestName', GLib.Variant('(su)', ('org.freedesktop.PolicyKit1', 0)),
                                      None, env.Gio.DBusCallFlags.NONE, 5000, None)

    def outcome(self, *args):
        box = self.client.call_async(*args)
        wait_until(lambda: box, 10, 'the reply')
        return box

    def test_reading_needs_no_authorisation(self):
        box = self.outcome(MODEM0, mm.VOICE, 'ListCalls')
        self.assertEqual(box.get('result'), ([],))
        self.assertEqual(self.asked, [])

    def test_denied_and_allowed(self):
        args = (MODEM0, mm.VOICE, 'CreateCall', 'a{sv}', ({'number': GLib.Variant('s', OTHER)},))
        box = self.outcome(*args)
        self.assertIn(mm.ERROR_PREFIX + 'Unauthorized', box['error'].message)
        self.assertEqual(self.asked, [('system-bus-name', 'org.freedesktop.ModemManager1.Voice', 1)])
        self.assertEqual(self.client.prop(MODEM0, mm.VOICE, 'Calls'), [])
        self.allow.add('org.freedesktop.ModemManager1.Voice')
        box = self.outcome(*args)
        self.assertEqual(box.get('result'), (ROOT + '/Call/0',))
        box = self.outcome(MODEM0, mm.MODEM, 'Enable', 'b', (False,))
        self.assertIn(mm.ERROR_PREFIX + 'Unauthorized', box['error'].message)
        self.assertEqual(self.asked[-1][1], 'org.freedesktop.ModemManager1.Device.Control')
        self.assertEqual(self.sitd.actions(), [], 'nothing reached sitd without authorisation')


if __name__ == '__main__':
    unittest.main()
