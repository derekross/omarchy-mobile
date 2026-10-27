<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven) M1: first light

Status (2026-10-15): **M1 and M2 done: Omarchy with the mobile shell runs
from slot B on our own kernel, from `userdata`, and slot B is marked
successful at every boot.** Kernel branches `omamobile-gs101-boot`,
`-touch`, `-gpu`, `-thermal`, `-power`, `-bluetooth`, `-wifi`, `-display`
and `-aoc` on linux-omarchy-mobile, one subsystem each, all off
`omamobile-gs101-boot` (which is off `omamobile`). They replace the stacked
bring-up branches (`omamobile-raven-dts` ... `-aoc`) that the commit hashes
in the results below come from. Slot A holds GrapheneOS (reinstalled 2026-10-27, NOTES); it is a
bootloader-level way back only, since it shares `userdata` with Omarchy
and can't boot without wiping it. Slot B is ours. Later stages have their own
plans: [GPU](GPU-PLAN.md), [Wi-Fi](WIFI-PLAN.md),
[display](DISPLAY-PLAN.md), [Bluetooth](BLUETOOTH-PLAN.md),
[power and thermal](POWER-PLAN.md), [audio](AUDIO-PLAN.md); cross-cutting
findings in [NOTES](NOTES.md).

## 1. Goal

Our kernel boots from slot B and answers `ssh root@172.16.42.1` over USB, and
stays up past the watchdog window. Nothing else: the screen keeps the
bootloader's last frame (no display trigger yet), and init never touches
`userdata` (`omamobile.initramfs` on the command line).

Then, while it is up: capture what stock root would have given us (the live
DT, `/proc/iomem`) and take the read-only backup of the calibration
partitions.

## 2. Facts

`R/` is `~/android/reference/raven-stock`, `F/` the factory image
`~/android/reference/factory/raven-img` (CP3A.261005.002.A1), `L/` our kernel
tree.

