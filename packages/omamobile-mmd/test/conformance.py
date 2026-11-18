# SPDX-License-Identifier: MIT
"""Real ModemManager clients against the bridge, inside the conformance
container (test/conformance builds and runs it): mmcli, GNOME Calls and
Chatty, each on a private system bus with omamobile-mmd -> omamobile-sitd ->
tools/sit-sim under it. Calls and Chatty run under Xvfb with their own
session bus. Prints TAP-style lines; exits non-zero on a failure."""
import env
from env import GLib, Gio, MM, ROOT, wait_until
import json
import os
import re
import socket
import sqlite3
import subprocess
import sys
import time

import mm_api as mm
import test_chain

OTHER = '+12025550199'          # fictional
failures = []


def check(ok, what, detail=''):
    print(('ok - ' if ok else 'not ok - ') + what + (f' ({detail})' if detail and not ok else ''), flush=True)
    if not ok:
        failures.append(what)
    return ok


def mmcli(*args):
    result = subprocess.run(['mmcli', *args], capture_output=True, text=True, timeout=30)
    return re.sub(r'\x1b\[[0-9;]*m', '', result.stdout + result.stderr)


def field(text, name):
    m = re.search(rf'\b{name}: (.+)', text)
    return m.group(1).strip() if m else ''


class Chain(test_chain.Chain):
    def runTest(self):
        pass


def start_chain(*args, bringup=True):
    chain = Chain()
    chain.start(*args, bringup=bringup)
    os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = chain.bus.address
    return chain


def session():
    """Xvfb and a session bus for the GUI clients."""
    if not os.environ.get('DISPLAY'):
        subprocess.Popen(['Xvfb', ':99', '-screen', '0', '480x1000x24'], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
        os.environ.update(DISPLAY=':99', GDK_BACKEND='x11', NO_AT_BRIDGE='1')
        time.sleep(1)
    out = subprocess.run(['dbus-daemon', '--session', '--fork', '--print-address=1'], capture_output=True,
                         text=True, check=True).stdout.strip()
    return out.splitlines()[0]


def gui(command, session_address, log):
    env_ = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=session_address, G_MESSAGES_DEBUG='all')
    return subprocess.Popen(command, env=env_, stdout=open(log, 'w'), stderr=subprocess.STDOUT)


def logged(path, needle, seconds=20):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        with open(path, errors='replace') as f:
            if needle in f.read():
                return True
        time.sleep(.2)
    return False


def mmcli_suite():
    chain = start_chain()
    wait_until(lambda: chain.client.prop(ROOT + '/Modem/0', mm.MODEM, 'State') == mm.STATE_CONNECTED, 40, 'connected')
    listing = mmcli('-L')
    check('/org/freedesktop/ModemManager1/Modem/0 [Samsung Electronics] Exynos Modem 5300' in listing, 'mmcli -L', listing)
    for selector in ('0', 'any'):
        info = mmcli('-m', selector)
        check(field(info, 'state') == 'connected' and field(info, 'registration') == 'home'
              and field(info, 'operator id') == '00101' and field(info, 'primary sim path') == ROOT + '/SIM/0',
              f'mmcli -m {selector}: connected, home, SIM', info)
    check('No calls were found' in mmcli('-m', '0', '--voice-list-calls'), 'mmcli --voice-list-calls (none)')
    check('No sms messages were found' in mmcli('-m', '0', '--messaging-list-sms'), 'mmcli --messaging-list-sms (none)')
    sim = mmcli('-i', '0')
    check(field(sim, 'emergency numbers') == '112, 911' and 'imsi' not in sim, 'mmcli -i 0: emergency numbers, no IMSI', sim)
    check(field(mmcli('-b', '0'), 'interface') == 'rmnet0', 'mmcli -b 0: the rmnet0 bearer')
    check('successfully' in mmcli('-m', '0', '-e'), 'mmcli -e (already enabled)')

    chain.control('ring')
    wait_until(lambda: 'ringing-in' in mmcli('-m', '0', '--voice-list-calls'), 10, 'ringing')
    calls = mmcli('-m', '0', '--voice-list-calls')
    check('/Call/0 incoming (ringing-in)' in calls, 'mmcli sees the incoming call', calls)
    check('successfully' in mmcli('-o', '0', '--accept'), 'mmcli -o 0 --accept')
    wait_until(lambda: field(mmcli('-o', '0'), 'state') == 'active', 10, 'active')
    check('successfully' in mmcli('-o', '0', '--send-dtmf=1'), 'mmcli --send-dtmf')
    check('successfully' in mmcli('-o', '0', '--hangup'), 'mmcli --hangup')
    wait_until(lambda: field(mmcli('-o', '0'), 'state') == 'terminated', 10, 'terminated')
    check('successfully' in mmcli('-m', '0', '--voice-delete-call=0'), 'mmcli --voice-delete-call')

    created = mmcli('-m', '0', f'--voice-create-call=number={OTHER}')
    check('/Call/1' in created, 'mmcli --voice-create-call', created)
    check('successfully' in mmcli('-o', '1', '--start'), 'mmcli -o 1 --start')
    wait_until(lambda: field(mmcli('-o', '1'), 'state') == 'active', 10, 'outgoing active')
    check('successfully' in mmcli('-o', '1', '--hangup'), 'mmcli hangs up the outgoing call')

    chain.control('wap-push')
    wait_until(lambda: 'received' in mmcli('-m', '0', '--messaging-list-sms'), 10, 'WAP push')
    push = mmcli('-s', '0')
    check('data:' in push and 'text:' not in push.split('Properties')[0], 'mmcli -s 0: the WAP push has data, no text', push)
    created = mmcli('-m', '0', f"--messaging-create-sms=number={OTHER},text='omamobile test text'")
    check('/SMS/1' in created, 'mmcli --messaging-create-sms', created)
    check('successfully' in mmcli('-s', '1', '--send'), 'mmcli -s 1 --send')
    check(field(mmcli('-s', '1'), 'state') == 'sent', 'the SMS is sent')
    check('successfully' in mmcli('-m', '0', '--messaging-delete-sms=0'), 'mmcli --messaging-delete-sms')
    chain.logs_have_no_secrets()
    chain.doCleanups()

    chain = start_chain('--no-sim', bringup=False)
    wait_until(lambda: chain.client.prop(ROOT + '/Modem/1', mm.MODEM, 'State') == mm.STATE_FAILED
               if chain.client.objects().get(ROOT + '/Modem/1') else
               chain.client.prop(ROOT + '/Modem/0', mm.MODEM, 'State') == mm.STATE_FAILED, 40, 'failed')
    info = mmcli('-m', 'any')
    check(field(info, 'state') == 'failed' and field(info, 'failed reason') == 'sim-missing'
          and field(info, 'power state') == 'low', 'mmcli -m any without a SIM: failed, sim-missing, low', info)
    check('wrong state' in mmcli('-m', 'any', '-e').lower() or 'failed' in mmcli('-m', 'any', '-e').lower(),
          'mmcli -e refused without a SIM')
    entries = chain.entries()
    check(not [e for e in entries if 'violation' in e or e.get('type') == 'at'], 'no-SIM run: read-only SIT, no AT')
    chain.doCleanups()


