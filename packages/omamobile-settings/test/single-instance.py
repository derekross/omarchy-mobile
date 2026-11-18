#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the application entrypoint with a neutral constructor fixture."""
import re
from pathlib import Path
import subprocess
import sys
import time

binary = sys.argv[1]
expected_version = (Path(__file__).resolve().parents[1] / 'version').read_text().strip()
version = subprocess.run([binary, '--version'], capture_output=True, text=True, timeout=5)
assert version.returncode == 0
assert version.stdout.strip().endswith(' ' + expected_version), version.stdout
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
    second = subprocess.run(
        [binary, '--page', 'about'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5,
    )
    assert second.returncode == 0
    assert application.poll() is None
    print('PASS private-bus entrypoint Open, route rejection and repeat launch')
finally:
    if application.poll() is None:
        application.terminate()
        try:
            application.wait(timeout=3)
        except subprocess.TimeoutExpired:
            application.kill()
            application.wait(timeout=3)
