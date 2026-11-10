# SPDX-License-Identifier: MIT
"""Bounded native chat bridge. Credentials and transcripts stay with the CLI."""
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

MAX_LINE = 131072
MAX_OUTPUT = 2097152
MAX_REPLY_TEXT = 120000
DEADLINE = 180
ID = re.compile(r'^[A-Za-z0-9_-]{1,80}$')
THREAD = re.compile(r'^[A-Za-z0-9_-]{1,100}$')


def selected_provider():
    try:
        with (Path.home()/'.config/omarchy/defaults/agent').open('rb') as stream:
            raw = stream.readline(130)
        if len(raw) > 128: return ''
        value = raw.decode('utf-8').strip()
        return value if ID.fullmatch(value) else ''
    except (OSError, UnicodeError):
        return ''


def qualified(path):
    if not path.is_file() or not os.access(path, os.X_OK): return False
    try:
        if path.resolve().name == 'mise': return False
        with path.open('rb') as stream: prefix = stream.read(8192)
        return not any(word in prefix for word in (b'omarchy-agent-account-exec', b'mise install', b'mise use'))
    except OSError:
        return False


def installed_binary(provider):
    # Never execute Omarchy's account-exec or mise dispatchers: either may install.
    for folder in os.get_exec_path():
        if any(part in ('command-wrappers', 'shims') for part in Path(folder).parts):
            continue
        path = Path(folder)/provider
        if qualified(path):
            return str(path)
    data = Path(os.environ.get('MISE_DATA_DIR', str(Path(os.environ.get('XDG_DATA_HOME', str(Path.home()/'.local/share')))/'mise')))
    for path in (data/'installs'/provider/'latest/bin'/provider, data/'installs'/provider/'latest'/provider):
        if qualified(path):
            return str(path)
    return ''


def account_environment(provider):
    env = dict(os.environ)
    key = {'codex': 'CODEX_HOME', 'claude': 'CLAUDE_CONFIG_DIR'}.get(provider)
    value = env.get(key, '') if key else ''
    if key and not value:
        helper = shutil.which('omarchy-agent-account-home')
        if helper:
            result = subprocess.run([helper, provider], stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL, timeout=3, check=True)
            if len(result.stdout) > 4096:
                raise ValueError('account')
            value = result.stdout.decode().strip()
            if value:
                env[key] = value
    if key:
        env['OMARCHY_AGENT_'+provider.upper()+'_HOME'] = value
    return env, (provider, value)


def classify_error(value):
    # Examine only bounded structured failure fields; never forward their text.
    pieces = []
    for part in (value, value.get('error', {})):
        if isinstance(part, dict):
            for key in ('code', 'message', 'type'):
                text = part.get(key)
                if isinstance(text, str): pieces.append(text[:2048].lower())
    text = ' '.join(pieces)
    if any(word in text for word in ('unauthorized', 'authentication', 'not logged in', 'login required', '401')): return 'auth_required'
    if any(word in text for word in ('sandbox', 'bwrap', 'landlock')): return 'sandbox_failed'
    if any(word in text for word in ('approval required', 'approval request', 'requires approval', 'approval_required')): return 'approval_required'
    return 'agent_failed'


def private_state(path):
    if not path.is_absolute(): raise ValueError('state')
    descriptor = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            if part in ('.', '..'): raise ValueError('state')
            try: os.mkdir(part, 0o700, dir_fd=descriptor)
            except FileExistsError: pass
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor); descriptor = child
        if os.fstat(descriptor).st_uid != os.getuid(): raise ValueError('state')
        os.fchmod(descriptor, 0o700)
    finally:
        os.close(descriptor)


