<!-- SPDX-License-Identifier: MIT -->
# Revised Bluejay daily-carry baseline

Status (2026-11-14, evening): corrected attended startup passed two fresh
automatic boots on signed kernel `720a495233734e4328a09c33c095d72a8291e1c4`,
release `7.3.0-rc6-omamobile-bluejay-review-20261111`. The first boot was B2;
one normal reboot returned at B1. Both boots passed the software checks below,
and the owner confirmed interaction and both battery percentage displays on
each. Three scoped station reconnects and the original ten-minute traffic
and battery window passed; its host dispatch failure is retained.
The implementation is in `bringup/bluejay-daily-baseline-20261114`, based on
upstream `54a6565`. This is an attended baseline, not daily-driver readiness.

Current B is unsuccessful with one retry. Send no further ordinary reboot or
push at this boundary. A new, frozen, unconsumed historical B recovery is
available privately for owner-attended Fastboot, with fresh serial/A checks,
independent natural B3 verification and a separate one-use boot command.
The earlier historical recovery and all consumed qualification launchers
remain evidence and must not be replayed.

## Scope and facts

[V] The previous private trial ran signed kernel source
`720a495233734e4328a09c33c095d72a8291e1c4`, release
`7.3.0-rc6-omamobile-bluejay-review-20261111`, once with GPU, ALIX touch,
restricted-DMA station Wi-Fi and provisional gauge monitoring. Its last
recorded slot B state was unsuccessful with one retry. Its physical interaction
and battery-widget observations were pending at that time; the two fresh
corrected boots above have their own owner confirmations.

[V] The exact historical recovery sources and all three complete B images
passed offline validation again on November 14; six recovery-control tests
passed. That recovery was consumed and cannot be replayed. A new named
historical recovery was prepared before the revised qualification boots and
remains unconsumed.

[V] Historical helpers target a different kernel and retain their pins. The
upstream bring-up directory at the base revision says revised startup has not
run. This work adds a separate opt-in path; no device package or historical helper
is changed. Calls, texts, modem/NV, native display and sleep are deferred.

## Design

Use separate root, GPU, touch, PCIe, Wi-Fi and provisional-gauge stages with
exact source/module/DT hashes in a private handset profile. Hold built-in
cpufreq-dt before loading the ACPM clock provider. Preserve the qualified
151 MHz GPU point, ALIX sequencing and below-4-GiB restricted DMA path.
Each hardware stage persists and syncs a pending marker before its first load,
publishes a boot-specific ready receipt only after postchecks, and never
unloads/rebinds to retry a failed load. A retained failure holds that stage on
later boots. No startup failure initiates another reboot at the retry boundary.

The candidate adds separate opt-in units and a release-conditional late user
UWSM environment override. Installed UWSM 0.27.2 source confirms that user
`env.d` follows system files. All 13 installed revised modules match the exact
manifest hashes and ABI. Fourteen offline startup-control tests and eight new
qualification-writer tests pass. The bounded unit graph validates with a local
stub for the phone-only SDDM executable. Six second-boot controls and nine
station-network controls also pass. The complete repository suite passed on
the corrected implementation before the live boots.

Accept only ABL's observed console=tty0 to console=null replacement; require
every other expected boot argument. Copy complete current-boot kernel journals
to private host/device evidence before and after every stage. Early probe
evidence must come from the retained journal, not just the live dmesg ring.

During attended qualification, startup waits for a fresh boot-specific host
logging receipt before hardware loads. Units then perform the stages without
manual module commands. This is an attended development startup; host-free
startup is a separate gate and must not be claimed from these runs.

## Gated runbook

1. **Offline / low risk.** Run the revised control tests, syntax/unit checks
   and project policy; verify the private profile against signed source,
   exact module archive, complete B images and protected backup. Review
   startup and recovery artifacts. Stop on any unknown provenance, unsafe
   path, loose console normalization or automatic reboot. Rollback: discard
   only this candidate; preserve all old evidence.
2. **Read-only / low risk.** Resolve the actual 6a USB interface; strict saved
   SSH host key plus board/bootconfig serial must agree. Capture actual boot,
   all 49 guards, full B/protected hashes, full devinfo/retry bytes, root,
   watchdog ownership, modules, services, battery and complete boot journal.
   Stop on SSH loss or mismatch. Do not retry commands into a silent phone.
   Request owner screen/physical observations and recovery attendance.
