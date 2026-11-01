<!-- SPDX-License-Identifier: MIT -->
# Pixel Fold cover touch: reports

Status, 2026-10-27. The report path is linux-omarchy-mobile#48, merged, head `0e8be406f`. #32 and #41 have merged. omarchy-mobile#82 has merged. The notes keep its 2026-10-27 section above this plan's section. `salixp.c` blob `c1752a85` is the stable name for the step 8 boot. That boot was packed release `7.3.0-rc6-omamobile-push1-gaa42f8a8c1bf`, the same tree as published head `aa42f8a8c` before the rebase. The rebase keeps the blob. Head `0e8be406f` fails probe on config CRC events `0x20` and `0x21` and on a missing scan echo. Step 0 is against Google's felix driver at tag `android-14.0.0_r0.102`.

The power key is linux-omarchy-mobile#41, merged. Touch in `docs/DEVICES.md` is WIP (cover chip id). Buttons is works.

## Goal

Hyprland sees a cover touch. The pass line for this stage is that, plus keys visible to `evtest`. Volume keys already reported a press and a release. The power key is covered by its own change.

In order:

1. Keep the cover controller disabled on a normal boot.
2. Learn the firmware hand-off from Google's felix driver, with file and line citations, before any new code.
3. Only then add a report path, on a new branch, still disabled in the board DTS.
4. One gated slot B boot, with the attention line requested only after that hand-off.

## Sources

