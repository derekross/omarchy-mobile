<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): notes

Findings from real hardware that matter beyond one subsystem, newest first.
Details are in the linked plans.

## 2026-10-27: raven boots the shared init

Raven's own `device/raven/initramfs/init` is gone; the image packs the
shared `initramfs/init` with raven's steps switched on by its descriptor
(`INITRAMFS_FB_WAIT`, `USB_SWITCH`, `SIMPLEFB_TRIG_CON`). Pushed to slot
B on kernel `7.3.0-rc6-omamobile-push1-gb3d6253b0d61`, with the same
overlays as before, so boot, dtbo and vendor_boot's DTB and command line
were byte-identical to the previous slot B and only the ramdisk changed.
The init logged the allowlist `boot_b vendor_boot_b dtbo_b userdata`
(every other partition read-only), loaded all six `INITRAMFS_MODULES`,
bound the gadget on `11110000.usb`, read `USBSW_CTRL` 0x09 (closed) and
switched to Arch; SSH answered 5 s after the reboot. Slot B stayed
successful, no failed units, and the boot check missed only `audio-card`
(speaker protection off, as on the boots before). `reboot-to bootloader`
reached fastboot (`current-slot: b`, both slots successful), so the
reboot-mode nvmem modules work from the initramfs, and `fastboot
continue` came back the same way. The early splash, checked on a second
boot the same day: the frame rendered on the phone with the build's own
`magick` command and packed through `SPLASH_BGRA_GZ` (this laptop has
neither the Omarchy theme nor ImageMagick), only the ramdisk changed
again; `fb0` (simpledrm) appeared at 0.73 s, and the human saw the logo
within about a second of the bootloader screen, before Plymouth.

## 2026-10-27: slot A holds GrapheneOS again

A GrapheneOS OTA had moved GrapheneOS 2026102100+ to slot B
(`current-slot: b`, `slot-unbootable:a: yes`), so slot B was no longer
free. The user reinstalled GrapheneOS 2026102100 with its official
`flash-all.sh` (signature verified): it forces slot A, writes the
bootloader to both slots (`slider-17.0-15681480`, unchanged), the radio
to slot A only (`g5123b-145971-260721-B-15910359`, `modem_a` unchanged by
checksum), and erases `userdata`. After one GrapheneOS boot:
`current-slot: a`, `slot-successful:a: yes`, `slot-unbootable:a: no`.
None of our tools wrote slot A; they only write `_b`. GrapheneOS and
Omarchy share the one `userdata`, so slot A is a bootloader-level way
back, not a dual boot. Before any slot B plan, read the slot variables
first: OTAs move GrapheneOS to the other slot. NV baseline after the last
GrapheneOS boot: `~/android/reference/raven-backup-2026-10-27b` (efs,
efs_backup, modem_userdata and persist changed; modem_a/b unchanged).

## 2026-10-20: reinstalled after GrapheneOS

Slot B and userdata reinstalled with `tools/install-phone` (kernel
`g6efb2b9205c1`, the 10-17 root image). Raven's ABL reports only the
current slot's bootloader, and GrapheneOS had left slot A current and B
marked unbootable, so slot B's was read by `fastboot --set-active=b` and
`reboot-bootloader`: the same `slider-17.0-15681480` as slot A. The
user's 10-17 profile backup (firmware, vendor trees, `/etc/omamobile`,
saved connections, home) replaced `tools/phone-provision`; after one
reboot every boot check passes except `bluetooth-address` (hci0's setup
failed four times early in boot; the controller powered up later). Fresh
NV backup: `~/android/reference/raven-backup-2026-10-20` (MODEM-PLAN
section 1). The laptop saw no USB device at all until the cable or port
was swapped, then the link flapped for a minute: suspect the cable first.

## 2026-10-20: kernel branch layout

The phone runs `omamobile-gs101-int` (was `-cpif`; it contains the old
`-merge-test`). Upstream PRs come from one-subsystem branches off
`omamobile`: `-boot` (glue only; the USB peripheral setup was dropped in
review) and `-gpu-pr` are open. `-thermal` is rebased on the new `-boot`
and also carries the 75/85 °C CPU trips and the 115 °C critical trips;
`-gpu-dvfs` (on `-gpu-pr`, stacked on `-thermal`) carries GPU devfreq
through ACPM and GPU cooling. All the other subsystem branches are
rebased on the new `-boot` too. Upstream now has cheetah's gs-decon and
LM3644 driver, so `-display` lost its import and `-torch`'s driver commit
is a help-text line; `-aoc` and `-wifi` still carry NOT FOR MERGE imports.
The CPIF and PCIe commits still live only on `-int`.

