# SPDX-License-Identifier: MIT
"""Explicit board selection for the modem owner's radio transport."""
from pathlib import Path
import struct

COMPATIBLE = Path('/sys/firmware/devicetree/base/compatible')
KOMODO = 'komodo-s5400'


def profile(settings):
    selected = settings['network'].get('startup_profile', 'default')
    if selected == 'default':
        return selected
    if selected != KOMODO:
        raise ValueError('Unknown modem startup profile')
    with COMPATIBLE.open('rb') as source:
        compatible = source.read(4097)
    if len(compatible) > 4096 or not compatible.endswith(b'\0'):
        raise ValueError('Unexpected device-tree compatible property')
    if compatible.split(b'\0') != [b'google,zumapro-komodo', b'google,zumapro', b'']:
        raise ValueError('komodo-s5400 requires the verified Komodo/Zumapro compatible tuple')
    return selected


def native_radio(client, enabled):
    # Own S5400 builder: operation 1 is OFF, operation 2 is ON, flags zero.
    # The caller owns IPC0. An uncertain reply propagates without retry.
    if type(enabled) is not bool:
        raise ValueError('Radio state must be boolean')
    client.request(0x0800, struct.pack('<IBB', 2 if enabled else 1, 0, 0), timeout=30)


def set_radio(client, settings, enabled, legacy_radio):
    if profile(settings) == KOMODO:
        native_radio(client, enabled)
    else:
        legacy_radio(enabled)


def configure_single_modem(client):
    """Only the qualified single-modem configuration; no arbitrary payload."""
    client.request(0x093f, b'\x00', timeout=30)
