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
| `userdata` | Omarchy's root image for this port (the Android build's data is gone) | `fastboot flash userdata` of a sparse image, 2026-11-28 |
| bootloader firmware | untouched by this port | - |

Slot flags are changed by hand with `fastboot --set-active` to move between
the slots: B for these tests, A to get Android back. A failed mainline boot
marks the active slot unbootable (`slot-unbootable:<slot>:yes`) and ABL then
falls to the other slot; `--set-active` clears that.

## Where the kernel and device tree come from

Linus's tree has no OnePlus 8/8T support. Since 2026-11-28 the kernel is
the [sm8250 tree][tree72]'s tag `sm8250-7.2.0_git20261010` (Linux 7.2.0),
whose `sm8250-oneplus-kebab.dts` and `sm8250-oneplus-common.dtsi` describe
the phone: board id `<8 0>` (MTP) with msm-id v1 and v2.1, ramoops at
0xb0000000, the Samsung AMB655X DSI panel, Synaptics S3908 touch, USB
through the PM8150B Type-C port (role switch, FSA4480 mux), Adreno 650,
QCA6390 Wi-Fi and Bluetooth, the remoteprocs. The same tree carries the
OnePlus 8 Pro (`sm8250-oneplus-instantnoodlep.dts`).

`tools/build-kebab-kernel` fetches mainline `v7.2` from GitHub and only
the tree's commits since then from its own (slow) server, appends
`device/kebab/dts/omamobile.dtsi` to the board DTS, and builds `defconfig`
+ `kernel/configs/omamobile.config` + `device/kebab/kernel.config` in an
arm64 container. It reports any option that comes out different from
what the fragment asks.

`device/kebab/dts/omamobile.dtsi` holds our one change: `pd-disable` on
the Type-C connector (2026-11-28 entry).

Until 2026-11-27 the kernel was the [sm8250-mainline tree][tree]'s
`sm8250/v6.13`, with a copy of its DTS; that DTS had USB as a plain
peripheral, no panel node and the wrong touch controller (S6SY761).

[tree72]: https://gitlab.postmarketos.org/soc/qualcomm-sm8250/linux
[tree]: https://gitlab.com/sm8250-mainline/linux

## 2026-11-28: the status bar's clock and the camera hole (`boot_b`)

