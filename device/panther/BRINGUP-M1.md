<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 (panther) first light

Status (2026-10-27): slot B boots the Arch root on `userdata` into
Hyprland and the Omarchy lock screen, on simpledrm over the bootloader's
framebuffer. SSH answers at `172.16.42.1`, and `bin/omamobile push`
rewrites slot B and reboots into it with no fastboot. The power and
volume keys work (the power key wakes the screen); there was no touch yet:
the FocalTech FT3658 on SPI0 had no mainline driver. Kernel 7.3.0-rc6,
local branch `panther-first-light` on `omamobile-int`; the board file was
merged into `omamobile` as
[linux-omarchy-mobile#108](https://github.com/derekross/linux-omarchy-mobile/pull/108), and the FT3658 driver as
[#109](https://github.com/derekross/linux-omarchy-mobile/pull/109) (later boots are in [NOTES.md](NOTES.md)). Stock Android is on slot A, with its
`userdata` erased.

## What booted

The board file enables the USB PHY and dwc3 (gadget networking and the
ACM console), a ramoops region at stock's address, and a
`simple-framebuffer` on the bootloader's splash at `0xfac00000`. The SoC
tree stops both cluster watchdogs. Everything else stays undescribed or
disabled: panel, touch, GPU, UFS, PMICs, buses. The descriptor's
`SIMPLEFB_TRIG_CON` is the only display-register write; there is no
`BRINGUP_PROBE`. Steps 1-3 below were the first boot, with no framebuffer
node and no trigger.

## Runbook

Each step: commands, Expect/Pass, Stop, Rollback, risk.

1. **Check the images (laptop, read-only).**
   `DEVICE=panther bin/omamobile images`, then unpack `vendor_kernel_boot.img`
   and `dtbo.img` and decompile: two DTBs with `soc_id` 0x9855001 and
   0x9855000, compatible `google,gs201-panther`, and one dtbo entry with
   board id 0x30406, rev 0x10000.
   Stop: any other board id, or a cheetah compatible. Risk: none.

2. **Flash slot B and boot (phone in fastboot).**
   `DEVICE=panther bin/omamobile flash` writes `boot_b`, `init_boot_b`,
   `vendor_boot_b`, `vendor_kernel_boot_b` and `dtbo_b`, sets slot B
   active and reboots.
   Expect: the unlocked-bootloader warning, then the bootloader logo stays
   on the panel; within about a minute the laptop sees a "Pixel 7 (M1)" USB
   device and `tools/phone-ssh uname -r` answers at 172.16.42.1.
   Stop: no USB device after 3 minutes. Rollback: slot B is not marked
   successful, so after the bootloader's retries the phone falls back to
   slot A by itself; otherwise hold Volume Down + Power about 20 s for
   fastboot and `fastboot --set-active=a`. Slot A is stock, and with Arch
   on `userdata` it boots to recovery: decline the data reset, go back to
   fastboot, and take a fresh read-only backup of `persist`, `efs`,
   `efs_backup`, `modem_userdata`, the modems and `devinfo` from the next
   Linux boot (NOTES.md, 2026-10-27). Risk: low (slot B only).

3. **Read the scanout address and the trigger (read-only, over SSH).**
   One register per call; DECON0 and DPP0 are powered because the logo is
   being scanned out.
   `tools/phone-ssh devmem 0x1c0b0040` (DPP0 `RDMA_BASEADDR_Y8`), then
   `tools/phone-ssh devmem 0x1c240030` (DECON0 `TRIG_CON`). `devmem ADDR`
   only, never a second argument: that is a write.
   Expect: a DRAM address for the splash carve-out, and the trigger mask
   ABL left. Stop: the session dies (an unpowered block). Risk: low.

4. **Next boot (one change):** a `simple-framebuffer` node and `no-map`
   carve-out at the address read in step 3, sized 1080 x 2400 x 4; then
   `SIMPLEFB_TRIG_CON` once the step 3 value is understood.

5. **Boot 4: UFS behind the guard (one change).** `&ufs_0`, `&ufs_0_phy`
   and the always-on UFS VCC (gpp0-1, boot-on, from Google's
   `gs201-ufs.dtsi`, not overridden for panther), plus
   `omamobile.ufs-probe` and `omamobile.initramfs` on the command line so
   the init never mounts stock's `userdata`. Fastboot by the buttons, then
   `DEVICE=panther bin/omamobile flash`.
   Expect: the `ufs-probe` report in `dmesg`; every partition `set
   read-only` except the five `_b` boot images and `userdata` (`left
   writable (allowlist)`), `/dev/sda` removed, nothing `FAILED`; the
   partition numbers match stock's `/dev/block/by-name` (`userdata` sda31,
   `devinfo` sdd1, `efs` sda5, `persist` sda1).
   Stop: any `FAILED` or `WARNING ... NOT read-only` line; a UFS error
   storm. Rollback: boot 3's images to slot B, or slot A. Risk: low (the
   guard runs before any partition node is used; nothing writes).

