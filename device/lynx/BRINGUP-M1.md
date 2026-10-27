<!-- SPDX-License-Identifier: MIT -->
# Pixel 7a (lynx) first light

Last verified state (2026-10-27, after Arch was reinstalled from the stock
afternoon): slot B is active and marked successful by
`omamobile-device-lynx` 0.2.0. Arch runs from `userdata`, USB SSH works at
`root@172.16.42.1`, and the on-screen console works through simpledrm/fbcon.
Kernel: `7.3.0-rc6-omamobile-push1-g38b5a04d67e0`. `/sys/power/mem_sleep`
reads `s2idle [deep]`; the package's sleep drop-in keeps suspend on s2idle.
Wi-Fi is parked ([WIFI-PLAN.md](WIFI-PLAN.md)). Recheck the live state
before further hardware work.

**Stock Android on slot A is no longer a working recovery boot because
Arch owns `userdata`. Use the physical bootloader buttons for recovery.**
The first-light sections below describe earlier initramfs boots; their
original automatic fallback assumptions no longer apply to this phone.

## Facts

The stock capture and what each boot showed are in [NOTES.md](NOTES.md).
Tracking issue: #36.

## What booted at first light (historical)

The original board file (linux-omarchy-mobile, `gs201-lynx.dts`) enabled the USB
controller and relies on the SoC tree for the cluster watchdogs. UFS, the
panel, touch, the GPU and the radios stay disabled. It carries
`/soc_compatible/B0_IPOP` instead of `/soc_id`, because lynx's ABL matches
the IPOP package's DTB on that node, and `ramoops` at stock's address.

`device/lynx/device.conf` is what `bin/omamobile` reads with `DEVICE=lynx`.
It differs from cheetah's in two ways the bootloader forces:

- `SOC_COMPATIBLE="b0-ipop:0x9855:1:0:1"`: one DTB, matched on
  `/soc_compatible`.
- `AVB_FOOTERS="boot:0x4000000 init_boot:0x800000"` with stock's rollback
  index and security patch: without a footer on `boot` and `init_boot`,
  lynx's unlocked ABL never shows the orange warning and never boots slot B
  (black screen, nothing on USB, three silent retries, then slot A).

At first light, `SIMPLEFB_TRIG_CON` and `BRINGUP_PROBE` were unset. The
current descriptor enables the board-specific trigger write described in
the console section below; `BRINGUP_PROBE` remains unset.

## First boot (historical, before Arch owned userdata)

Flash only slot B, from fastboot: `DEVICE=lynx bin/omamobile images`, then
`DEVICE=lynx bin/omamobile flash`. Slot A stays stock Android. Confirm the
phone is in fastboot before every `flash` (an `adb reboot bootloader` once
did nothing), and run fastboot commands under `timeout`: they otherwise wait
forever on a phone that is not there.

Expect, in this order:

1. The orange "bootloader unlocked" warning, then a black screen that stays
   black. The bootloader logo may stay instead. Both are normal: this kernel
   does not drive the panel.
2. Within about 20 s, a USB network device on the laptop. The phone's DHCP
   server did not answer here, so give the host side `172.16.42.2/24` by
   hand (an NetworkManager profile works).
3. `ssh root@172.16.42.1` answers, from the initramfs (busybox, dropbear).
   `dmesg | grep watchdog` shows both `10060000.watchdog` and
   `10070000.watchdog` as `watchdog inactive, reset disabled`.

Stop if no USB device appears within a minute or the phone resets by itself
at about 60 s (a watchdog was left running). Do not flash again until the
cause is understood. On the current Arch installation, do not wait for a
working Android fallback; follow the physical recovery procedure below.

## How to get back

Slot B was marked successful after Arch installation. The old fallback via
three unsuccessful boots relied on Android being able to boot slot A.
With Arch on `userdata`, Android stops at recovery instead. Likewise,
`bin/omamobile fastboot` cannot complete its crash-to-Android-to-adb path.
Do not use either route as the recovery plan for this installation.

- **Fastboot by hand:** hold Volume Down and Power together, from off or
  through a force restart, until the bootloader menu appears (about 20 s).
  Never choose "Factory data reset" in that menu or Android recovery: it
  erases the Arch root on `userdata`.
- **Force restart:** hold Power for about 30 s if the phone is unresponsive.
  Use the button recovery procedure with the human present; do not keep
  sending commands to a phone that has stopped answering. An armed capture
  watchdog may recover a test hang, but recovery must be confirmed.
