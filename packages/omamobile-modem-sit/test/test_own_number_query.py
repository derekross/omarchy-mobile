# SPDX-License-Identifier: MIT
"""Private, on-demand SIM-number access; no hardware or personal data."""
import env  # noqa: F401
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import Mock, patch

import paths
import service

NUMBER = '+12025550123'
RESULT = dict(status='available', source='sim', numbers=[NUMBER])


class PrivateQueryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run_path = patch.object(paths, 'RUN', self.root)
        self.run_path.start()
        self.addCleanup(self.run_path.stop)
        self.db = service.database(self.root / 'db')
        self.addCleanup(self.db.close)
        self.client = Mock()
        self.client.next_indication.return_value = None
        self.app = service.Service(self.client, self.db)

    def socket_request(self, clients):
        mine, theirs = socket.socketpair()
        self.addCleanup(theirs.close)
        theirs.settimeout(1)
        theirs.sendall(b'{"action":"own-number"}\n')
        service.serve_one(self.app, mine, clients)
        return json.loads(theirs.recv(65536))

    def test_authorized_query_is_private_and_not_cached_or_logged(self):
        out, err = io.StringIO(), io.StringIO()
        with patch('msisdn.read_numbers', return_value=RESULT) as reader, \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            response = self.socket_request({os.getuid()})
            self.app.publish()
            private = self.app.status()
            public = self.app.status(public=True)
            self.app.broadcast()
        reader.assert_called_once_with(self.client)
        self.assertEqual(response, dict(ok=True, result=RESULT))
        for text in (out.getvalue(), err.getvalue(), json.dumps(private),
                     json.dumps(public), (self.root / 'state.json').read_text()):
            self.assertNotIn(NUMBER, text)
        self.assertNotIn('own_numbers', private['modem'])

    def test_unauthorized_request_never_reads_the_sim(self):
        with patch('msisdn.read_numbers') as reader:
            result = self.socket_request(set())
        reader.assert_not_called()
        self.client.request.assert_not_called()
        self.assertFalse(result['ok'])

    def test_query_during_a_call_is_refused_before_sim_access(self):
        self.app.new_call('+12025550124', 'incoming', 'ringing-in', 7)
        with patch('msisdn.read_numbers') as reader:
            with self.assertRaisesRegex(RuntimeError, 'current call'):
                self.app.dispatch(dict(action='own-number'))
        reader.assert_not_called()

    def test_query_cannot_supply_raw_commands_or_file_ids(self):
        for field in ('command', 'file_id', 'aid', 'pin', 'payload'):
            with patch('msisdn.read_numbers') as reader:
                with self.assertRaises(ValueError):
                    self.app.dispatch(dict(action='own-number', **{field: 'anything'}))
            reader.assert_not_called()

    def test_status_never_triggers_a_number_query(self):
        with patch('msisdn.read_numbers') as reader:
            self.app.dispatch(dict(action='status'))
            self.app.publish()
        reader.assert_not_called()
        self.client.request.assert_not_called()


class CliTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).resolve().parents[1] / 'bin/omamobile-sit'
        loader = importlib.machinery.SourceFileLoader('own_number_cli', str(path))
        cls.cli = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
        loader.exec_module(cls.cli)

    def test_cli_json_is_an_explicit_private_request(self):
        out = io.StringIO()
        with patch.object(self.cli, 'request', return_value=RESULT) as request, \
                contextlib.redirect_stdout(out):
            self.assertEqual(self.cli.main(['own-number', '--json']), 0)
        request.assert_called_once_with('own-number', timeout=20)
        self.assertEqual(json.loads(out.getvalue()), RESULT)

    def test_cli_has_no_public_status_fallback(self):
        with patch.object(self.cli, 'request', side_effect=PermissionError('denied')), \
                patch.object(self.cli, 'public_state') as public, \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(self.cli.main(['own-number']), 1)
        public.assert_not_called()

    def test_empty_is_distinct_from_unavailable(self):
        for status, expected in [('empty', 'no stored'), ('unavailable', 'unavailable')]:
            out = io.StringIO()
            with patch.object(self.cli, 'request', return_value=dict(status=status, numbers=[])), \
                    contextlib.redirect_stdout(out):
                self.assertEqual(self.cli.main(['own-number']), 0)
            self.assertIn(expected, out.getvalue())


if __name__ == '__main__':
    unittest.main()
