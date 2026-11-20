<!-- SPDX-License-Identifier: MIT -->
# Pixel 9 Pro XL (komodo) bring-up notes

Stage 0 started 2026-11-18 with a read-only stock capture from one retail Pixel
9 Pro XL. The owner later authorized and completed a bootloader unlock, which
factory-reset userdata; Android setup was completed again. Experimental
Omarchy Mobile is installed on slot B and reachable over USB SSH. The
`/dev/sda34` userdata partition is mounted as the ext4 root, firstboot completed,
and SDDM, Hyprland, and Omarchy QuickShell are running on DSI-1. The touchscreen
driver is registered and a live sample confirmed BTN_TOUCH/absolute-axis events.
Display blanking is explained by the phone profile's 60-second idle lock with
screensaver disabled. This test phone's user config now requests a 600-second
lock, and the live idle service reports the new value; the existing lock remains
engaged. Omarchy's wake command re-enabled DSI/CRTC without unlocking. Wi-Fi is
not provisioned. Userdata was erased by the
authorized installer; no personal content was queried. Slot A remains untouched.
Raw captures remain private; only non-identifying facts are recorded here.

The current DECON stage-1 boot measures 60 Hz from the live 1344x2992 DPP0
handoff at `0xfac00000`, using a no-map reservation and no KMS or panel
commands. A stage-2 flip-only KMS plus framebuffer-console candidate is built
for the next boot.

