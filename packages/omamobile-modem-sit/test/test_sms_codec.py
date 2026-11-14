# SPDX-License-Identifier: MIT
import env  # noqa: F401  (paths and sys.path first)
import unittest
from sms_codec import pack7, unpack7, submit, deliver, received_pdu, number

class CodecTests(unittest.TestCase):
    def test_known_gsm_vector_and_extensions(self):
        self.assertEqual(pack7([104,101,108,108,111]),(5,bytes.fromhex('e8329bfd06')))
        self.assertEqual(unpack7(bytes.fromhex('e8329bfd06'),5),'hello')
        self.assertEqual(unpack7(pack7([27,101,27,20])[1],4),'€^')

    def test_long_text_headers_and_unicode_character_boundaries(self):
        for text in ('a'*161,'^'*81,'🙂'*40):
            parts=submit('+12025550123',text)
            self.assertEqual(len(parts),2)
            contents=[]
            for i,pdu in enumerate(parts):
                self.assertEqual(pdu[0],0x41)
                address_size=(pdu[2]+1)//2
                dcs=pdu[5+address_size]; length=pdu[6+address_size]; data=pdu[7+address_size:]
                self.assertEqual(data[:3],bytes([5,0,3]))
                self.assertEqual(data[4:6],bytes([2,i+1]))
                self.assertLessEqual(len(data),140)
                contents.append(unpack7(data,length,7) if dcs==0 else data[6:].decode('utf-16-be'))
            self.assertEqual(''.join(contents),text)

    def test_delivery_known_text_and_timestamp(self):
        # SMS-DELIVER, international sender, default alphabet, 2026-09-29 UTC.
        pdu=bytes.fromhex('000b912120550521f300006290922143650005e8329bfd06')
        sms=deliver(pdu)
        self.assertEqual(received_pdu(bytes.fromhex('07912120550521f3')+pdu),sms)
        self.assertEqual(sms['number'],'+12025550123')
        self.assertEqual(sms['text'],'hello')
        self.assertTrue(sms['timestamp'].startswith('2026-09-29'))
        with self.assertRaises(ValueError): deliver(pdu[:-1])

    def test_wap_push_keeps_its_bytes_and_port(self):
        # 8-bit SMS-DELIVER with ports 2948/9200 and part 1 of 2 in its header.
        body=bytes.fromhex('01060403be81ea')
        header=bytes.fromhex('0b05040b8423f0000307' '0201')
        pdu=bytes.fromhex('440b912120550521f3000462909221436500')+bytes([len(header)+len(body)])+header+body
        sms=deliver(pdu)
        self.assertEqual((sms['port'],sms['data'],sms['concat'],sms['text']),(2948,body,(7,2,1),''))
        other=deliver(pdu.replace(bytes.fromhex('0b84'),bytes.fromhex('1584')))
        self.assertEqual((other['data'],other['port']),(b'',0x1584))
        self.assertIn('cannot display',other['text'])

    def test_only_an_uncompressed_8_bit_wap_push_is_data(self):
        # The same WAP push header and body under other data coding schemes:
        # the reserved alphabet (0x0c) and compressed content (0x24 8-bit,
        # 0x20 default alphabet) are not bytes this phone can hand on.
        body=bytes.fromhex('01060403be81ea')
        header=bytes.fromhex('0b05040b8423f0000307' '0201')
        def push(dcs):
            return deliver(bytes.fromhex('440b912120550521f300')+bytes([dcs])+bytes.fromhex('62909221436500')
                           +bytes([len(header)+len(body)])+header+body)
        self.assertEqual(push(0x04)['data'],body)
        for dcs in (0x0c,0x24,0x20):
            sms=push(dcs)
            self.assertEqual((sms['data'],sms['port']),(b'',2948),hex(dcs))
            self.assertIn('cannot display',sms['text'],hex(dcs))

    def test_an_8_bit_part_without_a_port_is_data_only_when_concatenated(self):
        # A later part of a WAP push has no port of its own, so its bytes are
        # kept for the service to join and judge; a single 8-bit message with
        # no port is not a WAP push.
        body=b'\x00\xffsecond'
        def message(header):
            ud=header+body
            return deliver(bytes.fromhex('440b912120550521f3000462909221436500')+bytes([len(ud)])+ud)
        part=message(bytes.fromhex('050003090202'))
        self.assertEqual((part['data'],part['port'],part['concat']),(body,None,(9,2,2)))
        single=message(bytes.fromhex('0401020304'))     # a header with no port and no concatenation
        self.assertEqual((single['data'],single['port'],single['concat']),(b'',None,None))
        self.assertIn('cannot display',single['text'])

    def test_number_and_special_service_rejection(self):
        self.assertEqual(number('(202) 555-0123',voice=True),'+12025550123')
        for value in ('911','112','*123#'):
            with self.assertRaises(ValueError): number(value,voice=True)
