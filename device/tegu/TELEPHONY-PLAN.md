<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a telephony: call audio and starting the modem at boot

Status (2026-11-02): the SIM test passed on the owner's kernel (MODEM-PLAN,
"SIM test results"): LTE registration, mobile data and texts both ways,
with the modem and the RIL started by hand. Two things stand between that
and a phone that works on its own: calls have no audio route, and nothing
starts the modem at boot. Both are planned here; nothing below has run.
Sources: the 9a's stock vendor image (`vendor_a.img` from the owner's
factory capture, read-only: the audio HAL's configuration and the AoC ALSA
driver), `packages/omamobile-modem*`, MODEM-PLAN and AGENTS.md section 4.

## 1. Call audio

### What stock does

| Direction | Stock PCM | Mixer route | Back end |
| --- | ---: | --- | --- |
| Downlink | 4, EP5 playback | `TDM_0_RX Mixer EP5` = 1 | TDM 0, the TAS2572 speakers |
| Uplink | 11, EP4 capture | `EP4 TX Mixer INTERNAL_MIC_TX` = 1 | the built-in microphones |

- Built-in microphone list 0, 1, -1, -1; the voice path turns the DC
  blocker on, sets the microphone hardware gain to 130 cB and the record
  software gain to 0 dB, selects `Builtin_MIC`, and puts the downlink ASRC
  in `ASP_ON`. TDM 0 stays at the four slots, S32_LE, 48 kHz the media
  profile already uses.
- The HAL opens the voice PCMs as mono S16_LE, 8 kHz, 80-frame periods,
  two of them. They carry no speech through userspace: they switch the
  AoC's modem path on.
- The handshake is in ALSA: preparing EP5 sends the AoC
  `TELEPHONY_MODEM_START`, closing it sends `TELEPHONY_MODEM_STOP`. The
  driver also has a conditional CPIF voice-call notifier for power
  management. No separate SIT "audio ready" request was found in the
  HAL's start path (`SET_AUDIOPATH` and `SET_AUDIO_CLK` exist in the RIL,
  but nothing shows this path needs them).

### The smallest route for one call

1. Extend `packages/omamobile-modem-sit/lib/voice_audio.py` with a tegu
   route: keep its ownership and cleanup, replace its CS35L41 protection
   and gain checks (the 9a's amplifiers are TAS2572).
2. Speakerphone first, on the working TAS playback configuration. Stock's
   earpiece path selects a separate voice amplifier profile that our setup
   doesn't expose.
3. Per call: save the mixer state, mute the call sink, set the microphone
   and the two routes, open, prepare and start the voice PCMs once; on
   hang-up or any failure restore everything.
4. Gain: set a conservative TAS attenuation after the PCMs start and read
   it back before unmuting, because the amplifier profile rewrites gains at
   start. PipeWire's -10 dB ceiling doesn't cover this direct AoC route,
   and the card's `Voice Call Rx Volume` control has no implementation, so
   it can't be the limiter.
5. Before any call: audit the AoC voice memory window. The CPIF overlay
   (`overlays/tegu-modem-cpif.dtso`) leaves it out on purpose; whether the
   running firmware needs it isn't known. Don't add a guessed mapping.

Qualification: one announced, attended speakerphone call; speech both ways;
mute and hang-up; no AoC assertion, CP reset or UFS error; media routing
restored afterwards.

### The safety gap to close first

If sitd can't confirm a call's release, its safety stop stops the modem in
place (`cp.stop_modem`). On the 9a a stop of the running modem profile by
hand hard-reset the palmtop once (MODEM-PLAN M5), and the unit it targets
(`omamobile-modem.service`) is masked here. The 9a needs its own answer
before the first call: radio off, record, and an attended reboot, never a
stop in place.

## 2. Starting the modem at boot

Opt-in and attended at first, with sleep blocked for the boot.

1. **Packaging first.** `omamobile-modem` depends on
   `omamobile-device-cheetah`, which conflicts with `omamobile-device-tegu`,
   so the 9a's install used `pacman -U -dd`. Replace the dependency with the
   virtual `omamobile-modem-policy` (already provided by device-raven), have
   each supported device package provide it, and give tegu its own start
   policy. `-dd` is never the install method.
2. **One modem service.** Give it tegu's start (today the bring-up script
   `/usr/local/bin/omamobile-tegu-modem-up` and its transient unit) with the
   AoC's ordering, and drop the copied `/etc/systemd/system/omamobile-sitd.service`
   and the transient-unit workaround. sitd starts only after an explicit
   "CP ONLINE" check: a unit being active isn't enough.
3. **Preflight before any hardware access:** the kernel, DT, firmware,
   private provisioning and board properties present; the six NV and
   firmware partitions found by `PARTNAME`, read-only, unmounted and
   matching the checksums. Today's profile hashes five RAM copies, doesn't
   hash `modem_b`, and exempts `persist` from its read-only check: the boot
   preflight closes those gaps. A mismatch stops the start; the baseline is
   never refreshed automatically.
4. **Two guards:** an atomic per-boot "attempted" marker, never cleared in
   that boot, and a persistent failure latch written and synced before any
   driver loads, kept through the whole phone-service start while this is
   being qualified. No automatic CP or sitd restart, module unload, power
   cycle or latch clearing.
5. **Sleep:** take and confirm the sleep inhibitor before the modem drivers
   load, and hold it past sitd and the profile, until shutdown. Keep the
   owner's auto-sleep setting as it is; the inhibitor blocks the sleep and
   says why. No suspend hook that stops and restarts the modem. Low-battery
   actions must not force an unqualified suspend.
6. **Failure stays visible:** the failed stage reported, diagnostics left in
   place, no retry. At shutdown, the established order: the phone service's
   cleanup, the CP off, then rfsd.

Qualification, attended and on the charger: boot to ONLINE, data and texts;
the inhibitor; NV and UFS unchanged; then shutdown and reboot on their own.
Suspend with the CP on needs its own tests, with NFC polling stopped, and
incoming texts after resume. The cost until then: the modem on blocks sleep,
so the battery drains as if awake.
