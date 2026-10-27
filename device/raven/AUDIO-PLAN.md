<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): AoC, speakers and microphones

Status (2026-10-27): **sound works on raven with speaker protection on; the
packages in #41 leave it off.** With protection on (omamobile-audio 0.4.4,
stage media): both speakers and the microphones, through raven's own
protection firmware and tuning files and the phone's factory calibration;
the AoC and the sensors as well. Not done: raven's own ceilings. The stage
limits and the loudness filter are cheetah's, and nothing on raven has
measured the coil at each gain step or run `verify` (cheetah's C8/C9). So
#41's packages keep protection off, `cs35l41` never loads, and the card
waits for the amplifier codecs: no speakers **and no microphones** there
("Without the amplifiers" below). Next, each its own branch: the card and
microphones without the amplifiers, then raven's ceilings, then speakers on
by default.

Earlier status (2026-10-15): **Sound works on raven: both speakers (heard), the microphones, at boot from packages** (omamobile-device-raven 0.1.4, omamobile-audio 0.4.4), protection at stage media. R5: the sensors work through the AoC (omamobile-sensors 0.2.0). Next: raven's own speaker tuning. Kernel branch `omamobile-gs101-aoc`
(the hashes below are from the stacked bring-up branch it was split from):
- cheetah's Trusty, GSA and AoC stack imported (`ce7ae89a5`, `fa0873edc`);
- it builds against gs101's firmware interface (`9f5ed4b1f`, raven's
  `device/raven/kernel.config` sets `CONFIG_GOOGLE_AOC_GS101`);
- gs101 compatibles in the GSA, AoC, SysMMU and mailbox drivers, and
  disabled DT nodes for Trusty, GSA, the AoC SysMMU, the AoC mailbox and
  the AoC (`aa41c40c0`); builds clean.
- Findings:
  - the AoC carve-out is `0x94000000` on both SoCs (already reserved
    upstream as `aoc_reserve`);
  - the boot helper's `AOC_DRAM_BASE 0x98000000` is the AoC's own view;
  - the AoC core counts its mailbox channels from `mboxes` (16 on gs101).
- Next: the AoC rails on raven's PMICs (`gs201-aoc-rails.c` speaks
  S2MPG12/13), the AoC firmware in `extract-vendor-firmware -d raven`, then
  R1 on the phone.
- **R1 setup done (2026-10-15, kernel `g8c2f974b6ab5`, branch head
  `8c2f974b6`):**
  - Trusty and GSA are enabled in raven's DT and the phone runs that kernel.
  - Every AoC-stack module is blacklisted on the phone
    (`/etc/modprobe.d/omamobile-raven-aoc-bringup.conf`, not packaged yet).
  - Next: load `trusty_core`, `trusty_log` and `gsa` by hand, with kmsg
    streamed and the watchdog fed, and read the Trusty log. No RPMB writes
    and no storageproxyd.
- 2026-10-15 checks before R1 (read-only): the AoC-stack blacklist is
  in place and nothing from it is loaded; `/trusty` and `gsa@17c90000`
  are `okay`; rfkill leaves Bluetooth and Wi-Fi unblocked. GrapheneOS had
  changed efs, efs_backup, modem_userdata and persist, so a fresh backup
  was taken (`~/android/reference/raven-backup-2026-10-15b`, all six
  images match the phone).

The goal: port cheetah's AoC stack (`device/cheetah/AOC-PLAN.md`: on cheetah the AoC starts at every
boot and drives both speakers, the microphones and the sensors) to gs101.
The calibration partitions were checked first: four of them differed after
GrapheneOS's boot on 2026-10-14 (efs, efs_backup, modem_userdata, persist).
A fresh read-only backup is in `~/android/reference/raven-backup-2026-10-15`,
verified against the phone (private, never committed).

## R1 runbook (Trusty and GSA, by hand)

Uses `tools/aoc-stage` from branch `omamobile-raven-tools` (its `trusty`
and `gsa` stages need no AoC node). Each step streams kmsg to `logs/`
first. No RPMB writes, no `storageproxyd`, no AoC firmware. There is no
slot A on this phone: a human stays at the phone for the whole runbook.

