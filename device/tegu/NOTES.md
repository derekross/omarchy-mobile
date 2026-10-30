<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a (tegu): first light

2026-10-22: verified on one retail Pixel 9a, Tensor G4 (`zumapro`).
This is an experimental integration, not a supported release or installer
qualification. Kernel, image-tool and package changes need separate PRs.
The descriptor here intentionally fails closed with current public tools.

Tested kernel: `7.3.0-rc6-omamobile-tegu-tn3-g1cb4bd36f3be-dirty`, private
branch `omamobile-tegu-touch-power`, worktree/output `wt-touch-power` /
`out-touch-power`. Diagnostic Images are additionally distinguished by
hash/build ID; this dirty release is not a published kernel package.
`[V]` marks verified observations; `[I]` marks an inference still to test.
Raw captures, recordings, backups and vendor files remain off repository.

## 2026-10-29: two resets at about 34 s, right after Bluetooth started

[V] During the night's GNSS G3 tries (kernel
`7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`, gn3 DTB), two
boots reset at about 34 s of uptime, right after Bluetooth started (01:41
and 03:03), before any GNSS step. The cause was not seen. Read again from
the journal on 10-29 afternoon (the 03:03 boot; the 01:41 one is out of the
journal and its console was rotated out): its last 34 s are the same
timeline, to the tenth of a second, as the two boots around it that
survived (the Bluetooth firmware at 27.9 and 31.4 s, MGMT at 33.0,
`tegu-curated-bluetooth-prepare` at 34.1, `bluetooth.service` at 34.2,
`systemd-hostnamed` at 34.4, then nothing), and it ends there. The curated
Bluetooth dead-man is armed for 120 s, so it was not that; the audio
bring-up script had not yet acted (its first action comes 5-7 s later in
the surviving boots); the only thing running in that window is bluetoothd
setting the adapter up over the UART. Without the console of the reset
there is nothing more to read. The night's other
resets came from the modem side (the CP link hang after Kepler's watchdog
resets) and are in [MODEM-PLAN](MODEM-PLAN.md) under "G3, twenty-fourth to
thirty-fourth tries" and "The CP link hang". Not a GNSS matter: if a boot
with nothing but Bluetooth starting resets again at that time, start here.

## 2026-10-28, evening: USB-C host mode through TCPM

Kernel `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty` (the
integration tree), DTB with the TCPC as a dual-role port.

- **USB-C host mode works end to end** [V]. TCPM runs the port as dual-role
  (try sink, source PDO 5 V 900 mA), with `vbus-supply` = the MAX77779
  charger's `chgin-otg` regulator (kernel #124) over the RT9470's OTG boost,
  and a graph to dwc3's role switch. A USB flash drive attaches as source
  (SRC_READY), VBUS holds at 5.2 V, the data role goes to host, and the
  drive enumerates at high speed (`sde: sde1 sde2`). With the drive out and
  the laptop back: sink, a PD contract, the gadget configured. Again after a
  fresh boot. Two parts of that setup aren't in a public tree yet: the DT
  fragment (the TCPC as dual-role with `vbus-supply`, the graph to dwc3) and
  the RT9470 bring-up module that writes OTG_EN, JEITA_EN and the watchdog
  bits. They are on the kernel bring-up branch
  derekross/linux-omarchy-mobile#127, with the plan and runbook in #136.
  This supersedes #100's "the eUSB2 repeater doesn't take the host role
  yet".
- **How the cable swaps were covered** [V]: attended, with W4HO at the
  palmtop for every swap. Taking the laptop out cuts the only link, so each
  sampling script carried its own dead-man: with no USB gadget configured 6
  to 8 minutes after the cable came out, it unloaded `tcpci_maxim` and set
  the role switch back to device, so the laptop would come back as a sink.
  It never fired, because the laptop came back every time. The DTB boot
  itself ran under a one-boot DTB dead-man. The next run uses a reboot
  timer armed before the unplug and stopped over a fresh login (#136's
  runbook). `tools/usbc-deadman` is written for the 7 Pro's MAX77759 and
  doesn't apply here.
- **Why VBUS collapsed at first** [V]: the RT9470's JEITA temperature
  control (0x0c bit 7) was on with STAT2 reading 0x80, and its I2C
  watchdog (0x01 bits 1:0) had expired (STAT3 0x20). That JEITA read "hot"
  is an inference [I]: the TS pin may have no thermistor on it, which
  hasn't been checked. With either set, the
  boost reported OTG (ICSTAT 0x0f) while VBUS fell from 5.2 V within ~60 ms,
  and TCPM retried every second. Google's `rt9471_charger` turns JEITA off
  on the 9a (`en-jeita` is unset in `zumapro-buck-charge-rt9471.dtsi`) and
  only runs the watchdog while it kicks it. With both off, VBUS holds under
  Rd and Rp, with and without AutoDischargeDisconnect. The boost's driver
  has to clear both.
