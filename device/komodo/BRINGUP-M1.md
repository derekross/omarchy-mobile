<!-- SPDX-License-Identifier: MIT -->
# Pixel 9 Pro XL (komodo): first-light plan

**Status — 2026-11-20:** this is an experimental **native Omarchy Mobile** port
(Arch Linux ARM, Hyprland, mainline Linux), not Omarchy-in-Termux/PRoot. The
Pixel 9 Pro XL (`komodo`) is not a supported installer target. Omarchy boots
from slot B into a usable 1344x2992 GUI; USB SSH/internet, touch input, flip-only
KMS and the Mali-G715 Panthor render node have all been observed working on a
local integration build. The exact signed kernel PR head has been rebuilt but
not yet boot-smoked on hardware. This PR includes the watchdog-guarded GPU
package and its offline test; it remains experimental and needs maintainer
review before release. Idle CPU
samples improved after hardware rendering was enabled, but this was not a
controlled benchmark. Internal Wi-Fi is not working: its PCI host enumerates,
but the first `bcmdhd` probe failed coherent DMA allocation and oopsed in its
error path. A corrected shared-DMA-pool configuration has not yet been
verified with the driver. Local synthetic notifications appear in both the
logged-in session and on the lock screen; whether they wake the display is
unverified. WhatsApp is not linked and no real messages were read. See
[NOTES.md](NOTES.md) for evidence and chronology. The owner authorized
experimental writes to slot B and
`userdata`; slot A and firmware/calibration partitions remain untouched. No
personal content was queried. Current kernel worktree:
`~/dev/omamobile-kernel/wt-komodo-m3`; matching build outputs are under
`~/dev/omamobile-kernel/out-komodo-*`.

## 1. Goal

Get a usable Omarchy Mobile system booting on this Pixel as quickly as
possible. The owner has explicitly made phone data disposable and does not
want stock recovery or a separate recovery runbook treated as gates. Move
directly from the now-working USB rescue and DECON/KMS handoff to a local
rootfs install, then bring up the minimum input and network needed to use it.
Do not wait for a complete KM4 panel port, 120 Hz, or every peripheral before
booting userspace. Continue to keep all persistent writes inside the project's
supported slot-B and userdata install paths.

## 2. Evidence and source paths

- `R/` — private, owner-only read-only capture at
  `~/android/reference/komodo-stock/`; never commit raw captures.
- `G/` — public Google GPL reference checkout at
  `~/dev/omamobile-kernel/google-caimito`, branch
  `android-gs-caimito-6.1-android16`, commit `38a058681d6c`.
  Public sources: [`zumapro-komodo-mp.dts`](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/dts/zumapro-komodo-mp.dts)
  and [`constants.bzl`](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/constants.bzl).
- `L/` — `linux-omarchy-mobile`, branch `omamobile`, commit `26867fc4e826`.

### Verified facts

- **[V]** Pixel 9 Pro XL, codename `komodo`, SoC platform `zumapro`, hardware
  revision `MP1.0`. Initial capture was Android 17 build `CP3A.261005.005`,
  kernel `6.1.162-android14-11`; a targeted read after the stock update
  confirmed Android 17 build `CP4A.261105.040.A1`, kernel
  `6.1.172-android14-11`, slot A, and `dtbo_idx=34`. (R/ `getprop.txt`,
  `kernel-version.txt`, `post-update-targeted.txt`.)
- **[V]** A second targeted read reports `ro.boot.hw.soc.pkg_mode=0` and
  `ro.boot.hw.soc.rev=1`; `ro.boot.hw.soc.product_id`, `.major`, and `.minor` were
  empty. Google's public Zumapro source's `0x9875`, major-0 FOPLP A0/A1
  tuples are candidate DTS selectors, not live-read selector values. No
  personal content was queried.
- **[V]** Both the initial and post-update captures report `ro.boot.dtbo_idx=34`.
  In G/'s `constants.bzl`, zero-based entry 34 is `zumapro-komodo-mp.dtbo`; its source
  declares board ID `0x60806`, revision `0x010000`, and Komodo compatibility.
  (G/ `constants.bzl:42`, `dts/zumapro-komodo-mp.dts:16-24`.)
