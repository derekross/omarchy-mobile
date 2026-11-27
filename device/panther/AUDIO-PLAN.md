<!-- SPDX-License-Identifier: MIT -->
# Audio plan (panther / gs201): the Pixel 7 Pro's sound stack on the Pixel 7

Status (2026-11-27): **P1-P5 passed on a Pixel 7; on by default.** The
amplifier nodes are in gs201-panther, disabled (linux-omarchy-mobile, "add the
speaker amplifiers"); the overlays `audio-amps-test`, `aoc-core-test` and
`aoc-sound-test` in [`overlays/`](overlays) turn them and the AoC on, and
`device.conf` lists them. `audio-amps-test` and `aoc-sound-test` need
kernel-2026.11.24 or later, the first release with
[linux-omarchy-mobile#287](https://github.com/derekross/linux-omarchy-mobile/pull/287)
(the amplifier nodes): on an older kernel, `fdtoverlay` stops at
`audio-amps-test` with `FDT_ERR_NOTFOUND`, and the images can't be built.
Images from kernel-2026.11.24 with the default `DTB_OVERLAYS` booted on a
Pixel 7 (2026-11-27), and `tools/phone-smoke` passed every required check,
with the `googleaocsndcar` sound card and the AoC sensors up.
`omamobile-device-panther` 0.1.19 starts the AoC
with the Pixel 7 Pro's `omamobile-aoc-start`. The speakers run on the
protection firmware's default calibration (`OMAMOBILE_SPK_DEFAULT_CAL=1`,
`omamobile-audio` 0.5.16, #427/#496), as a stock Pixel 7 without
`speaker.cal` does. The P5 note below is kept as history.

Checked on 2026-11-22 on the phone, with the package built from this tree
installed: the AoC, the sound card, speaker protection and its watchdog and the
sensor proxy are active; a 1 kHz tone through the speaker, recorded by the
microphone, shows at 1 kHz about 100 times above 700 Hz and 1.3 kHz (no peak
in a recording of silence); the sensor proxy reports an accelerometer,
ambient light and proximity.

The audio hardware is the Pixel 7 Pro's (`device/cheetah/AUDIO-PLAN.md`,
`AOC-PLAN.md`), with **two differences**: the AoC board id, and **no factory
speaker calibration on this phone** (section 2). The second one blocks the
protected speakers that `omamobile-audio` runs on the 7 Pro.

Path abbreviations (all private, never committed):

- `S/` = the stock dtbo for this board, decompiled: `dtbo22`, board id
  `0x30406` rev `0x10000` (`androidboot.cdt_hwid 0x00030406…`,
  `androidboot.revision MP1.0` in this phone's `/proc/bootconfig`)
- `C/` = the Pixel 7 Pro's stock dtbo from the same OTA (`dtbo12`, board `0x30306`)
- `V/` = the stock `vendor` image of the same OTA (`CP3A.261005.002.A1`)

## 1. Same as the Pixel 7 Pro (checked)

| Item | Pixel 7 | Evidence |
|---|---|---|
| Amplifiers | two CS35L41 on `spi_7` (USI7), cs 0 = top (also the earpiece), cs 1 = bottom, prefix "R" on cs 1 in stock | `S/` fragment@90, lines 5384-5468 |
| Chip selects | gpp14-3, gpp22-1, GPIO, active low | `S/:5392` (`cs-gpios`), `:5335`, `:5357` |
| Interrupts | gpa6-3 (top), gpa8-6 (bottom), EINT, no pull; GPIO2 source 5 (push-pull, active high) | `S/:5296`, `:5303`, `:5403`, `:5438`, `:5417`, `:5453` |
| Resets | gpp17-1 (top), gpp25-2 (bottom), outputs | `S/:5341`, `:5364`, `:5404`, `:5439` |
| Bus pins | gpp14-0 CLK, gpp14-1 MOSI, gpp14-2 MISO (pull-down) | `S/:5317-5333` |
| Supplies | VA = S2MPG13 BUCKA (1.7-2.1 V, always on), VP = VSYS | `S/:5405`, `:5440`; BUCKA identical in `S/` and `C/` |
| Boost | 1000 nH, 30 uF, 3.5 A in the DT (we use 2.5 A) | `S/:5407-5409`, `:5442-5444` |
| Whole amplifier fragment | identical to the 7 Pro's except phandle numbers | `diff` of `S/:5200-5470` against `C/:5404-5674` with fragment numbers masked: only `phandle` lines and the AoC board lines differ |
| Mixer values | TDM 0 4 x 32 bit 48 kHz; RX slots top 0, bottom 1; TX top 0/2/4/6, bottom 1/3/5/7; speaker 817/17 through the DSP at 2.5 A; earpiece ASP, gain 6 (7 in calls) | `V/etc/mixer_paths.xml:37-42`, `:57-71`, `:80-99`, `:640-665`: the same values on the same lines that the 7 Pro's plan cites |
| Microphones | three (bottom, back, top), capture list 0, 3, 2 | `V/etc/audio_platform_configuration.xml:58-70`, `V/etc/mixer_paths.xml:721-728` |
| AoC rails | DMIC LDO20M, LDO19S, LDO20S 1.6-1.95 V always on; sensors LDO7S 1.6-1.95 V, LDO5S 2.5-3.3 V | the same constraints in `S/` and `C/`, so `gs201_aoc_rails` needs no change |
| Firmware names | `cs35l41-dsp1-spk-prot-panther{.wmfw,-top.bin,-bottom.bin}`, media deltas, `aoc.bin`, from `tools/extract-vendor-firmware -d panther` | the kernel's subsystem id is "panther", and `omamobile-speaker-protection` reads it from the DT |

So the kernel nodes are gs201-cheetah's with `cirrus,subsystem-id =
"panther"`, `audio-amps-test` is cheetah's (minus the PERIC0 pin controller,
already on in panther's DTS), and `aoc-sound-test` is cheetah's, byte for byte
from `/dts-v1/` on. The card keeps the name `google,aoc-snd-card`, so
`omamobile-audio`'s shared UCM profile (`conf.d/aoc-snd-card/aoc-snd-card.conf`,
the 7 Pro's HiFi and Voice Call) applies unchanged: same PCMs, same two
amplifiers, same microphone list.

## 2. Different from the Pixel 7 Pro

1. **AoC board id 0x30401** (the 7 Pro's is `0x30301`), rev `0x10000`, board
   config "P10" (7 Pro "C10"): `S/:5231-5233` against `C/:5435-5437`. Our AoC
   driver passes only the id and revision to the firmware (`aoc.c`,
   `aoc_board_config_parse()`), so `aoc-core-test` sets those two.
2. **No `speaker.cal`.** `persist:/audio` is empty on this phone, read
   read-only with `debugfs` on the phone (`/dev/sda1`, not mounted) and in the
   2026-11-03 backup after a journal replay on a private copy. Control: the
   same reads show `persist:/haptics/cs40l26.cal` (the vibration's
   calibration), and stock expects the file at the same path as on the 7 Pro
   (`V/etc/init/hw/init.pantah.rc:32-33`). Effect: `omamobile-speaker-protection
   start` stops at its calibration check and leaves both amplifiers muted (its
   design: never unprotected). Microphones do not need it (stage P4).

Not checked: whether the Pixel 7's speakers and tunings behave like the 7 Pro's
at the same levels (different phone body and speaker modules; only the stock
gains are known to be the same). `verified-firmware` has no panther line, so
`omamobile-audio` would stay at stage `media` (the lower ceilings) anyway.

## 3. Bring-up stages (each needs its own boot; ask before every boot)

Rules: one change per boot; the second terminal runs `tools/phone-ssh dmesg -w`;
**before every reboot, set the slot's tries back** (`Vol- + Power`, then
`fastboot --set-active=b`, or `bin/omamobile flash`, which does it): a hang
here costs a boot attempt. Rollback for every stage: the previous images
(`bin/omamobile flash` with the kernel output that ran before).

Build (laptop only): the kernel's DTB from `panther-sonido`, then
`DTB_OVERLAYS="<the stage's list>"` in a local copy of `device/panther/device.conf`
(not committed) and `bin/omamobile images`.

### P0 nothing enabled
DTB with the new nodes, no overlay. Pass: boots as before; `amp-va` and
`amp-vp` in `/sys/class/regulator/*/name`. **Stop if** anything else changed
in dmesg.

### P1 amplifier bus and IDs (`audio-amps-test`), nothing written
Before the boot (AGENTS: blacklist before the DTB that enables the node):

```sh
tools/phone-ssh 'echo "blacklist snd_soc_cs35l41_spi" > /etc/modprobe.d/omamobile-audio-bringup.conf'
```

Then as `device/cheetah/AUDIO-PLAN.md` A2.1 and A2.2 (same registers, same
pins): `10960000.spi` probed, `amplifier@0`/`@1` without a driver, then
spidev and `tools/cs35l41-id`. Pass: each amp `DEVID 0x00035a40`, `REVID`
low byte `0xb2`, `GLOBAL_EN 0`, or "no answer" for an amp the bootloader
keeps in reset. **Stop if** a non-zero ID other than `0x35a40`, SPI errors
or timeouts, or `GLOBAL_EN` set.

### P2 the AoC (`aoc-core-test` added)
Before the boot: install `aoc.bin` in `/usr/lib/firmware/updates`, cheetah's
`vendor/modprobe.d/omamobile-aoc.conf` (blacklists only; **not** its
`speaker_protection=1` line) and `bin/omamobile-aoc-start` by hand, no
service enabled. Then `omamobile-aoc-start`. Pass: `AoC board id 0x30401 rev
0x10000` in dmesg, `Services : N` with N > 0 in
`/sys/bus/platform/devices/181d0000.aoc/services`. **Stop if** Trusty or GSA
fail to probe, the image is refused, an AoC SysMMU fault, or no services in
15 s; if the phone hangs, the next boot finds the script's marker and leaves
the AoC off (and costs one attempt: set-active first).

### P3 the sound card (`aoc-sound-test` added)
Load the amplifier driver by hand with both muted: with PR #400
(`omamobile-speaker-protection mics`, open) or `modprobe snd_soc_cs35l41_spi`
followed at once by `amixer -c 0 cset name='Top Digital PCM Volume' 0` and the
same for Bottom. Pass: "Cirrus Logic CS35L41 (35a40), Revision: B2" and
"Subsystem ID: panther" for both, `/proc/asound/cards` lists the AoC card,
interrupt counts 0 and not rising. **Stop if** "Device ID mismatch", "OTP
Unpack failed", a rising interrupt count (`rmmod`), or no card in 30 s.

### P4 microphones (recording only, no playback)
`arecord` 5 s from the card's EP1 capture PCM, then look at the level on the
laptop. Pass: near -60 dBFS quiet, louder with speech (raven measured -64.5 and
-48 to -56 dBFS). **Stop if** silence (all zeros) or a constant full-scale signal.

### P5 speakers: blocked
History: this was the plan before the default calibration; P5 passed on
2026-11-22 (status at the top).

Needs a calibration first. Options, none designed yet: run the stock
`cs35l41-dsp1-spk-cali` firmware once at room temperature to measure each
coil (a new procedure; it plays a signal), or find where this phone's stock
keeps it. Until then, **no speaker playback**: without protection only the
limits in `device/cheetah/AUDIO-PLAN.md` section 4 apply (analog at most 10,
digital at most 657 for a first sound, 1 kHz bursts, never above 30 s, the
owner present). **High volume or bass without protection can damage the
speakers.**

## 4. Where it lives

`omamobile-device-panther` 0.1.19 ships the AoC service, the blacklists and
`omamobile-aoc-start` (the Pixel 7 Pro's, byte for byte; `test/all` checks), and
`device.conf` puts `omamobile-audio` and `omamobile-sensors` in the image.
