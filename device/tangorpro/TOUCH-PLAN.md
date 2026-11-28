<!-- SPDX-License-Identifier: MIT -->
# Pixel Tablet touch: NT36523N on SPI

**Status (2026-11-26):** driver, binding and board node on linux-omamobile branch `omamobile-tangorpro-touch` (worktree `wt-tangorpro-touch`, on top of `omamobile-tangorpro` `73a989d1f`), built as a module with `device/tangorpro/kernel.config` (kernel `7.3.0-rc6-omamobile-push1`). checkpatch `--strict` clean but for the missing human sign-off, `W=1` clean on the driver and the DTB, `dt_binding_check` clean, `dt-validate` 0 warnings on the DTB with and without `overlays/touch.dtso`. Not run on the tablet yet. The node is disabled; `overlays/touch.dtso` turns it on for one gated boot.

## Goal

1. Fingers reach Hyprland: ten-finger multitouch, protocol B, on the 1600x2560 portrait panel.
2. A missing firmware file, a wrong chip or a silent chip fails the probe cleanly: no hang, no oops, the display untouched.
3. Later, not here: the stylus (USI), suspend with the chip's deep-sleep command, panel-matched firmware picked without a DT edit.

## Path abbreviations

- `GT/` = Google's tablet DT, `google-tangorpro-dt/dts/` (gs201-tangorpro-touch.dtsi, -pmic.dtsi, -display*.dtsi).
- `G2/` = Google's gs201 DT, `google-gs201-dt/dts/gs201-common-touch.dtsi`.
- `GN/` = Google's GPL Novatek driver, `google-novatek-touch/nt36xxx/` (branch android-gs-tangorpro-6.1-android16, `ab0784a`).
- `F/` = factory image CP1A.260505.005.
- `L/` = linux-omamobile, branch `omamobile-tangorpro-touch`.

## Facts