- **[V]** The named fastboot reads found A/B boot partitions and the device
  returned to stock Android on slot A, locked and verified boot green. No slot
  selection or partition write was issued. (R/ `fastboot-vars.txt`,
  `post-fastboot-state.txt`.)
- **[V]** A fresh read-only fastboot inventory on 2026-11-18 reported product
  `komodo`, bootloader `ripcurrentpro-17.0-16433847`, `unlocked=yes`, and
  current slot A. Before the test, A was successful/not-unbootable; B was
  successful/unbootable; both reported two retries. Each A/B image partition
  exists with these sizes:
  `boot` 64 MiB, `init_boot` 8 MiB, `vendor_boot` 64 MiB,
  `vendor_kernel_boot` 64 MiB, and `dtbo` 16 MiB. `userdata` is
  `0x1b5e215000` bytes. This inventory itself did not change slot or partition
  state. The bootloader does
  not expose `dtbo_idx` through `getvar`; the earlier ADB read reported 34.
  (R/ `fastboot-postupdate-targeted.txt`, `post-unlock-targeted.txt`, and
  `fastboot-inventory-2026-11-18.txt`.)
- **[V]** User authorized bootloader unlock, its factory reset, and experimental
  device operations, and later explicitly declared the phone's data disposable
  and authorized flashing/erasure to reach Omarchy. Stage 2 first wrote only
  the five slot-B boot images. The subsequent supported rootfs install wrote
  those five images and `userdata`; slot A and firmware/calibration partitions
  were not written.
- **[V]** `fastboot fetch boot_a` failed while locked and was refused again
  after unlock with `Fetching restricted partition: boot_a is not allowed`.
  The later failed attempt left a zero-byte local placeholder, which was
  removed. No phone partition was written or fetched. Google's official
  factory image for this exact `komodo` build is now downloaded locally at
  `~/android/factory/komodo/CP4A.261105.040.A1/komodo-factory.zip`; its SHA-256
  matches Google's published value
  `ef15b7ca51ba393a836cbb07727d9b24aeecec80a9a40b11d5fe0dcef63a3aa5`.
  This provides the exact stock package, but does not replace the required
  read-only partition backups or finish the attended recovery runbook.
- **[V]** After the authorized reset and setup, Android reports `ro.build.type=user`
  and `sys.boot_completed=1`. ADB shell cannot read device-tree property files
  under `/sys/firmware/devicetree/base` or `/proc/iomem` (`Permission denied`),
  so the live memory map and chosen-node handoff are still unavailable. The
  phone was returned to fastboot afterward.
- **[V]** L/ already has `gs201.dtsi`, `zumapro.dtsi` and the Tegu board DTS,
  but no Komodo board DTS. The SoC description and drivers exist, so the first
  kernel task is a board-specific DTS adapted to L/'s upstream APIs rather than
  copying an Android DTS verbatim.

### Inferences and limits

- **[I]** The MP overlay is the best available board-source candidate because
  its index and board family match the initial capture. It is not proven to be
  the overlay used by the installed Android 17 build: G/ is an Android 16
  branch, and the exact Android 17 factory DTBO was not obtained.
- **[I]** `MP1.0` likely corresponds to the MP source variant; confirm through
  the exact factory image or live DT before treating the mapping as definitive.
- The unrooted Android capture could not read live DT properties, `/proc/iomem`,
  or `dmesg`. Later Linux bring-up verified the DECON handoff/reservation,
  flip-only KMS, and working USB gadget/SSH path. The USB2 overlay has been
  applied on-device as part of the working USB path. The Android 17 stock DTBO
  source match remains unresolved; see [NOTES.md](NOTES.md).
- The Pixel 9a (`tegu`) is the same SoC family but a different board. Do not
  reuse its board-specific panel, touch, GPIO, regulator, storage, or radio
  values without evidence.

## 3. Current development order

