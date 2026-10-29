<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 (panther) bring-up notes

Findings from real hardware, newest first. [BRINGUP-M1.md](BRINGUP-M1.md) is the first-light record.

The board file (`gs201-panther.dts`) was merged as [linux-omarchy-mobile#108](https://github.com/derekross/linux-omarchy-mobile/pull/108), and the FT3658 driver as [#109](https://github.com/derekross/linux-omarchy-mobile/pull/109); the test kernels below add one local commit each on top.

## 2026-10-31: the new omamobile base, #133's alignment, and stock's touch details

Three boots, one change each, on `omamobile` at b0d62d9e7 (new spi-s3c64xx PIO fixes, ACPM and RTC changes), each with the USB bus commit:

- **A**, `7.3.0-rc6-omamobile-push1-g8c9496448397`: the base, with #133's earlier head. Flashed, so slot B was back at 3 retries before it.
- **B**, `…-gfe29f1dadbb5`: plus only [linux-omarchy-mobile#133](https://github.com/derekross/linux-omarchy-mobile/pull/133)'s `__aligned(ARCH_DMA_MINALIGN)` buffers. Pushed.
- **C**, `…-ge57e346e9b71`: plus [linux-omarchy-mobile#166](https://github.com/derekross/linux-omarchy-mobile/pull/166), the interrupt pull-up and the 1 µs chip-select setup delay. Flashed, since a push would have left no retries. The live tree has `samsung,pin-pud = 3` in `ts-irq-pins` and `spi-cs-setup-delay-ns = 1000` in the touch node.

All three boots behaved the same:
- the FT3658 read chip id 0x56, firmware 0x16, and touches and the PIN unlock worked, with no SPI or CRC errors;
- the GPU and the haptics came up (the haptics were felt in A and C);
- ACPM had 14 of 15 channels, the RTC came up as `rtc0`, and `mem_sleep` was `[s2idle]`;
- on `i2c-1`, `USBSW_CTRL` read 0x09 and `CHG_DETAILS_00` 0x60.

A and B had the same kernel warnings. `tools/phone-smoke` passed on C.

## 2026-10-29: USB comes back after a replug (U1)

One boot of a local commit on top of the touch branch that enables USI13 as I2C at 400 kHz, as on the Pixel 7 Pro, with no devices described on it. Stock's live tree has the same MAX77759 there (TCPC 0x25, PMIC 0x66, fuel gauge 0x36, charger 0x69) on gpp25-0/1. The bus probes as `i2c-1`; the TCPC's `USBSW_CTRL` (0x93) reads 0x09 and the charger's `CHG_DETAILS_00` (0xb5) 0x60, VBUS valid. With the package's `omamobile-usb-rescue` running (a transient unit, same bytes as the Pixel 7 Pro's), the cable was pulled for about 5 s: the switch read 0x00, the script logged `VBUS valid, USBSW_CTRL 0x00: closing the data switch`, and SSH answered again within about 9 s. No I2C errors; the touch, the GPU and the haptics stayed up. The commit is merged as [linux-omarchy-mobile#167](https://github.com/derekross/linux-omarchy-mobile/pull/167); device-panther 0.1.3 ships the script and enables it. Installed on 2026-10-31 on kernel C below, its service closed the switch again after a replug, and SSH answered within seconds. It then started at boot on the next three kernels (BATTERY-PLAN.md D, E and F) and brought USB back after each of their four unplugs.

## 2026-10-29: the touch node, suspend-to-idle and LDO25M (T6)

One boot of kernel `7.3.0-rc6-omamobile-push1-g8d46192a301e`: the board branch of [linux-omarchy-mobile#134](https://github.com/derekross/linux-omarchy-mobile/pull/134) (the GPU, the haptics, `mem_sleep_default=s2idle`, LDO25M fixed at 1.8 V and the final touch node, since merged) merged with the driver's review fixes, [#133](https://github.com/derekross/linux-omarchy-mobile/pull/133) (DMA-safe SPI buffers, `fsleep()`), with `CONFIG_TOUCHSCREEN_FOCALTECH_FT3658=m` from `kernel/configs/omamobile.config`. The build's local merge, `8d46192a3`, predates the commit messages' test paragraphs and sign-offs; its tree is the same as the merge of the PR heads, #134 at `ace1ba57fbe7` and #133 at `fdc4f4403103` (both `0eb5d6eb`). The modules were pushed before the boot.

- `/sys/power/mem_sleep` reads `[s2idle] deep`.
- `vdd-ts` reads 1.8 V and `avdd-ts` 3.0 V, each with the touch controller as its only consumer.
- `focaltech_ft3658` loads at boot by itself: chip ID 0x56, firmware 0x16. Touches across the panel, the four corners included, drive Hyprland and unlock the PIN screen, with no SPI or CRC errors.
- The GPU and the haptics keep working (a 300 ms rumble was felt), and ACPM has 14 of its 15 channels usable.

## 2026-10-28: the GPU and the haptics, power off, and USB after a replug

Test kernels from local branches on slot B, each one change on top of the touch test kernel; one boot each.

- **GPU (G1).** Kernel `7.3.0-rc6-omamobile-push1-ga92e2bd8546c`: the touch test kernel plus local commit `a92e2bd85`, the same change as [linux-omarchy-mobile#129](https://github.com/derekross/linux-omarchy-mobile/pull/129). With `&gpu` enabled as on the Pixel 7 Pro and the package's always-on rule installed before the boot, panthor probes the Mali-G710 (id 0xa862, `shader_present` 0x1110055), boots the CSF firmware (interface v1.5.0) and registers `renderD128`. Hyprland renders on it through the project's Mesa ("Mali-G710 MC7 (Panfrost)"), with no MMU faults or GPU resets. Probe prints `_opp_set_regulators: no regulator (mali)`, as on the Pixel 7 Pro (harmless, [GPU-PLAN](../cheetah/GPU-PLAN.md)).
- **Haptics (H1).** Kernel `7.3.0-rc6-omamobile-push1-g575bb567ca5f`: the G1 kernel plus local commit `575bb567c`, the same change as [linux-omarchy-mobile#130](https://github.com/derekross/linux-omarchy-mobile/pull/130). The CS40L26A is on USI8 I2C at 0x43 with the same pins and stock values as the Pixel 7 Pro (read from the live device tree). With `cs40l26.wmfw` and `cs40l26.bin` from this phone's own factory image (`tools/extract-vendor-firmware -d panther`) in `/usr/lib/firmware/updates`, `cs40l26-vibra` finds revision A1, runs firmware 7.2.91 with the wavetable, and registers `cs40l26_vibra`; `tools/ff-rumble` effects of 100-500 ms at 25-80 % were felt.
- **Suspend must be s2idle.** `/sys/power/mem_sleep` reads `s2idle [deep]` on these kernels, and gs201 never wakes from `deep`, so the package now carries the Pixel 7 Pro's `sleep.conf.d` drop-in. Suspend itself is untested here.
- **Power off reboots the phone.** Omarchy's "Power off" (or `systemctl poweroff`) restarts the phone within a second, which spends a slot B retry. With the reboot watchdog off, systemd-shutdown runs to the end. A shutdown hook that saved the kernel log to `userdata` ten times a second, then powered off itself (sysrq `o`, the same `kernel_power_off()`), saved nothing after the trigger: no `sysrq: Power Off`, no device `shutdown` lines, no `reboot: Power down`. So the reset comes in the first tenth of a second of the kernel's power off, or before UFS can write another frame. With `syscon-poweroff` disabled in the test DT that leaves PSCI SYSTEM_OFF, which the firmware seems to turn into a restart (the boot reason reads `watchdog/apc`). The Pixel 7 Pro has never powered off from Linux either ([SUSPEND-PLAN](../cheetah/SUSPEND-PLAN.md) P7). To get to fastboot, hold Power and Volume Down from a running phone instead; that costs no retry.
- **USB doesn't come back after a replug.** A replug while Linux runs leaves the phone off the bus, as on the other Tensor phones (`AGENTS.md`): the MAX77759 opens its USB2 data switch, and nothing closes it. The Pixel 7 Pro's `omamobile-usb-rescue` needs the MAX77759's I2C bus (USI13, `10d60000`), which this board file doesn't enable yet, so for now a replug means Power and Volume Down, then a flash. (2026-10-29: fixed by enabling USI13 and the package's `omamobile-usb-rescue`; see U1 above.)

## 2026-10-27: modules-push and linux-modules-cleanup

`kernel-modules-hook` (in the root image) enables
`linux-modules-cleanup.service`, which on every boot moves each
`/usr/lib/modules/<release>` that is not the running kernel and that no
package owns into `/usr/lib/modules/.old`. A tree from
`bin/omamobile modules-push` is owned by no package, so a boot of any
other kernel before the new one (here, the unplanned reboot above) loses
it, and the new kernel then boots with no modules. `.old` kept only the
old release, so the pushed tree was not recoverable from it. Fix used:
`modules-push` again from the new kernel. Loading the missing modules
afterwards with `udevadm trigger` raced (ACPM probed before its mailbox,
`15 channels, 0 usable`, so `sec-pmic-acpm` failed with -ENODEV before
any PMIC write); a reboot loaded everything in order. To raise with the
tooling: push right before the reboot, or have `modules-push` warn.

## 2026-10-27: Omarchy's power off reboots the phone

"Shut down" in the Omarchy menu, with the USB cable to the laptop
plugged in, rebooted into slot B instead of powering off (and spent a
slot B retry). Holding the power key forced it off. Not looked into yet:
the bootloader may be powering the phone back on because the cable is in.
Until then, reach fastboot from a forced power off. (2026-10-28: it
reboots without the cable too, from the kernel's power off; see above.)

## 2026-10-27: a second stock fallback, and a new backup

Getting to fastboot from Arch went the same way twice: the phone came back
up in slot B instead of powering off, spent slot B's last retry, and the
next boot fell to slot A, whose stock recovery started. The data reset was
declined both times; `adb reboot bootloader` from recovery reached
fastboot (getvar: current slot A, B retry 0, not unbootable), and
`bin/omamobile flash` brought slot B back. A fresh read-only backup was
taken from Linux right after (each partition `ro=1`, found by `PARTNAME`,
checksum-matched against the phone): against the 2026-10-27 baseline,
`modem_a` and `modem_b` match, `persist`, `efs`, `efs_backup` and
`modem_userdata` differ in 100-750 bytes each, `devinfo` in 2. Those bytes
sit in the same places as after boot 6 (compared block by block, both
backups read-only): in each F2FS partition, the checkpoint (the other of
its two copies this time) and the root inode's node block written just
before it; in `persist`, the ext4 superblock, the first five journal blocks
and one inode table block, where only the ctime of `/sensors` and
`/sensors/registry` moved, the same two inodes as after boot 6. No data
block changed in any of them, so recovery's mount explains it. That copy is
the baseline now. To reach fastboot without spending a retry, hold Power
and Volume Down on the running phone until the bootloader shows, without
shutting down first.

## 2026-10-27: devinfo slot bytes against ABL (L-36 evidence)

devinfo is version **3.19** here (cheetah's bootctl is verified on 3.15
only). Only the version and the slot bytes (0x30-0x37) were read, from
Linux, read-only. Byte layout per slot: retry count, then flags (bit 0
unbootable, bit 1 successful, bit 2 active, bit 3 fastboot_ok).

| When | `fastboot getvar` | devinfo 0x30-0x37 |
| --- | --- | --- |
| stock capture, before any of our boots | A: retry 2, successful, bootable; B: retry 3, not successful, bootable | not read |
| one boot after `--set-active=b` (boot 7) | not read | `02 0a 00 00 02 04 00 00` |
| before the T2 flash (after boots 7 and 8) | B: retry 1, not successful, bootable | not read |
| after the T2 flash (`--set-active=b`) and two boots (T2, T2b) | not read | `02 0a 00 00 01 04 00 00` |
| one more boot of slot B (an unplanned reboot), then fastboot | current slot **A**; A: retry 2, successful, bootable; B: retry 0, not successful, bootable | not read |

Every reading agrees with the layout: slot A `02 0a` is retry 2,
successful, fastboot_ok, as getvar says; slot B counts down from 3 by one
per boot, ABL's own change, and `--set-active` resets it. The last row is
the next step of the count (1 to 0), and shows ABL's choice once B has no
retries left: A becomes current, B is not marked unbootable. Still
missing for L-36: a getvar and a byte read of the same state with no boot
in between; a byte read needs Linux, so it has to be taken right before a
planned reboot to fastboot.

## 2026-10-27: boot 6's fallback was a stock boot, and a new backup

When slot B ran out of retries (boot 6, [BRINGUP-M1.md](BRINGUP-M1.md)), ABL booted stock Android on slot A, which went to recovery because its `userdata` is now Arch. The data reset that recovery offers was **declined**: the phone was taken to fastboot with `adb reboot bootloader` and slot B flashed again.

- **Stock recovery wrote to the protected partitions.** Read back over SSH from Linux (read-only, each checked `ro=1` and by `PARTNAME`) and compared against the 2026-10-26 baseline: `modem_a` and `modem_b` match; `efs`, `efs_backup` and `modem_userdata` differ only in their F2FS checkpoint areas, `persist` in its ext4 superblock and journal (it now reads "needs journal recovery"), and `devinfo` in slot B's retry byte and two flag bytes. That is what a mount by recovery leaves, with no sign of data rewritten.
- **New backup.** All seven were read again and checksum-matched; that copy, kept off the repository with its `SHA256SUMS`, is the baseline from 2026-10-27. Any later stock boot, a fallback included, means another one.

## 2026-10-26: UFS behind the guard, and a fresh backup

- **UFS enumerates** (4 LUNs, 55 partitions, the same names and numbers as stock) and the initramfs guard leaves only slot B's five boot images and `userdata` writable. Details: [BRINGUP-M1.md](BRINGUP-M1.md), boot 4.
- **Fresh read-only backup.** `persist`, `efs`, `efs_backup`, `modem_userdata`, `modem_a`, `modem_b` and `devinfo` were read over SSH from the guarded initramfs (each checked `ro=1` and by `PARTNAME` first) and checksum-matched against the phone; the copy and its `SHA256SUMS` stay off the repository. All seven differ from the copy taken under LineageOS that morning, as expected: the factory image rewrote `modem_a`/`modem_b` (radio) and the slot flags in `devinfo`, and stock's first boot writes `efs`, `efs_backup`, `persist` and `modem_userdata`. This copy is the baseline from now on.

## 2026-10-26: first light

- **Console on the panel from boot** (boot 3): `simple-framebuffer` on `0xfac00000`, 1080x2400 ARGB8888, and the init writes DECON0 `TRIG_CON` `0x3061` (`SIMPLEFB_TRIG_CON`). Written by hand over SSH first (boot 2), then from the init.
- **Slot B boots** our kernel (`7.3.0-rc6`) with USB networking and SSH at `root@172.16.42.1`. Both cluster watchdogs are stopped, ramoops is at stock's `0xfd3ff000`. Slot B is not marked successful; slot A stays stock.
- **The bootloader scans the logo out of `0xfac00000`** (DPP0 `RDMA_BASEADDR_Y8`, read once over SSH), the same carve-out as the Pixel 7 Pro, which runs the same `cloudripper` ABL.
- **The splash is 1080x2400 ARGB8888** with no stride padding (DPP0 `RDMA_SRC_SIZE` `0x09600438`, `RDMA_IN_CTRL_0` format 0).
- **DECON0 `TRIG_CON` reads `0x3070`**: the hardware trigger is masked, so the panel keeps the logo until it is unmasked.
- **`reboot-to bootloader` did not reach fastboot.** `syscon-reboot-mode` is bound (`SYSIP_DAT0`, `mode-bootloader` 0xfc), but the phone rebooted straight back into slot B, and `/sys/fs/pstore` was empty on the next boot, so ramoops did not survive that reset. Not investigated yet; fastboot by the buttons meanwhile.
- **CMA:** the kernel's 384 MiB CMA reservation fails on this phone's 8 GB (`MemTotal` 7660972 kB). Nothing at first light needs it.

## 2026-10-26: stock facts

Captured on stock `CP3A.261005.002.A1` (Android 17, security patch 2026-10-05) on slot A, and from a rooted LineageOS 24 build on the same phone before it was restored. The captures stay off the repository.

| Fact | Value | Source |
| --- | --- | --- |
| SoC | GS201, MP1.0, package mode 0, SoC rev 2. Same B0 match as cheetah (`soc_id` 0x09855001) | [V] `getprop` ro.boot.hw.soc.pkg_mode, ro.boot.hw.soc.rev; live DT `/soc_id` |
| Board id | 0x30406, rev 0x10000, dtbo index 22 | [V] `ro.boot.cdt_hwid`, `ro.boot.dtbo_idx`; Google `gs201-panther-mp.dts:14-15` |
| Bootloader | `cloudripper-17.0-15902555`, the same ABL as the Pixel 7 Pro; radio `g5300q-260604-260807-B-16036236`. Both slots flashed from the factory image | [V] `fastboot getvar` |
| Boot images | `boot`, `init_boot`, `vendor_boot`, `vendor_kernel_boot`, `dtbo` on both slots, the same sizes as cheetah (64, 8, 64, 64 and 16 MiB) | [V] `fastboot getvar all` |
| Panel | `sdc-s6e3fc3-p10` (`samsung,s6e3fc3-p10`), 1080x2400, DSI 0 on DECON0 | [V] ABL's `exynos_drm.panel_name`, live DT, `dumpsys display` |
| Touch | FocalTech, `focaltech,ts` in the stock DT. Not cheetah's Synaptics: the TouchComm driver does not apply | [V] live DT |
| Charger, TCPC, gauge | MAX77759, as on cheetah | [V] live DT |
| Reserved memory | Every stock `reserved-memory` region that Google's tree describes matches gs201.dtsi. `sec_dram`, `sec_pt` and `pkvm_guest_firmware` are injected by the bootloader (not in Google's DTS); `cp_aoc_rmem` (0x197fd000) is AoC SRAM, not DRAM | [V] live DT against the built cheetah DTB; Google `gs201-rmem.dtsi` |
| Framebuffer | Not described in Google's tree: ABL injects it. Not copied from cheetah's `0xfac00000`; to be read from DPP0 on the first boot | [I] |
