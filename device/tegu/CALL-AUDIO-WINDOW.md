<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a: AoC voice-window audit

2026-11-02, offline. This supports TELEPHONY-PLAN section 1 (PR #360);
no call, memory access or phone operation was performed.

**The firmware voice path has a shared SRAM window; the Linux call-audio
route does not need a new CPU mapping of it.** The checked CPIF and AoC
paths provide no evidence that adding the omitted CPIF region is required
to start a PCIe call. Whether the running firmware's path works remains
unqualified until the attended call test.

Where it comes from:

- MODEM-PLAN F3 records tegu's own stock DT capture: `cp_aoc_rmem` is
  12 KiB at AP physical address `0x197fd000`. The stock `cp_shmem` node's
  fourth `memory-region` references it; `VSS_AOC` selects `SHMEM_VSS`
  (index 1), rmem index 3, offset 0, size `0x3000`, uncached. This is AoC
  SRAM, not a buffer for userspace to allocate. Google's
  [GPL reservation](https://android.googlesource.com/kernel/devices/google/zuma/+/eb90f2862e78b4c409ff992e116c44e81f836e9e/dts/zuma-rmem.dtsi)
  and [shared-memory description](https://android.googlesource.com/kernel/devices/google/zuma/+/b0dfdfc378dd37d7c1662bbd942240d55db83d68/dts/zuma-cp-s5300-sit.dtsi)
  describe the same resource; tegu's capture is the board-specific evidence.
- Our tegu `zumapro-reserved-memory.dtsi` already reserves this range as
  `cp-aoc@197fd000`, with `no-map`. Omitting the CPIF region from the
  bring-up overlay does not remove that reservation.
- In the GPL CPIF port, `init_shmem_maps()` maps VSS only in the
  `LINKDEV_SHMEM` case; tegu uses `LINKDEV_PCIE`. Its PCIe path does not
  require `vss_base` to start. Google's
  [GPL implementation](https://android.googlesource.com/kernel/google-modules/radio/samsung/s5300/+/refs/tags/android-16.0.0_r0.10/link_device.c)
  preserves that distinction. Diagnostic accessors/dump support are not
  the voice-stream transport.
- `aoc_alsa_voice.c` prepares the voice PCM through `prepare_phonecall()`
  in `aoc_alsa_hw.c`. For playback PCM 4 it sends
  `CMD_AUDIO_OUTPUT_TELEPHONY_MODEM_START_ID` (256); close sends STOP
  (257). Both are header-only AoC commands, with no supplied memory
  address (also confirmed in the saved GPL Zuma interface header).
  The speech stays between the modem and AoC; sitd owns the PCM handles
  and mixers, not the SRAM.

Keep the reservation and leave the window CPU-unmapped. This change adds
no DT region, PCIe translation, S2MPU permission or userspace memory
access. If a later call establishes a missing firmware-side window, trace
the stock tegu firmware/translation setup separately before any kernel
change; do not substitute another board's address or map the SRAM to
inspect it. The first call still needs the plan's gain checks, log stream,
watchdog, stop conditions and attended recovery.