1. **Done:** boot the Komodo RAM rescue, verify USB SSH, UFS enumeration and
   DECON handoff, then install Omarchy to `userdata`. Stage 1 measured 60 Hz;
   stage 2 registered flip-only KMS and `gs-decondrmfb`.
2. **Done, experimental:** boot persistent Omarchy on slot B; verify touchscreen
   interaction, USB networking, and guarded Panthor/Mali rendering in the GUI.
3. **Next:** diagnose the failed internal Wi-Fi module probe and verify or
   reject the shared-DMA-pool candidate. Keep the proprietary driver/firmware
   private unless a distributable licensing and packaging path is established.
4. **Later:** verify notification wake/interaction behavior, then continue with
   KM4 panel integration, brightness/sleep, charging, sensors, audio, and
   remaining peripherals. Do not describe this device as generally supported
   until these paths and installation/release handling are reviewed.

Keep build outputs and hardware captures in the isolated worktrees and
`bringup-artifacts/`; keep device-specific unproven settings out of shared
configs. Use `bin/omamobile flash|push` for development boot images and the
supported installer for userdata. No extra recovery-analysis milestone is
required for this owner-authorized experiment.

## 4. Risks and gates

| Gate | State | Evidence / next action |
| --- | --- | --- |
| M2: Omarchy rootfs and USB access | **Passed, experimental** | Persistent root, firstboot, USB SSH and USB internet verified. |
| M3: basic interaction | **Partial** | GUI, touch, flip-only KMS and GPU verified. Internal Wi-Fi failed; investigate the DMA pool and driver failure path. |
| M4: hardware completeness | **Open** | Notifications appear on the lock screen; wake behavior is unverified. Full panel/brightness, suspend, charging, sensors, audio, cellular and Bluetooth need separate tests. |

## 5. Results and open questions

- 2026-11-18: M1.0 research found a strong Google Android 16 MP-overlay
  candidate at DTBO index 34. Exact Android 17 artifact correspondence is
  unresolved.
- 2026-11-18: `linux-omarchy-mobile` worktree
  `~/dev/omamobile-kernel/wt-komodo-m1`, branch `omamobile-komodo-m1`, now contains
  a minimal `zumapro-komodo.dts`, Makefile entry, and Google compatible enum.
  The DTS builds; focused Google binding validation and `dt-validate` on the
  Komodo DTB reported no diagnostics. A full arm64 `Image` and all arm64 DTBs
  built with `W=1`; baseline warnings from unrelated kernel code and DTBs were
  present. This is compile evidence only, not a boot test.
- 2026-11-18: `device/komodo/overlays/usb2-gadget-test.dtso` now enables a
  USB2-only peripheral candidate using Google Caimito's HSI2C6/TCPC pin and IRQ
  mapping, the mainline Zumapro USB2 path, and a Tegu-derived S2MPG14 PMIC
  setup. `dtc -@` compiled the overlay and `fdtoverlay` applied it to the
  Komodo DTB. `dt-validate` 2026.9 against the kernel's processed schemas found
  zero findings in both the base and merged DTBs; the overlay added none. DTC
  emitted zero warnings. This is static validation only. The overlay is not
  named by a device descriptor and has not been run on Komodo. The PMIC IRQ
  remains a Tegu-derived candidate pending Komodo evidence.
- 2026-11-18: The kernel's `tcpm`, `tcpci`, and `tcpci_maxim` modules built
  successfully. Their vermagic matches the kernel release in
  `out-komodo-m1`; this is a targeted module build, not a complete module set.
- 2026-11-18: Downloaded Google's exact `komodo` factory package for
  `CP4A.261105.040.A1` (4,329,100,709 bytes) outside the repository, in an
  owner-only directory. SHA-256 matches Google's published checksum
  `ef15b7ca51ba393a836cbb07727d9b24aeecec80a9a40b11d5fe0dcef63a3aa5`.
  It is a verified stock image source; no phone restore was attempted.
