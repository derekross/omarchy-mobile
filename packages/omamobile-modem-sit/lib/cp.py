# SPDX-License-Identifier: MIT
"""Read the CP state without stopping or restarting the modem.

An in-place modem stop has reset tegu. Unconfirmed calls are handled by
service.py with best-effort radio-off and an attended-reboot requirement;
the CP and its NV server stay running until shutdown.
"""
import fcntl
import os

from paths import BOOT

IOCTL_GET_CP_STATUS = 0x6f27   # _IO('o', 0x27)
STATES = {0: 'offline', 1: 'crash-reset', 2: 'crash-exit', 3: 'booting', 4: 'online',
          5: 'nv-rebuilding', 6: 'loader-done', 7: 'sim-attach', 8: 'sim-detach',
          9: 'crash-watchdog'}
ONLINE = 4


# One open file for every status request. On the Pixel 9a each open and
# close of umts_boot0 wakes the CP's PCIe link for about 100 ms, while the
# status ioctl on a held file doesn't wake it at all (omamobile-modem 0.1.9,
# measured 2026-10-29), so the service's 2 s check would otherwise cycle the
# link thirty times a minute for as long as it runs.
_fd = None


def state():
    global _fd
    if BOOT == 'none':
        return ONLINE
    try:
        if _fd is None:
            _fd = os.open(BOOT, os.O_RDWR | os.O_CLOEXEC)
        return fcntl.ioctl(_fd, IOCTL_GET_CP_STATUS, 0)
    except FileNotFoundError:
        return 0
    except OSError:
        if _fd is not None:
            os.close(_fd)
            _fd = None
        raise


def online():
    return state() == ONLINE