6. **The Arch root on `userdata` (laptop, then the installer).**
   A contributor's local build (docs/RELEASES.md §10): `tools/local-key-init
   panther`, `tools/fetch-published out/panther/published`, `tools/build-packages
   --local panther --import out/panther/published` with the panther package
   and the tree's newer `omamobile-omarchy`, `omamobile-shell` and
   `omamobile-firstboot`, then `KERNEL_OUT=~/android/mainline/out
   tools/build-rootfs --local panther`. The boot images drop
   `omamobile.initramfs`, so the init hands over to Arch. Then, phone in
   fastboot, run by the owner (it asks for the user, password and SSH key):
   `tools/install-phone --device panther --images ~/android/mainline/out/images
   --rootfs out/panther/omamobile-rootfs-panther-<date>-aarch64.img.zst --dry-run`,
   and without `--dry-run` after reading every command.
   Expect: the initramfs grows the root to the partition, `arch: switching
   to Arch Linux on /dev/sda31`, `omamobile-firstboot` creates the user,
   SSH as root and as the user. Stop: the init stays in the initramfs
   (`arch:` line says why). Rollback: boot 4's images keep the initramfs
   (`omamobile.initramfs`); slot A is stock, but its `userdata` is now
   erased (factory reset needed to boot it). Risk: medium (erases
   `userdata`; no other partition is written).

## Results

### 2026-10-26: first light (steps 1-3)

Kernel `7.3.0-rc6-omamobile-push1-g1cb4bd36f3be-dirty` (`omamobile-int`
plus the local `gs201-panther.dts`), slot B, not marked successful.

- **Step 1 passed.** Two DTBs, `soc_id` 0x9855001 and 0x9855000, compatible
  `google,gs201-panther`; one dtbo entry, id 0x30406, rev 0x10000; the
  initramfs allowlist is slot B's five images and `userdata`. Only the USB
  PHY and dwc3 are `okay`; UFS is disabled.
- **Step 2 passed.** `bin/omamobile flash` wrote the five `_b` images and
  SSH answered 7.5 s into the boot. The host saw `1d6b:0104` and gave
  `172.16.42.2/24` to the `cdc_ncm` link. Both cluster watchdogs report
  inactive. ramoops registered at `0xfd3ff000`. No oops or driver error.
  The init logs `arch: no userdata partition`, as expected with UFS off.
  The panel kept the bootloader logo.
- **Step 3 passed.** DPP0 `RDMA_BASEADDR_Y8` (`0x1c0b0040`) reads
  `0xfac00000`, the address the Pixel 7 Pro's ABL also uses. DECON0
  `TRIG_CON` (`0x1c240030`) reads `0x3070`, the hardware trigger masked,
  the value felix's ABL leaves on DECON1. The session stayed up after both.
- **Scanout geometry.** DPP0 `RDMA_SRC_SIZE` (`0x1c0b0010`) reads
  `0x09600438`, 1080 x 2400 with no stride padding, and `RDMA_IN_CTRL_0`
  (`0x1c0b0008`) reads `0xff400000`: image format 0, ARGB8888
  (`gs-decon.c`). The framebuffer node uses those values.
- **`reboot-to bootloader` did not reach fastboot** (NOTES.md); fastboot
  was reached by the buttons for the next flash.

### 2026-10-26: boot 2, the bootloader's framebuffer

Same kernel, DTB with `framebuffer@fac00000` and a `no-map` carve-out of
1080 x 2400 x 4 bytes. Flashed through fastboot; SSH 7.6 s into the boot.

- The kernel reserved `0xfac00000..0xfb5e33ff` (10125 KiB) `nomap`.
- `simpledrm` bound `chosen:framebuffer@fac00000` as minor 0: `/dev/dri/card0`
  and `/dev/fb0`, virtual size 1080,2400, stride 4320. No oops or driver
  error.
- The panel kept the bootloader logo, as expected with DECON0's hardware
  trigger still masked.

- **Trigger, by hand.** Over SSH, DECON0 `TRIG_CON` (`0x1c240030`) read
  `0x3070`, was written once with `0x3061` (unmask, `HW_TRIG_EN`) and read
  back `0x3061`. The panel switched from the bootloader logo to the Linux
  console; the session stayed up. Boot 3 moves that write into the init
  (`SIMPLEFB_TRIG_CON`).

### 2026-10-26: boot 3, the trigger in the init

Same kernel and DTB as boot 2; the descriptor sets `SIMPLEFB_TRIG_CON`
(`0x1c240030 0x3061`). Fastboot by the buttons; SSH 4.5 s into the boot.

- DECON0 `TRIG_CON` read `0x3061` with nothing written over SSH, and the
  init logged no `simplefb trigger failed`.
- simpledrm bound the framebuffer as in boot 2. No oops or driver error.
- The panel showed the Linux console after the bootloader logo, with no
  SSH step.

### 2026-10-26: boot 4, UFS behind the guard

Same kernel; DTB with `&ufs_0`, `&ufs_0_phy`, the UFS VCC and
`omamobile.ufs-probe omamobile.initramfs`. Fastboot by the buttons; SSH
7.6 s into the boot.

- **Guard passed.** 4 disks (sda 119 GiB, sdb, sdc, sdd) and 55
  partitions. `/dev/sda` removed; every partition `set read-only` except
  `boot_b`, `init_boot_b`, `vendor_boot_b`, `vendor_kernel_boot_b`,
  `dtbo_b` (sda20-24) and `userdata` (sda31), the only six with `ro=0`.
  No `FAILED` or `NOT read-only` line, and no UFS error, abort or reset in
  `dmesg`.
- **Map matches stock.** All 55 names and numbers equal stock's
  `/dev/block/by-name` (stock's four extra entries are the whole-disk
  aliases). `persist` sda1, `efs` sda5, `efs_backup` sda6,
  `modem_userdata` sda7, `modem_a` sda19, `modem_b` sda29, `devinfo` sdd1.
- The init stayed in the initramfs (`omamobile.initramfs`); `userdata` was
  not mounted or checked.

- **Seen, not acted on.** `cma: Failed to reserve 384 MiB`: this phone has
  7.3 GiB of `MemTotal` against cheetah's 11.2 GiB. The `debug@fd3f0000`
  overlap with `debug_kinfo_reserved` comes from gs201.dtsi.

### 2026-10-27: the Arch root (step 6)

Local build (contributor key, `out/panther`), boot 4's DTB without
`omamobile.initramfs`. `tools/install-phone` (the owner, phone in fastboot
by the buttons) wrote the five `_b` images and `userdata`, set slot B
active and rebooted.

- The installer only sees the current slot's bootloader; slot A's
  (`cloudripper-17.0-15902555`, the stock capture with `current-slot:a`)
  was confirmed with `--bootloader-slots-match`.
- **Handover passed.** `arch: switching to Arch Linux on /dev/sda31`, root
  ext4 grown to 109 GiB; `omamobile-firstboot` exited 0 and made the user
  (`wheel`, `video`, `input`, `audio`); SSH as root and as the user.
  Hyprland, omarchy-shell and the on-screen keyboard started, and the
  session locked as designed.
- **The guard holds in Arch.** Only sda20-24 and sda31 have `ro=0`;
  `/dev/sda` is gone, `devinfo` (sdd1) is read-only.
- **The screen went dark** 60 s after the lock: the idle cycle set DPMS
  off, and `/proc/bus/input/devices` is empty, so nothing can wake it.
  `hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'` over SSH brought
  the lock screen back, and `omarchy-toggle-idle stay-awake` (as the user)
  keeps it on until there is an input device.