3. **Recovery / attended B-image risk.** At actual B1, no Linux reboot or push.
   Owner reaches Fastboot by buttons. The frozen historical recovery requires
   serial-pinned unlocked Bluejay/current B1 and unchanged stock-A flags,
   writes only known-good suffixed B images through the frozen project tool,
   independently verifies natural B3, then permits one current-B boot.
   Stop in Fastboot on partial/ambiguous results; never repeat an attempt,
   select a slot, restore metadata or enable boot-success. Expect historical
   B2 and intact guards; re-resolve USB and verify it afresh.
4. **Reversible root staging / moderate risk.** Only after live verification,
   snapshot exact existing files and enabled/masked states privately. Stage
   separate revised code/profile/units and module blacklists without starting
   hardware. Keep historical pins/masks, AUTO_WRITE=no, package hold, ZRAM
   policy, boot-success mask and paired root-marker semantics. Stop on any
   partial staging or unsafe file. Undo restores precisely that snapshot.
5. **Fresh revised B budget / attended B-image risk.** Prepare a NEW consumed-
   once Fastboot writer for the exact revised full image set, using the
   reviewed project B-only flash path without slot selection or auto-reboot.
   Require actual B1/B2, original A flags and known-good historical recovery.
   Independently verify natural B3 after flash before one current-B boot.
   Do not repurpose the historical recovery launcher for candidate images.
   Announce the screen interruption. Stop on any failed receipt or ambiguous
   write; preserve logs and stay in Fastboot.
6. **Exactly two revised boots / attended boot risk.** First revised boot
   must be B2; one ordinary reboot may then qualify B1. Open proven host
   logging and fresh SSH acknowledgment before the automatic stage chain.
   Each boot must pass source/modules/full B/protected hashes, 49 guards,
   owned 20-second watchdog, complete journal health, six required smoke
   checks, no failed units, nine GPU readbacks, touch zero-error checks,
   station-bound verified TLS and actual owner unlock/app/scroll observations.
   Gauge monitoring remains provisional. Stop at first failure, unexpected
   boot ID/reset, missing receipt or lost USB. No further reboot at B1.
   Recovery requires a new unconsumed attended historical B path prepared
   before step 5, with the same known-good complete images and unchanged-A gates.
7. **Bounded station checks / moderate risk.** On a qualified revised boot,
   perform three disconnect/reconnect cycles of only the phone's recorded
   station profile, with a 30-second association/TLS deadline each and fresh
   USB SSH after each. Arm a station-profile-only reconnect deadman before
   network changes; leave USB outside NetworkManager control.
   Then run ten minutes of station-bound verified HTTPS traffic with per-
   request deadlines, timestamps, bytes and errors retained. Require all
   three reconnects and the full traffic window without firmware/DMA/SPI/
   storage faults. Stop on first error; do not hide failed runs in a retry.
   No host network profile or other phone is part of these tests.
8. **Battery / measured readiness.** Record a ten-minute bounded monitoring
   window of voltage/current/temperature/capacity and UI observations. Keep
   pack identity, model accuracy, health and time estimates unqualified until
   the actual pack is identified. Model writes, charging and Type-C handover
   need their own staged runbook, measured input/current/thermal limits and
   USB deadman. No untethered-use claim from percentage alone.

## Corrected automatic startup, November 14

The runtime implementation at `cde98c4` completed the root, host-acknowledgment,
GPU, touch, PCIe, Wi-Fi, provisional-gauge and desktop units automatically on
two fresh boots. A B-only flash with independently verified natural B3 preceded
the first B2 boot; exactly one normal reboot produced the second B1 boot.
Slot A flags and protected contents remained unchanged. Each boot passed:

- Fresh USB mapping, strict saved SSH key, board and bootconfig identity.
- All 49 storage guards, complete candidate B and nine protected hashes,
  exact module bytes/ABI/root ownership, and the PID-1-owned 20-second watchdog.
- Nine hardware GLES pixel readbacks at the qualified 151 MHz point, Panfrost
  desktop environment and an open compositor render node.
- Qualified ALIX touch with zero SPI errors/timeouts, restricted DMA below
  4 GiB, managed station Wi-Fi and station-bound verified HTTPS.
- Six required smoke checks, no failed system units or pending startup/root
  markers, and no detected fatal/storage/GPU/SPI fault in the full boot journal.
- Owner interaction and both home-widget/top-bar percentage displays.
  First-boot interaction explicitly included scrolling; second-boot wording
  confirmed unlock, swipe and app opening.