The 8T's front camera hole is at the top left, under the status bar's
clock (the bar was laid out for a centred hole). omamobile-shell 0.2.159
(#1143) adds `bar.cutoutLeft`/`cutoutRight` and a device file;
`omamobile-device-kebab` 0.1.7 ships `{"left": 56}` (56 logical px, 168
physical at scale 3), which clears the hole by eye on the phone.

## 2026-11-28: the bottom speaker under PipeWire (`boot_b`, Arch root on `userdata`)

Through PipeWire only the earpiece played (YouTube in Chromium, `pw-play`):
the stream reached the sink with signal, the whole DAPM path to both
TFA9874s was on and no mixer control differed from a direct playback. A
direct `speaker-test -D hw:0,0` played on the bottom speaker. The
difference was the sample format: PipeWire opened PCM 0 as S24_LE, the
tests as S16_LE. The amplifiers take one 16-bit TDM slot each on the
tertiary MI2S port (top/earpiece slot 0, bottom slot 1); a 24-bit stream
widens the port's slots and the bottom amplifier reads the wrong bits.
`omamobile-device-kebab` 0.1.6 ships a WirePlumber rule that keeps the
speaker sink at S16LE; with it YouTube plays on the bottom speaker. The
kernel side (the backend's format fixed at 16 bits for this link) is not
changed.

## 2026-11-28: building the boot image from the repository

The boot image no longer needs hand steps:

```
tools/build-kebab-kernel                                   # OUT=out/kebab/kernel
DEVICE=kebab KERNEL_OUT=out/kebab/kernel \
  SPLASH_BGRA_GZ=<frame> bin/omamobile initramfs           # see the splash note below
KERNEL_OUT=out/kebab/kernel tools/build-kebab-images       # images/boot.img
```

- `tools/build-kebab-kernel` lays its output out as a kernel build
  directory: `include/config/kernel.release`,
  `arch/arm64/boot/Image.gz`, the DTB under `arch/arm64/boot/dts/qcom/`,
  and `modules-<release>.tar.zst` packed as `bin/omamobile modules` packs
  it, which `tools/build-rootfs` takes as `KERNEL_OUT`.
- `INITRAMFS_MODULES` is gone from `device.conf`: the 7.2.0 kernel builds
  the USB gadget in, so the initramfs carries no modules.
- `tools/build-kebab-images` packs header v2 (DTB section at 0x01f00000,
  gzip kernel) from `device.conf`'s offsets and `CMDLINE` with the pinned
  `mkbootimg.py`, fetching only it (and the module it imports) from
  `tools/toolchain.lock` and checking both SHA-256s.
- **The splash frame:** `bin/omamobile initramfs` renders it itself on a
  host with Omarchy's Plymouth theme and ImageMagick; elsewhere pass
  `SPLASH_BGRA_GZ`, rendered with the same command from
  `usr/share/plymouth/themes/omarchy/logo.png` in the published
  `omarchy-settings` package. Rendered both ways (on the phone, and from
  the package on the build host) the frame is byte-identical.

The image built this way (`7.2.0-omamobile-push1-00084-g3c5440e9dd3c`,
initramfs from `bin/omamobile initramfs` with only the builder's one SSH
key) was `fastboot boot`ed: no failed units, Hyprland once, audio on the
HiFi profile.

## 2026-11-28: the phone's own firmware, installed at boot

`omamobile-device-kebab` 0.1.5 adds `omamobile-kebab-firmware` (a script
and a `sysinit.target` service before the panel wait and Plymouth). When
any of the phone's own firmware is missing it reads it from the Android
partitions, read-only, and installs it under
`qcom/sm8250/OnePlus/kebab/` (each `.mdt` as the `.mbn` the DTS names,
its `.bNN` segments beside it), then starts any remote processor that came
up before its firmware:

- **ADSP, CDSP, SLPI, venus** from `modem_a`, a FAT partition, mounted
  `ro`;
- **the GPU zap shader** from `vendor_a`. `super` holds the dynamic
  partitions (LP metadata 10.2: `system_a`, `system_ext_a`, `product_a`
  ext4; `vendor_a`, `odm_a` **EROFS**). The kernel has no EROFS, so the
  script reads `super`'s LP metadata itself, puts a read-only loop
  (`losetup -r`) over `vendor_a`'s single linear extent, and takes the
  files out with `dump.erofs --cat` (`erofs-utils`).

`linux-firmware-qcom` and `linux-firmware-atheros` (the SQE, GMU and
ath11k files) are now dependencies of the package, so they come with the
image.

Test: with the hand-installed firmware moved aside, the next boot
installed 71 files at 5.86 s and started the SLPI and ADSP; the sound card
came back, Hyprland rendered on the Adreno 650 (`Renderer: FD650`) with
the zap shader from the current `vendor_a` (newer than the Android 13
copy installed by hand earlier: its `.mdt` and `.b01` differ), and a
dry run into a test directory matched the hand-installed DSP images byte
for byte. The loop and the mount are gone afterwards.

On that boot PipeWire put the card on the `off` profile (WirePlumber:
`failed to create proxy: Cannot allocate memory`) although the UCM verb
probes fine (`spa-acp-tool`: "Profile HiFi supported"); a clean restart of
the PipeWire units, and the next normal boot, chose HiFi. Seen twice today;
to watch on a fresh install's first boot.

## 2026-11-28: boot splash (`boot_b`)

The boot shows Omarchy's logo instead of kernel messages.

- **Command line** (`device.conf` `CMDLINE`): `console=tty0 quiet splash
  plymouth.graphical plymouth.force-scale=1 vt.global_cursor_default=0
  clk_ignore_unused pd_ignore_unused panic=10`, the splash words raven,
  husky and akita use. `quiet` keeps the panel driver's probe warnings off
  the screen (they stay in the log). `panic=10` replaces the bring-up
  `panic=0`, so a phone away from the laptop restarts rather than freezes.
- **The initramfs splash:** the shared init draws `/splash.bgra.gz` on fb0
  when `splash` is on the command line. The boot framebuffer is 1080x2400
  a8r8g8b8 (stride 4320), so the frame was rendered on the phone with
  `bin/omamobile initramfs`'s own command (Omarchy's Plymouth logo centred
  on #1a1b26, at scale 1, BGRA) and appended to the existing initramfs as a
  second cpio archive holding only that file, which the kernel unpacks
  after the first. `bin/omamobile initramfs` with `SPLASH_BGRA_GZ` does the
  same in one build.
- **Plymouth crashed** (`plymouth-start.service`: SIGSEGV) when it started
  on simpledrm and msm then took the panel away. `omamobile-device-kebab`
  0.1.4 runs the panel wait without default dependencies, after udev and
  before `plymouth-start.service`, and orders Plymouth after it with a
  `plymouth-start.service.d` drop-in: msm 5.44 s, Plymouth 6.26 s, no
  failed units.
- **Scale:** without `plymouth.force-scale=1` Plymouth picked a HiDPI scale
  for this 1080x2400 panel and the logo came out stretched; with it the
  logo matches the initramfs splash.

The logo is up for only about a second: the boot reaches SDDM's lock
screen that quickly. `boot_b` was rewritten with this image (slot flags
before and after: B active, not successful, not unbootable, retry-count 7)
and the next normal boot was clean.

## 2026-11-28: booting from `boot_b` (no `fastboot boot`)

`boot_b` now holds the same image that was `fastboot boot`ed all day
(header v2, `7.2.0-omamobile-push1-00084-g3c5440e9dd3c`, the board DTB
with `omamobile.dtsi`, the shared initramfs, no `omamobile.initramfs`).
Written by hand with `fastboot flash boot_b` (`bin/omamobile flash` refuses
`android-v0`), after a read-only copy of the old `boot_b` (a downstream
Android boot image) was taken to the laptop and checked by SHA-256.

| | `current-slot` | B: successful / unbootable / retry-count | A: successful / unbootable / retry-count |
| --- | --- | --- | --- |
| before the write | b | no / no / 7 | no / no / 6 |
| after the write | b | no / no / 7 | (not read) |
| after 5 normal boots from `boot_b` | b | no / no / 7 | no / no / 6 |

- **`fastboot reboot`:** ABL starts slot B by itself
  (`androidboot.slot_suffix=_b`, `androidboot.verifiedbootstate=orange`:
  the unlocked bootloader accepts the image although `vbmeta_b` still
  describes the old one; `vbmeta` was not touched), the init hands over to
  the root, the system reaches `running` and Hyprland starts. USB networking
  was up 9 s after the reboot.
- **Without the laptop:** powered off, USB unplugged, powered on with the
  Power key: Omarchy's lock screen. The initramfs's no-USB-host watchdog
  doesn't fire: `boot_arch` stops it (`kill -9 -1`) before `switch_root`.
- **Seen on that boot:** SDDM's first Hyprland session ended at 12 s
  (`sddm-helper exited with 9`) and SDDM started it again: Hyprland came up
  on simpledrm before msm DRM, loaded from the root, took the panel.
  `omamobile-device-kebab` 0.1.3 adds `omamobile-kebab-display.service`
  (ordered before the display manager by a `display-manager.service.d`
  drop-in, as husky and tegu do), which loads msm and the panel driver and
  waits up to 15 s for DSI-1 to be connected, always exiting 0 so a failed
  msm still leaves SDDM on simpledrm. Next boot: msm bound at 6.81 s, the
  wait returned at 7.14 s, SDDM started at 7.30 s; no `sddm-helper exited`,
  Hyprland started once. (A root `tty` session that logs out at about 8 s
  is a boot-time service's, not the user's.) The boot then ended in an orderly power-off at about 30 s
  whose cause isn't in the journal (UPower logged no critical action; logind
  ignores the power key, which the shell handles); plugging USB in powered
  the phone on again, and that boot is clean.
- **Retries aren't spent.** After five normal boots from `boot_b` (the
  `fastboot reboot`, a standalone power-on, the power-on from plugging USB
  in, a `systemctl reboot`, and the `reboot bootloader` below) slot B still
  reads retry-count 7, not successful, not unbootable: this ABL doesn't
  count normal boots against an unmarked slot, so slot B needn't be marked
  successful (a GPT write, a CONTRIBUTING.md §3.1 exception) for the phone
  to keep starting it.
