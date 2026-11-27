<!-- SPDX-License-Identifier: MIT -->
# OnePlus 8T (kebab) bring-up notes

Findings from one retail OnePlus 8T (`KB2001`, `oneplus,kebab`, Qualcomm
SM8250 / Snapdragon 865), newest first. Every entry says how the phone was
booted and where its root was. All boots so far are `fastboot boot` into
RAM with the root in the shared initramfs; nothing of this port is on the
phone's flash.

## Slots and what is on them (CONTRIBUTING.md §3.1)

**Slot A does not hold stock OxygenOS.** A third-party Android build runs
there; this phone is the owner's development phone and stock is not being
restored. Like enchilada, this port stays RAM-only (`fastboot boot`) until a
slot-B install and its §3.1 entry are agreed.

| Where | What is there now | How it got there |
| --- | --- | --- |
| slot A (`boot_a`, `dtbo_a`, `vbmeta_a`, `super`) | the third-party Android build | its own installer |
| `dtbo_b` | erased | `fastboot erase dtbo_b`, 2026-11-27, after a read-only copy of both `dtbo` partitions (kept off the repository): see first light |
| bootloader firmware | untouched by this port | - |

Slot flags are changed by hand with `fastboot --set-active` to move between
the slots: B for these tests, A to get Android back. A failed mainline boot
marks the active slot unbootable (`slot-unbootable:<slot>:yes`) and ABL then
falls to the other slot; `--set-active` clears that.

## Where the device tree comes from

Linus's tree has no OnePlus 8/8T support. The DTS is
`arch/arm64/boot/dts/qcom/sm8250-oneplus-kebab.dts` from the
[sm8250-mainline tree][tree], branch `sm8250/v6.13`, copied to
`device/kebab/dts/`, with these changes:

- `qcom,board-id = <8 0>, <0 0>` and `qcom,msm-id` v1 and v2.1 (first light,
  point 3);
- a `ramoops` node laid out as stock's (`0xb0000000`, 4 MiB, record,
  console and ftrace 256 KiB, pmsg 2 MiB);
- remoteproc and venus `firmware-name`s under `qcom/sm8250/oneplus/kebab/`.

`tools/build-kebab-kernel` builds that branch (`defconfig` +
`kernel/configs/omamobile.config` + `device/kebab/kernel.config`) in an
arm64 container. The branch is 6.13-based; linux-omamobile would need the
DTS forward-ported.

What the DTS covers (read from the file): simple framebuffer at 0x9c000000
(1080x2376 a8r8g8b8), gpio-keys, Samsung S6SY761 touch, QCA6390 Wi-Fi and
Bluetooth, NXP NCI NFC, BQ25980 charger, BQ27541 gauge, RPMh regulators,
USB 2.0 peripheral on `usb_1`. No modem, camera or IMU nodes. The panel
runs on the bootloader's framebuffer; there is no DSI panel driver yet.

[tree]: https://gitlab.com/sm8250-mainline/linux

## 2026-11-27: RAM-only first light (`fastboot boot`, root in the shared initramfs)

SSH as root over USB NCM at 172.16.42.1,
`6.13.0-rc7-omamobile-push1-gff61dd629750-dirty`, model "OnePlus 8T
(kebab)", UDC `configured`, 11.6 GB of RAM, booted with slot B active. The
init's log and the kernel's are on the framebuffer console. What it took,
in the order it was found:

1. **A downstream `dtbo` breaks every mainline DTB.** In a header-v2 boot
   ABL applies the active slot's `dtbo` overlays to the image's DTB. With
   the Android build's `dtbo` there, every mainline image, ours and a
   mainline image known to have run on this phone before (Linux 7.2.0 for
   sm8250), went black and reset about 13 s after handover, and ABL marked
   the slot unbootable. With `dtbo_b` erased and slot B active, both boot.
