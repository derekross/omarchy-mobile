# SPDX-License-Identifier: MIT
"""AoC call routes for the length of a call, restored when it ends.

Uses the AoC card's voice endpoints: PCM 4 playback (EP5) and PCM 11 capture
(EP4), whose numbers are the AoC entry points (AGENTS.md: the card numbers
its PCMs as stock does). AoC and CP exchange audio directly; no host
recording or SRAM mapping. On cheetah, amplifier protection, calibration
and gain stay with omamobile-audio: TDM 0 needs its amplifiers set up and
the protection service running.

TDM 0 feeds both amplifiers, and the top one is the earpiece. With the
protection service's earpiece mode (AOC-PLAN.md C9k) each call runs in that
mode; without it, routing is refused unless the protection service reports
itself running at stage media or c8 and the amplifiers are at or below the
earpiece ceiling (top analog <= 6, AUDIO-PLAN.md section 4) and the media
stage's (digital <= 737, analog <= 10, AGENTS.md). The built-in default
routes no call audio; a device package whose route is verified sets
[audio] card = auto in its defaults (paths.DEVICE_DEFAULTS). Tegu instead
uses its TAS2572 speakerphone path, muted until both amplifiers read back a
conservative gain after PCM start.
"""
import ctypes as C
import os
import shutil
from pathlib import Path
import re
import subprocess

from aoc_tuning import TuningError, VoiceTuning

# omamobile-speaker-protection's status line ("ok: stage <stage>, ...").
PROTECTION = Path(os.environ.get('OMAMOBILE_SPK_STATUS', '/run/omamobile/speaker-protection'))
STAGES = ('media', 'c8')
# (control, ceiling): the earpiece ceiling for the top amplifier, the media
# stage's for both (AUDIO-PLAN.md section 4, AGENTS.md "Speakers").
CEILINGS = (('Top Analog PCM Volume', 6), ('Bottom Analog PCM Volume', 10),
            ('Top Digital PCM Volume', 737), ('Bottom Digital PCM Volume', 737))
# In the protection service's earpiece mode (omamobile-speaker-protection
# earpiece on, AOC-PLAN.md C9k: the top amplifier alone at 657/6 through
# ASP, the bottom muted at Digital PCM Volume 0) the stage no longer
# matters: the top is at the earpiece level and the bottom carries nothing.
EARPIECE_CEILINGS = (('Top Analog PCM Volume', 6), ('Top Digital PCM Volume', 737),
                     ('Bottom Digital PCM Volume', 0))
EARPIECE_COMMAND = 'omamobile-speaker-protection'
# The mode is switched through omamobile-earpiece@on|off.service, which run
# the command with /etc/omamobile/speaker.conf's environment (the stage):
# run bare from sitd, "earpiece off" restored another stage's levels and
# the watchdog stopped, muting the speakers (2026-11-03).
EARPIECE_UNIT = '/usr/lib/systemd/system/omamobile-earpiece@.service'

TEGU_CARD = 'google,tegu-aoc-snd-card'
# tas2x20_dvc_table in include/sound/tas2x20-tlv.h: index 220 is unity,
# index 180 is -20 dB. Use the index, not the control's misleading dB TLV.
TEGU_GAIN = '180'
TEGU_EARPIECE_GAIN = '160'  # -30 dB; stock index 55 maps to unity (220)
TEGU_GAINS = ('Top Speaker Digital Volume', 'Bottom Speaker Digital Volume')
TEGU_ROUTE = (
    ('Incall Sink Mute', '1'),
    ('TDM_0_RX Chan', 'Four'), ('TDM_0_RX Format', 'S32_LE'),
    ('TDM_0_RX Sample Rate', 'SR_48K'),
    ('TDM_0_TX Chan', 'Four'), ('TDM_0_TX Format', 'S32_LE'),
    ('TDM_0_TX Sample Rate', 'SR_48K'),
    ('BUILDIN MIC ID CAPTURE LIST', '0,1,-1,-1'), ('MIC DC Blocker', '1'),
    ('Voice Call Audio Enable', '1'), ('Voice Call Mic Source', '1'),
    ('Voice Call Mic Mute', '0'), ('Incall Mic Mute', '0'),
    ('AoC Modem Downlink ASRC Mode', '1'),
    ('MIC HW Gain At High Power Mode (cB)', '130'),
    ('MIC Record Soft Gain (dB)', '0'),
    ('TDM_0_RX Mixer EP5', '1'), ('EP4 TX Mixer INTERNAL_MIC_TX', '1'))


