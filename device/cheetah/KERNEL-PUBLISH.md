<!-- SPDX-License-Identifier: MIT -->
# Publishing the kernel: candidate `omamobile-next` (cheetah / gs201)

Status (2026-10-19): **published.** `omamobile` is on GitHub
(linux-omarchy-mobile, 146 commits on v7.3-rc6) and moves forward without
rewriting published commits: `tools/publish-kernel` fast-forwards when the
published tip's tree matches a local commit, and otherwise stops unless
given `--rebuild`; it always stops when it can't read the published tip.
Community kernel PRs are reviewed against it (felix's board file and UFS
are merged). First patch sent upstream: "power: supply: max17042_battery:
infer the status when no supplier is described" (linux-pm, 2026-10-19),
Reviewed-by Hans de Goede, waiting for the maintainer.

Earlier status (2026-10-12): **prepared, not pushed.** Branch `omamobile-next` in
`~/android/mainline/wt-next`, built in `~/android/mainline/out-next`
(`7.3.0-rc6-omamobile-push1-00123-gadb29333ff8c`). Head `adb29333f`, 65
commits on top of the published `omamobile` (`7b0f8b5d1`, 58 commits on
v7.3-rc6). Nothing here has run on the phone as this exact tree; see
section 5 before publishing.

**Kernel branches renamed (2026-10-13).** With the project's rename to
Omarchy Mobile, every local kernel branch moved from `omandroid*` to
`omamobile*` (`omandroid` -> `omamobile`, `omandroid-int` -> `omamobile-int`,
`omandroid-<subsystem>` -> `omamobile-<subsystem>`, `publish/omandroid*` ->
`publish/omamobile*`); the `wt-*` worktree directories and the
`omandroid-final` tag keep their names, and old merge subjects keep the old
branch names. The in-tree strings followed: `omamobile` gained the
`omamobile.ufs-probe` bootargs commit, and `omamobile-camera` the
`omamobile/camera` firmware paths and comments; both are merged into
`omamobile-int`. So `omamobile-next` no longer sits directly on `omamobile`:
rebase it (`git rebase omamobile omamobile-next`) before 5.4's
`merge --ff-only`; the `omamobile-next` hashes below are from before that
rebase.

`omamobile-int` (what the phone runs) had 194 commits beyond `omamobile`.
Each was classified as ready, bring-up only, superseded or not yet verified on
the phone, from the plans' recorded results and NOTES.md. The ready ones
were picked into a clean series grouped by subsystem; fixups were squashed
into what they fix, and debug or staging code inside otherwise ready commits
was removed. Authorship and author dates are kept. No commit carries a
`Signed-off-by:` (the human signs off; see 6.2 in CONTRIBUTING.md).

## 1. What is in `omamobile-next`

| Subsystem | Commits | Source in int | On by default? | Evidence |
| --- | --- | --- | --- | --- |
| of/fdt: warn on a wrong-length address/size property | 1 | `d520f515d` | n/a | the reserved-memory gotcha (AGENTS.md) |
| Power: MCT, C2 idle states, enable, UFS auto-hibernate | 5 | `f417af56e` `8aafd27af` `048d17940` `241736cc0` `20bd72c37` | yes | POWER-PLAN 7 (C1, C2), default DTB since |
| Suspend: `mem_sleep_default=s2idle` | 1 | `025624c64` | yes | SUSPEND-PLAN S1, S2 |
| ACPM: mailbox, IPC, channel checks, gs201 data, DT | 6 | `6215075eb` `c1ec34140` `e571deea3` `a7a72e9f4`* `08ccfb13c` `28044d887` | yes | NOTES "everything working so far comes up at boot" (int 00171) |
| Bluetooth: CMU_APM, APM sysreg, UART, APM UART DT, BT node | 6 | `c059c9f2a` `13b9350ba` `9e489c0b2` `d0eb1ab5e` `b5f61a9bc` `8d84a3cd7` | **no** (described, disabled) | BT1-BT3 |
| USB/charger: USB DRD PHY binding, max77759 init fix, battery charge limits | 3 | `06e60a228` `1074d2178` `c86bd2db7`* | n/a (charger not autoloaded) | NOTES B3.3 (4450 mV, 1467 mA) |
| Haptics and torch: sysreg, i2c-exynos5 timeout, cs_dsp fix, CS40L26, LM3644, PERIC0/USI8/USI15, describe, enable | 10 | `16ff4879a` `00824e18b` `7df42ee05` `c89aea791` `f23ce2c8f` `1ad1af33c` `32d286884` `523b1e0e0` `ebcd2674f`* `d609c1b3e`* | yes | NOTES H1-H3, T1-T3; default-on since int 00171 |
| Speaker amplifiers: USI7 SPI, CS35L41 nodes, `cirrus,dsp-no-hibernate` | 5 | `94df2a402` `c115ad543`* `8c4a74fc3` `165c2da7b` `60d3ca176` | **no** (disabled; inert without an AoC sound card) | AOC-PLAN C7b, C7d-7, C8, C8f |
| HSI1 pinctrl | 1 | `f7a9852f1` | no (disabled) | MODEM-PLAN M0.4 |
| PCIe GEN4A_1: PHY and host bindings and drivers | 4 | `8e13b3087` `57b2fd4a6`* `4736d8694`* `acae5a0ab`*+`6f384898b` | n/a | WIFI-BATTERY-PLAN 9.14-9.16 |
| brcmfmac BCM4389 | 19 | see below | n/a | W2 (00088), W3 (00131), default-on (00171) |
| Wi-Fi DT: pool binding, HSI2 pinctrl + pcie_1, BCM4389 node, enable | 4 | `d67bdaad6`* `44de4b216`+`1d2d4f08e` `b715968cc`+`beb64496c`+`7ba655a94` `242602382`* | yes | WIFI-BATTERY-PLAN 9.21, NOTES (int 00171) |

