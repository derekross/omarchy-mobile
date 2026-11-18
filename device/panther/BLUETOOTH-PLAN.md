<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 (panther) Bluetooth: the BCM4389 on the APM UART

Status (2026-11-16): BT0 to BT3 passed on 2026-11-01. The kernel side merged as [linux-omarchy-mobile#196](https://github.com/derekross/linux-omarchy-mobile/pull/196), and the options for BLE mice and headphone buttons as omarchy-mobile#304. The package side, Bluetooth up at boot with the phone's own firmware and address (BT3, a local build numbered 0.1.7), is a pull request to come, with the address rule's fix from #423. With it the shell's panel, a BLE mouse and headphones (A2DP, AVRCP) work. `BT_RFCOMM` is left out of #304 (the headset profile, below).

The Pixel 7 has the same Broadcom BCM4389 as the Pixel 7 Pro, with the
same wiring. The Pixel 7 Pro's Bluetooth works through upstream `hci_bcm`
and `btbcm` (device/cheetah/BLUETOOTH-PLAN.md), so this plan brings the same
pieces to panther, one change per boot.

[V] is verified on this phone or in the source; [I] is inferred.

## What is known

| Fact | Evidence |
| --- | --- |
| The Bluetooth core is on the APM USI1 UART. BT_REG_ON (shutdown) is gpp16-2 and BT_DEV_WAKE is gpp16-3, both outputs with no pull; the host wake is gpa6-6, EINT, pulled down. These are the Pixel 7 Pro's pins and pulls | stock live DT `goog,nitrous` and its pin groups [V] |
| Wi-Fi's WL_REG_ON is gph2-4, separate, so Bluetooth powers up alone | stock live DT `android,bcmdhd_wlan` [V] |
| The firmware patch is the phone's own, from the user's factory image: `brcm/BCM.google,gs201-panther.hcd`, "BCM4389C1 ES1PX_GG_P10 FW:1c340ab760" | `tools/extract-vendor-firmware -d panther`, in `~/android/vendor-firmware-panther` (not committed) [V] |
| `omamobile` has everything the Pixel 7 Pro uses: the CMU_APM subset, `usi_apm1`, `serial_apm1`, `brcm,bcm4389-bt`, and `btbcm.patchram_nowait` for this chip's slow patch download | the Pixel 7 Pro's board file; `drivers/bluetooth/btbcm.c` [V] |
| `CONFIG_BT_HCIUART=m` with `BT_HCIUART_BCM` | `kernel/configs/omamobile.config` [V] |
| The Pixel 7 Pro sets the controller's address from the bootloader's `/chosen/config/bt_addr` (`omamobile-bt-addr`); without it the BCM4389 comes up with a placeholder | `packages/omamobile-device-cheetah/bin/omamobile-bt-addr` [V] |

## The change

Local kernel branch `omamobile-gs201-panther-bt`, one commit on
`omamobile`: "arm64: dts: exynos: google: gs201-panther: add Bluetooth"
(`cmu_apm`, `usi_apm1`, `serial_apm1` with the controller, and its three
pin groups).

## Gates

### BT1. The controller, loaded by hand (low risk)

Kernel BT1 (`7.3.0-rc6-omamobile-push1-gbb6c8a7ff379`) is the running kernel plus that commit.

**Before the boot:**
- copy the `.hcd` to the phone's `/usr/lib/firmware/updates/brcm/`;
- write a bring-up file, `/etc/modprobe.d/omamobile-bt-bringup.conf`,
  that blacklists `hci_uart` and sets `options btbcm patchram_nowait=1`;
- modules, then fastboot and flash.

**On the running kernel:** `modprobe hci_uart` with `dmesg -w` running.

**Pass:**
- `hci0` appears;
- the patch downloads ("BCM4389C1 … FW:1c340ab760");
- `btmgmt info` shows the controller and its version.

**Stop if:** the UART times out, or the patch fails.
**Rollback:** `rmmod hci_uart`; the bring-up file keeps it out at boot;
the previous image set by fastboot.

### BT2. Address, power and a pairing

- Set the bootloader's address as `omamobile-bt-addr` does.
- Power the controller on, scan, and pair with something.
- Play audio over A2DP if headphones are at hand.

**Pass:** the real address, a scan that finds devices, a pairing.
**Rollback:** as in BT1.

### BT3. By default

device-panther ships the btbcm option and the address service, as the
Pixel 7 Pro's package does, and the bring-up file goes.
**Pass:** after a reboot, Bluetooth comes up on its own with the real
address.
**Rollback:** the previous package, or the bring-up file again.

## Results

### 2026-11-01: BT1

Kernel BT1 (`7.3.0-rc6-omamobile-push1-gbb6c8a7ff379`), flashed after its
modules, with the firmware copied to `/usr/lib/firmware/updates/brcm/`
(sha256 matching the laptop's) and the bring-up file in place:
- `hci_uart` stayed out at boot. The APM UART registered as `ttySAC0`
  (181b0000), with the serdev device `serial0-0`.
- `modprobe hci_uart`: `hci_uart_bcm serial0-0` bound (vbat and vddio are
  dummies, as on the Pixel 7 Pro), then:
  - "BCM: chip id 170", "BCM4389C1", "BCM (003.002.009) build 0000";
  - "BCM 'brcm/BCM.google,gs201-panther.hcd' Patch";
  - 6.6 s later, "BCM4389C1 ES1PX_GG_P10 FW:1c340ab760 CFG:1645bab7ef
    [Baseline: 0395]" and "build 0203";
  - "MGMT ver 1.23".
- `hci0` appeared. `btmgmt info` reported version 11 (Bluetooth 5.2),
  manufacturer 15 (Broadcom), BR/EDR and LE, and powered (bluetoothd
  powers it).
- The address is the chip's placeholder (43:89:…). The bootloader's
  `/chosen/config/bt_addr` is present for BT2.
- Six "Failed to read codec capabilities (-22)" lines came after the patch.
- The display (90 Hz, no flip timeouts), the charger, the gauge, touch and
  the USB rescue were unchanged.

### 2026-11-01: BT2

On kernel BT1:
- **Address.** The Pixel 7 Pro's `omamobile-bt-addr`, run by hand for
  `hci0`, set the bootloader's address (`/chosen/config/bt_addr`):
  `btmgmt info` then matched it, and the controller stayed powered. Each
  power-on logs the six codec-capabilities lines again.
- **The shell's panel** stayed grey: the shell had started before `hci0`
  existed (`hci_uart` was loaded by hand), and it doesn't pick up an
  adapter that appears later. After a shell restart the panel was live.
  At BT3 the controller comes up at boot, before the shell.
- **A BLE mouse (Logitech MX Master 3)** paired and connected, but
  bluetoothd logged "input-hog profile accept failed": `CONFIG_UHID` was
  off, so there was no `/dev/uhid`. With `CONFIG_UHID=m`,
  `CONFIG_HID_LOGITECH=m` and `CONFIG_HID_LOGITECH_HIDPP=m` added to
  `kernel/configs/omamobile.config` and the same kernel rebuilt and
  flashed:
  - `/dev/uhid` appeared, and `uhid` and `hid_logitech_hidpp` loaded;
  - the kernel logged "input: MX Master 3 Mouse as
    /devices/virtual/misc/uhid/…" and "logitech-hidpp-device …: HID++ 4.5
    device connected";
  - the mouse drove the shell: a downward drag opened its panels.
  - No pointer shows, because the phone's Hyprland sets `cursor:invisible`
    (a touch device keeps it hidden; omamobile-omarchy patch 0006).
- **Headphones (Sony WF-1000XM5)** connected. PipeWire made them the
  default sink, mpv's audio played on them, and the phone's volume keys
  changed the volume. Two profiles are missing from the kernel config:
  - AVRCP: "failed to create uinput" (`CONFIG_INPUT_UINPUT` off), so the
    headphones' own buttons can't control playback;
  - Hands-Free: "socket(STREAM, RFCOMM): Protocol not supported"
    (`CONFIG_BT_RFCOMM` off), so there's no headset microphone. Calls would
    also need SCO audio routed over HCI, which the Pixel 7 Pro hasn't done
    yet (device/cheetah/BLUETOOTH-PLAN.md).

**AVRCP and RFCOMM.** With `CONFIG_INPUT_UINPUT=m` and `CONFIG_BT_RFCOMM=m`
added too, and the same kernel rebuilt and flashed:
- `uinput` and `rfcomm` loaded;
- bluetoothd created a "WF-1000XM5 (AVRCP)" input device;
- the headphones' play/pause and volume buttons controlled mpv's playback;
- the RFCOMM error was gone, and PipeWire listed the headphones' headset
  microphone as an audio source.

Calls over it (SCO) are not tested. bluetoothd also logs "kernel lacks
bnep-protocol support" (`CONFIG_BT_BNEP`, Bluetooth networking), which
nothing here needs.

### 2026-11-01: BT3 (device-panther 0.1.7)

device-panther 0.1.7 was installed on the phone, the Bluetooth bring-up
file deleted, and the phone rebooted on the same kernel. After the reboot:
- `hci_uart` and `btbcm` loaded on their own. `hci_uart_bcm` bound at
  3.8 s, and the patch was in at 10.7 s ("BCM4389C1 ES1PX_GG_P10
  FW:1c340ab760"), with `patchram_nowait` from the package.
- `omamobile-bt-addr@hci0`, started by the udev rule, exited 0. The
  controller had the bootloader's address and was powered.
- The adapter existed before the shell started (8.7 s), and the shell's
  Bluetooth panel was live with no restart.
- The headphones reconnected on their own, the mouse once it was moved,
  and both worked.

**The pointer.** The phone hides it (`cursor:invisible`, set once in the
user's `looknfeel.lua` by omamobile-shell's setup). With `invisible` off
at runtime and `hide_on_touch` kept on, the arrow showed while the mouse
moved and hid at the first touch.

### 2026-11-02: the headset profile and WirePlumber's switch

Asked on omarchy-mobile#304: with `CONFIG_BT_RFCOMM`, does a recording switch headphones from A2DP to the headset profile, and does playback survive? On kernel `7.3.0-rc6-omamobile-push1-gdb341d1e29e7` (which has `BT_RFCOMM`), with the WF-1000XM5 and a video playing in mpv, the card's active profile was logged once a second:

- **Before the test,** the card was already on `headset-head-unit` (mSBC, a 16 kHz mono sink), with nothing recording. The video was audible at call quality. What switched it there wasn't caught.
- **Set to `a2dp-sink` by hand,** the sound was back to normal quality.
- **`pw-record --target` the headset's source, 5 s:** the card switched to `headset-head-unit` for the whole recording, the music cut out and mpv paused. The card was back on `a2dp-sink` within a second of the end, but mpv stayed paused.
- **`pw-record` from the default source, 5 s, 15 s later:** the same switch and return, because the headset's microphone had become the default source.
- **After mpv was resumed by hand,** A2DP at normal quality.
- **Both recordings** hold real signal (48 kHz, RMS about 0.02-0.03, peak about 0.2).

WirePlumber's `bluetooth.autoswitch-to-headset-profile` is `true`. So on this phone, SCO audio reaches the headphones and the microphone records over it, but any recording interrupts the music. `BT_RFCOMM` was taken out of #304, to come back with a WirePlumber setting that keeps headsets on A2DP, or with call support.
