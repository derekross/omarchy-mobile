<!-- SPDX-License-Identifier: MIT -->
# omamobile-audio

The Pixel 7 Pro's speaker and microphones go through the AoC, the audio and
sensor DSP, whose ALSA card is `aoc-snd-card`. This package makes them a
normal PipeWire speaker ("Built-in Audio Speaker") and microphone ("Built-in
Audio Microphone"), and runs the two CS35L41 speaker amplifiers with Cirrus's
protection firmware and the phone's factory calibration, as stock Android does.

| File | What |
|---|---|
| `omamobile-speaker-protection` + `.service` (system, **not enabled by the package**) | loads the amplifier driver (or, when it is already bound, rebinds both amplifiers: a chip reset, so `systemctl restart` recovers a stuck DSP), mutes both at once, holds them out of runtime suspend (hibernation breaks the stock firmware), checks the kernel's volume limits, the stage's ceilings, the firmware and the factory calibration (`persist:/audio/speaker.cal` via debugfs, read-only), loads the protection firmware, writes `CAL_*` into both DSPs and reads it back, routes the DAC through the DSP, checks health (held awake, DSP controls present, no amplifier error in the kernel log), and only then unmutes. Any failure leaves both muted; a hang marker keeps the driver alone on the next boot. `status`, `health`, `monitor` and `verify` read the DSPs' state (coil temperature, CSPL state and errors, heartbeat), never the calibration values; `impedance` (during playback) reads the coil impedance the firmware measures, as a ratio to the factory value; `feedback start|stop|status` runs the amplifiers' VMON/IMON stream to the AoC as stock does (AOC-PLAN C9d-7); `mute` mutes |
| `omamobile-speaker-watch.service` | started with it and bound to it: mutes both amplifiers on an amplifier error in the kernel log (CSPL error, failed wake, failed resume), an amplifier no longer held awake, a level above the ceilings, or, during playback, a DSP not running the protection firmware with the calibration applied, a coil estimate above 80 C, or (stage c9 only, the stage whose analog ceiling is above 10; since 0.5.3) one that rises more than 5 C within a stream; mutes too when it stops. Writes stock's media delta at stream start; with `OMAMOBILE_SPK_FEEDBACK=1` runs the V/I feedback stream with every speaker stream |
| `udev.rules` | holds the amplifiers awake from the moment the driver binds |
| `/etc/omamobile/speaker.conf` | stage (media, the default at 737 / 10; c8 bring-up; c9 stock under verified protection), the amplifiers' levels (per amplifier too), the media delta switch (on by default when installed), DRE (on by default), the boost converter (since 0.5.3 off at analog 10 and below when the kernel's cs35l41 module has `boost_en`: in its light-load regime it droops and distorts both speakers and takes 8-11 dB off the output, AOC-PLAN C9j; `OMAMOBILE_SPK_BOOST=1|0` forces it, module-wide) |
| `modprobe.d/omamobile-audio.conf` | blacklists `snd_soc_cs35l41_spi`, so the card only comes up through the service |
| UCM2 `conf.d/aoc-snd-card`, `Google/cheetah/HiFi.conf` | HiFi verb: Speaker = AoC EP6 to TDM 0 (the amplifiers), Mic = AoC EP1 from the built-in microphones; PCMs found by id. Touches no amplifier control, so PipeWire uses software volume |
| UCM2 `conf.d/aoc-snd-card/google,tegu-aoc-snd-card.conf`, `Google/tegu/HiFi.conf` | the Pixel 9a's profile, found through the card's long name before the shared `aoc-snd-card.conf`: TDM 0 in stock's format, Speaker = EP6, Mic = EP1 from microphones 0 and 1 only (cheetah's list takes the 9a's AoC down), DC blocker and 22 dB; stock's amplifier gains (the owner's `tas2572RCA1.bin`, loaded at every playback start), without stock's processing or protection, so the WirePlumber rule caps the sink at about -10 dB |
| WirePlumber `52-omamobile-tegu-aoc.conf` | the Pixel 9a's node names, PCM settings and the speaker volume cap (`channelmix.max-volume = 0.562`, a -10 dB ceiling: the clamp applies to the master and the channel volumes, so the ceiling is the square) |
| PipeWire `60-omamobile-speaker-loudness.conf` | the speaker filter (a smart filter in front of the speaker sink only; `nofail`, so PipeWire starts without it if it can't load): an input matrix (stereo width, left/right swapped in landscape), optional bass management (the bass below a crossover, in mono, to the bottom speaker only) and bass harmonics (the bass the speakers can't play, heard through its harmonics), then per speaker a 4th-order high-pass, a low shelf, a presence dip, a treble shelf and a trim, and a look-ahead limiter per speaker at -3 dBFS. Defaults since 0.5.4, the owner's choice by ear with the boost converter off (AOC-PLAN C9j): 20 Hz high-pass, shelf and dip at 0 dB, limiter drive 6 dB, which gives streamed music (normalised 10-15 dB under a test tone) its loudness back while nothing above -3 dBFS reaches the amplifiers; `omamobile-speaker-eq preset flat` is the same with drive 0. Stock shapes the speaker sound on the AoC (Waves), which we don't send yet. Needs PipeWire's builtin `abs` (1.4 or later) |
| `omamobile-speaker-eq` (as the desktop user) | the filter's values while playing: `show` (and whether the filter is in the path), `set bass=3 dip=-3 trim_top=-2 bassmono=1 harm=0.5 drive=2 ...`, `preset default|flat|waves`, `save` (a copy under `~/.config/pipewire/pipewire.conf.d/` that replaces the package's at the next PipeWire start), `reset`, `orient` / `follow` (left and right from the phone's orientation); `measure left|right` records stepped tones with the phone's microphone (or plays them for another microphone, `--play-only`) and prints the speaker's response and harmonics (`lib/speaker_response.py`, which also has `suggest` and `compare`) |
| `omamobile-speaker-orient.service` (user unit, **not enabled**) | runs `omamobile-speaker-eq follow`: the speakers' left and right follow the phone's orientation, as stock swaps them in landscape |
| WirePlumber `51-omamobile-aoc.conf` | no mmap and 4 × 20 ms periods for the AoC PCMs (as the stock HAL), software volume only, names for the card and its nodes |

The protection firmware and the per-speaker tunings are Google's and are not
shipped: `tools/extract-vendor-firmware` copies them from the user's own
factory image to `cirrus/cs35l41-dsp1-spk-prot-cheetah{.wmfw,-top.bin,-bottom.bin}`, and
stock's media deltas to `cirrus/cs35l41-cheetah-{top,bottom}-media-delta.txt`.
The calibration never leaves the phone.

Needs the AoC running (`omamobile-aoc.service` in omamobile-device-cheetah)
and a kernel with the AoC sound card and its speaker limits. Bring-up:
`device/cheetah/AOC-PLAN.md`, stages C8, C8f and C9. The kernel should also carry `cirrus,dsp-no-hibernate`
on both amplifiers (branch `omamobile-audio-amp`); the service holds them awake
either way.
