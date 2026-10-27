# SPDX-License-Identifier: MIT
import env  # noqa: F401  (paths and sys.path first)
import json
import os
from pathlib import Path
import struct
import socket
import tempfile
import unittest
from unittest.mock import Mock, MagicMock, patch
import paths
import service as app_service

class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)
        self.paths=patch.object(paths,'RUN',self.root); self.paths.start()
        self.db=app_service.database(self.root/'db')
        self.client=Mock(); self.client.next_indication.return_value=None
        self.service=app_service.Service(self.client,self.db)
        self.service.ready=Mock()
    def tearDown(self):
        self.db.close(); self.paths.stop(); self.temp.cleanup()
    def test_phone_reset_indication_logs_its_first_bytes_raw(self):
        packet = struct.pack('<BBHHH', 2, 0, 0x0804, 8 + 6, 0) + bytes([0x08, 0x02, 0x00, 0x00, 0xaa, 0xbb])
        with patch('builtins.print') as out:
            self.service.event(packet)
        line = ' '.join(str(a) for a in out.call_args.args)
        self.assertEqual(line, 'Modem reset indication (IND_PHONE_RESET, 6 payload bytes): '
                         'bytes 0x08..0x0b = 08 02 00 00 (reset type and cause somewhere here, '
                         'offsets unconfirmed); not acted on')
        self.assertNotIn('aa', line)                     # only the first four bytes
        self.client.request.assert_not_called()          # logged, never answered
        self.assertEqual(self.service.indication_counts['0804'], 1)
    def test_short_phone_reset_indication(self):
        self.assertIn('bytes 0x08..0x09 = 01 07',
                      app_service.reset_indication(struct.pack('<BBHHH', 2, 0, 0x0804, 10, 0) + b'\x01\x07'))
        self.assertIn('no payload', app_service.reset_indication(struct.pack('<BBHHH', 2, 0, 0x0804, 8, 0)))
    def test_send_idempotency_after_success_and_unknown_response(self):
        for i,reply in enumerate((bytes(253),TimeoutError())):
            self.client.request.side_effect=[bytes([1])+bytes(12),reply]
            req=dict(request_id=str(i)*32,number='+12025550123',text='Hello €')
            result=self.service.send_sms(req)
            self.assertEqual(result['state'],'sent' if i==0 else 'unknown')
            before=self.client.request.call_count
            repeated=self.service.send_sms(req)
            self.assertEqual(repeated['state'],result['state'])
            self.assertEqual(self.client.request.call_count,before)
    def test_wap_push_parts_join_into_data(self):
        inbox=self.root/'inbox'; inbox.mkdir()
        pieces=[bytes(range(0,100)),bytes(range(100,160))]
        for seq,piece in enumerate(pieces,1):
            ud=bytes.fromhex('0b05040b8423f000030902')+bytes([seq])+piece
            tpdu=bytes.fromhex('440b912120550521f3000462909221436500')+bytes([len(ud)])+ud
            data=bytes.fromhex('07912120550521f3')+tpdu
            path=inbox/f'{seq}.sit'
            path.write_bytes(bytes(2)+struct.pack('<H',0x0d1e)+bytes(5)+bytes([len(data)])+data)
            self.service.ingest(path)
        listed=self.service.dispatch(dict(action='sms-list'))
        self.assertEqual(len(listed),1)
        self.assertEqual((listed[0]['number'],listed[0]['text'],listed[0]['data']),('+12025550123','',b''.join(pieces).hex()))
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM parts').fetchone()[0],0)
    def test_restart_does_not_retry_pending_sms(self):
        self.db.execute('INSERT INTO outgoing VALUES (?,?,?,?,?)',('a'*32,'digest','sending','',0)); self.db.commit()
        other=app_service.database(self.root/'db')
        self.assertEqual(other.execute('SELECT state FROM outgoing').fetchone()[0],'unknown'); other.close()

    def test_failed_radio_off_still_requires_reboot_without_claiming_release(self):
        self.client.request.side_effect = TimeoutError()
        with patch.object(app_service, 'radio', side_effect=OSError()), \
             patch.object(app_service.cp, 'state', side_effect=OSError()), \
             patch('builtins.print') as printed:
            with self.assertRaisesRegex(RuntimeError, 'attended reboot required'):
                app_service.unconfirmed_release(self.client, 'hangup deadline expired')
        log = ' '.join(' '.join(map(str, call.args)) for call in printed.call_args_list)
        self.assertIn('hangup deadline expired', log)
        self.assertIn('radio-off failed: OSError', log)
        self.assertIn('radio unavailable (TimeoutError) CP unavailable', log)
        self.assertIn('leaving the modem running', log)

    def test_unconfirmed_release_during_socket_request_is_fatal(self):
        mine, theirs = socket.socketpair()
        self.addCleanup(mine.close)
        self.addCleanup(theirs.close)
        theirs.sendall(b'{"action":"status"}\n')
        self.service.dispatch = Mock(side_effect=app_service.UnconfirmedRelease('attended reboot required'))
        with self.assertRaises(app_service.UnconfirmedRelease):
            app_service.serve_one(self.service, mine, {os.getuid()})
        self.assertEqual(mine.fileno(), -1)
    def test_ring_does_not_autoanswer_and_release_restores_audio(self):
        n=b'+12025550123'; body=struct.pack('<HBH',1,7,len(n))+n
        packet=struct.pack('<BBHHH',2,0,0x0d01,8+len(body),0)+body
        self.service.event(packet)
        self.client.request.assert_not_called()
        call=self.service.live()[0]
        self.assertEqual(call['state'],'ringing-in')
        audio=MagicMock(); self.service.audio=audio
        body=struct.pack('<HBBBBBBB',1,7,6,0,0,0,16,0)+bytes(2)
        self.service.event(struct.pack('<BBHHH',2,0,0x0d04,8+len(body),0)+body)
        audio.__exit__.assert_called_once()
        self.assertFalse(self.service.live())

    def test_keypad_only_targets_an_active_owned_call(self):
        call=self.service.new_call('+12025550123','outgoing','active',7)
        self.service.dispatch(dict(action='dtmf',id=call['id'],keys='5#'))
        self.assertEqual([c.args for c in self.client.request.call_args_list],[(0x0d0a,bytes([7,0,53])),(0x0d0a,bytes([7,0,35]))])
        call['state']='terminated'
        with self.assertRaises(RuntimeError): self.service.dispatch(dict(action='dtmf',id=call['id'],keys='5'))

    def test_screen_state_blocks_sleep_during_calls_and_only_caches_success(self):
        self.client.request.side_effect=TimeoutError()
        with self.assertRaises(TimeoutError):
            self.service.dispatch(dict(action='screen-state',on=False))
        self.assertIsNone(self.service.screen_on)
        self.client.request.side_effect=None
        self.service.dispatch(dict(action='screen-state',on=False))
        self.assertEqual([c.args for c in self.client.request.call_args_list[-2:]],
                         [(0x0902,bytes(4)),(0x0928,bytes(4))])
        count=self.client.request.call_count
        self.service.dispatch(dict(action='screen-state',on=False))
        self.assertEqual(count,self.client.request.call_count)
        self.service.new_call('+12025550123','incoming','ringing-in',7)
        with self.assertRaises(RuntimeError):
            self.service.dispatch(dict(action='screen-state',on=False))
        self.service.dispatch(dict(action='screen-state',on=True))
        self.assertEqual([c.args for c in self.client.request.call_args_list[-2:]],
                         [(0x0902,b'\x01\0\0\0'),(0x0928,b'\xff'*4)])
        with self.assertRaises(ValueError):
            self.service.dispatch(dict(action='screen-state',on=2))

    def test_failed_filter_does_not_hide_partial_screen_change(self):
        self.service.screen_on=True
        self.client.request.side_effect=[b'',TimeoutError()]
        with self.assertRaises(TimeoutError):
            self.service.dispatch(dict(action='screen-state',on=False))
        self.assertIsNone(self.service.screen_on)
        self.client.request.side_effect=None
        self.service.dispatch(dict(action='screen-state',on=True))
        self.assertTrue(self.service.screen_on)
        self.client.request.assert_called_with(0x0928,b'\xff'*4,timeout=5)

    def test_public_state_has_no_numbers(self):
        self.service.new_call('+12025550123','incoming','ringing-in',7)
        state=json.loads((self.root/'state.json').read_text())
        self.assertNotIn('2025550123',json.dumps(state))
        self.assertEqual(state['calls'],[dict(state='ringing-in',direction='incoming')])
        self.assertEqual((self.root/'state.json').stat().st_mode&0o777,0o644)

    def test_operator_name_is_display_only_and_defensive(self):
        payload=bytearray(0x77-12); payload[:6]=b'00101#'; payload[6:10]=b'Test'
        self.assertEqual(app_service.operator_name(bytes(payload)),dict(plmn='00101',name='Test'))
        self.assertEqual(app_service.operator_name(bytes(8)),dict(plmn='',name=''))

    def reg_failed(self, domain, cause, additional):
        packet = bytearray(0x11 + 8)
        struct.pack_into('<BBHH', packet, 0, 2, 0, 0x074a, len(packet))
        packet[8:14] = b'00101#'
        packet[0x0e:0x11] = bytes([domain, cause, additional])
        packet[0x11:] = b'\x12\x34\x56\x78\x9a\xbc\xde\xf0'   # cell identity: never shown
        return bytes(packet)

    def test_registration_failure_is_logged_with_codes_only(self):
        self.assertEqual(app_service.registration_failure(self.reg_failed(1, 10, 0xff)), ('CS+PS', 10, None))
        self.assertEqual(app_service.registration_failure(self.reg_failed(3, 0xff, 0)), ('PS', None, 0))
        with patch('builtins.print') as out:
            self.service.event(self.reg_failed(3, 7, 0))
        line = ' '.join(str(a) for a in out.call_args.args)
        self.assertEqual(line, 'Registration failed: domain PS cause 7 additional cause 0')
        self.assertEqual(self.service.next_poll, 0)
        with self.assertRaises(ValueError):
            app_service.registration_failure(bytes(0x10))

    def test_registration_changes_are_logged_once_each(self):
        replies = {0x0200: bytes(3), 0x0801: struct.pack('<I', 2), 0x0702: bytes(0x77 - 12)}
        states = [bytes([1, 0, 0, 14]), bytes([1, 0, 0, 14]), bytes([0, 0, 0, 14]), bytes([3, 7, 0, 14])]
        lines = []
        for ps in states:
            replies[0x0701] = ps
            self.client.request.side_effect = lambda ident, *a, **k: replies[ident]
            self.service.next_poll = 0
            with patch('builtins.print') as out:
                self.service.poll()
            lines += [' '.join(str(x) for x in c.args) for c in out.call_args_list
                      if c.args and c.args[0] == 'Packet registration:']
        self.assertEqual(lines, ['Packet registration: home (state 1), reject 0, RAT 14',
                                 'Packet registration: not-registered (state 0), reject 0, RAT 14',
                                 'Packet registration: denied (state 3), reject 7, RAT 14'])

    def signal_packet(self, mask, rsrp):
        payload = bytearray(2 + 0xc4)
        struct.pack_into('<H', payload, 0, mask)
        struct.pack_into('<I', payload, 2 + 0x3c, 13)        # LTE signal strength
        struct.pack_into('<I', payload, 2 + 0x40, rsrp)
        return struct.pack('<BBHH', 2, 0, 0x0906, 8 + len(payload)) + bytes(2) + bytes(payload)

    def test_radio_state_10_is_on(self):
        self.assertEqual(app_service.RADIO[10], 'on')

    def test_lte_rsrp_and_signal_percent(self):
        self.assertEqual(app_service.lte_rsrp(self.signal_packet(4, 109)[8:]), -109)
        self.assertIsNone(app_service.lte_rsrp(self.signal_packet(0, 109)[8:]))       # no LTE bit
        self.assertIsNone(app_service.lte_rsrp(self.signal_packet(4, 0)[8:]))         # not measured
        self.assertIsNone(app_service.lte_rsrp(self.signal_packet(4, 0x7fffffff)[8:]))
        self.assertIsNone(app_service.lte_rsrp(bytes(20)))
        self.assertEqual([app_service.signal_percent(r) for r in (-140, -109, -92, -44, -30, None)],
                         [0, 32, 50, 100, 100, 0])

    def test_signal_indication_reaches_status_while_registered(self):
        self.service.net['reg'] = 'home'
        self.service.event(self.signal_packet(4, 92))
        self.assertEqual(self.service.status()['modem']['signal'], 50)
        self.service.net['reg'] = 'not-registered'
        self.assertEqual(self.service.status()['modem']['signal'], 0)

    def test_network_state_indication_brings_the_poll_forward(self):
        import time
        self.service.next_poll = time.monotonic() + 30
        self.service.event(struct.pack('<BBHH', 2, 0, 0x070e, 8))
        self.assertLessEqual(self.service.next_poll, time.monotonic() + 5)

    def test_unconfirmed_release_turns_radio_off_and_keeps_call_ownership(self):
        call=self.service.new_call('+12025550123','outgoing','active',7)
        self.client.request.return_value = struct.pack('<I', 1)
        with patch.object(app_service, 'radio') as radio, \
             patch.object(app_service.cp, 'state', return_value=app_service.cp.ONLINE):
            self.service.dispatch(dict(action='hangup',id=call['id']))
            radio.assert_not_called()
            self.service.hangup_deadline=0.001
            with self.assertRaises(app_service.UnconfirmedRelease): self.service.pump()
            radio.assert_called_once_with(False)
        self.assertTrue(self.service.release_unconfirmed)
        self.assertEqual(self.service.live(), [call])
        self.assertTrue(json.loads((self.root/'active.json').read_text()))
    def run_main_with_channel_closed(self,online):
        # raven, 2026-10-27: the CP crashed during start-up and sitd died with
        # a traceback from the SIT read.
        with patch('sys.argv',['omamobile-sitd']), \
             patch.object(app_service.paths,'STATE',self.root), \
             patch.object(app_service.cp,'online',side_effect=[True]+online), \
             patch.object(app_service,'Sit'), \
             patch.object(app_service,'database'), \
             patch.object(app_service,'Service',side_effect=EOFError('SIT channel closed')), \
             patch.object(app_service.signal,'signal'):
            app_service.main()
    def test_a_crashed_cp_ends_the_service_in_one_line(self):
        with self.assertRaises(SystemExit) as raised: self.run_main_with_channel_closed([False])
        self.assertIn('the modem went away (SIT channel closed)',str(raised.exception.code))
    def test_a_closed_channel_with_the_cp_online_still_raises(self):
        with self.assertRaises(EOFError): self.run_main_with_channel_closed([True])


