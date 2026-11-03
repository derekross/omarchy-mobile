# SPDX-License-Identifier: MIT
"""The hand-set carrier manifest: validation, the 0x4600 layout, the one
reply to the modem's request, and the IMS stack start waiting for 0x4601.
The ID below is made up (40 hex characters), not a real manifest."""
import env  # noqa: F401  (paths and sys.path first)
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch

import bringup
import carrier_manifest
import paths
import service as app_service
import sit

FAKE = '0123456789abcdef0123456789abcdef01234567'


def indication(ident, payload=b''):
    return struct.pack('<BBHH', 2, 0, ident, 8 + len(payload)) + bytes(2) + payload


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)
        (self.dir / 'manifests').mkdir()
        (self.dir / 'manifests' / FAKE).write_bytes(b'manifest')

    def tearDown(self):
        self.temp.cleanup()

    def test_validation(self):
        self.assertEqual(carrier_manifest.manifest_id(FAKE.upper(), self.dir), bytes.fromhex(FAKE))
        for bad in ('', 'xyz', FAKE[:-1], FAKE + '0', 'g' * 40, '../' + FAKE[3:]):
            with self.assertRaises(ValueError):
                carrier_manifest.manifest_id(bad, self.dir)
        with self.assertRaises(ValueError):          # well formed, but not in the chroot
            carrier_manifest.manifest_id('f' * 40, self.dir)

    def test_request_layout(self):
        payload = carrier_manifest.request_payload(bytes.fromhex(FAKE))
        message = bytes(12) + payload
        self.assertEqual(len(message), 532)
        self.assertEqual(struct.unpack_from('<I', message, 0x0c)[0], 30)
        self.assertEqual(message[0x10:0x10 + 31], b'/vendor/firmware/carrierconfig\0')
        self.assertEqual(struct.unpack_from('<I', message, 0x110)[0], 20)
        self.assertEqual(message[0x114:0x128], bytes.fromhex(FAKE))
        self.assertEqual(message[0x128:], bytes(532 - 0x128))

    def test_status(self):
        self.assertEqual(carrier_manifest.status(indication(0x4601, struct.pack('<II', 1, 0))), (1, 0))
        with self.assertRaises(ValueError):
            carrier_manifest.status(indication(0x4601, b'\1'))

    def test_transport_allows_only_the_flagged_reply(self):
        with self.assertRaises(ValueError):
            sit.check(0x4600)
        with self.assertRaises(ValueError):
            sit.check(0x4600, sms=True, calls=True)
        sit.check(0x4600, manifest=True)
        with self.assertRaises(ValueError):          # the flag opens 0x4600 only
            sit.check(0x0931, manifest=True)

    def service(self, setting):
        settings = paths.config('/nonexistent')
        settings['network']['carrier_manifest'] = setting
        run = self.dir / 'run'
        run.mkdir(exist_ok=True)
        client = Mock()
        client.next_indication.return_value = None
        with patch.object(paths, 'RUN', run):
            svc = app_service.Service(client, app_service.database(run / 'db'), settings)
        svc.publish = Mock()
        return svc, client

    def test_empty_setting_never_sends(self):
        svc, client = self.service('')
        with patch('builtins.print') as out:
            svc.event(indication(0x4602, b'identity fields, never read' + bytes(200)))
        client.request.assert_not_called()
        self.assertIn('not answered', ' '.join(str(a) for a in out.call_args.args))

    def test_set_and_present_answers_once(self):
        svc, client = self.service(FAKE)
        with patch.object(carrier_manifest, 'HOST_DIRECTORY', self.dir), patch('builtins.print'):
            svc.event(indication(0x4602, bytes(200)))
            svc.event(indication(0x4602, bytes(200)))
        self.assertEqual(client.request.call_count, 1)
        args, kwargs = client.request.call_args
        self.assertEqual(args[0], 0x4600)
        self.assertEqual(args[1], carrier_manifest.request_payload(bytes.fromhex(FAKE)))
        self.assertTrue(kwargs['manifest_reply'])
        svc.event(indication(0x4601, struct.pack('<II', 1, 0)))
        self.assertEqual(svc.carrier_status, (1, 0))

    def test_missing_manifest_is_skipped(self):
        svc, client = self.service('f' * 40)
        with patch.object(carrier_manifest, 'HOST_DIRECTORY', self.dir), patch('builtins.print') as out:
            svc.event(indication(0x4602, bytes(200)))
        client.request.assert_not_called()
        self.assertIn('names no manifest', ' '.join(str(a) for a in out.call_args.args))


class StackStartTests(unittest.TestCase):
    def run_start(self, setting, wait_result):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = 'internet.example'
        settings['network']['carrier_manifest'] = setting
        service = Mock()
        service.carrier_status = (1, 0)
        service.manifest_sent = True
        service.registration.return_value = {}
        order = []
        def wait(svc, predicate, seconds, stopped):
            if seconds == settings['network'].getint('carrier_manifest_timeout'):
                order.append('wait-carrier')
                if wait_result is TimeoutError:
                    raise TimeoutError('deadline')
        with patch.object(bringup, 'wait_for', wait), patch.object(bringup, 'radio'), \
             patch.object(bringup, 'initial_attach'), patch.object(bringup, 'provision_profiles'), \
             patch.object(bringup, 'radio_state', return_value=0), \
             patch.object(bringup, 'nr_mode'), patch.object(bringup, 'data_snapshot'), \
             patch.object(bringup, 'activate'), patch.object(bringup, 'find_attach_bearer', return_value=None), \
             patch.object(bringup, 'start_stack', side_effect=lambda c: order.append('stack')), \
             patch.object(bringup, 'register', side_effect=RuntimeError('stop here')), \
             patch('builtins.print') as out:
            bringup.start(service, settings)
        lines = [' '.join(str(a) for a in c.args) for c in out.call_args_list]
        return order, lines

    def test_stack_start_waits_for_the_carrier_status(self):
        order, lines = self.run_start(FAKE, None)
        # Once before radio on (stock's order), once before the stack start.
        self.assertEqual(order[:3], ['wait-carrier', 'wait-carrier', 'stack'])
        self.assertTrue(any(l.startswith('Radio on after carrier config') for l in lines))
        self.assertTrue(any(l.startswith('IMS stack start released (after carrier config') for l in lines))

    def test_timeout_releases_it_too(self):
        order, lines = self.run_start(FAKE, TimeoutError)
        self.assertEqual(order[:3], ['wait-carrier', 'wait-carrier', 'stack'])
        self.assertTrue(any(l.startswith('Radio on without carrier config status') for l in lines))
        self.assertTrue(any(l.startswith('IMS stack start released (timeout') for l in lines))

    def test_no_setting_no_wait(self):
        order, lines = self.run_start('', None)
        self.assertEqual(order, ['stack'])
        self.assertFalse(any('IMS stack start released' in l for l in lines))
