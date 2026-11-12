# SPDX-License-Identifier: MIT
import env  # (paths and sys.path first; env.TMP for scratch files)
import os
import shutil
import tempfile
import unittest
from unittest.mock import patch
import paths
import voice_audio
from voice_audio import VoiceAudio

STATUS = os.path.join(tempfile.mkdtemp(dir=env.TMP), 'speaker-protection')


class AudioCleanupTests(unittest.TestCase):
    def setUp(self):
        with open(STATUS, 'w') as f:
            f.write('ok: stage media, protection firmware with factory calibration, digital/analog 737/6\n')
        patcher = patch.object(voice_audio, 'PROTECTION', voice_audio.Path(STATUS))
        patcher.start()
        self.addCleanup(patcher.stop)

    def fixture(self, fail_params=False, levels=None):
        class Alsa:
            opened = 0
            closed = []
            def snd_pcm_open(self, pointer, *args):
                self.opened += 1
                pointer._obj.value = self.opened
                return 0
            def snd_pcm_set_params(self, pcm, *args):
                return -5 if fail_params and pcm.value == 2 else 0
            def snd_pcm_prepare(self, pcm):
                return 0
            def snd_pcm_state(self, pcm):
                return 2
            def snd_pcm_start(self, pcm):
                return 0
            def snd_pcm_drop(self, pcm):
                return 0
            def snd_pcm_close(self, pcm):
                self.closed.append(pcm.value)
                return 0
        audio = VoiceAudio.__new__(VoiceAudio)
        audio.saved = []
        audio.pcms = []
        audio.mic_boost_db = 0
        audio.alsa = Alsa()
        changed = []
        def mixer(action, name, value=None):
            if action == 'cget':
                return '  : values=%s\n' % (levels or {}).get(name, '0')
            changed.append((name, value))
            return ''
        audio.mixer = mixer
        return audio, changed

    def test_partial_open_failure_closes_both_pcms_and_restores_all_routes(self):
        audio, changed = self.fixture(fail_params=True)
        with self.assertRaisesRegex(RuntimeError, 'params failed'):
            audio.__enter__()
        self.assertEqual(audio.alsa.closed, [2, 1])
        self.assertEqual(changed[10:], [(name, '0') for name, _ in reversed(changed[:10])])
        self.assertFalse(audio.saved)
        self.assertFalse(audio.pcms)

    def test_body_failure_still_restores_routes(self):
        audio, changed = self.fixture()
        with self.assertRaisesRegex(RuntimeError, 'call failed'):
            with audio:
                raise RuntimeError('call failed')
        self.assertEqual(audio.alsa.closed, [2, 1])
        self.assertEqual(len(changed), 20)

    def test_microphone_boost_is_bounded_and_restored(self):
        audio, changed = self.fixture()
        audio.mic_boost_db = 6
        with audio:
            self.assertIn(('MIC HW Gain At High Power Mode (cB)', '190'), changed)
        self.assertIn(('MIC HW Gain At High Power Mode (cB)', '0'), changed[10:])
        with self.assertRaises(ValueError):
            VoiceAudio(mic_boost_db=12)