`*` = changed while picking (section 2). The brcmfmac commits, in order:
`47b75a6a2` `6505722a9` `18b233c95` `f5efa077b` `9f7b5cac4` `44dca3e6b`
`7151e4834` `449fdf52b` `8358ff260` `bacfef43f` `e89538839`,
`2c738ed2d`*+`07c519fd7`, `2cf2a9426`*, `1b668f01f` `dfc8407db` `bbad7a1c6`,
`e1c6379cf`* (with its conflict against the dropped debug code resolved),
`c0545e232` `24cfee473`.

The series, in order (`git log --oneline omamobile..omamobile-next`):

| Commit | Subject |
| --- | --- |
| `f9e13bb90` | of: fdt: warn when an address/size property has the wrong length |
| `c631fbb85` | dt-bindings: timer: exynos4210-mct: add Google gs201 compatible |
| `fbe11bfd2` | arm64: dts: exynos: google: gs201: add the MCT |
| `6800c3c40` | arm64: dts: exynos: google: gs201: add the C2 CPU idle states |
| `ccf3b6122` | arm64: dts: exynos: google: gs201: enable the MCT and the C2 idle states |
| `9d7ff4a3b` | scsi: ufs: exynos: don't enable auto-hibernate on gs201 |
| `ac6a7bf4b` | arm64: dts: exynos: google: gs201-cheetah: default to suspend-to-idle |
| `1a25b8b20` | dt-bindings: mailbox: google,gs101-mbox: add gs201 |
| `503171c0f` | dt-bindings: firmware: google,gs101-acpm-ipc: add gs201 |
| `19bb6469a` | firmware: samsung: acpm: check the channel table read from SRAM |
| `1e9da6a3e` | firmware: samsung: acpm: skip channels the AP cannot use |
| `f3bad62f2` | firmware: samsung: acpm: add gs201 support |
| `e2f4666a4` | arm64: dts: exynos: google: gs201: add the APM mailbox, SRAM and ACPM |
| `b09b1aec5` | dt-bindings: clock: google,gs201: add CMU_APM |
| `7f269f862` | dt-bindings: soc: samsung: exynos-sysreg: add gs201 APM sysreg |
| `feddb2cbc` | dt-bindings: serial: samsung: add Google gs201 UART |
| `75cb3fdc6` | clk: samsung: gs201: add a read-only CMU_APM subset for the APM UART |
| `196021c72` | arm64: dts: exynos: google: gs201: add the APM UART, CMU_APM and PERIC0 pinctrl |
| `1ebb8df8c` | arm64: dts: exynos: google: gs201-cheetah: describe the BCM4389 Bluetooth |
| `730ef781c` | dt-bindings: phy: samsung,usb3-drd-phy: add Google gs201 |
| `c82b957e2` | power: supply: max77759: zero the regulator and power supply configs |
| `25c2f1dfc` | arm64: dts: exynos: google: gs201-cheetah: give the charger its battery limits |
| `67c5d7a5b` | dt-bindings: soc: samsung: exynos-sysreg: add gs201 PERIC0 compatible |
| `151c215ee` | i2c: exynos5: scale the transfer timeout with the message length |
| `7038eac47` | firmware: cs_dsp: don't treat a changed control as a write sequence error |
| `3777f82ce` | dt-bindings: input: add Cirrus Logic CS40L26 |
| `506753d15` | Input: add a Cirrus Logic CS40L26 haptics driver |
| `97a82fa50` | dt-bindings: leds: add TI LM3644 |
| `1016e2952` | leds: flash: add a torch-only TI LM3644 driver |
| `218c45eed` | arm64: dts: exynos: google: gs201: add PERIC0 pinctrl, USI8 and USI15 I2C |
| `d5e295232` | arm64: dts: exynos: google: gs201-cheetah: describe the haptics driver and the flash LED |
| `53cf527c0` | arm64: dts: exynos: google: gs201-cheetah: enable the haptics and the flash LED |
| `6831a72d7` | arm64: dts: exynos: google: gs201: add USI7 SPI |
| `feb542a70` | arm64: dts: exynos: google: gs201-cheetah: describe the speaker amplifiers |
| `230146695` | ASoC: dt-bindings: cirrus,cs35l41: add cirrus,dsp-no-hibernate |
| `ad46391ca` | ASoC: cs35l41: honour cirrus,dsp-no-hibernate |
| `859f3ef91` | arm64: dts: exynos: google: gs201-cheetah: keep the amplifier DSPs out of hibernate |
| `bd2f5bc61` | arm64: dts: exynos: google: gs201: add HSI1 pinctrl |
| `8485fe419` | dt-bindings: phy: add Google gs201 PCIe PHY |
| `5294a8c67` | phy: samsung: add Google gs201 PCIe PHY driver |
| `a0f805b2e` | dt-bindings: PCI: add Google gs201 PCIe host controller |
| `d06d0ed9b` | PCI: dwc: add Google gs201 PCIe host controller driver |
| `c2baaa466` | wifi: brcmfmac: don't cancel the bus reset work before it exists |
| `39ff7ce3c` | wifi: brcmfmac: chip: size the BCM4389 SYSMEM from its RAM banks |
| `d39cc747a` | wifi: brcmfmac: pcie: move the BAR1 window for RAM beyond the BAR |
| `3e6726fdc` | wifi: brcmfmac: pcie: request the BCM4389 power domains after reset |
| `d93b30a4c` | wifi: brcmfmac: msgbuf: put sequence numbers in H2D control messages |
| `4367094f0` | wifi: brcmfmac: msgbuf: never use packet ID 0 |
| `98e9e03ad` | wifi: brcmfmac: pcie: use a 64-bit DMA mask |
| `4ac2355e6` | wifi: brcmfmac: pcie: say why the ring indices fall back to TCM |
| `46bebad20` | wifi: brcmfmac: pcie: ring the core doorbells when the firmware has no DAR |
| `90eed1edb` | wifi: brcmfmac: pcie: write the host capabilities for the BCM4389 |
| `ee264652e` | wifi: brcmfmac: msgbuf: keep rx packet IDs for the control buffers |
| `702910e16` | wifi: brcmfmac: pcie: ring host ready once, early, on the BCM4389 |
| `158f42053` | wifi: brcmfmac: pcie: look at the rings again after an INTx on the BCM4389 |
| `eca67b6ac` | wifi: brcmfmac: pcie: reset the BCM4389 with an FLR |
| `7d14311a0` | wifi: brcmfmac: use the versioned join parameters on the BCM4389 |
| `fefd46c96` | wifi: brcmfmac: msgbuf: build the 802.3/LLC TX header on the host for the BCM4389 |
| `9a2d8df32` | wifi: brcmfmac: pcie: poll the D2H rings after interrupts on the BCM4389 |
| `943a18985` | wifi: brcmutil: decode the 6 GHz band in d11ac chanspecs |
| `1a39a3922` | wifi: brcmfmac: skip 6 GHz chanspecs when building the channel list |
| `411e965b7` | dt-bindings: net: wireless: brcm,bcm4329-fmac: allow a restricted DMA pool |
| `1d10f76cd` | arm64: dts: exynos: google: gs201: add HSI2 pinctrl and PCIe GEN4A_1 |
| `91eea0a9b` | arm64: dts: exynos: google: gs201-cheetah: wire up the BCM4389 Wi-Fi |
| `adb29333f` | arm64: dts: exynos: google: gs201-cheetah: enable Wi-Fi with its restricted DMA pool |