- **What that leaves open** [I]: with the watchdog off, nothing turns the
  boost off after a crash. What a warm reboot with host mode on leaves
  behind (the RT9470's OTG bit and ICSTAT before any driver loads) hasn't
  been measured, so whether VBUS stays out across one is unknown. With
  JEITA off the RT9470 has no temperature cut-off of its own, which
  matters only if it charges. Its CE comes from the MAX77779's sGPIO 7,
  which hasn't been read. On the charger with the battery full, FUNCTION
  read 0x41 (`CHG_EN` set) and ICSTAT 0xf1 (VBUS ready, not charging), so
  whether it charges under our kernel isn't known yet.
- **The eUSB2 side** [V]: the PHY has to come out of reset with the device
  attached. A drive plugged into a port that's already host isn't seen
  (the TUSB2E11's attach-detect interrupt never latched). TCPM's flow
  (attach on CC, then the role switch, then `phy-snps-eusb2` resetting the
  PHY on the role change) does it in that order.
- **NFC after s2idle** [V]: the ST54L loses its NCI state across a
  suspend. The first command after resume gets no I2C ACK (`NFC: Error -6
  on I2C send`), and every NCI request times out after it. Powering the
  adapter off and on through neard (a fresh NCI init) brings it back, so
  the sleep hook has to power the adapter off before the sleep and on
  after it, not only stop polling (10-29: not needed with
  https://github.com/derekross/linux-omarchy-mobile/pull/131, and a
  power-off hook failed to wake once; see #137).
- **Fingerprint calibration** [V]: the HAL injects it itself
  (`injectMtCali`), reading a 112-byte header at offset 0 of
  `/dev/block/by-name/mfg_data`. The file `fastboot oem udfps get-cal-url`
  names has exactly that layout (magic `0xca11ca11`, version 1, and the
  payload length at 0x6c). Written into the chroot's private `mfg_data.img`
  copy (the partition itself untouched), it's accepted:
  `vendor.gf.cali.state = 1`, and the "No SA calibration present" line is
  gone. Later that evening enrollment completed, but matching doesn't work
  yet (#135; 10-29: it does now, see FINGERPRINT-PLAN F9/F10 in #138).
- **GNSS** [V]: telling the AoC the GNSS type (`gnss-type = <2>`, as
  Google's `zumapro-phone-ignss.dtsi`) doesn't change the fault. Kepler
  loads and goes OPERATIONAL, and the HAL starts a session, but every engine
  start still ends in "KEP M7 HARDFAULT ... LR,PC 600B5B39 0000062C"
  (20 in 4 minutes).

## 2026-10-26 and 2026-10-28: slot A fallbacks that cost userdata

Both times slot B was active but **not marked successful**, so each boot
used up one ABL retry. After `fastboot --set-active=b` the 9a's ABL gives
B **three** tries (10-28: retry 3 after the flash, 1 after two boots, from
the devinfo dumps below). A boot that never reaches the USB host is crashed
by the initramfs safety net about 65 s in, so a bad image uses up the tries
within minutes, and ABL then boots stock on slot A.

**2026-10-26.** The failing boot was a comparison run of Google's own
kernel (`6.1.134-android14-11-g2bae8aca899a-ab13800907`), written to slot B
by `omamobile flash` (so `--set-active=b`). It ran with a RAM-only
filesystem assembled from our initramfs files, with PID 1 replaced by a
static supervisor that opens no block device. Stock's own first stage didn't
run on slot B. It never brought up USB.
Fastboot (buttons) then showed A selected and B at retry 0. Stock's own
boot wasn't captured. Afterwards `userdata`'s ext4 and F2FS magics were
gone, with non-zero data in their place, `e2fsck -fn` failed, and `persist`
had changed. [I] Stock on slot A wrote over the start of `userdata`; nobody
saw its boot. At 16:35 MST the palmtop sat in stock recovery (USB 18d1:4ee7,
sideload-only adbd: every adb command answered `error: closed`). Nobody
chose anything in recovery. A fresh read-only backup of efs, efs_backup,
modem_userdata, persist, modem_a/b, devinfo and metadata was taken
(off-repo). Slot B came back by `omamobile flash` of the last good five
images (which set it active again). The root came back by streaming the
verified 10-25 recovery image over USB SSH into `userdata` from our
initramfs, with a readback hash and a read-only `e2fsck`. B was then on its
last try (byte 0x34 `00` in the "before" row below): one more unmarked
reboot would have fallen back again.

**2026-10-28.** Kernel `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`
(the release the day's run kit records; the string stays the same across
that tree's builds, so it names the tree, not one build) with our initramfs
(`bin/omamobile initramfs`, `initramfs/init`, packed by the kit), and a new
DTB (the TCPC as a dual-role port with a link to dwc3's role switch). In the morning, slot B was
written by `omamobile flash`, recovering from a test boot of kernel #55's
head that hung on the Google logo, and it was **not marked** afterwards.
Every `push` round after that ran unmarked, so the tries ran out on the
first round that failed. That's the situation the rule is there to prevent. The DTB round lost USB on its boot (`push`: "no SSH after
reboot"), and a few minutes later the palmtop was on stock. adb answered
`error: closed` again, the same sideload-only adbd as 10-26. The owner
doesn't remember what the screen showed, and nobody tapped anything.
Afterwards `userdata` read as non-zero data with no filesystem magic (the
first 64 KiB looks random), and the root wouldn't mount. Fastboot by the
buttons, `omamobile flash` of the last good images, the 10-25 recovery
image streamed to `userdata` and read back against its sha256, then a boot.
Fresh read-only backup of the same eight partitions, taken before the boot:
efs, efs_backup, modem_userdata, persist, devinfo and metadata differed
from the 10-26 backup, modem_a/b didn't. `fastboot getvar slot-*` wasn't
captured either day, apart from `current-slot: a` on 10-28.

So stock doesn't just stop at a recovery prompt: on both days `userdata`
was overwritten before anyone could choose anything. Treat a fallback to
slot A as losing the Linux root.

**Marking B both days** was the approved operation below, `omamobile-bootctl
mark-successful` for B. The binary was built statically from
`packages/omamobile-device-cheetah/src/omamobile-bootctl.c` (source sha256
`89d03460…`, binary `f44936d5…`), driven by a laptop script that:

1. reads a fresh full `devinfo` snapshot and checks its sha256 against live
   storage right before the write;
2. runs the tool's dry run, which must plan exactly one byte;
3. arms a 30 s timed read-only restore, writes, reads back all 8192 bytes
   against the predicted image, and checks the read-only flags over a fresh
   SSH login.

systemd's 10 s runtime watchdog was running throughout (the bring-up checks
for it). The script didn't arm anything beyond that.

The laptop keeps the command log. The 10-28 harness copy differed from the
10-26 one only in its baseline paths (slot A's bytes are read live).

| Moment | Bytes 0x30–0x37 |
| --- | --- |
| 10-26, before | `02 1a 00 00 00 14 00 00` |
| 10-26, after | `02 1a 00 00 00 16 00 00` |
| 10-28, before | `02 1a 00 00 01 14 00 00` |
| 10-28, after | `02 1a 00 00 01 16 00 00` |

Only byte 0x35 changed (bit 0x02), and slot A was untouched.

## 2026-10-28: what the device table's claims rest on

Each line is a run on this 9a, on `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`
unless it says otherwise; the kernel pull request has the details.

- **Display:** the published kernel drives the panel at 60 Hz. 120 Hz runs
  on the palmtop with kernel #88's two files (DECON timers per panel), in
  review.
- **Touch, sleep fix (kernel #82):** 20 s2idle cycles with RTC wakes in a
  row, no `bad message header`, touch working after each; without it touch
  broke at the 13th.
- **Buttons, Power wakes s2idle:** checked by hand on 2026-10-27, Power from
  a freeze back to the desktop.
- **Bluetooth, BCM4383 (kernel #94, merged):** `hci_uart` reloaded with that
  exact `hci_bcm.c`: the controller came up as `hci0` on its REG_ON latch.
  Pairing (A2DP) ran with the older form of the code.
- **Charging, status and inhibit (kernel #92):** the driver bound at 0x69;
  status, and inhibit through `charge_behaviour`, read and set on the
  palmtop.
- **Haptics, CS40L26 with VPBR (kernel #95, merged):** binds, loads its
  firmware with brownout prevention at 3.008 V, plays effects.
- **Torch, LM3644 (DT in kernel #96):** 25 brightness steps up to 75 mA on
  the torch LED.
- **Suspend, Power and RTC wakes:** Power by hand as above; RTC wakes in the
  #82 run and in the 2026-10-28 sleep tests, where one of four never woke
  (recorded in the camera switching entry below).

## 2026-10-28: camera switching, pstore, idle hints, sleep memory rate

Kernel `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`.

- **Camera switching works** (kernel #103). The first capture after a
  switch away from the ultrawide or front camera came back empty about
  half the time. The LoCH's EN_STATUS (0x0a8) stays active with the old
  link in its low bits after a stream that stopped cleanly, and a disabled
  LoCH ignores the abort, so the next stream on another link got no
  interrupts. Enabling it for the abort fixes it: nine captures, every
  switch order, all write frames.
- **pstore** (kernel #106): ramoops on stock's region survives a watchdog
  reset on zumapro (the bootloader writes its own log at the start of the
  console zone).
- **Core and cluster power-down hints** (the CPU_INFORM register Google's
  driver writes at every idle entry): powering down cluster 0 stops ACPM
  answering its DVFS channel, and the palmtop resets (pstore shows it);
  Google never powers down cluster 0. Clusters 1 and 2 are stable, but
  neither hint saves anything measurable, screen on or off. Dropped.
- **Memory rate in s2idle:** with the cable in and charging paused,
  10-minute RTC-woken freezes drew 371 and 373 mA at MIF 2028 MHz and
  314 mA at 421 MHz. One later freeze never woke (in s2idle the watchdog
  is stopped); a hand restart brings it back.
- **Link errors** on every camera are ERR_WRONG_CONFIG: packets on VC 0
  with a data type no channel takes (an embedded-data line a frame on the
  front and ultrawide, about 527 PDAF packets a frame on the main camera).
- **Fingerprint:** the trusted app's secure storage is up, with Trusty's
  stores at the paths stock uses (`0`, `persist/0`) but on loop devices of
  Linux-owned images under `/var/lib/omamobile-fp`, not on stock's
  `trusty_userdata` and `trusty_persist` (omarchy-mobile #101;
  FINGERPRINT-PLAN D1 and F4b). The factory
  calibration lives with Google: the bootloader names the file (its
  `get-cal-url` answer) and it comes from a manufacturing bucket. The panel's
  id isn't the key (omarchy-mobile #101).
- **GNSS:** the S2MPG15's three GNSS rails are off at hand-off and stock
  turns them on; they're now described (kernel #101) and on.

### Reserved memory beyond Google's map (kernel #80)

`zumapro-reserved-memory.dtsi` in #80 carries Google's fixed regions from
`zumapro-rmem.dtsi`, zuma's xhci pools, and three more:

- `abl@f8800000`: predeclared in stock's own factory base DTB as 32 MiB,
  which ABL shrinks to 16 MiB at hand-off.
- `0x913a0000` (+0x60000) and `0xfd7ff000` (+0x1000): two ranges the early
  bring-up kept reserved, next to GXP and the debug tail. They come from the
  private DRAM map the first boots were built from, not from a public
  source.

Keeping them reserved is the safe direction. What would free the two gaps
is stock's live `/proc/iomem` and reserved-memory nodes compared with ours;
this palmtop can't produce that (stock on slot A overwrites `userdata`
before it reaches recovery: [2026-10-26 and 2026-10-28](#2026-10-26-and-2026-10-28-slot-a-fallbacks-that-cost-userdata)),
so it needs a second 9a or a reinstall of stock.

## 2026-10-27: cameras, NFC, USB-C, storage power, fingerprint, drain

Kernel `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty` (the
integration tree; the pieces are kernel PRs, linked below) for everything
here. The 35 s2idle cycles in AGENTS.md's NFC entry ran on this release too.

**Cameras (kernel #63, #103).** `cam -l`:

    1: Internal back camera (/base/soc/usi@108c00c0/i2c@108c0000/camera@56)
    2: Internal back camera (/base/soc/usi@108900c0/i2c@10890000/camera@1a)
    3: Internal front camera (/base/soc/usi@108a00c0/i2c@108a0000/camera@1a)

`tools/phone-smoke`: `| cameras | ok | 3 listed by libcamera |`. With the
ultrawide's test pattern on, LoCH 0 on link 1 (CTL 0x01000200, RESOL
0x0c001070, 5312 bytes a line, format 4) wrote three 4208x3072 frames
(48955392 bytes) showing the sensor's eight colour bars, full width and
height; the solid-colour pattern (R 1023, Gr 0, B 341, Gb 682) reads back as
BGGR. The main camera (S5KGN8, C-PHY) delivers whole 4000x3000 frames once
gs201-csis raises the INT domain and the ISP front end's NOC clock while it
streams. The ultrawide and the front stream at about 29 fps through the
software ISP. The tested `phy-gs201-mipi-dcphy-rx.c` is #63's (ed3dacc7f958);
the tested `gs201-csis.c` (acd8d7d0987a) differs from #63's in one comment.
Open: the first capture after a camera switch is often empty.

**NFC (kernel #100).** The ST54L reads a contactless card through the
kernel and neard once nxp-nci sends ST's CORE_SET_CONFIG after init: an
ISO-DEP target on NFC-A, 15 activations in 45 s with the card held, neard
lists a tag, with no periodic discovery restart. NFC polling costs about
60 mA, so omamobile-shell 0.2.33 (PR #99 here) stops it with the screen off.

**USB-C.** tcpci_maxim (merged, kernel #97) loads at boot: a PD contract at
5 V 3 A, replug back within 1 s. Host mode: VBUS comes from the RT9470 on
USI10 (Google's ext-otg-only use case; USI10 clocks in kernel #102), the
TCPC sees VBUS, dwc3 goes host, but a flash drive never connects: the
eUSB2 repeater (hsi2c9 0x3e) doesn't take the host role yet. Plug-in wakes
s2idle once the TCPC's interrupt is armed.

**Storage power (kernel #99).** UFS idle clock gating: the cores spend
60-68 % of an idle minute in C2 with the core's latency request left on
(0 % with the clocks held on), no UFS errors under load.

**Fingerprint.** The sensor's 3.3 V is S2MPG15 LDO15S, off at hand-off
(kernel #101); with it on the trusted app finds the sensor and the HAL
reports it at (540, 1769), radius 113. Init still ends without factory
calibration: `mfg_data` is all zeros on this palmtop and the TA's
calibration objects don't open (FINGERPRINT-PLAN.md).

**Drain, cable out.** Awake with the screen off: 556 mA before UFS gating,
409 mA after it at MIF 2028 MHz and 366 mA at 421 MHz (ACPM lowers MIF on
request); NFC polling about 60 mA of that; Wi-Fi off and the CPUs at their
lowest changed little. s2idle: about 140 mA over 59 min. MIF stays at the
bootloader's 2028 MHz until something asks for less.

**Recovery.** A reboot stuck in `device_shutdown` needs Power held about
30 s, then Power; with a task stuck in D, reboot with `echo b >
/proc/sysrq-trigger` instead of `systemctl reboot`.

## 2026-10-26: audio (speakers, microphones, A2DP) with omamobile-audio 0.5.0

Kernel `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`: the private
integration tree for now (the pieces go to linux-omarchy-mobile one by one;
the S2MPG14 RTC is #54), with the AoC started by a staged script. The card
is `google,tegu-aoc-snd-card`; the TAS2572 amplifiers (I2C 19, top 0x48 and
bottom 0x49) take their gains from `tas2572RCA1.bin` at every playback
start (corrected 10-29: that file is linux-firmware's
`ti/audio/tas257x/tas2572-1-1amp-reg.bin`, byte for byte; stock's factory
image carries no RCA-format profile, only its own `ti_sp_tuning.bin`), and the codec exposes only `Top/Bottom Speaker Digital Volume` = 220
(0 dB; 232 is +6 dB), unchanged during a 1 kHz tone at 100 % PipeWire volume.
Without stock's speaker processing or protection in the path, PipeWire's
100 % is full scale into stock's amplifier gains, so the WirePlumber rule caps
the 9a's speaker sink at `channelmix.max-volume = 0.562` (a -10 dB ceiling, a
cautious number, not a measured one) until the speakers' limits are measured
or a protection path exists. PipeWire applies the clamp twice, to the master
volume and to each channel volume, and the channel mixer multiplies the two,
so the ceiling is the square of the value: the first cut of this rule used
0.316 and measured about 20 dB down, not 10. Checked on the phone: with the
sink at 100 % (`wpctl set-volume @DEFAULT_AUDIO_SINK@ 100%`) `pw-dump` still
reports `channelVolumes [1.0, 1.0]` (the cap is applied inside the channel
mixer, not to the reported volume), and a 440 Hz tone at -20 dBFS played at
100 % and recorded through the 9a's own microphone measured -43.6 dBFS RMS
at 0.316 and -24.0 dBFS with the line removed and WirePlumber restarted
(19.6 dB apart through an uncalibrated microphone path); at 0.562 it measures
-33.3 dBFS RMS, 9.7 dB below uncapped. The Pixel 7 Pro's speaker loudness filter is active
on the 9a too (`effect_input.omamobile_speaker_loudness` in front of
`alsa_output.platform-sound-aoc.HiFi__Speaker__sink`); it adds a bass boost
tuned for amplifiers with protection behind them, so it should be limited to
the Pixel 7 Pro's card.

Tested on the phone: speakers through PipeWire (a 2 s 440 Hz sine at -20 dBFS
played with `pw-play --volume 0.2`, then a 1 kHz tone at 100 % for the
amplifier readback, then system sounds; the owner heard them), both
microphones recording (EP1, `0,1,-1,-1`), Bluetooth A2DP endpoints registered.
The tested package was omamobile-audio 0.4.1 with this branch's four files
copied in by hand (remove them before installing 0.5.0, since pacman does not
overwrite files it does not own): `/usr/share/alsa/ucm2/conf.d/aoc-snd-card/`
`aoc-snd-card.conf` (b7bf918a…) and `google,tegu-aoc-snd-card.conf`
(b6033775…), `/usr/share/alsa/ucm2/Google/tegu/HiFi.conf` (a6d460f3…) and
`/usr/share/wireplumber/wireplumber.conf.d/52-omamobile-tegu-aoc.conf`
(a8b4e025…, sha256 prefixes of the committed files; the speaker and microphone
tests above ran before the cap existed, and the cap's own measurement came after). The AoC's own log for the third
microphone: `Could not enable power for PDM 2`, no fault. Cheetah's list
`0,3,2` kills the DSP: `FF1 (task=AUD_CAP_PDM): Assertion failed: asp_status
== ASP_SUCCESS, mic_compensation.cc, 99 [SetPdmMask]`, after which the AoC
needs a reboot (restarting the proxy does not help).

`tools/phone-smoke`, 2026-10-26T16:42Z:

### phone-smoke: tegu

Kernel `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`, tools at `7310611`, 2026-10-26T16:43Z.

| Check | Result | Detail |
| --- | --- | --- |
| boot (required) | skip | kernel 7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty, no slot on the command line |
| storage guard (required) | ok | 62 partitions; only userdata and slot B's boot images writable |
| root (required) | ok | ext4 on userdata, 22G free |
| kernel health (required) | ok | no oops or BUG; 0 WARN, 307 error lines in dmesg |
| systemd units | ok | none failed |
| USB gadget (required) | ok | bound to 11210000.usb |
| display | ok | card1-DSI-1 connected, 1080x2424 |
| GPU | ok | render node on panthor |
| session (required) | ok | Hyprland and the Omarchy shell running |
| touch | ok | Synaptics TouchComm Touchscreen |
| buttons | ok | gpio-keys |
| Wi-Fi | ok | wlan0 on brcmfmac, link up |
| Bluetooth | ok | hci0, powered true |
| battery | ok | 92% Unknown |
| sound cards | ok | googleteguaocsn |
| sensors | ok | Accelerometer AmbientLight Proximity |
| cameras | skip | no libcamera tools |
| thermal | ok | hottest zone 46 °C |

Packages: hyprland 0.56.2-5.1, libcamera 0.7.2-4.16, mesa 1:26.2.4-1.4, omacam 0.1.9-1, omamobile-apps 0.2.0-1, omamobile-audio 0.4.1-1, omamobile-device-tegu 0.1.0-1, omamobile-fingerprint 0.1.8-1, omamobile-firstboot 0.1.0-1, omamobile-gnss 0.2.1-1, omamobile-keyring 20261013-1, omamobile-mirror 0.1.1-1, omamobile-modem 0.1.4-1, omamobile-omarchy 0.1.4-1, omamobile-owl-widgets 0.1.1-1, omamobile-sensors 0.2.0-1, omamobile-shell 0.2.17-1, omarchy 4.0.6-1, quickshell 0.3.2.r7.g2b4501a-1

## 2026-10-24: local curated candidate

[V] A later candidate, `7.3.0-rc6-omamobile-tegu-g7e457a96fc45`, reaches
native Arch on internal userdata and starts Panthor, the G715 Omarchy
session and the read-only fuel gauge locally. The laptop sends nothing
during the boot (no go-ahead, no driver load, no confirmation): the palmtop
finishes the recorded startup on its own.
Matching modules, storage guard, watchdog and protected-partition/image
checks pass. Physical gestures and unplugged cold boot were not requalified
by this test. The staged startup policy remains; this is not an installable public
kernel or device-package release.

[V] The same Image with board source `79288b2a3574` also registers the
ALIVE GPIO provider and native gpio-keys while preserving inherited pulls.
Input keycodes, IRQ ownership and shell bindings pass metadata/state checks;
physical presses, display wake and suspend remain unqualified. A later
boot removes both temporary reboot helpers, the out-of-tree modules
`tegu-reboot-probe` (writes the bootloader reason at PMU 0x810 through the
kernel's SMC-backed PMU regmap) and `tegu-reboot-normal` (its normal-mode
counterpart, a reboot notifier only), both in `device/tegu/probes/`.
Ordinary `systemctl reboot` with no reason returns to the native desktop
automatically; an explicit bootloader reboot reaches Fastboot, and flashing
the same five slot B images back (`bin/omamobile flash`: `boot_b`,
`init_boot_b`, `vendor_boot_b`, `vendor_kernel_boot_b`, `dtbo_b`, each
hash-checked against the candidate set) returns to the same native profile.
Fresh root, protected-data and image checks pass after each. That kernel
(`7e457a96fc45`) predates kernel #45's merge, and I did not record whether
its reboot-mode code matches #45, so the plain `systemctl reboot` result is
not evidence for #45. Unplugged cold boot and production packaging remain
open; these results do not qualify those gates.

The selected subsystem source and disabled board resources are being
curated for separate kernel reviews in [tracking #28](https://github.com/derekross/omarchy-mobile/issues/28).
Public main still lacks the complete board integration and install recipe.
Do not enable the staged descriptor or infer Wi-Fi, charging/thermal,
Bluetooth, haptics, sensors, audio, cameras or fingerprint support from this
local desktop result. Earlier prototype observations below remain attributed
to their original diagnostic kernel.

## 2026-10-24: read-only gauge review, temperature deferred

[V] Kernel PR38 driver blob `1e113081a07f0fc629842b31e3fb86b4f7c4fcdf`
(`drivers/power/supply/max77779_battery.c`) excludes TEMP reporting.
Google's GPL driver substitutes 22 C for firmware revision 1 with
subrevision below 15; this gate does not establish the
retail gauge firmware revision or a stock-temperature comparison.

The exact signed C source is compiled as an ARM64 W=1 module against the
running curated `7.3.0-rc6-omamobile-tegu-g7e457a96fc45` kernel. It uses
that integration's qualified USI6/HSI2C6 bus, not an installable public
kernel. The unchanged board node is:

```dts
fuel-gauge@36 {
    compatible = "maxim,max77779-fg";
    reg = <0x36>;
    shunt-resistor-micro-ohms = <2000>;
    status = "okay";
};
```

[V] Load by hand, read twice 31.11 seconds apart, unload and restore the
installed module all pass on one boot. Both snapshots report present,
Li-ion, MAX77779, status Unknown, 93%, voltage/average 4.340390 V, charge
4720 mAh, full 5045 mAh and design 5120 mAh. TEMP is absent. Relevant
kernel lines, excluding the laptop log nonce:

```text
[  442.171460] max77779_battery: loading out-of-tree module taints kernel.
[  442.174098] max77779-battery 0-0036: Read-only fuel gauge; firmware model retained
[  473.361184] tegu-gauge-clean-review: two read-only snapshots complete; unloading test module
[  473.419985] max77779-battery 0-0036: Read-only fuel gauge; firmware model retained
[  473.432595] tegu-gauge-clean-review: installed gauge restored
```

[V] Laptop kmsg, PID1 hardware watchdog and independent recovery cover the
test. Fresh root/guard, six protected checksums and five B payloads pass;
both recovery timers are canceled and confirmed inactive on a fresh login.
An earlier attempt also read and restored the module, but host cleanup
failed on a collected timer, leaving the emergency reset armed. It fired
(the controller's 150 s reset timer; it came back on slot B, the only
slot with the native desktop, on the same five images);
the owner confirmed the recovered desktop and full checks passed before
this clean repeat. This was a test-controller failure, not a demonstrated
gauge fault. No model, NVM, charging, current-direction, rail or voltage
setting is written. The original driver remains installed; production
package migration, thermal control and suspend remain separate.

## Sources and firmware gate

- `R0/`: private retail capture `tegu-20261020-1349`, before unlocking:
  selected `getprop` fields and `fastboot-getvar-all.txt`, 2026-10-20.
- `R1/`: guarded native Linux partition enumeration and off-repository
  protected backups, `tegu-protected-20261021T021535Z`.
- `R2/`: 2026-10-22 guarded read-only AVB and slot-A image reads;
  `avbtool` signature checks and comparison with the verified official OTA.
- `F/`: the user's stock `tegu-bp3a.250905.014` factory boot images,
  including `dtbo.img`; facts below are offline parses, not installed-build
  attestations. The later bring-up bundle is a different artifact.
- `G/`: Google's GPL manifest branch
  [`android-gs-tegu-6.1-android16`](https://android.googlesource.com/kernel/manifest/+/refs/heads/android-gs-tegu-6.1-android16),
  manifest revision `893fbfd2192bc1c4a921f5daf23ea8543c09670d`.
- `P/`: the prototype's private kernel, guarded captures and per-gate
  results; the kernel release is above. No raw captures or binaries ship here.

### Slot history and official OTA maintenance

| Slot | Observed bootloader | Stock Android build evidence | Evidence |
| --- | --- | --- | --- |
| A | `tegu-16.3-13642544` | `BP3A.250905.014` (Android 16, patch 2025-09-05) | R0/getprop: `_a`, `ro.bootloader`, `ro.build.id` |
| B | `tegu-16.0-13541477` | `BP2A.250805.005`, patch 2025-08-05, in signed AVB metadata; no successful stock-B boot attestation | P/ resident-B fastboot controls; R2/vbmeta_b and vbmeta_system_b |

[V] The numeric loader build identifiers are 13642544 and 13541477.
A factory archive or the firmware suffix does not establish B's Android
build ID. R2 instead identifies it from valid signatures on vbmeta_b and
vbmeta_system_b, whose keys match the official stock images. This verifies
those metadata declarations, not our modified B boot images, dynamic
snapshot contents or a successful stock-B boot. The slot mismatch should have stopped bring-up under
CONTRIBUTING §3.1. The prototype result does not waive that rule or show
that a zumapro-specific HCRX workaround is needed.

[V] On 2026-10-22 the official full OTA for `BP3A.250905.014` was
sideloaded through stock recovery twice; both passes completed with status
0. After the first pass the resident B loader reported
`tegu-16.3-13642544`; after the second, resident A reported the same
version. Stock A then booted successfully. Ordinary authorised ADB
confirmed `_a`, `BP3A.250905.014`, Android 16, patch `2025-09-05`,
`tegu-16.3-13642544` and `dtbo_idx=9`. This is not a stock-B boot
attestation. Live DT selector reads were unavailable without rooting;
artifact-derived selectors remain distinct from observed silicon.

[V] Guarded post-OTA readback verifies valid top-level and system AVB
signatures on both slots, flags 0, and declared image prefixes exactly
matching the official BP3A images. Fresh protected backups were taken
before peripheral startup. The first ordinary installed-B control boot
reached internal Arch/systemd root with normal HCRX initialization, KVM
enabled and CPU0-7 online, without a laptop RAM boot. A bounded real ARM64
KVM guest executed and trapped the expected virtual MMIO write of 42;
no host-device passthrough was used. Native guard and watchdog checks
passed, with no runtime kernel fault detected. Control GNU build ID:
`bd787a42658c58ed023e7bb6c203d46844e294b9` (same diagnostic release string).

This control needs no HCRX workaround. The earlier failure is specific to
the mismatched-firmware prototype evidence; it does not justify a
zumapro-wide kernel workaround. Two normal control boots have passed;
cold starts and desktop/peripheral requalification remain separate gates.
[BRINGUP-M1](BRINGUP-M1.md) records those gates; the workaround is not
proposed for upstream.

### Sanitised stock facts

[V] R0/getvar: `product:tegu`, `hw-revision:MP1.0`,
`secure-boot:PRODUCTION`, `current-slot:a`,
`version-bootloader:tegu-16.3-13642544`. This was a **pre-unlock** snapshot:
`unlocked:no`; both slots reported successful with retry count 2, A
unbootable=no and B unbootable=yes. These are historical values, not the
prototype's current flags. A single resident-loader version is not proof
of equal firmware on both slots.

[V] Each slot has `boot`, `vendor_boot`, `vendor_kernel_boot` at 64 MiB,
`init_boot` at 8 MiB and `dtbo` at 16 MiB; `devinfo` is 8192 bytes
(R0/getvar). R1 enumerates 62 named partitions across four LUNs, sda–sdd:

- Five slotted boot images: `boot`, `init_boot`, `vendor_boot`,
  `vendor_kernel_boot`, `dtbo`.
- Other slotted names: `bl1`, `ldfw`, `dpm`, `gcf`, `pbl`, `bl2`,
  `dram_train`, `abl`, `bl31`, `tzsw`, `gsa`, `gsa_bl1`, `vbmeta`,
  `vbmeta_system`, `vbmeta_vendor`, `pvmfw`, `modem`.
- Unslotted: `persist`, `metadata`, `fips`, `ufs_internal`, `klog`,
  `misc`, `super`, `userdata`, `frp`, `efs`, `efs_backup`,
  `modem_userdata`, `trusty_persist`, `trusty_userdata`, `devinfo`,
  `pinfo`, `blenv`, `mfg_data`.

Only the five B boot images and userdata are writable under the guard;
listing a partition here grants no write permission.

[V] F/dtbo has **10 entries**. Retail Android reported `dtbo_idx=9`
(R0/getprop); entry 9 has board ID `0x60b06`, revision `0x10000`.
The stock vendor-kernel boot base-DTB candidates carry these
`/soc_compatible` tuples (product_id, major, minor, pkg_mode):

| Base DTB | Candidates |
| --- | --- |
| 0, A0 FOPLP | `(0x9875, 0, 0, 0)` |
| 1, A0 IPOP | `(0x9875, 0, 0, 1)` |
| 2, A0/A1 FOPLP | `(0x9875, 0, 0, 0)`, `(0x9875, 0, 1, 0)` |
| 3, A0/A1 IPOP | `(0x9875, 0, 0, 1)`, `(0x9875, 0, 1, 1)` |

The prototype's IPOP pair matches base 3. This does not distinguish this
unit's A0 versus A1 silicon, nor replace an equalised-stock live-DT capture.
The descriptor keeps that pair **commented out**, using #27's syntax:
`a0-ipop:0x9875:0:0:1 a1-ipop:0x9875:0:1:1`. This device PR supplies
selector data only. Shared SOC_COMPATIBLE tooling and its images-layout
tests remain in the separate tooling PR, alongside zuma's requirements.
Both SOC_IDS and SOC_COMPATIBLE stay unset, so this descriptor remains
refused even when #27 accepts either selector. Activation belongs with the
public DTB and required AVB footer values in a later PR.

**Header values verified:** the descriptor uses OS_VERSION=16.0.0 and
OS_PATCH_LEVEL=2025-09 from this stock build’s init_boot header.
The full OTA for BP3A.250905.014 (matching captured A) is downloaded and
matches Google's published SHA-256. All five F/ stock boot-image sizes and
digests match its payload manifest. AOSP unpack_bootimg parses that stock
init_boot as Android 16.0.0 / patch 2025-09. These are verified candidate
header values, now backed by both OTA completions, both-slot signed AVB
metadata for BP3A and the successful stock-A build-property check. A
stock-B Android boot is not claimed.

## Verified before firmware equalisation (old B, HCRX bypass, KVM off)

| Area | Observation [V] |
| --- | --- |
| Boot | Ordinary installed B boot and subsequent phone-initiated Linux-to-Linux reboot; no laptop kernel download, module load, storage-enable approval token (the bring-up script called it `GO`) or root confirmation. Tests kept USB connected. |
| Root and CPUs | Arch on internal ext4 userdata, systemd/SDDM/UWSM/logind, CPU0-7 online. KVM disabled. |
| Protection | Whole main-LUN node absent; only five B boot partitions and userdata writable; protected partitions read-only; per-boot guard and watchdog checks pass. |
| USB | NCM, ACM and root SSH over the connected cable. |
| Display | Bootloader framebuffer through simpledrm, 1080x2424, scale 2. Reported 60 Hz is not an independently measured panel rate. |
| Touch | Synaptics S3908 TouchComm v1: taps, long press, launcher, quick settings and all four swipe directions physically exercised by the owner. |
| GPU | Mali-G715 MC7: Panthor initialization, system Mesa GLES3.1 color readback, actual Hyprland/shell GPU rendering and automatic startup after local reboot. |

[V] Touch/GPU startup uses local prototype policy with matching pinned
modules, hang markers and timed recovery. No public tegu release package
provides it yet. The matrix remains **WIP** until the kernel and prerequisites are public.

[V] Horizontal swipes remain clunky and the clock card briefly shows a
jagged tail. Native display KMS, brightness, DPMS and GPU DVFS are not
qualified. Shader/top rates inherited from firmware are approximately
150/160 MHz, derived from qualified clock registers. A separate small
quick-settings first-frame flash was removed by selecting its screen
before showing the window, confirmed in recordings and physical swipes.

[V] Moving G4 UFS clock-stop register programming before host-clock disable
resolved a shutdown stall. The retained trace now completes both callbacks
and reaches `Restarting system`. An ordinary reboot without the extra
logging returns the native root/touch/GPU desktop: USB disconnects in
3.7 seconds and Linux USB returns in 28.9, versus 85/111 before the fix.
The prototype still has a 45-second storage qualification delay. Cold
power-on, unplug/replug, buttons, battery/charging/thermal policy, suspend
and the other phone peripherals are not qualified.

### Exact private restoration path

The post-OTA restore used a private checkout at
`/tmp/tegu-maintenance-tools`, based on this repository's main plus the
proposed #27 selector support and the previously qualified development
`flash` function. This was not the unchanged public `bin/omamobile`.
The command was `bin/omamobile flash --no-reboot --rootfs <verified-image>
--rootfs-sha256 <verified-sha256>`, with DEVICE=tegu and the pinned image
output selected. The regular ext4 image was 32 GiB, labelled
`omamobile-root`, reconstructed from the verified Linux file backup with
matching modules and checked ownership, ACLs, xattrs and special files.
It was flashed to shared `userdata`; no Android partition was mounted
read-write and no main-LUN device was recreated.

The retained flash log names exactly `boot_b`, `init_boot_b`,
`vendor_boot_b`, `vendor_kernel_boot_b`, `dtbo_b`, plus `userdata`.
The private flash function did **not** pass an explicit `-s <serial>`;
it relied on the connected-device/product check. I cannot confirm serial
binding for those historical writes. Future Fastboot operations will use
an explicit serial selection. No additional flash is needed to correct
this record. Slot selection and boot were separately performed by ABL's
Fastboot commands, not by a devinfo set-active write.

## Bring-up findings and descriptor facts

- [V] Initial malformed embedded AVB metadata failed before handoff.
  Stock-style child boot metadata passed an offline six-image load check;
  that repair alone did not resolve the older-firmware entry failure.
- [V] Entry recorders localized the older B firmware's failure to
  HCRX_EL2 access. Omitting that access permitted full Linux with all eight
  CPUs and KVM disabled. [I] Missing permission in the older firmware is
  the leading explanation; EL3's control register was not read. The
  completed equalised-firmware control passes normal HCRX and a real KVM
  guest, so the old bypass is not proposed for kernel review.
- [V] Both touch rails were off at handoff. The qualified ACPM/S2MPG14
  path, LDO4M/LDO25M and AVDD-before-VDD sequencing enabled v1 identification
  and the existing S3908 driver; this did not need a v2 protocol port.
- [V] G715 startup needed Google's GPL ASN/L2 hash values through Panthor's
  existing SoC-data mechanism (source below), plus the full upstream Mesa architecture 11
  backports. Tested system Mesa: `1:26.2.4-1.4`. No GPU protection-permission
  change was used.
- [V] Prototype container metadata: Android v4, five boot images,
  2048-byte vendor page size. Android 16 / 2025-09 are historical bring-up
  bundle header values only, not descriptor evidence. Retail
  MP1.0 board dtbo entry 9 selects ID `0x60b06`, revision `0x10000`.
  These are board values, not per-phone IDs.
- [V] Base-DTB selection uses soc_compatible, not the public packer's
  soc_id rewrite path. SOC_IDS is deliberately absent. The shared init is
  retained; no gs201 display probe or trigger write is requested.

The unit began with different slot firmware versions. Recorded prototype
image writes targeted B; no stock-firmware update or downgrade is recorded
in those tests. This does not establish that A was factory-identical.

[V] Before the OTA, R2 found A's vbmeta flags at 3, versus factory 0. In the declared
factory image prefix, only byte 123 differs. That captured header signature
did not verify as-is; resetting that byte in an **offline copy** exactly
matches the official factory image. No such change was written to the
phone during this audit; the history of the flag change is not established.
At that audit, all five actual A boot images separately matched the official BP3A OTA's
stock images. A's vbmeta_system signature was valid and its declared image
matched the official OTA. The two subsequent official OTA passes restored
flags 0 on both slots; the post-OTA signature/build checks are recorded
above. This does not imply the custom B images are verified by stock AVB.

An earlier private bring-up note from 2026-10-20 records that
`fastboot oem disable-verity` and `fastboot oem disable-verification`
returned OKAY after unlocking. This is a historical note, not a retained
before/after vbmeta comparison; it does not establish which command
changed A's header flags. It must not be omitted from the account of the
earlier verification changes. No such command is part of this maintenance.

This observation does not override CONTRIBUTING section 3.1: another
mismatched unit must stop for maintainer guidance before flashing.
Protected backups were kept off repository and checked against live
read-only partitions.

### devinfo write disclosure and stop

[V] `omamobile-bootctl` **wrote devinfo** to mark slot B successful.
Its `dump` reported layout version **3.15**. A fresh full 8192-byte backup
was checked before the write; host simulation and live readback verified
that byte `0x35` alone changed by setting B's successful bit (`OR 0x02`).
The full 8192-byte comparison verified slot A and every other byte unchanged;
devinfo was restored read-only and the storage guard checked over a fresh
SSH connection. The generic boot-success service remains masked.
After that earlier write, `fastboot getvar slot-successful:b` returned
`yes`: ABL read the same successful bit the marker had set. The retained
Fastboot captures confirm this independently of the Linux parser.
This was evidence of the bounded operation; further writes were held
while the maintainer reviewed the paired layout evidence below. On
2026-10-22 the maintainer agreed **mark-successful for B only**, after a
fresh backup and checksum immediately before the write. No set-active
or other devinfo write is agreed. Keep the generic service masked.

### Read-only layout evidence after official OTA maintenance

[V] Layout remains 3.15. Guarded Linux dumps followed by graceful returns
to Fastboot give these matching requested ABL observations, without an
intervening marking, slot selection or flash:

| Record | Bytes 0x30–0x37 | A successful / unbootable / retry | B successful / unbootable / retry |
| --- | --- | --- | --- |
| First normal B boot | `02 1a 00 00 02 14 00 00` | yes / no / 2 | no / no / 2 |
| One further normal B boot | `02 1a 00 00 01 1c 00 00` | yes / no / 2 | no / no / 1 |

The intervening boot used ordinary fastboot reboot, with no set-active or
retry refresh. Byte 0x34 decreased by one; successful/unbootable stayed
clear for B. This was not the only change: 0x35 XOR 0x08 matches the parser's
fastboot_ok field, and two opaque header offsets also changed. Their
values remain private and uninterpreted. No direct devinfo write was made.
The two pairs and these additional changes were posted to the maintainer
for layout agreement. The maintainer subsequently confirmed the retry
and fastboot_ok decoding and approved only B mark-successful, subject to
the fresh backup and before/after checks described above.

### Approved B-success operation after layout review, 2026-10-22

The maintainer approved only `omamobile-bootctl mark-successful` for B in
[review 5622088453](https://github.com/derekross/omarchy-mobile/pull/24#pullrequestreview-5622088453).
A further ordinary B boot used explicit Fastboot serial selection and no
slot reselection, flash or retry refresh. On the guarded native root, a
fresh full devinfo backup was saved privately and its checksum matched
live storage immediately before the write. The unchanged existing tool
performed the operation under a proven laptop log, watchdog and timed
read-only restoration.

| Moment | Layout | Bytes 0x30–0x37 |
| --- | --- | --- |
| Fresh backup immediately before mark-successful | 3.15 | `02 1a 00 00 00 1c 00 00` |
| Immediately after mark-successful | 3.15 | `02 1a 00 00 00 1e 00 00` |

All 8192 bytes were compared: only byte 0x35 changed, setting bit 0x02;
slot A and every other byte stayed unchanged. The devinfo partition and
its parent were temporarily writable for that tool operation, then
restored read-only; all original sibling read-only flags and the storage
guard passed a fresh SSH check. The generic boot-success service remains
masked. No set-active or other devinfo write was performed.

After graceful return to Fastboot, explicit serial-bound
`fastboot getvar slot-successful:b` returned **yes** and
`slot-unbootable:b` returned **no**. A remained successful and bootable.
This confirms ABL reads the same successful bit the marker writes.

### GPL source of the G715 cache-hash data

[V] G/ [`kernel/devices/google/zuma`, revision
`42395e8adcb880aa336f0da6bb2a19ed53929c40`, dts/zuma-gpu.dtsi](https://android.googlesource.com/kernel/devices/google/zuma/+/42395e8adcb880aa336f0da6bb2a19ed53929c40/dts/zuma-gpu.dtsi)
supplies `l2-hash-values = <0x0036db6d 0x005b6db6 0>`.
[`kernel/devices/google/zumapro`, revision
`8831630eee2ad095b85ed452944e6353940966a5`, dts/zumapro-gpu.dtsi](https://android.googlesource.com/kernel/devices/google/zumapro/+/8831630eee2ad095b85ed452944e6353940966a5/dts/zumapro-gpu.dtsi)
includes that zuma GPU description. Both are from branch
`android-gs-tegu-6.1-android16`. The same manifest's
[`kernel/google-modules/gpu`, revision
`696fc0246c17ba4270c11f88ab742ad4040938de`](https://android.googlesource.com/kernel/google-modules/gpu/+/696fc0246c17ba4270c11f88ab742ad4040938de/)
contains the GPL kbase property reader and L2 programming sequence.
The separate Panthor submission should cite these immutable sources;
no vendor binaries or GPU-permission changes belong in it.

## Meaning of the bring-up terms

**Qualified** means one named gate passed its stated checks on the tested
prototype/kernel; it does not mean release support, independent replication
or that unrelated peripherals work. **GO** was a temporary script's explicit
operator approval token before enabling storage; it is not required for
ordinary installed boot and is not a waiver of the safety model.

## Submission gates and follow-ups

[V] Offline: images/initramfs/flash/push each refuse the descriptor for
missing SOC_IDS before mocked hardware tools are called or images written.
The empty overlay passes strict checkpatch and dtc, its ID/revision read
back correctly, and applying it leaves a synthetic base unchanged.
These are low-risk checks with no phone rollback; stop if tooling proceeds.

Next: kernel drivers/bindings/DTS in linux-omarchy-mobile, one subsystem per
branch, with strict checkpatch, W=1 and binding/DT validation; generic DTB
selection/packing and a qualified device package here. Each hardware gate
needs protected backups, fresh logs, watchdog/dead-man recovery, a stop
condition and a known-good B rollback. Preserve stock A and the storage
guard. This entry is not an installation or diagnostic-flashing runbook.

The gated retest and required evidence are in [BRINGUP-M1](BRINGUP-M1.md).