| Fact | Evidence |
| --- | --- |
| Boot partitions: `boot`, `vendor_boot`, `dtbo` (64, 64 and 16 MiB) in both slots; no `init_boot` or `vendor_kernel_boot` [V] | `R/partitions-by-name.txt`, `R/fastboot-getvar-all.txt` |
| Slot B, `userdata` and the calibration partitions (`efs`, `efs_backup`, `modem_userdata`, `persist`, `modem_a/b`) are on `sda`; `devinfo` on `sdd` [V] | `R/partitions-by-name.txt` |
| Base DTB `soc_id`s 0x9845000 and 0x9845001; vendor_boot page size 0x800, header v4 [V] | `F/vendor_boot.img` (unpack_bootimg) |
| `ro.boot.dtbo_idx` 6 = "Raven DVT", board_id 0x20204, board_rev 0x10000 [V] | `R/getprop.txt`, `F/dtbo.img` entry 6 |
| The factory `boot.img` sets no OS version or patch level [V] | `F/boot.img` |
| Upstream raven already has `/chosen/bootargs`, `/ect`, `simple-framebuffer` at 0xfac00000 (1440x3120), UFS, USB (dwc3 in peripheral mode by default) and `watchdog_cl0` [V] | `L/arch/arm64/boot/dts/exynos/google/gs101-*.dts*` |
| ABL leaves both cluster watchdogs running [I] (true on cheetah; `watchdog_cl1` now enabled too) | cheetah BRINGUP-M1 |
| Raven's DECON trigger counterpart of cheetah's 0x1c240030 is 0x1c300030 [I] (pmOS, issue #2): not used | |

## 3. What was built

| Where | Change |
| --- | --- |
| kernel `a045965f9` | `gs101-raven.dts`: `soc_id`, bootargs (`panic=10`, `omamobile.initramfs`), dpm node and label stubs, `watchdog_cl1`; `-@` |
| `bin/omamobile` | `images`/`flash` follow `BOOT_IMAGES`: on raven, `vendor_boot` carries the DTB and the initramfs |
| `device/raven/` | descriptor, empty board overlay, init without cheetah's gs201 register access |

## 4. Risks

- **What we write:** only `boot_b`, `vendor_boot_b` and `dtbo_b`, through
  `bin/omamobile flash`, which refuses anything off the allowlist and never
  activates slot B after a failed write. Slot A (Android) is untouched.
- **A silent failure:** ABL sets `console=null` and the screen is frozen, so a
  boot that never reaches USB shows nothing. `panic=10` reboots on a panic;
  init crashes the phone itself if no USB host configures the gadget within
  45 s. Either way ABL retries slot B, then falls back to slot A.
- **GrapheneOS updates install into slot B** and would overwrite our images
  and switch slots. Keep slot A offline.

## 5. Runbook

Each step: the human runs or approves it. Stop at the first failed Pass.

**R0. Offline image checks** (laptop, no phone; risk: none)

```sh
KERNEL_OUT=~/android/mainline/out-raven DEVICE=raven bin/omamobile images
```

Pass: `boot.img`, `vendor_boot.img`, `dtbo.img` built; `vendor_boot` holds
`dtb.img` (two DTBs, `soc_id` 0x9845001 then 0x9845000) and the initramfs;
the DTB has `/chosen/bootargs`, `/ect`, `/dpm`, `__symbols__`; `dtbo.img`
carries 0x20204/0x10000.

**R1. Slot A works** (phone; risk: none)

Boot GrapheneOS once from the bootloader (`fastboot reboot`), offline. Then
back to fastboot: `adb reboot bootloader`, or Volume Down + Power.
Pass: `fastboot getvar current-slot` is `a`, `unlocked` is `yes`.
Stop: slot A doesn't boot. Don't flash anything; ask.

**R2. Flash slot B and boot it** (phone in fastboot; risk: low, writes slot B only)

```sh
KERNEL_OUT=~/android/mainline/out-raven DEVICE=raven bin/omamobile flash
```

Expect: three `OKAY`s, the unlocked-bootloader warning, then the Google logo
stays. Within about 30 s the laptop sees a USB device "Omarchy Mobile /
Pixel 6 Pro": a network interface (the laptop sets 172.16.42.2/24 itself,
CONTRIBUTING.md section 2: the initramfs runs no DHCP server) and
`/dev/ttyACM0`.

Pass: `tools/phone-ssh 'uname -r; cat /proc/uptime'` answers.
Fallback console: `screen /dev/ttyACM0 115200` (or `picocom`).
Stop: no USB device after 3 minutes, or a reboot loop.
Rollback: Volume Down + Power held about 20 s for fastboot, then
`fastboot --set-active=a && fastboot reboot`.

**R3. Stays up** (read-only; risk: none)

Wait until uptime passes 120 s.
Pass: still answering; `dmesg | grep -i wdt` shows both watchdogs taken
over; `dmesg | grep ufs-ro` shows every partition but the allowlist set
read-only and `/dev/sda` removed.
Stop: a reset at about 60 s (a watchdog nobody feeds).

**R4. Capture** (read-only; risk: none)

```sh
mkdir -p ~/android/reference/raven-m1
tools/phone-ssh 'cat /sys/firmware/fdt' > ~/android/reference/raven-m1/live.dtb
tools/phone-ssh 'dmesg; cat /proc/iomem /proc/interrupts' > ~/android/reference/raven-m1/m1.txt
```

Then check every `reserved-memory` node of the live DT against
`/proc/iomem` (AGENTS.md: firmware writing into RAM we think is free).

**R5. Calibration backup** (read-only; risk: low)

Read `efs`, `efs_backup`, `modem_userdata`, `persist`, `modem_a` and `modem_b`
(found by `PARTNAME` in `/sys/class/block/*/uevent`) with `cat` over SSH
into `~/android/reference/raven-backup/`, with their SHA-256s. Never write
them. Never commit them.

