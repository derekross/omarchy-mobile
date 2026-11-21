<!-- SPDX-License-Identifier: MIT -->
# Microphone plan (hotdog / SM8150): the built-in microphones

**Status (2026-11-05): works. The voice and recording microphones record
through PipeWire from `boot_a` (M0-M8 in §7); AMIC1 and the kernel's
24-bit capture are open.** Kernel branch `omamobile-hotdog-mic` (worktree
`~/omamobile-kernel/wt-hotdog-mic`, output `~/omamobile-kernel/out-hotdog-mic`),
three commits on top of `omamobile-hotdog-fingerprint` @ `41a6c1235` (the
kernel the phone's `boot_a` came from). Overlay
[`overlays/mic.dtso`](overlays/mic.dtso). UCM in
`packages/omamobile-device-hotdog` 0.1.3.

**Goal.** The phone's built-in microphones record through PipeWire as two
sources, "Voice microphone" and "Recording microphone", next to the
speakers that already play. The path:

```
analog MEMS mic AMIC4 (voice) / AMIC3 (recording) / AMIC1 (third)
  biased by WCD9340 MICBIAS1 / MICBIAS4 (LDO input: PM8150L BoB)
  -> WCD9340 ADC4 / ADC3 / ADC1 -> AMIC MUX0 -> ADC MUX0 -> DEC0      wcd934x (mainline)
  -> CDC_IF TX0 -> SLIM TX0 -> AIF1_CAP                               MFD: wcd934x (+ micbias supply)
     | SLIMbus (LPASS NGD 1; the ADSP owns the bus, Linux asks over QMI)  slim-qcom-ngd-ctrl
  -> ADSP AFE SLIMBUS_0_TX -> ADM -> ASM MultiMedia2                  q6afe / q6adm / q6asm
  -> ALSA card "OnePlus 7T Pro", PCM 1 (MultiMedia2), 48 kHz          snd-soc-sm8150 (S16 on SLIMbus)
  -> UCM HiFi, devices Mic1 / Mic2 -> PipeWire / WirePlumber
```

---

## 0. Facts, from our own captures

All from the owner's OxygenOS 10.0.14 image (decrypted under
`~/android/reference/hotdog/ops/extract`, vendor in `vendor-fp/`), never
committed:

- **Codec.** `dtbo.img` entry 18 ("MTP 19801 MP 14 15", board-id <8 0>, the
  7T Pro) puts a WCD9340 (`qcom,tavil-slim-pgd`, elemental address
  `00 01 50 02 17 02`, interface device `00 00 50 02 17 02`) under
  `slim_aud` (`/soc/slim@171c0000`, NGD cell-index 1). The 7T Pro's card is
  `sm8150-tavil-snd-card`; the WCD9360 (pahu) card is disabled (fragment@90).