- **`reboot bootloader` works:** `omamobile-device-kebab`'s `reboot`
  wrapper (`reboot-to bootloader`, LINUX_REBOOT_CMD_RESTART2) reaches ABL's
  fastboot mode with no buttons.

Way back: `fastboot boot` of the same image, or `fastboot flash boot_b`
of the saved copy; slot A was not written.

## 2026-11-28: microphones (`fastboot boot`, Arch root on `userdata`)

Same kernel and DSP firmware. The phone's mics are two digital mics on the
DMIC1 and DMIC3 lines; stock's mixer paths (the vendor partition's
`mixer_paths.xml`) use DMIC3 as the handset mic and DMIC1 as the second
mic of its noise-cancelling pair.

- **Which path.** Recording 1.5 s from every candidate input while
  talking: through the TX macro's own DMIC lines every input read the
  same noise floor (about -65 dBFS), and through the TX macro's SoundWire
  inputs nothing at all; through the **VA macro** only DMIC1 and DMIC3
  picked anything up. Their level follows the decimator gain (VA_DEC0
  Volume 84/100/110: DMIC3 -65/-50/-38 dBFS while talking), so they are
  the mics, read through the VA macro.
- **The profile.** `omamobile-device-kebab` 0.1.2 adds a Mic device to
  the UCM verb: `VA DEC0 MUX` VA_DMIC, `VA DMIC MUX0` DMIC3, `VA_AIF1_CAP
  Mixer DEC0`, `MultiMedia3 Mixer VA_CODEC_DMA_TX_0`, `VA_DEC0 Volume` 104
  (+20 dB), PCM 2. PipeWire shows "Built-in Audio Microphone", and 5 s of
  speech recorded through it came in at -11.9 dBFS RMS, half-scale peaks.