Fresh host logging was proved before acknowledging root readiness on each
boot. No manual module command substituted for the automatic stage chain.
This does not qualify host-free startup, permanent boot-success policy, an
update package, native panel modes, lock/wake or suspend. CPU DVFS remains held.
The original pre-hardware refusal and its diagnosed corrections are retained
below; that failed boot is excluded from these two passes.

## Bounded station checks, November 14

Three station-profile-only disconnect/reconnect cycles completed association
and verified HTTPS in 6.56, 6.15 and 3.06 seconds, each below the 30-second
limit. Each had its own 45-second profile-only undo timer and a separate fresh
identity-pinned USB SSH check before that timer was stopped. The station PCI
identity and unmanaged USB interface were checked each time. No driver unload,
global NetworkManager reset, other-phone change or additional reboot occurred.

The original phone window completed 600.000115 seconds, all 60 verified HTTPS
downloads and exactly 62,914,560 bytes (60 MiB), at one 1 MiB request per
ten-second period. This is periodic traffic, not saturation, roaming, sleep or
owner carry endurance. Its host controller failed
while waiting for a long-running systemd oneshot to finish within a 20-second
SSH deadline. Fresh read-only SSH proved the original phone unit still running
on the same boot with its 660-second ceiling. A new read-only observer resumed
that existing run, recovering the full retained boot kernel journal before
following it. No traffic run was restarted. The dispatch failure and host-log
observation gap remain part of the result. The future controller now uses
`systemd-run --no-block`; an isolated regression fails the original dispatch
and passes the corrected one, preserving all finite phone bounds.

Final read-only checks on the same B1 boot passed full B/protected/module
hashes, all 49 guards, all eight startup units, compositor render-node use,
the full boot journal and six required smoke checks. No failed unit, pending
startup/root marker or active station undo timer remained. The original phone
traffic unit exited successfully. The modem remained inactive.

## Battery reporting and charging disposition, November 14

Provisional gauge monitoring and UPower started automatically on both boots.
The owner saw 98% in both displays on the first; both percentage displays were
confirmed again on the second without an exact new value. The widget's first
628-hour estimate is an observed reporting defect, not measured runtime.
A later read-only snapshot reported 9.7218 Wh and 0.028875 W in UPower, which
arithmetically implies about 336.7 hours. This explains how a very small
reported rate can produce a huge estimate; it does not reproduce the exact
earlier value or validate the underlying energy/current data. The kernel's
`Charging` status and UPower's `Discharging` state also disagreed.

Actual pack selection, gauge scaling/model accuracy, capacity, battery health,
time estimates and charge direction remain unqualified. The saved stock data
contains several model variants; a static model table does not identify this
handset's pack. No model, charger or Type-C configuration was changed in this
baseline. Monitoring success and a USB cable do not demonstrate controlled
charging. Follow up with read-only pack/model/scaling and UPower-state analysis,
then a separately staged charger-only trial with actual input/current/thermal
measurements and a tested USB recovery path.

All 60 provisional traffic-window samples reported 98% and 22 degC, with
4.302031-4.305156 V. Reported current ranged from -11,875 to +10,625 microamps;
the energy/current/model and charge-direction uncertainty prevents a drain or
runtime claim from this tethered observation.

## Completion and remaining gates

The defined attended baseline is achieved: two corrected automatic startup
boots with owner observations, three bounded station reconnects, the original
600-second traffic/battery window and final state verification. The initial
pre-hardware refusal and the host dispatch failure remain part of the evidence;
the host harness itself did not have a clean end-to-end pass. Exact private
boot IDs, snapshots, logs and consumed-attempt records are retained outside
the repository. No additional reboot or write is queued at B1.

| Daily-carry gate | Measured disposition |
| --- | --- |
| Attended revised startup and one normal reboot | Passed on two fresh boots |
| Owner interaction and both percentage displays | Confirmed on both boots |
| Three station reconnects and ten-minute periodic traffic | Passed; retained host-controller failure and recovered-log caveat above |
| Exact-build provisional gauge startup | Passed; values are uncalibrated |
| Pack/model/scaling, health, runtime and charge direction | Unqualified; implausible time and state disagreement observed |
| Controlled charging and Type-C/USB handover | Unqualified; no charger/Type-C trial performed |
| Permanent boot-success, host-free startup and update packaging | Open; current B1 forbids another ordinary reboot or push |
| Native display, lock/wake, sleep and idle drain | Open; no claim from desktop or traffic checks |
| Sustained owner carry | Open; baseline is not full daily-driver readiness |

