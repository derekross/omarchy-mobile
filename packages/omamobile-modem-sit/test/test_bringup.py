# SPDX-License-Identifier: MIT
import env  # noqa: F401  (paths and sys.path first)
import contextlib
import io
import tempfile
from pathlib import Path
import unittest
from unittest.mock import Mock, patch
import bringup
import paths
from sit import ModemError

SETTINGS = paths.config('/nonexistent')
SETTINGS['network']['apn'] = 'internet.example'
SETTINGS['network']['attach_apn'] = 'internet.example'
OVERRIDES = str(Path(__file__).resolve().parent.parent / 'share' / 'apn-overrides.conf')


def sim_with_aid():
    """A READY USIM with a made-up 8-byte AID."""
    record = bytearray(63)
    record[0], record[1], record[3] = 2, 5, 8
    record[4:12] = bytes(range(0xa0, 0xa8))
    return bytes([1, 0, 1]) + bytes(record)


def sim(card, *apps):
    payload = bytes([card, 0, len(apps)])
    for app_type, state in apps:
        record = bytearray(63)
        record[0], record[1] = app_type, state
        payload += bytes(record)
    return payload


def clock(step=.5):
    now = [0.0]

    def tick():
        now[0] += step
        return now[0]
    return tick


class BringupTests(unittest.TestCase):
    def test_sim_requires_ready_usim_and_rejects_truncation(self):
        self.assertTrue(bringup.sim_ready(bytes([1, 0, 1, 2, 5]) + bytes(61)))
        self.assertFalse(bringup.sim_ready(bytes([1, 0, 1, 2, 2]) + bytes(61)))
        self.assertFalse(bringup.sim_ready(bytes([0, 0, 0])))
        with self.assertRaises(ValueError):
            bringup.sim_ready(bytes([1, 0, 1, 2, 5]))

    def test_actual_lte_registration_required(self):
        self.assertTrue(bringup.packet_registered(bytes([5, 0, 0, 14]), lte=True))
        self.assertFalse(bringup.packet_registered(bytes([1, 0, 0, 21]), lte=True))
        self.assertFalse(bringup.packet_registered(bytes([0, 0, 0, 14]), lte=True))

    def test_shutdown_cancels_wait_before_any_query(self):
        service = Mock()
        predicate = Mock()
        with self.assertRaises(InterruptedError):
            bringup.wait_for(service, predicate, 1, lambda: True)
        predicate.assert_not_called()

    def test_failed_data_setup_never_attempts_ims(self):
        service = Mock()
        with patch.object(bringup, 'wait_for'), patch.object(bringup, 'radio'), \
             patch.object(bringup, 'radio_state', return_value=0), \
             patch.object(bringup, 'initial_attach'), patch.object(bringup, 'provision_profiles'), \
             patch.object(bringup, 'nr_mode'), patch.object(bringup, 'clear_stale', return_value=0), patch.object(bringup, 'release_owned', return_value=False), patch.object(bringup, 'activate', side_effect=TimeoutError), \
             patch.object(bringup, 'data_snapshot'), \
             patch.object(bringup, 'start_stack') as stack, patch.object(bringup, 'register') as register:
            with self.assertRaises(TimeoutError):
                bringup.start(service, SETTINGS)
            stack.assert_not_called()
            register.assert_not_called()
            service.client.request.assert_not_called()

    def run_start(self, settings, imsi_reply, overrides=OVERRIDES):
        """start() past the SIM stage with every modem step mocked; GET_IMSI
        answers imsi_reply (bytes, or an exception to raise)."""
        service = Mock()
        sim_payload = sim_with_aid()

        def request(ident, payload=b'', timeout=8):
            if ident == 0x0400:
                self.assertEqual(payload[0], 8)
                self.assertEqual(len(payload), 17)
                if isinstance(imsi_reply, Exception):
                    raise imsi_reply
                return imsi_reply
            return sim_payload
        service.client.request.side_effect = request
        out = io.StringIO()

        def fake_wait(service_, predicate, seconds, stopped):
            if seconds == settings['network'].getint('sim_timeout', 120):
                predicate()
        with patch.object(bringup, 'wait_for', side_effect=fake_wait), patch.object(bringup, 'radio') as radio, \
             patch.object(bringup, 'radio_state', return_value=0), \
             patch.object(bringup, 'initial_attach') as attach, \
             patch.object(bringup, 'provision_profiles') as profiles, \
             patch.object(bringup, 'nr_mode'), patch.object(bringup, 'activate') as activate, \
             patch.object(bringup, 'data_snapshot'), patch.object(bringup, 'find_attach_bearer', return_value=None), \
             patch.object(bringup, 'start_stack'), patch.object(bringup, 'register'), \
             patch.object(bringup.carrier_apn, 'OVERRIDES', overrides), \
             patch.object(bringup.carrier_apn, 'DATABASE', '/nonexistent.xml'), \
             contextlib.redirect_stdout(out):
            bringup.start(service, settings)
        return service, out.getvalue(), radio, attach, profiles, activate

    def tearDown(self):
        bringup.data_call.INTERNET_CID = 1

    def test_auto_apn_comes_from_the_sims_home_network(self):
        """A Verizon-network SIM: what registered IMS and carried calls and
        texts on the 7 Pro on 2026-11-03 (NOTES, IMS-SHANNON 11-12): no
        attach APN, stock's four profiles, IMS first on CID 2, the internet
        on CID 3."""
        settings = paths.config('/nonexistent')
        fake = '311480' + '0' * 9
        service, log, radio, attach, profiles, activate = self.run_start(
            settings, bytes([15]) + fake.encode())
        attach.assert_not_called()
        sent = profiles.call_args.args[1]
        self.assertEqual([(p.ident, p.apn, p.type_names(), p.ip, p.roaming_ip) for p in sent],
                         [(0, 'VZWINTERNET', 'default,supl,dun', 'ipv4v6', 'ipv4v6'),
                          (2, 'IMS', 'ims,ia', 'ipv4v6', 'ipv6'),
                          (3, 'VZWADMIN', 'fota', 'ipv4v6', 'ipv4v6'),
                          (4, 'VZWAPP', 'mms,cbs', 'ipv4v6', 'ipv4v6')])
        # IMS first (CID 2, the IMS profile's types), then the internet on CID 3.
        self.assertEqual([(c.args[1], c.kwargs.get('ims', False)) for c in activate.call_args_list],
                         [('IMS', True), ('VZWINTERNET', False)])
        self.assertEqual(activate.call_args_list[0].kwargs['apn_types'], 0x140)
        self.assertEqual(bringup.data_call.INTERNET_CID, 3)
        self.assertEqual(service.apn, dict(value='VZWINTERNET', source='override',
                                           attach='none', attach_source='override'))
        self.assertIn('APN chosen from', log)
        self.assertIn('attach APN chosen from', log)
        self.assertIn('not sent (attach_apn = none)', log)
        self.assertIn('bearer order and data profiles from', log)
        for secret in (fake, '311', '480', 'vzwinternet', 'vzwadmin', 'vzwapp'):
            self.assertNotIn(secret, log.lower())

    def test_typed_values_win_and_the_imsi_is_never_read(self):
        settings = paths.config('/nonexistent')
        settings['network'].update(apn='internet.example', attach_apn='internet.example', ims_apn='ims',
                                   ims_first='no', internet_cid='1')
        service, _, _, attach, profiles, activate = self.run_start(settings, AssertionError('GET_IMSI sent'))
        attach.assert_called_once_with(service.client, 'internet.example', 'ipv4v6', ims=False)
        self.assertEqual([p.apn for p in profiles.call_args.args[1]], ['internet.example'])
        self.assertEqual([c.args[1] for c in activate.call_args_list], ['internet.example', 'ims'])
        self.assertEqual((service.apn['source'], service.apn['attach_source']), ('manual', 'manual'))

    def test_a_typed_apn_still_takes_the_carriers_attach_and_bearer_order(self):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = 'vzwinternet'
        service, log, _, attach, profiles, activate = self.run_start(settings, bytes([15]) + b'311480000000000')
        attach.assert_not_called()
        # The typed internet APN is the internet bearer's; the carrier's
        # profiles (profile 0 included) and its bearer order still apply.
        self.assertEqual([(p.ident, p.apn) for p in profiles.call_args.args[1]],
                         [(0, 'VZWINTERNET'), (2, 'IMS'), (3, 'VZWADMIN'), (4, 'VZWAPP')])
        self.assertEqual([c.args[1] for c in activate.call_args_list], ['IMS', 'vzwinternet'])
        self.assertEqual(bringup.data_call.INTERNET_CID, 3)
        self.assertEqual((service.apn['source'], service.apn['attach_source']), ('manual', 'override'))
        self.assertIn('typed values kept', log)

    def test_typed_profiles_replace_the_carriers(self):
        settings = paths.config('/nonexistent')
        settings.read_string('[profiles]\n3 = fota.example; types=fota\n')
        _, _, _, _, profiles, _ = self.run_start(settings, bytes([15]) + b'311480000000000')
        self.assertEqual([(p.ident, p.apn) for p in profiles.call_args.args[1]],
                         [(0, 'VZWINTERNET'), (3, 'fota.example')])

    def test_without_a_carrier_attach_apn_the_internet_apn_attaches(self):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = 'internet.example'
        service, _, _, attach, _, activate = self.run_start(settings, bytes([15]) + b'001010000000000')
        attach.assert_called_once_with(service.client, 'internet.example', 'ipv4v6', ims=False)
        self.assertEqual(service.apn['attach_source'], 'same')
        self.assertEqual([c.args[1] for c in activate.call_args_list], ['internet.example', 'ims'])
        self.assertEqual(bringup.data_call.INTERNET_CID, 1)

    def test_no_apn_found_registers_for_calls_and_sms_without_data(self):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = ''
        service, log, radio, attach, profiles, activate = self.run_start(settings, ModemError(2, b''))
        radio.assert_any_call(True)
        attach.assert_not_called()
        profiles.assert_not_called()
        # Only the IMS bearer: no internet bearer without an APN.
        self.assertEqual([c.kwargs.get('ims') for c in activate.call_args_list], [True])
        self.assertEqual(service.apn, dict(value='', source='none', attach='', attach_source='same'))
        self.assertIn('without mobile data', log)

    def test_unknown_network_code_is_no_apn(self):
        settings = paths.config('/nonexistent')
        _, _, _, attach, _, _ = self.run_start(settings, bytes([15]) + b'001010000000000')
        attach.assert_not_called()

    def test_bad_typed_bearer_keys_stop_startup(self):
        for key, value in (('ims_first', 'maybe'), ('internet_cid', '2'), ('internet_cid', 'x'), ('internet_cid', '16')):
            settings = paths.config('/nonexistent')
            settings['network'].update(apn='internet.example', attach_apn='internet.example')
            settings['network'][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.run_start(settings, bytes([15]) + b'001010000000000')

    def test_an_overrides_ims_cid_is_refused_by_the_override_not_the_config(self):
        """internet_cid = 2 in an override is left out there (CID 1 stays),
        and the log names the override: never "[network] internet_cid"."""
        with tempfile.NamedTemporaryFile('w', suffix='.conf', delete=False) as f:
            f.write('[001/01]\nname = Test\napn = internet.example\ninternet_cid = 2\n')
        try:
            settings = paths.config('/nonexistent')
            _, log, _, _, _, _ = self.run_start(settings, bytes([15]) + b'001010000000000', overrides=f.name)
        finally:
            Path(f.name).unlink()
        self.assertEqual(bringup.data_call.INTERNET_CID, 1)
        self.assertIn("carrier override for this SIM has values that don't check, left out: "
                      'internet_cid (1..15, not 2: the IMS bearer)', log)
        self.assertNotIn('[network]', log)

    def test_imsi_layout_is_checked(self):
        client = Mock()
        for reply in (b'', bytes([20]) + b'1' * 20, bytes([15]) + b'31148000000000x', bytes([15]) + b'1'):
            client.request.return_value = reply
            with self.assertRaises(ValueError):
                bringup.read_imsi(client, b'\xa0' * 8)

    def test_usim_aid_only_from_a_ready_usim(self):
        self.assertEqual(bringup.usim_aid(sim_with_aid()), bytes(range(0xa0, 0xa8)))
        self.assertIsNone(bringup.usim_aid(sim(1, (2, 2))))
        self.assertIsNone(bringup.usim_aid(b''))

    def attach_run(self, attach_apn):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = 'internet.example'
        settings['network']['attach_apn'] = attach_apn
        service = Mock()
        with patch.object(bringup, 'wait_for'), patch.object(bringup, 'radio'), \
             patch.object(bringup, 'radio_state', return_value=0), \
             patch.object(bringup, 'initial_attach') as attach, \
             patch.object(bringup, 'provision_profiles') as profile, \
             patch.object(bringup, 'nr_mode'), patch.object(bringup, 'data_snapshot'), \
             patch.object(bringup, 'clear_stale', return_value=0), patch.object(bringup, 'release_owned', return_value=False), patch.object(bringup, 'activate', side_effect=TimeoutError) as activate:
            with self.assertRaises(TimeoutError):
                bringup.start(service, settings)
        return attach, profile, activate

    def withdraw_case(self, *, registered, cleared):
        service = Mock()
        registration = Mock()
        registration.exists.side_effect = [registered, registered and not cleared]
        with patch.object(bringup, 'wait_for'), patch.object(bringup, 'radio'), \
             patch.object(bringup, 'radio_state', return_value=0), \
             patch.object(bringup, 'initial_attach'), patch.object(bringup, 'provision_profiles'), \
             patch.object(bringup, 'nr_mode'), patch.object(bringup, 'data_snapshot'), \
             patch.object(bringup, 'REGISTRATION', registration), \
             patch.object(bringup, 'clear_stale', return_value=cleared), \
             patch.object(bringup, 'release_owned', return_value=False), \
             patch.object(bringup, 'withdraw_stale') as withdraw, \
             patch.object(bringup, 'activate', side_effect=TimeoutError):
            with self.assertRaises(TimeoutError):
                bringup.start(service, SETTINGS)
        return withdraw

    def test_a_stale_ims_registration_is_withdrawn_before_the_bearers(self):
        self.withdraw_case(registered=True, cleared=5).assert_called_once()
        self.withdraw_case(registered=False, cleared=4).assert_not_called()
        # The modem still lists a bearer: nothing cleared, nothing withdrawn.
        self.withdraw_case(registered=True, cleared=0).assert_not_called()

    def release_case(self, *, owned, listed, confirmed=True, registered=True):
        client = Mock()
        response = Mock()
        response.exists.return_value = confirmed
        registration = Mock()
        registration.exists.return_value = registered
        order = []
        with patch.object(bringup, 'owned_ids', return_value=set(owned)), \
             patch.object(bringup, 'call_ids', return_value=set(listed)), \
             patch.object(bringup, 'modem_owned_ids', return_value=set()), \
             patch.object(bringup, 'bearer_paths', return_value=(Mock(), response)), \
             patch.object(bringup, 'REGISTRATION', registration), \
             patch.object(bringup, 'unregister', side_effect=lambda c: order.append('unregister')), \
             patch.object(bringup, 'deactivate', side_effect=lambda c, cid: order.append(cid)):
            return bringup.release_owned(client), order

    def test_a_restart_with_the_radio_on_releases_exactly_our_bearers(self):
        self.assertEqual(self.release_case(owned={1, 2}, listed={1, 2}), (True, ['unregister', 2, 1]))
        self.assertEqual(self.release_case(owned={1, 2}, listed={1, 2}, registered=False), (True, [2, 1]))
        # A bearer we don't own, one we own missing, or an unconfirmed setup: nothing
        self.assertEqual(self.release_case(owned={1, 2}, listed={1, 2, 4}), (False, []))
        self.assertEqual(self.release_case(owned={1, 2}, listed={1}), (False, []))
        self.assertEqual(self.release_case(owned={1, 2}, listed={1, 2}, confirmed=False), (False, []))
        self.assertEqual(self.release_case(owned=set(), listed={1}), (False, []))

    def test_attach_apn_is_used_only_for_the_initial_attach(self):
        attach, profile, activate = self.attach_run('ims.example')
        self.assertEqual(attach.call_args.args[1], 'ims.example')
        self.assertEqual([p.apn for p in profile.call_args.args[1]], ['internet.example'])
        self.assertEqual(activate.call_args.args[1], 'internet.example')
        self.assertNotIn('ims', activate.call_args.kwargs)

    def test_attach_on_the_ims_apn_requests_the_pcscf(self):
        attach, _, _ = self.attach_run('ims')          # ims_apn auto: "ims" without an override
        self.assertEqual(attach.call_args.kwargs, {'ims': True})
        attach, _, _ = self.attach_run('other.example')
        self.assertEqual(attach.call_args.kwargs, {'ims': False})
        attach, _, _ = self.attach_run('')
        self.assertEqual(attach.call_args.kwargs, {'ims': False})

    def test_empty_attach_apn_attaches_on_the_internet_apn(self):
        for value in ('', '  ', 'auto'):
            attach, profile, _ = self.attach_run(value)
            self.assertEqual(attach.call_args.args[1], 'internet.example')
            self.assertEqual([p.apn for p in profile.call_args.args[1]], ['internet.example'])

    def test_apns_default_to_auto(self):
        net = paths.config('/nonexistent')['network']
        self.assertEqual((net['apn'], net['attach_apn'], net['ims_apn'], net['ims_first'], net['internet_cid']),
                         ('auto', 'auto', 'auto', 'auto', 'auto'))

    def test_wait_keeps_handling_incoming_sms(self):
        service = Mock()
        service.client.next_indication.side_effect = [b'private-sms', None]
        with patch.object(bringup.time, 'monotonic', side_effect=[0, 0, 0, 0, 2, 2]):
            bringup.wait_for(service, Mock(side_effect=[False, True]), 10, lambda: False)
        service.event.assert_called_once_with(b'private-sms')

    def test_readonly_status_timeout_does_not_abort_startup(self):
        service = Mock()
        service.client.next_indication.return_value = None
        with patch.object(bringup.time, 'monotonic', side_effect=[0, 0, 0, 0, 2, 2]):
            bringup.wait_for(service, Mock(side_effect=[TimeoutError(), True]), 10, lambda: False)



class OrderTests(unittest.TestCase):
    """Stock's order: attach APN, profiles and NR mode before radio on, the
    radio switched on once (never off when it is already on), and one line
    with the time to the first packet registration."""

    def run_start(self, level, settings=None, registrations=(bytes([1, 0, 0, 14]),), times=None):
        settings = settings or SETTINGS
        order = []
        service = Mock()
        service.client.request.side_effect = lambda ident, *a, **k: (
            order.append('reg') or registrations[min(order.count('reg'), len(registrations)) - 1])

        def wait(svc, predicate, seconds, stopped):
            # The SIM wait passes at once; the registration wait polls its
            # predicate until it holds, as wait_for does.
            if seconds == settings['network'].getint('sim_timeout'):
                return
            while not predicate():
                pass

        def note(name):
            return lambda *a, **k: order.append(name)
        patches = [patch.object(bringup, 'wait_for', wait),
                   patch.object(bringup, 'radio_state', side_effect=lambda: order.append('state') or level),
                   patch.object(bringup, 'radio', side_effect=lambda on: order.append('on' if on else 'off')),
                   patch.object(bringup, 'initial_attach', side_effect=note('attach')),
                   patch.object(bringup, 'provision_profiles', side_effect=note('profiles')),
                   patch.object(bringup, 'nr_mode', side_effect=note('nr')),
                   patch.object(bringup, 'data_snapshot'),
                   patch.object(bringup, 'clear_stale', return_value=0), patch.object(bringup, 'release_owned', return_value=False), patch.object(bringup, 'activate', side_effect=TimeoutError('stop here'))]
        printer = patch('builtins.print')
        if times:
            patches.append(patch.object(bringup.time, 'monotonic', side_effect=times))
        for item in patches:
            item.start()
        out = printer.start()
        patches.append(printer)
        try:
            with self.assertRaises(TimeoutError):
                bringup.start(service, settings)
            lines = [' '.join(str(a) for a in c.args) for c in out.call_args_list]
        finally:
            for item in reversed(patches):
                item.stop()
        return order, lines

    def test_radio_off_settings_then_radio_on_once(self):
        order, _ = self.run_start(0)
        self.assertEqual(order[:6], ['state', 'attach', 'profiles', 'nr', 'on', 'reg'])
        self.assertNotIn('off', order)
        self.assertEqual(order.count('on'), 1)

    def test_radio_already_on_is_never_switched(self):
        order, lines = self.run_start(1)
        self.assertEqual(order[:5], ['state', 'attach', 'profiles', 'nr', 'reg'])
        self.assertNotIn('off', order)
        self.assertNotIn('on', order)
        self.assertTrue(any('no radio cycle' in l for l in lines))

    def test_flight_mode_counts_as_off(self):
        order, _ = self.run_start(4)
        self.assertEqual(order[:5], ['state', 'attach', 'profiles', 'nr', 'on'])

    def test_unreadable_state_falls_back_to_the_old_cycle(self):
        order, lines = self.run_start(None)
        self.assertEqual(order[:6], ['state', 'off', 'attach', 'profiles', 'nr', 'on'])
        self.assertTrue(any('radio state unreadable' in l for l in lines))

    def test_nr_on_leaves_the_nr_mode_alone(self):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = 'internet.example'
        settings['network']['nr'] = 'on'
        order, _ = self.run_start(0, settings, registrations=(bytes([1, 0, 0, 21]),))
        self.assertEqual(order[:4], ['state', 'attach', 'profiles', 'on'])
        self.assertNotIn('nr', order)

    def test_nr_off_waits_for_lte_after_the_first_registration(self):
        order, lines = self.run_start(0, registrations=(bytes(4), bytes([1, 0, 0, 21]), bytes([1, 0, 0, 14])))
        self.assertEqual(order.count('reg'), 3)
        self.assertEqual(len([l for l in lines if l.startswith('Registration:')]), 1)

    def test_profiles_are_sent_from_the_config(self):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = 'internet.example'
        settings.read_string('[profiles]\n2 = ims.example; types=ia,ims; roaming_ip=ipv6\n')
        with patch.object(bringup, 'provision_profiles') as sent, patch.object(bringup, 'radio_state', return_value=0), \
             patch.object(bringup, 'radio'), patch.object(bringup, 'initial_attach'), patch.object(bringup, 'nr_mode'), \
             patch.object(bringup, 'wait_for', side_effect=[None, InterruptedError]):
            with self.assertRaises(InterruptedError):
                bringup.start(Mock(), settings)
        self.assertEqual([(p.ident, p.apn) for p in sent.call_args.args[1]],
                         [(0, 'internet.example'), (2, 'ims.example')])

    def test_a_bad_profile_stops_before_the_radio(self):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = 'internet.example'
        settings.read_string('[profiles]\n2 = ims.example; types=voice\n')
        with patch.object(bringup, 'radio') as radio, patch.object(bringup, 'radio_state') as state, \
             self.assertRaises(RuntimeError) as raised:
            bringup.start(Mock(), settings)
        radio.assert_not_called()
        state.assert_not_called()
        self.assertIn('Bad data profile', str(raised.exception))

    def test_registration_time_from_radio_on(self):
        # start() begins at 100; radio on at 110; registered at 152.5.
        _, lines = self.run_start(0, times=[100, 110, 152.5] + [200] * 20)
        self.assertIn('Registration: packet registered 42.5 s after radio on, RAT 14', lines)

    def test_registration_time_from_start_when_already_on(self):
        _, lines = self.run_start(1, times=[100, 134.0] + [200] * 20)
        self.assertIn('Registration: packet registered 34.0 s after start-up began '
                      '(the radio was already on), RAT 14', lines)


class SimStageTests(unittest.TestCase):
    def run_sim_stage(self, payload):
        service = Mock()
        service.client.request.return_value = payload
        service.client.next_indication.return_value = None
        with patch.object(bringup.time, 'monotonic', side_effect=clock()), \
             patch.object(bringup, 'radio') as radio, patch.object(bringup, 'radio_state') as state, \
             patch.object(bringup, 'initial_attach') as attach:
            with self.assertRaises((RuntimeError, TimeoutError)) as raised:
                bringup.start(service, SETTINGS)
        radio.assert_not_called()
        state.assert_not_called()
        attach.assert_not_called()
        return str(raised.exception)

    def test_lock_states(self):
        self.assertIsNone(bringup.sim_lock(sim(1, (2, 5))))
        self.assertIsNone(bringup.sim_lock(sim(0)))
        self.assertEqual(bringup.sim_lock(sim(1, (2, 2))), 'PIN')
        self.assertEqual(bringup.sim_lock(sim(1, (5, 5), (2, 3))), 'PUK')
        self.assertEqual(bringup.sim_lock(sim(1, (2, 4))), 'network')

    def test_pin_lock_stops_startup_well_before_the_timeout(self):
        message = self.run_sim_stage(sim(1, (2, 2), (5, 2)))
        self.assertIn('PIN lock is on', message)

    def test_puk_block_says_never_guess(self):
        self.assertIn('never guess', self.run_sim_stage(sim(1, (2, 3))))

    def test_no_card_times_out_with_the_reason(self):
        message = self.run_sim_stage(sim(0))
        self.assertIn('no SIM card detected', message)

    def test_a_transient_lock_state_is_not_fatal(self):
        service = Mock()
        service.client.request.side_effect = [sim(1, (2, 2)), sim(1, (2, 5))]
        service.client.next_indication.return_value = None
        with patch.object(bringup.time, 'monotonic', side_effect=clock()), \
             patch.object(bringup, 'radio_state', side_effect=InterruptedError):
            with self.assertRaises(InterruptedError):
                bringup.start(service, SETTINGS)


class IsimFallbackWiringTests(unittest.TestCase):
    def run_ims(self, value):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = 'internet.example'
        if value is not None:
            settings['network']['ims_pcscf_from_isim'] = value
        service = Mock()
        with patch.object(bringup, 'wait_for'), patch.object(bringup, 'radio'), \
             patch.object(bringup, 'radio_state', return_value=0), \
             patch.object(bringup, 'initial_attach'), patch.object(bringup, 'provision_profiles'), \
             patch.object(bringup, 'nr_mode'), patch.object(bringup, 'data_snapshot'), \
             patch.object(bringup, 'clear_stale', return_value=0), patch.object(bringup, 'release_owned', return_value=False), patch.object(bringup, 'activate'), patch.object(bringup, 'start_stack'), \
             patch.object(bringup, 'find_attach_bearer', return_value=None), \
             patch.object(bringup, 'ipv6_pcscf', return_value=['x']) as read, \
             patch.object(bringup, 'register', side_effect=RuntimeError('stop')) as register, \
             patch('builtins.print'):
            bringup.start(service, settings)
            fallback = register.call_args.kwargs['pcscf_fallback']
            if fallback is not None:
                self.assertEqual(fallback(b'bearer'), ['x'])
                self.assertEqual(read.call_args.args[2], b'bearer')
        return fallback

    def test_on_by_default_and_off_by_setting(self):
        self.assertIsNotNone(self.run_ims(None))
        self.assertIsNone(self.run_ims('no'))

    def test_ims_bearer_ip_type_follows_the_ims_profile(self):
        from data_call import Profile, APN_TYPES
        ims = Profile(2, 'IMS', APN_TYPES['ia'] | APN_TYPES['ims'], 'ipv4v6', 'ipv6')
        internet = Profile(0, 'internet.example', APN_TYPES['default'])
        self.assertEqual(bringup.ims_ip_type([internet, ims], 'ims'), 'ipv4v6')
        self.assertEqual(bringup.ims_ip_type([internet], 'ims'), 'ipv6')
        self.assertEqual(bringup.ims_ip_type([internet, ims], 'vzwims'), 'ipv6')

    def test_ims_setup_apn_types_follow_the_ims_profile(self):
        from data_call import Profile, APN_TYPES
        ims = Profile(2, 'IMS', APN_TYPES['ia'] | APN_TYPES['ims'], 'ipv4v6', 'ipv6')
        internet = Profile(0, 'internet.example', APN_TYPES['default'])
        # Stock's builder copies the APN's whole bitmask: ims|ia on Verizon.
        self.assertEqual(bringup.ims_apn_types([internet, ims], 'ims'), 0x140)
        self.assertIsNone(bringup.ims_apn_types([internet], 'ims'))
        self.assertIsNone(bringup.ims_apn_types([internet, ims], 'vzwims'))

    def test_isim_names_try_the_internet_bearers_dns_first(self):
        import ipaddress, tempfile, pathlib
        bearer = bytearray(132)
        bearer[9:25] = ipaddress.IPv6Address('2001:db8::2').packed
        bearer[0x1e:0x2e] = ipaddress.IPv6Address('2001:db8::53').packed
        with tempfile.TemporaryDirectory() as tmp:
            response = pathlib.Path(tmp, 'r.bin')
            response.write_bytes(bytes(bearer))
            with patch.object(bringup, 'bearer_paths', return_value=(None, response)), \
                 patch.object(bringup, 'resolve_on_bearer', return_value=[b'a' * 16]) as on, \
                 patch.object(bringup, 'resolve_system', side_effect=AssertionError), \
                 patch('builtins.print'):
                self.assertEqual(bringup.resolve_default_network('p.example'), [b'a' * 16])
                self.assertEqual(on.call_args.args, ('p.example', '2001:db8::2', ['2001:db8::53']))
            with patch.object(bringup, 'bearer_paths', return_value=(None, response)), \
                 patch.object(bringup, 'resolve_on_bearer', return_value=[]), \
                 patch.object(bringup, 'resolve_system', return_value=[b'b' * 16]):
                self.assertEqual(bringup.resolve_default_network('p.example'), [b'b' * 16])