- **Not yet:** the second mic (DMIC1, for stereo or noise cancelling) and
  the TX macro's DMIC path, which stock uses (likely a DMIC clock setting).

**Headset.** The 8T has no jack: a wired headset is an analog USB-C
headset, switched onto the WCD9385 by the FSA4480 in Type-C audio
accessory mode. Stock's `headset-mic` path is the WCD's ADC2 (`ADC2 MUX`
INP2, `TX SMIC MUX0` ADC1, `TX_DEC0 Volume` 84) on `TX_CDC_DMA_TX_4`, and
its headphones are the WCD's HPHL/HPHR through the RX macro. It can't be
tried while the USB-C port is the laptop link, so it isn't in the UCM
profile yet (a device without a working jack control would leave PipeWire
offering headphones that aren't there).

## 2026-11-28: battery and charging (`fastboot boot`, Arch root on `userdata`)

Same kernel. No change was needed for either.

- **Gauge:** the board DTS's `ti,bq28z610` at I2C 0x55 binds
  `bq27xxx_battery_i2c` (loaded by udev) as `bq28z610-0`: status, capacity,
  voltage, current, temperature, health, charge-full and cycle count read
  back sensibly. UPower reports it (`battery_bq28z610_0`: percentage, state,
  time to full, capacity health), so the shell's battery indicator has a
  source. The pack is two cells in series: `voltage_now` reads about 8.0 V.
- **Charging:** with the Type-C port online (`tcpm-source-psy`, 5 V,
  `current_max` 3 A from the laptop) the battery charges at about +376 mA,
  about 3 W: the PM8150B's charger runs on the limits the bootloader left,
  with no Linux driver.
- **Not enabled on purpose:** `qcom_pm8150b_charger` (`CHARGER_QCOM_SMB5`)
  is built and the OnePlus 8 Pro's DTS enables `&pm8150b_charger` with
  `monitored-battery`, but the 8 Pro's battery is one cell and the 8T's is
  two in series, and the 8T's board DTS leaves the node disabled. Driving
  a charger that assumes one cell on a 2S pack isn't something to try
  without the 8T's charging path written down first (the PM8150B, the
  BQ25970 charge pump, and how the downstream kernel splits the work), so
  faster charging waits for that. `qcom_fg` and `bq25970_charger` are
  built but not loaded for the same reason.

