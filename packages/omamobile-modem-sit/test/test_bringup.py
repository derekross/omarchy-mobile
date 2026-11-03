# SPDX-License-Identifier: MIT
import env  # noqa: F401  (paths and sys.path first)
import contextlib
import io
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
             patch.object(bringup, 'initial_attach'), patch.object(bringup, 'provision_default_profile'), \
             patch.object(bringup, 'nr_mode'), patch.object(bringup, 'activate', side_effect=TimeoutError), \
             patch.object(bringup, 'start_stack') as stack, patch.object(bringup, 'register') as register:
            with self.assertRaises(TimeoutError):
                bringup.start(service, SETTINGS)
            stack.assert_not_called()
            register.assert_not_called()
            service.client.request.assert_not_called()

    def run_start(self, settings, imsi_reply):
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
             patch.object(bringup, 'initial_attach') as attach, \
             patch.object(bringup, 'provision_default_profile') as profile, \
             patch.object(bringup, 'nr_mode'), patch.object(bringup, 'activate') as activate, \
             patch.object(bringup, 'start_stack'), patch.object(bringup, 'register'), \
             patch.object(bringup.carrier_apn, 'OVERRIDES', OVERRIDES), \
             patch.object(bringup.carrier_apn, 'DATABASE', '/nonexistent.xml'), \
             contextlib.redirect_stdout(out):
            bringup.start(service, settings)
        return service, out.getvalue(), radio, attach, profile, activate

    def test_auto_apn_comes_from_the_sims_home_network(self):
        settings = paths.config('/nonexistent')
        fake = '311480' + '0' * 9
        service, log, radio, attach, profile, activate = self.run_start(
            settings, bytes([15]) + fake.encode())
        # Verizon's network registers only with the IMS APN as attach APN.
        attach.assert_called_once_with(service.client, 'ims', 'ipv4v6')
        profile.assert_called_once_with(service.client, 'vzwinternet', 'ipv4v6')
        self.assertEqual(activate.call_args_list[0].args[1], 'vzwinternet')
        self.assertEqual(activate.call_args_list[1].args[1], 'ims')
        self.assertEqual(service.apn, dict(value='vzwinternet', source='override',
                                           attach='ims', attach_source='override'))
        self.assertIn('APN chosen from', log)
        self.assertIn('attach APN chosen from', log)
        for secret in (fake, '311', '480', 'vzwinternet'):
            self.assertNotIn(secret, log)

    def test_typed_apns_win_and_the_imsi_is_never_read(self):
        service, _, _, attach, _, _ = self.run_start(SETTINGS, AssertionError('GET_IMSI sent'))
        attach.assert_called_once_with(service.client, 'internet.example', 'ipv4v6')
        self.assertEqual((service.apn['source'], service.apn['attach_source']), ('manual', 'manual'))

    def test_a_typed_apn_still_takes_the_carriers_attach_apn(self):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = 'vzwinternet'
        service, _, _, attach, profile, _ = self.run_start(settings, bytes([15]) + b'311480000000000')
        attach.assert_called_once_with(service.client, 'ims', 'ipv4v6')
        profile.assert_called_once_with(service.client, 'vzwinternet', 'ipv4v6')
        self.assertEqual((service.apn['source'], service.apn['attach_source']), ('manual', 'override'))

    def test_without_a_carrier_attach_apn_the_internet_apn_attaches(self):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = 'internet.example'
        service, _, _, attach, _, _ = self.run_start(settings, bytes([15]) + b'001010000000000')
        attach.assert_called_once_with(service.client, 'internet.example', 'ipv4v6')
        self.assertEqual(service.apn['attach_source'], 'same')

    def test_no_apn_found_registers_for_calls_and_sms_without_data(self):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = ''
        service, log, radio, attach, profile, activate = self.run_start(settings, ModemError(2, b''))
        radio.assert_any_call(True)
        attach.assert_not_called()
        profile.assert_not_called()
        # Only the IMS bearer: no internet bearer without an APN.
        self.assertEqual([c.kwargs.get('ims') for c in activate.call_args_list], [True])
        self.assertEqual(service.apn, dict(value='', source='none', attach='', attach_source='same'))
        self.assertIn('without mobile data', log)

    def test_unknown_network_code_is_no_apn(self):
        settings = paths.config('/nonexistent')
        _, _, _, attach, _, _ = self.run_start(settings, bytes([15]) + b'001010000000000')
        attach.assert_not_called()

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


class SimStageTests(unittest.TestCase):
    def run_sim_stage(self, payload):
        service = Mock()
        service.client.request.return_value = payload
        service.client.next_indication.return_value = None
        with patch.object(bringup.time, 'monotonic', side_effect=clock()), \
             patch.object(bringup, 'radio') as radio, patch.object(bringup, 'initial_attach') as attach:
            with self.assertRaises((RuntimeError, TimeoutError)) as raised:
                bringup.start(service, SETTINGS)
        radio.assert_not_called()
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
             patch.object(bringup, 'radio', side_effect=InterruptedError):
            with self.assertRaises(InterruptedError):
                bringup.start(service, SETTINGS)
