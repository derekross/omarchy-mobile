#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise GPIO ownership and low-state cleanup on both Pixel board layouts."""
from pathlib import Path
import runpy
import struct
from unittest.mock import patch

m = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'tools/bt-uart-test'))
g = m['cmd_hci'].__globals__
for bank in ('gpp16', 'gpp14'):
    for fail in ('none', 'gpio', 'tty', 'exchange', 'cleanup'):
        events = []
        class Lines:
            def __init__(self, fd, offsets, consumer):
                self.fd, self.offsets = fd, offsets
                if fail == 'gpio' and fd == 14:
                    raise OSError('request failure')
                events.append(('request', fd, offsets))
            def set(self, offset, value):
                assert offset in self.offsets
                events.append(('set', self.fd, offset, value))
                if fail == 'cleanup' and offset == 2 and value == 0:
                    raise OSError('low failure')
            def close(self):
                events.append(('release', self.fd))
        def tty(*args, **kwargs):
            if fail == 'tty':
                raise OSError('tty failure')
            return 30
        def exchange(fd, reg, wake, delay):
            assert fd == 30 and reg.fd == 16
            assert wake.offset == 3
            reg.set(2, 1)
            wake.set(1)
            if fail == 'exchange':
                raise OSError('HCI failure')
            return 0
        with patch.dict(g, {'Lines': Lines, 'find_chip': lambda name: (int(name[3:]), name, 8),
                            'open_tty': tty, 'hci_exchange': exchange, 'say': lambda s: None}), \
             patch.object(g['os'], 'close', lambda fd: events.append(('close', fd))):
            try:
                result = m['cmd_hci']('test', 115200, 200, bank + ':3')
                assert result == 0
            except OSError:
                assert fail != 'none'
        for e in events:
            if e[0] == 'request':
                fd, offsets = e[1:]
                assert ('release', fd) in events and ('close', fd) in events
                for offset in offsets:
                    low = ('set', fd, offset, 0)
                    if fail not in ('tty', 'gpio'):
                        assert low in events
                        assert events.index(low) < events.index(('release', fd))
        if fail == 'gpio' and bank == 'gpp14':
            assert ('close', 14) in events
for fail_command in (None, 0x0c03, 0x1001, 0xfc79):
    events = []
    class Power:
        def __init__(self, name): self.name = name
        def set(self, *args): events.append((self.name, *args))
    commands = []
    def command(fd, opcode):
        commands.append(opcode)
        if opcode == fail_command: return None
        return {0x0c03: b'\0', 0x1001: b'\0' + struct.pack('<BHBHH', 11, 1, 11, 15, 2),
                0xfc79: b'\0\x69'}[opcode]
    with patch.dict(g, {'hci_cmd': command, 'read_exact': lambda *a: b'', 'say': lambda s: None}), \
         patch.object(g['termios'], 'tcflush', lambda *a: None), \
         patch.object(g['time'], 'sleep', lambda *a: None):
        result = m['hci_exchange'](30, Power('reg'), Power('wake'), 200)
    assert result == (1 if fail_command else 0)
    if fail_command: assert commands[-1] == fail_command
print('PASS: Bluetooth GPIO routing, low-state cleanup and stop on each failed HCI command')

for baud, delay in ((123, 200), (115200, -1)):
    with patch.dict(g, {'find_chip': lambda *a: (_ for _ in ()).throw(AssertionError("hardware acquired"))}):
        try:
            m['cmd_hci']('test', baud, delay, 'gpp14:3')
        except SystemExit:
            pass
        else:
            raise AssertionError("invalid arguments accepted")
with patch.object(g['os'], 'open', return_value=30), patch.object(g['os'], 'close') as close, patch.object(g['termios'], 'tcgetattr', side_effect=OSError("setup")):
    try:
        m['open_tty']('test', 115200, True)
    except OSError:
        pass
    close.assert_called_once_with(30)
