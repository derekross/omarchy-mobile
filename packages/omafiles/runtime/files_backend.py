#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""One async-frontend JSON request on stdin; one JSON result on stdout.

Progress JSON-lines go to stderr (at most10/sec). SIGTERM cancels this owned
worker; no external application is killed. The CLI never runs as root.
"""
import json, os, signal, sys, threading, time
from files_core import dispatch, FileError, convert_error

def main():
    if os.geteuid() == 0:
        print(json.dumps({'ok': False, 'error': {'code': 'root_forbidden', 'message': 'Run Files as a normal user.', 'details': {}}}))
        return 1
    cancellation = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: cancellation.set())
    signal.signal(signal.SIGINT, lambda *_: cancellation.set())
    try:
        line = sys.stdin.buffer.readline(1024 * 1024 + 1)
        if len(line) > 1024 * 1024:
            raise FileError('invalid_request', 'The request is too large.')
        try:
            request = json.loads(line)
        except (ValueError, UnicodeError):
            raise FileError('invalid_request', 'Invalid JSON request.')
        if not isinstance(request, dict):
            raise FileError('invalid_request', 'Invalid request object.')
        action = request.get('action')
        payload = request.get('payload', {})
        if not isinstance(action, str):
            raise FileError('invalid_request', 'A file action is missing.')
    except Exception as error:
        e = convert_error(error)
        print(json.dumps({'ok': False, 'error': e.json()}, ensure_ascii=True))
        return 1
    last = [0.0]

    def progress(data):
        now = time.monotonic()
        if now - last[0] >= 0.1:
            sys.stderr.write(json.dumps({'type': 'progress', **data}, ensure_ascii=True) + '\n')
            sys.stderr.flush()
            last[0] = now
    result = {}

    def work():
        try:
            result.update(ok=True, result=dispatch(action, payload, cancellation, progress))
        except Exception as error:
            result.update(ok=False, error=convert_error(error).json())
    thread = threading.Thread(target=work, name='mobile-files-operation')
    thread.start()
    while thread.is_alive():
        thread.join(0.05)
    print(json.dumps(result, ensure_ascii=True))
    return 0 if result.get('ok') else 1
if __name__ == '__main__':
    raise SystemExit(main())
