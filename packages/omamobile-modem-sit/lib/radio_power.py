# SPDX-License-Identifier: MIT
"""Explicit board selection for the modem owner's radio transport."""
from pathlib import Path
import struct

COMPATIBLE = Path('/sys/firmware/devicetree/base/compatible')
SIT_RADIO_BEFORE_SIM = 'sit-radio-before-sim'
# Compatibility for existing explicit local configurations; never auto-selected.
LEGACY_KOMODO = 'komodo-s5400'
BOARD_COMPATIBLES = {
    (b'google,zumapro-komodo', b'google,zumapro'),
}


def profile(settings):
    selected = settings['network'].get('startup_profile', 'default')
    if selected == 'default':
        return selected
    if selected not in (SIT_RADIO_BEFORE_SIM, LEGACY_KOMODO):
        raise ValueError('Unknown modem startup profile')
    with COMPATIBLE.open('rb') as source:
        compatible = source.read(4097)
    if len(compatible) > 4096 or not compatible.endswith(b'\0'):
        raise ValueError('Unexpected device-tree compatible property')
    if tuple(compatible.split(b'\0')[:-1]) not in BOARD_COMPATIBLES:
        raise ValueError('SIT-before-SIM startup requires an explicitly supported compatible tuple')
    return SIT_RADIO_BEFORE_SIM


def native_radio(client, enabled):
    # Fixed S5400 candidate payload: operation 1 is OFF, 2 is ON, flags zero.
    # The caller owns IPC0. An uncertain reply propagates without retry.
    if type(enabled) is not bool:
        raise ValueError('Radio state must be boolean')
    client.request(0x0800, struct.pack('<IBB', 2 if enabled else 1, 0, 0), timeout=30)


def set_radio(client, settings, enabled, legacy_radio):
    if profile(settings) == SIT_RADIO_BEFORE_SIM:
        native_radio(client, enabled)
    else:
        legacy_radio(enabled)


def configure_single_modem(client):
    """Fixed proposed payload; its Komodo meaning and persistence remain unresolved."""
    client.request(0x093f, b'\x00', timeout=30)