Tracking issue: [#913](https://github.com/derekross/omarchy-mobile/issues/913).

## Stage 0: stock Android capture

`R/` means the contributor's private capture made with `bin/omamobile capture
komodo-stock` over ADB on 2026-11-18, plus the named read-only follow-up queries
below. It was unrooted, so there is no live DT blob or property values,
`dmesg`, `/proc/iomem`, or other root-only kernel state. The capture contains
device identifiers and is not in this repository.

### Identity and current boot

- **Pixel 9 Pro XL, `komodo`, Tensor G4 (`zumapro`), hardware revision MP1.0**
  [V] (R/ `getprop.txt:675,677,872,878,926`).
- **Android 17, build `CP3A.261005.005`, security patch 2026-10-05** [V]
  (R/ `getprop.txt:764,778,783`).
- **Stock kernel `6.1.162-android14-11`** [V] (R/ `kernel-version.txt:1`).
- **At the initial ADB capture, Android was running slot B; bootloader locked
  and verified boot green** [V] (R/ `getprop.txt:666,695,709,732`).
- **The initial Android bootloader property was
  `ripcurrentpro-17.0-15819938`; `dtbo_idx` was 34** [V]
  (R/ `getprop.txt:655,664`).
- **A targeted read-only ADB check after returning from fastboot confirmed the
  stock update had booted on slot A:** Android 17, build
  `CP4A.261105.040.A1`, security patch 2026-11-05, kernel
  `6.1.172-android14-11`, hardware revision `MP1.0`, and `dtbo_idx=34` [V]
  (R/ `post-update-targeted.txt`). At the time of this read, the bootloader was
  locked and verified boot was green. No personal content was queried.

### Named fastboot reads and return to stock Android

With the owner's approval, the phone was rebooted into the bootloader on
2026-11-18. Only named `fastboot getvar` reads were run; `getvar all` was not
used. Results are in the private R/ capture.

- **Fastboot reported product `komodo`, revision MP1.0, current slot A, and
  bootloader `ripcurrentpro-17.0-16433847`** [V]
  (R/ `fastboot-vars.txt:3,7,11,15`).
- **At that read, slot A was `successful=no`, `unbootable=no`, with 3 tries;
  slot B was `successful=yes`, `unbootable=no`, with 2 tries** [V]
  (R/ `fastboot-vars.txt:26-47`).
- **The queried boot-image partition sizes** [V] (R/ `fastboot-vars.txt`):
  `boot_a/b`, `vendor_boot_a/b`, and `vendor_kernel_boot_a/b` were `0x4000000`
  each; `init_boot_a/b` were `0x800000` each; `dtbo_a/b` were `0x1000000` each.
  `userdata` was `0x1b5e215000` (R/ `fastboot-vars.txt:50-91`).
- **After the plain `fastboot reboot`, Android completed boot on slot A with
  build `CP4A.261105.040.A1`; bootloader remained locked and verified boot
  green** [V] (R/ `post-fastboot-state.txt:1-7`). The prior ADB capture was on
  slot B with build `CP3A.261005.005` (R/ `getprop.txt:764,695`).
- **During this initial fastboot measurement, no `set_active`, unlock, flash,
  or partition-write command was issued.**
  **Inference I1:** the pre-reboot state matches AOSP's documented
  "update applied, reboot pending" state: Android was on successful B while A
  was selected, bootable, but not yet marked successful. AOSP says the next
  reboot enters the new slot, which remains unsuccessful until its userspace
  verification completes ([A/B update flow](https://source.android.com/docs/core/ota/ab)).
  A stock OTA already staged to A is therefore the likely explanation for the
  `CP4A` build. No update logs were read, so its timing and source are unconfirmed.
  This describes the initial capture only; the device was later unlocked and
  intentionally used for slot-B Linux bring-up.

### CPU, memory, and partition names

- **Eight CPUs** [V] (R/ `proc.txt:7-70`): four with CPU part `0xd80`, three
  with `0xd81`, and one with `0xd82`. Part names are not inferred here.
- **`MemTotal` 15,957,128 kB** [V] (R/ `proc.txt:73`).
- **An unrooted listing of `/proc/device-tree` returned 732 entries, but
  reading the root `compatible` property was denied** [V]
  (R/ `device-tree-nodes.txt:1-732`, `device-tree-nodes.err:1`). These names
  are not a substitute for the live DT property values.
- **A/B names exist for `boot`, `init_boot`, `vendor_boot`,
  `vendor_kernel_boot`, and `dtbo`; `super` and `userdata` are also present**
  [V] (R/ `partitions-by-name.txt:11-12,18-19,30-31,51,57,64-67`). Partition
  sizes were first captured partially; a fresh read-only fastboot inventory
  below now records every boot-image partition size and userdata size.

### Google GPL board-source match (candidate)

- The public Google `kernel/devices/google/caimito` branch
  `android-gs-caimito-6.1-android16` contains `zumapro-komodo-mp.dts`.
  Its `constants.bzl` places that overlay at zero-based DTBO index 34; the
  overlay declares board ID `0x60806`, revision `0x010000`, and compatible
  `google,ZUMA PRO KOMODO`. This matches the captured `dtbo_idx=34` and
  `zumapro`/`komodo` identity [V] **for that published branch**, not yet for
  the installed Android 17 image [G/ [`zumapro-komodo-mp.dts`](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/dts/zumapro-komodo-mp.dts):16-24,
  [`constants.bzl`](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/constants.bzl):42;
  R/ `getprop.txt:655,675,677`].
- The phone's reported `MP1.0` hardware revision is consistent with the
  overlay's `MP` name, but that label alone does not prove which DTS revision
  or source version the installed image used [I].
- **Source limitation:** this is an Android 16 Google source branch, while
  the current system build is Android 17. No matching Android 17 caimito
  branch or factory DTBO for the installed build was found in this review.
  Treat the overlay as a strong reference candidate, not a verified exact
  source match. No Google source files or binaries were copied into this
  repository.

## Interpretation and open questions

- The Pixel 9a (`tegu`) is the current Tensor G4 bring-up, but it is a different
  board. Do not copy its board DTS or panel, touch, GPIO, regulator, or firmware
  assumptions onto `komodo` without evidence from this device.
- The modem package already notes that Pixel 9 Pro XL needs its PHY brought up
  before its PCIe host. This is a lead for a separate hardware investigation,
  not a verified result from this phone.
- Current engineering work is beyond the initial read-only gate: Komodo has a
  local experimental descriptor and board DTS; Omarchy boots from slot B with
  USB SSH and a running graphical session. The next work is characterizing the
  display idle/wake behavior and continuing hardware bring-up. Android 17
  source matching, Wi-Fi, the full KM4 panel path, and other peripherals are
  separate remaining work.
- A public Google GPL source checkout is now available locally at
  `~/omamobile-kernel/google-caimito`. Kernel DTS work belongs in
  `linux-omarchy-mobile`, not this repository; see the initial gate plan in
  [`BRINGUP-M1.md`](BRINGUP-M1.md).

## Safety boundary and state as of 2026-11-19

**Historical checkpoint — 2026-11-19:** the owner explicitly says phone data and stock
recovery do not matter and has authorized flashing and erasure to reach Omarchy.
After an Android fallback, Linux rescue reported userdata was not ext4; Android
reformatting it is plausible but not proven. `tools/install-phone --reinstall`
then rewrote the five slot-B boot images and userdata; every flash returned
`OKAY`, slot B was activated, and slot A/bootloader-related partitions were not
touched. The rootfs is mounted from `/dev/sda34` as ext4. Firstboot completed,
USB SSH works, and SDDM, Hyprland, and Omarchy QuickShell are running on the
connected 1344x2992 DSI output. The Synaptics driver reports BTN_TOUCH and
absolute-axis events through `/dev/input/event0`; Hyprland lists the touch
device enabled with transform 0. Omarchy's user idle profile first locked after
60 seconds (`screensaver=0`); the test user's config now requests 600 seconds
and the live idle service reports that value. That setting does not control the
separate lock-screen blank timer: the installed lock service uses 10 seconds
when the touch keypad is enabled. Wi-Fi is not provisioned.

**Touch interaction diagnosis at that checkpoint (2026-11-19):** a local screenshot confirmed the
lock glance rendered, but its swipe gesture did not respond. The separate
10-second lock blank timer and delayed physical wake made the earlier short
tests unreliable: `omarchy-shell lock wake` returns `ok` before the panel is
visibly lit, and the lock deliberately consumes touches while `displayDark` is
true and for a 400 ms post-wake guard. The user then tested on the unlocked
home screen for several minutes. SPI IRQ counts and thousands of touch events
confirmed the sensor and driver were active, while no UI controls responded.
The kernel boot log reports Synaptics app firmware range `13440x29920`; the
Komodo test overlay had incorrectly set `touchscreen-size-x/y` to the panel
pixel size `1344x2992`. The driver applies those values to the advertised axis
ranges but does not scale reported touch coordinates, leaving them about 10x
out of bounds. Removed those two properties from
`overlays/synaptics-touch-test.dtso` so the driver keeps its native firmware
range. Removed the properties in `overlays/synaptics-touch-test.dtso`, rebuilt
the five Android v4 boot images, and wrote only `boot_b`, `init_boot_b`,
`vendor_boot_b`, `vendor_kernel_boot_b`, and `dtbo_b`. Each write was SHA-256
verified; slot A and userdata were untouched. The phone rebooted and its USB
network returned, but at this checkpoint the graphical session and touch fix
were not yet verified: SSH key authentication was rejected and the owner saw a
text console. This was later resolved; the following USB internet/GPU entry
records the successful persistent GUI boot. The `lock-on-start` toggle was
temporarily preserved as `lock-on-start.paused-for-touch-test`. No message or
personal user data was read.

The device port follows the repository's supported write path: slot-B boot
images through `bin/omamobile flash|push`, and userdata only through
`tools/install-phone`. Userdata is explicitly disposable and may be erased by
the installer. Do not spend project time on stock recovery or data backups.
The older read-only fastboot inventory and exact factory image remain useful
historical facts, not prerequisites or gates for this experiment.

## 2026-11-20 Wi-Fi host and driver probe

At this checkpoint, the slot-B Wi-Fi host overlay brought the Komodo BCM4390 PCI function up as
PCI `14e4:4438` (subsystem `14e4:4390`) with a Gen3 x1 link. An experimental
Broadcom `bcmdhd` module was built in a private cache against the exact running
kernel release; no proprietary blobs or module sources were added to this
repository. Firmware and board calibration were copied from the local factory
vendor image, with owner-only permissions.

The first module probe reached `dhdpcie` attach, then failed its first 320 KiB
coherent DMA ring allocation. The active test DT used `restricted-dma-pool`,
which is for restricted streaming DMA and did not provide the driver's coherent
allocation. The failed attach also exposed a Broadcom cleanup bug: it purged an
RX skb queue before that queue had been initialized, causing a kernel NULL
pointer oops. A guard for that failure path exists only in the disposable
private driver build copy.

Changed the test pool to `shared-dma-pool` plus `no-map`, kept its 16 MiB
allocation below 4 GiB, and added `wifi-host-test` to the Komodo image overlay
list. `bin/omamobile images` succeeded. `bin/omamobile push` wrote and
read-back SHA-256 verified `boot_b`, `init_boot_b`, `vendor_boot_b`,
`vendor_kernel_boot_b`, and `dtbo_b`; slot A and userdata were not written by
that operation. The push tool did not observe a changed boot ID after its
`reboot-to omamobile` request. A subsequent explicit `systemctl reboot` did
reboot the phone, but at this checkpoint the laptop saw its `Komodo Omarchy
RAM test` USB gadget, could ping the phone, and got TCP connection refused on
SSH port 22. The coherent-pool overlay had not yet been tested at runtime, and
Wi-Fi was not working. The root filesystem check result was unverified. The
next entry records the subsequent recovery of the running GUI and USB SSH.

At that checkpoint, access recovery was still pending. Preserve slot A; keep
proprietary Wi-Fi firmware in private, owner-only staging until its driver and
licensing/package path are resolved.

## 2026-11-20 USB internet and GPU acceleration

The phone is back in persistent Omarchy on slot B. The touch fix and USB
networking are live. The laptop shares its Wi-Fi connection over an isolated
USB network; firewall forwarding blocks access to the home LAN while allowing
outbound internet. The phone's USB interface is configured persistently by the
Komodo package's systemd-networkd file. A live `curl` from the phone to
WhatsApp Web returned HTTP 200.
The browser pairing page was opened for owner testing; no account was linked
and no message content was viewed. The Pixel's internal Wi-Fi still does not
work; this is internet over USB.

Added `gpu-test` to the slot-B overlay set. It enables Komodo's Zumapro GPU
and G3D clock controller, uses the ACPM paired GPU clock and only the 150 and
302 MHz OPPs from the sibling Tegu bring-up, and blacklists Panthor autoload
until the guarded service probes it. The first manual probe was run with
`/dev/watchdog0` armed: Panthor bound, created `/dev/dri/renderD128`, identified
the chip as Mali-G715, and loaded CSF firmware. The kernel also logged
`_opp_set_regulators: no regulator (mali) found`, but initialization completed;
no higher OPPs have been tested.

Package `omamobile-device-komodo` 0.0.4 now installs the GPU startup unit,
watchdog-guarded loader, UWSM hardware-rendering environment, and persistent
USB network configuration. The service is enabled and active. On a subsequent
boot it loaded Panthor before the graphical session, and Hyprland/QuickShell
inherited `LIBGL_ALWAYS_SOFTWARE=0`, `QSG_RHI_BACKEND=opengl`, and
`AQ_DRM_DEVICES=/dev/dri/card0`. The device reports the Komodo Mali GPU. In
brief, idle samples Hyprland fell from the earlier 40-70% CPU observations to
about 1-8%; QuickShell settled around 3-10%. These are live observations, not
a controlled benchmark. The graphics session was restarted once and the
WhatsApp Web pairing page reopened. The five slot-B boot images were
read-back verified; slot A and userdata were not written.

Package version 0.0.4 is a local experimental bring-up artifact; its source is
not included in this PR because it still needs the repository's package
README/test scaffolding and release review.

## 2026-11-20 synthetic notification check

Sent a local `notify-send` test with placeholder text and no WhatsApp account
or message content. The notification appeared in the logged-in Omarchy session;
the owner confirmed that the lock screen continued to report no notifications.
The display did not wake for the test. This confirms desktop-session banners,
not WhatsApp Web delivery, lock-screen notification support, or vibration.
No real messages were accessed.
