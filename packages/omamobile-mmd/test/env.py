# SPDX-License-Identifier: MIT
"""Test helpers: a private D-Bus daemon (never the machine's system bus), a
fake omamobile-sitd speaking its socket protocol, and omamobile-mmd run as
a subprocess on that bus. Every number here is a fictional 555-01xx one."""
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import warnings

warnings.filterwarnings('ignore', category=DeprecationWarning)
import gi  # noqa: E402

gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.abspath(os.path.join(HERE, '..', 'lib'))
BIN = os.path.abspath(os.path.join(HERE, '..', 'bin', 'omamobile-mmd'))
if LIB not in sys.path:
    sys.path.insert(0, LIB)

MM = 'org.freedesktop.ModemManager1'
ROOT = '/org/freedesktop/ModemManager1'
BUS_CONFIG = '''<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>omamobile-mmd-test</type>
  <listen>unix:path={path}</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow user="*"/>
    <allow own="*"/>
    <allow send_destination="*" eavesdrop="true"/>
    <allow receive_sender="*"/>
    <allow eavesdrop="true"/>
  </policy>
</busconfig>
'''


class PrivateBus:
    """dbus-daemon on a socket in a temporary directory."""
    def __init__(self, directory):
        self.path = os.path.join(directory, 'bus')
        config = os.path.join(directory, 'bus.conf')
        with open(config, 'w') as f:
            f.write(BUS_CONFIG.format(path=self.path))
        self.proc = subprocess.Popen(['dbus-daemon', '--nofork', '--config-file=' + config],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.address = 'unix:path=' + self.path
        deadline = time.monotonic() + 10
        try:
            while not os.path.exists(self.path):
                if time.monotonic() > deadline or self.proc.poll() is not None:
                    raise RuntimeError('private dbus-daemon did not start')
                time.sleep(.02)
            while True:
                try:
                    self.connection = Gio.DBusConnection.new_for_address_sync(
                        self.address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT |
                        Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
                    break
                except GLib.Error as error:
                    # bind() creates the socket before listen() accepts clients.
                    if not error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.CONNECTION_REFUSED):
                        raise
                    if time.monotonic() > deadline or self.proc.poll() is not None:
                        raise RuntimeError('private dbus-daemon did not start') from error
                    time.sleep(.02)
        except BaseException:
            if self.proc.poll() is None:
                self.proc.terminate()
                try:
                    self.proc.wait(5)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
                    self.proc.wait()
            raise

    def close(self):
        self.connection.close_sync(None)
        self.proc.terminate()
        self.proc.wait(5)


class FakeSitd:
    """omamobile-sitd's socket: subscribe gets the status now and after each
    push(); requests are recorded and answered by self.handlers."""
    def __init__(self, path):
        self.path = path
        self.status = blank_status()
        self.requests = []
        self.handlers = {}
        self.subscribers = []
        self.lock = threading.Lock()
        self.server = None
        self.thread = None
        self.start()

    def start(self):
        try:
            os.unlink(self.path)
        except FileNotFoundError:
            pass
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.path)
        self.server.listen(16)
        self.thread = threading.Thread(target=self.serve, args=(self.server,), daemon=True)
        self.thread.start()

    def stop(self):
        """sitd going away: the listener and every subscription close."""
        server, self.server = self.server, None
        server.close()
        os.unlink(self.path)
        with self.lock:
            for s in self.subscribers:
                s.close()
            self.subscribers = []

    def serve(self, server):
        while True:
            try:
                conn, _ = server.accept()
            except OSError:
                return
            threading.Thread(target=self.handle, args=(conn,), daemon=True).start()

    def handle(self, conn):
        data = b''
        while b'\n' not in data:
            chunk = conn.recv(65536)
            if not chunk:
                conn.close()
                return
            data += chunk
        request = json.loads(data.split(b'\n', 1)[0])
        if request.get('action') == 'subscribe':
            with self.lock:
                conn.sendall(b'{"ok": true, "result": {"subscribed": true}}\n')
                conn.sendall(self.event())
                self.subscribers.append(conn)
            return
        with self.lock:
            self.requests.append(request)
        handler = self.handlers.get(request['action'])
        try:
            if handler is None:
                raise FakeRefusal('Unsupported phone action')
            reply = dict(ok=True, result=handler(request))
        except FakeRefusal as refusal:
            reply = dict(ok=False, error=str(refusal))
        conn.sendall(json.dumps(reply).encode() + b'\n')
        conn.close()

    def event(self):
        return json.dumps(dict(event='status', status=self.status)).encode() + b'\n'

    def push(self):
        with self.lock:
            line = self.event()
            for s in list(self.subscribers):
                try:
                    s.sendall(line)
                except OSError:
                    self.subscribers.remove(s)

    def actions(self):
        with self.lock:
            return [r['action'] for r in self.requests]