class AudioRefused(RuntimeError):
    """A tegu route was safely unwound; signalling may continue silently."""


def is_tegu_card(card):
    try:
        for line in Path('/proc/asound/cards').read_text().splitlines():
            match = re.match(r'\s*(\d+)\s+\[[^]]+\]:\s*.*? - (\S+)\s*$', line)
            if match and int(match[1]) == card:
                return match[2] == TEGU_CARD
    except OSError:
        pass
    return False


def aoc_card(setting='auto'):
    """The AoC card's index: the configured one, the card whose ALSA id or
    name mentions the AoC (/proc/asound/cards), or None for "none" (calls
    connect without routing any audio: for diagnosis and the tests)."""
    if setting == 'none':
        return None
    if setting not in ('', 'auto'):
        return int(setting)
    try:
        for line in Path('/proc/asound/cards').read_text().splitlines():
            match = re.match(r'\s*(\d+)\s+\[(\S+)\s*\]:\s*(.*)', line)
            if match and 'aoc' in (match[2] + match[3]).lower():
                return int(match[1])
    except OSError:
        pass
    # No AoC card: route nothing rather than guess another card's index.
    return None


class VoiceAudio:
    card = 0
    # the protection service's earpiece command, None when the route runs
    # without earpiece mode (no service installed, or [audio] earpiece = no)
    earpiece_cmd = None

    def __init__(self, *, mic_boost_db=6, card=None, earpiece=True, tegu_route='speaker', tegu_aec=False):
        if mic_boost_db not in (0, 6):
            raise ValueError('unsupported voice microphone boost')
        self.mic_boost_db = mic_boost_db
        self.earpiece_cmd = shutil.which(EARPIECE_COMMAND) if earpiece else None
        if card is not None:
            self.card = card
        self.tegu = is_tegu_card(self.card)
        if self.tegu:
            # The protection service's earpiece mode is the 7 Pro's CS35L41
            # route; the 9a's TAS2572 route sets its own gains.
            self.earpiece_cmd = None
        if tegu_route not in ('speaker', 'earpiece'):
            raise ValueError('unsupported tegu call route')
        self.tegu_route = tegu_route
        self.tegu_aec = tegu_aec
        self.tuning = None
        self.saved = []
        self.pcms = []
        self.alsa = C.CDLL('libasound.so.2')
        self.alsa.snd_pcm_open.argtypes = [C.POINTER(C.c_void_p), C.c_char_p, C.c_int, C.c_int]
        self.alsa.snd_pcm_set_params.argtypes = [C.c_void_p, C.c_int, C.c_int,
                                               C.c_uint, C.c_uint, C.c_int, C.c_uint]
        for name in ('snd_pcm_prepare', 'snd_pcm_start', 'snd_pcm_drop', 'snd_pcm_close', 'snd_pcm_state'):
            getattr(self.alsa, name).argtypes = [C.c_void_p]
        if self.tegu:
            self.alsa.snd_pcm_hw_params_malloc.argtypes = [C.POINTER(C.c_void_p)]
            self.alsa.snd_pcm_hw_params_free.argtypes = [C.c_void_p]
            for name in ('snd_pcm_hw_params_any', 'snd_pcm_hw_params'):
                getattr(self.alsa, name).argtypes = [C.c_void_p, C.c_void_p]
            for name in ('access', 'format', 'channels', 'rate_resample'):
                getattr(self.alsa, 'snd_pcm_hw_params_set_' + name).argtypes = [
                    C.c_void_p, C.c_void_p, C.c_uint]
            for name in ('rate', 'periods', 'period_size'):
                getattr(self.alsa, 'snd_pcm_hw_params_set_' + name).argtypes = [
                    C.c_void_p, C.c_void_p, C.c_ulong if name == 'period_size' else C.c_uint,
                    C.c_int]

    def mixer(self, action, name, value=None):
        args = ['amixer', '-c', str(self.card), action, 'name='+name]
        if value is not None:
            args.append(value)
        result = subprocess.run(args, capture_output=True, text=True, timeout=10)
        if result.returncode:
            raise RuntimeError('voice mixer operation failed: '+name)
        return result.stdout

    @staticmethod
    def check(code, operation):
        if code < 0:
            raise RuntimeError('voice PCM '+operation+' failed: '+str(code))

    def earpiece_argv(self, on):
        mode = 'on' if on else 'off'
        if os.path.exists(EARPIECE_UNIT):
            return ['systemctl', 'start', f'omamobile-earpiece@{mode}.service']
        return [self.earpiece_cmd, 'earpiece', mode]

    def earpiece(self, on):
        """The protection service's earpiece mode around the route: on
        before the levels are checked, off after the route is restored."""
        result = subprocess.run(self.earpiece_argv(on), capture_output=True, text=True, timeout=90)
        if result.returncode:
            raise RuntimeError('earpiece mode ' + ('on' if on else 'off') + ' failed: '
                               + (result.stdout + result.stderr).strip().splitlines()[-1:][0]
                               if (result.stdout + result.stderr).strip() else
                               'earpiece mode ' + ('on' if on else 'off') + ' failed')

    def check_levels(self):
        """Refuse call audio unless the amplifiers are under protection and
        within the earpiece and media ceilings: in the service's earpiece
        mode (any stage) the top at the earpiece level and the bottom
        muted, otherwise stage media or c8 within every ceiling. Reads only."""
        try:
            status = PROTECTION.read_text().strip()
        except OSError:
            status = ''
        earpiece = status.startswith('ok: stage ') and ', mode earpiece:' in status
        if not earpiece and not any(status.startswith(f'ok: stage {stage},') for stage in STAGES):
            raise RuntimeError('call audio refused: speaker protection is not running at stage media or c8')
        for name, ceiling in (EARPIECE_CEILINGS if earpiece else CEILINGS):
            match = re.search(r'^\s*: values=([0-9,]+)$', self.mixer('cget', name), re.M)
            if match is None:
                raise RuntimeError('call audio refused: cannot read ' + name)
            if max(int(v) for v in match[1].split(',')) > ceiling:
                raise RuntimeError(f'call audio refused: {name} is above {ceiling} '
                                   '(the earpiece ceiling needs the top amplifier at analog 6 or less)')

    def __enter__(self):
        if getattr(self, 'tegu', False):
            return self.tegu_enter()
        if self.earpiece_cmd:
            self.earpiece(True)
        try:
            self.check_levels()
        except BaseException:
            if self.earpiece_cmd:
                try:
                    self.earpiece(False)
                except (OSError, RuntimeError, subprocess.TimeoutExpired):
                    pass
            raise
        try:
            for name, value in (
                    ('Voice Call Audio Enable', '1'), ('Voice Call Mic Source', '1'),
                    ('Voice Call Mic Mute', '0'), ('Incall Mic Mute', '0'),
                    ('Incall Sink Mute', '0'), ('AoC Modem Downlink ASRC Mode', '1'),
                    # Stock gain is 130 cB; the user-confirmed normal-call
                    # default adds 6 dB, below the 240 cB hardware maximum.
                    ('MIC HW Gain At High Power Mode (cB)', str(130 + 10*self.mic_boost_db)),
                    ('MIC Record Soft Gain (dB)', '0'),
                    ('TDM_0_RX Mixer EP5', '1'), ('EP4 TX Mixer INTERNAL_MIC_TX', '1')):
                output = self.mixer('cget', name)
                match = re.search(r'^\s*: values=([0-9,\-]+|on|off)$', output, re.M)
                if match is None:
                    raise RuntimeError('voice mixer state unavailable: '+name)
                self.saved.append((name, match[1]))
                self.mixer('cset', name, value)
            # Have capture ready before playback prepare starts the modem.
            for device, direction in ((11, 1), (4, 0)):
                pcm = C.c_void_p()
                self.check(self.alsa.snd_pcm_open(C.byref(pcm), f'hw:{self.card},{device}'.encode(), direction, 0), 'open')
                self.pcms.append(pcm)
                # S16_LE, RW_INTERLEAVED, 2ch/48kHz, 80ms, no resampling.
                self.check(self.alsa.snd_pcm_set_params(pcm, 2, 3, 2, 48000, 0, 80000), 'params')
                # set_params normally leaves ALSA PREPARED. Avoid sending
                # duplicate TELEPHONY_MODEM_START commands through prepare.
                if self.alsa.snd_pcm_state(pcm) != 2:
                    self.check(self.alsa.snd_pcm_prepare(pcm), 'prepare')
                self.check(self.alsa.snd_pcm_start(pcm), 'start')
            print('AoC voice playback and capture prepared', flush=True)
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def mixer_value(self, name):
        match = re.search(r'^\s*: values=([0-9,\-]+|on|off)$', self.mixer('cget', name), re.M)
        if match is None:
            raise RuntimeError('voice mixer state unavailable: ' + name)
        return match[1]

    def tegu_params(self, pcm):
        params = C.c_void_p()
        self.check(self.alsa.snd_pcm_hw_params_malloc(C.byref(params)), 'params allocation')
        try:
            self.check(self.alsa.snd_pcm_hw_params_any(pcm, params), 'params reset')
            for name, value, direction in (
                    ('access', 3, None), ('format', 2, None), ('channels', 1, None),
                    ('rate_resample', 0, None), ('rate', 8000, 0),
                    ('period_size', 80, 0), ('periods', 2, 0)):
                args = (pcm, params, value) + (() if direction is None else (direction,))
                self.check(getattr(self.alsa, 'snd_pcm_hw_params_set_' + name)(*args), name)
            # hw_params prepares automatically. Never prepare a second time:
            # preparing EP5 sends TELEPHONY_MODEM_START to the AoC.
            self.check(self.alsa.snd_pcm_hw_params(pcm, params), 'params')
            if self.alsa.snd_pcm_state(pcm) != 2:
                raise RuntimeError('voice PCM was not prepared by hardware parameters')
        finally:
            self.alsa.snd_pcm_hw_params_free(params)

    def tegu_enter(self):
        if self.pcms:
            return self
        # Read everything before changing anything. Mute is first so its
        # original value is restored last, after closing the voice PCMs.
        route = list(TEGU_ROUTE)
        aec = getattr(self, 'tegu_aec', False)
        earpiece = getattr(self, 'tegu_route', 'speaker') == 'earpiece'
        if earpiece:
            if not aec:
                raise AudioRefused('tegu earpiece needs the handset AEC tuning enabled')
            # The supplied RCA voice-handset case is only a delta, not a
            # standalone initialization. Retain the full profile 0 for
            # this conservative top-only route, never guess profile 4.
            try:
                profiles = [self.mixer_value(amp + ' Speaker Profile Id') for amp in ('Top', 'Bottom')]
            except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                raise AudioRefused('tegu earpiece amplifier profile unavailable') from error
            if profiles != ['0', '0']:
                raise AudioRefused('tegu earpiece requires the full amplifier profile 0')
        if aec:
            route.insert(1, ('FT AEC Reference Source', 'SPEAKER'))
            # The output DSP stays in Ambient unless told otherwise, and the
            # uploaded tuning is for its APMg3 telephony mode.
            route.insert(2, ('Audio DSP Mode', 'Telephony_APMG3'))
            # The modem mixer's signal processing (block 19, where the tuning
            # goes) read ASP_OFF during our calls, with the echo coming back.
            route.insert(3, ('AoC Modem Mixer ASP Mode', 'ASP_ON'))
        names = [name for name, _ in route] + list(TEGU_GAINS)
        try:
            saved = [(name, self.mixer_value(name)) for name in names]
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            raise AudioRefused('tegu call mixer state unavailable') from error
        self.saved = saved
        try:
            for name, value in route:
                self.mixer('cset', name, value)
                if name == 'Incall Sink Mute' and self.mixer_value(name) not in ('1', 'on'):
                    raise AudioRefused('tegu call audio refused: sink mute read-back mismatch')
            # Capture is ready before playback prepare starts the modem.
            for device, direction in ((11, 1), (4, 0)):
                pcm = C.c_void_p()
                self.check(self.alsa.snd_pcm_open(C.byref(pcm), f'hw:{self.card},{device}'.encode(),
                                               direction, 0), 'open')
                self.pcms.append(pcm)
                self.tegu_params(pcm)
                self.check(self.alsa.snd_pcm_start(pcm), 'start')
            # The tuning goes up once the call's streams have started: the
            # AoC starts its voice path at the playback start ("Start voice
            # call"), and with the tuning sent before that the echo was gone
            # for 2-3 s only (2026-11-03). The sink is still muted here.
            if aec:
                try:
                    self.tuning = VoiceTuning(self.tegu_route)
                    self.tuning.start()
                except (OSError, TuningError) as error:
                    raise AudioRefused('tegu call audio refused: AoC tuning unavailable or unconfirmed') from error
            # The codec profile resets gain at playback start. These must
            # happen afterwards, while the modem downlink remains muted.
            gains = ((TEGU_GAINS[1], '0'), (TEGU_GAINS[0], TEGU_EARPIECE_GAIN)) if earpiece else tuple(
                (name, TEGU_GAIN) for name in TEGU_GAINS)
            for name, gain in gains:
                self.mixer('cset', name, gain)
            for name, expected in gains:
                try:
                    gain = self.mixer_value(name)
                except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                    raise AudioRefused('tegu call audio refused: TAS gain read-back unavailable') from error
                if gain != expected:
                    raise AudioRefused('tegu call audio refused: TAS gain read-back mismatch')
            self.mixer('cset', 'Incall Sink Mute', '0')
            print('AoC tegu ' + ('earpiece' if earpiece else 'speakerphone') +
                  ' prepared at conservative TAS gain', flush=True)
            return self
        except BaseException as error:
            try:
                self.__exit__(None, None, None)
            except RuntimeError as cleanup:
                if isinstance(error, AudioRefused):
                    raise AudioRefused('tegu call audio refused; cleanup unconfirmed, sink remains muted') from cleanup
                raise
            raise

    def __exit__(self, *args):
        failures = []
        if getattr(self, 'tegu', False) and self.saved:
            try:
                self.mixer('cset', 'Incall Sink Mute', '1')
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                failures.append('Incall Sink Mute')
        for pcm in reversed(self.pcms):
            if self.alsa.snd_pcm_drop(pcm) < 0 and getattr(self, 'tegu', False):
                failures.append('PCM drop')
            if self.alsa.snd_pcm_close(pcm) < 0:
                failures.append('PCM close')
        self.pcms.clear()
        if getattr(self, 'tuning', None) is not None:
            try:
                self.tuning.close()
            except (OSError, TuningError):
                failures.append('AoC tuning cleanup')
            finally:
                self.tuning = None
        for name, value in reversed(self.saved):
            if getattr(self, 'tegu', False) and name == 'Incall Sink Mute' and failures:
                continue  # uncertain cleanup must leave the call sink muted
            try:
                self.mixer('cset', name, value)
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                failures.append(name)
        self.saved.clear()
        if self.earpiece_cmd:
            try:
                self.earpiece(False)
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                failures.append('earpiece mode off')
        if failures:
            raise RuntimeError('voice cleanup failed: '+', '.join(failures))
        print('AoC call routes restored', flush=True)
