<!-- SPDX-License-Identifier: MIT -->
# akita M2: storage (UFS behind the guard, then the Arch root)

**Status (2026-11-10):** **M2 is complete.** M2.1-M2.6 are done and merged (#456), and **M2.7 passed gate (e)** on 2026-11-10: Omarchy's image runs from `userdata` with the session, the lock and the guard, `reboot-to bootloader` works from it, and a second boot comes up clean ([Results](#2026-11-10-omarchys-image-m27-gate-e)). M1 is complete and merged ([BRINGUP-M1](BRINGUP-M1.md)):
- derekross/linux-omarchy-mobile#192 was rebase-merged on 2026-11-05, so its three commits are on `omamobile` under new ids, with the same patches: `cb2cd5e4b` (binding), `c7eb44543` (first light) and `0e2739a92` (framebuffer).
- #414 was squash-merged as `905aa91`.

M2.1 is done and **M2.3 passed gate (c)** on 2026-11-06: UFS runs at HS-G4 on two lanes behind the guard ([Results](#results)). M2.1's kernel change is derekross/linux-omarchy-mobile#206, rebase-merged on 2026-11-07 as `75b9c0b73`. Its `zuma-akita.dts` is blob `bfa8b6f54e0e`, the DTS that booted in M2.3. M2.4 is done: a fresh backup from our kernel, verified and copied offline. M2.5 is done: `omamobile-device-akita` 0.1.0 and `build-u3-root`. **M2.6 passed gate (d)** on 2026-11-06: Arch Linux ARM runs from `userdata`, behind the guard, and comes up the same on a second boot. M2.7 used `omamobile-device-akita` 0.1.1 from the signed `[omamobile]` repository's development channel. A second retail 8a passed M2.3, M2.4 and M2.6 as well ([#456](https://github.com/derekross/omarchy-mobile/pull/456)).
- **Kernel:** linux-omarchy-mobile#206 (branch `omamobile-zuma-akita-ufs`), merged. Its builds used the worktree `~/omamobile-kernel/wt-zuma-akita-dts` (reused, so the build stays incremental) and `~/omamobile-kernel/out-zuma-akita-dts`.
- **This repository:** branch `device-akita-m2` (M2.1-M2.6), then `device-akita-m27` (M2.7's results).

## Goal

Stage 2 of CONTRIBUTING §5.4 ("Arch boots from UFS"), on husky's path ([UFS-PLAN](../husky/UFS-PLAN.md), U1-U4):

1. **UFS behind the guard (gate c).** The UFS driver brings up the 8a's storage behind the read-only storage guard. The init's probe report lists every LUN and partition by name, and only `UFS_RW` is writable: slot B's five boot images and `userdata`.
2. **A fresh read-only backup, taken from our own kernel.**
   - Stock Android kept running for about 43 hours after the clean stage-0 backup, and stock's modem stack writes `efs`, `persist` and `modem_userdata`.
   - Magisk's root left with slot B's `init_boot` at M1.3, so stock can't take the backup any more.
3. **Arch on `userdata`.** First from a test root image (gate d), then Omarchy's root image from the signed repository (gate e).

Slot A stays stock throughout. Only `*_b` boot images and `userdata` are written. `userdata` is written only in M2.6 and M2.7, by `tools/install-phone`, after the human's go.

## What akita inherits from husky's stage 2

husky's UFS work is merged, and all of it belongs to zuma, not to husky's board ([UFS-PLAN](../husky/UFS-PLAN.md), Design):

- The host and PHY bind Tensor G4's driver data through the fallback compatibles (`google,zuma-ufs` → `google,zumapro-ufs`; linux-omarchy-mobile#51).
- The zuma pin controllers, with the HSI2UFS and PERIC0 banks (#50).
- `zuma.dtsi`'s `ufs_0` and `ufs_0_phy`, disabled until a board enables them (#53). They come with:
  - the reset and reference-clock pin groups;
  - the UFS sysreg (IOCC at 0x710);
  - the PMU isolation;
  - `fixed-clock` stand-ins at stock's rates.

So akita's kernel change is only the board's part: husky's three nodes (Design 1).

## Path abbreviations

As in [BRINGUP-M1](BRINGUP-M1.md): `R/` is the private stock capture, `L/` our kernel tree. `H/` is husky's [UFS-PLAN](../husky/UFS-PLAN.md).

## Facts

| What | akita | As husky's | Evidence |
| --- | --- | --- | --- |
| Host | `ufs@13200000`, SPI 466, the six regions at husky's addresses, `dma-coherent` | yes | R/live.dts [V] |
| CAL board | `brd-for-cal = 1` | yes | R/live.dts [V] |
| Link | HS-G4 on 2 lanes (`ufs,pmd-attr-gear` 4, `ufs,pmd-attr-lane` 2). `fastboot getvar` reads `storage-power-mode: lanes=2 gear=4 mode=FAST hs_series=SERIES_B` | yes. husky's UFS 4.0 part also links at HS-G4 on 2 lanes | R/live.dts, `getvar` [V] |
| Device | Samsung `KLUDG4UHGC-B0E1`, 128 GB, UFS 3.1, rev 3203 | no: husky's is UFS 4.0 | `getvar` (stage 0) [V] |
| Pins | `gph5-1` (reset) and `gph5-0` (reference clock, drive 2), function 2 | yes | R/live.dts [V] |
| VCC | `regulator-fixed` "ufs-vcc" on `gpp0-1`, active high | yes | R/live.dts [V] |
| Sysreg, isolation | `google,zuma-sysreg-ufs` at 0x13020000 (IOCC 0x710, mask 0x3); PMU 0x3ec0, mask 0x1 | yes | R/live.dts [V] |
| Partitions | 62 on four LUNs: `sda` 34, `sdb` 12, `sdc` 12, `sdd` 4. `userdata` is `sda34`, and `boot_b` to `dtbo_b` are `sda23`-`sda27` | yes for the count and the shape (husky: 62, `userdata` on `sda34`) | R/partitions-by-name.txt [V] |
| UniPro clock, CAL variant | stock's `mclk` and `evt` lines had already rotated out of R/'s kernel log | 178 MHz and the `evt0` tables, as on husky | [I] until M2.3's log |

## Design

1. **Kernel: one commit on `omamobile-zuma-akita-ufs`, on `omamobile`.** It adds husky's nodes, which match akita's live tree:
   - `ufs_0_fixed_vcc_reg` on `gpp0-1`;
   - `vcc-supply` and `status = "okay"` on `ufs_0`;
   - `ufs_0_phy` switched on.

   No new binding or driver code. The nodes are enabled in the board file itself, under CONTRIBUTING §6.2's exception: a node whose pins, flags and driver are proven on another phone with the same SoC "may be added enabled in one commit, once it has passed on your phone". These are husky's. So the commit comes after M2.3, and the overlay below adds only the probe's `bootargs`.
2. **The first UFS boot is read-only and stays in the initramfs.** A bring-up overlay, `device/akita/overlays/ufs-probe.dtso`, sets the board's `bootargs` plus `omamobile.ufs-probe omamobile.initramfs`. That gives the probe listing and no hand-over to Arch, so nothing runs on `userdata`. `DTB_OVERLAYS="ufs-probe"` goes in `device.conf` for that build only, and comes out again afterwards.
3. **Nothing writes before the guard.** UFS is built in, so the disks appear before PID 1. In M2.3 they attached at 0.26 s, and `/init` started at 0.28 s. The init's first job is the guard, which flagged every partition by 0.61 s and removed `/dev/sda`. In between, the kernel only reads the partition tables, and nothing is mounted. `UFS_RW` is unchanged since stage 0.
4. **The fresh backup comes from our kernel.**
   - `NV_PARTS="efs efs_backup modem_userdata persist modem_a modem_b"` (cheetah's) and `NV_BACKUP_EXTRA="devinfo trusty_persist trusty_userdata"` (husky's since #449) go in the descriptor. M2.4 ran with `devinfo` alone; Trusty's two partitions joined after #456's review. Then `tools/nv-backup -d akita` copies the radio and calibration partitions read-only over SSH. Its `--check` can later show that nothing on Linux changed them, and report when Android has written the extras.
   - The rest of the stage-0 set is copied the same way, with each partition hashed on the phone and on the laptop.
5. **The device package comes first, in its own PR.** `omamobile-device-akita` starts with husky's generic first set:
   - the storage rule;
   - the USB gadget network;
   - NetworkManager's drop-in;
   - the power key;
   - the mirror list and its install hook;
   - `reboot-to`;
   - the descriptor.

   The display start, the GPU clock, the USB rescue and the MAX77759 blacklist come later, each with the stage it belongs to.

## Runbook

Ask the human before every flash and reboot (AGENTS.md §1).

**Slot B's retries.** Nothing marks slot B successful, so ABL counts every boot of B, clean ones too. Our first M1 boot left 2 of 3 (BRINGUP-M1 test 3), as husky's test K did.
- `bin/omamobile flash` and `tools/install-phone` both end with `--set-active=b`, so each one starts again at three.
- Before a third reboot without a flash: `reboot-to bootloader`, then `fastboot -s <serial> --set-active=b` and `fastboot -s <serial> reboot`.

**If stock boots from slot A:**
- Once Arch is on `userdata`, stock can't read it, and recovery is expected to offer a factory reset [I]. **Decline it:** it erases `userdata`, which is the install. Volume Down + Power reaches fastboot.
- Then take a fresh read-only backup (M2.4) before any radio, PMIC, AoC or Trusty work, because a stock boot rewrites `efs`, `persist` and `modem_userdata`.

### M2.1 Port (laptop only)

- **What:**
  - Design 1's kernel commit;
  - the `ufs-probe` overlay;
  - `NV_PARTS` and `NV_BACKUP_EXTRA` in the descriptor.
- **Pass:**
  - `W=1`, `dtbs_check` and `checkpatch --strict` show nothing new (the two eUSB2 supply warnings only);
  - the overlaid DTB's `bootargs` end in `omamobile.ufs-probe omamobile.initramfs`;
  - `tools/nv-backup -d akita --list` names the seven partitions.
- **Risk:** none.

### M2.2 Before the flash (laptop, and a read-only look at the phone)

1. The phone runs the M1.4 images from slot B (`reboot-to bootloader` reaches fastboot, BRINGUP-M1 test 3), or it is already in fastboot.
2. The `fastboot getvar` values of BRINGUP-M1's M1.2 step 4, plus `slot-retry-count:b`.
3. The laptop's side, as in M1.2 steps 2 and 3: the `omamobile-phone` profile and the SSH key in the agent.

- **Risk:** none (one reboot to fastboot).

### M2.3 First UFS boot, read only (gate c)

Build M2.1's kernel as in M1.1, with `DTB_OVERLAYS="ufs-probe"` in `device.conf` for this build only. Then `bin/omamobile flash`.

- **Expect:**
  - USB and SSH as in M1;
  - `dmesg` shows the link up at HS-G4 on 2 lanes, series B [I: husky's `Power mode changed to : FAST series_B G_4 L_2`];
  - `/run/ufs-probe.txt` lists `sda`-`sdd` with every partition by name, all `ro=1` except `UFS_RW`;
  - there's no `/dev/sda`.
- **Pass:** the listing matches R/partitions-by-name.txt by name and device node (62 partitions; `userdata` on `sda34`, slot B's images on `sda23`-`sda27`), and the guard's log shows each partition handled.
- **Stop if:**
  - the link doesn't come up: keep `dmesg`, then `reboot-to bootloader`;
  - any partition outside `UFS_RW` is writable: `reboot-to bootloader` at once, report it, and change nothing else.
- **Rollback:** `fastboot -s <serial> --set-active=a`, or flash the M1.4 known-good set. Nothing on UFS is written.
- **Risk:** medium, as husky's U2. A wrong table can fail the link (no harm) or hang the bus (a panic, then a reset). husky's first two tries failed for lack of the pins and VCC; akita has both from its first boot.

### M2.4 A fresh read-only backup (in M2.3's boot)

1. `tools/nv-backup -d akita ~/android/reference/akita-nv-<date>`. The output holds the IMEI, so it stays private.
2. The rest of the stage-0 set, copied over SSH: the 63 images of `akita-backup-clean-20261102`, which are every partition except `userdata` and `super`, plus the whole `sdb`, `sdc` and `sdd` LUNs. Each is hashed on the phone before and after its copy and on the laptop, then compared with `akita-backup-clean-20261102`. Then make the second, offline copy (CONTRIBUTING §3.3).

- **Expect:**
  - the bootloaders, `mfg_data`, `pinfo`, `fips`, `blenv` and `modem_a`/`modem_b` match the clean backup;
  - `efs`, `efs_backup`, `persist`, `modem_userdata`, `devinfo`, `misc`, `metadata` and others may differ. Stock ran for about 43 hours after the clean backup, and our flashes changed the slot flags.
- **Pass:** every copy's hashes agree on the phone and the laptop. The differences from the clean backup are named in Results.
- **Risk:** none: reads only, with the guard on.

### M2.5 The device package (laptop only; its own PR)

- **What:** `packages/omamobile-device-akita` (Design 5), and `device/akita/build-u3-root`, akita's copy of husky's test-root builder.
- **Pass:** the package's `test/all`, `tests/all` and `tools/pr-check`.
- **Risk:** none.

### M2.6 Arch root on `userdata`, test image (gate d)

M2.3's kernel without the overlay, so the init hands over to Arch:

```
KERNEL_OUT=<M2.3's build> bin/omamobile modules
device/akita/build-u3-root <M2.3's build>
KERNEL_OUT=<M2.3's build> tools/install-phone --device akita \
  --rootfs out/akita/u3-root/omamobile-rootfs-u3-akita-aarch64.img.zst \
  --bootloader-slots-match akita-17.0-15681527 --reinstall --dry-run
```

`--reinstall` is needed because after M2.3 the phone runs from slot B. `install-phone` refuses that unless the owner states that slot B holds Omarchy Mobile (our boot images) rather than stock Android after a system update.

Then run the same `install-phone` without `--dry-run`. It needs the human's go, because it erases `userdata`. That partition holds only stock's empty data since stage 0's wipe; no account was ever signed in.

- **Expect:** `install-phone`'s checks pass. It writes slot B's five images and `userdata`, sets B active and reboots. The init finds `omamobile-root`, grows it to the whole partition (109.7 GiB, `partition-size:userdata` 0x1b6a215000), switches to Arch, and systemd reaches `running`.
- **Pass:**
  - ssh as root with the installed key;
  - `systemctl --failed` is empty;
  - the guard's flags hold under Arch: only `UFS_RW` writable, `sdb`-`sdd` `ro`, no `/dev/sda`;
  - `reboot-to bootloader` reaches fastboot;
  - a second boot comes up the same.
- **Stop if:**
  - there's no ssh after 2 minutes;
  - any partition outside `UFS_RW` is writable: `reboot-to bootloader` at once.
- **Rollback:**
  - flash M2.3's images with the overlay to stay in the initramfs;
  - or `fastboot -s <serial> --set-active=a`, after which stock needs a factory reset, since its `userdata` is gone.
- **Risk:** low for the hardware, since the kernel is M2.3's. `userdata` is erased by design. Mind slot B's retries (above).

### M2.7 Omarchy's root image (gate e)

As husky's U4:
1. Build a fresh kernel from `omamobile`, with M2.1 merged, and tag it before it's flashed.
2. Fill `out/repo/aarch64` from the signed repository's development channel, checking each signature.
3. Run `DEVICE=akita tools/build-rootfs`, then `tools/install-phone --device akita --bootloader-slots-match akita-17.0-15681527 --reinstall` (slot B runs Omarchy Mobile since M2.6), with `--dry-run` first.

The install needs the human's go, since it erases `userdata` again.

- **Needs:** `omamobile-device-akita` in the signed `[omamobile]` repository. Only the maintainer can publish it (0.1.1 was, in the development channel).
- **Pass:**
  - the user logs in over ssh;
  - `systemctl --failed` is empty from the second boot on (`systemd-firstboot` fails once on the first, as on lynx and panther: below);
  - the guard's flags hold;
  - `reboot-to bootloader` works;
  - `tools/phone-smoke`'s report goes to the pull request, naming what doesn't apply yet (no GPU or touch driver).
- **Watch for:**
  - **The clock.** With no RTC driver and no network time, the clock starts early, and gpg can skip a new release key as "created in the future" (husky's U4 finding). Set it from the laptop over ssh before `pacman-key --populate`.
  - **Suspend.** Don't use it in M2.7. The package's drop-in makes Suspend mean s2idle, and that has never run on Tensor G3. It waits for the Pixel 8 Pro's U6, so the session test doesn't turn into a suspend test.
  - **The screen.** The lock blanks the display after 10 s without input, and nothing on the phone can wake it yet: there is no touch driver, and the power key isn't an input device. Wake it over SSH as the user with `omarchy-shell lock wake`.
- **Risk:** low for the hardware. The trap is the fallback to stock after three boots (above).

## Risks

- **`userdata` is erased by design in M2.6 and M2.7.** It holds stock's empty data since stage 0's wipe. Stock on slot A then needs a factory reset to boot, which is why it must be declined while Arch lives there.
- **A UFS 3.1 part where husky's is 4.0.** The host and PHY tables are the SoC's. The link runs at husky's gear and lanes, as stock's does on this phone. The core writes device state at probe: `fDeviceInit` and the exception-event mask, plus the RTC attribute on UFS 4.0 parts only. None of that is partition data.
- **Inline encryption.** Stock's `userdata` is encrypted with wrapped keys, and nothing in M2.3 or M2.4 reads or writes it.
- **Not in M2:** hibern8 and system suspend (husky's U5 and U6, untested on Tensor G3 and G4), the buttons (stage 3), and the panel size the session needs (the review of #414).

## Open questions

- B0 or B1 silicon (still; see BRINGUP-M1).
- Plymouth under Arch. `splash` reaches the kernel on this phone (BRINGUP-M1, M1.4). Does a plain `plymouth quit` on simpledrm need husky's retain-splash drop-in?
- ~~Stock's UniPro clock and CAL variant, from M2.3's log rather than stock's.~~ The mainline driver doesn't print them, and the link came up at stock's mode with the stand-in rates (M2.3).

## Results

### 2026-11-06: the port (M2.1, laptop only)

- **The kernel change:** `zuma-akita.dts` gains `<dt-bindings/gpio/gpio.h>`, `ufs_0_fixed_vcc_reg` (`regulator-fixed` "ufs-vcc" on `gpp0` 1, `GPIO_ACTIVE_HIGH`), `&ufs_0` with `vcc-supply` and `status = "okay"`, and `&ufs_0_phy` switched on, with husky's two comments. It is 25 lines, and is now linux-omarchy-mobile#206, merged as `75b9c0b73` (DTS blob `bfa8b6f54e0e`).
- **Checks** [V]:
  - `W=1` adds no warning;
  - `dtbs_check` reports only the two eUSB2-PHY supply warnings, the same two husky's DTB has on this tree, so the UFS nodes validate against zuma's merged bindings;
  - `checkpatch --strict` finds 0 errors, 0 warnings and 0 checks.
- **The built DTB** [V]: `/soc@0/ufs@13200000` is `okay` with its `vcc-supply` on `/regulator-ufs-vcc` (`gpio = <&gpp0 1 0>`), and its PHY is `okay`. That is husky's DTB node for node, only the phandles differ.
- **The overlay** [V]: `ufs-probe.dtso` compiles with `dtc -@` and applies onto that DTB with `fdtoverlay`. The overlaid `bootargs` are exactly the board's plus ` omamobile.ufs-probe omamobile.initramfs`, and the framebuffer and UFS nodes are unchanged.
- **The descriptor** [V]:
  - `tools/nv-backup -d akita --list` checks `efs efs_backup modem_userdata persist modem_a modem_b` and copies `devinfo`;
  - `DEVICE=akita bin/omamobile initramfs-config` still packs the same four files;
  - `tests/device-overlays` and `tests/nv-backup` pass, and `tests/all` gives 418 ok, 0 not ok.

### 2026-11-06: first UFS boot, read only (M2.3)

The kernel was `7.3.0-rc6-omamobile-push1-g29a7a9326bf0-dirty`: `omamobile` at `29a7a9326` plus M2.1's uncommitted UFS change, with the `ufs-probe` overlay on the DTB. The incremental build took 11 minutes. All writes went to `*_b` only, through `bin/omamobile flash`. Tests 1-5 are BRINGUP-M1's.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 6 | `bin/omamobile fastboot` from the M1.4 kernel, after 58.8 h of uptime | `reboot-to bootloader` reached fastboot in 26 s. `getvar`: slot B `slot-successful:no` with 2 tries, slot A `yes` with 2, anti-rollback counters 3 | M1.4's kernel ran for 2.5 days on the cable without a hang |
| 7 | `bin/omamobile flash` with the M2.3 images | Five `OKAY`s; SSH at 4.96 s. `Power mode changed to : FAST series_B G_4 L_2` at 0.24 s. The device reads `SAMSUNG KLUDG4UHGC-B0E1` rev 3203, `sda` is 128 GB, and there are LUNs 0-3 plus three W-LUNs. No UFS error, reset or I/O error | The link runs at stock's gear, lanes and rate series |
| 8 | The guard, from SSH and the init's log | 4 disks and 62 partitions, every name on stock's node (R/partitions-by-name.txt): none moved, missing or extra. Exactly `UFS_RW` is writable (`sda23`-`sda27`, `sda34`); `sdb`-`sdd` are `ro`; `/dev/sda` is removed. The guard set 56 partitions read-only and left the 6 on the allowlist | **Gate (c) passed** |
| 9 | A 64 MiB direct read of `boot_b` | 1.5 GB/s | Data moves on the link. husky's UFS 4.0 part read 1.8 GB/s |

Findings:

- **The disks come before PID 1.** That is the reverse of what this plan first assumed (Design 3), but nothing writes in between.
- **`ufshcd_populate_vreg` finds no `vdd-hba`, `vccq` or `vccq2` supply**, and assumes each is on, as on husky (H/ NOTES).
- **The stand-in clock rates work.** The mainline driver prints neither the UniPro clock nor the CAL variant, but the link came up at stock's mode with `zuma.dtsi`'s rates.
- The logs are private (`~/android/reference/akita-m2-ufs-20261106/`). The images are kept as `~/omamobile-kernel/known-good/akita-m2.3-g29a7a9326bf0-dirty`, with their DTS and overlay.

### 2026-11-06: a fresh read-only backup from our kernel (M2.4)

This was in M2.3's boot, with the guard on and nothing mounted. M2.3's kernel change is linux-omarchy-mobile#206: its `zuma-akita.dts` is blob `bfa8b6f54e0e`, the DTS that booted.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 10 | `tools/nv-backup -d akita` | 7 partitions copied and each verified against a second read on the phone. 5 min 40 s for 721 MB: one SSH connection timed out, and 4 chunks of `modem_b` were read again. The laptop logged no USB event, and a 100 MB stream afterwards ran at 36 MB/s | A verified radio backup. The link stalls now and then under many short connections, and the tool's retries absorb that |
| 11 | All 63 stage-0 items hashed on the phone (18 s) and compared with the clean backup of 2026-11-02 | 47 are unchanged. 11 changed: `efs`, `efs_backup`, `persist`, `modem_userdata`, `metadata` and `trusty_persist` (stock Android, which ran for about 43 h after that backup); `devinfo`, `dram_train_b` and `klog` (the bootloader's slot flags, memory training and log); and the `sdd` and `sdc` LUNs, which hold `devinfo` and `dram_train_b`. The other 5 are slot B's boot images, ours since M1.3 | Nothing changed that stock or the bootloader doesn't write. Our kernels couldn't write: M1's had no UFS, and M2.3's runs behind the guard |
| 12 | The full set, with a private helper on the laptop (`akita-backup-linux`): unchanged items come from the clean backup, the radio items from test 10, and the rest are read in 8 MiB chunks; every file is checked against the phone's hash, and the phone is hashed again afterwards | 58 items, 1.4 GB, all verified, and the phone's hashes the same before and after. Afterwards: no UFS error, and the guard's flags unchanged | **The fresh backup.** M2.6's writes and any later check compare against it. Both new backups have an offline copy |

The UFS change went out as linux-omarchy-mobile#206, signed off by the owner, and merged as `75b9c0b73`. `tools/kernel-pr-check --build OUT --merge origin/omamobile` passed on it:
- a clean merge;
- the sign-off;
- `checkpatch --strict` with 0 errors and 0 warnings;
- the 10 Google device trees with `W=1` and `dtbs_check`, no new warnings.

### 2026-11-06: the device package (M2.5, laptop only)

- **`packages/omamobile-device-akita` 0.1.0** is the generic set of the Pixel 8 Pro's first package (#42):
  - the storage rule, the USB gadget network and NetworkManager's drop-in;
  - the power key;
  - the mirror list and its pacman hook;
  - `reboot-to`;
  - the descriptor.

  `reboot-to.c`, the storage rule, the mirror list, the hook and the power key are byte-identical to cheetah's, and the two network files to husky's. Its `test/all` checks all of that. `install` stages nine files, none of which marks a slot or starts the radio, the charger or a camera.

  After review it also carries the suspend-to-idle drop-in (M2.6's `mem_sleep` finding). The drop-in's comment names zuma, and its settings are cheetah's, which the test checks. That makes ten files and 16 checks.
- **`device/akita/build-u3-root`** is husky's test-root builder with akita's names; only names differ.
- **Checks:** `tests/all` gives 418 ok, 0 not ok. `tests/packages` passes, the new package included, on a quiet CPU; five other packages' timing tests failed while a kernel build shared it.

### 2026-11-06: Arch on `userdata`, test image (M2.6, gate d)

- **Kernel:** `7.3.0-rc6-omamobile-push1-g31d8b229d0d0`: linux-omarchy-mobile#206's head before it merged (`31d8b229d`), built clean with no overlay. Its DTS is blob `bfa8b6f54e0e`, as merged in `75b9c0b73`.
- **The test root:** built by `device/akita/build-u3-root` from the Arch Linux ARM base (sha256 `42a4eeaa…`), `omamobile-device-akita` 0.1.0 and this kernel's modules. Its MANIFEST names repository commit `93de3d963c6d`.
- **The install:** `tools/install-phone --device akita --rootfs … --bootloader-slots-match akita-17.0-15681527 --reinstall`, run by the owner after a dry run.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 13 | `tools/install-phone --dry-run` | All checks pass: fastboot, product, unlocked, both slots, image sizes, and slot B acknowledged as ours. It prints the five `*_b` flashes, then `userdata`, `--set-active=b` and `reboot`. Nothing is written | The installer's plan is exactly the runbook's |
| 14 | `tools/install-phone` | The init grows the root on `sda34` from 3411 MiB to 112290 MiB and switches to Arch. Root's SSH works with the installed key. `systemctl is-system-running` reads `running`, with no failed units and 27 running. `usb0` is 172.16.42.1/24 under `systemd-networkd`, and the device package is in place | **Arch runs from `userdata`** |
| 15 | The guard under Arch | 62 partitions, exactly `UFS_RW` writable; `sdb`-`sdd` `ro`; no `/dev/sda`. Only `sda34` is mounted (ext4, 107.9 G). The kernel log has no UFS or ext4 error | The guard's flags hold after `switch_root` |
| 16 | `bin/omamobile fastboot` from Arch, 282 s into the first boot | `reboot-to bootloader` reached fastboot in 25 s. `getvar`: slot B `slot-successful:no` with 2 tries, slot A unchanged | The reboot mode works from Arch too. `reboot-to` syncs before it resets |
| 17 | `fastboot --set-active=b` (B back to 3 tries), then `fastboot reboot` | SSH at 28 s, with systemd `running` 9 s into boot. `systemd-analyze`: 2.0 s kernel and initramfs plus 2.2 s userspace. As before: no failed units, 27 running, the guard's flags, `usb0`, the same four journal lines. ext4 mounted cleanly with no journal replay, and the root wasn't grown again | **Gate (d) passed:** a second boot comes up the same |
| 18 | `tools/phone-smoke` from the laptop, 42 h into that boot (2026-11-08; the report's own date is the phone's clock, July) | Required rows: boot, storage guard (62 partitions, only `UFS_RW` writable), root (ext4 on `userdata`), kernel health (no oops or BUG, 0 WARN), systemd units, USB gadget, all ok; session not ok. Evidence: the display ok (1080x2400 on simpledrm); GPU, lock and touch not ok; buttons, radios, battery, sound, sensors and cameras skip. Its "new dmesg errors" are the two `exynos-clkout` lines, which husky's log has too (H/), but which the tool's known list (the 7 Pro's) doesn't name | As expected for the test root: everything below the session works, and the session rows wait for M2.7's image |

Findings:

- **The journal's four error lines are all harmless.** They are `exynos-clkout` (-22, as on husky), `unable to open an initial console` (ABL's `console=null`), and `systemd-gpt-auto-generator` exiting with 1 (there's no EFI root to discover). None needs a change.
- **The clock starts at systemd's built-in floor (Jul 24).** There is no RTC driver and no network time yet. Set it from the laptop before M2.7's `pacman-key --populate`, as husky's U4 found.
- **The kernel's default sleep is `deep`.** `/sys/power/mem_sleep` reads `s2idle [deep]` under Arch, and Linux has no zuma SoC sleep sequence to wake from it. `omamobile-device-akita` now carries the suspend-to-idle drop-in, with the Pixel 7 Pro's settings (`MemorySleepMode=s2idle`), so Omarchy's Suspend won't enter `deep`. The test image on the phone predates it. Suspend itself is still untested on Tensor G3 (husky's U6).
- **The test image had no module indexes.** There was no `modules.dep`, so `modprobe` found nothing. The kernel build installs its modules without depmod, and the image runs no pacman, whose kmod hook would make them. A second tester found this on #456, and this phone showed the same. Nothing at boot needs a module, which is why Arch still came up clean. `build-u3-root` now installs `kmod`, runs `depmod` for the slot B kernel's release, and fails the build if no `modules.dep` results. The rebuilt image has the full index set (`modules.dep` lists all 1820 modules) and the suspend drop-in.
- The logs are private (`~/android/reference/akita-m2-arch-20261106/`). The images and modules are kept as `~/omamobile-kernel/known-good/akita-m2.6-g31d8b229d0d0`.

### 2026-11-10: Omarchy's image (M2.7, gate e)

- **Kernel:** `7.3.0-rc6-omamobile-push1-gabcd6aac51cf`, built clean from `omamobile` at `abcd6aac5` (#206 and #214 merged), with no overlay.
- **The image:** `DEVICE=akita tools/build-rootfs --channel development` made `omamobile-rootfs-akita-2026.11.09-aarch64`. Its MANIFEST names repository commit `43facd88b986`: `main` at `b5207b8` plus one commit that changes only `tools/phone-smoke` and its test, so nothing in the image. It also names the Arch Linux ARM base `42a4eeaa…`, this kernel's modules and `omamobile-device-akita` 0.1.1-1 from the signed development channel. It took 96 min on the laptop, under emulation.
- **The install:** `tools/install-phone --device akita --bootloader-slots-match akita-17.0-15681527 --reinstall`, run by the owner after a dry run.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 19 | `tools/build-rootfs` | Exit 0. Its own checks pass: no per-machine state, no Google firmware or per-phone data, no old project name. Omarchy's list: 146 packages, none missing for aarch64, 2 skipped by design. All 20 `[omamobile]` packages are in. The checksum and `zstd -t` pass | The image is the one the runbook asks for |
| 20 | `tools/install-phone --dry-run`, then the install | The dry run printed the five `*_b` flashes, then `userdata`, `--set-active=b` and `reboot`, and wrote nothing. The install did the same. The USB link was up 5 s after the reboot | The installer's plan is exactly the runbook's |
| 21 | First boot | `omamobile-firstboot` succeeds after 2 min 59 s. Userspace takes 3 min 3 s on this boot, all but a few seconds of it first-boot setup. The release key `2056 7593 566E EEE2 DD88 6460 8632 C807 5EB9 4673` is in pacman's keyring with full trust. The clock read Oct 26 and was set from the laptop afterwards | First-boot setup completes on akita |
| 22 | Logins | Root and the user log in over SSH with the installed key. `usb0` is 172.16.42.1/24 | **The user logs in over SSH** |
| 23 | The guard under Omarchy | 62 partitions, exactly `UFS_RW` writable (`boot_b` … `dtbo_b`, `userdata`); `sdb`-`sdd` `ro`; no `/dev/sda`. `/` is `sda34`, ext4, 107.8 G | The guard's flags hold under the full image |
| 24 | `tools/phone-smoke` | Required rows all ok: boot (slot B), storage guard, root, kernel health (no oops or BUG, 0 WARN), USB gadget, **session (Hyprland and the Omarchy shell)**. The display is ok at 1080x2400, and the lock is ok (PAM present, the shell can lock). Not ok: GPU (no render node) and touch (no driver), as expected; `systemd units` (`systemd-firstboot`, below). Skip: buttons, Wi-Fi, Bluetooth, battery, sound, sensors, cameras. Its new dmesg lines are the two `exynos-clkout` lines and the preset line (below) | **The session runs on akita** |
| 25 | `bin/omamobile fastboot` from Omarchy | `reboot-to bootloader` reached fastboot in 27 s. `getvar`: slot B `slot-successful:no` with 2 tries, slot A unchanged | **`reboot-to bootloader` works from Omarchy** |
| 26 | `fastboot --set-active=b` (B back to 3 tries), then `fastboot reboot` | Ping and SSH at 25-26 s. `systemd-analyze`: 2.0 s kernel and initramfs plus 3.2 s userspace. `systemctl is-system-running` reads `running`, with no failed units and 45 running. The guard's flags and `usb0` as before. ext4 mounted cleanly. The clock came up at the last shutdown's time. `tools/phone-smoke` (at `main`'s `a51ef02`): required rows ok, `systemd units` ok, 4 error lines: 2 known, and the 2 `exynos-clkout` lines as new | **Gate (e) passed:** a second boot comes up the same, and clean |

Findings:

- **`systemd-firstboot.service` fails on the first boot only** (status 208/STDIN). With ABL's `console=null` it has no console. `omamobile-firstboot` already sets the host name, time zone and locale. lynx's NOTES and panther's BRINGUP-M1 record the same. It doesn't run again, so `systemctl --failed` is empty from the second boot on (test 26).
- **One new journal line:** `Failed to preset all unit: Unit /etc/systemd/system/systemd-networkd-wait-online.service is masked`. It came once in first boot's preset, for a unit the image masks on purpose. It isn't recorded for other phones yet, and is harmless here.
- **The two `exynos-clkout` lines stay "new" on purpose.** The driver had no `google,zuma-pmu` entry in this kernel. linux-omarchy-mobile#209 adds it (merged 2026-11-10, after this kernel was built), so akita's next kernel should stop printing them. `phone-smoke`'s known list is shared by every phone, and on the Pixel 7 Pro and the 9a the same lines mean NFC's clock is missing, so they aren't listed there (#584, closed).
- **The other error lines are known:** `unable to open an initial console`, `systemd-gpt-auto-generator` exiting with 1, and `gkr-pam: couldn't unlock the login keyring` (auto-login).
- **The lock screen blanks the display after 10 s without input,** whatever `omarchy-toggle-idle` says. That's the lock's own timer, by design. With no touch or key input yet, the screen can only be woken over SSH (`omarchy-shell lock wake`, run as the user). The power key isn't an input device yet: a short press does nothing, and a long press is the PMIC reset.
- **The USB link didn't come back after the host lost power.** The laptop crashed and restarted while the phone ran the M2.6 root. After that, the phone never appeared on USB again, even on a replug, while the display stayed up. Volume Down + Power reached fastboot, which enumerated at once on the same cable and port. This is probably the same as on the Pixel 7 Pro and the 9a, not checked on akita: there the charger IC opens the USB2 data switch when VBUS drops, and with no Type-C driver yet nothing closes it again. A laptop losing power looks like an unplug to the phone. Until that's fixed, the way back is the button combination.
- **The clock:** first boot read Oct 26 (not today, but not before the release key's creation date, 2026-10-26), so the keyring imported the release key with full trust, and no gpg line says "created in the future". The clock was set from the laptop over SSH afterwards. From then on it survives a reboot: systemd stores the time at shutdown (`/var/lib/systemd/timesync/clock`), so the second boot came up at the last shutdown's time, behind only by the time the phone was off.
- **`/sys/power/mem_sleep` still reads `s2idle [deep]`** (the kernel's default). The package's drop-in (`MemorySleepMode=s2idle`) applies when systemd suspends. Suspend wasn't tried, and the auto-sleep toggle (`omamobile-sleep`) is off.
- The logs are private (`~/android/reference/akita-m2.7-omarchy-20261110/`). The images, modules and root image are kept as `~/omamobile-kernel/known-good/akita-m2.7-gabcd6aac51cf`.
- **Slot B ended the session with 2 tries**: test 26's `--set-active=b`, then that one boot.
