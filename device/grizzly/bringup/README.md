<!-- SPDX-License-Identifier: MIT -->
# Grizzly D1 bring-up fixtures

The [milestone plan](../BRINGUP-M1.md) describes the storage and attended
boot gates. The current experiment uses D1 B0 and a link-only UFS diagnostic.
The prebuilt v29 package has SHA-256
`c30bee4abf52c796eb833841ad215b365a3525789b125589f812862e5e555ed2`.

- The [v29 kernel source commit](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/401ec7a0581a508ec414b5cdb5328b2d93f5a2ac)
  records the source used for the v29 fixture.
- `v29-rescue-init` is the first-stage wrapper used for the live DT and
  90-second warm restart markers. It hands off to the shared initramfs.
  The v29 archive uses RAM rescue with the write allowlist omitted.
- The four `.dtso` files are the watchdog, ramoops, USB and UFS diagnostic
  overlays. `grizzly-fixture.dts` and `d1-packaging.conf` record the
  B0 image layout. The packaging configuration is stored here as a
  historical input. The active descriptor for first-storage rescue is a
  separate review item.
- `check-handoff.py` validates the five-image handoff layout.
  `check-slot-b.py` validates saved Fastboot variables, image sizes and
  hashes, and an optional full `vendor_boot_b` readback. The standalone
  `stage-slot-b.sh` stages the five Grizzly images while A remains active.
- Building another package requires a local AVB signing key. The signing
  key and per-device calibration and capture data stay private.

## Kernel provenance