class FakeRefusal(Exception):
    pass


def blank_status(sim='absent', radio='off', registration='not-registered', **modem):
    status = dict(
        modem=dict(present=True, stage='running', ready=False, state='searching', registration=registration,
                   tech='', operator='', plmn='', operator_name='', voice=False, sms=False, data=False,
                   signal=0, audio=True, radio=radio, sim=dict(state=sim),
                   emergency_numbers=['112', '911'] + (['000', '08', '110', '118', '119', '999']
                                                       if sim == 'absent' else [])),
        calls=[], sms=dict(received=[]),
        audio=dict(available=True, running=False, mute=False, speaker=False, speaker_available=False,
                   error=''))
    status['modem'].update(modem)
    return status


def registered_status(**modem):
    status = blank_status(sim='ready', radio='on', registration='home', tech='LTE', plmn='00101',
                          operator_name='Test Network', operator='Test Network', voice=True, sms=True,
                          ready=True, state='registered')
    status['modem']['sim'].update(pin_retries=3, puk_retries=10)
    status['modem'].update(modem)
    return status


class Mmd:
    """omamobile-mmd as a subprocess on the private bus."""
    def __init__(self, bus, socket_path, directory, *args):
        self.log = os.path.join(directory, 'mmd.log')
        env = dict(os.environ, DBUS_SYSTEM_BUS_ADDRESS=bus.address, PYTHONDONTWRITEBYTECODE='1')
        with open(os.path.join(directory, 'sit.conf'), 'w') as f:
            f.write('[network]\napn = internet.example\nip_type = ipv4v6\n')
        with open(self.log, 'w') as log:
            polkit = [] if '--polkit' in args else ['--no-polkit']
            self.proc = subprocess.Popen(
                [sys.executable, BIN, '--socket', socket_path, *polkit,
                 '--sit-config', os.path.join(directory, 'sit.conf'), *[a for a in args if a != '--polkit']],
                env=env, stdout=log, stderr=subprocess.STDOUT)

    def output(self):
        with open(self.log) as f:
            return f.read()

    def stop(self):
        if self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        return self.proc.returncode


def spin(seconds=0.05):
    end = time.monotonic() + seconds
    context = GLib.MainContext.default()
    while time.monotonic() < end:
        context.iteration(False)
        time.sleep(.005)


def wait_until(predicate, seconds=10, message='condition'):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        spin(.02)
        try:
            value = predicate()
        except GLib.Error:
            value = None
        if value:
            return value
    raise AssertionError('timed out waiting for ' + message)


class Client:
    """A plain D-Bus client of the bridge, recording its signals."""
    def __init__(self, connection):
        self.c = connection
        self.signals = []
        self.c.signal_subscribe(MM, None, None, None, None, Gio.DBusSignalFlags.NONE, self._signal)

    def _signal(self, connection, sender, path, interface, name, parameters):
        self.signals.append((path, interface, name, parameters.unpack()))

    def call(self, path, interface, method, signature=None, args=(), out=None, timeout=10000):
        result = self.c.call_sync(MM, path, interface, method,
                                  GLib.Variant(f'({signature})', args) if signature else None,
                                  GLib.VariantType(out) if out else None, Gio.DBusCallFlags.NONE,
                                  timeout, None)
        return result.unpack() if result is not None else None

    def call_async(self, path, interface, method, signature=None, args=()):
        """Start a call; returns a dict that gets 'result' or 'error'."""
        box = {}

        def done(connection, result):
            try:
                box['result'] = connection.call_finish(result).unpack()
            except GLib.Error as error:
                box['error'] = error
        self.c.call(MM, path, interface, method,
                    GLib.Variant(f'({signature})', args) if signature else None,
                    None, Gio.DBusCallFlags.NONE, 30000, None, done)
        return box

    def objects(self):
        return self.call(ROOT, 'org.freedesktop.DBus.ObjectManager', 'GetManagedObjects')[0]

    def props(self, path, interface):
        return self.call(path, 'org.freedesktop.DBus.Properties', 'GetAll', 's', (interface,))[0]

    def prop(self, path, interface, name):
        return self.call(path, 'org.freedesktop.DBus.Properties', 'Get', 'ss', (interface, name))[0]

    def named(self, name):
        return [s for s in self.signals if s[2] == name]


def tempdir(prefix='mmd-test-'):
    directory = tempfile.mkdtemp(prefix=prefix)
    return directory, lambda: shutil.rmtree(directory, ignore_errors=True)
