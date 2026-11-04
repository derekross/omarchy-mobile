<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a: call tuning and the first earpiece route

Status, 2026-11-03: **implemented and tested offline, no phone trial**.
Branch `tegu-call-audio-aec-earpiece` builds on `sitd-tegu-call-audio`
(`d826388`); omamobile-modem-sit 0.3.13. AEC is off by default and call
audio still defaults to `card = none`. The earpiece mode below is a
conservative top-speaker route, not a reproduction of every stock codec
profile setting. This note records the remaining distinction explicitly.

## Sources and the tuning transport

Read the owner's saved 9a audio HAL, its AoC utility library, mixer paths,
platform configuration and factory-image `/vendor/etc/aoc` files as data.
No vendor program was run or copied into the repository. Compare the
functional interface with our GPL kernel at
[`253ddb231a89792ea845549c55fb0f04536c9317`](https://github.com/derekross/linux-omarchy-mobile/tree/253ddb231a89792ea845549c55fb0f04536c9317):
`drivers/soc/google/aoc/aoc-interface-gs201.h`, `aoc_char_dev.c`,
`alsa/aoc_alsa_ctl.c`, `alsa/aoc_alsa_hw.c`, and
`sound/soc/codecs/tas2781-{i2c,fmwlib}.c` / `include/sound/tas2x20-tlv.h`.
The kernel worktree is `~/android/mainline/wt-call-test`.

Stock uses the `fmapmg3hybrid` telephony tuner. Its APMg3 adapter wraps
an unchanged protobuf with this **12-byte little-endian envelope**:

| Offset | Type | Meaning used by the adapter |
| --- | --- | --- |
| 0 | u16 | 2 (envelope tag; its semantic name is not established here) |
| 2 | u16 | Total envelope plus protobuf length |
| 4 | u32 | 19 for uplink tuning, 20 for downlink tuning |
| 8 | u32 | Protobuf length |
| 12 | bytes | Original protobuf |

Both operations use AoC address **block 19, component 24, address type 0**.
In `AocTuningCommands::SetParameterBulk`, type 0 selects
**`audio_output_tuning`**, not `audio_input_tuning`: block/component names
do not select the character channel. Write the envelope padded to a full
**16384-byte block** to `/dev/acd-audio_bulk_tx`, then send a **22-byte**
CMD_AUDIO_OUTPUT_SET_PARAMETER_BULK (ID 210 / `0x00d2`) record on
`/dev/acd-audio_output_tuning`:

| Bytes | Field |
| --- | --- |
| 0, 1 | CMD type 0, counter |
| 2–3 | u16 length 22 |
| 4–5, 6–7 | u16 command ID 210, signed i16 reply initially 0 |
| 8, 9 | u8 block 19, component 24 |
| 10–13, 14–17 | u32 TX offset 0, TX address 0 |
| 18–21 | u32 envelope length, not the padding length |

Stock's utility has a separate type-1 family using `audio_input_tuning`,
`audio_input_bulk_tx/rx`, ID 234 and a 5120-byte staging buffer. That is
not the APMg3 upload described above. Stock opens the output bulk RX service
as part of its generic descriptor set; this write-only implementation
needs no bulk RX read. The tuning reply comes back on the tuning service.

`aoc_tuning.py` implements only the two uplink/downlink operations, with
bounded nonblocking writes, one-second readiness/acknowledgement deadlines,
exact record lengths, command/counter matching and a zero reply required.
It never resumes a short record, retries an unknown command, maps SRAM or
opens the CP/AoC shared voice window. `aoc_char_dev` makes the service
opens exclusive. An uncertain write/reply leaves the private RAM marker
`/run/omamobile-sit/aoc-voice-tuning-uncertain`; later tuning attempts refuse.
The unit already preserves its runtime directory. Do not delete the marker
to retry on the same AoC session.

**Echo reference is a separate ALSA step.**
`VoiceCall::EchoReferencePath::Set` selects **FT AEC Reference Source =
SPEAKER** for the speaker and handset paths. Our kernel's setter caches
that choice; `aoc_audio_modem_mic_input()` uses it as the reference input
when constructing MODEM_INPUT_START_2. Set it before EP4 capture starts.
Its saved value is restored after the PCMs stop. There is no additional SIT
request. The existing EP4/EP5 preparation starts the modem voice path.

`SendCommonCommand` is not the AEC protobuf transport. Its observed caller
here toggles **microphone compensation** with input-family command 355/356,
using an eight-byte CMD_HDR. Sending those would enable a different feature;
the implementation does not send them. The complete stock hybrid tuner's
band, volume and processing-mode policy is outside this first loader.
Actual echo cancellation still needs a far-end listening test.

## Files and lifecycle

`tools/extract-vendor-firmware -d tegu` now copies these six owner files
unchanged into **`usr/lib/firmware/updates/omamobile/tegu/aoc/`** in its
output tree, included in `vendor-firmware.sha256`:

| Route | Uplink on | Uplink cleanup | Downlink |
| --- | --- | --- | --- |
| Speakerphone | `uplink_speaker_aec_on_config.pb` | `uplink_speaker_aec_off_config.pb` | `downlink_speaker_config.pb` |
| Earpiece | `uplink_handset_aec_on_config.pb` | `uplink_handset_aec_off_config.pb` | `downlink_handset_config.pb` |

The source is `/vendor/etc/aoc/` in the owner's own 9a image. Do not use
another device's protobufs. HAC, wired, Bluetooth, dock and external-speaker
configs are unnecessary for these two routes. Missing any of these six
fails extraction. The loader requires the selected route's on, off and
downlink files before any upload. Files are not shipped in the package.

With `[audio] tegu_aec = yes`, the route first saves the mixer state and
verifies sink mute, sets the echo reference, uploads uplink-on and downlink,
and starts capture/playback once with the existing voice parameters. It
then applies and reads back the amplifier attenuation before unmuting.
Hang-up mutes, stops both PCMs, sends the same route's uplink-off package,
closes the tuning services and restores the mixers. **This turns AEC off;
it does not claim to restore an unknown previous protobuf**, and leaves the
selected downlink tuning resident in the inactive telephony component.

A missing or refused tuning setup refuses audio while call signalling
continues. Unknown setup or failed cleanup leaves the sink muted; the CP
is never stopped or reset. Tests cover cleanup, stale/mismatched/negative
acknowledgements, short writes and an unknown outcome blocking another call.

## Earpiece mapping and the limit of the stock comparison

The stock GPL TAS parser is
[Google amplifiers `33976d763bc0ace11603e7ecb207fc2b6e3f2608`](https://android.googlesource.com/kernel/google-modules/amplifiers/+/33976d763bc0ace11603e7ecb207fc2b6e3f2608/tas25xx/src/tas25xx-regbin-parser.c).
It builds playback-volume controls from the image's KCNTR table; values
are table indices, not decibels. A bounded private inspection of the owner's
table, following that parser, established:

| Stock setting | Mainline mapping / implementation |
| --- | --- |
| PLAYBACK_VOLUME_LEFT = 55 | Its coefficient matches **tas2x20 DVC index 220 (unity)**, not index 55. Use a lower first-test level: **Top Speaker Digital Volume = 160 (-30 dB)** |
| Top amplifier only | **Bottom Speaker Digital Volume = 0**, read back before unmuting. This is the table's minimum (-110 dB), not power-off or a hardware mute |
| CODEC PROFILE = voice | Mainline exposes per-amplifier **Speaker Profile Id**, not the vendor enum. The examined native RCA's index **4** is `case05-voice-handset`, but that case contains only one power-state write. It lacks profile 0's full initialization. Selecting 4 on a fresh, uninitialized amplifier is not a complete voice route |
| EM LEFT/RIGHT = OFF | Mainline has **no EM mixer control**. The stock driver writes bits 7:6 of register 0:0:3. The examined full native profile 0 writes EM off; no userspace register write or invented control is added |
| AoC Modem Sink Channel Bitmap | **Read-only**: its SOC_SINGLE_EXT has a get handler and NULL put. It reports a sink's active channel bitmap; it is not a writable TDM-slot selector in this kernel |

For the first usable top-only mode, retain the existing **full profile 0**
on both amplifiers, load handset AEC/downlink tuning, and attenuate/mute as
above. Refuse earpiece audio if the selected amplifier profiles are not 0,
or AEC was not enabled. This keeps startup on the already working native
initialization instead of treating a profile label as sufficient evidence.
Only the top is intended to be audible; the bottom still powers up.
Exact stock voice-profile and per-amplifier EM control remain a separate
firmware/kernel task if needed after this route is qualified. Gains have
not been acoustically qualified at the ear.

Configuration (changes apply on the next **fresh CP** session):

```ini
[audio]
card = none
tegu_aec = no
tegu_route = speaker
```

The attended trial chooses `card = auto`, `tegu_aec = yes`, then `speaker`
or `earpiece`. The earpiece mode does not affect the 7 Pro's CS35L41 route;
there is no mid-call route switch in this change. Do not enable it globally.

## Verification and the attended gate

Laptop checks, risk **low**, with synthetic service records and an ext4
fixture containing fictional data only:

```sh
tests/packages omamobile-modem-sit
tests/extract-tegu-call-tuning
tools/pr-check d826388
```

Expect: all package tests, including the existing cheetah route and sit-sim
calls/SMS, pass; six synthetic tuning files are copied byte-for-byte and
checksummed; missing cleanup tuning fails; the PR gate passes. Stop on a
failure. Rollback is the parent branch or removal of this isolated
worktree. Nothing contacts the phone or executes the saved HAL.

Before any phone trial, the human reviews a device-specific runbook and
approves the install and fresh boot. First **read-only**, confirm the NV
backup checksums, exact daily kernel/modules, mixer control availability,
profile files and their checksums, and no active call/PCMs. Keep the modem's
sleep inhibitor and once-per-boot rule. Record the actual `uname -r` with
results; no phone kernel release is claimed for these offline checks.

Then test **speaker AEC only first**, with live kmsg streamed to the laptop,
a watchdog and the human ready to recover. Check command replies, gain
readbacks, two-way audio and the far end's echo before trying the earpiece
on another approved fresh session. Risk **medium**: new AoC tuning and an
unqualified acoustic path. Begin the earpiece test away from the ear at the
fixed attenuation. Stop on an AoC timeout/reset, any NV/UFS error,
unexpected gain, feedback, missing bottom attenuation or unconfirmed
cleanup. Hang up and retain the mute/uncertainty state. Never retry or reset
the running CP in place. Rollback is the previous package/config on an
attended fresh boot; no automatic unit restart, warm modem restart or
manual marker deletion. Hardware results: **not run**.