class RefusedAudioTests(unittest.TestCase):
    def test_a_refused_audio_route_does_not_stop_the_call(self):
        import service as service_module
        svc = service_module.Service.__new__(service_module.Service)
        svc.audio = None
        svc.audio_error = ''
        svc.muted = False
        svc.settings = {'audio': {'card': 'auto', 'mic_boost_db': '6', 'earpiece': 'yes'}}
        import configparser
        cfg = configparser.ConfigParser()
        cfg.read_dict(svc.settings)
        svc.settings = cfg
        with patch.object(service_module, 'aoc_card', return_value=0), \
             patch.object(service_module.VoiceAudio, '__init__', return_value=None), \
             patch.object(service_module.VoiceAudio, '__enter__',
                          side_effect=RuntimeError('earpiece mode on failed: refused')):
            svc.audio_start()   # must not raise
        self.assertIsNone(svc.audio)
        self.assertIn('earpiece mode on failed', svc.audio_error)


    def test_a_failed_audio_cleanup_does_not_stop_the_service(self):
        import service as service_module
        svc = service_module.Service.__new__(service_module.Service)
        svc.audio_error = ''
        svc.muted = True
        class Broken:
            def __exit__(self, *a):
                raise RuntimeError('voice cleanup failed: earpiece mode off')
        svc.audio = Broken()
        svc.audio_stop()   # must not raise
        self.assertIsNone(svc.audio)
        self.assertFalse(svc.muted)
        self.assertIn('earpiece mode off', svc.audio_error)
