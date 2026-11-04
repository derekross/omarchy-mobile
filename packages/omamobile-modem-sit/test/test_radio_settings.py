# SPDX-License-Identifier: MIT
import env  # noqa: F401  (paths and sys.path first)
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch
import radio_settings


class NrModeTests(unittest.TestCase):
    def test_a_second_start_up_this_boot_accepts_mode_0_already_set(self):
        class Client:
            sent = []
            def request(self, ident, payload=b'', **kwargs):
                self.sent.append(ident)
                return b'\0' if ident == 0x0749 else b''
        with tempfile.TemporaryDirectory() as directory:
            saved = Path(directory)/'nr'
            saved.write_bytes(b'\3')
            with patch.object(radio_settings, 'SAVED_NR', saved):
                client = Client()
                radio_settings.nr_mode(client)
                self.assertEqual(client.sent, [0x0749])     # read only, no SET_NR_MODE
                self.assertEqual(saved.read_bytes(), b'\3')  # the original is kept

    def test_saved_original_survives_failure_and_restores_exactly(self):
        class Client:
            value = b'\3'
            fail = True
            def request(self, ident, payload=b'', **kwargs):
                if ident == 0x0749:
                    return self.value
                if self.fail:
                    raise TimeoutError('unknown result')
                self.value = payload
                return b''
        with tempfile.TemporaryDirectory() as directory:
            saved = Path(directory)/'nr'
            with patch.object(radio_settings, 'SAVED_NR', saved):
                client = Client()
                with self.assertRaises(TimeoutError):
                    radio_settings.nr_mode(client)
                self.assertEqual(saved.read_bytes(), b'\3')
                with self.assertRaises(RuntimeError):
                    radio_settings.nr_mode(client)
                client.value = b'\0'
                client.fail = False
                radio_settings.nr_mode(client, restore=True)
                self.assertEqual(client.value, b'\3')
                self.assertFalse(saved.exists())

    def test_a_restart_in_the_same_boot_keeps_the_saved_original(self):
        class Client:
            value = b'\3'
            sets = 0
            def request(self, ident, payload=b'', **kwargs):
                if ident == 0x0749:
                    return self.value
                self.sets += 1
                self.value = payload
                return b''
        with tempfile.TemporaryDirectory() as directory:
            saved = Path(directory)/'nr'
            with patch.object(radio_settings, 'SAVED_NR', saved):
                client = Client()
                radio_settings.nr_mode(client)
                radio_settings.nr_mode(client)
                self.assertEqual(client.sets, 1)
                self.assertEqual(saved.read_bytes(), b'\3')
                radio_settings.nr_mode(client, restore=True)
                self.assertEqual(client.value, b'\3')