def calls_suite(session_address):
    chain = start_chain()
    log = os.path.join(chain.dir, 'calls.log')
    proc = gui(['gnome-calls', '--gapplication-service'], session_address, log)
    try:
        check(logged(log, 'Adding new voice-capable modem'), 'GNOME Calls adds the modem')
        check(logged(log, 'Adding origin Exynos Modem 5300'), 'GNOME Calls lists it as an origin')
        bus = Gio.DBusConnection.new_for_address_sync(
            session_address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT |
            Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)

        def calls_api(path, interface, method, args=None, out=None):
            return bus.call_sync('org.gnome.Calls', path, interface, method, args,
                                 GLib.VariantType(out) if out else None, Gio.DBusCallFlags.NONE, 10000, None)

        def calls_objects():
            return calls_api('/org/gnome/Calls', 'org.freedesktop.DBus.ObjectManager', 'GetManagedObjects').unpack()[0]
        contacts = calls_api('/org/gnome/Calls', 'org.gnome.Calls.EmergencyCalls', 'GetEmergencyContacts').unpack()[0]
        check({c[0] for c in contacts} >= {'112', '911'}, 'Calls reads the SIM\'s emergency numbers', str(contacts))

        chain.control('ring')
        objects = wait_until(calls_objects, 10, 'the call in Calls')
        path, props = next(iter(objects.items()))
        check(props['org.gnome.Calls.Call']['Inbound'], 'Calls shows the incoming call')
        calls_api(path, 'org.gnome.Calls.Call', 'Accept')
        mm_call = chain.client.prop(ROOT + '/Modem/0', mm.VOICE, 'Calls')[0]
        check(bool(wait_until(lambda: chain.client.prop(mm_call, mm.CALL, 'State') == mm.CALL_ACTIVE, 10,
                              'answered from Calls')), 'Calls answers through Call.Accept')
        calls_api(path, 'org.gnome.Calls.Call', 'SendDtmf', GLib.Variant('(s)', ('7',)))
        calls_api(path, 'org.gnome.Calls.Call', 'Hangup')
        # Calls may delete the object as soon as it ends. Check the recorded
        # transition and the modem request, rather than polling a vanished object.
        def terminated(call_path):
            return any(s[0] == call_path and s[1] == mm.CALL and s[3][1] == mm.CALL_TERMINATED
                       for s in chain.client.named('StateChanged'))

        check(bool(wait_until(lambda: terminated(mm_call), 10, 'hung up from Calls')),
              'Calls reports the incoming call ended')
        check(len([e for e in chain.entries() if e.get('type') == 'req' and e.get('id') == 0x0d03]) == 1,
              'Calls sends one incoming hangup to the modem')
        check([e.get('key') for e in chain.entries() if e.get('event') == 'dtmf'] == ['7'], 'Calls sends DTMF')

        subprocess.run(['gnome-calls', f'--dial={OTHER}'], env=dict(os.environ, DBUS_SESSION_BUS_ADDRESS=session_address),
                       capture_output=True, timeout=20)
        dialled = wait_until(lambda: [p for p in chain.client.prop(ROOT + '/Modem/0', mm.VOICE, 'Calls')
                                      if chain.client.prop(p, mm.CALL, 'Direction') == mm.DIRECTION_OUTGOING], 15,
                             'a call placed by Calls')
        check(bool(wait_until(lambda: chain.client.prop(dialled[0], mm.CALL, 'State') == mm.CALL_ACTIVE, 10,
                              'outgoing active')), 'Calls places a call (CreateCall, Start)')
        out_path = wait_until(lambda: [p for p, v in calls_objects().items()
                                       if not v['org.gnome.Calls.Call']['Inbound']], 10, 'outgoing in Calls')[0]
        calls_api(out_path, 'org.gnome.Calls.Call', 'Hangup')

        check(bool(wait_until(lambda: terminated(dialled[0]), 10, 'outgoing call ended')),
              'Calls reports the outgoing call ended')
        check(bool(wait_until(lambda: dialled[0] not in chain.client.prop(ROOT + '/Modem/0', mm.VOICE, 'Calls'),
                              10, 'outgoing call deleted')), 'Calls deletes its ended call')
        check(len([e for e in chain.entries() if e.get('type') == 'req' and e.get('id') == 0x0d03]) == 2,
              'Calls sends one outgoing hangup to the modem')
        with open(log, errors='replace') as f:
            text = f.read()
        bad = [line for line in text.splitlines() if re.search(r'CRITICAL|Segmentation|dumped core', line)]
        check(not bad, 'no criticals or crashes in Calls\' log', '; '.join(bad[:3]))
        check(proc.poll() is None, 'GNOME Calls still running')
    finally:
        if os.environ.get('CONFORMANCE_LOGS'):
            print(open(log, errors='replace').read()[-6000:], open(chain.mmd.log).read()[-3000:], sep='\n')
        proc.terminate()
        proc.wait(10)
        chain.doCleanups()