- [V] The controller is the touch half of the panel's Novatek NT36523N touch and display chip, on USI0 SPI: `GT/gs201-tangorpro-touch.dtsi` `&spitouch` (`compatible = "novatek,NVT-ts-spi"`, `reg = <0>` on `&spi_0`).
- [V] Same pins as the Pixel 7: chip select gpp20-3, interrupt gpa7-0, reset gpp23-2 (`GT/...-touch.dtsi:33,45-46`, `G2/...-common-touch.dtsi:9-13`).
- [V] 15 MHz (`spi-max-frequency`), 1 µs chip select to clock (`controller-data { cs-clock-delay = <1>; }`), interrupt on the rising edge (`novatek,irq-gpio = <&gpa7 0 0x2001>`, IRQF_TRIGGER_RISING), no pull on the interrupt or reset (`G2/...-common-touch.dtsi` `ts_irq`, `ts_reset`; tangorpro does not override them).
- [V] **No supply of its own.** `G2` gives the touch node `vdd-supply = <&m_ldo25_reg>` and `avdd-supply = <&m_ldo26_reg>`, but on the tablet LDO25M is `L25M_DISP_BL` (the backlight's enable supply, `GT/...-pmic.dtsi:19-26`, `GT/...-display.dtsi:40,68`) and LDO26M is `L26M_ACC_DETECT` (pogo, `GT/...-pmic.dtsi:59-62`), and `GN/nt36xxx.c` switches no regulator. The chip runs from the panel's rails (VDDI is LDO24M, `GT/...-display-common.dtsi:17`), which the bootloader leaves on for the framebuffer. The board node therefore has no supply, and the Pixel 7's LDO25M/LDO26M node must not be copied.
- [V] Flashless (host download). Stock's `F/vendor_dlkm/lib/modules/nvt_touch.ko` has the "Download Firmware failed" and "full download" paths and none of the SPI-flash (GCM) code. `GN/Kbuild` builds the flash variant only with `CONFIG_TOUCHSCREEN_SPI_FLASH`.
- [V] Firmware by panel: `novatek,firmware_names = "novatek_ts_fw.bin", "novatek_ts_fw_csot.bin"` with `novatek,panel_map` mapping the BOE ts110f5mlg0 panels to the first and the CSOT ppa957db2d panels to the second (`GT/...-touch.dtsi:47-57`). Both are in `F/vendor/firmware/`, 196608 bytes each: BOE sha256 `d032484be13f8bec1821d919efb840c337efc51632bfce764001f409787dec26`, CSOT `e7028230ef4af091254dcab98b396a754d53085420ad04091df9c0a1c4b5f334`.
- [V] Both images parse with `GN/nt36xxx_fw_update.c`'s header rules: "NVT" end flag at 0x30000, version 0x1d, cascaded header (0x200), no overlays, 16 sections of which ILM (0x198dc bytes to SRAM 0, CSOT 0x19904), DLM (0xb7c0 to 0x20000) and two 0x100-byte header sections are written.
- [V] Chip id at 0x3f004: `17 xx xx 23 65 03` (`GN/nt36xxx_mem_map.h` trim table, `tid_nt36523n` in `GN/nt36xxx_goog.h`). Memory map `NT36523N_memory_map` (event buffer 0x2fd00); `swrst-n8-addr` 0x3f0fe and `spi-rd-fast-addr` 0x3f310 from `GT/...-touch.dtsi`. NT36523N has the hardware CRC (`hw_crc = 2`), so the download is `nvt_download_firmware_hw_crc()`.
- [I] The SPI lines may pass a mux to the AoC (Google's `touch_bus_negotiator`, `ap2aoc` on gph1-0, "Low: AP"). The Pixel 7's and 7 Pro's touch nodes work without driving it, so the bootloader leaves the bus with the AP; check on the tablet.
- [I] The panel on a given tablet (BOE or CSOT) is unknown until read: look for the panel name on the kernel command line or in `/proc/bootconfig` from stock.

## Design

A new driver, `drivers/input/touchscreen/novatek-nt36523.c` (compatible `novatek,nt36523n-ts`, in the style of `novatek,nvt-ts.yaml`), not the 2024 "Novatek NT36xxx" SPI RFC (George Chan, never merged): that series has no NT36523N entry and builds on a regmap with a fake 32-bit register, and its review never finished. The protocol is ported from `GN/` into ~840 lines: the window framing, the engineering and boot loader resets, the chip-id check, the image parser, the CRC-checked download, the firmware-info read, the 65-byte report and Google's watchdog recovery (reload the firmware after more than ten 0xfd/0xfe frames). Left out: pen, heatmaps, gestures, the MP self-test, Google's touch interface.

- The firmware comes from `request_firmware()` with the DT's `firmware-name` (required: the image is panel-specific). It is requested before the chip is touched, so a missing file fails the probe with the chip as the bootloader left it.
- Every wait is bounded (chip id 5 tries, boot state 11 polls of 10 ms, SPI DMA 200 polls of 1 ms, 3 download attempts), so a silent chip ends in `-ENODEV` or `-ETIMEDOUT`.
- The touch reset is only pulsed, as Google's driver does, and is left released on failure and removal: the chip also drives the display, and a held touch reset is untested there.
- Axes from the firmware's info block; the DT's `touchscreen-size-x/-y` (1600x2560, Google's `DEFAULT_MAX_WIDTH/HEIGHT`) wins when given.

## What was built

| Commit (L/) | What |
| --- | --- |
| `8450fc8ee` dt-bindings: input: touchscreen: Add Novatek NT36523N | `novatek,nt36523n-ts.yaml` |
| `e82ba2398` Input: add Novatek NT36523N SPI touchscreen driver | `novatek-nt36523.c`, Kconfig, Makefile, MAINTAINERS |
| `68fe3dfc6` arm64: dts: exynos: google: gs201-tangorpro: describe the touchscreen | the node, disabled |

This repository: `kernel.config` (`CONFIG_TOUCHSCREEN_NOVATEK_NT36523=m`), `overlays/touch.dtso`, `extract-touch-fw` (stages both images as `novatek/nt36523n-tangorpro-{boe,csot}.bin` under `/usr/lib/firmware/updates`), this plan.

## Risks

- The download writes only the chip's SRAM; there is no flash to damage. A wrong image (BOE on CSOT) gives bad or no touch, not damage.
- The touch and display share a chip. The probe pulses the touch reset for ~2 ms, as stock does every boot with the panel lit. If the display glitches at that moment, stop.
- A hang inside `spi_sync` would stall the probe's thread, not the system; the SPI controller's own timeouts bound it.

## Runbook

Each step needs the human. Rollback for any boot: slot B images built without `touch`, or `modprobe -r novatek-nt36523` and the blacklist below.

### 1. Firmware onto the tablet (no boot)

```sh
device/tangorpro/extract-touch-fw -o out/touch-firmware <factory zip or image zip>
tar -C out/touch-firmware -cf - usr | tools/phone-ssh 'tar -C / -xf -'
```

**Expect / pass:** both files under `/usr/lib/firmware/updates/novatek/` with the sha256 above. **Stop:** a mismatch. **Rollback:** delete the two files. **Risk:** none.

### 2. Blacklist, then the overlay image

On the tablet: `echo 'blacklist novatek-nt36523' > /etc/modprobe.d/omamobile-touch.conf`. On the laptop, build with this branch (the fragment makes the module), install its modules as usual, and for this pack only add `DTB_OVERLAYS="touch"` to `device/tangorpro/device.conf`, run `DEVICE=tangorpro bin/omamobile images`, then remove the line (do not commit it).

**Expect / pass:** the pack prints `DTB overlays: touch`. **Stop:** the overlay fails to apply. **Risk:** low.

### 3. Boot, then load by hand

After the boot: `ls /sys/bus/spi/devices/` shows `spi0.0`; then `modprobe novatek-nt36523; dmesg | grep -i nt36523`.

**Expect / pass:** `firmware 0x1d, PID 0x..., 32x50 channels, 1600x2560` (or the firmware's own size), and `evtest` on the new "Novatek NT36523N" device shows ABS_MT_POSITION_X/Y for each finger, 0..1599 across and 0..2559 down in portrait.

**Stop:** `no NT36523N found (id ...)` (copy the bytes), `firmware did not start (state ..., CRC flags ...)`, `firmware info is broken`, any display change, or no interrupts (`grep nt36523 /proc/interrupts` stays at 0 while touching). **Rollback:** `modprobe -r novatek-nt36523`. **Risk:** low.

If touch works but is wrong, check which panel the tablet has; a CSOT tablet needs `firmware-name = "novatek/nt36523n-tangorpro-csot.bin"`.

## Results

None yet.

## Open questions

- Which panel this tablet has, and whether the firmware-name should follow it automatically (a panel driver, or two compatibles).
- Whether the AoC bus mux (gph1-0) needs to be driven low by Linux.
- Suspend: the chip keeps running; Google's driver sends a deep-sleep command and reloads the firmware on resume.

## Results

### 2026-11-26: T1, the probe (Arch running from slot B, no reboot)

The modules from this kernel (with the driver) were unpacked into
`/usr/lib/modules/7.3.0-rc6-omamobile-push1`, the BOE image staged at
`/usr/lib/firmware/updates/novatek/nt36523n-tangorpro-boe.bin` (sha256
`d032484b…`), autoload blacklisted
(`/etc/modprobe.d/omamobile-touch-bringup.conf`), and the board's touch
node enabled by `overlays/touch.dtso`.

- **First load:** `spi0.0` (modalias `spi:nt36523n-ts`) probed and read
  the chip id over SPI: `0a 00 01 23 65 03`. The driver only accepted
  `0x17` (NT36523N) and gave up cleanly, no hang, no display change.
  **This tablet's chip is the NT36523**, not the NT36523N: Google's trim
  table maps 0x0a/0x0b/0x0c/0x20 to `NT36523_memory_map` (event buffer
  0x2fe00, no SPI DMA divider) and 0x17 to `NT36523N_memory_map` (event
  buffer 0x2fd00).
- **The fix:** the driver picks the revision from the chip id; the
  binding and compatible became `novatek,nt36523-ts`.
- **Second load** (`insmod`, then `driver_override` to bind the rebuilt
  driver to the running `spi0.0`): firmware downloaded, CRC accepted,
  `firmware 0x1d, PID 0x7803, 32x50 channels, 1600x2560`, input device
  created, its interrupt (gpa7-0, rising) registered and fired once, and
  Hyprland lists it under "Touch". **No supply was needed**: the panel's
  rails the bootloader leaves on are enough, as planned.
- **Not yet done:** a finger on the glass (`evtest`, Hyprland taps). The
  bring-up ran with nobody at the tablet.