- `L/` is linux-omarchy-mobile on `omamobile`, plus the open #32 series.
- `N/` is `device/felix/NOTES.md` and `device/felix/COVER-TOUCH-PLAN.md` (the chip-id gate, omarchy-mobile#34).
- `G/` is Google's felix touch driver, `kernel/devices/google/felix` path `touch/ftm5/`. Public history: <https://android.googlesource.com/kernel/devices/google/felix/+log/refs/tags/android-14.0.0_r0.102/touch/ftm5/fts.c>.
- `F/` is factory image CP3A.261005.002.A1. Its `vendor.img` is an ext4 image whose root is the vendor directory. Factory-image terms: <https://developers.google.com/android/images>.

## Facts

- [V] Cover touch is `st,fts` on `spi_6`, chip select `gpp12-3`, reset `gpp23-3`, attention `gpa6-7`, supplies S2MPG12 LDO25M and LDO26M. Stock firmware name `ftm5_fw_f10_ext.ftb`. `N/` 2026-10-20.
- [V] `F/` `vendor.img` contains `firmware/ftm5_fw_f10_ext.ftb`, 153640 bytes, mode `0644`, SELinux type `vendor_fw_file`. The header signature is `0xAA55AA55` and the chip id in the header is `36 40`. No license file sits beside it. The same directory has `ftm5_fw_p7.ftb`, `ftm5_fw_p7_ext.ftb`, and `stm_fts_production_limits_f10_ext.csv`. `firmware/ftm5_fw_f10.ftb` is not there. Google's factory-image terms allow the files on a personal Pixel and do not allow redistribution, so this blob stays out of the repository.
- [V] A hand-loaded `salixp` module on `7.3.0-rc6-omamobile-push1-gdd05dd347ad0` logged `salixp spi0.0: chip id 36 40`, held each of those two rails with one user, and dropped both on unbind. `N/` and #32.
- [V] Attention is level-low. After reset is released it falls and stays low. #32 describes the line and does not request it. `L/` `salixp.c` says a level interrupt would storm before any firmware handshake.
- [V] The controller answered with no AoC driver loaded. Touch offload stays out of this plan.
- [V] Inner touch is `st,fst2` on `spi_0`. Its rails are S2MPG13 LDO22S and LDO6S. Its reset is `gpp23-2`. None of those are in this plan. `N/` 2026-10-20.
- [V] `G/` tag `android-14.0.0_r0.102`. `fts_crc_check` (`touch/ftm5/fts_lib/ftsCore.c:952`) returns OK when it finds no CRC error, and a value greater than OK when it does. `fts_fw_update` (`touch/ftm5/fts.c:4222`) sets `reflash_fw` in that second case. `flash_burn` (`touch/ftm5/fts_lib/ftsFlash.c:1010`) skips the write when force is clear and the file matches the firmware already running.
- [V] `G/` same tag. When `fts_crc_check` cannot read the CRC register it returns that negative error (`ftsCore.c:968`) and does not reset the controller. The status register is checked before any reset. `fts_system_reset` runs only after that register reads clear (`ftsCore.c:980`). `fts_fw_update` sets `reflash_fw` only when the return is greater than OK (`fts.c:4224`). A negative return takes the other branch, which logs "NO CRC Error or Impossible to read CRC register" and leaves `reflash_fw` clear (`fts.c:4227`).
- [V] `G/` same tag. `flashProcedure` (`touch/ftm5/fts_lib/ftsFlash.c:178`) reads the firmware file and calls `flash_burn` (`touch/ftm5/fts_lib/ftsFlash.c:209` and `:1000`). The programming procedure starts at `touch/ftm5/fts_lib/ftsFlash.c:1045`. Those steps stay in `G/`.
- [V] `G/` same tag. `fts_interrupt_install` (`touch/ftm5/fts.c:4492`) requests the IRQ level-low and then disables it (`touch/ftm5/fts.c:4526`). `fts_init_sensing` (`touch/ftm5/fts.c:4675`) runs that install, turns sensing on, and then calls `fts_enableInterrupt` with enable true (`touch/ftm5/fts.c:4682`). `fts_enableInterrupt` (`touch/ftm5/fts_lib/ftsCore.c:914`) is `enable_irq` or `disable_irq`. `fts_fw_update` reaches `fts_init_sensing` at `touch/ftm5/fts.c:4385`, after the flash path.
- [V] `G/` same tag. `fts_init` (`touch/ftm5/fts.c:4555`) continues when reset fails for a reason other than a bus error. Probe calls `fts_fw_update` directly only when both `FW_UPDATE_ON_PROBE` and `FW_H_FILE` are set (`touch/ftm5/fts.c:5685`). Otherwise it queues `fts_fw_update_auto` (`touch/ftm5/fts.c:4400`).
- [V] `G/` same tag. `senseOn` (`touch/ftm5/fts_lib/ftsTool.c:283`) is `setScanMode` with `SCAN_MODE_ACTIVE` and settings `0xFF` (`ftsCore.c:377`, opcode `FTS_CMD_SCAN_MODE` `0xA0` at `ftsSoftware.h:75`). It does not compare `u16_cxVer`. `fts_init_sensing` (`fts.c:4675`) requests the IRQ, disables it (`fts.c:4492` and `:4526`), then the screen-up path sends that scan command (`fts.c:4855`), and only then enables the IRQ (`fts.c:4682`). A CX CRC error is a different check: `fts_fw_update` calls `fts_system_reset` and polls CX error events (`fts.c:4287`). A hit there is the flash path, which this plan does not transcribe. An AFE mismatch between config, CX, and panel also selects panel init (`fts.c:4348` and `:4364`). Those three bytes follow the CX version in the system-info block (`ftsCore.c:662`).
- [V] `G/` same tag. `readSysInfo` (`touch/ftm5/fts_lib/ftsCore.c:583`) reads the 216-byte system-info block from the framebuffer when `request` is 0. The comment at `ftsCore.c:577` says that block is loaded after every system reset. `request` 1 writes `SYS_CMD_LOAD_DATA` (`ftsCore.c:594`). `fts_init` calls `fts_system_reset` and then `readSysInfo(info, 0)` (`touch/ftm5/fts.c:4563` and `:4574`). On SPI the framebuffer read is opcode `0xA7`, a 16-bit address, and one dummy byte (`ftsHardware.h:210`, `:224`, `:249`). The header byte is `0xA5` and the data id is `0x01`. The firmware version is the little-endian u16 at offset 16 and the CX version is the little-endian u16 at offset 24 (`ftsCore.c:632` through `:656`, `ftsTool.c:129`). That version is not the CX calibration.
- [V] `G/` same tag. A touch report is one FIFO event, `event[0]` through `event[7]`. Enter is `0x13`, motion is `0x23`, leave is `0x33` (`touch/ftm5/fts_lib/ftsSoftware.h:387`). `fts_interrupt_handler` (`touch/ftm5/fts.c:3838`) reads the FIFO and dispatches those three. `fts_enter_pointer_event_handler` (`touch/ftm5/fts.c:2908`) takes the slot from the high nibble of `event[1]`, X and Y from `event[2]` through `event[4]`, and pressure from `event[5]`. At most `TOUCH_ID_MAX` (10) slots (`touch/ftm5/fts.h:186`). The non-offload path reports `BTN_TOUCH`, `ABS_MT_POSITION_X`, `ABS_MT_POSITION_Y`, and `ABS_MT_PRESSURE` (`touch/ftm5/fts.c:3047`). `fts_leave_pointer_event_handler` (`touch/ftm5/fts.c:3076`) clears the slot. The FIFO read command stays in `G/`.
- [I] This tree has no Google touch offload. The report path to add later is the plain `input` calls above.
- [V] `F/` board overlay, `st,fts` `st,max-coords` is `<0x437 0x82b>`. That is 1079 by 2091, the maximum coordinate, one less than the 1080 by 2092 size in the board file. It is not a different panel.
- [V] `G/` same tag. `st,sensor_inverted_x` and `st,sensor_inverted_y` reorder heatmap and self-sense frames for touch offload (`fts.c:2580` and `:2685`). Pointer coordinates are reported raw and only clamped (`fts.c:2948`). Those properties are not `touchscreen-inverted-x` or `touchscreen-inverted-y`.
- [V] `G/` same tag. After the CX poll finds nothing, `fts_fw_update` polls panel CRC types `0x22` and `0x23` (`fts.c:4293` through `:4304`, `ftsSoftware.h:460`). A hit selects panel init. A CX CRC hit selects full panel init under `COMPUTE_INIT_METHOD` (`fts.c:4307` through `:4321`). Felix does not set `st,skip-fpi-for-unset-mpflag` (`fts.c:5379`), so an MP flag other than `0xA5`, `0x5A`, or `0xDF` also selects full panel init, and a config AFE that differs from the panel AFE selects panel init (`fts.c:4330` through `:4361`).
- [V] `G/` same tag. `fts_crc_check` resets after a clear CRC register and polls config CRC types `0x20` and `0x21` before the CX types (`ftsCore.c:957` and `:979` through `:982`, `ftsSoftware.h:456` through `:458`). A hit returns `CRC_CONFIG`. `fts_fw_update` sets `reflash_fw` for any return above OK (`fts.c:4224`). A failed system reset skips initialisation because the state is unknown (`fts.c:4325`). That miss is not the full panel init.
- [V] `G/` same tag. Felix does not set `st,disable-auto-fw-update`, so `auto_fw_update` stays true (`fts.c:5367` through `:5369`). `flash_burn` with force clear still burns when the file's firmware, config, CX AFE, or external release differs from the running controller (`ftsFlash.c:1008` through `:1024`). This driver has no firmware file, so that comparison is not in the stop set. The stop set is not the whole of stock's write decisions.
- [V] `G/` same tag. The cover node's `controller-data` has `cs-clock-delay = <2>` (`dts/gs201-felix-outer-touch.dtsi`), 2 µs from chip select to the first clock. Upstream spells that `spi-cs-setup-delay-ns`. The board file in published head `aa42f8a8c` sets `<2000>`.
- [I] That driver delivers events through Google's touch interface, which this tree does not have. A mainline `input` device is a later revision of this plan.

## Design

Leave #32 and #34 as they are. Reports are a new series after those merge: binding changes only if the report path needs a property, then the driver, then the felix node still `disabled`. An overlay in this repository may enable it for one boot. `regulator-always-on` stays out.

Do not request `gpa6-7` in the same change that only reads the chip id. Do not port `ftm5.c`. Do not add the inner panel, its reset, or S2MPG13.

The firmware file named in the factory node is `F/` `firmware/ftm5_fw_f10_ext.ftb`. Do not vendor that blob. The terms above do not allow shipping it.

The report path never writes or erases the controller's flash, never requests a reflash, and never runs a panel init or a full panel init. It never sends a CX tuning or save command, and it never writes the MP flag. Felix's driver defines `COMPUTE_INIT_METHOD`, so `fts_chip_initialization` can compute new CX and save it and the MP flag into the controller's flash without `flash_burn`. `fts_fw_update` selects that path on its own (`fts.c:4330` through `:4372`) when the AFE versions disagree, and also when the MP flag is not `A5`, `5A`, or `DF`. The firmware and the CX calibration live in that flash. A burn holds the core, unlocks and erases it page by page, and whether the panel-init and CX area survives depends on `keep_cx`. A bad or interrupted burn can lose the cover panel's factory calibration, and this tree has no way to restore it. A flash write is a separate decision, taken together. The published report path sends four SPI things: opcode `0xfb`, opcode `0xa7`, opcode `0x87`, and scan command `0xa0 0x00 0xff`. It toggles the reset GPIO once. It does not send opcode `0xfa` or a load command, and it does not request the interrupt. Probe fails, and does not scan or register an input device, when the CRC status is non-zero, the system-info header is not `a5 01`, controller-ready does not arrive, a config CRC event (`0x20` or `0x21`), a CX or panel CRC event arrives, the scan echo does not arrive, or the AFE bytes or MP flag are a combination stock would panel-init. The 2026-10-24 hand-load did not do that: `salixp_poll_cx()` returned 0 on a hit and the probe continued. The CX, panel, header, CRC-status, and AFE stops are in `b2a37752b`, an ancestor of the step 8 boot. The config CRC stop and the missing-echo stop are in that boot, `salixp.c` blob `c1752a85`. No controller-ready is not the full panel init. Stock skips init because the state is unknown. A missing echo fails probe after one scan command. It does not send a second one.

## What was built

The report path is linux-omarchy-mobile#48. Step 8 booted it as a packed image. The chip-id reader and its overlay are the earlier pull requests.

| Piece | Where | State |
| --- | --- | --- |
| Chip-id reader, node disabled | linux-omarchy-mobile#32 | merged |
| Chip-id plan, notes, blacklist | omarchy-mobile#34 | merged |
| Report path | linux-omarchy-mobile#48, head `0e8be406f` | merged |
| Probe stop before a stock repair | `salixp.c` blob `c1752a85`, step 8 release `7.3.0-rc6-omamobile-push1-gaa42f8a8c1bf` | booted, slot B not marked successful |

## Risks

Requesting attention while it sits low storms the interrupt line. A guessed flash program can leave the cover controller without firmware. Enabling the main PMIC to reach LDO25M and LDO26M is the same risk as the chip-id gate: other rails register, and an Android slot A boot would rewrite the calibration partitions.

Slot A was rewritten on purpose to another Omarchy Mobile test build. The date, the tool, which of `boot_a`, `init_boot_a`, `vendor_boot_a`, `vendor_kernel_boot_a` and `dtbo_a` were written, and whether `vbmeta` was touched, are not recorded. `super`'s slot A has not been read. On 2026-10-22 slot A was GrapheneOS, and the later rewrite does not say it touched `super`. Neither slot holds Android, so there is no fallback. The way back is fastboot from the buttons and step 8a, agreed in this review on 2026-10-27. The 2026-10-27 copy is not a baseline. It is the current contents, and the cause of the change is unknown. The 2026-10-16 set stays beside it. The baseline for any later PMIC step is the backup taken after the return to slot B from stock's first boot on slot A.

## Runbook

Steps 0 through 7 have run. Steps 3 through 7 were written afterwards, on 2026-10-24 at 16:19 -0400, in the commit that recorded the hand-loads. Step 8 has run. Step 9 is written and not agreed. From here a new step is written here and agreed before it runs. Do not mark slot B successful. Do not request attention in step 8. Do not write the flash.

### 0. Read the firmware hand-off

Passed, 2026-10-23, against `G/` tag `android-14.0.0_r0.102`. The decision is `fts_crc_check` plus the match check in `flash_burn`. The write is `flash_burn`, reached from `flashProcedure`. The interrupt enable is `fts_init_sensing`, after `fts_interrupt_install` has requested the IRQ and disabled it. Lines are in Facts. The programming procedure that starts at `ftsFlash.c:1045` is not transcribed.

**Expect / pass:** those functions are cited, and this file still has no command list.

**Stop:** a later edit adds the body of `flash_burn` or a guessed register list.

**Rollback:** none. Nothing was written to the phone.

**Risk:** none. This step reads the source. It does not touch the phone.

### 1. Later, and not this commit

A new kernel branch, one subject, node left disabled. The first boot of that branch is step 2. Its stop conditions include: attention requested before the hand-off, any rail other than LDO25M and LDO26M changing, a UFS error handler, USB dropping, or the phone failing to come back. If ABL falls back to slot A, stop and take a fresh backup.

### 2. Read the CRC status register

Passed, 2026-10-24. See Results. One slot B boot of `523924301`. The cover node stays disabled in the kernel DTB. The image overlay is `device/felix/overlays/cover-touch.dtso`. `salixp` stays blacklisted. Load it by hand after the mailbox, the ACPM protocol, and `sec-acpm`.

**Expect / pass:** dmesg has `salixp spi0.0: chip id 36 40` and `salixp spi0.0: crc status NN raw NN`. `crc status 00` means the low two bits were clear. Any other status is the CRC-error value. The driver does not reset the controller after this read and does not write the flash. Both cover rails show one user. Unbind leaves both with no users.

**Stop:** attention is requested, any rail other than LDO25M and LDO26M changes, a UFS error handler, USB drops, or the phone does not come back. If ABL falls back to slot A, stop and take a fresh backup.

**Rollback:** unbind `salixp`. Do not mark slot B successful.

**Risk:** the same PMIC bind as the chip-id gate. This step does not call `fts_system_reset`.

### 3. Read system info

Passed as a hand-load on the already-running `523924301` boot, 2026-10-24. The runbook was written afterwards, 2026-10-24 16:19 -0400. Not a new image and not marked successful. The reader was a hand-loaded module, not the booted image. Same image rules as step 2: slot B only, not marked successful, cover node disabled in the kernel DTB, `salixp` blacklisted until a hand load after the mailbox, the ACPM protocol, and `sec-acpm`. The power-on reset is the same GPIO sequence as step 2. There is no second reset after the CRC read.

The read is opcode `0xA7`, 16-bit address 0, one dummy byte, and 216 payload bytes. It does not send `SYS_CMD_LOAD_DATA`. It does not call `fts_system_reset`. It does not write the flash. Attention stays unrequested.

**Expect / pass:** dmesg has `salixp spi0.0: chip id 36 40`, `salixp spi0.0: crc status 00 raw c0` or a new raw byte with the low two bits clear, and `salixp spi0.0: sysinfo header a5 id 01`. The hand-load treated a missing header as a pass and stopped. The review fix fails probe on a header other than `a5 01`. Both cover rails show one user. Unbind leaves both with no users. No other rail changes. No UFS error-handler line.

**Stop:** attention is requested, the driver resets the controller or writes the flash, any rail other than LDO25M and LDO26M changes, a UFS error handler, USB drops, or the phone does not come back. If ABL falls back to slot A, stop and take a fresh backup.

**Rollback:** unbind `salixp`. Do not mark slot B successful.

**Risk:** the same PMIC bind as the chip-id gate, plus one framebuffer read. This step does not call `fts_system_reset` and does not send a load command. A CX version is not the calibration.

### 4. Read the three AFE version bytes

Passed as a hand-load on the already-running `523924301` boot, 2026-10-24. The runbook was written afterwards, 2026-10-24 16:19 -0400. Not a new image and not marked successful. Same hand-load as step 3. No new boot. The read is the same framebuffer block. It logs the three bytes that follow the CX version. It does not call `fts_system_reset`, send a scan command, write the flash, or request attention.

**Expect / pass:** dmesg has `sysinfo afe cfg NN cx NN panel NN` after the header and version lines from step 3. A mismatch between those bytes is a result, not a reason to initialize the panel. Both cover rails show one user. Unbind leaves both with no users. No other rail gains a user. No UFS error-handler line.

**Stop:** attention is requested, a scan command is sent, the driver resets the controller or writes the flash, any rail other than LDO25M and LDO26M gains a user, a UFS error handler, USB drops, or the phone does not come back. If ABL falls back to slot A, stop and take a fresh backup.

**Rollback:** unbind `salixp`. Do not mark slot B successful.

**Risk:** the same PMIC bind as step 3. This step does not select panel init.

### 5. Poll CX CRC errors after a system reset

Passed as a hand-load on the already-running `523924301` boot, 2026-10-24. The runbook was written afterwards, 2026-10-24 16:19 -0400. Not a new image and not marked successful. `fts_fw_update` (`touch/ftm5/fts.c:4287`) calls `fts_system_reset` and polls `0xA0`, `0xA1`, `0xA5`, and `0xA6`. A hit is the flash path. On this board `fts_system_reset` toggles the reset GPIO and waits for controller-ready (`ftsCore.c:66`). It does not request attention.

The hand-load logged the miss and returned 0, so probe continued to the scan command. That is not what this step claimed. The review fix fails probe, before the scan command and before an input device is registered, on a hit, on no controller-ready, and on a panel CRC event (`0x22` or `0x23`). That fix is in the step 8 boot, `salixp.c` blob `c1752a85`. Step 8 does not request attention.

**Expect / pass:** dmesg names whether any of those four events arrived within 100 ms of the reset. No event, and controller-ready, is a pass. An event fails probe and does not scan. No flash write. No attention request.

**Stop:** the driver writes or erases the flash, attention is requested, any rail other than LDO25M and LDO26M gains a user, a UFS error handler, USB drops, or the phone does not come back. If ABL falls back to slot A, stop and take a fresh backup.

**Rollback:** unbind `salixp`. Do not mark slot B successful.

**Risk:** a GPIO reset of the cover controller. This step does not call the flash path.

### 6. Scan command, no interrupt

Passed as a hand-load on the already-running `523924301` boot, 2026-10-24. The runbook was written afterwards, 2026-10-24 16:19 -0400. Not a new image and not marked successful. `senseOn` (`ftsTool.c:283`) is scan command `0xA0`, mode `0x00`, settings `0xFF`. Google writes a hardware-register preamble first (`ftsCore.c:380`: opcode `0xFA`, address `0x20000000`). That is the same prefix as the flash commands, so this step does not send it. It writes the three-byte scan command and reads the FIFO for echo `0x43 0x01` followed by that command. It does not request `gpa6-7`.

**Expect / pass:** dmesg names whether the echo arrived. Either result is a pass for this step. No flash write. No interrupt request.

**Stop:** the preamble or any other hardware-register write is sent, the flash is written or erased, attention is requested, any rail other than LDO25M and LDO26M gains a user, a UFS error handler, USB drops, or the phone does not come back. If ABL falls back to slot A, stop and take a fresh backup.

**Rollback:** unbind `salixp`. Do not mark slot B successful.

**Risk:** one scan command on a controller whose CRC poll had already returned clear. This step does not send the `0xfa` preamble and does not request attention.

### 7. Report a FIFO touch without the interrupt

Passed as a hand-load on the already-running `523924301` boot, 2026-10-24, and left bound. The runbook was written afterwards, 2026-10-24 16:19 -0400. Not a new image and not marked successful. After the scan command, a work item reads the same FIFO and, for enter, motion, and leave, reports the existing 8-byte decode into the input device. It does not request `gpa6-7`. The first eight touch events are logged. Remove disables the work before the input device goes away.

**Expect / pass:** with a finger on the cover, dmesg shows `touch event`, and an input event is visible to the session. No interrupt request. No flash write. No hardware-register preamble.

**Stop:** attention is requested, the preamble or any other hardware-register write is sent, the flash is written or erased, any rail other than LDO25M and LDO26M gains a user, a UFS error handler, USB drops, or the phone does not come back. If ABL falls back to slot A, stop and take a fresh backup. Unbind if the pointer moves and the finger is not on the cover.

**Rollback:** unbind `salixp`. Do not mark slot B successful.

**Risk:** a 10 ms FIFO poll on a controller that is already scanning. This step does not request attention and does not write the flash.

### 8. Boot the folded report path, no interrupt

Passed, 2026-10-26. See Results. This step is attended. It does not request `gpa6-7`. The boot is a packed build of published head `aa42f8a8c`, `salixp.c` blob `c1752a85`, which fails probe on config CRC events `0x20` and `0x21` and on a missing scan echo. It is not a boot of ancestor `b2a37752b`, not a hand-loaded module, and not a hand-edited DTB. If the review's fold lands before the boot, the identity is the blob, not a commit id that will change. `tools/phone-smoke` is the report. Slot B is not marked successful.

Build that head with an explicit worktree and output directory. For this pack only, set `DTB_OVERLAYS=cover-touch` in `device/felix/device.conf`, run `bin/omamobile images`, then remove that line. Do not commit it. The overlay is the one in omarchy-mobile#34, `device/felix/overlays/cover-touch.dtso`. It enables the disabled node. It does not set `regulator-always-on`. It is not a hand edit of the DTB.

Write the packed images with `bin/omamobile push`. That writes slot B and reboots. Do not mark slot B successful. `omamobile-device-felix` does not mark a slot successful. Before that reboot, read `androidboot.slot_suffix` from `/proc/bootconfig`. `reboot-to` boots the current slot and does not switch slots. If the current slot is not B, do not reboot. If the phone comes back on A, do not load drivers. Enter fastboot with the buttons and run `fastboot --set-active=b`. That restores slot B's retry count. It does not mark the slot successful, and it does not need a second image write unless the images themselves need rewriting.

After the phone is back, `uname -r` must be the release of that head. The slot must be B. `salixp` stays blacklisted. The module that is loaded is the one `push` installed for that release, not a module built beside it. Start a kmsg stream to the laptop first: `tools/phone-ssh 'dmesg -w' > logs/felix-cover-touch-step8-$(date +%s).log &`. In that stream, both cluster watchdogs must already be inactive (`s3c2410_wdt`, "watchdog inactive, reset disabled"). If either is still running, stop. That line shows `s3c2410_wdt` has taken ABL's watchdogs and stopped them (`tmr_atboot` is 0). It is not a reset. Nothing else feeds `/dev/watchdog0`, and the bootargs have only `panic=10`, so a hang that does not panic lasts until the buttons unless a feeder is armed.

Load the mailbox, the ACPM protocol, and `sec-acpm` before any timer. Those three are not under the dead-man: four loads plus the confirmation do not fit in 90 s, and a slow run must not unbind a driver that already probed. Save `regulator_summary` after `sec-acpm` and before `salixp`. A snapshot taken before `sec-acpm` makes every S2MPG12 rail look new. This one is the bind's before.

Arm a feeder, the same shape as `tools/acpm-stage --watchdog`: open `/dev/watchdog0`, write `k` every 2 s, and on `TERM` write magic-close `V` and exit. A hang that stops the feeder resets the phone in about 15 s. Record the pid in `/run/salixp-wd.pid`. If the feeder does not arm, stop. The step is attended. If the phone has already stopped answering and the feeder is not running, recover by holding Power about 30 s, then pressing Power.

Then arm a dead-man: `systemd-run --unit=salixp-deadman --on-active=90` that unbinds `spi0.0` from `salixp`. Load that release's `salixp`. Confirm with `tools/phone-ssh --fresh true`. `--fresh` is `ControlMaster=no` and `ControlPath=none`. A checkout whose `phone-ssh` has no `--fresh` uses `ssh -o ControlMaster=no -o ControlPath=none -o BatchMode=yes root@172.16.42.1 true`. Either way the check is not the connection opened before the load. Only then stop the dead-man and `kill` the feeder pid, which is the magic close. If the confirmation does not arrive, leave both armed. An unbind cannot undo a hang. The feeder is the reset if the phone stops answering. The log stream is the record of that.

Diff `regulator_summary` after the `salixp` load against the snapshot taken after `sec-acpm`.

**Expect / pass:** `tools/phone-smoke` passes. dmesg has chip id `36 40`, crc status `00`, sysinfo header `a5 01`, mp flag `a5`, controller-ready, no config CRC event (`0x20` or `0x21`), no CX CRC event, no panel CRC event, and a sense echo. A finger produces an enter. No interrupt is requested. No flash write. `uname -r` matches the pushed release. The rail diff shows a new user only on LDO25M and LDO26M.

**Stop:** attention is requested, the module loaded is not the one from that release, the DTB was hand-edited, the flash is written, the before snapshot is missing, any rail other than LDO25M and LDO26M gains a user, a UFS error handler, USB drops, the watchdogs are not owned, the feeder does not arm, the phone does not come back, or the dead-man fires. If ABL falls back to slot A, stop and take a fresh backup.

**Rollback:** the dead-man unbinds `salixp`. The feeder resets a hang that the unbind cannot undo. Pack slot B again without `cover-touch` and reboot slot B. Do not mark slot B successful. Do not boot slot A.

**Risk:** a GPIO reset and one scan command on the driver that contains the config CRC stop, plus a slot B reboot, plus a watchdog that is armed only for this load. This step does not request attention. A controller stock would repair, including on a config CRC event, does not reach the scan command. A missing echo does not register an input device.

### 8a. Restore stock Android on slot A

Not run. Agreed in this review on 2026-10-27. Written that day, and revised the same day from the review. This is a slot A write, outside everything the tools allow. It is a named, one-time exception to CONTRIBUTING.md §3.1 for this phone, run by hand. It does not extend to a tool or to any other device. The command list below is the dry run.

The image is factory build CP3A.261005.002.A1, the build the 2026-10-20 notes name, or a newer factory build, never an older one. Its bootloader image is `bootloader-felix-felix-17.0-15902555.img`. `version-bootloader` must be `felix-17.0-15902555`. If it is not, stop and ask. Do not flash that bootloader image. Its radio image is `radio-felix-g5300q-260604-260807-b-16036236.img`. `version-baseband` must be `g5300q-260604-260807-B-16036236`. If it is not, stop and ask. Do not flash the radio.

`super`'s slot A is not known. On 2026-10-22 slot A was GrapheneOS. The later rewrite is recorded only for the five boot images, and whether `vbmeta` was touched is not recorded. `super` and its logical partitions are not in that record, and they have not been read. They may still be GrapheneOS, or something else. Five stock boot images on top of that would not be stock Android, and nobody can say what that boot does, including to `efs` and `persist`. The write is the whole of stock's slot A, and nothing else, so the boot is not that mix.

Every command is `fastboot -s <serial> …`. The placeholder stays in this file. The real serial is checked on the machine and is not written here. A check once does not pin a later command.

Before any write, record these. Product must be `felix`. The bootloader must be unlocked.

```
fastboot -s <serial> getvar product
fastboot -s <serial> getvar unlocked
fastboot -s <serial> getvar version-bootloader
fastboot -s <serial> getvar version-baseband
fastboot -s <serial> getvar current-slot
fastboot -s <serial> getvar slot-successful:a
fastboot -s <serial> getvar slot-successful:b
fastboot -s <serial> getvar slot-unbootable:a
fastboot -s <serial> getvar slot-unbootable:b
fastboot -s <serial> getvar slot-retry-count:a
fastboot -s <serial> getvar slot-retry-count:b
```

The image's `fastboot-info.txt` is what `fastboot update` writes. Felix's file lists:

```
flash boot
flash init_boot
flash dtbo
flash vendor_kernel_boot
flash pvmfw
flash vendor_boot
flash --apply-vbmeta vbmeta
flash vbmeta_system
flash vbmeta_vendor
reboot fastboot
update-super
flash system
flash system_dlkm
flash system_ext
flash product
flash vendor
flash vendor_dlkm
flash --slot-other system system_other.img
if-wipe erase userdata
if-wipe erase metadata
```

This step keeps that file's slot A flashes and drops `update-super`, the `--slot-other` line, and both erases. The names in the file are unsuffixed because `fastboot update` uses the current slot. Here every partition name is `_a`.

From the unpacked factory image, still in the bootloader, and only these:

```
fastboot -s <serial> flash boot_a boot.img
fastboot -s <serial> flash init_boot_a init_boot.img
fastboot -s <serial> flash dtbo_a dtbo.img
fastboot -s <serial> flash vendor_kernel_boot_a vendor_kernel_boot.img
fastboot -s <serial> flash pvmfw_a pvmfw.img
fastboot -s <serial> flash vendor_boot_a vendor_boot.img
fastboot -s <serial> flash vbmeta_a vbmeta.img
fastboot -s <serial> flash vbmeta_system_a vbmeta_system.img
fastboot -s <serial> flash vbmeta_vendor_a vbmeta_vendor.img
fastboot -s <serial> reboot fastboot
```

`--apply-vbmeta` stays in the quoted file, where it is `fastboot-info.txt` syntax. It is not a fastboot command-line option, so the `vbmeta_a` line above does not carry it. Fastboot applies its `vbmeta*` handling by itself, and this step does not use `--disable-verity`.

Then in fastbootd, the `_a` logical partitions that file lists. Not `super` itself, and not `update-super`. Before each of these, fastboot resizes the partition to the image's size. That rewrites the partition table at the start of `super` for slot A. It is part of writing the `_a` logical partitions, and this exception covers it. It is not a flash of `super`, and it is not an unsuffixed write.

```
fastboot -s <serial> flash system_a system.img
fastboot -s <serial> flash system_dlkm_a system_dlkm.img
fastboot -s <serial> flash system_ext_a system_ext.img
fastboot -s <serial> flash product_a product.img
fastboot -s <serial> flash vendor_a vendor.img
fastboot -s <serial> flash vendor_dlkm_a vendor_dlkm.img
```

If a logical flash refuses because the layout cannot take it, stop and ask. Do not flash `super` to make it fit.

Do not flash `bootloader_a`, `radio_a`, `abl`, `bl1`, `bl2`, `bl31`, `gsa`, `ldfw`, `modem`, `pbl`, or `tzsw`. The image contains those files. They are not in `fastboot-info.txt`. They are not this write. Do not flash `system_other.img`, and do not use `--slot-other`. Do not flash `super`, `userdata`, `misc`, `metadata`, `devinfo`, `persist`, `efs`, `efs_backup`, `modem_userdata`, `modem_a`, or `modem_b`. Do not flash anything unsuffixed, and nothing `_b`. Do not relock. Do not run the image's `flash-all.sh`. It flashes the bootloader and the radio and wipes `userdata`.

Then:

```
fastboot -s <serial> --set-active=a
fastboot -s <serial> reboot
```

Attended. Stock cannot use the Arch root, so expect a factory data reset offer, not a lock screen. Decline it. Confirming it erases the only Linux root. Go to fastboot with the buttons. Do not load drivers if the phone is still on A.

From that fastboot:

```
fastboot -s <serial> --set-active=b
fastboot -s <serial> reboot
```

The fresh backup is taken after that, from Linux on slot B, read-only, of `efs`, `efs_backup`, `modem_userdata` and `persist`. Stock has no root shell to read them, so it cannot be taken during the slot A boot. That copy is the baseline for step 9, whatever the stock boot reached. Record the before and after `getvar` slot variables in the notes. If the phone comes back on A, do not load drivers. Enter fastboot with the buttons and run `fastboot -s <serial> --set-active=b`.

**Expect / pass:** the dry-run list is the only write, slot A offered a data reset rather than a lock screen and it was declined, `userdata` is still the Linux root, the backup above exists, the slot variables are in the notes, and slot B is current again.

**Stop:** the product is not `felix`, the bootloader is locked, `version-bootloader` is not `felix-17.0-15902555`, `version-baseband` does not match the image, any command lacks `-s <serial>`, any forbidden partition would be written, a logical flash refuses, or the data reset is confirmed.

**Rollback:** `fastboot -s <serial> --set-active=b` from the buttons. Do not mark slot B successful.

**Risk:** a slot A write the tools do not perform, including `vbmeta_a`, `pvmfw_a`, the slot A logical partitions, and the resize of those partitions in `super`'s metadata. An Android boot rewrites the calibration partitions. The backup comes after the return to slot B, because stock cannot take it.

### 9. Request the attention line

Not run. Held. Not before stock is back on slot A and a fresh backup is taken after that boot. Written 2026-10-25, before any boot, for agreement first. Do not run until that agreement is in the review. The cover refresh oneshot is still installed. This step either disables it for that boot or lists it as the second change. The code that requests `gpa6-7` is not in #48. This step does not name a head. The boot, when agreed, is a `bin/omamobile push` of the head that contains that request, plus `tools/phone-smoke`. It is not a module built beside another release. The same slot rule as step 8 applies: read `androidboot.slot_suffix` from `/proc/bootconfig` before the reboot, and do not reboot unless it is B. If the phone comes back on A, do not load drivers. Enter fastboot with the buttons and run `fastboot -s <serial> --set-active=b`. That restores the retry count and does not mark the slot successful.

Start a kmsg stream to the laptop first, the same way as step 8, and confirm both cluster watchdogs are inactive before any load. That check is not a reset. Load the mailbox, the ACPM protocol, and `sec-acpm` before any timer, if they are not already loaded from step 8. Save `regulator_summary` after `sec-acpm` and before the attention module. Arm the same feeder as step 8. If it does not arm, stop. Then arm a dead-man: `systemd-run --unit=salixp-deadman --on-active=90` that unbinds `salixp` and does not leave the IRQ requested. Load the module that requests attention. Confirm with `tools/phone-ssh --fresh true`, and only then stop the dead-man and magic-close the feeder. If the confirmation does not arrive, leave both armed. An unbind cannot undo a hang. The feeder is the reset if the phone stops answering. The step is attended. The log stream is the record of that.

The driver may request `gpa6-7` only after controller-ready, and only level-low, and it disables the IRQ before the scan command the way `fts_interrupt_install` does. It still does not write the flash. A storm is the stop, not a reason to keep the line requested.

**Expect / pass:** one finger produces an enter and a leave through the IRQ, `tools/phone-smoke` passes, and the IRQ count is not climbing while the finger is up. No flash write.

**Stop:** the IRQ count climbs with no finger, USB drops, a UFS error handler runs, the flash is written, the phone does not come back, or the dead-man fires. If ABL falls back to slot A, stop and take a fresh backup.

**Rollback:** the dead-man unbinds `salixp`. Do not mark slot B successful.

**Risk:** a level-low line that sits low storms the interrupt. The dead-man is the bound on that.

## Results

2026-10-26. Step 8. Slot B boot of published head `aa42f8a8c`, `salixp.c` blob `c1752a85`, release `7.3.0-rc6-omamobile-push1-gaa42f8a8c1bf`. Not marked successful. The first reboot stayed on slot A because `reboot-to` boots the current slot and does not switch slots. Slot A is another Omarchy install, not GrapheneOS. SSH came back. Nothing was loaded. There was no lock screen and no offer to reset `userdata`. The buttons entered fastboot. `fastboot --set-active=b` restored the retries from 1 to 3. No second image write. `salixp` stayed blacklisted and was loaded from that release after the mailbox, the ACPM protocol, and `sec-acpm`. Both cluster watchdogs were already inactive. The feeder and the 90 s dead-man were armed before the load, a new SSH login answered, and both were then stopped. The dead-man did not fire.

```
salixp spi0.0: chip id 36 40
salixp spi0.0: crc status 00 raw c0
salixp spi0.0: sysinfo header a5 id 01
salixp spi0.0: sysinfo fw 0003 cxver ffff
salixp spi0.0: sysinfo afe cfg 02 cx 02 panel 02
salixp spi0.0: sysinfo mp flag a5
salixp spi0.0: cx poll ready yes config-crc no cx-crc no panel-crc no events 1
salixp spi0.0: sense echo yes events 2
salixp spi0.0: touch event 13 slot 0
```

Controller-ready arrived. No config CRC event, no CX CRC event, and no panel CRC event. The sense echo arrived. A finger produced an enter and motion on slot 0 while Hyprland had the device open. The log stops after eight events. No `salixp` interrupt. No flash write. No UFS error-handler line. `vdd-outer-ts` and `avdd-outer-ts` each went from zero users to one (`spi0.0-vdd`, `spi0.0-avdd`). No other rail gained a user. `tools/phone-smoke` passed the required checks, including the session, after Hyprland and quickshell were started by hand on the cover framebuffer. The GPU render node was panthor. The GPU cap stayed 0. The inner panel was not programmed. Slot B was not marked successful. The step 8 table was not saved. A later read-only run of the same release, with `salixp` not loaded, is below. Touch is absent in that run because the module was not loaded. The slot was B.

```
boot (required)          skip   no slot on the command line
storage guard (required) ok     only userdata and slot B boot images writable
root (required)          ok     ext4 on userdata
kernel health (required) ok     no oops or BUG
systemd units            ok     none failed
USB gadget (required)    ok
display                  ok     1080x2092, connected
GPU                      ok     panthor
session (required)       ok     Hyprland and the shell
touch                    not ok no multitouch device (module not loaded)
buttons                  ok     gpio-keys
Wi-Fi, Bluetooth, battery, sound, sensors, cameras  skip
```

On 2026-10-27 the six partitions were compared read-only with the 2026-10-16 backup. `efs`, `efs_backup`, `modem_userdata`, and `persist` differ. `modem_a` and `modem_b` match. No boot list exists between those two copies, so no Android boot can be named and a write from Linux cannot be ruled out. The 2026-10-27 copy is the current contents, cause of the change unknown. It is not a baseline. The 2026-10-16 set stays beside it. `devinfo` was in the 2026-10-16 set and was not copied on 2026-10-27, so it was not compared. It is expected to differ, because `set-active` and the retry counters write it. The sums stay off the repository. The cover refresh-rate oneshot does not reboot the phone and does not change slots. It is still installed. The only slot A landing in step 8 was the `push` reboot above. The journal has no slot field. The boot between the previous session and the step 8 `salixp` boot is the landing: kernel `7.3.0-rc6-omamobile-push1-g223035c3541c-dirty`. That commit is not in the published tree. It was a local build. It is not the images just written to slot B, no `salixp`, and SSH. Its initramfs ran the storage guard. `efs`, `efs_backup`, `modem_userdata` and `persist` were set read-only. It is an initramfs from this repository, so that landing is not the Linux write that cannot be ruled out.

2026-10-24. Fourth hand-load on the same boot. The scan command was written. The hardware-register preamble was not. No flash write. No interrupt request.

```
salixp spi0.0: sense event 43 type 05
salixp spi0.0: sense event 43 type 01
salixp spi0.0: sense echo yes events 2
```

The echo matched the scan command. The other status event is type `0x05`, force calibration triggered (`ftsSoftware.h`). The driver did not start a calibration and did not write a register. No `salixp` interrupt. The two cover rails each gained one user and returned to zero on unbind. No other rail gained a user. No UFS error-handler line.

2026-10-24. Fifth hand-load on the same boot. The poller stayed bound. A finger on the cover produced an enter and motion on slot 0. The log stops after eight events; later motion and the lift were still reported to the input device. No `salixp` interrupt. No UFS error-handler line. Hyprland was not running, so it did not see the touch. `sddm.service` is not installed. The DRM output is the cover framebuffer, connected and enabled. A Hyprland start on that device, as the login user, aborted in backend creation before it opened the touch device. The 2026-10-21 cover session was software-rendered: the lua config, `LIBGL_ALWAYS_SOFTWARE=1`, `GALLIUM_DRIVER=llvmpipe`, and `AQ_DRM_DEVICES` pointed at the cover framebuffer. Restarting that way left Hyprland active. Its control socket answered. The renderer still reports no matching device for the cover output and retries the commit. Libinput had opened the touch node and refused it: not tagged as a touchscreen, because the input device did not advertise position axes. A reload that sets those axes made udev tag it, and libinput then accepted it. A later finger produced an enter and motion, and the cover pointer disappeared. A full-screen window then changed while the finger was down. The touch coordinates moved across the cover. The booted device tree inverted both axes, and that put the reported point opposite the finger. A later slot B write of that same image removed the invert properties. `uname -r` was still `7.3.0-rc6-omamobile-push1-g523924301fb3`. The image was not a rebuild of the then-published head `e4b78a44a`, and slot B was not marked successful. The write was `fastboot flash vendor_kernel_boot_b` only. Both `gs201-felix` DTB copies in that image, `soc_id` `0x9855001` and `0x9855000`, had `touchscreen-inverted-x` and `touchscreen-inverted-y` removed. The other four slot images were not rewritten. The polling reader was loaded after that boot and was not part of the image. The reported point sat on the finger, including 1077, 2025 at the bottom edge, with no shell correction. That is Hyprland taking the touch. The renderer still reports no matching device for the cover output. The inner panel was not programmed. The touch device was left bound.

```
salixp spi0.0: touch event 13 slot 0
salixp spi0.0: touch event 23 slot 0
```

2026-10-24. Third hand-load on the same boot. The reset pin was toggled and the FIFO was read. No flash write.

```
salixp spi0.0: cx poll event 03 type 00
salixp spi0.0: cx poll ready yes cx-crc no events 1
```

Controller-ready arrived. None of `0xA0`, `0xA1`, `0xA5`, or `0xA6` arrived. No scan command and no attention request. No `salixp` interrupt. The two cover rails each gained one user and returned to zero on unbind. No other rail gained a user. No UFS error-handler line.

2026-10-24. Second hand-load on the same boot. The three AFE version bytes were `02`, `02`, and `02`.

```
salixp spi0.0: sysinfo afe cfg 02 cx 02 panel 02
```

Config, CX, and panel AFE versions match, so that mismatch does not select panel init. The CX version field is still `ffff`. No scan command, no system reset, no flash write, and no attention request. No `salixp` interrupt. The two cover rails each gained one user and returned to zero on unbind. No other rail gained a user. No UFS error-handler line.

2026-10-24. Hand-load on the running slot B kernel `7.3.0-rc6-omamobile-push1-g523924301fb3`, not a new boot and not marked successful. An earlier head of #48, no longer on a branch. Slot B was written by hand. `salixp` was loaded by hand after the mailbox, the ACPM protocol, and `sec-acpm`.

```
salixp spi0.0: chip id 36 40
salixp spi0.0: crc status 00 raw c0
salixp spi0.0: sysinfo header a5 id 01
salixp spi0.0: sysinfo fw 0003 cxver ffff
```

A later request-0 read on that same hand-loaded module logged `salixp spi0.0: sysinfo mp flag a5`. That line is in the #48 description. `a5` is the factory full panel init (`MP_FLAG_FACTORY`). The header matched, so the block was present without a system reset and without a load command. The firmware version field is `0003`. The CX version field is `ffff`, which is not the calibration. The driver did not reset the controller, write the flash, or request attention. No `salixp` interrupt. `vdd-outer-ts` and `avdd-outer-ts` each went from zero users to one, and unbind returned both to zero. The other S2MPG12 LDOs registered with zero users when `sec-acpm` loaded and did not gain a user. No UFS error-handler line.

2026-10-24. Slot B boot of `523924301`, release `7.3.0-rc6-omamobile-push1-g523924301fb3`. Not marked successful. `salixp` was blacklisted and loaded by hand after the mailbox, the ACPM protocol, and `sec-acpm`.

```
salixp spi0.0: chip id 36 40
salixp spi0.0: crc status 00 raw c0
```

Masked status `00` is the low two bits of raw `c0` (`CRC_MASK` is `0x03`). Those bits were clear. The driver did not reset the controller and did not write the flash. The upper bits of the raw byte are not decoded. System info was not read. Attention was not requested.

`vdd-outer-ts` and `avdd-outer-ts` each gained one user (`spi0.0-vdd` at 1800 mV, `spi0.0-avdd` at 3300 mV, min equal to max). Unbind of `spi0.0` returned both to zero users. No other rail changed. No UFS error-handler line.

2026-10-23. Chip id `36 40` on `dd05dd347` is the earlier gate. Step 0 citations are from `G/` tag `android-14.0.0_r0.102` and were not run on this phone. `F/` identifies `firmware/ftm5_fw_f10_ext.ftb` and the file was not copied into this repository.

## Open questions

- Step 5 showed no CX CRC event within 100 ms of controller-ready. The four types Google checks, `0xA0`, `0xA1`, `0xA5`, and `0xA6`, did not arrive. The hand-load returned 0 and continued, so that boot does not show the probe stop. The panel CRC types `0x22` and `0x23` did not arrive either. Config CRC types `0x20` and `0x21` are the same class of stop. They were not in that hand-load's fail set. Published head `aa42f8a8c`, `salixp.c` blob `c1752a85`, fails probe on them, and on a missing scan echo. Step 8 booted that head on 2026-10-26. The fold the review asked for is before #48 leaves draft. It was not done before this boot. This phone's header, MP flag, and AFE bytes do not take the repair path, so the stop is still a code fact, not a log line. The stop set is not the whole of stock's write decisions: felix leaves auto firmware update on, and stock would also flash on a version difference with the file.
- The status event `43 05` on the step 8 boot was `43 05 01 00 00 00 00 01`. Google's handler logs `event[2]` through `event[7]`; `event[2]` of `0x01` is "Sense on Force cal". The driver did not start a calibration and did not write a register.
- Step 8 ran on 2026-10-26 on published head `aa42f8a8c`, `salixp.c` blob `c1752a85`, not on ancestor `b2a37752b`. The feeder and the fresh SSH confirmation ran. Step 9, the attention line, is written and not agreed. Its code is not in #48, so it does not name a head.
- The hand-loaded module was `insmod`'d into the non-dirty `523924301` release after the mailbox, the ACPM protocol, and `sec-acpm`. Its blob was not recorded, so it is not known whether that file was the blob Derek asked about, `2a479290`. Ancestor `b2a37752b` has `salixp.c` blob `9cfad57f`. Published head `aa42f8a8c` has `salixp.c` blob `c1752a85`. The `523924301` release's own driver only reads the CRC register. The step 8 release is `aa42f8a8c`.
- The inner panel stays on its own plan.
