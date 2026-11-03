# SPDX-License-Identifier: MIT
"""The automatic APN: the SIM's home network code looked up in the project's
overrides, then in the carrier database. Every IMSI here is a made-up one:
a carrier's public network code followed by zeros."""
import env  # noqa: F401  (paths and sys.path first)
import os
from pathlib import Path
import tempfile
import unittest

import carrier_apn

HERE = Path(__file__).resolve().parent
OVERRIDES = HERE.parent / 'share' / 'apn-overrides.conf'
SYSTEM_DB = Path('/usr/share/mobile-broadband-provider-info/serviceproviders.xml')

# Shaped like serviceproviders.xml (serviceproviders.2.dtd), with the cases
# that matter: an operator and resellers sharing a code, primary="true",
# an IMS APN filed as internet, MMS-only APNs and a two-digit-MNC country.
FAKE_DB = '''<?xml version="1.0"?>
<serviceproviders format="2.0">
<country code="us">
  <provider><name>Example Reseller</name><gsm>
    <network-id mcc="310" mnc="410"/>
    <apn value="reseller.example"><usage type="internet"/></apn></gsm></provider>
  <provider><name>Example Operator</name><gsm>
    <network-id mcc="310" mnc="150"/><network-id mcc="310" mnc="410"/>
    <apn value="operator.example"><usage type="mms-internet-hipri"/></apn>
    <apn value="attach.example"><usage type="ia"/></apn></gsm></provider>
  <provider><name>Example IMS First</name><gsm>
    <network-id mcc="311" mnc="480"/>
    <apn value="ims"><usage type="internet"/></apn>
    <apn value="first.example"><usage type="internet"/></apn></gsm></provider>
  <provider primary="false"><name>Example MVNO</name><gsm>
    <network-id mcc="310" mnc="260"/>
    <apn value="mvno.example"><usage type="internet"/></apn></gsm></provider>
  <provider primary="true"><name>Example Wholesale</name><gsm>
    <network-id mcc="310" mnc="260"/>
    <apn value="mms.example"><usage type="mms"/></apn>
    <apn value="wholesale.example"><usage type="internet"/></apn></gsm></provider>
</country>
<country code="gb">
  <provider><name>Example UK</name><gsm>
    <network-id mcc="234" mnc="15"/>
    <apn value="uk.example"/></gsm></provider>
</country>
</serviceproviders>
'''


def imsi(mcc, mnc):
    return mcc + mnc + '0' * (15 - len(mcc) - len(mnc))


class CarrierApnTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='carrier-apn-')
        self.db = os.path.join(self.dir, 'serviceproviders.xml')
        Path(self.db).write_text(FAKE_DB)
        self.none = os.path.join(self.dir, 'absent.conf')

    def tearDown(self):
        for name in os.listdir(self.dir):
            os.unlink(os.path.join(self.dir, name))
        os.rmdir(self.dir)

    def look(self, mcc, mnc, overrides=None):
        return carrier_apn.lookup(imsi(mcc, mnc), self.db, overrides or self.none)

    def test_home_plmn_keeps_only_the_network_code(self):
        self.assertEqual(carrier_apn.home_plmn(imsi('311', '480')), ('311', ['480', '48']))
        self.assertEqual(carrier_apn.home_plmn(imsi('234', '15')), ('234', ['15', '150']))
        for bad in ('', '31148', '3114800000000000', '31148x000000000', None):
            with self.assertRaises(ValueError):
                carrier_apn.home_plmn(bad)

    def test_the_operator_wins_over_a_reseller_on_its_code(self):
        found = self.look('310', '410')
        self.assertEqual((found['apn'], found['attach_apn'], found['source']),
                         ('operator.example', 'attach.example', 'carrier-database'))
        # No "ia" APN: attach with the internet APN ('').
        self.assertEqual(self.look('310', '260')['attach_apn'], '')

    def test_primary_true_and_internet_usage(self):
        self.assertEqual(self.look('310', '260')['apn'], 'wholesale.example')

    def test_an_ims_apn_is_never_the_internet_apn(self):
        self.assertEqual(self.look('311', '480')['apn'], 'first.example')

    def test_two_digit_mnc_and_an_apn_without_usage(self):
        self.assertEqual(self.look('234', '15')['apn'], 'uk.example')

    def test_unknown_code_and_missing_database(self):
        self.assertIsNone(self.look('001', '01'))
        self.assertIsNone(carrier_apn.lookup(imsi('310', '410'), os.path.join(self.dir, 'none.xml'), self.none))
        Path(self.db).write_text('<not xml')
        self.assertIsNone(self.look('310', '410'))

    def test_overrides_come_first_and_are_checked(self):
        path = os.path.join(self.dir, 'overrides.conf')
        Path(path).write_text('[311/480]\nname = Example\napn = override.example\nims_apn = ims.example\n'
                              '[310/410]\napn = bad apn\n')
        found = self.look('311', '480', path)
        self.assertEqual((found['apn'], found['ims_apn'], found['source']),
                         ('override.example', 'ims.example', 'override'))
        # A value that isn't a plain APN is ignored: the database answers.
        self.assertEqual(self.look('310', '410', path)['apn'], 'operator.example')

    def test_no_part_of_the_imsi_is_returned(self):
        subscriber = '311480' + '987654321'
        found = carrier_apn.lookup(subscriber, self.db, self.none)
        self.assertNotIn('987654321', repr(found))

    def test_shipped_overrides_send_verizon_codes_to_vzwinternet(self):
        for mcc, mnc in (('311', '480'), ('310', '012')):
            found = carrier_apn.lookup(imsi(mcc, mnc), self.db, str(OVERRIDES))
            self.assertEqual((found['apn'], found['attach_apn'], found['source']), ('vzwinternet', 'ims', 'override'))
        text = OVERRIDES.read_text()
        self.assertIn('https://www.verizon.com/support/', text)


@unittest.skipUnless(SYSTEM_DB.exists(), 'mobile-broadband-provider-info is not installed')
class SystemDatabaseTests(unittest.TestCase):
    """The installed database with the shipped overrides: the big three US
    carriers and a reseller SIM on Verizon's network."""
    def look(self, mcc, mnc):
        return carrier_apn.lookup(imsi(mcc, mnc), str(SYSTEM_DB), str(OVERRIDES))

    def test_verizon_and_its_resellers(self):
        self.assertEqual(self.look('311', '480')['apn'], 'vzwinternet')

    def test_t_mobile(self):
        self.assertEqual(self.look('310', '260')['apn'], 'fast.t-mobile.com')

    def test_att_operator_not_a_reseller(self):
        found = self.look('310', '410')
        self.assertEqual(found['carrier'], 'AT&T')
        self.assertTrue(found['apn'])


if __name__ == '__main__':
    unittest.main()