## 2. What changed while picking (review these first)

The tree differs from what the phone ran in these places. All are removals
of bring-up code that is off at its default value, comment and message
wording, or the squashes named here.

- **`phy-gs201-pcie.c`:** removed the `trace`, `trace_delay_ms` and
  `check_tcxo` parameters, the trace helper and its calls, and the
  TCXO check (off by default). The lock-poll helper lost its label argument.
- **`pcie-gs201.c`:** removed `stop_after` (staged probe), `trace`,
  `trace_delay_ms`, `use_ia` (always on, as at its default), `cmu_acg_off`
  and the `samsung,cmu` CMU_HSI2 mapping and dump. The stage functions became
  plain helpers (`gs201_pcie_clocks_on/wake/phy_on/ctrl_setup/power_up/
  power_down`); `ctrl_setup` always releases PERST#, which was the only path
  the bound driver used. The stage announcements, the ELBI, D-state and IOCC
  register prints went to `dev_dbg`. A duplicated block of I/A defines was
  dropped. `6f384898b` (coherency again after link up and after enumeration)
  is squashed in, without its disproven "this is how the first runs fail"
  claim.
- **`google,gs201-pcie.yaml` and `gs201.dtsi`:** `samsung,cmu` removed (it
  only served the dropped `cmu_acg_off`).
