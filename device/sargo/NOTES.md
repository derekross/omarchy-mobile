<!-- SPDX-License-Identifier: MIT -->
# Pixel 3a (sargo) bring-up notes

Findings from one retail Pixel 3a (`sargo`, Qualcomm SDM670 / Snapdragon
670, 4 GB RAM, 64 GB eMMC, bootloader `b4s4-0.4-8048689`, baseband
`g670-00145-220106-B-8048689`, the last stock build SP2A.220505.008), newest
first. Captures (`fastboot getvar all`, `dmesg`, the stock images) stay off
the repository; facts from them are quoted here. The Pixel 3a XL (`bonito`)
shares the SoC and the bootloader's board name but not the panel.

Every kernel here is linux-omamobile at `00860bdedea4`
(`7.3.0-rc6-omamobile-push1-g00860bdedea4`; from the battery and
Bluetooth entries of 2026-11-25, that plus the commits named there), arm64 defconfig plus
`kernel/configs/omamobile.config` plus [`kernel.config`](kernel.config),
built with Debian's clang 19 instead of the pinned Android clang, and the
upstream `qcom/sdm670-google-sargo.dtb`.

## Slots and what is on them (CONTRIBUTING.md §3.1)

**Slot A does not hold stock Android.** Before this port the owner had
installed another Linux system on this phone: its own boot image on
`boot_a`, its root on `userdata`, and an unsigned `vbmeta` with verification
disabled (`Flags: 2`, `Algorithm: NONE`) on **both** `vbmeta_a` and
`vbmeta_b`. Stock's `system`, `vendor` and `dtbo` are still on both slots
(`dtbo_a` and `dtbo_b` are byte for byte the factory `dtbo.img`). This port
never wrote slot A or `vbmeta`.

| Read (`fastboot getvar all`) | current | A: successful / unbootable / tries | B: successful / unbootable / tries |
| --- | --- | --- | --- |
| 2026-11-24, before anything | a | yes / no / 3 | no / no / 3 |
| 2026-11-24, after eleven refused and six accepted RAM boots | a | yes / no / 3 | no / no / 3 |
| 2026-11-24, after `--set-active=b` | b | yes / no / 3 | no / no / 3 |

Slot B is not marked successful: marking it is a write to the eMMC's GPT
attributes, which needs this phone's CONTRIBUTING.md §3.1 entry. Every boot
of slot B spends one of its three tries; at zero the bootloader starts
slot A, whose system no longer has its root. `fastboot --set-active=b` from
the buttons' fastboot (Volume Down + Power) gives B three tries again.

**Writes made by hand on 2026-11-24**, outside `bin/omamobile` (whose
`flash` and `push` refuse `android-v2`) and `tools/install-phone`, with the
owner's go:

- `fastboot flash userdata` (the root image below, as a sparse image),
  `fastboot flash boot_b`, `fastboot --set-active=b`;
