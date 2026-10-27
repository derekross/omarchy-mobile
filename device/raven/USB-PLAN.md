<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): USB

Status (2026-10-20): USB 2 device mode works (NCM and ACM, SSH at
172.16.42.1) with a raven-only DT change that makes dwc3 a USB 2
peripheral and drops `orientation-switch` from the PHY. The PR review of
the boot glue (derekross/linux-omarchy-mobile#2) asked to keep upstream's
USB description in `gs101-pixel-common.dtsi`, so that change now lives
only in `omamobile-gs101-int`, as a NOT FOR MERGE commit. Open: U1, does
upstream's description work as it is?

## 1. Goal

USB device mode on raven with upstream's DT unchanged: dwc3 dual-role
behind the USB role switch, `orientation-switch` on the PHY, the MAX77759
TCPC described. Later, a TCPC driver that owns the port (host mode,
orientation, charging contracts), as cheetah's [USB-C-PLAN](../cheetah/USB-C-PLAN.md).

## 2. Facts

- [V] With upstream's DT and pmOS's 7.0.6 kernel (2026-10-14,
  [BRINGUP-M1](BRINGUP-M1.md) section 7), dwc3 ran dual-role at
  super-speed-plus, its SS link stayed `SS.Disabled` and USB 2 never
  connected.
- [V] `dr_mode = "peripheral"` without `usb-role-switch` made dwc3 defer
  forever ("failed to get extcon", through the PHY's port graph to the
  TCPC).
- [V] With `orientation-switch` on the PHY, phy-exynos5-usbdrd forced
  `UTMI_FORCE_VBUSVALID | UTMI_FORCE_BVALID` only once a TCPC reported an
  orientation, so dwc3's link stayed `Disconnected`.
- [V] `omamobile` now has `4d015fb82` ("phy: samsung: usbdrd: keep VBUS
  valid until Type-C reports a connection"): with an orientation switch,
  the PHY keeps forcing VBUS valid until the port controller first
  reports an orientation. None of the raven kernels above had it.
- [V] `tcpci_maxim` is blacklisted on raven (`omamobile-raven.conf`), so
  no TCPC driver runs; `omamobile-usb-rescue` closes the MAX77759 data
  switch after an unplug.
- [V] On a wall charger the rescue doesn't change charging (2026-10-27,
  `gb3d6253b0d61`, logged every 2 s with the cable out): `USBSW_CTRL` read
  0x09 the whole time, so the rescue never wrote it, and the battery
  charged at a median of 1.39 A with the rescue running, 1.45 A with it
  stopped and 1.62 A with it running again (rising as the battery warmed,
  40 to 45 %, screen on throughout). This charger never held the switch
  at 0x24, the case the rescue backs off from; that one is untested on
  raven.
- [A] With `4d015fb82`, upstream's description should enumerate as a USB 2
  device: the role switch defaults to peripheral and the PHY keeps VBUS
  valid. SuperSpeed may still not train; device mode over USB 2 is enough.

## 3. U1: upstream's USB description (boot B)

Kernel: `omamobile-gs101-int` without its NOT FOR MERGE USB commit (the
only difference from boot A, [GPU-PLAN](GPU-PLAN.md) G5). Run only after
G5 has passed, on a separate occasion, with time to recover.

**U1.0 (offline, before the day):** build the boot B images from `-int`
with the USB commit reverted, into their own output directory; keep the
boot A images as the rollback. Check that the DTB differs from boot A's
only in `usb@0` (`dr_mode`, `maximum-speed`, `phys`, `phy-names`,
`role-switch-default-mode`) and the PHY's `orientation-switch`.

**U1.1 (push, reboot; the human approves and stays at the phone):**

- **Screen:** the phone reboots.
- **Expect:** SSH within about 60 s as usual.
- **Stop:** no USB device on the laptop after 3 minutes. Do not send
  more commands.
- **Rollback (no USB):** Volume Down + Power about 20 s for fastboot,
  then `bin/omamobile flash` with boot A's `KERNEL_OUT`. Slot A's
  GrapheneOS can't boot over Omarchy's `userdata`, so fastboot is the only
  way back; check before U1.1
  that `fastboot devices` sees the phone from the bootloader.
- **Risk:** high: USB is the only link.

**U1.2 (read-only, if SSH came back):**

```sh
tools/phone-ssh 'dmesg | grep -iE "dwc3|usbdrd|role|extcon|orientation" | head -20
cat /sys/class/udc/*/state /sys/class/udc/*/current_speed
ls /sys/class/usb_role/ 2>/dev/null; cat /sys/class/usb_role/*/role 2>/dev/null'
```

- **Pass:** UDC `configured`, `high-speed` (or better), the role switch
  reads `device`; an unplug and replug still reconnects.
- **Result:** if U1 passes, the NOT FOR MERGE USB commit goes away and
  #2 needs no USB follow-up. If it fails, the peripheral setup stays a
  raven bring-up change, described in this plan.