## 2026-10-17

- **First real install on raven (2026-10-17):** `tools/install-phone --device raven` with the raven root image and slot B's images from 7.3.0-rc6-omamobile-push1-g6efb2b9205c1. The first userdata flash stopped at sparse chunk 24/34 (`reap_urb ... Protocol error`, USB); a rerun completed. First boot created the account and finished in about a minute. **Gaps:** the image has no Google files, and `tools/phone-provision` only extracts cheetah's (no `-d raven`), so the first boot had no Wi-Fi, Bluetooth, AoC, audio or sensors (boot check: 10 FAILs). Restoring a backup of the phone's own Google files and /etc/omamobile, then a reboot, brought everything up (boot check ok). The user profile (~/ minus caches) restored on top, with ownership remapped (uid 1001 -> 1000). `omamobile-modem-sit` and `omamobile-mmd` aren't in the image (rootfs/packages.omamobile): installed afterwards. To do: phone-provision for raven.
- **The installer works for raven (2026-10-17):** `tools/install-phone --dry-run --device raven` with the raven root image (`tools/build-rootfs`, DEVICE=raven) and slot B's images: product raven, unlocked, current slot b, first-boot answers written into a local copy, and exactly six commands (boot_b, vendor_boot_b, dtbo_b, userdata, set-active b, reboot). Raven's ABL reports only the current slot's bootloader; the installer now accepts that when the current slot is already b (activating b switches nothing). The root image passes tests/rootfs-smoke. A real install erases userdata: not done.
- **Boot splash (2026-10-17, 7.3.0-rc6-omamobile-push1-g6efb2b9205c1):** raven's ABL drops every `console=` we pass and appends `console=null`, so `/proc/consoles` is empty and plymouthd 26.134 segfaulted at every boot (`kernel_console_is_ttynull()` strcmps a NULL). `plymouth.graphical` skips that check. Plymouth then hung on quit (no fbdev console to hand back to) and held `graphical.target`, so the session started at 97 s, until `plymouth quit --retain-splash` as on cheetah (device-raven 0.1.13). The initramfs logo was missing (the build host had no Omarchy theme; `SPLASH_BGRA_GZ`) and raced simpledrm's fb0 by 3 ms (init now waits). Now: ABL logo, Omarchy logo, Plymouth, Hyprland at 21.5 s, no text. `plymouth.debug` prints its log on the screen: don't leave it on.
- **`boot.img` with an empty generic ramdisk boots too** (2026-10-17, 7.3.0-rc6-omamobile-push1-g6efb2b9205c1): `main`'s images step (#5) packs the 512-byte empty cpio into `boot.img`; ours had no ramdisk there. Rebuilt only `boot.img` that way and pushed it: initramfs unpacked, SSH at 8.6 s, boot check ok. Raven can use #5's layout unchanged. Backup of the no-ramdisk images: `out-gs101-cpif/images-g6efb2b9205c1-noramdisk`.

## 2026-10-16: reading GSA's pin controller aborts

A read of every pin controller's state (`/sys/kernel/debug/pinctrl/*/pins`)
hung raven once; the watchdog reset it about 40 s later. One controller at
a time showed why: `17940000` (`pinctrl_gsactrl`, the GSA's, secure)
raises a synchronous external abort. Every other controller, HSI1
included, reads cleanly ([MODEM-PLAN](MODEM-PLAN.md) section 3).
## 2026-10-15

- **The torch works** (`omamobile-gs101-torch`, kernel `gd2521ee96675`):
  raven's rear flash LED is an LM3644TT (ID 0x04) at `0x63` on I2C 7 (USI7,
  370 kHz), HWEN gpp23-6, driven by cheetah's torch-only `leds-lm3644`:
  `white:torch`, 17 steps of 2.55-49 mA per channel; the shell's torch tile
  drives it through brightnessctl. Strobe (gpp27-0) is left alone.
