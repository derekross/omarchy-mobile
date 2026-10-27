<!-- SPDX-License-Identifier: MIT -->
# Audio plan (cheetah / gs201): amplifiers, AoC, USB-C, Bluetooth, PipeWire

Status (2026-10-12): **this plan's research is done, and its stages continue
in other plans.** Working: Bluetooth A2DP (A1, through `BLUETOOTH-PLAN.md`
BT3), and the built-in speakers and microphones through the AoC (A6, carried
out as `AOC-PLAN.md` C5-C9): both CS35L41 amplifiers in stereo under
Google's speaker protection at stage `media`, about 17 dB below stock, and
the microphones at stock's gain (omamobile-audio 0.3.0). Not done: headset
calls over HFP/HSP (the BCM4389's SCO routing, A1), USB-C audio (A4, needs
`USB-C-PLAN.md` B4b and B4c), the UAC2 gadget (A5) and the earpiece path
(designed in `AOC-PLAN.md`, built with the modem). **Next** is in
`AOC-PLAN.md` C9 and `AOC-TUNING-RESEARCH.md`. Kernel: `omamobile-audio` @
`c115ad543` (`wt-audio`, `out-audio`), merged into `omamobile-int`. Section
4's limits still apply.

Earlier status (historical, superseded by the status above): **offline research done, 2026-10-12. Nothing has run on the phone.**
Kernel branch `omamobile-audio` in `~/android/mainline/wt-audio` (out dir
`out-audio`), on `omamobile-haptics` @ `ebcd2674f` because it needs the
PERIC0 pin controller that branch adds. Two DT commits, everything new
disabled; the DTB builds W=1 clean and `dt-validate` (base, and base +
`audio-amps-test`) reports only the existing `soc_id` and simplefb
`post-init-providers` items. The branch merges into `omamobile-int` with no
conflict. Bring-up uses `device/cheetah/overlays/audio-amps-test.dtso` and
`tools/cs35l41-id`.

Path abbreviations:

- `L/` = our kernel, branch `omamobile-audio` (`~/android/mainline/wt-audio`)
- `G/` = `~/android/omamobile/out-kernel/google/gs-6.1/private` (Google's GPL gs201 kernel)
- `GS/` = `G/google-modules/soc/gs`
- `R/` = `~/android/reference/cheetah-stock-cp2a-root` (stock live DT, dmesg, modules)
- `V/` = `~/android/omamobile/vendor/google/cheetah/proprietary/vendor` (stock vendor blobs)
- `P/` = `~/android/reference/cheetah-partition-backup-20261011` (partition backup)

---

## 0. Top findings

1. **All on-device audio goes through the AoC.** gs201 has no ABOX. The
   speaker amplifiers' audio port (TDM 0), the three PDM microphones and
   the Bluetooth SCO PCM link all end in the AoC (Always-on Compute, Google's
   audio/sensor DSP), and ALSA on stock is `aoc_alsa`, which only talks to
   AoC firmware. There is **no AP-side I2S/TDM controller** to drive the
   amplifiers directly, so there is no minimal non-DSP speaker path.
   Speaker, earpiece and microphones all need an AoC port (stage A6), which
   is large: GSA firmware authentication, a SysMMU v8 driver, AoC mailboxes,
   ACPM, then about 4,000 lines of AoC core and 16,700 lines of `aoc_alsa`,
   all GPL.
2. **The amplifiers are reachable today over SPI**, without the AoC: two
   CS35L41 rev B2 on PERIC0 USI7 SPI. Mainline has a complete CS35L41 ASoC
   codec driver, so register access, IDs, boost setup and the DSP firmware
   load all work without new drivers. This is the safe, cheap first hardware
   stage (A2/A3), and it settles the board facts before any sound.
3. **The earpiece is the top speaker.** There is no separate receiver amp:
   chip select 0 ("top") plays the earpiece in calls with the CS35L41 DSP
   bypassed and a low gain (stock `handset` path), and is the top half of
   the stereo speaker pair otherwise.
4. **USB-C audio is not a quick win yet.** It needs host mode, which needs
   the USB-C plan's B4b (role switch) and B4c (VBUS from the external boost,
   still design only), and moving SSH off the USB link. There is no analog
   audio accessory mode on this board, so only USB audio class devices
   (including USB-C to 3.5 mm adapters with a DAC) can work.
5. **Bluetooth A2DP is likely the first real sound.** It needs no audio
   kernel work: BlueZ plus PipeWire's bluez5 plugin, once `BLUETOOTH-PLAN.md`
   BT3 passes. HFP/HSP voice needs the BCM4389's SCO routing changed from
   PCM (to the AoC) to the HCI transport.
6. **The factory speaker calibration exists** in `persist`
   (`/mnt/vendor/persist/audio/speaker.cal`, and in our backup `P/persist.img`):
   per amplifier, a ReDC value with status 1 and checksum = ReDC + status,
   plus the ambient temperature at calibration. (The values are unique to
   each phone and stay out of the repository.) Speaker protection must be fed these values;
   which value belongs to which amplifier is still to be confirmed.

---

## 1. Hardware, with evidence

### 1.1 Speaker amplifiers (CS35L41 x2)