- **brcmfmac `pcie.c`:** dropped the debug-only commits `e765e7004` (32-bit
  alias watcher) and `53a679e7a` (dongle DMA dump), and the index dump half
  of `2c738ed2d`. After the series the file differs from int only by that
  debug code (checked with `git diff omamobile-int`). `07c519fd7` (host
  ready only once, 0x12345678) is squashed into `2c738ed2d`. The proprietary
  firmware symbol-map citation (`_hnd_die`, `pciedev_handle_hostready_intr`)
  is gone from the message and the code comment; the trap lines from the
  firmware console (our capture) stay.
- **ACPM `a7a72e9f4`:** kept as its own commit, without the `dump_chans`
  parameter and the raw-descriptor dump; a skipped channel gets a one-line
  warning.
- **Charger `c86bd2db7`:** only the battery limits and `monitored-battery`.
  The sink-only port half is held (B4 has not run), and so is the comment
  about `default_ilim_ua`.
- **Wi-Fi DT:** `1d2d4f08e` (INTx map 1..4) squashed into `44de4b216`;
  `beb64496c` (no host-wake interrupt) and `7ba655a94` (pool below 4 GiB)
  squashed into `b715968cc`, with the disproven "writes above 4 GiB are not
  seen" replaced by the stock reason (32-bit IOVAs). The enable commit is
  rewritten without the `&pcie_1_sysmmu` hunk, since the SysMMU is held.
  The messages no longer promise S2MPU confinement.
- **Comments and messages:** references to our plan files (`*-PLAN.md`, gate
  names) and "until bring-up" wording are gone from the new DT comments
  (APM UART, PERIC0, Bluetooth, haptics, torch, speaker amplifiers, the APM
  mailbox placeholder). The haptics enable message no longer claims feedbackd
  and the shell tile (H4/T4 have no recorded result).

## 3. What is held back, and why