| Step | Command | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| R1.0 | backup check (AGENTS.md M0.1) against `raven-backup-2026-10-15b` | all six match | any differs | none (stop) | read-only |
| R1.1 | `tools/aoc-stage --watchdog trusty` | `modprobe-exit=0`, Trusty version line, `/dev/trusty-ipc-dev0` exists | SError, hang, no `trusty-ipc-dev0` | watchdog resets in ~15 s; then `--pstore` | medium: first SMC calls into the secure world |
| R1.2 | Trusty log: `tools/phone-ssh 'dmesg \| grep -i trusty'` | Trusty's own boot lines, no panic | a Trusty panic | reboot (`reboot-to omamobile`) | read-only |
| R1.3 | `tools/aoc-stage --watchdog gsa` | `mailbox ready, irq N, S2MPU, Trusty`; `sjtag_status` and `aoc_state_tz` answer | probe error or hang | as R1.1 | low |

After a hang: wait for the watchdog reset, then `tools/aoc-stage --pstore`.
Never `rmmod` these modules (AGENTS.md); reboot instead. Record each result
here with the date and `uname -r`. Pass for R1: R1.1-R1.3; then R2 (the
AoC through Trusty's hwmgr) needs the AoC node and raven's rails.

**R1 results (2026-10-15, `7.3.0-rc6-omamobile-push1-g8c2f974b6ab5`): passed.**
- R1.0: all six calibration images match `raven-backup-2026-10-15b`.
- R1.1: `trusty version: Project: slider, Build: 15644732, Built: 13:17:42
  Jun 15 2026`, API version 5; `trusty_ipc virtio0: is online`;
  `/dev/trusty-ipc-dev0` present. No hang.
- R1.2: Trusty's log shows no panic, but one error near its init banner
  (so probably from its start at boot, before Linux):
  `dma_buf: 64: Mbox cmd err = 1` and
  `gsaproxy: 532: Failed (-1) to set GSA mbox DMA buf`. Not seen on cheetah
  (no log of it). **Open question for R2:** the AoC start goes through the
  GSA, so if R2.3/R2.4 fail, look here first.
- R1.3: `google-gsa 17c90000.gsa: mailbox ready, irq 147, Trusty`;
  `sjtag_status` answers (cmd 100, err 0); `TZ:
  com.android.trusty.gsa.hwmgr.aoc connected`; `aoc_state_tz`: state 0
  (inactive). No hang; the watchdog feeder stopped cleanly.

**R5 results (2026-10-15, `g6ca39f28ee4c`): passed.**
- Registry: raven's vendor has `etc/sensors/registry/` (`raven_evt.reg`,
  `raven_evt_win.reg`, `raven_pro_1_0.reg`, `raven_pro_1_1.reg`,
  `append/motion_state.reg`); `extract-vendor-firmware -d raven` now stages
  it and it sits in `/usr/share/omamobile/sensors/registry` (Google's files,
  not packaged). The CDT comes from `/chosen/plat`, as on cheetah.
- `usf.py --load-registry … --list`: the AoC creates raven's sensors:
  LSM6DSR accelerometer, gyroscope, temperature and motion events (cheetah
  has an LSM6DSV), TMD3719 light and proximity, two MMC56X3X magnetometers,
  ICP10101 pressure, VD6282 rear light/flicker/spectral, the touch gesture
  sensors and Google's virtual ones (game rotation, pickup, auto
  brightness, motion state). Accelerometer at 10 Hz: z about 9.95 m/s^2
  lying flat.
