# SPDX-License-Identifier: MIT
import env  # noqa: F401 (private paths before imports)
import contextlib
import io
import struct
import unittest
from unittest.mock import patch
import service


class ProbeTests(unittest.TestCase):
    def execute(self, overrides=None, present=False):
        sim = bytes([1, 0, 1, 2, 5] + [0] * 61) if present else bytes(3)
        replies = {0x0200: sim, 0x0801: struct.pack('<I', 1), 0x0701: bytes(4),
                   0x0749: bytes([3]), 0x0711: bytes([1]), 0x0108: bytes([0])}
        replies.update(overrides or {})
        calls, closed = [], []

        class Client:
            def request(self, ident, **kwargs):
                calls.append((ident, kwargs))
                value = replies[ident]
                if isinstance(value, BaseException):
                    raise value
                return value

            def close(self):
                closed.append(True)

        code = 0
        with patch.object(service, 'Sit', Client), contextlib.redirect_stdout(io.StringIO()):
            try:
                service.probe()
            except SystemExit as error:
                code = error.code
        self.assertEqual(closed, [True])
        return code, calls

    def test_complete_six_gets_and_first_usim_timeout(self):
        code, calls = self.execute()
        self.assertEqual(code, 0)
        self.assertEqual([item[0] for item in calls], [0x0200, 0x0801, 0x0701, 0x0749, 0x0711, 0x0108])
        self.assertEqual(calls[0][1], {'timeout': 20})

    def test_malformed_sim_stops_and_closes(self):
        for value in [b'', b'\0', bytes([0, 0, 1]), bytes([0, 0, 9])]:
            code, calls = self.execute({0x0200: value})
            self.assertEqual(code, 1)
            self.assertEqual(len(calls), 1)

    def test_malformed_radio_and_packet_registration_fail(self):
        for ident in [0x0801, 0x0701]:
            self.assertEqual(self.execute({ident: b'\1'})[0], 1)

    def test_empty_replies_fail(self):
        for ident in [0x0749, 0x0711, 0x0108]:
            self.assertEqual(self.execute({ident: b''})[0], 1)

    def test_unavailable_status_fails_but_closes(self):
        for ident in [0x0801, 0x0701, 0x0749, 0x0711, 0x0108]:
            self.assertEqual(self.execute({ident: TimeoutError('synthetic')})[0], 1)

    def test_absent_sim_smsc_error_11_is_expected(self):
        self.assertEqual(self.execute({0x0108: service.ModemError(11, b'')})[0], 0)

    def test_present_sim_smsc_error_11_fails(self):
        self.assertEqual(self.execute({0x0108: service.ModemError(11, b'')}, present=True)[0], 1)

    def test_other_absent_sim_smsc_error_fails(self):
        self.assertEqual(self.execute({0x0108: service.ModemError(2, b'')})[0], 1)


if __name__ == '__main__':
    unittest.main()
