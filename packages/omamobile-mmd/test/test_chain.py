# SPDX-License-Identifier: MIT
"""The whole chain offline: a ModemManager client -> omamobile-mmd ->
omamobile-sitd (the real RIL, ../omamobile-modem-sit) -> tools/sit-sim. Needs
the repository (skipped from a copy of this package alone)."""
import env
from env import GLib, Client, Mmd, PrivateBus, ROOT, spin, tempdir, wait_until
import json
import os
import signal
import socket
import subprocess
import sys
import time
import unittest

import mm_api as mm

REPO = os.path.abspath(os.path.join(env.HERE, '..', '..', '..'))
SIM = os.environ.get('SIT_SIM') or os.path.join(REPO, 'tools', 'sit-sim')
SITD = os.path.join(REPO, 'packages', 'omamobile-modem-sit', 'bin', 'omamobile-sitd')
OTHER = '+12025550199'   # fictional


@unittest.skipUnless(os.path.exists(SIM) and os.path.exists(SITD), 'needs tools/sit-sim and omamobile-sitd')
class Chain(unittest.TestCase):
    def start(self, *sim_args, bringup=True):
        self.dir, cleanup = tempdir('mmd-chain-')
        self.addCleanup(cleanup)
        orig_cwd = os.getcwd()
        os.chdir(self.dir)
        self.addCleanup(os.chdir, orig_cwd)
        run = os.path.join(self.dir, 'run')
        os.mkdir(run, 0o700)
        with open(os.path.join(self.dir, 'sit.conf'), 'w') as f:
            f.write('[network]\napn = internet.example\nsim_timeout = 20\nregister_timeout = 30\n[audio]\ncard = none\n')
        self.env = dict(os.environ, OMAMOBILE_SIT_RUN='run', OMAMOBILE_SIT_STATE='state',
                        OMAMOBILE_SIT_CONFIG='sit.conf',
                        OMAMOBILE_SIT_DEVICE='unix:ipc0',
                        OMAMOBILE_SIT_ROUTER='unix:router',
                        OMAMOBILE_SIT_BOOT='none', PYTHONDONTWRITEBYTECODE='1')
        self.transcript = os.path.join(self.dir, 'transcript.jsonl')
        self.control_path = 'control'
        logs = [open(os.path.join(self.dir, n), 'w') for n in ('sim.log', 'sitd.log')]
        self.addCleanup(lambda: [f.close() for f in logs])
        self.procs = []
        self.procs.append(subprocess.Popen(
            [sys.executable, SIM, '--ipc', 'ipc0', '--router', 'router',
             '--transcript', 'transcript.jsonl', '--control', 'control', *sim_args],
            cwd=self.dir, stdout=logs[0], stderr=logs[0]))
        wait_until(lambda: os.path.exists(os.path.join(self.dir, 'router')), 5, 'sit-sim')
        self.procs.append(subprocess.Popen([sys.executable, SITD] + (['--bringup'] if bringup else []),
                                           cwd=self.dir, env=self.env, stdout=logs[1], stderr=subprocess.STDOUT))
        self.addCleanup(self.stop_all)
        wait_until(lambda: os.path.exists(os.path.join(run, 'socket')), 40, 'sitd ready')
        self.bus = PrivateBus(self.dir)
        self.addCleanup(self.bus.close)
        self.mmd = Mmd(self.bus, 'run/socket', self.dir)
        self.addCleanup(self.mmd.stop)
        self.client = Client(self.bus.connection)
        return wait_until(lambda: self.client.objects(), 10, 'the modem')

    def stop_all(self):
        for proc in reversed(self.procs):
            if proc.poll() is None:
                proc.send_signal(signal.SIGTERM)
                try:
                    proc.wait(15)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()

    def control(self, command):
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
            sock.sendto(command.encode(), self.control_path)

    def entries(self):
        with open(self.transcript) as f:
            return [json.loads(line) for line in f]

    def logs_have_no_secrets(self):
        for name in ('sitd.log', 'mmd.log'):
            with open(os.path.join(self.dir, name)) as f:
                text = f.read()
            for secret in ('2025550', 'omamobile test text', 'hello'):
                self.assertNotIn(secret, text, name)

    def test_no_sim_without_bringup_is_failed_and_read_only(self):
        # The phone's T1 run: no SIM, sitd serving without its start-up.
        objects = self.start('--no-sim', bringup=False)
        modem = list(objects.values())[0][mm.MODEM]
        path = list(objects)[0]
        if modem['State'] != mm.STATE_FAILED:
            wait_until(lambda: self.client.prop(path, mm.MODEM, 'State') == mm.STATE_FAILED, 40, 'failed')
        modem = self.client.props(path, mm.MODEM)
        self.assertEqual((modem['State'], modem['StateFailedReason'], modem['PowerState'], modem['Sim']),
                         (mm.STATE_FAILED, mm.FAILED_SIM_MISSING, mm.POWER_LOW, '/'))
        self.assertEqual(self.client.prop(path, mm.MODEM_3GPP, 'RegistrationState'), mm.REG_IDLE)
        with self.assertRaises(GLib.Error):
            self.client.call(path, mm.MODEM, 'Enable', 'b', (True,))
        entries = self.entries()
        self.assertFalse([e for e in entries if 'violation' in e or e.get('type') == 'at'])
        self.assertLessEqual({e['id'] for e in entries if e.get('type') == 'req'}, {0x0200, 0x0701, 0x0801})
        self.logs_have_no_secrets()

    def test_calls_and_messages_end_to_end(self):
        objects = self.start()
        path = list(objects)[0]
        # sitd's start-up brings the internet bearer up: CONNECTED.
        wait_until(lambda: self.client.prop(path, mm.MODEM, 'State') == mm.STATE_CONNECTED, 40, 'connected')
        self.assertEqual(self.client.prop(path, mm.MODEM_3GPP, 'OperatorCode'), '00101')

        self.control('ring')
        added = wait_until(lambda: self.client.named('CallAdded'), 10, 'the incoming call')
        call = added[0][3][0]
        self.assertEqual(self.client.props(call, mm.CALL)['State'], mm.CALL_RINGING_IN)
        self.client.call(call, mm.CALL, 'Accept')
        wait_until(lambda: self.client.prop(call, mm.CALL, 'State') == mm.CALL_ACTIVE, 10, 'active')
        self.client.call(call, mm.CALL, 'SendDtmf', 's', ('5',))
        self.client.call(call, mm.CALL, 'Hangup')
        wait_until(lambda: self.client.prop(call, mm.CALL, 'State') == mm.CALL_TERMINATED, 10, 'ended')
        self.client.call(path, mm.VOICE, 'DeleteCall', 'o', (call,))

        new = self.client.call(path, mm.VOICE, 'CreateCall', 'a{sv}', ({'number': GLib.Variant('s', OTHER)},))[0]
        self.client.call(new, mm.CALL, 'Start')
        wait_until(lambda: self.client.prop(new, mm.CALL, 'State') == mm.CALL_ACTIVE, 10, 'outgoing active')
        self.client.call(new, mm.CALL, 'Hangup')
        wait_until(lambda: self.client.prop(new, mm.CALL, 'State') == mm.CALL_TERMINATED, 10, 'outgoing ended')

        self.control('wap-push')
        messages = wait_until(lambda: self.client.prop(path, mm.MESSAGING, 'Messages'), 10, 'the WAP push')
        sms = self.client.props(messages[0], mm.SMS)
        self.assertEqual(sms['Text'], '')
        self.assertIn(b'application/vnd.wap.mms-message', bytes(sms['Data']))
        self.client.call(path, mm.MESSAGING, 'Delete', 'o', (messages[0],))
        spin(.5)
        self.assertEqual(self.client.prop(path, mm.MESSAGING, 'Messages'), [])

        out = self.client.call(path, mm.MESSAGING, 'Create', 'a{sv}', ({
            'number': GLib.Variant('s', OTHER), 'text': GLib.Variant('s', 'omamobile test text')},))[0]
        self.client.call(out, mm.SMS, 'Send', timeout=60000)
        self.assertEqual(self.client.prop(out, mm.SMS, 'State'), mm.SMS_SENT)

        entries = self.entries()
        self.assertFalse([e for e in entries if 'violation' in e])
        self.assertEqual([e['key'] for e in entries if e.get('event') == 'dtmf'], ['5'])
        self.assertEqual(len([e for e in entries if e.get('event') == 'send_sms']), 1)
        ids = [e['id'] for e in entries if e.get('type') == 'req']
        self.assertIn(0x0d02, ids)   # AIMS_ANSWER
        self.assertIn(0x0d00, ids)   # AIMS_DIAL
        self.logs_have_no_secrets()


if __name__ == '__main__':
    unittest.main()
