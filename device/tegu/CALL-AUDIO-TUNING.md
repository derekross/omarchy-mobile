<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a: call tuning and the first earpiece route

Status, 2026-11-03: tried on the palmtop. On 2026-11-02 (the daily kernel
`7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`, speakerphone
calls to the owner's iPhone, results at the end) the AoC accepted both
uploads, but the far end still heard its own voice. AEC is off by default,
and call audio still defaults to `card = none`. The earpiece mode below is
a conservative top-speaker route, not a reproduction of every stock codec
profile setting.

## Sources and the tuning transport

The command and its fields come from our GPL kernel on `omamobile`:
`struct CMD_AUDIO_OUTPUT_SET_PARAMETER_BULK` (ID 210) and `struct CMD_HDR`
in `drivers/soc/google/aoc/aoc-interface-gs201.h`, the character services
in `aoc_char_dev.c`, and the `Audio DSP Mode` and `FT AEC Reference Source`
controls in `alsa/aoc_alsa_ctl.c`. The tuning files themselves are the
owner's, copied unchanged from the factory image's `/vendor/etc/aoc`; no
vendor program is run or copied into the repository.

Each protobuf goes to the AoC wrapped in a 12-byte little-endian envelope,
the form stock's telephony tuning sends and the palmtop's AoC accepts
(status 0):

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | u16 | 2 (a tag; its name isn't known) |
| 2 | u16 | Total envelope plus protobuf length |
| 4 | u32 | 19 for uplink tuning, 20 for downlink tuning |
| 8 | u32 | Protobuf length |
| 12 | bytes | The protobuf, unchanged |

Both operations use AoC **block 19, component 24** on the output tuning
service (`audio_output_tuning`), not the input one. Write the envelope padded to a full
**16384-byte block** to `/dev/acd-audio_bulk_tx`, then send a **22-byte**
CMD_AUDIO_OUTPUT_SET_PARAMETER_BULK (ID 210 / `0x00d2`) record on
`/dev/acd-audio_output_tuning`:

| Bytes | Field |
| --- | --- |
| 0, 1 | `CONTAINER_HDR` type 0, counter (the AoC rewrites the counter in its reply) |
| 2–3 | u16 length 22 |
| 4–5, 6–7 | u16 command ID 210, signed i16 reply initially 0 |
| 8, 9 | u8 block 19, component 24 |
| 10–13, 14–17 | u32 TX offset 0, TX address 0 |
| 18–21 | u32 `tx_size`: the envelope length, not the padding length |

The input side has its own command, `CMD_AUDIO_INPUT_SET_PARAMETER_BULK`
(ID 234), on `audio_input_tuning`; it isn't used here. This upload needs no
bulk RX read: the reply comes back on the tuning service.

`aoc_tuning.py` implements only the two uplink/downlink operations, with
bounded nonblocking writes, one-second readiness/acknowledgement deadlines,
exact record lengths, and a reply that matches the command's type, length
and ID with a zero status. The second header byte, the counter, isn't
compared: the AoC answers with its own (0x01 sent, 0x3e back on the
palmtop), which the first version took for an unknown outcome (0.3.19).
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
manual marker deletion.

## Results on the palmtop, 2026-11-02

The daily kernel, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`,
the six files from the owner's factory image (BP3A.250905.014, matching the
palmtop's AoC firmware), `tegu_aec = yes`, `tegu_route = speaker`, calls to
the owner's iPhone, which the owner answered:

1. sitd 0.3.18 (before the counter fix): the uplink upload was accepted
   with status 0, but the reply's counter byte differed, sitd took it for an
   unknown outcome and kept the call silent, as designed.
2. 0.3.19: both uploads confirmed, audio both ways. The far end heard its
   own voice come back, as without the tuning.
3. 0.3.20, with `Audio DSP Mode` set to `Telephony_APMG3` before the
   uploads: the far end heard no echo for the first few seconds and a new
   low hiss, then the echo came back with the hiss still there.

So the uploads and the DSP mode take effect, but the cancellation doesn't
hold yet. The earpiece route hasn't been tried.

## Results on the palmtop, 2026-11-03 and 2026-11-11

Two more changes, each tried on calls to the owner's iPhone on the
speakerphone, the owner listening on the far end, `tegu_aec = yes`,
`tegu_route = speaker`, the same six files, the daily kernel as above:

4. 2026-11-03, `AoC Modem Mixer ASP Mode` set to `ASP_ON` before the
   uploads (and, in another call, stock's microphone gain): no echo for
   2 to 3 s, then the echo again, in both.
5. 2026-11-11, the tuning sent after both voice streams have started
   instead of before, with the DSP mode and `ASP_ON` as in 4 (sitd built
   on the palmtop from this stack's head merged onto that day's main, as
   0.3.37): two calls, 25 s and 14 s. The owner heard no echo for about
   the first 2 s of each and his own voice for the rest. sitd logged
   "AoC tegu speakerphone prepared at conservative TAS gain" at each
   call's start and "AoC call routes restored" at its end, and no refusal,
   so both uploads were acknowledged (an unconfirmed one keeps the call
   silent).

So nothing tried so far makes the cancellation hold: with the tuning
before or after the streams' start, with ASP on or off, the far end hears
no echo for about 2 s and then hears it. Results 3 to 5 read those first
seconds as cancellation that then stopped. The calls of 2026-11-12 below
show they are not that.

## Results on the palmtop, 2026-11-12: the first seconds are a silent uplink

The same setup (the daily kernel, sitd 0.3.37 built from this stack's
head, `tegu_aec = yes`, `tegu_route = speaker`), with
`bringup/call-audio-watch.py` running on the palmtop through each call. It
is read-only: it prints the AoC's own log (`/dev/acd-logging`) as it
arrives and, unless `CTL=0`, reads fifteen of the call's mixer controls
every half second and prints the changes. `bringup/call-levels.py` reads
its output on the laptop.

6. Four calls to the owner's iPhone, the owner in another room, and in
   the last in a far one; the watcher ran through the first three. He
   heard no echo for 3 to 4 s after answering and then his own voice, as
   before.
   - **The controls are set once and stay.** At the call's start:
     `Audio DSP Mode` `Telephony_APMG3`, `AoC Modem Mixer ASP Mode`
     `ASP_ON`, `FT AEC Reference Source` `SPEAKER`, `MIC HW Gain (cB)` 130,
     microphones 0 and 1 on. Nothing changed until the hang-up.
   - **The AoC has the tuning.** Its log has both uploads right after
     "PCIe Modem Telephony Started" (command 0x00d2 on the tuning service,
     rc 0, then "APMG3 uplink config received" and "APMG3 downlink config
     received"), with "Telephony Voice Processor enabled" and "Mixer 0
     active (APMg3)" just before. Nothing in the log changes a few
     seconds into the call.
   - **The answer is a new session.** The audio path first gets one modem
     session (the ringing; its configuration arrives about 2 s after the
     path starts, with "Modem Path Active but no configuration received"
     until then), and at the answer a second one: "Session ID changed but
     no handoff performed. Forcing FadeOut!", a new "PCIe Modem
     Configuration" with the next session number, both resamplers reset.
   - **The uplink is silent for the first 5 s of the answered session.**
     The AoC prints one uplink and one downlink sample about three times
     a second ("PCIe Session N ... Tx: ... Rx: ..."). In the first 5 s
     after each answer all sixteen uplink samples were below 80 (16-bit
     values), in the three calls, while the downlink carried the owner's voice
     at several thousand; after that the uplink had samples in the
     hundreds and thousands.
7. The same with a voice next to the palmtop: the laptop beside it counted
   aloud through the call while the owner, in the far room, said nothing.
   He heard the counting only in the room at first and through the phone
   a few counts later. The uplink samples agree: below 80 for the first
   5 s after the answer with the counting going on, then up to 2,560. So
   the uplink carries nothing in those seconds, the palmtop's own side
   included, and the "no echo" of results 3 to 6 is that silence.
8. A call with no listener: the palmtop dialled a talking clock (NIST's
   time line), nobody near it, 80 s. In the 50 s of ticks alone the uplink
   stayed below 100 in all but 5 of 156 samples; in the two voice
   announcements, a minute apart, it had samples of 21,188 and 27,913. So the echo is in the uplink the AoC sends, and it can be seen
   without anyone listening.

What this says: the APMg3 processor runs and has stock's tuning, and the
echo still passes. What it doesn't say is why, or what the 5 s of silence
are. One sample every 0.32 s is a rough level and no more.

## Next for the echo

A call to a talking clock with `call-audio-watch.py` running is now the
test, with no listener: the uplink's samples during the announcements
against those during the ticks. To do, each on a fresh boot since the
configuration is read at sitd's start:

- The same call with `tegu_aec = no`, for the echo's level without the
  tuning. If it is the same, the processor is passing the echo untouched.
- A better level than one sample in 0.32 s: stock's in-call capture
  (`Incall Capture Stream0` at `UL_DL`, the `audio_incall_cap_0` PCM),
  which nothing here has opened during a call yet.
- The speaker tuning's own layout, read from the owner's file with
  `protoc --decode_raw`: it declares a two-channel reference and three
  capture channels (the handset one a one-channel reference). Whether the
  reference the processor gets on our route is what that layout expects,
  both speakers and in step with the microphones, isn't checked.


From our kernel's AoC driver and the owner's stock configuration
(`vendor/etc/audio_platform_configuration.xml`, `mixer_paths_aidl.xml`):

- `FT AEC Reference Source` doesn't reach the AoC when set; it goes out
  with the modem microphone's start (`CMD_AUDIO_INPUT_MODEM_INPUT_START_2`,
  `ref_input_source`). With the built-in microphone, `SPEAKER` and `Default`
  both send index 0, so this control changes nothing for our calls.
- `AoC Modem Mixer ASP Mode` (block 19, component 15, the block the tuning
  goes to) read `ASP_OFF` during our calls. Stock's mixer file doesn't set
  it, so stock's HAL sets it in code if at all. `ASP_ON` during the call is
  the next thing to try, with the tuning and the DSP mode.
- Stock's telephony tuner applies the wideband tuning to narrowband voice
  (`APPLY_WB_TUNING_FOR_NB_VOICE`), so which section of the tuning applies
  may depend on the call's codec band.
- Stock also runs a telephony speaker compensation tuner with
  `compens_spk_l.conf` and `compens_spk_r.conf` (text tables of value
  pairs in the factory image's `/vendor/etc`), which we don't apply.
