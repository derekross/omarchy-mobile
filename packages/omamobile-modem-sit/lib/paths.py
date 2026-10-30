# SPDX-License-Identifier: MIT
"""Where the SIT RIL finds its devices and keeps its files.

Every path can be overridden from the environment, which is how the offline
tests run the whole stack against tools/sit-sim (OMAMOBILE_SIT_DEVICE=unix:...,
OMAMOBILE_SIT_BOOT=none).
"""
import configparser
import os
from pathlib import Path

# RAM only: bearer ownership records, the data call's response (addresses),
# the IMS registration record, the socket. Gone at reboot, as the modem's
# own state is.
RUN = Path(os.environ.get('OMAMOBILE_SIT_RUN', '/run/omamobile-sit'))
# Persistent, root-only (0700): received SMS (before they are acknowledged)
# and the apps database. Holds numbers and message text: never copy it into
# the repository or a log.
STATE = Path(os.environ.get('OMAMOBILE_SIT_STATE', '/var/lib/omamobile-sit'))
INBOX = STATE / 'inbox'
CONFIG = Path(os.environ.get('OMAMOBILE_SIT_CONFIG', '/etc/omamobile/modem-sit.conf'))

# CPIF's character devices. "unix:PATH" is a SOCK_SEQPACKET socket (the
# simulator); "none" for BOOT means "no CP state ioctl: assume ONLINE".
IPC = os.environ.get('OMAMOBILE_SIT_DEVICE', '/dev/umts_ipc0')
ROUTER = os.environ.get('OMAMOBILE_SIT_ROUTER', '/dev/umts_router')
BOOT = os.environ.get('OMAMOBILE_SIT_BOOT', '/dev/umts_boot0')

DEFAULTS = {
    'network': {'apn': '', 'ip_type': 'ipv4v6', 'ims': 'yes', 'ims_apn': 'ims',
                'ims_required': 'no', 'ims_timeout': '120',
                'nr': 'off', 'sim_timeout': '120', 'register_timeout': '180'},
    'data': {'route': 'yes', 'metric': '700', 'ipv6': 'yes', 'ra_timeout': '10',
             'clat': 'auto', 'clat_prefix': ''},
    'control': {'group': 'wheel'},
    'ims': {'hidden_menu': '523:30 527:30 529:30 531:30 533:30',
            'add_pdn_flags': '17 0 0 1 0 0 35 0 0 1', 'profile_dir': '/etc/omamobile/ims.d'},
    'audio': {'card': 'none', 'mic_boost_db': '6'},
    'trace': {'record': 'no', 'directory': str(STATE / 'trace'), 'max_bytes': str(4 << 20)},
}


def config(path=None):
    parser = configparser.ConfigParser(interpolation=None)
    parser.read_dict(DEFAULTS)
    parser.read(path or CONFIG)
    return parser


def open_channel(path, flags=os.O_RDWR | os.O_NONBLOCK | os.O_CLOEXEC):
    """A file descriptor for a CPIF channel, or for the simulator's socket."""
    if path.startswith('unix:'):
        import socket
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        sock.connect(path[5:])
        sock.setblocking(False)
        return sock.detach()
    return os.open(path, flags)


def private_dir(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.chmod(0o700)
    return path