## 6. After M1

1. Display trigger (read the candidate register once, while the panel is
   known on), so the console shows on screen.
2. Arch root on `userdata` (drops `omamobile.initramfs`).
3. Touch, buttons, then the GPU (Mali-G78: Panfrost, not Panthor).

## 7. Results

**2026-10-14, kernel 7.3.0-rc6-omamobile-push1-gcb50dd686ccc-dirty
(`omamobile-raven-dts` plus its uncommitted USB change).**

- **Tries 1 and 2 (R2):** flashed fine; slot B ran out of its two retries
  and ABL fell back to slot A. The Google logo stayed about a minute or
  more each time, and the laptop saw no USB device at all. Try 2 switched
  dwc3 to plain USB 2 peripheral mode; no change.
- **Crash test:** the same kernel and DTB with an init that crashes at once
  (`echo c > /proc/sysrq-trigger`, `panic=10`). Still a minute or more per
  try, so the kernel never reached init: an early hang, then the watchdog
  ABL leaves running.
- **Try 3:** the crash test without `earlycon=exynos4210,0x10A00000` on the
  vendor_boot command line. Fast reboot loop, then slot A: **the kernel
  reaches init.** Unlike cheetah's, raven's ABL passes the vendor_boot
  command line on (the stock one carries real arguments), and earlycon's
  writes to the unclocked UART hung the SoC before any console existed.
  Never put `earlycon` on raven's command line without the debug UART
  enabled (`fastboot oem uart enable`, untested).
- **Try 4:** the real init with the USB 2 peripheral DT. Each slot B try
  lasted over a minute (init's 45 s USB wait, then its crash); the laptop
  saw no USB device at all.
- **Try 5:** adds postmarketOS's DECON trigger (`devmem 0x1c300030 0x3061`,
  from pmaports `soc-google-gs101/00-enable-fb.sh`), `fbcon=font:TER16x32`,
  `regulator_ignore_unused` (pmaports `device-google-raven`) and a 120 s
  error screen. The logo stayed about 2.5 minutes per try: init runs and
  reaches its "USB never configured" branch, but no console reached the
  screen and still no USB device. Every USB piece (dwc3-exynos glue, the
  usbdrd PHY, configfs NCM/ACM) is built in.
- **Next:** pmOS's own gs101 kernel (gs101-mainline/linux d28cfa4275b9,
  7.0.6, pmaports config plus `USB_CONFIGFS=y`, `FONT_TER16x32`,
  `BOOT_CONFIG`) and its unmodified raven DT, with our initramfs: a
  known-good reference that splits "our kernel tree" from "our init and
  packaging".
- **Tries 6-13: first light, with pmOS's kernel** (gs101-mainline/linux
  d28cfa4275b9, `7.0.6-gs101`, pmaports config plus `USB_CONFIGFS=y`,
  `FONT_TER16x32`, `BOOT_CONFIG`) and our initramfs:
  - pmOS's kernel shows a console on screen with the DECON trigger; ours
    did not (not yet understood). The screen became the debug channel.
  - The MAX77759 USB data switch (`USBSW_CTRL` 0x93) already reads 0x09
    (closed) at handoff. CC status 0x14 (attached on CC2), power status
    0x0d (VBUS present).
  - With upstream's DT, dwc3 runs dual-role at super-speed-plus, its SS
    link stays `SS.Disabled`, and USB 2 never connects.
  - `dr_mode = "peripheral"` without `usb-role-switch` makes dwc3 defer
    forever: "failed to get extcon", found through the **PHY's** port
    graph to the TCPC. Keeping `usb-role-switch` skips that lookup.
  - Then dwc3 runs (Run/Stop set, HS) but its link stays `Disconnected`:
    with `orientation-switch` on the PHY, phy-exynos5-usbdrd only forces
    `UTMI_FORCE_VBUSVALID | UTMI_FORCE_BVALID` when a TCPC reports an
    orientation. Dropping `orientation-switch` makes it force them at init.
  - **Try 13 enumerates:** CDC NCM and ACM on the laptop, SSH at
    172.16.42.1 (the laptop needs a static 172.16.42.2/24: Alpine's
    BusyBox has no `udhcpd`).