- **Power off:** the earlier `poweroff` test stopped the SoC but left the
  panel lit and USB absent. Use the bootloader menu's "Power off".

Only slot B's five boot images and `userdata` belong to this work. Keep the
storage guard intact. Slot A's untouched boot images do not make Android
bootable with the current userdata. Reboots and flashes still require the
human's explicit approval and physical recovery readiness.

## The on-screen console (2026-10-24)

One register write, made by the shared init at boot and only when the
board's compatible is `google,gs201-lynx`: `SIMPLEFB_TRIG_CON="0x1c240030
0x3061"`, DECON0's `TRIG_CON`, the same unmask the Pixel 7 Pro uses. It
needs the kernel's `simple-framebuffer` on ABL's scanout buffer at
`0xfac00000`, reserved by the board file (linux-omarchy-mobile #44); never
run the write on a kernel without that reservation.

Expect: `TRIG_CON` reads `0x3070` before the write and `0x3061` after (the
init logs both), fbcon comes up at 67x75 on the panel, and the boot log and
a shell prompt follow the bootloader logo. ABL replaces `console=tty0` with
`console=null`, so the init's own messages still arrive, but not a panic.

Stop if the panel goes black and stays black, shows a torn or shifted
picture, or if the phone resets right after the write. Roll back by
building and flashing slot B from a descriptor without `SIMPLEFB_TRIG_CON`;
the phone then boots as at first light, with the bootloader logo on screen.

## devinfo against fastboot (2026-10-27, `g38b5a04d67e0`, device-lynx 0.2.0)

For Derek's #88 question: lynx's bootloader is a different build from the
Pixel 7 Pro's (it needs AVB footers), so the slot bytes are checked against
what the bootloader itself reports. devinfo is `/dev/sdd1`, version 3.15 in
every reading. Only bytes 0x30-0x37 are shown (slot a 0x30-0x33, slot b
0x34-0x37), from `omamobile-bootctl dump`, next to `fastboot getvar
slot-successful`, `slot-unbootable` and `slot-retry-count` for the same
state:

| State | a: bytes | a: fastboot | b: bytes | b: fastboot |
| --- | --- | --- | --- | --- |
| B marked by `omamobile-boot-success` | `00 0a 00 00` | successful yes, unbootable no, retry 0 | `02 06 00 00` | successful yes, unbootable no, retry 2 |
| `fastboot --set-active=b`, before booting | (unchanged) | successful yes, unbootable no, retry 0 | (not readable in fastboot) | successful no, unbootable no, retry 3 |
| after one unmarked boot (`omamobile-boot-success` masked) | `00 0a 00 00` | successful yes, unbootable no, retry 0 | `02 04 00 00` | successful no, unbootable no, retry 2 |

So byte 0 is the retry count and byte 1 holds the flags, as on the
Pixel 7 Pro and Pixel 6 Pro: 0x04 active, 0x02 successful, 0x08 what the
tool calls fastboot-ok (set on slot a only here); no reading had
unbootable set. Afterwards the unit was unmasked, `fastboot
--set-active=b` and one boot left slot b at `02 04` with the bootloader's
retry spent, and the marker wrote 0x35 `04 -> 06`: `02 06 00 00` again.

A forced restart (Volume Down + Power, released too early, so it booted
slot B rather than stopping in the menu) did not spend a retry on the
marked slot: `02 06 00 00` before and after, retry 2 in fastboot.

**The first marks were made by hand, outside the storage guard's rules.**
On 2026-10-24, over SSH from the running Arch system, before the package
shipped the marker: `/dev/sdd` and `/dev/sdd1` were set writable with
`blockdev --setrw`, a trap set both back read-only on exit, and the
Pixel 7 Pro package's `omamobile-bootctl mark-successful /dev/sdd1 b
--i-understand` (copied to `/tmp`) changed byte 0x35 `04 -> 06` and
verified the block. On 2026-10-27, after the reinstall from the stock
afternoon, the root image still carried 0.1.0: 0.2.0's
`omamobile-boot-success` and `omamobile-bootctl` were copied in over SSH
and the marker was run once by hand, 0x35 `04 -> 06`, verified (slot b
`02 04 00 00` before, `02 06 00 00` after). Since then only the packaged
`omamobile-boot-success` writes devinfo.
