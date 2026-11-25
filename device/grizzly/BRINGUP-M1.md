<!-- SPDX-License-Identifier: MIT -->
# Grizzly M1 bring-up plan

The test phone has November D1 on stock A. Earlier B trials reached
authenticated USB SSH in RAM rescue. Two RAM-root trials also reached
systemd with zero SCSI disks. The UFS diagnostic stops at PHY readiness.
See the [D1 recovery and trial record](NOTES.md#november-d1-recovery-and-first-light-checks)
and the [kernel provenance and fixtures](bringup/README.md). Coordinate with
the October-build Grizzly in [#26](https://github.com/derekross/omamobile/issues/26).

| Step | Pass | Stop | Return |
| --- | --- | --- | --- |
| Review sources and fixture | Confirm the published source branch, kernel release and commit for the fixture. Reproduce the five image checks, B0 DT selection, AVB signatures and ABL handoff bounds. Verify stock A and its Recovery route, the matching D1 bootloaders and the attended return timer. | Source mismatch, failed validation, uncertain stock recovery or nobody available to catch Fastboot. | Leave the phone on stock A. |
| Stage the diagnostic | The serial-pinned stage-only writer acknowledges the five B images. A remains active and successful. The 64 MiB `vendor_boot_b` readback matches the entire 8,192-byte payload. | Any write or readback fails, snapshot update is active, or slot and bootloader checks disagree. | Leave A selected. Keep B inactive until staging is complete and verified. |
| Capture the v29 handoff state | The handoff-only fixture logs `cpm-before-handshake`, confirms the UFS driver blacklist and reaches RAM rescue. Verify the same sample after stock A boots. Completed on 2026-11-24. | The wrapper guard skips the child PSM reads, the UFS driver starts, a block device appears, or the return path is lost. | Catch Fastboot with Volume Down after the timed warm restart, select A, then boot stock. |
| Measure PSM3 with the v32 link diagnostic | Capture the four vote samples, prep/core vote provenance and final PHY/TOP results. Match the retained console after stock A boots. Completed on 2026-11-24. | The NV backup gate is unresolved, the return path is lost, or a block device appears. | Return to stock A and preserve the console before considering a repeat. |
| Measure device buck settings with v33 | Capture BUCK11S and BUCK13S on either side of the core vote and the final readiness result. Completed on 2026-11-24. | The NV backup gate is unresolved, the return path is lost, or a block device appears. | Return to stock A and preserve the console. |
| Measure PHY reset acknowledgment with v34 | Capture the guarded status word after the PHY timeout and verify it in the retained console. Completed on 2026-11-24. | The NV backup gate is unresolved, the return path is lost, or a block device appears. | Return to stock A and preserve the console. |
| Measure PHY readiness after external device power-on with v35 | Capture the initial timeout and reset acknowledgment, the device-on result, and the second PHY and conditional TOP polls. Completed on 2026-11-24. | A preflight gate fails, PHY reset release is unconfirmed, or the pre-device-on wrapper or child state differs from v34. | End the fallback before HCI, keep the held domain references, and use the attended stock A return. |
| Measure REFCLK status with v36 | Capture GPIO gate acknowledgment before device-on and around device-off, GPIO auto-gating and M-PHY gate bits before device-on, and the raw GPIO clock replies. Completed on 2026-11-24. | A preflight gate fails or the initial guarded samples are unavailable. Record any cleanup query error separately from the PHY result. | End the fallback before HCI and use the attended stock A return. |
| Observe the DBL UFS config clock with v37 | The single 2026-11-24 trial preserved the pre-handshake PSMs and an SError at the config-clock load. No config word was captured. | The v37 AP read caused an early panic. Treat this bundle as a record of the failed probe. | Fastboot returned and stock D1 slot A completed boot. |
| Observe UFS power states through boot with v38 | Capture the wrapper, HC and PHY before and after the CPM startup frame and at both delayed samples. Verify RAM rescue and zero UFS disks. Completed on 2026-11-24. | A preflight gate fails, the wrapper guard skips the child reads, or rescue does not appear. | Preserve the available samples and use the attended stock A return. |
| Observe initial provider votes with v39 | Capture the conditional HSIO-S, UFS prep and UFS core ON votes before domain registration, the guarded PSMs on either side, and the delayed samples. Verify RAM rescue and zero UFS disks. Completed on 2026-11-24. | The backup gate is unresolved, a vote fails, a child read is skipped, or RAM rescue is lost. | Preserve the partial sequence and use the attended stock A return. |
| Trace the stock D1 UFS consumer | Verify the stock inventory and compare consumer-phase MBFS votes, PHY reads and TOP readiness against v39. | The trace cannot arm, the stock inventory or NV guard fails, or the relevant part of the trace is incomplete. | Catch Fastboot after the existing warm return timer, select A, verify stock boot, then read the retained console. |
| Review first storage-visible rescue | Pair a qualified enumerating kernel with the Grizzly inventory-only ramdisk. Inspect the exact archive for the storage guard and match the stock UFS reference-clock attribute. Keep raw SCSI, BSG and RPMB exposure disabled. | Open write allowlist, unresolved clock attribute, unexplained LUN mapping, or any path that hands off to an installed userspace. | Keep the storage-visible fixture offline. Retain the link-only diagnostic and stock A. |
| Back up calibration and radio partitions | The first storage-visible boot runs Grizzly RAM rescue. Verify expected partitions by unique GPT label, `ro=1` and unmounted state. The first reads are through `tools/nv-backup`. Complete the backup and check its hashes in a private off-repo directory. Size the attended return window for the reads and verification pass. | Missing or ambiguous labels, any writable or mounted target, a failed hash, or not enough time to finish. | Keep files private, return to stock A, and defer further CPM, PMIC and charger experiments until a verified backup exists. |
| Install Grizzly userspace | A Grizzly-specific root and boot policy pass their own review and tested recovery procedure. | A Cheetah device package, boot-success unit or AoC service in the storage-visible root, or an unverified recovery path. | Keep Grizzly in RAM rescue or return to stock A. |

### Maintainer decision on the first NV backup

[Derek approved the v29 UFS rail requests before the NV backup](https://github.com/derekross/omamobile/pull/1002#issuecomment-7142236516)
because storage needs those rails. Use only the stock voltage settings.
During the rescue boot, keep every partition read-only under the storage
guard and run `tools/nv-backup` as soon as the guarded storage is available,
before any other partition consumer. Verify the backup privately before
further CPM, PMIC or charger experiments. If storage does not enumerate
or the guard fails, stop and use the stock A return.

The original v29 link fixture stops before LUN discovery. An enumerating
Grizzly RAM rescue with a closed write allowlist and enough time to finish
the backup is still needed to exercise the mainline backup path. For a
backup now, use the [stock D1 RAM rescue](#stock-d1-read-only-ram-rescue),
which uses the factory UFS power sequence and already enumerated all nine targets.
The standalone Grizzly staging helper is already in
`device/grizzly/bringup/`. The shared `flash` command follows its normal
`load_device` and allowlist path.

## v29 handoff-only result

The recorded boot below is the handoff-only repack requested on
2026-11-24 at 05:43:57 UTC. See the maintainer's later decision above
for the full v29 rail requests and NV backup order.

On 2026-11-24, the Mac staged all five slot B images and matched all
8,192 supplied bytes in the `vendor_boot_b` readback. One attended boot
of `7.3.0-rc6-omamobile-grizzly-uic-v29` reached USB SSH in RAM rescue.
The repack disabled UFS SGIA, GPIO, standby pinctrl and regulators, and
passed `initcall_blacklist=ufs_malibu_driver_init`. The live kernel
confirmed the blacklist and reported zero UFS disks.

At 0.099530 s, before the Linux CPM startup frame, the HSIO-S wrapper
and HC PSM read `0x00000010` (on), while the PHY PSM read `0x00000011`
(off). HC was already on by the first safe sample. The sample puts the
PHY power-up later than this point in the diagnostic boot.

USB SSH, ramoops and `SYSTEM_LAST_KMSG` all recorded the same sample.
The retained console also recorded the timed warm restart. Fastboot
returned, and stock D1 `CP4A.261105.040.D1` completed boot on A with
enforcing verity and the factory VBMeta digest.

## Stock D1 PHY power-up

The offline trace follows stock D1 B0 device-tree resources and the
factory `power_controller.ko`, `ufs.ko`, `cpm.img`, `dbl.img` and
`abl.img`. The saved stock A kernel log loads the power-domain provider
at 0.885 s and `ufs.ko` at 1.016 s. UFS reports PHY patching mode 0,
applies calibration at 1.137 s and registers the SCSI host at 1.163 s.
The capture has no stock PHY PSM sample or CPM mailbox trace for the
transition.

1. D1 B0 marks HSIO-S, UFS prep and UFS core `force-on`. In
   `power_controller.ko` (`0x3ba4`, `0x3d2c`–`0x3d3c`), the provider
   reads the initial MBFS vote and can issue an on vote for an off
   domain during registration. This can run before the UFS consumer
   registers its notifier. The consumer prepares Deep H8 and core
   clocks, performs PMIC decoupling, registers the core notifier, then
   resumes prep and core (`ufs.ko` `0x9c18`–`0x9c8c`, `0x9e48`–`0x9e74`,
   `0xc6e0`–`0xc724`).
2. When the consumer gets a core transition, its `PRE_ON` notifier
   waits for PHY `0x11`, then programs TOP patch controls, resistor trim
   and HS-LSS (`ufs.ko` `0xc470`–`0xc638`). Its `ON` notifier waits up
   to 10 ms for PHY `0x10`, then up to 400 µs for TOP `+0x8` bit 4
   (`0xc4e0`–`0xc654`, `0xd0c0`). REFCLK setup, link-time reset release
   and calibration follow readiness. The full v28 diagnostic already
   gave the PHY the same 10 ms and skipped the TOP poll when PHY stayed
   at `0x11`.
3. CPM maps prep `0x222` and core `0x220` to LPCM8 PSM1, with on targets
   2 and 0. Prep-on can return success from states 0 through 2.
   Prep 3→2 clears CPM `0x9c00941c` and `0x9c00a004`. Core-on can
   return success from states 0 or 1. From state 2 the custom callback
   calls the LDO1S/LDO24S enable helper, then writes `1` to CPM
   `0x9c00a014`. The engine waits for PSM1 completion
   (`cpm.img` text `0x39b84`–`0x39c26`, `0x3b148`, `0x3b1cc`, `0x83f8`).
   The sequencer patch is identical on B1 and D1. The loader consumes
   six records totaling 192 bytes followed by a four-byte zero
   terminator (`cpm.img` file offsets D1 `0x60720`, B1 `0x5fcc8`).
   It writes one controller word at `0x9c009008` and 41 words of
   sequencer SRAM at sparse addresses from `0x9c00b9b8` to
   `0x9c00ba60`. The sequencer's PHY gates remain unresolved.
4. DBL provides a separate firmware example of the transition. It
   checks HSIO-S readiness, HC `0x12` and PHY `0x11`, clears bit 0 at
   AP `0x3c00a010` and `0x3c00a004`, then sets bit 0 at `0x3c00a014`.
   It waits for HC and PHY `0x10`, then checks TOP bit 4 (`dbl.img`
   `0x69e8`–`0x6b38`, `0x6dec`–`0x6e9c`). The matching offset and
   sequence make `0x3c00a014` the likely AP view of the CPM trigger.
   The captured A and B ABL epochs both reached UFS gear 5 before
   Linux. ABL can enter Hibern8 and switch off external signals at
   handoff. The logs leave the inherited PSM state unmeasured.

The live v29 sample establishes that HC was already on while PHY was
off before the diagnostic's CPM startup frame. The v28 core vote was
issued and acknowledged with the same HC/PHY pair on either side.
CPM derives the PSM1 status address from the live descriptor at
`0x9c009018` and masks the low nibble (`cpm.img` text `0x87c0`,
`0x1942c`, `0x40c80`). The v30 capture below resolves the AP status
address to the HC register at `0x3c00c210` and shows state 0 before
both votes, a state that satisfies both CPM requests.
The saved stock logs leave open whether provider force-on or a later
consumer resume first brought the PHY up after handoff.

For the next diagnostic, look for CPM's `Started p state change` and
`Chg p state` records for LPCM8 PSM1 target 0 (`0x080100`). An
earlier crash snapshot preserved both records for prep-off target 3
(`0x080103`). Pair the trace with PSM1, HC and PHY samples across the
core vote. Keep the NV backup gate above before any new power-control
writes.

## v30 LPCM8 PSM1 diagnostic

D1 ABL's UFS core status query (`abl.img` `0x20cb0`, `0x49070`)
selects PSM1 at AP LPCM base `0x3c009000`. The AP getter reads the
controller's PSM count from header bits 13:8 and descriptor 1 at
`0x3c009018` (`0x7b7a0`, `0x7b848`). The descriptor supplies the
status register address. ABL (`0x7b7bc`, `0x7b8c0`, `0x4936c`) and CPM
(`0x87c0`, `0x1942c`, `0x40c80`) use equivalent address calculations
and read the low nibble as the PSM state. The saved GC access-control
DT places the header, descriptor, and known status words in the same
HSIO-S LPCM region. The trial below verified Linux access and the
decoded address on this D1 handset.

The v30 fixture samples around `pm_runtime_resume_and_get()` for prep
and core. When the HSIO-S wrapper reads `0x10`, it records HC, PHY,
and the descriptor. It reuses the existing AP sample if the decoded
address matches the wrapper (`0x3c00b108`), HC (`0x3c00c210`), or PHY
(`0x3c00d108`). Any other decode is logged and skipped. An unavailable
mapping, inactive wrapper, or invalid PSM count also results in a skip.
The new diagnostic only reads MMIO and retains the v29 link-only
configuration, vote provenance, and PHY/TOP readiness polls.

The offline `7.3.0-rc6-omamobile-grizzly-uic-v30` build uses local kernel
commit `132b85b41f606322f5ba773bcdd3ba48c0673dbc`. It passed the
ARM64 `W=1` build, all 8,192 decoder field combinations, and the mocked
MMIO and log guards. The packed device tree matches v29. Both AVB
signatures, the five image hashes, D1 handoff bounds, and saved
Fastboot capacities passed. The v30 archive SHA-256 is
`8c66c5f9cb954dcf883d7ceaccc599053a9a8f17a3961e88a9f1456b4b8f76f1`.

### v30 slot B result

On 2026-11-24 one attended B boot captured the four samples below. The
live descriptor `0x00063143` selected the AP HC status word at
`0x3c00c210`. PSM1 decoded from its low nibble.

| Vote | Sample | LPCM8 PSM1 | HC raw | PHY raw |
| --- | --- | --- | --- | --- |
| Prep | Before | `0x0` | `0x00000010` | `0x00000011` |
| Prep | After | `0x0` | `0x00000010` | `0x00000011` |
| Core | Before | `0x0` | `0x00000010` | `0x00000011` |
| Core | After | `0x0` | `0x00000010` | `0x00000011` |

The driver issued both MBFS votes and recorded return code 0. The PHY
stayed at `0x11` until the 10 ms poll timed out with `-110`, so the TOP
poll was skipped. The sampled values match the CPM already-satisfied
conditions. The firmware branch itself remains unobserved.

USB SSH, ramoops, and `SYSTEM_LAST_KMSG` recorded all four samples.
Both retained consoles recorded the timed warm restart. Stock D1 booted
on A with enforcing verity and the factory VBMeta digest. The owner
approved this one trial without the fresh NV backup. The existing
backup gate applies to subsequent trials.

## Stock D1 core and prep cycle

**ABL full initialization can cycle both domains before Linux.** The
warm-init branch skips the full sequence (`abl.img` `0x20bf4`–`0x20c0c`).
The full path requests core OFF followed by prep OFF when the
boot-context lookup returns 4, the core status query fails, or the
query reports the core on (`0x20c98`–`0x20d3c`). That query reports on
when LPCM8 PSM1 is 0. Either failed OFF request aborts initialization.
ABL then requests prep ON, programs TOP, requests core ON and checks
TOP bit 4 (`0x20d5c`, `0x20e28`, `0x20e98`–`0x20eac`). The saved
full-init marker follows the optional OFF pair and occurs on the
branch that skips the pair as well. The captures leave the actual
OFF requests unconfirmed.

The ABL writes use the LPCM mailbox service (`0x08`, operation 1).
Controller group 1 maps to LPCM8. Core selector 0 and prep selector 2
both use the PSM1 transition table in CPM (`cpm.img` text `0x3968c`,
`0x39cac`, `0x39b0c`, tables `0x63184` and `0x631ec`). The ABL prep
entry uses PSM2 for its local status-query index. Its write selector
targets PSM1. The service requires the LPCM controller to be powered.
Linux MBFS power callbacks reach the same CPM dispatcher through
`0x45178`.

| Request | PSM1 target | CPM condition and result |
| --- | --- | --- |
| Core OFF | `2` | State `3` satisfies the request. Other states require LPCM8 **PSM3 = `1`**. From `0`, the callback (`0x3b12c`) waits for a nested transition to `3`, calls the prep-on callback (`0x3b148`) and waits for exactly `2`. From `2`, the request can leave it there. State `1` has no `1`→`2` callback. |
| Prep OFF | `3` | State `3` satisfies the request. From `0` or `1`, CPM uses callback `0x3b174`. From `2` it uses `0x3b1f0`. All three paths wait for `3`. |
| Prep ON | `2` | States `0` through `2` satisfy the request. From `3`, the prep callback runs and CPM waits for `2`. |
| Core ON | `0` | States `0` and `1` satisfy the request. From `2`, the core callback calls the analog rail helper and asserts the UFS power trigger. |

The request targets are `2 → 3 → 2 → 0`. They can put PSM1 in state
`2` immediately before core-on when the power-off conditions hold and
the transitions complete. ABL's LPCM service reaches hardware without
the per-client MBFS vote arbitration. Linux MBFS OFF only releases the
caller's vote. Other holders can keep the physical domain active
(`cpm.img` text `0x287fc`, `0x2883c`–`0x28884`).

The physical callback table comes from LPCM8 descriptor `0x2000b730`
and its PSM1 rows at `0x2000b708`. For the `0`→`2` edge, the outer
wait rereads PSM1 with an equality comparator (`cpm.img` text
`0x8492`, `0x8f24`, `0x3b836`). A future trace of this edge should
pair the core OFF request with `Started p state change` for
`0x080102`, the nested `0x080103` records and `Chg p state` for
`0x080102`. `0x080102` also means prep ON when paired with that
request. The direct qualification for core ON is a guarded PSM1
sample of `2` immediately before the vote.

The older CPM logs contain `spmR exec 53` and target `0x080103`.
Firmware resource table `0x64040` maps ordinal `53` to prep `0x222`.
That confirms a physical prep-off in those epochs. The saved
archives contain no corresponding target `0x080102` or `0x080100`
completion record. A successful `pm_runtime_put_sync_suspend()`
alone would leave the physical result unknown. Genpd can skip OFF
for a busy domain or a rejected provider request, and the Malibu
provider leaves an inherited vote alone.

**Stock Android's healthy probe requests power.** Its force-on provider
can raise an off vote, and the UFS consumer gets prep then core. The
stock GKI queues genpd power-off work when it attaches a virtual domain
(`Image` `0xb27104`–`0xb2721c`). An idle, eligible domain could therefore
go off before the consumer gets it. Genpd can also evaluate the prep
parent after powering off core (`Image` `0x168190`). The saved stock
logs leave those transitions unobserved. The provider's `sync_state`
clears any boot hold and leaves the transition decision to genpd.

The UFS driver explicitly releases core then prep during power-down
and takes prep then core on recovery or resume. The full cycle in
the HCE pre-change notifier is gated by `UFSHCD_EH_IN_PROGRESS`
(`ufs.ko` `0xa11c`–`0xa198`, `0xdfe4`–`0xe02c`). It is an error
recovery path. The live v30 samples establish the inherited PSM1 `0`
case and leave the stock Android probe's physical off/on history open.

## v31 LPCM8 PSM3 diagnostic

The D1 CPM core-OFF action selects LPCM8 PSM3 and compares its low
nibble with `0x1` (`cpm.img` text `0x631a0`, `0x39bf8`–`0x39c1c`).
The adjacent `HsioSSd.v` resource (`0x221`) uses PSM3 with ON state
`0` and OFF state `1`. The merged D1 B0 DT declares that domain
(`hsio_s_sd_pd`) under UFS core. The domain has no `force-on` property
or consumer reference in that DT. Its state at handoff remains
unmeasured.

D1 ABL's LPCM descriptor loop (`abl.img` `0x49274`–`0x492a4`) calls
the AP getter at `0x7b848`. It checks the controller's PSM count,
then reads descriptor offset `0x10 + 8 * index`. For LPCM8 PSM3 that
is AP `0x3c009028`, in the same header page as PSM1. The descriptor
selects the actual status register. The v31 trial below supplies the
live descriptor and decoded address.

v31 captures HC, PHY, PSM1 and PSM3 before and after both votes. With
the wrapper on, it reads PSM3's descriptor only if the LPCM header
reports at least four PSMs. The diagnostic logs the descriptor and
its decoded address. It reuses a status word only when the decode
matches one of the three known AP samples. `PSM3_eq_1=yes` or `no`
reports the sampled low nibble. `unknown` means the status was
skipped. A skipped PSM3 sample leaves the PSM1, HC and PHY samples
available. The fixture adds no power-control writes or votes.

The offline `7.3.0-rc6-omamobile-grizzly-uic-v31` build uses local kernel
commit `2fe5a3a92f1b38a22011b5755c0046b69a022dcc`. The ARM64 `W=1`
build, all 8,192 decoder combinations per PSM, and mocked guard and
logging cases passed. The packed DT matches v30. Both AVB signatures,
all five image hashes, the D1 handoff bounds, and the saved Fastboot
capacity checks passed. The v31 archive SHA-256 is
`804db33ed3380d4adaf3c2a15577e2d9fc7a599e843902126727c459161c7b77`.

### v31 slot B result

On 2026-11-24 one attended B boot sampled before and after each prep
and core vote. The LPCM8 header `0x01914420` reported four PSMs. In
all four samples, PSM3 descriptor `0x00021325` resolved to AP status
address `0x3c00e108`. The v31 allowlist skipped that address with
`-ERANGE`, so `PSM3_eq_1` was `unknown`.

PSM1 was `0`, HC was `0x10`, and PHY was `0x11` in all four samples.
Both votes were issued and returned 0. The PHY readiness poll timed
out with `-110`, so the TOP bit 4 check was skipped.

USB SSH, ramoops, and `SYSTEM_LAST_KMSG` each captured all four vote
samples. The retained logs also captured the timed warm restart.
Stock D1 returned on A with enforcing verity and the factory VBMeta
digest. The owner approved this one trial without the fresh NV backup.
The backup gate applies to later trials.

## v32 guarded PSM3 status read

The v31 descriptor `0x00021325` puts the PSM3 status word `0x5108`
bytes from the LPCM8 base. CPM reads the corresponding address
`0x9c00e108` as a 32-bit status word for the core-off precondition
(`cpm.img` text `0x39c00`, `0x1942c`, `0x19742`). ABL's AP getter
uses the same decoder and an ordinary 32-bit load (`abl.img`
`0x7b7bc`, `0x7b804`, `0x7b8c0`), giving AP `0x3c00e108`.

D1 GC's active `hsio_s_rfw0_lpcm` region assigns one access rule
(`0x30301`) to `0x3c009000`–`0x3c012fff`. DBL applies the rule from
the trusted-firmware DT (`dbl.img` `0x351dc`–`0x35224`, `0x34888`).
That region covers the exact target and the descriptor, HC and PHY
words already read from Linux on D1. The saved evidence supports a
guarded status read. The exact AP load and effective access policy at
that word still need hardware validation.

v32 maps a single 32-bit status word at `0x3c00e108`. It only reads
that word for PSM3 on Grizzly while the HSIO-S wrapper reports on,
the header includes PSM3, and the live descriptor matches
`0x00021325` and decodes to that address. It keeps the v31 vote logs,
including `PSM3_eq_1` and skipped-read reasons. It keeps the existing
vote and power sequence. The NV backup gate still applies to the
full fixture before hardware use.

The offline `7.3.0-rc6-omamobile-grizzly-uic-v32` build uses local kernel
commit `f504759241af7a6ed5e29a9207e59276afeb8043`. The ARM64 `W=1`
build, all 8,192 decoder combinations per PSM, and mocked guard and
vote-log cases passed. The packed DT is byte-identical to v31. Both
AVB signatures, all five image hashes, the D1 handoff bounds, and the
saved v31 Fastboot capacity checks passed. The v32 archive SHA-256 is
`cdd3633f2172f3e1edf5d28d360436a34ba183932ff1d07458e9dcf59d36dce9`.

### Interpreting a v32 capture

Use the exact v32 release banner and one boot's console per source.
For `SYSTEM_LAST_KMSG`, use the matching entry. Look for all four
`prep`/`core` × `before`/`after` rows through `vote_ret=`, both CPM
`vote=` rows, and the PHY/TOP poll results. Match the retained
console and its timed-restart marker after the return to stock A.
The driver buffers the snapshots until the readiness check returns.
Use the phase labels for read order and the CPM `vote=` rows for
vote provenance. A partial capture may end before the rows print.

At each phase, count an exact PSM3 sample when the row contains
descriptor `0x00021325`, address `0x3c00e108` and a raw value whose low
nibble matches both the state field and `PSM3_eq_1`. Keep a guard
skip, a missing row and a suspect all-ones read distinct. The driver
can also report `yes` or `no` for a descriptor that reuses a sampled
AP word. Check the descriptor and address before interpreting it.

| PSM3 at `0x3c00e108` | Core-OFF implication while PSM1 is `0` |
| --- | --- |
| `1` | Satisfies the CPM PSM3 dependency at that sample. An OFF request also needs the other votes and transition conditions to allow it. |
| `0` | `HsioSSd.v` is on. CPM would reject a core-OFF action that reaches this dependency while the sampled state holds. |
| Other valid state | Fails the equality test. The SD ON state is specifically `0`. |
| Unavailable or suspect | The dependency remains unmeasured. Preserve the raw row or the last observed stage if the row is absent. |

The PSM3 predicate belongs to core OFF (`cpm.img` text `0x631a0`,
`0x39bf8`–`0x39c1c`). Prep ON, prep OFF and core ON have no PSM3
predicate. If v32 repeats PSM1 `0` and PHY `0x11` across both ON
votes, the sampled state satisfies both CPM ON requests. An issued
vote with `ret=0` confirms the MBFS request and state readback.
Evidence of a physical core-on transition requires a PSM1 change
from `2` to `0` or a matching CPM `Started p state change` and
`Chg p state` pair for `0x080100` (decimal `524544`) in the same boot.
`p_state_sync_with_comp` marks entry to the transition engine. A
missing trace is inconclusive. Keep the PHY `0x10` and TOP bit 4
results alongside the transition evidence.

### PSM3 in the retained CPM timeout

The bugreport collected after v22 retains an earlier LPCM8 timeout
in `bl_data.bin`. The same `31.166094` CPM record occurs in the v21
archive and precedes the v22 slot B bootloader epoch. The trace
records prep-off completion (`0x080103`) followed by
`ufs_deeph8_enable: 0`. CPM's Deep H8 disable handler waits for
LPCM8 PSM1 `== 1` followed by PSM2 `== 1` (`cpm.img` text
`0x49b4e`–`0x49b6e`). The first wait expired with PSM1 still at `3`.

The timeout dump iterates PSM indices from zero and prints the raw
words in that order (`cpm.img` text `0x85f8`–`0x8716`). It gives
`0x10`, `0x13`, `0x11` and `0x11`. The fourth word establishes
PSM3 state `1` at timeout.

This establishes PSM3 state `1` in the CPM failure snapshot. The
v32 trial below confirms state `1` earlier in the sequence, around
both ON votes.

### v32 slot B result

On 2026-11-24, one attended B boot of
`7.3.0-rc6-omamobile-grizzly-uic-v32` reached RAM rescue and USB
SSH with zero UFS disks. LPCM8 header `0x01914420` and PSM3
descriptor `0x00021325` passed the read guard at `0x3c00e108`.

| Sample | PSM3 raw (state) | PSM1 raw (state) | HC raw | PHY raw |
| --- | --- | --- | --- | --- |
| Prep before | `0x11` (`1`) | `0x10` (`0`) | `0x10` | `0x11` |
| Prep after | `0x11` (`1`) | `0x10` (`0`) | `0x10` | `0x11` |
| Core before | `0x11` (`1`) | `0x10` (`0`) | `0x10` | `0x11` |
| Core after | `0x11` (`1`) | `0x10` (`0`) | `0x10` | `0x11` |

Both MBFS votes were issued and returned 0. PHY readiness timed
out at `0x11` (`-110`); the driver skipped TOP bit 4. The samples
satisfy the PSM3 core-OFF dependency and match PSM1's
already-satisfied state for both ON requests. They leave the PHY
startup callback unobserved.

USB SSH, ramoops and `SYSTEM_LAST_KMSG` agree on all four samples
and the poll results. Both retained sources carry the timed warm
restart marker. Stock D1 slot A completed boot with enforcing
verity and the factory VBMeta digest. The owner approved this one
trial without the fresh NV backup. The backup gate applies to
later trials.

## Stock D1 UFS device supply order

The merged D1 B0 DT maps UFS `vcc-supply` to BUCK11S and
`vccq-supply` to BUCK13S. In two saved healthy stock A boots, the
regulator framework applied the board voltages before `ufs.ko`
loaded. The stock capture after v28 shows BUCK11S going from
0.8 V to 2.5 V at 0.939304 s, BUCK13S from 0.24 V to 1.2 V at
0.941418 s, then `ufs.ko` loading at 1.016069 s. The stock capture
after v22 repeats that order at 0.996844 s, 0.998663 s and 1.065180 s.
These log lines show voltage programming. The device GPIO controls
rail enable separately.

v32 suppresses regulator registration's `apply_uV`. Its explicit
device preparation sets both selectors after the PHY/TOP readiness
gate. v32 stopped at the PHY poll with LDO1S and LDO24S enabled and
selectors 70 and 160. The device buck selectors at that point remain
unmeasured. The stock driver polls PHY/TOP in the core-domain ON
notifier. Its normal probe calls device-on directly after the prep
and core gets (`ufs.ko` `0x9e64`–`0x9e74`). The healthy stock logs
leave notifier execution and the time of PHY power-up unobserved.

v33 adds CPM GETs for BUCK11S (`0x33`) and BUCK13S (`0x35`) in the
existing windows before TOP preparation and after the PHY/TOP poll
or core-vote error. It keeps the v32 PSM, vote and LDO fields. The
stock targets are selectors 170 and 192. A matching selector pair
would establish that the target voltages were configured at the
samples even if the GPIO held the rails off. A different pair would
establish the voltage-setup difference and leave its effect on the
PHY to test separately. A negative value records a failed GET.

The extra requests are read-only and add mailbox traffic before TOP
preparation. The probe retains its v32 vote, PMIC write, readiness
and clock release sequence. The NV backup gate applies to a hardware
trial of the full fixture. The older CPM panic and the unobserved
core-off completion leave a power-cycle test pending.

The offline `7.3.0-rc6-omamobile-grizzly-uic-v33` build uses local
kernel commit `c1ef5a9dd4d1fe119ae0150eed3affc864df48d4`. ARM64
`W=1`, the mocked CPM GET and PSM guard cases, and the Malibu UFS
and supplier schema checks passed. The packed DT matches v32.
Both AVB signatures, all five image hashes, the D1 handoff bounds
and the saved v32 Fastboot capacities passed. The v33 archive
SHA-256 is
`109ae3cc43626c0390b6df32fab44dfe3dc0be9e5a7bb00730b7d4a7fd62c706`.

### v33 slot B result

On 2026-11-24, one attended boot of
`7.3.0-rc6-omamobile-grizzly-uic-v33` reached RAM rescue. The live
SSH smoke test produced an empty capture because its release check
still expected v32. Ramoops and `SYSTEM_LAST_KMSG` agree on both
rail samples, all four vote samples, the PHY timeout, the TOP skip
and the timed restart marker.

| Rail | Before core | After PHY poll |
| --- | --- | --- |
| BUCK11S (VCC) | Enabled, selector `170` (2.5 V) | Enabled, selector `170` (2.5 V) |
| BUCK13S (VCCQ) | Enabled, selector `192` (1.2 V) | Enabled, selector `192` (1.2 V) |
| LDO1S | Enabled, selector `70` | Enabled, selector `70` |
| LDO24S | Enabled, selector `160` | Enabled, selector `160` |

Both votes were issued and returned 0. PSM3 remained `1`, PSM1 `0`,
HC `0x10` and PHY `0x11`. The PHY poll timed out with `-110`, so TOP
bit 4 was skipped. CPM reported both device bucks enabled and at
the stock selectors before the timeout. The missing voltage setup
hypothesis is resolved for this boot. A physical PSM1 transition
before core-on remains unobserved.

Fastboot returned and stock A completed boot with enforcing verity
and the factory VBMeta digest. The owner approved this one trial
without the fresh NV backup. The backup gate applies to later trials.

## Core vote release after v33

Holding Linux's prep reference keeps the prep genpd active. A D1
core-OFF action from PSM1 `0` still runs the nested physical `0`→`3`
leg within CPM. The nested callback at `0x3b174` asserts
`UfsPhyReset`, then programs the LPCM power sequence. D1 DBL names
the AP alias `0x3c01b040` in the `UfsPhyReset` descriptor, and D1's
LPCM8 reset mailbox table maps `phy_rst` to the same register on the
CPM side. The stock reset driver uses argument `0` for assert and `1`
for deassert. The `0x3b12c` callback continues to the `3`→`2` setup
after its nested request returns. CPM separately checks the outer
target `2`.

Core-on from `2` enables the analog rails and triggers the sequencer
(`cpm.img` text `0x3b1cc`–`0x3b1e2`). The software callback contains
no explicit PHY reset deassert. Stock's explicit deassert happens
during PHY initialization (`ufs.ko` `0xb2fc`), after the genpd ON
readiness check when that notifier runs. The sequencer's effect on
the reset remains unverified. v33 also shows that preparing Deep H8
and core clocks leaves PHY at `0x11`. Stock's ordinary Hibern8
exit path expects an existing link. ABL can skip its Hibern8 entry
under some handoff conditions, so its teardown marker alone leaves
the controller state at v33's failure point unknown.

A general-purpose runtime suspend is insufficient as a diagnostic
trigger. It consumes the reference even when genpd keeps the domain
on. A queued genpd power-off pass can later revisit it. The CPM MBFS
`.v` result is the caller's vote (`cpm.img` text `0x28ca4`,
`0x288bc`). The `.r` read returns the caller's notification bitmap.
The global vote helper (`0x2892c`) has an internal call from the
AOSS recovery path, outside those MBFS reads. The existing interface
therefore gives no aggregate vote qualification for an attempted
release.

| Qualification | Evidence to record | Stop and return |
| --- | --- | --- |
| Preflight | Establish a quiescent pre-link controller, validated stock recovery, the NV backup, an owned core vote and current guarded PSM1 `0`, PHY `0x11` and PSM3 `1`. Retain the prep and HSIO-S references and both prepared clocks. | A missing qualification keeps this experiment offline. The v33 console has no HCE or queue-idle sample. |
| One core OFF | Use genpd's existing provider, with a one-shot PRE_OFF guard to veto automatic repeats. Record the provider result, logical genpd state, and stable physical HC/PSM1 `0x12` with PHY `0x11`. Require the D1 descriptor mappings and a valid wrapper sample. | A skipped release, rejection, or a different raw PSM ends the experiment. Preserve the logs and hold the remaining resources for the stock return. |
| One core ON | Confirm stable state `2` again before stock TOP preparation. Use the existing genpd resume and capture the physical PSM1, PHY `0x10` and TOP bit 4 results. | A failed guard or poll ends the attempt. Keep Deep H8 prepared and use the attended stock return. |

The OFF path touches reset and can reach CPM's internal timeout
before Linux can recover. The cycle remains offline.

## v34 guarded PHY reset acknowledgment

D1 DBL selects `UfsPhyReset` at `0x1312c` and reads the exact AP
status word `0x3c01b05c` during its reset pulse. The loads at
`0x25880` and `0x258c0` wait for bit 12 clear and set respectively.
D1 ABL's direct reset path polls the same bit (`abl.img` `0x7b638`,
`0x7b63c`). Its UFS PHY initialization issues reset release
(`0x1fd38`–`0x1fd44`) after the earlier TOP readiness wait attempt.
The D1 GC trusted-firmware policy covers `0x3c01b000`–`0x3c01cfff`
with the same `0x30301` rule as the PSM words read by Linux in v33.
Those observations support the guarded AP read. Its value at the
Linux timeout remains unmeasured.

After an acknowledged core vote and a readiness timeout, v34 first
prints the original polls and vote snapshots. It then samples the
reset word once if a fresh check shows HSIO-S and HC at `0x10` and
PHY at `0x11`. Both UFS clocks and the domain references are still
held. The driver prints the address before issuing the load. It
logs the raw word and decodes bit 12. `released=0` means asserted,
`released=1` means released, and an all-ones word is unknown. An
unavailable mapping or a different power state skips the load.

A released acknowledgment would establish that this reset is
released while the PHY PSM is still off. An asserted acknowledgment
would establish the reset state at the timeout. Stock orders the
explicit release after its readiness stage, so an asserted status
alone leaves the cause of the timeout open. The v34 additions only
read status. The existing NV backup gate and stock A return apply
to an attended slot B trial of the full fixture.

The offline `7.3.0-rc6-omamobile-grizzly-uic-v34` build uses local
kernel commit `1d2178811c18f1ae44bf5b073f0a8ab7d1a4839f`. ARM64
`W=1`, the mocked PSM and reset guards, and the Malibu UFS and
supplier schema checks passed. The packed DT matches v33, and
the rescue ramdisk uses the same legacy LZ4 settings with the
v34 restart marker. Both AVB signatures, all five image hashes,
the D1 handoff bounds and saved v33 Fastboot capacities passed.
The v34 archive SHA-256 is
`3fce8569b57d234566f5b114510474b8e6d2ffb707c8e5f5245705cbf78289a7`.

### v34 slot B result

On 2026-11-24, one attended boot of
`7.3.0-rc6-omamobile-grizzly-uic-v34` reached RAM rescue and
authenticated USB SSH with zero UFS disks. Both prep and core
votes were issued and returned 0. Across the four samples PSM1
stayed at `0`, PSM3 at `1`, HC at `0x10` and PHY at `0x11`.
The PHY poll timed out with `-110`, so TOP bit 4 was skipped.

The fresh power guard qualified one read of `0x3c01b05c`. The
two live console captures contain the address breadcrumb and
the same word `0x1001`, with bit 12 set. `UfsPhyReset` was
released at the timeout while the PHY PSM remained at `0x11`.
The device buck settings repeated v33's enabled selectors `170`
and `192` before the core vote and after the poll.

USB SSH, ramoops and `SYSTEM_LAST_KMSG` agree on the reset word,
vote samples and polls. Both retained sources carry the tagged
warm restart marker. Stock D1 slot A completed boot with enforcing
verity and the factory VBMeta digest. The owner approved this one
trial without a fresh NV backup. The backup gate applies to later
trials.

## v35 external device-on diagnostic

D1 `ufs.ko` resumes prep and core, then calls the external device-on
helper (`0x9e6c`–`0x9e74`, `0xc6e0`–`0xc724`). Its PHY and TOP
readiness checks sit in the core transition notifier. The platform
probe has no separate readiness check between domain resume and
device-on. The saved stock console leaves the PHY state at device-on
unknown. In v34 the first PHY poll times out before the driver raises
the device enable GPIO or enables GPIO REFCLK. Its enabled buck
readbacks describe the PMIC settings, while the external enable
remains low.

The stock device-on sequence selects the active pins, asserts
RESETB low, raises the device enable, and waits 1.5–2 ms. With
HS-LSS enabled and its GPIO present, it drives LSS and waits
another 100–110 µs. It then enables GPIO REFCLK and waits
300–310 µs before releasing RESETB
(`ufs.ko` `0xc728`–`0xc88c`). Grizzly's helper
uses the same physical GPIO levels and takes LSS from the live FDT.
The GPIO clock is LPCM8 selector 0. D1 CPM uses the local gate block
at `0x9c0196c0` for both operations (`0x37a74`, `0x37c1c`,
`0x18cd8`). The gate path checks its own acknowledgment. The PHY,
Hibern8 and Deep H8 conditions belong to separate clock paths.

v35 keeps the v34 GPIO setup, PMIC decoupling, prep/core votes, rail
readbacks and first PHY/TOP result. The fallback requires successful
domain resumes, a timeout from the PHY poll itself, a released PHY
reset acknowledgment, and a fresh sample with the wrapper on,
HC `0x10` and PHY `0x11`. It runs the existing rail preparation and
external device-on once. That path can reach the 2.5 V VCC and
1.2 V VCCQ selector requests and external GPIO writes. The NV
backup gate applies to a later hardware trial. A GPIO REFCLK
enable failure stops before RESETB release. The fallback logs
HC and PHY immediately after successful device-on
and repeats the 10 ms PHY poll and conditional 400 µs TOP poll when
the wrapper is on and HC remains at `0x10`. The fallback stops before
HCI access even if both polls pass.

If the post-device-on sample shows the wrapper accessible, the
fallback logs the poll or guard result and uses the existing
external device-off sequence. That sequence uses the stock order
(`ufs.ko` `0xdec0`–`0xdf9c`) and
keeps prep/core and Deep H8 held. Look for a GPIO REFCLK unprepare
error from the CPM clock driver separately because the clock
framework's unprepare callback cannot return an error. If the
wrapper sample fails, the fallback skips further child reads and
device-off and records `-EAGAIN` with the wrapper sample. If only
the HC guard fails, `-EAGAIN` precedes the external device-off result.
An initial readiness pass still follows the existing link/Hibern8
diagnostic. A PHY at `0x10` after the fallback would establish that
the PHY PSM is on. The complete readiness gate also requires TOP
bit 4. A time-matched control would be needed to attribute the
transition to an external signal.

The offline `7.3.0-rc6-omamobile-grizzly-uic-v35` build uses local
kernel commit `350616f47bfd8403e0653ca326cc4a0dd1d08ab8`. ARM64
`W=1`, the mocked PSM and device-on guards, and the Malibu UFS
and supplier schema checks passed. The packed DT, `vendor_boot`
and `dtbo` match v34. Both AVB signatures, the five image hashes,
the D1 handoff bounds, legacy LZ4 round-trip and saved v34 slot
capacities passed. The v35 archive SHA-256 is
`f4dbc1e5e03039db1e5a64c591ce96a1458619f7f7304588c7a8a30114c467f8`.

### v35 slot B result

On 2026-11-24, the Mac staged all five images and matched the 8,192
supplied bytes in the `vendor_boot_b` readback. The attended slot B
boot reached authenticated USB SSH in RAM rescue with zero UFS disks.
Both domain votes were issued and returned 0. PSM1 stayed at `0`,
PSM3 at `1`, HC at `0x10` and PHY at `0x11` across the votes. The
first PHY poll timed out and reset acknowledgment was `0x1001`
with bit 12 set. The LDO and buck readings matched v34.
The live FDT retained the UFS alias, 296 bytes of calibration,
a four-byte resistor trim and the HS-LSS property.

Rail preparation and the external device-on helper each returned 0.
Before and immediately after device-on, the wrapper and HC read
`0x10` and PHY read `0x11`. The second 10 ms PHY poll also returned
`-110` with final PHY `0x11`. Both polls skipped TOP bit 4. The
external sequence completed in software and failed to bring the
PHY to `0x10` within the second poll. The fallback stopped before HCI.

During device-off the provider logged
`failed to unprepare clock malibu-ufs-gpio-ref: -110`, while the
device-off helper returned 0. Clock framework unprepare is void, so
the helper result covers GPIO and pinctrl operations. The roughly
144 µs from the pre-cleanup log to the warning is consistent with
the firmware's local timeout reply (`-13`, translated to `-110`),
given the 1,000 ms AP mailbox timeout and the preceding successful
GPIO REFCLK prepare. The raw firmware return and physical clock
state remain unconfirmed.

The two USB SSH captures, ramoops and `SYSTEM_LAST_KMSG` agree on the
device-on results, both PHY polls and the GPIO REFCLK timeout. Both
retained sources contain the v35 timed warm-restart marker. Fastboot
returned with Volume Down held. The owner did not press Power.
Stock D1 slot A completed boot with enforcing verity and the original
stock VBMeta digest. The owner approved this single v35 trial without
a fresh NV backup. The backup gate still applies to later trials.

### Other offline findings

D1's CPM transition table at `0x2000b730` has zero entries for PHY
PSM2 (`cpm.img` text `0x63220`, `0x83b6`–`0x83cc`). The traced
stock path uses PSM1 `2→0`. A separate supported PHY power-up
callback remains unverified. CPM's timeout reporter also reads
each PSM's sequencer word at status `+4`, with PC in bits 12:0 and
RP in bits 25:13 (`0x8650`–`0x8714`, `0x19554`). The derived AP
addresses for HC, PHY and PSM3 are `0x3c00c214`, `0x3c00d10c`
and `0x3c00e10c`. Linux access to those words remains unverified.
Two distinct LPCM8 OFF timeout epochs retained in the v21 and v22
archives record raw states `0x10/0x13/0x11/0x11` and PC values
`196/165/50/4` for PSM0–3. All four RP values are zero. Both
epochs have target tag `0x080103` for PSM1→3 and end with a PSM1
timeout at state 3 waiting for 1. The same epochs contain
`set_gate fail 34`, where 34 identifies the GPIO REFCLK descriptor.
The line omits the operation direction and raw result. The
PC/RP records identify the sequencer positions during those OFF
failures. A stock successful ON example remains unobserved, and
equal snapshots would leave intervening sequencer execution unresolved.

D1 ABL reads HCI CAP at `0x3c2d0000` after successful core-on and
before its later TOP wait (`abl.img` `0x20ce8`–`0x20cf4`). The
resume branch also reads CAP (`0x742d8`, `0x74340`). The stock reads
have no simultaneous PHY PSM sample. The available evidence
leaves HCE and doorbell access in the v34 state unverified, so
the guarded CPM core OFF/ON trial remains offline.

## v36 REFCLK status diagnostic

The D1 stock ABL descriptor for `hsio_s_gpio_ref_clk` (file
`0x1f3508`) maps to LPCM8 selector 0. Its disable path uses
command `0x01000802`, argument `1` (`abl.img` `0x20a4c`,
`0x48adc`). The saved v28 `bl_data.bin` contains a panic-warm
epoch where ABL reports raw `-13` for that clock and continues
through calibration and HS gear 4. The same warning and gear
result appear in other distinct saved panic-warm epochs. The
warning can occur with a working UFS link later in that boot.

In the D1 CPM selector-0 disable routine (`0x18d14`–`0x18de8`),
bit 0 of `0x9c0196c8` determines whether to request a Q-channel
shutdown and wait for `(status & 0x11) == 1`. The routine clears
the enable request at `0x9c0196c4` and waits for bit 8 of
`0x9c0196dc` to clear. Either poll can return `-13`, which
Linux translates to `-110`. The CPM log strings distinguish
`qch timeout` from `dis timeout`. A later clear gate bit would
leave the first-stage handshake and its timing unresolved.

D1's clock status operation `2` looks up the selector, reads the
requested status bit and compares the result with the argument
(`cpm.img` `0x386be`–`0x38702`, `0x383d8`–`0x3849c`).
These single-bit requests return `1` for set and `0` for clear.
A negative firmware result and a mailbox transport error are
logged separately.

| Sample | Command | Argument | D1 CPM word and bit |
| --- | --- | ---: | --- |
| GPIO REFCLK gate acknowledgment | `0x02000802` | 1 | `0x9c0196dc` bit 8 |
| GPIO REFCLK auto-gating | `0x02000802` | 2 | `0x9c0196d8` bit 0 |
| M-PHY REFCLK gate acknowledgment | `0x02010802` | 1 | `0x9c01b15c` bit 8 |

D1 B0 sets `google,enable-refclk-acg`. Stock `ufs.ko` disables
auto-gating on GPIO and M-PHY REFCLK before device-off in the HCE
and system-suspend paths (`0xa164`–`0xa170`, `0xabe4`–`0xabf4`,
`0xada0`). v35 leaves the inherited settings in place. Its M-PHY
`clk_get_rate()` reads a provider constant of 38.4 MHz. Stock
Linux obtains that clock at `0x9b74` and uses it for auto-gating
later. These status bits do not measure either clock waveform.

v36 keeps v35's PHY, TOP and reset checks. Once the same fallback
qualifies, it samples all three bits before external rail
preparation. A failed baseline sample ends the fallback there.
After the second PHY/TOP result it samples the GPIO gate before
and after external device-off. Those cleanup samples do not
replace the original poll and cleanup results. The clock
provider records the raw firmware reply or transport error for
the existing GPIO prepare and unprepare requests. v36 adds no
clock writes. The v35 rail and GPIO path and its NV backup gate
still apply to a later hardware trial.

The stock system suspend/resume path drops core then prep and
reacquires prep then core (`ufs.ko` `0xad8c`–`0xada0`,
`0xb00c`–`0xb03c`). It operates on an initialized host.
Seven saved D1 Android logs reached UFS before the power
provider's delayed `sync_state` callback and contain no
physical PSM samples. That callback clears `boot_stay_on`
(`power_controller.ko` `0x44a8`). A supported transition to PSM1
state `2` from the diagnostic's pre-link state remains unverified.

The offline `7.3.0-rc6-omamobile-grizzly-uic-v36` build uses local
kernel commit `92963fecee888738f30fc11c4a9898322229e419`. The ARM64
`W=1` build, mocked PSM, device-on and clock reply checks, and
Malibu supplier schema checks passed. The packed DT, `vendor_boot`
and `dtbo` match v35. Both AVB signatures, all five image hashes,
the D1 handoff bounds, legacy LZ4 round-trip and saved v35 slot
capacities passed. The archive SHA-256 is
`4dad07b3764e471f20a8104a394ed6584c3d507d8e4d5f83a104005780f2979f`.

### v36 slot B result

On 2026-11-24, all five images staged successfully and the Mac matched
the 8,192 supplied bytes in the `vendor_boot_b` readback. The single
slot B boot reached authenticated USB SSH in RAM rescue with zero
UFS disks. Both votes were issued and returned 0. PSM1 stayed
at 0, PSM3 at 1, HC at `0x10` and PHY at `0x11`. The first PHY
poll timed out and reset acknowledgment was `0x1001`.

| Measurement | v36 result |
| --- | --- |
| Before external device-on | GPIO REFCLK gate `0`, GPIO auto-gating bit `0`, M-PHY REFCLK gate `1` |
| Device-on and second poll | CPM GPIO prepare reply `0`, device-on returned `0`, PHY stayed at `0x11` and timed out again |
| Before external device-off | GPIO REFCLK gate `1` |
| During external device-off | CPM GPIO unprepare reply `-13`, translated to `-110` |
| After external device-off | GPIO REFCLK gate `0`, device-off helper returned `0` |

Both TOP polls were skipped and the fallback ended before HCI.
The GPIO unprepare response identifies a CPM-side failure.
The later gate sample shows bit 8 clear. A Q-channel timeout or
a late gate acknowledgment remains possible. GPIO auto-gating
was already disabled at the baseline sample. The firmware passes
the enable flag directly to this bit on the auto-gating branch
(`0x37c60`–`0x37c62`, `0x18f12`, `0x18f32`). The M-PHY gate
was already acknowledged while the PHY PSM reported off. The
capture leaves physical clock activity and the PHY power-state
transition unresolved.

Both USB SSH captures, ramoops and `SYSTEM_LAST_KMSG` agree on the
clock samples and both PHY polls. The two retained sources include
the v36 warm-restart marker. Fastboot returned while Volume Down
was held. Stock D1 slot A completed boot with enforcing verity and
the factory VBMeta digest. The owner approved this single trial
without a fresh NV backup. The backup gate still applies to later
trials.

## v37 UFS configuration clock at handoff

D1 DBL qualifies HSIO-S on, HC `0x12` and PHY `0x11` in its
UFS init path (`dbl.img` code `0x69e8`–`0x6b18`). It switches
the Q-channel mode of `HSIO_S_UFS_CFG_CLK` (`0x6d68`–`0x6d74`,
`0x25bf4`), then reads AP `0x3c0199d8` and sets bit 0 to disable
automatic gating (`0x6da8`–`0x6db8`, `0x25c88`, `0x25ca4`).
The config register is gate base `0x3c0199c0` plus `0x18`.
This happens before the UFS power trigger at `0x6e1c`. The
active GC rule covers AP page `0x3c019000` with permission
`0x30301`, as it does the previously sampled PSM/reset ranges.
The stock read witnesses HC `0x12` in DBL. The trial below
tested the Linux handoff state with HC `0x10`.

ABL's traced shutdown callback disables GPIO REFCLK at selector
0 (`abl.img` `0x750e4`–`0x750f8`, `0x20230`, `0x20a4c`–`0x20a64`).
Its group-1 clock table has no direct gate at offset `0x9c0`.
The similarly named `hsio_s_ufs_clk` entry is CPM selector 2,
with divider and mux addresses and no gate pointer (`cpm.img`
text `0x6573a`). D1's B0 DT has no consumer for selector 2.
The traced shutdown path leaves the fate of DBL's config bit
through the full handoff unmeasured. GPIO REFCLK's v36
auto-gating bit belongs to a separate register and control.

v37 takes one guarded sample before the Linux CPM startup frame
and one after successful completion. Each phase logs the wrapper,
HC and PHY first. The config read requires the Grizzly PSM mappings,
an on wrapper, HC `0x10` and PHY `0x11`. The kernel records the
exact AP address before the load and reports `0xffffffff` as
unknown. Bit 0 set means DBL's disable-gating setting is present
at the sample. The read gives neither clock activity nor the
cause of the PHY stall.

The DBL witness runs in a different AP exception level. The
entry chain `0x5068`→`0x17fc4` reaches `0x19b50`, which
programs EL3 registers and calls the UFS init path at `0x6338`.
v37's panic traverses the Linux EL1 SError handler. The B1 and
D1 GC FDT entries for all 11 nodes under the HSIO-S wrapper
match byte for byte. The ESR and those static tables leave the
runtime firewall and clock conditions unresolved.

The observation bundle compiles out `SCSI_UFS_MALIBU` and uses
the v29 handoff-only DT. The UFS SGIA, pinctrl and regulators
are disabled. The UFS node remains available for ABL's calibration
fixup and the CPM PSM mapper. The UFS host cannot run the v36
prep/core, PMIC or device-on sequence. Normal CPM startup and
the USB RAM rescue path still run.

The offline `7.3.0-rc6-omamobile-grizzly-uic-v37` build uses local
kernel commit `48372ded713ceec02fca9bb7225fda08787f193d`. The ARM64
`W=1` build, guard and sample mocks, and Malibu supplier schema
checks passed. The packed DT matches the v29 observation bundle.
Both AVB signatures, all five image hashes, legacy LZ4 round-trip,
D1 handoff bounds and saved v36 slot capacities passed. The archive
SHA-256 is
`a3373132703449cdcf90b1fe269d4e7ef506f7282ceb103d2d9789a80f5b53a9`.

### v37 slot B result

On 2026-11-24, all five slot B writes passed and the Mac matched
the 8,192 bytes supplied in the `vendor_boot_b` readback. The
single test boot logged HSIO-S `0x10`, HC `0x10` and PHY `0x11`
at 0.100823 s. At 0.100844 s the sampler printed its AP address
`0x3c0199d8`. At 0.100859 s the kernel recorded asynchronous
SError `0xbe000011` and panicked in
`malibu_cpm_ufs_cfg_sample+0x118/0x1a0`.

Disassembly of the exact packed kernel places the MMIO load
`ldr w3, [x21]` at `+0x110`, followed by its `dmb oshld` at
`+0x114` and the recorded PC at `+0x118`. Ramoops and
`SYSTEM_LAST_KMSG` agree on that sequence. No register value or
post-handshake sample was logged. The AP read fails under the
tested Linux handoff conditions. The available evidence does
not identify which clock, ownership or interconnect condition
caused the abort. The static GC rule and the wrapper guard
are insufficient to qualify that read in this state.

Fastboot returned before USB rescue or the 90-second rescue timer.
The Mac selected A and verified stock D1 completed boot with
enforcing verity and the pre-trial factory VBMeta digest. The
observation bundle remains a reproducible record of the failed
access. The sequencer PC/RP words remain untested.

A read-only bugreport from the returned stock A boot preserved
the board's `bootlogs/bl_data.bin`. It records one slot B Linux
handoff with the v37 initramfs boundary, then a GDMC warm crash
reset with CDD reason `0xbab9` (Early Kernel PANIC). ABL logged
`Invalid log header: bypass` for BL31 and reported that ramdump
was disabled. The following cold boot entered Fastboot with
Volume Down, and stock A booted after selection. The archive
has no `0xc101` EL1-pending-SError classification or valid BL31
fault log. It establishes the reset sequence and leaves the
fabric cause unresolved.

### Stock power-dashboard visibility

D1's `google_powerdashboard.ko` reads cumulative software state
and residency records from a CPM shared-memory section. Its
`pwrblk_hsio_s_show` at `0xe5c` displays three rows for the HSIO-S
wrapper and two PSM slots. The read at `0x2b64` takes repeated
copies to detect concurrent updates. State records contain a
32-bit entry count and a 64-bit residency in microseconds. Saved
D1 boots show section 1 published at AP `0x0ea210d0`. The stock
driver discovers it through CPM destination `0x68` and maps the
returned address, so the saved address describes those boots.
CPM maps HSIO-S LPB 26 to dashboard block 25
(`cpm.img` `0x20358`, `0x1fffe`). The two child rows have no
verified mapping to LPCM8 PSM1, PSM2 or PSM3. Firmware startup
initializes the section and clears its records (`0x1e348`,
`0x1fe54`). The counts cover a CPM firmware epoch.

On the connected stock D1 slot A, the ADB shell can find
`/sys/devices/platform/powerdashboard`. Reading its
`pwrblk_hsio_s` attribute returns `Permission denied`.
`dumpsys powerstats` lists `SSWRP_HSIOS` ON and UFS HIBERN8, with
no child PSM counters in the dump. Direct power-stats HAL
`dumpsys` returns `FAILED_TRANSACTION`. These reads leave stock A
running. The v37 bundle does not add a dashboard client or access
the unverified sequencer PC/RP words.

## v38 passive UFS power-state timeline

D1's LPCM mailbox destination `0x08` has no verified raw
PSM getter. The handler (`cpm.img` `0x22a48`, `0x3968c`)
dispatches operation 0 into `SetOpLvl` and operation 1 into a
power-state request. Operation 1 reads the hardware PSM as
part of qualification and can invoke the transition engine.
Operation 3 returns a software cache byte for selected LPCM
IDs from 9 through 40 (`0x8d84`, `0x39d34`, `0x398f8`).
For LPCM8 that byte is always zero, independent of PSM1.
ABL's Boolean core status getter uses a descriptor-derived
AP load instead (`abl.img` `0x49070`→`0x492bc`→`0x7b7bc`).
The 188 clock descriptors searched by CPM `0x37da0` have no
gate pointer for the DBL configuration clock at `0x9c0199c0`.
The v36 clock status query therefore provides no alternate
selector for the v37 register.

Stock D1 marks HSIO-S, prep and core `force-on`, and its
provider issues an initial ON for a zero client vote before
each domain's registration (`power_controller.ko` `0x3ba4`,
`0x3d14`–`0x3d48`, `0x3e3c`). The three stock DT nodes
omit `google,boot-stay-on`. The provider's later `sync_state`
is therefore outside their initial force-on path. The Grizzly
provider defers the lookups and first votes until a consumer
requests power. v36 issued the prep and core ON votes and
verified primary client votes `1`. CPM's `.v` read distinguishes
an active vote `1` from a queued vote `2`
(`0x288fe`–`0x28918`, `0x28ca4`).

CPM can add a new caller to an already active resource bitmap
and return success without scheduling a physical transition
(`0x2860e`→`0x286f8`, `0x28700`–`0x28714`).
If the transition handler runs with PSM1 already `0`, that state
also satisfies the core ON request. Neither mechanism would
exercise the verified PSM1 `2→0` PHY power-up leg. The v36 vote
readbacks alone cannot distinguish these cases. The internal
aggregate bitmap getter at `0x2892c` appears in the AOSS restart
diagnostic. Its resource table omits the three UFS domain IDs,
and no stock AP consumer of that getter was identified.

v38 removes the v37 config-clock load and uses the three
already sampled PSM words at `0x3c00b108`, `0x3c00c210` and
`0x3c00d108`. It logs them before and after successful CPM
startup-frame retirement, then about 2 and 20 seconds after
the provider finishes probing. Every sample checks the wrapper
before reading HC and PHY. The delayed worker runs only in
the observation build with `SCSI_UFS_MALIBU` compiled out.
The DT keeps UFS SGIA, GPIO, standby pinctrl and regulators
disabled. v38 issues no new UFS mailbox commands or power
requests and leaves ABL's UFS calibration target available.

The two delayed samples are beyond stock's saved first UFS
calibration time and the provider's later sync callback.
A persistent PHY rise would show that the state can change
without this Linux UFS driver. Equal samples would rule out
a sustained rise at those points. The samples cannot detect
every intervening transition or reproduce stock's force-on
and consumer timing.

The offline `7.3.0-rc6-omamobile-grizzly-uic-v38` build uses local
kernel commit `ae148563e6e759bf0ba87dedc000970bcfc45d02`. ARM64
`W=1`, mocked wrapper and scheduling checks, and Malibu supplier
schema checks passed. The packed DT matches the v29 observation
bundle and v37. Both AVB signatures, all five image hashes,
legacy LZ4 round-trip, D1 handoff bounds and saved v37 slot
capacities passed. The archive SHA-256 is
`1fa7819bcdd4f43bc4f69a89240840cb87ff41d4f87a70737b22b1b655053663`.

### v38 slot B result

On 2026-11-24, all five slot B writes succeeded and the Mac matched
the 8,192 bytes supplied for `vendor_boot_b`. The single test boot
reached authenticated USB SSH in RAM rescue with zero UFS disks.
The live FDT reported the UFS alias, 296 bytes of PHY calibration,
four bytes of trim and HS-LSS present. The console has no UFS
prep/core vote, PMIC decoupling or device-on sequence markers.

| Sample | Kernel time (s) | HSIO-S | HC | PHY |
| --- | ---: | --- | --- | --- |
| Before CPM startup frame | 0.096747 | `0x10` | `0x10` | `0x11` |
| After startup-frame retirement | 0.096802 | `0x10` | `0x10` | `0x11` |
| First delayed sample | 2.120989 | `0x10` | `0x10` | `0x11` |
| Second delayed sample | 21.480999 | `0x10` | `0x10` | `0x11` |

The startup frame and the passive wait left the same sampled
states. The PHY remained off at both delayed samples with the
UFS host compiled out. The capture leaves transient transitions
between samples and the effects of stock's force-on and consumer
sequence unresolved.

Late USB SSH, ramoops and `SYSTEM_LAST_KMSG` agree on all four
samples. Both retained copies include the timed warm restart
marker at 90.146010 s. The owner reported a black screen for
2–3 seconds before Fastboot appeared with Volume Down held.
The Mac selected A and verified stock D1 completed boot with
enforcing verity and the pre-trial factory VBMeta digest.

## v39 initial provider vote diagnostic

The stock provider processes HSIO-S `hsio_s.v` (`0x1a`),
UFS prep `HsioSUfsPrep.v` (`0x222`), and UFS core
`HsioSUfs.v` (`0x220`) in order. For each D1 `force-on`
node, it looks up the MBFS file, reads the client vote and
requests ON if the vote is zero. It registers the domain
afterward and adds its parent links in a second pass
(`power_controller.ko` `0x3b94`, `0x3ba4`,
`0x3d14`–`0x3d48`, `0x3e3c`, `0x3f9c`–`0x4008`).
The successful stock kernel log places this provider before
`ufs.ko`. It contains no guarded PSM sample between them.

v39 enables `COMMON_CLK_GOOGLE_MALIBU_CPM_UFS_VOTE_DIAG`
for this build. The option is off by default and requires
the Malibu UFS driver to be disabled. It also requires the
existing Grizzly-specific PSM mappings to succeed. The CPM
provider checks the same three MBFS votes in order before
registering each domain. It reuses the serialized request,
deferred completion, and readback path. The log identifies
inherited and newly issued votes. Each vote has guarded
wrapper/HC/PHY samples before and after success. An error
stops the diagnostic sequence. The driver continues provider
registration so unrelated consumers retain their usual path
when the mailbox remains available.

The diagnostic holds acknowledged domains on until reboot
to exclude generic idle power-off from the experiment. D1
stock does not mark these three domains permanently on.
The v38 startup and delayed PSM samples, UFS-calibration
handoff, RAM rescue, and return timer apply. The UFS host and
raw SCSI storage drivers are disabled, and the diagnostic
adds no explicit OFF, reset, or AP PMIC write. A successful
firmware request may still exercise CPM's rail and sequencer
path.

The offline `7.3.0-rc6-omamobile-grizzly-uic-v39` build
uses v38 kernel commit
`ae148563e6e759bf0ba87dedc000970bcfc45d02` plus the initial
vote patch. ARM64 `W=1` compilation and six mocked cases
passed. They cover the opt-in and mapping gates, inherited
and new votes, failure short-circuiting, the wrapper check,
and the exact request order. The ramdisk and packed DT
match v38 byte for byte. Both AVB signatures, five image
hashes, D1 handoff bounds and the saved reader-trial slot
capacities passed. The archive SHA-256 is
`3babe4f2562ff676c55dec4fb14d1d8de09f0be04dd022455ebc433f23f83fdf`.
The verified D1 NV recovery snapshot captured the state
before stock A restarted. Check freshness before any
PMIC or CPM power-control trial as described by the backup
procedure.

### v39 slot B result

On 2026-11-24, the owner approved one boot using the verified
existing NV recovery snapshot without a fresh comparison against
the phone. Fastboot accepted all five slot B writes. The Mac
matched all 8,192 supplied bytes in the `vendor_boot_b` readback.
The single boot reached authenticated USB SSH in RAM rescue with
zero UFS disks. The live FDT reported the UFS alias, 296 bytes of
PHY calibration, four bytes of trim and HS-LSS present.

| Sample or vote | Kernel time (s) | Result | HSIO-S / HC / PHY |
| --- | ---: | --- | --- |
| Before CPM startup frame | 0.094747 | | `0x10` / `0x10` / `0x11` |
| After startup-frame retirement | 0.094786 | | `0x10` / `0x10` / `0x11` |
| `hsio_s.v` before and after | 0.096360 / 0.096496 | Inherited ON, `ret=0` | `0x10` / `0x10` / `0x11` both times |
| `HsioSUfsPrep.v` before and after | 0.096516 / 0.097056 | Issued ON, `ret=0` | `0x10` / `0x10` / `0x11` both times |
| `HsioSUfs.v` before and after | 0.097076 / 0.097519 | Issued ON, `ret=0` | `0x10` / `0x10` / `0x11` both times |
| First delayed sample | 2.120802 | | `0x10` / `0x10` / `0x11` |
| Second delayed sample | 21.480792 | | `0x10` / `0x10` / `0x11` |

HC was on before the CPM startup frame. CPM accepted the prep
and core client votes while PHY remained at `0x11` at every
sample. The samples rule out a sustained PHY rise through the
last observation in this provider-only sequence. They leave
transitions between samples and the effect of stock's later UFS
consumer sequence unresolved.

The 10 PSM snapshots and three vote results match across late
USB SSH, ramoops and `SYSTEM_LAST_KMSG`. Both retained copies
record the timed warm restart at 90.137367 s. The Mac saw
Fastboot 133 seconds after the boot request, selected stock A
and verified D1 completed boot with enforcing verity and the
pre-trial factory VBMeta digest.

## Stock D1 UFS consumer trace

The stock consumer attaches the core notifier, resumes prep then
core, and proceeds to external device-on. Its PHY and TOP readiness
polls are inside the conditional core notifier (`ufs.ko`
`0x9e60`–`0x9e78`, `0xc6e0`–`0xc724`). Earlier mainline link
probes stopped at their unconditional PHY gate. In v35 and v36
the external device-on fallback completed with PHY still at
`0x11`. The stock driver also conditionally acquires the two
analog regulator enable references before the GPIO and clock
setup (`0x9750`, `0x977c`). The mainline readiness failures
already recorded both analog rails at their stock enabled
selectors, so the reference ordering alone leaves the cause
unresolved.

The stock GKI enables `CONFIG_TRACE_MMIO_ACCESS`. Its
`rwmmio_post_read` event records the result of each driver's
existing traced read. D1's UFS `readl` wrapper at `0xcfc4`
passes the caller's return address to that event. The PHY wait
helper's three call sites return to `0xd0f8`, `0xd144` and
`0xd15c`. The core ON notifier's TOP polls return to `0xc514`,
`0xc54c` and `0xc648`. The stock merged tree maps PHY status to
`0x3c00d108` and TOP readiness to `0x3c2e0008`. The trace
filter uses their 4 KiB page offsets and the log extractor
requires the matching symbol and call-site offset. It emits
the register value without the virtual address.

The RAM inventory fixture `--ufs-power-trace` mounts a
private trace instance after checking the factory preloads
and before loading the remaining stock modules. The first
trace used 64 KiB per CPU. The verified inventory boot already had
`power_controller.ko` loaded at PID 1. Its
`send_mail_mbfs` and `recv_result_mbfs` events can capture
consumer-phase request and result pairs for resources
`0x1a`, `0x222` and `0x220`. Earlier provider probe events
are outside this window. The fixture uses the stock
supplier and UFS module list. It stops tracing at the
first complete inventory or the bounded inventory timeout,
then runs the existing five-parent, nine-target NV read-only
guard if inventory passed. The existing 90-second warm return
timer runs independently.

Read the trace from the retained console after returning to
stock A. Require the arm and outcome markers, compare the
summary's retained and written entry counts, and check
`omitted=0` before interpreting an absent event. The summary
counts repeated readings even when the log collapses them.
PHY readings are from a shared wait helper and need timing
and vote context to identify the caller's power phase. A TOP
match is specific to the stock core ON notifier, after its
PHY check passed. A complete inventory with no recognized
PHY or TOP records leaves the physical transition unobserved.
A successful MBFS reply alone gives no physical PSM1 state.

The 2026-11-24 build retains the four D1 factory images.
Replacement `init_boot` SHA-256 is
`974126535afbf6361ce078bc13433f0347b9f0ec70a2994f4d1953f74c76c8b0`.
The initrd ends at `0x88fb7385`, below the FDT at
`0x8a000000`. The five image hashes, init boot AVB
signature, packed payload, saved slot capacities and saved
stock vendor boot readback passed. Twelve ARM64 BusyBox
mocks covered trace parsing, output limits, cleanup and PID
1 dispatch.

### Stock D1 slot B trace result

On 2026-11-24, Fastboot accepted all five slot B writes and the
full 64 MiB vendor boot readback matched. The trace armed at
0.968988 s, before `ufs.ko` loaded at 1.340166 s.

| Trace time (s) | Sample | Value |
| ---: | --- | --- |
| 1.501699 | PHY PSM | `0x11` |
| 1.502089 | PHY PSM | `0x10` |
| 1.502091 | Core ON notifier TOP status | `0x10` (bit 4 set) |
| 1.646228 | Later PHY PSM | `0x11` |

Stock observed PHY ON 390 µs after observing it OFF. Its core
ON notifier then read TOP ready, before the probe reported PHY
patching mode 0, applied calibration, registered the SCSI host
and reached HS gear 5. The later PHY read uses a shared helper
and does not establish which callback made it. The stock
inventory passed, and the NV guard verified five parent disks
and nine read-only targets.

The ring retained 1,362 of 3,234 events. It yielded four PHY
reads, one TOP read and zero MBFS vote records. The log collapsed
one repeated sample. Overwrite leaves the preceding vote history
unresolved, so the capture does not establish which request or
prior PSM1 state caused the PHY transition.

Ramoops and `SYSTEM_LAST_KMSG` match on all trace and outcome
markers and the timed restart at 90.866376 s. Fastboot returned
136 seconds after the boot request. The Mac selected A and
verified D1 completed boot with enforcing verity and its
pretrial factory VBMeta digest.

The follow-up build raises the trace buffer to 512 KiB per CPU
to retain the observed event volume. The event filters, output
cap, stock module manifest and return timer are the same.
Replacement `init_boot` SHA-256 is
`e36e7664d0e0563cd9e5b7f6467d72bedebee802405b1fa47f555bf7208841b0`.
The initrd ends at `0x88fb73f7`. The ARM64 trace mocks and
offline package checks passed.

### Stock D1 larger-buffer trace result

On 2026-11-24, one attended slot B boot used the 512 KiB per
CPU image. All five writes and the full 64 MiB vendor boot
readback passed. The trace armed at 0.944310 s, before
`ufs.ko` loaded at 1.311316 s.

| Trace time (s) | Sample | Value |
| ---: | --- | --- |
| 1.470826 | PHY PSM | `0x11` |
| 1.471468 | PHY PSM | `0x10` |
| 1.471469 | Core ON notifier TOP status | `0x10` (bit 4 set) |
| 2.381773 | Later PHY PSM | `0x11` |

The transition repeated between reads 642 µs apart. Stock
reported PHY patching mode 0, reached HS gear 5, and passed
the five-parent, nine-target NV read-only guard.

The ring retained all 3,224 recorded events. The extractor
reported three PHY reads, one TOP read, zero matched MBFS
records and zero omissions. The complete ring rules out
overwrite in this run. The earlier parser could reject
valid MBFS records, as described below, so the zero count
leaves the request history unresolved.

Ramoops and `SYSTEM_LAST_KMSG` agree on all nine trace,
guard and return records. The timed restart was at 90.834267 s.
Fastboot returned after 136 seconds. Stock D1 slot A finished
booting with enforcing verity and the pretrial VBMeta digest.

### Stock D1 provider event decoding

The exact D1 `power_controller.ko` formatter starts the MBFS
payload with a tab before the resource ID. The LPCM and LPB
formatters do the same and append a two-digit subdomain to the
ID. The first two fixtures required the ID at the start of the
payload, so valid records could pass the kernel filter and be
discarded in userspace. The retained summaries contain only the
parser output and cannot recover those records. The PHY and TOP
rows use a different event format and are unaffected.

The corrected fixture strips leading whitespace and captures the
send and result events for MBFS, LPCM and LPB. It counts each
family before applying the UFS resource selection and reports
unparsed records separately. The output keeps the existing cap,
512 KiB per CPU, and the PHY and TOP filters. The retained log
includes only selected resource IDs, direction, result and
timestamps. Check the ring counts, raw family totals, parse
failures and output omissions alongside the transition.

Replacement `init_boot` SHA-256 is
`ca6999db59afc09f65892e30ac5c79565252094bf5748169b0b6faa7ac991823`.
The image hashes, AVB verification, D1 handoff and slot fit,
ShellCheck, and five ARM64 BusyBox mock cases passed. The
corrected capture ran once on slot B on 2026-11-24.

### Stock D1 provider event trial result

Fastboot accepted all five writes and the full 64 MiB
vendor boot readback matched. The trace armed at 1.072057 s
and stock loaded `ufs.ko` at 1.452074 s.

| Trace time (s) | Stock event | Result |
| ---: | --- | --- |
| 1.607321 | UFS prep MBFS `0x222` ON request | |
| 1.607902 | UFS prep MBFS reply | `0` |
| 1.607937 | PHY PSM | `0x11` |
| 1.607949 | UFS core MBFS `0x220` ON request | |
| 1.608349 | UFS core MBFS reply | `0` |
| 1.608353 | PHY PSM | `0x10` |
| 1.608355 | Core ON notifier TOP status | `0x10` (bit 4 set) |
| 1.742234 | Later PHY PSM | `0x11` |

Stock's core request returned after 400 µs. The next PHY
read, 4 µs after the reply, saw `0x10`. The capture establishes
the MBFS route and places the physical change around the stock
consumer's core ON request. v39 issued the same prep and core
ON resource IDs while HC was already `0x10`, and its PHY stayed
at `0x11`. The stock trace contains no matching HC/PSM1 read
before core ON. It leaves the incoming PSM1 state and any
earlier pre-PID-1 power history unresolved.

The ring retained all 3,254 events. The extractor counted
36 MBFS events across all resources, including the four UFS
request and reply records. It found zero LPCM events, LPB
events, parse failures or output omissions. Stock reported
PHY patching mode 0, reached HS gear 5 and passed the read-only
guard for five parent disks and nine NV targets.

Ramoops and `SYSTEM_LAST_KMSG` agree on all 14 trace, guard and
return records. The timed restart was at 90.958568 s. Fastboot
returned after 133 seconds. Stock A booted with enforcing verity
and the pretrial VBMeta digest.

### Stock PSM1 visibility and CPM firmware trace

D1 `ufs.ko` maps the HC PSM word at `0x3c00c210` during
`ufs_google_init` (`0x95bc`–`0x95c4`). The core PRE_ON
and ON notifier paths poll the PHY mapping at
`0x3c00d108` (`0xc470`–`0xc498`, `0xc4e0`–`0xc4f8`).
The HC pointer feeds runtime-suspend checks at `0xe97c`
and `0xeb24`, and Hibern8 exit at `0xf03c`. Adding
`0x210` to the existing MMIO trace filter would catch those
later accesses. It would leave the pre-core PSM1 state
unobserved. The stock AP trace remains the reference for
the request and reply timestamps.

D1's CPM transition engine builds
`(LPCM ID << 16) | (PSM << 8) | target` at `0x8254`–`0x8264`.
The log at `0x83dc` uses the firmware string
`Started p state change` before the selected callback,
and `0x84d2` uses `Chg p state` after the completion
check. Both call the trace writer through `0x8efc` and
`0x329a8`. The string pointers `0x2001ff20` and
`0x2001ffb8` map to factory file offsets `0x8eb9c` and
`0x8ec34`. The writer and the call sites have logging
gates. A missing record needs a working capture control
before it can be interpreted.

Capture `0x080100` (524544) between the stock core MBFS
ON request and reply to identify a physical PSM1 transition
to state 0. The payload encodes the target. Within that
request, the traced CPM core-on branch admits the physical
callback at PSM1 state 2 and already satisfies an ON request
from states 0 or 1 (`0x39b84`–`0x39c26`, callback
`0x3b1cc`). Pair the start and completion records and
align firmware and AP timestamps before drawing that
inference. Tags `0x080102` and `0x080103` identify
targets 2 and 3 and need their request context.

The factory DT's `google,fwtp-cpm` node uses mailbox
destination `0x17` and a dedicated 16 KiB DMA pool at
`0x8cdf4000`. Stock lists `fwtp_cpm_module.ko` ahead of
`ufs.ko`. The driver requests the firmware interface,
initializes the reserved-memory device, allocates its
buffer and obtains the ring (`fwtp_cpm_module.ko`
`0x188c`, `0x1938`, `0x195c`, `0x20a0`, `0x20cc`).
Its notification worker decodes entries and converts
firmware timestamps to AP boottime. The driver's
`request_subscribe` path sends an IPC subscription
(`0x241c`, `fwtp_lib.ko` `0x3154`). That path changes
firmware trace state and uses shared DMA. Decoded text can
go to `fwtp_ftrace:fwtp` through `fwtp_dev_append_output`
(`fwtp_lib.ko` `0xc6c`–`0xd48`) when the driver's
`enable_ftrace` flag is set. This gives a capture path
without enabling the unfiltered kernel log output. Use a
boottime trace clock and compare the decoded record's
embedded timestamp with the AP MBFS events. The ftrace
record timestamp reflects AP drain time.

The inventory fixture omits `fwtp_cpm_module.ko` and its
additional dependencies `fwtp_lib.ko` and
`google_thermal_cpm_mbox.ko`. The thermal dependency
opens its own CPM mailbox at probe
(`google_thermal_cpm_mbox.ko` `0x780`, stock DT
`thermal-cpm-mbox` destination `0x0c`). A firmware
trace fixture must account for these additional probe
and subscription operations. Qualify decoded output and
clock alignment with a known record before treating a
missing transition tag as evidence.
No stock firmware transition record has been captured
for the successful provider-event trial.

### Offline D1 CPM trace fixture

The `--ufs-cpm-trace` build retains the stock kernel and
inserts the factory FWTP module and its two additional
dependencies before `ufs.ko`. It uses the read-only
`fwtp_cpm/cpm/trace` debugfs snapshot after inventory.
The D1 `fwtp_debugfs_trace_show` handler requests ring
metadata and decodes via the existing DMA buffer
(`fwtp_lib.ko` `0x1d24`–`0x1e7c`). This keeps
subscription and log output controls at their stock
settings. The read has an eight-second timeout and a
256 KiB cap. PID 1 drops the raw snapshot from RAM and
prints only the target records and capture summaries.

`fwtp_print_tracepoint` (`0x3860`–`0x397c`) formats the
firmware counter using the ring frequency. The text
prefix uses GTC seconds. The separate structured-event
decoder's boottime conversion does not apply to that
text. The fixture selects tracefs `boot` and brackets
each stock `gtc/current_ns` read with AP trace markers,
once immediately before loading `ufs.ko` and once
after inventory. The GTC reader converts the AP
architectural counter to nanoseconds. The parser
intersects the two measured AP-minus-GTC intervals
and accounts for the printed microsecond resolution.

Expect matched AP ring counts, `clock alignment=consistent`,
and a successful single core ON request/reply pair.
`core correlation=inside` requires one timestamped
`0x080100` start and one completion that can overlap the
selected core request, in order, and places both inside
that pair for every supported clock offset. Other
transitions entirely outside the core window are still
reported within the output limit. If the bounds overlap a
request boundary the fixture reports `uncertain`. It also
reports whether the timestamped firmware text extends
across the whole core window. That range cannot establish
continuous ring coverage or that firmware logging was
enabled for the entire interval. A missing record or
invalid clock bracket leaves the transition unverified.
Keep the existing NV guard and attended 90-second warm return.

The offline package preserves the four D1 factory images.
The current replacement `init_boot` SHA-256 is
`4f78f0d10a5e209f27ba019a5d02f593e7453fdaeb4b0efd4920b87330c4ce09`.
The initrd ends at `0x88fb813f`, below the FDT.
The five hashes, AVB signature, manifest dependency order,
packed payload and saved slot fit passed. Fifteen ARM64
BusyBox cases covered the clock and event matching,
including other transitions outside the core window, an
ambiguous second start, an empty snapshot and timestamp
coverage. Four more covered the capture helper. The live GTC
brackets and actual firmware ring output await an attended boot.

### D1 CPM trace hardware result

On 2026-11-24, all five slot B writes and the full 64 MiB vendor
boot readback passed. The AP trace armed on the `boot` clock at
0.982941 s. The FWTP module's probe failed at 1.391140 s with
`Failed to acquire DMA reserved memory`. In the exact module this
message follows a successful `memory-region` phandle parse and
a NULL `of_reserved_mem_lookup()` result (`0x191c`–`0x1920`,
`0x1b38`–`0x1b48`). It precedes pool attachment and allocation.

The retained Linux boot log has no initialized
`cpm_tracepoint_ipc_dma_buff` pool. Earlier saved D1 ABL epochs
record `dp(tp_dram_enable) 0x0 => 0` followed by successful FDT
disables of the CPM trace buffer, its IPC DMA pool, and the CAP
and VFA buffers. That explains how the factory phandle can
resolve while Linux has no reserved-memory entry. The current
trial did not independently capture the live FDT property.

The fixture stopped before loading `ufs.ko` when the firmware
debugfs ring failed to appear. The AP trace retained 3,133 of
3,133 events, including 32 MBFS events across other resources
and zero selected UFS records. No core ON request, firmware
`0x080100` event, clock bracket, or NV guard result was produced.
This run establishes a firmware capture prerequisite. The AP
core ON and PHY evidence remains in the earlier provider trial.

Ramoops and `SYSTEM_LAST_KMSG` agree on the failure and timed
restart at 90.855274 s. Fastboot returned after 133 seconds.
Stock D1 slot A finished booting with enforcing verity and the
pretrial verified boot digest.

### D1 `tp_dram_enable` policy

ABL reads `tp_dram_enable` from the debug-policy FDT's
`abl` node. Initialization selects that node from the
bootloader's policy buffer (`abl.img` `0x5959c`–`0x59668`).
The property getter accepts a four-byte big-endian value
(`0x9a668`–`0x9a710`). The Boolean helper returns false
on lookup failure. Value 1 returns true. Value 2 requires
the debugger-authorization bits checked in
`DBGAUTHSTATUS_EL1` (`0x591dc`–`0x59294`). The log value
can therefore read `0x0 => 0` when the property is absent.

ABL caches the Boolean and uses it for two boot-time
actions (`0x4237c`–`0x42534`). With the policy off,
it sends a CPM DRAM-trace disable request (`0x42290`),
and disables the CPM ring, CPM IPC DMA pool, CAP and
VFA reserved-memory nodes in the Linux handoff FDT.
The saved D1 logs report policy absent, policy hash
empty, and both disable actions. Restoring the Linux
pool description alone would leave the firmware-side
disable in place.

The stock DBL contains a path for replacing the legacy
DPM debug policy with a policy from the separate `dp`
partition. Stock ABL recognizes `dp_a` and `dp_b` as
policy partitions, separately from `devinfo` and the
radio NV targets. Its policy image hook passes the
candidate to a GSA signature check
(`0x5977c`–`0x597dc`, `0xa425c`). This is evidence
of a persistent policy mechanism. The captures contain
no accepted policy enabling DRAM tracing on this phone.

The traced stock fastboot DP handler queries
`get-abl-enabled` and prints the effective value
(`0x59b0c`–`0x59bfc`). The trace parser reads existing
trace output. The separate boottrace command uses
`boottrace-enabled` and exports `fastboot.boottrace`
(`0x84d14`–`0x84ecc`). None of those paths sets
`tp_dram_enable`. The audited stock paths offer no
verified temporary override through Android, fastboot,
boot arguments or the stock FWTP driver. An authorized
policy would use persistent debug-policy storage,
separate from the bootloader image and radio NV partitions.
This trace used only saved images and logs.

### D1 local CPM trace with DRAM export disabled

CPM emits the PSM transition start and change records through its
level-0 logger (`cpm.img` text `0x83dc`, `0x84d2`, `0x8efc`).
The writer uses a local enable byte at `0x200359f9` and selects
the level-0 descriptor at `[0x200031ac + 0x14]`
(`0x329a8`–`0x32a1a`, `0x21720`–`0x2173e`).
The local ring setup gives that descriptor a 32 KiB buffer at
CPM address `0x4002e8e0` (`0x215a8`–`0x215bc`).
The separate DRAM export flag at `0x200031ac` gates the flush
routine (`0x210a8`–`0x210c4`, `0x2198a`–`0x21990`).
Turning off DRAM export leaves the local write path available.
The CPM address does not establish a safe Linux AP mapping.

ABL's `tp_parse cpm` decodes the INFO and ERROR sections of
an existing crash-dump container (`abl.img` `0xc30a4`–`0xc3100`,
`0xc331c`–`0xc3440`, `0x53c84`–`0x53d34`). The lookup
checks the container header before resolving the named sections.
This is evidence for an archived trace reader. A live CPM ring
reader on stock Android and retention through a normal reboot
both remain unverified.

An offline scan of 35 saved `bl_data.bin` files found decoded
CPM trace sections in 26. Seven copies of the
`0x080103` start/change pair represent the two distinct LPCM8
off-timeout epochs already identified in the v21 and v22
archives. None of the decoded records had target `0x080100`
or `0x080102`. The archived trace demonstrates that local
CPM records are recoverable with the D1 DRAM policy off.
It leaves the successful stock core-on path unresolved.
The measurement still needed is a `0x080100` start and
completion between the stock `0x220` request and reply,
or a PSM1 sample immediately before that request.

### Stock D1 pre-core PSM1 sampling point

The exact factory `ufs.ko` (build ID
`7608bf1c6db66bb74927c99488e98bec65226fe5`) attaches its
notifier to the UFS core domain at `0x9e50`–`0x9e64`. It
resumes prep first and core second at `0xc708` and `0xc714`.
In the core PRE_ON notifier, `0xc4a0`
(`ufs_google_pd_notifier+0x68`) is reached only after the
stock PHY wait for `0x11` succeeds. It precedes the TOP
configuration and the provider's `0x220` ON request. This
is a more qualified sample than the one at the call to
resume core, which precedes the PHY wait.

At this instruction, `x19` holds the notifier pointer.
The pointer stored at `x19 - 0xd8` is the existing HC
mapping filled by `ufs_google_init` at `0x95bc`–`0x95c4`.
This is the same AP word at `0x3c00c210` that v30 verified
as PSM1. The low nibble is the state. The sample would
precede stock's remaining PRE_ON register operations.
Correlate it with a single subsequent core ON request and
successful reply. If state 0 or 1 precedes a PHY change,
the result narrows the explanation but leaves any change
in the interval before the request unobserved.

The factory kernel `6.12.81-android16-6-gf5369e7496cb-ab16467452-4k`
enables kprobe events and contains the callback for resolving
trace probes when a module loads. A module-qualified tracefs
probe can qualify the site without reading a new register.
At this site `w0` still contains the successful PHY wait
result. Only the timestamp and that result are needed to
check the ordering against the stock MBFS trace. Tracefs
memory fetches use generic no-fault kernel reads, so use
only register arguments for that probe.

A PSM1 sampler requires a kernel helper with an MMIO
accessor and the verified factory UFS layout. Arm it before
the first UFS bind, use only the existing non-error mapping
after the successful PHY wait, sample once, and preserve
normal notifier execution. The exact kernel image exports
`register_kprobe` and `unregister_kprobe`; it also enables
module versioning, CFI and GKI protected-symbol checks.
The local mainline build's symbol versions are for a different
kernel. The exact D1 module build inputs and loader admission
remain unverified, so this audit produced no bootable sampler.

The offline `--ufs-pre-on-trace` fixture arms the
module-qualified kprobe before loading the stock UFS modules.
It adds the notifier timestamp and signed PHY-wait result to
the existing AP power trace. It prints no probe address or
task name and deletes the event during cleanup. It uses no
extra MMIO reads and retains the stock NV guard and timed
return. During qualification, require matching trace ring
counts, zero omitted records, and one `pre-on phy_wait_ret=0`
between the prep reply and core ON request. Require the
successful core reply and subsequent PHY `0x10` as in the
baseline. A missing landmark leaves probe registration or
execution unverified. The landmark contains no PSM1 value.

The replacement `init_boot` SHA-256 is
`1c9ae402805419bbc98679644af9f32949b7c1d9907eed766b36690155be0de3`.
The four other images retain their D1 factory hashes.
The AVB check, saved slot capacities and handoff bounds
passed. Offline mocks covered landmark extraction,
address and task-name filtering, the ordinary power trace,
an empty landmark result, and tracing setup failures.
Live probe registration and timing remain untested.

### D1 PSM1 sampler module ABI

The factory kernel Image contains BTF and per-export module
version CRCs. The offline audit decoded 10,144 export entries.
It independently matched all 2,188 shared CRCs against
`__versions` from the 199 modules in the factory ramdisk.
None of those modules imports the kprobe or module-notifier
registration functions, so the Image supplies those CRCs.

| Kernel export | D1 CRC |
| --- | --- |
| `register_kprobe` | `0xcca4d86f` |
| `unregister_kprobe` | `0x1d045bd3` |
| `register_module_notifier` | `0x0a227d4d` |
| `unregister_module_notifier` | `0x0a227d4d` |
| `copy_from_kernel_nofault` | `0x2aacc14e` |
| `module_layout` | `0x797f2b3e` |

The decoded BTF gives `struct kprobe` size 128 bytes,
`offset` at `0x38` and `pre_handler` at `0x40`.
`struct module` is `0x640` bytes, with its
`init` and `exit` pointers at `0x188` and `0x5f8`.
Those three module-layout values match the factory
`ufs.ko`'s module section and initializer relocations.
Its vermagic names `gfc13f29942eb-ab16530091`, while
the running kernel Image names `gf5369e7496cb-ab16467452`.
The successful stock UFS trace establishes that this
factory pairing works. Both identifiers are needed when
tracking down the matching build artifacts.

### D1 PSM1 sampler build and loader verification

The public ACK source for D1 is commit
`f5369e7496cb231d2b41cbca078b8b69160ac22d`. Android CI
listed no downloadable artifacts for either exact build
ID (`16467452` or `16530091`). We prepared the matching
source with the embedded factory config and built the
[sampler](bringup/stock-psm1/grizzly_stock_psm1.c) with
Kbuild and the factory-derived `Module.symvers`.
Debian Clang 19.1.7 supplied the toolchain. The factory
compiler is Android Clang 19.0.1. Kbuild omitted
optional module BTF because the matching `vmlinux`
was unavailable.

All 15 undefined imports are present in the exact stock
loader's permitted import table. All 16 version CRCs,
including `module_layout`, match the factory Image.
The ARM64 module layout, initializer relocation offsets,
vermagic and GPL declaration passed the offline checks.
The module SHA-256 is
`ca17e8708c219353529834b72c478b5e5105d5f46132857717b5c73944a584fa`.

QEMU ran the unmodified D1 kernel Image in two tests.
On the standard virtual board, the stock loader reached
the sampler's init and the Grizzly guard returned
`-ENODEV`. With only the Grizzly compatible added to
the emulated device tree, the same stock loader admitted
the unsigned module. The sampler registered its module
notifier, reported a pending sample and unloaded cleanly.
Neither VM loaded the UFS module or accessed a PSM register.
The live UFS kprobe and PSM1 measurement still need an
attended trial.

Before adding the sampler to a trial fixture, require
the exact factory `ufs.ko` SHA-256
`24463ad9d4f63b3f5672883468f8e8228c0bfc75e91cd62299ffae38469350b0`
and arm the sampler before the first UFS module load.
It checks the stock release, Grizzly compatible and saved
PRE_ON instruction before sampling once. The read-only
`sample` module parameter reports registration and capture
status, or the raw HC word, PSM1 low nibble and monotonic
timestamp. Pair that timestamp with the stock `mono` AP
trace and its prep reply, core request, core reply and
PHY `0x10` sample. Preserve the NV guard and timed return
in that fixture.

### Packaged D1 PSM1 trace fixture

`pack-stock-inventory.py --ufs-psm1-trace SAMPLER_KO`
checks the loader-verified sampler and extracts and hashes
`ufs.ko` from the exact factory ramdisk. PID 1 checks the
live ramdisk's `/lib/modules/ufs.ko` against the packed
digest and requires UFS and the sampler to be absent from
`/proc/modules`. It arms the stock AP trace on `mono`,
loads the sampler, checks that its sample is pending, then
allows the stock module manifest to load UFS. A failed hash
or sampler preflight stops before vendor modules are loaded.

The console logs `UFS power trace pre-core PSM1` with
the raw word, low nibble and `mono_ns`, beside the
stock request/reply and PHY/TOP trace. Divide `mono_ns`
by 1,000,000,000 to compare it with the AP trace seconds.
Require a complete trace and a sample between a successful
prep reply and the core `0x220` ON request. Record the core
reply and subsequent PHY status. A missing sample logs the
registration and capture status when available. Cleanup
unloads the sampler. A capture failure still runs the
read-only NV guard when inventory completes. The existing
90-second warm return remains in place.

The checked five-image bundle retains the four factory
images. The replacement `init_boot` SHA-256 is
`24bcd0f7b848e8d602b3a071d258ef3af63c3c492eb9166a0029e749724bce59`.
The AVB verification, all image hashes, saved slot fit and
handoff bounds passed. Offline mocks covered the hash and
preload gates, arming order, sample logging, cleanup and
NV guard on capture failure. Live sampling remains untested.

An offline QEMU run exercised the exact packaged sampler
on the unmodified D1 kernel with a synthetic `ufs` module.
The synthetic module provided the same notifier symbol,
instruction and pointer layout, with guest RAM supplying
the test word. The module-load notifier registered the
probe before the synthetic module's init ran. Two hits
with words `0x12` and `0x10` retained only the first,
reporting PSM1 `0x2` and a monotonic timestamp. Separate
cases reported `-EFAULT` for a null HC mapping and
`-ESTALE` for an instruction mismatch. The sampler
and synthetic module unloaded cleanly after each case.
The remaining hardware check is the sample on factory
UFS and its timing relative to the real core vote.

### D1 PSM1 trace hardware result

On 2026-11-24 the owner approved one slot B boot using
the existing verified nine-partition NV backup. Its hashes
passed before staging. The backup predated the latest
stock Android boot. All five slot B images passed staging
and the full 64 MiB vendor boot readback matched.

| Monotonic time (s) | Stock event | Result |
| ---: | --- | --- |
| 1.552220 | Prep `0x222` ON reply | `0` |
| 1.552247 | PRE_ON PHY PSM | `0x11` |
| 1.552260842 | PRE_ON HC/PSM1 sample | Raw `0x12`, PSM1 `0x2` |
| 1.552276 | Core `0x220` ON request | |
| 1.552579 | Core `0x220` ON reply | `0` |
| 1.552583 | PHY PSM | `0x10` |
| 1.552584 | TOP | `0x10`, bit 4 set |

PID 1 verified the factory UFS module hash and armed the
sampler before loading UFS. The sample was about 15 µs
before the core request. Stock entered PRE_ON with PSM1
at state 2, the entry state for the physical CPM core-on
callback identified offline. The stock PHY reached `0x10`
after the reply and UFS reached HS gear 5. This contrasts
with v30's PSM1 state 0 on both sides of its accepted
ON vote and its unchanged PHY `0x11`. This fixture sampled
PSM1 once. The firmware transition tag and the earlier
sequence that put stock PSM1 in state 2 remain unobserved.

The AP trace retained 3,255 of 3,255 entries without
omissions or parse failures. The NV guard passed with
all five parent disks and nine targets reporting `ro=1`.
Ramoops and `SYSTEM_LAST_KMSG` matched on the sample,
votes, PHY/TOP and guard. The timed warm restart logged
at 90.886478 s. Fastboot returned 134 s after the boot
request. Stock A completed boot with enforcing verity
and the pretrial factory VBMeta digest.

### How stock D1 reaches PSM1 state 2 before core-on

The strongest candidate is stock Linux's early unused-domain
power-off sweep followed by the UFS consumer resuming prep.
The exact D1 B0 DT puts UFS core `0x220` under prep
`0x222`, which is under HSIO-S `0x1a`. The unreferenced
SD domain `0x221` is a child of core. The first three
domains have `force-on` and omit the persistent always-on
and boot-hold properties. The stock provider reads its
MBFS vote, issues ON if a force-on domain has a zero vote,
then registers a successfully initialized force-on domain
as logically ON (`power_controller.ko` `0x3ba4`,
`0x3d14`–`0x3d48`, `0x3e28`–`0x3e3c`).

The PSM1 trial logged `genpd: Disabling unused power domains`
at 0.858644 s, before PID 1 at 0.871336 s, trace arm at
1.002230 s and UFS module load at 1.398870 s. D1's exact GKI
`drivers/pmdomain/core.c` queues power-off work for all
registered domains in that late initcall (lines 1278–1297).
The worker checks active devices and child domains before
calling the provider's OFF path. After a successful OFF it
can evaluate the parent under the same lock chain (lines
856–940). Stock `power_off` passes enable 0 to the MBFS path
(`power_controller.ko` `0x4560`–`0x4570`). Other HSIO-S
consumers can keep the wrapper powered while UFS votes drop.
The later provider `sync_state` timeout at 11.490553 s
followed the UFS probe. The relevant nodes have no
boot-stay-on flag for that callback to clear.

Stock's first UFS prep and core resumes both reached the
provider's ON callback. The core PRE_ON notifier also ran.
The exact GKI's `genpd_power_on()` skips those callbacks
for an already-ON domain (lines 948–984). Together with
the successful force-on registration, this establishes
a logical OFF interval for both domains before those
resumes. The consumer trace saw only the two ON requests
and replies for `0x220` and `0x222`. The late sweep is the
leading source of the logical OFF interval. Its individual
MBFS writes and physical results fell outside the capture.
Genpd's later queueing on virtual-device attach (line 3110)
was inside the trace window and produced no UFS OFF record.

There are two compatible physical sequences. If the last
core OFF vote takes PSM1 from 0 to 2 and prep stays active,
the later prep ON can return with PSM1 already at 2.
If prep also powers off, PSM1 can reach 3 and the observed
prep ON supplies the 3→2 transition. Both account for the
measured 2 after prep and before core ON. CPM consolidates
the MBFS votes across clients, so successful Linux OFF
and ON replies leave the physical edges unconfirmed.

The ordinary ABL shutdown path can enter Hibern8 and
disable external REFCLK (`abl.img` `0x5f148`–`0x5f16c`,
`0x74dfc`–`0x750f8`, `0x209d8`–`0x20a64`). That
path contains no LPCM core or prep OFF request. ABL's
separate full-init cycle ends with core ON. The earlier
DBL UFS teardown marker belongs to the DBL-to-ABL leg
and qualifies HC and PHY `0x11`, before ABL brings up UFS
again (`dbl.img` `0xd618`–`0xd6fc`, `0x24878`–`0x24958`).
The live stock PSM1 state at the Linux handoff remains
unmeasured.

Mainline v39 sampled PSM1 0 around the early votes, then
set `GENPD_FLAG_ALWAYS_ON` on the three diagnostic domains
to keep idle genpd work from issuing OFF
(`clk-google-malibu-cpm.c` lines 1164–1191 in the v39
source). Its own unused-domain sweep at 0.126723 s therefore
skipped those votes after the 0.097519 s post-core sample.
The normal lazy mainline provider starts these domains
logically OFF and preserves inherited votes it did not
acquire. Matching stock resource IDs and successful ON
replies reproduces the requests while leaving stock's
pre-consumer power-off sequence untested.

The narrowest read-only discriminator is the stock GKI's
`pm_genpd` debugfs `current_state` and `idle_states` for
core and prep before UFS loads, paired with guarded
PSM1 samples immediately before and after the prep ON
vote. Nonzero idle usage counts completed logical OFF
operations, including an OFF callback that returns
success without changing the physical state. A guarded
3→2 sample pair identifies prep ON as the physical edge.
State 2 before prep calls for earlier evidence to identify
how it got there. The kernel's boot-time trace option
cannot be assumed to arm the vendor MBFS module's events
before they register. No phone operations were used for
this comparison.

### Offline D1 prep PSM1 and genpd fixture

`pack-stock-inventory.py --ufs-psm1-prep-trace SAMPLER_KO`
retains factory UFS hash verification and arms the sampler
with `prep_trace=1` before UFS can load. Immediately before
the `ufs.ko` insertion, PID 1 mounts a private read-only
debugfs and logs `current_state` and each idle state's time,
usage and rejected count for `hsio_s_ufs_prep_pd` and
`hsio_s_ufs_pd`. It unmounts debugfs before continuing.
Missing counters are reported without preventing the AP
trace, NV guard or timed return.

The two new probes bracket the prep runtime-resume call
in the exact factory `ufs_google_pd_get_sync`. The
pre-call instruction at `0xc704` and first instruction
after the call at `0xc70c` both retain the UFS pointer in
`x19`. The sampler verifies the original instructions and
uses the existing HC mapping at UFS offset `0x478`. It
reads HSIO-S wrapper status at `0x3c00b108` before each
prep sample and skips HC unless bits `[4:0]` equal `0x10`.
The original core PRE_ON probe retains its PHY-wait guard.
Each probe records one raw word, low nibble and monotonic
timestamp. Match the prep samples to a single `0x222`
ON request and its successful reply in the retained AP
trace, then check core `0x220`, PHY/TOP and the NV guard.
A missing vote or skipped sample leaves that edge
unverified. The 90-second warm return is retained.

The sampler has 19 stock-permitted imports and 20 matching
version CRCs. The unmodified stock kernel in QEMU accepted
the exact module with prep tracing enabled and unloaded it
cleanly. A separate synthetic QEMU case substituted an
emulated wrapper register and exercised both prep hooks
and the core hook, capturing `0x3`, `0x2` and `0x2` in
order. Shell mocks covered count parsing, missing or
malformed data, skipped samples and cleanup. The live
wrapper guard and PSM1 values await a hardware trial.

Replacement `init_boot` SHA-256 is
`d129532d285fdb18036b9c5e29b7990f371d9b0bccfdbb2e174521fc99cb77d8`.
All five image hashes, AVB, the saved slot-fit checks and
the D1 handoff bounds passed. The other four images match
the exact D1 factory files.

### D1 prep PSM1 and genpd hardware result

On 2026-11-24 the owner approved one slot B boot using the
existing nine-partition NV backup. The saved checksums all
passed. The backup predated the preceding stock A boot.
All five slot B writes and the full 64 MiB vendor boot
readback passed. PID 1 verified the factory UFS module hash
and armed the sampler before loading `ufs.ko`.

| Monotonic time (s) | Stock event | Result |
| ---: | --- | --- |
| 0.874621 | genpd unused-domain sweep | Queued OFF work |
| 1.453564 | Prep genpd before UFS load | `off-0`, S0 time 577 ms, usage 1, rejected 0 |
| 1.456176 | Core genpd before UFS load | `off-0`, S0 time 580 ms, usage 1, rejected 0 |
| 1.619009814 | PSM1 before prep ON | Raw `0x13`, state `0x3` |
| 1.619021 | Prep `0x222` ON request | |
| 1.619482 | Prep `0x222` ON reply | `0` |
| 1.619490866 | PSM1 after prep ON | Raw `0x12`, state `0x2` |
| 1.619496752 | PSM1 before core ON | Raw `0x12`, state `0x2` |
| 1.619510 | Core `0x220` ON request | |
| 1.619877 | Core `0x220` ON reply | `0` |
| 1.619881 | PHY PSM | `0x10` |
| 1.619883 | TOP | `0x10`, bit 4 set |

Each domain recorded one completed logical OFF before UFS
loaded. Subtracting the rounded S0 idle times places both
OFF completions near the early sweep. The AP trace first
armed at 1.050418 s, so it leaves their individual OFF
mailbox requests and physical transitions unobserved.
The prep samples bracket the successful `0x222` vote by
about 11 µs before the request and 9 µs after the reply.
They identify prep ON as the physical `3→2` edge in this
boot. PSM1 remained at 2 for core PRE_ON. The successful
core reply was followed by PHY `0x10` and HS gear 5.

The AP trace retained 3,265 of 3,265 records with no
omissions or parse failures. The NV guard passed for five
parent disks and nine targets, all `ro=1`. Ramoops and
`SYSTEM_LAST_KMSG` matched. The warm restart was logged
at 90.915341 s and Fastboot returned 134 s after the boot
request. D1 stock A finished booting with enforcing
verity and the original VBMeta digest.

### Mainline v40 idle prep diagnostic

The [v40 kernel source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/341a5e41a7836e346ba6bdabfed818ac1dd938de)
adds `COMMON_CLK_GOOGLE_MALIBU_CPM_UFS_IDLE_DIAG` on top of the
initial-vote diagnostic. The option defaults off and requires the
UFS host driver to be disabled. The Grizzly firmware mapping and the
HSIO-S wrapper guard qualify every child PSM sample.

| Phase | Pass condition | Stop and return |
| --- | --- | --- |
| Initial votes | Keep HSIO-S on. At the known inherited HC `0x10` and PHY `0x11` handoff, acquire the prep vote if the client has none. | A different handoff state stops prep seeding. An inherited prep vote remains untouched. |
| Idle release | Stock-style genpd idle work releases the diagnostic-owned prep vote once. The CPM core client vote must first read zero, and the guarded physical state must be PSM1 0 with PHY `0x11`. Require physical PSM1 3 after release. | An unowned prep vote, an active core client vote, a failed mailbox request or an unexpected PSM state stops the sequence. Keep HSIO-S on and preserve logs. |
| Prep resume | At the delayed observation, attach to the existing UFS node's prep and core domains. Confirm both are logically off, then require guarded PSM1 3 before prep ON and 2 after its successful reply. | Missing domains, an inherited vote or an unexpected PSM stops core resume. Retain any successfully acquired prep reference through the return. |
| Core resume | Recheck guarded PSM1 2 and PHY `0x11` immediately before issuing core ON. Record the vote result and HC/PHY after it. | A failed guard blocks the request. A failed vote ends the sequence. The fixture retains the timed stock A return and keeps HCI disconnected. |

The experiment exercises prep's idle OFF and resume. It starts
with the core client vote off and skips stock's separate core-OFF
phase and TOP programming. A successful core reply therefore
establishes the mailbox outcome. PHY readiness remains a separate
measurement. The v29 rail decision applies to the backup path.
v40's prep release is separate power-control work and needs its
own attended approval and backup check. Nine offline
cases cover the transition, vote ownership, timeout, invalid
states, and repeated-release veto. Strict checkpatch passed.

The offline ARM64 build uses release
`7.3.0-rc6-omamobile-grizzly-uic-v40` and Debian Clang
19.1.7. The CPM object passed `W=1`. The bundle retains
v39's RAM rescue, four disabled UFS supplier nodes, and
the 90-second warm return. The five image checksums,
both AVB signatures, unpacked payload, D1 handoff and
saved slot capacity checks passed. The manifest SHA-256
is `2ea36f14275f9ba31822c7b3d0279f4f38d11f8be06c9e9ca52d68fccd43a679`.
The archive SHA-256 is
`ec6aab8feeebfb4e61db6ee605e8f6683886f1e22347647aa46dc3f0a0ee4ff0`.
These build checks were performed offline.

#### Attended v40 slot B trial

On 2026-11-24 the owner approved one trial using the verified
nine-partition NV backup. Before staging, the Mac independently
rechecked the backup sizes, hashes and private file modes. The
backup captures NV before the most recent stock A boot. All five
slot B writes and the full `vendor_boot_b` readback passed.

The retained `7.3.0-rc6-omamobile-grizzly-uic-v40` console shows
an inherited HSIO-S vote and an issued initial prep ON vote with
`ret=0` at 0.192848 s. The guarded readings stayed at HSIO-S
`0x10`, HC `0x10` (PSM1 `0x0`) and PHY `0x11` before and after
that vote. Genpd began its unused-domain sweep at 0.228547 s.
At 2.217212 s the diagnostic reported `idle release not qualified
stage=0`, which is `MALIBU_UFS_IDLE_WAIT_OFF`. The retained log
contains no prep OFF callback records. The release gate therefore
blocked both diagnostic resume votes. The trial did not exercise
the `0x3` to `0x2` prep transition or issue core ON. PHY remained
`0x11` at the two-second and 21.481198 s samples.

The timed restart reached Fastboot 133 seconds after the B boot
request. Stock D1 completed boot on A with enforcing verity and
the original factory VBMeta digest. `SYSTEM_LAST_KMSG` matched the
ramoops diagnostic records for the failed release gate and late
PHY sample.

### Mainline v41 genpd idle-release trace

The same v40 console and `SYSTEM_LAST_KMSG` report `sync_state()
pending due to 3c2d0000.ufs` for the CPM provider at 10.473236 s.
The fixture enables the UFS device-tree node so the diagnostic can
attach its power domains. The UFS host driver is compiled out, so the
device stays unbound and its managed CPM supplier link stays inactive.

In v40, `malibu_cpm_register_domains()` registers prep logically ON
after the initial vote. Mainline `pm_genpd_init()` sets `stay_on` for
boot-on OF domains unless the provider opts out. `genpd_power_off()`
checks this latch before the provider callback. The CPM provider's OF
`sync_state` would clear it and retry, but the inactive UFS consumer
holds off that sync. The sweep message alone shows work was queued.
The v40 source and retained provider message identify the expected
veto. The new trace will capture the actual gate values at work time.

Stock D1's GKI at `f5369e7496cb231d2b41cbca078b8b69160ac22d`
also queues unused-domain work. Its genpd has no boot-on `stay_on`
gate. Stock prep and core each recorded one successful logical OFF
before `ufs.ko` loaded, despite a later supplier sync warning. That
boot measured prep PSM1 `0x3` before and `0x2` after the prep ON vote.

[v41 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/e040f855e9ca3eb513734e5bad5c176497446ec6)
adds a default-off diagnostic for the two named UFS domains. It logs
registration, sweep queue, worker, blocking predicates, provider sync
and OFF callback entry. It keeps v40's domain flags, sync policy,
vote sequence, disabled UFS host and 90-second warm return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the v41 source, image manifest and v40 safety configuration below. | Keep stock A selected if any check fails. |
| One attended slot B boot, power-control risk | With separate approval and the NV backup gate satisfied, expect `malibu-ufs-genpd` registration, `sweep-queue` and `worker` records for prep. The expected `entry-gate` has `on=1 stay_on=1` with no other blocking flags, no prep `provider-off`, and the pending UFS consumer message. | Preserve any differing first gate. Use the timed warm return and select stock A. Abort further trials if a preflight check fails, the recovery path is lost, or a disk appears. |

Offline build `7.3.0-rc6-omamobile-grizzly-uic-v41` passed strict
checkpatch and `W=1` for the genpd object. The config delta is the
trace option and release suffix. The DTB and rescue ramdisk match v40.
DT schema validation returns the same three baseline diagnostics.
All five image hashes, both AVB signatures, unpacked payload, ABL
handoff bounds and saved D1 slot capacities passed. Manifest SHA-256
`35ec623a13ed8859116289ac03d110c6db1e44c62a508a310b7ab539dc1d76be`.
Archive SHA-256
`0933993bfe03cec6508186b8e98fcc8e93d14b906d1b4a7dc0b53f0002e55ca9`.

#### Attended v41 slot B trial

On 2026-11-24 the owner approved one trial using the existing
nine-partition NV backup. The Mac rechecked the private backup's sizes,
hashes and modes before staging. All five slot B writes passed and the
`vendor_boot_b` readback matched all 8,192 supplied bytes.

Prep registered with `on=1 stay_on=1` at 0.193464 s. The sweep queued
prep at 0.232418 s and its worker reached `entry-gate` at 0.232447 s.
At that gate, `on=1 stay_on=1`, `always_on=0`, `rpm_always_on=0`,
`prepared=0`, `subdomains_on=0` and `devices=0`. This directly confirms
the boot-on latch blocked prep before the provider OFF callback. Core
was already logically OFF. The trace contains no prep `provider-off`
or `of-provider-sync` record.

The two-second observation stayed at `WAIT_OFF`. At 10.473131 s CPM
reported `sync_state() pending due to 3c2d0000.ufs`. Ramoops and
`SYSTEM_LAST_KMSG` agree on the genpd gate and pending consumer. The
late sample retained HC `0x10` and PHY `0x11`. Fastboot returned 133
seconds after the B boot request. Stock D1 completed boot on A with
enforcing verity and the original factory VBMeta digest.

### Mainline v42 guarded prep idle release

[v42 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/0d5e4078f0a7d2f6be666948820ea04b96e7cd96)
sets `GENPD_FLAG_NO_STAY_ON` before `pm_genpd_init()` for diagnostic
prep only, after it successfully acquires its own initial ON vote.
An inherited vote keeps the latch. The default-off build option
requires the v41 genpd tracing option. The v41 logs and the existing
OFF ownership, core vote, wrapper, PSM1 and PHY guards remain in use.
The UFS host remains disabled and HSIO-S stays held on.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the source, image manifest and safety configuration below. | Keep stock A selected if any check fails. |
| One attended slot B boot, power-control risk | With separate approval and the NV backup gate satisfied, confirm prep `on=1 stay_on=0` and `provider-off`. Capture the core client vote and guarded prep OFF samples. If OFF leaves PSM1 `0x3`, capture PSM1 before and after prep ON. After a qualified `0x3` to `0x2` transition, capture the core ON reply and guarded PHY sample against the stock `0x10` target. | Preserve the first rejected gate or unexpected sample. Use the 90-second warm return and select stock A. Stop further trials if the recovery path is lost or any disk appears. |

The ARM64 `7.3.0-rc6-omamobile-grizzly-uic-v42` build passed strict
checkpatch and `W=1` for the CPM and genpd objects. Six registration
flag cases and the nine existing idle transition cases passed offline.
The DTB and RAM rescue match v41, with the same three baseline schema
diagnostics. All five hashes, both AVB signatures, unpacked payload,
ABL handoff bounds and saved D1 slot capacities passed. Manifest SHA-256
`5f2422cb1856f0bba2c72c7a205eed89d8811cda811142422541f5636e1e4446`.
Archive SHA-256
`6e55eeef5052bd8c475be9d50adab6b793ef4a01a2bb2db1340eaae15c5a34f0`.

#### Attended v42 slot B trial

On 2026-11-25 the owner approved one v42 boot with the verified
nine-partition NV snapshot. The Mac rechecked the snapshot's hashes,
sizes and modes. All five slot B writes passed and the `vendor_boot_b`
readback matched all 8,192 supplied bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.137805 | Prep registration | `on=1 stay_on=0` after an owned prep seed |
| 0.180536 | Prep provider OFF callback | Core client vote then read `0` |
| 0.180725–0.181016 | Prep OFF samples | HC `0x10` to `0x13`, PSM1 `0x0` to `0x3`, PHY `0x11` |
| 2.154182 | Virtual-domain attachments | Prep and core both logically OFF |
| 2.154463–2.154820 | Prep ON samples | HC `0x13` to `0x12`, PSM1 `0x3` to `0x2`, PHY `0x11` |
| 2.155012–2.155384 | Core ON samples | HC `0x12` to `0x10`, PHY `0x11` to `0x10` |
| 10.477439 | CPM supplier sync | Still pending due to `3c2d0000.ufs` |
| 21.481400 | Late sample | HC and PHY both `0x10` |

The packed DT maps the UFS `prep` and `core` phandles to CPM
onecell indices `6` and `7`. The named attachments create runtime-PM
devices and leave both domains OFF until the explicit resumes, as the
live log confirmed. Prep OFF, prep ON and core ON each returned `0`.
The prep-only latch opt-out reproduced the physical PSM1 and PHY
transitions measured on stock D1 with CPM supplier sync still pending.
The UFS host remained disabled. This fixture establishes PHY power
readiness. UIC link startup and LUN discovery still need hardware tests.

Ramoops and `SYSTEM_LAST_KMSG` matched the diagnostic records.
Fastboot returned 133 seconds after the B boot request. Stock D1
completed boot on A with enforcing verity and the original factory
VBMeta digest.

### Mainline v43 guarded UFS link diagnostic

[v43 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/ffdbb1117dfaacbeca2b9646edff4ef513833121)
combines v42's guarded provider prep OFF with the existing Malibu
link-only host. `System.map` places the genpd unused-domain sweep
before the late host initcall. The initcall schedules host registration
after two seconds. The host waits up to 200 ms for the provider's
`RELEASED` state before taking any prep reference or starting host
setup. The provider's own temporary resume path is inactive in this
build. Prep runtime resume must reach `PREP_ON` before TOP programming,
even if genpd reports an acknowledged vote. The core callback keeps
the pre-vote PSM1 and PHY checks.

The packed DT changes only the four UFS supplier statuses. It enables
the HSIO-S SGIA, GPIO and standby pinctrl nodes and the CPM regulator
node. The ABL calibration target and stock rail values are retained.
The host uses its existing PHY/TOP readiness checks and synchronous
`ufshcd_probe_link_hibern8()` test. This path exits before transfer
queues, SCSI host registration and LUN discovery. On a PHY timeout
the guarded path exits before the external device power-on fallback.
Following a successful link and Hibern8 test, the HCI must stop.
The diagnostic retains prep and core references and the remaining
resources through the timed return, since the v42 state machine only
qualifies one prep OFF and does not implement a core OFF transition.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the v43 source, image manifest and verified recovery path. | Keep stock A selected if any check fails. |
| One attended slot B boot, power-control risk | With separate approval and the verified NV backup gate satisfied, capture guarded prep OFF and prep ON samples, core reply, PHY `0x10` and TOP bit 4. Capture the UIC startup result, HCI IRQ and Hibern8 qualification, then the held-votes marker. No disk should appear. | Preserve the first failing phase or gate. Stop on a missing supplier, failed calibration, readiness, IRQ or link check, or unexpected disk. Use the 90-second warm return and verify stock A. |

The ARM64 `7.3.0-rc6-omamobile-grizzly-uic-v43` build passed strict
checkpatch, `W=1` for the CPM and host objects, and all nine existing
vote-state tests. The DT schema diagnostics match v42. The RAM rescue,
both AVB signatures, all five image hashes, unpacked payload, ABL
handoff bounds and saved D1 slot sizes passed offline checks. Manifest
SHA-256 `883e0ac865be75ebde396cbb1160145c2550d2f566f7e2e2f6bc948f37406caf`.
Archive SHA-256
`6f5b4af750de5f77b45c970271a4c68a64c2a35da7d7158a27251c5d6d64c3ea`.

#### Attended v43 slot B trial

On 2026-11-25 one slot B boot used the verified nine-partition NV
snapshot. All five writes passed and `vendor_boot_b` readback matched
all 8,192 supplied bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.176623–0.176904 | Guarded prep OFF | PSM1 `0x0` to `0x3`, PHY `0x11` |
| 2.185367 | Host release gate | `stage=1 expected=1` |
| 2.187032–2.187425 | Host prep ON | PSM1 `0x3` to `0x2`, qualified stage `2` |
| 2.188111–2.188509 | Core ON and readiness | Vote `0`, PHY `0x10`, TOP bit 4 set |
| 2.210030–2.210169 | UIC link and Hibern8 | `link=0 hibern8=0`, with a fresh Hibern8-enter IRQ required by the test |
| 2.220185 | Deep H8 clock-release gate | HC `0x11`, PHY `0x10`, `-ETIMEDOUT` |
| 2.220883 | Host exit | `deep-h8-qualification`, remaining UFS votes retained |

The link-only path reached Hibern8 before the Deep H8 gate timed out.
Only HC reached `0x11` within the gate's 10 ms window. Deep H8 was
left prepared. The later HC and PHY sample was `0x10` for both.
The retained console has no SCSI disk enumeration, consistent with
the link-only path. UFS storage remains untested.

Cleanup also emitted a workqueue warning. The stack reaches
`ufs_debugfs_hba_exit()` through `ufshcd_hba_exit()`. The link-only
init skips `ufs_debugfs_hba_init()`, which initializes
`debugfs_ee_work`, while the shared exit calls `cancel_delayed_work_sync()`
on it. Cleanup needs to match that initialization before another trial.

The v43 markers match between ramoops and `SYSTEM_LAST_KMSG`.
Fastboot returned 133 seconds after the B boot request. Stock D1
completed boot on A with enforcing verity and the original factory
VBMeta digest.

### Mainline v44 link-only cleanup and Deep H8 timing

[v44 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/78741a14311dee2451f8690883ac50e3fa3cbb10)
skips debugfs teardown on the link-only path, matching its init path.
Normal UFS host teardown still cancels its initialized debugfs work.
The Malibu callback saves the initial HC and PHY samples and logs
elapsed poll time and the existing final samples after Hibern8.
The host samples both PSMs again once link-only HCI cleanup returns.
The 10 ms gate still requires both PSMs at `0x11` before disabling
Deep H8. A timeout still retains the remaining votes until warm return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the source, image hashes and v43 board DT and RAM rescue. | Keep stock A selected on any mismatch. |
| One attended slot B boot, power-control risk | With separate approval and the NV backup gate satisfied, reproduce UIC startup and IRQ-backed Hibern8. Record the initial and final PSMs, elapsed poll time, post-HCI sample and whether Deep H8 was released. Expect no workqueue warning or disk discovery. | Preserve the first failing phase. Keep the release guard in place. Use the 90-second warm return, select stock A and verify Android. |

Offline `7.3.0-rc6-omamobile-grizzly-uic-v44` passed strict checkpatch,
`W=1` for the UFS core and host objects, and source checks for symmetric
debugfs cleanup and the original clock-release guard. The packed DTB
and RAM rescue are byte-identical to v43. All five hashes, both AVB
signatures, unpacked payload, ABL handoff and saved slot sizes passed.
Manifest SHA-256 `37eb128786648d73509bd5020435943e8c64ca6a4e957908fc92cacee74fe245`.
Archive SHA-256 `8f77c893c50e237584cb07ce931fe0eb2af07d9372dc909919ebe699fc0a32e7`.

#### Attended v44 slot B trial

On 2026-11-25 one slot B boot used the verified nine-partition NV
snapshot. All five writes passed and the `vendor_boot_b` readback
matched all 8,192 supplied bytes. Prep registered with its owned
vote and `stay_on=0`. Its guarded OFF callback recorded a zero core
client vote and issued prep OFF successfully.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.144365 | Before prep OFF | HC `0x10`, PSM1 `0x0`, PHY `0x11` |
| 0.144523 | Immediate sample after prep OFF reply | HC `0x10`, PSM1 `0x0`, PHY `0x11` |
| 0.144528 | Prep OFF result | `owned_before=1 owned_after=0 ret=0` |
| 2.121156 | Delayed sample | HC `0x13`, PSM1 `0x3`, PHY `0x11` |
| 2.354140 | Host gate | `stage=4 expected=1`, probe deferred |
| 21.481148 | Late sample | HC `0x13`, PSM1 `0x3`, PHY `0x11` |

The physical transition was visible only after the immediate
post-reply sample. That sample left the one-shot state machine at
`STOPPED`, and the later probe could not qualify `RELEASED`. This
boot never exercised prep or core ON, UIC startup, Deep H8 timing,
or the link-only cleanup fix. A separate earlier warning came from
`device_links_no_driver()` in deferred probe work at 0.107135 s.
The cause of that warning remains unverified.

Ramoops and `SYSTEM_LAST_KMSG` agree on these results. Fastboot
returned after 133 seconds. Stock D1 completed boot on A with
enforcing verity and the original factory VBMeta digest.

### Mainline v45 guarded prep OFF settling

[v45 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/c6cf13436ab3e557478ac3ee386d0db5dfd9f79d)
checks the immediate sample after the single acknowledged prep OFF.
If HC is still `0x10` with the HSIO-S wrapper on and PHY `0x11`, it
polls for HC `0x13` (PSM1 `0x3`) with a 10 ms deadline. Every sample
uses the wrapper guard. An unavailable wrapper, unexpected HC or PHY,
or timeout blocks the host. It logs the initial and final samples,
elapsed time and qualification result. CPM still reports an accepted
OFF vote to genpd even if the physical state does not qualify. The
one-shot state machine preserves that ownership decision and issues
no second OFF vote. Prep ON and core ON gates remain as in v44.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the source, manifest and v44 DTB and rescue ramdisk. | Leave stock A selected on any mismatch. |
| One attended slot B boot, power-control risk | With approval and the verified NV backup, capture the post-reply PSM samples and `qualification=0`. Confirm host stage `RELEASED`, then capture prep/core votes, UIC/Hibern8, v44 Deep H8 timing and HCI cleanup. Expect zero disks. | Stop after the first failing qualification. Keep clock-release guards in place and use the 90-second warm return to verify stock A. |

ARM64 release `7.3.0-rc6-omamobile-grizzly-uic-v45` passed strict
checkpatch, `W=1` for the CPM object, six settle cases and nine guard
cases. The packed DTB and rescue ramdisk match v44. Both AVB signatures,
all five image hashes, unpacked payload, ABL handoff and saved D1 slot
sizes passed. Manifest SHA-256
`4f738b788a2593a8c58e8302517eff3d3a8ba9456ab3d1abb192922a2b1b1e62`.
Archive SHA-256
`d820562ef78e54911d4b033e47feb54efb30161a94b7606ab53f5641fc8e7763`.

#### Attended v45 slot B trial

On 2026-11-25 one slot B boot used the verified nine-partition NV
snapshot. All five writes passed and the `vendor_boot_b` readback
matched all 8,192 supplied bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.144568–0.144590 | Prep OFF qualification | HC `0x13` (PSM1 `0x3`) and PHY `0x11` on the first sample, `qualification=0`, elapsed 4 µs |
| 2.153328–2.155396 | Host release and prep ON gates | Stage `1` then `2`, PSM1 `0x2` after prep ON |
| 2.156431–2.156475 | Core ON and readiness | HC and PHY `0x10`, TOP bit 4 set |
| 2.177963–2.178100 | Link and IRQ-backed Hibern8 | `link=0 hibern8=0` |
| 2.188125–2.188144 | Deep H8 gate | Initial HC/PHY `0x10`/`0x10`, final `0x11`/`0x10` after 10,013 µs, `-ETIMEDOUT` |
| 2.188231 | After HCI cleanup | HC and PHY both `0x10` |

The first post-reply sample passed. The 4 µs value is the time to
qualify that sample. This boot did not exercise the delayed settling
branch seen to be necessary in v44. The driver kept Deep H8 prepared
and retained the remaining votes after the gate timed out. The
link-only cleanup ran without the v43 debugfs workqueue warning.
The separate early `device_links_no_driver()` warning recurred before
the host probe. No disk discovery was attempted.

Ramoops and `SYSTEM_LAST_KMSG` agree on these results. Fastboot
returned after 133 seconds. Stock D1 completed boot on A with
enforcing verity and the original factory VBMeta digest.

### Mainline v46 M-PHY Hibern8 power gating

The factory D1 B0 device tree enables both `google,enable-hc-swh8-pg`
and `google,enable-hc-ah8-pg`. The factory `ufs.ko` maps them to bits 2
and 1 of its feature word. In `ufs_google_pwr_change_notify()`
(`.text` `0xa780`–`0xa7b8`), stock sets local DME attribute `0x8118`
to `1` when either feature is enabled, then sends `0xd085=1` to apply
the M-PHY configuration. With both flags set, stock does not update
HCI `+0xc0` in its link-startup callback (`0xa460`–`0xa494`). v45
applies M-PHY configuration before link startup but never sets `0x8118`.

Stock runtime suspend checks HC and PHY separately for `0x11` before
releasing the Deep H8 clock (`0xe97c`–`0xe9b8`, `0xeb1c`–`0xeb58`).
Each stock poll has a 10 ms timeout. The mainline diagnostic keeps its
single 10 ms window requiring both states simultaneously.

[v46 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/3aa99fc043107df12eddbccd5f6f4e8a0d73e99d)
adds a default-off option for those two local SETs after successful
link startup and link parameter validation. It logs each command's
result and stops on error. This isolates the stock setting in the
existing PWM-G1 single-lane link test. Stock normally programs it after
a power-mode change. The trial preserves the fresh Hibern8-enter IRQ
requirement, v45 prep settle guard and v44 timing samples. The AH8
timer policy, DT, rail settings and link-only boundary match v45.

The earlier device-link warning arises in deferred-probe rollback,
before the Malibu UFS host registers. Its trace indicates a managed
runtime-PM link with an inactive supplier. The captured warning lacks
the endpoint names. v45 reached link startup despite it.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match source, manifest and the recovery snapshot. | Leave stock A selected on any mismatch. |
| One attended slot B boot, power-control risk | With approval and the verified NV backup, check both local SET results, the fresh Hibern8 IRQ, the HC/PHY pair and the Deep H8 release result. Expect no disk discovery. | Preserve the first failure. Keep the release guard in place and use the 90-second warm return to verify stock A. |

Offline ARM64 `7.3.0-rc6-omamobile-grizzly-uic-v46` passed strict
checkpatch, `W=1` for the Malibu link object and five command-path
cases. The packed DTB and rescue ramdisk are byte-identical to v45.
All five image hashes, both AVB signatures, unpacked payload, ABL
handoff bounds and saved D1 slot capacities passed. Manifest SHA-256
`eab265ecf6ee653452ec78e0771344251c920f446168ae82fd330cacd452a319`.
Archive SHA-256 `3de8276eed7d2e783907ed58d376d5cd0b1c8c3562c96f5e2a4c0c7057f7dcc1`.

#### Attended v46 slot B trial

On 2026-11-25 one slot B boot used the verified nine-partition NV
snapshot. All five writes passed and the `vendor_boot_b` readback
matched all 8,192 supplied bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.178273–2.178305 | Local `0x8118` and `0xd085` commands | Both `ret=0` |
| 2.178315–2.178450 | Link and IRQ-backed Hibern8 | `link=0 hibern8=0` |
| 2.178565–2.178583 | Deep H8 release gate | Initial HC/PHY `0x10`/`0x11`, final `0x11`/`0x11` after 103 µs, `ret=0` |
| 2.178709 | Deep H8 unprepare | Returned |

The stock DME pair let both PSMs reach `0x11` during the diagnostic
Hibern8 entry. The trace ends before the post-HCI sample, 20-second
observer or timed restart. It records no panic. Fastboot returned
45 seconds after the B boot request. Ramoops and `SYSTEM_LAST_KMSG`
agree through clock release. The early device-link warning also recurred.

The callback releases Deep H8 before `ufshcd_abort_init()` masks HCI
interrupts and stops the controller. That sequence can attempt HCI
MMIO after the successful PHY transition and clock release. The
retained log does not identify the exact stalled operation or reset
source. A follow-up can hold Deep H8 after the qualified sample and
trace the HCI cleanup boundary before changing shutdown order.

Stock D1 completed boot on A with enforcing verity and the original
factory VBMeta digest.

### Mainline v47 HCI cleanup with Deep H8 held

[v47 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/ccb9a4a7940a9bfa3200450cd676e4e5af617c5f)
applies the v46 DME pair and checks the same fresh Hibern8 IRQ and
dual `0x11` PSM gate. After qualification the diagnostic keeps the
Deep H8 clock prepared. It logs entry to HCI cleanup, the existing
interrupt-mask write and readback, HCI stop entry and return, and
completion of IRQ release. These markers add no HCI accesses. The
link-only host still retains prep and core votes and exits before
transfer queues or disk discovery.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match source, manifest and the v46 packed DTB and rescue ramdisk. | Leave stock A selected on any mismatch. |
| One attended slot B boot, power-control risk | With approval and the verified NV backup, confirm both DME replies, fresh Hibern8, both PSMs at `0x11` and the held-clock marker. Capture HCI stop, IRQ release and the post-cleanup PSM sample. Expect the 90-second return. | On an early reset or missing marker, preserve the last cleanup step in ramoops and select stock A. Confirm Android completes boot. |

ARM64 `7.3.0-rc6-omamobile-grizzly-uic-v47` passed strict checkpatch,
`W=1` for the UFS core and host, and source checks for cleanup order
and the held-clock branch. The built kernel contains all seven new
markers. The packed DTB and rescue ramdisk match v46 byte for byte.
All five hashes, AVB signatures, unpacked payload, handoff and saved
D1 slot capacities passed offline. Manifest SHA-256
`2f00a9299f568e85739a868bb44f285a9c63ae603a3e1f5c1eb338530fc810fe`.
Archive SHA-256
`a1c87c17ba9156f6351a199c8fe14e137aed644c58eea41b7481ec5ad29e327e`.

#### Attended v47 slot B trial

On 2026-11-25 one slot B boot used the verified nine-partition NV
snapshot. All five writes passed and `vendor_boot_b` readback matched
all 8,192 supplied bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.181940–2.181983 | Local Hibern8 gating and M-PHY update | Both `ret=0` |
| 2.182001–2.182136 | UIC link and fresh Hibern8 IRQ | `link=0 hibern8=0` |
| 2.182294–2.182320 | Deep H8 gate | HC/PHY `0x11`/`0x11` after 146 µs. Deep H8 left prepared. |
| 2.182328–2.182389 | HCI cleanup | Interrupt mask write and readback, controller stop and IRQ release completed. |
| 2.182450 | After HCI cleanup | HC `0x10`, PHY `0x11` |
| 2.182461 | Host completion | Controller stop check passed and UFS votes were retained. |
| 90.154188 | Warm return | Timer requested the restart. |

HC and PHY still read `0x10` and `0x11` at the late sample. The v43
debugfs workqueue warning did not recur. The earlier deferred-probe
device-link warning remained. This boot confirms HCI cleanup can
complete with Deep H8 held after both PSMs reach `0x11`. It leaves
the exact v46 reset mechanism and safe clock-release order open.
The link-only host did not attempt disk discovery.

Ramoops and `SYSTEM_LAST_KMSG` agree. Fastboot returned 133 seconds
after the B boot request. Stock D1 completed boot on A with enforcing
verity and the original factory VBMeta digest.

## Staging and return sequence used for D1

These commands describe the attended workflow used by the trials.
The review and validation gates above apply before another B boot.
`GRIZZLY_SERIAL` selects the phone, `GRIZZLY_M1_DIR` holds the reviewed
bundle's `images/` directory, and `VERIFIED_SLOT_B_BOOTLOADER` comes from
an independent observation of B's bootloader. D1 reports the version of
the executing slot. Keep the raw captures and partition readback private.

```sh
adb -s "$GRIZZLY_SERIAL" reboot bootloader
fastboot -s "$GRIZZLY_SERIAL" getvar all > "$CAPTURE/fastboot-before.txt" 2>&1
FASTBOOT_SERIAL="$GRIZZLY_SERIAL" device/grizzly/bringup/stage-slot-b.sh \
    "$GRIZZLY_M1_DIR/images" --bootloader-slots-match "$VERIFIED_SLOT_B_BOOTLOADER"
fastboot -s "$GRIZZLY_SERIAL" fetch vendor_boot_b "$CAPTURE/vendor_boot_b.readback.img"
fastboot -s "$GRIZZLY_SERIAL" getvar all > "$CAPTURE/fastboot-staged.txt" 2>&1
printf 'version-bootloader:b: %s\n' "$VERIFIED_SLOT_B_BOOTLOADER" >> "$CAPTURE/fastboot-staged.txt"
python3 device/grizzly/bringup/check-slot-b.py \
    "$GRIZZLY_M1_DIR/images" "$GRIZZLY_M1_DIR/images/SHA256SUMS" \
    --fastboot-vars "$CAPTURE/fastboot-staged.txt" --require-healthy-a \
    --vendor-boot-readback "$CAPTURE/vendor_boot_b.readback.img"
```

Once staging passes and the live reader and return plan are ready, select
B, confirm it, and issue one boot request.

```sh
fastboot -s "$GRIZZLY_SERIAL" --set-active=b
fastboot -s "$GRIZZLY_SERIAL" getvar current-slot
fastboot -s "$GRIZZLY_SERIAL" reboot
```

Catch Fastboot with Volume Down at the scheduled restart. Confirm that the
bootloader is back, select A and confirm that selection. Release Volume
Down before the stock boot request.

```sh
fastboot -s "$GRIZZLY_SERIAL" --set-active=a
fastboot -s "$GRIZZLY_SERIAL" getvar current-slot
fastboot -s "$GRIZZLY_SERIAL" reboot
```

On Android, verify `sys.boot_completed=1`, `ro.boot.slot_suffix=_a`,
`ro.build.id=CP4A.261105.040.D1`, enforcing verity and the original
stock VBMeta digest. Capture the matching tagged console in ramoops
and DropBox before another trial.

```sh
adb -s "$GRIZZLY_SERIAL" exec-out cat /sys/fs/pstore/console-ramoops-0
adb -s "$GRIZZLY_SERIAL" shell dumpsys dropbox --print SYSTEM_LAST_KMSG
```

## Storage and reference clock

Stock D1's UFS `mphy_ref_clk` selects LPCM8 clock 1 at 38.4 MHz. The
v29 packed DT connects `mphy-ref` to the same clock. The external
device REFCLK and the device attribute remain unmeasured. The
diagnostic checks the configured M-PHY rate and stops at link/Hibern8.
The [Malibu reference-clock guard](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/af719fb07680986d5e2ad0a3f798f0c55f7306fe)
uses the configured `mphy-ref` rate as the expected code
(`0x2` for 38.4 MHz). When a full-device fixture reaches
`ufshcd_post_device_init()`, the guard issues `READ_ATTR(0x0a)`
and logs the raw and expected values before HS gear selection
or LUN discovery. It returns an error on a mismatch, failed read,
or invalid host rate. This path never issues `WRITE_ATTR` for
`bRefClkFreq`. Other UFS hosts retain the generic behavior.
The current link/Hibern8 fixture lacks the transfer queue required
to run this query. Both affected ARM64 objects passed the
`W=1` build and 11 offline tests covered the guard and default
paths. The device attribute still requires a hardware measurement.

The exact v29 ramdisk already carries the shared initramfs in RAM rescue
and omits its write allowlist. The historical `d1-packaging.conf`
also omits `UFS_RW`. The first storage-visible Grizzly fixture
must preserve the shared guard's
all-read-only behavior. Verify this in the finished ramdisk and then
verify every relevant LUN on the phone before reading data. The
`tools/nv-backup` descriptor requires a verified Grizzly NV inventory.
D1's partition list and vendor labels support
`persist nvdata nvram protect_f protect_s modemdp modem_a modem_b`
as the initial NV inventory. Copy `devinfo` separately because the
slot flags can change. Confirm each label and its size in Grizzly
rescue. Allow at least 3,235 MiB of private host storage and a separate
on-phone checksum pass. The v29 90-second window is insufficient
for this backup.

The v33 Fastboot capture reports `secure:yes` with the bootloader
unlocked. D1 ABL's `secure` response and `fetch` handler consult the
same policy function (`abl.img` `0x9eef8`, `0x9de5c`). Under that
policy the fetch table contains `vendor_boot` and `super`
(`0x336cc0`–`0x336cd0`). The successful `vendor_boot_b` readback
therefore establishes a boot-image check. The NV inventory is
outside that fetch policy. The verified backup below uses the
stock-kernel restricted reader.

### Offline rehearsal using the recovery inventory

The verified backup's `partitions.txt` contains nine unique
GPT labels with their observed device names and sizes. The
manifest names and local file sizes agree with that inventory,
totaling 3,392,151,552 bytes. An offline ARM64 rehearsal used
those label, size and parent mappings in a synthetic sysfs
tree with five UFS parents. The stock guard accepted the
matching inventory and published its verified RAM snapshot.
It refused a changed size, duplicate label, mounted parent
and failed parent read-only ioctl. The rehearsal used no
partition payloads.

For a future mainline storage-visible boot, check label
uniqueness, size and controller ancestry before accepting
the layout. Linux device names can change with probe order.
Prove read-only state for each parent and target before
permitting storage reads. The shared initramfs now applies
`BLKROSET` to all SCSI parents when the effective write
allowlist is empty. It checks for ioctl success and sysfs
`ro=1`, retries failures, and includes writable parents in
the unguarded-device report. Valid writable-root allowlists
retain their normal whole-disk node policy. The storage-guard
tests passed with Linux `sh` and Grizzly's ARM64 BusyBox ash.
The root-policy and persistent-root tests passed as well.

The packed v39 ramdisk predates this change and is suitable
for its zero-disk test. The shared initramfs starts the
rescue shells before the optional UFS probe report. A first
storage-visible fixture still needs an early inventory gate
such as the stock reader's parent and partition checks.

The backup contains partition contents and inventory, so it
cannot establish PHY readiness or the device's reference
clock attribute. The known 38.4 MHz value is the M-PHY
clock. The stock RAM fixture can qualify the device's raw
`bRefClkFreq` through the read-only
`attributes/reference_clock_frequency` sysfs path once UFS
has initialized. The current mainline link-only probe has
no transfer queues for that query. The Malibu full-init guard
above is independent of block read-only flags and refuses to
change the attribute.

### Mainline inventory-only RAM rescue

Build the standalone ramdisk with
`pack-mainline-inventory.py --rescue-cpio RESCUE_CPIO OUTPUT`.
It includes the Grizzly PID 1, the tested ARM64 BusyBox and
musl loader, and the inventory and NV guard libraries. It
contains no writable partition allowlist, USB or network
services, storage reader, or userspace handoff. PID 1
requires Grizzly and slot B and mounts a private `/dev`
containing only null, console, and kmsg. The guard uses a
separate private RAM workspace and removes its temporary
block nodes after the read-only ioctls.

The fixture waits up to 20 seconds for the nine expected
labels and their sizes. The guard requires five parents
under `3c2d0000.ufs`, checks topology, mounts and holders,
and verifies read-only state with `BLKROGET` and sysfs.
The nine targets may move among the five observed parent
names. An extra or missing parent requires review. All
reported partition information comes from sysfs. The
kernel's own UFS startup commands precede this userspace
guard and must be qualified separately.

The fixture uses a 90-second warm return with a retained
console marker. If the prior marker is present, PID 1 ends
the inventory stage and calls for a manual Fastboot return.
This suppresses a second timed restart if ABL starts B
again. Kernel work before PID 1 can still repeat. Thirteen
ARM64 BusyBox dispatch and inventory mocks
passed with the backup-derived label and size table. Three
timer mocks passed for the new and existing fixtures.

The standalone compressed ramdisk SHA-256 is
`639b89649c3df9df7d8a2b5d83de2953b58a4e2026ecffaf6f08197b9785693e`.
It passed archive membership, legacy LZ4 round-trip and
D1 handoff bounds using the v39 kernel layout. The two
later v39 ramdisk layers are empty. The v39 kernel itself
has storage disabled and cannot enumerate the disks, so
this ramdisk awaits a separate enumerating kernel. The v39
trial used its original RAM rescue. See the
[v39 slot B result](#v39-slot-b-result).

### Mainline v48 device management before discovery

The ordinary `ufshcd_query_attr()` path uses a reserved SCSI
request. Its recovery can call `ufshcd_complete_dev_init()` and
write `fDeviceInit`. The [v48 kernel](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/57b81e11421bbc71e71fbb4b467b7d38c5535ae2)
instead uses one polled legacy doorbell slot for NOP OUT and one
`READ_ATTR(0x0a)` after a valid NOP IN. It reuses the
core DMA descriptor allocation and layout. It requires legacy SDB
support, an idle doorbell and a ready transfer list. It masks the
transfer interrupt and suppresses UFS recovery work. Slot retirement,
OCS, response transaction, tag and query fields must match before
the driver compares `bRefClkFreq` with `0x2` for 38.4 MHz. A timeout
attempts slot clear, then stops the list and exits through HCI cleanup.
The Malibu probe retains DMA resources and UFS votes until the timed
return. The diagnostic tests DMA and UPIUs without measuring transfer
completion IRQ delivery.

The v47 UIC and Hibern8 IRQ path remains active. The device query
ends before Hibern8, and Deep H8 is held through HCI teardown. The
host never registers a SCSI host, sends a SCSI command, issues a
query write or initiates `fDeviceInit`. The packed vendor boot
command line adds `scsi_mod.scan=none`. Build the private rescue
with `pack-mainline-inventory.py --device-query-only`. It keeps sysfs
read-only after setting warm return, checks that no SCSI disks appear,
and starts no shell or network service. Any result leaves storage
enumeration for a separate fixture.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Verify the manifest, private ramdisk membership and the scan-disabled command line. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power-control risk | With separate approval and the verified NV backup, capture a valid NOP IN, `READ_ATTR(0x0a)`, raw code `0x2`, and held-clock HCI teardown. Expect zero SCSI disks and the 90-second warm return. | Preserve the first transport refusal, doorbell or response error, or mismatched code. Stop after any unexpected disk or early reset. Select stock A and verify Android. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v48` passed strict
checkpatch, `W=1` on UFS core and host, seven mocked query and refusal
cases, shell parsing and ShellCheck. The DTB matches v47. The five
image hashes, both AVB signatures, unpacked payload, ABL handoff and
saved slot capacities passed. Manifest SHA-256
`4394206b525cb77de109bba51148deeeefea3f411ce07367bcc79f833ce0abfd`.
Archive SHA-256 `9a65a5c8dde3bc21194aff5c41e361e6e7b6598ccda38edd9268f52227c12b4c`.

#### Attended v48 slot B trial

On 2026-11-25 one slot B boot used the verified nine-partition
NV snapshot. All five writes passed and `vendor_boot_b` readback
matched all 8,192 supplied bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.191865 | Private RAM stage | `scsi_disks=0` |
| 2.174496 | UIC link | `ret=0` |
| 2.174929 | Polled NOP IN | OCS `0x0`, type `0x20`, code `0x0` |
| 2.175528–2.175550 | `READ_ATTR(0x0a)` | OCS `0x0`, type `0x36`, code `0x0`. `bRefClkFreq=0x2` (38.4 MHz), query result `0`. |
| 2.175684–2.176001 | Hibern8 and HCI cleanup | Fresh Hibern8 IRQ, HC/PHY `0x11`/`0x11` before cleanup, IRQ freed with Deep H8 held. |
| 90.192769–90.192836 | Private RAM stage before return | `scsi_disks=0`, warm restart requested. |

This verifies a legacy SDB management transfer and reference-clock
query before `fDeviceInit`. Transfer completion was polled. Normal
SCSI transport, discovery and disk reads remain untested. The early
deferred-probe device-link warning recurred before UFS probe.

Ramoops and `SYSTEM_LAST_KMSG` match. Fastboot returned after 133
seconds, and stock D1 completed boot on A with enforcing verity and
the original factory VBMeta digest.

### Mainline v49 device initialization before discovery

[v49 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/a1596ab67e57fc81c4465d066d70256ab519491f)
uses the same polled SDB slot as v48. It requires a valid NOP IN and
`bRefClkFreq=0x2`, then issues one standard `SET_FLAG` for `fDeviceInit`
(IDN `0x01`). It polls that flag until the device clears bit 0, using
the core's 1.5-second completion window and a bounded timeout for each
transfer. The SET is an explicit device management write. A command
error or timeout stops the sequence. The diagnostic issues no second
SET, no other query write and no SCSI commands.

The transfer list stops before Hibern8. The fixture preserves v48's
read-only sysfs, `scsi_mod.scan=none`, zero-disk checks and warm return.
It retains Deep H8 across HCI cleanup. It does not register a SCSI host
or expose storage.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the source, manifest and v48 private ramdisk. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power-control and device-init risk | With separate approval and the verified NV backup, capture the single accepted `fDeviceInit` SET, clear flag, status and elapsed time. Verify Hibern8, HCI cleanup, zero SCSI disks and the 90-second warm return. | Preserve the first transport or flag error. Do not repeat the SET or boot. Select stock A and confirm Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v49` passed strict
checkpatch and seven mocked command-path cases. The core compiled at
`W=1` with an existing kernel-doc warning for `link_only` in
`ufshcd_hba_capabilities()`. The DTB and private rescue match v48.
All five hashes, both AVB signatures, unpacked payload, ABL handoff
and saved D1 slot sizes passed. Manifest SHA-256
`a5318c22bdd3637f2baddcac37bb07ade6fd63b7a4303fbfaa47f87025f7febd`.
Archive SHA-256 `7e7248ee9550780e2caeb5a1b3737b2b1a07a8c2997f2771fc52898f56adde38`.

#### Attended v49 slot B trial

On 2026-11-25 one slot B boot used the verified nine-partition NV
snapshot. All five writes passed and `vendor_boot_b` readback matched
all 8,192 supplied bytes. The device returned NOP IN and read back
`bRefClkFreq=0x2` before the initialization request.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.181941–2.181950 | One `fDeviceInit` SET | OCS `0x0`, QUERY_RSP `0x36`, response `0x0`, `ret=0` |
| 2.183059 | First `READ_FLAG` | `raw=0x0 polls=1 elapsed_us=1100 ret=0` |
| 2.183207–2.183472 | IRQ-backed Hibern8 and HCI cleanup | Both PSMs reached `0x11`. Deep H8 remained prepared and the HCI IRQ was freed. |
| 90.197045–90.197111 | Timed return | `scsi_disks=0`, warm restart requested. |

The first flag read completed 1.1 ms after SET acknowledgement, so
that bounds when the flag had cleared. The exact transition time is
unmeasured. Zero SCSI disks were confirmed at RAM startup and before
restart. The early device-link warning recurred independently of UFS
probe. Normal SCSI transport and discovery remain untested.

Ramoops and `SYSTEM_LAST_KMSG` agree. Fastboot returned after 133
seconds, and stock D1 completed boot on A with enforcing verity and
the original factory VBMeta digest.

### Mainline v50 one SCSI INQUIRY before discovery

[v50 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/9809ee4f38b1bc2b1c22004c9f6a51d21a7d01fc)
adds one standard 36-byte INQUIRY to LUN 0 after NOP IN,
`bRefClkFreq=0x2` and the first successful read of a cleared
`fDeviceInit` flag. It sends the command over the same polled legacy
SDB slot, with one device-to-host PRD and a coherent receive buffer.
The diagnostic requires a successful UFS completion and SCSI status,
the expected LUN and tag, no residual, and a standard direct-access
device response. It logs numeric fields only. The receive buffer stays
allocated through controller teardown.

The kernel issues no READ CAPACITY or partition reads. It registers no
SCSI host, keeps `scsi_mod.scan=none`, and uses the same private RAM
rescue as v49. The transfer list stops after the query sequence. On
success the kernel checks IRQ-backed Hibern8 and retains Deep H8
through HCI cleanup before the 90-second warm return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the v50 source, manifest, v49 DTB and v49 private ramdisk. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control and device initialization | Use the verified nine-partition NV backup. Capture the fDeviceInit clear and exactly one INQUIRY with OCS `0x0`, UPIU `0x21`, response and status `0x0`, zero residual, qualifier/type zero and `result=0`. Verify Hibern8, HCI cleanup, zero SCSI disks and the timed return. | Preserve the first failure and return to stock A without retrying the command or boot. Confirm stock Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v50` passed strict
checkpatch, the targeted `W=1` compile and eleven mocked command
cases. The extracted helper tests verified the CDB and PRD, and
covered timeout, allocation failure, completion errors, residual
data and an invalid or missing payload. The DTB and private ramdisk
match v49. All five image hashes, both AVB signatures, the unpacked
payload, ABL handoff and saved D1 slot sizes passed. Manifest SHA-256
`b499f332261833829be780859ad73ce4a9be8b67e4f5da2c75b85d045db223ba`. Archive SHA-256
`1b06400da452aba41c753d150c7f3a68605bacf688b5a7df78e34641c3548476`.

#### Attended v50 slot B trial

On 2026-11-25 one v50 boot used the verified nine-partition NV backup.
All five slot B writes passed, and the readback matched all 8,192
supplied `vendor_boot_b` bytes. The UFS device returned NOP IN and
reported `bRefClkFreq=0x2`.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.214022–2.215131 | Device initialization | One SET accepted. First flag read returned `raw=0x0 polls=1 elapsed_us=1100 ret=0`. |
| 2.215565–2.215588 | One standard INQUIRY to LUN 0 | OCS `0x0`, response UPIU `0x21`, response and SCSI status `0x0`, zero flags and residual. Qualifier and type were zero, version `0x6`, format `0x2`, additional length 31, and `result=0`. |
| 2.215734–2.215981 | Hibern8 and HCI cleanup | Link and Hibern8 returned zero. HC and PHY both reached `0x11`; Deep H8 stayed prepared through IRQ release. |
| 90.205025–91.207861 | Timed warm return | `scsi_disks=0` before restart and at RAM startup. |

Ramoops and Android's `SYSTEM_LAST_KMSG` reported the same results.
Fastboot returned after 132 seconds. Stock D1 booted on A with enforcing
verity and the expected factory VBMeta digest.

This confirms a data-bearing SCSI command through the polled slot and
its DMA buffer. Normal SCSI registration, transfer completion IRQs,
capacity queries and partition reads remain untested. The early
`device_links_no_driver()` warning recurred before UFS probe.

### Mainline v51 INQUIRY transfer completion IRQ

[v51 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/0a48d0edc56f8ec20d6de72da6a485a0f7c79221)
keeps v50's single standard 36-byte INQUIRY on LUN 0 and its response
checks. NOP IN, the reference-clock read and `fDeviceInit` still use
polling. Before INQUIRY the driver clears the prior transfer status,
checks the doorbell is idle and arms a completion for slot 0. It sets
the descriptor's interrupt bit and unmasks transfer completion.
The HCI interrupt handler signals completion only after the doorbell
clears and the controller replaces the descriptor's initial OCS.

The driver masks transfer completion and drains the IRQ handler before
disarming the waiter. A 100 ms timeout records the doorbell, interrupt
status and OCS, then attempts to clear slot 0 if it is still busy.
There is no polling fallback for INQUIRY. The same RAM rescue keeps
SCSI scanning disabled. No SCSI host is registered and no capacity or
partition reads are issued. A successful query is followed by the same
Hibern8 check, HCI cleanup and timed warm return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v51 source and manifest. The DTB and private RAM rescue match v50. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control and device initialization | Use the verified nine-partition NV backup. Require `ufs-uic-v51 INQUIRY IRQ observed`, a GOOD v50 INQUIRY response with zero residual, Hibern8, HCI cleanup, zero SCSI disks and the timed return. | Capture the first failure, including doorbell, interrupt status and OCS on timeout. Return to stock A and confirm Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v51` passed strict
checkpatch, the targeted `W=1` compile and seven mocked interrupt cases.
These covered a delivered IRQ, stale and invalid completions, a lost
IRQ with completed DMA, timeout with a busy slot, and two preflight
rejects. All five image hashes, both AVB signatures, the unpacked
payload, ABL handoff and saved D1 slot sizes passed. Manifest SHA-256
`53873e1de814ba2e2e6c15bf839cb7785d615b262faa32b04058f37f39177271`. Archive SHA-256
`256cf75579b584944198927bb54e1e69b1377a24347a96836bad4a5d28c690bb`.

#### Attended v51 slot B trial

On 2026-11-25 one v51 boot used the verified nine-partition NV backup.
All five slot B writes passed, and the readback matched all 8,192
supplied `vendor_boot_b` bytes. The prep OFF request succeeded and
released the owned vote. The existing prep guard stopped before UFS
link startup, leaving the INQUIRY transfer IRQ untested.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.140145–0.140372 | Prep OFF qualification | HC was initially `0x10`, then read `0x32` while PHY remained `0x11`. The poll exited at 59 µs with `qualification=-5` (`-EIO`). |
| 2.120991 | CPM observation | HC had reached `0x13`, with PHY still `0x11`. The transition time is unmeasured. |
| 2.353986–12.723047 | Host probe attempts | The gate stayed at stage 4 (`STOPPED`), leaving UFS deferred with `guarded prep release did not qualify`. |
| 90.184360–91.187309 | Timed warm return | `scsi_disks=0` at RAM startup and before restart. |

The v45 poll only treats masked HC `0x10` as pending. The v51
sample `0x32 & 0x1f = 0x12` hit the error case. The later read
confirms that the expected terminal state was reached after that
sample. It gives no information about when HC left `0x32`.
Before another IRQ trial, qualify this prep OFF intermediate within
a bounded read-only poll while preserving the existing PHY and
terminal-state guards.

Ramoops and Android's `SYSTEM_LAST_KMSG` agree. Fastboot returned
after 133 seconds and stock D1 booted on A with enforcing verity
and the expected factory VBMeta digest.

### Mainline v52 prep OFF settling before the transfer IRQ test

[v52 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/08247b88ab3dfd9105bf575025ed444de767835b)
allows the existing prep OFF poll to wait through the exact raw HC
sample `0x32` seen on v51. The poll still checks the validity of the
child PSM reads and requires PHY `0x11` throughout. It accepts prep
OFF only when masked HC returns `0x13`. Other HC samples retain their
previous handling, including treating masked HC `0x10` as pending
and rejecting an unqualified `0x12`. The poll retains its 10 ms
timeout. The log records whether `0x32` was sampled, alongside the
existing start and end snapshots, elapsed time and qualification
result. The v51 log gives no timing bound inside this window for
the transition to `0x13`.

The guarded prep/core votes and v51 IRQ INQUIRY are carried forward.
There is one INQUIRY to LUN 0 after `fDeviceInit` clears. The RAM
rescue keeps disk scanning disabled and requests a timed warm
return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v52 source and manifest. The DTB and private RAM rescue match v51. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control and device initialization | Use the verified nine-partition NV backup. Capture `saw_hc_0x32`, elapsed time and qualification. Require terminal HC `0x13` and PHY `0x11`, then confirm `INQUIRY IRQ observed`, GOOD status with zero residual, Hibern8, HCI cleanup and zero SCSI disks. A boot that never samples `0x32` can qualify the IRQ but does not exercise the updated transition on hardware. | Capture the first failure and return to stock A without retrying. Confirm stock Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v52` passed strict
checkpatch and targeted `W=1` compilation. Seven mocked prep OFF cases
covered the recorded sample sequence, immediate success, a persistent
`0x32`, invalid PHY, unexpected HC and a disconnected child PSM.
The seven v51 IRQ mock cases still pass. All five image hashes, both
AVB signatures, the unpacked payload, ABL handoff and saved D1 slot
sizes passed. Manifest SHA-256
`5826e45805123a0bccebfb1de70e12d6be907f6291070373e1c4e51a39ee48f0`. Archive SHA-256
`1ebb9222dd34d508fda8da3a1856faf1b3ea05b9cc279a814460d76a9c6e7246`.

#### Attended v52 slot B trial

On 2026-11-25 one v52 boot used the verified nine-partition NV backup.
All five slot B writes passed, and the readback matched all 8,192
supplied `vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.152705–0.153014 | Prep OFF qualification | HC moved from `0x10` before the vote to `0x13` by the first post-vote sample. PHY was `0x11`. The poll reported `elapsed_us=4 qualification=0` and `saw_hc_0x32=0`. |
| 2.177237–2.181584 | Link and initialization | Link startup passed, NOP IN returned, `bRefClkFreq=0x2` and `fDeviceInit` was clear on the first read. |
| 2.182795–2.182815 | Transfer completion IRQ and INQUIRY | The armed slot received the IRQ. The command returned OCS `0x0`, response UPIU `0x21`, SCSI GOOD, zero residual and `result=0`. |
| 2.182952–2.183146 | Hibern8 and HCI cleanup | Hibern8 passed. HC and PHY both reached `0x11`; Deep H8 stayed prepared through IRQ release. |
| 90.197675–91.200447 | Timed warm return | Zero SCSI disks at RAM startup and before restart. |

This qualifies transfer completion via the HCI IRQ for one data-bearing
SCSI command on the dedicated slot. The v52 poll did not sample
`0x32`; that branch is covered offline and still needs a hardware
observation. Normal SCSI host registration and discovery remain
untested. The early `device_links_no_driver()` warning recurred.

Ramoops and Android's `SYSTEM_LAST_KMSG` agree. Fastboot returned
after 133 seconds. Stock D1 booted on A with enforcing verity
and the expected factory VBMeta digest.

### Mainline v53 LUN 0 capacity before discovery

[v53 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/570f01322382a5d7fd474a8e82b9c5b48a5b79c8)
adds one standard READ CAPACITY(10) on LUN 0 after the v52 link,
`fDeviceInit` and INQUIRY checks pass. It uses the same dedicated
transfer slot and requires a separate completion IRQ. The command
returns eight bytes of geometry data through one device-to-host PRD.
The driver checks OCS, response UPIU, SCSI status and residual before
decoding the big-endian last LBA and logical block size. It accepts
power-of-two block sizes from 512 to 4,096 bytes. A last LBA of
`0xffffffff` fails the diagnostic without issuing READ CAPACITY(16).

The prep OFF guard and subsequent Hibern8, HCI cleanup and timed
return follow v52. The kernel registers no SCSI host and issues no
logical-block reads. The private RAM rescue keeps disk scanning
disabled.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v53 source and manifest. The DTB and private RAM rescue match v52. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control and device initialization | Use the verified nine-partition NV backup. Capture prep OFF qualification, the distinct INQUIRY and READ CAPACITY(10) IRQs, both GOOD completions with zero residual, the reported geometry and computed capacity. Verify Hibern8, HCI cleanup, zero disks and the timed return. | Capture the first error and return to stock A without retrying. Confirm stock Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v53` passed strict
checkpatch and targeted `W=1` compilation. Mocked cases checked both
command descriptors and response paths, the opcode allowlist, IRQ
and build-option gates, transport failures, bad block geometry and
the READ CAPACITY(10) sentinel. All five image hashes, both AVB
signatures, the unpacked payload, ABL handoff and saved D1 slot sizes
passed. Manifest SHA-256 `a74f941f328ba1788db6063463739970a21bf33a164260b5140986a5833f7aec`.
Archive SHA-256 `57c53e5879cdc2dfcca3f1d1200f7aed831dbb141a093fea6b703b182ed2679a`.

#### Attended v53 slot B trial

On 2026-11-25 one v53 boot used the verified nine-partition NV backup.
All five slot B writes passed. The readback matched all 8,192 supplied
`vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.164711–0.165020 | Prep OFF | First post-vote sample was HC `0x13`, PHY `0x11`. Qualification passed in 4 µs with `saw_hc_0x32=0`. |
| 2.210085–2.215160 | Link and initialization | Link startup and NOP passed. `bRefClkFreq=0x2` and the first read of `fDeviceInit` returned clear. |
| 2.215448–2.215479 | INQUIRY | The transfer IRQ arrived. INQUIRY returned GOOD with zero residual and `result=0`. |
| 2.215599–2.215619 | READ CAPACITY(10) | A separate transfer IRQ arrived. OCS `0x0` and UPIU `0x21` reached the host, with response code `0x1`, SCSI status `0x2` (CHECK CONDITION), and `result=-5`. |
| 2.215638–2.215703 | Cleanup | The command failure skipped the Hibern8 check (`-ECANCELED`). HCI stop completed and the IRQ was freed. |
| 90.209453–91.212357 | Timed warm return | Zero SCSI disks at RAM startup and before restart. |

The second IRQ confirms that the host received the device response.
The diagnostic did not parse geometry after CHECK CONDITION. It also
did not log sense data, so the device's reason is unknown. Before
changing the command sequence or retrying automatically, validate the
sense length and decode the sense key, ASC and ASCQ from the response
UPIU if present.

Ramoops and Android's `SYSTEM_LAST_KMSG` agree. Fastboot returned
after 133 seconds. Stock D1 booted on A with enforcing verity and
the expected factory VBMeta digest.

### Mainline v54 sense data for LUN 0 READ CAPACITY

[v54 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/abba6fdc713c53beea4158fd9d9078281ba181ca)
keeps v53's command sequence and failure handling. If INQUIRY or READ
CAPACITY(10) returns CHECK CONDITION in a valid response UPIU for
slot 0 and LUN 0, the driver checks the response data segment and
sense lengths against the UFS sense field. It uses the SCSI core to
decode fixed or descriptor sense. The log reports the sense format,
key, ASC and ASCQ when all fields are available, or the two lengths
when the payload cannot be decoded. It issues no REQUEST SENSE and
does not retry either command.

The v52 prep OFF guard, IRQ transfers, scanning prohibition and
timed return remain in place. Geometry is accepted only on a GOOD
READ CAPACITY response. If a command fails, the Hibern8 check is
skipped and HCI cleanup still runs.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v54 source and manifest. The DTB and private RAM rescue match v53. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control and device initialization | Use the verified nine-partition NV backup. Capture both IRQs and either READ CAPACITY geometry or the CHECK CONDITION sense fields. Verify HCI cleanup, zero disks and the timed return. | If sense is unavailable, record the reported lengths. Preserve the first failure and return to stock A without retrying. Confirm stock Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v54` passed strict
checkpatch and targeted `W=1` compilation. Eleven mocked cases used
the diagnostic helper and the SCSI core decoder to verify fixed and
descriptor sense and reject missing, truncated, oversized or
unsupported responses. All five image hashes, both AVB signatures,
the unpacked payload, ABL handoff and saved D1 slot sizes passed.
Manifest SHA-256 `f30b91c0d09756d425044f9038010cfe9e21a19f1fb2f3016fb6c5ae91086348`.
Archive SHA-256 `3a44fbc0e50f993398da0aa8bb770b798aa55c1230d83903b914ae9b5bef2157`.

#### Attended v54 slot B trial

On 2026-11-25 one v54 boot used the verified nine-partition NV backup.
All five slot B writes passed, and the readback matched all 8,192
supplied `vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.199267–0.199576 | Prep OFF | Qualification passed in 4 µs with HC `0x13`, PHY `0x11` and `saw_hc_0x32=0`. |
| 2.242159–2.247396 | Link and initialization | Link startup and NOP passed, `bRefClkFreq=0x2`, and the first read of `fDeviceInit` returned clear. |
| 2.247677–2.247709 | INQUIRY | Transfer IRQ observed, GOOD status, zero residual. |
| 2.247872–2.247904 | READ CAPACITY(10) | Separate IRQ observed, OCS `0x0`, UPIU `0x21`, response `0x1`, status `0x2`. Fixed sense `format=0x70 key=0x6 asc=0x29 ascq=0x0 len=18`. |
| 2.247923–2.247986 | Cleanup | The error skipped Hibern8. HCI stop completed and the IRQ was freed. |
| 90.243352–91.246180 | Timed warm return | Zero SCSI disks before restart and at RAM startup. |

Sense key `0x6` is UNIT ATTENTION. ASC/ASCQ `29h/00h` reports
“power on, reset, or bus device reset occurred.” The code does not
identify which event occurred. A future fixture can test one retry
of the same READ CAPACITY command only after this exact current
UNIT ATTENTION. Geometry remains unmeasured.
[T10 ASC/ASCQ assignments](https://www.t10.org/lists/asc-num.htm)

Ramoops and Android's `SYSTEM_LAST_KMSG` agree. Fastboot returned
after 133 seconds. Stock D1 booted on A with enforcing verity and
the expected factory VBMeta digest.

### Mainline v55 one READ CAPACITY retry after reset Unit Attention

[v55 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/bde761da40e26c193ee1924f330864ed9e48ff10)
keeps the v54 sequence through the first READ CAPACITY(10). After
a valid response UPIU for slot 0 and LUN 0, it allows one identical
retry only for response code `0x1`, SCSI CHECK CONDITION, and
current fixed or descriptor sense `06/29/00`. Deferred sense,
missing or invalid sense, other errors and a failed retry end the
sequence. Both attempts require their own transfer completion IRQ.
The log distinguishes the retry from a first-attempt success.

The fixture issues no additional SCSI opcode or logical-block
read. It retains the v52 prep OFF guard, v54 sense logging and
v53 geometry checks. Successful geometry is followed by Hibern8
and HCI cleanup. The RAM rescue keeps disk scanning disabled and
requests the timed warm return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v55 source and manifest. The DTB and private RAM rescue match v54. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control and device initialization | Use the verified nine-partition NV backup. Capture INQUIRY, every READ CAPACITY IRQ and sense response, and the reported LUN 0 geometry. If the initial command reports current `06/29/00`, require exactly one retry. Verify Hibern8 on success, HCI cleanup, zero disks and the timed return. | Preserve the first terminal result and return to stock A. Confirm stock Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v55` passed strict
checkpatch and targeted `W=1` compilation. Twelve mocked cases
checked first-attempt success, the retry from both current sense
formats, the two-attempt limit, and rejection of unrelated or
malformed responses, deferred sense, timeouts and INQUIRY retry.
All five image hashes, both AVB signatures, the unpacked payload,
ABL handoff and saved D1 slot sizes passed. Manifest SHA-256
`b766360ac99afab2714b328bb632b471ff9ca5c6b7c05db9023720cab5c5262d`. Archive SHA-256 `ae38b9c6758060fd5556842d932bbe5cb8f0343ea89204d1b3f5053f9d7be1c9`.

#### Attended v55 slot B trial

On 2026-11-25 one v55 boot used the verified nine-partition NV backup.
All five slot B writes passed, and the readback matched all 8,192
supplied `vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.152738–0.153044 | Prep OFF | HC reached `0x13`, PHY remained `0x11`, and qualification passed in 4 µs with `saw_hc_0x32=0`. |
| 2.178299–2.182606 | Link and initialization | Link and NOP passed, `bRefClkFreq=0x2`, and the first `fDeviceInit` read returned clear. |
| 2.183672–2.183703 | INQUIRY | IRQ observed, GOOD status and zero residual. |
| 2.183823–2.183854 | First READ CAPACITY(10) | IRQ observed and CHECK CONDITION with current fixed sense `06/29/00`. Exactly one retry followed. |
| 2.183976–2.184014 | READ CAPACITY(10) retry | Separate IRQ observed. GOOD status, zero residual, last LBA 12,801,023, block size 4,096 bytes, and `result=0`. |
| 2.184159–2.184395 | Cleanup | Hibern8 passed. HC and PHY reached `0x11`. Deep H8 stayed prepared through HCI IRQ release. |
| 90.197550–91.200337 | Timed warm return | Zero SCSI disks at RAM startup and before restart. |

LUN 0 reported 12,801,024 logical blocks, or 52,432,994,304 bytes.
This is the geometry of LUN 0. Logical-block reads, partition
discovery and normal SCSI registration remain untested. The
early `device_links_no_driver()` warning recurred.

Ramoops and Android's `SYSTEM_LAST_KMSG` agree. Fastboot returned
after 132 seconds. Stock D1 booted on A with enforcing verity and
the expected factory VBMeta digest.

### Offline stock D1 device reference-clock diagnostic

The exact D1 `reference_clock_frequency_show` handler
(`Image` `0xec9f94`) takes the host semaphore, checks that
user access is allowed, and runtime-resumes the device WLUN.
It calls `ufshcd_query_attr` with `READ_ATTR` (opcode 3),
IDN `0x0a`, index 0 and selector 0 at `0xeca004`, then
calls runtime idle. The file belongs to the `attributes`
group, has mode 0444 and has no store callback. Its format is
`0x%08X\n`. The D1 table maps encodings 0, 1, 2 and 3 to
19.2, 26, 38.4 and 52 MHz respectively.

File existence alone is insufficient. D1 creates the sysfs
nodes before the device WLUN required by the handler
(`Image` `0xebc2c4`–`0xebc2ec`). The
`--ufs-refclk-only` fixture waits for the complete stock
inventory and the five-parent, nine-target NV guard. It
checks the canonical `3c2d0000.ufs` platform node, the
bound `google-ufshcd` driver and the exact sysfs attribute,
then reads it once with an eight-second timeout. It logs
the raw code and the frequency it encodes, or records why
the read was refused. There is no USB data service and the
query accesses device metadata only. The 90-second warm
return timer is armed independently.

The 2026-11-24 package preserves the four factory images.
Replacement `init_boot` SHA-256 is
`20df104741b6496f2ed3ba4789bd54cfcfcbe6013951e1bcf0a4801dea4efdaa`.
The initrd ends at `0x88fb699b`, below the FDT at
`0x8a000000`. The image hashes, AVB leaf, saved B sizes,
vendor boot readback and archive checks passed. Thirteen
ARM64 BusyBox mocks covered the read and refusal cases.
Eight more covered guard-first dispatch and mode refusal.
The real device attribute remains to be captured.

## Stock D1 kernel and NV backup feasibility

The saved D1 factory chain includes the exact boot images and
VBMeta graph used by stock A. The kernel release is
`6.12.81-android16-6-gf5369e7496cb-ab16467452-4k`. ABL copies
`vendor_kernel_boot`, `vendor_boot`, then `init_boot`
(`abl.img` `0x80448`–`0x80520`). The smallest stock-kernel
variant can preserve the factory boot, vendor boot, vendor kernel
boot and DTBO bytes. A replacement executable `/init` in the final
`init_boot` archive would supply RAM-only PID 1. Qualification
must verify the merged archive's executable and prevent entry to
Android init or recovery. The archived stock initrd ends at
`0x88eb44fd`, leaving 18,135,811 bytes below the FDT. Check
the exact repack's memory ranges and the 8 MiB slot capacity.
The handoff-only trial below confirmed that unlocked D1 reaches
Linux with the test-signed `init_boot` and factory ML-DSA-65
`boot`. The module-loading inventory variant remains untested.

The [stock UFS audit](bringup/audit-stock-ufs.py) reads the
embedded kernel configuration and the factory 4 KiB module
archive. It checks the UFS hard dependency closure and shows
where the factory loader requests each relevant module. Supply
the kernel payload extracted from `boot.img` and the
`vendor_kernel_boot` module ramdisk. It accepts these files in
their factory LZ4 form.

```sh
python3 device/grizzly/bringup/audit-stock-ufs.py "$STOCK_KERNEL" "$STOCK_VENDOR_RAMDISK"
```

The archive has 199 modules and 23 in the UFS hard closure,
including `ufs.ko`. That closure includes the DA9188 PMIC stack,
GSA and Trusty IPC. DT-selected suppliers such as AMB SMMU,
the mailbox and interrupt aggregators, clock/reset providers,
pinctrl and the DA9189 regulators add dependencies outside
`modules.dep`'s UFS closure. The stock boot log records GSA
wrapped-key initialization before UFS disk registration. The
saved boot reached `scsi host0: ufshcd` at 1.242 s and attached
five disks whose SCSI write-protect flags were off.
Custom PID 1 also needs to preserve the applicable stock
module parameters and loader ordering. The kernel and vendor
module release strings differ in the factory pair. Preserve
their matched KMI and module version checks. The factory UFS
module has no individual signature trailer. Its provenance
comes from the authenticated factory boot chain.

Stock D1 has `CONFIG_DEVTMPFS=n`, `CONFIG_BLK_DEV_BSG=y` and
`CONFIG_SCSI_UFS_BSG=y`. The existing rescue init expects a
devtmpfs and its `/dev/sd*` guard covers block nodes. Stock's
normal module list also loads `sg.ko`. A stock-compatible
inventory boot needs a custom RAM PID 1, a private tmpfs
`/dev` and an audited module list. It can report partition
labels, sizes and readiness through stock ramoops without
exporting a shell or disk nodes. A backup fixture needs a
restricted reader with the parent disk and target partitions
confirmed read-only and unmounted. That reader must exclude
raw SCSI/BSG ioctls, block-node recreation and general root
access. Stock probe-time controller operations still need
separate qualification. A block read-only flag applies to
block I/O. The stock image includes advanced RPMB handling
in UFS BSG even though the standalone RPMB option is off.
The runbook's PMIC and Trusty backup requirement applies to
experiments with those drivers.

The stock B0 UFS node has `mphy_ref_clk` at 38.4 MHz. It has
neither the generic `ref_clk` name nor `ref-clk-freq` property
used by the generic driver to choose a `bRefClkFreq` value.
The exact decompressed stock Image checks those inputs at
`0xeb90fc`–`0xeb914c` and `0xeb9268`–`0xeb9298`. At gear-up
it skips the generic attribute query and setter when the
configured value is absent (`0xebf920`–`0xebf928`). Preserving
the stock DT therefore keeps that generic write dormant.
On the connected stock A, the read of
`/sys/bus/platform/devices/3c2d0000.ufs/attributes/reference_clock_frequency`
returned `Permission denied`. The device's current value is
still unverified.

Stock userspace fastbootd also gives no NV fetch path. The D1
recovery ramdisk declares a user build. Its exact `fastbootd`
command table registers `fetch` at `0x60d14`–`0x60d50`, with
handler `0x5d430` returning `Fetch is not allowed on user build`
before partition lookup. This is separate from the ABL fetch
policy.

The saved unlocked stock A capture still shows `adbd` running as
`shell` in a production `user` build with `ro.debuggable=0`. The
D1 Recovery ramdisk has the same debug policy. Its root console
is gated on a debuggable build and its sideload ADB service has no
shell or file sync. The original D1 and v37-return stock bugreports
contain four diagnostic directory archives from `nvdata`,
`protect_f` and `protect_s` in `dumpstate_board.bin`. These cover
selected file trees and have no complete partition checksum or
restore contract. Keep the archives private. No supported stock
interface in the available evidence can produce the complete
NV backup. A read-only ADB check on unlocked stock A on
2026-11-24 found all nine paths below under `/dev/block/by-name`.
The shell reported each path unreadable. The check opened no
block devices.

A fresh stock A capture on 2026-11-24 exported the four supported
diagnostic trees. The private off-repo set holds 14 files inside
6,406,262 bytes of compressed archives. Each gzip stream and tar
index passed validation. All four SHA-256 checks and the capture
manifest check passed. The capture is partial and leaves the
complete partition backup requirement open.

| Partition | Bytes in the saved D1 v38 Fastboot snapshot |
| --- | ---: |
| `persist` | 134,217,728 |
| `nvdata` | 209,715,200 |
| `nvram` | 96,468,992 |
| `protect_f` | 20,971,520 |
| `protect_s` | 20,971,520 |
| `modemdp` | 1,048,576 |
| `modem_a` | 1,454,374,912 |
| `modem_b` | 1,454,374,912 |
| `devinfo` (separate, may change) | 8,192 |

Use `google,malibu-grizzly` as the stock DT's first compatible.
The primary inventory totals 3,235 MiB. A scratch descriptor
with these labels and separate `devinfo` passed
`tools/nv-backup -d grizzly --list` offline. Resolve each live
device by unique GPT `PARTNAME` and verify its size and RO
state before copying.

### Stock D1 RAM inventory prototype

The offline 2026-11-24 prototype uses the factory D1 4 KiB GKI
`6.12.81-android16-6-gf5369e7496cb-ab16467452-4k` and retains the
factory `boot`, `vendor_boot`, `vendor_kernel_boot` and `dtbo`
images byte for byte. [The packer](bringup/pack-stock-inventory.py)
checks the exact D1 image hashes, vendor ramdisk paths, hard
module dependencies, ARM64 handoff bounds, test AVB signature and
partition sizes from a saved Fastboot snapshot. The current
inventory `init_boot` preserves the factory generic ramdisk
and appends the overlay containing the replacement `/init`.
The extraction order preserves the early factory devices and
modprobe and then replaces the factory Android init executable.
See the supplier-preserving build below for the measured bounds.

The [module list](bringup/stock-inventory.modules) has 37 entries
in verified hard-dependency order. It includes the stock UFS
module and DT-selected suppliers. Its ability to bind every
supplier is unverified on Grizzly. It excludes `sg.ko`, Android
init, modem and secure-storage userspace, and the optional
`pixel-reboot.ko` dependency chain. The Grizzly v3 handler in that
reboot module writes GBMS tag `0x5253424d` on a named `bootloader`
restart. The prototype uses the kernel's ordinary reboot syscall
with no restart command string.

[PID 1](bringup/stock-inventory-init) checks `google,malibu-grizzly`
and slot B before it loads any modules. The GKI's factory
protected-module loads run earlier. PID 1 temporarily makes sysfs
writable to request the in-memory `warm` reboot mode, remounts
sysfs read-only and verifies the mode before arming its 90-second
timer. It requires an enabled ramoops console and a successful
kmsg write. Stock D1 registers the backend name with index −1
and enables it at decompressed Image `0x8d96a0`–`0x8d96ec`.
PID 1 disables automatic module loading and uses a private
tmpfs `/dev` with only `console`, `null` and `kmsg`. The inventory
reads GPT labels, sector counts and RO flags from sysfs, and emits
`grizzly-stock-inventory` markers to the kernel console. It neither
opens block data nor provides a login or export interface. Mocked
complete, missing, duplicate and wrong-size inventories passed
under the exact ARM64 BusyBox ash used in the fixture.

The GKI PSCI path at decompressed Image `0xeee96c`–`0xeee9d8`
uses `SYSTEM_RESET2` for warm mode when firmware advertises it.
D1 BL31 initializes capability bit 18 from its non-null reset2
callback (`0x21d38`–`0x21d44`), returns that capability through
`PSCI_FEATURES` (`0x210c0`) and maps architectural reset type 0
to platform mode 4 and CDD reason `0xbaba`
(`0x26740`–`0x26774`). This is the expected warm reset route
with the exact D1 chain. Stock A reported PSCI v1.1 and uses
`loglevel=8 printk.devkmsg=on`. Retention of this fixture's marker
still needs a hardware check. The ordinary restart
still shuts down registered devices, and the SCSI disk driver
can request a cache sync on shutdown.

Inventory userspace has no block read or write interface. The
stock probe still sends PMIC rail and decoupling commands,
initializes Trusty and GSA, and requests inline-encryption keyslot
evictions with a null key before disk registration. Stock D1
exposes the physical UFS LUNs with write protection off. These
controller operations still need qualification under the
runbook's PMIC and Trusty backup requirement. A matching inventory
confirms discovery and sizes. A separate restricted reader and
verified block RO state are required before a backup.

| Step and risk | Expect and pass | Stop condition | Rollback |
| --- | --- | --- | --- |
| Offline package check, low | `pack-stock-inventory.py` verifies factory hashes and the AVB leaf, then `check-slot-b.py` passes the saved size and stock A checks. | Any image hash, size, archive or handoff mismatch. | Retain the previous verified files. |
| Attended inventory trial, high | After the PMIC and Trusty backup gate and explicit trial approval, recheck the live product, slot A and capacity with `check-slot-b.py`, then use the slot B staging and stock A return above. After return, read `adb -s "$GRIZZLY_SERIAL" shell dumpsys dropbox --print SYSTEM_LAST_KMSG`. Expect the stock GKI, slot and warm-mode markers, `factory preloads verified`, the ordered supplier loads, and all nine unique expected labels. Record whether the 90-second timer runs. | Missing backup or approval, any failed preflight, protected-module or AMB check failure, unexpected reset, missing or mismatched record, module load failure, or missing console. | Catch Fastboot with Volume Down, select A, release Volume Down and boot stock D1. The early watchdog can return the phone before the timer if takeover fails. Preserve the logs and leave further B boots pending. |

### Stock D1 handoff-only preflight

Use `pack-stock-inventory.py --handoff-only` to emit a separate
five-image set for the handoff and logging check. The final
archive contains a handoff marker and omits the inventory module
manifest. PID 1 checks board, slot, warm mode and the enabled
ramoops console. It disables module autoload and checks that
`/proc/modules` is empty and there are zero SCSI disks, then
checks both again before the timed return. The current handoff
fixture requests restart after 20 seconds. The exact GKI has an
empty static usermode-helper path and no uevent helper. The D1
board's `google,ufshc` match string is present in the vendor UFS
module and absent from the GKI, whose built-in generic UFS
support does not bind that node. DA9188, Trusty and GSA probe
through the vendor modules that this variant leaves unloaded.

The handoff-only image passed the RSA leaf, archive and saved
slot size checks. Its initrd ends at `0x88cdfae8` including the
bootconfig allowance. An offline merge of the legacy LZ4
fragments in ABL order preserves the factory vendor paths and
replaces `/init` with the inventory script. The GKI config
enables LZ4 initrd, script and ELF loading. The successful v38
trial established that unlocked D1 boots locally signed RSA
leaves in the all-RSA test set. The stock handoff fixture adds
an executable PID 1 to `init_boot` and pairs the test RSA-4096
leaf with the factory ML-DSA-65 `boot`. The earlier stock B
D1 boot had the same factory VBMeta digest as stock A. The slot
B stage script only writes the five boot images.

| Step and risk | Expect and pass | Stop condition | Rollback |
| --- | --- | --- | --- |
| Offline check, low | Build with `--handoff-only`. The packer reports zero stock module requests. Verify the handoff marker is present and the inventory manifest absent in `inventory.cpio`. | Signature, slot capacity, archive or mode mismatch. | Retain the previous verified artifacts. |
| Attended handoff trial, moderate | After explicit approval, use the D1 stage-only and stock A return procedure above with the 20-second handoff-only bundle. Check the full `vendor_boot_b` readback against the D1 `vendor_boot.img` with `check-slot-b.py --vendor-boot-readback`. After stock A returns and passes the usual health checks, inspect pstore and `SYSTEM_LAST_KMSG` for `return timer armed delay_s=20`, the two zero-module and zero-disk samples, and `timed restart requested delay_s=20`. Check the bootloader reset record for `0xbaba`, the expected PSCI warm reset reason. | Any preflight or readback failure, APC watchdog or other unexpected reset, module/disk presence or missing marker. | Catch Fastboot with Volume Down, select A, release Volume Down and boot stock D1. Use the attended Fastboot fallback if the timer does not arm. Capture the logs before considering another trial. |

#### Attended handoff-only trial

On 2026-11-24 all five slot B writes succeeded and the entire
67,108,864-byte `vendor_boot_b` readback matched the D1 factory
image. The host issued one B boot and saw Fastboot return 107 s
later with B still selected and two retry attempts remaining.
Stock D1 completed boot on A with enforcing verity and the
same factory VBMeta digest as before the trial.

The slot B console identifies the stock D1 4 KiB GKI and shows
Linux running the replacement `/init`. Both ramoops and
`SYSTEM_LAST_KMSG` contain the PID 1 announcement at 0.596080 s,
the slot B check at 0.617278 s, `reboot_mode=warm sysfs=ro`, and
`handoff complete modules=0 scsi_disks=0` at 0.623285 s. The
board archive confirms the prepared initrd end `0x88cdfae8`.
ABL reported the test key mismatch for `init_boot_b` against
the factory chain and continued to Linux on the unlocked phone.
Android's BootReceiver copied `console-ramoops-0` to
`SYSTEM_LAST_KMSG`. The log ends at
10.722250 s after the idle-domain sync-state timeout. Neither the
second module/disk snapshot nor the timer marker is in either
retained copy.

The post-trial `bootlogs/bl_data.bin` ties that handoff to GDMC
`DER Event 2` and `SEM: apc wdt expiry` at GDMC time 71.691126 s.
The DBL entry preceding the handoff reports that it enabled a
60-second watchdog. The time budget remaining at Linux entry
was not measured.
GDMC reports CDD reason `0xcbca` and triggers a warm crash reset.
ABL reports `0xcbea` (`APC Watchdog Early`) and applies its
automatic cold reboot before the Volume Down Fastboot entry.
The startup marker was recoverable across that sequence. The
90-second userspace timer did not account for the observed reset.
The GDMC timestamp is on the firmware timebase and does not
measure the elapsed kernel time.

Before PID 1, the GKI attempts its stock protected-module load.
It reports `Failed to load pkvm module goog-mba-ctrl: 11` and
continues with pKVM enabled without an IOMMU driver. The pre-init
`modprobe` also reports missing `/dev/kmsg`. The factory
`init_boot` supplies that character node before the attempt.
The handoff overlay creates the node only when its PID 1 starts.
The GKI uses an explicit `/system/bin/modprobe` helper for this
protected-module path and passes through the process wait
status (`0x2190834`–`0x2190954`). That helper uses `/dev/kmsg`
to establish standard I/O before exec. If the open fails, it
leaves any closed descriptors unrepaired. The exact static D1
`modprobe` checks those descriptors in Bionic startup
(`0x254160`) and tries `/dev/null` and `/sys/fs/selinux/null`
on `EBADF`. If it cannot repair a descriptor, it deliberately
faults at `0x25479c`. The trial lacks both early device nodes,
which explains the observed status 11 if the helper starts with
closed descriptors. No linker or shared libraries are needed
by that static executable. The available ARM64 host container
lacks SVE and could not execute the factory tool through startup.

The initial offline archive model prepended the exact factory generic
ramdisk to the inventory overlay in `init_boot`. All five newc
archives decoded in ABL order. The factory `/dev/null`,
`/dev/console`, `/dev/urandom`, `/dev/kmsg` and `modprobe`
survived the overlay, and the final `/init` was the inventory
script. The modeled initrd ends at `0x88fb4f0a`, with room
below the FDT. The supplier-preserving build below implements
that layout and verifies preloads before its `insmod` pass.
The six protected modules and their five
hard dependencies are already in the inventory manifest. The
factory `modules.softdep` adds no dependency to this closure.

Match these normalized stock `/proc/modules` names before
starting inventory loads.

```text
arm_smmu_v3_kvm goog_mba_cpm_iface goog_mba_ctrl google_gtc
io_pgtable_pixel irq_gia_google irq_gia_lib mbfs mbfs_cpm_backend
pinctrl power_controller
```

On stock A, `readlink -f` confirmed that
`/sys/bus/platform/devices/4190000.amb_smmu/driver` resolves to
`/sys/bus/platform/drivers/kvm-arm-smmu-v3`. The ADB shell cannot
read AMB's `device_id` and `cmdq_sync_count` telemetry files.
The stock vendor bugreport records device ID `0` and later S2
traffic from UFS at SID `0x8000`. Driver binding precedes
`kvm_iommu_init_hyp`, so check a readable boot log for
protected-module or IOMMU init failures before loading suppliers.
A required positive early `cmdq_sync_count` is still unqualified.

#### 20-second handoff fixture

Within the updated handoff-only archive, only PID 1 changed.
It reports the timer delay when the timer starts
and when it requests restart. The 20-second interval leaves
time for the previous 10.722250 s deferred-probe observation
while aiming to beat the firmware watchdog. The supplier-loading
inventory mode still uses 90 seconds.

The replacement `init_boot` SHA-256 is
`344177c28d69aa1dffdabba16fd3e5ea39b602f09fa18844709473e14a6db58d`.
The initrd ends at `0x88cdfb25` including bootconfig allowance.
Local AVB verification, all image hashes, the saved slot sizes
and the full `vendor_boot_b` readback comparison passed. The
exact ARM64 BusyBox timer test waited 20 seconds, made the late
zero-module and zero-disk check and reached the mocked ordinary
reboot. The inventory mode selected 90 seconds in its mock.
The attended trial below checked the real timer and firmware
reset path.

#### Attended 20-second handoff trial

On 2026-11-24 the five slot B writes passed and the full
67,108,864-byte `vendor_boot_b` readback matched the factory
image. The Mac issued one B boot. Ramoops and `SYSTEM_LAST_KMSG`
agree on the GKI `6.12.81-android16-6-gf5369e7496cb-ab16467452-4k`
running the replacement PID 1. Both report `reboot_mode=warm`
and these markers.

| Kernel time (s) | Observation |
| ---: | --- |
| 0.614359 | Timer armed for 20 seconds |
| 0.615321 | Initial sample with zero modules and zero SCSI disks |
| 20.617907 | Late sample with zero modules and zero SCSI disks |
| 20.617986 | Timer requested restart |
| 20.621768 | Linux logged `reboot: Restarting system` |

The Mac detected Fastboot 75 s after the boot request. It
selected and booted A. Stock D1 completed boot with enforcing
verity and the pre-trial factory VBMeta digest.

The returned stock bugreport's `bootlogs/bl_data.bin` matches
this trial's initrd end `0x88cdfb25`. The following GDMC epoch
records CDD reason `0xbaba`, GRM reset reason 3 and a warm reset.
ABL applied its automatic cold reboot, and the following boot
entered Fastboot because Volume Down was held. D1 labels
`0xbaba` as `Kernel PANIC` in the archive. The retained Linux
console shows the ordinary reboot request, and the offline
GKI/BL31 trace maps that warm PSCI request to the same code.
Together the logs verify the intended timer and reset path.

The pre-init `goog-mba-ctrl` load again returned status 11.
This fixture preserves the original handoff-only early ramdisk
layout. The supplier-preserving inventory path remains untested
on the phone.

#### Supplier-preserving inventory fixture

The offline 2026-11-24 build retains 2,969,964 bytes of the
factory generic ramdisk as the exact prefix of the signed
`init_boot` ramdisk. The executable overlay follows it. The
combined initrd ends at `0x88fb5536` including bootconfig
allowance, with 17,083,082 bytes below the FDT. The 8 MiB
replacement `init_boot` SHA-256 is
`378b7b79aaf6ac42c14f99973ade3b2bd6fc233d0868e260e57a986b192110f6`.
All five image hashes, the RSA leaf, the saved slot capacities
and the comparison with the saved full `vendor_boot_b` readback
passed. The four other image files match the factory images.

The packer derives 11 expected preloads from the exact D1 hard
dependencies. PID 1 requires every expected name to be `Live`,
an exact AMB driver binding, readable early pKVM logs without
protected-module or IOMMU init errors, and zero SCSI disks.
After validating the full manifest it skips the 11 verified
preloads and requests the other 26 in order. ARM64 BusyBox
mocks passed 19 preload and AMB cases and verified that order.
The handoff-only path still checks for zero modules and disks.

Inventory requests `google_wdt.ko` after `google_gtc.ko` and
`google_timestamp_sync.ko`. The stock probe starts the cluster
watchdogs and registers them as already running. The GKI enables
`CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED` and sets
`CONFIG_WATCHDOG_OPEN_TIMEOUT=0`, so the kernel can service
successfully bound watchdogs before userspace opens a device.
The 90-second timer still depends on successful watchdog takeover
and continued kernel progress.

These checks run after the factory pre-init path. The preload-only
trial below confirms the expected preloads and AMB binding with
the same factory ramdisk prefix. The inventory fixture's later
supplier loads remain untested. The stock UFS probe can issue
PMIC, Trusty and GSA operations, so the backup gate above applies
before a hardware trial. Inventory userspace reads partition
metadata and does not open raw block devices.

#### Factory preloads-only fixture

`pack-stock-inventory.py --preloads-only` retains the exact D1
generic ramdisk prefix and packages the same eleven expected
preloads as inventory mode. The overlay has the `preloads-only`
marker and leaves out `/stock-inventory.modules`. PID 1 checks
the protected-module set, the AMB driver and the boot log at
startup and again before the 20-second warm restart. Both checks
require zero SCSI disks. The fixture ends its startup path after
the preload check without requesting a module insertion.

All five image checksums passed, along with the test AVB leaf
verification, saved slot sizes and saved full `vendor_boot_b`
comparison.
The signed replacement `init_boot` SHA-256 is
`5b43ec48883718ead90bf61af5118b220d5b8ac9f3a898a06f79a9ca6d9eb1e3`.
The initrd ends at `0x88fb534b` with the bootconfig allowance,
leaving 17,083,573 bytes below the FDT. Unpacking confirmed the
2,969,964-byte factory ramdisk prefix and the absence of the
manual module manifest. Offline ARM64 tests exercised success,
missing preloads, contradictory archives, a late SCSI disk,
and the existing handoff and inventory branches.

The closure contains the stock `power_controller.ko` and
`pinctrl.ko`. `power_controller.ko` reads the existing vote
through MBFS (`0x3ba4`) and requests ON for initially off
`force-on` domains (`0x3d14`–`0x3d48`). The D1 B0 DT marks
HSIO-S, UFS prep `0x222` and UFS core `0x220` as `force-on`.
A core-on request can reach CPM's LDO1S/LDO24S helper if PSM1
is in state 2. The protected pinctrl probe can also resume the
HSIO-S CSR power domain (`pinctrl.ko` `0x6a40`–`0x6a58`).
These operations can occur before the PID 1 checks. The closure
has no direct PMIC, Trusty, GSA, UFS, RPMB or block-storage
imports. CPM rail changes depend on the inherited vote and
hardware state. The existing CPM and PMIC backup gate therefore
applies to the preload-only trial as well.

| Step and risk | Expect and pass | Stop condition | Rollback |
| --- | --- | --- | --- |
| Offline package check, low | Build with `--preloads-only`. Verify the factory prefix, 11 expected preloads, preload-only marker and absence of the manual inventory manifest. | Any archive, signature, capacity or layout mismatch. | Retain the verified 20-second handoff-only bundle. |
| Attended preload check, power-control risk | After the backup gate and trial approval, stage only the reviewed five slot B images and match the full vendor boot readback. Boot B once and return through Fastboot to stock A. In ramoops and `SYSTEM_LAST_KMSG`, check `factory preloads verified phase=startup`, `preloads-only complete`, `factory preloads verified phase=before-restart`, `scsi_disks=0` in both samples and `timed restart requested delay_s=20`. Expect `0xbaba` in the firmware archive. | Missing backup or approval, failed preflight, wrong module or AMB state, storage enumeration, a missing sample or an APC watchdog reset. | Catch Fastboot with Volume Down, select A and boot stock D1. Preserve the logs and review the failure before any UFS inventory boot. |

#### Pre-init factory helper startup fixture

Build with `pack-stock-inventory.py --preinit-helper-only`. The
package preserves the D1 generic ramdisk and its early device
nodes. The last newc archive replaces `/system/bin/modprobe`
with [the probe script](bringup/stock-modprobe-probe) and keeps
the byte-identical factory helper at
`/grizzly-inventory/factory/modprobe`. The same archive supplies
the replacement `/init` and selects the tested 20-second
zero-module handoff. It contains neither module manifest.

The GKI's pKVM callback opens `/dev/kmsg` and passes descriptors
0 through 2 to `/system/bin/modprobe`, invoked as
`-q -- goog-mba-ctrl`. The wrapper recognizes that exact first
attempt. It runs the factory helper with only `--help`, preserves
its inherited descriptors and records the child exit code. The
exact D1 binary's help branch (`0x2969a4`–`0x2969b4`) calls
`print_usage` at `0x297f80` and returns zero before constructing
the module loader. The wrapper returns 125 for every invocation,
so the kernel records an intentional failed load and stops the
preload sequence. Expect raw wait status `32000`. This exercises
factory helper startup without inserting `power_controller.ko`
or the UFS suppliers. It leaves actual pKVM module loading and
AMB attachment for a later trial.

The offline 2026-11-24 build has replacement `init_boot` SHA-256
`ac6f14c906ea5bd7b10819844117c1804b1522f608d762bf044437e37ab61fab`.
Its initrd ends at `0x890158e7` including bootconfig allowance,
16,688,921 bytes below the FDT. The image checksums, test AVB
leaf, saved capacities and full saved `vendor_boot_b` readback
pass. A merged-archive check verified all five newc archives, the
four stock character devices, the original tool and the final
wrapper. Three ARM64 mocks verified fixed `--help` and exit 125.
The exact factory tool exits with SIGILL on the host ARM64 VM,
which lacks SVE. It stops before the help branch there. The
retained Grizzly kernel log shows SVE available on the Pixel.

| Step and risk | Expect and pass | Stop condition | Rollback |
| --- | --- | --- | --- |
| Offline helper check, low | Match the original helper hash, the final `/system/bin/modprobe` wrapper and the four factory character nodes in the merged archive. Confirm the handoff marker and absence of both module manifests. | Any archive, signature, capacity or layout mismatch. | Retain the tested 20-second handoff bundle. |
| Attended helper trial, moderate | After approval, stage the five checked B images and verify the full vendor boot readback. Boot B once and return to stock A. In ramoops and `SYSTEM_LAST_KMSG`, check `factory helper help start`, factory usage output and `factory helper help status=0 wrapper_status=125`. Check for the raw kernel wait status `32000`, zero modules and zero SCSI disks in both handoff samples, and the 20-second restart with firmware reason `0xbaba`. Also check the earlier `/dev/kmsg` warning is absent. | Missing approval, failed preflight, any module or disk present, an unexpected helper result or reset, or an incomplete marker set. A missing marker alone is inconclusive because the logger uses the early descriptors. | Catch Fastboot with Volume Down, select A and boot stock D1. Preserve the logs before any supplier-enabled trial. |

#### Attended pre-init helper trial

On 2026-11-24 all five slot B writes passed and the full
67,108,864-byte `vendor_boot_b` readback matched the factory
image. The Mac issued one B boot. Ramoops and `SYSTEM_LAST_KMSG`
recorded the stock D1 GKI `6.12.81-android16-6-gf5369e7496cb-ab16467452-4k`
and these events.

| Kernel time (s) | Observation |
| ---: | --- |
| 0.571269 | Pre-init wrapper started the exact factory helper |
| 0.573398 | Factory helper printed its usage text |
| 0.574055 | Factory helper returned 0 and wrapper reported its planned exit 125 |
| 0.574450 | The GKI reported raw wait status 32000 for `goog-mba-ctrl` |
| 0.615491 | Replacement PID 1 started |
| 0.642909 | Startup sample had zero modules and zero SCSI disks |
| 20.643025 | Late sample also had zero modules and zero SCSI disks |
| 20.643100 | Timer requested restart in warm mode |
| 20.647365 | The kernel logged `reboot: Restarting system` |

The retained log has both inherited-descriptor markers and no
missing `/dev/kmsg` warning. This verifies that preserving the
factory early ramdisk allows the factory binary to reach its
usage branch from the kernel's pre-init call. Actual protected
module insertion and AMB binding still need a supplier-enabled
trial under the CPM and PMIC backup gate.

Fastboot returned 62 s after the B boot request. The Mac
selected and booted A. Stock D1 completed boot with enforcing
verity and the same factory VBMeta digest as before the trial.
The returned stock bugreport matches this fixture's initrd end
`0x890158e7`. Its following firmware records show CDD reason
`0xbaba`, the warm reset, ABL's automatic cold reboot, and
Volume Down entry to Fastboot. Those records agree with the
20-second timer and the retained ordinary Linux restart.

#### AMB isolation audit

`arm_smmu_v3_kvm.ko` has one ELF module dependency,
`io-pgtable-pixel.ko`. Its actual probe scope on the exact D1
B0 tree is six available `arm,smmu-v3` nodes. The module counts
them at `0x4560`–`0x45ac`, probes synchronously at `0x4694`,
and checks that the number of successful bindings equals the
count before loading its EL2 module (`0x46a8`–`0x46c8`).

| SMMU | Stock DT power domain |
| --- | --- |
| AMB at `0x4190000` | No explicit domain |
| Display at `0xf190000` | `0xa2` |
| GPU at `0x34c00000` | `0xe9` |
| TPU at `0x36100000` | `0x67` |
| Audio DSP at `0x385be000` | `0x48` |
| Media at `0x3d190000` | No explicit domain |

AMB's three IRQs route through the FABSTBY pulse SGIA at
`0x4371000`, inputs `0xf`, `0x11` and `0x16`, then to GIC SPI
`0xf4`. Those IRQs add a platform dependency on the stock
SGIA driver and its `irq-gia-lib.ko` dependency. The SMMU's
named IRQ reads can tolerate unavailable IRQs in its probe.
An AMB binding alone therefore cannot qualify interrupt delivery.

The GKI stops the protected load list at the first nonzero
helper status (`0x21903a8`–`0x21903c8`). Its failure branch
clears guest pVM firmware and still reaches KVM IOMMU init
(`0x218fd40`–`0x218fd50`). Substituting an AMB module load for
the first request would still reach the same six SMMU probes.
A fixture limited to AMB would require a different board tree
and an independently qualified interrupt supplier. The driver
also resets SMMU hardware during probe (`0x4ea0`) and can issue
SMC `0x83000011` from EL2 when `smc_s2` is enabled, as requested
in the stock boot arguments. The effective SMC path also needs
at least one successfully probed node with `synchronize-fw`
(`0x4ff8`–`0x5048`), and the init call checks that flag on the
individual instance (`.hyp.text` `0xc58`–`0xc84`). Only GPU
has that property in B0. A genuinely isolated AMB tree would
skip the audited firmware-sync calls. It would still need
IRQ-supplier and AMB reset qualification. The unchanged stock
tree includes GPU. D1 BL31 routes function `0x11` through the
nonsecure EL2 check at `0x1b8d0` and into Trusty at `0x2a8e0`.
The Trusty payload looks up the SMMU by address and validates
its state and class before an enable or resume path. No such
operation has been observed in a custom preload trial.

The verified 20-second `--preloads-only` fixture remains the
hardware check for real protected loads in the stock sequence.
Revalidation matched the image checksums, local AVB leaf,
saved slot B capacities and full `vendor_boot_b` readback.
The stock sequence includes the force-on and power-domain
behavior above. The existing CPM and PMIC backup gate applies.

#### Attended factory preload trial

On 2026-11-24 the owner approved one preload-only slot B trial
without a full NV backup. All five slot B writes passed and the
full 67,108,864-byte `vendor_boot_b` readback matched the factory
image. The Mac issued one B boot and detected Fastboot 64 s
later with B selected. Fastboot reported Volume Down as the
entry reason. The Mac selected A, verified the active slot and
issued one reboot. USB ADB was initially unavailable after the
return. When it came back, the Mac verified completed stock D1
on slot A with enforcing verity and the original VBMeta digest.

Ramoops and `SYSTEM_LAST_KMSG` agree that the stock pKVM preload
sequence completed and that the preload-only guard passed.
The `kvm-arm-smmu-v3` driver bound `4190000.amb_smmu`. AMB
reported 40-bit input and output addresses and allocated 256
entries each for its command and event queues. The log names
all six stock SMMUs and has no protected-module or IOMMU init
failure. The guard found exactly the expected eleven `Live`
modules and zero SCSI disks at 0.884867 s and 20.889339 s.
It requested the warm restart at 20.889423 s. Linux logged
`reboot: Restarting system` at 20.893836 s.

The returned stock bugreport matches the preload fixture's
initrd end `0x88fb534b`. Its firmware records show CDD reason
`0xbaba`, the warm reset, the automatic cold reboot and
Volume Down entry to Fastboot.

This trial qualifies the factory preload closure and AMB binding
with the supplier-preserving archive. UFS initialization was
qualified in the separate inventory trial below. The full NV
backup remains pending.

#### Attended stock UFS inventory trial

On 2026-11-24 the owner approved one supplier-preserving
inventory trial without a full NV backup. All five slot B
writes and the full 67,108,864-byte `vendor_boot_b` readback
passed. The Mac issued one B boot and detected Fastboot 135 s
later. It selected A, booted stock D1 and verified enforcing
verity and the original factory VBMeta digest.

Both retained logs report the expected 11 factory preloads,
AMB binding and the full 26-module request sequence. Trusty
and GSA preceded the UFS driver. The UFS host joined IOMMU
group 1, applied the factory calibration, configured ESI and
MCQ and reported HS gear 5, series 1, rate 2. Five physical
LUNs appeared as `sda`–`sde`. The source driver reported write
protection off for every LUN.

| Kernel time (s) | Observation |
| ---: | --- |
| 0.852358 | PID 1 verified the factory preload set and AMB binding |
| 1.281284 | PID 1 requested `ufs.ko` |
| 1.493513 | `scsi host0: ufshcd` |
| 2.842402 | Inventory complete with all nine expected labels and sector counts |
| 90.835231 | Timer requested restart |
| 91.374239 | Linux printed `reboot: Restarting system` |

Ramoops and `SYSTEM_LAST_KMSG` agree on all nine target records.
Each reports `ro=0`. The inventory path reads sysfs metadata
and opens no raw block device. During kernel shutdown the UFS
driver logged a UIC `DME_SET` timeout for attribute `0xd085`
and CPM logged an `hsios_gpio_ref_clk` timeout. Linux continued
to its restart. Those messages occurred after inventory and
do not change the enumeration result.

The returned stock bugreport matches the inventory initrd end
`0x88fb5536`. It records a GDMC warm reset with CDD reason
`0xcafe` (`User Reboot(S/W Reboot)`), followed by ABL's cold
reboot and Volume Down entry to Fastboot. The kernel console
records the stock GCDD normal restart callback before the
firmware transition. The timer and kernel restart both ran.

This establishes stock-kernel UFS enumeration and the Grizzly
partition layout. The backup step still needs verified RO
enforcement for every parent LUN and target partition, an
unmounted-state check, a restricted USB reader and a return
window long enough for the copy and second hash pass.

#### NV read-only guard fixture

`pack-stock-inventory.py --nv-guard-only` uses the successful
stock UFS inventory path and keeps the 90-second return timer.
After inventory matches the nine expected labels and sector
counts, PID 1 verifies the storage topology and applies Linux
block read-only flags. It uses private temporary device nodes
in RAM for the block ioctls, then removes them. The fixture
ends after the guard check. The host receives proof through
the retained console after stock A boots.

The guard verifies all five SCSI parent paths belong to
`3c2d0000.ufs`, validates device numbers against their sysfs
records, and checks every UFS disk and partition for mounts
by major/minor and for active holders. It sets the five parent
flags first, then the nine target flags. `BLKROGET` and sysfs
must both report `1`. It rechecks topology before the final
verification and removes the temporary private nodes outside
`/dev`. The exact BusyBox opens them `O_RDONLY` for the ioctls.
The operation changes Linux block write policy in RAM. The
stock UFS probe still performs the controller operations noted
above.

The 2026-11-24 build has replacement `init_boot` SHA-256
`9992d73d0166fab80655b3110d2acfaa469308521e9dab7d43607dfce83f8a46`.
The initrd ends at `0x88fb641a`, 17,079,270 bytes below the FDT.
The exact stock ramdisk prefix, four factory image files, test
AVB leaf, image hashes, saved B capacities and the saved full
`vendor_boot_b` readback passed. Fourteen ARM64 guard mocks
covered success and refusal paths, including an active mount,
a holder, a wrong size, changing topology and failed RO ioctls.
Four more tested the PID 1 dispatch and its missing-guard and
failure exits. The checks did not use phone storage.

The host `tools/nv-backup` now accepts `NV_BACKUP_TRANSPORT`
for a restricted reader executable. Its operations are `probe`,
`read LABEL OFFSET_BYTE LENGTH_BYTE` and `sha256 LABEL`.
The tool accepts at most 8 MiB per read, verifies the exact
chunk length, compares an independent phone-side hash with
each copy, and checks identity, size and read-only state again
at the end. The structured protocol uses GPT labels as request
arguments. It does not give the host a device shell. The backup
format stays `SHA256SUMS`, `partitions.txt` and `NV-BACKUP`.
The host suite passed the existing SSH tests and structured
transport mocks, and the structured path passed a macOS smoke
test with Homebrew Bash and GNU coreutils. The local host bundle
uses a private Grizzly descriptor with the eight primary
partitions, separate `devinfo` and an empty write allowlist.

The target-side reader and the stock USB link are separate
dependencies for the full backup. The read-only trial should
qualify the guard before any fixture exposes partition data.

The exact D1 kernel has USB ACM and NCM gadget functions built
in. Stock Android uses UDC `a210000.dwc3` and the Google PHY
firmware `usb_phy_fw_2.27.0.bin`. The 40,960-byte firmware was
extracted offline from the hash-verified D1 OTA's vendor image.
Its SHA-256 is
`723ff8e0e2aeda20c9b3b18277c93a6a69ddb4f45ff22a30838d7392ebb2b345`.
The stock path needs the DWC3 glue, Google PHY, role supplier
and external eUSB2 repeater. The direct USB2 role diagnostic
is still a candidate. The stock role switches permit userspace
control, and the repeater's role path enables regulators and
sends I²C writes. This guard fixture stops before USB setup.

| Step and risk | Expect and pass | Stop condition | Rollback |
| --- | --- | --- | --- |
| Offline guard check, low | Build `--nv-guard-only`. Verify the factory prefix, guard marker and helper, inventory manifest, and the hash, slot and AVB checks above. | Archive, signature or layout mismatch. | Keep the verified inventory fixture. |
| Attended guard check, power-control risk | With approval under the existing backup gate, stage the verified five files on B, check the full vendor boot readback, boot B once and return to A. Expect nine matching sizes, five `NV guard parent` lines and nine `NV guard target` lines with `ro=1`, `NV read-only guard complete parents=5 targets=9` and the timed return in the retained logs. | Any failed preflight, guard refusal, missing label or LUN, writable target, mount or holder, or unexpected reset. | Catch Fastboot with Volume Down, select A and boot stock D1. Preserve the logs. A later reader must recheck the guard in its own boot before exporting any block data. |

#### Attended NV read-only guard trial

On 2026-11-24 the owner approved one guard-only slot B boot
without the full NV backup. All five slot B writes and the
67,108,864-byte `vendor_boot_b` readback passed. Fastboot
returned 135 s after the single B boot request. The Mac
selected and booted A. Stock D1 completed boot with enforcing
verity and the original factory VBMeta digest.

The UFS host registered at 2.051466 s. Ramoops and
`SYSTEM_LAST_KMSG` agree on all nine initial `ro=0` size
matches and all fourteen final `ro=1` guard records. The
guard verified parents `sda`–`sde` and the eight primary NV
partitions on `sda`, with the separate `devinfo` on `sdd1`.
It completed topology, mount and holder checks, matched the
read-only ioctl results with sysfs, and removed the temporary
nodes by 4.097951 s. PID 1 reported `NV guard complete` at
4.098246 s. The timer requested restart at 90.876350 s and
Linux logged `reboot: Restarting system` at 91.396652 s.

The returned stock bugreport matches the guard fixture's initrd
end `0x88fb641a`. It confirms a GDMC warm reset with CDD reason
`0xcafe`, followed by the automatic cold reboot and Volume Down
entry to Fastboot.

The read-only flags apply to this Linux boot. A backup reader
must run the same guard again before exposing data. This run
copied no block payloads. The stock USB link and the restricted
device-side reader remain to be qualified.

The USB2 candidates `nvmem-rmem.ko`, `i2c-designware-core.ko`,
`i2c-designware-platform.ko`, `google-eusb2-repeater.ko`,
`google_icc.ko`, `google-usb-phy.ko` and `dwc3-google.ko` pass
the stock hard-dependency order after the verified inventory
manifest. A dummy-data USB trial can test the link before
any partition export.

#### Stock USB2 dummy-data fixture

`pack-stock-inventory.py --usb2-test`
keeps the D1 boot, vendor boot, vendor kernel boot and DTBO.
The replacement init ramdisk retains the factory prefix and
runs the same 37-module inventory and 14 read-only checks.
PID 1 starts the USB test only after the guard succeeds.
The seven USB modules load in the audited order from the
unchanged vendor kernel ramdisk. D1's first vendor boot
ramdisk already contains `lib/firmware/usb_phy_fw_2.27.0.bin`.
The packer checks its bytes against the D1 vendor image hash
above and uses the existing copy.

On the Mac, run `python3 device/grizzly/bringup/check-stock-usb2.py --wait 75`
before starting the slot B boot. It looks for the CDC ACM
callout device under the USB product `Grizzly USB2 Diagnostic`
and serial `grizzly-usb2-test`. The test sends
`GRIZZLY-USB2-PROBE` and expects `GRIZZLY-USB2-OK` followed by
65,536 bytes of the repeated byte sequence `0x00`–`0xff`.
The payload is embedded in the ramdisk. Its SHA-256 is
`7daca2095d0438260fa849183dfc67faa459fdf4936e1bc91eec6b281b27e4c2`.
The USB function has no command shell, block reader or partition
export. The 90-second return timer is armed before module loading.

The 2026-11-24 image has replacement `init_boot` SHA-256
`946e6bc10e9c8508d643a884a6bd1c475ac35b3431385db092295a713f79e4a3`.
The initrd ends at `0x88fb796b`, 17,073,813 bytes below the
FDT. The five file hashes, four factory image comparisons,
AVB leaf, saved slot B capacities and full vendor boot readback
passed. ARM64 BusyBox tests covered PID 1 refusing to start USB
after guard failure, the seven-module order, role and gadget
cleanup, and malformed or missing requests. The macOS checker
passed descriptor discovery and complete exchange tests with a
mocked IORegistry and a local pseudo-terminal.

| Step and risk | Expect and pass | Stop condition | Rollback |
| --- | --- | --- | --- |
| Attended USB2 test, power-control risk | With owner approval under the backup gate, stage the five verified images on B and verify the vendor boot readback. Boot B once with the data cable connected. Expect the 14 read-only checks, both device roles, UDC `a210000.dwc3`, and the complete synthetic payload on the Mac. | Guard, role, UDC or payload failure, or unexpected reset. Capture the retained FDT/ramoops evidence before another test. | Catch Fastboot with Volume Down, select A and boot stock D1. Verify enforcing verity and the original factory VBMeta digest. |

The eUSB2 repeater role path invokes regulator and I²C
operations. The direct device-role path for this fixture
still needs a cable test. Stock Android's full Type-C attach
and charger stack is outside this fixture. A successful trial
qualifies the link for a later restricted reader running under
the NV guard in its own boot.

On 2026-11-24 the owner approved one dummy-data boot without a
fresh NV backup. All five slot B writes and the full vendor boot
readback passed. Ramoops and `SYSTEM_LAST_KMSG` agree that the NV
guard completed at 5.680776 s with five read-only parents and
nine read-only targets. The seven USB modules loaded. I²C
controller `3a1cd000.i2c` initialized, the eUSB2 repeater probe
completed at 5.754417 s, and the combo PHY reported firmware
2.27.0 at 5.818984 s.

The child `a210000.dwc3` joined IOMMU group 2. At 5.819940 s
the parent reported `probe deferred due to dwc3_drd_sw is not
ready` and powered down the USB top domain. The fixture timed
out waiting for the role switches at 13.862410 s, before
requesting a role or configuring the gadget. A deferred-probe
retry at 15.862094 s hit the same child role-switch check.
The Mac saw no diagnostic descriptors or ACM device and received
no payload. Exact D1 kernel config confirms `USB_DWC3=y`,
`USB_DWC3_DUAL_ROLE=y` and `USB_ROLE_SWITCH=y`.

The timer requested a restart at 90.932030 s. Fastboot was
visible to the Mac 134 seconds after the B boot request. Stock
slot A booted with enforcing verity and the original factory
VBMeta digest. The NV backup still requires a working transport.

The exact D1 kernel's `dwc3_probe` reads `usb-psy-name` from
the child FDT node, then calls `power_supply_get_by_name`.
The property is `usb` on Grizzly. With no matching supply,
the core returns `-EPROBE_DEFER` before registering its role
switch. The wrapper checks for the child's switch immediately
after populating the child and removes the child on failure.
This accounts for the parent defer logged on both attempts.
In the decompressed D1 `Image`, the lookup is at `0xcfc520`
and the failure block starts at `0xcfc5c0`.

Read-only stock A sysfs resolves `power_supply/usb` to SPMI
device `ebf1000.spmi/spmi-0/0-04`, the `max77759tcpc-spmi@4`
node in the D1 tree. Stock A loads `tcpci_max777x9_spmi`,
`tcpci_max77759` and `usb_psy`. The TCPC closure is absent
from the dummy fixture. `usb_psy.ko` supplies the registration
helper, which the TCPC driver calls during probe. The helper
registers `usb` even if its `gcpm` charger lookup fails. The
TCPC root adds eleven stock modules by hard dependencies.
That closure covers module symbols. The stock TCPC probe also
waits for the `USB_DR_EL` and `CHARGER_MODE` votes and a Type-C
mux before reaching `usb_psy_setup`. Grizzly declares
`phy-mode-mux` and omits `gvotable-lazy-probe`. A stock-supplier
trial therefore needs the platform drivers that provide those
dependencies, along with a check that `usb` is present before
DWC3 probes. That trial exercises PMIC and Type-C paths and
needs separate attended approval.

#### Offline DWC3 probe isolation image

The exact core continues if the child property is absent.
The local follow-up package omits only `usb-psy-name` on
`a210000.dwc3`. It keeps the same four other images and the
same USB2 runtime. Entry 19 supplies the property through
`/fragment@26/__overlay__`. Replacing that record with four
FDT NOPs preserves all entry offsets and sizes. Applying the
original and modified overlays to the same stock base and
diffing the results shows one removed property. The TCPC's
`usb-psy-name = "usb"` and the child's peripheral role-switch
settings remain present.

Replacement `dtbo.img` SHA-256 is
`075c0d37e382253b58f50e5cac6cfdcfe5e0bad0f57964eb68c7146a921f33e9`.
The rebuilt hash footer uses the stock DTBO's `NONE` algorithm.
AVB hash verification, all five image hashes, measured B sizes,
saved vendor boot readback and initrd/FDT placement passed
offline.

#### Attended DWC3 isolation trial

On 2026-11-24 the owner approved one isolation boot without a
fresh NV backup. All five slot B writes and the full vendor boot
readback passed. Ramoops and `SYSTEM_LAST_KMSG` record five
read-only parents and nine read-only targets at 4.634774 s.
DWC3 joined IOMMU group 2, the wrapper accepted device role at
4.903570 s, and the fixture bound the ACM gadget to
`a210000.dwc3` at 4.979767 s. The DWC3 probe passed with the
single child property removed.

The Mac saw the exact gadget product and serial at USB high
speed from 18.132 s to 50.290 s after the boot request. Its
checker found no verified ACM callout and received no dummy
bytes. At the request deadline, the kernel reported
`status=12 speed=high-speed state=addressed` at 36.997024 s.
The link reached USB address assignment. The recorded state at
timeout was before configuration, and the device had not
received the full 19-byte request. The fixture unbound the
gadget and restored both roles to `none` and sysfs to read-only.

The 90-second timer requested restart at 90.832535 s. The Mac
saw Fastboot 134 seconds after the B boot request and returned
to stock A. ADB confirmed stock D1 had completed boot with
enforcing verity and the original factory VBMeta digest. The NV
backup remains pending.

The next transport diagnostic should capture EP0 setup requests
and errors, including the configuration descriptor and
`SET_CONFIGURATION`. The exact D1 Image contains the
`dwc3_ctrl_req` and `dwc3_event` tracepoints. On the Mac,
capture the matching device subtree and its interfaces while the
gadget is present. This can show whether the host attempts to
configure the gadget and whether its ACM interfaces acquire a
serial driver.

#### Offline DWC3 EP0 trace image

Build with `--usb2-test --usb2-ep0-trace ISOLATION_DTBO` and
pass the matching isolation tree to `--board-dtb`. The packer
checks both isolation input hashes. The five-image package
keeps the previous isolation DTBO and the three stock kernel
and vendor images. Only `init_boot` changes. Its SHA-256 is
`d62486e2fc61ce262eabfda7401755d79f3fb9cbec49c83f2c8f861b91d15e95`.
The initrd ends at `0x88fb7e0c`, below the FDT at
`0x8a000000`. The five image hashes, DTBO and init boot AVB
checks, prior B capacities and saved vendor boot readback
passed offline.

After the NV guard passes and before UDC binding, the fixture
arms a private tracefs instance with 16 KiB per CPU. It records
DWC3 setup requests, and enables controller and EP0 events and
EP0 SETSTALL commands when the corresponding filters are
accepted. The log records which filters were enabled. At
exchange exit it stops the trace and logs ring occupancy,
up to 64 setup records and 40 context records, and an omitted
record count before unbinding. A missing request is conclusive
only within the portion captured without overwrite or truncation.
The existing 90-second return timer and synthetic exchange stay
in place.

Start the Mac checker before the slot B reboot.

```sh
python3 device/grizzly/bringup/check-stock-usb2.py --wait 100 --timeout 12 --observe NEW_PRIVATE_JSONL_PATH
```

The observer records changes in the matching USB subtree,
including any numeric address and configuration properties,
interface descriptors, and associated CDC, ACM and serial
services exposed by IORegistry. The file is created with mode
0600. Unexposed properties and services outside the observed
ancestry remain unknown. Observer changes are also collected
when the checker times out without a serial device.

Seven ARM64 BusyBox mocks checked setup, bounded output and
cleanup, including missing trace controls and a failed trace
read. The Mac observer passed mocked discovery and a real
pseudo-terminal transfer of all 65,536 synthetic bytes. The
next attended boot should compare the observed configuration
descriptor requests, `SET_CONFIGURATION` and EP0 status with
the Mac interface records, then return the Pixel to stock A.

#### Attended DWC3 EP0 trace trial

On 2026-11-24 the owner approved one EP0 trace boot without a
fresh NV backup. All five slot B writes and the full vendor
boot readback passed. The NV guard verified five read-only
parents and nine read-only targets at 4.559749 s. The fixture
armed the setup, controller and stall tracing before binding
the gadget to `a210000.dwc3` at 4.911990 s.

Ramoops and `SYSTEM_LAST_KMSG` agree on the DWC3 setup trace.
It records `SET_ADDRESS(1)`, the device and BOS descriptor
requests, and configuration descriptor requests for 9 and
75 bytes. DWC3 received `Set Configuration(Config = 1)` at
10.367914 s on the trace clock. The next setup request read
the current configuration. The device reported
`speed=high-speed state=configured` and queued all 65,536
synthetic bytes at 12.944285 s. The ring retained 213 of 213
events and the console preserved all 37 setup records. The
console cap omitted 136 of 176 context records, which limits
inspection of the later EP0 status phases.

The Mac observer first identified the gadget at 18.218 s.
At 23.444 s it recorded configuration 1 with
`AppleUSBACMControl` on interface 0 and `AppleUSBACMData` on
interface 1. At 23.729 s `IOSerialBSDClient` exposed one
verified serial callout. The checker received all 65,536 bytes
in 0.011 s with the expected SHA-256
`7daca2095d0438260fa849183dfc67faa459fdf4936e1bc91eec6b281b27e4c2`.
The transfer establishes the synthetic USB path for this boot.
The earlier isolation trial's failure to configure remains
unexplained.

The fixture exited cleanly and requested its timed restart at
90.875048 s. Fastboot returned 135 seconds after the B boot
request. Stock slot A completed boot with enforcing verity and
the original factory VBMeta digest. The full NV backup still
requires a restricted partition reader and its own NV guard
check before any partition payload is sent.

#### Offline Grizzly NV backup reader image

The local package uses the tested DWC3 isolation DTBO, stock
D1 kernel and vendor images, and a new `init_boot` with the
restricted reader. Build with `--usb2-test --usb2-nv-reader
READER_ELF ISOLATION_DTBO` and supply the matching
`--board-dtb`. Build the reader as a static ARM64 executable.
The 2026-11-24 package has `init_boot` SHA-256
`a600dfa4420a507974cbef3828148b4a17bf7f6767d34814e025ac44ec7da7be`
and reader SHA-256
`6150ecd98a592f8198b08826b11885f17b7a5b8fc79f5e82250ccf25b4e8a7ba`.
The initrd ends at `0x8901119c`, below the FDT at
`0x8a000000`. All five image hashes, the DTBO and init boot
AVB checks, the measured slot B capacities, and the saved
vendor boot readback passed.

The guard publishes its verified topology in a root-owned
mode-0600 RAM file after checking all five parents and nine
targets. The ACM reader presents only the nine GPT labels.
It checks live identity, read-only flags, mounts and holders,
opens the selected block device read-only, and checks the
actual file descriptor before and after preparing a reply.
It accepts sector-aligned reads up to 8 MiB and calculates
SHA-256 from a separate full read. The host bridge keeps one
descriptor-verified serial session open with a mode-0600
local socket in a mode-0700 directory. The backup tool
requires each local image to match the separate phone-side
read and rechecks the inventory after the copy.

The measured partitions total 3,392,151,552 bytes (3.16 GiB).
The independent read in the phone adds UFS and hashing work
without sending the partition bytes twice over USB. At 5
MiB/s, the USB copy alone takes about 11 minutes. PID 1
arms a 20-minute fallback. The reader closes after an explicit
host `finish`. PID 1 then requests the warm return after the
gadget and USB roles are cleaned up. Hold Volume Down when
cued for that return, or before the timer expires if the
connection fails.

Start the macOS bridge before booting slot B. Use the private
host bundle with the Grizzly descriptor and the GNU
coreutils directory on PATH.

```sh
bridge_dir=$(mktemp -d /private/tmp/grizzly-nv.XXXXXXXX)
export GRIZZLY_NV_SOCKET="$bridge_dir/bridge.sock"
export NV_BACKUP_TRANSPORT="$bundle/tools/stock-nv-transport.py"
"$NV_BACKUP_TRANSPORT" serve "$GRIZZLY_NV_SOCKET" --wait 100
```

In a separate shell with the same two environment variables,
wait for `Grizzly NV reader ready` before starting the copy.

```sh
PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH" \
  /opt/homebrew/bin/bash "$bundle/tools/nv-backup" -d grizzly "$backup_dir"
```

Use a new private backup directory outside the checkout.
After all nine hashes and the bundle manifest verify, cue
Volume Down, then send `"$NV_BACKUP_TRANSPORT" finish`.
Select and start stock A from Fastboot. Treat this copy as a
recovery snapshot. Returning to stock A can change the NV
contents, so the freshness check before later PMIC work
still applies.

Offline tests covered verified-topology publication, PID 1
dispatch and timed return, ARM64 reader refusal after guard
changes, and an exact 8 MiB serial frame. The macOS bridge and
`tools/nv-backup` completed a nine-partition synthetic copy
and verification across a local pseudo-terminal. A wrong
phone-side hash removed the partial backup. The attended run
below verified hardware startup and full-size copy throughput.

#### Attended full NV backup

On 2026-11-24 the owner approved one reader boot without a
fresh NV backup. All five slot B image writes and the full
vendor boot readback passed. The retained log shows the
1,200-second return timer, five guarded UFS parents and nine
guarded targets at 5.583438 s, and ACM ready at 5.915850 s.
The Mac accepted the reader inventory 20 seconds after the
slot B boot request.

The Mac copied all nine partitions, totaling 3,392,151,552
bytes, in 303 seconds including the separate phone-side
SHA-256 reads and final inventory check. An independent local
pass checked all nine output sizes and hashes, the guarded
inventory, and the directory and file modes. The recovery
snapshot is stored privately outside the checkout.

The reader acknowledged `finish` at high speed in the
configured state. The fixture restored read-only sysfs and
requested the warm return at 353.115731 s. The Mac saw
Fastboot 32 seconds after `finish`, selected A and started
stock D1. ADB confirmed Android completed boot with enforcing
verity and the original factory VBMeta digest. The backup
contains the pre-return NV state.

#### Stock D1 read-only RAM rescue

Run the stock inventory packer on the Mac with `--usb2-test
--usb2-nv-reader READER_ELF ISOLATION_DTBO` and the matching isolation
board DTB as described above. The packer now emits `images/` and a
standalone `host-tools/` directory together. For the bridge and backup
commands above, set `bundle` to the generated `host-tools/` directory.
The descriptor has an empty `UFS_RW` and exactly nine backup labels.

The rescue keeps the factory D1 kernel, UFS module and UFS regulator
settings. The isolation DTBO changes USB setup. PID 1 enumerates GPT
metadata, sets and verifies all UFS parents and partitions read-only,
and then starts the restricted ACM service. There is no Android or
installed root, shell service, raw SCSI service or other partition
payload reader. `tools/nv-backup` is the first payload reader through
ACM. The service allows 1,140 seconds for the copy and its independent
on-phone hash pass, with the 1,200-second return timer armed by PID 1.
The previous full copy and verification took 303 seconds.

The offline repack passed all five image hashes, AVB, saved slot size
and handoff bounds checks. Its `init_boot` SHA-256 is
`0c0405256bd3fb214c340721b16588e82f02096a02d115a36cc6d030b757e175`.
It keeps the previously tested reader binary and packs the current PID 1.
The bundled host tools completed a synthetic nine-partition backup and
rejected a separate bad-hash test.

Keep the images and the backup off-repo. Use the attended staging and
return sequence only after approval. Stop if the guard or descriptor
check fails, any target is missing, or a hash differs. An incomplete
copy does not qualify as a backup. Use the timed return and select
stock A if the bridge cannot finish.

On 2026-11-24 one slot B boot of this repack verified the five image
writes and the full `vendor_boot_b` readback. The retained console
records five read-only UFS parents and nine read-only targets at
4.571028 s, before the USB gadget was ready at 4.912065 s. The Mac
accepted the guarded inventory and started `nv-backup` 19 seconds
after the B boot request. No other partition payload reader ran.

The first copy lost the USB stream during `modem_a` with the default
8 MiB chunks. `nv-backup` removed the incomplete copy. The ACM port
remained present, but a fresh probe encountered bytes from the
interrupted reply. The host drained those bytes without saving them,
re-probed the same guarded inventory, and retried within the same
boot with `NV_CHUNK_BLOCKS=4`. The cause of the first interruption
remains unknown.

The retry copied all nine partitions to the Mac and checked them
against independent phone-side hashes in 356 seconds. A separate Mac
pass verified all sizes and SHA-256
hashes, the inventory, and file and directory permissions for
3,392,151,552 bytes. The verified backup is private and outside the
checkout. `finish` completed at USB high speed and restored sysfs
read-only before the warm return. Fastboot appeared 32 seconds after
the host requested `finish`. Stock D1 completed boot on A with
enforcing verity and the original VBMeta digest. The snapshot records
the NV state before that stock boot.