- **R3:** up past 180 s, no watchdog reset (`watchdog_cl0` reports
  "inactive": raven's ABL leaves it off). The storage guard set 48
  partitions read-only, left exactly `boot_b`, `vendor_boot_b`, `dtbo_b`
  and `userdata` writable, removed `/dev/sda`, and `sdb`-`sdd` are ro.
- **R4:** live DT, dmesg, `/proc/iomem` and interrupts saved to
  `~/android/reference/raven-m1/` (private).
- **R5:** `efs`, `efs_backup`, `modem_userdata`, `persist`, `modem_a` and
  `modem_b` read (all ro=1) into `~/android/reference/raven-backup/`, each
  matching its on-phone SHA-256.
- **Try 14: our own kernel** (`7.3.0-rc6-omamobile-push1-ga045965f9e7e`)
  with the same DT fixes: SSH 8.8 s after boot. Both cluster watchdogs
  report "inactive" (raven's ABL leaves them off). No console on screen:
  `chosen:framebuffer-0` defers on its `vci`/`vddi` supplies (S2MPG10/11
  rails), and the PMIC driver (`sec-acpm`, over `acpm-protocol` and
  `exynos-mailbox`) is a module in the shared config. Loading the three by
  hand registered 72 regulators, set the clock from the PMIC RTC and
  brought up simpledrm and fbcon (90x97, Terminus 16x32).
- **Reboot to fastboot:** ABL reads the reboot reason from the MAX77759's
  nvmem (`nvmem-reboot-mode` on `maxim,max77759-nvmem`). With
  `max77759`, `nvmem-max77759` and `nvmem-reboot-mode` loaded,
  `reboot-to bootloader` reaches fastboot in about 8 s; without them ABL
  boots slot B again. `max77759_charger` is never loaded (no power supply
  registered).
- **Try 16:** the descriptor's new `INITRAMFS_MODULES` carries those six
  modules and the init loads them first. Everything comes up unattended:
  SSH at 8.8 s, the screen console, 72 regulators, reboot to fastboot and
  `fastboot reboot` back to SSH 4.8 s after boot. **M1 is done.**
- **M2, Arch root (2026-10-14):** the human ran `tools/raven-install-alarm` (since removed: `tools/install-phone` installs raven)
  with the official Arch Linux ARM aarch64 tarball (GPG-verified, Arch
  Linux ARM Build System key 68B3537F39A313B3E574D06777193F152BDBE6A6):
  `userdata` (sda27) formatted ext4 `omamobile-root`, the root unpacked,
  networkd on `usb0` (172.16.42.1), `sshd` with the laptop's key, a serial
  getty on `ttyGS0`, no modules for our kernel (so udev loads nothing).
  With `omamobile.initramfs` dropped from `bootargs`, init switched to
  systemd: `systemctl is-system-running` reports `running`, no failed
  units, SSH 9.9 s after boot, the screen console still up.
- **Modules in Arch:** the kernel rebuilt at the committed tree
  (`7.3.0-rc6-omamobile-push1-gac82e61d2b0a`) with its module set installed
  by `omamobile modules-push`, and `omamobile-raven.conf` (now in `omamobile-device-raven`)
  in `/etc/modprobe.d` first (no `max77759_charger`, `tcpci_maxim`,
  `gpio_max77759` or `panfrost`). udev loaded only `clk_acpm`, `at24`,
  `cfg80211`, `rfkill`, `arm_dsu_pmu`, `fuse` and the `max17042_battery`
  fuel gauge: 99 %, 4329 mV, 22.0 °C. Still `running`, no failed units.
  From Arch, `systemctl reboot --reboot-argument=bootloader` reaches
  fastboot (the reboot-mode modules stay loaded after switch_root).
- **USB across unplugs:** after the phone was unplugged in Arch, the link
  never came back (the MAX77759 opens its USB2 data switch on unplug, and
  the initramfs loop that closed it ends at switch_root). Arch now runs
  `omamobile-usb-rescue` (now in `omamobile-device-raven`): while TCPCI POWER_STATUS
  (0x1e) reports VBUS, it puts USBSW_CTRL (0x93) back to 0x09, through
  `omamobile-i2c` (`omamobile-device-raven/src`, static, because the base root has
  no i2c-tools). Installed from an initramfs-mode boot (`omamobile.initramfs`
  on the vendor_boot command line); active at boot, `running`.
- **Omarchy installed (2026-10-14):** `[omarchy]` edge ahead of Arch Linux
  ARM's repositories, Omarchy's key from its own `omarchy-update-keyring`
  (40DFB630FF42BCFFB047046CF0134EE680CAC571), Omarchy's
  `omarchy-base.packages` plus `omarchy-aarch64.packages` and the image's
  `packages.base`, minus `packages.omarchy-skip`: Omarchy 4.0.4, Hyprland
  0.56.2, Mesa 26.2.4. Not on aarch64: `dotnet-runtime`, `iptables-nft`,
  `nvim`, `vi`. NetworkManager and sddm stay disabled (networkd owns usb0;
  NM is told to leave usb0 unmanaged). `plymouth-start` fails without
  `splash` on the command line (harmless).
- **Omarchy on screen (2026-10-14):** user `user` from Omarchy's
  `/etc/skel` (no password yet, SDDM autologin to `hyprland-uwsm`), the
  Arch Linux ARM `alarm` account removed and root's password locked (root
  keeps SSH with the laptop's key). Hyprland 0.56.2 runs on simpledrm with
  software rendering: `Unknown-1`, 1440x3120@60. Omarchy's `"auto"` scale
  chose 1 for the unidentified panel; `omarchy_monitor_scale = 3` (480
  logical px, as cheetah). SDDM enabled at boot. No touch and no GPU yet.
  Without touch the session sits idle, so Omarchy's screensaver starts;
  stay-awake (`omarchy-toggle-idle`) is on for bring-up. Renaming the
  account after its first login broke the theme's background symlinks
  (absolute paths into the old home): create the account under its final
  name.
- **Touch (2026-10-14):** a Samsung S6SY79x on SPI 11, through upstream's
  `s6sy761` with a new SPI transport (`omamobile-raven-dts`), from Google's
  GPL `sec_ts` and device trees. What it took, found on the phone:
  - the reset is **active-low** (sec_ts drives it 0 until powered, then
    1, 0, 1); described active-high, the controller stayed in reset and
    answered zeros;
  - the reply to a read can come on the **second** read frame: without
    reading the frame again, exactly every other read failed (a TS_STATUS
    self-test showed `.O.O.O.O…`; CS setup/hold/recovery delays, padding
    and the controller's power mode changed nothing) and touch reports
    stopped after the first;
  - after about 1-2 ms of silence its interface dozes: retries, a wake
    read before writes, and a SENSE_ON checked through TS_STATUS (system
    mode 2, touch);
  - at boot its rails are still on from the bootloader and it does not
    answer until power cycled: the driver now does that on a failed first
    init.
  Device ID 0x3792. Continuous multi-touch coordinates at about one report
  per 10-15 ms on a drag; loads at boot (s6sy761 no longer blacklisted).
  Plugged into a laptop, the controller reports frequency hopping (noise)
  status events: the charger-mode command sec_ts sends is not implemented.
- **Mobile shell (2026-10-14):** `neard`, `omamobile-omarchy` (all 13
  patches applied to Omarchy 4.0.4), `omamobile-apps` and `omamobile-shell`
  0.1.51 built on the phone with `tools/phone-install-package`, then
  `omamobile-setup-user` and a shell restart: the phone profile (status
  bar, home, launcher, quick settings, switcher, keyboard) runs on raven.
  Without a GPU it was slow; Hyprland blur, shadows and animations off
  (in the user's `looknfeel.lua`) and the performance governor
  (now `omamobile-device-raven`'s tmpfiles.d) made it usable.
- Note: run `reboot-to` by full path (`/usr/local/bin`) and detached
  (`setsid`): dropbear's sessions have no `/usr/local/bin` in `PATH` and
  kill a plain background job when the session closes.
- Note: GrapheneOS keeps the USB data line off while the phone is locked,
  so the laptop's USB log can't time a fallback to slot A.

- **Slot B falling back to GrapheneOS:** nothing marked slot B good, so ABL
  spent a retry on every boot (reboots, resets and held power keys alike)
  and switched to slot A at 0; GrapheneOS then fails on our ext4 userdata
  and lands in recovery or fastboot. `fastboot --set-active=b` gives 3
  tries. Fixed with cheetah's `omamobile-boot-success` (raven's devinfo has
  the same layout, `DEVI` 3.15; first mark by hand: byte 0x35 04 -> 06,
  verified).

GPU results: [GPU-PLAN](GPU-PLAN.md). Thermal: [POWER-PLAN](POWER-PLAN.md).

## devinfo against fastboot (2026-10-27, `gb3d6253b0d61`, device-raven 0.1.23)

For Derek's #41 question, whether `DEVI` 3.15's slot bytes mean on gs101
what they mean on gs201. Raven's devinfo is `/dev/sdd1` (`PARTNAME`
devinfo); version 3.15 in every reading. Only bytes 0x30-0x37 are shown
(slot a 0x30-0x33, slot b 0x34-0x37), from `omamobile-bootctl dump`,
next to `fastboot getvar slot-successful/unbootable/retry-count` for the
same state:

| State | a: bytes | a: fastboot | b: bytes | b: fastboot |
| --- | --- | --- | --- | --- |
| B marked by `omamobile-boot-success` | `02 0a 00 00` | successful yes, unbootable no, retry 2 | `02 06 00 00` | successful yes, unbootable no, retry 2 |
| `fastboot --set-active=b`, before booting | (unchanged) | successful yes, unbootable no, retry 2 | (not readable in fastboot) | successful no, unbootable no, retry 3 |
| after one unmarked boot (`omamobile-boot-success` masked) | `02 0a 00 00` | successful yes, unbootable no, retry 2 | `02 04 00 00` | successful no, unbootable no, retry 2 |

The same unmarked state also appears in the first boot after today's
install (`02 04`, retry 2, logged by `omamobile-boot-success` before it
marked). So byte 0 is the retry count and byte 1 holds the flags:
0x04 active, 0x02 successful, 0x08 what the tool calls fastboot-ok; no
reading had unbootable set. The next boot, after a `reboot-to
bootloader` and `fastboot reboot`, read `01 0c`: the bootloader had spent
another retry and set 0x08 on slot b (slot a has it too); the mark then
wrote 0x35 `0c -> 0e`. After the test the service was unmasked and slot b
is marked again.

**The first mark (2026-10-14)** was written by hand over SSH from the
running Arch system, before `omamobile-boot-success` was enabled on raven:
`/dev/sdd` and `/dev/sdd1` were set writable with `blockdev --setrw`, a
trap set both back read-only on exit, and `omamobile-bootctl
mark-successful /dev/sdd1 b --i-understand` changed byte 0x35 `04 -> 06`
and verified the block; the dump afterwards showed `ro=1` again. That
`--setrw` was outside the storage guard's rules; since then only
`omamobile-boot-success` writes devinfo.
