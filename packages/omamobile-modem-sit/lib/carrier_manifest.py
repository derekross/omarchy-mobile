# SPDX-License-Identifier: MIT
"""The modem's carrier profile, named by hand ([network] carrier_manifest).

After the SIM loads, the CP sends OEM_IND_CARRIER_CONFIG_SIM_INFO (0x4602)
and waits for the AP to name a carrier manifest. Stock's libsitril answers
it with OEM_SET_CARRIER_CONFIG_MANIFEST (0x4600), only ever as that answer
(OnOemCpCarrierConfigSimInfoInd queues DoOemSetCpCarrierConfig with the
indication); the CP then reads the manifest and its configuration sequences
from the carrier-config directory through rfsd and reports the outcome in
OEM_IND_CARRIER_CONFIG_STATUS (0x4601). Stock's IMS service holds the AIMS
stack start until that status has come.

Here the manifest ID is set by hand in the configuration, and 0x4602 is
only a trigger: its payload is never read. Empty setting: nothing is sent,
and 0x4600 stays on the transport's do-not-send list.

0x4600 (stock ProtocolMiscBuilder::BuildSetCpCarrierConfig, 532 bytes with
the header): 0x0c u32 length and 0x10 the directory string (stock passes
CarrierConfigManager's "/vendor/firmware/carrierconfig"), 0x110 u32 length
and 0x114 the encoded manifest (CarrierManifest::getEncodedManifest: the
manifest's hex ID decoded to bytes). 0x4601 (stock
ProtocolMiscCarrierConfigStatusIndAdapter): 0x08 u32 status, 0x0c u32 cause.
"""
import os
from pathlib import Path
import re
import struct

DIRECTORY = '/vendor/firmware/carrierconfig'
# The modem chroot's image on the host (omamobile-vendor-chroot's IMAGE).
HOST_DIRECTORY = Path(os.environ.get('OMAMOBILE_SIT_CARRIERCONFIG',
                                     '/usr/lib/omamobile-vendor/modem/root' + DIRECTORY))


def manifest_id(value, directory=None):
    """The 20-byte manifest ID for a configured value, or raise ValueError
    with the reason: exactly 40 hex characters, and manifests/<id> present
    in the chroot's carrier-config directory (where the CP will read it)."""
    value = (value or '').strip().lower()
    if not re.fullmatch(r'[0-9a-f]{40}', value):
        raise ValueError('carrier_manifest is not a 40-character hex manifest ID')
    if not ((directory or HOST_DIRECTORY) / 'manifests' / value).is_file():
        raise ValueError('carrier_manifest names no manifest in the modem chroot '
                         '(re-run tools/extract-vendor-chroot -p modem)')
    return bytes.fromhex(value)


def request_payload(ident):
    """The 0x4600 payload (the 532-byte request without its 12-byte header)."""
    if len(ident) > 256:
        raise ValueError('manifest ID too long')
    payload = bytearray(0x214 - 12)
    path = DIRECTORY.encode('ascii')
    struct.pack_into('<I', payload, 0x0c - 12, len(path))
    payload[0x10 - 12:0x10 - 12 + len(path)] = path
    struct.pack_into('<I', payload, 0x110 - 12, len(ident))
    payload[0x114 - 12:0x114 - 12 + len(ident)] = ident
    return bytes(payload)


def status(packet):
    """(status, cause) of an OEM_IND_CARRIER_CONFIG_STATUS."""
    if len(packet) < 0x10:
        raise ValueError('short carrier-config status')
    return struct.unpack_from('<II', packet, 8)