class CallAudioCeilingTests(AudioCleanupTests):
    def refused(self, audio, changed, reason):
        with self.assertRaisesRegex(RuntimeError, reason):
            audio.__enter__()
        self.assertEqual(changed, [])           # not one control written
        self.assertEqual(audio.alsa.opened, 0)  # no PCM opened

    def test_media_stage_top_amplifier_above_the_earpiece_ceiling(self):
        # The media stage's default (analog 10 on both) is too loud at the ear.
        audio, changed = self.fixture(levels={'Top Analog PCM Volume': '10'})
        self.refused(audio, changed, 'Top Analog PCM Volume is above 6')

    def test_levels_above_the_media_stage(self):
        for name, value in (('Bottom Analog PCM Volume', '17'), ('Top Digital PCM Volume', '817'),
                            ('Bottom Digital PCM Volume', '737,817')):
            audio, changed = self.fixture(levels={name: value})
            self.refused(audio, changed, name + ' is above')

    def test_protection_must_run_at_media_or_c8(self):
        for line in ('', 'muted: no calibration', 'ok: stage c9, ...', 'MUTE FAILED: x'):
            with open(STATUS, 'w') as f:
                f.write(line)
            audio, changed = self.fixture()
            self.refused(audio, changed, 'speaker protection is not running')
        os.unlink(STATUS)
        audio, changed = self.fixture()
        self.refused(audio, changed, 'speaker protection is not running')

    def test_earpiece_mode_is_accepted_in_any_stage(self):
        with open(STATUS, 'w') as f:
            f.write('ok: stage c9, mode earpiece: Top 657/6 through PCM Source ASP, DRE on; Bottom muted (Digital PCM Volume 0); x\n')
        audio, changed = self.fixture(levels={'Top Analog PCM Volume': '6', 'Top Digital PCM Volume': '657',
                                              'Bottom Digital PCM Volume': '0', 'Bottom Analog PCM Volume': '17'})
        audio.check_levels()          # the bottom's analog gain doesn't matter: it is muted

    def test_earpiece_mode_needs_the_bottom_muted_and_the_top_at_the_earpiece_level(self):
        for name, value in (('Bottom Digital PCM Volume', '1'), ('Top Analog PCM Volume', '7'),
                            ('Top Digital PCM Volume', '738')):
            with open(STATUS, 'w') as f:
                f.write('ok: stage media, mode earpiece: Top 657/6 ...; Bottom muted (Digital PCM Volume 0); x\n')
            levels = {'Top Analog PCM Volume': '6', 'Top Digital PCM Volume': '657', 'Bottom Digital PCM Volume': '0'}
            levels[name] = value
            audio, changed = self.fixture(levels=levels)
            self.refused(audio, changed, name + ' is above')

    def test_earpiece_mode_switched_on_before_the_route_and_off_after(self):
        calls = []
        def run(args, **kwargs):
            mode = args[-1].replace('omamobile-earpiece@', '').replace('.service', '')
            calls.append(['earpiece', mode])
            with open(STATUS, 'w') as f:
                f.write('ok: stage media, mode earpiece: Top 657/6; Bottom muted (Digital PCM Volume 0); x\n'
                        if mode == 'on' else 'ok: stage media, protection firmware\n')
            class R:
                returncode = 0
                stdout = stderr = ''
            return R()
        audio, changed = self.fixture(levels={'Top Analog PCM Volume': '6', 'Top Digital PCM Volume': '657',
                                              'Bottom Digital PCM Volume': '0'})
        audio.earpiece_cmd = '/usr/bin/omamobile-speaker-protection'
        with patch.object(voice_audio.subprocess, 'run', run):
            with audio:
                self.assertEqual(calls, [['earpiece', 'on']])
        self.assertEqual(calls, [['earpiece', 'on'], ['earpiece', 'off']])

    def test_earpiece_mode_refused_switches_it_back_off(self):
        calls = []
        def run(args, **kwargs):
            mode = args[-1].replace('omamobile-earpiece@', '').replace('.service', '')
            calls.append(['earpiece', mode])
            class R:
                returncode = 1 if mode == 'on' else 0
                stdout = 'omamobile-speaker: refused: protection not running\n'
                stderr = ''
            return R()
        audio, changed = self.fixture()
        audio.earpiece_cmd = '/usr/bin/omamobile-speaker-protection'
        with patch.object(voice_audio.subprocess, 'run', run):
            with self.assertRaisesRegex(RuntimeError, 'earpiece mode on failed'):
                audio.__enter__()
        self.assertEqual(changed, [])
        self.assertEqual(audio.alsa.opened, 0)

    def test_unreadable_level_refuses(self):
        audio, changed = self.fixture(levels={'Top Analog PCM Volume': ''})
        self.refused(audio, changed, 'cannot read')