- 2026-11-18: The first bootloader-version measurement found A at
  `ripcurrentpro-17.0-16433847` and B at `ripcurrentpro-17.0-15819938`. The
  active-slot flag changed immediately on `fastboot --set-active`; a later
  confirmed boot on B reported its bootloader version from Android. After
  booting stock A, the exact Google full OTA for
  `CP4A.261105.040.A1` was sideloaded once from A and once from B. Its SHA-256
  matched Google's published `e174085532dbb9e588c67d489b5f4d0165a2d7dfaa6051984e5b38422fb24266`.
  Both boots completed on the same build and reported bootloader
  `ripcurrentpro-17.0-16433847`.
- 2026-11-18: Three non-writing `fastboot boot` experiments returned to
  Fastboot without a USB rescue connection. A subsequent temporary Android-v4
  image set was written with `DEVICE=komodo bin/omamobile flash --from-slot-a`:
  `boot_b`, `init_boot_b`, `vendor_boot_b`, `vendor_kernel_boot_b`, and
  `dtbo_b` all reported successful writes. The initramfs used `ram-rescue`, an
  empty UFS write allowlist, and no slot marker. No USB network interface or
  SSH appeared. The host kernel log at 22:31:30 recorded a Pixel USB product
  `4ee7`; it disconnected at 22:32:20, and Fastboot product `d001` appeared at
  22:32:36. The initramfs configures its NCM+ACM gadget as `1d6b:0104`, which
  was not observed. Available evidence cannot attribute `4ee7` to the test
  kernel or prove how far Linux booted.
  After the B retry count reached zero, Android completed boot on stock A.
  Final Fastboot flags: A successful/not-unbootable with two retries; B
  unsuccessful/not-unbootable with zero retries. No userdata or other
  partition was written. The phone was left booted on stock A. No kernel log,
  display result, or attributable USB enumeration from the test kernel was
  captured, so the cause is unknown. The temporary local image descriptor and
  empty board DTS are retained outside this repository under the kernel
  worktree's `bringup-artifacts/ramtest-2026-11-18/` directory.
- 2026-11-18: Prepared a diagnostic rebuild at
  `~/dev/omamobile-kernel/out-komodo-diag-2026-11-18/images/`. It reuses the exact
  tested kernel, initramfs, DTB and overlays, adding only `omamobile.debug` to
  the vendor command line. This enables the existing initramfs USB, interrupt
  and uptime diagnostics on the display; its NCM+ACM gadget and serial shell
  are unchanged. The debug descriptor and image checksums are saved beside the
  previous local test inputs.
- 2026-11-19: Flashed that diagnostic set to the five slot-B boot partitions
  and activated B. All writes reported success; no userdata, slot-A, or
  firmware partition was written. The host saw USB disconnect, then about six
  minutes later a Pixel USB device with ID `18d1:4ee7`; it never saw the
  diagnostic Linux gadget ID `1d6b:0104`, a USB network interface, or an ACM
  serial device. ADB later confirmed stock Android build
  `CP4A.261105.040.A1`, slot A, and `sys.boot.reason=watchdog`;
  `/sys/fs/pstore` was empty. The test DTB includes the source-derived ramoops
  reservation, but no persistent record was available from stock Android.
  This is consistent with a watchdog reset and fallback to A, but does not
  show whether the custom kernel started or the exact cause. Slot retry flags
  were not re-read after this attempt. The phone
  is left booted on stock A. Host USB events are saved in the local artifact
  directory; the temporary repository descriptor was removed.
- 2026-11-19: The failed test descriptor omitted `USB_SWITCH` and
  `INITRAMFS_I2C_TOOLS`; its initramfs had no `etc/omamobile-usb-switch`.
  The selected USB overlay defines the MAX77759 at `0x25` on HSI2C6, whose
  controller address is `0x108d0000`. The shared init already supports this
  switch: when configured, it reads register `0x93` and writes `0x09` only if
  needed. A corrected diagnostic candidate is built at
  `~/dev/omamobile-kernel/out-komodo-usbswitch-2026-11-19/images/` with
  `USB_SWITCH="108d0000.i2c 0x25"` and the required I2C tools. Image sizes,
  packed descriptor, and checksums were verified. The candidate was later
  rebuilt with the Komodo DTB enabling both cluster watchdogs and the PMU
  system controller; see the following result.