| Area | int commits | Why |
| --- | --- | --- |
| Display (gs-decon KMS, 120 Hz, panel sleep) | `1ca875861` `1d567d206` `96f810ca9` `00e49c41b` `52ec674f1` `a2a2ee90d` `fa6d7aec8` `04cbbeca6` `32b4bf0c3` `445d2b4f7` `3e242dc3f` `cb0400f56` `5081097ac` `d4b2e68a3` `fe2647543` `dcc41a530` `2ca20ad4d` `172c08f89` `7d689978a` `5f4808c32` | Works (D6, 120 Hz), but needs rework: the driver commit is a staged bring-up driver (`stage`, `force_xrgb`, "bring-up driver" Kconfig); five later commits are fixups of it; `cb0400f56` mixes the KMS-default change with the 120 Hz mode; comments cite DISPLAY-PLAN. Its DTS needs the ACPM `mif`/`disp` clocks, so it also waits for the ACPM clock commit. `screen_off` (`172c08f89`, `dcc41a530`, `2ca20ad4d`) has not passed D3b-1c/D3b-2. |
| ACPM GPU clock and GPU DVFS | `12af44fa2` `d9a47b2d0` | Verified (151-572 MHz), but the cap is a staging module parameter (`gs201_gpu_max_khz`, default read-only) that `omamobile-device-cheetah` sets. Rework: cap through the OPP table, drop the parameter and the package option together. |
| Bluetooth enable | `ff4788789`, `d273f95bf` | Works only with the `btbcm patchram_nowait=1` bring-up parameter the package sets. Needs an upstream-style BCM4389 quirk first. The BT nodes are in next, disabled. |
| S2MPG12 PMIC, RTC, VGPIO2AP, s2idle PMU hint | `279130ea5` `a0cdfa111` `6c0840744` `9270c1a8c` `9f0ff0acc` `93555da2a` `8d820bc0a` | SUSPEND-PLAN S3/S4 not run. |
| S2MPG13, USI5, GNSS | `4a2cadde4` `7ef20d70e` `3510a9c19` `c3937a59e` `cb0505cc1` `bb576befa` `85664485f` `eb04c6c3c` `7f4083e7c` | S2MPG13 passed G1-G3d, but only with overlays, and it depends on the held S2MPG12 commits. The BCM4775x driver is a misc driver with Broadcom's private ABI and bring-up logging (belongs in `drivers/gnss/`); `7f4083e7c` mixes its needed nstandby fix with event logging. `bb576befa` cites GNSS-PLAN in comments. |
| NFC | `cad9624c0` `2f769ea68` `40a8b3779` `9b7ba4873` `829e25aed` `e4e3913df` `ec375b274` `a6ed1ea8b` | N2/N3 never ran; clock pad polarity open. |
| USB-C / Type-C, charger policy | `49a930690` `6cb72374d` `80ffae6d5` `45e5489db` `37a83337c`, sink-only half of `c86bd2db7` | B4 not run; `default_ilim_ua`, `force_vbus_valid` and `temp_guard` are policy module parameters; the temperature guard (B3g) has no results. |
| AoC, GSA, AoC SysMMU, Trusty, AoC sound card | `58e9fb0a2` `21aa277d2` `aed858b94` `477a82e16` `18c468053` `6b3275d37` `36319e05e` `d239d411e` `2fcba2704` `5caf0d303` `0610de752` `3a71f0471` `973b54b71` `2f785843b` `615b5188a` `0e5c2082d` `edfb4e5df` `aa453aaee` `c868f906b` `deb7b47bd` `d9cc04ae4` `f141bb96a` `f716b607e` `b45ee6475` `8945b2413` `33b28cee6` `d696fde42` `67abdfab5` `dfeafb2ba` `2211dd734` `24483c36e` `e8929e1b2` `71c7777b0` `24d9b9826` `829fd316a`; Trusty `d50eb73ae` `0fa5efc32` `210377ee6` `edae3bf75` `5a9cf359f` | Imported Google drivers (AoC core 10.6k lines, ALSA 17.6k, Trusty 8.4k) not yet ported to upstream style; "for bring-up" boot/rails/GSA drivers with debugfs steppers; a WIP port. Works on the phone (first sound, sensors), so this is the largest porting job left. Squash map when ported: `18c468053`->`58e9fb0a2`, `36319e05e`->`aed858b94`, `edfb4e5df`->`5caf0d303`, `c868f906b`->`973b54b71`, `2f785843b`->`6b3275d37`, `33b28cee6`/`67abdfab5`/`2211dd734`->core port, `dfeafb2ba`/`71c7777b0`/`24d9b9826`->ALSA port. |
| Modem PCIe GEN4A_0 | `af92668ea` `d6b91d06d` `5f6a1a989` `fb3537d02` `665a08b47` `c22dc53b3` `d04cff4b9` `9c201b3f3` `078ad0c76` `3a8f4c503` | A debugfs-stepped bring-up driver; M2.5 and M3 not done. |
| Wi-Fi bring-up only | `e765e7004` `53a679e7a` `c7b2c66ec` `998f718de` `434a1be2e` `49b341b4a`, debug half of `2c738ed2d` | Debug dumps and the staged HSI2 probe. |