class CallAudioDefaultTests(unittest.TestCase):
    PACKAGED = os.path.join(os.path.dirname(__file__), '..', 'etc', 'omamobile', 'modem-sit.conf')

    def device_defaults(self, text):
        directory = tempfile.mkdtemp(dir=env.TMP)
        if text is not None:
            with open(os.path.join(directory, '50-device.conf'), 'w') as f:
                f.write(text)
        return patch.object(paths, 'DEVICE_DEFAULTS', paths.Path(directory))

    def test_no_call_audio_by_default(self):
        # No device package defaults (any phone but a verified one): no route.
        with self.device_defaults(None):
            self.assertEqual(paths.config('/nonexistent')['audio']['card'], 'none')
            self.assertEqual(paths.config(self.PACKAGED)['audio']['card'], 'none')
        self.assertIsNone(voice_audio.aoc_card('none'))

    def test_the_packaged_config_leaves_the_card_to_the_device(self):
        # A fresh install's /etc file must not override the device package's
        # default: an explicit "card = none" there gave the 7 Pro silent calls.
        with self.device_defaults('[audio]\ncard = auto\n'):
            self.assertEqual(paths.config(self.PACKAGED)['audio']['card'], 'auto')

    def test_a_broken_device_file_is_skipped(self):
        for text in ('[audio\ncard = auto\n', 'card = auto\n'):
            with self.device_defaults(text):
                self.assertEqual(paths.config(self.PACKAGED)['audio']['card'], 'none')

    def test_device_defaults_set_only_audio(self):
        with self.device_defaults('[network]\napn = example\n[audio]\ncard = auto\n'):
            settings = paths.config(self.PACKAGED)
            self.assertEqual(settings['audio']['card'], 'auto')
            self.assertEqual(settings['network']['apn'], 'auto')

    def test_a_typed_card_wins_over_the_device_default(self):
        conf = os.path.join(tempfile.mkdtemp(dir=env.TMP), 'modem-sit.conf')
        with open(conf, 'w') as f:
            f.write('[audio]\ncard = none\n')
        with self.device_defaults('[audio]\ncard = auto\n'):
            self.assertEqual(paths.config(conf)['audio']['card'], 'none')

    def test_the_7_pro_ships_auto(self):
        shipped = os.path.join(os.path.dirname(__file__), '..', '..', 'omamobile-device-cheetah', 'vendor',
                               'omamobile', 'modem-sit.conf.d', '50-cheetah.conf')
        if not os.path.exists(shipped):
            self.skipTest('not in the repository (a copy of this package alone)')
        directory = tempfile.mkdtemp(dir=env.TMP)
        shutil.copy(shipped, directory)
        with patch.object(paths, 'DEVICE_DEFAULTS', paths.Path(directory)):
            self.assertEqual(paths.config(self.PACKAGED)['audio']['card'], 'auto')

    def test_no_aoc_card_routes_nothing(self):
        with patch.object(voice_audio, 'Path') as fake:
            fake.return_value.read_text.return_value = ' 0 [Headset        ]: USB-Audio - Headset\n'
            self.assertIsNone(voice_audio.aoc_card('auto'))

    def test_tegu_detection_uses_the_selected_card_and_exact_name(self):
        cards = (' 0 [Headset ]: USB-Audio - Headset\n'
                 ' 3 [aocsndcard ]: aoc-snd-card - google,tegu-aoc-snd-card\n')
        with patch.object(voice_audio.Path, 'read_text', return_value=cards):
            self.assertEqual(voice_audio.aoc_card('auto'), 3)
            self.assertTrue(voice_audio.is_tegu_card(3))
            self.assertFalse(voice_audio.is_tegu_card(0))
        with patch.object(voice_audio.Path, 'read_text', return_value=cards.replace('tegu', 'cheetah')):
            self.assertFalse(voice_audio.is_tegu_card(3))
        with patch.object(voice_audio.Path, 'read_text', side_effect=OSError):
            self.assertFalse(voice_audio.is_tegu_card(3))


