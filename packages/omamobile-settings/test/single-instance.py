#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the application entrypoint with a neutral constructor fixture."""
import json
import re
import subprocess
import sys
import time

binary = sys.argv[1]
application = subprocess.Popen(
    [binary, '--page', 'about'],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)


def call(method, *arguments):
    return subprocess.run(
        ['dbus-send', '--session', '--print-reply=literal',
         '--dest=org.omamobile.Settings', '/Settings',
         'org.omamobile.Settings.' + method, *arguments],
        capture_output=True, text=True, timeout=2,
    )


try:
    deadline = time.monotonic() + 5
    while True:
        reply = call('Open', 'string:about')
        if reply.returncode == 0:
            break
        if application.poll() is not None or time.monotonic() >= deadline:
            raise AssertionError('The private application service did not become ready.')
        time.sleep(0.05)
    assert re.search(r'\bboolean\s+true\b', reply.stdout)
    unknown = call('Open', 'string:nonexistent')
    assert unknown.returncode == 0
    assert re.search(r'\bboolean\s+false\b', unknown.stdout)
    palette = call('SurfacePalette')
    assert palette.returncode == 0
    value = palette.stdout.strip()
    start, end = value.find('{'), value.rfind('}')
    assert start >= 0 and end > start
    decoded = json.loads(value[start:end + 1])
    assert decoded['version'] == 1 and isinstance(decoded['known'], bool)
    if decoded['known']:
        assert re.fullmatch(r'#[0-9a-fA-F]{6}', decoded['top'])
        assert decoded['bottom'] == decoded['top']
    second = subprocess.run(
        [binary, '--page', 'about'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5,
    )
    assert second.returncode == 0
    assert application.poll() is None
    print('PASS private-bus entrypoint Open, route rejection, palette schema and repeat launch')
finally:
    if application.poll() is None:
        application.terminate()
        try:
            application.wait(timeout=3)
        except subprocess.TimeoutExpired:
            application.kill()
            application.wait(timeout=3)