Next proposed goal: establish trustworthy Bluejay battery reporting by
identifying the actual pack and validating gauge scaling/model selection,
reconciling UPower state and time estimates, then qualifying conservative
charger-only tethered behavior under a separate measured runbook. Begin
read-only and resolve the B1 recovery boundary before any new boot or hardware
change. Calls, texts and modem work remain deferred.

## Recovery observations, November 14

The original memory-only host USB profile was absent after re-enumeration.
Only the verified 6a interface received a replacement memory-only static
profile, without gateway, default route or IPv6. Routes outside that interface
were unchanged; no other phone or global service was changed. Strict saved SSH
host key plus remote board and bootconfig serial then passed.

The historical kernel retains its earlier trace-event self-test warning
(`test_double_dereference`), reproduced in the saved November 8 boot log. Its
held USI probe deliberately returns `-ECANCELED` before configuration; the
smoke classifier reports that as an optional new error. Both remain recorded.
No new fatal, GPU, SPI or storage fault was found. The revised kernel keeps
strict trace/fault refusal; this historical warning is not added to its
allowlist. Battery monitoring is absent after recovery, as expected from its
prior session-only load. No gauge launcher was replayed.


## Preboot staging, November 14

Sixteen new files were installed under a consumed-once staging operation on
that historical B2 boot, with private file/enablement snapshots and verified
readback. No unit or hardware was started and no boot image was written.
The new root/desktop units are enabled only for the revised command-line
selector. The late user graphics file also checks the exact revised release,
leaving the historical environment intact.

A preboot review found that the initial graphics override tried to read
root-private receipts. A separately recorded correction now queries the
completed current-boot GPU unit, keeping the receipts private. Historical,
software-fallback and active-GPU environment branches pass offline tests.
The original staging/frozen receipts and pre-correction file are preserved.
Guarded undo verifies all sixteen files before removing only this staging.

The original recovery was consumed. A new independent unconsumed historical
B recovery is frozen for the qualification, with complete original image
provenance, unchanged-A checks, natural B3 verification and a separate one-use
boot command. The revised writer likewise stays in Fastboot after flashing;
its separate boot command requires independently verified B3. Neither selects
a slot or writes metadata directly. Revised runtime tests remain pending.

## First revised refusal and diagnosed correction, November 14

The attended writer verified actual B2 and original A flags, flashed the exact
revised B set once, independently verified natural B3, and sent one current-B
boot. The revised kernel returned as boot
`bf8a76f2-0ca2-492c-9921-1ebfa8e14864`. Its root verifier refused before any
hardware load: the live command line contains two copies each of
`clk_ignore_unused` and `pd_ignore_unused`, while the initial verifier expected
one. The packed DT and vendor header each carry these holds; the generic boot
header and compiled CONFIG_CMDLINE are empty. Every other required safety token
was present with no conflicting value. This failed boot remains recorded and
is not a qualification pass. The owner's observed black Linux screen ending
at switching to Arch Linux is a held-desktop observation, not an interaction
pass.

The corrected gate requires exactly two copies of those two flags, retaining
all other multiplicities and the single console=tty0 to console=null rewrite.
The captured actual command line and fourteen offline refusal/control tests
pass. A subsequent read-only preflight found the thirteen exact revised
modules and twenty-nine parent directories retained the build user's ownership.
Their hashes and ABI matched, but the new root-ownership requirement properly
refused them. The module guard now also checks parent ownership.

A new consumed-once diagnosed correction preserved the original runtime,
failed unit journal, root-pending marker and all module metadata. It normalized
only those pinned module files/directories to root ownership and ordinary
read-only-to-users modes, preserving all bytes and the historical release.
Under a fresh proven host log stream, only the recorded software-unit failure
was reset. The corrected root-only gate then passed full B/protected hashes,
49 guards, watchdog, DT/module/firmware identity and kernel-journal checks;
only that fresh boot's root readiness was acknowledged. No driver or service
was started and no reboot was sent. This permits a future guarded Arch boot;
it does not turn the failed startup into a pass.

At that point a new qualification ledger and two fresh automatic startup boots
were required with this exact correction. They subsequently passed as recorded
above. The original consumed writer/observer remain evidence; never rerun them.
The independent historical recovery remains unconsumed.