Light/dark mode needs nothing device-specific: Omamobile's quick settings
"Dark theme" tile switches between Omarchy's dark and light themes, and a
long press opens the theme switcher.

## 2026-11-28: DSPs and speakers (`fastboot boot`, Arch root on `userdata`)

Same kernel, with `SND_SOC_TFA987X`, `CHARGER_QCOM_SMB5`,
`BATTERY_QCOM_FG`, `CHARGER_BQ25970` and `INPUT_AW8695_HAPTICS` added as
modules (no MODVERSIONS, so they load into the running kernel of the same
release; the charger, gauge and haptics are built, not yet tried, and
`CHARGER_QCOM_SMB5` builds no module in this tree).

- **Firmware.** The ADSP, CDSP, SLPI and venus images come from the
  phone's own `modem` partition (`/image/<name>.mdt` and `.bNN`), each
  `.mdt` installed as `qcom/sm8250/OnePlus/kebab/<name>.mbn` (the DTS
  names) with its segments beside it. Not in this repository.
- **ADSP:** starts (`remote processor adsp is now up`), its APR audio
  services register, the LPASS SoundWire buses come up and the WCD9380
  codec binds on both. The sound card then waits on `Speaker Playback:
  codec dai not found` until the TFA9874 driver (`snd-soc-tfa987x`,
  "tfa987x" in this tree, not `tfa989x`) binds both amplifiers (I2C 0x34
  and 0x35, revision 0x0c74). Then card 0 is "OnePlus 8T" (driver
  sm8250).
- **Speakers:** `TERT_MI2S_RX Audio Mixer MultiMedia1` on routes PCM 0 to
  the amplifiers; a -20 dB tone played from `hw:0,0` and through PipeWire
  was heard. `omamobile-device-kebab` 0.1.1 ships an ALSA UCM profile
  (`conf.d/sm8250/OnePlus 8T.conf`, verb HiFi, device Speaker) and
  PipeWire shows "Built-in Audio Speakers". Microphones (WCD9380 ADCs, TX
  macro) are not in the profile yet; neither are the earpiece or headset.
