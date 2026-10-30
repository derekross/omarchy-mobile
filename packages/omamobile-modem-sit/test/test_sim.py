# SPDX-License-Identifier: MIT
"""The whole RIL against tools/sit-sim: the start-up sequence to IMS, then
SMS both ways and a call through the socket and the CLI. Needs SIT_SIM (the
simulator's path); skipped without it."""
import env  # noqa: F401  (paths and sys.path first)
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest

import test_ims
import test_ipv6

HERE = Path(__file__).resolve().parent
BIN = HERE.parent / 'bin'
SIM = os.environ.get('SIT_SIM')
KEEP = os.environ.get('KEEP')


@unittest.skipUnless(SIM and Path(SIM).exists(), 'no simulator (set SIT_SIM)')
class SimulatorTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix='sit-sim-'))
        (self.dir / 'run').mkdir(mode=0o700)
        self.env = dict(os.environ,
                        OMAMOBILE_SIT_RUN=str(self.dir / 'run'),
                        OMAMOBILE_SIT_STATE=str(self.dir / 'state'),
                        OMAMOBILE_SIT_CONFIG=str(self.dir / 'modem-sit.conf'),
                        OMAMOBILE_SIT_DEVICE='unix:' + str(self.dir / 'ipc0'),
                        OMAMOBILE_SIT_ROUTER='unix:' + str(self.dir / 'router'),
                        OMAMOBILE_SIT_BOOT='none', PYTHONDONTWRITEBYTECODE='1')
        (self.dir / 'modem-sit.conf').write_text(
            '[network]\napn = internet.example\nsim_timeout = 20\nregister_timeout = 30\n'
            '[audio]\ncard = none\n')
        self.transcript = self.dir / 'transcript.jsonl'
        self.procs = []

    def tearDown(self):
        for proc in reversed(self.procs):
            if proc.poll() is None:
                proc.send_signal(signal.SIGTERM)
                try:
                    proc.wait(10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
        for f in self.files:
            f.close()
        if KEEP:
            print('kept', self.dir, file=sys.stderr)
        else:
            subprocess.run(['rm', '-rf', str(self.dir)])

    files = []

    def start(self, *sim_args, daemon=True, bringup=True):
        sim_log = open(self.dir / 'sim.log', 'w')
        daemon_log = open(self.dir / 'daemon.log', 'w')
        self.files = [sim_log, daemon_log]
        self.procs.append(subprocess.Popen(
            [sys.executable, SIM, '--ipc', str(self.dir / 'ipc0'), '--router', str(self.dir / 'router'),
             '--transcript', str(self.transcript), '--control', str(self.dir / 'control'), *sim_args],
            stdout=sim_log, stderr=sim_log))
        deadline = time.monotonic() + 5
        while not (self.dir / 'router').exists() and time.monotonic() < deadline:
            time.sleep(.05)
        if not daemon:
            return
        self.daemon = subprocess.Popen([sys.executable, str(BIN / 'omamobile-sitd')] + (['--bringup'] if bringup else []),
                                       env=self.env, stdout=daemon_log, stderr=subprocess.STDOUT)
        self.procs.append(self.daemon)

    def wait_ready(self, seconds=40):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if (self.dir / 'run' / 'socket').exists():
                return
            if self.daemon.poll() is not None:
                self.fail('daemon exited: ' + (self.dir / 'daemon.log').read_text())
            time.sleep(.1)
        self.fail('daemon not ready: ' + (self.dir / 'daemon.log').read_text())

    def cli(self, *args, check=True):
        result = subprocess.run([sys.executable, str(BIN / 'omamobile-sit'), *args], env=self.env,
                                capture_output=True, text=True, timeout=60)
        if check and result.returncode:
            self.fail(f'omamobile-sit {args}: {result.stdout}{result.stderr}')
        return result.stdout

    def transcript_entries(self):
        return [json.loads(line) for line in self.transcript.read_text().splitlines()]

    def test_bringup_sms_and_call(self):
        self.start('--incoming-sms')
        self.wait_ready()
        status = json.loads(self.cli('status', '--json'))
        modem = status['modem']
        self.assertEqual((modem['stage'], modem['voice'], modem['sms'], modem['data']),
                         ('running', True, True, True))
        self.assertIn('SIM: ready', self.cli('status'))
        # The simulator's IND_SIGNAL_STRENGTH (stock V2 layout) as MM's quality.
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and not json.loads(self.cli('status', '--json'))['modem']['signal']:
            time.sleep(.2)
        modem = json.loads(self.cli('status', '--json'))['modem']
        self.assertEqual((modem['signal'], modem['signal_detail']),
                         (60, dict(layout='v2', lte=dict(rssi=-73, rsrp=-95, rsrq=-10, snr=12))))
        # The incoming SMS arrives just after the IMS registration.
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and 'hello' not in self.cli('sms', 'list'):
            time.sleep(.2)
        listed = json.loads(self.cli('sms', 'list', '--json'))
        self.assertEqual([m['text'] for m in listed], ['hello'])
        self.assertEqual(self.cli('sms', 'send', '+12025550199', 'omamobile test').strip(), 'sent')
        self.cli('sms', 'delete', listed[0]['id'])
        self.assertEqual(json.loads(self.cli('sms', 'list', '--json')), [])
        call = self.cli('dial', '+12025550199').strip()
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            calls = json.loads(self.cli('status', '--json'))['calls']
            if calls and calls[0]['state'] == 'active':
                break
            time.sleep(.1)
        self.assertEqual(calls[0]['id'], call)
        self.cli('hangup')
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            calls = json.loads(self.cli('status', '--json'))['calls']
            if calls[0]['state'] == 'terminated':
                break
            time.sleep(.1)
        self.assertEqual(calls[0]['state'], 'terminated')
        public = (self.dir / 'run' / 'state.json').read_text()
        self.assertNotIn('2025550', public)

        entries = self.transcript_entries()
        self.assertFalse([e for e in entries if 'violation' in e])
        ids = [e['id'] for e in entries if e.get('type') == 'req']
        # The verified order: SIM, attach APN and profile, registration, NR
        # off, internet bearer, IMS stack, IMS bearer, ADD_PDN.
        order = [0x0200, 0x0603, 0x0613, 0x0701, 0x0748, 0x0600, 0x0d39, 0x0600, 0x0d08]
        positions = []
        start = 0
        for ident in order:
            start = ids.index(ident, start)
            positions.append(start)
        self.assertEqual(positions, sorted(positions))
        at = [e['cmd'] for e in entries if e.get('type') == 'at']
        self.assertEqual(at, ['AT+CFUN=0', 'AT+CFUN=1'])
        setups = [e for e in entries if e.get('event') == 'setup_data_call']
        self.assertEqual([(s['cid'], s['apn'], s['ip']) for s in setups],
                         [(1, 'internet.example', 3), (2, 'ims', 2)])
        # The IMS values went out exactly as the proven ones (test_ims.py).
        menus = [e['sha256'] for e in entries if e.get('event') == 'hidden_menu']
        self.assertEqual(menus, [test_ims.GOLDEN_HIDDEN_MENU])
        self.assertIn('IMS values: defaults', (self.dir / 'daemon.log').read_text())
        log = (self.dir / 'daemon.log').read_text()
        for secret in ('2025550123', '2025550199', 'hello', 'omamobile test'):
            self.assertNotIn(secret, log)
        # The SIM's AID and label and the IMS identity (an IMSI-based SIP URI
        # and a number) reach neither the log nor any status, public or not.
        published = log + public + self.cli('status', '--json') + self.cli('status')
        for secret in ('001010000000017', '3gppnetwork', '2025550100', 'SIMSIM', 'a0000000871002ff',
                       '89012600'):
            self.assertNotIn(secret, published)
        self.assertIn('"pin_retries": 3', self.cli('status', '--json'))

        self.assertEqual(self.cli('radio', 'off').strip(), 'off')
        at = [e['cmd'] for e in self.transcript_entries() if e.get('type') == 'at']
        self.assertEqual(at[-1], 'AT+CFUN=0')

        self.daemon.send_signal(signal.SIGTERM)
        self.assertEqual(self.daemon.wait(15), 0)
        self.assertFalse((self.dir / 'run' / 'socket').exists())

    def control(self, command):
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
            sock.sendto(command.encode(), str(self.dir / 'control'))

    def subscribe(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(10)
        sock.connect(str(self.dir / 'run' / 'socket'))
        sock.sendall(b'{"action": "subscribe"}\n')
        self.addCleanup(sock.close)
        reader = sock.makefile('r')
        self.assertEqual(json.loads(reader.readline()), dict(ok=True, result=dict(subscribed=True)))
        return reader

    def next_status(self, reader, predicate, seconds=10):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            status = json.loads(reader.readline())['status']
            if predicate(status):
                return status
        self.fail('no matching status event')

    def test_no_sim_without_bringup_stays_read_only(self):
        # The phone's T1 run: CP ONLINE, no SIM, the RIL serving without
        # its start-up. Only read-only polls reach the modem.
        self.start('--no-sim', bringup=False)
        self.wait_ready()
        reader = self.subscribe()
        status = self.next_status(reader, lambda s: s['modem']['sim']['state'] != 'unknown')
        modem = status['modem']
        self.assertEqual((modem['sim'], modem['radio'], modem['registration']),
                         (dict(state='absent'), 'off', 'not-registered'))
        self.assertIn('999', modem['emergency_numbers'])
        self.assertEqual((status['calls'], status['sms']), ([], dict(received=[])))
        entries = self.transcript_entries()
        self.assertFalse([e for e in entries if 'violation' in e or e.get('type') == 'at'])
        self.assertLessEqual({e['id'] for e in entries if e.get('type') == 'req'}, {0x0200, 0x0701, 0x0801})

    def test_subscription_follows_calls_and_messages(self):
        self.start()
        self.wait_ready()
        reader = self.subscribe()
        self.control('ring')
        status = self.next_status(reader, lambda s: any(c['state'] == 'ringing-in' for c in s['calls']))
        call = status['calls'][0]
        self.assertEqual((call['direction'], call['number']), ('incoming', '+12025550123'))
        self.cli('answer')
        self.next_status(reader, lambda s: s['calls'][0]['state'] == 'active')
        self.cli('dtmf', '1#')
        self.control('remote-hangup')
        self.next_status(reader, lambda s: s['calls'][0]['state'] == 'terminated')
        self.control('wap-push')
        status = self.next_status(reader, lambda s: s['sms']['received'])
        listed = json.loads(self.cli('sms', 'list', '--json'))
        self.assertEqual([m['id'] for m in listed], status['sms']['received'])
        self.assertEqual(listed[0]['text'], '')
        self.assertIn(b'application/vnd.wap.mms-message', bytes.fromhex(listed[0]['data']))
        dtmf = [e['key'] for e in self.transcript_entries() if e.get('event') == 'dtmf']
        self.assertEqual(dtmf, ['1', '#'])
        self.assertFalse([e for e in self.transcript_entries() if 'violation' in e])

    def test_probe_is_read_only(self):
        self.start(daemon=False)
        probe = subprocess.run([sys.executable, str(BIN / 'omamobile-sitd'), '--probe'], env=self.env,
                               capture_output=True, text=True, timeout=30)
        self.assertEqual(probe.returncode, 0, probe.stdout + probe.stderr)
        self.assertIn('SIM card state 1 applications [(2, 5)]', probe.stdout)
        entries = self.transcript_entries()
        self.assertFalse([e for e in entries if 'violation' in e or e.get('type') == 'at'])
        self.assertEqual(sorted({e['id'] for e in entries if e.get('type') == 'req'}),
                         [0x0108, 0x0200, 0x0701, 0x0711, 0x0749, 0x0801])

    def test_rejected_bearer_ends_startup_without_ims(self):
        self.start('--reject-setup', '36')
        self.assertNotEqual(self.daemon.wait(40), 0)
        ids = [e['id'] for e in self.transcript_entries() if e.get('type') == 'req']
        self.assertIn(0x0600, ids)
        self.assertNotIn(0x0d39, ids)
        self.assertNotIn(0x0d08, ids)
        self.assertFalse([e for e in self.transcript_entries() if 'violation' in e])

    def test_ims_failure_keeps_data_without_sms_or_calls(self):
        (self.dir / 'modem-sit.conf').write_text(
            '[network]\napn = internet.example\nsim_timeout = 20\nregister_timeout = 30\nims_timeout = 2\n'
            '[audio]\ncard = none\n')
        self.start('--no-ims-registration')
        self.wait_ready()
        modem = json.loads(self.cli('status', '--json'))['modem']
        self.assertEqual((modem['stage'], modem['ims'], modem['data'], modem['voice'], modem['sms']),
                         ('running', 'failed', True, False, False))
        self.assertIn('IMS failed', self.cli('status'))
        refused = subprocess.run([sys.executable, str(BIN / 'omamobile-sit'), 'sms', 'send', '+12025550199', 'x'],
                                 env=self.env, capture_output=True, text=True, timeout=60)
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn('not registered', refused.stderr)
        ids = [e['id'] for e in self.transcript_entries() if e.get('type') == 'req']
        self.assertEqual(ids.count(0x0d08), 1)       # ADD_PDN_INFO never repeated
        self.assertNotIn(0x0d1b, ids)                # no SMS went out
        self.assertIn('serving data only', (self.dir / 'daemon.log').read_text())

    def test_ims_required_ends_startup_when_ims_fails(self):
        (self.dir / 'modem-sit.conf').write_text(
            '[network]\napn = internet.example\nsim_timeout = 20\nregister_timeout = 30\nims_timeout = 2\n'
            'ims_required = yes\n[audio]\ncard = none\n')
        self.start('--no-ims-registration')
        self.assertNotEqual(self.daemon.wait(40), 0)

    def test_ipv6_only_bearer(self):
        # An IPv6-only internet bearer (PDP type 2) no longer ends anything:
        # start-up completes, and omamobile-sit-data configures IPv6 and a
        # CLAT (in a private network namespace, when the machine allows one).
        self.start('--bearer-ip', 'ipv6')
        self.wait_ready()
        self.assertTrue(json.loads(self.cli('status', '--json'))['modem']['data'])
        log = (self.dir / 'daemon.log').read_text()
        self.assertIn('PDP type 2', log)
        from data_network import configuration
        bearer = configuration((self.dir / 'run' / 'data-call-response.bin').read_bytes())
        self.assertEqual((bearer.ipv4, bearer.ipv6), ('', '2001:db8:64::2'))
        if not test_ipv6.NETNS:
            self.skipTest('no unprivileged network namespace for omamobile-sit-data')
        for name, text in (('tayga', test_ipv6.STUB_TAYGA), ('ip6tables', test_ipv6.STUB_IP6TABLES)):
            (self.dir / name).write_text(text)
            (self.dir / name).chmod(0o755)
        (self.dir / 'resolv.conf').write_text('nameserver 192.0.2.1\n')
        with open(self.dir / 'modem-sit.conf', 'a') as conf:
            conf.write('[data]\nclat_prefix = 64:ff9b::/96\n')
        env = dict(self.env, STUB_LOG=str(self.dir / 'stub.log'), OMAMOBILE_SIT_TAYGA=str(self.dir / 'tayga'),
                   OMAMOBILE_SIT_IP6TABLES=str(self.dir / 'ip6tables'),
                   OMAMOBILE_SIT_RESOLVER=str(self.dir / 'resolv.conf'))
        data_log = open(self.dir / 'data.log', 'w')
        self.files.append(data_log)
        data = subprocess.Popen(['unshare', '-rn', 'sh', '-c', 'ip link add rmnet0 type dummy && exec "$0" "$1"',
                                 sys.executable, str(BIN / 'omamobile-sit-data')],
                                env=env, stdout=data_log, stderr=subprocess.STDOUT)
        self.procs.append(data)
        record = self.dir / 'run' / 'bearer-ip.json'
        deadline = time.monotonic() + 20
        while not record.exists() and time.monotonic() < deadline and data.poll() is None:
            time.sleep(.1)
        self.assertTrue(record.exists(), (self.dir / 'data.log').read_text())
        modem = json.loads(self.cli('status', '--json'))['modem']
        self.assertEqual(modem['bearer']['ipv6']['address'], '2001:db8:64::2')
        self.assertEqual(modem['bearer']['ipv4'], dict(address='192.0.0.1', prefix=29, dns=[], clat=True))
        self.assertEqual((self.dir / 'resolv.conf').read_text().split('\n')[1:-1], ['nameserver 2001:db8:64::53',
                                                                                    'nameserver 2001:db8:64::54'])
        public = (self.dir / 'run' / 'state.json').read_text()
        data.send_signal(signal.SIGTERM)
        self.assertEqual(data.wait(20), 0, (self.dir / 'data.log').read_text())
        self.assertFalse(record.exists())
        self.assertEqual((self.dir / 'resolv.conf').read_text(), 'nameserver 192.0.2.1\n')
        for text in (public, (self.dir / 'data.log').read_text(), (self.dir / 'daemon.log').read_text()):
            self.assertNotIn('2001:db8:64', text)
            self.assertNotIn('192.0.0.1', text)

    def test_trace_is_scrubbed(self):
        # [trace] record = yes over start-up, SMS both ways and a call: the
        # record holds IDs, lengths, codes and allowed shapes, no values.
        trace = self.dir / 'trace'
        with open(self.dir / 'modem-sit.conf', 'a') as conf:
            conf.write(f'[trace]\nrecord = yes\ndirectory = {trace}\n')
        self.start('--incoming-sms')
        self.wait_ready()
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and 'hello' not in self.cli('sms', 'list'):
            time.sleep(.2)
        self.assertEqual(self.cli('sms', 'send', '+12025550199', 'omamobile test').strip(), 'sent')
        self.cli('dial', '+12025550199')
        time.sleep(.5)
        self.cli('hangup')
        time.sleep(1.5)
        self.daemon.send_signal(signal.SIGTERM)
        self.daemon.wait(15)
        files = list(trace.iterdir())
        self.assertEqual(len(files), 1)
        self.assertEqual((trace.stat().st_mode & 0o777, files[0].stat().st_mode & 0o777), (0o700, 0o600))
        text = files[0].read_text()
        records = [json.loads(line) for line in text.splitlines()]
        import sit_trace
        allowed = {'t', 'dir', 'kind', 'id', 'name', 'len', 'error', 'ms', 'codes', 'shape', 'note'}
        for r in records:
            self.assertLessEqual(set(r), allowed, r)
            if 'shape' in r:
                self.assertIn(int(r['id'], 16), sit_trace.SHAPED)
                self.assertRegex(r['shape'], r'^[0x]*$')
        ids = {(r['dir'], r['kind'], r['id']) for r in records}
        for wanted in (('out', 'req', '0d1b'), ('out', 'req', '0d00'), ('in', 'ind', '0d1e'),
                       ('in', 'ind', '0906'), ('in', 'resp', '0600')):
            self.assertIn(wanted, ids)
        setup = [r for r in records if r['id'] == '0600' and r['kind'] == 'resp']
        self.assertEqual(setup[0]['codes'], dict(status=0, cid=1, active=2, pdp=3))
        for secret in ('2025550', 'hello', 'omamobile test', 'internet.example', '"ims"', '192.0.2', '2001:db8',
                       '00101', 'Test', 'SIMSIM', 'a0000000871002ff', '3gppnetwork', 'c0000202'):
            self.assertNotIn(secret, text)
        self.assertNotRegex(text, r'[0-9a-f]{8}')    # no hex dump of anything

    def pin(self, digits):
        return subprocess.run([sys.executable, str(BIN / 'omamobile-sit'), 'sim-pin'], input=digits + '\n',
                              env=self.env, capture_output=True, text=True, timeout=60)

    def pin_tries(self):
        return [e for e in self.transcript_entries() if e.get('event') == 'verify_pin']

    def test_sim_pin_entry(self):
        # sitd without its start-up (as T1) and a PIN-locked SIM: one try per
        # request, the result reported, the PIN never logged.
        self.start('--sim-pin', bringup=False)
        self.wait_ready()
        sim = json.loads(self.cli('status', '--json'))['modem']['sim']
        deadline = time.monotonic() + 5
        while sim['state'] == 'unknown' and time.monotonic() < deadline:
            time.sleep(.2)
            sim = json.loads(self.cli('status', '--json'))['modem']['sim']
        self.assertEqual((sim['state'], sim['pin_retries']), ('pin', 3))
        wrong = self.pin('1357')
        self.assertNotEqual(wrong.returncode, 0)
        self.assertIn('Wrong SIM PIN; 2 tries left', wrong.stderr)
        right = self.pin('2468')
        self.assertEqual(right.returncode, 0, right.stderr)
        self.assertEqual(right.stdout.strip(), 'accepted (2 tries left)')
        self.assertEqual([e['outcome'] for e in self.pin_tries()], ['rejected', 'accepted'])
        again = self.pin('2468')
        self.assertIn('not asking for its PIN', again.stderr)
        self.assertEqual(len(self.pin_tries()), 2)
        log = (self.dir / 'daemon.log').read_text()
        self.assertIn('SIM PIN accepted', log)
        for digits in ('1357', '2468'):
            self.assertNotIn(digits, log + self.transcript.read_text())
        self.assertFalse([e for e in self.transcript_entries() if 'violation' in e])

    def test_sim_pin_last_try_is_refused(self):
        self.start('--sim-pin', bringup=False)
        self.wait_ready()
        for left in (2, 1):
            self.assertIn(f'{left} tries left', self.pin('1357').stderr)
        last = self.pin('2468')
        self.assertNotEqual(last.returncode, 0)
        self.assertIn('One PIN try left', last.stderr)
        self.assertEqual(len(self.pin_tries()), 2)      # the refused one never reached the modem
        bad = self.pin('12')
        self.assertNotEqual(bad.returncode, 0)
        self.assertEqual(len(self.pin_tries()), 2)

    def test_no_apn_never_switches_the_radio(self):
        (self.dir / 'modem-sit.conf').write_text('[audio]\ncard = none\n')
        self.start()
        self.assertNotEqual(self.daemon.wait(30), 0)
        self.assertFalse([e for e in self.transcript_entries() if e.get('type') == 'at'])


if __name__ == '__main__':
    unittest.main()