class TeguAudioTests(unittest.TestCase):
    def fixture(self, *, mismatch=None, unreadable=None, fail_params=False,
                fail_start=False, fail_close=False, fail_mixer=None, fail_mute=False):
        controls = {name: '0' for name, _ in voice_audio.TEGU_ROUTE}
        controls.update({'BUILDIN MIC ID CAPTURE LIST': '0,1,-1,-1',
                         'Top Speaker Digital Volume': '220',
                         'Bottom Speaker Digital Volume': '210'})
        original = dict(controls)
        events = []

        class Alsa:
            def __init__(self):
                self.opened = 0
                self.closed = []
                self.states = {}
                self.params = {}

            def snd_pcm_open(self, pointer, device, direction, mode):
                self.opened += 1
                pointer._obj.value = self.opened
                events.append(('open', device, direction))
                self.states[self.opened] = 0
                self.params[self.opened] = {}
                return 0

            def snd_pcm_hw_params_malloc(self, pointer):
                pointer._obj.value = 100
                return 0

            def snd_pcm_hw_params_free(self, pointer):
                events.append(('free_params', pointer.value))

            def snd_pcm_hw_params_any(self, pcm, params):
                return 0

            def __getattr__(self, name):
                if not name.startswith('snd_pcm_hw_params_set_'):
                    raise AttributeError(name)
                def setter(pcm, params, value, *direction):
                    self.params[pcm.value][name.removeprefix('snd_pcm_hw_params_set_')] = (value, direction)
                    return 0
                return setter

            def snd_pcm_hw_params(self, pcm, params):
                if fail_params and pcm.value == 2:
                    return -5
                # ALSA prepares as part of hw_params; no explicit second
                # prepare is allowed. Playback's profile resets TAS gains.
                events.append(('prepare', pcm.value))
                self.states[pcm.value] = 2
                if pcm.value == 2:
                    for name in voice_audio.TEGU_GAINS:
                        controls[name] = '220'
                return 0

            def snd_pcm_prepare(self, pcm):
                raise AssertionError('duplicate modem prepare')

            def snd_pcm_state(self, pcm):
                return self.states[pcm.value]

            def snd_pcm_start(self, pcm):
                events.append(('start', pcm.value))
                if fail_start and pcm.value == 2:
                    return -5
                self.states[pcm.value] = 3
                return 0

            def snd_pcm_drop(self, pcm):
                events.append(('drop', pcm.value))
                return 0

            def snd_pcm_close(self, pcm):
                events.append(('close', pcm.value))
                self.closed.append(pcm.value)
                return -5 if fail_close else 0

        audio = VoiceAudio.__new__(VoiceAudio)
        audio.tegu = True
        audio.card = 3
        audio.mic_boost_db = 6  # ignored on tegu: stock 130 cB only
        audio.saved, audio.pcms = [], []
        audio.alsa = Alsa()
        failed = False

        def mixer(action, name, value=None):
            nonlocal failed
            events.append((action, name, value))
            if action == 'cget':
                if controls[name] == voice_audio.TEGU_GAIN:
                    if name == unreadable:
                        return '  : values=unavailable\n'
                    if name == mismatch:
                        return '  : values=220\n'
                return '  : values=' + controls[name] + '\n'
            if name == fail_mixer and not failed:
                failed = True
                raise RuntimeError('mixer failed')
            if fail_mute and name == 'Incall Sink Mute' and value == '1':
                return ''
            controls[name] = value
            return ''

        audio.mixer = mixer
        return audio, events, controls, original

    def test_route_uses_exact_voice_params_and_checks_gain_before_unmuting(self):
        audio, events, controls, original = self.fixture()
        with audio:
            self.assertIs(audio.__enter__(), audio)  # no second PCM start
            for name, value in voice_audio.TEGU_ROUTE:
                if name != 'Incall Sink Mute':
                    self.assertEqual(controls[name], value)
            self.assertEqual(controls['MIC HW Gain At High Power Mode (cB)'], '130')
            self.assertEqual([e for e in events if e[0] == 'open'],
                             [('open', b'hw:3,11', 1), ('open', b'hw:3,4', 0)])
            self.assertEqual([e for e in events if e[0] == 'prepare'], [('prepare', 1), ('prepare', 2)])
            self.assertEqual([e for e in events if e[0] == 'start'], [('start', 1), ('start', 2)])
            expected = {'access': (3, ()), 'format': (2, ()), 'channels': (1, ()),
                        'rate_resample': (0, ()), 'rate': (8000, (0,)),
                        'period_size': (80, (0,)), 'periods': (2, (0,))}
            self.assertEqual(audio.alsa.params, {1: expected, 2: expected})
            last_start = events.index(('start', 2))
            unmute = events.index(('cset', 'Incall Sink Mute', '0'))
            for name in voice_audio.TEGU_GAINS:
                gain = events.index(('cset', name, '180'))
                read = events.index(('cget', name, None), gain)
                self.assertLess(last_start, gain)
                self.assertLess(gain, read)
                self.assertLess(read, unmute)
        self.assertEqual(audio.alsa.closed, [2, 1])
        self.assertEqual(controls, original)
        self.assertEqual(events[-1], ('cset', 'Incall Sink Mute', '0'))
        self.assertFalse(audio.saved or audio.pcms)

    def test_partial_pcm_or_mixer_failure_restores_saved_state(self):
        for failure in ({'fail_params': True}, {'fail_start': True},
                        {'fail_mixer': 'TDM_0_RX Mixer EP5'},
                        {'fail_mixer': 'Bottom Speaker Digital Volume'}):
            with self.subTest(failure=failure):
                audio, events, controls, original = self.fixture(**failure)
                with self.assertRaises(RuntimeError):
                    audio.__enter__()
                self.assertEqual(controls, original)
                self.assertEqual(len(audio.alsa.closed), audio.alsa.opened)
                self.assertFalse(audio.saved or audio.pcms)

    def test_unconfirmed_sink_mute_refuses_before_opening_pcms(self):
        audio, _, controls, original = self.fixture(fail_mute=True)
        with self.assertRaisesRegex(voice_audio.AudioRefused, 'sink mute'):
            audio.__enter__()
        self.assertEqual(audio.alsa.opened, 0)
        self.assertEqual(controls, original)

    def test_gain_mismatch_or_unreadable_gain_refuses_audio_and_closes_before_restore(self):
        for option in ('mismatch', 'unreadable'):
            for name in voice_audio.TEGU_GAINS:
                with self.subTest(option=option, control=name):
                    audio, events, controls, original = self.fixture(**{option: name})
                    with self.assertRaises(voice_audio.AudioRefused):
                        audio.__enter__()
                    # Restoring the original mute is safe only after both
                    # voice PCMs have closed; no failed route is audible.
                    unmute = events.index(('cset', 'Incall Sink Mute', '0'))
                    self.assertLess(events.index(('close', 1)), unmute)
                    self.assertEqual(controls, original)
                    self.assertEqual(audio.alsa.closed, [2, 1])

    def test_body_failure_restores_state(self):
        audio, _, controls, original = self.fixture()
        with self.assertRaisesRegex(RuntimeError, 'call failed'):
            with audio:
                raise RuntimeError('call failed')
        self.assertEqual(controls, original)
        self.assertEqual(audio.alsa.closed, [2, 1])

    def test_failed_close_keeps_sink_muted(self):
        audio, _, controls, _ = self.fixture(fail_close=True)
        audio.__enter__()
        with self.assertRaisesRegex(RuntimeError, 'PCM close'):
            audio.__exit__(None, None, None)
        self.assertEqual(controls['Incall Sink Mute'], '1')

    def test_set_output_switches_the_loudspeaker_and_the_earpiece_and_restores(self):
        audio, events, controls, original = self.fixture()
        with audio:
            self.assertEqual(audio.output, 'speaker')
            audio.set_output('earpiece')
            self.assertEqual(audio.output, 'earpiece')
            self.assertEqual(controls['Bottom Speaker Digital Volume'], '0')   # loudspeaker muted
            self.assertEqual(controls['Top Speaker Digital Volume'], voice_audio.TEGU_GAIN)
            self.assertEqual(controls['Incall Sink Mute'], '0')                 # unmuted after the switch
            audio.set_output('speaker')
            self.assertEqual(controls['Bottom Speaker Digital Volume'], voice_audio.TEGU_GAIN)
        self.assertEqual(controls, original)   # the call's end restores the pre-call gains
        with self.assertRaises(ValueError):
            audio.set_output('headset')

    def test_a_configured_earpiece_output_starts_the_call_on_the_earpiece(self):
        audio, events, controls, original = self.fixture()
        audio.output = 'earpiece'
        with audio:
            self.assertEqual(controls['Bottom Speaker Digital Volume'], '0')
            self.assertEqual(audio.output, 'earpiece')
        self.assertEqual(controls, original)

    def test_set_output_needs_a_running_route(self):
        audio, _, _, _ = self.fixture()   # pcms not opened yet
        with self.assertRaisesRegex(RuntimeError, 'no call audio is running'):
            audio.set_output('earpiece')

class EarpieceUnitTests(unittest.TestCase):
    def test_the_mode_goes_through_the_units_when_installed(self):
        audio = VoiceAudio.__new__(VoiceAudio)
        audio.earpiece_cmd = '/usr/bin/omamobile-speaker-protection'
        with patch.object(voice_audio.os.path, 'exists', return_value=True):
            self.assertEqual(audio.earpiece_argv(True), ['systemctl', 'start', 'omamobile-earpiece@on.service'])
            self.assertEqual(audio.earpiece_argv(False), ['systemctl', 'start', 'omamobile-earpiece@off.service'])
        with patch.object(voice_audio.os.path, 'exists', return_value=False):
            self.assertEqual(audio.earpiece_argv(True), [audio.earpiece_cmd, 'earpiece', 'on'])