**Superseded, dropped for good:** the PCIe SysMMU approach (`be2c591e3`
`43d687e72` `cb50d430a` `aecc19faa` `528c3381f` `841baece6` `7ff22794d`:
VID 0 is shared with UFS, WIFI-BATTERY-PLAN 9.20/9.21); the CS40L26 split
writes and their revert (`893060cbf` `892abb750`); the int-only revert and
reapply of the ACPM merge (`561b8a03a` `86683adea`, they cancel); the AoC
mailbox ranges replaced by `mboxes` (`01be75e8a` `7bea582c5`); and
`375055bd1`, a duplicate of `33b28cee6`.

Not merged into int and not considered: 7 commits only on
`omamobile-fingerprint`, 1 only on `omamobile-wifi-d3`.

**For the repo, when publishing:** `kernel/configs/omamobile.config` still
enables `CONFIG_PCIE_GS201_SYSMMU=m` and the modem, AoC and Trusty symbols;
`merge_config` ignores symbols the tree doesn't have, so `omamobile-next`
builds as is. `CONFIG_BRCMDBG=y` is a debug option worth reviewing.

## 4. Checks run (offline, 2026-10-12)

- Full build with the repo's config fragment:
  `KERNEL_DIR=~/android/mainline/wt-next KERNEL_OUT=~/android/mainline/out-next bin/omamobile kernel`:
  no compiler warnings.
- `W=1` of every C file the series touches: no warnings.
- Every commit builds its changed objects and `gs201-cheetah.dtb` on top of
  the previous ones (bisectability check, section 4.1).
- `dt-doc-validate` and yamllint of every binding the series touches: clean.
- `dt-validate` of `gs201-cheetah.dtb` against the tree's bindings: see 4.1.
- No dtc warnings for gs201 in the build log.
- checkpatch: no errors except `7d14311a0`, where `chanspec_list[1]`
  mirrors the firmware's fixed `wl_assoc_params` layout as the existing
  `brcmf_assoc_params_le` does. Warnings are the `Co-Authored-By` spelling,
  MAINTAINERS for new files, and long DT clock-name lines.
- Messages: no mention of other projects, no MAC or Bluetooth addresses,
  serials, IMEIs or SSIDs, no non-citable source (the firmware symbol-map
  reference was removed). Sources cited: Google's GPL kernel and
  google-modules, bcmdhd, the stock device tree and boot logs (our captures),
  upstream Linux.

### 4.1 Results

- Per-commit build: 53 of 65 commits rebuilt their changed objects and the
  DTB without errors; the other 12 change only binding YAML (nothing to
  compile).
- `dt-validate` reports only the two findings the int and published DTBs
  already have: `/soc_id` has no schema (ABL needs it), and simplefb's
  `post-init-providers` is not in the simple-framebuffer schema. Nothing
  for any node this series adds.

## 5. Runbook: review, test, publish

Every step is the human's. Nothing is pushed until step 5.4.

**5.1 Review (read-only, no risk).**

```sh
cd ~/android/mainline/wt-next
git log --oneline omamobile..omamobile-next
git range-diff omamobile..omamobile-int omamobile..omamobile-next | less   # what changed vs int
git diff omamobile-int omamobile-next -- drivers/phy/samsung/phy-gs201-pcie.c \
  drivers/pci/controller/dwc/pcie-gs201.c drivers/net/wireless/broadcom/   # only bring-up code may differ
```

Pass: the differences are the ones in section 2. Stop if anything else
differs.

**5.2 Sign off (rewrites the branch, no risk).** The human adds their own
`Signed-off-by:`; for upstream, `Co-Authored-By:` becomes `Assisted-by:`
(`Documentation/process/coding-assistants.rst`). Keep the published branch
consistent with the existing 58 commits, which carry `Co-Authored-By:`.

```sh
git -C ~/android/mainline/wt-next rebase --signoff omamobile
```

**5.3 Boot it once (optional but recommended; risk: medium).** The phone
has only ever run int. This tree drops the AoC, Trusty, GNSS, modem,
display KMS and GPU DVFS, so on the phone the screen stays on simplefb, the
GPU runs at its placeholder clock and the AoC unit fails; Wi-Fi, haptics,
torch, buttons, touch and USB should come up. Expect `clk_acpm`,
`btbcm` and `gs_decon` options in `/etc/modprobe.d` to be reported as
unknown or unused. Ask the human first (AGENTS.md section 1).

