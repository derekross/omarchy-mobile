# SPDX-License-Identifier: MIT
"""omamobile-mmd: Omarchy Mobile's ModemManager-compatible bridge.

Owns org.freedesktop.ModemManager1 on the system bus and serves MM 1.24's
API (the subset in docs/TELEPHONY-APPS-PLAN.md section 1.4) from
omamobile-sitd's socket, so GNOME Calls, Chatty, mmsd-tng and NetworkManager
see a modem. It never talks to the modem itself: sitd stays the only owner
of the SIT channel, and nothing here starts the modem or sitd.

  omamobile-mmd [--socket PATH] [--sit-config PATH] [--mms-daemon PATH] [--no-polkit]

--no-polkit skips the polkit checks (offline tests on a private bus only;
the shipped unit keeps them). DBUS_SYSTEM_BUS_ADDRESS picks another bus.
"""
import argparse
import configparser
import os
from pathlib import Path
import signal
import sys

from gi.repository import Gio, GLib

import bridge as bridge_module
import mm_api
from bridge import Bridge
from exporter import Exporter
from sitd_link import SitdLink

RUN = os.environ.get('OMAMOBILE_SIT_RUN', '/run/omamobile-sit')
SIT_CONFIG = os.environ.get('OMAMOBILE_SIT_CONFIG', '/etc/omamobile/modem-sit.conf')


def sit_settings(path):
    """The APN and IP type from sitd's own config, for
    Modem3gpp.InitialEpsBearerSettings and the bearer's properties, until
    sitd's status names the APN its start-up used ("auto" is chosen from
    the SIM, so it is no APN here)."""
    parser = configparser.ConfigParser(interpolation=None)
    try:
        parser.read(path)
    except (OSError, configparser.Error):
        return {}
    if not parser.has_section('network'):
        return {}
    return dict(apn=parser['network'].get('apn', '').strip(),
                attach_apn=parser['network'].get('attach_apn', '').strip(),
                ip_type=parser['network'].get('ip_type', 'ipv4v6').strip())


def main(argv=None):
    parser = argparse.ArgumentParser(description="ModemManager's D-Bus API in front of omamobile-sitd")
    parser.add_argument('--socket', default=os.path.join(RUN, 'socket'), help="omamobile-sitd's socket")
    parser.add_argument('--sit-config', default=SIT_CONFIG, help="omamobile-sitd's settings (the APN)")
    parser.add_argument('--mms-daemon', default=str(bridge_module.MMS_DAEMON),
                        help='the MMS daemon whose presence makes a WAP push binary data (tests)')
    parser.add_argument('--no-polkit', action='store_true', help='skip polkit (offline tests only)')
    args = parser.parse_args(argv)
    bridge_module.MMS_DAEMON = Path(args.mms_daemon)

    loop = GLib.MainLoop()
    state = dict(bridge=None, link=None, code=0)

    def bus_acquired(connection, name):
        exporter = Exporter(connection, polkit=not args.no_polkit)
        bridge = Bridge(exporter, None, sit_settings(args.sit_config))
        bridge.export_manager()
        link = SitdLink(args.socket, bridge.on_status, bridge.on_lost)
        bridge.link = link
        state.update(bridge=bridge, link=link)

    def name_acquired(connection, name):
        print(f'{name} acquired (ModemManager API {mm_api.VERSION})', flush=True)
        state['link'].start()

    def name_lost(connection, name):
        print(f'Could not own {name} (is ModemManager running?)', flush=True)
        state['code'] = 1
        loop.quit()

    def stop():
        loop.quit()
        return False

    owner = Gio.bus_own_name(Gio.BusType.SYSTEM, mm_api.SERVICE, Gio.BusNameOwnerFlags.NONE,
                             bus_acquired, name_acquired, name_lost)
    for signum in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signum, stop)
    try:
        loop.run()
    finally:
        Gio.bus_unown_name(owner)
        if state['link']:
            state['link'].stop()
    return state['code']


if __name__ == '__main__':
    sys.exit(main())