- **Codec wiring (fragment@71/72):** reset GPIO 143 (`cdc_reset_active`:
  drive 8, pull-down, output-high); the `wcd9xxx-irq` interrupt on TLMM GPIO
  123 (`wcd_intr_default`: drive 2, pull-down); MCLK from
  `audio_ext_clk_lnbb`, `<&clock_rpmh 2>`, which is LN_BB_CLK2 in mainline's
  numbering too (also the clock on mainline's SDM845 WCD9340 boards), at
  9.6 MHz (`qcom,cdc-mclk-clk-rate`). Supplies: buck, buck-sido, tx-h, rx-h
  and vddpx-1 from PM8150 S4 (1.8 V), and OnePlus's extra `cdc-vdd-3v3` from
  PM8150L BoB at 3.3 V, a static supply (on for the codec's whole life).
  Micbias: 1, 2 and 4 at 2700 mV, 3 at 1800 mV.
- **Card routing (fragment@91, the last word, OnePlus's):** AMIC1 to MIC
  BIAS1, AMIC2 to MIC BIAS2 ("Headset Mic"), AMIC3 to MIC BIAS4, AMIC4 to
  MIC BIAS1, AMIC5 to MIC BIAS1; `qcom,msm-mbhc-usbc-audio-supported` (the
  headset mic is USB-C analog audio); `qcom,wsa-max-devs = 0` (no WSA
  speakers).
- **Mixer paths (`vendor/etc/mixer_paths_tavil.xml`):** `handset-mic` is
  `amic4` (`AIF1_CAP Mixer SLIM TX0`, `CDC_IF TX0 MUX DEC0`,
  `ADC MUX0 AMIC`, `AMIC MUX0 ADC4`, `AMIC4_5 SEL AMIC4`), used for voice,
  camcorder and voice recognition. `handset-mic-rec` is `amic3` (ADC3 gain
  6), `third-mic-mmi` and `sva-re-mic` are `amic1`. Two- and three-mic
  paths combine AMIC4, AMIC3 and AMIC1. `audio-record` is
  `MultiMedia1 Mixer SLIM_0_TX`. Defaults: `ADCn Volume` 12,
  `DECn Volume` 84 (downstream's 0 dB).
- **Kernel:** the device fragment already builds `SLIMBUS`,
  `SLIM_QCOM_NGD_CTRL`, `MFD_WCD934X`, `SND_SOC_WCD934X` and `SOUNDWIRE_QCOM`
  as modules. `sm8150.dtsi` (from the postmarketOS SM8150 tree) has
  `slimbam` and `slim` (`qcom,slim-ngd-v2.1.0`, BAM pipes 3 and 4, SMMU SID
  0x1b46), disabled. No SM8150 board in that tree or in mainline has used
  them: **SLIMbus has never run on SM8150 under mainline as far as we know.**
  The sm8150 machine driver already handles SLIMbus back ends as sdm845.c
  does (channel maps 128-143 / 144-156, the codec's jack).

## 1. What is reused, what is new

| Piece | State |
| --- | --- |
| wcd934x codec and MFD, slim-qcom-ngd-ctrl, q6afe SLIMbus ports | mainline, used on SDM845 (DB845c, Yoga C630, OnePlus 6/6T) |
| `mfd: wcd934x: Enable the optional micbias supply` | **new**, `0ce7aef3e`: the binding always had `vdd-micbias-supply`; the driver now takes it, so BoB stays on while the codec is bound |
| `ASoC: qcom: sm8150: Run SLIMbus back ends at 16 bits` | **new**, `9507047af`: the fixup forced S24_LE on every link; SLIMbus gets S16_LE, the only format WCD934x SLIMbus has run in mainline. The MI2S speakers keep S24_LE |
| DT: WCD9340 under `slim@1`, pins, `SLIM Capture 1` link | **new**, `b743280ab`; the controller and the link stay `disabled` |
| [`overlays/mic.dtso`](overlays/mic.dtso) | **new**: enables the controller and the link, adds the card's routes |
| UCM `OnePlus/hotdog/HiFi.conf` | Mic1 (AMIC4) and Mic2 (AMIC3), only when the codec's controls exist |

Why the overlay carries the routes: a route to a widget that doesn't exist
fails the whole card, and so does a link to a codec that never probes. In
the base DT both would take the working speakers with them.

Why `"AIF1 CAP", "MCLK"`: in mainline the codec's MCLK widget (the clock
its digital core and decimators run on) is turned on only through a route.
The SDM845 boards route it from `RX_BIAS` (codec playback), and their
SoundWire speakers hold it too. This phone has neither, so without the
route nothing turns MCLK on for a capture.

## 2. Unknowns (each is checked read-only, or in its own step)

- **U1, the ADSP's SLIMbus service.** The NGD driver powers the bus by
  asking the ADSP over QMI (service 0x301). OnePlus's downstream NGD uses
  the same service, so the firmware should have it. M1 checks that the ADSP
  announces it, before anything changes.
- **U2, SMMU stream IDs.** The tree gives `slimbam` and `slim` SID 0x1b46
  only (mask 0), the SDM845 pattern (0x1806 there). Downstream lists
  0x1b46/0x8, 0x1b4d/0x2 and 0x1b50/0x1 (with stage 1 bypassed). If the BAM
  uses another SID, M3 shows `arm-smmu ... Unhandled context fault` with
  the SID; the fix is a hotdog `iommus` override with downstream's list.
- **U3, BAM pipes 3 and 4** for NGD 1's message queues are SDM845's. Same
  controller version, not confirmed for SM8150. Symptom: the NGD times out
  waiting for its first message.
- **U4, BoB's voltage.** Nothing asks BoB for a voltage, so it sits at its
  constraint minimum, 3.008 V (stock: 3.3 V). That leaves about 0.3 V of
  headroom for a 2.7 V bias. If captures are quiet or distorted, M5 retries
  with MICBIAS1 at 1.8 V (the OnePlus 6's level) before anything else.
- **U5, the jack detector (MBHC).** The machine driver starts the codec's
  jack detection on the first SLIMbus link. The phone has no 3.5 mm jack,
  and the mainline OnePlus 6T (also jackless, same codec) runs it this way.
  M4 watches for jack events with nothing plugged in.
- **U6, the third microphone.** AMIC1's location isn't documented. M6
  records it once; the UCM leaves it out until then.

## 3. Rules for this subsystem

- Nothing here touches radio, PMIC registers, RPMB, any partition or a slot.
  The only phone writes are the module tree for the test kernel
  (`/usr/lib/modules/<new release>`, next to the running one), a bring-up
  file in `/etc/modprobe.d`, and (M7) the device package.
- Test kernels are **RAM-booted** (`fastboot boot`): `boot_a` stays as it
  is, and a power cycle returns to it. Reaching fastboot is the owner's job
  (the buttons; [BRINGUP-M1](BRINGUP-M1.md) §2), and every boot back into
  `boot_a` spends a slot-A try while `slot-successful:a` is `no`. Read the
  count first (M0) and keep boots few.
- One change per boot: the overlay boots with the SLIMbus controller
  blacklisted, so the step loads each module by hand under a log stream.
- **Announce before M4:** the speakers are gone from the boot with the
  overlay until the codec has probed (the card waits for it). M5 makes no
  sound.
- Never `rmmod` the SLIMbus, codec or card modules mid-test. Reboot instead
  (a half-removed ADSP audio stack is not worth debugging).
- Recordings with speech stay in `logs/` (gitignored). Quote numbers, not
  audio.

## 4. Decisions for the owner

1. Run the plan at all, and when: each M step needs a yes.
2. After M5-M7 pass: make it permanent, as a `fastboot flash boot_a` of an
   image that has RAM-booted (owner's step, BRINGUP-M1 rule), or wait until
   the nodes are enabled in the kernel DT and the overlay goes away.

## 5. Kernel build

```sh
# kernel.config carries the fingerprint options, as the boot_a kernel has
DEVICE=hotdog KERNEL_DIR=~/omamobile-kernel/wt-hotdog-mic \
  KERNEL_OUT=~/omamobile-kernel/out-hotdog-mic bin/omamobile kernel
DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-mic bin/omamobile modules
DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-mic bin/omamobile initramfs
# DTB_OVERLAYS="mic" in device/hotdog/device.conf for this build only
DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-mic bin/omamobile images
```

Without the overlay this kernel boots like `omamobile-hotdog-fingerprint`:
the controller and the capture link are disabled, and the two driver
changes only act on a bound codec.

## 6. Runbook

Each step is the owner's to run or approve. Read-only first. Each has
Expect/Pass, a **Stop** condition, a Rollback and a risk level. Results go in
§7 with the date and `uname -r`.

### M0: preconditions (read-only; risk none)

- The phone boots Omarchy Mobile from `boot_a` with USB SSH, and the
  speakers play (`speaker-test -D hw:0,0 -c 2 -t sine -l 1`, announce it).
- In fastboot, read the slot flags:
  `fastboot getvar slot-successful:a` and `fastboot getvar slot-retry-count:a`.
- **Stop** if the retry count is 2 or lower: the plan needs two boots
  (the RAM boot doesn't count; the return to `boot_a` does). Mark slot A
  first (the owner's open decision in BRINGUP-M1).

### M1: what the running kernel shows (read-only; risk none)

```sh
tools/phone-ssh 'for r in /sys/class/remoteproc/*; do echo "$(cat $r/name) $(cat $r/state)"; done'
tools/phone-ssh 'qrtr-lookup 2>/dev/null | grep -iE "769|slim" || echo "no qrtr-lookup or no service"'
tools/phone-ssh 'grep -E "gpio(123|143) " /sys/kernel/debug/gpio; grep -E "^pin (123|143) " /sys/kernel/debug/pinctrl/*tlmm*/pinmux-pins'
tools/phone-ssh 'grep -iE "bob|s4a" /sys/kernel/debug/regulator/regulator_summary'
tools/phone-ssh 'grep -E "ln_bb_clk2" /sys/kernel/debug/clk/clk_summary'
tools/phone-ssh 'amixer -c 0 controls | grep -E "MultiMedia2 Mixer SLIMBUS_0_TX"'
```

- **Expect:** the ADSP (`adsp`) `running`; service 769 (0x301, SLIMbus) on
  the ADSP's node; GPIO 123 and 143 unclaimed; BoB listed (state and
  voltage recorded); `ln_bb_clk2` present; the routing control exists.
- **Stop** if the ADSP has no SLIMbus service (U1: the design needs it), or
  another driver owns GPIO 123 or 143.

### M2: the test kernel on the phone (one write: a new module tree; risk low)

Build as §5. Then:

```sh
DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-mic bin/omamobile modules-push
tools/phone-ssh 'printf "%s\n" "# MIC-PLAN M3: the step loads it by hand" \
  "blacklist slim_qcom_ngd_ctrl" "blacklist wcd934x" \
  > /etc/modprobe.d/omamobile-mic-hotdog-bringup.conf'
```

- **Expect:** `/usr/lib/modules/<new release>` next to the running one,
  which is untouched; the blacklist file.
- **Rollback:** `rm /etc/modprobe.d/omamobile-mic-hotdog-bringup.conf`; the
  extra module tree is harmless (remove it after the plan).

### M3: RAM boot with the overlay, SLIMbus up (one boot; risk low)

Announce: the speakers are missing in this boot until M4. Fingerprint
unlock should work as from `boot_a` (the test kernel has the same base, DT
and fingerprint modules, and device-hotdog runs it); if it doesn't, use the
PIN. The owner brings the phone to fastboot by the buttons, then:

```sh
fastboot boot ~/omamobile-kernel/out-hotdog-mic/images/boot.img
# after SSH is up: a log stream to the laptop first
tools/phone-ssh 'dmesg -w' > logs/mic-m3-$(date +%H%M).log &
tools/phone-ssh 'uname -r; ls /sys/bus/slimbus/devices/ 2>/dev/null; modprobe slim-qcom-ngd-ctrl; sleep 3; dmesg | grep -iE "slim|ngd|smmu|qmi" | tail -20'
tools/phone-ssh 'ls /sys/bus/slimbus/devices/'
```

- **Expect:** `uname -r` is the test kernel's release; the NGD probes and
  powers up without an error; the slimbus bus lists the controller's
  devices (`217:250:...`); no SMMU fault.
- **Pass:** no error lines, the two `slim217,250` devices registered.
- **Stop** on an SMMU context fault (U2), an NGD timeout (U3), a QMI error
  (U1), or an ADSP crash (`remoteproc ... crash`).
- **Rollback:** power cycle (Power about 15 s, cable out): `boot_a` boots
  as before (one slot-A try).

### M4: the codec (same boot; risk low)

```sh
tools/phone-ssh 'modprobe wcd934x; sleep 5; dmesg | grep -iE "wcd|slim|mbhc|jack|asoc" | tail -30'
tools/phone-ssh 'cat /proc/asound/cards; ls /dev/snd/; amixer -c 0 controls | grep -cE "AMIC|ADC|DEC"'
tools/phone-ssh 'grep -iE "bob" /sys/kernel/debug/regulator/regulator_summary'
```

- **Expect:** `WCD934X Minor:... Version:...` (the codec answered over
  SLIMbus), no `Efuse sense is not complete` warning (that one means no
  MCLK); the card registers (speakers back, `pcmC0D1c` present); BoB
  enabled with the codec as a consumer; no jack events with nothing plugged
  in (U5).
- **Pass:** all of the above, and `speaker-test` plays as in M0 (announce).
- **Stop** on the efuse warning (MCLK: check LN_BB_CLK2 first), on the card
  not registering, or on a stream of MBHC interrupts.
- **Rollback:** power cycle.

### M5: the first recording, raw ALSA (same boot; risk low)

No sound comes out of the phone. Someone talks at the bottom edge (AMIC4,
the voice mic) for the 5 seconds, then stays quiet for the second take.

```sh
tools/phone-ssh 'amixer -c 0 cset name="MultiMedia2 Mixer SLIMBUS_0_TX" 1
  amixer -c 0 cset name="AIF1_CAP Mixer SLIM TX0" 1
  amixer -c 0 cset name="CDC_IF TX0 MUX" DEC0
  amixer -c 0 cset name="ADC MUX0" AMIC
  amixer -c 0 cset name="AMIC4_5 SEL" AMIC4
  amixer -c 0 cset name="AMIC MUX0" ADC4
  amixer -c 0 cset name="ADC4 Volume" 12
  amixer -c 0 cset name="DEC0 Volume" 84'
tools/phone-ssh 'arecord -D hw:0,1 -f S16_LE -r 48000 -c 2 -d 5 /tmp/mic-amic4-talk.wav; arecord -D hw:0,1 -f S16_LE -r 48000 -c 2 -d 5 /tmp/mic-amic4-quiet.wav; dmesg | tail -10'
tools/phone-ssh 'cat /tmp/mic-amic4-talk.wav' > logs/mic-amic4-talk.wav
tools/phone-ssh 'cat /tmp/mic-amic4-quiet.wav' > logs/mic-amic4-quiet.wav
python3 -I - logs/mic-amic4-talk.wav logs/mic-amic4-quiet.wav <<'PY'
import sys, wave, array, math
for f in sys.argv[1:]:
    w = wave.open(f); a = array.array("h", w.readframes(w.getnframes()))
    for ch in range(w.getnchannels()):
        s = a[ch::w.getnchannels()]
        rms = math.sqrt(sum(x * x for x in s) / max(len(s), 1))
        print(f, "ch", ch, "rms %.1f dBFS" % (20 * math.log10(max(rms, 1) / 32768)), "peak", max(map(abs, s)))
PY
```

- **Expect:** `arecord` runs 5 s without an I/O error; talk clearly above
  quiet (20 dB or more); quiet above digital silence (a live mic has a
  noise floor, roughly -70 to -50 dBFS). One channel may be empty (one
  SLIMbus port, two-channel back end); record which.
- **Pass:** the above, and the talk take, played on the laptop, is speech.
- If both takes are digital silence: `AMIC MUX0` and `ADC MUX0` read back
  as set, then retry with MICBIAS off as the cause in mind: U4 (MICBIAS1 at
  1.8 V is a DT change, so the next boot).
- **Stop** on an ADSP error (`q6afe ... port`), on a hang of `arecord`, or
  on distortion at a normal speaking level.
- **Rollback:** `amixer -c 0 cset name="AMIC MUX0" ZERO`; power cycle if
  anything hangs.

### M6: the other microphones (same boot; risk low)

As M5 with `AMIC MUX0 ADC3` (+ `ADC3 Volume 12`), then `AMIC MUX0 ADC1`
(+ `ADC1 Volume 12`). Tap near the top edge, then near the camera, during
each take, to find which mic is where.

- **Pass:** both record live signal; their positions recorded in §7.

### M7: UCM and PipeWire (device package 0.1.3; risk low)

```sh
tools/phone-install-package packages/omamobile-device-hotdog
tools/phone-ssh 'alsaucm -c 0 dump text | sed -n "1,80p"'
tools/phone-ssh 'su - <user> -c "systemctl --user restart wireplumber pipewire pipewire-pulse; sleep 3; wpctl status | sed -n /Sources/,/Filters/p"'
```

- **Expect:** the HiFi verb lists Speaker, Mic1 and Mic2; PipeWire shows
  "Voice microphone" and "Recording microphone" sources; a `pw-record`
  from each is speech; the speakers still play.
- **Stop** if the speakers' sink is gone (the verb broke): roll back.
- **Rollback:** reinstall device-hotdog 0.1.2 (the speakers' UCM alone).

### M8: making it stay (owner's decision 2)

Either flash the image of M3 to `boot_a` (BRINGUP-M1's rule: an image that
has RAM-booted, read back after the write), with the blacklist file removed
so the modules load at boot, or enable the nodes in the kernel DT, drop the
overlay and build the next `boot_a` from that.

## 7. Results

**2026-11-05, on the phone, RAM boot** of the M2 image (overlay `mic`,
`boot.img` sha256 `9c32c5ae…5779`), `uname -r`
`7.3.0-rc6-omamobile-push1-gb743280ab222`; `boot_a` untouched.

- M0: slot A `slot-successful` no, `retry-count` 6.
- M1 (on `boot_a`'s kernel): ADSP, CDSP and modem running; **U1 answered:
  service 769 (0x301) on node 5, the ADSP** (read with a Python QRTR
  name-service lookup; the phone has no `qrtr-lookup`); GPIO 123 and 143
  unclaimed; BoB 3032 mV, S4A 1800 mV; `ln_bb_clk2` at 19.2 MHz; the
  routing control present.
- M2: modules pushed next to the running tree; blacklist file written.
- M3: `slim-qcom-ngd-ctrl` probed: `SLIM SAT: Rcvd master capability`,
  `SLIM controller Registered`, devices `217:250:0:0` and `217:250:1:0`.
  **U2 and U3 answered**: SID 0x1b46 alone and BAM pipes 3/4 are enough,
  no SMMU fault, no timeout. SMMU faults on SIDs 0x800/0xc20 at 1.16 s
  come before anything of this plan loads.
- M4: `WCD934x chip id major 0x108, minor 0x1`, `Version:0x411`, no efuse
  warning; the card registered with `pcmC0D1c`; the codec holds BoB
  (`vdd-micbias`), `ln_bb_clk2` (`extclk`) and GPIO 123/143. A burst of 18
  `SLIM SAT: Rcvd master capability` lines during the codec's start, then
  none. **U5:** MBHC ran its impedance check, logged `Impedance detect ramp
  error` and `MONO plug type detected`, and `Headset Jack` reads on with
  nothing plugged in (the phone has no jack); no interrupt storm. Watch
  item: nothing routes a headset, so nothing acts on it yet.
- M5: the first take was digital silence: `DEC0 Volume` 0 is -84 dB on
  mainline's control (`min=0,max=124`, register 0xac); **84 is 0 dB**, as
  on stock. Fixed in the runbook and the UCM. At 84, AMIC4 (ADC4 gain
  12): quiet -71 dBFS, speech -50 to -58 dBFS per second, peak -32 dBFS;
  the owner listened: speech, clean. Both channels carry the same samples.
  The AMIC4 TX hold bit (0x611 bit 5) stays set (mainline sets it at the
  ADC's power-up and never clears it); the mics record anyway. Each take
  ends with `underflow error on TX port 0, value 6`, harmless so far.
- M6: AMIC3 (ADC3 gain 12): quiet -74 dBFS, speech -45 to -63 dBFS, peak
  -19 dBFS, loudest from the bottom edge. AMIC1: not taken yet.
- M7: device-hotdog 0.1.3 then 0.1.4 installed; `alsaucm` lists Speaker,
  Mic1 and Mic2; PipeWire offers "HiFi (Mic1, Speaker)" (active) and
  "HiFi (Mic2, Speaker)". **PipeWire's first take was full-scale noise:**
  it opened `hw:0,1` at S24_LE, and asked for S24_LE the ADSP hands back
  the 16-bit samples left-justified in 32-bit words (an S32 layout; raw
  `arecord -f S24_LE` shows `0xffa90000`-style words). S16_LE is clean.
  device-hotdog 0.1.4 pins the capture node to S16LE with a WirePlumber
  rule; `pw-record` is then clean. The kernel side (q6asm-dai capture at
  24 bits behind a 16-bit back end) is open. PipeWire drives `ADC4` as
  the source's volume (100 % = gain 20).
- M8 (the owner tested playback and recording, then gave the go): the
  blacklist file removed; `fastboot flash boot_a` of the RAM-booted image
  (slot A `retry-count` 6 before, 7 after, `slot-successful` still no);
  `boot_a` (`sde11`) read back from Linux: sha256 `9c32c5ae…5779`, equal.
  At boot the modules load by themselves: `SLIM controller Registered` at
  6.9 s, the codec at 6.9 s, the card with `pcmC0D1c`, PipeWire's "Voice
  microphone" source, fingerprint active; `pw-record` gives 16-bit audio.
  New in this boot: `QMI wait timeout` from the NGD at 7.9 s, after the
  codec came up; recording works after it (watch item). Rollback image:
  `boot-fp-g41a6c1235a0b.img` (sha256 `14fe1d55…be79`).

**2026-11-05, laptop only:** stock facts in §0 read from the owner's
OxygenOS dtbo and vendor image; three kernel commits on
`omamobile-hotdog-mic`; the overlay and the UCM written. Checks:

- Kernel built as §5 (`7.3.0-rc6-omamobile-push1-gb743280ab222`, the
  fingerprint options included): no new warnings. `W=1` on
  `drivers/mfd/wcd934x.o` and `sound/soc/qcom/sm8150.o`: clean.
- `checkpatch --strict`: the two driver commits clean; the DT commit warns
  only that `slim217` isn't a vendor prefix (it is the SLIMbus
  manufacturer-ID form, as in mainline's `sdm845-wcd9340.dtsi`).
- DTB: dtc's warnings are the three it already gave (IPA, DSI, PM8150B), none
  in the new nodes. dt-validate (dtschema 2026.9): the same 22 messages for
  the running kernel's DTB, this branch's and this branch's with `mic.dtso`
  applied; nothing new. `sound` has no schema (`qcom,sm8150-sndcard` is the
  out-of-tree machine driver's).
- `mic.dtso` compiles and `fdtoverlay` applies it to the built DTB: the
  controller and `slimcap-dai-link` go from `disabled` to `okay` and `/sound`
  gets the five routes; without it both stay `disabled`.
- UCM: `HiFi.conf` loads with alsa-lib's config parser (syntax only; the
  `If`/`ControlExists` layout is the one upstream's
  `HDA/DualCodecs/HiFi.conf` uses). The package test checks that no codec
  control sits outside `If.mic`.
