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
    'network': {'apn': '', 'attach_apn': '', 'ip_type': 'ipv4v6', 'ims': 'yes', 'ims_apn': 'ims',
                'ims_required': 'no', 'ims_pcscf_required': 'yes',
                'ims_pcscf_from_isim': 'yes',
                'carrier_manifest': '', 'carrier_manifest_timeout': '60', 'ims_timeout': '120',
                'nr': 'off', 'sim_timeout': '120', 'register_timeout': '180'},
    # Extra modem-managed data profiles, one per line (data_call.parse_profile).
    'profiles': {},
    'data': {'route': 'yes', 'metric': '700'},
    'control': {'group': 'wheel'},
    'audio': {'card': 'none', 'mic_boost_db': '6', 'tegu_route': 'speaker', 'tegu_aec': 'no'},
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


def run_dir():
    """RUN for a client of sitd's directory (a SIT client, omamobile-sit-data):
    created private if missing, else only narrowed to at most 0710. sitd sets
    it 0710 root:<control group> so the group reaches state.json and the
    socket; a client that reset it to 0700 hid the modem from the shell."""
    if not RUN.exists():
        return private_dir(RUN)
    mode = RUN.stat().st_mode & 0o777
    if mode & ~0o710:
        RUN.chmod(mode & 0o710)
    return RUN
