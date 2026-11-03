# SPDX-License-Identifier: MIT
import env  # noqa: F401  (paths and sys.path first)
import unittest
from unittest.mock import Mock, patch
import bringup
import paths

SETTINGS = paths.config('/nonexistent')
SETTINGS['network']['apn'] = 'internet.example'


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
             patch.object(bringup, 'data_snapshot'), \
             patch.object(bringup, 'start_stack') as stack, patch.object(bringup, 'register') as register:
            with self.assertRaises(TimeoutError):
                bringup.start(service, SETTINGS)
            stack.assert_not_called()
            register.assert_not_called()
            service.client.request.assert_not_called()

    def test_no_apn_stops_before_the_radio(self):
        settings = paths.config('/nonexistent')
        with patch.object(bringup, 'radio') as radio, self.assertRaises(RuntimeError):
            bringup.start(Mock(), settings)
        radio.assert_not_called()

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
