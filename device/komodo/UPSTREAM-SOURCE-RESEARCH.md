<!-- SPDX-License-Identifier: MIT -->
# Komodo upstream source research

**Checked 2026-11-18.** Source-only research for the Pixel 9 Pro XL first-light
port. No new device access or firmware binaries were used; the phone facts
below come from the sanitized system metadata in the owner's stage-0 capture.
Public source links are pinned to the revisions inspected.

## Verified matches

- The phone's targeted, private ADB capture reports `komodo`, SoC platform
  `zumapro`, hardware revision `MP1.0`, `ro.boot.dtbo_idx=34`, and
  `ro.boot.hw.soc.pkg_mode=0` on Android 17 build `CP4A.261105.040.A1`. A second
  targeted read returned `ro.boot.hw.soc.rev=1`; product ID and major/minor
  properties were empty (private `R/post-update-targeted.txt`).
- In Google's public Caimito Android 16 source, the zero-based entry 34 in
  [`constants.bzl`](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/constants.bzl#42)
  is `zumapro-komodo-mp.dtbo`. The overlay declares board ID `0x60806`, board
  revision `0x010000`, and `google,ZUMA PRO KOMODO` compatibility
  ([source](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/dts/zumapro-komodo-mp.dts#16)).
  This is a strong MP-board match to the phone's `dtbo_idx` and revision
  string, but only for the published Android 16 source revision.
- That MP overlay includes shared Zumapro/Caimito definitions and the Komodo
  board includes, including the board-specific display and touch files
  ([MP overlay](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/dts/zumapro-komodo-mp.dts#11),
  [Komodo common](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/dts/zumapro-komodo-common.dtsi#8)).
- Komodo's Google GPL display source describes 1344×2992 and 1008×2244 modes
  ([`zuma-komodo-display.dtsi`](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/dts/zuma-komodo-display.dtsi#12)).
  It establishes panel modes, not the ABL handoff framebuffer's address,
  dimensions, pixel format, stride, or allocation.
- The shared Google Caimito USB source sets the USB device controller and
  USB2 PHY extcons to the MAX77759 TCPC, enables SuperSpeed on DWC3, and
  configures an eUSB repeater
  ([`zuma-caimito-usb.dtsi`](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/dts/zuma-caimito-usb.dtsi#8)).
  This gives a board-source lead for USB gadget networking, but does not by
  itself prove that the mainline configuration works on this phone.
- The sibling Google Zumapro Android 16 source is a closer USB-family match:
  its `zumapro-ripcurrentpro-usb.dtsi` attaches the UDC and USB2 PHY to the
  MAX77759 TCPC, requests SuperSpeed, and configures a Samsung eUSB repeater
  at HSI2C address `0x3e` with LDO19 power. Its shared `zumapro-common.dtsi`
  assigns HSI0 sub-power-domain rails to LDO8, LDO9, and LDO19, while
  `zumapro-pmic.dtsi` labels those rails USB/eUSB2
  ([USB](https://android.googlesource.com/kernel/devices/google/zumapro/+/915d1f0ccf770fc1d9af1ae5223331c13029d51b/dts/zumapro-ripcurrentpro-usb.dtsi),
  [common](https://android.googlesource.com/kernel/devices/google/zumapro/+/915d1f0ccf770fc1d9af1ae5223331c13029d51b/dts/zumapro-common.dtsi),
  [PMIC](https://android.googlesource.com/kernel/devices/google/zumapro/+/915d1f0ccf770fc1d9af1ae5223331c13029d51b/dts/zumapro-pmic.dtsi)).
  The current mainline tree does not have the Samsung eUSB repeater driver, so
  that node is not a usable port as-is.
- Mainline Tegu provides a different, USB2-only peripheral setup on Zumapro:
  DWC3 in peripheral/high-speed mode with four HSI0 clocks and the eUSB PHY
  supplied by LDO8/LDO9. This is a useful driver/API reference, but its PMIC
  interrupt and board wiring are Tegu evidence only
  ([Tegu DTS](https://github.com/derekross/linux-omarchy-mobile/blob/26867fc4e826a03d1095341af50b6165d4ea5164/arch/arm64/boot/dts/exynos/google/zumapro-tegu.dts#L211)).
  The exact Komodo USB/TCPC-to-mainline translation and regulator control
  remain unproven; keep USB disabled in Komodo's board file until they are
  resolved rather than treating the Tegu wiring as interchangeable.
- The current kernel tree already has the MAX77759 data-switch behavior: its
  Maxim TCPM driver closes register `0x93` on attach and updates the switch
  when a PD partner reports USB communications capability. The binding accepts
  the two-string compatible `maxim,max77759-tcpci`, `maxim,max33359`, which
  falls through to the driver's MAX33359-compatible variant. I initially
  missed this existing implementation; the claim that it was absent was
  incorrect. What remains unverified is the exact Komodo I2C bus, IRQ, pin
  state, connector description, and regulator wiring needed to bind and use
  the path on this board
  ([TCPCI binding](https://github.com/derekross/linux-omarchy-mobile/blob/26867fc4e826a03d1095341af50b6165d4ea5164/Documentation/devicetree/bindings/usb/maxim,max33359.yaml),
  [`tcpci_maxim_core.c`](https://github.com/derekross/linux-omarchy-mobile/blob/26867fc4e826a03d1095341af50b6165d4ea5164/drivers/usb/typec/tcpm/tcpci_maxim_core.c)).
- The Google Caimito Type-C source uses HSI2C6 for this MAX77759 family,
  assigns SDA/SCL to `gpp12-0`/`gpp12-1`, and routes the TCPC interrupt to
  `gpa8-3`. Mainline Zumapro exposes the matching HSI2C6 controller at
  `0x108d0000` and the same GPIO bank; Tegu's mainline DTS independently uses
  the same bus, pins, and interrupt. These are a strong shared-family mapping
  for a Komodo test overlay, but remain Android 16 / sibling-board source
  evidence until the live Komodo DT is available
  ([Tegu mainline Type-C](https://github.com/derekross/linux-omarchy-mobile/blob/26867fc4e826a03d1095341af50b6165d4ea5164/arch/arm64/boot/dts/exynos/google/zumapro-tegu.dts#L504),
  [Google Caimito Type-C](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/dts/zuma-caimito-typec.dtsi),
  [Google shared MAX77759 node](https://android.googlesource.com/kernel/devices/google/zuma/+/refs/tags/android-16.0.0_r0.1/dts/max777x9-tcpc.dtsi)).
- The existing Omarchy Mobile initramfs can reopen the MAX77759 USB2 switch
  directly as a fallback, using the descriptor's controller path and address;
  this is already used for the MAX77759 family on other devices. For Komodo,
  `108d0000.i2c 0x25` is the source-derived candidate, not yet a device-verified
  descriptor value. The fallback needs the HSI2C6 controller and its pin state
  to work before the normal root filesystem is available.
- The Omarchy kernel base has matching `google,zuma-usb32drd-phy`,
  `google,zumapro-eusb2-phy`, generic DWC3, and MAX33359 TCPCI fallback-driver
  support. Its current build config has DWC3 and the Zumapro USB3 PHY built in,
  while TCPM/Maxim TCPCI are modules. The Android 16 Caimito config uses a
  MAX77759 Type-C controller and eUSB repeater; exact Komodo regulator, pin,
  and I2C wiring still needs translation. Do not use Tegu's MAX77779 or its
  board-specific rails as substitutes.
- In the inspected Omarchy kernel base (`26867fc4e826`), the Zumapro SoC DTS
  already defines DWC3 at `0x11210000`, USB32 PHY at `0x11100000`, and eUSB2
  PHY at `0x11110000`; those nodes start disabled. Tegu's board DTS enables a
  peripheral-mode, high-speed USB path. These are reusable SoC/driver starting
  points, not proof that Tegu's board wiring applies to Komodo
  ([Zumapro SoC DTS](https://github.com/derekross/linux-omarchy-mobile/blob/26867fc4e826a03d1095341af50b6165d4ea5164/arch/arm64/boot/dts/exynos/google/zumapro.dtsi#L1044),
  [Tegu USB nodes](https://github.com/derekross/linux-omarchy-mobile/blob/26867fc4e826a03d1095341af50b6165d4ea5164/arch/arm64/boot/dts/exynos/google/zumapro-tegu.dts#L873)).
- The same kernel base's Tegu DTS reserves the ABL splash at `0xfac00000` with
  size `0x009fc900`, then attaches it to Tegu's display engine. That reservation
  is paired with Tegu-specific panel information and must not be copied as
  Komodo evidence ([Tegu DTS](https://github.com/derekross/linux-omarchy-mobile/blob/26867fc4e826a03d1095341af50b6165d4ea5164/arch/arm64/boot/dts/exynos/google/zumapro-tegu.dts#L176)).

## Important unknowns

- `ro.boot.dtbo_idx=34` identifies an applied overlay index; it does not
  establish the base Zumapro DTB selection. The new targeted check verifies
  FOPLP package mode (`ro.boot.hw.soc.pkg_mode=0`) and SoC revision 1
  (`ro.boot.hw.soc.rev=1`), but it does not
  expose the bootloader selector's `product_id`, `major`, or `minor` fields.
  Google's Zumapro base DTBs match those fields; the source has distinct FOPLP
  (`pkg_mode=0`) and IPOP (`pkg_mode=1`) variants
  ([A0 FOPLP](https://android.googlesource.com/kernel/devices/google/zumapro/+/915d1f0ccf770fc1d9af1ae5223331c13029d51b/dts/zumapro-a0-foplp.dts#9),
  [A0 IPOP](https://android.googlesource.com/kernel/devices/google/zumapro/+/915d1f0ccf770fc1d9af1ae5223331c13029d51b/dts/zumapro-a0-ipop.dts#9)).
  The source's `0x9875`, major 0, minor 0/1 FOPLP selector tuples are therefore
  included as public-source candidates, not represented as live-read values.
- The Google Caimito board files inspected are from
  `android-gs-caimito-6.1-android16` (commit `38a058681d6c`); the sibling
  Zumapro source is `android-gs-comet-6.1-android16` (commit `915d1f0ccf77`).
  The phone now runs Android 17. A live `git ls-remote --heads` of Google's
  public Caimito repo returned Android 16 branch refs and no Android 17-named
  ref; Google's kernel build guide also lists Pixel 9 Pro XL on the Android 16
  Caimito branch. No exact Android 17 public board source was found in this
  review. Thus the MP mapping remains a candidate match, not an exact-build
  reconstruction
  ([Google kernel guide](https://source.android.com/docs/setup/build/building-pixel-kernels),
  [Caimito source](https://android.googlesource.com/kernel/devices/google/caimito/)).
- After the authorized reset, Android booted successfully, but `ro.build.type`
  is `user`. ADB shell cannot read the live device-tree property files or
  `/proc/iomem`, so Android does not provide the needed framebuffer/memory
  handoff values without additional privilege.
- Google's Zumapro reserved-memory source has shared fixed regions, while the
  bootloader also supplies secure reservations; Komodo's ABL framebuffer
  reservation and handoff geometry remain unverified
  ([`zumapro-rmem.dtsi`](https://android.googlesource.com/kernel/devices/google/zumapro/+/915d1f0ccf770fc1d9af1ae5223331c13029d51b/dts/zumapro-rmem.dtsi#13),
  [Tegu's board-specific splash reservation](https://github.com/derekross/linux-omarchy-mobile/blob/26867fc4e826a03d1095341af50b6165d4ea5164/arch/arm64/boot/dts/exynos/google/zumapro-tegu.dts#L176)).

## Port implications

1. Keep the public-source FOPLP selector tuples marked as candidates; keep
   splash geometry unresolved until public source or non-invasive device
   evidence establishes it. A non-default USB2 test overlay now maps the
   supported mainline DWC3/eUSB2 and MAX77759 TCPCI paths using Google
   Caimito/Zumapro and mainline Tegu evidence. It compiles and applies, but is
   not selected by a device descriptor and remains untested on Komodo. Keep
   USB disabled in the base DT; keep the eUSB repeater, SuperSpeed, and other
   unproven features disabled.
2. Keep the Tegu panel/splash and board wiring out of Komodo's DTS. Reuse the
   existing Zumapro SoC nodes only where the Google source and mainline binding
   support agree.
3. The new minimal Komodo board DTB builds and validates against the current
   bindings. It does not enable display or USB and is not a bootable first-light
   image; do not install it until the live DT and recovery plan are established.
