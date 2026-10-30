<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 (panther) bring-up notes

Findings from real hardware, newest first. [BRINGUP-M1.md](BRINGUP-M1.md) is the first-light record.

The board file (`gs201-panther.dts`) was merged as [linux-omarchy-mobile#108](https://github.com/derekross/linux-omarchy-mobile/pull/108), and the FT3658 driver as [#109](https://github.com/derekross/linux-omarchy-mobile/pull/109); the test kernels below add one local commit each on top.

## 2026-10-28: the GPU and the haptics, power off, and USB after a replug

Test kernels from local branches on slot B, each one change on top of the touch test kernel; one boot each.

- **GPU (G1).** Kernel `7.3.0-rc6-omamobile-push1-ga92e2bd8546c`: the touch test kernel plus local commit `a92e2bd85`, the same change as [linux-omarchy-mobile#129](https://github.com/derekross/linux-omarchy-mobile/pull/129). With `&gpu` enabled as on the Pixel 7 Pro and the package's always-on rule installed before the boot, panthor probes the Mali-G710 (id 0xa862, `shader_present` 0x1110055), boots the CSF firmware (interface v1.5.0) and registers `renderD128`. Hyprland renders on it through the project's Mesa ("Mali-G710 MC7 (Panfrost)"), with no MMU faults or GPU resets. Probe prints `_opp_set_regulators: no regulator (mali)`, as on the Pixel 7 Pro (harmless, [GPU-PLAN](../cheetah/GPU-PLAN.md)).
- **Haptics (H1).** Kernel `7.3.0-rc6-omamobile-push1-g575bb567ca5f`: the G1 kernel plus local commit `575bb567c`, the same change as [linux-omarchy-mobile#130](https://github.com/derekross/linux-omarchy-mobile/pull/130). The CS40L26A is on USI8 I2C at 0x43 with the same pins and stock values as the Pixel 7 Pro (read from the live device tree). With `cs40l26.wmfw` and `cs40l26.bin` from this phone's own factory image (`tools/extract-vendor-firmware -d panther`) in `/usr/lib/firmware/updates`, `cs40l26-vibra` finds revision A1, runs firmware 7.2.91 with the wavetable, and registers `cs40l26_vibra`; `tools/ff-rumble` effects of 100-500 ms at 25-80 % were felt.
- **Suspend must be s2idle.** `/sys/power/mem_sleep` reads `s2idle [deep]` on these kernels, and gs201 never wakes from `deep`, so the package now carries the Pixel 7 Pro's `sleep.conf.d` drop-in. Suspend itself is untested here.
- **Power off reboots the phone.** Omarchy's "Power off" (or `systemctl poweroff`) restarts the phone within a second, which spends a slot B retry. With the reboot watchdog off, systemd-shutdown runs to the end. A shutdown hook that saved the kernel log to `userdata` ten times a second, then powered off itself (sysrq `o`, the same `kernel_power_off()`), saved nothing after the trigger: no `sysrq: Power Off`, no device `shutdown` lines, no `reboot: Power down`. So the reset comes in the first tenth of a second of the kernel's power off, or before UFS can write another frame. With `syscon-poweroff` disabled in the test DT that leaves PSCI SYSTEM_OFF, which the firmware seems to turn into a restart (the boot reason reads `watchdog/apc`). The Pixel 7 Pro has never powered off from Linux either ([SUSPEND-PLAN](../cheetah/SUSPEND-PLAN.md) P7). To get to fastboot, hold Power and Volume Down from a running phone instead; that costs no retry.
- **USB doesn't come back after a replug.** A replug while Linux runs leaves the phone off the bus, as on the other Tensor phones (`AGENTS.md`): the MAX77759 opens its USB2 data switch, and nothing closes it. The Pixel 7 Pro's `omamobile-usb-rescue` needs the MAX77759's I2C bus (USI13, `10d60000`), which this board file doesn't enable yet, so for now a replug means Power and Volume Down, then a flash.

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
