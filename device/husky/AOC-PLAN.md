<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro (husky): AoC and sound plan

Status 2026-11-07: kernel pull requests 203 and 204 (derekross/linux-omarchy-mobile) and package pull request 453 (derekross/omarchy-mobile) now carry the work below. Status 2026-11-06: **the AoC runs on the 8 Pro and the speakers play** (a test branch on one phone, not in a pull request). Sound goes through Google's AoC (the audio DSP): the AoC core and ALSA drivers ported from the 7 Pro's, a zuma System MMU programmer, the two CS35L41 amplifiers and Google's speaker-protection firmware. Mics, the earpiece and headset paths, calibration and the husky speaker ceilings are not done. [V] = read in a file or seen on the phone, [I] = inferred, [U] = unknown. The model is `device/cheetah/AOC-PLAN.md` (the 7 Pro's AoC is online; its Stages C0 to C10 are the template).

The code that ran is public: branch `husky-e1-aoc-20261106` and tag `husky-test-20261106-e1-aoc` on https://github.com/Somnius/linux-omarchy-mobile (commit `7fa4d8b91`; the `uname -r` of its last build is `7.3.0-rc6-omamobile-push1-g1f109674c767`). It is Brett's c6 tag plus my commits, all "TEST ONLY": nothing there is meant to go upstream as it is. Two of the commit messages were reworded for publishing, so the commit ids in the `uname -r` of the later builds differ from the branch (the trees are the same); the table below gives both. No firmware, calibration or other blob is in the branch.

## 1. Facts (stage 0)

From Google's GPL tree (`android-gs-shusky-6.1-android16`; `kernel/devices/google/zuma` and `shusky` `dts/`, and `kernel/google-modules/aoc`).

- [V] `zuma-aoc.dtsi`: `aoc@17000000`, compatible `google,aoc`; regs `blk_aoc` 0x17000000 (32 MiB), `aoc_req` 0x154B0000, `aoc_s2mpu` 0x190C0000, `ssmt_aoc` 0x19060000; watchdog interrupt; `iommus = <&sysmmu_aoc>`; `memory-region = <&aoc_reserve>` (aoc@94000000, the carve-out we already have); `gsa-enabled`, `gsa-device = <&gsa>`; 48 mailbox channels over three `google,mailbox-whitechapel` mailboxes at 0x15200000 (a32), 0x15220000 (f1), 0x15240000 (p6); `acpm-ipc-channel = <13>`; `pcu-base` 0x1400000, `gpio-base` 0x1C00000, `pcu-db-set-offset` 0x1F004, `pcu-db-clr-offset` 0x1F008, cp aperture 0x7FDF80 to 0x7FFFFF, `clock-divider` 1, `force-vnom = <0>`.
- [V] husky only adds `aoc-board-cfg = "HK3"`, `aoc-board-id = <0x40202>`, `aoc-board-rev = <0x10000>` (`zuma-husky-audio.dtsi`). Amplifiers: two `cirrus,cs35l41` on `spi_19` (HSI0 USI1), chip selects the controller's own CS0 and gpn1-0 (`zuma-shusky-audio.dtsi`). The ALSA card is Google's AoC card; `zuma-audio.dtsi` includes `gs101-audio.dtsi`.
- [V] GSA: non-secure mailbox 0x16490000 (SPI 375), compatible `google,gs101-gsa-v1`; the AoC's System MMU is `samsung,sysmmu-v9` at 0x19090000, its S2MPU `google,s2mpu-v9`.
- [V] The AoC interface header for zuma differs from gs201's by about 120 lines (new commands, a speed config for the output decoder, a few ASP IDs).
- [V] Firmware, from the owner's own vendor image (never in a repo): `aoc.bin`, 29,076,160 bytes, release **16047897-polygon** (the 7 Pro's was 14022723): signed auth header v2, `fw_start` **0x94000000**, `fw_size` 0x1c00000, seven IOMMU windows (virtual to physical, size): 0x98000000 to 0x94000000 0x3000000; 0x9b000000 to 0x97000000 0x400000; 0x9e000000 to 0x15100000 0x200000; 0x9e200000 to 0x16400000 0x100000; 0x9e500000 to 0x11200000 0x100000; 0x9e300000 to 0x40000000 0x80000; 0x9e380000 to 0x40400000 0x80000. The 7 Pro's firmware has six windows.

## 2. Stages and results

