# SPDX-License-Identifier: MIT
"""The CP (modem) state from CPIF, and the one way this stack powers it off.

The modem stays on once it is up (device/cheetah/MODEM-PLAN.md M2.6: every
modem power-off costs one recovered UFS error-handler pass). The RIL powers
it off only when a call's release can't be confirmed: then stopping the
modem unit is the only way to be sure the radio isn't carrying a call. The
unit's stop powers the CP off before rfsd goes (omamobile-modem profile).
"""
import fcntl
import os
import subprocess
import time

from paths import BOOT

IOCTL_GET_CP_STATUS = 0x6f27   # _IO('o', 0x27)
STATES = {0: 'offline', 1: 'crash-reset', 2: 'crash-exit', 3: 'booting', 4: 'online',
          5: 'nv-rebuilding', 6: 'loader-done', 7: 'sim-attach', 8: 'sim-detach',
          9: 'crash-watchdog'}
ONLINE = 4
MODEM_UNIT = 'omamobile-modem.service'


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


def stop_modem(reason):
    """Stop the modem unit (CP off, then rfsd) and wait for OFFLINE."""
    print('Stopping the modem:', reason, flush=True)
    if BOOT == 'none':
        return
    subprocess.run(['systemctl', 'stop', '--no-block', MODEM_UNIT],
                   stdin=subprocess.DEVNULL, capture_output=True, timeout=20)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if state() == 0:
            print('CP OFFLINE', flush=True)
            return
        time.sleep(.25)
    raise RuntimeError('CP shutdown not confirmed; reboot the phone')