- `omamobile-sensors` 0.2.0 unchanged (built and installed from the local
  repo, `omamobile-sensor-proxy` enabled by hand as cheetah's setup does):
  `sensors: accel (handle 29), light (43), proximity (23), compass (52), gyro
  (30, 13-416 Hz)`; over D-Bus: `HasAccelerometer` 1, orientation undefined
  (flat), light 4.5 lux, proximity far. The gyro range comes from the
  sensor itself, so the LSM6DSR's rates need no change.

**R4 results so far (2026-10-15):**
- Kernel: `omamobile-gs101-audio` `6840f2059` describes both CS35L41s on SPI 13
  (disabled); `device/raven/overlays/audio-amps-test.dtso` enables USI13,
  SPI 13 and both amplifiers. `snd_soc_cs35l41(_spi)` is blacklisted on the
  phone (`/etc/modprobe.d/omamobile-raven-amps-bringup.conf`, not packaged).
- **Thermal on that kernel (`g54329ac04b65`):** three boots of four powered off
  cleanly at about 17.5 s: `big-thermal: critical temperature reached`. A
  temperature log showed real heat, not a bad reading: big 51 to 103 C in
  about 6 s as the UI started (mid and little to 88), then back to 60 C.
  The phone idled at 52 C after hours on the charger, and step_wise adds one
  cooling state per 250 ms poll (big has 16). No process used much CPU
  (quickshell 2 s in 100 s), so no runaway loop. Fix on
  `omamobile-gs101-thermal` `a52582432`: polls of 250 ms (100 ms passive) and a
  second passive trip at 95 C that throttles at once (big state 10, mid 8,
  little 6). On `g8a843c69252e` two more boots ended after about a second of
  journal (hard reset, cause not known), then the phone stayed up; big
  peaked about 62 C at 2.4 GHz.
- **A2** (spidev, read-only, `tools/cs35l41-id`): both read all zeros, with
  the reset lines (gpp16-3, gpp23-7) held as outputs by the default pin
  state: in reset, as cheetah's plan expects.
- **A3: passed.** `modprobe snd_soc_cs35l41_spi`: `spi1.0` and `spi1.1`:
  `Subsystem ID: raven`, `Cirrus Logic CS35L41 (35a40), Revision: B2`; taint
  0. No sound card links them yet, so their output stage stays off.
- TDM 0: stock raven's `mixer_paths.xml` uses cheetah's slots (L/top RX
  slot 0, R/bottom slot 1; feedback TX 0,2,4,6 and 1,3,5,7), so
  `aoc-sound-test` is now cheetah's overlay with its codec links and
  amplifier clocks.
- Protection (`omamobile-audio` 0.4.2, run from `/tmp`, not installed):
  `persist:/audio/speaker.cal` is 48 bytes (two records), read read-only;
  `start`: both amplifiers held awake, calibration written to both DSPs and
  read back, healthy, **speaker protection on (stage media), 737/10 on
  both**. Firmware from `extract-vendor-firmware -d raven` in
  `/usr/lib/firmware/updates/cirrus` (not packaged).
- First tone (2 s, 1 kHz, -20 dBFS, left only, EP6 to TDM 0 at Four/S32_LE/48k,
  stock's DSP path): played, amplifiers healthy, but ALSA logged `invalid
  position: pos = 1073740800`: `aoc_pcm_update_pos()` rounded an unsigned
  position below zero right after a wrap. Fixed on `omamobile-gs101-aoc`;
  on `g6ca39f28ee4c` the same tone plays with no error, healthy, taint 0.
- **Heard (2026-10-15):** the top speaker on the left channel and the bottom
  one on the right, as stock's slots say.
- UCM (`omamobile-audio` 0.4.3+): one `conf.d` entry for both phones; raven
  is picked by a `Path` condition on its AoC node and gets mics 0,1,2.
- **Packaged and at boot (0.1.4 / 0.4.4, unsigned local repo):**
  `omamobile-aoc.service` (raven's copy of the hang-safe start script, no
  rails step) and `omamobile-speaker-protection.service` (enabled by hand,
  as the package leaves it off) bring up the AoC, the card and protection by
  about 10 s of uptime; the bring-up blacklists in `/etc/modprobe.d` are
  gone. PipeWire shows `Built-in Audio Speaker` (default sink) and
  `Built-in Audio Microphone`; `pw-play` as the user plays a tone, healthy,
  taint 0. Cheetah's loudness filter runs on raven too: raven's own tuning is
  still to do.
- Next: the tone heard from each speaker (top on L, bottom on R), then a raven
  UCM profile, a packaged `omamobile-aoc-start` for raven and the protection
  service at boot.
- Next: the TDM 0 codec link and clocks in `aoc-sound-test` (as cheetah's,
  with stock raven's slot use), raven's speaker calibration (from the
  phone's own `persist`, never committed) and the protection service, then
  a quiet tone at stage `media`.

**R3 results (2026-10-15, `7.3.0-rc6-omamobile-push1-gb8ae147c37d0`): passed.**
- Kernel (`omamobile-gs101-aoc`): `aoc_core` runs Google's gs101 `blkpwr_aoc`
  on sequence (`aoc_blk_pd_on()`, through the PMU regmap) before it touches
  the S2MPU (`bae944541`); `mailbox-wc` takes an optional APB clock and
  gs101's AoC mailbox names `CLK_GOUT_APM_MAILBOX_AP_AOC_PCLK`
  (`b4ab8345d`).
- DT: `device/raven/overlays/aoc-sound-test.dtso`. Raven's stock
  `sound-aoc` has cheetah's 53 DAI links with the same ids and formats, so it
  is cheetah's overlay without the TDM 0 codecs and amplifier clocks (R4).
- `tools/aoc-stage --watchdog core` (Trusty, gsa, `gs201_aoc_sysmmu`,
  `mailbox_wc`, `aoc_core`, `aoc_channel_dev`, `aoc_alsa_dev`, `aoc_char_dev`,
  then `aoc.bin` through aoc_core): `Services : 69`, 37 `/dev/acd-*`, card 0
  `aoc-snd-card` with PCMs 0-32 (EP1 capture = PCM 8). The speaker limits
  are logged (digital 817/657, analog 10). One PCM open failed while the
  PCMs were probed: `fail to alloc service for audio_hotword_tap`.
- Microphones: raven's stock `mixer_paths.xml` (`handset-mic`) uses built-in
  mics **0, 1, 2** (cheetah 0, 3, 2), DC blocker 1, soft gain 22 dB, then
  `EP1 TX Mixer INTERNAL_MIC_TX` 1. `arecord -D hw:0,8 -f S16_LE -r 48000 -c 2
  -d 3`: 240000 samples, RMS 123 (-48.5 dBFS), peak 959: a quiet room, not
  silence.
- Next for R3's packaging: a raven `omamobile-aoc-start` (node `175d0000.aoc`,
  no rails step) and a raven UCM profile with mics 0,1,2.

## R2 preparation (offline, 2026-10-15)

- **Rails:** stock raven names the AoC's sensor supplies in the AoC node
  (`sensor_1v8` = S2MPG11 LDO7S, `sensor_3v3` = LDO6S, `sensor_power_list`),
  and Google's `aoc.c` power-cycles and enables them at probe
  (`reset_sensor_power`). Mainline already has those regulators, so raven
  needs no rails driver: `omamobile-gs101-aoc` `70c6dbe56` adds the supplies
  and stock's board id `0x20202` / rev `0x10000` to `gs101-raven.dts` (node
  still disabled). The microphones' LDO20M is always on in mainline.
  `aoc-stage` refuses its gs201-only `c3` and `rails` stages on raven.
- **Firmware:** `extract-vendor-firmware -d raven` now stages `aoc.bin` and
  the CS35L41 protection firmware; a private copy is staged in
  `~/android/vendor-firmware-raven` (`aoc-stage`'s raven default for `c4a`).
- **Overlay:** `device/raven/overlays/aoc-boot-test.dtso` enables the AoC
  System MMU, mailbox and AoC node; applies cleanly to the
  `omamobile-gs101-merge-test` DTB. Not in `DTB_OVERLAYS` until R2.
- The SysMMU, mailbox, AoC boot and core modules are already blacklisted
  (R1 setup), so enabling their nodes autoloads nothing.

## R2 runbook (the AoC through Trusty)

Only after R1 passes. Needs a push: a kernel with `70c6dbe56`
(`omamobile-gs101-merge-test` `8a47ed1b7` or later) and
`DTB_OVERLAYS="aoc-boot-test"`. A human stays at the phone throughout.

| Step | Command | Expect / Pass | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| R2.0 | build `out-raven-split` from merge-test, `DTB_OVERLAYS="aoc-boot-test"`, `bin/omamobile images`, then **push (human's go)** | boots, slot B marked good, nothing from the AoC stack in `lsmod` | no boot | fastboot: old `out-raven` images to slot B | medium: new kernel |
| R2.1 | `tools/aoc-stage --watchdog trusty` then `tools/aoc-stage --watchdog --trusty c2` | modules-ok; `info` shows GSA AoC state via hwmgr; carve-out not System RAM | carve-out overlaps RAM, hang | watchdog; reboot | low: no AoC register |
| R2.2 | `tools/aoc-stage mbox` | AP-side mailbox registers read | hang | watchdog | read-only |
| R2.3 | `tools/aoc-stage --watchdog c4a` | GSA state "loaded" | load error | reboot (never `rmmod`) | medium |
| R2.4 | `tools/aoc-stage --watchdog c4b` | control block present, services listed, no `blocked` | hang, no control block | `tools/aoc-stage stop`; reboot | medium |
| R2.5 | `tools/aoc-stage diag`; AoC log from `/dev/acd-logging` | firmware runs, sensors listed | AoC watchdog IRQ | `stop` | read-only |

If c4b leaves GSA state 4 without a control block, see cheetah's
AOC-PLAN.md C4b-2 (`release`) before trying anything new.

**R2 results (2026-10-15):**
- R2.0: the split kernel (`omamobile-gs101-merge-test`) with
  `aoc-boot-test` boots (`g8a47ed1b70ae`); the GPU probes with the renamed
  supplies; slot B marked good. **Bluetooth did not come up:** BCM baudrate
  write and reset timed out (-110); a driver rebind reached the chip (BCM4389C1)
  but the patch download timed out (`fc4e`, -110). Driver and DT are the same
  as the old stack's, so this is open (it was already shaky: before R1
  `bluetoothctl` showed no power state).
- R2.1 first try: `gs201-aoc-boot` failed with -EBUSY on the chipid block:
  gs101's `efuse@10000000` (Exynos chipid) owns it. Fixed by mapping it
  unrequested in the boot helper and aoc_core (`e7b81df33`).
- R2.1 on `ge74933a670e4`: Trusty ok; gsa, the AoC System MMU and the boot
  helper probe; `aoc_req 0x1 ack 0x1 (BLK_AOC on)`, GSA AoC state 0,
  `chip product 0x9845000 type 0x1 revision 0x1`, board id `0x20202` rev
  `0x10000`, carve-out not System RAM. Then **`cat blk` took a synchronous
  external abort** (`96000010`) on its first read, the AoC S2MPU's CTRL0
  at `0x1a0b0000`; only `cat` died, the kernel is tainted [M]. Cheetah reads
  the same address fine. **Stop:** c4a writes that register, so the load
  would abort too. `aoc-stage` now skips `blk` on raven.
- R2.1b (`g20e96c427598`): `cycle` powered BLK_AOC down and up through
  `aoc_req` (ack 0, then 1) with the AoC inactive; the single-register
  `s2mpu` read still took the same abort. So an ACPM power-up alone does
  not open it.
- Lead: Google's gs101 `aoc.c` touches the AoC S2MPU only once "AOC_TZPC has
  been restored", and stock's gs101 DT has `pd_aoc` (disabled) with
  `need_smc = <0x1a010204>`: D_TZPC_AOC at `0x1a010000`. Google's
  `exynos-pd_el3.c` restores a domain's DTZPC with SMC `0x82000410`
  (`EXYNOS_WAKEUP_PD_DOWN` 1, the `need_smc` address, `RUNTIME_PM_TZPC_GROUP`
  2), and saves it with mode 0 before a power-down. Next test: that restore
  SMC after `cycle`, then `s2mpu`.
- R2.1c (`gdc5db1a82fe4`, `google,tzpc-smc = <0x1a010204>`): after `cycle`,
  the restore SMC (`0x82000410`, mode 1, `0x1a010204`, group 2) **hung the
  SoC**: the last line on the laptop is the stage's marker; the watchdog
  reset the phone; pstore empty. Stock's PD driver always saves (mode 0)
  before a power-down, so EL3 may have restored from a slot never filled.
  Next: save, `cycle`, restore, `s2mpu`; if the save alone hangs, drop the
  SMC path.
- R2.1d: the **save** SMC (mode 0, BLK_AOC on, before any cycle) hung the
  SoC too (watchdog reset, pstore empty). The SMC path is dropped. Since
  EL3 itself hangs on D_TZPC_AOC, this is not a security denial: BLK_AOC's
  AP-side registers (`0x1a0x0000`: CMU_AOC, D_TZPC_AOC, the S2MPU) look
  unclocked or isolated despite the `aoc_req` acknowledge.
- Stock (`aoc.c`, raviole android14) reads the S2MPU's CTRL0 at probe with no
  ACPM call or `aoc_req` before it, so on stock those registers are
  reachable at hand-off. Clocks are not the kernel's doing here
  (`clk_ignore_unused` is set); at hand-off `gout_apm_mailbox_ap_aoc_pclk`
  is off, which the AP-AoC mailbox node will need (`cmu_apm`).
- Open: what makes BLK_AOC's SFRs unreachable on our boot. Candidates: CMU_AOC
  (no mainline driver; `cmu_id 0x1a000000` in stock's pd_aoc) gated by the
  bootloader; something between hand-off and the module load (ACPM DVFS,
  `sec_acpm`, Trusty's connect); or the AoC's PMU state (stock reads PMU
  `0x3ac0`/`0x3ac4`, AoC custom out/in, through the kernel's PMU regmap).
  Next: read those two PMU words through the kernel regmap (never from
  userspace), and read CTRL0 as early in boot as the helper can probe.
- R2.1e (`g4d822b603b76`): the AoC's PMU words through the kernel regmap
  read `custom_out 0x68 custom_in 0xc00`, the same before and after an
  `aoc_req` 0/1 cycle (whose acknowledge did go 0 and back to 1). So the
  cycle may never really power BLK_AOC down, and the acknowledge says less
  than it seemed. Next: decode those words (Google's gs101 flexpmu/CAL) and
  find CMU_AOC's gate state, offline, before touching BLK_AOC again.
- **R2.1f, the cause (`gf1f0538251ea`):** the PMU shows BLK_AOC **off** at
  hand-off: `AOC_CONFIGURATION` (`0x1880`) 0, `AOC_STATUS` (`0x1884`) 0, while
  `aoc_req` reads acknowledged. BUS0 is on (`0x1a04` = 1) and CMU_BUS0's
  `LHS_AXI_P_AOC` Q-channel matches the GSA's working port (`QCH_CON`
  0x3f0002, `DBG_NFO` 0x4). So every BLK_AOC access (S2MPU, D_TZPC_AOC from
  EL3) hit a powered-off block. Source: Google's
  `cal-if/gs101/flexpmu_cal_local_gs101.h` (`blkpwr_aoc`: `aoc_on` sets
  `AOC_CONFIGURATION` bit 0 and waits for `AOC_STATUS` bit 0).
- **R2.1g (`g92926291d434`): passed.** The boot helper's `pd` file runs
  `aoc_on` through the kernel's PMU regmap: `blkpwr_aoc on: status 0x1`,
  `configuration 0x1 status 0x1`, custom in 0xc00 to 0xc08. Then the
  single-register read: **`aoc s2mpu CTRL0 0x5`** (as cheetah's C2), no
  abort, taint 0. No DTZPC SMC needed. The R2.1c/d SMC hangs were most
  likely EL3 touching the powered-off block.
- `blk` with the domain on: AoC System MMU v8.1, ctrl 0x24, capa0
  0x41085800, capa1 0xe051 (8 VIDs), every VID off: as cheetah's C2.
- **R2.3 `c4a`: passed.** System MMU windows as on cheetah (carve-out 48 MiB,
  0x97000000 4 MiB, 0x17600000, 0x17c00000, 0x11100000, 0x40000000), VID 0
  translating; GSA wakelock (cmd 150), `loading AoC image: header
  0xb0000000 body 0x94000000`, cmd 90 err 0, wakelock released; parameters
  board 0x20202/0x10000 chip 0x9845000 type 1 rev 1; **GSA AoC state 1
  (loaded)**. Raven has no GSA S2MPU to open (stock's gs101 DT lists none).
- **R2.4 `c4b`: passed.** Start through Trusty's hwmgr.aoc (AoC command 1),
  GSA state 2 (running), AoC S2MPU CTRL0 0 after; **`firmware up: 69
  services`** within 0.2 s, among them `audio_output_control`,
  `audio_input_control`, `audio_playback0`-`6`, `com.google.usf`,
  `usb_control`, `logging`. Taint 0.
- **Runbook change for raven:** after c2, run `PD=1 tools/aoc-stage pd`
  (BLK_AOC's power domain) before anything touches BLK_AOC; then c4a, c4b.
  aoc_core will need the same `aoc_on` step on gs101 before it maps the
  S2MPU (R3).
- Also needed later: `gout_apm_mailbox_ap_aoc_pclk` is off at hand-off (the
  AP-AoC mailbox at `0x176a0000` is in APM), so don't read the mailbox
  before its clock is on.
- Seen on the same kernel: the AoC boot helper's probe deferred until about
  31 s of uptime (Trusty/GSA), so c2 run right after boot finds no debugfs;
  and Bluetooth came up on one boot (`hci0` read codec capabilities) and not
  on another: flaky, not gone.
- Earlier note, next (offline): why the AoC S2MPU aborts on gs101 with BLK_AOC
  acknowledged: a CMU_AOC gate (no gs101 CMU_AOC driver upstream), access
  control left by raven's bootloader, or a different S2MPU instance. Stock's
  gs101 DT names it `aoc_s2mpu` in the AoC node only (no `google,s2mpu`
  node for it, unlike the other blocks). Then one read-only register per
  run, as AGENTS.md says.

## 1. Facts

From Google's raviole DT and GPL sources.

| Item | raven (gs101) | cheetah (gs201) | Source |
| --- | --- | --- | --- |
| AoC | `0x19000000` (16 MiB), `aoc-board-cfg "r4"`, board id `0x20202`, rev `0x10000` | the same base | `gs101-aoc.dtsi:28`, `gs101-raven-audio.dtsi` |
| AoC interface | `aoc-interface-gs101.h` (2799 lines, google-modules/aoc raviole android14) | `aoc-interface-gs201.h` | fetched to scratch |
| Speaker amplifiers | 2x CS35L41 on **SPI 13** (`cs35l41@0`, `@1`, 25 MHz) | 2x CS35L41 on I2C | `gs101-raviole-audio.dtsi:223-280` |
| Haptics | **CS40L25A** on I2C 8 at `0x43` | CS40L26 | `gs101-raviole-audio.dtsi:162-211` |
| Start | through Trusty (GSA hwmgr), as on cheetah | the same | AGENTS.md AoC gotchas |

**AoC node, gs101** (Google's `gs101-aoc.dtsi`):

| Item | Value |
| --- | --- |
| `blk_aoc` | `0x19000000` (16 MiB) |
| `aoc_req` | `0x175d0000` |
| `aoc_s2mpu` | `0x1a0b0000` |
| `ssmt_aoc` | `0x1a060000` |
| mailbox `aoc2ap` | `0x176a0000` (IRQ `MAILBOX_AOC2AP_ALIVE`), 16 channels, `wc-mbox-non-wake-channels` `0x7000` |
| IOMMU and memory | `sysmmu_asoc`, `aoc_reserve` |
| ACPM channel | 13 |
| PCU | `pcu-base` `0xb00000`, doorbells at `0xd004`/`0xd008` |
| GPIO base | `0xb70000` |
| AoC vsync pins | gpp3-1, gpp5-1, gpp7-1, gpp9-1 (function 2) |

**Speaker amplifiers, stock raven DVT overlay** (for R4; mainline gs101
already has `usi13` and `spi_13` at `0x10d60000`):

| Item | Left / top (`cs35l41@0`) | Right / bottom (`cs35l41@1`, prefix `R`) |
| --- | --- | --- |
| SPI 13 chip select | gpp25-3 (cs-gpios, active low) | gpp1-0 (cs-gpios, active low) |
| IRQ | gpa6-3, level, no pull | gpa9-6, level, no pull |
| Reset | gpp16-3, active high | gpp23-7, active high |
| VA / VP | S2MPG11 BUCKA / V_SYS | the same |
| Boost | 3500 mA peak, 1000 nH, 30 uF | the same, plus `cirrus,right-channel-amp` |
| Other | `asp-sdout-hiz 3`, `hw-noise-gate-select 0x3f`, GPIO2 source 5 (output), 25 MHz SPI | the same |

The SPI bus pins are gpp25-0/1/2 (function 2; MISO pulled down). The
CS35L41s join the AoC's TDM 0 back end (`dai_be_tdm0_rx/tx`), as on
cheetah. Haptics (CS40L25A on I2C 8 at 0x43) share that card's
`haptic_rx` back end.

## 2. Port

Reusable from cheetah's integration snapshot (`ebe48386d`), with DT data:
the AoC core, IPC, firmware loader, channel and char devices, the ALSA card
(`drivers/soc/google/aoc/`), `drivers/trusty/` and `gsa.c`.

To redo for gs101:
- `aoc-interface-gs201.h` becomes gs101's;
- `gs201-aoc-boot.c`: addresses and boot sequence;
- `gs201-aoc-rails.c`: raven's PMICs are the S2MPG10 and S2MPG11, not the
  S2MPG12 and S2MPG13;
- `gs201-aoc-sysmmu.c`: gs101's AoC SysMMU;
- the CS35L41 amplifiers over SPI 13, with gs101's USI and pinctrl.

Raven's AoC firmware and speaker tuning come from the owner's factory
image (`tools/extract-vendor-firmware -d raven` gets an AoC map). The
speaker calibration is never committed.

## 3. Stages (each gated, read-only first; AGENTS.md AoC gotchas apply)

1. **R0 (offline):** import the stack on a branch `omamobile-raven-aoc`;
   gs101 interface, boot, rails and sysmmu; DT nodes disabled; build.
2. **R1:** Trusty and GSA up on raven (read-only probes, no RPMB writes).
3. **R2:** the AoC started through Trusty, its firmware log readable.
4. **R3:** the AoC sound card and the microphones (capture).
5. **R4:** the speakers at cheetah's safe level (stage `media`), with
   speaker protection.
6. **R5:** sensors (auto-rotate) through the same AoC.

## Without the amplifiers (2026-10-27, `gb3d6253b0d61`, device-raven 0.1.23)

Derek asked on #41 whether the sound card, and so the microphones, still
comes up while `cs35l41` stays blacklisted. It doesn't. With speaker
protection disabled (as 0.1.23 intends) and the amplifier driver never
loaded, the AoC comes online and registers its ALSA services ("alsa-aoc
communication is ready"), but `sound-aoc` stays in deferred probe: its
DAI links name the two CS35L41s as codecs, so the card waits for them.
`/proc/asound/cards` is empty, the boot check fails `audio-card`, and
phone-smoke reports no sound card. So 0.1.23 leaves raven with no
speakers **and no microphones**; the matrix row must say so.

The earlier report from this boot set (speakers and microphones working)
came from the 10-17 root image's older local `omamobile-audio` 0.4.4,
whose service still started speaker protection on raven: the version
clash Derek pointed out. Ways forward, not decided: give the card a
speaker-less link set when the amplifiers are absent, or load the
amplifier driver muted with no protection firmware, so the card and the
microphones come up while the speakers stay off.