- from the running system, `boot_b` twice more with `dd` (the guard leaves
  exactly the running slot's `boot` and `userdata` writable), each read back
  by sha256;
- into the root, by hand: the kernel modules, `linux-firmware-qcom` and
  `linux-firmware-whence` (`pacman -U -dd`, signatures checked), Arch Linux
  ARM's `mesa`, `vulkan-mesa-implicit-layers` and `vulkan-freedreno`
  26.3.1-3 (signatures checked), and the vendor firmware from
  `tools/extract-vendor-firmware -d sargo`.

## 2026-11-25: Bluetooth (omamobile-device-sargo 0.1.2), and a boot that stayed in RAM

Kernel `7.3.0-rc6-omamobile-push1-g07598f0b0ecc`: the fuel gauge branch
below plus a local branch `omamobile-sargo-bt` (not published), two
commits:

- "arm64: dts: qcom: sdm670: Add QUP UART6": upstream's `sdm670.dtsi`
  describes the QUP serial engines only as I2C. Stock's tree puts the
  Bluetooth UART on serial engine 6 (`hsuart0`, `qupv3_se6_4uart`,
  0x898000) on gpio45-48 (CTS, RTS, TX, RX), function `qup6`; the node and
  its pin states follow SDM845's `uart6`.
- "arm64: dts: qcom: sdm670-google-common: Add Bluetooth": the WCN3990's
  PMU (`qcom,wcn3990-pmu`, the power sequencer) on PM660 L9 (XO, 1.8 V),
  L6 (RF, 1.3 V) and L19 (chain 0, 3.3 V), the rails stock's Bluetooth and
  Wi-Fi nodes name; the controller (`qcom,wcn3990-bt`) on UART6; and the
  first QUP wrapper (`qupv3_id_0`) enabled, which the board left disabled
  (without it the UART never probed). Stock names no I/O supply; L13A comes
  from `sda660-inforce-ifc6560.dts`, which wires the same PMIC to the same
  chip. `dtbs_check` adds no warning for these nodes.

The firmware is Google's, from the vendor partition's `/firmware`:
`crbtfw21.tlv` (ROM patch) and `crnv21.bin` (this board's NV), named by the
DT's `firmware-name` under `qca/sdm670/sargo/`;
`tools/extract-vendor-firmware -d sargo` now copies both. The phone's
`bluetooth_a` and `bluetooth_b` partitions are empty (all zeros).

On the phone: `hci0` came up 11 s into the boot ("setting up wcn399x", SoC
version 0x40010214, ROM 2.1), loaded both files and finished its setup in
1.2 s. The WCN3990 has no address of its own: it comes up unconfigured,
missing its public address, and BlueZ saw no controller. The bootloader
writes the phone's address into the DT at every boot
(`/chosen/cdt/cdb2/bt_addr`, a colon-separated unicast public address);
`btmgmt public-addr` with it configured the controller (it reran its setup)
and the controller reported that address in the DT's byte order. A
15-second scan saw 28 devices, LE among them. Pairing is not tested yet.
`omamobile-bt-addr` (udev, `hci_uart_qca`) does this at every boot; on a
boot from `boot_b` the controller was configured and powered by 24 s of
uptime.

**A boot that stayed in RAM.** The first RAM boot of this kernel stayed in
the initramfs: `init` looked for `userdata` at 1.33 s, the eMMC's
partitions appeared at about 1.7 s, and "arch: no userdata partition"
ended the handover. Earlier boots had won that race. `initramfs/init` now
looks again for up to 10 s; with it, Arch started at 1.95 s (RAM boot) and
2.46 s (from `boot_b`).

**Slot B's tries do run out.** `slot-retry-count:b` read 3 on the morning
of 2026-11-25 and 0 that afternoon, with `slot-unbootable:b:yes`, after
seven boots of slot B since the last `--set-active=b` (2026-11-24), RAM
boots included; with B unbootable, a `fastboot boot` went straight back to
fastboot. `fastboot --set-active=b` gave B three tries again. The note in
the clock entry below that this bootloader might not count down was wrong.
`androidboot.slot_retry_count` on the kernel command line shows the tries
left.

## 2026-11-25: battery and charging (charger, RRADC, fuel gauge)

Kernel `7.3.0-rc6-omamobile-push1-gd230b9b46eaf`: linux-omamobile at
`00860bdedea4` plus a local branch `omamobile-sargo-fg` (not published),
four commits:

- "dt-bindings: power: supply: Add schema for Qualcomm pmi8998 fuel gauge",
  "power: supply: Add driver for Qualcomm PMI8998 fuel gauge" (Joel
  Selvaraj) and "arm64: dts: qcom: pm660: Add fuel gauge" (Richard Acayan),
  patches 1, 2 and 4 of the RFC series "Qualcomm 3rd gen fuel gauge
  support" (David Heidelberg, linux-kernel, 2025-11-24), applied unchanged;
  the driver's author gave his Signed-off-by on the list afterwards;
- the FG node enabled in `sdm670-google-common.dtsi` beside the charger
  (the series' 8/8 enables it in `sdm670-google-sargo.dts`, which in this
  tree holds only what the 3a and 3a XL don't share).

The charger (`qcom,pm660-charger`, `qcom_smbx`) and the RRADC were already
upstream and enabled in the board DTS; arm64 defconfig builds neither.
[`kernel.config`](kernel.config) now sets all three as modules, and they
load from the DT on their own. The driver reads the FG's results and writes
only its memory-interface controls, never the battery profile in FG memory.

On the phone, on the laptop's USB port (a CDP, 875 mA input limit):

- `pm660-charger`: online, CDP, health Good. It reports `voltage_now` and
  `current_now` only while charging, 0 otherwise (by design in the
  driver); the RRADC read the USB input at 5.23 V, 60 mA.
- `qcom-battery`: capacity 99 %, 4.23 V, 26.0-26.5 °C, Li-ion, 3000 mAh
  design (from the board DTS); UPower's display device showed 99 %,
  `fully-charged`.
- USB input paused for 3 minutes (`Unknown` written to the charger's
  `status`, which sets the PMIC's USBIN suspend bit; a dead-man timer would
  have cleared it): the charger went offline, the battery drew 45-95 mA
  (`current_now` negative) and fell from 4.232 to 4.207 V, and USB data
  stayed up. Input back on: 20 mA into the battery, status Full (99 % is
  above the recharge threshold, so a full charge cycle is not shown yet).
- The image was RAM-booted first (`fastboot boot`), then written to
  `boot_b` from the running system (read back by sha256) and booted from
  there; the earlier `boot_b` is kept off the repository as the rollback.

Known gaps: the battery's status follows the charger only when the charger
signals a change. Pausing the input by register write signals nothing, so
the battery stayed `Full` while discharging; a real unplug raises the
`usb-plugin` interrupt and should signal it, but that is untested, since
the cable is the only link. Charging from below the recharge threshold,
the readings near empty, and UPower's critical-battery power-off on this
phone are not qualified yet.

## 2026-11-25: the clock keeps time across reboots (omamobile-device-sargo 0.1.1)

The PM660's RTC (`rtc-pm8xxx`, `rtc0`) runs through reboots and through
time in fastboot, but Linux can't set it: `pm660.dtsi`'s RTC node has no
`allow-set-time`, and the board has no nvmem cell or UEFI variable for an
offset, so the driver refuses every write. Its count starts at the epoch
(it read 1970-01-31 18:43, about 30 days of counting, on 2026-11-25), and
the kernel starts the clock there.

`omamobile-rtc-offset` keeps the difference between the clock and the RTC
in `/var/lib/omamobile/rtc-offset`, as Android does in its own storage. Its
unit sets the clock early in sysinit (before `time-set.target` and
timesyncd), moves it forward only, and falls back to the time of the last
save when the RTC reads earlier than it did then (an RTC reset). Saves come
at shutdown, every 15 minutes and after each timesyncd sync, and are
skipped while the clock is before 2026. Save and restore both wait for the
RTC's next one-second tick: the first version, without that, came back
2-3 s slow after a reboot, a second of rounding each way.

On the phone (`7.3.0-rc6-omamobile-push1-g00860bdedea4`):

- `reboot-to bootloader`, 60 s in fastboot, `fastboot reboot`: clock set at
  11.1 s of uptime, the fastboot minute included (first version, 2-3 s
  slow).
- The clock set from the laptop, saved, put an hour back, `restore`: 30-60
  ms from the laptop's clock.
- `systemctl reboot`: clock set at 11.7 s of uptime (the tick wait costs up
  to a second there), then within 0.1 s of the laptop's clock, measured over
  SSH, with no network on the phone.

`fastboot getvar all` read `slot-retry-count:b:3` and `slot-successful:b:no`
on 2026-11-25. (This entry first said the bootloader might not count tries
down; it does, see the Bluetooth entry above.)

## 2026-11-24: Omarchy on slot B, display, GPU and touch

Booted from slot B (`androidboot.slot_suffix=_b`), the shared initramfs
guarded the eMMC (allowlist `boot_b userdata`), grew the root from 10880 MiB
to 51163 MiB in 7 s and switched to Arch on `/dev/mmcblk0p72`. First boot
created the user and host from `firstboot.conf` and deleted it; SDDM
started the user's Hyprland session through uwsm with the Omarchy shell and
the phone helpers. Root image: `tools/build-rootfs --local sargo` (packages
fetched from the stable channel, `omamobile-device-sargo` 0.1.0 built here).

What works: USB networking and SSH (link-local IPv6; the Mac needs an IPv4
address on its side for 172.16.42.1), the display through msm (DPU, DSI,
`samsung,s6e3fa7-ams559nk06`, 1080x2220 at 60 Hz), the Adreno 615 as
Hyprland's renderer (`/dev/dri/card1`, Mesa's freedreno), touch (Synaptics
S3706B over I2C, RMI4 F12), the power and volume keys, CPU frequency scaling,
and the eMMC guard.

What it took, each a step that failed first:

- **The panel driver** (`DRM_PANEL_SAMSUNG_S6E3FA7`) is not in arm64
  defconfig. Without it msm's DPU, DSI and GPU probe but the DRM device never
  assembles, and Hyprland, with only simpledrm, has no renderer: it ran but
  drew nothing, and the screen kept the initramfs's last lines.
- **Mesa's Adreno driver.** The project's `mesa` is built with
  `gallium-drivers=panfrost,llvmpipe,softpipe,zink` (packages/mesa): with
  it, EGL on msm fails with "DRI2: failed to load driver". Arch Linux ARM's
  Mesa has freedreno and works. `packages/mesa` needs `freedreno` (and
  Turnip, `vulkan-drivers=freedreno`) for this phone.
- **GPU firmware.** `qcom/a630_sqe.fw` and `qcom/a630_gmu.bin` come from
  linux-firmware (`linux-firmware-qcom`), which the root image does not
  install; the zap shader is the owner's (`qcom/sdm670/sargo/a615_zap.mbn`).
- **Touch** needs `RMI4_CORE`, `RMI4_I2C` and `RMI4_F12`, none in defconfig.
- **The clock.** The PMIC's RTC can't be set from Linux on this phone, and
  with no network the clock starts at 1970: pacman then refused Arch Linux
  ARM's signatures ("key created 16058 days in the future"). Set it by hand
  (`date -s`) until the phone has network time or an RTC offset (the
  offset came on 2026-11-25, above).

Not working yet (on that kernel; battery and charging came on 2026-11-25,
above, Bluetooth too): battery and charging (no power supply registers),
Wi-Fi, Bluetooth, modem, audio, sensors, cameras, suspend. Plymouth's unit fails.

## 2026-11-24: the eMMC guard on the phone (RAM boot)

A RAM boot (`fastboot boot`) with the eMMC driver built in and
`UFS_RW_LUNS=mmcblk0`: `mmc0` with `mmcblk0` (72 partitions) and the boot
areas `mmcblk0boot0/1`. The guard removed `/dev/mmcblk0` and
`/dev/mmcblk0rpmb`, set both boot areas and 70 partitions read-only, and
left the running slot's `boot` (`boot_a` on a RAM boot from slot A) and
`userdata` writable. Nothing was mounted or written.

## 2026-11-24: first light, and what this bootloader wants

`fastboot boot` of a mainline image fails in ABL with "Error verifying the
received boot.img: Invalid Parameter". What did not change that: header v0
with the DTB appended, header v2, gzip or LZ4-frame kernels, padding to the
64 MiB partition, an AVB hash footer, the ramdisk and DTB moved above the
43 MiB kernel, `text_offset` 0x80000 alone, `qcom,msm-id`/`board-id` alone.
Stock's own `boot.img` booted (and so did a copy with one padding byte
changed, but with `vbmeta` verification disabled on this phone that says
nothing about a stock `vbmeta`). Our kernel and initramfs with stock's DTB
section were accepted. So the DTB was what ABL refused: it merges the stock
`dtbo` overlay for this board (`androidboot.dtbo_idx=9`) into the DTB, and
those overlays fix up 153 labels of Google's downstream tree that a mainline
DTB doesn't have.

The image that boots (`BOOT_METHOD=android-v2` in
[`device.conf`](device.conf), built by `bin/omamobile images`):

- header v2 as stock's (4096-byte pages, kernel at 0x8000, ramdisk at
  0x01000000, tags at 0x100, DTB at 0x01f00000, OS 12.0.0, patch 2022-05);
