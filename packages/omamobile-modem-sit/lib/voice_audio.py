# SPDX-License-Identifier: MIT
"""AoC call routes for the length of a call, restored when it ends.

Uses the AoC card's voice endpoints: PCM 4 playback (EP5) and PCM 11 capture
(EP4), whose numbers are the AoC entry points (AGENTS.md: the card numbers
its PCMs as stock does). AoC and CP exchange audio directly; no host
recording or SRAM mapping. Amplifier protection, calibration and gain stay
with omamobile-audio: the downlink plays through TDM 0, so it needs the
amplifiers set up (stock's TDM 0 format, protection service running).

TDM 0 feeds both amplifiers, and the top one is the earpiece. Until the
protection service has an earpiece mode (TELEPHONY-APPS-PLAN T4), routing is
refused unless the protection service reports itself running at stage
media or c8 and the amplifiers are at or below the earpiece ceiling (top
analog <= 6, AUDIO-PLAN.md section 4) and the media stage's (digital <= 737,
analog <= 10, AGENTS.md). The default config routes no call audio at all.
"""
import ctypes as C
import os
import shutil
from pathlib import Path
import re
import subprocess

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

    def __init__(self, *, mic_boost_db=6, card=None, earpiece=True):
        if mic_boost_db not in (0, 6):
            raise ValueError('unsupported voice microphone boost')
        self.mic_boost_db = mic_boost_db
        self.earpiece_cmd = shutil.which(EARPIECE_COMMAND) if earpiece else None
        if card is not None:
            self.card = card
        self.saved = []
        self.pcms = []
        self.alsa = C.CDLL('libasound.so.2')
        self.alsa.snd_pcm_open.argtypes = [C.POINTER(C.c_void_p), C.c_char_p, C.c_int, C.c_int]
        self.alsa.snd_pcm_set_params.argtypes = [C.c_void_p, C.c_int, C.c_int,
                                               C.c_uint, C.c_uint, C.c_int, C.c_uint]
        for name in ('snd_pcm_prepare', 'snd_pcm_start', 'snd_pcm_drop', 'snd_pcm_close', 'snd_pcm_state'):
            getattr(self.alsa, name).argtypes = [C.c_void_p]

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

    def __exit__(self, *args):
        failures = []
        for pcm in reversed(self.pcms):
            self.alsa.snd_pcm_drop(pcm)
            if self.alsa.snd_pcm_close(pcm) < 0:
                failures.append('PCM close')
        self.pcms.clear()
        for name, value in reversed(self.saved):
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
