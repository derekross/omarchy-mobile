<!-- SPDX-License-Identifier: MIT -->
# Revised Bluejay daily-carry baseline

Status (2026-11-14): offline implementation in branch
`bringup/bluejay-daily-baseline-20261114`, based on upstream `54a6565`.
No new startup files have run on the handset. After USB/SSH became unavailable,
the owner reached Fastboot. Fresh serial-pinned Fastboot verified actual B1
and unchanged A flags. Historical B recovery completed once, independently
verified natural B3, and sent one current-B boot. The historical desktop is now
identity-verified at B2 with full B/protected hashes, 49 guards, the owned
watchdog and six required smoke checks passing. The owner confirmed unlock,
app opening and scrolling on this recovered historical boot.

## Scope and facts

[V] The previous private trial ran signed kernel source
`720a495233734e4328a09c33c095d72a8291e1c4`, release
`7.3.0-rc6-omamobile-bluejay-review-20261111`, once with GPU, ALIX touch,
restricted-DMA station Wi-Fi and provisional gauge monitoring. Its last
recorded slot B state was unsuccessful with one retry. Physical interaction
and battery-widget observations remain pending.

[V] The exact historical recovery sources and all three complete B images
passed offline validation again on November 14; six recovery-control tests
passed. That recovery is now consumed and cannot be replayed. Prepare a new
named historical recovery before the revised qualification boots.

[V] Historical helpers target a different kernel and retain their pins. The
current upstream bring-up directory still says revised startup has not run.
This work adds a separate opt-in path; no device package or historical helper
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
manifest hashes and ABI. Twelve offline startup-control tests and eight new
qualification-writer tests pass. The bounded unit graph validates with a local
stub for the phone-only SDDM executable. No live revised result follows.

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
   USB SSH after each. Arm the applicable USB deadman before network changes.
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

## Completion and remaining gates

The goal remains open until the defined live tests and owner observations pass
or are recorded as actual blockers. Preparation is not completion. Record
successes and failures with exact source, boot IDs and durations privately;
publish only redacted conclusions. The next milestone should address the
largest measured blocker, likely charging/pack accuracy or native display/
lock/wake/sleep. Reliable updates, host-free startup and long owner carry
trials remain later gates; this baseline is not full daily-driver readiness.

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

Prepare a new qualification ledger and two fresh automatic startup boots with
this exact correction. The original consumed writer/observer remain evidence;
never rerun them. The independent historical recovery remains unconsumed.
