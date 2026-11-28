<!-- SPDX-License-Identifier: MIT -->
# Grizzly M1 bring-up plan

## Where it stands

- **Boot and recovery.** The Grizzly test phone is back on November D1 stock A.
  Slot B reached [Omarchy systemd and authenticated USB SSH from a read-only
  RAM root](#attended-usb-ssh-handoff-trial). Stock A is the recovery path.
- **Storage.** The [v72 UFS trial](#attended-v72-slot-b-trial) verified
  read-only GPT discovery and a 4 KiB read through `boot_b`. The
  [v73 trial](#attended-v73-slot-b-trial) verified the guarded partition
  range. The [stock D1 RAM rescue](#stock-d1-read-only-ram-rescue) can
  back up all nine NV partitions. Persistent installation is pending.
- **Display.** Stock D1 identified the CGYDA panel. The
  [mainline PHY scaffold](#slot-b-mainline-dsi0-phy-vote-fixture) acquired
  wrapper → BE → DSI0 and released it in reverse. First native output
  still needs verified APB and external reset readiness and a working
  compressed display pipeline. PHY TX and DSI0 host reads stay disabled.
- **Stock trace.** [Perfetto on A](#attended-stock-d1-perfetto-result)
  captured live SurfaceFlinger frames while scrolling. The two vendor
  events remain unavailable. Take a fresh verified nine-partition
  backup after that stock session before the next Linux trial.

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

### Stock A boots and NV backup age

The private NV copies record the slot B rescue state before Android
returned on A. Android may write radio partitions on each stock
boot. A host-side hash check verifies the saved copy and does not
compare it with the phone's current contents. The table identifies
the last **recorded** stock D1 A boot before each trial covered
here. It uses the stock-return checks in the linked trial results
and the attended order. For v61, the retained preflight also
matched the stock properties saved after v60. This record cannot
exclude unrecorded Android boots or establish per-partition
changes. Exact A boot-completion times are unavailable. For
future trials, record the preflight's slot, build, enforcing
verity and boot-completed check, the UTC boot-request times for
the predecessor and trial, and which backup was verified and
whether it predated a stock boot.

| Trial on B | Last recorded stock A boot before it | NV copy context |
| --- | --- | --- |
| [v39](#v39-slot-b-result) | After the [full NV backup reader](#attended-full-nv-backup) | The reader copy preceded that stock return. The trial used it with owner approval and without a new comparison against the phone. |
| [Stock D1 power trace](#stock-d1-slot-b-trace-result) | After v39 | No replacement copy is recorded for this trace. |
| [Stock D1 larger-buffer trace](#stock-d1-larger-buffer-trace-result) | After the first stock D1 power trace | No replacement copy is recorded for this trace. |
| [Stock D1 provider event trace](#stock-d1-provider-event-trial-result) | After the larger-buffer trace | No replacement copy is recorded for this trace. |
| [D1 CPM firmware trace](#d1-cpm-trace-hardware-result) | After the provider event trace | No replacement copy is recorded for this trace. UFS did not load. |
| [D1 pre-core PSM1 trace](#d1-psm1-trace-hardware-result) | After the CPM firmware trace | The existing nine-partition copy predated the latest stock boot. The owner approved this single trial with that copy. |
| [D1 prep PSM1 and genpd trace](#d1-prep-psm1-and-genpd-hardware-result) | After the pre-core PSM1 trace | The existing copy predated that stock boot. The owner separately approved this trial. |
| [v40](#attended-v40-slot-b-trial) | After the [read-only RAM rescue](#stock-d1-read-only-ram-rescue) | The rescue made a second verified nine-partition copy before its stock return. It was already older than stock A for v40. |
| [v41](#attended-v41-slot-b-trial) | After v40 | Same read-only RAM rescue copy. |
| [v42](#attended-v42-slot-b-trial) | After v41 | Same copy. |
| [v43](#attended-v43-slot-b-trial) | After v42 | Same copy. |
| [v44](#attended-v44-slot-b-trial) | After v43 | Same copy. |
| [v45](#attended-v45-slot-b-trial) | After v44 | Same copy. |
| [v46](#attended-v46-slot-b-trial) | After v45 | Same copy. |
| [v47](#attended-v47-slot-b-trial) | After v46 | Same copy. |
| [v48](#attended-v48-slot-b-trial) | After v47 | Same copy. |
| [v49](#attended-v49-slot-b-trial) | After v48 | Same copy. |
| [v50](#attended-v50-slot-b-trial) | After v49 | Same copy. |
| [v51](#attended-v51-slot-b-trial) | After v50 | Same copy. |
| [v52](#attended-v52-slot-b-trial) | After v51 | Same copy. |
| [v53](#attended-v53-slot-b-trial) | After v52 | Same copy. |
| [v54](#attended-v54-slot-b-trial) | After v53 | Same copy. |
| [v55](#attended-v55-slot-b-trial) | After v54 | Same copy. |
| [v56](#attended-v56-slot-b-trial) | After v55 | Same copy. |
| [v57](#attended-v57-slot-b-trial) | After v56 | Same copy. |
| [v58](#attended-v58-slot-b-trial) | After v57 | Same copy. |
| [v59](#attended-v59-slot-b-trial) | After v58 | Same copy. |
| [v60](#attended-v60-slot-b-trial) | After v59. Stock D1 A was checked before the v60 boot request at 14:58:48 UTC on 2026-11-25. | Same copy, all nine hashes rechecked locally. The v59 stock-return request time is unavailable. |
| [v61](#attended-v61-slot-b-trial) | After v60. The A restart was requested at 15:01:29 UTC and verified before the v61 boot request at 15:19:29 UTC on 2026-11-25. | Same copy, all nine hashes rechecked locally. Stock A restart after v61 was requested at 15:22:41 UTC and startup was verified. |
| [v62](#attended-v62-slot-b-trial) | After v61. Stock D1 A preflight matched the prior return. The v62 boot was requested at 15:38:16 UTC on 2026-11-25. | Same copy, nine hashes rechecked. The owner approved this trial using the copy that predates the stock boot. |
| [v63](#attended-v63-slot-b-trial) | After v62. Stock D1 A preflight matched the prior return. The v63 boot was requested at 15:49:24 UTC on 2026-11-25. | Same copy, nine hashes rechecked. The owner approved this trial using the copy that predates the stock boot. |
| [v64](#attended-v64-slot-b-trial) | After v63. Stock D1 A preflight matched the prior return. The v64 boot was requested at 16:09:22 UTC on 2026-11-25. | Same copy, nine hashes rechecked. The owner approved this trial using the copy that predates the stock boot. |
| [v65](#attended-v65-slot-b-trial) | After v64. Stock D1 A preflight matched the prior return. The v65 boot was requested at 16:39:58 UTC on 2026-11-25. | Same copy, nine hashes rechecked. The owner approved this trial using the copy that predates the stock boot. |
| [v66](#attended-v66-slot-b-trial) | After v65. Stock D1 A preflight matched the prior return. The v66 boot was requested at 16:54:28 UTC on 2026-11-25. | Same copy, nine hashes rechecked. The owner approved this trial using the copy that predates the stock boot. |
| [v67](#attended-v67-slot-b-trial) | After v66. Stock D1 A preflight matched the prior return. The v67 boot was requested at 17:12:03 UTC on 2026-11-25. | Same copy, nine hashes rechecked. The owner approved this trial using the copy that predates the stock boot. |
| [v68](#attended-v68-slot-b-trial) | After v67. Stock D1 A preflight matched the prior return. The v68 boot was requested at 17:57:17 UTC on 2026-11-25. | Same copy, nine hashes rechecked. The owner approved this trial using the copy that predates the stock boot. |
| [v69](#attended-v69-slot-b-trial) | After v68. Stock D1 A preflight matched the prior return. The v69 boot was requested at 18:15:08 UTC on 2026-11-25. | Same copy, nine hashes rechecked. The owner approved this trial using the copy that predates the stock boot. |
| [v70](#attended-v70-slot-b-trial) | After v69. Stock D1 A preflight matched the prior return. The v70 boot was requested at 18:34:28 UTC on 2026-11-25. | Same copy, nine hashes rechecked. The owner approved this trial using the copy that predates the stock boot. |
| [v71](#attended-v71-slot-b-trial) | After v70. Stock D1 A preflight matched the prior return. The v71 boot was requested at 20:45:44 UTC on 2026-11-25, after the [19:06 UTC maintainer decision requiring a fresh backup](https://github.com/derekross/omamobile/pull/1002#issuecomment-7171826035). | Ran without a fresh copy. Nine hashes passed on the copy that predated the stock boot. The owner approved reuse, but the maintainer had not approved an exception. |
| [v72](#attended-v72-slot-b-trial) | The Mac left verified stock D1 A at 21:02:34 UTC on 2026-11-25. A guarded B rescue returned to Fastboot with A selected before the v72 boot request at 21:24:55 UTC. | Fresh read-only rescue copy verified at 21:13:45 UTC. All nine hashes were rechecked before staging. The stock A return after v72 requires a new copy before the next power or CPM trial. |
| [v73](#attended-v73-slot-b-trial) | The Mac left verified stock D1 A at 21:35:59 UTC on 2026-11-25. A guarded B rescue returned to Fastboot with A selected before the v73 boot request at 21:42:45 UTC. | Fresh read-only rescue copy verified at 21:41:18 UTC. All nine hashes passed. The stock A return after v73 requires a new copy before the next power or CPM trial. |
| [Read-only test root](#attended-read-only-test-root-slot-b-trial) | The Mac left verified stock D1 A at 06:13:51 UTC on 2026-11-26 and ran the guarded B rescue. Fastboot stayed active between the rescue and the test-root boot request at 06:20:35 UTC. | Fresh read-only rescue copy verified at 06:19:08 UTC. All nine hashes passed. The stock A return requires a new copy before the next power or CPM trial. |
| [Omarchy systemd RAM root](#first-attended-omarchy-systemd-ram-root-trial) | The Mac left verified stock D1 A at 06:43:33 UTC on 2026-11-26 and ran the guarded B rescue. Android stayed off between the rescue and the Omarchy boot request at 06:51:20 UTC. | Fresh read-only rescue copy verified at 06:49:41 UTC. All nine hashes passed. The stock A return requires a new copy before the next power or CPM trial. |
| [Corrected Omarchy systemd RAM root](#attended-corrected-omarchy-systemd-ram-root-trial) | The Mac left verified stock D1 A at 07:07:30 UTC on 2026-11-26. A guarded rescue retry completed with no intervening Android boot before Omarchy started at 07:20:51 UTC. | All nine hashes passed at 07:19:08 UTC. The stock A return requires a new copy before the next power or CPM trial. |
| [Omarchy USB SSH after systemd handoff](#attended-usb-ssh-handoff-trial) | The Mac left verified stock D1 A at 07:40:15 UTC on 2026-11-26. Android stayed off between the guarded rescue and the Omarchy boot request at 07:46:39 UTC. | All nine hashes passed at 07:45:27 UTC. The stock A return requires a new copy before the next power or CPM trial. |
| [Display CPM queries](#attended-display-cpm-query-trial) | The Mac left stock D1 A at 09:06:49 UTC on 2026-11-26. Android stayed off between the guarded backup rescue and the display CPM boot request at 09:14:51 UTC. | All nine hashes passed at 09:13:31 UTC. Another power or CPM trial needs a fresh copy after the stock A return. |
| [Display MBFS operating-point query](#attended-display-mbfs-operating-point-trial) | The Mac left stock D1 A at 09:38:09 UTC on 2026-11-26. Android stayed off between the guarded rescue and the operating-point boot request at 09:44:34 UTC. | All nine hashes passed at 09:43:06 UTC. Another power or CPM trial needs a fresh copy after the stock A return. |
| [Corrected display MBFS operating-point query](#attended-corrected-display-mbfs-trial) | The Mac left stock D1 A at 10:00:35 UTC on 2026-11-26. Android stayed off between the guarded rescue and the corrected boot request at 10:08:05 UTC. | All nine hashes passed at 10:05:32 UTC. Another power or CPM trial needs a fresh copy after the stock A return. |
| [Display DVFS row query](#attended-display-dvfs-row-trial) | The Mac left stock D1 A at 10:27:54 UTC on 2026-11-26. Android stayed off between the guarded rescue and the DVFS boot request at 10:34:59 UTC. | All nine hashes passed at 10:33:35 UTC. Another power or CPM trial needs a fresh copy after the stock A return. |
| [DPU wrapper trigger trial](#attended-dpu-wrapper-trigger-trial) | The Mac left stock D1 A at 12:24:53 UTC on 2026-11-26. Android stayed off between the guarded rescue and the wrapper boot request at 12:31:12 UTC. | All nine hashes passed at 12:29:51 UTC. Another power or CPM trial needs a fresh copy after the stock A return. |
| [Corrected DPU wrapper trial](#attended-corrected-dpu-wrapper-trial) | The Mac left stock D1 A at 12:50:54 UTC on 2026-11-26. Android stayed off between the guarded rescue and the corrected wrapper boot request at 12:57:01 UTC. | All nine hashes passed at 12:55:52 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [DPU BE power-vote trial](#attended-dpu-be-power-vote-trial) | The Mac left stock D1 A at 13:14:40 UTC on 2026-11-26. Android stayed off between the guarded rescue and the BE boot request at 13:21:30 UTC. | All nine hashes passed at 13:20:20 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [Powered DPU BE clock trial](#attended-powered-dpu-be-clock-trial) | The Mac left stock D1 A at 13:43:43 UTC on 2026-11-26. Android stayed off through the rescue retry and until the diagnostic boot request at 14:04:12 UTC. | All nine hashes passed at 13:58:01 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [DPU FE0 power-vote trial](#attended-dpu-fe0-power-vote-trial) | The Mac left stock D1 A at 14:21:19 UTC on 2026-11-26. Android stayed off between the rescue and the FE0 boot request at 14:28:09 UTC. | All nine hashes passed at 14:27:01 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [Powered DPU FE0 clock trial](#attended-powered-dpu-fe0-clock-trial) | The Mac left stock D1 A at 14:43:36 UTC on 2026-11-26. Android stayed off between the rescue and the diagnostic boot at 14:49:59 UTC. | All nine hashes passed at 14:48:33 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [DSI0 power-vote trial](#attended-dsi0-power-vote-trial) | The Mac left stock D1 A at 15:09:28 UTC on 2026-11-26. Android stayed off between the rescue and the diagnostic boot at 15:15:49 UTC. | All nine hashes passed at 15:14:25 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [Powered DSI0 pixel clock trial](#attended-powered-dsi0-pixel-clock-trial) | The Mac left stock D1 A at 15:42:07 UTC on 2026-11-26. Android stayed off between the rescue and the diagnostic boot at 15:48:20 UTC. | All nine hashes passed at 15:47:04 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [Passive stock D1 DSI0 trace](#attended-passive-stock-d1-dsi0-trace) | The Mac left stock D1 A at 16:29:20 UTC on 2026-11-26. Android stayed off between the rescue and the trace boot request at 16:37:33 UTC. | All nine hashes passed at 16:35:44 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [Stock D1 DSI0 genpd and MBFS trace](#attended-stock-d1-dsi0-genpd-and-mbfs-trace) | The Mac left stock D1 A at 16:46:20 UTC on 2026-11-26. Android stayed off between the rescue and the trace boot at 16:53:23 UTC. | All nine hashes passed at 16:52:00 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [Stock D1 DSI0 clock and reset trace](#attended-stock-d1-dsi0-clock-and-reset-trace) | The Mac left stock D1 A at 17:08:28 UTC on 2026-11-26. Android stayed off between the rescue and the trace boot at 17:15:58 UTC. | All nine hashes passed at 17:14:41 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [Stock D1 DSI0 PHY init trace](#attended-stock-d1-dsi0-phy-init-trace) | The Mac left stock D1 A at 20:30:01 UTC on 2026-11-26. Android stayed off between the rescue and the trace boot at 20:38:41 UTC. | All nine hashes passed at 20:37:24 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [Stock D1 DSI0 genpd worker trace](#attended-stock-d1-dsi0-genpd-worker-trace) | The Mac left stock D1 A at 06:07:15 UTC on 2026-11-27. Android stayed off between the rescue and the single trace boot at 06:13:36 UTC. | All nine hashes passed at 06:12:23 UTC. The stock A return requires a fresh copy before the next power or CPM trial. |
| [Stock D1 PHY reset trace](#attended-stock-d1-phy-reset-trace) | After the stock D1 DSI0 genpd worker trace on 2026-11-27. | The guarded rescue verified all nine partitions. |
| [Stock D1 UIC trace](#attended-stock-d1-uic-trace-result) | After the stock D1 PHY reset trace on 2026-11-27. | The guarded rescue retry verified all nine partitions. |
| [Combined UIC and PHY reset trace](#attended-combined-uic-and-phy-reset-result) | After the stock D1 UIC trace on 2026-11-27. | The guarded rescue verified all nine partitions. |
| [PHY runtime PM trace](#attended-phy-runtime-pm-result) | After the combined UIC and PHY reset trace on 2026-11-27. | The guarded rescue verified all nine partitions. |
| [Stock CGYDA connector discovery](#attended-stock-cgyda-connector-discovery) | After the PHY runtime PM trace on 2026-11-27. | The guarded rescue retry verified all nine partitions. |
| [CGYDA GPIO and VDDD trace](#attended-cgyda-gpio-and-vddd-trace) | After the CGYDA connector discovery on 2026-11-27. | The guarded rescue verified all nine partitions. |
| [Stock D1 DRM aggregate snapshot](#attended-stock-d1-drm-aggregate-snapshot) | After the CGYDA GPIO and VDDD trace on 2026-11-27. | The guarded rescue verified all nine partitions. |
| [DSI0 discovery with DP encoder excluded](#attended-dsi0-discovery-with-dp-encoder-excluded) | After the stock D1 DRM aggregate snapshot on 2026-11-27. | The guarded rescue verified all nine partitions. |
| [Stock D1 genpd device and sibling trace](#attended-stock-d1-genpd-device-and-sibling-trace) | After the DSI0 discovery with DP encoder excluded on 2026-11-27. | The guarded rescue verified all nine partitions. |
| [Stock D1 wrapper vote and display runtime PM trace](#attended-stock-d1-wrapper-vote-and-display-runtime-pm-trace) | After the stock D1 genpd device and sibling trace on 2026-11-27. | The guarded rescue retry verified all nine partitions. |
| [Mainline DSI0 PHY vote fixture](#slot-b-mainline-dsi0-phy-vote-fixture) | After the stock D1 wrapper vote and display runtime PM trace on 2026-11-27. | The guarded rescue verified all nine partitions. |
| [DSI0 sibling MBFS vote trial](#attended-dsi0-sibling-mbfs-vote-trial) | After the mainline DSI0 PHY vote fixture on 2026-11-27. | The guarded rescue verified all nine partitions. |
| [DSI0 selector 3 gate trial](#attended-dsi0-selector-3-gate-result) | After the DSI0 sibling MBFS vote trial on 2026-11-27. | The guarded rescue verified all nine partitions. |
| [Stock D1 DC customer-ID trace](#attended-stock-d1-dc-customer-id-result) | After the DSI0 selector 3 gate trial on 2026-11-27. | The guarded rescue retry verified all nine partitions. |
| [Stock D1 DP-off firmware vote trace](#attended-stock-d1-dp-off-firmware-vote-trace) | After the stock D1 DC customer-ID trace on 2026-11-27. | The guarded rescue verified all nine partitions. |

For the 15 entries after the genpd worker trace, each verified copy
preceded the linked B trial and Android stayed off between rescue
and trial. The table uses the recorded predecessor and date when
exact UTC times are unavailable in the linked trial record.

[Maintainer decision on backup freshness](https://github.com/derekross/omamobile/pull/1002#issuecomment-7171826035).
Take a fresh read-only backup of all nine partitions after the latest
stock Android boot, including a fallback to A, and before each further
power or CPM trial. Use the guarded stock D1 RAM reader and a new
private directory. Verify every local copy against the separate
phone-side digest and record which stock boot preceded the backup.
The earlier one-trial approvals above are historical. Any future
exception to a rule set by the maintainer requires the maintainer's
approval in the PR thread before the trial. [Maintainer review](https://github.com/derekross/omamobile/pull/1002#pullrequestreview-6082210711).

If a power or CPM trial will follow the backup, catch the reader's warm
return in Fastboot and keep it there until the separately approved trial
is staged. Another stock Android boot, even when used to retrieve logs,
invalidates the backup for the next power or CPM trial.

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

### Stock PSM1 module load record

The attended record identifies two hardware boots that loaded the
out-of-tree `grizzly_stock_psm1.ko`. Both were stock D1 kernel
fixtures on **slot B** on 2026-11-24, with an instrumented RAM
rescue and a verified factory `ufs.ko` loaded after the sampler.

| Slot B fixture | Sampler mode | Additional live HC/PSM1 reads |
| --- | --- | --- |
| [D1 pre-core PSM1 trace](#d1-psm1-trace-hardware-result) | Single core PRE_ON sample | At 1.552260842 s, HC raw `0x12`, PSM1 `0x2`, about 15 µs before core `0x220` ON. |
| [D1 prep PSM1 and genpd trace](#d1-prep-psm1-and-genpd-hardware-result) | `prep_trace=1` plus core PRE_ON | At 1.619009814 s before prep ON, raw `0x13`, PSM1 `0x3`. At 1.619490866 s after prep ON, raw `0x12`, PSM1 `0x2`. At 1.619496752 s before core ON, raw `0x12`, PSM1 `0x2`. |

The PHY and TOP values in those results came from the factory
driver's traced accesses. The table lists only the extra register
reads added by the sampler. The prior power and provider traces
used stock tracepoints, and the CPM firmware trace stopped before
UFS loaded. Loader checks and synthetic QEMU samples were offline.
The documented stock A return steps used factory Android for
boot and log retrieval, with no sampler load recorded on A.

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

After a fresh NV rescue, reselecting A can clear its Fastboot
success flag and reset its retry count to 3. To stage the next
trial without starting Android, append `--before-rescue CAPTURE`
to both the stager and the readback checker. Use the private
`getvar all` capture from healthy stock A immediately before
that rescue. The checker requires the same device, bootloader
and slot capacities, plus the expected bootable A return state.
Verify the fresh backup separately and keep the phone in Fastboot
between the rescue and the trial.

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
permitting storage reads. The shared initramfs change is tracked
separately. It applies `BLKROSET` to all SCSI parents when the
effective write allowlist is empty, and retains whole-disk node
removal for the protected parents. A failed read-only change
keeps the writable sysfs state visible to the handover check.
The standalone change passed synthetic Bash and Dash tests.
[Shared storage-guard draft PR](https://github.com/derekross/omamobile/pull/1074)

The packed v39 ramdisk was used for its zero-disk trial. The
storage-visible backup trial used the stock-kernel RAM rescue
and its own guard. A future mainline storage-visible fixture
still needs an early inventory gate such as the stock reader's
parent and partition checks.

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

### Mainline v56 one logical block read before discovery

The stock D1 RAM rescue log maps SCSI LUN 0 to `sda`, reports
12,801,024 logical blocks of 4,096 bytes, and shows partitions on
that LUN. Its geometry matches the v55 mainline response. The
Linux disk name is specific to that stock boot.

[v56 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/08e24bf3d288995eefaeb9a8b833954a0b029469)
keeps the v55 prep OFF, initialization, INQUIRY and capacity retry
sequence. After valid capacity and a 4,096-byte block size, it
issues one READ(10) for LBA 0 on LUN 0, using one device-to-host
PRD and its own completion IRQ. It checks response status and
residual, then records whether DMA changed the initial buffer
pattern and whether the legacy MBR signature is present. An
unchanged buffer is inconclusive and stops the diagnostic. The
signature is a reported observation. It does not validate a
partition table. The driver scrubs the buffer after inspection
and does not log, export or save its contents.

There is no SCSI host registration, disk scan, partition discovery
or SCSI write command. A successful block read is followed by
Hibern8 and HCI cleanup. The same RAM rescue requests the timed
warm return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v56 source and manifest. The DTB and private RAM rescue match v55. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control, device initialization and one read | Use the verified nine-partition NV backup. Capture capacity, exactly one READ(10) IRQ, GOOD status with zero residual, `dma_changed=1`, and the reported MBR signature result. Verify Hibern8, HCI cleanup, zero disks and the timed return. | Preserve the first terminal result without repeating the block read. Return to stock A and confirm Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v56` passed strict
checkpatch, targeted `W=1` compilation and mocked tests for the
one-block CDB, build and geometry gates, response errors, buffer
scrubbing and prior capacity retry. All five image hashes, both
AVB signatures, the unpacked payload, ABL handoff and saved D1
slot sizes passed. Manifest SHA-256 `cd4d02fab1396dc22087470ca17743bd9652da35f3ccc5507753b55f48c61a10`.
Archive SHA-256 `4ed896bd54e6548359418470815403a9986db9e3e9cf1987714c44149e6c25bc`.

#### Attended v56 slot B trial

On 2026-11-25 one v56 boot used the verified nine-partition NV backup.
All five slot B writes passed, and readback matched all 8,192
supplied `vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.156509–0.156814 | Prep OFF | HC reached `0x13`, PHY stayed at `0x11`, and qualification passed in 4 µs with `saw_hc_0x32=0`. |
| 2.210073–2.215641 | Link, initialization and INQUIRY | Link and NOP passed, `bRefClkFreq=0x2`, the first `fDeviceInit` read returned clear, and INQUIRY returned GOOD through its IRQ. |
| 2.215761–2.215952 | READ CAPACITY(10) | Current `06/29/00` triggered one retry, which returned GOOD with zero residual, last LBA 12,801,023 and logical block size 4,096 bytes. |
| 2.216256–2.216283 | One READ(10) on LUN 0, LBA 0 | Completion IRQ observed, OCS `0x0`, UPIU `0x21`, GOOD status and zero residual. `bytes=4096 dma_changed=1 mbr_signature=1`, `result=0`. |
| 2.216429–2.216693 | Cleanup | Hibern8 passed. HC and PHY reached `0x11`. Deep H8 stayed prepared through HCI IRQ release. |
| 90.201086–91.203706 | Timed warm return | Zero SCSI disks before restart and at RAM startup. |

This verifies one 4 KiB logical-block read via the diagnostic IRQ
path. The MBR signature was observed. GPT validation and normal
SCSI host registration remain untested. The early
`device_links_no_driver()` warning recurred.

Ramoops and Android's `SYSTEM_LAST_KMSG` agree. Fastboot returned
after 133 seconds. Stock D1 booted on A with enforcing verity and
the expected factory VBMeta digest.

### Mainline v57 primary GPT header before discovery

[v57 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/106ccf9ebe88bba02ddd9e32226605ab80aca732)
keeps v56's prep OFF, initialization, INQUIRY, capacity and LBA 0
checks. After LBA 0 passes, it issues one READ(10) at LUN 0, LBA 1
on the same IRQ-backed slot. It requires 4,096-byte blocks and
capacity extending through LBA 1. The READ(10) helper accepts only
LBA 0 or, in this diagnostic, LBA 1.

After a GOOD completion with zero residual, the diagnostic checks
the primary GPT signature, revision, reserved field, header size
and current LBA. It computes the header CRC with the CRC field
zeroed, compares it with the stored value and scrubs the buffer.
The log records the result without header bytes or identifiers.
This checks the primary header only. The entry array and backup
header remain untested. Disk scanning and SCSI host registration
stay off, and no SCSI write is issued.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v57 source and manifest. The DTB and private RAM rescue match v56. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control, device initialization and two reads | Use the verified nine-partition NV backup. Capture one IRQ for each READ(10), GOOD status with zero residual, the LBA 0 result and `LUN 0 LBA 1 GPT header result=0`. Verify Hibern8, HCI cleanup, zero disks and the timed return. | Preserve the first error without repeating the read. Return to stock A and confirm Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v57` passed strict
checkpatch, targeted `W=1` compilation and mocked checks for good
and malformed headers, CRC mismatch, transfer errors, LBA bounds,
build-option gating and buffer scrubbing. All five image hashes,
both AVB signatures, the unpacked payload, ABL handoff and saved
D1 slot sizes passed. Manifest SHA-256 `9962a2aa65f28398446aa6ebfaedaa055dc6e5ee289175cbfe7853613c310721`.
Archive SHA-256 `2f0026bbe1524b3b6650710b49175be14c2a1daecc5f10daf8376e4726adeab8`.

#### Attended v57 slot B trial

On 2026-11-25 one v57 boot used the verified nine-partition NV backup.
All five slot B writes passed, and readback matched all 8,192
supplied `vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.131488 | Prep OFF | Qualification passed in 4 µs. |
| 2.183304–2.183922 | Initialization, INQUIRY and capacity | The first `fDeviceInit` read returned clear. INQUIRY passed, and capacity confirmed last LBA 12,801,023 with 4,096-byte blocks. |
| 2.184382–2.184410 | READ(10) at LUN 0, LBA 0 | Completion IRQ observed, GOOD status and zero residual. DMA changed the buffer and the MBR signature was present. |
| 2.184617–2.184637 | READ(10) at LUN 0, LBA 1 | Separate completion IRQ, GOOD status and zero residual. The primary GPT header format and CRC passed, with `GPT header result=0`. |
| 2.184783–2.184973 | Cleanup | Hibern8 passed, HCI stopped and its IRQ was freed. |
| 90.176255–91.179181 | Timed warm return | Zero SCSI disks at RAM startup and before restart. |

This verifies the primary GPT header on LUN 0. The partition entry
array, backup GPT and normal SCSI discovery remain untested.
Ramoops and Android's `SYSTEM_LAST_KMSG` agree. Fastboot returned
after 132 seconds. Stock D1 booted on A with enforcing verity and
the expected factory VBMeta digest.

### Mainline v58 primary GPT entry-array CRC before discovery

[v58 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/cb8d562809d34d6ae53d2061e1067e52ff60b2d9)
keeps v57's checks through the primary GPT header. After header
CRC validation, it accepts an entry array starting at LBA 2
with one to 128 entries of 128 bytes each. The array must fit
before the header's first usable block, and that boundary must
fit within the LUN capacity reported by READ CAPACITY(10).

The fixture reads the array in one IRQ-backed READ(10) using one
device-to-host PRD covering at most four 4 KiB blocks. It requires
GOOD status and zero residual, then hashes the entry bytes with
the GPT CRC algorithm, excluding any sector padding. It scrubs
both buffers and logs the number of blocks and validation result.
It does not parse entries, publish identifiers, validate the
backup GPT, register a SCSI host or scan disks.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v58 source and manifest. The DTB and private RAM rescue match v57. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control, device initialization and bounded reads | Use the verified nine-partition NV backup. Capture the LBA 0 and header results, one array transfer IRQ, GOOD status, zero residual and `LBA 2 GPT entries result=0`. Verify Hibern8, HCI cleanup, zero disks and timed return. | Preserve the first failure without retrying the reads. Return to stock A and confirm Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v58` passed strict
checkpatch, targeted `W=1` compilation and mocked checks for
one- and four-block transfers, CRC mismatch, entry layout bounds,
build-option gating and scrubbing. All five image hashes, both
AVB signatures, the unpacked payload, ABL handoff and saved D1
slot sizes passed. Manifest SHA-256 `8a287c4f3f3dcf1730cc69b03d84b696779bda62123856029b3a6aadb67fcd21`.
Archive SHA-256 `96f6b0f0e6ddf403611b22fabe29dfd3056edbc28cd8819ebb32b56b521557fa`.

#### Attended v58 slot B trial

On 2026-11-25 one v58 boot used the verified nine-partition NV backup.
All five slot B writes passed, and readback matched all 8,192
supplied `vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.140699–0.140734 | Prep OFF | The first post-vote HC sample was `0x10`. The poll recorded `saw_hc_0x32=1` and qualified HC `0x13` with PHY `0x11` in 87 µs. This exercises the v52 transition guard on hardware. |
| 2.183445–2.184057 | Initialization, INQUIRY and capacity | The first `fDeviceInit` poll returned clear. INQUIRY passed, and capacity confirmed last LBA 12,801,023 and 4,096-byte blocks. |
| 2.184526–2.184782 | LBA 0 and primary GPT header | Both READ(10) commands received their own IRQ, GOOD status and zero residual. The MBR signature and primary header CRC passed. |
| 2.184789–2.185061 | Primary GPT entry array | One READ(10) fetched two 4 KiB blocks starting at LBA 2. The IRQ arrived, status was GOOD, residual was zero and the CRC over 5,376 bytes passed (`result=0`). |
| 2.185213–2.185438 | Cleanup | Hibern8 passed. HC and PHY reached `0x11`. Deep H8 stayed prepared through HCI IRQ release. |
| 90.184884–91.187724 | Timed warm return | Zero SCSI disks at RAM startup and before restart. |

This validates the primary entry-array CRC and a multi-block read
on LUN 0. The backup GPT, individual entry semantics and normal
SCSI discovery remain untested. Ramoops and Android's
`SYSTEM_LAST_KMSG` agree. Fastboot returned after 134 seconds.
Stock D1 booted on A with enforcing verity and the expected factory
VBMeta digest.

### Mainline v59 SCSI host registration without discovery

[v59 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/6b84a6cb12b41fc124b18e52b90637265e6f7091)
adds a synchronous SCSI host registration and removal check after
the v58 GPT reads. It uses the normal UFS host registration and
task-management queue allocation in legacy doorbell mode. The HBA
remains in its diagnostic reset state. The fixture blocks normal and
reserved command dispatch, rejects real LUNs in the device-init
callback, and skips UFS queries when that callback receives the
SCSI core's internal pseudo-device.

The diagnostic counts discovered devices, excluding the pseudo-device,
then removes the host and frees the task-management queue before
Hibern8 and HCI cleanup. There is no SCSI scan, normal device probe,
filesystem mount or SCSI write. The RAM rescue retains
`scsi_mod.scan=none` and the timed warm return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v59 source and manifest. The DTB and private RAM rescue match v58. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control, device initialization and host registration | Use the verified nine-partition NV backup. Require successful GPT results, registration with zero discovered devices, host removal and `SCSI host lifecycle ret=0`. Verify Hibern8, HCI cleanup, zero disks and the timed return. | Preserve the first error. Return to stock A and confirm Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v59` passed strict
checkpatch, targeted `W=1` compilation and eight mocked host lifecycle
cases covering registration, removal, an unexpected child, allocation
failure and entry guards. All five image hashes, both AVB signatures,
the unpacked payload, ABL handoff and saved D1 slot sizes passed.
Manifest SHA-256 `3b8d244c2d9306db391df33fc4de81a2389a9170c903b2ed44aa451bb571289d`.
Archive SHA-256 `1455cb490b0f4ad0b863fae6dcb4518b297984bd16e9e5e49573dac30da869b8`.

#### Attended v59 slot B trial

On 2026-11-25 one v59 boot used the verified nine-partition NV backup.
All five slot B writes passed, and readback matched all 8,192
supplied `vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.191781–0.191789 | Prep OFF | Qualification passed in 4 µs with `saw_hc_0x32=0`. |
| 2.248854–2.249129 | GPT validation | Primary header and entry-array CRC checks both passed before host registration. |
| 2.249412–2.249422 | SCSI host registration | `ret=0`. No discovered SCSI devices, excluding the core pseudo-device. |
| 2.281325–2.281336 | Host removal | Terminal state 4 (`SHOST_DEL`) and `SCSI host lifecycle ret=0`. |
| 2.281471–2.281707 | Controller cleanup | Hibern8 passed and the HCI IRQ was freed. |
| 90.236786–91.239602 | Timed warm return | Zero SCSI disks at RAM startup and before restart. |

The normal SCSI host and task-management queue could be created
and removed during the guarded legacy-mode probe. Normal LUN
discovery and I/O through the SCSI midlayer remain untested.
Ramoops and Android's `SYSTEM_LAST_KMSG` agree. Fastboot returned
after 133 seconds. Stock D1 booted on A with enforcing verity and
the expected factory VBMeta digest.

### Mainline v60 bounded REPORT LUNS before discovery

[v60 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/f5598755ff3ae247892cf5edbf65b98bdb88f714)
issues one IRQ-backed REPORT LUNS to well-known UPIU LUN `0x81`
after the GPT reads and before v59's SCSI host check. The command
requests ordinary LUNs, with space for a header and up to 16
entries. A successful short transfer is accepted only for this
opcode, with matching underflow and residual and a complete
header. The diagnostic validates the list length, ordinary
peripheral addressing, uniqueness and presence of LUN 0 before
reporting the LUN numbers and scrubbing the response. Other
diagnostic commands still require zero residual.

The query uses the dedicated diagnostic slot. No discovered LUN
is attached or scanned, and the subsequent SCSI host check keeps
midlayer dispatch blocked. The midlayer timeout path can invoke
UFS reset recovery, which is still unqualified. The RAM rescue
keeps `scsi_mod.scan=none` and the timed warm return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v60 source and manifest. The DTB and private RAM rescue match v59. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control, device initialization and bounded LUN inventory | Use the verified nine-partition NV backup. Capture the GPT results, one REPORT LUNS IRQ, validated list and `REPORT LUNS result=0`. Verify host creation/removal with zero devices, Hibern8, HCI cleanup, zero disks and timed return. | Preserve the first failure without retrying the report. Return to stock A and confirm Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v60` passed strict
checkpatch and targeted `W=1` compilation. Mocked cases covered the
CDB and WLUN, successful full and bounded short transfers, invalid
residuals and list data, timeouts, build-option gating and the
previous GPT path. All five image hashes, both AVB signatures, the
unpacked payload, ABL handoff and saved D1 slot sizes passed.
Manifest SHA-256 `b7c9c3c17b4b207f4a55641e88e1a0afc63a43b4fdd60b8316995dede6ef8321`.
Archive SHA-256 `50d0335c91be3bc7eed040b607b728c9f712cda1a22d121fe66cdce3b5c51454`.

#### Attended v60 slot B trial

On 2026-11-25 one v60 boot used the reverified nine-partition private
NV backup. All five slot B writes passed, and readback matched all
8,192 supplied `vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.152812–0.152819 | Prep OFF | Qualification passed in 4 µs with `saw_hc_0x32=0`. |
| 2.184365–2.184640 | Primary GPT | Header and entry-array CRC checks both passed. |
| 2.185109–2.185140 | REPORT LUNS on UPIU WLUN `0x81` | One completion IRQ, GOOD status, underflow `0x20` and residual 88. Of the 136 requested bytes, 48 were delivered. The 40-byte list contained ordinary LUNs 0 through 4 and passed validation. |
| 2.185390–2.217110 | SCSI host lifecycle | Registration and removal passed with zero discovered devices. |
| 2.217244–2.217510 | Controller cleanup | Hibern8 passed and the HCI IRQ was freed. |
| 90.197100–91.199780 | Timed warm return | Zero SCSI disks at RAM startup and before restart. |

The ordinary LUN inventory matches the five LUN numbers seen in
the stock D1 RAM rescue. This trial qualifies REPORT LUNS through
the dedicated diagnostic slot. SCSI midlayer command dispatch
and disk discovery remain untested. Ramoops and Android's
`SYSTEM_LAST_KMSG` agree. Fastboot returned after 132 seconds.
Stock D1 booted on A with enforcing verity and the pretrial VBMeta
digest.

### Mainline v61 one SCSI midlayer TEST UNIT READY

[v61 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/0bfe2a96eae7085f47b15eeccb01b981ab43e5ae)
keeps the v60 GPT, LUN inventory and host registration checks.
It opens one dispatch through the SCSI core pseudo-device and
uses the ordinary legacy SCSI queue to send a six-byte TEST UNIT
READY to LUN 0. This tests the midlayer without a data buffer.
Real LUN attachment, reserved dispatch and any additional command
remain blocked.

The test restarts the transfer list for the single command,
requests a completion IRQ, and validates OCS, the response header,
SCSI status and residual. A nonzero result is terminal. The
one-second request timeout masks and drains the transfer IRQ
before claiming a still-outstanding tag. It attempts to clear the
slot and stops the HCI if the clear fails. There is no generic
SCSI error recovery and no data buffer to unmap. The powered
platform keeps the controller descriptor allocations until
restart in the diagnostic path. The fixture removes the host,
checks Hibern8 on success, then runs the usual HCI cleanup.
The RAM rescue retains `scsi_mod.scan=none` and the timed return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v61 source and manifest. The DTB and private RAM rescue match v60. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control, device initialization and one midlayer command | Use the verified nine-partition NV backup. Require the v60 checks, one `midlayer TUR IRQ` with GOOD status, `midlayer TUR ret=0`, successful host removal, Hibern8 and zero disks. | Retain the first failure, including timeout clear/enable state if applicable. Return to stock A and verify Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v61` passed strict
checkpatch, targeted `W=1` compilation and eleven mocked lifecycle
and timeout cases. All five image hashes, both AVB signatures,
the unpacked kernel and ramdisk, ABL handoff and saved D1 slot
checks passed. Manifest SHA-256 `6dfd09bd5c675cb9e128118aca22202bb903e4987e620cc5ccfcbffeb2140004`.
Archive SHA-256 `978b5dcae14ea11b04357a62da5817113abe940d119b114accaddc55a7a0e2ce`.

#### Attended v61 slot B trial

On 2026-11-25 one v61 boot used the reverified nine-partition private
NV backup. All five slot B writes passed, and readback matched all
8,192 supplied `vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.153361–0.153369 | Prep OFF | Qualification passed in 4 µs with `saw_hc_0x32=0`. |
| 2.185239–2.185737 | GPT and REPORT LUNS | Primary entry-array CRC and REPORT LUNS passed. |
| 2.186018–2.186027 | Host creation | Registration succeeded with zero discovered devices. |
| 2.186132 | Midlayer TUR | `scsi_execute_cmd()` returned 983,040 (`0x000f0000`, `DID_TRANSPORT_FAILFAST`). No diagnostic completion IRQ or timeout was recorded. |
| 2.217623–2.217703 | Cleanup | The host reached `SHOST_DEL`. Lifecycle returned `-EIO`, Hibern8 was skipped, and HCI cleanup freed the IRQ. |
| 90.197890–91.200686 | Timed warm return | Zero SCSI disks at RAM startup and before restart. |

There is no evidence of a TUR transfer reaching the controller.
The command gate and the mapping-failure path can both return
this fail-fast status without a completion log. The next fixture
should record the gate inputs, mapping result and doorbell
submission before changing the dispatch rules. The hardware
timeout path remains untested.

Ramoops and Android's `SYSTEM_LAST_KMSG` agree. Fastboot returned
after 133 seconds. Stock D1 booted on A with enforcing verity and
the pretrial VBMeta digest.

### Mainline v62 trace midlayer TEST UNIT READY dispatch

[v62 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/590dd2fd96a4a566597daff1905dfdaca95fa016)
adds checkpoints around v61's single midlayer TEST UNIT READY.
A rejection records the pseudo-device match, buffer length,
command length, CDB match, the opcode and byte 1, the SCSI core's
`lun_in_cdb` flag and dispatch phase. An accepted command records
mapping status, scatterlist count and DMA direction. The
legacy doorbell checkpoint records the tag and immediate readback
under the outstanding-request lock. A command can finish before
the readback, so an already clear doorbell requires the IRQ and
completion records for interpretation. The synchronous result
records the final dispatch phase and raw SCSI result.

The CDB, one-command limit, legacy IRQ path and timeout cleanup
follow v61. The fixture attaches no real LUN and keeps
`scsi_mod.scan=none`. It removes the host before the usual
controller cleanup and timed return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match v62 source and manifest. The DTB and private RAM rescue match v61. | Leave stock A selected on a mismatch. |
| One attended slot B boot, power control, device initialization and one midlayer command | Use the verified nine-partition NV backup. Capture the admission decision, mapping and doorbell checkpoints if reached, the IRQ or timeout if observed, and the returned phase and result. Verify host removal, Hibern8 on success, zero disks and the timed return. | Preserve the first failure without retrying. Return to stock A and verify Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v62` passed strict
checkpatch, targeted `W=1` compilation and six mocked dispatch
cases covering admission and each rejection condition. All five
image hashes, both AVB signatures, the unpacked payload, ABL
handoff and saved D1 slot checks passed. Manifest SHA-256
`6b3543f06db90d33d7aecd04c7b5dab91b023e433f9e6038153fdb125d94fd2c`. Archive SHA-256 `eec462ed0dea02b6bcc3af910d4c1efe9f2e61ff7bc76b2026dfde0a1f19f378`.

#### Attended v62 slot B trial

On 2026-11-25 at 15:38:16 UTC, one v62 boot used the nine-partition
private NV backup with the owner's approval. All nine local hashes
passed. The copy predates the last stock A boot. All five slot B
writes passed, and the readback matched all 8,192 supplied
`vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.139382 | Prep OFF | Qualification passed in 4 µs. |
| 2.184974–2.185216 | GPT and REPORT LUNS | Primary entry-array CRC and REPORT LUNS passed. |
| 2.185474–2.185483 | Host creation | Registration succeeded with zero discovered devices. |
| 2.185534–2.185617 | Midlayer TUR | The armed request matched the pseudo-device, zero bytes and six-byte CDB length. CDB bytes 0–1 were `00 e0`, `lun_in_cdb=1` and `cdb_match=0`. The gate rejected it and the phase stayed armed. The returned SCSI result was `0x000f0000` (`DID_TRANSPORT_FAILFAST`). |
| 2.217163–2.217246 | Cleanup | Host removal reached `SHOST_DEL`. Hibern8 was skipped, and HCI cleanup freed the IRQ. |
| 90.183291–91.185827 | Timed warm return | Zero SCSI disks at RAM startup and before restart. |

The SCSI core sets `lun_in_cdb` in `scsi_sysfs_device_initialize()`
using the target's default SCSI-2 level. `scsi_dispatch_cmd()` then
copies the low three bits of the pseudo-device's `U64_MAX` LUN
into byte 1 bits 7:5, producing `0xe0`. UFS uses the UPIU LUN field
and this diagnostic targets LUN 0 explicitly. The next fixture
can disable legacy CDB LUN encoding for only the diagnostic
pseudo-device and keep the exact six-byte guard. Mapping and the
doorbell write were never reached in this trial.

Ramoops and Android's `SYSTEM_LAST_KMSG` agree. Fastboot returned
after 133 seconds. Stock D1 A was restarted at 15:41:02 UTC and
booted with enforcing verity and the pretrial VBMeta digest.

### Mainline v63 preserve the diagnostic TUR CDB

[v63 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/6138d5b281be0b4801b91f4de5139e8d519e7dad)
clears legacy CDB LUN encoding on the diagnostic pseudo-device
before arming TEST UNIT READY. The one-command gate still
requires the six-byte all-zero CDB and a zero-length payload.
The UPIU explicitly targets LUN 0. The fixture still keeps
automatic scanning disabled, attaches no real SCSI device and
removes the host after the test.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the kernel commit, all five image hashes and the saved slot capacity checks. The vendor DTB and RAM rescue match v62. | Leave stock A selected on a mismatch. |
| One attended slot B boot | Capture `ufs-uic-v63 TUR pseudo-device lun_in_cdb=0`, gate acceptance, mapping `ret=0`, the doorbell event, the v61 completion IRQ and TUR `ret=0`. Verify host removal, Hibern8 on success, zero disks and the timed return to stock A. | Keep the first rejection, error or timeout and its cleanup logs. Return to stock A without retrying and verify Android completes boot. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v63` passed
strict checkpatch, targeted arm64 `W=1` compilation and eleven
mocked cases covering CDB preservation, preflight rejection and
timeout cleanup. Both AVB signatures, the unpacked kernel and
ramdisk, ABL handoff and saved D1 slot capacity checks passed.
Manifest SHA-256 `52e1c1489b1dd344c5aa9b8f3bbd63b00d3ee0967bea5b40feb7fe9fa51136a3`.
Archive SHA-256 `2326f96b449b8dcd4184f4f493dae75b03b2a40021d18ddcc17555875eac8945`.

#### Attended v63 slot B trial

On 2026-11-25 at 15:49:24 UTC, one v63 boot used the nine-partition
private NV backup with the owner's approval. All nine local hashes
passed. The copy predates the last stock A boot. All five slot B
writes passed, and the readback matched all 8,192 supplied
`vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.184471–2.185261 | GPT and REPORT LUNS | Header and entry checks passed. REPORT LUNS completed by IRQ and returned LUNs 0–4. |
| 2.185522–2.185531 | SCSI host registration | `ret=0` with zero discovered devices. |
| 2.185546–2.185635 | Midlayer TEST UNIT READY dispatch | `lun_in_cdb=0`, gate accepted tag 5, mapping `ret=0` with no scatterlist entries, doorbell readback `0x20`. |
| 2.185808–2.185857 | Completion | The matching IRQ returned OCS, SCSI response, status and raw result all zero. The sent phase was 2 and the synchronous call returned 0. |
| 2.217260–2.217581 | Cleanup | Host removed with lifecycle `ret=0`; link and Hibern8 returned 0, both PSMs reached `0x11`, Deep H8 gate returned 0 and the HCI IRQ was freed. |
| 90.197538–91.200396 | Timed warm return | Zero SCSI disks both at RAM startup and before restart. |

This confirms one command from the SCSI midlayer through the UFS
transfer doorbell to matching IRQ and SCSI completion on Grizzly.
The command had no data payload. The earlier deferred-probe
`device_links_no_driver` warning was still present.

Ramoops and Android's `SYSTEM_LAST_KMSG` agree. Fastboot returned
after 133 seconds. Stock D1 A was restarted at 15:51:55 UTC and
booted with enforcing verity and the pretrial VBMeta digest.

### Mainline v64 test one 36-byte midlayer INQUIRY

[v64 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/4b5971a8c4744e72eb2e54b8e693475f7a15d817)
sends standard INQUIRY with CDB `12 00 00 00 24 00` from the
diagnostic SCSI pseudo-device to UPIU LUN 0. The gate requires the
exact CDB, a 36-byte `DMA_FROM_DEVICE` request and one scatterlist
entry. It consumes the dispatch token once and uses the normal UFS
scatter-gather mapping, PRDT and legacy doorbell path. The IRQ checks
the response type, LUN, tag and clean status with zero residual.
The caller validates the returned header after DMA unmapping.
The earlier direct INQUIRY reported qualifier 0, disk type 0,
version 6, response format 2 and additional length 31.

The host remains in the read-only diagnostic flow with automatic
scanning disabled. Normal completion removes the temporary host and
runs Hibern8 and HCI teardown. The 90-second return remains armed.

A timed-out request can release its DMA mapping after IRQ drain and
controller acknowledgement of the transfer clear or HCE disable.
If the doorbell remains set with HCE enabled after both attempts, the
request and mapping stay live and the driver requests an emergency
restart. Ordinary device shutdown can wait on the blocked probe.
The arm64 restart path reaches PSCI without that wait. DMA quiescence
across an emergency warm restart on Malibu has no hardware evidence.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the source, five image hashes, both AVB signatures and saved capacity checks. The packed DTB and RAM rescue match v63. | Leave stock A selected if a check fails. |
| One attended slot B trial | Capture gate acceptance, mapping with `sg=1` and `bytes=36`, the matching IRQ with zero residual, the INQUIRY header and `ret=0`. Verify host removal, Hibern8, zero disks and stock A return. | Hold Volume Down after the first orange warning in case the restart comes early. Preserve the first error, timeout or emergency restart marker and return to stock A without retrying. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v64` passed
targeted arm64 `W=1` compilation and 35 sanitizer-backed mocks
covering dispatch, response validation, timeout and synchronous
completion. Both AVB signatures, ABL handoff, all five image hashes
and saved D1 slot checks passed. Manifest SHA-256
`8fd6f7a9d3238943bc888f3bc5254a3f748747ac73a0be9995fe8877fe4299a9`. Archive SHA-256
`88f67146468e78b1c944afd633eb59b28ab79b7a0163039370c3c29058e1c03a`.

#### Attended v64 slot B trial

On 2026-11-25 at 16:09:22 UTC, one v64 boot used the nine-partition
private NV backup with the owner's approval. All nine local hashes
passed. The copy predates the last stock A boot. All five slot B
writes passed, and the readback matched all 8,192 supplied
`vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.180842–2.181357 | GPT and REPORT LUNS | Header and entries passed. REPORT LUNS completed by IRQ and found LUNs 0–4. |
| 2.181622–2.181633 | SCSI host registration | `ret=0` with zero discovered devices. |
| 2.181649–2.181759 | Midlayer INQUIRY dispatch | `lun_in_cdb=0`. The gate accepted tag 1. Mapping returned 0 with one DMA-from-device segment of 36 bytes. Doorbell readback was `0x2`. |
| 2.181935–2.182006 | IRQ and payload | Matching tag 1 IRQ, OCS 0, status 0 and residual 0. Sent phase 2 returned raw 0 and residual 0. The header matched direct INQUIRY with qualifier 0, disk type 0, version 6, format 2 and additional length 31. The call returned 0. |
| 2.213568–2.213893 | Cleanup | Host removal completed, link and Hibern8 returned 0, Deep H8 qualified with both PSMs at `0x11`, and the HCI IRQ was freed. |
| 90.176527–91.179352 | Timed warm return | Zero SCSI disks at RAM startup and before restart. |

This verifies a 36-byte data-in transfer through the SCSI midlayer
and normal UFS scatter-gather mapping on Grizzly. The deferred-probe
`device_links_no_driver` warning remained. The success path ran
without invoking timeout or emergency restart.

Fastboot returned after 133 seconds. Stock D1 A restarted at
16:11:52 UTC and completed boot with enforcing verity and the
pretrial VBMeta digest. Ramoops and Android's `SYSTEM_LAST_KMSG`
agree on all 38 filtered v64 lines after BootReceiver finished.

### Mainline v65 compare one midlayer GPT block read

[v65 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/f3b61d764826cb0598fe2e199a65dbe7e4bb6cf2)
requires 4 KiB logical blocks from live READ CAPACITY and saves the
validated primary GPT block from the direct read during this boot.
The header validator restores the original CRC field after checking
it. The direct entry-array CRC and REPORT LUNS gates still apply.

The SCSI pseudo-device admits one `READ(10)` with CDB
`28 00 00 00 00 01 00 00 01 00`. The request targets LUN 0, LBA 1
and one block. It requires `DMA_FROM_DEVICE`, one scatterlist entry
and exactly 4,096 mapped bytes. The matching IRQ must report a good
response and zero residual. After unmapping, the driver validates the
returned GPT header and compares all 4,096 bytes with the reference.
It logs only the result and clears both copies before freeing them.

The host attaches no real devices. Automatic scanning stays
disabled. Host removal, Hibern8 on success, the 90-second return
and v64's stuck-DMA timeout handling remain in place. The emergency
restart path remains untested on hardware.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the source, five image hashes, both AVB signatures and saved capacity checks. DTB and RAM rescue match v64. | Leave stock A selected if any check fails. |
| One attended slot B trial | Check live 4 KiB geometry, direct GPT and REPORT LUNS, then the midlayer gate, `sg=1 bytes=4096`, matching IRQ with zero residual and `comparison bytes=4096 ret=0`. Verify host removal, Hibern8, zero disks and stock A return. | Hold Volume Down after the first orange warning. Capture the first failure and return to stock A without retrying. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v65` passed the
targeted arm64 `W=1` build and 39 sanitizer-backed cases. The cases
cover CRC restoration, mismatch outside the GPT header, gate
rejections, response validation and timeout handling. Both AVB
signatures, ABL handoff, all five image hashes and saved D1 slot
capacity checks passed. Manifest SHA-256 `9f6356a27630f5df2078b2d9fe11a22390f7b375f9698092c84fa32c9dfd4065`.
Archive SHA-256 `c95ab36c798f973250a2291670e6614bb97404ebaf99705b7aaa09808a2c99ba`.

#### Attended v65 slot B trial

On 2026-11-25 at 16:39:58 UTC, one v65 boot used the nine-partition
private NV backup with the owner's approval. All nine local hashes
passed. The copy predates the last stock A boot. All five slot B
writes passed, and the readback matched all 8,192 supplied
`vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.216231–2.217549 | Live geometry, direct GPT and REPORT LUNS | Block size 4,096, GPT header and entry-array CRC checks passed, and REPORT LUNS found LUNs 0–4. |
| 2.217807–2.217934 | Host registration and midlayer dispatch | Zero discovered devices. The gate accepted tag 17 with `lun_in_cdb=0`. Mapping returned 0 with one DMA-from-device segment of 4,096 bytes. Doorbell readback was `0x20000`. |
| 2.218131–2.218205 | IRQ and comparison | Matching tag 17 IRQ with OCS 0, response 0, status 0 and residual 0. Sent phase 2 returned raw 0 and residual 0. The entire 4,096-byte block matched the direct GPT read and the call returned 0. |
| 2.249363–2.249724 | Cleanup | Host removal completed, link and Hibern8 returned 0, both PSMs reached `0x11`, and the HCI IRQ was freed. |
| 90.225517–91.228338 | Timed warm return | Zero SCSI disks at RAM startup and before restart. |

This verifies a one-block read from LUN 0, LBA 1 using the SCSI
midlayer and normal UFS DMA mapping. The deferred-probe
`device_links_no_driver` warning remained. The trial reached
neither timeout nor emergency restart.

Fastboot returned after 133 seconds. Stock D1 A restarted at
16:42:30 UTC and completed boot with enforcing verity and the
pretrial VBMeta digest. Ramoops and Android's `SYSTEM_LAST_KMSG`
agree on all 38 filtered v65 lines.

### Mainline v66 register one real SCSI child

[v66 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/3e92b7cefbc0c490b9bdad6e3bd1f5b9b55373f9)
uses the SCSI core's explicit device-add path for channel 0,
target 0, LUN 0. The direct LUN 0 GPT and REPORT LUNS qualification
still comes first. The add path requires `scsi_mod.scan=manual`
because `scan=none` rejects the explicit add as well. Manual mode
suppresses automatic host scans. `scsi_mod.inq_timeout=1` lowers the
SCSI core's discovery request timeout to about 1.5 seconds.

The diagnostic host allows only the child with the driver's private
token and exact address. It permits one six-byte standard INQUIRY
while that child is in the created state. The gate requires 36 bytes
of DMA from the device in one scatterlist entry. The driver skips
normal UFS per-LUN setup, optional VPD and opcode checks, and omits
UFS attributes that could send queries. It blocks upper-layer driver
matching. The verified config leaves `sd`, SG, BSG and RPMB disabled.

Success requires a visible, running, unbound disk-type SCSI child
with a 36-byte INQUIRY response. The driver removes that child,
then removes the host and runs Hibern8 and HCI cleanup. This tests
SCSI device discovery before adding a Linux block disk. The inherited
emergency restart path for a stuck DMA transfer remains untested on
hardware.

Build the RAM fixture with `pack-mainline-inventory.py --single-lun-only`.
The new marker requires the manual scan and inquiry timeout arguments
and preserves the zero-disk checks at startup and before the timed
return. It retains the private RAM environment, read-only sysfs
after setting warm restart, and no userspace handoff.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match source, five image hashes, both AVB signatures, saved slot B capacities, packed manual scan arguments and both RAM markers. DTB and DTBO match v65. | Leave stock A selected if any check fails. |
| One attended slot B trial | Check the RAM policy marker, one accepted 36-byte INQUIRY, matching IRQ with zero residual, child visibility and `no_uld=1 ret=0`. Confirm host removal, Hibern8, zero disks and the timed return to stock A. | Hold Volume Down after the first orange warning. Preserve the first failure, unexpected command, binding, disk or reset. Return to stock A without retrying. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v66` passed
targeted arm64 `W=1` compilation, 22 sanitizer-backed kernel mock
cases and nine RAM policy cases. Both AVB signatures, ABL handoff,
all five image hashes, unpacked vendor payloads and saved D1 slot
capacity checks passed. Manifest SHA-256 `9f77ddfe2ccebba61a7ac3a658b0d85b8bfc74ab1f1b923ee72dc5dbd98d9e4b`.
Archive SHA-256 `7445e3f324d28c3c34e64a82af038b485121040ac60cf6372d61836bd92b2595`.

#### Attended v66 slot B trial

On 2026-11-25 at 16:54:28 UTC, one v66 boot used the nine-partition
private NV backup with the owner's approval. All nine local hashes
passed. The copy predates the last stock A boot. All five slot B
writes passed, and the readback matched all 8,192 supplied
`vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 0.199902–0.200783 | RAM policy | Single-LUN policy verified and zero SCSI disks. |
| 2.216746–2.217548 | Direct GPT and REPORT LUNS | Header and entry checks passed. REPORT LUNS found LUNs 0–4. |
| 2.217808–2.218278 | Host registration and LUN 0 INQUIRY | The host started with zero discovered devices and admitted one command. Tag 13 mapped one 36-byte DMA-from-device segment and completed by IRQ with OCS 0, status 0 and residual 0. |
| 2.218509 | SCSI child | LUN 0 was visible, running and unbound. It reported disk type 0, `inquiry_len=36`, `no_uld=1` and `ret=0`. |
| 2.249340–2.249707 | Cleanup | Host lifecycle returned 0, link and Hibern8 returned 0, both PSMs reached `0x11` and the HCI IRQ was freed. |
| 90.201125–91.203943 | Timed warm return | Zero SCSI disks before restart. |

The trial confirms SCSI discovery of a real child at channel 0,
target 0, LUN 0, without an attached disk driver. The retained
console contains no SCSI disk registration. The prior deferred-probe
`device_links_no_driver` warning remained.

Fastboot returned after 133 seconds. Stock D1 A restarted at
16:56:51 UTC and completed boot with enforcing verity and the
pretrial VBMeta digest. Ramoops and Android's `SYSTEM_LAST_KMSG`
agree on all 36 filtered v66 lines.

### Mainline v67 publish one read-only SCSI disk

[v67 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/919c85ac0470a6cafaa79c21d701bc3243bf06db)
keeps the direct geometry, GPT and REPORT LUNS checks and the one
standard INQUIRY to the real LUN 0 child. After that command and
IRQ cleanup, the fixture explicitly attaches the built-in `sd`
driver to the qualified child. SCSI I/O stays closed at the UFS
transport, including writes and further reads.

The diagnostic `sd` path consumes the live 4 KiB geometry already
qualified by READ CAPACITY. It sets the disk read-only and disables
partition scanning before publication. It skips the normal `sd`
revalidation commands. The kernel verifies a live read-only disk,
4 KiB logical blocks, matching capacity and partition suppression.
It keeps the disk visible for four seconds, then removes it and the
host before Hibern8 and controller teardown. SG, BSG and RPMB stay
disabled.

The `--single-disk-only` RAM fixture samples sysfs without opening
a block device. It requires one whole `sd` disk under
`3c2d0000.ufs` at channel 0, target 0, LUN 0, with no partitions,
holders or mounts. It requires read-only state, 4,096-byte logical
blocks and 102,408,192 512-byte sectors for this Pixel, based on the
previous live capacity. The timed return still checks for zero
SCSI disks after removal. This trial tests publication and teardown.
A filesystem mount, block data read and full NV inventory are later
milestones.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the five image hashes, both AVB signatures, packed RAM markers and saved slot B capacity checks. DTB, DTBO and `vendor_boot` match v66. | Leave stock A selected on a mismatch. |
| One attended slot B trial | Capture the one LUN 0 INQUIRY, `LUN 0 disk read-only`, independent RAM sysfs verification, host removal, Hibern8 and zero disks before restart. | Hold Volume Down after the orange warning. Preserve the first geometry mismatch, unexpected command, partition, disk, timeout or reset. Return to stock A without retrying. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v67` passed targeted
arm64 `W=1` for UFS core and `sd`, 12 sanitizer-backed kernel mock
cases, 11 synthetic sysfs cases and ShellCheck. Both AVB signatures,
ABL handoff, all five image hashes and saved D1 slot capacity checks
passed. Manifest SHA-256 `283f7b28c18293c978d2cc6f5cacda850e7b57e4df5de5b209d38696392a67c1`.
Archive SHA-256 `0f4d21e59376e163b58719041564bfa56ec3d453cafc52ddf163ec86fa2beca1`.

#### Attended v67 slot B trial

On 2026-11-25 at 17:12:03 UTC, one v67 boot used the nine-partition
private NV backup with the owner's approval. All nine local hashes
passed. The copy predates the last stock A boot. All five slot B
writes passed, and the readback matched all 8,192 supplied
`vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.183735–2.184975 | Direct gates | 4,096-byte logical blocks, valid primary GPT header and entries, and REPORT LUNS found LUNs 0–4. |
| 2.185410–2.186694 | Real LUN 0 discovery | One 36-byte INQUIRY mapped one segment, completed by tag 21 IRQ with zero residual, and exposed the qualified child. |
| 2.198272–2.198678 | RAM sysfs check | Exactly one whole LUN 0 disk with `ro=1`, 4,096-byte logical blocks and 102,408,192 sectors. No partitions, holders or mounts. The check did not open a block device. |
| 2.201293–2.201324 | Kernel disk check | `sd` attached at `0:0:0:0`. The disk was live and read-only with matching geometry and `no_part=1`. |
| 6.453117–6.453514 | Cleanup | Host removal and Hibern8 passed. Both PSMs reached `0x11`, and the HCI IRQ was freed. |
| 90.189888–91.192619 | Timed warm return | Zero SCSI disks before restart. |

The two checks confirm read-only block-device publication on
Grizzly. This trial issued no block-data read after publication.
The deferred-probe `device_links_no_driver` warning remained.

Fastboot returned after 133 seconds. Stock D1 A restarted at
17:14:25 UTC and completed boot with enforcing verity and the
pretrial VBMeta digest. Ramoops and Android's `SYSTEM_LAST_KMSG`
agree on all 38 filtered v67 lines.

### Mainline v68 read one GPT block through the read-only disk

[v68 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/c835be6fcfc606a9fea57f2e2321ecfd3710b042)
saves the validated primary GPT block from this boot's direct read.
It runs the v67 LUN 0 discovery and confirms `sd` published a
read-only disk with 4 KiB logical blocks and partition scanning
disabled. It then submits one kernel bio directly to that disk.
The bio uses a fresh page and targets sector 8 in 512-byte units,
which is LBA 1 at the qualified geometry.

The UFS gate admits only this bio, with no merging, one 4,096-byte
DMA-from-device segment and the exact LUN 0 `READ(10)` CDB
`28 00 00 00 00 01 00 00 01 00`. A separate dispatch token allows
one submission after the original discovery INQUIRY. Writes,
other reads, wrong LUNs and redispatch remain blocked.

Success requires a matching IRQ with good status and zero residual,
successful bio completion, and byte-for-byte equality across all
4,096 bytes. Invalid SCSI responses become terminal failures with
a full residual and cleared sense before reaching `sd`. The page
and direct reference are cleared before freeing. The existing
stuck-DMA emergency restart remains untested on hardware.

The RAM fixture still observes the read-only disk via sysfs without
opening it. Partition scanning, SG, BSG, RPMB and userspace
handoff remain disabled. On success the disk stays visible for the
RAM check, then disk and host removal precede Hibern8 and the
90-second return.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the source, five image hashes, both AVB signatures and saved slot capacities. DTB, DTBO, RAM rescue and vendor boot images match v67. | Leave stock A selected on a mismatch. |
| One attended slot B trial | Capture direct GPT, LUN 0 discovery, read-only publication with no partitions, one accepted opcode `0x28`, `sg=1 bytes=4096`, matching IRQ with zero residual, and `block GPT comparison bytes=4096 ret=0`. Verify RAM sysfs, disk removal, Hibern8, zero disks before restart and stock A return. | Hold Volume Down after the first orange warning. Preserve the first refusal, comparison failure, timeout or reset and return to stock A without retrying. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v68` passed strict
checkpatch, targeted arm64 `W=1` compilation and 32
sanitizer-backed mock cases for command gating, completion,
bio lifetime and comparison. Both AVB signatures, ABL handoff,
all five image hashes and saved D1 slot checks passed.
Manifest SHA-256 `83577576443f12ee285f5894c81335e22266e26c3d723d012a034a2b821fb036`.
Archive SHA-256 `abc60f1f53a6f1561ee168351e42b62adba31580bf4bd92cc7e83a0451414f5d`.

#### Attended v68 slot B trial

On 2026-11-25 at 17:57:17 UTC, one v68 boot used the nine-partition
private NV backup with the owner's approval. All nine local hashes
passed. The copy predates the last stock A boot. All five slot B
writes passed, and the readback matched all 8,192 supplied
`vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.183712–2.185110 | Direct gates | 4,096-byte logical blocks, valid primary GPT header and entries, and REPORT LUNS found LUNs 0–4. |
| 2.185500–2.186061 | Discovery | One 36-byte INQUIRY completed by tag 5 IRQ with zero residual and exposed the qualified LUN 0 child. |
| 2.193026–2.201261 | Disk publication | RAM sysfs confirmed one whole read-only LUN 0 disk with no partitions, holders or mounts. The kernel reported `no_part=1` with the same 4,096-byte blocks and 102,408,192 sectors. |
| 2.201324–2.201580 | Block-layer read | One READ(10) on tag 6 mapped a single 4,096-byte DMA-from-device segment. Its IRQ reported OCS 0, status 0 and residual 0. The full block matched the validated direct GPT read byte for byte. |
| 6.441035–6.441391 | Cleanup | Host removal and Hibern8 passed. Both PSMs reached `0x11`, and the HCI IRQ was freed. |
| 90.184707–91.187566 | Timed warm return | Zero SCSI disks before restart. |

This confirms a real, one-block read through the published `sd`
disk while partition scanning is disabled. The deferred-probe
`device_links_no_driver` warning remained.

Fastboot returned after 133 seconds. Stock D1 A restarted at
17:59:41 UTC and completed boot with enforcing verity and the
pretrial VBMeta digest. Ramoops and Android's `SYSTEM_LAST_KMSG`
agree on all 43 filtered v68 lines.

### Mainline v69 discover GPT partitions read-only on LUN 0

[v69 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/d68b15006714e4baef8d854e2c0fc3e45ea4c616)
extends the temporary read-only disk with Linux's native EFI GPT
parser. DOS and other partition parsers are disabled. The v68
standalone block read is disabled for this fixture.

Before registering `sd`, the driver validates the direct primary GPT
header and entry-array CRCs. It requires the primary header to place
the alternate header at the last LBA and to leave the canonical
alternate entry-array range outside usable blocks. The direct array
provides the expected number of used partition entries.

Only while `sd` attaches, the transport permits one read per metadata
block. The allowlist contains LBA 0, LBA 1, the primary array beginning
at LBA 2, the final LBA and the canonical alternate array immediately
before it. The previous D1 geometry implies seven requests at LBAs
0–3 and 12,801,021–12,801,023. Each must be one 4 KiB,
DMA-from-device `READ(10)` to the whole read-only LUN 0 disk.
Writes, duplicates, other LUNs, partition-device requests, and reads
outside these ranges fail closed. The driver rejects the trial if
a command is refused or fails, or if the completed scan did not need
every expected block. It suppresses later scans and checks the
published read-only partition count against the direct GPT.

The `--gpt-scan-only` RAM image waits for the kernel verification
marker. It checks one whole LUN 0 disk and the same number of
read-only children, each belonging to that disk with nonzero,
aligned, in-capacity extents, no holders and no mounts. It does
not open block nodes. Disk and host removal precede Hibern8 and
the existing 90-second warm return. This fixture reads GPT metadata
only and does not mount storage or hand off to an installed system.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Match the source, five image hashes, both AVB signatures, saved slot capacities, EFI-only config and the GPT RAM marker. DTB, DTBO and `vendor_boot` match v68. | Leave stock A selected on a mismatch. |
| One attended slot B trial | Capture the live metadata layout, one successful transfer per allowed block, kernel and RAM partition count and read-only checks, successful teardown, zero disks before restart and stock A return. | Hold Volume Down after the orange warning. Preserve the first unexpected request, layout, partition, mount, timeout or reset. Return to stock A without retrying. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v69` passed strict
checkpatch, targeted arm64 `W=1` compilation, 33 sanitizer-backed
metadata gate/layout cases, 20 synthetic sysfs cases and ShellCheck.
Both AVB signatures, ABL handoff, all five image hashes and saved
D1 slot checks passed. Manifest SHA-256 `8594d28095e868aa19dfd11ddf3a6307e1628aa2218af4002bd1500b724d4e73`.
Archive SHA-256 `5443e16745c8d1cbe9a4c93b6d243ef188704eb8aba5d53dc930b0d205694f75`.

#### Attended v69 slot B trial

On 2026-11-25 at 18:15:08 UTC, one v69 boot used the nine-partition
private NV backup with the owner's approval. All nine local hashes
passed. The copy predates the last stock A boot. All five slot B
writes passed, and the readback matched all 8,192 supplied
`vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.212351–2.213317 | Direct gates | 4,096-byte blocks, two primary entry-array blocks, 42 used entries and alternate header at LBA 12,801,023. |
| 2.221744–2.223098 | Parser transfers | Only LBAs 0–3 and 12,801,023 reached the controller. Each used one 4,096-byte mapping and completed by IRQ with zero residual. |
| 2.223139–2.223271 | Gate refusal and primary fallback | The parser requested sector 102,408,152 (LBA 12,801,019, CDB `28 00 00 c3 53 fb 00 00 01 00`). The gate refused it before mapping or ringing the doorbell. Linux used the primary GPT and announced 42 partitions, matching the direct count. |
| 2.226242–2.313590 | Failure and cleanup | The whole disk was read-only. The metadata check returned `reads=0x4f expected=7 failed=1`. The host was removed and IRQ freed. Hibern8 qualification did not run. |
| 20.449863–91.223993 | RAM and timed return | The RAM check timed out waiting for the kernel success marker. It did not complete per-partition read-only verification. There were zero SCSI disks before restart. |

The trial verified a primary GPT count match and that only the
five admitted metadata requests were issued. No storage mount was
attempted. The alternate header led Linux to LBA 12,801,019,
four blocks before that header and outside v69's inferred array
range. Linux's alternate GPT warning followed the rejected I/O.
The next fixture needs to qualify the alternate header and its
entry-array pointer and length before arming the metadata gate.

Fastboot returned after 133 seconds. Stock D1 A restarted at
18:17:35 UTC and completed boot with enforcing verity and the
pretrial VBMeta digest. Ramoops and Android's `SYSTEM_LAST_KMSG`
agree on all 59 filtered v69 lines.

### Mainline v70 qualify the backup GPT before allowing the scan

[v70 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/3130fccb4490bb633ab11ed5d9fd6a0991565bb3)
uses live capacity and the validated primary GPT to qualify one
direct read at the last LBA. It checks the backup header's CRC,
self and reciprocal header LBAs, usable range, disk GUID, and
entry count, length and declared array CRC against the primary.
The entire declared array must lie above the last usable block
and fit before the backup header. The header check itself reads
only that final block. No array read is permitted until it passes.

The scan gives the backup header its own gate slot and uses the
validated backup array start and length. Any gap between them is
outside the gate. The v69 request suggests the backup array starts
at LBA 12,801,019 and spans two 4 KiB blocks. v70 derives both from
the live headers. The EFI parser validates the actual array CRC
during the gated scan. The RAM check refuses an EFI fallback to
the primary even if all metadata transfers completed successfully.

The scan still allows only one read per metadata block and blocks
all writes and partition-data I/O. RAM verification now requires
exactly 42 partitions from the completed kernel scan, and checks
read-only state, parentage, bounds, holders and mounts across all
42. It opens no partition devices and mounts no storage.
The existing cleanup and timed warm return stay in place.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Verify both AVB signatures, all five image hashes, unchanged DTB, DTBO and `vendor_boot`, and updated GPT RAM marker logic. | Leave stock A selected on a mismatch. |
| One attended slot B trial | Capture the direct backup header result and declared array range. Check exactly one successful IRQ transfer for each gated metadata block, no EFI fallback, kernel and RAM verification of all 42 read-only partitions, zero disks before restart and stock A return. | Hold Volume Down after the first orange warning. Preserve the first header mismatch, read refusal, partition or mount failure, timeout or reset. Return to stock A without retrying. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v70` passed strict
checkpatch, targeted arm64 `W=1` compilation, 50 sanitizer-backed
layout and admission cases, 22 synthetic sysfs cases and four RAM
marker cases. The synthetic fixtures include v69's observed backup
array start, rejection of the gap before the header and rejection
of a writable forty-second partition. ShellCheck, both AVB
signatures, ABL handoff, all five image hashes and saved D1 slot
checks passed. Manifest SHA-256 `08d513363ee87fe98a91b50b1d59a0936907ab498537bfa5d829b20c499f0b09`.
Archive SHA-256 `d767a5b618a834e2c042ef650863e7113f1d0f14bc16d0c9d64ccaf3eac40b23`.

#### Attended v70 slot B trial

On 2026-11-25 at 18:34:28 UTC, one v70 boot used the nine-partition
private NV backup with the owner's approval. All nine local hashes
passed. The copy predates the last stock A boot. All five slot B
writes passed, and the readback matched all 8,192 supplied
`vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.215499–2.216892 | Direct qualification | 4,096-byte blocks, 42 primary entries and backup header at LBA 12,801,023. The backup header checks passed and authorized the declared two-block array at 12,801,019. |
| 2.225117–2.226838 | Native GPT scan | The controller received only LBAs 0–3, 12,801,023, 12,801,019 and 12,801,020. Each used one 4,096-byte DMA segment and completed by IRQ with zero residual. There was no rejection or EFI fallback. |
| 2.229494–2.413046 | Kernel and RAM verification | The read-only disk published 42 partitions, matching the direct GPT. RAM checked that all 42 were read-only, with correct parentage and bounded, aligned extents, and no mounts or holders. No storage was mounted. |
| 6.432869–6.433260 | Cleanup | Host removal and Hibern8 passed. Both PSMs reached `0x11`, and the HCI IRQ was freed. |
| 90.221749–91.224573 | Timed warm return | Zero SCSI disks before restart. |

The trial verifies primary and backup GPT discovery through the
one-use metadata gate. The gap at LBAs 12,801,021–12,801,022
was outside the gate and the parser did not request it. The
deferred-probe `device_links_no_driver` warning remained.

Fastboot returned after 133 seconds. Stock D1 A restarted at
18:37:10 UTC and completed boot with enforcing verity and the
pretrial VBMeta digest. Ramoops and Android's `SYSTEM_LAST_KMSG`
agree on all 70 filtered v70 lines.

### Mainline v71 compare the first block through boot_b

[v71 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/a0110b8b189c41964b2f66d4b337793ec81b41c0)
selects `boot_b` as a non-NV target. The saved Grizzly Fastboot
inventory reports a 64 MiB partition. The [Kodiak stock map](../kodiak/BRINGUP-NOTES.md)
places it on LUN 0 on the sibling board. Grizzly's live LUN
and GPT index still need confirmation. The fixture never assumes
a Linux partition number for either board.

The validated primary LUN 0 GPT must contain exactly one in-use
entry named `boot_b`, with a 64 MiB extent inside the usable range
and no overlap with any other in-use entry. The alternate
header still has to pass v70's checks. The direct path then
permits one 4 KiB read at the selected extent's first LBA and
requires Android boot header magic before retaining the reference.

After the same seven metadata transfers and the kernel's 42
read-only partition checks, v71 locates the published partition
by GPT index. It independently matches its name, start, size and
read-only flag to the validated GPT. A private kernel bio targets
partition-relative sector 0. The one-shot gate requires that exact
bio after remapping, the same absolute LBA and the exact one-block
`READ(10)`. Other reads and all writes remain blocked outside
the metadata window. The read starts with every byte inverted
relative to the direct copy, then compares all 4,096 bytes
after successful completion and IRQ drain. No payload is logged.

The RAM fixture still checks all 42 read-only partitions with no
mounts or holders. No block node is opened or filesystem mounted.
Disk and host removal, Hibern8 on success and the timed return
retain the v70 sequence.

| Step | Pass | Stop and return |
| --- | --- | --- |
| Offline review | Verify the source, five image hashes, both AVB signatures and saved slot fit. DTB, DTBO and both vendor images match v70. | Leave stock A selected on a mismatch. |
| One attended slot B trial | Capture the qualified direct `boot_b` read, seven GPT-only transfers with no fallback, all 42 read-only partitions, exactly one partition bio with IRQ and zero residual, and `block comparison ... bytes=4096 ret=0`. Confirm zero disks before the timed return and verify stock A. | Hold Volume Down after the first orange warning. Preserve the first missing or overlapping GPT entry, mapping or comparison failure, extra I/O, mount or reset. Return to stock A without retrying. |

Offline release `7.3.0-rc6-omamobile-grizzly-uic-v71` passed strict
checkpatch, targeted arm64 `W=1` compilation and 35 sanitizer-backed
selection, remap and comparison cases. Both AVB signatures, ABL
handoff, all five image hashes and saved D1 slot checks passed.
Manifest SHA-256 `f72c489d0410a07085b9be13c597e2dc82480e74506e77a5c1d478b4bf599b6d`.
Archive SHA-256 `95ece9ccca05c1b3eff72bcc7dbfc1fe51366602deaf9e5c4621d0064a0bfdba`.

#### Attended v71 slot B trial

On 2026-11-25 at 20:45:44 UTC, one v71 boot powered the UFS
host and its PSMs after the maintainer's fresh-backup decision.
It ran without a fresh copy. The owner approved reuse, but the
maintainer had not approved an exception. All nine local hashes
passed on the copy taken before the last stock A boot. All five
slot B writes passed, and the readback matched all 8,192 supplied
`vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.216515–2.217759 | Direct qualification | Both GPT headers passed. The primary table identifies `boot_b` as partition 23 on LUN 0, starting at LBA 598,710. Its first 4,096 bytes passed the direct UFS read and Android boot header check. |
| 2.229405–2.234101 | GPT scan | Seven metadata reads completed by IRQ with zero residual, no gate refusal and no EFI fallback. The kernel verified 42 read-only partitions. |
| 2.234153–2.234388 | Partition block read | One `READ(10)` through partition 23 used one 4,096-byte DMA-from-device segment. Tag 9 completed by IRQ with OCS 0, status 0 and zero residual. All 4,096 bytes matched the direct UFS read at LBA 598,710. |
| 3.409276–3.409691 | RAM verification | All 42 partitions were read-only and unmounted, with correct parentage, aligned, bounded extents and no holders. No storage was mounted. |
| 6.469168–6.469584 | Cleanup | Host removal and Hibern8 passed. Both PSMs reached `0x11`, and the HCI IRQ was freed. |
| 90.206106–91.208898 | Timed warm return | Zero SCSI disks before restart. |

The first-block result confirms partition-relative I/O through
the published read-only `boot_b` device. The deferred-probe
`device_links_no_driver` warning remained.

Fastboot returned after 134 seconds. Stock D1 A restarted at
20:48:41 UTC and completed boot with enforcing verity and the
pretrial VBMeta digest. Ramoops and Android's `SYSTEM_LAST_KMSG`
agree on all 76 filtered v71 lines.

### Mainline v72 read at a nonzero boot_b offset

[v72 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/d88baf0503373d304ed85906c7acc45c9ab6509d)
keeps the GPT-selected read-only `boot_b` partition and
qualifies its Android header with a direct UFS read. It takes
a separate 4 KiB direct reference at partition-relative block 1.
The private partition bio begins at sector 8. The request gate
requires the remapped one-block READ(10) to use the GPT start
plus one, expected LUN 0 LBA 598,711 from v71. The comparator
checks all 4,096 bytes. GPT discovery and the read-only,
unmounted checks for all 42 partitions still apply.

The Arm64 `W=1` compile, strict checkpatch and 15
sanitizer-backed request checks passed. The five image hashes,
both AVB signatures and handoff bounds passed. The DTB, DTBO,
vendor images and RAM payload match v71. The live slot fit
matched the verified pre-rescue capture. Manifest SHA-256
`a8733788231cbf3cfc2dfab547bc84bb57bfbb0f5e0248a3fd8819644d3ea3f0`.

The attended test should confirm a single partition bio to the
expected LBA after GPT discovery, completion by IRQ with zero
residual, and a byte-for-byte match. Check that all 42 partitions
remain read-only and unmounted, then return to stock A.

#### Attended v72 slot B trial

On 2026-11-25 at 21:24:55 UTC, the Mac requested one v72
boot using the fresh nine-partition backup from the preceding
rescue. The live stager matched stock A to the pre-rescue
capture. All five slot B writes passed, and the readback
matched all 8,192 supplied `vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.181585–2.183199 | Direct qualification | Both GPT headers passed. The direct reference read 4,096 bytes from block 1 of partition 23, LUN 0 LBA 598,711. |
| 2.194205–2.198894 | GPT scan | Seven metadata reads completed by IRQ with zero residual, no rejection and no EFI fallback. The kernel verified 42 read-only partitions. |
| 2.198943–2.199180 | Partition block read | One READ(10) through `boot_b` used one 4,096-byte DMA-from-device segment. Tag 25 completed by IRQ with OCS 0, status 0 and zero residual. All 4,096 bytes matched the direct reference. |
| 2.381571–2.382007 | RAM verification | The guard verified all 42 partitions as read-only and unmounted. The RAM stage mounted no storage. |
| 6.437960–6.438352 | Cleanup | SCSI host removal and Hibern8 passed. HC and PHY reached `0x11`, and the HCI IRQ was freed. |
| 90.192187–91.194937 | Timed warm return | Zero SCSI disks before restart. |

The deferred-probe `device_links_no_driver` warning remained.
Fastboot returned after 133 seconds. Stock D1 A restarted at
21:27:28 UTC and completed boot with enforcing verity and the
pretrial VBMeta digest. Ramoops and Android's `SYSTEM_LAST_KMSG`
agree on all 76 filtered v72 lines.

### Mainline v73 compare two blocks through boot_b

[v73 source](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/9f76c0ccdc26acb1646b1fde2fe0b9a7ea2b898b)
qualifies the Android boot header and captures two separate 4 KiB
direct UFS reads from blocks 1 and 2 of the GPT-selected `boot_b`
partition. The expected LUN 0 range is 598,711–598,712. After the
same seven GPT metadata reads and validation of all 42 read-only
partitions, a private bio reads the same 8 KiB starting at
partition-relative sector 8.

The gate requires the exact remapped two-block READ(10) and one
DMA-from-device segment. The existing IRQ completion checks
reject a nonzero residual. The comparator starts with every byte
inverted and checks all 8,192 bytes after completion. The RAM
guard still requires all 42 partitions to remain read-only and
unmounted. Host removal, Hibern8 and the timed Fastboot return
use the v72 sequence.

Offline verification passed strict checkpatch, an Arm64 `W=1`
compile, 27 sanitizer-backed bio and range checks, both AVB
signatures, handoff bounds and the saved D1 slot fit. The DTB,
DTBO, vendor images and RAM payload match v72. Manifest SHA-256
`b04aebf6fb6d0bd90246ba645b7b57797fdb2260ff1615a268f439349faf24fd`.

Before an attended trial, take a fresh guarded NV backup and
leave the phone in Fastboot. Boot v73 once and capture both
reference reads, the single 8 KiB partition read and IRQ result,
the byte comparison and the read-only guard checks. Return to
stock A and retrieve the retained trace.

#### Attended v73 slot B trial

The guarded stock D1 rescue copied and independently verified
all nine read-only, unmounted NV targets on 2026-11-25. The copy
took 255 seconds and the Mac verified the saved 3,392,151,552
bytes again. The bridge reported no timeouts. The rescue returned
to Fastboot with A selected and Android stayed off while the
Mac staged all five v73 images. The readback matched all 8,192
supplied `vendor_boot_b` bytes.

| Monotonic time (s) | Event | Result |
| ---: | --- | --- |
| 2.182531–2.183960 | Direct qualification | Both GPT headers passed. Two direct 4 KiB reads supplied the reference for `boot_b`, partition 23, starting at LUN 0 LBA 598,711. |
| 2.198941 | GPT scan | Seven GPT metadata reads completed, with no rejection or EFI fallback. The kernel verified 42 read-only partitions. |
| 2.199002–2.199281 | Partition read | One READ(10) used one 8,192-byte DMA-from-device segment. Tag 31 completed by IRQ with OCS 0, status 0 and zero residual. All 8,192 bytes matched the direct reference. |
| 2.384079–2.384506 | RAM verification | The guard verified all 42 partitions as read-only and unmounted. The RAM stage mounted no storage. |
| 6.450208–6.450411 | Cleanup | Hibern8 passed, HC and PHY reached `0x11`, and the HCI IRQ was freed. |
| 90.192793–91.195611 | Timed warm return | Zero SCSI disks before restart. |

The deferred-probe `device_links_no_driver` warning remained.
Fastboot returned after 133 seconds. Stock D1 A restarted at
21:45:18 UTC and completed boot with enforcing verity and the
pretrial VBMeta digest. Ramoops and Android's `SYSTEM_LAST_KMSG`
agree on all 76 filtered v73 lines.

### Dedicated read-only Grizzly test root

The first dedicated root lives in RAM. Its 4 MiB ext4 image is
embedded in the Grizzly inventory initramfs inside
`vendor_kernel_boot_b`. It uses the known ARM64 BusyBox and
musl loader, a Grizzly release marker, and a small smoke probe.
This isolates filesystem and userspace execution from the choice
of a persistent install target. The fixture leaves Android's
`super`, `userdata`, and radio partitions alone. The prior v20
RAM-root trial reached Omarchy systemd and USB SSH with UFS absent.
Here the v73 UFS test and the minimal root run during the same boot.

Build the inventory ramdisk with
`pack-mainline-inventory.py --rescue-cpio RESCUE --read-only-test-root OUTPUT`
using an ARM64 rescue archive with the v73 BusyBox and loader.
The packer requires `mke2fs`. Replace the single vendor ramdisk
fragment in the v73 `vendor_kernel_boot` template with
`OUTPUT/inventory.cpio.lz4`, retain the DTB and bootconfig, and
regenerate the five-image checksums. The other four images from
v73 remain byte-identical.

PID 1 arms the existing 90-second warm return, then waits for
v73's 8 KiB comparison and live checks on all 42 read-only,
unmounted UFS partitions. It attaches only the embedded image to
`loop0` with the read-only flag and verifies its backing file
and sysfs read-only state. It mounts ext4 with `ro,noload,nodev,nosuid`,
checks mountinfo, then runs the release and write-denial probes
inside the test root. It unmounts and detaches the loop before
completing the RAM stage. The expected marker is
`Grizzly test root passed ram=1 loop_ro=1 write_denied=1 detached=1`.
The test root runs as a chroot under the inventory PID 1.

Offline checks passed both existing AVB signatures, all five
image hashes, same DTB and bootconfig, the D1 handoff bounds and
saved slot fit. The exact v73 kernel ran the root helper in an
Arm64 QEMU guest with no physical storage. The write probe hit
`EROFS`. A separate writable RAM control was refused. The
loop was detached, the mount disappeared, and a second run
refused the existing loop node. Manifest SHA-256
`78d107fdb3cdd0a75ea6fc319faf1c18eee938d56db59395acee779bfb7168e0`.

For a later trial, take a fresh guarded NV backup and keep the
phone in Fastboot while staging. A mock of this package's stager
wrote only the five slot B destinations and left A active. The
saved v73 captures verify the physical recovery sequence from B
through bootloader Fastboot to stock A, with enforcing verity and
the original VBMeta digest. On return, hold Volume Down to catch
Fastboot, select A, confirm the active slot, release Volume Down
and start stock Android. The earlier D1 recovery record also
verifies A's Recovery ADB sideload path with the same-build
signed OTA. That fallback follows the recorded Recovery procedure
and needs separate approval. Neither hardware recovery path was
rerun during offline preparation.

#### Attended read-only test root slot B trial

On 2026-11-26 the guarded stock rescue copied all nine NV
partitions in 255 seconds with no bridge timeouts. The Mac
verified the independent phone-side and saved-file hashes
for 3,392,151,552 bytes. The rescue returned through Fastboot
and stock Android stayed off while the five test-root images
were staged on B. The `vendor_boot_b` readback matched all
8,192 supplied bytes.

| Monotonic time (s) | Result |
| ---: | --- |
| 2.199034 | The v73 comparison matched all 8,192 bytes from `boot_b` to the direct UFS reference. |
| 2.381804 | The RAM guard verified all 42 UFS partitions read-only and unmounted before the root test. |
| 2.396239–2.408602 | The 4 MiB RAM image mounted on read-only loop0 as ext4 without a journal. The chroot probe verified the release marker and write denial. The kernel unmounted the filesystem and the helper confirmed the loop detached. |
| 2.567914–2.568336 | The guard again verified all 42 UFS partitions read-only and unmounted. The RAM stage completed. |
| 90.192618 | PID 1 requested the timed warm return. |

Fastboot returned after 133 seconds. Stock D1 A restarted at
06:23:08 UTC and completed boot with enforcing verity and the
original VBMeta digest. Ramoops and the current Android
`SYSTEM_LAST_KMSG` entry agree on all 81 filtered trial lines.

### Read-only Omarchy systemd RAM root

The systemd fixture uses the v73 kernel and device tree. Only
`vendor_kernel_boot` changes in the five-image package. It
starts with the same fixed 8 KiB `boot_b` comparison and live
checks on all 42 read-only, unmounted UFS partitions. The
kernel then retires the temporary SCSI host as in v73. The
receiver and the systemd smoke service each require zero
SCSI disks. The fixture exposes no UFS device nodes or mounts.

The userspace asset is the signed Omarchy Mobile 2026.11.15
ARM64 ext4 release previously tested in v20, which contains
Omarchy 4.5.0-3. Its compressed size is 3,081,094,118 bytes.
The Mac verified the release signature, manifest and compressed
digest. The receiver expands it sparsely into a size-capped
tmpfs and checks the exact 11,542,724,608-byte length and raw
SHA-256 before allowing a read-only loop mount. Ext4 mounts
with `ro,noload,nosuid,nodev`. There is no internal install.

Build `systemd-ram-return.c` as a static ARM64 executable.
Run the existing inventory packer with `--gpt-scan-only`
and use `pack-systemd-ram-root.py` to add the receiver, isolated
units and selected ARM64 tools from the archived v20 ramdisk.
Supply a fresh Dropbear host key and a fresh client public key.
Replace the v73 vendor ramdisk fragment with the resulting
`inventory.cpio.lz4` and retain the existing DTB, bootconfig
and other four images. Keep the boot bundle and matching SSH
credentials private.

For a later attended hardware trial, use the same fresh NV
backup and Fastboot staging gates as the read-only test root.
The fixture requires at least 12,000,000 KiB of available RAM
before it starts the USB receiver. Run the tracked host script
with the Mac's USB NCM interface, verified compressed image
and private SSH directory. It pins the host key, sends only
the root image, and requests handoff after the exact digest
matches. The forced SSH command allows status, receive and
handoff. It closes the receiver before systemd starts.

```sh
bash device/grizzly/bringup/stream-systemd-ram-root.sh USB_INTERFACE ROOT.img.zst PRIVATE_SSH_DIR
```

Only the Grizzly smoke target is visible to systemd. The
service checks the PID 1 executable, tmpfs backing, read-only
loop and mount, write denial, lack of SCSI disks, and required
Omarchy packages. It also checks that the independent return
helper survived `switch_root`. The helper requests a warm
restart after 600 seconds of uptime, including when root
receipt fails. Catch Fastboot with Volume Down and return
to stock A using the verified procedure above.

The full ARM64 guest test rejected a truncated stream, verified
the full release image and reached the isolated systemd target.
It logged
`GRIZZLY_SYSTEMD_PASS pid1=systemd root=ext4 ro=1 ram=1 write_denied=1 scsi_disks=0 timer=1`.
Separate local tests verified the scoped IPv6 listener, pinned
SSH authentication, refusal of arbitrary commands and refusal
of a handoff before image verification. The five image hashes,
two unchanged AVB signatures, handoff bounds and saved D1 slot
fit passed for the first trial package. Its manifest SHA-256 was
`45a32cc861d7dd42affc4f084cf9cb4de432bf928c281273798d4f011b4ae830`.

#### First attended Omarchy systemd RAM-root trial

The guarded rescue copied all nine read-only, unmounted NV
partitions and verified the 3,392,151,552 bytes privately on
the Mac. The phone remained in Fastboot between rescue and
staging. All five Omarchy B writes passed, with an 8,192-byte
matching `vendor_boot_b` readback.

| Monotonic time (s) | Result |
| ---: | --- |
| 1.197237 | The 600-second return helper armed. |
| 2.198541–2.377312 | The v73 8 KiB comparison passed. The RAM guard verified all 42 UFS partitions read-only and unmounted. |
| 6.437643–7.400412 | The temporary SCSI host was removed. The Omarchy receiver confirmed zero SCSI disks before USB setup. |
| 17.421593 | USB NCM setup failed. The Mac saw no verified NCM interface after reconnecting USB-C once. The root never streamed and the trial did not reach the systemd or write-denial checks. |
| 600.009639–601.010082 | The independent helper requested the warm return. |

Fastboot returned after 644 seconds. Stock D1 A restarted at
07:02:24 UTC and completed boot with enforcing verity and the
prior factory VBMeta digest. Ramoops and Android's
`SYSTEM_LAST_KMSG` agree on all 31 filtered trial lines.

The receiver waited for stock's `a210000.dwc3` UDC name.
The trial trace reports mainline's `a210000.usb` platform
device and successful USB2 PHY and Type-C attach. The v73
DWC3 and UDC core sources derive the UDC name from that
platform device. The ten-second gap before the setup failure
matches the receiver's controller wait. The corrected fixture
waits for `a210000.usb`, binds it and verifies configfs readback.
Separate log markers identify configfs, binding and link-local
address failures in the next run. A mocked configfs test bound
the mainline name and rejected the stock-only name before any
bind. The corrected bundle passed all five hashes, both
unchanged AVB signatures, D1 handoff bounds and saved slot fit.
Its manifest SHA-256 is
`c7d9d1480d23863456c6d3fd14d3daeea5ae85de99bb2524a1e0623bd0141a0a`.
The corrected bundle was verified on hardware in the trial below.

#### Attended corrected Omarchy systemd RAM-root trial

The first backup rescue lost USB before producing a backup.
The Mac recovered Fastboot manually, then retried the staged
rescue without starting stock Android. The bridge recovered
three serial timeouts and copied all nine guarded partitions.
The Mac independently verified the 3,392,151,552-byte copy
and its private file modes. The phone returned to Fastboot
with A selected. The five corrected images were then staged
on B, with an 8,192-byte matching `vendor_boot_b` readback.

| Monotonic time (s) | Result |
| ---: | --- |
| 1.200658 | The 600-second return helper armed. |
| 2.206722–2.378411 | The seven GPT metadata reads and the 8 KiB `boot_b` comparison passed. The RAM guard verified all 42 UFS partitions read-only and unmounted. |
| 6.434100–7.401149 | The temporary SCSI host was removed. The receiver confirmed zero SCSI disks. |
| 7.436572–18.474538 | Configfs bound `a210000.usb` and the link-local NCM receiver became ready. |
| 309.653595–312.387815 | The receiver verified the complete raw image hash and handed off to systemd. The isolated target reached `GRIZZLY_SYSTEMD_PASS pid1=systemd root=ext4 ro=1 ram=1 write_denied=1 scsi_disks=0 timer=1`. The root reported Omarchy 4.5.0-3. |
| 600.010134–601.010597 | The independent timer requested the warm return. |

The Mac authenticated the pinned USB SSH receiver at
07:21:24 UTC and streamed 3,081,094,118 bytes. The phone
acknowledged the verified image and handoff at 07:26:14 UTC.
USB SSH closed at handoff as designed.

Fastboot returned 643 seconds after the boot request.
Stock D1 A restarted at 07:31:55 UTC with enforcing verity
and the prior factory VBMeta digest. Ramoops and Android's
`SYSTEM_LAST_KMSG` agree on all 41 filtered trial lines.
The deferred-probe `device_links_no_driver` warning remained.

#### USB SSH status after systemd handoff

The optional live-status fixture keeps the existing USB NCM gadget
bound while it stops Dropbear and switches to the read-only RAM
root. After the root smoke check passes, the isolated systemd
target starts Omarchy's OpenSSH on the same scoped USB link-local
address and port. Both servers use the same pinned Ed25519 host
identity. The Mac helper's `--verify-live-ssh` option reconnects
and requires the `GRIZZLY_LIVE_SSH_PASS` reply. The listener
accepts only the authenticated `status` request. It has no shell,
PTY or forwarding, and the status check performs no write probe.
The initial systemd smoke check still verifies write denial.

An ARM64 VM booted the same Omarchy root, refused a truncated
stream and verified the complete image before handoff. The smoke
check passed with systemd as PID 1, a read-only ext4 RAM loop, zero
SCSI disks and the return timer still alive. A pinned SSH request
returned the expected status, and an attempted `id` command
returned exit status 2. The VM used IPv6 loopback to exercise
OpenSSH. The hardware trial below verified reconnection over
USB NCM.

The five image hashes, both AVB signatures and the D1 handoff
layout passed offline checks. Four images are byte-identical to
the last hardware trial. Only the inventory fragment in
`vendor_kernel_boot` changed. The 42-partition guard, SCSI host
removal and 600-second return are carried forward. Take a fresh nine-partition
backup after any stock A boot before another power or CPM trial.
Keep the key material and images private.

##### Attended USB SSH handoff trial

On 2026-11-26 the stock rescue verified the nine targets
read-only and unmounted before the first partition payload
read. The Mac verified all nine independent phone-side
hashes, 3,392,151,552 copied bytes, and private file modes.
The full 64 MiB rescue `vendor_boot_b` readback matched.
The rescue finished and returned to Fastboot with A selected.
The Mac staged the five Omarchy images on B and verified the
8,192-byte `vendor_boot_b` payload against its readback.

| Monotonic time (s) | Result |
| ---: | --- |
| 1.193935 | The 600-second return helper armed. |
| 2.199104–2.374250 | The seven GPT metadata reads and the 8 KiB `boot_b` comparison passed. The guard verified all 42 UFS partitions read-only and unmounted. |
| 6.486204–9.448721 | The kernel retired the temporary SCSI host. The receiver confirmed zero SCSI disks, bound USB NCM and brought up the link-local address. |
| 298.151231–300.338813 | The phone verified the raw image hash. Systemd reported PID 1, a read-only ext4 RAM loop, write denial, zero SCSI disks and an armed timer, then started OpenSSH. |
| 600.010210–601.010680 | The independent helper requested the warm restart. |

The Mac sent the 3,081,094,118-byte signed release asset over
USB SSH. At 07:51:52 UTC it reconnected on the same USB NCM
interface using the same pinned host key and received
`GRIZZLY_LIVE_SSH_PASS pid1=systemd root=ext4 ro=1 ram=1 scsi_disks=0 timer=1`.
The live listener rejected `id` with exit status 2 and empty
standard output. Pinned status checks continued to succeed
through 07:55:44 UTC.

Fastboot returned 643 seconds after the Omarchy boot request.
Stock D1 A restarted at 07:57:33 UTC and completed boot with
enforcing verity and the original VBMeta digest. Ramoops and
`SYSTEM_LAST_KMSG` agree on all 45 filtered trial lines.

### Offline D1 display handoff and first frame

The retained D1 stock `vendor_kernel_boot` holds two base FDTs.
The B0 tree starts at DTB container offset `0x82d70`. Applying
entry 19 (`0x80506`, revision `0x10000`) from the retained
USB-isolation DTBO produces `GRIZZLY MP based on MALIBU`.
Entry 28 is the same board ID at revision `0x10001` and
describes the same DSI0 and panel choices. These are offline
merges. The exact selection and firmware fixups on a live D1
boot remain to be captured.

Both base FDTs, the merged B0 tree and the v73 fixture have no
`simple-framebuffer` node, no child under `/chosen` and no named
boot framebuffer reservation. The v73 kernel builds simpledrm
in, but the retained console from the live SSH trial has no
framebuffer registration.

The exact D1 factory FBPK contains ABL's private splash-buffer
setup. At ABL file offset `0x59fcc`, the framebuffer-info function
gets the dimensions from the panel callback and derives a stride
of `ALIGN(width, 8) * 4` with internal format token `7`.
The retained D1 `bl_data.bin` records 1280×2856 for display 0,
which gives a 5120-byte stride. The scanout setup at `0x7c5f8`
uses the private address from this record. The address and
format token have no verified Linux memory reservation or
DRM fourcc mapping.

During system handoff, ABL `0x5f13c` calls `0x59fc4`, which
branches to the display teardown function at `0x7c89c`. The
retained D1 bootloader log corroborates the D-PHY power-off.
Keep simple-framebuffer disabled. Enabling it would require
evidence of an AP-visible reserved buffer, its exported pixel
layout and scanout continuing past handoff.

D1's supplier display stack has a separate power handoff.
In the stock 4 KiB-page GKI module set,
`mipi-dsi2h.ko`'s `_dsi_has_power_during_handoff_dt` follows the first
`power-domains` phandle and checks `google,boot-stay-on`.
After a runtime PM get, `dw_mipi_dsi2h_probe` reads DSI
register `0x0c` bit 0 and logs
`DSI power handoff from bootloader: dt=%d reg=%d`. It keeps
the handoff vote when both are set. `vs_drm.ko` also checks
`google,boot-stay-on` on its power domains. The flag is absent
from both base FDTs and all 55 entries in the retained DTBO.
In the saved D1 stock Android bugreport, the existing DSI0
probe logged `DSI power handoff from bootloader: dt=0 reg=0`
at 1.160279 s, then the stock CGYDA panel driver bound at
1.225111 s. The probe did not find a handoff flag or an enabled
host on that boot. The offline audit introduced no PHY TX or
host register accesses.

| Stage | D1 evidence |
| --- | --- |
| Scanout | `verisilicon,dc9x00` at `0x0f600000`, GPCSR at `0x0f790000`. FE0 and BE sit behind the DPU wrapper. Display SMMU at `0x0f190000` serves the DPU's stream IDs `0x8000` through `0x801f` with nested translation in the stock tree. |
| Power and clocks | CPM MBFS `dpu.v` (`0x08`) is the parent of `DpuBe.v` (`0x200`). `DpuFe0.v` (`0x201`) and `DpuDsi0.v` (`0x203`) hang off BE. Stock BE, FE0 and DSI0 pixel clock definitions use LPCM `0x23`. |
| DSI0 and PHY | `verisilicon,dc9x00-mipi-dsi2h` at `0x0f7d8000` uses the Synopsys G301 C/D-PHY in D-PHY mode at `0x0f7c0000`. Four lanes, 38.4 MHz PLL reference, DT data rate `0x56e`. DSI0 IRQ uses input `0x14` on the display multicast aggregator at `0x0f46e060`. DSI1 is disabled. |
| Panel | The DSI0 connector prefers `google,gs-cgyda` (`panel-gs-pkcgda.ko`, stock modes include 1280×2856). The alternate is `google,gs-bzea` (`panel-gs-bmea.ko`). The board routes VDDI to BUCK12S, VCI to LDO18S, VDDD to S2DOS07x02, and reset to DA9188 GPIO 11. The overlay preference alone cannot identify the fitted panel. |

The stock ramdisk carries `vs_drm`, `mipi-dsi2h`,
`mipi-cdphy`, and the Google connector and panel modules.
They target the D1 GKI ABI. The v73 fixture lacks a native
Malibu display binding and its GS201 DECON/DSIM drivers do
not match this pipeline. The CGYDA driver registers
`gs_panel_prepare_with_reset`, which calls the common panel
prepare helper before the pre-enable reset. Its enable path
handles panel-specific DCS initialization, DSC configuration,
TE setup and mode programming. The DT alone does not supply
that sequence or the mode parameters.

First qualify the powered DSI0 path and panel identity with
stock DT and driver evidence. Capture the firmware's live
power handoff flags if available. Any later DSI status read
needs a bound driver and confirmed runtime power, as in the
stock probe. For the first native frame, qualify FE0/BE
power and clock votes and the DSI0 link. The v73 CPM provider
has neither the display genpd IDs nor the LPCM `0x23` clocks.
Those suppliers need to be qualified before a mainline DSI0
probe. Carry forward USB SSH and the timed stock A return.
Keep UFS read-only and unmounted.

#### Stock display test pattern

The 4 KiB-page D1 `vs_drm.ko` registers a per-CRTC debugfs
`pattern` file in `vs_crtc_late_register`. The display pattern
help lists three insertion points, `BLD` (blender), `POST_PROC`
(post-processing), and `OFIFO` (output FIFO). It also lists a
solid-color mode and horizontal and vertical color bars. This
is a different path from the driver’s per-plane pattern.

`vs_dc_enable_display_pattern` checks the selected CRTC's
pattern capability and validates the position and mode.
`dc_hw_set_display_pattern` writes pattern enable, mode and
parameters via `dc_write`. It takes no framebuffer address and
does not call a buffer pin, DMA mapping, or plane setup function.
That rules out a framebuffer requirement for programming the
generator itself. An active stock modeset may still carry plane
mappings and the offline trace does not establish whether all
plane fetches can be disabled or whether OFIFO insertion works
with the panel’s DSC mode.

The immediate CRTC pattern path has no runtime-PM acquisition
of its own. The stock delayed branch calls the same generator
in `vs_dc_enable` immediately before `dc_hw_display_commit`.
Use that ordering as the reference when implementing the first
native pattern. A pattern request needs a powered and clocked
output and a valid DSI0/panel mode. A write count from the stock
debugfs handler only confirms that it accepted input.

For first light, qualify a known panel mode, then generate one
pattern at the blender while retaining the established panel
mode and compression path. Record the pattern setting, a
visible screen change, and frame completion. Stock exposes
`frame_done_count` and `te_count` per CRTC and has a
`disp_frame_done` trace event. Check for underruns and display
SMMU faults, and confirm the pattern clears. A visible pattern
tests the panel path before framebuffer DMA is qualified. A
later RAM-backed test frame still needs a verified display
SMMU mapping. Keep touch and Hyprland for after first light.

#### D1 display power and clock provider

In both Grizzly B0 merges, DPU clients refer to child domains
of `google,mbu-power-controller`. Use the MBFS names and
parent relationships above. The factory ramdisk also carries
`lpm_pm_domains.ko` with direct DPU register and PSM callbacks
for `google,mbu-dpu-lpm-pm-domains`, but that compatible is
absent from both Grizzly trees. The presence of a callback in
the module is insufficient to use those MMIO offsets on Grizzly.

The three CPM clock tuples are identical in both merges.
The rates are clock-provider entries, independent of the
DRM mode's pixel-clock field.

| Clock | LPCM ID | Clock ID | Stock rates (MHz) |
| --- | --- | --- | --- |
| DSI0 pixel | `0x23` | `0x01` | 50, 100, 150 |
| BE | `0x23` | `0x04` | 200, 356, 480, 672 |
| FE0 | `0x23` | `0x05` | 200, 356, 480, 672 |

The stock 4 KiB-page `clk-cpm.ko` mailbox helper packs
`op << 24 | clock_id << 16 | lpcm_id << 8 | 0x02` and an
argument word into an eight-byte request. The command format
matches v73's existing LPCM transport. In the stock mailbox
path, prepare uses op 0 with argument 1, rate readback uses
op 3, and set-rate uses op 5 with the rate argument.
The v73 USB/UFS clock gates do not implement this display
rate interface.

For the next provider diagnostic, qualify the four MBFS
domain lookups and the LPCM rate replies before adding display
consumers. Treat a resolved MBFS handle or nonzero clock rate
as firmware metadata. Domain vote acknowledgement, clock
readback under power, DSI host access and a frame completion
are separate checks.

##### Offline display CPM query fixture

The diagnostic kernel `7.3.0-rc6-omamobile-grizzly-display-cpm`
at `52b7d6537d16f771d52d07b6f14c8c7ccdc964a2` adds an opt-in
`clk_google_malibu_cpm.display_query=1` boot parameter. On Grizzly,
after the existing CPM power-domain provider registers, the
diagnostic performs four lookups under the existing MBFS client
root and logs each handle or error. It then sends these rate-only
LPCM commands with argument zero.

| Clock | Rate query |
| --- | --- |
| DSI0 pixel | `0x03012302` |
| BE | `0x03042302` |
| FE0 | `0x03052302` |

The code records the signed firmware reply or transport error
for each clock and continues after individual failures. It sends
no display vote, rate change, reset or MMIO access. The kernel
retains the existing v73 UFS initialization and read-only guard.

The ARM64 build and kernel style check passed. A mock of the exact
helper verified the four names, all three command words and zero
arguments. It also exercised lookup failure, a transport timeout
and a negative firmware reply. The five image hashes, both AVB
signatures, the handoff bounds and the fit against saved D1
Fastboot variables passed. The manifest SHA-256 is
`896e572d2b28d06a0e109385116cb366e42b9babfb809c8b2ce4850da5a3c0d6`.
The fixture reuses the live-SSH vendor images and DTBO byte for
byte. The `init_boot` payload was signed with the same new offline
key as `boot`.

For an attended test, take a fresh verified nine-partition backup
and use the normal slot B staging and stock A return. Capture
`display-cpm: read-only queries start`, all seven result lines,
and `display-cpm: read-only queries complete` in the retained
console. If the markers are absent, check whether ABL forwarded
the boot parameter. A zero or negative clock reply is evidence
about the unpowered query and does not qualify a usable rate.
The display stays disabled. The hardware trial is recorded
below.

##### Attended display CPM query trial

On 2026-11-26 the guarded rescue backed up nine read-only,
unmounted NV partitions. The bridge recovered two serial framing
interruptions. The Mac verified all nine independent hashes,
3,392,151,552 bytes, and private file modes. The 64 MiB rescue
`vendor_boot_b` readback matched. The rescue returned to Fastboot
with A selected and stock Android stayed off before the diagnostic.
All five diagnostic images staged on B, and the 8,192-byte
`vendor_boot_b` payload matched its readback.

ABL forwarded the opt-in boot parameter. All seven requests
completed between 0.192796 and 0.193350 seconds of kernel uptime.

| Query | Live result |
| --- | --- |
| MBFS `dpu.v` | Handle `0x15c0008` |
| MBFS `DpuBe.v` | Handle `0x15c0027` |
| MBFS `DpuFe0.v` | Handle `0x15c0028` |
| MBFS `DpuDsi0.v` | Handle `0x15c002a` |
| DSI0 pixel rate | Firmware `-3` |
| BE rate | Firmware `-3` |
| FE0 rate | Firmware `-3` |

The MBFS results identify four distinct resources. All three
LPCM responses were firmware replies, with no transport
timeouts. The provider's generic clock error mapping maps
`-3` to `ENODATA`. These samples were taken before any display
power vote from the diagnostic. They leave open whether the
same calls return a rate once stock has brought the display up.

The UFS guard verified 42 read-only, unmounted partitions and
the 8 KiB `boot_b` comparison. The temporary SCSI host retired
before the authenticated USB receiver became ready. The return
helper requested the warm restart at 600.010909 seconds.
Fastboot returned 644 seconds after the boot request. Stock D1
A completed boot with enforcing verity and the original VBMeta
digest. Ramoops and `SYSTEM_LAST_KMSG` match on all 20 filtered
trial lines.

##### Stock D1 display and performance-domain checks

On 2026-11-26 stock D1 A reported its internal display ON.
SurfaceFlinger listed 1080×2410 at 120 Hz as the active mode.
The stock bugreport identifies the fitted panel as CGYDA and
records revision MP from `panel-gs-pkcgda`. Its stock boot log
reports `DSI power handoff from bootloader: dt=0 reg=0` and later
reports the panel enabled at boot. The handoff message is a
snapshot at DSI probe. The bugreport had no clock-rate rows for
the three LPCM clocks, and the device had gone back to display
OFF by the time collection finished.

The Android ADB shell could list the DSI device and the display
devfreq entries. DRM connector attributes, runtime power states,
`dpu_clamp/fw_freq`, `fabdisp_clamp/fw_freq` and the
`goog_cpm_mailbox` trace were inaccessible. Neither standard
debugfs path exposed `clk_summary`. The D1 clock driver registers
the three clock nodes uncached, so an authorized per-clock
`clk_rate` read would use the same LPCM op 3. The active-display
comparison remains unmeasured.

The two Grizzly B0 merges have no static clock consumers for
the three LPCM nodes. Stock `vs_drm.ko` has no clock API imports.
Its `dc_probe` calls `gs_perf_domain_find_devfreq` with `dpu`
and the DT fabric name `fabdisp`, and its display QoS path uses
devfreq votes. The DSI host also has no clock API imports. The
C/D-PHY driver's clock input is the fixed 38.4 MHz PLL reference.

Factory `perf_domain.ko` reads `mbfs-perf-domains-path`
(`cpm/perf/domains`) and enumerates children. For `fw_freq`, it
resolves the child `CurOpp`, reads the MBFS scalar and converts the
OPP level through the firmware DVFS table. `cur_freq` returns the
driver's cached value. Read the raw OPP level before treating it
as Hz, and distinguish both devfreq domains from the DSI pixel
clock and the panel refresh rate.

##### Offline display MBFS operating-point fixture

The follow-up kernel `7.3.0-rc6-omamobile-grizzly-display-opp`
at `192c6b85d2f25bccaeebe065d517614cd2d11d64` keeps the opt-in
display CPM queries. From the same MBFS namespace root, it
resolves `cpm/perf/domains`, then reads only `CurOpp` under
`dpu` and `fabdisp`. It records the handle and complete raw
64-bit value, or the lookup or read error. The helper uses the
existing MBFS read opcode, which matches the factory
`mbfs_read_file` request. The existing boolean vote reader
still rejects values outside 0 and 1.

The ARM64 build and kernel style check passed. A mock confirmed
the path and dispatch, both payload words, failure on a missing
path segment, and continued sampling after a timeout. The five
image hashes, both AVB signatures, handoff layout and saved D1
slot fit passed. The manifest SHA-256 is
`30b1674c38471bd174b06cbac97a715b22ebb6d1effb7f62e6db7bb3df2844d7`.

The fixture keeps the verified UFS guard, USB receiver and
timed return. It sends no display vote, rate setting or MMIO
access. On a later approved slot B trial after a fresh NV
backup, capture both `display-perf` results and the original
`display-cpm` lines. This establishes whether the same MBFS
resources are available to mainline before display enable.
The raw level needs the D1 DVFS table for a frequency, and
this fixture cannot measure a powered display.

##### Attended display MBFS operating-point trial

On 2026-11-26 the stock rescue backed up nine read-only,
unmounted NV partitions. The Mac verified the private modes,
all nine independent hashes and 3,392,151,552 copied bytes.
The 64 MiB rescue `vendor_boot_b` readback matched. The rescue
returned to Fastboot with A selected. Stock Android stayed off
before the diagnostic, and the five diagnostic images staged
successfully with a matching 8,192-byte `vendor_boot_b` payload.

The four distinct MBFS handles and three LPCM `-3` replies
matched the preceding trial. At 0.102355 seconds, the new
query logged `display-perf: path segment cpm error=-2`.
It did not reach either `CurOpp` file.

In the exact stock `mbfs.ko`, `mbfs_get_handle` extracts the
first path component, compares it with registered backend
names, and takes the matching backend's root handle before
walking the remaining components. `mbfs_cpm_backend.ko`
registers the name `cpm`. The raw protocol already addresses
that backend and returns its namespace root. The path below
that root begins at `perf/domains`. The trial treated the backend
name as a directory, which accounts for the `-ENOENT` result.

The kernel verified the 8 KiB `boot_b` read and all 42 UFS
partitions read-only and unmounted. The temporary SCSI host
retired before USB SSH was ready. The helper requested warm
restart at 600.009709 seconds. Fastboot returned 644 seconds
after the boot request. Stock D1 A completed boot with enforcing
verity and the original VBMeta digest. Ramoops and
`SYSTEM_LAST_KMSG` matched all 21 filtered trial lines.

The retained factory `dvfs_helper.ko` obtains the frequency
table from CPM destination `0x0e`. It first queries domain
count (`0x00000003`), then descriptors
(`0x00000103 | index << 16`) and pairs of OPP rows
(`0x00000203 | domain_id << 16 | even_level << 24`).
Its exact conversion checks that the zero-based OPP index
is within the domain count of levels and that row bit 14
is set. Bits 13:0 hold MHz. The saved stock bugreport's CPM
mailbox trace is empty, so it does not supply the live
`dpu` or `fabdisp` table.

##### Corrected display MBFS operating-point fixture

Kernel `7.3.0-rc6-omamobile-grizzly-display-opp-root` at
`26b2e93cb0791ad8fdb2b2fd0bdddf869f2a9c76` starts the lookup
at `perf/domains` below the CPM backend root. The opt-in
parameter, four original MBFS lookups, three LPCM reads
and two raw `CurOpp` reads are retained. The change adds
no display power votes, clock writes or MMIO access.

The ARM64 build and style check passed. A mock confirmed both
`CurOpp` reads from the corrected path and that a missing
`perf` component stops the lookup. All five image hashes, both
AVB signatures, handoff bounds, and saved slot-fit checks passed.
The manifest SHA-256 is
`48e16ff392feb409cfc36bb2be0e9424898cc08efc9df6b1e71e90223bb24145`.
The hardware trial below used a fresh verified NV backup.

##### Attended corrected display MBFS trial

On 2026-11-26 the stock rescue verified all nine NV targets
read-only and unmounted. The Mac verified 3,392,151,552 bytes,
all nine independent hashes, and private file and directory
modes. The full 64 MiB rescue `vendor_boot_b` readback matched.
The rescue returned to Fastboot with A selected. The five
diagnostic images staged on B, and the 8,192-byte
`vendor_boot_b` payload matched its readback.

The four display MBFS power-domain handles and three LPCM
`-3` firmware replies matched the two preceding trials.
The corrected `perf/domains` path resolved and both raw
`CurOpp` reads succeeded.

| Kernel time (s) | Domain | Handle | Raw level |
| ---: | --- | --- | ---: |
| 0.107086 | `dpu` | `0x10d000a` | 3 |
| 0.107239 | `fabdisp` | `0x10f000a` | 3 |

The two values are indices into separate firmware DVFS
tables. Matching indices do not establish equal frequencies.
The capture precedes display enable and establishes access
to the stock performance backing files.

The kernel verified seven GPT metadata reads, the 8 KiB
`boot_b` comparison and all 42 UFS partitions read-only and
unmounted. It retired the temporary SCSI host before the
authenticated USB receiver became ready. The independent
helper requested the warm restart at 600.009948 seconds.
Fastboot returned 644 seconds after the B boot request.
Stock D1 A completed boot with enforcing verity and the
original VBMeta digest. Ramoops and `SYSTEM_LAST_KMSG`
matched all 22 filtered trial lines.

For a later read-only DVFS table capture, resolve exact
`dpu` and `fabdisp` descriptors and request only the pair of
rows covering the observed level for each domain. Bound domain
enumeration to the stock limit of 48 and OPP entries to 32.
Require an in-range index and a valid row before converting
to MHz. Start enumeration after the storage guard and USB
receiver are ready. A timeout stalls the shared CPM transport,
so stop on that failure without retrying.

##### Offline display DVFS row fixture

Kernel `7.3.0-rc6-omamobile-grizzly-display-dvfs` at
`84024df794f1fbdc5166660edce935174ee5e43b` keeps the
earlier CPM and MBFS measurements. The additional
`clk_google_malibu_cpm.display_dvfs=1` parameter exposes
a root-only, one-shot sysfs read on Grizzly. The RAM
initramfs reads it after the UFS guard and SCSI retirement,
with USB NCM ready and the SSH receiver started. The original
return helper stays armed.

The read enumerates at most 48 DVFS descriptors and matches
`dpu` and `fabdisp` by exact name. It validates that each
matched domain offers level 3, fetches the pair starting at
level 2, and selects the odd row. Each result reports the
domain ID, level, raw word, and the table's MHz value if the
row is valid. The command phase has a three-second budget
and stops at the first transport error, with no retries.
It issues no display power votes, rate changes or display
MMIO accesses. A decoded value is a nominal table entry.
Compare it with the separately logged `CurOpp` index before
using it to describe this boot.

The ARM64 build and kernel style check passed. Mocks verified
the request words, exact names, level-3 selection, descriptor
bounds, invalid rows, failure handling and the one-shot gate.
An ARM64 guest verified that the appended archive supplies
the updated initramfs script and that the Grizzly-only
attribute is absent on the VM. No CPM requests ran in the
guest. All five image hashes, both AVB signatures, the
handoff bounds and the fit against saved D1 variables passed.
The manifest SHA-256 is
`35fb3aa1744486723b4f20d9e19c204f52f8283154ae5d2f8a50573c73401c48`.

For the first attended trial, use a fresh verified NV
backup, capture both `display-dvfs` rows, compare them with
the live `CurOpp` samples and return to stock A. The display
stays disabled.

##### Attended display DVFS row trial

On 2026-11-26 the rescue copied nine read-only, unmounted NV
partitions. The USB bridge recovered one serial framing
interruption. The Mac verified 3,392,151,552 bytes, all nine
independent hashes, and private modes. The full 64 MiB rescue
`vendor_boot_b` readback matched. After the rescue returned to
Fastboot, the Mac staged all five diagnostic images on B and
verified the 8,192-byte `vendor_boot_b` payload.

The four display power-domain handles matched earlier trials.
All three LPCM rates again returned firmware `-3`. Both early
MBFS `CurOpp` reads returned level 3. After the UFS guard,
temporary SCSI host removal and USB NCM setup, the DVFS query
ran from 10.451803 to 10.456252 seconds of kernel uptime.

| Domain | Firmware ID | Level | Raw DVFS row | Nominal rate |
| --- | ---: | ---: | --- | ---: |
| `dpu` | 7 | 3 | `0x7fff4164` | 356 MHz |
| `fabdisp` | 8 | 3 | `0x7fff40f0` | 240 MHz |

Both rows had bit 14 set. These are nominal entries in separate
firmware tables, matched to the early `CurOpp` indices. The
fixture left the display disabled, so the entries do not
establish a measured pixel clock or an active scanout rate.

The guard verified all 42 UFS partitions read-only and
unmounted, and the 8 KiB `boot_b` comparison passed.
The authenticated USB receiver became ready. The independent
helper requested the warm restart at 600.009660 seconds.
Fastboot returned 642 seconds after the B boot request.
Stock D1 A completed boot with enforcing verity and the
original VBMeta digest. Ramoops and `SYSTEM_LAST_KMSG`
matched all 26 filtered trial lines.

##### Offline DPU wrapper power-vote fixture

The exact D1 Grizzly tree assigns `dpu.v` resource `0x08`.
The wrapper has no parent. The stock `power_controller.ko`
uses its shared MBFS power callback for this resource.
The callback sends a boolean write and, for firmware status 5,
waits for completion matched by resource ID. The stock DPU
wrapper has no separate register callback. The BE, FE0, FE1,
DSI0, DSI1 and DP0 domains are descendants of the wrapper.

Kernel `7.3.0-rc6-omamobile-grizzly-display-wrapper` at
`bd43fcf44bd23f6262711e23f96c212bf9690dc7` keeps the early
display CPM and MBFS reads. The boot parameter
`clk_google_malibu_cpm.display_wrapper=1` enables the one-shot
root-only trigger. The RAM initramfs invokes it after the UFS
guard and SCSI retirement with the USB receiver started.
The DVFS table query is disabled for this fixture so it
cannot run between the ON and OFF requests.

The trigger looks up and samples the AP client votes for
the wrapper and all six descendants. It sends no write if
any vote is already on or a required sample fails. With all
seven off, the existing serialized MBFS helper sends a
wrapper ON request, handles deferred completion and verifies
readback. Only a confirmed ON is followed by OFF. A rejected
or ambiguous request stops the diagnostic without retry.
It logs both raw acknowledgement statuses and each available
readback. These are client votes, not a measurement of the
physical clocks, SMMU, or scanout. The diagnostic changes only
the wrapper vote and does not exercise the panel or DSI PHY.

The ARM64 build and style check passed. Mocks covered immediate
and deferred completion, inherited votes, a failed sample,
rejection, mismatched readback, timeouts and repeated triggers.
An ARM64 VM verified the packaged initramfs script and Grizzly
board gate without exercising hardware. Five image hashes,
both AVB signatures, handoff bounds and saved slot-fit checks
passed. The manifest SHA-256 is
`ffe6b8cf364a8f251797a31765aa96e402b143ac2a6786464089343afd56c2f4`.

For an attended test, use a fresh verified NV backup and
the existing timed stock A return. Capture all seven initial
votes and the wrapper acknowledgement, completion and readback
for any ON/OFF requests. An inherited vote or an ambiguous
transition is a reason to end the trial without exercising
child domains.

##### Attended DPU wrapper trigger trial

On 2026-11-26 the guarded rescue verified all nine NV partitions
read-only and unmounted. The Mac verified 3,392,151,552 bytes,
all nine independent hashes and private modes. The full 64 MiB
rescue `vendor_boot_b` readback matched. The Mac staged the
diagnostic on B with a matching 8,192-byte `vendor_boot_b` payload.

The kernel accepted the wrapper boot flag, and the early CPM
rate and MBFS operating-point samples matched prior trials.
The UFS guard checked all 42 UFS partitions read-only and
unmounted and retired the temporary SCSI host. The USB
receiver authenticated. The RAM script logged
`display-wrapper: vote cycle start` at 10.452192 seconds and
`display-wrapper: vote cycle failed` at 10.452297 seconds.
The trace contains no initial vote, acknowledgement or
readback from the kernel's wrapper callback.

The RAM inventory mounts sysfs read-only, remounts it briefly
to set the warm-return policy, and reseals it before the root
script runs. The first fixture tried to write a sysfs attribute
on that mount. The failure happened before the vote samples
and did not qualify an ON/OFF cycle.

Fastboot returned 644 seconds after the B boot request.
Stock D1 A completed boot with enforcing verity and the
original VBMeta digest. Ramoops and `SYSTEM_LAST_KMSG`
matched all 24 filtered trial lines.

##### Corrected DPU wrapper trigger fixture

Kernel branch `grizzly-display-wrapper-node` at
`633b3a933fe75cf3fbc7bba08f1a46f15e18daf8` exposes a write-only
misc device when the Grizzly board and wrapper boot flag match.
After the storage checks, temporary SCSI host removal and USB
receiver startup, the RAM script reads the device numbers from
read-only sysfs, creates a mode-0200 node in RAM-backed `/dev`,
sends `run\n` once and removes the node. The UFS checks and
independent timed return remain in place. The kernel samples
all seven client votes first and leaves any inherited votes
in place. When all are clear, it sends OFF only after ON succeeds.

The arm64 build and five image checks passed, including both
AVB signatures, the vendor handoff and fit against captured D1
slot B capacities. The `SHA256SUMS` file hashes to
`c9df99ba557ace0b261b2fd9ef738196a2d62cbfa8cdc4dc1bacbb6cfaf57bb0`.
A mock exercised malformed commands, copy failure, inherited
votes, ON timeout, a successful ON/OFF pair and repeat-trigger
rejection. Apple Virtualization verified writing through a
temporary device node with sysfs read-only. The Grizzly misc
device was absent on the virtual board.

##### Attended corrected DPU wrapper trial

On 2026-11-26 the guarded rescue verified all nine NV partitions
read-only and unmounted. The Mac independently checked all nine
SHA-256 hashes, 3,392,151,552 bytes and private permissions.
The full 64 MiB rescue `vendor_boot_b` readback matched.
After the rescue returned to Fastboot, the Mac staged the five
corrected images on B and verified the 8,192-byte
`vendor_boot_b` payload.

The diagnostic verified the 42-partition read-only UFS inventory,
passed the 8 KiB `boot_b` comparison, retired the temporary
SCSI host and reached the authenticated USB receiver. The RAM
device node triggered one wrapper cycle. The initial AP client
votes for `dpu.v` (handle `0x15c0008`), `DpuBe.v`, `DpuFe0.v`,
`DpuFe1.v`, `DpuDsi0.v`, `DpuDsi1.v` and `DpuDp0.v` were all
`0`. The trigger issued these requests to `dpu.v`.

| Request | CPM acknowledgement | Vote readback | Driver result |
| --- | --- | --- | --- |
| ON | `5` (deferred, completion received) | `1` | `0` |
| OFF | `0` (immediate) | `0` | `0` |

The cycle completed in about 2.6 ms from the trigger marker
to its return. It verified the wrapper vote and release through
CPM. Physical clock rates and scanout were outside this trial.

The independent helper requested the warm restart at
600.009654 seconds of kernel uptime. Fastboot returned 642
seconds after the B boot request. Stock D1 A completed boot
with enforcing verity and the original VBMeta digest.
Ramoops and `SYSTEM_LAST_KMSG` matched all 37 filtered lines.

##### Offline DPU BE power-vote fixture

Both retained stock D1 base trees describe `dpu_be_pd` as
`DpuBe.v` with MBFS resource ID `0x200` and wrapper parent
`dpu.v` (`0x08`). FE0 and DSI0 are children of BE. Neither
Grizzly B0 overlay changes those relationships. The stock
power driver matches deferred MBFS completion against the
full 32-bit resource ID in notification word 1. The mainline
helper already uses that field. The last live wrapper trial
resolved the BE handle to `0x15c0027`.

Kernel `7.3.0-rc6-omamobile-grizzly-display-be` at
`9eb185def0ca317c101045731d9a8012d0ceafec` adds
`clk_google_malibu_cpm.display_be=1` to the Grizzly-only
one-shot wrapper fixture. The trigger samples the same seven
initial AP votes. If all samples succeed and all votes are
clear, it runs wrapper ON, BE ON, BE OFF, then wrapper OFF.
Each step logs its CPM acknowledgement, available readback
and driver result. If a BE transition fails, the diagnostic
stops and keeps the wrapper vote for the timed return.
There are no retries or votes for BE descendants.

The BE clock uses LPCM GET_RATE word `0x03042302` with
argument zero. The earlier unpowered query returned firmware
`-3`. The new diagnostic keeps that early query. It defers
any powered LPCM query until the BE cycle is qualified because
a transport timeout would also block MBFS release requests.
The fixture leaves the display consumers disabled.

The arm64 build and style check passed. A mock of the trigger
verified the four-step order, skipping writes for an inherited
vote or any failed initial sample, stopping at each failed
transition, one-shot enforcement and the wrapper-only path
with the BE flag absent. Five image hashes, both AVB
signatures, the ABL handoff bounds and captured D1 slot fit
passed. The tested vendor ramdisks, DTB and DTBO are byte
identical to the corrected wrapper fixture and retain the
UFS guard, USB SSH and independent timed return. The SHA-256
of the new `SHA256SUMS` file is
`4b883b9d6a51cab1aef7715bfbbf4a0cbde9b9b2fa7262a18e346f827bb5ca8d`.

##### Attended DPU BE power-vote trial

On 2026-11-26 the guarded rescue copied all nine NV partitions
read-only and unmounted. The Mac independently verified all nine
SHA-256 hashes, 3,392,151,552 bytes and private permissions.
The full 64 MiB rescue `vendor_boot_b` readback matched.
After the rescue returned to Fastboot, the Mac staged all five
BE diagnostic images and verified the 8,192-byte
`vendor_boot_b` payload.

The diagnostic verified the 42-partition read-only UFS inventory,
passed the 8 KiB `boot_b` comparison, retired the temporary SCSI
host and reached the authenticated USB receiver. The initial
AP client votes for `dpu.v`, `DpuBe.v`, `DpuFe0.v`, `DpuFe1.v`,
`DpuDsi0.v`, `DpuDsi1.v` and `DpuDp0.v` were all `0`.
BE resolved to handle `0x15c0027` and used resource `0x200`.

| Request in execution order | CPM acknowledgement | Vote readback | Driver result |
| --- | --- | --- | --- |
| Wrapper ON | `5` (deferred, completion received) | `1` | `0` |
| BE ON | `5` (deferred, completion received) | `1` | `0` |
| BE OFF | `0` (immediate) | `0` | `0` |
| Wrapper OFF | `0` (immediate) | `0` | `0` |

The cycle ran from 8.466174 to 8.469439 seconds of kernel
uptime. The early unpowered LPCM replies stayed at `-3` and
both `CurOpp` replies reported level 3. This trial verified
parent and child CPM vote sequencing. Powered clock readback
and scanout remain to be tested.

The independent helper requested a warm restart at
600.009574 seconds of kernel uptime. Fastboot returned 643
seconds after the B boot request. Stock D1 A completed boot
with enforcing verity and the original VBMeta digest.
Ramoops and `SYSTEM_LAST_KMSG` matched all 44 filtered lines.

##### Offline powered DPU BE clock diagnostic

Kernel `7.3.0-rc6-omamobile-grizzly-display-be-rate` at
`ccad299eb5ab278b427587dce03c3ef17e4189c4` adds the opt-in
`clk_google_malibu_cpm.display_be_rate=1` flag to the tested
Grizzly wrapper and BE one-shot fixture. It keeps the early
unpowered BE reply for comparison. After all seven initial
votes are checked and the wrapper and BE ON requests have
completed with readbacks of `1`, it sends one LPCM GET_RATE
request with word `0x03042302` and argument `0`. The request
uses the existing one-second clock timeout and logs the raw
signed firmware reply or the transport error. Any positive
reply reports the CPM rate and leaves the physical clock
measurement open.

When the transport returns a reply, including a negative
firmware reply, the diagnostic releases BE before the
wrapper and verifies both vote readbacks. A transport error
stops further requests and leaves the votes for the independent
timed return. The shared mailbox can stall on a timeout.
The fixture keeps the initial-vote and one-shot guards and
leaves the clock gates, display consumers and panel alone.

The arm64 build and style check passed. A mock verified the
exact request, ordering, positive, zero and negative replies,
transport failures, failed vote transitions, inherited vote
and sample guards, and the behavior with the new flag absent.
The five image hashes, both AVB signatures, handoff bounds
and captured D1 slot fit passed. The vendor boot images and
DTBO match the tested BE fixture byte for byte, preserving
the UFS guard, USB SSH and independent timed return.
The `SHA256SUMS` file hashes to
`216ab1dd14642dbd0d323e720035429d07bade39159ba5a83320247caccb4478`.

##### Attended powered DPU BE clock trial

On 2026-11-26 the initial backup transfer failed over USB.
The phone returned to Fastboot and the Mac verified the full
64 MiB rescue `vendor_boot_b` readback again before restarting
the rescue. The retry copied all nine NV partitions read-only
and unmounted. The Mac independently verified all nine SHA-256
hashes, 3,392,151,552 bytes and private permissions. After the
rescue returned to Fastboot with A selected, the Mac staged all
five diagnostic images and verified the 8,192-byte
`vendor_boot_b` payload.

The diagnostic verified the 42-partition read-only UFS
inventory, passed the 8 KiB `boot_b` comparison, retired the
temporary SCSI host and reached the authenticated USB receiver.
All seven initial AP client votes were `0`. The same LPCM
GET_RATE request (`0x03042302`, argument `0`) produced these
replies in one boot.

| BE power state | Firmware reply |
| --- | --- |
| Early unpowered query | `-3` |
| After wrapper and BE ON readbacks of `1` | `356000000` (356 MHz) |

Both ON requests returned deferred acknowledgement `5`,
completed, and read back `1`. After GET_RATE, BE OFF
returned immediate acknowledgement `0` and read back `0`
at 10.452104 seconds of kernel uptime. The wrapper OFF
acknowledgement followed at 10.452204 seconds with status
`0`, and the wrapper read back `0` at 10.452436 seconds.
All four vote requests completed successfully. CPM reported
the powered BE rate. Physical clock and scanout measurements
remain open.

The independent warm restart was requested at 600.009461
seconds of kernel uptime. Fastboot returned 642 seconds after
the B boot request. Stock D1 A completed boot with enforcing
verity and the original VBMeta digest. Ramoops and
`SYSTEM_LAST_KMSG` matched all 45 filtered lines.

##### Offline DPU FE0 power-vote fixture

Both retained D1 base trees place `DpuFe0.v` (resource
`0x201`) under `DpuBe.v` and place FE1 under FE0. Earlier
live queries resolved `DpuFe0.v` to handle `0x15c0028`.
The FE0 clock uses LPCM `0x23`, clock `0x05`, and the
earlier unpowered GET_RATE `0x03052302` returned `-3`.

Kernel `7.3.0-rc6-omamobile-grizzly-display-fe0` at
`74843513bb91f16298fb93ede4d831bf460096bc` enables
`clk_google_malibu_cpm.display_fe0=1` with the tested
Grizzly wrapper and BE flags. The trigger checks the seven
initial votes and runs wrapper ON, BE ON, FE0 ON, FE0 OFF,
BE OFF, then wrapper OFF. It checks acknowledgement and vote
readback at each step. The cycle stops on a failed transition.
If FE0 release is unconfirmed, it leaves BE and the wrapper
voted on for the timed return. FE1 stays gated by the initial
vote check and receives no write.

This fixture keeps the early unpowered clock queries and
leaves both powered clock reads out of the vote window to
isolate FE0. Clock gates and display consumers remain disabled.
The vendor boot images and DTBO match the tested BE rate fixture
byte for byte, preserving the storage guard, USB SSH and timed
return.

The arm64 build and style check passed. A mock verified all
six transitions, every inherited vote and initial read failure,
failure at each transition, one-shot enforcement, and the
wrapper-only and powered BE paths. All five image hashes, both
AVB signatures, the ABL handoff bounds and captured D1 slot
fit passed. The `SHA256SUMS` digest is
`3a840d5521bc42765cc41afa1a65807ae71dc5c450304f6bad974f769d7b20ac`.

##### Attended DPU FE0 power-vote trial

On 2026-11-26 the guarded rescue copied all nine NV partitions
read-only and unmounted. The Mac independently verified all
nine SHA-256 hashes, 3,392,151,552 bytes and private permissions.
The full 64 MiB rescue `vendor_boot_b` readback matched.
After the rescue returned to Fastboot, the Mac staged all
five FE0 images and verified the 8,192-byte `vendor_boot_b`
payload.

The diagnostic verified the 42-partition read-only UFS
inventory, passed the 8 KiB `boot_b` comparison, retired the
temporary SCSI host and reached the authenticated USB receiver.
The AP client votes for `dpu.v`, `DpuBe.v`, `DpuFe0.v`,
`DpuFe1.v`, `DpuDsi0.v`, `DpuDsi1.v` and `DpuDp0.v`
were all initially `0`. FE0 resolved to handle `0x15c0028`
and used resource `0x201`.

| Request in execution order | CPM acknowledgement | Vote readback | Driver result |
| --- | --- | --- | --- |
| Wrapper ON | `5` (deferred, completion received) | `1` | `0` |
| BE ON | `5` (deferred, completion received) | `1` | `0` |
| FE0 ON | `5` (deferred, completion received) | `1` | `0` |
| FE0 OFF | `0` (immediate) | `0` | `0` |
| BE OFF | `0` (immediate) | `0` | `0` |
| Wrapper OFF | `0` (immediate) | `0` | `0` |

The full cycle ran from 9.450635 to 9.454547 seconds of kernel
uptime. The early unpowered FE0 GET_RATE again returned
firmware `-3`. Powered FE0 clock readback remains open.

The independent warm restart was requested at 600.009960
seconds of kernel uptime. Fastboot returned 642 seconds
after the B boot request. Stock D1 A completed boot with
enforcing verity and the original VBMeta digest. Ramoops and
`SYSTEM_LAST_KMSG` matched all 51 filtered lines.

##### Offline powered DPU FE0 clock diagnostic

Kernel `7.3.0-rc6-omamobile-grizzly-display-fe0-rate` at
`583e5c71ad1ae86b3a3ecdcfef605a3e93d69f49` adds the opt-in
`clk_google_malibu_cpm.display_fe0_rate=1` flag. It keeps the
early unpowered readings and the seven initial vote checks.
After the wrapper, BE and FE0 ON requests complete with
readbacks of `1`, the fixture sends one LPCM GET_RATE request
(`0x03052302`, argument `0`) with the one-second timeout.
The separate powered BE query stays disabled for this fixture.

A firmware reply, including a negative one, allows FE0, BE
and the wrapper to release in that order with vote readback.
A transport error stops further requests and leaves recovery
to the independent timed return. The fixture leaves the clock
gates and display consumers disabled.

The arm64 build and style check passed. A mock verified the
request order, positive, zero and negative firmware replies,
transport timeout, vote failures, inherited-vote and sampling
guards, repeat-trigger rejection, and the prior BE and FE0
paths. The five image hashes, both AVB signatures, handoff
bounds and saved D1 slot fit passed. The vendor boot images
and DTBO match the live-tested FE0 bundle byte for byte,
preserving the UFS guard, USB SSH and timed return. The
`SHA256SUMS` digest is
`45c7945c8599cc038e0b61d3deec74cef820742086d1fddc4ac7b5c8682d587c`.

##### Attended powered DPU FE0 clock trial

On 2026-11-26 the guarded rescue copied all nine NV
partitions read-only and unmounted. The Mac independently
verified all nine SHA-256 hashes, 3,392,151,552 bytes and
private permissions. The full 64 MiB rescue `vendor_boot_b`
readback matched. After the rescue returned to Fastboot, the
Mac staged the five diagnostic images and verified the
8,192-byte `vendor_boot_b` payload.

The diagnostic verified the 42-partition read-only UFS
inventory, passed the 8 KiB `boot_b` comparison, retired the
temporary SCSI host and reached the authenticated USB receiver.
All seven initial AP client votes were `0`. The same LPCM
GET_RATE request (`0x03052302`, argument `0`) returned `-3`
before power-up and `356000000` (356 MHz) after the wrapper, BE
and FE0 all read back `1`. The powered reply arrived at
10.456824 seconds of kernel uptime. This is the CPM-reported
rate. Physical clock and scanout measurements remain open.

All three ON requests returned deferred acknowledgement `5`
and completed. After the powered reply, FE0, BE and the wrapper
released in that order. The OFF acknowledgements were `0` and
the vote readbacks were `0` at 10.457081, 10.457370 and
10.457703 seconds. All six vote requests returned success.

The warm restart was requested at 600.009586 seconds of kernel
uptime. Fastboot returned 643 seconds after the B boot
request. Stock D1 A completed boot with enforcing verity and
the original VBMeta digest. Ramoops and `SYSTEM_LAST_KMSG`
matched all 52 filtered lines.

##### Offline DSI0 power-vote fixture

Both retained stock D1 base trees identify `DpuDsi0.v` as
resource `0x203` under `DpuBe.v`. Earlier live queries
resolved the DSI0 handle to `0x15c002a`.

Kernel `7.3.0-rc6-omamobile-grizzly-display-dsi0` at
`c8dd5c7184e0e0f09c9511c3102cb384182078fa` adds the opt-in
`clk_google_malibu_cpm.display_dsi0=1` flag. The fixture
enables it with the Grizzly wrapper and BE flags. The one-shot
trigger checks all seven initial AP votes. With all seven
clear, it requests wrapper ON, BE ON, DSI0 ON, DSI0 OFF,
BE OFF, then wrapper OFF. Each step checks the CPM reply and
vote readback, including deferred completion where applicable.
If a transition fails, the fixture stops without retry. An
unconfirmed DSI0 transition leaves the parent votes in place
for the independent timed return.

The fixture keeps the early read-only clock queries. It
isolates DSI0 by leaving the FE0 cycle, powered rate queries,
display clock gates, DSI host, PHY and panel disabled. The
vendor boot images and DTBO are byte identical to the
live-tested powered FE0 fixture and preserve the UFS guard,
USB SSH and timed return.

The arm64 build and style check passed. A mock verified all
six transitions, inherited votes, failure of each initial
sample and transition, repeat-trigger rejection and the
prior wrapper, BE and FE0 paths. All five image hashes, both
AVB signatures, ABL handoff bounds and saved D1 slot fit
passed. The `SHA256SUMS` digest is
`6ea2ff8095ede05e1fc1473ec9e44f7d3343c8b5a3f13331f6b58bf656fc613a`.

##### Attended DSI0 power-vote trial

On 2026-11-26 the guarded rescue copied all nine NV
partitions read-only and unmounted. The Mac independently
verified all nine SHA-256 hashes, 3,392,151,552 bytes and
private permissions. The full 64 MiB rescue `vendor_boot_b`
readback matched. After the rescue returned to Fastboot, the
Mac staged all five DSI0 diagnostic images and verified the
8,192-byte `vendor_boot_b` payload.

The diagnostic verified the 42-partition read-only UFS
inventory, passed the 8 KiB `boot_b` comparison, retired the
temporary SCSI host and reached the authenticated USB receiver.
All seven initial AP client votes were `0`. DSI0 resolved to
handle `0x15c002a` and used resource ID `0x203`.

| Request in execution order | CPM acknowledgement | Vote readback | Driver result |
| --- | --- | --- | --- |
| Wrapper ON | `5` (deferred, completed) | `1` | `0` |
| BE ON | `5` (deferred, completed) | `1` | `0` |
| DSI0 ON | `5` (deferred, completed) | `1` | `0` |
| DSI0 OFF | `0` (immediate) | `0` | `0` |
| BE OFF | `0` (immediate) | `0` | `0` |
| Wrapper OFF | `0` (immediate) | `0` | `0` |

The early unpowered DSI0 pixel clock GET_RATE (`0x03012302`)
returned `-3`. The powered pixel clock query and DSI host,
PHY and panel bring-up remain open.

The warm restart was requested at 600.009881 seconds of kernel
uptime. Fastboot returned 642 seconds after the B boot
request. Stock D1 A completed boot with enforcing verity and
the original VBMeta digest. Ramoops and `SYSTEM_LAST_KMSG`
matched all 51 filtered lines.

##### Offline powered DSI0 pixel clock diagnostic

Both retained D1 base trees place `dpu_dsi0_pix_clk` at LPCM
`0x23`, clock `0x01`. The previous unpowered GET_RATE returned
`-3`. Kernel `7.3.0-rc6-omamobile-grizzly-display-dsi0-rate` at
`17160cba1f659f350447ce9c70a74ae1555e600d` adds the opt-in
`clk_google_malibu_cpm.display_dsi0_rate=1` flag to the tested
DSI0 vote sequence. It preserves the early clock queries and
the seven initial vote checks. After wrapper, BE and DSI0 all
read back `1`, the fixture sends one LPCM GET_RATE with word
`0x03012302`, argument `0` and the one-second timeout.

The fixture logs the signed firmware reply or transport error.
A firmware reply, including a negative one, allows DSI0, BE
and wrapper to release in that order with vote readback. A
transport error stops further requests and leaves recovery to
the independent timed return. The fixture leaves clock gates,
the DSI host, the PHY and the panel disabled. A positive reply
would report the firmware rate. Physical clock and scanout
measurements remain open.

The arm64 build and style check passed. Mocks verified the
exact request and order, positive, zero and negative firmware
replies, transport errors, failed transitions, inherited vote
and sample guards, repeat-trigger rejection and the previous
BE and FE0 queries. The five image hashes, both AVB signatures,
handoff bounds and saved D1 slot fit passed. Both vendor boot
images and DTBO match the live-tested DSI0 fixture byte for
byte, preserving the UFS guard, USB SSH and timed return. The
`SHA256SUMS` digest is
`9f762f96e64da6e915b75770563fe8214974d48895987a92ac921d126f21b62d`.

##### Attended powered DSI0 pixel clock trial

On 2026-11-26 the guarded rescue copied all nine NV
partitions read-only and unmounted. The Mac independently
verified all nine SHA-256 hashes, 3,392,151,552 bytes and
private permissions. The full 64 MiB rescue `vendor_boot_b`
readback matched. After the rescue returned to Fastboot, the
Mac staged the five diagnostic images and verified the
8,192-byte `vendor_boot_b` payload.

The diagnostic verified the 42-partition read-only UFS
inventory, passed the 8 KiB `boot_b` comparison, retired the
temporary SCSI host and reached the authenticated USB receiver.
All seven initial AP client votes were `0`. The same LPCM
GET_RATE request (`0x03012302`, argument `0`) returned `-3`
before power-up and `150000000` (150 MHz) after wrapper, BE and
DSI0 all read back `1`. The powered reply arrived at 9.457798
seconds of kernel uptime. This is the CPM-reported rate.
Physical clock, DSI link and scanout measurements remain open.

All three ON requests returned deferred acknowledgement `5`
and completed. After the powered reply, DSI0, BE and wrapper
released in that order. The OFF acknowledgements were `0` and
the vote readbacks were `0` at 9.458050, 9.458339 and 9.458672
seconds. All six requests returned success.

The warm restart was requested at 600.010182 seconds of kernel
uptime. Fastboot returned 642 seconds after the B boot
request. Stock D1 A completed boot with enforcing verity and
the original VBMeta digest. Ramoops and `SYSTEM_LAST_KMSG`
matched all 52 filtered lines.

##### Offline DSI0 host access prerequisites

Both stock D1 Grizzly B0 merges translate
`dsi2host@3d8000` to physical `0x0f7d8000`, size `0x800`,
and attach `DpuDsi0.v` with BE and wrapper parents. The host
has a PHY link and no clock or reset phandles. The PHY's
38.4 MHz `pllref` and LPCM DSI0 pixel clock are separate
from the host's APB clock.

In the D1 `mipi-dsi2h.ko`, `dw_mipi_dsi2h_probe` sets up
MMIO regmap with a null clock name (text `0x2310`). It
calls `phy_init` (`0x24e0`), then enables runtime PM. The
D1 G301 D-PHY init reads PHY offset `0x7124` bit 8 before
saving the result in software. The host probe reads core ID
and version at host offsets `0x00` and `0x04`. The handoff
status query follows a successful `pm_runtime_resume_and_get`
(`0x267c`) and reads bit 0 at host offset `0x0c`
(`0x2694`). The module's regmap field and debugfs label identify
that bit as `pwr_up`. It describes the host's internal enable
state and gives no independent APB or external reset evidence.
The stock glue's initial runtime resume exits without host
programming because the core pointer is assigned
only after the core probe returns. The retained stock bugreport
logs ID `0x30313130`, version `0x1a000110` and handoff
`dt=0 reg=0`.

The host and glue expose no separate APB clock or reset
operation before that status query. The D1 legacy
`lpm_pm_domains.ko` contains DSI state polling, but neither
stock Grizzly merge binds its DPU compatible or assigns the
expected LPCM resource. The tested MBFS client votes and
150 MHz LPCM reply establish the voted power chain and the
firmware-reported pixel rate. The APB clock and reset state
for a mainline MMIO read remain unverified. A future stock
trace can capture the existing `regmap_reg_read` at offset
`0x0c` alongside genpd and runtime PM events without adding a
host read. A mainline read still needs independently qualified
access prerequisites.

Kernel `7.3.0-rc6-omamobile-grizzly-display-dsi0-host` at
`16a63b142e0bf13855b78a7c24dd381444320956` builds a
prerequisite-only fixture. The opt-in
`clk_google_malibu_cpm.display_dsi0_host=1` uses the guarded
wrapper, BE and DSI0 vote sequence and the known pixel GET_RATE.
It logs that host status was skipped because the APB clock and
reset remain unverified. It performs no host MMIO, clock-gate
writes or reset requests. DSI0, BE and wrapper release in
reverse order after a firmware reply. The independent timer
covers the existing fail-stop path.

The arm64 build, style check, vote and release mocks, five
image hashes, AVB signatures, ABL handoff bounds and saved D1
slot fit passed. The vendor boot images and DTBO are byte
identical to the tested DSI0 rate fixture, preserving the UFS
guard, USB SSH and timed return. The `SHA256SUMS` digest is
`f68686c9fc117351e65d00e7584a14329293ae55ee201c031affcf7275c24da7`.

##### Offline passive stock D1 DSI0 trace

The retained stock boot log reports `vs_mipi_dsi2h_resume:
bridge not ready` before the `dt=0 reg=0` handoff message.
That runtime resume returns before link programming. The
existing status read is still the stock driver's read of
`pwr_up` at host offset `0x0c`.

The exact D1 GKI has `CONFIG_BOOT_CONFIG=y` and
`CONFIG_BOOTTIME_TRACING` disabled. The kernel accepted an
offline bootconfig payload but created no ftrace instance.
Use [stock-dsi0-trace.sh](bringup/stock-dsi0-trace.sh) from
a privileged early caller after mounting proc and tracefs and
before releasing the stock display module loader. Pass the
tracefs mount and the retained rescue BusyBox executable.
The helper checks the D1 kernel release and refuses a loaded
`vs_drm` or `mipi_dsi2h` module or an existing trace instance.
The caller must serialize arming with the loader.

The helper arms a private `grizzly_dsi0` trace instance on
`mono` with 64 KiB per CPU. It filters `regmap_reg_read` to the
DSI0 host at offset `0x0c` and installs a one-shot stop trigger
for that same read. It captures `power_domain_target` for the
wrapper, BE and DSI0 domains, DSI0 runtime resume, return and
status events, and Common Clock Framework enable, disable and
rate events with DSI or DPU names. It loads no modules and sends
no register reads, power votes, clock or reset requests.

After the stock probe, confirm that the instance's
`tracing_on` file reports `0`, then copy its `trace` file to
the private host workspace. Run
`python3 device/grizzly/bringup/check-stock-dsi0-trace.py TRACE`
from the repository root. The checker rejects an overrun or
missing status read. It orders the retained target and clock
events and correlates the host read with a successful runtime
resume in the same task. Keep the raw trace private. Remove
the instance after capture.

The D1 kernel exposes Common Clock Framework events and no
host reset-control trace event. The DSI0 pixel clock and PHY
PLL reference do not identify a host APB gate. A reported
genpd target, runtime resume or `pwr_up` value supplies no
independent APB clock or external reset evidence. A missing
trace event also cannot rule out clock or reset actions inside
firmware.

An offline QEMU run used the unmodified D1 stock kernel and
verified all eight event filters, the one-shot trigger and
duplicate-instance rejection. Synthetic traces checked
successful correlation, same-timestamp ordering, overrun,
failed resume and missing status. QEMU has no Grizzly display
host.

##### Packaged early stock D1 DSI0 trace

`pack-stock-inventory.py --dsi0-trace` takes the audited D1 NV
rescue images as its `--factory` input. It uses the B0 base
DT merged with rescue DTBO entry 19 for its offline handoff
check. The packer retains the factory generic ramdisk prefix
and replaces the NV export overlay with the trace inventory.
It keeps the stock kernel, vendor boot images and rescue DTBO
byte for byte.

PID 1 verifies Grizzly slot B, sets the warm reset policy,
starts the existing 90-second return timer and disables
automatic module loading. The stock inventory manifest loads
UFS and the NV guard checks the nine partitions. Only then
does PID 1 arm the private trace. A successful arm is required
before it loads the seven audited display module dependencies
ending with stock `vs_drm.ko`. The manifest has no panel
module, and the instrumentation adds no hardware access of
its own. The stock display module still runs its own probes.

The first scoped register event stops tracing. PID 1 waits
up to eight seconds for that stop and copies the trace header
and scoped rows into the retained console with a `DSI0 trace`
prefix. Strip that prefix before running the host checker.
A failed arm blocks the display module load. A missing
capture or failed probe leaves the return timer running.

QEMU exercised the packaged trace helper and PID 1 functions
on the exact D1 kernel. The guest verified that the trace
and one-shot trigger were active before its simulated display
loader ran, that a pre-existing instance blocked loading and
survived that failure, and that the existing 90-second timer
invoked the warm restart command. The loader, captured status
and final restart were simulated in the guest. The retained
sample passed the host checker.

All five image hashes, the replacement `init_boot` AVB
signature, ABL handoff bounds and saved D1 slot fit passed.
The `SHA256SUMS` digest is
`38f1be9e60340b4c503ff5f97aaaa03acafa9296cc30aaa65c1996d73008b9f7`.
##### Attended passive stock D1 DSI0 trace

On 2026-11-26 the rescue copied all nine NV partitions
read-only and unmounted. The Mac independently checked all nine
SHA-256 hashes, 3,392,151,552 bytes and private permissions. The
full 64 MiB `vendor_boot_b` readback matched both the rescue
and the subsequent five-image DSI0 trace bundle.

The trace boot registered the 90-second return timer at
0.850023 seconds of kernel uptime and passed the NV guard.
Trace arming was logged at 5.773670 seconds, before the first
display module at 5.776306 and `vs_drm.ko` at 5.860501.
The trace ring retained all nine records. These are its
host-resume and read timestamps.

| Monotonic time (s) | DSI0 trace event |
| ---: | --- |
| 5.917018 | Runtime resume entered |
| 5.917020 | `RPM_RESUMING` |
| 5.917039 | `RPM_ACTIVE` |
| 5.917040 | Runtime resume returned `0` |
| 5.917043 | Existing regmap read at `0x0c` returned `0x00000000`, `pwr_up=0` |

The resume and read came from the same task. The stock driver
also reported core ID `0x30313130`, version `0x1a000110`,
`bridge not ready`, and handoff `dt=0 reg=0`. The scoped
ring had no matching genpd target or CCF clock event. This
capture correlates the host read with runtime PM. It leaves
the genpd transition timing, host APB clock and external
reset state unverified.

The warm restart was requested at 90.851713 seconds of
kernel uptime. Fastboot returned 134 seconds after the
B boot request. Stock D1 A completed boot with enforcing
verity and the original VBMeta digest. Ramoops and
`SYSTEM_LAST_KMSG` matched the filtered capture.

##### Offline DSI0 genpd and MBFS trace follow-up

The passive trial captured the existing host read and its
successful runtime resume. Its nine-entry ring contained
zero matching `power_domain_target` or CCF clock events.
The follow-up keeps those filters and adds the stock
`power_controller` events `send_mail_mbfs` and
`recv_result_mbfs`. Both trace event field tables in the
audited D1 module expose `pm_resource_id` as a 32-bit field.
The filters select wrapper `0x08`, BE `0x200` and DSI0
`0x203`. The host checker reports match timestamps, requests
and stock driver return values before the `pwr_up` read.

After the NV guard and trace arm, PID 1 also samples the
three named genpd `current_state` files from read-only
debugfs before display modules load. The log records each
validated state or `unavailable`. This can distinguish a
domain already on from one with an observed probe-time
vote. A missing snapshot leaves the trace running. Missing
MBFS trace support fails arming before display load. The
one-shot stop, NV guard and independent 90-second return
remain in place. The instrumentation adds no power or
clock requests and no host register access.

In QEMU, the exact D1 kernel accepted the resource filter
against a synthetic event with the same field type. The
stock helper kept a pre-existing instance and removed a
partial instance when the vendor events were absent.
Offline parser checks replayed the retained physical trace,
correlated synthetic MBFS events with it and rejected a
malformed reply. The trace exposes software votes and
genpd state. The APB gate and external reset state require
separate evidence.

The packaged sequel uses `pack-stock-inventory.py --dsi0-trace`.
The five hashes, replacement `init_boot` AVB signature, ABL
handoff bounds and saved D1 slot fit passed. The remaining
four images match the attended passive fixture byte for
byte. The `SHA256SUMS` digest is
`e085554efae30ea3980af98ae9e2c27241fff8ad63872ad9ef0afdd15256dfcd`.

##### Attended stock D1 DSI0 genpd and MBFS trace

On 2026-11-26 the read-only rescue copied all nine NV
partitions. Independent SHA-256 checks, the byte count of
3,392,151,552 and private permissions passed. The full
64 MiB `vendor_boot_b` readback matched for both the rescue
and the one slot B diagnostic boot.

The 90-second timer armed at 0.926461 seconds of kernel uptime.
After the NV guard passed, tracing armed at 5.779560 seconds.
Before the first display module loaded, read-only debugfs
reported `off-0` for `sswrp_dpu_pd`, `dpu_be_pd` and
`dpu_dsi0_pd`. `vs_drm.ko` began loading at 5.891762 seconds.

The stopped trace retained all 39 records, including 15
stock MBFS request/result pairs. Every result was `0`.
Earlier activity included a complete wrapper, BE and DSI0
ON/OFF cycle, then shorter parent sequences. The final ON
requests and results came from the same task as the host
probe. All times in the table are trace `mono` seconds.

| Event | Request | Result |
| --- | ---: | ---: |
| Wrapper ON (`0x08`) | 5.934103 | 5.935494 |
| BE ON (`0x200`) | 5.935526 | 5.935896 |
| DSI0 ON (`0x203`) | 5.935900 | 5.936410 |
| DSI0 runtime resume | 5.947687 | 5.947707 |
| Host offset `0x0c` read | 5.947711 | `0x00000000` (`pwr_up=0`) |

Runtime resume returned `0` four microseconds before the
status read. The final DSI0 ON result preceded the read by
11.301 ms. There were no matching generic genpd target or CCF
events in that ring. The snapshot and MBFS records show
the stock software power sequence. APB clock and external
reset state remain unverified.

The warm restart was requested at 90.929965 seconds of
kernel uptime. Fastboot returned 133 seconds after
the B boot request. Stock D1 A completed boot with enforcing
verity and the original VBMeta digest. Ramoops and
`SYSTEM_LAST_KMSG` matched the filtered capture.

##### Offline stock D1 DSI0 clock and reset trace

The D1 B0 merge with DTBO entry 19 gives the DSI0 host a
`DpuDsi0.v` power domain and the D-PHY. The host has no
clock or reset consumer phandle. The stock host opens its
MMIO regmap with a null clock name, reads the core ID and
version, and reads `pwr_up` after runtime resume. The host
probe and the first glue resume issue no separate clock or
reset request. The G301 PHY's reset callback only logs and
returns success. The DSI0 pixel clock is a separate LPCM
`0x23` clock at selector `0x01`. The DPU channel clock
uses LPCM `0x2a`, selector `0x00`. The stock CPM clock
table has no identified DSI0 APB gate and the CPM reset
provider has no display LPCM `0x23` child.

The two stock providers already load in the UFS inventory.
`clk-cpm.ko` sends its native mailbox commands through
`goog_cpm_clk_send_mba_mail`, while `rst-cpm.ko` uses
`goog_cpm_rst_send_mba_mail`. The D1-only `--apb-reset`
trace checks that both symbols are loaded, then attaches
entry and return probes before display modules load. It
records the existing LPCM ID, selector, operation and
provider return value from the audited ARM64 arguments and
RAM-backed structures. The host checker pairs calls and
returns by task and provider, reports display LPCM and DPU
channel clock activity, and retains the earlier MBFS and
runtime PM correlation. Existing host reads at offsets
`0x00`, `0x04` and `0x0c` give ID, version and
`pwr_up` on the same timeline.

The existing `pack-stock-inventory.py --dsi0-trace` mode
packages this follow-up. It arms after the NV guard and
stops on the first `pwr_up` read. The capture requires the
arm marker, no missed probes and one status read. The host
checker rejects trace ring loss. Missing providers or an
arming failure block display loading. The 90-second warm
return remains independent. The instrumentation issues no
hardware reads, clock operations or reset operations of
its own.

Matching ID `0x30313130` and version `0x1a000110` show
the APB interface was responding by those reads. The
provider probes can show whether an AP-issued clock or reset
request completes first. CPM-internal gate and reset
transitions during MBFS power-on remain unobservable with
the stock D1 firmware trace policy described above. An empty
provider trace applies only to the captured AP-side window.

The exact D1 kernel and vendor modules accepted all four
probes in QEMU, rejected missing providers and duplicate
arming, and cleaned up before a successful rearm. The
checker passed the retained hardware trace and synthetic
clock/reset pairs, zero-event, malformed and loss cases.
All five image hashes, the replacement `init_boot` AVB
signature, ABL handoff bounds and saved slot fit passed.
The other four images match the prior stock diagnostic.
The bundle `SHA256SUMS` digest is
`8fe724b47507e4622d547d6eb88aeb466f8b1f57611b0a174d2b529eb39ece8d`.

##### Attended stock D1 DSI0 clock and reset trace

On 2026-11-26 the read-only rescue copied all nine NV
partitions. Independent checks verified the hashes,
3,392,151,552 bytes and private permissions. The full 64 MiB
`vendor_boot_b` readback matched for the rescue and the
single diagnostic boot.

The trace armed before the display modules loaded. All
three display domains were `off-0` in the pre-load
snapshot. PID 1 checked the probe profile and completed
the trace and NV guard. The ring retained all 42 records,
including 15 MBFS request/result pairs with every result
`0`. The final power sequence and host reads used the
same task. Times below use the trace's monotonic clock.

| Time (s) | Event | Result |
| ---: | --- | --- |
| 6.402408 | Wrapper ON result | `0` |
| 6.402716 | BE ON result | `0` |
| 6.402993 | DSI0 ON result | `0` |
| 6.411881 | Host ID at `0x00` | `0x30313130` |
| 6.411885 | Host version at `0x04` | `0x1a000110` |
| 6.413203 | Runtime resume result | `0` |
| 6.413207 | Status at `0x0c` | `0x00000000`, `pwr_up=0` |

There were zero clock or reset provider calls or replies
between the arm marker and `pwr_up`. The host ID and
version show effective APB access 8.888 ms after the DSI0 ON
reply and before runtime resume. The individual CPM-internal
APB gate and external reset transitions remain unobserved.

The 90-second warm return requested restart at 90.901349
seconds of kernel uptime. Fastboot returned 134 seconds
after the B boot request. Stock D1 A completed boot with
enforcing verity and the original VBMeta digest. Ramoops and
`SYSTEM_LAST_KMSG` matched, including the full scoped trace.

##### Offline stock D1 and mainline DSI0 power comparison

Stock D1 and the mainline diagnostic use the same CPM
mailbox pair at `0x0ea60000` and `0x0ea61000`, MBFS
service `0x14`, and `syspm/clients/vm1` vote tree. The
stock `power_controller.ko` calls `mbfs_write_file` with
the handle and vote. Its payload matches mainline's
`{ 0x80000000 | handle, on, 0 }` with a 28-bit handle.
Both wait for client `7` notifications keyed to the full
resource ID when CPM returns deferred status `5`. The
stock trace reports the driver's final result after any
wait. Only mainline's retained log shows the raw status.
Stock's final ON sequence also follows earlier probe-time
ON/OFF cycles that the mainline one-shot test does not run.

| Step | Stock D1 | Mainline powered DSI0 fixture |
| --- | --- | --- |
| Pre-vote state | Wrapper, BE and DSI0 genpd report `off-0` before module load | All seven display client votes read `0` before the cycle |
| Final ON sequence | Wrapper `0x08` → BE `0x200` → DSI0 `0x203`; all three return `0` | Same order and IDs; all three complete deferred status `5` and read back `1` |
| Consumer path | Stock attaches both the host and PHY to DSI0 genpd. PHY init reads offset `0x7124` bit 8 and stores it in software. The host then reads ID and version, resumes, and reads `pwr_up`. | No DSI0 host or PHY node in the fixture DT. The vote cycle queries the DSI0 pixel rate, then releases DSI0 → BE → wrapper. |
| Access evidence | Expected host ID appears 8.888 ms after the final DSI0 ON result. No AP clock or reset provider event precedes it. | The pixel GET_RATE replies 150 MHz. DSI0 OFF is acknowledged 145 µs after the ON result. |

The matching votes qualify the CPM request path. A client
vote readback and the pixel rate do not read the host APB
gate or external reset. Stock's PHY access supplies evidence
from its own consumer path. The gap from its ON reply to its
first host read includes probe work, so it does not establish
a minimum wait or a readiness deadline for mainline. Before
adding a mainline host read, establish a firmware ordering
guarantee or an independently qualified clock and reset
status check outside the target DSI0 aperture.

The offline comparison leaves the prerequisite-only fixture
at `16a63b142e0b` in place. Its five image hashes match and
its vendor boot images and DTBO match the tested powered-rate
fixture. The UFS read-only guard, post-guard trigger and
independent 600-second warm return remain in that bundle.
The host ID, version and `pwr_up` MMIO reads stay disabled.

##### Offline D1 CPM completion and external status audit

The prior D1 firmware audit used factory build
`CP4A.261105.040.D1` and bootloader `spacecraft-17.4-16729013`.
Its CPM image and extracted text were missing at this stage.
The saved D1 firmware analysis identifies the
generic MBFS vote handler and shows that an already-active
resource can accept another caller's vote without scheduling a
new physical transition. The saved disassembly does not cover
the DSI0-specific `0x203` callback through deferred completion.
The stock trace shows valid DSI0 host reads after the final ON
result, with no intervening AP clock or reset provider request.
That leaves the ordering of the firmware's completion, APB gate
and external reset unresolved.

| Candidate outside the DSI0 host | D1 evidence | What it can establish |
| --- | --- | --- |
| Stock `powerdashboard/pwrblk_dpu` | `google_powerdashboard.ko` `pwrblk_dpu_show` (`0x82c`) reads firmware shared-memory section 1 and formats DPU block 7 with six rows. | The wrapper row tracks the aggregate vote. The five child labels have no verified mapping to DSI0 PSM3, the APB gate or external reset. |
| Stock `powerdashboard/lpcm_dpu` and CPM clock provider | `lpcm_dpu_show` (`0x161c`) reads section 2, index 16, for the DPU operating point. The clock provider has no identified DSI0 APB gate getter. | Operating-point or configured-rate telemetry. |
| Stock `latency_stats/dpu_dsi0_pd/ack_on` | `power_controller.ko` stops the acknowledgment timer immediately after the MBFS write returns, before the deferred completion wait. | Timing and count of synchronous replies. |
| Stock CPM reset provider | `rst-cpm.ko` supplies assert and deassert operations; the merged tree has no reset child for display LPCM `0x23`. | No read-only display reset status operation was identified. |
| Legacy DPU power-state poll | `lpm_pm_domains.ko` `poll_for_dpu_dsi_state` (`0x216c`) reads provider base plus `0x1018` and tests the low nibble. The D1 merge has no `google,mbu-dpu-lpm-pm-domains` binding. | A lead for the legacy controller. Its D1 AP mapping, safe access and separate gate/reset meanings are unverified. |

The dashboard read path uses the stock driver's CPM-published
shared-memory section, outside the target host aperture. It
can help correlate a DPU transition, but cannot gate a host
read until the relevant row and both readiness conditions are
mapped. The legacy status offset is unqualified for a D1 AP
load. Recovering the exact firmware would allow the next
offline comparison to follow resource `0x203` into its
sequencer and locate any gate/reset status providers before
the completion notification. The existing host-read hold
remains in effect.

##### Exact D1 DSI0 completion and status paths

The downloaded Grizzly `CP4A.261105.040.D1` factory archive
matched Google's SHA-256. The bootloader member matched the
separate range extraction byte for byte. Its FBPK entry
contains CPM at offset `0x10aa000`, length `0x9c000`. The
extracted CPM SHA-256 is
`77347069aae56f1acc30bdf1a371315d195ef09b59e4c6d3832e19b37052cc84`.
The CPM disassembly addresses below are relative to text at
image offset `0x50d0`.

1. The MBFS resource table at `0x64040` maps `0x203` to
   ordinal 42. The power group at `0x200132f0` starts at
   ordinal 39, giving local index 3. Its ON dispatcher at
   `0x467bc` uses a cached state check and queues the worker
   at `0x46644`.
2. The worker calls `0x1d06c` for member 3. The member's ON
   callback `0x45364` dispatches through `0x45178` and
   `0x39b0c` to the LPCM `0x23` PSM3 ON handler at
   `0x3a3f0`. PSM3 states 0 and 1 already satisfy this
   handler. It requests 2 → 0 or 3 → 1 through `0x8248`.
   Both transitions set mask `0x0c` at CPM `0x6f40a000`,
   then the common transition code polls the descriptor-derived
   PSM3 status. The mask requests the hardware transition.
   Its individual clock and reset effects are unresolved.
3. The PSM poll records `-1` for faults at `0x80b8`–`0x80be`.
   The ON handler discards a returned transition error at
   `0x3a416`, and the member callback returns zero.
   `0x1d06c` then caches ON and the worker passes completion
   onward through `0x45eb0` and `0x27830`.
   The deferred completion path advances the pending vote
   and queues the client 7 notification. The per-client
   branch `0x28978` → `0x26488` performs no new hardware
   status read.
   A hard poll timeout follows a separate fatal path from
   `0x855c` to `0x22258` and does not reach completion.

Completion therefore cannot certify that the APB gate opened
and external reset released. The APB clock has a separate
descriptor from the pixel clock. D1 ABL names it
`dpu_dsi0_apb_clk` at file offset `0x1f51b0`, with group 4,
gate offset `0x6e0`, and no mailbox selector. ABL's group
base is AP `0x0f419000`. Its direct clock helper polls
gate + `0x1c` bit 8, giving APB acknowledgment at
`0x0f4196fc`. The D1 GC rule for that AP page is
`0x30300`, unlike the `0x30301` PSM pages previously
sampled from Linux. This gate word is unqualified for an
EL1 read. The CPM clock status service covers DSI0 pixel
selector 1, whose gate is separate. The CPM read-only reset
helper's descriptor lookup excludes display LPCM `0x23`.
The LPCM power service's operation 3 reads a software
request cache. No read-only status for the host's external
reset was mapped.

PSM3 is a separate read-only observation candidate. CPM
`0x87c0` → `0x7f90` → `0x1942c` and ABL's AP-side
decoder resolve the status word from the LPCM controller
header and the PSM3 descriptor at base + `0x28`. ABL maps
the DPU LPCM base to AP `0x0f409000`; GC assigns that
header page `0x30301`. The descriptor-derived word can
land under several GC rules. Any future diagnostic needs a
powered wrapper, an audited descriptor and confirmation of
effective EL1 access to the exact word. Before and after
PSM samples can show a sequencer state change alongside the
vote. They still leave the separate APB gate and external reset
conditions unqualified. The mainline host reads stay disabled.

##### Offline DPU PSM3 address and EL1 access audit

The exact D1 CPM and ABL decoders agree on the layout. ABL
maps the controller to AP `0x0f409000`. The controller word's
bits 13:8 must report at least four PSMs. The PSM3 descriptor
is the 32-bit word at `0x0f409028`. For descriptor `d`, CPM
`0x1942c` and `0x40c80`–`0x40cf2` compute the status address
as follows.

```text
0x0f409000 + ((d & 0xf) << 12) + ((d >> 12) & 0x1f0)
           + 0x64 * ((d >> 4) & 0xf) + 0x20
```

The exact DPU initializer selected by CPM `0x11e0` starts at
text `0x5c814`. Its 17 records leave the controller header
and PSM3 descriptor untouched. The audit also checked the
other packed LPCM initializers for overlapping writes. No
retained D1 stock bugreport or DSI0 trial log contains the
descriptor or a Linux access to the resulting word. ABL's
generic PSM getter establishes the AP decoder. Its identified
stock caller reads the HSIO-S UFS state, leaving the DPU word
without a stock read witness.

An exhaustive check of the 8,192 address-field combinations
gave aligned status words from `0x0f409020` to `0x0f4187ec`.
They span the following trusted-firmware GC page rules.

| Candidate pages | D1 GC rule |
| --- | --- |
| `0x0f409000`, `0x0f40b000`–`0x0f410000`, `0x0f412000`–`0x0f413000` | `0x30301` |
| `0x0f40a000`, `0x0f411000` | `0x30303` |
| `0x0f414000`–`0x0f418000` | `0x300` |

The header and descriptor share the `0x30301` page at
`0x0f409000`. That rule describes static policy. In v37,
a different AP word with the same rule raised an EL1 SError
after the wrapper and controller checks passed. Here the
actual DPU descriptor, the exact status word and its access
while the wrapper is held remain unqualified. Leave both the
descriptor and status reads out of the boot fixture. The
verified prerequisite-only fixture retains the NV guard and
independent 600-second return.

##### Offline DPU PSM3 power-dashboard audit

The exact D1 stock dashboard module asks CPM client `0x68`
for section 1 and maps the AP address returned by firmware.
CPM's section table at `0x607c4` and initializer `0x1e348`
place the section at CPM `0x400210d0`. Its ABI length is
`0xd68` bytes. The stock module compares repeated copies
of the section to detect concurrent updates. It formats DPU
block 7 as a wrapper row and five rows labeled `psm[0]`
through `psm[4]`.

CPM `0x20358` maps DPU wrapper LPB `0x08` to block 7.
The vote update at `0x1f7b2`–`0x1f7be` calls the
dashboard writer `0x1e8f0`. Its category-0 resolver
`0x1e518` → `0x1ffa4` selects the first DPU record
at section offset `0x19b`. That record stores the aggregate
wrapper vote. The caller at `0x274d8` records the vote
before invoking the transition handler at `0x274e8`.
This writer does not select a DPU child row.

The successful hardware transition path calls `0x7538`
from `0x84de` with the LPCM ID, PSM index and target state.
That helper updates a separate CPM-local statistics array
when present. For DPU LPCM `0x23`, the pointer at
`0x2000b438 + 0x44` is zero in the exact image's initialized
data. The helper exits immediately with a null pointer.
No producer was identified for a dashboard row tied to
the actual state of LPCM `0x23` PSM3. The DPU getter at
`0x3b8a8` has callers in the firmware display state handlers
and no identified AP-facing export. The retained stock
display bugreport reports the wrapper but contains no
`pwrblk_dpu` child observations.

Both stock D1 base DTBs configure a 100 ms dashboard
sampling interval. The mainline pixel-clock trial received
DSI0 OFF only 145 µs after the ON result. A periodic
publisher could miss that powered interval even if the
row mapping were established. The stock probe also sends
commands to configure and start sampling. A read from an
already bound dashboard only copies the published data.

Use the dashboard as wrapper-vote evidence. Leave the
PSM3 sampler and DSI0 host reads disabled. A sample would
require an identified PSM3 publisher with a timing guarantee
or a stock EL1 access witness for the exact status word.

##### Offline DSI0 acknowledgment and clock-status audit

The saved stock display bugreport includes a request to read
`/sys/devices/platform/power_controller/latency_stats/dpu_dsi0_pd/ack_on/count`.
In the exact D1 `power_controller.ko`, `set_power_state`
starts profiling at `0x47b4`, calls `mbfs_write_file` at
`0x487c` and stops the acknowledgment timer at `0x4894`.
The status-5 wait for deferred completion follows at
`0x48f0`. The `count` handler (`0x2378` → `0x263c`)
reads the accumulated sample count from RAM.

The deferred completion callback separately loads the
mailbox timing field at message offset `0xc` (`0x4638`),
passes it to the firmware timing bucket at `0x46cc`,
and wakes the waiter at `0x46ec`. Neither profiling path
accesses the APB gate or external reset status. The existing
`recv_result_mbfs` trace remains the observation of the final
vote result.

D1 ABL's clock table also distinguishes the DSI0 system
clock from both the APB and pixel clocks. All three records
use clock group 4 with distinct gate offsets.

| ABL clock record | File offset | Gate offset |
| --- | --- | --- |
| `dpu_dsi0_apb_clk` | `0x1f51b0` | `0x6e0` |
| `dpu_dsi0_sys_clk` | `0x1f5220` | `0x720` |
| `dpu_dsi0_pix_clk` | `0x1f5290` | `0x760` |

The three stock DSI0 trace captures and stock display
bugreport contain no access witness for APB acknowledgment
at `0x0f4196fc` or an external reset-status read. In the
clock/reset trace, stock reads the host ID and version
8.888 ms after the final DSI0 ON result. The interval
measures stock's observed ordering and supplies no minimum
settle time for mainline. Keep the host reads disabled
pending an independent readiness check.

##### Offline stock D1 DSI0 PHY init trace

The D1 B0 merge maps the first CD-PHY resource
(`cdphy-tx`) at AP `0x0f7c0000` and gives it the same
`DpuDsi0.v` power domain as the host. In exact D1
`mipi-cdphy.ko`, `dw_dphy_init_g301` calls
`regmap_read` at `0x2f0` using the first resource's
regmap and offset `0x7124`. It saves bit 8 in the
PHY instance. The host probe calls this callback via
`phy_init` before its host ID and version reads.

The `--dsi0-trace` bundle now includes that existing
PHY read in the tracefs filter. The checker correlates
it on the task that reads `pwr_up` and reports the raw
word and bit 8. The filter excludes DSI1. The NV guard
still precedes display module load and the independent
90-second return is preserved. The trace adds no
register accesses and cannot qualify a mainline read of
the host, APB gate or external reset.

Offline validation replayed the previous hardware capture
with identical output. A synthetic capture correlated a
DSI0 PHY read and rejected DSI1 and an unrelated task.
The four unchanged boot images match the previous stock
clock/reset trial byte for byte. The replacement
`init_boot` SHA-256 is
`86f034c3e44dd775743b8c9704f99ff58d746d8f2019a857a1559eb7993a5ab0`.
All five image hashes and the saved D1 slot-fit and
handoff checks passed. The new event still needs an
attended stock trace to confirm capture on hardware.

##### Attended stock D1 DSI0 PHY init trace

On 2026-11-26 the rescue copied all nine NV partitions.
The Mac independently verified 3,392,151,552 bytes, all nine
hashes and private permissions. Both the rescue and trace
passed the full 64 MiB `vendor_boot_b` readback. One slot B
diagnostic boot was requested after the rescue, with stock
Android off between the two.

The trace armed before display module load. Wrapper, BE and
DSI0 genpd all reported `off-0` in the pre-load snapshot.
The ring retained all 44 events. The final votes and reads
below were recorded on the same task after the NV guard.

| Time (s) | Event | Result |
| ---: | --- | --- |
| 4.881742 | Wrapper ON result | `0` |
| 4.882140 | BE ON result | `0` |
| 4.882675 | DSI0 ON result | `0` |
| 4.892460 | First CD-PHY resource, offset `0x7124` | `0x000001cc`, bit 8 set |
| 4.892467 | DSI0 host ID | `0x30313130` |
| 4.892469 | DSI0 host version | `0x1a000110` |
| 4.893712 | DSI0 runtime resume result | `0` |
| 4.893716 | DSI0 host status at `0x0c` | `0x00000000`, `pwr_up=0` |

The PHY read came 9.785 ms after the final DSI0 ON result
and 7 µs before the host ID. There were zero clock or reset
provider calls or replies in the scoped trace. This
establishes stock's first observed PHY access and its
ordering relative to the host. The sampled bit supplies
no independent host APB gate or external reset status.

PID 1 reported the trace and NV guard complete. The
90-second timer requested restart at 90.908479 s and
the kernel logged restart at 91.445895 s. The Mac only
detected Fastboot after the owner used Power and Volume Down,
264 seconds after the B boot request. Stock D1 A completed
boot with enforcing verity and the original VBMeta digest.
Ramoops and the later `SYSTEM_LAST_KMSG` entry match on all
83 filtered lines and the full scoped trace.

##### Offline interpretation of the stock DSI0 PHY sample

In exact D1 `mipi-cdphy.ko`, the PHY field allocator
(`0x7ba8`–`0x7bd0`) binds bit 8 at CD-PHY TX offset
`0x7124` to its register field named
`phy_common9_reg_lp_dco_clk_dyn_gating` (allocation
failure label referenced at `0x91c8`). The PLL mode
path clears and sets the same field at `0x950` and
`0xa2c`. At init, the driver uses it to seed a
software PLL-enabled flag, which `dw_cdphy_set_ulps`
tests before changing ULPS. The initial `0x000001cc`
sample therefore records that the dynamic-gating
control was set. The trace checker now labels bit 8
with that field name. The init callback returns zero
without testing the `regmap_read` return code. Its
success return alone gives no read or readiness evidence.

The hardware PLL lock check uses bit 1 at offset
`0x24` of the second PHY resource, `u0-apb-regbank`
(AP `0x0f7d8800`). The stock field table labels it
`phy_sts_r_pll_lock`, and the PLL mode path polls
it at `0xf3c`–`0xf5c`. The attended init trace
contains the first PHY resource read only. Lock at
the time of the host ID read remains unobserved.
Both PHY fields are distinct from the host APB clock
acknowledgment and external reset. Mainline PHY and
host reads remain disabled pending qualified access.

##### Offline passive stock D1 DSI0 PLL-lock trace

`pack-stock-inventory.py --dsi0-pll-trace` extends the
guarded stock DSI0 trace. Packaging pins the exact D1
`mipi-cdphy.ko` hash. PID 1 loads the stock module closure
after the NV guard and arms the PLL probes after
`mipi-cdphy.ko` loads, before the DSI host loads.

The probes record the first and final values consumed by
the three identified bit 1 polls in the stock driver.
These are D1 module text offsets.

| Callback | First sample | Final sample |
| --- | --- | --- |
| `dw_dphy_set_mode_g301`, lock path | `0xf0c` | `0xf5c` |
| `dw_dphy_set_mode_g301`, relock path | `0xa7c` | `0xbf8` |
| `dw_dphy_configure_g301` | `0x31b8` | `0x31f0` on lock or `0x3238` after the deadline |

They fetch the word from
the saved register and filter on the physical resource
start from the driver's RAM structure
(`u0-apb-regbank`, `0x0f7d8800`). The diagnostic adds
no MMIO access or modeset. It retains the regular host,
PHY init and MBFS events and stops three seconds after the
display module load completes. The independent 90-second
return stays armed.

The checker reports the raw sample, bit 1, and its signed
timing relative to the expected host ID, together with the
elapsed time since the latest successful DSI0 ON reply that
has no succeeding successful OFF. If stock never polls
within the capture window, it reports zero samples and
leaves PLL lock unobserved. The result does not qualify
mainline host APB access or external reset.

The normal host probe calls `phy_init` and reads host ID
without calling `phy_configure`. Its first runtime resume
can return while the bridge pointer is still absent,
as observed in the attended PHY trace. The separate host
enable path invokes `phy_configure` at `0x155c`.
The host's ULPS-exit path can invoke `phy_set_mode_ext`
with mode `0x10`, submode `0`, at `0x1afc`.
It first checks the host command interface. These
paths follow host access. The fixture loads the same
seven display modules as the previous trace and does not
load a panel module or request a DRM modeset. Zero samples
are expected if the stock driver only probes the host.

The exact D1 kernel accepted all seven filtered probes in
QEMU, refused to arm them without the PHY module and
removed them cleanly afterward. Replay preserved the
previous hardware trace output. Synthetic cases covered
samples before and after host ID, cleared vote correlation
after OFF, both configuration outcomes, zero samples and
malformed scope. The packed
`init_boot` SHA-256 is
`64b8c3c99d16436f8657bfbc4ee62388258c6d82422e7fdc751eaa339f604f61`.
The other four images match the attended PHY init fixture.
Checks passed for all five hashes, initramfs readback,
handoff bounds and saved slot fit. The hardware capture
remains pending.

##### Full stock D1 boot timing for DSI0 PHY lock

The retained stock Android display bugreport places the
first logged DSI0 configuration 6.284649 seconds after
the initial host ID read. Times below are stock kernel
uptime from the same boot.

| Time (s) | Stock event |
| ---: | --- |
| 1.159314 | G301 PHY init |
| 1.159337 | Host ID `0x30313130` |
| 1.160279 | Host power handoff `dt=0 reg=0` |
| 1.212963 | CGYDA panel boot-enable message |
| 7.443980 | DSI0 PHY speed set to 1390 |
| 7.443986 | G301 PHY configuration starts |
| 7.444803 | PHY state `16` |
| 7.444816 | G301 PHY power-on |

The PHY-state log at `dw_dphy_configure_g301` text
`0x328c` formats bits 4:0 from CD-PHY TX offset
`0x7030`. Its control-flow path passes the separate
`u0-apb-regbank + 0x24` bit 1 poll at
`0x31b8`–`0x3238`. The bit-clear timeout exits
before the message. The saved log therefore gives
indirect evidence that the configuration poll observed
lock by 7.444803 s. It supplies neither the raw poll
word nor the time of the lock edge.

The earlier panel boot-enable message comes from
`gs_dsi_panel_common_init` at `0x6410`, after the
panel GPIO and regulator checks. The message describes
the driver's panel handoff decision. Host probe still
reported `dt=0 reg=0`, and the logged PHY configuration
followed later.

The probe-only bundle omits the panel module and Android
display stack. Extending its trace window alone would
leave the stock configuration trigger absent. The saved
Android boot already establishes the useful ordering:
stock host access precedes the later observed PLL lock.
The APB clock and external reset still need independent
qualification for a mainline host read.

##### Offline D1 APB clock and reset readback audit

The exact D1 ABL descriptor for `dpu_dsi0_apb_clk`
(clock ID `0x40007`) selects direct gate group 4 and
offset `0x6e0`. The direct gate lookup at `0x48834` resolves the descriptor
to AP `0x0f4196e0`. The clock helper at `0x7ac78`
tests bit 8 of gate offset `0x1c`, with 1 denoting
the enabled acknowledgment. The direct reset lookup
at `0x487cc` resolves the same gate descriptor and
uses `0x7b5b4`. That helper tests bit 12 of offset
`0x1c` (`0x7b638`–`0x7b648`), with 1 denoting
the deasserted acknowledgment.

This derives two independently decoded bits in the same
candidate word, AP `0x0f4196fc`. The reset bit describes
the per-gate reset acknowledgment. The generic direct
helper establishes its polarity. The retained stock Linux
traces contain no access to that word, and the audit
does not establish a DSI0-specific stock reset call or
the state of any additional downstream reset. The ABL
clock and reset helpers themselves write control words.

D1 BL31 dispatches the PMU register service at
`0x1a434` to `0x24250` (file offsets). The read
branch at `0x242c8` follows the address check at
`0x2438c`. Neither of its explicit address tables
(`0xa028`, 27 ranges, and `0xa1d8`, 16 ranges)
contains the DSI0 acknowledgment word. The supported
PMU service cannot provide either bit.

The exact CPM clock-status lookup at `0x37da0` uses
188 descriptors from the table at RAM `0x2001524c`.
Its operation 2 clock getter reads bit 8 at the selected
gate's offset `0x1c` (`0x18e20`). None of the
descriptors refers to gate `0x6f4196e0`, the CPM alias
of the APB clock.
The seven LPCM `0x23` clock selectors in the stock
board tree match the firmware table. Selector 1
refers to the pixel gate at `0x6f419760`.
The stock clock provider exposes rate and control
operations and has no hardware enabled-status callback.
The CPM reset status lookup also excludes display
LPCM `0x23`.

The target AP page has the D1 GC rule `0x30300`.
The stock host ID and PHY reads occurred in different
apertures and leave EL1 access to this CMU word
unqualified. Keep the APB acknowledgment and host
reads disabled. No guarded fixture is qualified by
this audit.

##### Stock D1 ABL callers and Linux access evidence

The DSI0 branch in the exact D1 ABL display bring-up
(`0x7c0ec`) and shutdown (`0x7cac8`) calls the
display power dispatcher `0xf4508` with domain index 4.
It dispatches at `0xf4610`–`0xf4618` to the generic
power vote handler with table index 10. The corresponding
row at `0x32df90` names `DPU_DSI0` and has group 4,
subdomain 3. The handler `0x49410` packs the vote and
calls the CPM mailbox routine at `0x49484`. This path
has no direct APB acknowledgment read. The separate
PHY power-off callback at `0xf2a50` updates local
PHY controls through `0xf1fd8`.

The direct helpers establish how ABL would read the
gate acknowledgment if called with the clock descriptor.
The inspected display paths do not resolve clock ID
`0x40007` through those helpers. The generic clock/reset
callback rows at `0x32cb68`, `0x32cb98` and
`0x32cbc8` refer to other clock IDs. No DSI0
runtime use of the direct acknowledgment word was
identified in ABL.

CPM's generic `lcm_get_reset` at `0x19190`
also extracts bit 12 of gate offset `0x1c`.
Its table-backed reset handler at `0x3859c` excludes
DPU LPCM `0x23`. This corroborates the clock-cell reset
field and leaves its connection to the full DSI0 host
external reset tree unresolved. The Linux host's
`pwr_up` is a separate internal enable field.

The retained early, MBFS, clock/reset and PHY-init stock
DSI0 captures and the full stock display bugreport have
no read witness for AP `0x0f4196fc` or its CPM alias
`0x6f4196fc`. The observed Linux reads cover the host
ID, version, `pwr_up` and CD-PHY init word in their own
apertures. The capture scopes were selective, so the
absence is a limit of the available evidence. Direct
Linux access to the APB acknowledgment word and coverage
of the full host reset path remain unqualified.

##### Offline D1 DPU GPCSR status audit

The B0 board tree maps `dpu-gpcsr` at AP `0x0f790000`
with size `0xe004`, as the second register resource of
`dc9x00@200000`. In exact D1 `vs_drm.ko`, `dc_probe`
maps it by name at `0x29284` and stores the pointer at
driver object offset `0x50`. This map is optional at probe.

The identified consumer is the DPU backend idle check.
`vs_dc_pm_runtime_suspend` passes the hardware subobject
at driver offset `0x28` to `dc_hw_is_be_idle`
(`0x2a7dc`). This makes GPCSR the pointer at hardware
subobject offset `0x28`. The idle check issues a write
of `0x01000002` at GPCSR offset `0x107c` and polls
offset `0x1084` bit 14 for zero
(`0x37740`–`0x377b0`). Its timeout reports backend
idle status. The passive stock DSI0 captures and full
stock display bugreport contain no direct witness for
the FE controls at `+0x104c` or `+0x1070`.

The stock backend clock-domain isolation helper
(`0x31260`) writes FE/BE offset `0x80248` through
`dc_write`, whose base pointer comes from the first
resource. That operation is distinct from the DSI0
APB gate status. The board's `0x0f46e060` DSI0
interrupt parent is a wrapper-powered interrupt
aggregator. Its description exposes interrupt delivery
and supplies no clock or reset acknowledgment field.

The identified GPCSR read is part of a backend idle
transaction with a preceding write. The audit found
no GPCSR field that qualifies as a passive DSI0 APB
gate or host reset readback.

##### Exact D1 DSI0 PSM3 transition callbacks

The matrix-backed path in CPM `0x83a4`–`0x83f8` selects
the callback by LPCM, PSM number, sampled source state and
requested target state. The LPCM `0x23` entry in the table
at `0x20009b24` resolves to `0x6303c`. Its PSM3 record
points to the four-state matrix at `0x2000a820`.

| Vote | PSM3 transition | CPM callback | Operation at CPM `0x6f40a000` |
| --- | --- | --- | --- |
| ON | 2 → 0 | `0x3a8a0` calls `0x3a8b4` | Set mask `0x0c` |
| ON | 3 → 1 | `0x3a8b4` | Set mask `0x0c` |
| OFF | 0 → 2 | `0x3a830` | Clear mask `0x08` |
| OFF | 1 → 3 | `0x3a88c` calls `0x3a830` | Clear mask `0x08` |

Both writes use `0x3b7c0`, which stores the updated word
and returns zero. The OFF path leaves bit 2 unchanged,
so the ON and OFF masks give no independent decoding
of the gate and reset signals.

The matrix entries used here return no post-poll callback.
The success test at `0x7ffc` reads the descriptor-derived
PSM3 status through LPCM `0x23`'s `0x1942c` reader.
It checks the status flags, then passes the low nibble
and the requested state to the exact-match comparator
at `0x3b836`. The optional residency accounting at
`0x7538` returns immediately for this controller because
its accounting pointer is null. When PSM3 already reports
0 or 1, the ON handler skips this transition and poll.

The traced path establishes PSM3 sequencing only. Firmware
does not sample the APB gate word or a separate host
reset status in these callbacks or their completion poll.
The DSI0 host read remains gated on independent evidence
that the APB clock is running, external reset has been
released and the target is accessible from EL1.

##### Stock D1 DSI0 votes before host module load

The retained MBFS, clock/reset and PHY-init trials each
record a successful DSI0 ON/OFF pair after the loader starts
`mipi-cdphy.ko` and before it starts `mipi-dsi2h.ko`.
Ramoops and `SYSTEM_LAST_KMSG` agree on the events. The
first ON runs on the module-loading task, the OFF runs on
a worker, and a later task issues the final ON and reads
the host. Times below use the trace clock.

| Stock trace | Early ON result (s) | Early OFF result (s) | Final ON result (s) | Early OFF to final ON (ms) |
| --- | ---: | ---: | ---: | ---: |
| MBFS | 5.830878 | 5.833863 | 5.936410 | 102.547 |
| Clock/reset | 6.319319 | 6.321630 | 6.402993 | 81.363 |
| PHY init | 4.808976 | 4.811529 | 4.882675 | 71.146 |

The exact D1 kernel explains the ON/OFF pair. In the B0
merge, `f7c0000.dw_mipi_cdphy` and the host each reference
the same single domain, `DpuDsi0.v` (`0x203`). The other
PHY at `f7e0000` references `0x204`.

1. Before entering the PHY driver's probe, `platform_probe`
   calls `dev_pm_domain_attach(dev, true)` at Image
   `0xbfca9c`. The single-domain path enters
   `__genpd_dev_pm_attach` and calls `genpd_power_on` at
   `0xb27018`. It powers the parent domains first.
   The early wrapper, BE and DSI0 ON replies in the module
   loader's task match this path.
2. The PHY probe resolves the 38.4 MHz `pllref` at module
   `0xf8`. `cdphy_init_g301` initializes both PHY regmaps
   at `0x33fc` and `0x3470` with a null bus-clock name.
   The probe registers the PHY provider and enables runtime
   PM at `0x208`.
3. Domain attachment installs `genpd_dev_pm_sync` at
   `0xb26f6c`. On successful probe, `really_probe` invokes
   that exact callback slot at `0xbf9268`, before calling
   `driver_bound`. The callback queues the domain's
   power-off work at `0xb2869c`. Its worker calls
   `genpd_power_off` at `0xb25524`. The early OFF replies
   come from a worker in child-to-parent order, which fits
   the post-probe idle-domain release. The retained trace
   did not record the work item or call stack, so it cannot
   attribute the individual OFF reply to that worker
   function directly.

The host later attaches to the same domain, calls
`phy_init` at module `0x24e0` and reads host ID and version.
The early OFF reply occurs before host module load. Its
firmware handler can request a PSM3 OFF transition, and
the later ON can request a transition back. Neither reply
captures the physical PSM3 state, the APB gate bit or the
external reset state. The stock clock/reset trace has no
AP-side provider operations for either cycle. The observed
intervals are module sequencing, and the effect of omitting
the early cycle on mainline host readiness remains untested.
Keep direct mainline host reads disabled.

##### Passive stock D1 genpd power-off trace

Use `pack-stock-inventory.py --dsi0-genpd-trace` with the
checked D1 NV rescue images and the B0 merge of isolation
DTBO entry 19. Packaging pins the kernel image, vendor
images, board DTB and the factory `mipi-cdphy.ko`. PID 1
verifies the NV guard before arming tracefs and loading
the seven stock display modules. The independent
90-second warm return remains armed.

The four new probes use the exact D1 kernel text and
read registers or RAM-backed genpd data. They add no
MMIO, power vote, clock request or reset operation.

| Probe | D1 Image offset | Data |
| --- | --- | --- |
| `genpd_dev_pm_sync+0x3c` | `0xb2869c` | The DSI0 work pointer at the call to `queue_work_on` |
| `genpd_dev_pm_sync+0x40` | `0xb286a0` | The queue result, paired by task because the inputs are caller-saved |
| `genpd_power_off_work_fn+0x4c` | `0xb25524` | The DSI0 work pointer before calling `genpd_power_off` |
| `genpd_power_off_work_fn+0x50` | `0xb25528` | The same pointer after the call returns |

Run `check-stock-dsi0-trace.py --require-genpd TRACE` on
the retained trace. Between the PHY and host module load
markers, require the early DSI0 ON reply on the sync task
and a successful queue result. The worker must execute the
same work item. Its task must issue the DSI0 OFF request and
receive result zero between the two worker probes. Preserve
the existing clock/reset and host status records. A missing
marker, lost events, missed probes or an ambiguous sequence
leaves the correlation unconfirmed. The worker match alone
cannot establish the APB gate or external reset state.

Offline, the checker replayed four saved profiles with
identical output and passed 13 synthetic correlation cases.
A tracefs mock checked probe registration and cleanup,
DSI0 filters, the stock host-read stop trigger and refusal
when the PHY was already loaded.

The packed `init_boot` SHA-256 is
`efa1456c8f96248b0ee353f318adbef64662e67795001919d4b4b1b46aa3165a`.
The other four images match the attended PHY-init fixture
byte for byte. All five image hashes, replacement AVB seal,
archive readback, saved slot fit and handoff bounds passed.
For an attended run, take a fresh guarded NV backup after
the latest stock boot, return the rescue to Fastboot and
keep Android off until the approved trace boot. Use the
timed return to Fastboot and select stock A.

##### Attended stock D1 DSI0 genpd worker trace

On 2026-11-27 the fresh read-only rescue backup verified
all nine NV partitions, 3,392,151,552 bytes, the independent
phone-side hashes and private permissions. Copy and host
verification took 255 seconds. Both five-image staging
passes matched the full 64 MiB `vendor_boot_b` readback.
The rescue returned to Fastboot with A selected and Android
stayed off before the single trace boot on B.

The NV guard reported five read-only parents and nine
targets before the trace armed. PID 1 confirmed all eight
probes with zero misses and retained all 58 trace records.
The PHY-load marker precedes the early DSI0 ON, and the
host-load marker follows the early OFF and worker return.

| Trace time (s) | Event | Result |
| ---: | --- | --- |
| 6.331662 | Early DSI0 ON reply | `0` on the PHY-loading task |
| 6.333763–6.333782 | `genpd_dev_pm_sync` and queue result | Same loading task, `queued=1` |
| 6.333799 | Power-off worker enters | Same work item |
| 6.333803 | Worker sends DSI0 OFF | MBFS `0x203` |
| 6.334095 | Worker receives DSI0 OFF reply | `0` |
| 6.335422 | Worker returns from `genpd_power_off` | Same work item and task |
| 6.413343–6.413347 | Later worker pass | Same work item, no DSI0 OFF request in this pass |
| 6.433622 | DSI0 ON reply before host access | `0` |
| 6.444544–6.445875 | Stock host reads | ID `0x30313130`, version `0x1a000110`, `pwr_up=0` |

The early OFF reply fell inside the worker queued by
the PHY probe's genpd sync callback. No AP-side clock
or reset provider call was captured. The trace establishes
the source of the early OFF and leaves the physical APB
gate and external reset state unmeasured.

The 90-second timer requested restart at 90.857439 seconds
of kernel uptime. Fastboot returned 138 seconds after the
slot B boot request. Stock D1 A completed boot with
enforcing verity and the pretrial VBMeta digest. Ramoops and
`SYSTEM_LAST_KMSG` matched on all 97 filtered lines, and
both passed the required genpd correlation check.

##### Offline D1 DSI0 and BE transition control

In the retained worker trace, BE OFF completes 1.014 ms
after DSI0 OFF, and wrapper OFF completes 1.316 ms after
DSI0 OFF. On the final power-up, BE ON completes 0.542 ms
before DSI0 ON. The worker later evaluates DSI0 again
without sending another OFF. The captured mailbox replies
cover these distinct votes.

In exact D1 CPM, the OFF worker branch at `0x466d0`
calls `0x1d0e8`. The member-3 OFF callback at `0x4537c`
selects the OFF half of the DPU entry at `0x62fa0` through
`0x45178` and `0x39b0c`. Its handler at `0x3a438`
accepts PSM3 states 2 and 3 without requesting a transition.
From 0 or 1, it requests 0 → 2 or 1 → 3, clearing bit 3
at CPM `0x6f40a000`. If PSM3 starts in 2 or 3 on the
later ON, the handler sets bits 2 and 3 while requesting
2 → 0 or 3 → 1. If PSM3 starts in 0 or 1, it skips the
transition. The trace supplies no physical PSM3 sample for
either vote, so the actual branch remains unobserved.

The BE member at `0x62f04` uses LPCM `0x23` PSM1.
Its OFF side accepts state 4 or, when the PSM2 dependency
equals 2, requests state 4. The matrix at `0x2000a79c`
selects `0x3a6c4` for 3 → 4, which writes zero to the
entire word at `0x6f40a000`. BE ON accepts PSM1 states
0 through 3 and requests 4 → 3 otherwise for a valid
source state. The 4 → 3 callback at `0x3a708` sets bit 2
in the same word before DSI0 requests bits 2 and 3. These
are conditional firmware paths. They show that the parent
can change the same bits around a DSI0 vote, with no
independent decoding of either bit as a gate or reset.

The factory `lpm_pm_domains.ko` corroborates the use of
bit 3 for DSI0. Its legacy selector 3 sets or clears
that bit at the provider base plus `0x1000` and
`poll_for_dpu_dsi_state` checks only the low nibble at
base plus `0x1018`. The ON and OFF checks accept states
0–1 and 2–3 respectively. D1 Grizzly has no binding for
that provider. Relative to the D1 LPCM base, the
descriptor formula reaches at most `0x7ec` with a
page index of 0 and starts at `0x1020` with a page
index of 1, excluding the legacy offset `0x1018`.
The legacy poll reports only a sequencer state.

The stock host's `sys_clk`, `phy_clk`, `ipi_clk` and
`lptx_clk` properties are configuration values.
`vs_mipi_dsi2h_probe` reads them as scalar DT cells
in `vs_drm.ko`. The B0 tree has no resource for the
DSI0 APB CMU page and only the panel node supplies a
reset GPIO. The direct acknowledgment candidate remains
AP `0x0f4196fc`. Bit 8 reports the APB gate, and bit 12
reports the clock-cell reset. EL1 access to that word
and the coverage of any downstream host reset remain
unverified. The audited read-only CPM and PMU services
offer no access to that word.

Neither child handler samples the separate APB acknowledgment
word. A sample taken after the entire power cycle would also
include the parent effects. To isolate DSI0, an independently
qualified status source would need to distinguish the DSI0
edges from the adjacent BE and wrapper transitions. Direct
mainline host reads and the candidate status reads remain
disabled.

##### Offline EL1 and reset-scope qualification for the APB word

The exact D1 FBPK GC image contains the trusted-firmware
policy FDT at GC offset `0x52b8`. Its
`dpu_rfw_lpcm` node assigns `0x30300` to AP
`0x0f419000`–`0x0f419fff`. DBL parses the three-cell
range record at `0x351dc`–`0x35224` and passes the
permission value to the firewall initializer. In the
packed-byte path (`0x33c38` → `0x359c0`), the exact
encoder maps `0x30300`, `0x30301` and `0x30303` to
`0x1f`, `0x5f` and `0x7f` respectively. Source bits
0 and 1 feed separate permission fields. This is a
static programming path. The effective rule and bus
response for a non-secure EL1 read of the exact word
remain unobserved.

The successful stock PHY init load at `0x0f7c7124`
and host ID load at `0x0f7d8000` both fall under
`0x30303` in the separate DPU bridge firewall. No saved
stock D1 display trace or bugreport records a load from
the AP acknowledgment word or its CPM alias. The
HSIO-S trial v37 is additional evidence that static
policy and a powered parent do not qualify a new AP
load. Its `0x30301` config-clock read raised an SError
under the tested handoff conditions.

ABL names the reset helper `lcm_set_reset`. Its
`0x487cc` dispatch resolves one descriptor to one
clock cell. The helper at `0x7b5b4` changes the
selected cell's control and request words, polls
bit 12 at that cell's offset `0x1c`, and restores
the saved control word. The D1 table has separate cells
for DSI0 APB, system and pixel clocks, plus the shared
DSI PHY clock. The APB call polls only `0x0f4196fc`.
The merged tree supplies no host or PHY reset mapping,
and its panel reset GPIO belongs to the panel. The
bit-12 acknowledgment is verified for the selected
clock cell. Its coverage of resets downstream of that
cell remains unverified.

Neither qualification passed offline. No read-only
diagnostic was built for this word.

##### Offline D1 system, pixel and PHY reset paths

The D1 ABL group-4 descriptors at file offsets `0x1f5220`,
`0x1f5290` and `0x1f5300` identify the following clock cells.
Each has reset selector `-1`. If requested, ABL's clock-reset
dispatch (`0x48e44`–`0x48e90`) uses the direct MMIO helper,
which waits for bit 12 at the selected cell's offset `0x1c`.
This establishes the scope of the acknowledgment. The stock
display sequence has no observed invocation for these cells.

| ABL clock cell | AP acknowledgment word | Stock D1 association |
| --- | --- | --- |
| DSI0 system, `0x40009` | `0x0f41973c` | ABL names it for DSI0. Stock Linux describes the host's system clock as a scalar and supplies no separate clock or reset handle. |
| DSI0 pixel, `0x4000b` | `0x0f41977c` | DPU LPCM `0x23`, clock selector 1, matches `dpu_dsi0_pix_clk` in the merged tree. Its provider phandle has no consumer in that tree. |
| DSI PHY, `0x4000d` | `0x0f4197bc` | ABL uses an unindexed PHY name. D1 Linux labels DPU LPCM clock selector 3 `dpu_dsi1_phy_clk`. This cell's connection to DSI0 is unverified. |

The host's `phys` phandle resolves to the DSI0 CD-PHY
supplier, which takes a fixed 38.4 MHz `pllref`. The host
and PHY share DSI0 genpd `0x203`. This establishes the
PHY-to-host dependency. The system and pixel descriptors
identify DSI0 clocks, but the preserved artifacts do not
show which downstream host blocks their reset signals reach.

For all three words, the AP page has the same `0x30300`
firewall policy as the APB cell. A search of 35 saved pstore
text files and the saved stock display bugreport found no
mention of these addresses or their CPM aliases. The stock
`clk-cpm.ko` operations lack a hardware enable-state getter.
`rst-cpm.ko` supplies assert and deassert only. Its debugfs
files have no read getter. CPM's reset-status handler at
`0x3859c` uses the lookup at `0x49cf4`, whose allowed
LPCM IDs exclude DPU `0x23`. CPM's separate clock query
can compare the gate state for selectors 1 and 3 using bit 8
at the cell's offset `0x1c`. It does not sample bit 12,
and the DSI0 system cell has no entry in that clock table.
Neither that query nor the earlier `GET_RATE` replies
provide a stock readback of these resets.

The stock CD-PHY driver allocates PHY-local reset and
shutdown controls at bits 0 and 1 of its second resource
(`0x0f7d8800 + 0x28`). The driver asserts both
active-low controls during shutdown and early setup and
deasserts them during late setup. Stock D1 enables
debugfs, but its driver does not create files for these
two controls. The paths tested below came from the
driver's removal table. External CMU resets and DSI0
host reset coverage remain unverified.

##### Passive stock D1 PHY reset trace

`pack-stock-inventory.py --dsi0-phy-reset-trace` uses the
same pinned D1 NV rescue images and B0 DTBO entry 19 merge
as the genpd fixture. Packaging verifies the stock
`mipi-cdphy.ko` hash. PID 1 keeps the NV guard ahead of
display module load and leaves the independent 90-second
warm return armed.

The fixture tested the candidate PHY-local debugfs paths just
after `mipi-cdphy.ko` loads and again just after the stock
display module load finishes. It mounts debugfs read-only.
The stock getter calls `pm_runtime_get_if_in_use()` and
skips the hardware read unless it can hold a reference to
a PHY already in use. The fixture adds no explicit resume,
power vote, modeset, reset write or direct MMIO access.

The trace brackets each file read and records the signed
regmap return at `dw_mipi_debugfs_u32_get+0x5c` in the
exact D1 module. This instruction runs after
`regmap_field_read()` at module offset `0xb794`.
The regmap result must be zero on the same task before
the checker accepts the debugfs value. For a confirmed
sample, 0 means asserted and 1 means released. The two
files are sampled separately. The fixture cannot see a
transition between samples, and a PHY active only inside
probe may yield no confirmed reads.

Run `check-stock-dsi0-trace.py --require-phy-reset TRACE`
against the retained trace. It checks all four attempts
and pairs them with the latest successful DSI0
`0x203` ON reply without a succeeding successful OFF,
and with the stock host `pwr_up` read. A skipped or
failed read remains unobserved. An incomplete trace or
an inconsistent result is rejected.

The packed `init_boot` SHA-256 is
`a824c9066a4691e8dd8fa329242e01445fc0894de4a139180e12887467c8db09`.
All five image hashes, AVB packaging, initramfs readback,
handoff bounds and saved slot fit passed. The four other
images match the attended genpd fixture byte for byte.
Offline checks covered shell syntax, sampler output,
legacy replay, successful reads, skipped reads, a failed
regmap read returning zero through debugfs, and malformed
correlations. Probe registration and PHY values remain
pending on the Pixel.

###### Attended stock D1 PHY reset trace

On 2026-11-27 the read-only rescue verified nine unmounted
NV partitions and saved 3,392,151,552 bytes privately on
the Mac. The remote and local SHA-256 checks passed.
The rescue returned directly to Fastboot. All five trace
images were staged to B, the full `vendor_boot_b`
readback matched, and B booted once.

| Kernel uptime | Trace boot result |
| ---: | --- |
| 0.912 s | Independent 90-second return timer armed. |
| 2.529 s | Stock UFS `DME_GET` for attribute `0x1587` timed out. |
| 3.041 s | Stock UFS power mode change failed with `-110`. |
| 3.052 s | HC PSM still reported `0x10` while waiting for `0x11`. Asynchronous SCSI scan failed with `-110`. |
| 21.698 s | All nine expected NV labels were missing. PID 1 stopped at `inventory incomplete`, before the NV guard and display module load. |
| 90.913 s | Timer requested the warm restart. |

Ramoops and the matching `SYSTEM_LAST_KMSG` entry agree
on the 25 selected lines. The NV guard passed in the
backup rescue. The trace boot never reached it and
produced no DSI0 ON, `pwr_up` or PHY reset samples.
The earlier genpd fixture passed UFS initialization with
the same four other images. This run leaves the cause of
the stock UFS failure open.

Fastboot returned 133 seconds after the trace boot
request. Stock D1 completed boot on A with enforcing
verity and the original VBMeta digest.

###### Offline comparison of the stock UFS timeout

Both display trials followed a verified NV rescue with a
warm return to Fastboot and no intervening Android boot.
The four non-`init_boot` images, effective kernel command
line and all 37 module entries through `ufs.ko` match.
The extracted factory `ufs.ko` matches the pinned D1
SHA-256. The ramdisk overlays differ only in PID 1, the
display trace helper and the mode marker. Before the UFS
scan the new mode adds a marker check. Its debugfs mount,
probe registration and field reads run after the NV
guard.

| Stock UFS step | Successful genpd boot | PHY reset boot |
| --- | --- | --- |
| `ufs.ko` load | 1.356423 s | 1.415109 s |
| M-PHY calibration complete | 1.583949 s, 4,932 µs | 1.658052 s, 4,934 µs |
| Asymmetric power-mode workaround applied | 2.017316 s | 1.668058 s |
| ESI and MCQ setup, then SCSI host registration | Host registered at 2.460063 s | Host registered at 2.539264 s, after a UIC timeout |
| Final power mode and device discovery | HS gear 5, series 1 and rate 2 at 2.461129 s. First direct-access LUN at 2.481410 s. | HS negotiation returned `-524`. The subsequent power-mode command and asynchronous scan failed with `-110`. No LUNs were discovered. |

Both report REXT trim 34, PHY patch mode 0 and the same
missing optional `hsios_aux_clk`. In exact `ufs.ko`,
`ufs_google_link_startup_notify` sets two active RX and
TX lanes at `0xa588` and `0xa5a4`, then sends the
automatic power-mode request at `0xa5c4`. Each error
branches away from the success log at `0xa5f4`. The
different timing of that log precedes the first explicit
error. Other successful stock display captures also show
variation in the delay between the workaround and ESI.

The first failed command was local `DME_GET` for
`PA_MAXRXHSGEAR` (`0x1587`). The exact stock Image
branches from that DME request at `0xebf2dc` to its error
path at `0xebfb94`, clears the RX gear and tries
`PA_MAXRXPWMGEAR` (`0x1586`) at `0xebf2ec`.
The PWM fallback sets RX to slow mode at
`0xebf320`–`0xebf324`. The Google variant calls
`ufshcd_negotiate_pwr_params` at module `0xa850`
and reports `-524` when HS negotiation fails. The
later `DME_SET PA_PWRMODE` had mode `0x21`, slow
RX and fast TX. Its separate timeout caused the scan
failure. The HC PSM wait for `0x11` failed afterward
during cleanup.

At the power-mode timeout the host dump showed
`IS=0x400` and `IE=0x00171af5`. Generic UIC command
completion was latched. The exact stock power-control
path masks `0x400` before waiting for the asynchronous
event (Image `0xdca5c`–`0xdca70`) and restores it
after the timeout (`0xdcb00`–`0xdcb08`). Power-mode completion
(`0x10`) was enabled and absent from that status word.
The following interrupt logged `0x400` as unhandled
and the next dump showed `IS=0` and `IE=0x00171ef5`.
The timeout dump also retained opcode `0x2`, argument 1
`0x15710000` and argument 2 result `0x02`
(`INVALID_ATTR_VALUE`). That register state is
consistent with the controller rejecting the `0x21`
mode request.
The successful genpd boot logged a similar unhandled
`0x400` only during timed shutdown, after partition and
display checks passed. The snapshots identify which
completion was missing during the failed transition.
They leave the cause of the earlier capability read
timeout and the hardware state at handoff unresolved.

###### Passive stock D1 UIC command and interrupt trace

`pack-stock-inventory.py --ufs-uic-trace` pins the D1
factory `ufs.ko` hash and uses the same four
non-`init_boot` images and B0 DTBO entry 19 merge as
the attended display fixtures. It arms a private
monotonic trace before `ufs.ko` loads and exports it
to ramoops after the bounded inventory scan, including
when UFS initialization prevents partition discovery.
PID 1 runs the existing NV guard when the inventory is
present. The independent 90-second warm return remains
armed for either outcome.

The exact D1 kernel implements the native UIC
completion trace by issuing four additional HCI
register reads. This fixture instead records only
existing driver values in ARM64 registers and RAM.
The following offsets are relative to symbols in the
pinned stock Image.

| Probe | Evidence |
| --- | --- |
| `__ufshcd_send_uic_cmd+0x88` and `+0x10c` | Opcode and all three arguments before and after dispatch. |
| `ufshcd_intr+0xe0` | Existing interrupt status and enable reads before software masks or acknowledges them, plus the active opcode and MIB when present. |
| `ufshcd_intr+0x184` | Existing command-completion result and payload. |
| `ufshcd_intr+0x1ac` | The pending asynchronous bits just before the stock handler completes the power-control waiter. |
| `ufshcd_wait_for_uic_cmd+0x68` | Signed status, ARG2 result and ARG3 payload from the ordinary UIC wait. |
| `ufshcd_uic_change_pwr_mode+0x90` | Signed return from the asynchronous power-control path. |

The command filters keep local `DME_GET` for
`0x1587` and its `0x1586` fallback, plus
`DME_SET PA_PWRMODE` (`0x1571`). Inspect the
`UFS UIC trace` rows by monotonic timestamp. Match
the command dispatch and wait result with the IRQ
rows scoped to that command. For a late generic IRQ,
`cmd=0` can mean that the active command was cleared.
An observed `0x400` in IS with the bit clear in IE
shows a masked command completion. The power-control
wait needs the separate `0x10` event. A timeout with
no matching IRQ sample leaves the hardware interrupt
state unobserved. Check the buffer, export and missed
probe counters before interpreting an absent row.

The packed `init_boot` SHA-256 is
`48a8782644b64c6083f974483ce9d1f16239fae3036ed23858e52eb83872466e`.
Image hashes, AVB, initramfs readback, handoff bounds
and saved slot fit passed. Shell mocks exercised probe
registration, parsing, loss checks and cleanup. Probe
registration on stock D1 and the hardware capture
remain pending.

###### Attended stock D1 UIC trace result

On 2026-11-27 the first backup rescue did not enumerate
over USB. After returning to Fastboot, the same rescue
booted and verified all nine read-only, unmounted NV
partitions. The private Mac copy totaled 3,392,151,552
bytes and passed SHA-256 verification. The rescue
returned directly to Fastboot. The five UIC trace
images were staged, full `vendor_boot_b` readback
matched, and the UIC fixture booted once.

| Kernel uptime | Stock trace result |
| ---: | --- |
| 1.031180 s | Seven probes armed before `ufs.ko` loaded. |
| 1.594844–1.595396 s | Early `PA_PWRMODE=0x44` completed asynchronously with pending `0x10` and returned 0. |
| 2.534196 s | Local `DME_GET 0x1587` sent. |
| 2.534206 s | IRQ had `IS=0x400`, `IE=0x71ef5`. Command completion was enabled. |
| 2.534213–2.534222 s | `ARG2=0`, `ARG3=5` and wait result 0. The read returned HS gear 5, 26 µs after send. |
| 2.540926–2.542942 s | Final `PA_PWRMODE=0x11` completed with `IS=0x410`, `IE=0x171af5`, asynchronous pending `0x10` and result 0. |
| 5.729903 s | NV guard passed on the trace boot. |
| 90.916912 s | Warm return timer requested restart. |

The trace retained 15 of 15 rows with no missed probes,
malformed rows or loss. Ramoops and the matching
`SYSTEM_LAST_KMSG` entry agree on all 52 selected
lines. The `0x1586` fallback did not run. This is a
successful baseline for the UIC request, IRQ and wait
sequence. The earlier `0x1587` timeout did not recur,
so the point where its completion was lost remains open.

Fastboot returned 134 seconds after the trace boot
request. Stock A completed boot with enforcing verity
and the original VBMeta digest.

###### Combined stock D1 UIC and PHY reset trace

`pack-stock-inventory.py --dsi0-phy-reset-uic-trace`
packages the two existing trace helpers for a single
attended boot. The UIC probes arm before `ufs.ko` and
their output reaches ramoops after the bounded inventory
scan, even if UFS never exposes partitions. PID 1 closes
the UIC trace before invoking the NV guard. If the guard
passes, PID 1 attempts the DSI0 trace and reports the
UIC capture result independently. A missing inventory or
failed guard prevents display module load. Both traces
use the monotonic clock, and the independent 90-second
warm return stays armed.

Check the UIC rows for the `0x1587` request, interrupt
and wait result. If the display trace runs, use
`check-stock-dsi0-trace.py --require-phy-reset TRACE`
to correlate the active-only PHY readbacks with DSI0 ON
and the host `pwr_up` read. A failed UFS scan leaves
the PHY fields unobserved.

The packed `init_boot` SHA-256 is
`ab087582a1dccb2dbf000c5151f49c379b8df51ef35a821812559ecbf7be1383`.
The four other images and both trace helpers match the
previous fixtures byte for byte. The NV guard is
unchanged. All five hashes, AVB, initramfs readback,
handoff bounds and saved slot fit passed. Offline tests
exercised the path with a passing guard, missing
partitions, a failed guard, either trace failing and
an ambiguous fixture. The combined boot remains pending.

###### Attended combined UIC and PHY reset result

On 2026-11-27 the read-only rescue copied and verified all
nine NV partitions privately on the Mac. It returned
directly to Fastboot. All five combined-trace images
were staged to B, the full `vendor_boot_b` readback
matched, and the combined fixture booted once.

UFS `DME_GET 0x1587` was sent at 1.676837 s. Command
completion arrived 13 µs later with `IS=0x400` and
`IE=0x71ef5`. The read returned HS gear 5 with wait
result 0. The UIC trace retained all 15 rows with no
missed probes. The NV guard passed before display load.

The stock DSI0 ON reply for host probe arrived at
5.907836 s. The host then returned ID `0x30313130`,
version `0x1a000110`, and `pwr_up=0` at 5.919049 s.
The earlier post-PHY sample pair followed a successful
DSI0 OFF reply and preceded that host status read by
90.370 and 90.281 ms. The post-display pair followed
`pwr_up` by 7.826 and 7.957 ms, while the latest
recorded DSI0 vote was ON. Neither pair reached
`regmap_field_read`, so all four values remain
unobserved. This trace does not distinguish an
unavailable debugfs file from the getter declining its
in-use runtime PM reference.

The DSI0 trace retained all 63 rows. Ramoops and
`SYSTEM_LAST_KMSG` agree on all 124 selected lines.
The 90-second warm return worked. Fastboot returned
134 seconds after the trace boot request, and stock A
completed boot with enforcing verity and matching VBMeta.

###### Offline PHY runtime PM follow-up

The stock driver's successful probe calls
`devm_pm_runtime_enable()` for the CD-PHY platform
device. The host's generic PHY init holds a temporary
runtime reference. A successful DSI0 genpd vote and
the host's runtime resume leave the PHY platform
device's own usage and runtime status unverified.

The updated combined fixture records the exact result
of `pm_runtime_get_if_in_use()` at
`dw_mipi_debugfs_u32_get+0x48`, before stock checks
that result. A zero means the PHY was not in use. A
negative return identifies a runtime PM error. A
positive return is paired on the same task with the
existing `regmap_field_read()` result probe.
The sampler also distinguishes a missing or unreadable
debugfs file from a read that returns an error.
The added probe observes a register already written by
the stock call. The fixture keeps the existing
in-use check, NV guard and timed return.

The updated `init_boot` SHA-256 is
`c77ca5e5304a0cebf9051a3a8966f2b68e62161e74eab2523b397fc2bd94796c`.
Legacy hardware trace replay and synthetic runtime PM
cases passed offline.

###### Attended PHY runtime PM result

On 2026-11-27 the read-only rescue copied and verified
all nine NV partitions privately on the Mac. It returned
directly to Fastboot. The five trace images were staged
to slot B, the full `vendor_boot_b` readback matched,
and the updated fixture booted once.

The local `0x1587` read again returned HS gear 5 with
wait result 0. The NV guard passed before the display
modules loaded. The host-probe DSI0 ON reply succeeded
at 6.897893 s and the stock host read `pwr_up=0`
at 6.910303 s. The two candidate files were missing
at both sample points. Neither the getter's runtime
PM probe nor its regmap-result probe recorded an event.
The trace retained 63 of 63 DSI0 rows and 15 of 15 UIC
rows. Ramoops and `SYSTEM_LAST_KMSG` matched on all
126 selected lines.

A recheck of the exact D1 module resolved the missing
paths. The file-name relocations at module `0xa58c`
and `0xa5a0` belong to `cdphy_remove_g301`
(`0xa31c`–`0xa85c`). Neither
`dw_create_debugfs_hwv_files_1` nor
`dw_create_debugfs_hwv_files_2` creates these names
or uses the two corresponding field pointers. The
original offline audit misread an ADRP page label as
the containing function. These paths cannot provide
the PHY reset readbacks in stock D1. The internal
field mappings and runtime guard for exported files
remain valid.

The 90-second warm return worked. Fastboot returned
134 seconds after the B boot request. Stock A completed
boot with enforcing verity and matching VBMeta.

###### Offline stock PHY reset register access

The D1 CD-PHY module maps the second platform resource
at `cdphy_init_g301+0xf8`, initializes its MMIO regmap
at `+0x124` and stores it at private offset `0x30`.
The two reset field allocations use that regmap and
offset `0x28`. An exhaustive check of references to
the five fields in that word found the following
hardware access sites in the exact stock module.

| Stock callback | Module call offsets | Operation |
| --- | --- | --- |
| `dw_dphy_configure_g301`, initial configuration path | `0x11bc`, `0x11d8` | Clear `shutdown_n`, then `phy_rst_n`. |
| `dw_dphy_configure_g301`, release paths | `0x2ff0`, `0x300c` or `0x30a8`, `0x30c4` | Set `shutdown_n`, then `phy_rst_n`. |
| `dw_dphy_configure_g301`, adjacent field | `0x2fd4` or `0x308c` | Update bit 8 of the same word. |
| `dw_dphy_power_off_g301` | `0x50c`, `0x528` | Clear `shutdown_n`, then `phy_rst_n`. |

All listed calls use `regmap_field_update_bits_base`.
The remaining two fields in this word, bits 16 and
17, have allocation and removal references only in
this module. The stock `dw_dphy_reset_g301` callback
logs and returns zero. The normal init callback reads
`0x7124` from the first resource. Neither callback
touches the reset word.

The host's enable path calls `phy_configure` at
`0x155c` and `phy_power_on` at `0x1584`.
A host transfer, a ready bridge's runtime resume
or DRM atomic enable can reach that enable path.
The disable path calls `phy_power_off` at `0xae0`
only after the host has entered an enabled state.
The DRM platform shutdown callback calls
`drm_atomic_helper_shutdown` at `0x9948` when the
DRM device exists. It tears down an active pipeline.
The RAM fixture captured the probe's `bridge not ready`
and `dt=0 reg=0` messages and neither configuration
nor PHY power-off before the timed return. Extending
the idle capture window alone supplies no modeset.

The saved full stock D1 Android bugreport shows the
DSI0 PHY configuring at 7.443986 s, powering on at
7.444816 s and powering off at 12.912277 s. Further
configure and power-off cycles appear in the same log.
These are natural driver opportunities to observe
the reset word. A passive capture would pair filtered
existing regmap read and write events at `0x28` with
the identified calls and their returns on the same task.
Both PHY regmaps share the platform device name in
generic regmap events, so the call site is needed to
identify the second resource. An existing read can
report the prior latch bits. A write event alone
reports the word issued by the driver.

These paths can establish PHY-local state during a
stock display transition. They leave the PHY state
at the initial `pwr_up` read and the separate APB
and external host reset state unresolved. No modeset
fixture was built from the probe-only bundle.

###### Passive stock D1 modeset capture

`stock-dsi0-rmw-trace.sh TRACEFS BUSYBOX arm` attaches
to a loaded D1 `mipi-cdphy` driver in a privileged
stock display session. Run `dump` after a normal
display enable and power-off, then `cleanup`.
`check-stock-dsi0-trace.py --phy-rmw TRACE` decodes
the result. Access to a privileged stock display
session with tracefs remains unverified.

The collector scopes ten before/after call pairs to
the RAM-backed second resource start `0x0f7d8800`.
It records the driver request and return code, and
uses the existing regmap trace events for its
`0x28` reads and writes. The checker pairs those
events with the bracketed driver call on the same
task and decodes both active-low bits. It reports an
existing read separately from a write. The collector
adds no MMIO access and requests no display activity.

`pack-stock-inventory.py --dsi0-rmw-trace` puts the
same collector in the D1 RAM fixture. PID 1 verifies
the NV guard, then arms after CD-PHY loads and before
the DSI host loads. It dumps to ramoops 20 seconds
after the display module load and leaves the
independent 90-second warm return in place. This
guarded bundle has no panel or display userspace to
initiate a modeset. A capture with zero paired calls
leaves the PHY bits unobserved.

The packed `init_boot` SHA-256 is
`31656fea544a7de52eafe659edd7adff5a86a9406af8e4873a54df161e18c7d5`.
The other four images match the attended D1 display
fixture. Offline checks covered the five hashes,
AVB, handoff bounds, saved slot fit, legacy trace
replay, and mocked registration, capture and cleanup.
Hardware registration and a modeset capture remain
pending.

###### Stock D1 modeset prerequisites

The saved stock D1 Android bugreport identifies the
fitted CGYDA panel and a 1080×2410 display mode at
120 Hz. It also records SELinux denying the Android
shell read access to tracefs `available_events` on
the production build (`ro.debuggable=0`). The
standalone collector needs permission to create
tracefs instances and kprobes. The bugreport's
Perfetto collection reported no eligible session, so
it provides no existing register trace to decode.

The exact factory vendor ramdisk contains the panel
and I²C modules. The packed board tree selects
`google,gs-cgyda` for DSI0. Its VDDI and VCI supplies
resolve to the already-loaded DA9188 regulator, while
VDDD resolves to `samsung,s2dos07x02` at I²C
address `0x60` on AP controller `0x3a1ce000`.
The stock S2DOS07x02 driver registers the regulator
and reads registers `0x04` and `0x03` during probe.
The stock DesignWare platform driver matches
`google,i2c-mbu`. Loading it also permits matches
on the enabled controllers at `0x3bdcb000`,
`0x3a1ca000` and `0x3a1cd000`. Those buses have
other board devices behind them. The panel I²C path
therefore needs a scoped binding plan in a guarded
RAM fixture.

The supplier and panel additions to the current
display closure are `i2c-designware-core.ko`,
`i2c-designware-platform.ko`,
`s2dos07x02-regulator.ko`, `gs-panel.ko` and
`panel-gs-pkcgda.ko`. The proposed combined
manifest passes the packer's hard-dependency check
with 49 entries and the same 11 protected preloads.
That check covers the module dependency graph.
I²C, regulator and panel binding are unverified.

The stock `vs_drm` driver registers a DRM device
at module `0x9c14` and provides
`vs_gem_dumb_create` (`0xb4e0`),
`drm_atomic_helper_set_config` and
`drm_atomic_helper_page_flip`. A RAM-resident KMS
client could use these interfaces after connector
registration and choose a mode advertised by the
fitted panel. The existing bundle includes no such
client. The next guarded milestone is to verify
the panel I²C supplier and connected DSI0 connector
before issuing any display commit.

###### Guarded stock CGYDA connector discovery

`pack-stock-inventory.py --dsi0-panel-discovery`
adds the five factory modules to the guarded display
manifest. The exact D1 Image's `platform_match`
(`0xbfc93c`) checks `driver_override` before OF
matching. The setter changes the override string in
RAM. The factory driver name is `i2c_designware`.

After the NV guard passes, PID 1 verifies the four
expected platform-device names, their compatible
strings and unbound state. It refuses a preexisting
override or an unexpected DesignWare match. It
temporarily remounts sysfs writable to write a
nonmatching override for the three other buses,
restores read-only sysfs and verifies the overrides
before loading the driver. The exclusions remain
in place until reboot. The target and two excluded
buses share a power domain. The check scopes driver
binding and leaves shared-domain power behavior to
the stock driver.

Before loading the regulator and panel, PID 1 checks
that only `3a1ce000.i2c` bound. It then checks for
the S2DOS07x02 client at `0x60` under that controller
and the CGYDA panel under DSI0. The last step reads
cached DRM connector status, encoder association and
mode count through sysfs. A missing or unknown
connector is recorded as incomplete. There is no
DRM client, connector force-probe or display commit
in this fixture. The stock kernel drivers still
perform their normal probe and power-management
operations. The independent 90-second warm return
remains armed.

The packed `init_boot` SHA-256 is
`9d081028c16014659193a8c88c3b4f853129d5a8206136b0e8b30a1976984190`.
The other four images match the previous D1 display
fixtures. Image hashes, AVB, archive readback,
handoff bounds and saved slot fit passed. Offline
sysfs mocks exercised both the scoped binding and
refusals for an unexpected match, an existing override,
failure to restore read-only sysfs, a second binding
and incomplete connector discovery. Hardware binding
remains pending.

###### Attended stock CGYDA connector discovery

On 2026-11-27 the first NV rescue did not enumerate
over USB. The rescue retry copied and verified all nine
NV partitions privately on the Mac, with a total of
3,392,151,552 bytes. After the rescue returned to
Fastboot, all five discovery images were staged to B.
The full `vendor_boot_b` readback matched, and the
discovery fixture booted once.

| Kernel uptime | Discovery result |
| ---: | --- |
| 5.574238 s | The NV guard passed for five parent disks and nine target partitions. |
| 7.123461 s | All three I²C exclusions were verified and sysfs was read-only. |
| 7.324250 s | DesignWare bound only to `3a1ce000.i2c`. |
| 10.534273 s | The S2DOS07x02 client `9-0060` was bound. CGYDA was missing, so the fixture stopped before reading cached DRM connector status. |
| 17.637541 s | Stock CGYDA probe reported `failed to get reset gpio (-EPROBE_DEFER)`. |
| 31.921332 s | Late regulator cleanup failed to set the disable register after a DesignWare timeout (`-110`). |
| 90.885854 s | The warm return timer requested restart. |

The Google DSI0 connector platform driver probed but
also reported a failed device-link creation for `9-0060`.
That platform probe does not establish a connected DRM
connector. The packed B0 tree routes the panel's
`reset-gpios` phandle `0xa1`, line 11, to
`google,da9188-gpio`. The factory `da9188-gpio.ko`
is absent from this fixture's manifest. No display
commit was issued. The late regulator timeout leaves
the resulting VDDD state unverified.

Ramoops and `SYSTEM_LAST_KMSG` matched on all 40
selected lines. Fastboot returned 133 seconds after
the B boot request. Stock A completed boot with
enforcing verity and matching VBMeta.

###### Revised CGYDA fixture with VDDD timeout trace

The revised `--dsi0-panel-discovery` manifest uses
the factory `da9188-gpio.ko`. The stock MFD cell
matches `google,da9188-gpio`. Its probe obtains the
PMIC mailbox, enables pinctrl and registers the GPIO
chip at module offset `0x110`. PID 1 verifies the
bound provider and its registered gpiochip before
loading CGYDA, whose reset is line 11. The existing
scoped I²C binding and NV guard remain in place.

The earlier DesignWare timeout dump showed IRQ 419
pending and unmasked, `IR_STAT=0x200` (STOP detect),
and `TX_ABRT_SRC=0`. The ISR history contained one
`0x10` event (TX empty). This is consistent with a
STOP completion that was still unserviced at the
deadline. The underlying cause and physical VDDD
state remain unresolved.

The stock `s2dos07x02_disable` callback clears its
software enable flag before writing zero to SMBus
register `0x04`. It logs a transport timeout and
converts `-110` to success at `0x438`–`0x444`.
The fixture records both the raw SMBus result at
`s2dos07x02_disable+0x34` and the regulator return
at `+0x38`. It also captures native SMBus events
for adapter 9, address `0x60`, commands `0x03`
and `0x04`, and native DesignWare ISR events for
`3a1ce000.i2c`. The trace adds no diagnostic I²C
transactions or MMIO reads.

The trace starts before the panel suppliers load.
It dumps at or after 45 seconds of kernel uptime,
including when module load or connector discovery
fails. The separate 90-second warm return stays
armed. The fixture reads cached connector status and
issues no display commit. The stock drivers still
perform their normal discovery and regulation.

The packed `init_boot` SHA-256 is
`554079b5159e6c94ed9b142b1eae0093120c6d48ed47989c2f8e036a722ba36c`.
The other four images match the attended discovery
fixture. Offline checks verified archive contents,
device bounds, all five hashes, GPIO registration
gating, scoped event setup, timeout export and trace
loss handling. Probe registration and the revised
panel binding remain unverified on hardware.

###### Attended CGYDA GPIO and VDDD trace

On 2026-11-27 the read-only rescue copied all nine NV
partitions (3,392,151,552 bytes) to a private Mac
directory and verified their SHA-256 hashes. The five
revised images were staged to B, and the full
`vendor_boot_b` readback matched. The fixture booted
once with no display commit.

| Kernel uptime | Discovery result |
| ---: | --- |
| 5.663773 s | The NV guard passed for five parent disks and nine target partitions. |
| 7.209446–7.418019 s | The three I²C exclusions passed, sysfs was read-only and DesignWare bound only to `3a1ce000.i2c`. |
| 7.909931 s | DA9188 GPIO was bound and its gpiochip was registered before loading the panel. |
| 7.957904 s | The stock panel driver finished probing `google-cgyda` on DSI0. |
| 10.971923 s | The fixture found S2DOS07x02 at `9-0060` and the panel at `f7d8000.dsi2host.0`. |
| 45.984813 s | The VDDD trace retained all 31 events. Both disable probes were registered with zero misses. |
| 90.873224 s | The warm return timer requested restart. |

The native trace captured five successful SMBus reads
and one successful write of `0x9e` to command
`0x03`. The initial read of command `0x04` returned
`0x21`. Each transfer recorded DesignWare ISR status
with STOP detected. Neither disable probe fired, and
the trace contains no write to command `0x04`. The
previous late-disable timeout did not recur in this
capture. The successful transfers establish bus
completion during discovery. They do not establish the
physical VDDD state after disable.

The Google DSI0 platform driver reported failed
device-link creation for `9-0060` and `da9188-gpio`.
The fixture reported incomplete discovery without a
cached DRM connector row. It does not distinguish a
missing connector from an attribute or state check
failure. The next offline check is to trace DRM
component assembly and log which connector check
failed before considering a modeset.

Ramoops and `SYSTEM_LAST_KMSG` matched on all 72
selected lines. Fastboot returned 134 seconds after
the B boot request. Stock A completed boot with
enforcing verity and matching VBMeta.

###### Offline stock D1 DRM component discovery

The exact D1 `vs_drm_platform_probe` in `vs_drm.ko`
(`0x9694`) builds its component match list from
available OF nodes for DC, BE, FE, WB, DSI2H and DP.
It registers the master at `0x98f4`. The master
`vs_drm_bind` calls `component_bind_all` at `0x9a44`
and `drm_dev_register` at `0x9c14`. The DSI2H
bridge attach resolves the remote bridge at
`mipi-dsi2h.ko+0x8978`. The panel's bridge attach
later calls its connector initializer, which calls
`drm_connector_init` at `gs-panel.ko+0x8fd4`.
The panel probe and connector registration are
separate steps.

The audited B0 DT enables the DP encoder. Its stock
probe resolves the bridge before calling
`component_add` (`vs_drm.ko+0x513a4` and
`+0x513cc`). The remote node is
`a2b4000.dwc_dptx`, whose stock `dwc_dptx.ko`
registers the bridge. That module is absent from the
three fixture manifests. The prior boot's deferred
`dp-encoder` is consistent with this path holding
the complete master unbound. The aggregate snapshot
is needed to check that explanation on hardware.

The diagnostic reports card and DSI connector counts,
missing or unreadable attributes, and rejected cached
status and encoder state. It samples after module load
and retries at the end of the VDDD capture if the first
sample was incomplete. After exporting VDDD, it takes
a bounded read from the read-only debugfs component
report for `sswrp_dpu@f400000:display-subsystem` and
selects only the DP encoder's deferred-probe entry.
The exact D1 `component_devices_show`
(`Image+0xbefbac`) formats cached state under the
component mutex. The fixture adds no modules,
forces no connector probe and issues no display commit.
The NV guard, I²C exclusions and independent 90-second
return remain in place.

Offline mocks passed nine connector and scope cases
and three component snapshot cases. The packed helper
matched source and all module manifests were unchanged.
All five image hashes, AVB, handoff bounds and saved
slot fit passed. The revised `init_boot` SHA-256 is
`754f4eefef48647b493d5f936339a8ac304f880a5d3cf51e8c4087070a1067fe`.
The other four images match the attended VDDD fixture.

For one attended slot B trial, verify a fresh private
nine-partition NV backup and all five staged images
before boot. Confirm the NV guard and single I²C
binding first. Compare the aggregate and DP deferred
entry with both connector samples when present. An
unbound aggregate with unregistered components and a
deferred DP encoder would support the suspected block.
Stop at discovery and let the timed return run. Select
stock A in Fastboot, boot Android and verify the
captured slot, verity and VBMeta.

###### Attended stock D1 DRM aggregate snapshot

On 2026-11-27 the fresh read-only rescue copied and
verified all nine NV partitions (3,392,151,552 bytes)
privately on the Mac. All five diagnostic images
passed staging checks, including the full
`vendor_boot_b` readback. The fixture booted once
on B with no display commit.

| Kernel uptime | Discovery result |
| ---: | --- |
| 5.692727 s | The NV guard passed for five parent disks and nine target partitions. |
| 7.469911 s | DesignWare bound only to `3a1ce000.i2c`. |
| 7.986055 s | DA9188 GPIO registered before CGYDA probed. |
| 11.047876 s | S2DOS07x02 and CGYDA had bound. The DRM class had zero cards and zero DSI connectors. |
| 18.145913 s | The DP encoder was still on the deferred-probe list, with no reason recorded. |
| 45.084383 s | The late sample again found zero cards and zero DSI connectors. |
| 45.095472–45.099356 s | The aggregate was unbound. Six named components (DC, BE, two FEs, WB and DSI2H) were registered but unbound. One unnamed slot was unregistered. The DP encoder was still deferred. |
| 90.882213 s | The warm return timer requested restart. |

The aggregate report leaves the missing slot unnamed.
The exact B0 match list and the deferred DP encoder
point to the encoder as the missing component. There
was no DRM connector to read at either sample. A
separate offline check can determine whether a
diagnostic-only DT overlay can exclude just the DP
encoder from the match list and preserve the DSI0
pipeline for one further discovery boot.

The VDDD trace retained all 31 events. It recorded six
successful SMBus transfers and no disable invocation.
Ramoops and `SYSTEM_LAST_KMSG` matched on all 84
selected lines. Fastboot returned 133 seconds after
the B boot request. Stock A completed boot with
enforcing verity and matching VBMeta.

###### Offline DSI0 discovery with DP encoder excluded

Use `pack-stock-inventory.py --dsi0-panel-discovery
--dsi0-panel-dp-off` with the same pinned D1 rescue
images, audited B0 merged DTB and rescue cpio as the
aggregate diagnostic. This option also requires
`dtc` and `fdtoverlay`. It adds a fragment to entry
19 (board ID `0x80506`, revision `0x10000`) of the
rescue DTBO. The packer reconstructs the baseline
from the factory vendor-kernel-boot DTB and requires
it to match the audited B0 merge byte for byte.

The sorted merged tree differs by exactly one
property. `/sswrp_dpu@f400000/dp-encoder` gains
`status = "disabled"`. Both DSI0 inputs and its
output to `gs-dsi0-connector` keep their reciprocal
endpoint references. The DP endpoints and phandles
also remain intact. Stock D1's match list skips
unavailable nodes, so the expected aggregate now
has the six components registered in the last
trial. The exclusion allows stock bind callbacks to
run if all six are ready. Those callbacks can
initialize display hardware without any display
commit from the fixture.

Offline checks preserved all 55 entry identities and
54 other entry payloads, verified the rebuilt AVB
hash descriptor, and checked handoff bounds and
saved slot fit. All module manifests and the other
three boot images match the prior fixture. PID 1
requires the disabled status in the live tree after
the NV guard and before loading display modules.
The check refused a missing status, an enabled
encoder and a malformed status list in mock runs.
The I²C scope, VDDD and DRM snapshots, and 90-second
return remain in place.

| Image | SHA-256 |
| --- | --- |
| `init_boot.img` | `e1f1e8b3f681bb2530153d60500989adeed6b4e3e77aafac381b445f192314e5` |
| `dtbo.img` | `5de69d7cb7ba8ff2844182c5f3bb1797c7c21a0aca209b524c650560ab8b1cd1` |

For one attended slot B trial, verify a fresh private
nine-partition backup and all five staged images.
Require the live-DT marker and scoped I²C binding.
Compare the six aggregate component states with the
DRM card and DSI connector samples. If the master
still fails to bind, record the first bind error and
let the timed return run. Issue no display commit.
Select stock A in Fastboot and verify Android comes
up with enforcing verity and the original VBMeta.

###### Attended DSI0 discovery with DP encoder excluded

On 2026-11-27 the fresh read-only rescue copied and
verified all nine NV partitions (3,392,151,552 bytes)
privately on the Mac. All five diagnostic images
passed staging checks, including the full
`vendor_boot_b` readback. The fixture booted once on B
with no display commit.

| Kernel uptime | Discovery result |
| ---: | --- |
| 5.704473 s | The NV guard passed for five parent disks and nine target partitions. |
| 5.710108 s | The live B0 tree reported the DP encoder disabled, before display module load. |
| 7.455459 s | DesignWare bound only to `3a1ce000.i2c`. |
| 7.958986 s | DA9188 registered before CGYDA probed. |
| 8.037148–8.045574 s | The stock master bound all six components and registered DRM minor 0. |
| 11.063835 s | The fixture found one connector, `card0-DSI-1`, with cached status `connected`, encoder state `disabled` and zero cached modes. |
| 45.099683–45.102938 s | The aggregate and all six components were still bound. The DP encoder was absent from the deferred-probe list. |
| 90.911009 s | The warm return timer requested restart. |

The single-property DT change resolved the aggregate
block in the stock diagnostic. The connected cached
status establishes registration. Mode enumeration and
display output still need verification. The stock
driver logged that it could not enable the
`vs_drm/disp_component_reg_switch` trace event, then
registered the device successfully.

The VDDD capture retained all 31 events, with six
successful SMBus transfers and no disable invocation.
Ramoops and `SYSTEM_LAST_KMSG` matched on all 83
selected lines. Fastboot returned 133 seconds after
the B boot request. Stock A completed boot with
enforcing verity and matching VBMeta.

The next offline step is to trace how the stock CGYDA
connector populates modes. A later discovery fixture
can enumerate modes without a display commit once
the connector probe path and its power dependencies
are understood.

###### Offline CGYDA mode enumeration and DRM file lifetime

The DP-off boot registered `card0-DSI-1` with an
empty cached mode list. Reading the sysfs `modes`
file only displays that list. In exact D1
`drm_mode_getconnector` (`Image+0xba15a8`), the
branch at `0xba17bc`–`0xba17f4` calls
`fill_modes` only for a current DRM master whose
request has `count_modes=0`. A subsequent request
with a nonzero buffer count returns the cached
modes without invoking that branch again.

The stock Google connector's `fill_modes` points
to `drm_helper_probe_single_connector_modes`
(`Image+0xbddb24`). Its detect and force callbacks
are absent, as is the panel connector helper's
`detect_ctx`. The generic detect path defaults to
connected. The connector's `get_modes`
(`gs-panel.ko+0xb5b4`) calls `drm_panel_get_modes`,
which dispatches to `gs_panel_get_modes`
(`gs-panel.ko+0x24cc`). That function walks the
in-memory descriptor and duplicates accepted entries
into the probed mode list. The CGYDA filter at
`panel-gs-pkcgda.ko+0x4884` rejects rows with flag
`0x2000`. The stock connector, DSI encoder, DSI2H
and panel bridges, and DPU CRTC have no pipeline
`mode_valid` callback on this path. The inspected
enumeration callbacks require no panel power vote or
DSI transfer.

The normal CGYDA table contains six entries. The two
60 Hz entries set `0x2000` and are filtered. Four
120 Hz candidates remain across 1280×2856 and
1080×2410. Two of those use `vscan=2` and twice the
pixel clock of their same-resolution counterpart.
The 30 Hz entries are in a separate low-power table.
Descriptor selection and DRM filtering still apply,
so the exact userspace count is unverified.

A standalone DRM query would introduce a hardware
operation on close. Exact D1 `drm_release`
(`Image+0xbb13fc`) calls `drm_file_free` at
`0xbb14c8` before decrementing `open_count` at
`drm_device+0xe0`. `drm_file_free` invokes the
driver's `postclose` at `Image+0xbb1110`.
`vs_drm_postclose` (`vs_drm.ko+0x9d68`) sees a
count of one for the last file and calls
`drm_atomic_helper_shutdown` and `vs_dc_sw_reset`.
The reset path acquires FE and BE power and resets
and reinitializes the display controller. It can run
even when the client only queried modes.

No DRM client was added to the fixture. Before
introducing one, qualify its lifetime and teardown,
or capture enumeration passively from an existing
stock DRM client without opening another file. In
either case use `gs_panel_get_modes`, the DSI2H
host transfer callback and `vs_drm_postclose` as
separate trace points to distinguish enumeration,
panel traffic and teardown.

###### Passive stock D1 CGYDA mode trace

[The collector](bringup/stock-cgyda-mode-trace.sh)
arms a dedicated tracefs instance beside an existing
stock DRM client. It checks the D1 kernel release
and exact loaded module symbols. It opens no DRM
file and issues no DRM ioctl. Any enumeration,
transfer or close must come from the system under
observation.

| Event | Fields |
| --- | --- |
| `cgyda_getconnector` | Connector ID for a zero-mode-count query. A query only reaches enumeration if its caller is DRM master. |
| `cgyda_modes_enter`, `cgyda_modes_return` | Entry to `gs_panel_get_modes` and returned count or error. |
| `cgyda_dsi_enter`, `cgyda_dsi_return` | Stock DSI2H host packet type, TX and RX lengths, and transfer result. No payload is collected. |
| `cgyda_postclose` | Stock DRM driver's open count before it decides whether to run last-close shutdown and reset. |

The trace retains timestamps and task IDs. Match the
query and mode rows by task. Inspect the interval for
DSI work on that task and other threads. A transfer
within the window alone is insufficient to attribute
it to the query. A window without a mode entry did
not witness enumeration. A missing postclose row only
means none was observed in the capture window.

Use this helper only from an already privileged
shell with writable tracefs and loaded D1 display
modules. Stock production ADB previously could not
access tracefs. The guarded discovery ramdisk has
no existing Android DRM client. A live run needs a
context with both prerequisites. The helper does
not start or stop a display client to obtain events.

```sh
stock-cgyda-mode-trace.sh "$TRACEFS" "$BUSYBOX" arm
# Observe a short window of existing stock client activity.
umask 077
stock-cgyda-mode-trace.sh "$TRACEFS" "$BUSYBOX" dump > cgyda-modes.local
stock-cgyda-mode-trace.sh "$TRACEFS" "$BUSYBOX" cleanup
```

Stop if the symbols are unavailable or the instance
cannot arm. If dump reports overwritten events,
missed probes or an oversized capture, retain the
output privately as incomplete and clean up the
instance. Cleanup removes the dedicated group and
probes. Run cleanup after the capture even if dump
fails. Keep raw traces local.

Offline checks verified the probe arguments against
the factory Image and modules. Shell mocks exercised
arming, capture, cleanup, duplicate-arm refusal,
rollback after partial setup, and rejection of a
wrong kernel, a missing symbol, overwritten events
or missed probes. Live registration and capture
remain unverified.

###### Stock D1 access for the passive CGYDA trace

The saved D1 Android bugreport identifies a production
`user` build with `ro.debuggable=0`, `ro.secure=1`
and enforcing SELinux. The `shell` domain was denied
read and getattr on tracefs `available_events`.
The saved kernel config enables kprobes, kretprobes
and dynamic events. It lacks the function and ftrace
syscall tracers. Kernel support alone does not grant
the shell permission to create the collector's
instance and probes. This denial was recorded while
the bootloader was already unlocked.

The exact D1 ABL includes a boottrace command, and
the saved Android init log shows `atrace.rc` checks
`ro.boot.fastboot.boottrace` during late init. The
property was unset in the capture. This is a boot-time
path. It cannot arm the collector alongside the
already-running stock client, and the saved evidence
does not show that it creates the six custom probes.

The stock bugreport shows the System Tracing app,
`traced` and `traced_probes`. The probe daemon runs
in its own SELinux domain and the shell denial
does not establish what it can access. The
bugreport's Perfetto command found no session
eligible for export. It did not attempt to register
probes. The saved material contains neither a D1
probe policy nor a successful request for these
dynamic events, so a supported production Perfetto
route for the full collector remains unverified.

Exact D1 `gs-panel.ko` defines `panel/dsi_tx`
and `panel/dsi_rx`. Both event formats include
packet payloads. They are unsuitable for the
metadata-only collector. `vs_drm/disp_set_mode`
and `vs_drm/disp_commit_begin` describe programming
and commits. The inspected factory display modules
provide no corresponding native events for
`gs_panel_get_modes` or `vs_drm_postclose`.
Stock logged failure to enable the differently
named `vs_drm/disp_component_reg_switch` event
during boot. Finding a compiled tracepoint does
not establish production Perfetto access to it.

The existing stock Composer HAL dump already
reports six DSI-1 configurations. It lists the
four 120 Hz timings at 1280×2856 and 1080×2410
with their two clock variants, and two 30 Hz
timings. This confirms the reported stock timings
without opening a DRM file. It does not time
enumeration or establish transfer and teardown
behavior.

In the saved stock D1 Composer dump, the CGYDA
1280×2856 `vscan=1` row is enabled and carries the
DRM preferred flag `0x8`. Its pixel clock is 497640
kHz, with horizontal sync start, end and total
1360/1384/1430 and vertical sync start, end and
total 2868/2872/2900. These totals give exactly
120 Hz. Both `vscan=2` rows, including the 995280 kHz
1280×2856 timing, are disabled in that snapshot. Composer
reports config 5 (1080×2410 at 358680 kHz) as its
active and preferred configuration. Preserve the
distinction when choosing a first native mode.

Leave the exact collector unarmed on stock D1
unless a supported tracefs context alongside the
existing client is established. A normal System
Tracing capture can provide a display timeline
through the events available to that build. The
current discovery ramdisk has the tracing controls
but no stock Composer client to observe.

###### Stock CGYDA compression and mainline DSI2 reuse

In the exact D1 `panel-gs-pkcgda.ko`, the two
1280×2856 120 Hz rows (`.rodata+0x448` and `+0x6a0`)
both point to the DSC configuration at `.data+0x288`.
It specifies DSC 1.2, RGB conversion, block prediction,
8 bits per component, 8 compressed bits per pixel, two
640×24 slices and a 640-byte slice chunk. Running the
factory `drm_dsc_pps_payload_pack` as a pure ARM64
function with those configuration bytes produced a
128-byte PPS with SHA-256
`7c52ba59aa85542e0f8a578e11a93fb8306b36fa255bdf00f27840ec724eb8f1`.
This is an offline reference for the packer.

The panel enable path selects the configuration by
panel variant and resolution, sends the PPS via
`gs_dcs_write_dsc_config`, then sends the panel's
compression-enable command. On the scanout side,
`vs_dc_display_set_mode` reads the connector state and
calls `dc_hw_config_dsc` before `dc_hw_setup_display_mode`
(`vs_drm.ko` text `0x42ac0` and `0x42ad8`). The first
native pattern at this timing needs the compressed
stream and a matching panel configuration. The active
pixel payload alone would be about 10.53 Gbit/s at 24 bpp,
above the aggregate 5.56 Gbit/s of four 1390 Mbit/s lanes
before accounting for any protocol overhead.

The local mainline base (`82e3cf0b7f74`) has the
Synopsys `dw-mipi-dsi2` bridge. It matches the stock
host power register offset `0x0c` and supplies a
generic command packet transfer. DRM's DSC helpers
can pack a PPS and send it as a DSI picture parameter
set. The bridge itself defines `IPI_FORMAT_DSC` but
`dw_mipi_dsi2_ipi_color_coding_cfg` always selects
`IPI_FORMAT_RGB`. Sending the PPS would configure the
panel decoder. A native compressed stream also needs
matching DPU encoder and host IPI programming.

The bridge gets `pclk` and `sys` from the platform.
Its probe can pulse an optional `apb` reset, and its
mode setup performs host-local soft resets and writes
`PWR_UP`. Those operations depend on a qualified Malibu
APB clock and external reset sequence. Keep the bridge
disabled in Grizzly diagnostics until that prerequisite
is met. Keep the PHY TX and host read holds in place.

###### Attended stock D1 Perfetto result

On 2026-11-28 ADB verified slot A, `CP4A.261105.040.D1`,
completed boot and enforcing verity. Stock Perfetto v58.3
advertised `linux.ftrace` from `traced_probes` and the
SurfaceFlinger frame timeline. The existing Composer
service and SurfaceFlinger were running.

A 12-second trace requested `vs_drm/disp_set_mode`,
`vs_drm/disp_frame_done` and `power/cpu_frequency`. The
trace contained 94 CPU-frequency events. Its start-of-trace
setup stats listed both display events under
`unknown_ftrace_events`. This establishes that the stock
Perfetto producer could not find the two vendor events in
this session. The trace does not identify why the events
were unavailable to the producer.

A 20-second fallback also requested the generic DRM
`drm_vblank_event` and `drm_vblank_event_delivered`
tracepoints. The producer reported both as unknown.
The same trace enabled userspace `gfx` and SurfaceFlinger
frame timeline. It contained no frames, and the subsequent
power query showed the display session was dozing.
The 20-second rerun while the owner scrolled on awake stock A
recorded 256 completed display-level SurfaceFlinger timeline
rows with distinct display-frame tokens and 479 actual surface
rows. The retained display rows span 6.839 seconds. The 8 MiB
ring buffer wrapped, and Trace Processor reported four frame
timeline parser errors and one unpaired end event. The counts
describe the retained rows. SurfaceFlinger confirms live
Android frame activity. Vendor modeset and hardware frame
completion were unavailable in the separate ftrace check.

A second scrolling run enabled only
`android.surfaceflinger.frametimeline`. Perfetto recorded
both service boundaries, 20.004 seconds apart. The 1,280
completed display rows had distinct tokens and covered
19.722 seconds, from 3.7 ms after session start to 278.3 ms
before stop. The 8 MiB ring buffer recorded zero wraps,
overwritten bytes or chunks, discarded chunks, and writer
or sequence packet loss. Stock A completed-boot and
enforcing-verity checks matched before and after the capture.

The offline packet audit accounts for all 71 FrameTimeline
parser errors. On 41 actual surface-frame starts, the producer
sent `PRESENT_UNSPECIFIED` (`0`) explicitly in `present_type`.
Thirty of those starts also had that value in
`present_type_experimental`. Trace Processor v59.1 counts
each explicit value outside its accepted range (1–5) and
keeps the default unspecified classification. It still
creates the surface slice. [Pinned parser source](https://github.com/google/perfetto/blob/1e9c61e9844affd7dccd3d42d9ea9f3a3d10cf6d/src/trace_processor/importers/proto/frame_timeline_event_parser.cc).

Each of the 1,280 raw actual display starts has exactly one
later end with the same cookie. The raw and SQL display rows
match by display token, start timestamp and duration. The
4,458 actual surface rows also match by display token,
surface token, start and duration, with multiplicities. The
71 errors affect surface presentation classification. They
did not reduce either frame count in this capture.

After this stock Android session, take and verify a fresh
guarded nine-partition NV backup before the next Linux
slot B trial. Keep Android off between the rescue and trial.

###### Mainline DSI0 readiness after stock connector registration

The mainline prerequisite fixture at kernel
`16a63b142e0b` still uses wrapper `0x08` → BE
`0x200` → DSI0 `0x203`, then reads the pixel
clock rate through CPM selector 1. Its code logs
that host access was skipped and releases the
votes in reverse order. Neither a host nor PHY
consumer runs. The earlier powered-rate trial
recorded successful ON and OFF results and a
150 MHz pixel rate. The prerequisite-only bundle's
five saved image hashes still match.

Stock uses the same final vote sequence, but its
host probe runs after its own PHY initialization
and earlier genpd cycles. The new DP-off trace
again shows CD-PHY G301 initialization at
7.408682 s, host ID `0x30313130` at 7.408717 s and
version `0x1a000110` at 7.408759 s. This precedes
DSI2H component bind at 8.043425 s and the
connected connector sample at 11.063835 s. The
DP change resolved the later DRM aggregate block.
It added no independent APB or external-reset
observation. This fixture did not arm the earlier
clock and reset provider probes.

| Prerequisite | Offline result |
| --- | --- |
| Host APB gate | The pixel GET_RATE is for a different clock. Stock demonstrated effective APB access on its supplier path. ABL's bit 8 at `0x0f4196fc` remains an unqualified non-secure EL1 read. |
| Host external reset | ABL bit 12 at that word acknowledges the selected APB clock cell. Its coverage of downstream host resets is unverified. The PHY-local resets and the panel reset GPIO cover different blocks. |
| Firmware completion | The exact CPM path polls PSM3 and can discard a returned transition error before the deferred success notification. It supplies no independent APB or reset status. |

The offline checks did not qualify a mainline read
of ID, version or `pwr_up`. The existing
prerequisite-only package stays in place. A future
guard needs either an independently qualified
outside-aperture status for both conditions or an
audited stock-equivalent supplier sequence that
establishes both before the first host access.

###### Stock D1 PHY and genpd sequence before the first host read

Replaying the retained MBFS, APB, PHY-init and
genpd-worker captures gave the same 15 successful
replies for the three scoped domains. The pstore
and `SYSTEM_LAST_KMSG` traces agree in all four
captures. The table uses the genpd-worker trace clock.

| Phase | Stock D1 event |
| --- | --- |
| PHY attachment | The platform attaches the CD-PHY to DSI0 genpd before driver probe. Wrapper `0x08` → BE `0x200` → DSI0 `0x203` finish power-on at 6.331662 s. |
| PHY provider probe | Resolves the fixed 38.4 MHz `pllref`, creates both MMIO regmaps without an APB bus-clock handle, registers the PHY and enables runtime PM. |
| Post-probe idle release | `genpd_dev_pm_sync` queues the recorded worker. DSI0 → BE → wrapper OFF complete between 6.334095 and 6.335411 s. |
| Other parent transitions | Wrapper and BE cycle at 6.336984–6.340016 s, before the DSI host load marker. A wrapper-only cycle follows that marker at 6.412526–6.413023 s. |
| Final host attachment | Wrapper → BE → DSI0 ON complete at 6.433622 s. The host probe then calls `phy_init` on DSI0. |
| First observed reads | PHY `0x0f7c7124` returns `0x000001cc` at 6.444536 s. Host ID and version follow 8 and 12 µs later. The host reads `pwr_up=0` at 6.445875 s after runtime resume. |

The extra parent cycles recur in all four captures.
The trace filters downstream votes to DSI0 and does
not establish which other consumers caused the parent
cycles. They are part of the observed schedule.
Their necessity for DSI0 access is unverified.

The PHY provider's platform probe and its later
`phy_init` callback are separate. In the exact
`dw_dphy_init_g301` path, the first-resource
`0x7124` read takes the
`phy_common9_reg_lp_dco_clk_dyn_gating` bit and
caches it in software. The callback does not check the
read result. The captured read proves this PHY register
responded on stock. The PHY-local reset and shutdown
fields at the second resource's `0x28` are used by
later configure or power-off callbacks. Replaying
those writes before the first host read would change
the observed stock order.

In mainline `16a63b142e0b`, generic genpd already
has the parent traversal and post-probe sync worker.
The Malibu CPM onecell provider has no display
domains, and the fixture has no DSI0 PHY or host
consumer. The explicit MBFS diagnostic can be
extended to replay the observed vote order, but this
would reproduce requests and replies. Reproducing
stock's supplier lifecycle needs display-domain
topology and consumer bindings, plus attribution of
the remaining parent cycles.

Neither the PHY gating bit nor the scoped MBFS
replies independently verifies the host APB gate
or its external reset. No host read was added.
To attribute the parent cycles, a passive stock
follow-up can log the calling genpd device and
widen the MBFS filter to include sibling display
domains such as DSI1 `0x204`. That would test
whether the extra parent votes belong to other
consumers before treating them as DSI0 prerequisites.

###### Passive stock D1 genpd device and sibling trace

The updated `pack-stock-inventory.py
--dsi0-genpd-trace` fixture observes the stock
driver's existing domain operations. The two MBFS
filters now cover wrapper `0x08` and DPU resources
`0x200`–`0x205` (BE, FE0, FE1, DSI0, DSI1 and
DP0). It still stops at the stock DSI0 `pwr_up`
read. The NV guard precedes module load and the
independent 90-second return remains armed.

Two probes bracket `genpd_power_on` in exact D1
`__genpd_dev_pm_attach` at `+0x210` and `+0x214`.
They record the device name, domain and result.
The sync probe moves from `+0x3c` to `+0x34`,
where the device argument is still available.
It records the name alongside the domain and
work item. The worker probes observe that same
work item. All three domain filters now include
the seven audited display domains. These probes
read kernel device and genpd objects in RAM.
They add no MMIO, clock or reset operation.

Use `check-stock-dsi0-trace.py --require-genpd-devices
TRACE` on the retained trace. Compare MBFS rows by
task with each named attach interval. For the OFF
half, match a named sync with the worker by domain
and work item and compare the worker's MBFS replies.
The decoder prints local work numbers instead of
kernel addresses. A sibling reply within the matching
window can attribute a parent cycle. A parent-only
interval without a matching device remains unresolved.

Offline checks passed the retained genpd replay and
a synthetic DSI1 attach, ON/OFF and worker case.
The decoder rejected a missing device, a mismatched
attach result, a different DSI0 work item and a
legacy trace in the new required mode. Mock arming
verified both sibling filters and cleanup of all ten
probes. The image hashes, AVB, handoff bounds and
saved slot fit passed. The NV guard and display
module manifest match the previous fixture.

The replacement `init_boot` SHA-256 is
`15bf2b35158a776875ffd826098c154a9462fbb2a1b16f21e76ce03dc8a6bf91`.
The other four images are unchanged. Probe
registration and caller attribution remain pending
on hardware. A later attended slot B trial needs
a fresh verified NV backup and the usual stock A
return. This is a passive capture of stock probe
activity.

###### Attended stock D1 genpd device and sibling trace

On 2026-11-27 the read-only rescue copied all nine
NV partitions (3,392,151,552 bytes) privately to
the Mac and verified their SHA-256 hashes. Both
slot B staging passes matched the full
`vendor_boot_b` readback. The follow-up booted
once on B and passed the NV guard.

| Trace time (s) | Observation |
| --- | --- |
| 6.461384–6.466466 | `f7c0000.dw_mipi_cdphy` attaches to DSI0, queues its genpd worker and completes the child-to-parent OFF sequence. |
| 6.466438–6.472364 | `f7e0000.dw_mipi_cdphy` attaches to DSI1. Wrapper → BE → `0x204` ON complete on its attach task. The same named device queues the DSI1 work, which gets `0x204` OFF at 6.471857, then releases BE and wrapper. |
| 6.543714–6.545605 | The display-module task sends wrapper ON. A worker sends wrapper OFF. No matched display attach or sync names a device for this pulse. |
| 6.562356–6.566930 | The final rise enables wrapper, BE, DSI0, DSI1, FE0 and FE1, all on the display-module task. |
| 6.575735–6.577896 | The DSI0 host attaches after those votes. The stock PHY read, expected host ID and version, and `pwr_up=0` follow. |

The first apparent parent-only cycle belongs to the
sibling DSI1 PHY. The earlier filter hid its
`0x204` requests and replies. The second pulse is
still unattributed. It falls after `vs_drm.ko` load
and before the same task logs the display
controller's IOMMU attach. The B0 tree places
`f190000.disp_smmu` on the wrapper domain and
connects `f600000.dc9x00` to that SMMU. This makes
display-SMMU runtime PM a candidate. The Linux
driver core can acquire runtime PM references to
existing suppliers before configuring DMA during
probe. The current runtime-PM trace is scoped to
the DSI0 host. A follow-up should include the
SMMU and DC device names and capture the wrapper
vote call path to check this hypothesis.

The capture retained all 104 events, and ramoops
and `SYSTEM_LAST_KMSG` matched on 144 selected
lines. The device-aware decoder passed. The warm
return requested restart at 90.890568 s. Fastboot
returned 133 seconds after the B boot request.
Stock A completed boot with enforcing verity and
the original VBMeta digest.

###### Offline stock D1 wrapper vote and display runtime PM trace

The latest `pack-stock-inventory.py --dsi0-genpd-trace`
fixture extends the named genpd capture. The runtime PM
filter retains `f7d8000.dsi2host` and adds
`f190000.disp_smmu` and `f600000.dc9x00`. It records
resume, suspend, idle, return and status events for
those devices. A tracefs stack trigger on the existing
`power_controller/send_mail_mbfs` event captures callers
only for wrapper resource `0x08`. The saved exact D1
kernel config enables event tracing and stack traces.

Use `check-stock-dsi0-trace.py --require-wrapper TRACE`.
The decoder matches each stack to its preceding
wrapper request on the same task and CPU and reports
the symbolic call path alongside the runtime PM
events. Compare the wrapper-only ON and OFF stacks
with the SMMU and DC events to test the supplier
runtime PM hypothesis. Leave attribution open if the
stack or device evidence is inconclusive.

The NV guard, sibling MBFS filter, existing DSI0
`pwr_up` stop trigger and independent 90-second
return remain in the fixture. It adds no register
access or display operation. Mock arming verified
the filters and trigger cleanup. The offline decoder
replayed the previous hardware capture unchanged and
accepted synthetic SMMU/DC events and wrapper stacks.
It rejected a stack on the wrong task, a missing stack
and a legacy trace in wrapper-required mode.

All five image hashes, AVB, handoff bounds and saved
slot fit passed. The four baseline images and the
display module manifest are unchanged. The replacement
`init_boot` SHA-256 is
`3f41787eea7c0cdf87e4a13eb9b8a65d5e74d2831bb051aaee7a98d66c97726f`.
Hardware trigger registration and attribution remain
pending. A later attended boot requires a fresh
verified nine-partition NV backup and stock A return.

###### Attended stock D1 wrapper vote and display runtime PM trace

On 2026-11-27 the first rescue did not enumerate
over USB. The retry copied all nine NV partitions
(3,392,151,552 bytes) privately to the Mac and
verified their SHA-256 hashes. The trace image
staged with a matching full `vendor_boot_b`
readback, booted once on B and passed the NV guard.

The second pulse is the stock display SMMU resuming
and suspending during IOMMU setup. The ON call stack
runs from `platform_dma_configure` through
`of_iommu_configure`, `kvm_arm_smmu_probe_device`,
`device_link_add`, `rpm_resume` and
`genpd_runtime_resume`. The OFF stack runs through
`pm_runtime_work`, `rpm_suspend` and
`genpd_runtime_suspend`. Both match the named
`f190000.disp_smmu` runtime PM events.

| Trace time (s) | Witness |
| --- | --- |
| 6.460979–6.460982 | SMMU resume starts and enters `RPM_RESUMING` on the display-module task. |
| 6.461050–6.462468 | That task sends wrapper `0x08` ON and receives result 0. |
| 6.462506 | SMMU becomes `RPM_ACTIVE` with zero usage references, and the task requests idle. |
| 6.462543–6.462545 | A worker starts SMMU suspend. |
| 6.462562–6.462746 | That worker sends wrapper OFF, receives result 0 and completes SMMU suspend. |

The later wrapper ON has a different stack through
`of_platform_populate` in `dc_probe`. The separate DC
runtime PM rows and the previously attributed DSI1
attach and idle cycle were retained. The wrapper
pulse is a consequence of stock supplier runtime PM.
The trace does not independently qualify the APB
gate or external reset for mainline host access.

The trace retained all 194 records and decoded
seven wrapper stacks and 78 scoped SMMU/DC runtime
PM events. Ramoops and `SYSTEM_LAST_KMSG` contained
identical trace rows and matched on all 391 selected
lines present in both. Six earlier selected lines
were present only in ramoops. Fastboot returned
133 seconds after the B boot request. Stock A
completed boot with enforcing verity and original
VBMeta.

###### Offline mainline mapping of the stock display power paths

Compared the audited D1 B0 tree and retained genpd
and runtime PM captures with mainline fixture
`16a63b142e0b`. The mainline Grizzly DT has no
display SMMU, DC, CD-PHY or DSI2H node. Its Malibu
CPM onecell provider has no display domains.
Wrapper, BE and DSI0 are exercised through the
diagnostic's explicit MBFS votes.

| Stock path | Mainline mapping and DSI0 relevance |
| --- | --- |
| Display SMMU | `f190000.disp_smmu` is a wrapper `0x08` consumer. Its DT client is `f600000.dc9x00`, with streams `0x8000`–`0x801f` and nested translation. Stock's KVM SMMU probe calls `device_link_add` for the DC consumer. The observed resume occurs during DMA configuration and the idle worker releases the wrapper. |
| Mainline SMMU | The fixture enables `CONFIG_ARM_SMMU_V3`. The upstream `arm_smmu_probe_device` does not add the stock runtime PM link. Its IOMMU core's `iommu_device_link` creates sysfs links. Generic device links and runtime PM can represent a supplier relationship once the bindings exist. Display DMA and SMMU power handling need separate qualification before scanout. |
| DSI1 | The available PHY at `f7e0000.dw_mipi_cdphy` owns `DpuDsi1.v` (`0x204`), with its own TX and APB resources. DSI0 and DSI1 share the fixed 38.4 MHz reference and the BE → wrapper ancestors. The DSI1 host is disabled. Mainline checks the inherited DSI1 vote and does not drive it in this diagnostic. |
| DSI0 | The DSI0 PHY and host both reference `DpuDsi0.v` (`0x203`) under BE `0x200` and wrapper `0x08`. The host's only PHY phandle points to `f7c0000.dw_mipi_cdphy`. Neither node has an IOMMU link. The stock host initializes its own PHY before reading ID and version. |

The stock probe has no direct dependency on the
DSI1 PHY or display SMMU for those register reads.
The DP-in capture read the expected host ID and
version even though the display aggregate remained
unbound and registered no connector. The stock
captures do not isolate the effect of omitting the
earlier sibling or SMMU cycles on shared physical
state. Their observed order does not make explicit
replay part of a minimal DSI0 host fixture.

The scoped mainline path would hold wrapper, BE
and DSI0 while the DSI0 PHY and host consumers run.
Its first host access still needs separate evidence
for the APB gate and external reset. The SMMU
pulse establishes wrapper runtime PM, the DSI1
pulse establishes sibling MBFS activity, and the
DSI0 PHY init sample reports a PHY-local gating
control. None is a host APB or reset readback.
The ABL APB acknowledgment at `0x0f4196fc`
still lacks qualified EL1 access and its reset bit
covers only the selected clock cell. No host reads
or display bindings were enabled.

###### Offline minimal mainline DSI0 genpd and PHY scaffold

The [kernel branch](https://github.com/adrienlacombe/linux-omarchy-mobile/tree/grizzly-dsi0-scaffold)
at `11c4782eb636dee4776827fbdb580e69cbcfbedb`
adds Grizzly CPM indices 8, 9 and 10 for wrapper
(MBFS `0x08`), BE (`0x200`) and DSI0 (`0x203`).
The provider links wrapper → BE → DSI0. It performs
the first lookup when a consumer powers on and
releases only a vote acquired by the driver.
The existing manual wrapper diagnostic option
keeps the old provider layout and avoids competing
for the same firmware votes.

The Grizzly tree describes one disabled C/D-PHY
with TX registers at `0x0f7c0000` (size
`0x18000`), the PHY APB bank at `0x0f7d8800`
(size `0x800`), DSI0 genpd, and a fixed
38.4 MHz reference. With
`CONFIG_PHY_GOOGLE_MALIBU_CDPHY`, its scaffold
registers a generic PHY provider without mapping
the registers or enabling a clock. Its init and
power-on callbacks return `-EOPNOTSUPP`.
The mainline DTB has no display SMMU, DSI1 or
DSI0 host node. Host ID, version and `pwr_up`
remain gated on independent APB and external reset
qualification.

The full ARM64 Image linked, including both drivers.
The changed objects and Grizzly DTB compiled with
`W=1`. Checkpatch passed with its new-file reminder
suppressed after the paths were added to the
Google Tensor entry in `MAINTAINERS`. DTB inspection
verified the two ranges, the 38.4 MHz clock phandle,
domain index 10 and disabled status. Both YAML
files parse. Full DT schema validation requires
`dtschema`, which was unavailable in the offline
toolchain. The build was not booted.

###### Slot B mainline DSI0 PHY vote fixture

Build the scaffold kernel at `11c4782eb636dee4776827fbdb580e69cbcfbedb`
with `CONFIG_PHY_GOOGLE_MALIBU_CDPHY=m` and module unloading enabled.
Use the read-only v73 LUN 0 diagnostic configuration and add
`bringup/dsi0-phy-scaffold.dtso` to its overlays. That overlay changes
only the DSI0 PHY status to `okay`. The PHY module and diagnostic
script go in the standalone inventory initramfs via
`pack-mainline-inventory.py --dsi0-phy-scaffold PHY_MODULE` with
the matching rescue cpio. The fixture keeps the manual display vote
diagnostics off and omits DSI1, the display SMMU and the DSI0 host.
The scaffold driver performs no PHY register accesses or host reads.

The slot B inventory arms the 90-second warm return and disables
module autoload. PID 1 verifies the metadata-only GPT scan, all 42
read-only and unmounted LUN 0 partitions, and the v73 block
comparison. It waits for the kernel to retire the guarded disk
before inserting the PHY module. It checks for the `malibu-cdphy`
platform binding, unloads the module, and waits for the genpd
power-off worker. The retained console should show the following
six transitions, with each acknowledgement followed by its
matching vote readback.

| Phase | Order |
| --- | --- |
| ON | wrapper `0x08` → BE `0x200` → DSI0 `0x203` |
| OFF | DSI0 `0x203` → BE `0x200` → wrapper `0x08` |

Only newly acquired votes are released. An inherited vote, failed
probe, or missing or out-of-order reply leaves the trace incomplete
and the independent return active. The fixture keeps the
read-only UFS guard and mounts no UFS partitions. A fresh verified
private NV backup is needed for an attended trial, followed by a
return to stock A and retrieval of the retained console. APB gate
and external reset qualification is still required before any host
read.

The offline build on 2026-11-27 used kernel release
`7.3.0-rc6-omamobile-grizzly-dsi0-phy-fixture`. The ARM64 Image and
board DTB built, and the PHY module built with `W=1` and matching
vermagic. Readback verified the five images against the saved D1
slot capacities and ABL handoff limits, checked the AVB signatures
on `boot` and `init_boot`, and compared the embedded DT and initramfs
against their inputs. The DT diff showed only the one status change.
Mocked traces passed the vote-order and storage-guard checks.

The single attended slot B boot on 2026-11-27 followed a fresh
private backup of all nine partitions. The guard reported each
target read-only and unmounted. The local hashes matched the
independent on-phone hashes and the completed manifest.
Android stayed off between the rescue and the fixture.

Ramoops and `SYSTEM_LAST_KMSG` agree on the live sequence.
LUN 0 verified all 42 partitions read-only and unmounted, using
seven GPT metadata reads and the successful v73 byte comparison.
After the disk retired, the PHY module bound and released all
three votes it had acquired.

| Phase | Vote order | CPM acknowledgement | Vote readback |
| --- | --- | --- | --- |
| ON, 6.468–6.470 s | wrapper → BE → DSI0 | `5` for each | `1` for each |
| OFF, 6.473–6.474 s | DSI0 → BE → wrapper | `0` for each | `0` for each |

The fixture reported completion at 6.510 s and requested the
warm restart at 91.243 s. Stock D1 returned on slot A with
enforcing verity and the original VBMeta digest. The DSI0 host
stayed disabled, so the vote cycle did not qualify the host APB
gate or external reset.

###### Offline APB and external-reset qualification after the PHY trial

The retained console puts DSI0's ON vote readback at 6.470088 s
and its OFF acknowledgement at 6.472960 s. The 2.872 ms gap
bounds the opportunity to sample the powered child in this
fixture. The stock clock/reset trace read host ID and version
8.888 ms after its final ON reply. That stock interval supplies
no minimum settle time. For a future qualified status source,
take the powered sample synchronously after the ON reply with
wrapper, BE and DSI0 held. Sample the released state after DSI0
OFF while BE and wrapper are still held, so their later releases
cannot explain the result. A periodic dashboard read cannot
reliably capture these phases.

The mainline readback issues an MBFS value read for the resource
handle and accepts a Boolean reply. D1's physical transition,
when needed, polls LPCM PSM3. The new ordered replies confirm
genpd ownership and release. The trace supplies neither the APB
gate bit nor the external reset state.

The exact D1 GC FDT gives the APB, system, pixel and PHY clock
cell words the same `0x30300` rule on
`0x0f419000`–`0x0f419fff` in the LPCM firewall. The stock
host and PHY APB accesses at `0x0f7d8000` and `0x0f7d8800`
are covered by a separate DPU bridge rule, `0x30303`.
The saved stock bugreport has host and PHY witnesses but no
LPCM acknowledgement address or `dpu_dsi0_apb_clk` status.
The additional `CLK_STATUS_MASK` check in exact CPM text
`0x3ce00`–`0x3cebc` belongs to the MNA platform path.
It polls gate words relative to `0x6b830660`, outside the DPU
LPCM, and cannot supply the DSI0 status.

The status gate remains closed. Bit 8 of `0x0f4196fc` is a
candidate APB acknowledgement once the exact access has a
qualified read path. Bit 12 acknowledges that clock cell.
Before using any reset observation to permit host access,
identify the reset signal at the host boundary or document
how the clock-cell acknowledgement covers every external
reset needed for the first host read. The D1 PMU and CPM
status services audited above offer neither a path to the
APB cell nor that reset evidence. Leave direct status and
host reads disabled until these checks pass.

###### D1 APB clock-cell reset scope

ABL resolves `dpu_dsi0_apb_clk` to the group-4 cell at
`0x0f4196e0`. The direct reset helper at `0x7b5b4`
temporarily changes the cell's control at offset `0x00`,
sets the active-low reset request in bit 0 at offset `0x0c`,
polls bit 12 at offset `0x1c`, and restores the control
word. For this descriptor the request and acknowledgement
addresses are `0x0f4196ec` and `0x0f4196fc`. A set bit 12
is the deasserted acknowledgement for that request.
The gate uses a separate request at offset `0x04` and a
separate acknowledgement, bit 8 of the same status word.
The reset helper touches only the selected clock cell.
Firmware therefore identifies its reset handshake but
does not identify the downstream reset nets or where the
acknowledgement is generated relative to those nets.

CPM's low-level read-only getter at `0x19190` extracts that
same single bit from the selected cell. The reset-status
handler at `0x3859c` looks up a reset group and packs one
acknowledgement bit per listed cell into a reply bitmask.
The grouping comes from the firmware table. There is no
implicit whole-block reset indication in the low-level
getter. The lookup rejects display LPCM `0x23` before
reading any cell. The seven reset provider children in both
stock D1 B0 trees with DTBO entry 19 applied also omit
`0x23`. Neither the DSI0 host nor its CD-PHY has a reset
phandle in either merge.

The stock host ID and version witness establish that the
host APB interface responded in the stock sequence.
The later `pwr_up` read covers an internal host enable
field. The PHY's reset and shutdown fields cover its
separate APB bank. None supplies a readback of the external
host reset boundary. No mapped D1 status source was found
for that boundary. Before adding a test, obtain a reset
routing description or a supported readback whose
documented scope covers the external host reset inputs, and
qualify the exact access path. DSI0 host and direct LPCM
status reads stay disabled.

###### Stock D1 dump and bootloader reset-routing audit

The factory FBPK scan found four embedded FDTs in GC. The
registry, memory configuration and placeholder contained no DPU
reset route. The access-control FDT lists DPU
`sre_sswrp_info` and gives `sre_component_info` to the LPCM,
GIA and bridge register firewalls. The surrounding firmware
identifies SRE save/restore of access-control state. The DPU
entries provide address ranges and permission metadata, with
no DSI0 reset signal, sink or status selector.

The factory `vendor_kernel_boot` ramdisk includes three
display register-dump paths. Their scope is visible in the
D1 module code.

| Stock path | Readback and side effects |
| --- | --- |
| DSI2H `reg_dump_show` at `0x86ac` | Passes the mapping from platform resource 0 to `gs_reg_dump_with_skips`. For DSI0 that is the host aperture at AP `0x0f7d8000`. The runtime-PM check precedes the dump and supplies no independent reset evidence. |
| CD-PHY `reg_dump_show` at `0xb910` | Dumps the two PHY banks from the PHY instance. Those cover CD-PHY TX and its local APB bank. Both are outside the host reset path under investigation. |
| Display controller `dc_hw_reg_dump` at `0x36c1c` | The regular dump uses the FE/BE resource. It writes the three FE/BE controls at offsets `0x140`, `0x40140` and `0x80000` before collection and restores them afterward. It cannot serve as a passive DSI0 reset read. |

The saved stock display bugreport includes no attached display
register dump or reset-routing data. The audit identified no
supported readback of the external DSI0 host reset inputs and
no hardware routing description that links all those inputs
to the APB clock cell. Both the DSI0 host aperture and the
unqualified clock-cell status word remain excluded from the
mainline diagnostic.

###### Public Malibu DSI0 reset source audit

The public [Spacecraft source snapshot](https://github.com/GrapheneOS/kernel_pixel/commit/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122)
identifies build `CP41.260831.019`. It contains the Malibu
and Grizzly vendor source paths. The D1 GKI hash resolves
to [Android common](https://android.googlesource.com/kernel/common/+/f5369e7496cb231d2b41cbca078b8b69160ac22d),
whose binding, reset and display bridge trees lack the
Malibu DSI2H and CPM provider code. The Spacecraft snapshot
corroborates the D1 binary and DT observations below. Its
build metadata predates D1.

- The [Malibu DPU DTSI](https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/devices/google/malibu/dts/malibu-dpu.dtsi#L271-L294)
  gives the host and PHY the DSI0 power domain. The host
  references the PHY and the DSI0 event IRQ. Neither node
  supplies a reset phandle. The
  [Grizzly display overlay](https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/devices/google/spacecraft/dts/malibu-grizzly-display.dtsi#L26-L73)
  supplies panel reset GPIOs and sets the DSI0 data rate.
- The downstream [host binding](https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/Documentation/devicetree/bindings/display/verisilicon/vs-dsi2h.yaml)
  describes the DSI event/error interrupt and PHY link. The
  [PHY binding](https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/Documentation/devicetree/bindings/display/synopsys/dw-cdphy.yaml)
  describes the PLL reference clock. Neither specifies
  an external host reset connection or status source. The
  PHY schema lists the older compatible variants, so the
  Malibu DTSI is the wiring evidence for its v2 node.
- The [Malibu reset provider](https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/devices/google/malibu/dts/malibu-base.dtsi#L1335-L1380)
  has the same seven reset groups as the saved D1 B0 merges
  and omits DPU LPCM `0x23`. The [reset driver](https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/soc/rdo/drivers/rst/google/rst-cpm-main.c#L169-L225)
  provides assert and deassert. It lacks a reset status
  callback and its two debugfs entries have no getter.
- The [Malibu GIA test map](https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/devices/google/malibu/dts/malibu-gia-test.dtsi#L371-L473)
  names software-reset-done events for display FE and BE.
  DSI0 has the DSI subsystem event IRQ in its own row,
  with no named external host reset acknowledgement.

The public sources supply no DSI0 external reset routing
or supported read-only status for that boundary. The
clock-cell handshake remains the only identified APB reset
acknowledgement. Host reads and direct LPCM status reads
stay disabled.

###### D1 vendor source provenance and comparison

The public kernel manifest does not list a Malibu or Spacecraft
vendor branch for `CP4A.261105.040.D1`. The relevant public
[Spacecraft branch](https://github.com/GrapheneOS/kernel_pixel/commit/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122)
and its checked mirrors point to `CP41.260831.019`. The
[Android common revision](https://android.googlesource.com/kernel/common/+/f5369e7496cb231d2b41cbca078b8b69160ac22d)
matches the D1 GKI release hash. The D1 vendor DTS and module
source revisions remain unidentified, so the comparison below
uses the exact saved D1 factory binaries against the earlier
public vendor source.

- Both D1 base DTBs merged with B0 entry 19 match the public
  source for the DSI0 host and PHY register ranges, the PHY link,
  DSI0 power resource `0x203`, and GIA interrupt 20. Both host
  and PHY still lack reset mappings. All seven CPM reset group
  IDs and reset counts match. DPU LPCM `0x23` remains absent.
- The DSI0 system, PHY, IPI and low-power transmit clock values,
  the Grizzly overlay's data rate, and the DSI0 pixel-clock
  LPCM/selector pair agree. They add no APB or external reset
  status channel.
- D1 `rst-cpm.ko` registers only assert and deassert. The
  `reset` and `status` slots are zero in the operations table
  and have no relocations. This matches the public driver's
  initializer. The D1 DSI2H probe likewise initializes the PHY
  before reading its host registers, with no reset-control API
  call in the probe.

There is no observed D1 change in the compared reset routing
or status interfaces. A source-level comparison still requires
the exact D1 vendor drop. The checked interfaces supply no
independent host reset evidence, so direct host and LPCM
status reads stay disabled.

###### Stock D1 first PHY read and mainline qualification

The D1 PHY provider probe obtains `pllref`, and
`cdphy_init_g301` maps the TX and PHY APB resources and
allocates the regmap fields. Its mapping calls use no
bus-clock handle. The provider probe enables runtime PM.
The later DSI2H consumer calls `phy_init` before enabling
its own runtime PM or reading host ID and version.
The exact D1 PHY init callback at `0x2a8` issues a
32-bit `regmap_read` of TX offset `0x7124` at
`0x2f0`, copies bit 8 to the software PLL flag and
returns zero. It performs no PHY register write. The
first read samples the LP-DCO dynamic-gating control.
It does not measure PLL lock or an external reset.

The word at AP `0x0f7c7124` is within the TX resource
and independently falls within the D1 GC bridge rule
`0x30303` for `0x0f7c3000`–`0x0f7c9fff`. In four
retained stock captures, it returned `0x000001cc`
9.785–11.229 ms after the last DSI0 ON reply. The two
captures that included sibling votes also show DSI1,
FE0 and FE1 ON when the PHY read ran. The other two
filtered those domains out. Those observations prove
the read path on the stock sequence and leave the
necessity of the sibling domains and timing unresolved.

The mainline scaffold proved only the wrapper, BE and
DSI0 vote cycle. It omitted those sibling domains and
received the DSI0 OFF acknowledgement 2.872 ms after
the ON readback. Neither the MBFS readback nor a fixed
delay qualifies the TX aperture under the isolated
mainline setup. A future single-word diagnostic needs
independent evidence that the PHY TX aperture is
accessible with that setup. Keep the NV guard and timed
return on any such fixture. No PHY-read image was built.
The existing no-MMIO PHY scaffold and DSI0 host hold
remain in place.

###### D1 PHY TX readiness with sibling domains off

The Malibu DT gives the DSI0 PHY the DSI0 power domain.
The DSI0 domain's ancestors are BE and the DPU wrapper.
DSI1 and FE0 are other BE children, and FE1 is a child of
FE0. None is an ancestor of the DSI0 PHY.

The exact D1 CPM display records at `0x62f38` and
`0x62f6c` both select PSM2 for FE0 and FE1. The DSI0
and DSI1 records at `0x62fa0` and `0x62fd4` both select
PSM3. Decoding the DSI0 and DSI1 ON/OFF handlers gives
the following PSM3 state meanings.

| PSM3 state | DSI0 | DSI1 |
| --- | --- | --- |
| 0 | ON | ON |
| 1 | ON | OFF |
| 2 | OFF | ON |
| 3 | OFF | OFF |

DSI0 ON from state 3 requests state 1 through
`0x3a3f0` and `0x3b8b0`. Both DSI0 ON transition
callbacks set mask `0x0c` at CPM `0x6f40a000`.
DSI1 ON sets `0x14` at the same address and clears
its own bit 4 on OFF. The DSI0 handler samples PSM3
and does not test PSM2. This establishes a DSI0-only
firmware state and separate FE sequencing. It does
not identify which physical conditions make the TX
bank respond from Linux.

Across six distinct retained stock reads of
`0x0f7c7124`, all returned `0x000001cc`. The two
captures with sibling vote coverage show DSI1, FE0
and FE1 ON at the read. The four narrower captures
give no sibling state. No retained witness has all
three verified OFF.

Read-only MBFS queries could establish the sibling
vote values. PSM3 state 1, if available from a
qualified firmware export, would corroborate DSI0
sequencer state. The audited D1 paths offer no
qualified PSM3 export or PHY TX clock/reset readback,
and neither vote values nor PSM3 alone validate
the TX transaction. Keep direct PHY TX and DSI0 host
reads disabled. There is no PHY-read fixture from
this audit.

###### Offline DSI0 sibling MBFS vote fixture

The slot B fixture uses kernel `e9579f8e084af38118ac4f24f67bb1e62a0041e0`
on `grizzly-dsi0-scaffold`. It enables
`clk_google_malibu_cpm.display_dsi0_siblings=1` in the fixture's vendor
command line and pairs `pack-mainline-inventory.py --dsi0-phy-scaffold`
with `--require-dsi0-sibling-votes`. PID 1 checks the parameter is enabled
before inserting the scaffold. The normal descriptor and scaffold keep
their existing defaults.

The CPM driver uses MBFS lookup and read requests for `DpuDsi1.v`,
`DpuFe0.v`, and `DpuFe1.v`. It samples immediately before and after
DSI0 ON and before and after DSI0 OFF, with wrapper and BE held. A
nonzero vote or failed read before ON blocks the DSI0 request. Later
observations never block release of a vote the fixture owns. The fixture
requires all four ordered `display-dsi0-siblings` lines to report
`dsi1=0 fe0=0 fe1=0`, plus the existing acknowledgments and readbacks
for wrapper → BE → DSI0 and the reverse release. These sequential
samples establish the reported votes at those checkpoints. Physical
power, intermediate changes, and PHY TX readiness remain unverified.

The fixture issues no sibling vote writes and makes no DSI0 PHY TX or
host reads. It runs after the NV guard verifies the 42 read-only,
unmounted LUN 0 partitions and the disk retires. The 90-second timed
return remains armed independently of the diagnostics.

Offline checks covered the ARM64 build, the actual packaged command
line and ramdisk, the PHY-only DT overlay, the signatures on boot and
init_boot, the ABL handoff, and slot B fit against saved D1 metadata.
The log checker accepted the required sequence and rejected active
votes, read errors, missing or misordered samples, and failed release.
The verified five-image archive has SHA-256
`2fc9d727eabfa6de261e6f0d659fd620cb0b9b30fa2607a8ee44d791c6e0aaa0`.

###### Attended DSI0 sibling MBFS vote trial

On 2026-11-27, the guarded rescue backed up all nine NV partitions
before the single MBFS fixture boot. The private copy is 3,392,151,552
bytes. The rescue verified the partitions were read-only and unmounted,
and the saved SHA-256 hashes matched the on-device hashes. Stock
Android stayed off between the rescue and the fixture.

Ramoops and `SYSTEM_LAST_KMSG` agree on all four samples.

| Checkpoint | Boot time (s) | DSI1 | FE0 | FE1 |
| --- | ---: | ---: | ---: | ---: |
| Before DSI0 ON | 6.424467 | 0 | 0 | 0 |
| After DSI0 ON | 6.425383 | 0 | 0 | 0 |
| Before DSI0 OFF | 6.428641 | 0 | 0 | 0 |
| After DSI0 OFF | 6.429298 | 0 | 0 | 0 |

The LUN 0 read-only check passed for 42 partitions, the GPT scan used
seven metadata reads, and the v73 comparison passed. The fixture then
bound the DSI0 PHY scaffold, acquired wrapper → BE → DSI0, released
DSI0 → BE → wrapper, and reported completion at 6.463 s. The kernel
reported no SCSI disks before requesting its warm restart at 90.198 s.

Stock D1 booted on A with enforcing verity and its original VBMeta
digest. The trial verifies the three MBFS votes at the four sampled
checkpoints. Physical power and PHY TX readiness remain unverified.
PHY TX and DSI0 host reads stayed disabled.

###### D1 PHY TX clock and reset prerequisites after the MBFS trial

Re-extraction of the pinned D1 `mipi-cdphy.ko` and both stock
Grizzly B0 DT merges agrees on the driver-visible inputs.
The DSI0 PHY is on genpd `0x203` and gets only the fixed
38.4 MHz `pllref`. It has no reset phandle. The driver passes a
null clock ID to the MMIO regmap setup for both resources
(`0x33fc` and `0x3470`). The first observed TX load is the
read of `0x0f7c7124` at `0x2f0`. The stock host calls PHY
init at `mipi-dsi2h.ko` `0x24e0`, before reading its own
registers. The PHY callback issues no clock-gate enable or
external reset call. Bit 8 of the first word is LP-DCO
dynamic-gating control. PLL lock uses a separate bit in
the second aperture and is polled during later configuration.

The PHY-local `phy_rst_n` and `shutdown_n` fields are bits 0
and 1 in the second aperture at `0x0f7d8828`. Stock Linux's
initial configuration path requests both bits clear at
`0x11bc` and `0x11d8`, then updates TX offset `0x38d0`
at `0x11f4` before the later release calls. The field is
allocated from the TX regmap at `0x6dc8`. Exact D1 ABL
likewise clears both local bits at `0xf2c14`–`0xf2c44`
and issues a TX `+0x38d0` read-modify-write at `0xf2c68`
before releasing them. Both sequences expect TX register
access during PHY-local reset. The Linux writes do not
independently confirm the latch state. ABL votes FE0 and
FE1 ON at `0x7c11c` and `0x7c128` before configuring the
PHY, including its single-DSI path. Neither sequence
qualifies the external TX register-bus reset with all three
siblings off.

The exact CPM LPCM `0x23` clock record at `0x658c6` gives
selector 3 the gate `0x6f4197a0`. ABL calls this cell
`dpu_dsi_phy_clk` at `0x1f5300`. The merged stock trees
label it `dpu_dsi1_phy_clk` and have no clock consumer for it.
Both PHYs consume the fixed reference. The firmware clock
query for selector 3 could report that gate's bit 8, but its
routing to the DSI0 TX register interface is unresolved.
The direct clock-cell reset acknowledgment at
`0x0f4197bc` bit 12 has neither a supported CPM reset-status
path nor an EL1 read witness.

The attended diagnostic confirms zero sibling votes at all
four checkpoints. DSI0's deferred acknowledgment and
Boolean readback only establish the MBFS vote. Exact CPM
can skip the PSM3 transition when the state already matches
and can discard a transition fault before caching ON. Even
a successful PSM3 poll does not sample the TX bus gate or
external reset. All retained stock EL1 reads of
`0x0f7c7124` with sibling coverage had DSI1, FE0 and FE1
ON. The GC bridge rule covers the address, but does not
establish the bus response under the isolated setup.

**Access decision.** The external TX clock and reset path
remains unqualified for `0x0f7c7124` with all three siblings
off. Qualification needs a trusted readback tied to the
TX register interface or a matching existing EL1 read with
the three votes known off. Keep PHY TX and DSI0 host reads
disabled. This audit used only saved artifacts and built
no diagnostic image.

###### D1 LPCM selector 3 gate and reset status

Exact D1 ABL group 4 describes separate clock cells at AP
`0x0f4196e0` (DSI0 APB), `0x0f419720` (DSI0 system),
`0x0f419760` (DSI0 pixel), `0x0f4197a0` (DSI PHY),
and `0x0f4197e0` (DPU PHY reference). The DSI PHY cell's
ABL descriptor at `0x1f5300` has clock selector 3 and
reset selector `-1`. The CPM record at `0x658c6` binds it
to LPCM `0x23` at the alias `0x6f4197a0`. The record
has no downstream consumer information. The two B0 trees
label selector 3 `dpu_dsi1_phy_clk` and have no clock
consumer for it. Both PHY nodes use the separate fixed
`pllref`. ABL's DSI0 controller record identifies the
TX and PHY APB resources. The inspected display path
selects the DSI0 power domain and calls the PHY setup
without tying those resources to selector 3. The firmware
and DT names leave the physical TX clock route unresolved.
The saved Malibu binding uses the unindexed constant
`DPU_DSI_PHY_CLK` for selector 3.

ABL's `0xf26a8` call uses a different selector numbered 3:
the internal aperture for the DPU wrapper. It writes 1
to AP `0x0f6b60b4` for DSI0 or `0x0f6b6178` for
DSI1, with no readback on that path. These words lie in
the BE register space. Exact D1 `vs_drm.ko` clears both
in `dc_hw_disable_all_be_interrupts` at `0x32f5c` and
`0x32f6c`. This is interrupt-control evidence and adds
no gate or reset status.

Clock operation 2 with argument 1 is the read-only path
for this cell. The existing LPCM transport to CPM
destination 8 encodes it as command `0x02032302`.
The dispatcher at `0x386be` calls `0x383d8`, which
looks up the descriptor and calls the gate getter at
`0x18e20`. That getter loads CPM `0x6f4197bc` and
extracts bit 8. The dispatcher returns 1 if it matches
the requested set bit, 0 if clear, or a negative
firmware error. Transport errors are separate. With this
argument, the path changes no clock or reset control and
touches neither the PHY nor the host. The established
UFS diagnostic used the same operation with a different
selector. Selector 3 has no retained live reply. Either
gate value would describe that cell and leave its effect on
the DSI0 TX bus unverified. Stock CCF's rate callback uses
operation 3 and has no hardware gate-status callback.

The cell's bit 12 is a separate reset acknowledgment.
Clock operation 2 samples bit 8 for argument 1. The
other status flags select bit 0 at gate offsets `0x18`
and `0x08`, leaving bit 12 outside this operation.
The firmware reset-status lookup at `0x49cf4`
rejects DPU LPCM `0x23` before reading a reset cell.
BL31's PMU register service rejects both `0x0f4197bc`
and `0x6f4197bc` in its address-range check at
`0x24258`–`0x24278`. The direct AP word is on the
GC `0x30300` CMU page and has no saved EL1 read witness.
ABL's direct reset helper polls the bit as part of a
write transaction and establishes only that cell's
acknowledgment. The DSI GIA inputs signal device
interrupts, while the named DPU reset-done inputs cover
BE and FE. The PHY's separate APB status at offset
`0x24` describes local PHY ready, PLL lock and PLL VPL
detect. It has no verified field for the external reset,
and the stock `reg_dump` touches TX before reaching it.
No qualified status source covers the external reset
at the DSI0 PHY TX register interface.

Keep `0x0f7c7124` and the DSI0 host aperture disabled.

###### Offline DSI0 selector 3 gate fixture

Kernel `66e7799dfff3d6ef17040a0891d49d61fb494482` on
`grizzly-dsi0-scaffold` adds the opt-in parameter
`clk_google_malibu_cpm.display_dsi0_selector3_gate=1`.
The fixture also enables `display_dsi0_siblings`.
Build the existing PHY scaffold with the matching kernel.
Pass `--dsi0-phy-scaffold PHY_MODULE`,
`--require-dsi0-sibling-votes` and
`--require-dsi0-selector3-gate` to the inventory packer.
PID 1 verifies the two ramdisk markers and enabled
kernel parameters before loading the module.

Each checkpoint samples the DSI1, FE0 and FE1 votes
and sends clock status command `0x02032302` with
argument `1` only when all three readings are zero.
It logs `display-dsi0-selector3-gate` with the same
phase name as the sibling sample. Both parents are held
for all four phases.

| Sample | Position |
| --- | --- |
| `before-on` | After wrapper and BE ON readbacks, before DSI0 ON |
| `after-on` | After DSI0 ON readback |
| `before-off` | Before DSI0 OFF |
| `after-off` | After DSI0 OFF readback, before BE and wrapper release |

The checker requires all four ordered sibling and gate
pairs and the full vote and release sequence. Either
Boolean gate reply is valid. Missing samples, firmware
errors, transport errors and nonzero sibling votes fail
the diagnostic. The gate result does not change the
genpd cleanup path. A transport timeout can still stall
the shared CPM mailbox and prevent later releases.
The independent timed return stays armed. An active or
unreadable sibling before ON still blocks the DSI0 vote.
The gate result covers only the clock cell. Its routing
to DSI0 TX and the external reset remain unverified.

The fixture runs after the unchanged 42-partition
read-only NV guard and UFS disk retirement. It keeps the
90-second warm return and leaves PHY TX and host reads
disabled.

The ARM64 kernel and module built with release
`7.3.0-rc6-omamobile-grizzly-dsi0-selector3-gate`. The
CPM and scaffold targets passed their `W=1` builds.
Offline verification confirmed both boot parameters,
both ramdisk markers, the PHY-only DT overlay, AVB
signatures on boot and init_boot, ABL handoff bounds,
and slot fit against the saved D1 metadata. The host-side
mock checked the exact command and sibling guard, and
the trace checker passed replay with the fixture's
ARM64 BusyBox. The five-image archive SHA-256 is
`05e289825c20d4c2d061a4b5ff05c9d0befc6fce57fb33783b368ab137a35c4a`.

###### Attended DSI0 selector 3 gate result

On 2026-11-27, the guarded rescue backed up all nine
read-only, unmounted NV partitions before the single
slot B diagnostic boot. The private copy contained
3,392,151,552 bytes, and independent on-device
SHA-256 hashes matched the saved images. The USB
bridge recovered four framing interruptions.
Stock Android stayed off between rescue and diagnostic.

Ramoops and `SYSTEM_LAST_KMSG` matched on all 38
selected lines. Both passed the ordered trace checker.

| Checkpoint | Gate sample time (s) | Selector 3 gate | DSI1 | FE0 | FE1 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `before-on` | 6.427970 | 0 | 0 | 0 | 0 |
| `after-on` | 6.428955 | 0 | 0 | 0 | 0 |
| `before-off` | 6.432239 | 0 | 0 | 0 | 0 |
| `after-off` | 6.432948 | 0 | 0 | 0 | 0 |

The fixture acquired wrapper → BE → DSI0 and released
DSI0 → BE → wrapper. DSI0 ON and OFF readbacks were
1 and 0 respectively. Selector 3's gate acknowledgment
stayed clear at every sampled checkpoint, including
both samples taken while the DSI0 vote was ON. This
confirms the observed vote did not change the selector 3
acknowledgment at those checkpoints. The trace provides
no physical clock or external reset qualification for TX.

The read-only LUN 0 scan verified 42 partitions using
seven GPT metadata reads. The v73 block comparison
passed and the disk retired. The fixture reported
completion at 6.466 s and requested its timed warm
restart at 90.199 s. PHY TX and host reads stayed
disabled. Stock D1 resumed on slot A with enforcing
verity and the original VBMeta digest.

###### D1 DSI0 system clock and PSM3 control trace

Exact D1 ABL descriptor `0x1f5220` names clock ID
`0x40009` as `dpu_dsi0_sys_clk`. Group 4 resolves to
AP `0x0f419000`, and offset `0x720` selects the cell
at `0x0f419720`. Both mailbox selectors are `-1`.
The generic ABL paths at `0x48f54` and `0x48e88`
use the direct clock and reset controls. They poll
the cell word at `0x0f41973c`, with bit 8 for gate
acknowledgment and bit 12 for reset deassertion.
The inspected ABL display path requests the DSI0 power
domain. No clock ID `0x40009` operation was identified
in that path. The descriptor describes this clock cell
and leaves the downstream TX bus clock and external
reset routing unresolved.

In exact D1 `vs_drm.ko`, `0x50ab4` reads the stock
host's `sys_clk` DT scalar of 300,000 kHz. The earlier public
binding describes that scalar as the host APB clock in
kHz. ABL has distinct system and APB cells. The host
probe copies the scalar to its private state at
`mipi-dsi2h.ko` `0x2374`.
Loads from that field at `0xf88`, `0x1004` and
`0x12bc` supply the low-power TX divisor, host
PHY-HS/system-clock ratio and ULPS wakeup calculation.
The host code provides no CCF gate operation or reset
operation for that cell. The PHY still receives its
separate fixed 38.4 MHz reference.

The CPM clock lookup at `0x37da0` has 188 entries.
None resolves to the system cell's CPM alias
`0x6f419720`. The 17 records of the DPU initializer
at `0x5c814`, applied by `0x19598` relative to
`0x6f409000`, also leave the system cell untouched.
The CPM reset service excludes LPCM `0x23` and the
BL31 PMU register service excludes the status word.
The direct AP word is in the GC `0x30300` clock page.
A search of 61 retained pstore and trace files and the
stock display bugreport found no system-cell read
witness. Direct EL1 access remains unqualified.

The PSM3 matrix uses a different interface. For DSI0 ON
from state 2 or 3 it sets `0x0c` at CPM `0x6f40a000`
(`0x3a8b4`). OFF from state 0 or 1 clears only bit 3
(`0x3a830`). DSI1 transitions use bit 4, and DSI1 ON and
BE ON also set bit 2. These shared request masks give
no signal-level definition for the TX clock or reset.
The legacy `lpm_pm_domains.ko` independently uses
LPCM base + `0x1000`. Its BE routine sets mask
`0x04` at `0x1b34`, and the DSI routine sets
`0x08` or `0x10` at `0x1e90` for its separate
DSI selectors. That provider is unbound on Grizzly.
The four DSI0 transition entries return zero from the
callback and supply no post-poll callback to change or
verify the system clock cell.

The completion poll at `0x7ffc` examines the LPCM
status flags and compares the current-state nibble to
the target. The diagnostic strings identify
`state_valid`, `psm_sts`, `sw_seq_done`, `psm_err`
and `seq_err` as fields in that same status word.
The 8,192 descriptor address combinations resolve
within CPM `0x6f409020`–`0x6f4187ec`, outside the
system clock cell and both PHY apertures. The poll
supplies sequencer status only. The isolated selector
3 trial measured the MBFS votes and that separate
cell's gate acknowledgment. It supplied no live PSM3
state or DSI0 system clock observation.

The traced software shows a DSI0 transition request
and a separate system clock cell. A hardware route
from either to the PHY TX register clock or external
reset remains unverified. Keep PHY TX and DSI0 host
reads disabled. This audit used saved artifacts and
did not build or boot a fixture.

###### D1 DPU request word and trigger-ready status

The exact D1 CPM image has 20 direct literal references
to `0x6f40a000`. Each leads to a write in the DPU
transition callbacks. The reads on these paths preserve
fields for the update. The code uses the word to request
LPCM hardware transitions, then polls descriptor-derived
PSM status. No direct-reference path checks bits 2 or 3
as status or exports either to the AP.

The DSI0 PSM3 transitions use bit 3. Other matrix entries
can also change that bit or the shared bit 2. The PSM0
and PSM2 callbacks below each write a GPCSR control
before modifying the request word.

| Matrix transition | CPM callback | GPCSR write (CPM alias) | Request word update |
| --- | --- | --- | --- |
| PSM0 0 → 6 | `0x3a528` | `0x6f791070 = 1` | Replace bits 2:0 with `0x5` |
| PSM0 6 → 0 | `0x3a608` | `0x6f791070 = 0` | Set mask `0x0f`, including bits 2 and 3 |
| PSM0 6 → 5 | `0x3a640` | `0x6f79104c = 1` | Clear mask `0x39`, including bit 3 |
| PSM2 2 → 1 | `0x3a7d4` | `0x6f79104c = 0` | Set mask `0x05`, including bit 2 |

These are static transition paths. The isolated DSI0
trial did not capture these wider state transitions.
The GPCSR words at AP `0x0f79104c` and `0x0f791070`
fall under GC bridge policy `0x30303`. The traced
writes and that address policy establish no readback
meaning. The stock BE idle transaction uses separate
GPCSR offsets `0x107c` and `0x1084`. The legacy
`curr_state` sysfs getter in `lpm_pm_domains.ko` reads
a cached software index at `0x16f4`. It supplies no
physical clock or reset status.

CPM's internal LPCM trigger-ready getter at `0x39334`
reads a global bitmap at `0x5008e014`. The table at
`0x627f8` gives DPU LPCM `0x23` compact wrapper index
8, and `0x62b98` maps that index to bitmap bit 8.
The wait routine at `0x392ac` uses mask `0x16803e4f`
and skips index 8 before reading the bitmap. The
matching interrupt handling at `0x39370` also excludes
that index. This is wrapper trigger readiness, with no
identified AP-facing readout or per-DSI indication.
The saved stock display bugreport and 61 retained
trace and pstore files contain no read witness for the
GPCSR controls or trigger-ready word.

The software evidence ends at LPCM transition requests
and the sequencer's state poll. The downstream TX bus
clock and external reset signals remain unverified, and
no qualified read-only status for them was found.
Keep PHY TX and DSI0 host reads disabled. This audit
built no fixture and took no on-device measurements.

###### D1 GPCSR front-end transition controls

The stock Grizzly B0 DT maps `dpu-gpcsr` at AP
`0x0f790000` with size `0xe004`. Exact D1 CPM uses the
`0x6f79xxxx` alias. Its FE0 and FE1 descriptors at
`0x62f38` and `0x62f6c` both select PSM2. The desired
state passed by the dispatcher at `0x39c20` is 1 for
FE0 ON, 2 for FE0 OFF, 0 for FE1 ON, and 1 for FE1 OFF.
This identifies the role of the two GPCSR words in
the front-end transition sequences.

| AP word | Front-end transition | PSM2 change | CPM callback | GPCSR value |
| --- | --- | --- | --- | ---: |
| `0x0f79104c` | FE0 OFF | 1 → 2 | `0x3a79c` | 1 |
| `0x0f79104c` | FE0 ON | 2 → 1 | `0x3a7d4` | 0 |
| `0x0f791070` | FE1 OFF | 0 → 1 | `0x3a72c` | 1 |
| `0x0f791070` | FE1 ON | 1 → 0 | `0x3a764` | 0 |

PSM0 also uses both controls. For `+0x104c`, PSM0
5 → 6 writes 0 at `0x3a5da` and 6 → 5 writes 1
at `0x3a64a`. For `+0x1070`, PSM0 0 → 6 writes 1
at `0x3a534` and 6 → 0 writes 0 at `0x3a612`.
Writing 1 precedes clearing the matching front-end
request bit, and writing 0 precedes setting it.
All eight GPCSR writes use the full-word store helper
at `0x3b83e`. The store takes place
before the callback updates the LPCM request word.
The display power path checks the sequencer later.

The exact FBPK contains four direct address literals for
each word, all in those CPM callbacks. No direct-literal
read was identified. This scan leaves computed-address
access possible. The PSM2 association identifies when
the controls are used, while electrical effects and
readback semantics remain unresolved.

In exact D1 `vs_drm.ko`, the identified GPCSR reads at
`0x3776c`, `0x377ac` and `0x377d8` all read
`+0x1084` in the BE idle transaction after the write to
`+0x107c`. The normal and custom display dumps use
the FE/BE aperture. The custom dump passes that aperture
at `0x36c08` to `gs_reg_dump_with_skips`. These paths
supply no readback of either front-end control.
The generated header comparison below identifies the
FE1 field and the layout-dependent interpretation of FE0.

GC policy `0x30303` covers both addresses. It establishes
the static address rule and leaves EL1 read behavior and
field semantics unqualified. Both AP words and CPM
aliases are outside BL31's PMU register read range
checked at `0x2425c`–`0x2427c`. No safe readback for the
PHY TX bus clock or external reset was found at either
word. Keep both GPCSR word reads, PHY TX and DSI0 host
reads disabled. This audit used only saved artifacts
and built no fixture.

###### Generated Malibu GPCSR layouts

Both generated GPL headers are available in the public
Spacecraft kernel snapshot for `CP41.260831.019`. Their
Git blob hashes match the snapshot tree. The headers
subtract `0x00390000` from the wrapper-relative addresses,
giving offsets from the B0 `dpu-gpcsr` base `0x0f790000`.

| GPCSR offset | `0x20000005` layout | `0x32a` layout |
| --- | --- | --- |
| `+0x104c` | FE0 `QCHCTL_ACTIVE_ASYNC_MASK_0`, bit 0 read/write. [FE0 mask definition][gpcsr-20000005-fe0] | FE0 `QCHCTL_DBG_STATUS`, all bits readable in the header and write mask zero. The FE0 async mask is at `+0x1054`. [FE0 status and mask definitions][gpcsr-32a-fe0] |
| `+0x1070` | FE1 `QCHCTL_ACTIVE_ASYNC_MASK_0`, bit 0 read/write. [FE1 mask definition][gpcsr-20000005-fe1] | Same FE1 bit 0 mask. [FE1 mask definition][gpcsr-32a-fe1] |

For these async activity masks, bit 0 controls whether the
front-end Q-channel logic includes the DPU back-end activity
input. `1` excludes it and `0` includes it. D1 CPM's FE0
stores at `+0x104c` fit the `0x20000005` mask definition.
D1 Linux's BE idle transaction uses `+0x107c` and `+0x1084`,
which match the `0x32a` debug selector and status pair. The
`0x20000005` pair is at `+0x1080` and `+0x108c`.
[BE idle implementation][gpcsr-be-idle] · [0x32a BE pair][gpcsr-32a-be] · [0x20000005 BE pair][gpcsr-20000005-be]

The public Malibu defconfig enables both DC9400 options, and
the driver's preprocessor chooses `0x32a` GPCSR constants
when both are enabled. The exact D1 module includes both
`dc_info_9400_32a` and `dc_info_9400_20000005`. Its matcher at
`0x19548` compares live chip, product and customer IDs. The
two entries share chip ID, product ID and revision and differ
in customer ID. The BE transaction confirms the compiled
offsets. The attended customer-ID capture below matches
the `0x20000005` layout. Direct GPCSR access remains untested.
[Malibu defconfig][gpcsr-malibu-config] · [Compile-time selection][gpcsr-hw-include] · [Runtime chip match][gpcsr-chip-match]

Neither header identifies a PHY TX bus-clock or external reset
status field. The wrapper Q-channel debug word has a programmable
selector with no documented DSI0 mapping. The `0x20000005`
GSPAN debug APB control is for the GSPAN path. Stock's existing
PLL-lock poll at `+0x24` is in the separate PHY `u0-apb-regbank`
and reports PLL lock. These sources leave PHY TX bus-clock and
external reset status unqualified. Keep the GPCSR control word
reads, PHY TX reads and DSI0 host reads disabled.
[Wrapper debug definitions][gpcsr-wrapper-debug] · [GSPAN debug APB control][gpcsr-gspan-apb] · [PHY PLL poll][gpcsr-phy-pll]

[gpcsr-20000005-fe0]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x20000005.h#L880-L907
[gpcsr-32a-fe0]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x32a.h#L761-L833
[gpcsr-20000005-fe1]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x20000005.h#L1109-L1136
[gpcsr-32a-fe1]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x32a.h#L985-L1012
[gpcsr-be-idle]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/vs_dc_hw.c#L6344-L6368
[gpcsr-32a-be]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x32a.h#L1062-L1134
[gpcsr-20000005-be]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x20000005.h#L1211-L1299
[gpcsr-malibu-config]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/devices/google/malibu/malibu_defconfig#L133-L135
[gpcsr-hw-include]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/vs_dc_hw.h#L19-L23
[gpcsr-chip-match]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/vs_dc_info.c#L11-L35
[gpcsr-wrapper-debug]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x32a.h#L464-L538
[gpcsr-gspan-apb]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x20000005.h#L1482-L1533
[gpcsr-phy-pll]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/phy/synopsys/dw-mipi-cdphy-g301.c#L2320-L2325

###### Offline stock D1 DC customer-ID trace

`pack-stock-inventory.py --dc-cid-trace` starts with the
audited read-only NV rescue images and Grizzly B0 DTB. Only
DTBO entry 19 changes. It disables both DSI2H nodes, both
CD-PHY nodes and the DP encoder. The display master skips
these disabled components and retains DC, BE, FE0, FE1 and
writeback. The live DT statuses are checked before loading
the seven stock display modules. The DSI2H and CD-PHY
modules satisfy link dependencies. Their device probes
are excluded by the disabled nodes.

Exact D1 `vs_drm.ko` calls `dc_hw_init` from `dc_bind`
after the stock BE and FE power requests. Its normal
`dc_read` of DC offset `0x30` at module offset `0x2e224`
returns the customer ID. The driver passes that value in
`w3` to `vs_dc_get_chip_info` (`0x19548`). The fixture
records the four scalar arguments at that function in a
private tracefs instance. It adds no device register reads
and issues no display commit. It reports the observed
customer ID and the corresponding generated layout, or
`unknown` for an unrecognized tuple. Lost records and
conflicting samples make the capture incomplete.

The existing five-parent, nine-target NV guard must pass
before trace arming and display load. The stock inventory's
90-second warm return is armed independently before loading
the inventory modules. The CID result is emitted to the
stock inventory kernel log for retained-console collection.

QEMU with the exact D1 kernel and factory module closure
verified early event enablement, probe registration after
module load, and cleanup. Synthetic traces verified both
known IDs, unknown IDs, repeated samples, and rejection of
lost or conflicting records. The live DT check accepted
the five disabled nodes and rejected an enabled DSI host.

All five image hashes, the replacement AVB metadata,
the B0 DT merge, saved B partition sizes and handoff bounds
passed offline. The initrd ends at `0x88fb8ec1`, below the
FDT at `0x8a000000`. Replacement hashes are
`init_boot` `5c1c835ecc5969494f354e1c05746852e4706db3b74ab933c40661d90d9c9806`
and `dtbo` `c2725fb4f145fecd87efc6b12f4639a6c7d27ccdc6bf1efca43c75b692a846cf`.

###### Attended stock D1 DC customer-ID result

On 2026-11-27 the first rescue USB connection dropped
before copying. The retry copied all nine partitions
(3,392,151,552 bytes) to the private Mac backup directory.
The independent phone-side hashes and local checksum
manifest verified. The phone returned to Fastboot
without booting Android between the backup and CID trial.
The five CID images were staged with A selected, and the
full `vendor_boot_b` readback matched the supplied image.

| Kernel uptime | Result |
| ---: | --- |
| 0.875222 s | The 90-second warm return was armed. |
| 4.682894 s | The NV read-only guard passed for five parents and nine targets. |
| 4.712157 s | Both DSI hosts and both PHY nodes passed the disabled-status check. The probe armed before `vs_drm` loaded. |
| 4.884209–4.889099 s | DC, BE, FE0, FE1 and writeback bound. The retained log showed no DSI host or PHY probe. |
| 4.897425 s | One sample recorded chip `0x9400`, revision `0x7002`, product `0x02094000` and customer ID `0x20000005`. |
| 4.909952 s | The CID trace reported completion. |
| 90.878081 s | The timer requested the warm return. |

The live ID selects the `0x20000005` generated layout.
In that layout `+0x104c` is the FE0 asynchronous Q-channel
activity mask and `+0x1070` is its FE1 counterpart. Bit 0
excludes the BE activity input when set. This matches the
direction of D1 CPM's writes around the front-end votes.
The `0x32a` BE idle offsets in the Linux binary are still
compile-time constants. The CID trace adds no GPCSR, PHY TX
or host reads and leaves the TX clock and external reset
readback questions open.
[FE0 mask definition][gpcsr-20000005-fe0] · [FE1 mask definition][gpcsr-20000005-fe1]

Ramoops and `SYSTEM_LAST_KMSG` matched on all 39 selected
lines. Fastboot returned 134 seconds after the only CID
boot request. Stock A completed boot with the same D1
build, enforcing verity and matching VBMeta digest.

###### Offline D1 wrapper Q-channel debug selector

The live DC customer ID selects `0x20000005`. At the
`dpu-gpcsr` base of `0x0f790000`, that layout places the
wrapper's debug control and status on the same CSR page.

| AP word | Definition |
| --- | --- |
| `0x0f791010` | `DPU_SSWRP_QCHCTL_DBG_STATUS_CTL`. Bit 24 enables debug and bits 23:0 select a signal. Both fields default to zero. [Wrapper debug control][gpcsr-20000005-debug-ctl] |
| `0x0f79101c` | `DPU_SSWRP_QCHCTL_DBG_STATUS`. The read mask covers 32 bits and the write mask is zero. The result has no named subfields. [Wrapper debug status][gpcsr-20000005-debug-status] |

The header leaves the selector encoding and source list
undocumented. The four nearby `ACTIVE_MASK_0`,
`ACTIVE_MASK_1`, `ACTIVE_ASYNC_MASK_0` and `QCH_MASK_0`
words configure which activity and handshake inputs the
wrapper considers. Their labels cover AXI/APB paths,
FE/BE activity, LPCM power-bus activity and
`dbg_clk_ctrl_wrap`, `lpdp_1to5_clk` and `axi2apb5_cg`.
Those bit positions describe the masks. There is no
documented mapping from them to the debug selector, and
none names the DSI0 PHY TX bus clock or external reset.
[Wrapper input masks][gpcsr-20000005-input-masks]

Exact D1 `vs_drm.ko` maps GPCSR but has no identified
access to this pair. Its `0x101c` instruction matches
form FE/BE offsets in underrun and trigger paths. The
GPCSR transaction at `0x37754`–`0x377d8` is the
compiled BE idle check. It writes `0x01000002` to
`+0x107c` and polls bit 14 at `+0x1084`. The
`0x20000005` layout identifies those two offsets as
the BE debounce and bypass controls. The latter has a
read mask of `0x1`, so per this layout a clear bit 14
would supply no BE idle evidence. The BE debug pair
for this layout is `+0x1080` and `+0x108c`. The stock
sequence provides no selector or status interpretation
for the wrapper instance.
[BE idle implementation][gpcsr-be-idle] · [BE registers][gpcsr-20000005-be-registers]

The exact D1 FBPK and CPM image contain no direct AP or
CPM address literal for either wrapper word. The decoded
CPM initialization writes also miss both words. A
wrapper-relative page reference in CPM belongs to an
access-control save/restore table. Computed-address
accesses outside the inspected paths remain possible.
The saved stock bugreport and 84 retained stock log files
have no exact-address or selector-name witness.

GC `dpu_rfw_brg1` assigns rule `0x30303` to the AP
page `0x0f791000`–`0x0f791fff`. This is static policy.
The exact word's EL1 bus response and power prerequisites
remain unobserved. BL31's PMU read service excludes
both AP addresses and CPM aliases at its range check
(`0x2425c`–`0x2427c`). A raw status read
would have no verified signal interpretation, and
selecting a signal requires programming the control word.
Keep the wrapper debug words, PHY TX and DSI0 host reads
disabled. The audit used only saved artifacts.

[gpcsr-20000005-debug-ctl]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x20000005.h#L441-L469
[gpcsr-20000005-debug-status]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x20000005.h#L520-L539
[gpcsr-20000005-input-masks]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x20000005.h#L541-L703
[gpcsr-20000005-be-registers]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x20000005.h#L1187-L1306

###### Offline D1 AXI2APB5 clock and reset route

The CID-selected `0x20000005` GPCSR layout identifies two
wrapper inputs associated with AXI2APB5.

| AP word and bit | What it controls |
| --- | --- |
| `0x0f791024` bit 6 | `ACTIVE_MASK_1` excludes the synchronous `axi2apb5` activity input when set. [Activity input][gpcsr-20000005-apb5-active] |
| `0x0f79102c` bit 15 | `QCH_MASK_0` excludes the `axi2apb5_cg` Q-channel handshake when set. [Handshake input][gpcsr-20000005-apb5-qch] |

Both fields default to zero. Reading either field would
report its mask configuration. The header supplies no
live gate, handshake or reset state for the bridge and
does not assign either input a wrapper debug selector.

The exact B0 tree maps a 4 MiB DPU wrapper at
`0x0f400000`. It places DSI0 PHY TX
at `0x0f7c0000` (size `0x18000`), the host at
`0x0f7d8000` (size `0x800`) and the separate PHY APB
bank at `0x0f7d8800` (size `0x800`). It supplies a
fixed `pllref` and the DSI0 power domain to the PHY.
The tree has no numbered APB bridge node, clock or
reset provider tying those ranges to AXI2APB5.
[DPU wrapper and PHY DT][malibu-axi2apb5-dpu-dt]

Exact D1 GC groups the GPCSR mask page, TX init word
`0x0f7c7124`, host and PHY APB bank under the broad
`dpu_rfw_brg1` firewall with rule `0x30303`. The TX
word falls in rule range `0x0f7c3000`–`0x0f7c9fff`.
The host and PHY APB share the separate page rule
`0x0f7d8000`–`0x0f7d8fff`. These are address access
rules. They give no downstream bridge routing or
clock/reset evidence for the TX interface.

The 19 ABL DPU clock rows at `0x1f5028`–`0x1f5418`
have no named AXI2APB5 gate. They distinguish
`dpu_sswrp_clk` at `0x0f419680`, `dpu_dsi0_apb_clk`
at `0x0f4196e0` and `dpu_dsi_phy_clk` at `0x0f4197a0`.
The generic acknowledgments at the first two cells'
`+0x1c` describe those clock cells. Both cells lack a
CPM clock selector and their AP status words lack a
qualified stock EL1 read. Of the seven DPU CPM clock
selectors, selector 5 is FE0 (`0x6f419620`) and selector
3 is the named DSI PHY cell. Neither lookup establishes
the AXI2APB5 route. CPM reset status still excludes
DPU LPCM `0x23`.
[Stock DPU CPM clock names][malibu-axi2apb5-clock-dt]

The inspected stock modules and exact D1 firmware
yielded no operation that reads AXI2APB5 gate or reset
state. No exact mask address or bridge-name witness
appeared in 84 retained stock log files or the saved
display bugreport. The AXI2APB5 connection to DSI0
PHY TX and any safe clock or reset readback remain
unverified. Keep PHY TX and DSI0 host reads disabled.

[gpcsr-20000005-apb5-active]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x20000005.h#L581-L618
[gpcsr-20000005-apb5-qch]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x20000005.h#L671-L703
[malibu-axi2apb5-dpu-dt]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/devices/google/malibu/dts/malibu-dpu.dtsi#L271-L294
[malibu-axi2apb5-clock-dt]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/devices/google/malibu/dts/malibu-cpm-clk.dtsi#L14-L62

###### Offline D1 `dbg_clk_ctrl_wrap` readback

In the CID-selected `0x20000005` layout, `dbg_clk_ctrl_wrap`
is named in two wrapper Q-channel input masks. Setting
`0x0f791028` bit 1 excludes its asynchronous activity input.
Setting `0x0f79102c` bit 9 excludes its synchronous
Q-channel handshake. Both bits default to zero. A read
would give the exclusion settings. The header supplies
no debug selector encoding for either input and no field
for TX gate or reset state.
[Wrapper input masks][gpcsr-20000005-input-masks]

The same layout's `DPU_GSPAN_DEBUG_APB_PATH_CLKEN` at
`0x0f7910a0` holds an AON GSPAN debug APB clock-gating
disable bit, an activity mask and an idle debounce count.
Those fields describe the debug APB gating policy. The
`0x32a` variant's ATB gate control at `0x0f791094` names
the DPU TCU ELA, the DPU funnel and the ATB initiator.
At that address the `0x20000005` layout defines the BE
asynchronous activity mask. Neither header connects these
controls to `dbg_clk_ctrl_wrap` or the DSI0 TX interface.
[GSPAN debug APB control][gpcsr-gspan-apb] · [0x32a ATB control][gpcsr-32a-atb-control] · [0x20000005 BE mask][gpcsr-20000005-be-async]

Exact D1 ABL records `0x236d58` and `0x236d70` name
the DPU and FABDISP endpoints of `dpu_atb`. The crash
diagnostic at `0x55d58` resolves the pair through the
scan database. The load at `0x58a18` extracts FSM bits
from the captured scan buffer. The adjacent `dpu_cfg`
record is a separate configuration link. The stock GIA
test description names a configuration-link error IRQ
for that link.
[FABDISP GIA test description][malibu-fabdisp-gia-test]

Exact D1 GDMC lists `funnel_dpu` at AP `0x0f506000`
and `funnel_fabdisp` at `0x0f383000` in its CoreSight
table. That table establishes the funnel addresses.
The `fabdisp_debug_clocks` path (`0xe1fe`) changes four
FABDISP clock cells. The DPU ICD test (`0xe0d8` →
`0xc6bc`) reads each ICD block at offsets `+0x8` and
`+0xc`, then writes `1` at `+0x10`. These paths supply
no qualified passive readback for the PHY TX clock or
external reset.

GC rule `0x30303` covers the DPU funnel and the GPCSR
page in separate address ranges. The exact FBPK and CPM
image lack direct AP or CPM literals for the two masks
and GSPAN debug APB control. The saved B0 DT and
checked Linux drivers have no identified readback consumer
for the funnel or GSPAN debug APB control. The saved stock
display bugreport and 84 retained stock log files yielded
no exact name or address witness. Keep PHY TX and DSI0
host reads disabled. This audit used only saved artifacts.

[gpcsr-32a-atb-control]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x32a.h#L1241-L1264
[gpcsr-20000005-be-async]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x20000005.h#L1346-L1375
[malibu-fabdisp-gia-test]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/devices/google/malibu/dts/malibu-gia-test.dtsi#L1292-L1315

###### Offline D1 `lpdp_1to5_clk` route and readback

The CID-selected `0x20000005` layout names
`lpdp_1to5_clk` at `0x0f791028` bit 0, in the wrapper's
asynchronous activity exclusion mask. The bit defaults
to zero and excludes that activity input when set. Its
readback describes the mask setting. The header supplies
no LPDP clock-gate, reset-status field or debug selector.
The `0x32a` variant also names the input at bit 0, in
its mask at `0x0f791034`.
[D1 layout][gpcsr-20000005-input-masks] · [0x32a layout][gpcsr-32a-lpdp-mask]

The exact B0 tree routes DPU mux 2 through `dp-encoder`
to `a2b4000.dwc_dptx`. The transmitter uses the HSIO-N
USB/DP PHY at index 2, `DpuDp0.v` (`0x205`) and
`HsioNDp.v` (`0x213`). DSI0 CD-PHY uses its fixed
38.4 MHz reference and `DpuDsi0.v` (`0x203`). Exact
ABL records at `0x236db8` and `0x236dd0` pair
`dpu_hsio0` with `dptx0_gspan_stream_target` for
crash-snapshot decoding. This identifies the DP0 stream
path. The tree and records leave the LPDP input's
downstream wiring unresolved.
[DP encoder graph][malibu-lpdp-dp-encoder] · [DPTX resources][malibu-lpdp-dptx] · [CD-PHY resources][malibu-axi2apb5-dpu-dt]

The DP0 MBFS descriptor (`0x63008`) requests PSM1
state 0 for ON and 3 for OFF. The `3 → 0` callback
(`0x3a6a0`) sets bit 5 at CPM `0x6f40a000`. The
`0 → 3` callback (`0x3a678`) clears bit 5 and sets
shared bit 2. DSI0 uses PSM3. Neither callback reads
the LPDP signal. ABL
describes the `dpu_dp0_pix_clk` cell at `0x0f4197c0`
and associates it with clock selector 0. The exact
CPM selector-0 record (`0x65800`) has a null gate
pointer. Clock status operation 2 rejects that record
at `0x3841e` and returns `-24` before the gate read.
The DP0 vote and pixel-clock paths supply no LPDP
gate or reset feedback.
[DPU clock names][malibu-axi2apb5-clock-dt]

In the retained DP-off trial, the live B0 tree confirmed
the DP encoder disabled at 5.710108 s. The packaged
module manifests omitted `dwc_dptx.ko`. Stock CD-PHY
initialized at 7.408682 s and DSI0 then read host ID
`0x30313130` and version `0x1a000110`. This shows
that the DSI0 startup reached those reads without the
Linux DisplayPort path. The trial did not sample the
DP0 firmware vote or the LPDP clock.

The exact D1 FBPK, CPM image and checked stock drivers
yielded no LPDP name or register access linking that
input to the DSI0 TX interface. A connection to the TX
bus and a safe clock or external reset readback remain
unverified. Keep PHY TX and DSI0 host reads disabled.
This audit used only saved artifacts.

[gpcsr-32a-lpdp-mask]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/google-modules/display/vsi-drm/verisilicon/9x00/info/sswrp_dpu_gpcsr_pg_9400_0x32a.h#L574-L626
[malibu-lpdp-dp-encoder]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/devices/google/malibu/dts/malibu-dpu.dtsi#L445-L472
[malibu-lpdp-dptx]: https://github.com/GrapheneOS/kernel_pixel/blob/cbc6305f4ca4f4a63c4e6f476fd0d0aa09fa2122/private/devices/google/malibu/dts/malibu-base.dtsi#L890-L916

###### Offline stock D1 DP-off firmware vote trace

`pack-stock-inventory.py --dsi0-dp0-vote-trace` reuses the attended
DP-off panel fixture. It checks that the live DT disables the DP
encoder and keeps the same display module list, scoped I²C and VDDD
trace. The stock kernel and modules are unchanged. The new trace
starts after the five-parent, nine-target NV guard. The independent
90-second warm return remains armed.

The B0 power controller maps `dpu_dp0_pd` (`0x205`) to
`cpm/syspm/clients/vm1/DpuDp0.v`. The stock
`power_controller/dpu_dp0_pd/state` debugfs node is mode 0220 and
has separate read and write handlers. The fixture opens it read-only
as root under a read-only debugfs mount. The audited stock getter
(`power_controller.ko+0x4f38`) calls `mbfs_read_file` with the
resolved handle. In exact D1 CPM the read provider
(`0x28c6c` → `0x288bc`) looks up the AP client's bitmaps. It
returns `1` for the current vote bit, `2` if only the secondary
bit is set, and `0` when both are clear. The fixture preserves
the raw reply. These values describe the AP client vote. They
leave physical DP0 power, other clients, and LPDP unresolved.

The trace samples the vote before loading display modules. After
`vs_drm.ko` loads, it waits up to four seconds for the stock
`regmap_reg_read` at DSI0 CD-PHY offset `0x7124`, then samples
the vote again. It requires exactly one matching PHY event between
the sample markers without trace loss, and retains stock
`send_mail_mbfs` and `recv_result_mbfs` events for `0x205` in
the same monotonic trace. A missing getter, unknown reply or
incomplete capture fails the diagnostic. Two zero replies and an
empty `0x205` event span would show that the AP vote was clear at
both samples and that the stock power controller logged no DP0
request between them. The fixture adds no vote writes, PHY TX or
host register accesses, or display commit.

The 2026-11-27 offline bundle retained all four other boot images
byte for byte from the attended DP-off fixture. Replacement
`init_boot` SHA-256 is
`72fbd775fadfc4c494952f177fd08955a64ac05e75c7449bbb440aa67ecdb72a`.
All five image checksums, the AVB checks, the saved slot capacity
check and the packed helper, guard and module manifests passed.
The initrd ends at `0x88fb9b5d`, below the FDT at `0x8a000000`.
Mocks using the packed ARM64 BusyBox checked the sample reader and
trace validation. The stock getter and trace remain to be tested
on the device.

| Step and risk | Expect | Stop condition | Rollback |
| --- | --- | --- | --- |
| Offline verification, low | Build with `--dsi0-dp0-vote-trace`. Match the five checksums and the original DP-off DTBO. Confirm the NV guard and new trace marker in the archive. | Image, archive or scope mismatch. | Keep the previous verified DP-off bundle. |
| Attended slot B trial, stock display and storage startup | After a fresh verified nine-partition NV backup and approval, verify the staged images and boot once. Collect the guard, both raw vote replies, the bracketed PHY line and any `0x205` requests and replies from the retained log. | Missing backup or guard, unexpected hardware access, read error, or incomplete trace. | Catch Fastboot with Volume Down at the timed return, select stock A and start Android. Retain the partial log for analysis. |

###### Attended stock D1 DP-off firmware vote trace

On 2026-11-27 the D1 rescue copied and verified all nine
read-only, unmounted NV partitions (3,392,151,552 bytes)
privately on the Mac. All five staged trace images passed
preflight, including the full `vendor_boot_b` readback.
One diagnostic boot ran on slot B. The NV guard passed for
five parent disks and nine targets at 4.598048 s, and the
live tree confirmed the DP encoder disabled at 4.602150 s.

| Monotonic trace time | Observation |
| ---: | --- |
| 6.233081 s | The AP client's `DpuDp0.v` pre-load reply was `0`. |
| 6.376053 s | Stock DSI0 CD-PHY init's existing read at offset `0x7124` returned `0x1cc`. |
| 6.385419 s | The fixture requested the second DP0 vote sample. |
| 6.389265 s | The post-init reply was `0`. |

The trace retained all four records (4/4), with no
`0x205` power-controller requests or replies. Ramoops and
`SYSTEM_LAST_KMSG` agree. This establishes that stock D1
reached its DSI0 PHY read with the AP DP0 vote clear at
both samples and no AP power-controller DP0 transition
observed between them. Physical DP0 power, votes from
other clients, and the LPDP clock and external reset
remain unverified. The trace added no PHY TX or host
reads and issued no display commit.

Panel discovery and VDDD capture finished at 45.141678 s.
The timer requested the warm restart at 90.861067 s.
Fastboot returned and stock D1 Android booted on A with
enforcing verity and the original VBMeta digest.

###### Offline D1 DP0 PSM1 hardware state audit

Exact D1 CPM dispatches `0x205` through the DP0 record at
`0x63008`. The pair selects DPU LPCM `0x23`, PSM1.
The dispatch at `0x39b84`–`0x39ba4` reads the hardware
state through `0x87c0` → `0x7f90` → `0x1942c`
before comparing it with the requested state. DP0 ON
requests `0`. OFF requests `3` and accepts state `4`
as already off (the unsigned comparison at `0x3b898`).
State `4` also satisfies BE OFF.

| PSM1 transition | CPM callback | Operation at CPM `0x6f40a000` |
| --- | --- | --- |
| DP0 ON, 3 → 0 | `0x3a6a0` | Set bit 5. |
| DP0 OFF, 0 → 3 | `0x3a678` | Clear bit 5 and set bit 2. |
| BE OFF, 3 → 4 | `0x3a6c4` | Write zero. |
| BE ON, 4 → 3 | `0x3a708` | Set bit 2. |

The five-state matrix at `0x2000a79c` drives these
requests. The request word is shared with other PSMs.
The independent poll at `0x7ffc` reads sequencer status
and checks the status flags before testing the low
nibble against the target state.

The read-only hardware candidate is the descriptor-derived
status word. The PSM1 descriptor is at AP `0x0f409018`
(CPM `0x6f409018`). The status formula is the same as
in the PSM3 audit, with the PSM1 descriptor substituted.
The DPU initializer leaves that descriptor untouched.
The saved artifacts contain no captured PSM1 descriptor
or qualified stock EL1 read of the resulting DPU word.
Its possible pages span several GC rules. BL31's PMU read
service excludes the entire AP range and the CPM alias.
The factory legacy `lpm_pm_domains.ko` DP callbacks
poll provider base + `0x1010` for states `0` and `3`
(calls at `0x1fe0` and `0x2058`). That offset would
map to AP `0x0f40a010` on the D1 LPCM base, outside
the descriptor formula's possible words. The Grizzly DT
has no matching provider binding, so the dormant poll
supplies no stock EL1 access witness.

LPCM operation 3 reads the requested operating level cached
at `0x20009abf`. The DPU power-dashboard wrapper row reports
the aggregate vote, and no publisher was found for its
physical PSM1 row. CPM trace tags `0x230100`, `0x230103`
and `0x230104` identify PSM1 transition targets, but the
stock trace DMA path remains disabled and a transition
record alone cannot supply the state at PHY init.

The prior slot B run establishes what the AP voted.
Physical DP0 OFF during the stock DSI0 PHY read still
requires a qualified PSM1 observation at that point.
The audit leaves both the candidate PSM1 read and the
mainline PHY TX and host reads disabled.

###### Offline search for the D1 PSM1 descriptor

The retained stock D1 display bugreport's
`dumpstate_board.bin` contains a 311,280-byte
`bootlogs/bl_data.bin` made entirely of text. The
crash-dump entries report that APC and CPM register
dumps were unavailable (`-2`). The archive contains
no raw DPU register snapshot or DPU PSM1 row. A scan
of 213 retained trial-capture files also found no
PSM1 descriptor address, legacy status address, or
DPU PSM1 label. The available parser fixtures are
synthetic and supply no device observations.

In the exact D1 FBPK, the ABL and CPM records contain
the respective LPCM bases. The GC entries describe
page policy. Neither descriptor alias appears as an
address literal in either byte order. The DPU
initializer pointer for LPCM `0x23` selects
`0x5c814`. Decoding all 17 records shows that its
first write is at CPM `0x6f409008` and no write covers
the descriptor at `0x6f409018`. ABL's direct caller
of the generic AP PSM decoder uses HSIO-S. The named
DP0 capture records identify stream targets, without
a register range or descriptor value.

The descriptor value and therefore the exact status
word remain unresolved. EL1 access cannot be qualified
from the page policy alone. Keep the PSM1, PHY TX and
host reads disabled.

###### Offline D1 CPM register dump path

Exact D1 ABL asks for CPM register dump selector `2`
with length `0x74` at `0x54d8c`–`0x54db0`.
Its helper at `0xc4f44` sends GDMC command
`0x07000002` with the fixed destination `0x8b420000`
and length. On success ABL repacks the CPU context
as `regdump_cpm` at `0x54de0`–`0x54e28`.
The separate CPM INFO and ERROR trace parser reads
sections of an existing crash archive.

In GDMC, the handler at text offset `0x1b8d4`
validates the destination and dispatches to the
fixed source table at `0x1b820`. Selector `2`
at `0x1b85c` requires byte `0x5004af74` to equal
`1`. A valid context supplies `0x74` bytes from
`0x5004af00`. Otherwise the helper leaves the source
pointer null and the handler returns `-2` at
`0x1b948`. The message has no source-address field.
Neither the source buffer nor any other selector
covers the DPU LPCM descriptor at AP `0x0f409018`.

ABL can also return `-2` locally at `0xc5018` if
its GDMC mailbox device lookup returns null. The
saved stock crash log gives the resulting code in
both the crash-dump summary and the console formatter.
It contains neither the GDMC reply nor the validity
byte for those calls, so it cannot identify which
branch produced the observed code. It contains no
CPM register-dump payload. Recovering that payload
would supply CPU context and would still leave the
PSM1 descriptor and its EL1 access unresolved.
The audit used only saved artifacts.

###### Offline D1 GDMC DPU crash snapshot coverage

The exact GDMC DPU and FABDISP GEM records are
interconnect monitor descriptors. The five DPU
records (GDMC image offsets `0x3dbd8`–`0x3dc28`)
select monitor blocks at CPM aliases `0x6f500000`
through `0x6f504000` in 4 KiB steps. The related
FABDISP records select blocks at `0x6f3c0000`,
`0x6f3c1000`, `0x6f3c4000`, `0x6f3c6000` and
`0x6f3c7000`. The GEM snapshot path handles monitor
counters. None of these blocks covers the descriptor
at AP `0x0f409018` (CPM alias `0x6f409018`).

GDMC's DPU ICD entries (`0x2d95c`–`0x2d988` in
the image) point to four control words at
`0x6f4094fc`, `0x6f40953c`, `0x6f4095b8` and
`0x6f4095f8`, with paired banks at `0x6f78f0xx`.
The helper at text offset `0xc6bc` reads the
paired bank's interrupt enable and mask at
`+0x8` and `+0xc`, then writes at `+0x10`.
These are individual locations on an interrupt-control
path. The `DPU_RFW_LPCM` table row points to the
firewall at `0x6f401000`, and `DPU_LPCM_0` is
an interconnect ID in the QoS table. Neither defines
a dump of the LPCM register page.

ABL `0x55d8c`–`0x55ea4` walks pairs of
interconnect deadlock peers. The DPU/DP0 pair
uses decode indices `0x1d614` and `0x1d61b`.
Through `0x58fac` and `0x58854`, the indices
select five bits of link FSM state from an existing
scan image. They are independent of the AP MMIO
address. The retained stock D1 crash log reports
power-domain scandump disabled (`0/27`) and no
scan preparation. It contains no decoded DPU/DP0
peer or PSM1 descriptor. The inspected tables
provide no stock capture for the descriptor.
Coverage of a hardware scan chain absent from the
saved artifacts remains unverified. Keep direct
PSM1, PHY TX and host reads disabled.

###### Offline D1 power-domain scandump selection and DPU block

The retained stock crash log reports `S2M status:
Blocked by PD`, `PD status: disabled` and an all-zero
16-byte PD debug vector. ABL `0x529e0`–`0x52a10`
obtains the status and vector from GDMC. The vector
request is command `0x19000003` through ABL
`0xc7118` and `0xc6e1c`. The GDMC selector 3
handler copies four words from `0x69920200`.
Selector 2 reports the separate policy status using
the enable bit in `0x69920230`. GDMC also checks
the policy block in its crash-reset scandump
decision at text offset `0x3898`.

The `disabled (0/27)` line counts set bits in the
returned policy vector. ABL `0x538dc`–`0x53950`
walks 27 label/bit-index rows at `0x2084d0`,
calling `0xc8998` for each. All 27 selected bits
are zero in the retained vectors. The policy labels include
`fabdisp_scan_en` at bit `0x44`. They have no
separate DPU entry and do not describe chain
contents. The crash log also reports incomplete
scan preparation. The earlier `scan2mem_init`
and DDR save/restore messages show setup activity.
The retained crash provides no completed DPU scan.

ABL's separate block table at `0x236048` has 33
entries. It names `fabdisp` at ordinal 13 and
`dpu` at ordinal 22 (`0x2361a8`). The DPU record
uses layout 8 and validation tags `0xa616` and
`0xa617`. The validator at `0x56224`–`0x562dc`
uses indices `0x1c9fe` and `0x1ca10` to decode
two 16-bit tags from the packed DPU scan data.
The previously traced DP0 peer indices decode
link FSM bits. These entries establish a named
DPU scan block and a few known fields. They give
no register-to-scan-bit mapping for AP
`0x0f409018`. Whether the physical chain includes
the PSM1 descriptor remains unverified. Keep
direct PSM1, PHY TX and host reads disabled.

###### Offline D1 scan2mem engine setup and block selection

DBC looks up `scan2mem_init` in the DRAM BLFS
archive at `0x15690`–`0x156a0`. Its reinit path
looks up `scan2mem_reinit` at `0x7808`–`0x7814`.
All 12 factory DRAM-init archives have both records.
They hold setup sequences for the scan engine and
memory path. The crash-reset policy test and the
per-block capture mask are handled separately in GDMC.

When the PD policy check is active, GDMC
`0x3898` calls the all-bits test at
`0x88c0`–`0x892a`. `fabdisp_scan_en` (PD
vector bit `0x44`) is one of its 25 required bits.
The archived vector is all zero. The log supplies no
sample of GDMC's separate local policy-enforcement
selector, which it initializes from `0x69894004`.

The normal crash capture-mask builder at GDMC text
`0x3708` uses a separate 33-row table at
`0x20008784`. Each two-byte row gives a scan-mask
bit and a wrapper-state selector. The test at
`0x3234` takes the low two bits of the live wrapper
word. A nonzero value sets the row's capture bit.
The selector and capture bit pairings are:

| Stock scan block | Capture bit | Wrapper selector | GDMC state word |
| --- | --- | --- | --- |
| DPU | 22 | 8 | `0x51540200` |
| FABDISP | 13 | 9 | `0x51540240` |

GDMC `0x4864` programs the scan engine mask, with
a diagnostic override path and special handling
for other blocks. ABL `0x56fa4`–`0x56fb8` uses
the enabled bit indices as block IDs in a saved
packet. Thus policy bit `0x44` can affect permission
to start the scan. DPU block 22 selection on the
normal path comes from its own wrapper.

The two 33-entry layout tables selected by GDMC
`0x7e0` both give DPU a scan length of `0x367c87`
bits and FABDISP `0xb9363` bits. The setup loop
at `0x48e6`–`0x491c` programs these per block. ABL
`0x56910`–`0x5692c` converts the declared bit count
to an aligned packet size. The lengths and ABL's decoded validation
and link-state bits provide no mapping from AP
`0x0f409018` to scan bits. No retained D1 capture
supplies that mapping. PSM1, PHY TX and host reads
remain disabled.

###### Offline D1 ABL scan-bit table provenance

The scan decoder at ABL `0x58854` calls `0xe284`
to select one of two tables linked into the ABL
image. It uses file offset `0x2b3110` for silicon
revision byte `0x10` and `0x2396b8` otherwise.
The revision helper at `0x2d0d0` caches the low
byte of the word at `0x3444601c`. ABL's revision
print path (`0x47678`, `0x476a8`) splits the
same byte into the revision letter and digit. The
saved stock log identifies B0, which selects
`0x2b3110`.

The decoder uses a 32-bit field index to locate a
record in the selected table. It then reads bits
from the captured scan image at the record's
numeric positions (`0x589fc`–`0x58a58`). The
linked DPU validation table entry at `0x236738`
supplies indices `0x1c9fe` and `0x1ca10`. In both
revision tables those records select 16 bits each,
at positions `0x2`–`0x11` and
`0x367c67`–`0x367c76`. The DPU/DP0 ICD peer
records use five-bit fields. The DPU peer record
matches across revisions. The HSIO-N peer record
has different bit positions in the B0 table.

The binary names `s2m_register_parser.c` and
`s2m_block_parser.c` in its crash-dump code.
The traced decoder uses the linked constants
directly. ABL reads the payload from GMC scan
memory anchored at `0xc0000000` and registers
it as a crash archive output at `0x56434`, named
`p_s2m.bin` or `p_s2m_c2m.bin`. The saved FBPK and local
Malibu source snapshot supply no identified
generator, named netlist or register-to-scan
map for DPU LPCM. The retained stock bugreport
also contains no scan output archive member.
No saved generated map identifies the PSM1
descriptor at `0x0f409018`. Its inclusion in the
physical scan chain remains unverified. Keep
PSM1, PHY TX and host reads disabled.

###### Offline B0 DPU PSM1 descriptor reset-value audit

Exact D1 CPM reads PSM metadata from the controller.
It checks the count in the hardware header and loads
the descriptor at LPCM base `+0x10 + 8 * psm`
(`0x40c0c` and `0x40c80`). For DPU PSM1 the word
is at AP `0x0f409018`, CPM `0x6f409018`. The
decoder uses its page, instance and offset fields
to locate the separate status word. The PSM control
and state-entry writes at `0x1936c`, `0x193c4`
and `0x19470` also use descriptor-derived locations.

The initializer dispatcher at `0x39188` resolves
packed tables through `0x11e0` and applies the
records through `0x19598`. Expanding all 15
nonempty tables gave 484 records. The audit used
the actual write widths of 4, 8 and 16 bytes per
element, including the full spans of multiword
writes. None covers the DPU PSM1 descriptor at
either alias. The DPU table itself has 17 records.
Its only write in the first `0x40` bytes is at
base `+0x8`. This is consistent with hardware
configuration metadata supplied before the CPM
initializer. The audited write paths do not
establish that the word is hardwired or immutable.

The saved Malibu LPCM bindings define controller,
clock, reset and performance-state IDs. The
generated DPU GPCSR headers give defaults and
access masks for the GPCSR window at AP
`0x0f790000`. Their LPCM references describe
signals crossing that wrapper. Neither header set
defines the descriptor at `0x0f409018` or its
reset value. The reset value, direct EL1 access
and status address remain unverified. Keep PSM1,
PHY TX and host reads disabled.

###### Offline B0 descriptor and early firmware setup

The exact D1 FBPK has no AP or CPM descriptor
address literal in DBL, GDMC or GC. The audit
also followed the computed-address paths in
their DPU setup. DBL checks the optional
`psm_regs` property at `0x30f84`–`0x30fa4`.
When present, its three cells supply wrapper-
relative status and request addresses and the
expected state. DBL can write `1` to the request
address at `0x31084` and poll the status nibble.
The exact GC DPU wrapper has no such property.

The GC image's access-control FDT at `0x52b8`
describes `dpu_rfw_lpcm` as a firewall at AP
`0x0f401000` with window length `0x4400`.
Its `init,trustedfirmware` property specifies rule
`0x30301` for the protected range
`0x0f409000`–`0x0f409fff`. DBL decodes range
triplets at `0x351dc`–`0x3521c` and indexes
the firewall rule table relative to the protected
base at `0x33c58`–`0x33d38`. These addresses
select protected bytes and their permission
entries. The actual rule stores are to the
separate firewall block.

GDMC's DPU late-init path at text offset
`0xe118` walks IRQ, firewall and ICD tables.
The DPU IRQ words are at `0x6f46f000`–
`0x6f46f110`. The closest DPU ICD words are at
`0x6f4094fc`–`0x6f4095f8` and have separate
interrupt banks. The LPCM firewall entry starts
at `0x6f401000`. GDMC also has a generic LPCM
descriptor reader at image offset `0x1d068`. The
identified state request call at image offset
`0x13f44` supplies base `0x52070000` and writes
to descriptor-derived control words. The six
identified state-table set/clear call pairs also
use other LPCM bases and each targets PSM0
state 1. None of the traced paths writes
`0x6f409018`.

The stock log records the DBL boot-sequencer
wait and the GDMC/CPM boot-argument handoff.
It gives no timestamp or value for CPM's first
DPU descriptor read. The inspected early setup
supplies no writer for the descriptor. Its origin
and value at reset remain unverified. Keep PSM1,
PHY TX and host reads disabled.

###### Offline D1 DP0 operating-point telemetry

The exact CPM definitions for `dpu_dp0` and `dpu_dp1`
at `0x8515c` and `0x8517c` register LPCM operating-point
directories for IDs `0x28` and `0x29`. The descriptor
and I/O callbacks at `0x14030`, `0x13e74` and `0x13fa4`
handle operating-point attributes including `lpcm.cur`,
`cur` and per-point `MHz`. The matching configuration
records at `0x58cd8` and `0x58ce4` both have a null
configuration pointer and a clear enable byte. Reads
of the current-level attributes branch from `0x13e9c`
to the error return at `0x13f50` before calling the
getter. The `0x205` power-domain dispatch uses the
separate DPU LPCM ID `0x23` and PSM1.

The exact stock `google_powerdashboard.ko` residency
handler (`0x29e4`) has compiled labels for AOSS and GSA
votes on FABSTBY and DRAM. The blocker handler (`0x1ce4`)
labels a DPU wrapper row but has no DP0 or PSM1 row.
Neither the named CPM directories nor these dashboard
views provide a sample of physical DP0 state. The AP
DP0 vote trace remains the available same-window
evidence. No new PSM1, PHY TX or DSI0 host access is
qualified by this audit.

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

The Grizzly-only host bridge offers a `backup DIRECTORY` command
through `stock-nv-transport.py`. It uses the restricted reader's
`probe`, `read LABEL OFFSET_BYTE LENGTH_BYTE` and `sha256 LABEL`
operations. Each read is capped at 8 MiB and checked for exact length.
The bridge compares each saved image with a separate phone-side
SHA-256 and rechecks the board, partition identity, size and read-only
state after the last copy. It writes `SHA256SUMS`, `partitions.txt`
and `NV-BACKUP` in the private destination. The transport only
accepts the nine Grizzly labels and exposes no shell.

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
read and rechecks the inventory after the copy. It requests
at most 4 MiB per chunk. If a serial transfer times out, the
bridge reopens the verified ACM endpoint, discards the partial
reply, and confirms the same guarded inventory before the host
retries the chunk.

The measured partitions total 3,392,151,552 bytes (3.16 GiB).
The independent read in the phone adds UFS and hashing work
without sending the partition bytes twice over USB. At 5
MiB/s, the USB copy alone takes about 11 minutes. PID 1
arms a 20-minute fallback. The reader closes after an explicit
host `finish`. PID 1 then requests the warm return after the
gadget and USB roles are cleaned up. Hold Volume Down when
cued for that return, or before the timer expires if the
connection fails.

Start the macOS bridge before booting slot B. The generated
`host-tools/` directory contains the Grizzly bridge and USB checker.
Set `bundle` to that directory.

```sh
bridge_dir=$(mktemp -d /private/tmp/grizzly-nv.XXXXXXXX)
export GRIZZLY_NV_SOCKET="$bridge_dir/bridge.sock"
"$bundle/tools/stock-nv-transport.py" serve "$GRIZZLY_NV_SOCKET" --wait 100
```

In a separate shell with the same socket path, wait for
`Grizzly NV reader ready` before starting the copy. Use an
existing private parent directory and a new backup directory
outside the checkout.

```sh
"$bundle/tools/stock-nv-transport.py" backup "$backup_dir"
(cd "$backup_dir" && shasum -a 256 -c SHA256SUMS)
```

After all nine hashes and the bundle manifest verify, cue Volume
Down and run `"$bundle/tools/stock-nv-transport.py" finish`.
To use this backup for an upcoming power or CPM trial, leave the
phone in Fastboot after the reader's warm return. If the session
ends here, select and boot stock A. That makes this copy a recovery
snapshot and requires another fresh backup before a later power
or CPM trial.

Offline tests covered verified-topology publication, PID 1 dispatch
and timed return, ARM64 reader refusals after guard changes, and an
exact 8 MiB serial frame. The Grizzly backup command also passed a
synthetic nine-partition copy over the macOS socket and refused a bad
digest, a changed inventory, an unguarded partition, and an existing
destination. The historical attended run below verified
hardware startup and full-size copy throughput with the same guarded
reader protocol.

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
The host bridge and guarded reader accept exactly nine backup labels.

The rescue keeps the factory D1 kernel, UFS module and UFS regulator
settings. The isolation DTBO changes USB setup. PID 1 enumerates GPT
metadata, sets and verifies all UFS parents and partitions read-only,
and then starts the restricted ACM service. There is no Android or
installed root, shell service, raw SCSI service or other partition
payload reader. The Grizzly backup command is the first payload reader
through ACM. The service allows 1,140 seconds for the copy and its independent
on-phone hash pass, with the 1,200-second return timer armed by PID 1.
The previous full copy and verification took 303 seconds.

The offline repack passed all five image hashes, AVB, saved slot size
and handoff bounds checks. Its `init_boot` SHA-256 is
`0c0405256bd3fb214c340721b16588e82f02096a02d115a36cc6d030b757e175`.
It keeps the previously tested reader binary and packs the current PID 1.
The bundled host tools completed a synthetic nine-partition backup and
rejected a separate bad-hash test.

Keep the images and the backup off-repo. Use the attended staging and
return sequence only after approval. Stop if the guard or USB descriptor
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

#### First hardware backup with the Grizzly host command

On 2026-11-25, the Mac left stock D1 A at 21:02:34 UTC and
requested one rescue boot on B at 21:03:21 UTC. The rebuilt
rescue kept the checked D1 factory boot images and USB
isolation DTBO, with a fresh `init_boot` from the same guarded
RAM rescue sources. The five slot B writes passed. The
`vendor_boot_b` readback matched all 67,108,864 image bytes.
The Mac accepted the guarded inventory before the first
partition payload request.

The first copy stalled at 8 MiB per read. The 4 MiB retry
also hit an ACM reply timeout. Both incomplete copies were
removed. Within the same rescue boot, the final copy used
4 MiB reads and recovered one further timeout by reopening
the verified ACM port and rechecking the inventory. It then
retried the interrupted chunk and continued the existing copy.

The final copy took 297 seconds, including the independent
phone-side digests and final guarded inventory check. On
the Mac, the nine files totaled 3,392,151,552 bytes. Separate
checks verified all nine hashes and sizes, the recorded
read-only and unmounted state, and directory and file modes
of 0700 and 0600. The backup stays private and off-repo.

The reader acknowledged `finish` at 21:14:09 UTC. Bootloader
Fastboot returned 33 seconds later, and the Mac selected
and verified slot A. The phone stayed in Fastboot so this
copy captures the NV state after the latest stock Android
boot and before the next power or CPM trial.