2. **Header v2, not v0.** This ABL ignores enchilada's header-v0 image with
   an appended DTB ("Booting OKAY", then it stays in fastboot). It takes
   header v2 with the DTB in its own section at 0x01f00000 (page 4096, the
   offsets below), and a gzip `Image.gz`: the raw 47 MB `Image` gives
   `Failed to load/authenticate boot image: Load Error`. `bin/omamobile
   images` has no such method yet, so these images were packed by hand with
   the pinned `mkbootimg.py` (`--header_version 2 --dtb ... --dtb_offset
   0x01f00000`).
3. **Board ID.** With `qcom,board-id = <0 0>` alone ABL refuses the image
   without a message (it stays in fastboot). `<8 0>, <0 0>` works. This
   unit's `/sys/devices/soc0/revision` reads 2.1, so msm-id v1 and v2.1
   cover it; stock's 19805 DTBs also list v2 (0x20000).
4. **Boot-path drivers built as modules.** The initramfs loads only the USB
   gadget modules, so everything USB needs must be built in. The kernel log
   on screen showed both dwc3 controllers stuck in deferred probe
   (`dwc3: failed to initialize core`, then `no USB device controller
   found`): `PHY_QCOM_USB_SNPS_FEMTO_V2` (sm8250's USB2 PHY,
   `qcom,usb-snps-hs-7nm-phy`) was `m`. `TYPEC_TCPM=m` also turned the
   requested `TYPEC_QCOM_PMIC=y` into a module without a word (the build's
   dropped-option check only catches options that vanish), and
   `INTERCONNECT_QCOM_OSM_L3=m` left cpufreq-hw without its icc path. All
   are built in now (`kernel.config`). The USB 2.0 peripheral node as it is
   in the DTS works; no Type-C link was needed.

Boot image used: header v2, `Image.gz` at 0x8000, the shared initramfs at
0x01000000, DTB at 0x01f00000, tags 0x100, page 4096, command line
`console=tty0 ignore_loglevel loglevel=8 panic=0 clk_ignore_unused
pd_ignore_unused omamobile.initramfs omamobile.ufs-probe`.

**ABL quirks.**

- After a refused image, the next `fastboot boot` answers `Load Error`,
  for any image, until `fastboot reboot bootloader`.
- ramoops can't carry a log across a reset here: ABL or XBL clears
  0xb0000000 on every reboot, even the Android build's own console log
  after a plain `reboot`. The node is in the DTS anyway.
- With no reboot path from the initramfs yet, getting back to fastboot
  takes the buttons: Power + Volume Down held through the restart.

**Host side (macOS).** The initramfs runs no DHCP server, so the laptop
sets 172.16.42.2/24 itself. `networksetup -setmanual` saved the address but
did not apply it; `ifconfig <if> inet 172.16.42.2 netmask 255.255.255.0
alias` did.

Next: the Arch root on `userdata` (the shared init hands off when the
command line has no `omamobile.initramfs`), then the display.

## 2026-11-25: board IDs and first builds (no phone access)

**Board IDs.** The phone's stock DTB blob holds 18 concatenated DTBs
(projects 19805, 19811, 19821, 19855, 20809, 20828, each at SoC v1, v2 and
v2.1). The 8T is project 19805: `qcom,msm-id` `<0x164 0x10000>`,
`<0x164 0x20000>`, `<0x164 0x20001>`; `qcom,board-id` `<0 0>`.

**DTB build.** The `sm8250/v6.13` DTS compiles with dtc 1.7 with no
errors; its warnings all come from `sm8250.dtsi` or the DTS's i2c/spi
alternates (`unique_unit_address`, `interrupt_map`,
`avoid_unnecessary_addr_size`).

**Kernel and initramfs.** `bin/omamobile initramfs` ran in an arm64
container (`DEVICE=kebab`, the pinned `mkbootimg.py` and
`gki/generate_gki_certificate.py`, SHA-256 checked against
`tools/toolchain.lock`). `DRM_MSM` is a module (`QCOM_LLCC` and
`QCOM_OCMEM` are modules); simpledrm gives the console.

## Stock boot image

Header v2, 4096-byte pages, base 0, kernel 0x8000, ramdisk 0x01000000,
tags 0x100, dtb 0x01f00000, separate `dtbo`; `boot` is 96 MiB.