| Item | Value | Evidence |
|---|---|---|
| Chips | Cirrus Logic CS35L41, DEVID `0x35a40`, revision **B2**, on `spi7.0` and `spi7.1` | `R/dmesg.txt:1705,2064` |
| Roles | `cs35l41_l` (cs 0) = **top** speaker, also the earpiece; `cs35l41_r` (cs 1, name prefix "R") = **bottom** loudspeaker | `G/devices/google/pantah/dts/gs201-cheetah-audio.dtsi:8-9` ("cs35l41_l = top, cs35l41_r = bottom"); `V/etc/mixer_paths.xml:640-644` (`handset` uses only the unprefixed amp), `:700-703` (`speaker-safe` uses only R) |
| Bus | PERIC0 **USI7 SPI** at `0x10960000`, GIC SPI **680** (0x2a8), USI sysreg offset `0x18` on `sysreg_peric0` (`0x10821000`, i.e. our `0x10820000 + 0x1018`) | `R/live.dts:8642-8660` |
| SPI clock | 25 MHz on stock; mainline's driver forces 4 MHz (`CS35L41_SPI_MAX_FREQ`), which the USI divider rounds to what it can reach | `R/live.dts:8664`; `L/sound/soc/codecs/cs35l41-spi.c:41` |
| Bus pins | gpp14-0 CLK, gpp14-1 MOSI (func 3, 5 mA), gpp14-2 MISO (func 3, pull-down) | `R/live.dts:3958-3964,4316-4332`; `gs201-cheetah-audio.dtsi` comments `AUDIO_SPI_CLK/MOSI/MISO` |
| Chip selects | cs 0 **gpp14-3** (`AUDIO_AMP1_SPI_CS_L`), cs 1 **gpp22-1** (`AUDIO_AMP2_SPI_CS_L`), GPIO, active low (stock log "enforce active low on chipselect handle") | `R/live.dts:8659,4334-4338,4830-4835`; `R/dmesg.txt:735-736` |
| Interrupts | top **gpa6-3** (XEINT_3, `AMP1_IRQ_L`), bottom **gpa8-6** (XEINT_18, `AMP2_IRQ_L`), both FAR_ALIVE. The amps drive them from GPIO2 as **push-pull, active high** (src 5) despite the `_L` names | `R/live.dts:3206-3218,8669-8670,8704-8705`; `gpio-config2 { gpio-src-select = <5> }` `R/live.dts:8682-8686,8718-8722`; `L/sound/soc/codecs/cs35l41-lib.c` `cs35l41_gpio_config()` (5 = `IRQF_TRIGGER_HIGH`) |
| Resets | top **gpp17-1** (`AMP1_RESET_L`), bottom **gpp25-2** (`AMP2_RESET_L`), outputs, power-down state "previous" | `R/live.dts:4340-4347,4837-4844,8671,8706` |
| Supplies | VA = **S2MPG13 BUCKA** ("SA", always on, 1.7-2.1 V range); VP = `V_SYS_DUMMY` (4.2 V fixed: VSYS) | `R/live.dts:8672-8673,13927-13940,6108-6116` |
| Boost | inductor **1000 nH**, capacitance **30 uF**, peak current **3.5 A** in the DT; the HAL lowers it to **2.5 A** for speaker playback and raises it to 3.5 A for voice | `R/live.dts:8674-8676`; `V/etc/mixer_paths.xml:98-99,660-665` (`speaker`: 2.50A), `:646-650` (`voice-handset`: 3.50A); `R/dmesg.txt:6535-6536,6557-6558` |
| Boost voltage | not set by DT or HAL: chip default (class-H tracking, 11 V ceiling, code `0xAA`) | Google's control `Boost Target Voltage` max `0xAA`, `G/google-modules/amplifiers/cs35l41/cs35l41.c:1802`; no `boost-ctl-millivolt` in `R/live.dts:8661-8730` |
| Other | `asp-sdout-hiz = 3`, `hw-noise-gate-select = 63`, `hibernate-enable`, `tuning-has-prefix` (Google-only properties except the first) | `R/live.dts:8677-8680` |
| TDM | AoC TDM 0, `dsp_a`, 4 slots x 32 bit, 48 kHz (BCLK 6.144 MHz from the AoC, which is also the amps' PLL reference). RX: top slot 0, bottom slot 1; TX (VMON/IMON feedback): top 0/2/4/6, bottom 1/3/5/7 | `R/live.dts:6925-6947` (codecs `<0x3d2 0x3d3>` = the two amps); `V/etc/mixer_paths.xml:37-42,57-71`; `gs201-cheetah-audio.dtsi` `sys@cs35l41_l { src = "BCLK" }` |
| Gains (stock) | speaker: `AMP PCM Gain` **17** (17.5 dB), `Digital PCM Volume` **817** (0 dB), PCM source DSP (protection firmware); earpiece (`handset`): PCM source **ASP** (DSP bypass), gain **6** (6.5 dB); voice earpiece gain 7 | `V/etc/mixer_paths.xml:80-83,90-99,640-650` |
| DSP firmware | `cs35l41-dsp1-spk-prot.wmfw` (both amps) + `cs35l41-dsp1-spk-prot.bin` (top) / `R-cs35l41-dsp1-spk-prot.bin` (bottom); also `-spk-cali` and `-spk-diag` sets; firmware 0x400a4 v0.45.0, algorithms `cd` (protection) and `f20b` | `R/vendor-firmware.txt`; `V/firmware/`; `R/dmesg.txt:6468-6486` |
| Tuning deltas | `fast_switch1..4.txt` ("Fast Use Case" deltas: FIR bypass vs enable). Google-only mechanism, not in mainline | `V/firmware/fast_switch*.txt`; `V/etc/mixer_paths.xml:111-115,667-673` |
| Calibration | `/mnt/vendor/persist/audio/speaker.cal`, 48 bytes, two records of six LE u32: `CAL_R, 1, CAL_R + 1, ambient °C, x, y` per amplifier (values not recorded here) (CAL_R, CAL_STATUS, CAL_CHECKSUM = R + status, CAL_AMBIENT °C, two unidentified). Applied by the HAL library to the DSP controls `CAL_R`, `CAL_STATUS`, `CAL_CHECKSUM`, `CAL_AMBIENT` | `P/persist.img` (`debugfs -R 'cat /audio/speaker.cal'`); `V/lib64/audio_spk_35l41.so` strings; `V/etc/init/hw/init.pantah.rc:32-33` |

### 1.2 Earpiece

Not a separate part: it is the top speaker on the top CS35L41 (1.1, "Roles").
In calls stock bypasses the DSP (`PCM Source = ASP`) and uses gain 6-7
(6.5-7.5 dB) instead of 17.5 dB. A future UCM `Earpiece` device is the top
amplifier alone with those settings.

### 1.3 Microphones

| Item | Value | Evidence |
|---|---|---|
| Count, placement | three: `builtin_mic_1` bottom, `builtin_mic_2` back, `builtin_mic_3` top | `V/etc/audio_platform_configuration.xml:58-70` |
| Type, path | digital (PDM) microphones into the **AoC** (`INTERNAL_MIC_TX` back end of the AoC card; AoC mic IDs 0, 3, 2 in the capture list). No AP pins or codec for them anywhere in the AP DT | `R/live.dts:7009-7037`; `V/etc/mixer_paths.xml:721-728` |
| Supplies | DMIC1 S2MPG12 LDO20 (`L20M_DMIC1`), DMIC2 S2MPG13 LDO20 (`L20S_DMIC2`), DMIC3 S2MPG13 LDO19 (`L19S_DMIC3`), all always on, 1.6-1.95 V | `R/live.dts:13532-13541,14185-14205` |

### 1.4 The AoC (audio DSP)

| Item | Value | Evidence |
|---|---|---|
| Block | `google,aoc` at `0x19000000` (16 MiB), plus `aoc_req` `0x181d0000`, `aoc_s2mpu` `0x1a0b0000`, `ssmt_aoc` `0x1a060000`; watchdog GIC SPI 116 | `R/live.dts:6060-6098` |
| Memory | `aoc@94000000`, 48 MiB, no-map (already `no-map` in our gs201.dtsi) | `R/live.dts:103-107`; `L/arch/arm64/boot/dts/exynos/google/gs201.dtsi` reserved-memory |
| Firmware | `aoc.bin` (21 MB, "14022723-polygon"), loaded by the AP kernel 4 s into boot, authenticated and started by the **GSA** (`gsa_load_aoc_fw_image`, `GSA_AOC_START`) | `R/dmesg.txt:5799-5885`; `G/google-modules/aoc/aoc.c:485-504,655-690` |
| IOMMU | `sysmmu_asoc` `0x1a090000`, **`samsung,sysmmu-v8`** (no upstream driver); the AoC firmware carries its own IOMMU map that the kernel must install | `R/live.dts:4925-4937`; `aoc.c:1270-1320`; `R/dmesg.txt:1976` |
| Mailboxes | `google,mailbox-whitechapel` at `0x18300000` (node named `@176a0000`), `0x18320000`, `0x18340000`, GIC SPI 75/76/77 | `R/live.dts:6024-6058` |
| Other links | ACPM IPC channel 13 (AoC reset/power), GSA at `0x17c90000` (SPI 363), sensor rails `sensor_1v8`/`sensor_3v3` | `R/live.dts:6075-6094,7209-7215` |
| Also hosts | CHRE/sensors (`chre-supported`), hotword, USB audio offload, UWB reset GPIO | `R/live.dts:6090-6105`; `R/modules.txt` (`aoc_usb_driver`, `aoc_uwb_*`) |
| ABOX | **not present**: no node in the live DT; `init.gs201.rc` still lists `17c50000.abox` paths and a `main_abox` service that fails to start | `V/etc/init/hw/init.gs201.rc:416-422`; `R/dmesg.txt:5732` |

The AoC also owns the sensor hub, so an AoC port is shared with
auto-rotate and the proximity sensor (needed for in-call earpiece use).

### 1.5 USB-C

- Stock routes USB audio through the AoC too (`USB_RX`/`USB_TX` back ends,
  `aoc_usb_driver`, the `xhci_dma` carve-out). Mainline does not need that:
  plain xHCI plus `snd-usb-audio` works once the port is a host.
- No analog audio accessory support: no `accessory-mode-audio`, no audio
  switch in the DT (`grep -i accessory R/live.dts` is empty).
- Today the port is device-only (`USB-C-PLAN.md`): dwc3 has no role switch
  in the default DT (B4b adds it), and host mode needs VBUS from the
  external boost (B4c, design only). `CONFIG_SND_USB_AUDIO=m` and
  `CONFIG_USB_XHCI_HCD=y` are already in our config.

### 1.6 Bluetooth audio

- A2DP is plain HCI ACL data over the UART: BlueZ + PipeWire, no AoC.
- SCO (HFP/HSP) goes over the BCM4389's PCM pins to the AoC on stock
  (`BT_RX`/`BT_TX` AoC back ends, `R/live.dts:7039-7067`). For PipeWire's
  HFP over HCI, the controller's SCO routing must be set to "transport".

---

## 2. What mainline has and lacks

| Piece | Mainline (v7.3-rc6) | Missing |
|---|---|---|
| CS35L41 | `sound/soc/codecs/cs35l41{,-lib,-spi}.c` with `wm_adsp`/`cs_dsp` firmware loading, controls `Digital PCM Volume`, `Analog PCM Volume` (= stock `AMP PCM Gain`), `PCM Source` (ASP/DSP), `DSP RX1/2 Source`, ASP TX sources | only Google extras: fast use case switch, hibernate, runtime boost-peak control, calibration loading (mainline does it only for HDA laptops, from EFI) |
| USI7 SPI | `spi-s3c64xx` (`google,gs101-spi`), USI, clocks (`CLK_GOUT_PERIC0_USI7_*`, with `CLK_SET_RATE_PARENT`) | the DT nodes: **added on `omamobile-audio`** |
| AoC | nothing (`grep -r google,aoc` empty) | GSA driver, AoC mailbox, SysMMU v8, AoC core, AoC ALSA, AoC machine driver |
| ABOX | not applicable (no ABOX on gs201) | |
| USB audio | `snd-usb-audio`, dwc3 host, xHCI | host mode on this board (USB-C plan B4b/B4c) |
| BT audio | BlueZ/HCI, `hci_bcm` (BT plan) | SCO routing to HCI (vendor command, userspace) |

---

## 3. Stages, ranked by value against effort

| Stage | What | Value | Effort | Risk | Depends on |
|---|---|---|---|---|---|
| **A0** | PipeWire, volume keys and the quick-settings slider on a software loopback card (`snd-aloop`) | medium: the whole userspace path works before any hardware | hours | none | nothing |
| **A1** | Bluetooth A2DP, then HFP | **high**: first real sound in and out | hours after BT3 | low | `BLUETOOTH-PLAN.md` BT3 |
| **A2** | Amplifier bus, read-only chip IDs over spidev | low on its own, gates A3 | hours (built) | very low | this branch |
| **A3** | CS35L41 driver probe, no card (no sound) | low on its own; proves resets, IRQs, boost config | hours | low | A2 |
| **A4** | USB-C host audio (USB DAC/headset) | high | days (mostly USB-C work) | medium (USB lifeline) | USB-C B4b, B4c; SSH over Wi-Fi or a detached test |
| **A5** | USB gadget UAC2: the laptop hears the phone (optional dev aid) | low | hours | low-medium (USB lifeline) | config change |
| **A6** | AoC port: GSA, SysMMU v8, mailbox, AoC core, AoC ALSA | **highest**: speaker, earpiece, mics, calls, sensors | months | high (firmware, memory, IOMMU) | ACPM (`ACPM-PLAN.md`) |
| **A7** | Machine driver + UCM2 + calibration + protection: first speaker sound | highest | weeks after A6 | **speaker damage** if limits are wrong (section 4) | A3, A6 |

Recommended order: **A0 now** (software only), **A2 and A3** whenever the
phone is free (cheap, read-mostly, and they turn the amplifier facts into
checked ones), **A1** right after BT3, **A4** after USB-C B4c. A6/A7 is the
long project; start it as a feasibility study (section 7) and share the
GSA/SysMMU/mailbox work with the sensor hub.

---

## 4. Speaker safety: limits and what must be confirmed first

Micro-speakers die from **excursion** (low frequencies at high level) and
**voice-coil heat** (long high-level playback). The CS35L41 protection
firmware (`spk-prot`, algorithm `cd`) models both using the measured coil
resistance (ReDC, from `speaker.cal`) and the VMON/IMON feedback the amps
send back on TDM. Without it, only static limits protect the speakers.

Hard limits for all bring-up, until A7 has calibrated protection running:

| Setting | Limit | Why |
|---|---|---|
| Boost peak current (`cirrus,boost-peak-milliamp`) | **2500 mA** (in our DT); never above 3500 mA | 2.5 A is stock's speaker-playback value, 3.5 A its voice/DT maximum. Lower is always safe (output clips earlier). |
| Boost inductor / capacitor | exactly **1000 nH / 30 uF** | they select the boost loop coefficients (`cs35l41_boost_config()`: K1 `0x32`, K2 `0x49`, slope `0x75`); wrong values can make the boost unstable |
| Boost voltage | chip default (class-H; `BSTCVRT_VCTRL1` reads 0 on both amplifiers, and neither Google's driver nor stock's DT sets it); never write `BSTCVRT_VCTRL1` except through the `bst_ctl` bring-up parameter (0 by default), with the owner's go and restored after, as C9j did at 5.7 and 8.0 V. The converter itself is off at analog 10 and below since omamobile-audio 0.5.3 (AOC-PLAN C9j) | stock never changes it; at the everyday level its light-load regime distorts |
| `Analog PCM Volume` (stock `AMP PCM Gain`) | top used as earpiece: **≤ 6** (6.5 dB); either amp with the DSP bypassed: **≤ 10**; with calibrated protection: ≤ 17 (stock speaker) | stock values; mainline's default is 0 (0.5 dB) |
| `Digital PCM Volume` | **≤ 817** (0 dB) always; first sound at **≤ 657** (-20 dB) | 817 = 0 dB in both stock and mainline (-102 dB + (n-1) x 0.125 dB) |
| `PCM Source` | `ASP` (bypass) only for the earpiece or for first-sound tests at the limits above; `DSP` with calibration for the loudspeaker | stock `handset` vs `speaker` paths |
| Test signals | 1 kHz (never below 300 Hz) tone bursts of 1-2 s, or band-limited pink noise; no sine sweeps, no bass-heavy music until protection runs | excursion grows fast below resonance |
| Duration | ≤ 30 s of continuous playback per test without protection | coil heating |

Confirm before any sound (A7):

1. The amp-to-speaker mapping (top = cs 0) by ear at the lowest level,
   **before** loading per-amplifier tuning: swapped `.bin` files would put
   the wrong speaker model on each speaker.
2. Which `speaker.cal` record belongs to which amplifier (the two ReDC values
   differ by about 6 %, which the protection model reads as roughly a 15 °C
   coil-temperature error), from Google's library behaviour or by running
   the `spk-cali` firmware once and comparing.
3. The VMON/IMON feedback slots reach the DSP (TX slots in 1.1); protection
   without feedback is blind.
4. The IRQ lines work (A3), so over-temperature, boost and short-circuit
   errors are reported and the driver can shut the amp down.

---

## 5. Kernel and repo changes made

Kernel branch `omamobile-audio` (`L/`), on `omamobile-haptics`:

| Commit | What | Default |
|---|---|---|
| `94df2a402` arm64: dts: exynos: google: gs201: add USI7 SPI | `usi7`/`spi_7` (GIC SPI 680, sysreg `0x1018`), `spi7_bus`/`spi7_miso` pins | `disabled` |
| `c115ad543` arm64: dts: exynos: google: gs201-cheetah: describe the speaker amplifiers | `amplifier@0` (top, prefix "Top"), `amplifier@1` (bottom, "Bottom"), IRQ/reset/CS pins, fixed `amp-va`/`amp-vp` rails, `cirrus,subsystem-id = "cheetah"`, boost 2500 mA / 1000 nH / 30 uF | amplifiers and bus `disabled`; the two fixed regulators are inert placeholders |

Built: `exynos/google/gs201-cheetah.dtb` into `out-audio` (`W=1`: only the
existing framebuffer warning). Not built yet: kernel image and modules.

Why on `omamobile-haptics`: the PERIC0 pin controller and banks (gpp14,
gpp17) come from `523b1e0e0` there; basing on it keeps one copy (the BT
branch adds another, already resolved in `omamobile-int`).

Repo:

- `device/cheetah/overlays/audio-amps-test.dtso` (A2/A3): enables PERIC0
  pinctrl, USI7, `spi_7` and both amplifiers.
- `tools/cs35l41-id`: read-only ID and state dump over spidev (DEVID,
  REVID, OTPID, PWR_CTRL1/2, boost control, PCM source, volumes). Every
  transfer carries the read flag; no status/IRQ registers.

Config needed later (not in `kernel/configs/omamobile.config` yet):

```
CONFIG_SND_SOC_CS35L41_SPI=m        # A3
CONFIG_SOUND=y                      # A5 only: f_uac2 is built in with libcomposite
CONFIG_SND=y                        # A5 only
CONFIG_USB_CONFIGFS_F_UAC2=y        # A5 only
```

`CONFIG_SPI_SPIDEV=m`, `CONFIG_SND_ALOOP=m` and `CONFIG_SND_USB_AUDIO=m`
already come from defconfig.

Firmware names for later (A7; mainline `wm_adsp_request_firmware_files()`,
with the subsystem ID and name prefix from our DT). Install from the
phone's own vendor partition, as `tools/extract-vendor-firmware` does for
the other blobs; never commit them:

| Stock file | Install as |
|---|---|
| `cs35l41-dsp1-spk-prot.wmfw` | `cirrus/cs35l41-dsp1-spk-prot-cheetah.wmfw` (shared by both) |
| `cs35l41-dsp1-spk-prot.bin` | `cirrus/cs35l41-dsp1-spk-prot-cheetah-top.bin` |
| `R-cs35l41-dsp1-spk-prot.bin` | `cirrus/cs35l41-dsp1-spk-prot-cheetah-bottom.bin` |
| `*-spk-cali.*`, `*-spk-diag.*` | same pattern with `spk-cali` / `spk-diag` |

Never install an unsuffixed `.bin`: with only suffixed ones, a name mix-up
fails to load instead of loading the other speaker's tuning.

---

## 6. Runbook (on the phone; each step has its stop condition and rollback)

From the omamobile repo, phone in Arch over USB, a second terminal running
`tools/phone-ssh dmesg -w`. Overlays as in `HAPTICS-TORCH-PLAN.md` 4:

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-audio KERNEL_OUT=$HOME/android/mainline/out-audio
O=$KERNEL_OUT D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb
ov() {  # ov NAME...: rebuild the DTB from default + overlays, then images
  cp -n "$D" "$D.default"; local o= n
  for n; do $O/scripts/dtc/dtc -q -I dts -O dtb -o out/$n.dtbo device/cheetah/overlays/$n.dtso; o="$o out/$n.dtbo"; done
  $O/scripts/dtc/fdtoverlay -i "$D.default" -o "$D" $o
  bin/omamobile images
}
# rollback for every overlay step: cp "$D.default" "$D"; bin/omamobile images && bin/omamobile push
```

### A0 userspace on a loopback card (no hardware)

```sh
U='U=$(id -nu 1000); as_user() { runuser -u $U -- env XDG_RUNTIME_DIR=/run/user/1000 "$@"; }'
tools/phone-ssh 'pacman -Q pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils pamixer'
tools/phone-ssh "$U"'; as_user systemctl --user is-active pipewire wireplumber pipewire-pulse; as_user wpctl status | head -30'
tools/phone-ssh 'modprobe snd-aloop; cat /proc/asound/cards'
tools/phone-ssh "$U"'; sleep 2; as_user wpctl status | sed -n "/Sinks/,/Sources/p"; as_user pactl get-default-sink'
tools/phone-ssh "$U"'; as_user speaker-test -D pipewire -c 2 -t sine -f 1000 -l 1'
```

Pass: the user services are active; after `snd-aloop` loads, WirePlumber
shows a "Loopback" sink and makes it the default; the volume keys move the
Omarchy OSD and `pactl get-sink-volume @DEFAULT_SINK@`; the quick-settings
slider (`Quickshell.Services.Pipewire` default sink) changes from
unavailable to a live value and follows the keys; `speaker-test` runs
without underruns (the loopback card makes no sound).

Stop: any of the services missing or failing. That is the per-user Omarchy
install gap (`NOTES.md`), fixed by running Omarchy's own install, not by hand.

Rollback: `modprobe -r snd-aloop`.

### A1 Bluetooth audio (after `BLUETOOTH-PLAN.md` BT3)

```sh
tools/phone-ssh 'ls /usr/lib/spa-0.2/bluez5/; ls /usr/share/omarchy/config/wireplumber/wireplumber.conf.d/'
# pair and connect a headset with bluetoothctl (BT3), then as the user:
wpctl status    # a bluez_output.* sink, A2DP profile
```

Pass: A2DP playback through the headset at moderate volume; the slider and
keys follow it. Omarchy's `bluetooth-a2dp-autoconnect.conf` asks
WirePlumber to auto-connect A2DP.

HFP (voice): the BCM4389 routes SCO to its PCM pins (the AoC) by default.
Switch it to the HCI transport after each controller power-on, then pick
the headset's HFP profile:

```sh
hcitool cmd 0x3f 0x1c 0x01 0x02 0x00 0x01 0x01   # Broadcom Write_SCO_PCM_Int_Param: routing 1 = transport
```

(`hcitool` is in Arch's `bluez-deprecated-tools`; `bluetoothctl` and
`btmgmt` cannot send raw vendor commands.)

To confirm on hardware: the command's status byte is 0 and mSBC/CVSD audio
flows. If it works, a small unit in `omamobile-device-cheetah` runs it when
hci0 comes up. Rollback: power-cycle the controller (`bluetoothctl power off/on`).

### A2 amplifier bus, read-only IDs

Build once from `wt-audio` (no config change needed for A2):

```sh
bin/omamobile kernel && bin/omamobile modules && bin/omamobile initramfs && bin/omamobile images
bin/omamobile modules-push && bin/omamobile push      # A2.0: default DTB
```

**A2.0 pass:** boots as before; `ls /sys/class/regulator/*/name | xargs cat`
lists `amp-va` and `amp-vp`; nothing else new. Rollback: previous images.

**A2.1 bus up, pin states (registers read, nothing written):**

```sh
ov audio-amps-test && bin/omamobile push
tools/phone-ssh 'ls /sys/bus/platform/devices/ | grep 10960000; for d in /sys/bus/spi/devices/spi*; do echo $d $(readlink -f $d/of_node | sed "s,.*/,,") $(readlink $d/driver); done'
tools/phone-ssh 'for a in 0x108401c0 0x108401c4 0x10840220 0x10840224 0x10c40040 0x10c40044 0x10c400a0 0x10c400a4 0x180e0000 0x180e0004 0x180e0040 0x180e0044; do printf "%s " $a; devmem $a 32; done'
```

Expect `10960000.spi` probed and two SPI devices `amplifier@0`/`@1` with no
driver. Decode (CON: 4 bits per pin, 0 input, 1 output, 3 SPI, 0xf EINT;
DAT: one bit per pin):

| Register | Pin | Expect |
|---|---|---|
| `0x108401c0` / `c4` gpp14 CON/DAT | 0-2 SPI, 3 CS top | CON nibbles 0-2 = 3, nibble 3 = 1; DAT bit 3 = 1 (CS idle) |
| `0x10840220` / `24` gpp17 | 1 = reset top | **record** CON nibble 1 and DAT bit 1: 1 = out of reset |
| `0x10c40040` / `44` gpp22 | 1 = CS bottom | CON nibble 1 = 1, DAT bit 1 = 1 |
| `0x10c400a0` / `a4` gpp25 | 2 = reset bottom | **record** CON nibble 2 and DAT bit 2 |
| `0x180e0000` / `04` gpa6 | 3 = IRQ top | DAT bit 3 = 0 (no interrupt pending, active high) |
| `0x180e0040` / `44` gpa8 | 6 = IRQ bottom | DAT bit 6 = 0 |

Stop: `10960000.spi` fails to probe, or any SPI error in dmesg. An IRQ line
reading 1 is not a stop, but note it for A3.

**A2.2 chip IDs over spidev (reads only):**

```sh
tools/phone-ssh 'modprobe spidev; for d in /sys/bus/spi/devices/spi*; do case $(readlink -f $d/of_node) in */spi@10960000/amplifier@*) echo spidev > $d/driver_override; echo ${d##*/} > /sys/bus/spi/drivers/spidev/bind;; esac; done; ls /dev/spidev*'
tools/phone-ssh 'python3 -' < tools/cs35l41-id
```

Binding applies each amp's default pin state, which makes its reset pin an
output at its current level: if A2.1 showed reset as an input, the amp may
go into reset now. That is harmless (reset = everything off).

Expect for each amp: `DEVID 0x00035a40`, `REVID` low byte `0xb2`,
`GLOBAL_EN 0`. Or "no answer (all zeros)" when A2.1 showed the reset low:
the bootloader leaves that amp in reset, so A3 is the first to see its ID.

Stop: a non-zero ID that isn't `0x35a40`/B2 (wrong chip select or bus),
SPI timeouts, or **`GLOBAL_EN` set** (something left an amp running).

Rollback: `echo spiB.C > /sys/bus/spi/drivers/spidev/unbind` (both), then
the default DTB.

### A3 driver probe (no card, no sound)

Add `CONFIG_SND_SOC_CS35L41_SPI=m` to the config fragment, rebuild kernel
and modules, and keep it from loading on its own:

```sh
tools/phone-ssh 'echo "blacklist snd_soc_cs35l41_spi" > /etc/modprobe.d/omamobile-audio-bringup.conf'
bin/omamobile modules-push && bin/omamobile push       # same overlay as A2
tools/phone-ssh 'modprobe snd-soc-cs35l41-spi; sleep 1; dmesg | grep -iE "cs35l41|10960000"; grep -i cs35l41 /proc/interrupts'
tools/phone-ssh 'for r in /sys/kernel/debug/regmap/spi*.[01]; do echo $r; head -c 65536 $r/registers | grep -iE "^0*(2014|2018|3800|3804|3808|3810|3814|4c00|6000|6c04):"; done'
```

The driver resets each amp, reads ID and OTP, applies the B2 errata
patch, writes the boost configuration and unmasks the error interrupts. It
never sets `GLOBAL_EN`: that only happens when a sound card powers the
output, and there is no card.

Expect per amp: "Cirrus Logic CS35L41 (35a40), Revision: B2" and
"Subsystem ID: cheetah"; interrupt counts 0 and not rising; registers
`2014` bit 0 = 0 (GLOBAL_EN), `3808` low byte `0x22` (2.5 A),
`3810` low 16 bits `0x4932`, `3814` bits 15:8 `0x75` and bits 1:0 `0`
(1 uH), `2018` bits 5:4 = 2 (boost armed, only runs with GLOBAL_EN),
`6c04` analog gain field 0. Record `3800`/`3804` (boost target and control
select, never written by the driver; the chip default should be class-H
with the `0xaa` = 11 V ceiling). Before A3 the peak-current register holds
the chip default `0x4a` (4.5 A); the DT's 2.5 A replaces it.

Failure points: "Failed to request IRQ" (pin or polarity: check the gpa6/gpa8
lines in `/proc/interrupts`), "OTP Unpack failed" or "CS35L41 Device ID
mismatch" (stop, report), an interrupt count that keeps rising (**stop**,
`rmmod`: an error condition is latched, e.g. boost or temperature).

Rollback: `rmmod snd_soc_cs35l41_spi` (puts both amps back into reset),
then the default DTB.

### A4 USB-C host audio (after USB-C B4b and B4c)

Host mode removes the USB gadget, so the test runs detached and undoes
itself (`USB-C-PLAN.md` B4c):

```sh
# on the phone, as root, started with systemd-run so it survives the link going down
systemd-run --unit=usb-audio-test sh -c '
  R=$(ls -d /sys/class/usb_role/*/role); echo host > $R; sleep 8
  { cat /proc/asound/cards; dmesg | tail -40; } > /root/usb-audio-test.log
  C=$(awk "/^ *[0-9]+ \\[/ {n = \$1} END {print n}" /proc/asound/cards)
  amixer -c "$C" sset PCM 30% >> /root/usb-audio-test.log 2>&1
  speaker-test -D "plughw:$C" -c 2 -t sine -f 1000 -l 1 >> /root/usb-audio-test.log 2>&1
  echo device > $R'
```

Pass: after the link comes back, the log lists the adapter's card and the
1 kHz tone was heard. Rollback: the script ends in device mode; a dead-man
timer (as `tools/usbc-deadman`) sets `device` if it does not.

### A5 USB gadget UAC2 (optional; the laptop plays the phone's audio)

With the A5 config, add a `uac2.0` function to the running gadget from a
detached script with a dead-man (unbinding the UDC drops SSH): unbind,
`mkdir functions/uac2.0` (48 kHz, 2 channels, S16), link it into `c.1`,
rebind. The laptop then sees a "UAC2_Gadget" card; the phone's playback
arrives there as a capture stream. Rollback: the dead-man removes the
link and rebinds the plain NCM+ACM gadget. Only worth doing if A1/A4 are far
off and a real ALSA card helps test PipeWire on the phone.

---

## 7. A6: AoC port (design only)

What the stock kernel does to get audio, in order, and what each needs:

| Step | Stock source (GPL) | Size | Our status |
|---|---|---|---|
| ACPM IPC channel 13 (AoC reset/power requests) | `GS/drivers/soc/google/acpm/` | | `ACPM-PLAN.md` (gs201 ACPM IPC on `omamobile-acpm`) |
| GSA mailbox: load and authenticate `aoc.bin`, start the AoC | `GS/drivers/soc/google/gsa/` | ~2,500 lines | none |
| SysMMU v8 for the AoC (`0x1a090000`), install the firmware's IOMMU table | `GS/drivers/iommu/samsung-iommu*.c` | ~3,200 lines (v8) | none; also wanted by display (`DISPLAY-PLAN.md`) and Wi-Fi |
| SSMT bypass, `aoc_req` handshake, S2MPU state | `G/google-modules/aoc/aoc_v1.c` | 370 | none |
| AoC mailboxes (whitechapel) | `G/google-modules/aoc/mailbox-wc.c` | 410 | none (mainline `exynos-mailbox` is the AP-APM one) |
| AoC core, services, channels | `G/google-modules/aoc/aoc.c`, `aoc_service_core.c`, `aoc_firmware.c`, `aoc-interface-gs201.h` | ~6,800 | none |
| AoC ALSA: card, PCM, controls, path (back ends incl. TDM 0 to the amps) | `G/google-modules/aoc/alsa/` | ~16,700 | none |

Open problems before writing code:

- **Does the AoC firmware set up the audio graph by itself**, or does it
  need commands that only the closed audio HAL sends (`audio_output_control`,
  `audio_input_control` services, `R/dmesg.txt:6101-6108`)? `mixer_paths.xml`
  covers part of it (TDM formats, mixers, mic IDs); read `aoc_alsa_ctl.c`
  and `aoc_alsa_path.c` for the rest.
- **AoC power state at hand-off**: read the PMU AoC status through the
  `exynos-pmu` regmap (read-only, via SMC); never touch `0x19000000` while it
  may be powered off (bus error).
- **Firmware licence**: `aoc.bin` is Google's, signed; extract from the
  phone's own vendor partition, never redistribute.

A7 then adds a machine driver (or `aoc_alsa`'s card) with the two CS35L41
as TDM 0 codecs, `snd_soc_limit_volume()` caps from section 4 in the
kernel, the calibration write (`speaker.cal` -> DSP `CAL_*` controls, as
mainline's `cs-amp-lib` does for HDA laptops), and UCM2.

---

## 8. Userspace: PipeWire, WirePlumber, UCM2

- **What Omarchy ships** (`/usr/share/omarchy/install/omarchy-base.packages`,
  `omarchy-other.packages`): `pipewire`, `pipewire-alsa`, `pipewire-pulse`,
  `pipewire-jack`, `wireplumber`, `alsa-utils`, `pamixer`, `libpulse`,
  `gst-plugin-pipewire`, plus `bluez`/`bluez-utils`. `sof-firmware` is
  Intel-only and harmless. The phone must get these from Omarchy's own
  install, which never fully ran there (`NOTES.md`).
- **Volume keys**: our `gpio-keys` emit KEY_VOLUMEUP/DOWN; Omarchy binds
  `XF86AudioRaiseVolume`/`Lower` to `omarchy-audio-output-volume` (pactl on
  the resolved physical sink, plus its OSD). Nothing phone-specific needed.
- **Quick settings**: `packages/omamobile-shell/plugins/omamobile.quicksettings/QuickSettings.qml`
  already uses `Pipewire.defaultAudioSink`; it lights up with any sink (A0).
- **Speaker tuning**: Omarchy's `omarchy-speaker-tuning.service` runs a
  filter-chain matched on the DMI product SKU. The phone has no DMI, so a
  cheetah tuning needs a device-tree match upstream in Omarchy; only after
  protection runs (A7), and never as a substitute for it.
- **UCM2** (A7): no upstream profile exists. Write one for our card with a
  `HiFi` verb: `Speaker` (both amps, DSP, stereo), `Mic` (AoC internal mic,
  IDs 0/3/2), and a `Voice Call` verb with `Earpiece` (top amp only, `PCM
  Source` ASP, `Analog PCM Volume` 6) and `Mic`. Give `Earpiece` the lowest
  priority so WirePlumber never picks it as a default sink. USB and
  Bluetooth devices are separate cards and need no UCM.

---

## 9. Risks and open questions

| Risk | Answer |
|---|---|
| Speaker damage from gain, boost or missing protection | section 4 limits; nothing can play before A6/A7 anyway; A2/A3 never enable the output |
| Wrong tuning file on the wrong speaker | suffixed-only firmware names (5); confirm mapping by ear first (4.1) |
| Wrong calibration record per amp | open: confirm (4.2) before enabling protection |
| PERIC0 register reads hanging if its clock were off | A2.1 reads only after the overlay probes `pinctrl@10840000` (its driver enables the clock); `clk_ignore_unused` keeps ABL's clocks |
| A3 IRQ storm from a latched amp error | stop and `rmmod`; reset puts the amp off |
| USB lifeline lost in A4/A5 | detached scripts with dead-man undo, as in `USB-C-PLAN.md` |

Open questions:

- Does ABL leave either amplifier out of reset (A2.1 answers)?
- Is S2MPG13 BUCKA really 1.8 V? Read it once ACPM PMIC access exists; the
  fixed regulator is only a placeholder.
- Which `speaker.cal` record is which amp; what the last two words
  (`0x11`, `0x331`) are (firmware/algorithm version?).
- Can the AoC audio graph be brought up without the closed audio HAL (A6)?
- Does Broadcom's `0xfc1c` SCO routing command apply to the BCM4389
  firmware as on older BCM chips (A1)?