- `systemd-firstboot.service` failed on the first boot (`status=208/STDIN`,
  no console), leaving the system `degraded`; omamobile-firstboot had done
  the setup. It does not run again: the next boot was `running`.
- No RTC and no network route, so the clock is wrong (the image's date)
  and unsynchronised.

### 2026-10-27: the push loop

`DEVICE=panther bin/omamobile push` with the same images: the module
tarball's checksum already matched, the five `_b` images were written and
read back equal, and `reboot-to omamobile` rebooted into slot B. SSH
answered with a new boot id 5.5 s into the boot; the system came up
`running`, with Hyprland and stay awake. The development loop no longer
needs fastboot or the buttons, as long as the new kernel reaches SSH.

### 2026-10-27: boot 5, the keys

One change, through `bin/omamobile push`: a `gpio-keys` node with cheetah's
pins, which Google's `gs201-common.dtsi` gives every gs201 board (power
`gpa10-0`, PMIC_PWRON_OD_L; volume down `gpa10-1`; volume up `gpa8-5`).
Same kernel image; SSH 5.5 s into the boot.

- `input: gpio-keys as /devices/platform/gpio-keys/input/input0`, and
  logind watches `event0`. No pinctrl error.
- Read from `event0` over SSH while the owner pressed: `KEY_VOLUMEUP` (115)
  and `KEY_VOLUMEDOWN` (114), each a press and a release.