def chatty_suite(session_address):
    chain = start_chain()
    log = os.path.join(chain.dir, 'chatty.log')
    proc = gui(['chatty', '-vvv'], session_address, log)
    try:
        check(logged(log, 'Modem Manager appeared', 30), 'Chatty finds ModemManager')
        time.sleep(3)
        chain.control('sms')
        # Chatty stores the SMS and then deletes it on the modem: the bridge's
        # Messages and sitd's store both end empty.
        added = wait_until(lambda: chain.client.named('Added'), 10, 'the SMS')
        check(bool(added), 'the bridge announces the SMS')
        gone = wait_until(lambda: chain.client.prop(ROOT + '/Modem/0', mm.MESSAGING, 'Messages') == []
                          and chain.client.named('Deleted'), 20, 'Chatty to take the SMS')
        check(bool(gone), 'Chatty receives the SMS and deletes it from the modem')
        listed = test_chain.json.loads(subprocess.run(
            [sys.executable, os.path.join(test_chain.REPO, 'packages', 'omamobile-modem-sit', 'bin', 'omamobile-sit'),
             'sms', 'list', '--json'], env=chain.env, capture_output=True, text=True).stdout)
        check(listed == [], 'sitd\'s store is consumed too')
        # libpurple's directory: ~/.purple/chatty/db (chatty-application.c:394).
        history = os.path.expanduser('~/.purple/chatty/db/chatty-history.db')
        time.sleep(1)
        count = 0
        if os.path.exists(history):
            with sqlite3.connect(history) as db:
                count = db.execute('SELECT COUNT(*) FROM messages').fetchone()[0]
        check(count >= 1, 'the SMS is in Chatty\'s history', f'{count} rows')
        with open(log, errors='replace') as f:
            text = f.read()
        bad = [line for line in text.splitlines() if re.search(r'CRITICAL|Segmentation|dumped core', line)]
        check(not bad, 'no criticals or crashes in Chatty\'s log', '; '.join(bad[:3]))
        check(proc.poll() is None, 'Chatty still running')
    finally:
        proc.terminate()
        proc.wait(10)
        chain.doCleanups()


def guarded(suite, *args):
    try:
        suite(*args)
    except AssertionError as error:
        check(False, suite.__name__ + ' finished', str(error))


def main():
    guarded(mmcli_suite)
    address = session()
    guarded(calls_suite, address)
    guarded(chatty_suite, address)
    print(f'# {len(failures)} failure(s)', flush=True)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