- 2026-11-19: Retried the watchdog-enabled, USB-switch diagnostic images on
  slot B while the owner watched the screen. The five slot-B boot partitions
  were rewritten through `bin/omamobile flash`; slot A, userdata, and firmware
  were untouched. The owner saw the Google/Android boot screen, not readable
  Omarchy diagnostics. The host briefly enumerated Google USB product
  `18d1:4ee0`, then disconnected; it never saw the Linux gadget, USB network,
  ACM console, or SSH. After about six minutes, ADB returned on stock Android
  slot A (`CP4A.261105.040.A1`), with `sys.boot.reason=watchdog` and no pstore
  records. This still does not establish whether the custom kernel started or
  identify the reset cause. The phone is left booted on stock A. The sanitized
  host USB log is retained in the local kernel worktree's bring-up artifacts.
- 2026-11-19: A follow-up test corrected the failures found in that boot's
  `SYSTEM_LAST_KMSG`: ACPM's mailbox/SRAM/CMU and the USB PHY's PMIC regulator
  dependencies were disabled, and the watchdog CMUs were disabled. The board
  DTS now enables the watchdog CMUs; the USB overlay enables ACPM's mailbox,
  SRAM and CMU. The test image rebuilt cleanly and was written only to the five
  slot-B boot partitions. Linux reached `first light` on
  `7.3.0-rc6-omamobile-push1-g26867fc4e826-dirty`; ACPM reported 16 usable
  channels, both watchdog drivers probed without the previous missing-clock
  errors, the USB switch read `0x09`, and the NCM/ACM gadget came up on
  `11210000.usb`. The host enumerated Linux gadget `1d6b:0104`, and root SSH
  over USB succeeded after explicitly selecting the laptop's existing key.
  The normal `phone-ssh` default had not selected that non-default identity, so
  the flash helper's initial SSH wait timed out even though Linux was running.
  The Linux FDT still marks `display-controller@19470000` disabled; there is no
  framebuffer device or handoff node, so the screen is not yet usable. UFS is
  also disabled and no storage block device appeared. This run used a RAM
  rescue initramfs; no user messages or files were accessed, and no userdata,
  slot-A, or firmware partition was written. The test descriptor's allowlist
  included userdata, but UFS was disabled; no userdata content was read or
  written. In storage tests, keep userdata unmounted; writes remain restricted
  to the supported installer path. Candidate image hashes are recorded in the
  local kernel worktree under `bringup-artifacts/ramtest-2026-11-18/`.
- 2026-11-19: A later RAM-rescue boot enabled the UFS path after adding the
  source-derived VCC rail and HSI2 clock. Linux reached USB SSH and enumerated
  the UFS LUNs and GPT partitions. The rescue root is still `rootfs`; no phone
  partition is mounted. Only UFS device descriptors and partition metadata
  were read to enumerate storage. The userdata partition was not mounted,
  opened, or written. The storage guard kept protected partitions read-only;
  its descriptor allowlist leaves the five slot-B boot partitions and userdata
  writable, but no write was issued. Slot A and protected firmware/calibration
  partitions remain untouched. The screen still shows the Google boot image;
  Linux has no active Komodo display handoff yet.