| Stage | What | Date, `uname -r` (`7.3.0-rc6-omamobile-push1-` +) | Result |
| --- | --- | --- | --- |
| Z0 | offline facts, the header, the windows | 2026-11-04, none | done |
| Z1 | GSA node (mailbox 0x16490000, SPI 375), module by hand, `sjtag_status` and the GET_STATE query (mailbox command 91) | 2026-11-04, `gbf556c5b22ba` | `mailbox ready`, state "inactive", `sjtag_status` `hw_status 0x10` |
| Z2 | Trusty (project ripcurrent build 15649251, api 5): connect to `com.android.trusty.gsa.hwmgr.aoc` | 2026-11-04, `g534d7fa07ed9` | works **only if `trusty-ipc` is loaded before `trusty-virtio`**: the other way round Trusty logs `validate_descr:1094: unexpected status 1`, never sends GO_ONLINE and the GSA's connect fails with -ENOENT (a reboot clears it). Ports `hwmgr.aoc`, `.tpu`, `.dsp` connect |
| Z1b | read-only: `aoc_req` and its acknowledge | 2026-11-04, `gd39ee40b43b6` | `aoc_req 1 ack 1`: the bootloader leaves BLK_AOC powered. **Reading the AoC System MMU and S2MPU registers reset the phone** (see 3) |
| Z3 | describe the AoC, the three mailboxes, the S2MPU, the System MMU (v9) and the carve-out in the DT | 2026-11-04, `gd39ee40b43b6` | probes succeed |
| Z5 | load: copy `aoc.bin` into the carve-out, GSA command 90, the AoC S2MPU (CTRL0 = 0), the System MMU windows | 2026-11-05, `g3e4f718872d` | image validates, command 90 returns 0, v9 windows install (first attempt stopped on the two 512 KiB windows, fixed with 4 KiB pages), no reset |
| Z6 | start through Trusty | 2026-11-05, `g3e4f718872d` | GSA state 2 "running", control block magic 0xa0c00a0c, **94 services** about 0.65 s after the start |
| Z7a | the AoC core driver (mailboxes, service rings) | 2026-11-05, `g0d5de1bbb9b4` | `did become online with 94 services` |
| Z7b | spi19 clocks and DT, both amplifiers | 2026-11-05, `g4b0fc77182d8`, `gbb5ba9ba53d2` | both probe as `Cirrus Logic CS35L41 (35a40), Revision: B2`, subsystem "husky" (see 4) |
| Z7c | ALSA card, amplifiers linked into it, protection firmware | 2026-11-05, `g757721ba1a81` | the card `google,aoc-snd-card` with 30 PCM devices and the amplifiers' controls; protection firmware loads on both |
| Z7d | first sound | 2026-11-05, `g74d6ba329f68` | the speaker route is the deep-buffer entry point (`TDM_0_RX Mixer EP6`); EP1 (UltraLL) hangs the AoC (see 5) |
| Z7e | PipeWire / browser sound, boot unit | 2026-11-05, `g69c83385020e`, `gd0d87517121a` | works (see 6) |
| Z8 | the packaged start: `omamobile-husky-aoc.service` and its script from derekross/omarchy-mobile#453 (local builds of omamobile-device-husky 0.1.9 and omamobile-audio 0.5.18 from `aafe089` and `80e5905`; the versions that merged are Derek's), no hand steps | 2026-11-09, `ga291900124c4` | see "The packaged start" below |

### The packaged start (2026-11-09, one phone, kernel `ga291900124c4`)

With the packages from #453 installed and my hand-installed start, UCM and WirePlumber files moved away: a first boot (which I recovered by hand), then a clean cold boot; the A/B check below used two more cold boots.

- **First boot: "no firmware node in /sys/bus/platform/devices/154b0000.aoc"** [V]. The unit stopped before touching the firmware file, as it should. My test kernel carries `gs201_aoc_boot`, which matches `google,zuma-aoc`, so it autoloaded and bound the AoC node before `aoc_core`; my old local blacklist had hidden that. `80e5905` adds `blacklist gs201_aoc_boot` to the package. Derek's note on #453: the published kernel's `gs201_aoc_boot` only matches `google,gs201-aoc`, so the line does nothing there (the 7 Pro's and Pixel 6 Pro's packages have it too); it matters only on a test kernel like mine.
- **Trusty is under `soc@0` on the 8 Pro** [V]: `/proc/device-tree/soc@0/trusty/status` reads `okay`, and the start script looked for `/proc/device-tree/trusty/status` only. `aafe089` checks both, with tests for the root layout, the `soc@0` layout and no node (it still fails closed with no node).
- **Second boot, cold, no hand steps** [V]: the card came up within a second or two of the unit starting, `Services : 94`, `EP6 playback` and `EP1 capture`, no failed units, no CS35L41 mailbox errors, uptime 203 s. `tools/phone-smoke` on that boot (at 898 s of uptime): every required check ok, 0 WARN and 0 errors in dmesg, hottest zone 54 C.
- **A/B tone check** [V]: the packaged start and my old hand-run start, each on a cold boot, amplifiers at digital 737 and analog 8 (top) and 10 (bottom), `pw-play` at 1.0, speaker 0.75, a file with 440 Hz left then 880 Hz right peaking at -22 and -12 dBFS. Both tones were heard clean on both paths, and the mic (EP1 mono, 48 kHz) read the 880 Hz tone at -51.6 and -43.1 dBFS (hand-run) against -52.9 and -43.1 (packaged), within about a dB. The first test file (`lr-test.wav`) peaked at -32 dBFS and was near the hearing threshold, so the quiet speaker I reported on #453 was that file, not a fault. Nothing above -12 dBFS was played, and the ceilings (737 / 8 and 10) were not exceeded.
- **Unexplained** [U]: seven `cs35l41 spi1.1: Failed to set mailbox cmd 1` lines (with `Bottom DSP1 event failed: -42`) at about 271 s of uptime on the first boot, which I had recovered by hand (`modprobe -r gs201_aoc_boot`, binding the node to `aoc_core`, starting the unit). None of the four earlier boots and none of the cold boots had them. Cause unknown. Derek's advice on #453: after a failed start a reboot is the safer way back than unloading and rebinding by hand.
- **Not covered** [U]: the packaged `HiFi.conf` drives both amplifiers in stereo for the Speaker device, where my old one used the bottom one only. Which `HiFi.conf` the hand-run side of the A/B check used was not recorded, and the difference was not measured further.

