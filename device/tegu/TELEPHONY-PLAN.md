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
   kept from ONLINE until the profile's unit stops at a shutdown (its
   ExecStopPost, whatever the stop's result). *Target:* an atomic per-boot
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
| 3. Cold boot / medium (the CP starts at boot, sleep blocked) | Power off, then on; after login: `journalctl -b -u omamobile-tegu-modem-boot`; `omamobile-sit status`; `systemd-inhibit --list`; `tools/phone-smoke` (laptop) | "modem OK: CP ONLINE", sitd running and registered, the inhibitor held, the latch present (it stays until the profile's unit stops at shutdown, or until the next boot after a `reboot-to`, which clears it from its note), phone-smoke clean | No ONLINE, a reset, a UFS or NV error, no inhibitor | `systemctl disable omamobile-tegu-modem-boot`, reboot; after a reset the latch keeps the next boot from starting the modem |
| 4. Clean shutdown / medium (one UFS handler pass expected on the 7 Pro's pattern) | `systemctl reboot`; after login: `journalctl -b -1 -k \| grep -c ufshcd_err_handler`; `ls /var/lib/omamobile/modem-bringup-started`; `tools/nv-backup --check` | The latch gone (clean stop), the CP up again at this boot, the UFS count recorded, NV matches | The latch still there after a clean reboot, I/O errors, NV mismatch | As step 3 |
| 5. A day's use / low | Calls, texts and data as usual | No reset, no latch left over | A reset or hang | As step 3 |

Record each run here with the date, `uname -r`, the package versions, the
phone-smoke report and the UFS count.

**2026-11-03, the palmtop** (the daily kernel
`7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`; slot B marked
successful on 2026-10-31 with no fastboot write since; the kernel keeps the
PERIC0 GPIO bus clock critical, as #172
does; on the charger; `omamobile-device-tegu` 0.2.12, `omamobile-modem-sit`
0.3.36 and `omamobile-mmd` 0.1.4 from the pull requests above this one
(#376 to #380), `omamobile-gnss` 0.2.7 from main):

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
5. Later the same day (10:03), a `systemctl reboot` with the CP up left the
   latch: the CP's power-off in ExecStop ended rfsd before systemd's
   SIGINT, the profile's supervisor exited 1 ("CP OFFLINE", then
   `Control process exited, status=1`), and the old ExecStopPost removed
   the latch only on `SERVICE_RESULT=success`. The next boot (10:33)
   refused the modem. Failed; fixed in this pull request's last commit
   (ExecStopPost runs `omamobile-tegu-modem-up --stopped`, which removes
   this boot's latch after ONLINE whatever the result). Re-run with the
   fixed script: modem started and ONLINE, `systemctl reboot` at 10:43
   ("modem stopped (success): … removed"), the next boot ONLINE on its own,
   and a second reboot at 10:47 removed that boot's latch too. Passed.
   `tools/nv-backup -d tegu --check` against the same backup after the
   day's reboots (these, two kernel pushes and two sysrq reboots after
   sleep tests): every NV partition and `metadata` the same, `devinfo`
   different, as after any boot-success mark (tegu NOTES, 2026-11-03).
   Passed.
6. The `reboot-to` path (#403's `reboot-to` installed): in the evening,
   with the CP ONLINE, `reboot-to omamobile`. The next boot logged "the
   last boot with the modem up ended with reboot-to:
   /var/lib/omamobile/modem-bringup-started removed", started the modem on
   its own to "modem OK: CP ONLINE", and left no
   `/var/lib/omamobile/deliberate-restart` behind. Passed. Whether the
   CP's power-off or UFS logged anything is not observable after a
   `reboot-to`: it skips systemd's shutdown, so the kernel's final
   shutdown runs after the journal's last write, and the next boot's
   `journalctl -b -1` ends before it. The `reboot-to` here was #403's,
   built by hand on the palmtop; pacman puts the packaged one back when
   #403's `omamobile-device-tegu` lands.
7. The stop witness (2026-11-08, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty` build #99, the
   owner's sleep-test kernel; `omamobile-device-tegu` 0.2.13 and
   `omamobile-modem` 0.1.17 from this branch, built on the palmtop; on the
   charger, attended). Three rounds of `systemctl start
   omamobile-tegu-modem-boot` (the unit's `--phone --gnss` path, the
   bring-up modules), then `systemctl reboot`:
   - Round 1: CP ONLINE 8 s after the start; the latch read `boot <id>`,
     `invocation <id>`, `online`; sitd and the bridge active. At the reboot
     82 s later the unit's stop logged "CP OFFLINE", then "modem stopped
     (success, the CP OFFLINE before the daemons went):
     /var/lib/omamobile/modem-bringup-started removed", and systemd
     "Deactivated successfully": the first shutdown with the CP up whose
     result was `success` (the rfsd hold). `journalctl -b -1 -k | grep -c
     ufshcd_err_handler` 0, no UFS error on the next boot, no latch.
     Passed.
   - Round 2: ONLINE 9 s after the start; the carrier's welcome text
     arrived in Messages through the bridge; 50 s after ONLINE the palmtop
     reset on its own: the bootloader's record in the next boot's ramoops
     reads "Reboot reason: 0xcbea - APC Watchdog Early", the console ends
     with sitd bringing `rmnet0` up and cpif's AP2CP doorbell line
     (`pcie_send_ap2cp_irq`), no panic, no stall report. The latch stayed,
     and the two boots after it (one of them a clean `systemctl reboot`)
     left it: the design's answer to a reset with the modem up.
   - Round 3: the start found the other boot's ONLINE latch, moved it aside
     (`modem-bringup-started.unclean-20261108T202217`), and went on to
     ONLINE in 9 s (the one retry); 22 s later the same watchdog reset,
     the console again ending on cpif's AP2CP doorbell. Two unclean ends
     in a row: the latch and its copy now hold the modem off until a human
     clears them.

   The resets are the known G3-L1 hang, not this branch: the sleep-test
   kernel the palmtop ran (#99, built from the integration tree as it
   stands) has `zumapro_gpio_peric0` at `CLK_IGNORE_UNUSED`
   (`/sys/kernel/debug/clk/zumapro_gpio_peric0/clk_flags`), without
   kernel #172's `CLK_IS_CRITICAL`, which the daily Image carries
   (`logs/tegu-clkfix-20261101`), and without kernel #150's SPI flush
   order (gnssd's CHPP link showed the ACK timeouts of MODEM-PLAN G3).
   With the modem's AP2CP lines toggling twice a second under GNSS, that
   gate hung the SoC within minutes before #172, and round 1's 82 s were
   the luck of the draw. The re-run the same night on #100 (#99 with
   kernel #172 and #150, `zumapro_gpio_peric0` reading `CLK_IS_CRITICAL`):
   the start first met the hold ("the last two boots with the modem up
   ended without a clean stop ..."), the latch and its copy were removed
   by hand as the message says, and the next start reached ONLINE in 8 s;
   4.5 minutes later, sitd registered and the bridge active, no reset, no
   UFS error-handler pass; `systemctl reboot`: "CP OFFLINE", "modem stopped
   (success, the CP OFFLINE before the daemons went): ... removed",
   "Deactivated successfully", no latch and no UFS error on the next boot.
   Passed. (The bootloader's "Reboot reason" line in ramoops keeps the
   last abnormal reason across clean reboots; its "power on source" tells
   them apart: 0x20 after the watchdog resets, 0x80 after a clean reboot.)

### 2.8 The boot start running by itself (gated runbook and results, the follow-up to #372)

**Status: the unit stays opt-in.** This runbook was written to turn the
start on by default, and its runs below are the record of the unit running
by itself on the owner's palmtop, where it was turned on with a vendor wants
link for the test (step 1; an owner turns it on with `systemctl enable`).
The package doesn't ship that link, for two reasons: marking slot B on the
9a is on hold (#483), the unit can't tell whether B is marked, and with B
unmarked a reset spends one of ABL's three tries and the latch's retry a
second; and a phone built from the tree gets its CP drivers' `cpif` node
from the `modem-cpif` overlay, whose first runs are 2.9. Turning the link on
is a small change once both are settled.

What the test changed: `omamobile-tegu-modem-boot` turned on with a vendor
wants link, as #398 did for the 7 Pro, with conditions that skip it (not
fail it) on a phone without the provisioning files or without CP drivers
(the conditions are in the package). Preconditions as 2.7: slot B marked,
the kernel with #172 (check
`/sys/kernel/debug/clk/zumapro_gpio_peric0/clk_flags` reads
`CLK_IS_CRITICAL`), the charger in. Risk: medium (the modem starts at every
boot; the latch's one retry and hold bound a reset loop).

| Step / risk | Command | Expect / Pass | Stop | Rollback |
| --- | --- | --- | --- | --- |
| 1. Install / low | `tools/phone-install-package packages/omamobile-device-tegu`; `ls -l /usr/lib/systemd/system/multi-user.target.wants/omamobile-tegu-modem-boot.service` | The link is there; `systemctl is-enabled` reads "disabled" (vendor link), `systemctl list-dependencies --plain multi-user.target` lists the unit | The link missing | `pacman -U` the previous package |
| 2. Two reboots / medium | `systemctl reboot`, twice; after each: `journalctl -b -u omamobile-tegu-modem-boot`, `omamobile-sit status`, `cat /var/lib/omamobile/modem-bringup-started`, `journalctl -b -1 -u omamobile-tegu-modem \| grep "modem stopped"` | Each boot: "modem OK: CP ONLINE" with nothing started by hand, registered, the latch with this boot's invocation; the previous boot's stop "success, the CP OFFLINE before the daemons went"; no `ufshcd_err_handler` pass, no UFS error | A reset, a refused start, a latch left | `systemctl mask omamobile-tegu-modem-boot`, reboot |
| 3. The skip / low | `systemd-analyze condition 'ConditionPathExists=/var/lib/omamobile-vendor/modem/props.conf'` with the file moved aside for the check, then back; or read the unit's conditions | A phone without the files or the drivers skips the unit with "Condition check resulted in ... being skipped", no latch, no inhibitor | The unit fails instead of skipping | As step 2 |
| 4. Off and on / low | `systemctl mask omamobile-tegu-modem-boot`, reboot; `systemctl unmask`, reboot | Masked: no modem, no latch, the palmtop sleeps; unmasked: the modem comes back at boot | The masked boot starts the modem | Remove the mask |
| 5. `tools/nv-backup -d tegu --check` / low | After the reboots | Every NV partition the same as the backup | A difference | Stop; look before any further boot |

**2.8 results (2026-11-09, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty` build #100, `omamobile-device-tegu` 0.2.14 with the vendor link, built on the palmtop, `omamobile-modem` 0.1.17; on the charger).**

1. Installed 13:14 MST: the vendor link is there (`multi-user.target.wants/omamobile-tegu-modem-boot.service -> ../omamobile-tegu-modem-boot.service`), `systemctl is-enabled` reads "disabled" as a vendor link does, `systemctl list-dependencies --plain multi-user.target` lists the unit once. The gate's `clk_flags` check read `CLK_IS_CRITICAL`. Passed.
2. Two `systemctl reboot`s with nothing started by hand (13:15 and 13:21 MST): each boot the unit ran (`ConditionResult=yes`, `Result=success`), "drivers: the bring-up modules", "modem OK: CP ONLINE", the phone service and the bridge started; `omamobile-sit status`: SIM ready, radio on, home LTE, IMS voice and SMS, data bearer up; the latch read this boot and `invocation <id>` and `online`, one latch file; gnssd running. The first boot's stop at the second reboot: "CP OFFLINE", "modem stopped (success, the CP OFFLINE before the daemons went): /var/lib/omamobile/modem-bringup-started removed", "Deactivated successfully"; 0 `ufshcd_err_handler` passes in that boot, 0 UFS error lines in both. Passed.
3. The skip: not run on the palmtop (it is provisioned and has the modules); the conditions are read-only in the unit file and the package test holds them.
4. Off: `systemctl mask omamobile-tegu-modem-boot` at 14:01 MST before a kernel push for a sleep run; the boot after it read `masked`, started no modem and left no latch (the sleep series ran). On again: unmasked at 16:29 MST and rebooted; that boot ran the unit by itself ("modem OK: CP ONLINE" at 16:30), the phone service and the bridge active, SIM ready, home LTE, IMS voice and SMS, data bearer up, 0 UFS lines. Passed.
5. `tools/nv-backup -d tegu --check` (14:00 MST, after the day's reboots with the modem up: two by the boot unit, two in 2.7's step 7 the evening before, and the resets of the sleep tests): efs, efs_backup, modem_userdata, persist, modem_a, modem_b and metadata SAME as the 2026-10-28 backup; devinfo different, as expected. Passed.

`tools/phone-smoke` on the second boot: every required check ok (boot, the
storage guard, root, kernel health, USB, session), and display, GPU, lock,
touch, buttons, Wi-Fi, Bluetooth, battery, sound card, sensors, cameras and
thermal ok. It flagged a stale bring-up unit in `/etc/systemd/system` from
2026-10-28 (`omamobile-tegu-audio.service`, failing), now moved aside, and
new dmesg lines from NFC (an unknown notification opcode) and CPIF (packets
for a channel nobody has opened); neither came with a fault.

### 2.9 The in-tree drivers through the starter, on the published tip plus four open changes (2026-11-09)

The 2.8 boots took the starter's bring-up branch ("drivers: the bring-up
modules"), because the board's device tree has no `cpif` node: it comes
from the device's `modem-cpif` overlay ([#594](https://github.com/derekross/omarchy-mobile/pull/594)).
With that overlay on the published DTB, on
`7.3.0-rc6-omamobile-push1-g773b4102f5ec` (`omamobile` at `abcd6aac51cf`
plus kernel #224, kernel #236 and the 9a's GNSS nodes; defconfig, the shared
config, #274's PCIe PHY and the GNSS link driver), the same unit took the
other branch, on the charger, watched over SSH with the owner away for the
first boot:

- Three boots in a row by the unit itself (18:32, 18:50 and 19:12 MST):
  "drivers: the running kernel's" (`modprobe pcie_gs201_cp allow_hw=1`,
  `shm_ipc`, `cpif`, `gnss_spi`, `gnssif`), "modem OK: CP ONLINE" 8 s after
  the unit started, the phone service and the bridge up, registered at home
  on LTE, the latch with the boot's invocation, no UFS error-handler pass.
- Two `systemctl reboot`s with the modem up (18:45 and 19:11 MST): "CP
  OFFLINE", then "modem stopped (success, the CP OFFLINE before the daemons
  went)", the latch removed. A boot with the unit masked between them
  started nothing and left no latch.
- Four 150 s GNSS sessions through the Location switch's socket: 108 of
  113, 142 of 143, 105 of 107 and 142 of 144 GGA sentences fixed; each
  stopped on its idle lease with the CP ONLINE.

The details, and why the GNSS bus keeps zumapro's SPI port configuration,
are in MODEM-PLAN after section P (with #594). A fourth boot by the unit
(19:26 MST) took an incoming call through the bridge (accepted, 8 s, hung
up, the release confirmed in 272 ms) and mobile data over `rmnet0`; its
`systemctl reboot` was confirmed like the two before; and
`tools/nv-backup -d tegu --check` after it read every NV partition SAME as
the 2026-10-28 backup. Texts went both ways on a later boot of it (the sixth by the unit, the modem up at 20:37 MST, the texts at about 20:40: one sent from the palmtop arrived, the reply reached the palmtop 22 s after the send).

One gap found by reading and closed the same evening: the link driver takes
its PHY from `phy_zuma_pcie`, which the guards keep from autoloading and
which only the Wi-Fi start loaded, and only on a phone with the Wi-Fi
firmware. The boots above had that firmware, so the PHY's driver was there
by the time the modem started. The starter now loads it itself, before the
link driver, and refuses before the latch on a kernel without it. Checked on
a fifth boot of the same kernel (20:26 MST) with the Wi-Fi firmware moved
aside for that boot: the graphics start skipped Wi-Fi ("no Wi-Fi host, DMA
pool or BCM4383 firmware"), `brcmfmac` and `pcie_gs201` weren't loaded, the
starter loaded `phy_zuma_pcie`, `pcie_gs201_cp` and CPIF, and the unit
reached "modem OK: CP ONLINE", registered at home on LTE; its stop at
`systemctl reboot` was confirmed. What the start does without the PHY's
driver wasn't tried on the palmtop.

**One unclean end the same evening, not explained (2026-11-09, 20:35 MST).**
Of the thirteen `systemctl reboot`s with the modem up on 11-08 and 11-09
(seven on the owner's kernels, six on the published one), twelve logged the
confirmed stop. One didn't: build #100 with the bring-up modules, the unit
started by hand with `systemctl start omamobile-tegu-modem-boot` 2 minutes
40 s earlier, then `systemctl mask`, `sync`, `systemctl reboot`. That boot's
journal ends at logind's "System is rebooting." with no stop line, the next
boot's kernel started 61 s later (a clean one takes about 20 s), and the
latch was still there, so the shutdown ended abruptly before the stop was
recorded. The latch did what it is for: the next boot with the unit on
logged "ended without a clean stop ... starting the modem again", kept the
copy, started the modem, and the confirmed stop after that removed both.
The console of the failed shutdown is lost: my next step was a kernel push
22 s into the following boot, and that boot's console replaced it in
`/var/lib/systemd/pstore`. The same sequence run again nineteen minutes
later on the same build (the boot of 20:49: hand start, 160 s, mask, sync,
reboot at 20:54) stopped cleanly in 23 s. So: one in
thirteen, cause unknown, not reproduced in one repeat. After a reboot that
takes a minute or leaves no stop line, copy `/var/lib/systemd/pstore` before
anything else.

The evening's boots with the modem up, from the palmtop's
`journalctl --list-boots` and each boot's own lines (read 2026-11-10; an
earlier version of this section had three of these times wrong):

| Boot started (MST) | Kernel | Modem up | Started by | The stop at `systemctl reboot` |
| --- | --- | --- | --- | --- |
| 18:32:33 | the 2.9 kernel (`push1-g773b4102f5ec`, in-tree drivers) | 18:32:49 | the unit | confirmed |
| 18:50:14 | the same | 18:50:30 | the unit | confirmed |
| 19:12:04 | the same | 19:12:20 | the unit | confirmed |
| 19:25:44 | the same (the call, data, the NV check) | 19:26:00 | the unit | confirmed |
| 20:18:38 | build #100 (bring-up modules) | 20:18:52 | the unit | confirmed |
| 20:26:15 | the 2.9 kernel (the Wi-Fi firmware moved aside) | 20:26:29 | the unit | confirmed |
| 20:30:52 | build #100 | 20:32:56 | by hand | **none: the journal ends at 20:35:36, the next boot started 20:36:37** |
| 20:37:12 | the 2.9 kernel (the texts) | 20:37:28 | the unit, after "ended without a clean stop" | confirmed |
| 20:49:39 | build #100 (the repeat) | 20:51:44 | by hand | confirmed |
| 20:56:52 to 22:29:16, thirty boots | build #100 | about 14 s into each boot | the unit | confirmed, thirty of thirty |

**Thirty more, all confirmed (2026-11-09, 20:57 to 22:32 MST).** To look for
it again, a laptop loop rebooted the palmtop thirty times with the modem up
(build #100, the bring-up modules, the unit starting the modem at each boot,
`omamobile-device-tegu` from this branch, `omamobile-modem` 0.1.17): wait
for the phone service and CP ONLINE, hold two minutes, `sync`,
`systemctl reboot`, and at the next boot copy pstore first, then read the
previous boot's stop line. Thirty of thirty logged "modem stopped (success,
the CP OFFLINE before the daemons went)" with the journal closed cleanly,
SSH was back 24 or 25 s after each reboot, no boot reported an unclean end,
and none had a UFS error-handler pass. `tools/nv-backup -d tegu --check`
afterwards: every NV partition SAME as the 2026-10-28 backup. With the
thirteen before, that is 42 confirmed stops in 43, and the one still
unexplained.

Qualification, attended and on the charger: boot to ONLINE, data and texts;
the inhibitor; NV and UFS unchanged; then shutdown and reboot on their own.
Suspend with the CP on needs its own tests, with NFC polling stopped, and
incoming texts after resume. The cost until then: the modem on blocks sleep,
so the battery drains as if awake.
