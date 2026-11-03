# SPDX-License-Identifier: MIT
"""Fixed AT commands on CPIF's router channel (/dev/umts_router).

Only radio power goes this way (and its read-only query): the start-up
sequence that registered on this phone switched the radio with AT+CFUN, and
SIT radio power and AT CFUN were seen to disagree. No arbitrary command can be sent from here.
"""
import os
import re
import select
import time

from paths import ROUTER, open_channel

COMMANDS = {'radio-off': 'AT+CFUN=0', 'radio-on': 'AT+CFUN=1', 'radio-state': 'AT+CFUN?'}


def exchange(fd, command, timeout):
    data = (command + '\r').encode('ascii')
    if os.write(fd, data) != len(data):
        raise RuntimeError('short command write')
    deadline = time.monotonic() + timeout
    response = bytearray()
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], max(0, deadline - time.monotonic()))
        if not ready:
            break
        try:
            data = os.read(fd, 4096)
        except BlockingIOError:
            continue
        if not data:
            break
        response.extend(data)
        if len(response) > 16384:
            raise RuntimeError('response exceeds limit')
        if re.search(rb'(?:^|[\r\n])(OK|ERROR|\+CME ERROR[^\r\n]*)[\r\n]', response):
            break
    return response.decode('ascii', errors='replace')


def radio(enabled):
    fd = open_channel(ROUTER)
    try:
        response = exchange(fd, COMMANDS['radio-on' if enabled else 'radio-off'], 25)
        if not re.search(r'(?:^|[\r\n])OK(?:[\r\n]|$)', response):
            raise RuntimeError('Radio command was not accepted')
    finally:
        os.close(fd)


def radio_state():
    """AT+CFUN?: the functionality level (0 minimum, 1 full, 4 flight), or
    None when the answer can't be read. Read-only."""
    fd = open_channel(ROUTER)
    try:
        response = exchange(fd, COMMANDS['radio-state'], 10)
    finally:
        os.close(fd)
    found = re.search(r'\+CFUN:\s*(\d+)', response)
    if not found or not re.search(r'(?:^|[\r\n])OK(?:[\r\n]|$)', response):
        return None
    return int(found.group(1))
