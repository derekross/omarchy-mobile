# SPDX-License-Identifier: MIT
"""Private D-Bus startup must tolerate a socket that is not listening yet."""
import os
from types import SimpleNamespace
import unittest
from unittest import mock

import env
from env import Gio, GLib


class PrivateBusStartup(unittest.TestCase):
    def setUp(self):
        self.directory, cleanup = env.tempdir()
        self.addCleanup(cleanup)
        # bind() has created the path, but listen() has not necessarily run.
        open(os.path.join(self.directory, 'bus'), 'w').close()
        self.process = mock.Mock()
        self.process.poll.return_value = None
        self.connection = mock.Mock()
        self.connect = mock.Mock()
        self.gio = SimpleNamespace(DBusConnectionFlags=Gio.DBusConnectionFlags,
                                   DBusConnection=SimpleNamespace(new_for_address_sync=self.connect),
                                   io_error_quark=Gio.io_error_quark, IOErrorEnum=Gio.IOErrorEnum)
        for patcher in (mock.patch.object(env, 'Gio', self.gio),
                        mock.patch.object(env.subprocess, 'Popen', return_value=self.process),
                        mock.patch.object(env.time, 'sleep')):
            patcher.start()
            self.addCleanup(patcher.stop)

    @staticmethod
    def error(code):
        return GLib.Error.new_literal(Gio.io_error_quark(), 'test error', code)

    def test_refused_connection_retries_until_bus_is_listening(self):
        self.connect.side_effect = [self.error(Gio.IOErrorEnum.CONNECTION_REFUSED), self.connection]
        bus = env.PrivateBus(self.directory)
        self.assertIs(bus.connection, self.connection)
        self.assertEqual(self.connect.call_count, 2)
        bus.close()
        self.process.terminate.assert_called_once()
        self.process.wait.assert_called_once_with(5)

    def test_other_connection_error_stops_and_cleans_up(self):
        self.connect.side_effect = self.error(Gio.IOErrorEnum.PERMISSION_DENIED)
        with self.assertRaises(GLib.Error):
            env.PrivateBus(self.directory)
        self.connect.assert_called_once()
        self.process.terminate.assert_called_once()
        self.process.wait.assert_called_once_with(5)

    def test_refusal_timeout_stops_and_cleans_up(self):
        self.connect.side_effect = self.error(Gio.IOErrorEnum.CONNECTION_REFUSED)
        with mock.patch.object(env.time, 'monotonic', side_effect=[0, 11]):
            with self.assertRaisesRegex(RuntimeError, 'did not start'):
                env.PrivateBus(self.directory)
        self.process.terminate.assert_called_once()
        self.process.wait.assert_called_once_with(5)

    def test_daemon_exit_stops_retrying(self):
        self.connect.side_effect = self.error(Gio.IOErrorEnum.CONNECTION_REFUSED)
        self.process.poll.return_value = 1
        with self.assertRaisesRegex(RuntimeError, 'did not start'):
            env.PrivateBus(self.directory)
        self.connect.assert_called_once()
        self.process.terminate.assert_not_called()


if __name__ == '__main__':
    unittest.main()