- **SLPI:** starts; `/dev/fastrpc-sdsp` appears. The motion, light and
  proximity sensors sit behind the SLPI's sensor core and need a userspace
  stack this image doesn't have: a fastrpc daemon serving the SLPI's files
  (from the phone's `dsp` partition), a QMI client for the sensor core,
  and iio-sensor-proxy built against it. `iio:device0-2` are the PMIC ADCs.
- **CDSP:** `can't start rproc cdsp: -22`; not needed for audio or sensors.
- **venus:** with its firmware the `qcom-iris` "firmware download failed"
  messages stop.

## 2026-11-28: Wi-Fi (`fastboot boot`, Arch root on `userdata`)

Same kernel. With `linux-firmware-atheros` (20261124) in the root,
`ath11k_pci` brings up the QCA6390 over PCIe at boot (`qca6390 hw2.0`,
MHI to mission mode, firmware `0x10121492`) as `wlp1s0`, and
NetworkManager joins a WPA2 network from Omarchy's own Wi-Fi picker:

- 5 GHz, 80 MHz, Wi-Fi 6 (HE, 2 streams): rx 864.8 Mbit/s (HE-MCS 8), tx
  576.4 Mbit/s (HE-MCS 5) at -61 dBm;
- DHCP, DNS and HTTPS work; the default route goes through Wi-Fi (metric
  600) with `usb0` behind it (900), as `omamobile-device-kebab`'s networkd
  file intends;
- systemd-timesyncd syncs from ntp.omarchy.org, which fixes the 1970 clock
  (and pacman's signature checks) whenever Wi-Fi is up.

The chip reports `board_id 0xff`, so ath11k takes a generic board-data
entry from `board-2.bin`; the phone's own `bdwlan.elf` (odm partition)
isn't needed for the rates above. No device-specific change was needed.

## 2026-11-28: display, GPU and touch (`fastboot boot`, Arch root on `userdata`)

Kernel `7.2.0-omamobile-push1-00084-g3c5440e9dd3c` with `pd-disable` and
`typec-power-opmode`. Hyprland and the Omarchy shell draw on the AMB655X
panel through msm DRM and the Adreno 650 (`Renderer: FD650` in Hyprland's
log, the GPU's devfreq changing level), and touch works.

What the GPU needed, in order:

1. **Firmware in the root.** Without `qcom/a650_sqe.fw` the GPU can't
   start, and once msm owns the panel Mesa no longer falls back to
   software rendering: Hyprland's `eglInitialize` fails and the screen
   clears. The phone's own vendor partition has `a650_sqe.fw`,
   `a650_gmu.bin` and the zap shader (`a650_zap.mdt` + `.b00`-`.b02`).
2. **A new enough SQE.** The vendor's `a650_sqe.fw` is refused: `a650 SQE
   ucode is too old. Have version 93 need at least 95`. linux-firmware's
   (`linux-firmware-qcom` 20261124) is accepted. The zap shader must
   still be the phone's own: its `.mdt` installed as
   `qcom/sm8250/OnePlus/kebab/a650_zap.mbn` (the name the DTS asks for)
   with the `.bNN` files beside it, which the MDT loader finds by base
   name. msm keeps a rejected SQE in memory, so a new file takes a new
   boot (`modprobe -r msm` refuses: fbcon holds it).
3. **Mesa with freedreno.** The published `mesa` 26.2.4-1.4 is built for
   the Pixels' Mali GPUs only (panfrost): `DRI2: failed to load driver`.
   Arch Linux ARM's own `mesa` 26.3.1 (with `vulkan-freedreno`) works.
   `packages/mesa` needs `freedreno` in its gallium drivers (and
   `vulkan-freedreno`) before an image can carry one Mesa for both.

None of these files is in this repository; the firmware came from the
phone's own partitions and linux-firmware.

**The clock.** The RTC reads 1970 after every boot and nothing syncs time
without a network, so pacman refuses every package signature ("key
created ... in the future") until the clock is set by hand.

**`qcom-iris` (video):** `firmware download failed` and `core init
failed` for `qcom/sm8250/OnePlus/kebab/venus.mbn`, on screen at every
probe. It is in the phone's `modem` partition (`/image/venus.*`), with
the ADSP, CDSP and SLPI firmware; not installed yet.

## 2026-11-28: the 7.2.0 tree (`fastboot boot`, root in the shared initramfs)

Kernel `7.2.0-omamobile-push1-00084-g3c5440e9dd3c`, both the tree's DTB
and our `omamobile.dtsi`.

- **USB through Type-C.** The initramfs's NCM gadget comes up through the
  PM8150B port's role switch (`TYPEC_TCPM`, `TYPEC_QCOM_PMIC` and
  `TYPEC_MUX_FSA4480` built in): SSH works.
- **PD resets the link.** With the connector as the tree has it, TCPM
  sends a PD signal (`typec@1500: isr: tx_sig`) about once a second to a
  laptop port that never completes a PD contract, and each is followed by
  `dwc3 a600000.usb: remote wakeup not configured` and a new network
  interface on the laptop: an SSH session lasts seconds to a minute.
  `pd-disable` on the connector (`omamobile.dtsi`) stops it: no `tx_sig`,
  no link resets, SSH holds. But TCPM also needs `typec-power-opmode` on
  a port without PD: with `pd-disable` alone `qcom,pmic-typec` failed its
  probe with -22, so its DP HPD bridge never registered (`aux_bridge:
  failed to acquire drm_bridge`), the DP controller deferred forever and
  msm DRM never bound. With `typec-power-opmode = "default"` it probes
  (`/sys/class/typec/port0` and its partner).
- **Display.** udev loads `msm`, `panel_samsung_amb655x` and
  `synaptics_s3908` from the root. msm DRM binds (`card1`, `msm_dpu`:
  DSI-1, DP-1, writeback), DSI-1 is connected and enabled at 1080x2400,
  `fb0` is `msmdrmfb`, the backlight is `ae94000.dsi.0` (0-1023). The
  panel's probe logs `DSI PLL(0) lock failed` and unbalanced clock
  disable/unprepare warnings, then works. The GPU waits for firmware:
  `failed to load a650_sqe.fw`.
- **Touch.** `synaptics_s3908` registers "Synaptics TCM Oncell
  Touchscreen" (i2c-13, 0x4b).
- **Root without modules.** Booted into the root on `userdata` before its
  modules were installed, the phone answered ping but not SSH: ufw sets
  its default-deny policy and then can't load its rules, which need
  netfilter modules for the running kernel (enchilada's firewall entry
  again), and touch had no driver. The modules were then written into the
  root from the initramfs (`omamobile.initramfs`, mount `userdata`,
  `busybox tar`): `msm.ko`, `panel-samsung-amb655x.ko`,
  `synaptics_s3908.ko` and the rest.
- **Host side (macOS).** A manual IPv4 alias on the phone's interface is
  dropped whenever the interface is re-created; SSH to the phone's IPv6
  link-local address (found with `ping6 ff02::1%<if>`) needs no address on
  the laptop at all.

Next: the GPU (done the same day, entry above).

## 2026-11-28: Omarchy from `userdata` (`fastboot boot`, Arch root on `userdata`)

The boot image was sent with `fastboot boot` (slot B active, `dtbo_b`
erased), so nothing but `userdata` was written; its command line has no
`omamobile.initramfs`, so the shared init handed over to the root on
`userdata`. Kernel `6.13.0-rc7-omamobile-push1-gff61dd629750-dirty`.

- **The root image:** `tools/build-rootfs --local kebab`, 11 GB ext4
  (8.5 GB of files), all 18 `tests/rootfs-smoke` checks passed. The owner's
  answers (`firstboot.conf`, root's `authorized_keys`, `boot-update.conf`
  with `AUTO_WRITE=no`) were written into a copy with debugfs as
  `tools/install-phone` does; the installer refuses this phone
  (`android-v0`).
- **Writing `userdata`:** `fastboot flash userdata` of the raw image stops
  at once with `Failed reading from userdata` (fastboot 37 reads an AVB
  footer from the end of a raw image smaller than its partition); the
  Android sparse image from `img2simg` (8.2 GB) went in 12 chunks in
  4.5 minutes, as the installer does it.
- **First boot:** the init grew the file system to the whole partition
  (220.8 GB), `omamobile-firstboot` ran to `firstboot done` and removed
  `firstboot.conf`, the user exists, `systemctl is-system-running` says
  `running` with no failed units. ufw is active, and SSH over `usb0`
  (172.16.42.1, from `omamobile-device-kebab`'s networkd file) worked.
  SDDM logged the user in and Hyprland and the Omarchy shell run on
  simpledrm (no GPU yet, so the CPU draws: "Realtime budget exceeded"):
  Omarchy's lock screen is on the panel.
- **Clock:** the RTC reads 1970 and nothing syncs time without a network;
  the system clock came up a month early.
- systemd-gpt-auto-generator fails at every daemon reload (harmless; the
  root is not found through a GPT root type).

**Building the image.** Published `hyprland 0.57.0-3.3` wants
`libhyprgraphics.so=5`, but Arch Linux ARM moved to `hyprgraphics 0.7.0`
(`.so=6`), so a root image can't be built from the published set today:
`packages/hyprland` was rebuilt against it (`--local kebab`). That rebuild
needed two tool fixes (a split package's own names taken as dependencies;
an aarch64 build host refused) and a case-sensitive build directory: on a
case-insensitive host file system the source's `VERSION` file answers
`#include <version>`.

Next: the display (msm DRM and the 8T's DSI panel), then the GPU (2026-11-28, the 7.2.0 tree, above).

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