```sh
cd ~/Projects/omarchy-mobile
KERNEL_DIR=~/android/mainline/wt-next KERNEL_OUT=~/android/mainline/out-next bin/omamobile initramfs
KERNEL_DIR=~/android/mainline/wt-next KERNEL_OUT=~/android/mainline/out-next bin/omamobile images
KERNEL_DIR=~/android/mainline/wt-next KERNEL_OUT=~/android/mainline/out-next bin/omamobile push
tools/phone-ssh 'uname -r; ip -br link; journalctl -b -p err --no-pager | head -50'
```

Pass: SSH comes back, `uname -r` is the next release, Wi-Fi associates,
`dmesg` shows no new oops. Stop on any hang (wait for the watchdog, then
section 1 "When a reboot gets stuck"). Rollback: push the int build again
(`KERNEL_DIR=~/android/mainline/wt-int KERNEL_OUT=~/android/mainline/out-int bin/omamobile push`,
with the int images still in `out-int/images`),
or flash `~/android/mainline/known-good` from fastboot.

**5.4 Publish (irreversible: force-pushes the public `omamobile`).**

```sh
cd ~/android/mainline/linux                  # has `omamobile` checked out, must be clean
git merge --ff-only omamobile-next           # omamobile-next sits directly on omamobile
cd ~/Projects/omarchy-mobile
tools/publish-kernel                         # defaults: branch omamobile, tag v7.3-rc6
```

`tools/publish-kernel` replays the 123 commits on the squashed v7.3-rc6
base in a throwaway worktree, checks the tree matches `omamobile`, and
force-pushes `publish/omamobile` to `github.com/derekross/linux-omarchy-mobile`.
Pass: "Published omamobile (123 commits on v7.3-rc6)". (Since 2026-11-01 the
tool fast-forwards a published branch and stops instead of rewriting one: a
rebuild like this one takes `tools/publish-kernel --rebuild`, and its push
is leased on the published tip the run read.) Rollback: the
previous published head is `publish/omamobile` before the run
(`056bfe463`); `git push --force-with-lease=refs/heads/omamobile:<the tip
it replaces> <remote> 056bfe463:refs/heads/omamobile` restores it.

Afterwards: `git worktree remove ~/android/mainline/wt-next` and
`git branch -d omamobile-next` once merged.

## 6. gs201 PMU and watchdog bindings (`omamobile-gs201-bindings`)

Status (2026-10-24): **boot test passed; waiting for the sign-off and the
pull request (6.2).** dt-validate on the
published `omamobile` reported gs201's PMU, its interrupt generator and both
cluster watchdogs as matching no schema: the drivers had gs201 entries, the
bindings never did. Branch `omamobile-gs201-bindings` (worktree
`~/android/mainline/wt-gs201-bindings`, on `github/omamobile` 97a6b87a87cb),
six commits:

1. `dt-bindings: watchdog: samsung-wdt: add google,gs201-wdt`
2. `dt-bindings: soc: samsung: exynos-pmu: add google,gs201-pmu`
3. `dt-bindings: soc: google: gs101-pmu-intr-gen: add google,gs201-pmu-intr-gen`
4. `arm64: dts: exynos: google: gs201: use the gs101 fallbacks for the PMU and watchdogs`
5. `watchdog: s3c2410_wdt: drop the gs201 compatible`
6. `soc: samsung: exynos-pmu: drop the gs201 compatible`

Each gs201 compatible gets its gs101 fallback, since both drivers already
used gs101's data unchanged. The PMU node also drops `"syscon"`, as gs101's
did: with it, a consumer that looks the PMU up before `exynos-pmu` probes
(the UFS and USB PHYs and the watchdogs use
`syscon_regmap_lookup_by_phandle()`) gets a plain MMIO regmap whose writes
the PMU ignores, and `exynos-pmu`'s own registration then fails with
`-EEXIST`. For the watchdogs that would mean ABL's running watchdogs never
stop, and a reset about a minute in. Without `"syscon"` such a consumer
defers. On the boots so far `exynos-pmu` came first, so this removes an
ordering dependency, not a seen failure.