class Codex:
    @staticmethod
    def command(binary, thread):
        args = [binary, 'exec', '--sandbox', 'workspace-write']
        if thread:
            args += ['resume', thread]
        return args + ['--json', '--skip-git-repo-check', '-']

    @staticmethod
    def event(value):
        kind = value.get('type')
        if kind == 'thread.started':
            thread = value.get('thread_id', '')
            return ('thread', thread) if isinstance(thread, str) and THREAD.fullmatch(thread) else (None, None)
        item = value.get('item', {})
        if kind == 'item.completed' and isinstance(item, dict) and item.get('type') == 'agent_message':
            text = item.get('text')
            return ('reply', text) if isinstance(text, str) else (None, None)
        if kind in ('turn.failed', 'error'):
            return ('failure', classify_error(value))
        return (None, None)


ADAPTERS = {'codex': Codex}


class Server:
    def __init__(self, output=sys.stdout):
        self.output = output
        self.lock = threading.RLock()
        self.active = None
        self.thread = None
        self.binding = None
        self.seen = set()
        self.reset_pending = False
        state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state')))/'omamobile/agent-chat'
        private_state(state)
        self.workspace = Path(tempfile.mkdtemp(prefix='session-', dir=state))

    def emit(self, kind, request=None, **fields):
        with self.lock:
            value = dict(type=kind, **fields)
            if request is not None:
                value['id'] = request
            self.output.write(json.dumps(value, ensure_ascii=True, separators=(',', ':'))+'\n')
            self.output.flush()

    def capabilities(self):
        provider = selected_provider()
        installed = bool(provider and installed_binary(provider))
        native = provider in ADAPTERS and installed
        reason = '' if native else ('select_agent' if not provider else 'install_agent' if not installed else 'terminal_required')
        self.emit('capabilities', provider=provider, nativeChat=native, installed=installed, reason=reason)

    def cancel(self, request=None):
        with self.lock:
            active = self.active
            if active and (request is None or request == active['id']):
                active['cancel'].set()

    def handle(self, value):
        if not isinstance(value, dict):
            self.emit('error', code='invalid_request'); return
        op = value.get('op')
        if op == 'capabilities':
            self.capabilities(); return
        if op == 'cancel':
            self.cancel(value.get('id')); return
        if op == 'reset':
            self.cancel()
            with self.lock:
                self.thread = None; self.binding = None
                if self.active: self.reset_pending = True
                else: self.emit('reset')
            return
        request = value.get('id')
        if op != 'send' or not isinstance(request, str) or not ID.fullmatch(request):
            self.emit('error', code='invalid_request'); return
        prompt = value.get('prompt')
        if not isinstance(prompt, str) or not prompt.strip() or len(prompt.encode()) > 32768:
            self.emit('error', request, code='invalid_prompt'); return
        provider = selected_provider()
        if value.get('provider') != provider or provider not in ADAPTERS:
            self.emit('error', request, code='provider_changed' if value.get('provider') != provider else 'terminal_required'); return
        binary = installed_binary(provider)
        if not binary:
            self.emit('error', request, code='install_agent'); return
        with self.lock:
            if self.active:
                self.emit('error', request, code='busy'); return
            if request in self.seen or len(self.seen) >= 4096:
                self.emit('error', request, code='request_id_used'); return
            self.seen.add(request)
            active = dict(id=request, cancel=threading.Event())
            self.active = active
            worker = threading.Thread(target=self.run, args=(active, provider, binary, prompt))
            active['worker'] = worker
            worker.start()

    def run(self, active, provider, binary, prompt):
        request = active['id']; process = None; code = None
        try:
            env, binding = account_environment(provider)
            with self.lock:
                if self.binding is not None and self.binding != binding:
                    self.thread = None
                    self.emit('reset', reason='account_changed')
                    self.binding = None
                elif self.binding != binding:
                    self.thread = None
                thread = self.thread
            if active['cancel'].is_set():
                return
            process = subprocess.Popen(ADAPTERS[provider].command(binary, thread),
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                cwd=str(self.workspace), env=env, start_new_session=True)
            self.emit('started', request)
            outbound = prompt.encode()
            os.set_blocking(process.stdin.fileno(), False)
            pending = b''; total = 0; started = time.monotonic(); new_thread = thread; replies = []
            with selectors.DefaultSelector() as poll:
                poll.register(process.stdout, selectors.EVENT_READ)
                while True:
                    if active['cancel'].is_set(): break
                    if time.monotonic()-started > DEADLINE:
                        code = 'timeout'; break
                    if outbound:
                        try:
                            sent = os.write(process.stdin.fileno(), outbound)
                            outbound = outbound[sent:]
                            if not outbound: process.stdin.close()
                        except BlockingIOError: pass
                    if not poll.select(.1): continue
                    chunk = os.read(process.stdout.fileno(), 16384)
                    if not chunk: break
                    total += len(chunk); pending += chunk
                    if total > MAX_OUTPUT or len(pending) > MAX_LINE:
                        code = 'output_limit'; break
                    while b'\n' in pending:
                        line, pending = pending.split(b'\n', 1)
                        try: event = json.loads(line)
                        except (ValueError, UnicodeError): continue
                        if not isinstance(event, dict): continue
                        kind, text = ADAPTERS[provider].event(event)
                        if kind == 'thread':
                            if thread and text != thread: code = 'session_mismatch'
                            else: new_thread = text
                        elif kind == 'failure': code = text
                        elif kind == 'reply' and not active['cancel'].is_set():
                            replies.append(text)
            if not active['cancel'].is_set() and not code:
                try: status = process.wait(timeout=2)
                except subprocess.TimeoutExpired: status = -1
                if status or not replies: code = 'agent_failed'
                elif not new_thread:
                    code = 'session_unavailable'
                else:
                    with self.lock:
                        if not active['cancel'].is_set():
                            reply = '\n\n'.join(replies)
                            wire = json.dumps(dict(type='reply', id=request, text=reply), ensure_ascii=True, separators=(',', ':')).encode()
                            if len(reply) > MAX_REPLY_TEXT or len(wire)+1 > MAX_LINE:
                                code = 'output_limit'
                            else:
                                self.thread = new_thread; self.binding = binding
                                self.emit('reply', request, text=reply)
        except (OSError, ValueError, subprocess.SubprocessError):
            code = 'agent_unavailable'
        finally:
            if process:
                if process.poll() is None:
                    try: os.killpg(process.pid, signal.SIGTERM)
                    except ProcessLookupError: pass
                    try: process.wait(timeout=1)
                    except subprocess.TimeoutExpired:
                        if process.poll() is None:
                            try: os.killpg(process.pid, signal.SIGKILL)
                            except ProcessLookupError: pass
                        process.wait()
                process.stdout.close()
                if not process.stdin.closed: process.stdin.close()
            with self.lock:
                cancelled = active['cancel'].is_set()
                self.active = None
                if cancelled: self.emit('cancelled', request)
                elif code: self.emit('error', request, code=code)
                else: self.emit('done', request)
                if self.reset_pending:
                    self.reset_pending = False
                    self.emit('reset')

    def close(self):
        self.cancel()
        active = self.active
        if active:
            active['worker'].join(timeout=8)
            if active['worker'].is_alive():
                # Do not remove a workspace while a child could still use it.
                return
        try: self.workspace.rmdir()
        except OSError: pass  # Preserve client-created task artifacts; never recurse.


def main():
    if os.geteuid() == 0: return 1
    server = Server()
    def shutdown(signum, frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, shutdown)
    try:
        server.capabilities()
        while True:
            line = sys.stdin.buffer.readline(MAX_LINE+1)
            if not line: break
            if len(line) > MAX_LINE:
                server.emit('error', code='input_limit'); break
            try: value = json.loads(line)
            except (ValueError, UnicodeError):
                server.emit('error', code='invalid_request'); continue
            server.handle(value)
    finally:
        server.close()
    return 0