The v14–v29 sources are published on the
[grizzly-ufs-bringup-v29 branch](https://github.com/adrienlacombe/linux-omarchy-mobile/tree/grizzly-ufs-bringup-v29).
The v21 row records the original build commit. The v22–v29 commits were reconstructed from the saved
incremental build inputs and have the exact recorded source trees.
The v17–v20 bundles reused the v16 kernel byte for byte.

| Trial | Kernel release | Source commit |
| --- | --- | --- |
| v16 | `7.3.0-rc6-omamobile-push1` | `060ea533afee5e0d2d294781d71c9c71ca4c209d` |
| v17 | `7.3.0-rc6-omamobile-push1` | `060ea533afee5e0d2d294781d71c9c71ca4c209d` |
| v18 | `7.3.0-rc6-omamobile-push1` | `060ea533afee5e0d2d294781d71c9c71ca4c209d` |
| v19 | `7.3.0-rc6-omamobile-push1` | `060ea533afee5e0d2d294781d71c9c71ca4c209d` |
| v20 | `7.3.0-rc6-omamobile-push1` | `060ea533afee5e0d2d294781d71c9c71ca4c209d` |
| v21 | `7.3.0-rc6-omamobile-grizzly-uic` | `636ab3520b59c3a46c9c665ec8dca69b166a54f6` |
| v22 | `7.3.0-rc6-omamobile-grizzly-uic-v22` | `3116d3d595d6db7c005bebcf3208eadbf96c2b01` |
| v23 | `7.3.0-rc6-omamobile-grizzly-uic-v23` | `8cf8b2c0e59610d9a094671cacd2d77332ab948c` |
| v24 | `7.3.0-rc6-omamobile-grizzly-uic-v24` | `18f8e88446b1887abd9d9b90ee1376ad6b3a9212` |
| v25 | `7.3.0-rc6-omamobile-grizzly-uic-v25` | `a1a624dc7369afc9a1e797ec04ce08ff86d85fbd` |
| v26 | `7.3.0-rc6-omamobile-grizzly-uic-v26` | `8d06ebd99ceeb6262e9bf25e36aee1ec80ae4b31` |
| v27 | `7.3.0-rc6-omamobile-grizzly-uic-v27` | `d7f14a149fa53698909573c69f40524fe0ee1156` |
| v28 | `7.3.0-rc6-omamobile-grizzly-uic-v28` | `66718fcd0432e029d2f57070adcfebfa02ccb3e0` |
| v29 | `7.3.0-rc6-omamobile-grizzly-uic-v29` | `401ec7a0581a508ec414b5cdb5328b2d93f5a2ac` |

The [v39 diagnostic branch](https://github.com/adrienlacombe/linux-omarchy-mobile/tree/grizzly-ufs-bringup-v39)
contains the v30–v39 source history. Commit
`8ba5fdb292d5229c01d6b4948b21306721e5360f` records the
initial-vote patch used to build v39 on top of the v38 source.
The [v39 trial](../BRINGUP-M1.md#v39-slot-b-result) records the
original build provenance and hardware results.
The same branch carries the
[read-only bRefClkFreq guard](https://github.com/adrienlacombe/linux-omarchy-mobile/commit/af719fb07680986d5e2ad0a3f798f0c55f7306fe)
for future full-device initialization.

The [v40 diagnostic branch](https://github.com/adrienlacombe/linux-omarchy-mobile/tree/grizzly-ufs-bringup-v40)
adds the provider-only idle prep experiment at
`341a5e41a7836e346ba6bdabfed818ac1dd938de`. See the
[v40 runbook](../BRINGUP-M1.md#mainline-v40-idle-prep-diagnostic)
for its vote ownership and PSM1 gates.

The [v41 diagnostic branch](https://github.com/adrienlacombe/linux-omarchy-mobile/tree/grizzly-ufs-bringup-v41)
adds genpd idle-release logging at `e040f855e9ca3eb513734e5bad5c176497446ec6`.
See the [v41 runbook](../BRINGUP-M1.md#mainline-v41-genpd-idle-release-trace)
for the stock D1 comparison and expected gate records.

The [v42 diagnostic branch](https://github.com/adrienlacombe/linux-omarchy-mobile/tree/grizzly-ufs-bringup-v42)
adds the prep-only latch opt-out at `0d5e4078f0a7d2f6be666948820ea04b96e7cd96`.
See the [v42 runbook](../BRINGUP-M1.md#mainline-v42-guarded-prep-idle-release)
for the guarded OFF and resume sequence.

The [v43 diagnostic branch](https://github.com/adrienlacombe/linux-omarchy-mobile/tree/grizzly-ufs-bringup-v43)
adds the guarded UIC link test at `ffdbb1117dfaacbeca2b9646edff4ef513833121`.
See the [v43 runbook](../BRINGUP-M1.md#mainline-v43-guarded-ufs-link-diagnostic)
for the host handoff and link-only boundaries.

The earlier first-light sources are published on the
[grizzly-first-light-archive branch](https://github.com/adrienlacombe/linux-omarchy-mobile/tree/grizzly-first-light-archive).
The table distinguishes
the kernel binary source from the board DT source for the
DT-only repacks. These archived commits reproduce the recorded
trees. All rows used kernel release `7.3.0-rc6-omamobile-push1`.

| Trial family | Kernel source commit | Board DT source commit |
| --- | --- | --- |
| Initial USB-logging candidate, stopped in ABL | `a06d506d04cfc38d250f583e896ab07a90982070` | `a06d506d04cfc38d250f583e896ab07a90982070` |
| Corrected USB candidate plus timed poweroff, USB, DWC3, rail and deferred-warm variants | `a06d506d04cfc38d250f583e896ab07a90982070` | `659e3f611c1c78cc80a51f22ed8ec80b3258c43d` |
| v13 | `7b0f8846ee93629eb60355ca1249e159ae565be2` | `659e3f611c1c78cc80a51f22ed8ec80b3258c43d` |
| v14 | `02332bce8eebeb4f098acf786061068cd83f428f` | `659e3f611c1c78cc80a51f22ed8ec80b3258c43d` |
| v15 | `d59854d29c5cb03305ff8a08e49fd29f3582cfe2` | `659e3f611c1c78cc80a51f22ed8ec80b3258c43d` |

Hardware provenance for the older offline v1–v10 experiments remains unverified.