- 2026-11-19: Display source review found Google Caimito's Komodo panel
  compatible `google,gs-km4` and 1344x2992/1008x2244 DSI modes. The current
  mainline kernel has no KM4 panel driver. Google does publish a KM4 driver
  ([source](https://android.googlesource.com/kernel/google-modules/display/panels/caimito/+/refs/heads/android-gs-akita-android16/panel-gs-km4.c));
  it uses Google's `gs_panel` framework, which this kernel does not have, so it
  is a source for a mainline port rather than a drop-in driver. Its Tegu sibling
  reserves a splash buffer at `0xfac00000`, but that is not verified for
  Komodo, so the address was not copied. The current live FDT has no framebuffer
  or splash reservation and keeps DECON disabled. Enabling a guessed address
  or panel sequence would risk displaying garbage or disrupting the still-
  working rescue path; the next display milestone needs a Komodo-verified
  handoff or a minimal KM4 driver with source-backed panel power/reset details.
- 2026-11-19: The DECON stage-0 RAM-rescue candidate at
  `~/dev/omamobile-kernel/bringup-artifacts/ramtest-2026-11-18/decon-stage0/images/` was flashed
  to slot B and booted. Linux read DECON version `0x07060000`, active command
  mode (`GLOBAL_CON=0x133`), a 1344x2992 DPP0 image, and base address
  `0xfac00000`; SSH remained available. The live `/proc/iomem` calls that
  address System RAM, with no existing reserved-memory node for it. After
  2,375 seconds in stage 0, DECON `frame_count` and frame-start/done IRQ
  counts remained zero, consistent with the bootloader's masked trigger.
  Stage 0 does not map or write the buffer. The stage-1 candidate reserved
  exactly `1344*2992*4` bytes with `no-map`, enabled the frame interrupts and
  existing boot trigger, and left KMS and DSI/panel commands off. It booted on
  slot B and reported 1,155 start and 1,155 done interrupts over 19,227 ms
  (60.071 Hz); no userdata was accessed. The exact images and overlay are
  saved privately under
  `bringup-artifacts/ramtest-2026-11-18/decon-stage1/`.
- 2026-11-19: Built and booted stage 2 from slot B at
  `~/dev/omamobile-kernel/out-komodo-decon-stage2-2026-11-19/images/`. It adds a
  64 MiB shared scanout pool in the live-verified System RAM range below 4 GiB,
  registers flip-only KMS, and enables the DRM fbdev console. There is no DSI
  link or panel node in this overlay, so it cannot send panel commands. Live
  DRM reports connected DSI output at 1344x2992, `/proc/fb` reports
  `gs-decondrmfb`, and kernel stats show 60.04 Hz with 723 frame starts and
  completions and no flip timeouts. The rescue root remains RAM-backed and no
  phone filesystem was mounted. Its image hashes and overlay are saved
  privately under `bringup-artifacts/ramtest-2026-11-18/decon-stage2/`.
- 2026-11-19: Rebuilt the stage-2 image set with the initramfs in
  `persistent-development` mode: it attempts the installed Arch root on
  `userdata` and falls back to RAM rescue if root mounting or SSH health fails.
  Built an experimental local-only Komodo package containing only the device
  descriptor and package mirrorlist. Fetched and verified all 53 published
  development packages and assembled a locally signed package repository with
  the custom Komodo package. The temporary signing key remains under ignored
  `keys/komodo/`; neither package nor key is a release artifact. Built the
  matching kernel module archive and Omarchy rootfs. The 2026.11.19 compressed
  rootfs is in `out/omamobile-rootfs-komodo-2026.11.19-aarch64.img.zst`; its
  checksum, manifest, and installer `--verify-only` check passed. The rootfs
  includes the local development repository and Komodo package.
- 2026-11-19: Installed the rootfs with `tools/install-phone --reinstall` on
  the already-running slot B. The installer wrote only `boot_b`, `init_boot_b`,
  `vendor_boot_b`, `vendor_kernel_boot_b`, `dtbo_b`, and `userdata`, then set B
  active and rebooted. All writes reported `OKAY`; slot A and bootloader-related
  partitions were untouched. USB SSH confirmed kernel
  `7.3.0-rc6-omamobile-push1-gd41411c7ef78-dirty`, `/` mounted from `/dev/sda34`
  as ext4, successful firstboot, and SSH key authentication. SDDM, Hyprland and Omarchy QuickShell are running on DSI-1
  at 1344x2992/60 Hz; the owner saw the graphical session on the phone. The
  built-in lock-on-start then locked the session and the display later entered
  DPMS off. Wake the display with the power button to inspect the lock screen;
  touch and unlock interaction remain unverified. No Wi-Fi was provisioned.
- 2026-11-19: From the running RAM rescue, `reboot-to bootloader` and a
  controlled kernel panic both restarted into the same slot-B rescue; neither
  exposed fastboot. SSH confirmed a new boot ID, the rescue root remained the
  only mounted filesystem, and the UFS guard stayed active. No phone partitions
  were written by these transitions. The bootloader's reboot-reason handling
  is therefore not a reliable way into fastboot on this build; use the physical
  key combination or a verified Android-to-bootloader path for the next flash.
- 2026-11-19: After a later boot sequence, Linux rescue reported userdata was
  not ext4. This followed an Android fallback; Android reformatting userdata is
  a plausible explanation, but the writer was not independently proven. Ran
  `tools/install-phone --reinstall` again after confirming Fastboot reported
  `komodo`, unlocked, current slot B. The signed Arch `android-tools` package
  was verified and extracted under `/tmp` only to supply `img2simg`; nothing
  was installed system-wide. The root image checksum and installer
  `--verify-only` passed. All five slot-B boot image writes and all 34 userdata
  chunks returned `OKAY`; slot B was activated and rebooted. Slot A and
  bootloader-related partitions were not written.
- 2026-11-19: USB SSH then confirmed `/dev/sda34` mounted as `/` with ext4,
  kernel `7.3.0-rc6-omamobile-push1-gd41411c7ef78-dirty`, firstboot completion,
  and removal of `/etc/omamobile/firstboot.conf`. SDDM,
  Hyprland, and the Omarchy Mobile UI layers were live. `/dev/input/event0`
  registered `Synaptics TouchComm Touchscreen`; a 12-second event sample
  captured `BTN_TOUCH` and absolute-axis events, confirming touch reports reach
  evdev. No coordinates were retained. The live idle config was
  `screensaver=0, lock=60`; shell logs correlated idle with
  `lock-timeout-immediate` and a successful `omarchy-system-lock` invocation.
  `/usr/bin/omamobile-setup-user` documents this one-minute blank-and-lock as
  the phone default. Changed only this test user's `idle.lock` to 600 seconds;
  the live idle service reports 600, so the setting hot-applied. The previous
  lock remains engaged; a post-unlock check past the 60-second mark is pending.
  A correctly scoped Omarchy wake command re-enabled DSI/CRTC while keeping
  the lock engaged. The active power profile is `balanced`; no battery/charger
  device was exposed in sysfs. No Wi-Fi was provisioned.
- 2026-11-18: `tools/kernel-pr-check` passed on the Komodo board-DTS commits:
  checkpatch reported no errors (one standard MAINTAINERS warning), all 11
  device trees built with `W=1`/`dtbs_check` with no new warnings, and the
  touched DT binding passed `dt_binding_check`.
- The output is a 42 MiB uncompressed arm64 `Image` and a 45 KiB Komodo DTB.
  The temporary Android-v4 images were test artifacts, not a supported device
  package. USB2 gadget networking was observed on the integration build; the
  separate Type-C-controller test overlay remains unverified.
- Open: verify notification wake behavior, bring up internal Wi-Fi, match the
  Android 17 source/DTBO, port the full panel
  driver, and test the remaining peripherals. Persistent userspace, USB SSH,
  touch, flip-only KMS, and the GPU are proven on this one test device;
  `boot_a` remains unreadable through Fastboot.

## 2026-11-23 PR handoff checkpoint

The kernel PR head now contains the board description for the measured
display handoff, UFS, USB2 and boot-critical SoC blocks; optional Type-C,
touchscreen, WLAN and GPU nodes remain disabled in the board DTS. Its exact
signed commit was rebuilt into `out-komodo-m2`, but the phone was not available
over USB for an exact-head smoke test. The successful persistent GUI, touch
and GPU observations came from the preceding local integration build and do
not substitute for that test. The Omarchy Mobile PR includes the experimental
device package, README and offline package test. Wi-Fi remains excluded from
the selected overlays until the DMA-pool and driver failure are resolved.
