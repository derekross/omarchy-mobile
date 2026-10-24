<!-- SPDX-License-Identifier: MIT -->
# Pixel Fold cover touch: reports

Status, 2026-10-23. The chip-id gate is linux-omarchy-mobile#32 and omarchy-mobile#34. Neither has merged. `drivers/input/touchscreen/salixp.c` resets the cover controller and reads chip id `36 40`. It does not load firmware or report touches. Step 0 below is done against Google's felix driver at tag `android-14.0.0_r0.102`. This file still adds no driver, no overlay, and no boot.

The power key is linux-omarchy-mobile#41. Touch in `docs/DEVICES.md` is WIP (cover chip id) from omarchy-mobile#34. Buttons stays `no` until the power-key notes merge.

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
- [I] That driver delivers events through Google's touch interface, which this tree does not have. A mainline `input` device is a later revision of this plan.

## Design

Leave #32 and #34 as they are. Reports are a new series after those merge: binding changes only if the report path needs a property, then the driver, then the felix node still `disabled`. An overlay in this repository may enable it for one boot. `regulator-always-on` stays out.

Do not request `gpa6-7` in the same change that only reads the chip id. Do not port `ftm5.c`. Do not add the inner panel, its reset, or S2MPG13.

The firmware file named in the factory node is `F/` `firmware/ftm5_fw_f10_ext.ftb`. Do not vendor that blob. The terms above do not allow shipping it.

The report path never writes or erases the controller's flash and never requests a reflash. The firmware and the CX calibration live in that flash. A burn holds the core, unlocks and erases it page by page, and whether the panel-init and CX area survives depends on `keep_cx`. A bad or interrupted burn can lose the cover panel's factory calibration, and this tree has no way to restore it. A flash write is a separate decision, taken together. This path only reads what is already running: system info, and the CRC status register. It does not call `fts_system_reset`. A read-only step stops after that register read.

## What was built

Nothing for reports. The chip-id reader and its overlay are the earlier pull requests.

| Piece | Where | State |
| --- | --- | --- |
| Chip-id reader, node disabled | linux-omarchy-mobile#32 | open |
| Chip-id plan, notes, blacklist | omarchy-mobile#34 | open |
| Report path | this plan, step 0 | citations only |

## Risks

Requesting attention while it sits low storms the interrupt line. A guessed flash program can leave the cover controller without firmware. Enabling the main PMIC to reach LDO25M and LDO26M is the same risk as the chip-id gate: other rails register, and a slot A boot would rewrite the calibration partitions.

## Runbook

This revision has no phone step. Do not pack an image from this file. Do not load `salixp` again for reports. Do not mark slot B successful.

### 0. Read the firmware hand-off

Passed, 2026-10-23, against `G/` tag `android-14.0.0_r0.102`. The decision is `fts_crc_check` plus the match check in `flash_burn`. The write is `flash_burn`, reached from `flashProcedure`. The interrupt enable is `fts_init_sensing`, after `fts_interrupt_install` has requested the IRQ and disabled it. Lines are in Facts. The programming procedure that starts at `ftsFlash.c:1045` is not transcribed.

**Expect / pass:** those functions are cited, and this file still has no command list.

**Stop:** a later edit adds the body of `flash_burn` or a guessed register list.

**Rollback:** none. Nothing was written to the phone.

**Risk:** read-only. The read is the CRC status register. It does not call `fts_system_reset`.

### 1. Later, and not this commit

A new kernel branch, one subject, node left disabled. The first boot of that branch is a separate runbook written after step 0. Its stop conditions include: attention requested before the hand-off, any rail other than LDO25M and LDO26M changing, a UFS error handler, USB dropping, or the phone failing to come back. If ABL falls back to slot A, stop and take a fresh backup.

## Results

2026-10-23. No report boot. Chip id `36 40` remains the last cover-touch result, on `dd05dd347`. Step 0 citations are from `G/` tag `android-14.0.0_r0.102` and were not run on this phone. `F/` identifies `firmware/ftm5_fw_f10_ext.ftb` and the file was not copied into this repository.

## Open questions

- Does the controller's flash already hold valid firmware and CX? System info and the CRC status register can answer that without writing. That read does not call `fts_system_reset`. The id read did not run either check.
- What does a touch report look like once the interrupt is allowed to fire?
- The inner panel stays on its own plan.