Offline (2026-10-24): `tools/kernel-pr-check --build` passes except the
sign-offs, which are the human's; checkpatch's only notes are the
`Co-Authored-By` trailers. The 2 touched C files build with `W=1`;
`dt_binding_check` passes on the 3 bindings. `dt-validate -m` on cheetah and
felix: the 8 "failed to match any schema" messages are gone, nothing new.
The camera branch's `clk-exynos-clkout` also has a `google,gs201-pmu` entry
with gs101's data; it still matches, and can go when that branch is curated.

The boot test is the phone's running kernel (`omamobile-test-touch`,
8cd00dcfc564) plus this series: branch `omamobile-test-gs201b`, worktree
`~/android/mainline/wt-test-gs201b`, output `~/android/mainline/out-test-gs201b`.
That tree is older than the published one, so the two binding hunks and the
two driver hunks were applied by hand there (the zuma entries aren't in it);
the DTS commit applied as it is. Built as `7.3.0-rc6-omamobile-push1-00576-gc545bd509c58`;
its DTB differs from the running one in the four compatible lines only.

Baseline (read-only, 2026-10-24, `7.3.0-rc6-omamobile-push1-00570-g8cd00dcfc564`):
both watchdogs bound to `s3c2410-wdt`, the PMU to `exynos-pmu`, `exynos-clkout`
present, `devices_deferred` empty, the regmaps `pmu_regs` and `pmu_intr_gen`
only, `/dev/watchdog0` and `watchdog1`, PMU compatible `google,gs201-pmu syscon`.

**6.1 Boot it (risk: medium; the human's go, AGENTS.md section 1).** What
can go wrong: the watchdogs not taken over (a reset about 60 s after boot,
then ABL's slot A fallback after repeated failures) or UFS not coming up.

```sh
cd ~/Projects/omarchy-mobile
KERNEL_DIR=~/android/mainline/wt-test-gs201b KERNEL_OUT=~/android/mainline/out-test-gs201b bin/omamobile push
tools/phone-ssh 'uname -r; cut -d" " -f1 /proc/uptime
  tr "\0" " " < /proc/device-tree/soc@0/system-controller@18060000/compatible; echo
  for d in 10060000.watchdog 10070000.watchdog 18060000.system-controller; do
    echo "$d -> $(basename "$(readlink /sys/bus/platform/devices/$d/driver)")"; done
  ls /sys/bus/platform/devices | grep -c exynos-clkout
  cat /sys/kernel/debug/devices_deferred; ls /sys/kernel/debug/regmap | grep 18060000
  dmesg | grep -iE "exynos-pmu|s3c2410|syscon|pmu-syscon|ufs.*(err|fail)"'
sleep 90; tools/phone-ssh 'cut -d" " -f1 /proc/uptime'   # still the same boot
```

Expect: the new release; compatible `google,gs201-pmu google,gs101-pmu`; the
same three drivers bound; `exynos-clkout` present; nothing deferred; only
`pmu_regs` and `pmu_intr_gen`; no PMU, syscon or UFS errors (a "failed syscon
remap" from the UFS PHY that then probes is a deferral, not a failure);
uptime past 150 s on the second read. Then `tools/phone-smoke`.

Stop: no SSH after 3 minutes, an uptime that drops between the reads (the
watchdog fired), or a missing driver binding. Rollback: push the running
kernel again (`KERNEL_DIR=~/android/mainline/wt-touch
KERNEL_OUT=~/android/mainline/out-touch bin/omamobile push`, images still in
`out-touch/images`); if the phone reset-loops, `bin/omamobile flash` those
images from fastboot. If it fell back to slot A, take a fresh read-only
backup before any radio work (AGENTS.md section 1).

Result (2026-10-24, `7.3.0-rc6-omamobile-push1-00576-gc545bd509c58`): **pass.**
PMU compatible `google,gs201-pmu google,gs101-pmu`; both watchdogs bound to
`s3c2410-wdt`, the PMU to `exynos-pmu`; `exynos-clkout` present;
`devices_deferred` empty; the regmaps `pmu_regs` and `pmu_intr_gen` only;
`/dev/watchdog0` and `watchdog1`; no PMU, syscon or UFS errors (the two
watchdogs log "inactive, reset disabled" at 0.59 s, their takeover).
Uptime 87 s, then 180 s on the same boot. `tools/phone-smoke`: every check
ok, no failed units.

**6.2 Publish.** After a passing boot: sign off, then open the six commits
as a pull request against linux-omarchy-mobile's `omamobile`, so CI gates
them like any other, and merge with a rebase.