Public commit ids of the kernels whose ids differ on the branch: `gbb5ba9ba53d2` is `3239ac2628e4`, `g757721ba1a81` is `d59a29c08111`, `g3f5ba5e70070` is `9bd5c74b96da`, `g74d6ba329f68` is `cc4f0ec38718`, `gd0d87517121a` is `08c3095dc5aa`, `g1f109674c767` is `7fa4d8b91e8b`. Kernels up to `g4b0fc77182d8` have the same id on the branch.

## 3. The System MMU read that reset the phone

2026-11-04, `7.3.0-rc6-omamobile-push1-gd39ee40b43b6`: a debugfs file of my bring-up driver (`debugfs/aoc/blk`) reading the AoC System MMU and S2MPU registers **reset the phone at once** (no oops text; it came back by itself, nothing flashed). Cause, found on 2026-11-05 with `g129efb688b6f`: I had copied the 7 Pro's (gs201, v8) register offsets (CAPA0/CAPA1 0x870 and 0x874, CFG 0x4, interrupt registers at 0x60), and zuma's System MMU is v9, which does not have them. With the v9 map (CTRL 0x0, STATUS 0x8, VERSION 0x34, the VM registers at 0x8000) the same read gives `version 0x90000000`, `ctrl 0`, `status 0`, and the AoC S2MPU's CTRL0 reads 0, with no reset. The v9 programmer is a static table beside the 7 Pro's `gs201-aoc-sysmmu.c` (its own compatible, `google,zuma-aoc-sysmmu`): the first-level table for the firmware's seven windows, the 4 KiB-page path for the two 512 KiB windows, the AP read/write bits, QoS 15, VID 0 only, the 29 stream matches of Google's `sysmmu_aoc` node, no fault interrupt yet.

## 4. The amplifiers share MISO and one chip select is the native one

2026-11-05. Both CS35L41 are on `spi19`: amplifier 1 on the controller's native CS0, amplifier 2 on a GPIO (gpn1-0). `spi-s3c64xx` asserts the native nSS for every message, also for a device on a GPIO chip select, so both amplifiers drove MISO when amplifier 2 was addressed and it read zeros. A test that kept the native nSS released gave `-EIO` (the shifter does not run without it). Setting the native nSS to auto mode (`CS_AUTO | NSC_CNT_2 | SIG_INACT`) for devices on a GPIO chip select makes both probe (`g4b0fc77182d8`); it only runs on controllers with `manual_native_cs`, which only the zuma/zumapro port config sets (not the gs101 one the 7 Pro binds). Not shown yet: that a write to one amplifier does not reach the other. This will go to the kernel repository as its own change.

## 5. The speaker route, and what hangs the AoC

