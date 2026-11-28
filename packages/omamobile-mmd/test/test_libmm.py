# SPDX-License-Identifier: MIT
"""The bridge through libmm-glib, the library GNOME Calls, Chatty,
NetworkManager and mmsd-tng use: the same object manager client, proxies
and property parsing. Skipped without libmm-glib's typelib."""
import env
from env import GLib, Gio, MM, ROOT, FakeSitd, Mmd, PrivateBus, blank_status, registered_status, \
    spin, tempdir, wait_until
import os
import unittest

import mm_api as mm

try:
    env.gi.require_version('ModemManager', '1.0')
    from gi.repository import ModemManager as MMLib
except (ValueError, ImportError):
    MMLib = None

OTHER = '+12025550199'   # fictional


@unittest.skipUnless(MMLib, 'libmm-glib typelib not installed')
class LibmmClient(unittest.TestCase):
    def start(self, status, handlers=()):
        self.dir, cleanup = tempdir()
        self.addCleanup(cleanup)
        orig_cwd = os.getcwd()
        os.chdir(self.dir)
        self.addCleanup(os.chdir, orig_cwd)
        self.bus = PrivateBus(self.dir)
        self.addCleanup(self.bus.close)
        self.sitd = FakeSitd('sitd.sock')
        self.sitd.status = status
        self.sitd.handlers.update(handlers)
        self.mmd = Mmd(self.bus, self.sitd.path, self.dir)
        self.addCleanup(self.mmd.stop)
        connection = Gio.DBusConnection.new_for_address_sync(
            self.bus.address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT |
            Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        self.addCleanup(connection.close_sync, None)
        # As Calls and Chatty do: watch for the name first, then build the
        # manager (built earlier, its proxies get no destination).
        wait_until(lambda: self.bus.connection.call_sync(
            'org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
            'NameHasOwner', GLib.Variant('(s)', (MM,)), None, Gio.DBusCallFlags.NONE, 1000, None).unpack()[0],
            10, 'the bus name')
        self.manager = MMLib.Manager.new_sync(connection, Gio.DBusObjectManagerClientFlags.DO_NOT_AUTO_START, None)
        return wait_until(lambda: self.manager.get_objects(), 10, 'a modem through libmm-glib')[0]

    def test_no_sim(self):
        modem_object = self.start(blank_status())
        self.assertEqual(self.manager.get_version(), mm.VERSION)
        modem = modem_object.get_modem()
        self.assertEqual((modem.get_state(), modem.get_state_failed_reason(), modem.get_power_state()),
                         (MMLib.ModemState.FAILED, MMLib.ModemStateFailedReason.SIM_MISSING, MMLib.ModemPowerState.LOW))
        self.assertIsNone(modem.dup_sim_path() if modem.dup_sim_path() != '/' else None)
        self.assertTrue(modem_object.get_modem_voice().get_emergency_only())
        self.assertIsNone(modem_object.get_modem_messaging())
        self.assertEqual(modem_object.get_modem_3gpp().get_registration_state(),
                         MMLib.Modem3gppRegistrationState.IDLE)
        with self.assertRaises(GLib.Error) as caught:
            modem.enable_sync(None)
        self.assertTrue(caught.exception.matches(MMLib.core_error_quark(), MMLib.CoreError.WRONGSTATE))

    def test_registered_call_and_messages(self):
        status = registered_status()
        wap = b'\x01\x06"application/vnd.wap.mms-message\x00x'
        status['sms'] = dict(received=['sit:a'])
        self.start(status, {
            'sms-list': lambda r: [dict(id='sit:a', number=OTHER, text='', timestamp='2026-09-29T12:34:56+00:00',
                                        data=wap.hex(), state='received')],
            'sms-send': lambda r: dict(state='sent', error='', completed=1),
            'dial': lambda r: dict(call='7', number=r['number']), 'hangup': lambda r: {}})
        modem_object = self.manager.get_objects()[0]
        modem = modem_object.get_modem()
        self.assertEqual((modem.get_state(), modem.get_unlock_required()),
                         (MMLib.ModemState.REGISTERED, MMLib.ModemLock.NONE))
        sim = modem.get_sim_sync(None)
        self.assertEqual((sim.get_imsi(), sim.get_emergency_numbers()), (None, ['112', '911']))
        settings = modem_object.get_modem_3gpp().peek_initial_eps_bearer_settings()
        self.assertEqual((settings.get_apn(), settings.get_ip_type()), ('internet.example', MMLib.BearerIpFamily.IPV4V6))
        self.assertEqual(modem_object.get_modem_simple().get_status_sync(None).get_state(), MMLib.ModemState.REGISTERED)

        # mmsd-tng: an SMS with no text and data is a WAP push.
        messaging = modem_object.get_modem_messaging()
        listed = wait_until(lambda: messaging.list_sync(None), 5, 'the WAP push')
        self.assertEqual((listed[0].get_text(), bytes(listed[0].get_data()), listed[0].get_state(),
                          listed[0].get_pdu_type()), (None, wap, MMLib.SmsState.RECEIVED, MMLib.SmsPduType.DELIVER))

        # Chatty: create, then send.
        properties = MMLib.SmsProperties.new()
        properties.set_number(OTHER)
        properties.set_text('omamobile test text')
        sms = messaging.create_sync(properties, None)
        sms.send_sync(None)
        wait_until(lambda: sms.get_state() == MMLib.SmsState.SENT, 5, 'sent')

        # GNOME Calls: create, start, see it dial, hang up.
        voice = modem_object.get_modem_voice()
        self.assertFalse(voice.get_emergency_only())
        properties = MMLib.CallProperties.new()
        properties.set_number(OTHER)
        new_call = voice.create_call_sync(properties, None)
        self.assertEqual((new_call.get_direction(), new_call.get_number()), (MMLib.CallDirection.OUTGOING, OTHER))
        new_call.start_sync(None)
        wait_until(lambda: new_call.get_state() == MMLib.CallState.DIALING, 5, 'dialing')
        self.sitd.status['calls'] = [dict(id='7', number=OTHER, direction='outgoing', state='active', reason='',
                                          multiparty=False, since=0)]
        self.sitd.push()
        wait_until(lambda: new_call.get_state() == MMLib.CallState.ACTIVE, 5, 'active')
        new_call.hangup_sync(None)
        self.assertEqual([c.get_path() for c in voice.list_calls_sync(None)], [new_call.get_path()])
        spin(.1)


if __name__ == '__main__':
    unittest.main()