- Power: logind logged `Power key pressed short` (and ignores it, as the
  device package configures); a press turned the screen off (DPMS 0) and
  the next one woke it (DPMS 1). The screen can now be woken without SSH.
- A buffered `od` under `timeout` loses its output: capture with
  `timeout N cat /dev/input/eventX > file`, then decode the file.

### 2026-10-27: boot 6 lost to the slot B retry budget, not to the driver

Boot 6 (the FT3658 driver built in, SPI0 and the touch node) was pushed
and never answered SSH; ABL fell back to slot A, whose stock Android went
to recovery (`reboot,recovery`: its `userdata` is now Arch). pstore was
empty there. The data reset was declined, and a fresh backup was taken
afterwards (NOTES.md, 2026-10-27).

- `devinfo` slot bytes (0x30-0x37 and the version only, read-only from
  boot 7): version **3.19** (cheetah's verified layout is 3.15); slot A
  retry 2, successful; slot B retry **2**, active, not successful, one
  boot after `fastboot --set-active=b`.
- So `--set-active` gives slot B three boots, and with nothing marking it
  successful every boot spends one: the install's boot, the push-loop
  test and boot 5 used them, and boot 6 found none left. Panther has no
  `omamobile-boot-success` (it writes `devinfo`, L-36), so until the
  layout is checked on 3.19 every reboot counts: `bin/omamobile flash`
  (it sets slot B active) restores the budget, `push` does not.
- Boot 7 (fastboot, `--set-active=b`): boot 6's DTB with the driver as a
  module and `modprobe.blacklist=focaltech_ft3658`. It booted; SPI0 probed
  (`spi0.0`, `spi:ft3658`). `modprobe focaltech_ft3658` by hand did not
  crash: the chip ID read failed (`-EBADMSG`, ID 0x00), the probe gave
  up cleanly.
- Pins, read-only: `gpp23-2` (reset) output high, out of reset;
  `gpa7-0` (interrupt) EINT, no pull, low.
- The FT3658 never drives MISO: a debug build of the module (raw response
  dump; loaded with `insmod`, no reboot) read `00` in every byte of every
  chip-ID read, in SPI mode 0 and 3, at 10 and 1 MHz. SPI0 itself is
  cheetah's configuration, which works with its S3908.
- Two suspects, neither visible from user space yet:
  - **The AP/AoC SPI select, `gph1-0`** ("Low: AP, High: AOC", Google's
    `gs201-common-touch.dtsi`). Stock asks for the bus through TBN before
    every touch reset (`tbn: AP request bus ... SUCCESS!`). `gph1` is on
    the HSI1 pin controller, which is disabled in `gs201.dtsi` (no CMU_HSI1
    driver) on both phones, so its level here is unknown. AOC2AP
    (`gpa8-7`, far-alive) reads 0.
  - **The supplies**, S2MPG12 LDO25M (1.8 V) and LDO26M (3.3 V): no PMIC
    regulator driver; cheetah's touch relies on ABL leaving them on.
- PMU registers are not read from user space (cheetah's
  RADIOS-CAMERA-PLAN.md: one `/dev/mem` read in the G3D range reset the
  phone).

### 2026-10-27: boot 8, the HSI1 pin controller

One change, through `push` (slot B's last-but-one retry): `&pinctrl_hsi1`
enabled, as cheetah's MODEM-PLAN M0.4. It registered (`gph0`, `gph1`) and
changed no pin.

- **The bus select is on the AP side.** `gph1-0`: input, DAT 0, pull-down,
  as on cheetah. Not the cause.
- SPI0 pins in their functions: `gpp20-0/1/2` function 3, `gpp20-3` (CS)
  output high.
- **ABL hands over the touch held in reset:** before any driver runs,
  `gpp23-2` is an output driven low.
- A debug module with a 10 ms reset pulse and up to 3.8 s of chip-ID reads
  still saw only zeros. With the driver, the timing, the SPI mode and
  speed, the controller and the bus select ruled out, the supplies are
  left: LDO25M (1.8 V) and LDO26M (3.3 V) of the S2MPG12, which on this
  phone ABL most likely leaves off. Reading or switching them needs the
  S2MPG12 over ACPM: the core (`CONFIG_MFD_SEC_ACPM`) reads the PMIC but
  has no regulator cell yet (cheetah's SUSPEND-PLAN.md).