- [V] `TDM_0_RX Mixer EP1 = 1` (source 0, UltraLL) permanently stalls the AoC firmware after `Source 0 [UltraLL] mastered by sink 0 [Speaker]` / `Power: Yes, Config: No` (its watchdog fires 4 to 14 s later; with the watchdog disabled the firmware stays stuck). The 7 Pro's route, `TDM_0_RX Mixer EP6` (deep buffer, source 5), starts the speaker TDM at 6144 kHz: `Speaker TDM Started with Clk: 6144 KHz, FS: 48 KHz, Slots: 4`. Binding the I2S_0 sink instead returns an error and the AoC survives. Not the cause, each tested: the System MMU/SSMT, the amplifiers, ACPM, the GSA.
- [V] The card needs the `clks` block of the stock DT (BCLK as the amplifiers' system clock), or the amplifiers' power-up times out (`Enable(1) failed: -110`), and `force-vnom = <0>` on the AoC node (a missing property reads as set in `aoc.c`).
- [V] The AoC's debug shell on `/dev/acd-debug` (`help`, `watchdog_enable off`) and its log on `/dev/acd-logging` helped. `bclk ds` and `gpio ds` are drive-strength overrides, not dumps: running them was a mistake. Reading the AoC's PCU registers from the AP resets the SoC: do not.

## 6. The deep-buffer entry point and PipeWire

The AoC's deep-buffer entry point (EP6) throws away what was written before the stream starts (its read index jumps to the write index, no interrupt) and starts consuming only when its ring is 75 % full. `aplay -R -450000` (a small start threshold) plays; PipeWire pre-fills and then stops writing because `hw_ptr` stays at 0. The test branch has two driver changes in the shared ALSA driver (`aoc_alsa_pcm.c`, `aoc_alsa_hw.c`): the PCM pointer is taken from the live ring read index, and the pre-start data is kept and written again once the AoC has started. **These are not gated for zuma yet** and must not reach the 7 Pro: they go behind zuma's match data, with the 7 Pro's objects shown unchanged, before any pull request. The WirePlumber rule that works: match `alsa_output.platform-sound-aoc.*`, S16LE, no mmap, 960-frame periods, headroom 6000 frames, no idle-suspend. The UCM2 profile is keyed on the card driver name `aoc-snd-card` (`alsactl info` shows `driver_name: aoc-snd-card`, `longname: google,aoc-snd-card`).

## 7. Speaker levels and protection

The 7 Pro's stages (`omamobile-audio`): `media` is digital at most 737 and analog at most 10 on both amplifiers, `c9` is stock's 817 and 17. The speaker protection firmware (`cs35l41-dsp1-spk-prot.wmfw` and the `.bin` tunings from the owner's own vendor image, HK3 tuning, v0.59.0) is loaded on both amplifiers with the PCM source set to DSP, but the 8 Pro has **no calibration of its own** and VMON/IMON were not read, so it is not shown to be protecting. On 2026-11-05 the 8 Pro was driven above `media` during level tests. As I wrote it on issue #1: "Short tone bursts on the bottom amp at `c9` numbers (digital 817, analog 12 up to 17, a few seconds each), and then a good while, tens of minutes, of YouTube and music through the bottom amp at digital 817 / analog 8. The top amp went up to 817 / analog 8 for music too." "I had been loading the card driver with `speaker_protection=1`, which allows analog 17; the boot unit doesn't anymore." Since 2026-11-06 06:50 both amplifiers are back at digital <= 737 / analog <= 10 (the UCM profile and the boot unit enforce it) and stay there until husky has ceilings of its own. From the same comment: "No amp fault or over-temperature in dmesg, AoC fine." Firmware and calibration stay out of every repository.

## 8. Next

1. This document and the public branch (done with this change).
   Now in review: kernel pull requests derekross/linux-omarchy-mobile#203 and #204. Merged 2026-11-09: package pull request derekross/omarchy-mobile#453 (the AoC start with a hang marker and the UCM2 profile; results in "The packaged start" above).
2. The spi-s3c64xx change as a pull request against `omamobile`, with cheetah's object file before and after, the 9a's SPI nodes, and the check that a write to one amplifier does not reach the other.
3. The zuma System MMU v9 file beside `gs201-aoc-sysmmu.c`, with its own compatible and table.
4. The driver changes of section 6 behind zuma's match data, with the 7 Pro's objects shown unchanged.
5. The AoC boot unit in `omamobile-device-husky` with a hang marker written before the hardware is touched (skip the step when the previous boot left it), and the UCM2 profile and the WirePlumber rule in `omamobile-audio`, keyed on husky's card name, with the amplifier driver blacklisted so only the protection service loads it.
6. Then: husky's own speaker ceilings (calibration), microphones (the PMIC rails are [U]), earpiece, headset, Bluetooth routing.

## 9. Safety (from the 7 Pro's findings, unchanged)

Never read the carve-out after load; touch the S2MPU only the way the GSA does; no PMU reads from user space and no reads of the AoC's internal blocks from the AP; the speaker limits above apply; a failed AoC start cannot be retried in the same boot, so the boot unit writes a hang marker first; nothing here sources power or changes charging; every flash has the backup and the owner at the phone. Reboot loops are recovered through fastboot (Volume Down + Power), never by writing the partitions of a phone that resets.

On `/dev/acd-debug` only `help` and read commands are run without asking first: `watchdog_enable off`, `bclk ds` and `gpio ds` all change something.