- **Sound and sensors on a fresh install:** kernel `omamobile-gs101-merge-test`
  built with `DEVICE=raven` (bin/omamobile defaults to cheetah: no raven
  kernel.config, cheetah's overlays) and `DTB_OVERLAYS="aoc-boot-test
  aoc-sound-test audio-amps-test"`; the packages omamobile-device-raven
  (0.1.5+), omamobile-audio (0.4.4+) and omamobile-sensors; then
  `tools/phone-provision -d raven FACTORY.zip` (firmware, the AoC sensor
  registry, and the sensor proxy and speaker protection enabled).
  [AUDIO-PLAN](AUDIO-PLAN.md)
- **BLK_AOC's power domain is off at hand-off** although `aoc_req` reads
  acknowledged: every BLK_AOC register (and EL3's DTZPC SMC) then aborts or
  hangs. The PMU's `AOC_STATUS` (`0x1884`) is the truth; aoc_core now runs
  Google's `blkpwr_aoc` on sequence first. [AUDIO-PLAN](AUDIO-PLAN.md) R2
- **A boot burst can trip the 110 C critical trip** on a phone that already
  idles warm: the big cluster went from 51 to over 110 C in six seconds as
  the UI started, and the kernel powered the phone off. A 95 C trip now
  throttles deep at once (`omamobile-gs101-thermal`).
- **simpledrm probed after gs-decon** and stayed as a phantom second monitor;
  gs-decon now holds the framebuffer's aperture. [DISPLAY-PLAN](DISPLAY-PLAN.md)
- Moving the laptop dropped the USB link once (the phone stayed up); a
  replug brought it back.

- **Never list `/sys/kernel/debug/pinctrl/*/pins` or `pinconf-pins` for
  every controller at once on gs101.** GSA's pin controller (`17940000`)
  belongs to the secure world and aborts the SoC on a read, and the reader
  dies holding the bank's lock: reboot after one. Read the one controller
  you need instead; every other one reads cleanly (AGENTS.md, 2026-10-16
  below, [MODEM-PLAN](MODEM-PLAN.md) section 3).
- **The panel rails belong to the simple-framebuffer node.** vci (ldo22m)
  and vddi (bucka) are held by `chosen:framebuffer-0`; removing simpledrm
  for gs-decon released them and the panel went dark. They are now
  always-on in the DT. [DISPLAY-PLAN](DISPLAY-PLAN.md) D3
- **An Android boot on slot A changes the calibration partitions.** Four
  of them (`efs`, `efs_backup`, `modem_userdata`, `persist`) differed after
  one boot of slot A's Android, as on cheetah: take a fresh read-only
  backup after every Android boot, before radio, PMIC, AoC or Trusty work.
  [AUDIO-PLAN](AUDIO-PLAN.md)
- **Idle power:** about 460 mA with the screen off, from 610 mA, mostly
  from MIF at 1014 MHz, unused power domains off and DECON's trigger masked
  while dark. [POWER-PLAN](POWER-PLAN.md)

## 2026-10-14

- **Mali-G78 needs AArch64 page tables in panfrost.** With the legacy LPAE
  format every fragment job faulted (`DATA_INVALID_FAULT`); every G57 SoC
  entry already forces AArch64. [GPU-PLAN](GPU-PLAN.md)
- **Slot B falls back to slot A unless something marks it successful.**
  ABL spends a retry on every boot, resets and held power keys included.
  Raven's `devinfo` has cheetah's layout (`DEVI` 3.15), so
  `omamobile-boot-success` works unchanged. [BRINGUP-M1](BRINGUP-M1.md) §7
- **ABL reads the reboot reason from the MAX77759's nvmem.** Without
  `max77759`, `nvmem-max77759` and `nvmem-reboot-mode` loaded,
  `reboot-to bootloader` boots slot B again. The initramfs loads them first
  (`INITRAMFS_MODULES`), never the charger. [BRINGUP-M1](BRINGUP-M1.md) §7
- **The simple-framebuffer waits for PMIC rails**, so the screen console
  needs `exynos-mailbox`, `acpm-protocol` and `sec-acpm` in the initramfs
  too. [BRINGUP-M1](BRINGUP-M1.md) §7
- **Raven's ABL leaves both cluster watchdogs off** (cheetah's leaves them
  running). [BRINGUP-M1](BRINGUP-M1.md) R3
- **The MAX77759 opens the USB2 data switch on unplug**, as on cheetah: the
  initramfs closes it until switch_root, `omamobile-usb-rescue` after.
  [BRINGUP-M1](BRINGUP-M1.md) §7
- **The touch controller (S6SY79x on SPI 11) needs care:** its reset is
  active-low, a reply can arrive on the second read frame, its interface
  dozes after 1-2 ms of silence, and at boot it answers only after a power
  cycle. [BRINGUP-M1](BRINGUP-M1.md) §7
- **Create the user account under its final name.** Renaming it after the
  first login broke the theme's background symlinks (absolute paths into
  the old home). [BRINGUP-M1](BRINGUP-M1.md) §7
- **GrapheneOS on slot A keeps USB data off while the phone is locked**, so
  the laptop's USB log can't time a fallback to slot A.