- the `Image` header's `text_offset` set to 0x80000 (stock's; mainline has
  0 since Linux 5.8; the Pixel 4's bootloader wants the same,
  device/coral/BRINGUP-M1.md §3), the kernel as an LZ4 frame;
- the DTB with stock's `qcom,msm-id = <0x150 0x0>` and
  `qcom,board-id = <0x0 0x0>`, and a sink for the 153 labels
  (`tools/dtbo-sink`, from the owner's `dtbo.img`): one disabled node per
  label and symbols for those labels only. Every overlay merges into the
  sink and the kernel populates nothing there.

After the merge the running board's root `compatible` is the overlay's,
`google,b4s4-sdm670`, `qcom,sdm670` (and `model` the overlay's), so the
descriptor's `COMPATIBLE` is that. The 3a XL's overlays carry the same name.

First light, from RAM and the eMMC driver left out of the kernel: USB
gadget up 32 s after `fastboot boot`, SSH, simpledrm on the bootloader's
framebuffer, the three keys; `reboot-to bootloader` reaches fastboot
through the PON's reboot mode (`mode-bootloader = <0x2>` in `pm660.dtsi`),
so the loop needs no buttons. `CONFIG_INTERCONNECT_QCOM_SDM670` is needed
too: newer upstream defaults it on, this kernel doesn't, and without it USB
and cpufreq wait for a provider.

## Firmware (`tools/extract-vendor-firmware -d sargo`)

From the SP2A.220505.008 factory image's vendor partition, all present and
ELF where the map says: `a615_zap` and `ipa_fws` as split ELFs (`.mdt`
renamed `.mbn`, segments `.b00`-`.b02` and `.b00`-`.b04` beside), `adsp`,
`cdsp`, `venus`, `wlanmdsp`, and the remote processors' `.jsn` lists, under
`qcom/sdm670/sargo/`. Not in the vendor partition: the modem's `mba.mbn` and
`modem.mbn` (the phone's `modem` partition) and the audio DSP's calibration
database (`Global_cal.acdb`, which the Q6 core driver needs before the sound
card probes).

## What comes next

1. `packages/mesa` with freedreno and Turnip; the device package depends on
   `linux-firmware-qcom`; the root image then needs nothing by hand.
2. The release kernel: the options in [`kernel.config`](kernel.config) into
   the shared config, or the phone keeps a development kernel.
3. This phone's CONTRIBUTING.md §3.1 entry (slot B's GPT mark), then
   `flash`/`push` and the installer for `android-v2`.
4. The fuel gauge and Bluetooth into linux-omamobile, then Wi-Fi: the modem
   processor first (remoteproc nodes for SDM670, `rmtfs` read-only from RAM,
   and a read-only backup of `modemst1`, `modemst2`, `fsg` and `persist`,
   which `tools/nv-backup` can't read from eMMC yet).
