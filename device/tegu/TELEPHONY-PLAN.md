<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a telephony: call audio and starting the modem at boot

Status (2026-11-03): the SIM test passed on the owner's kernel (MODEM-PLAN,
"SIM test results"), and both parts of this plan have since run on the
palmtop on 2026-11-02 (the daily kernel,
`7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`): speakerphone
calls with audio both ways through section 1's route (#367), and a cold
boot that started the modem and the phone service on its own through
#372's opt-in unit. Section 2 marks which items #363 and #372 do and which
remain targets.
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

1. **Packaging first.** *Done in #363.* `omamobile-modem` depends on
   `omamobile-device-cheetah`, which conflicts with `omamobile-device-tegu`,
   so the 9a's install used `pacman -U -dd`. Replace the dependency with the
   virtual `omamobile-modem-policy` (already provided by device-raven), have
   each supported device package provide it, and give tegu its own start
   policy. `-dd` is never the install method.
2. **One modem service.** *Partly in #372:* `omamobile-tegu-modem-up` is
   packaged, with the explicit CP ONLINE check and an opt-in boot unit, and
   #371 replaces the copied sitd unit with device drop-ins. *Target:* tegu's
   start as one modem service with the AoC's ordering, in place of the
   transient unit `omamobile-tegu-modem-up` runs the profile in, and no
   copied `/etc/systemd/system/omamobile-sitd.service` or transient-unit
   workaround on any palmtop. sitd starts only after an explicit
   "CP ONLINE" check: a unit being active isn't enough.
3. **Preflight before any hardware access:** *Target.* #372 runs the
   profile's own check (NV read-only, unmounted, checksums of its RAM
   copies), after the drivers load because it needs CPIF's ports; the
   up-front NV-only check and the gaps below are still to do: the kernel,
   DT, firmware, private provisioning and board properties present, and the
   six NV and firmware partitions found by `PARTNAME`, read-only, unmounted
   and matching the checksums. Today's profile hashes five RAM copies, doesn't
   hash `modem_b`, and exempts `persist` from its read-only check: the boot
   preflight closes those gaps. A mismatch stops the start; the baseline is
   never refreshed automatically.
4. **Two guards:** *Partly in #372:* a boot that has loaded CPIF refuses a
   second start, and the latch is written and synced before any driver and
   kept from ONLINE until a clean shutdown. *Target:* an atomic per-boot
   "attempted" marker, never cleared in that boot, and the failure latch
   kept through the whole phone-service start while this is being
   qualified. No automatic CP or sitd restart, module unload, power
   cycle or latch clearing.
5. **Sleep:** *Done in #372:* the sleep inhibitor is taken and confirmed
   before the modem drivers load, and held past sitd and the profile until
   the reboot. Keep the
   owner's auto-sleep setting as it is; the inhibitor blocks the sleep and
   says why. No suspend hook that stops and restarts the modem. Low-battery
   actions must not force an unqualified suspend.
6. **Failure stays visible:** *Partly in #372:* the stage is reported and
   the latch stays after a failed start, with no retry. *Target:*
   diagnostics left in place, and the shutdown order through one modem
   service: the phone service's cleanup, the CP off, then rfsd.

### 2.7 Enabling the boot start (gated runbook, #372)

Attended, on the charger, one step per boot. Preconditions: slot B marked
successful, a kernel with linux-omarchy-mobile#172, an off-repo NV backup.

| Step / risk | Commands | Expect / pass | Stop condition | Rollback |
| --- | --- | --- | --- | --- |
| 1. Read-only / none | `uname -r`; `pacman -Q omamobile-device-tegu omamobile-modem omamobile-modem-sit omamobile-mmd`; `tools/nv-backup --check "$NV_BACKUP"` (laptop); `ls /var/lib/omamobile/modem-bringup-started` | The kernel and packages recorded, NV matches, no latch | NV mismatch, a latch present, B not marked | None |
| 2. Enable / low | `systemctl enable omamobile-tegu-modem-boot` | A wants link, nothing started | Anything starts | `systemctl disable omamobile-tegu-modem-boot` |
| 3. Cold boot / medium (the CP starts at boot, sleep blocked) | Power off, then on; after login: `journalctl -b -u omamobile-tegu-modem-boot`; `omamobile-sit status`; `systemd-inhibit --list`; `tools/phone-smoke` (laptop) | "modem OK: CP ONLINE", sitd running and registered, the inhibitor held, the latch present (it stays until a clean shutdown), phone-smoke clean | No ONLINE, a reset, a UFS or NV error, no inhibitor | `systemctl disable omamobile-tegu-modem-boot`, reboot; after a reset the latch keeps the next boot from starting the modem |
| 4. Clean shutdown / medium (one UFS handler pass expected on the 7 Pro's pattern) | `systemctl reboot`; after login: `journalctl -b -1 -k \| grep -c ufshcd_err_handler`; `ls /var/lib/omamobile/modem-bringup-started`; `tools/nv-backup --check` | The latch gone (clean stop), the CP up again at this boot, the UFS count recorded, NV matches | The latch still there after a clean reboot, I/O errors, NV mismatch | As step 3 |
| 5. A day's use / low | Calls, texts and data as usual | No reset, no latch left over | A reset or hang | As step 3 |

Record each run here with the date, `uname -r`, the package versions, the
phone-smoke report and the UFS count.

**2026-11-03, the palmtop** (the daily kernel
`7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`; slot B marked
successful on 2026-10-31 with no fastboot write since; the kernel keeps the
PERIC0 GPIO bus clock critical, as #172
does; on the charger; `omamobile-device-tegu` 0.2.12, `omamobile-modem-sit`
0.3.36, `omamobile-mmd` 0.1.4 and `omamobile-gnss` 0.2.7, all from this
stack):

1. Read-only: `tools/nv-backup -d tegu --check` against the 2026-10-28
   backup (#407): every NV partition the same. Passed.
2. Enabled `omamobile-tegu-modem-boot`. Passed.
3. `systemctl reboot` with the unit enabled: "modem OK: CP ONLINE", the
   phone service and the bridge queued, IMS registered with nothing started
   by hand, gnssd running, the latch reading `boot <id>` and `online`, the
   inhibitor held. A GNSS session through the Location socket had 133 of 135
   GGA sentences fixed (first fix 48 s). Passed.
4. A second `systemctl reboot` with the CP up: the profile's unit stopped
   cleanly, the latch was removed and the next boot wrote its own; no
   `ufshcd_err_handler` pass in the boot that shut down. Passed.

`tools/phone-smoke` on the second boot: every required check ok (boot, the
storage guard, root, kernel health, USB, session), and display, GPU, lock,
touch, buttons, Wi-Fi, Bluetooth, battery, sound card, sensors, cameras and
thermal ok. It flagged a stale bring-up unit in `/etc/systemd/system` from
2026-10-28 (`omamobile-tegu-audio.service`, failing), now moved aside, and
new dmesg lines from NFC (an unknown notification opcode) and CPIF (packets
for a channel nobody has opened); neither came with a fault.

Qualification, attended and on the charger: boot to ONLINE, data and texts;
the inhibitor; NV and UFS unchanged; then shutdown and reboot on their own.
Suspend with the CP on needs its own tests, with NFC polling stopped, and
incoming texts after resume. The cost until then: the modem on blocks sleep,
so the battery drains as if awake.
