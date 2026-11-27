<!-- SPDX-License-Identifier: MIT -->
# Haptics and torch plan (cheetah / gs201)

Status (2026-10-12): **haptics and the torch work and load at boot from the
default DTB.** H1-H3 and T1-T3 passed on the phone (NOTES.md): the CS40L26
runs firmware 7.2.91 and buzzes, the LM3644TT gives 17 torch steps with no
fault flags. H2 needed two kernel fixes (the i2c-exynos5 timeout now scales
with the message length; cs_dsp's write sequence accepts 1, "changed"). H4:
feedbackd uses the CS40L26 through the device package's udev rule
(`74a5f74`). T4: the shell's torch tile works (omamobile-shell 0.1.10+).
Kernel: `omamobile-haptics` @ `d609c1b3e` (`wt-haptics`), merged into
`omamobile-int`. Open: T5 (stock's torch current, before any higher cap).

Earlier status (historical, superseded by the status above): offline work done (drivers, DT, overlays, firmware extraction), built,
**nothing tested on the phone yet**. Build: release
`7.3.0-rc6-omamobile-push1-00065-gebcd2674f279`, images in
`~/android/mainline/out-haptics/images` (`logs/haptics-*.log`); both drivers
W=1 and checkpatch `--strict` clean; `dt-doc-validate` of the three schemas
and `dt-validate` of `gs201-cheetah.dtb`, alone and with the `haptics` +
`torch` overlays applied, report only the existing `soc_id` and
framebuffer items. Written 2026-10-12 against `omamobile`
@ `7b0f8b5d1` (Linux 7.3-rc6), kernel branch `omamobile-haptics` in
`wt-haptics`, build in `out-haptics`.

Goal: vibration through the standard force-feedback API (FF_RUMBLE, which
feedbackd uses) and the rear flash LED as an LED class torch
(`/sys/class/leds/white:torch`) for the quick-settings tile.

Path abbreviations:

- `L/` = `/home/raven/android/mainline/wt-haptics` (our kernel, this branch)
- `G/` = `/home/raven/android/omamobile/out-kernel/google/gs-6.1/private`
- `C/` = `G/google-modules/amplifiers/cs40l26` (Cirrus Logic's GPL driver as shipped by Google)
- `R/` = `/home/raven/android/reference/cheetah-stock-cp2a-root` (stock live DT, logs)

---

## 1. Haptics: Cirrus Logic CS40L26A

### 1.1 Hardware

| Item | Value | Evidence |
|---|---|---|
| Chip | CS40L26**A**, DEVID `0x40A260`, revision **A1** | `R/dmesg.txt:6038` ("Cirrus Logic CS40L26 ID: 0x40A260, Revision: 0xA1") |
| Bus | Google's I2C 8 = PERIC0 **USI8** HSI2C at `0x10970000`, GIC SPI 681, 400 kHz, pins gpp16-0/1 func 3 | `R/live.dts:7868-7889`, `R/live.dts:3903-3909`; USI sysreg `sysreg_peric0` (`0x10821000`) + `0x1c` = our `0x10820000` + `0x101c` (`R/live.dts:7657-7660`, `R/live.dts:7884-7885`) |
| Address | `0x43` | `R/live.dts:7891-7893`; `R/dmesg.txt:6034` (`8-0043`) |
| Neighbours on the bus | ST21NFC `0x08`, SLG51002 camera PMIC `0x75` (neither enabled by us) | `R/live.dts` hsi2c_8 children after line 7918 |
| IRQ | gpa8-1 (FAR_ALIVE, XEINT_13), level low | `R/interrupts.txt:485` (`gpa8 1 Level cs40l26 IRQ1 Controller`); `G/devices/google/gs201/dts/gs201-cs40l26a-config.dtsi:38-45,84-85` |
| Reset | gpp24-3, active low (output, no pull) | `R/live.dts:7898` (`reset-gpios = <gpp24 3 1>`); `gs201-cs40l26a-config.dtsi:48-55,87` |
| Trigger GPIO | gpp24-2 (output, unused by us) | `gs201-cs40l26a-config.dtsi:57-63` |
| Supplies | none in the DT: VA/VP are fixed rails ("supply VP not found, using dummy regulator") | `R/dmesg.txt:6035-6036` |
| Boost | peak current **2.5 A**, VBST **11 V**, DCM default, explosion mode disabled | `R/live.dts:7900-7906`; `gs201-cs40l26a-config.dtsi:89-95` |
| Actuator | f0 145 Hz (`0x244000`, Q10.14), ReDC 13 ohm (`0x68000`, Q?.15) | `gs201-cs40l26a-config.dtsi:96-97`; live DT shows the f0 bytes as a string, `R/live.dts:7907` |
| Firmware | `/vendor/firmware/cs40l26.wmfw` (59960 B), `cs40l26.bin` (wavetable), `cs40l26-svc.bin`, `cs40l26-dvl.bin`, `cs40l26-calib.wmfw` | `R/vendor-firmware.txt:24-28`; loads in `R/dmesg.txt:6040-6041,6319-6370` ("Firmware revision 7.2.91", "14 RAM waveforms") |

### 1.2 Upstream status

Mainline has the **CS40L50** (`drivers/mfd/cs40l50-*.c`, `drivers/input/misc/cs40l50-vibra.c`),
a later part of the same family: same Halo Core DSP memory map
(`L/include/linux/mfd/cs40l50.h` vs `C/cs40l26.h:109-129`) but a different
control-port map (IRQs at `0xE010` vs `0x10010`, mailbox `0x11020` vs
`0x13020`, `C/cs40l26.h:90-108`), a different boot (CS40L50 runs from ROM,
CS40L26 needs its RAM firmware) and only FF_CUSTOM effects. CS40L26 is not in
mainline. So this branch adds a small standalone driver instead of bending
the CS40L50 MFD.

### 1.3 What the new driver does (`L/drivers/input/misc/cs40l26-vibra.c`)

Same sequence as Cirrus' driver, minus everything not needed to vibrate:

1. Reset pulse, wait 6 ms, read DEVID/REVID (A1/B0/B1 only: the ROM
   addresses below are those revisions', `C/cs40l26.c:16-25`).
2. ROM firmware: PLL open loop, GPI event mappings off, amplifier output
   Hi-Z (`C/cs40l26.c:5516-5600`); PREVENT_HIBERNATE through the mailbox
   (`C/cs40l26.c:136-162`); HALO_STATE = RUN; wait until the DSP is
   standby/shutdown; CCM core **kill** (`C/cs40l26.c:549-599`).
3. `cs_dsp_power_up()` loads `cs40l26.wmfw` + `cs40l26.bin`; in `post_run`:
   MEM_RDY + CALL_RAM_INIT, the power-on write sequence (Hi-Z, A1 errata:
   `C/cs40l26-tables.c:270-276`, after the boost-short test,
   `C/cs40l26.c:3861-3935`), CCM core **reset** = start
   (`C/cs40l26.c:525-547`), PREVENT_HIBERNATE, check the RAM firmware's
   HALO_STATE, then the stock boost limits (`C/cs40l26.c:3677-3735`) and
   f0/ReDC (`C/cs40l26.c:3625-3675`), TIMEOUT_MS = 0
   (`C/cs40l26.c:4136-4339` is the full stock version).
4. Playback: the memoryless FF layer (FF_RUMBLE, plus FF_PERIODIC emulated by
   ff-memless) gives a magnitude; the driver writes the firmware's buzz
   generator slot 2 (`BUZZ_EFFECTS2_BUZZ_FREQ/LEVEL/DURATION`, level 0-255,
   duration in 4 ms units) and triggers index `0x01800081`
   (`C/cs40l26.c:2643-2715`, `C/cs40l26.h:466-473`); magnitude 0 sends
   STOP_PLAYBACK `0x05000000` (`C/cs40l26.h:444`). Frequency = f0 (145 Hz).
   Each buzz is capped by `cs40l26_vibra.max_buzz_ms` (default 10000) in the
   firmware itself, so a lost stop can't run forever.

Firmware controls are found by name, matching the **low 16 bits** of the
algorithm ID as Cirrus' own code does (`C/cl_dsp.c:154`): the RAM firmware
relocates IDs (`BUZZGEN` is `0x1f202` in ROM, `0x4f202` in `cs40l26.wmfw`;
`PM` `0x4f206`; `VIBEGEN` `0x400bd`). Checked offline against the user's
`cs40l26.wmfw`: every control the driver uses exists, all XM (type 5).

Not done yet (follow-ups, none needed to vibrate): hibernation (the DSP is
kept awake while bound, a few mW), the IRQ (amplifier errors are not
released; vibration would simply stop), RAM/ROM waveform effects (FF_CUSTOM
clicks), gain, VP/VBST brownout prevention (`cirrus,vpbr-*`), SVC/DVL tuning
files (only one coefficient file goes through `cs_dsp_power_up()`; the tool
already extracts them, a merged WMDR is possible since all three are plain
algorithm blocks), calibration, system suspend.

### 1.4 Safety

- Boost peak current set to stock's 2.5 A (chip default 4.5 A,
  `C/cs40l26.h:570`), VBST 11 V (chip maximum, `C/cs40l26.h:574`).
- A1 errata and the "explosion mode" disable go into the power-on sequence
  before the core starts, as stock; the boost-short test refuses to continue
  on a latched short.
- Output Hi-Z whenever the amplifier is off; unbinding puts the chip back
  into reset.
- I2C only: an unanswered transfer is an error, not a bus hang. PERIC0 has no
  power domain on gs201 (no `pd-peric0` in the stock DT) and its CMU is
  already probed, so the USI8 block is clocked and powered.

---

## 2. Torch: TI LM3644TT

### 2.1 Hardware

| Item | Value | Evidence |
|---|---|---|
| Chip | TI **LM3644TT** dual-channel flash LED driver | camera HAL `com.google.pixel.camera.hal.apex` → `lib64/liblyric_hwl.so` string "LM3644TT-flash"; node name `flash-lm3644` |
| Driver on stock | none in the kernel: LWIS (`google,lwis-i2c-device`) gives the camera HAL raw register access (`/dev/lwis-flash-lm3644`) | `R/live.dts:19041-19050`; `R/dmesg.txt:4348-4350,6331`; `device/google/gs201/sepolicy/vendor/file_contexts:170` |
| Bus | Google's I2C 15 = PERIC1 **USI15** HSI2C at `0x10DA0000`, GIC SPI 696, 400 kHz, pins gpp24-0/1 func 2; also carries the camera EEPROM (M24C08 at `0x50`) | `R/live.dts:8408-8440`, `R/live.dts:4469-4475` |
| Address | `0x63`, 8-bit registers | `R/live.dts:19044-19047`; `G/devices/google/pantah/dts/gs201-cheetah-camera.dtsi:1084-1089` |
| HWEN | gpp8-2 (PERIC0), active high; input with no pull at boot, so the chip is in **shutdown** until someone drives it | `gs201-cheetah-camera.dtsi:1096-1100`; `R/live.dts:4307-4311` (`flash-en`, function 0 = input) |
| STROBE | gpp27-0; LWIS holds it deasserted. Not used by us (the strobe-enable bit stays 0) | `gs201-cheetah-camera.dtsi:1097,1100` |

### 2.2 Register use and limits

Torch only. The driver raises HWEN only while lit (every switch-on starts from
reset values) and writes three registers: LED1 torch (`0x05`), LED2 torch
(`0x06`, LED2-override bit cleared), Enable (`0x01` = mode torch | LED1 |
LED2, TX-pin bit cleared). It never selects flash mode, so the flash timeout
and strobe paths are never armed. Torch current per channel:
LM3644TT 2.55 mA + 2.91 mA × code, LM3644 0.977 mA + 1.4 mA × code (TI
datasheet), told apart by the device ID register `0x0C` (`0x04` / `0x02`).

**Limits.** Stock has no kernel driver to copy limits from: the camera HAL
enforces them from its own configuration ("Flash current is above hardware
spec", "Torch strength level" in `liblyric_hwl.so`), which is not readable
offline. So the DT cap is **our own: `led-max-microamp = <50000>` per
channel** (17 steps, 2.55 to 49.1 mA per channel, ~100 mA total at the top),
well under the chip's power-on default code (186 mA per channel on the TT).
Raise it only after measuring Android's torch (section 4, T5).

Because the register map comes from the datasheet, not from Google code, the
driver **refuses to bind** unless, right after HWEN goes high, the ID is
`0x02`/`0x04` and Enable/LED1-torch/LED2-torch read their documented reset
values `0x80`/`0xBF`/`0x3F`. Fault flags (`0x0A`/`0x0B`) are read and logged
after each switch-on and before switch-off.

---

## 3. Kernel and repo changes

Kernel branch `omamobile-haptics` (`L/`), one commit per subsystem:

| Commit | What | Default |
|---|---|---|
| `16ff4879a` dt-bindings: soc: samsung: exynos-sysreg: add gs201 PERIC0 compatible | `google,gs201-peric0-sysreg` | n/a |
| `c89aea791` dt-bindings: input: add Cirrus Logic CS40L26 | `input/cirrus,cs40l26.yaml` | n/a |
| `f23ce2c8f` Input: add a Cirrus Logic CS40L26 haptics driver | `cs40l26-vibra.c`, `CONFIG_INPUT_CS40L26_VIBRA` | module |
| `1ad1af33c` dt-bindings: leds: add TI LM3644 | `leds/ti,lm3644.yaml` | n/a |
| `32d286884` leds: flash: add a torch-only TI LM3644 driver | `leds-lm3644.c`, `CONFIG_LEDS_LM3644` | module |
| `523b1e0e0` arm64: dts: exynos: google: gs201: add PERIC0 pinctrl, USI8 and USI15 I2C | `sysreg_peric0`, `pinctrl_peric0` (+ gpp0-19, `hsi2c8_bus`), `usi8`/`hsi2c_8`, `usi15`/`hsi2c_15` (+ `hsi2c15_bus`) | all `disabled` (sysreg inert) |
| `ebcd2674f` arm64: dts: exynos: google: gs201-cheetah: describe the haptics driver and the flash LED | `haptic-driver@43`, `led-controller@63`, `hapt_amp_irq`/`hapt_amp_rst` pins | `disabled` |

Note for merging: `wt-fingerprint` and `wt-bt` add the same `pinctrl_peric0`
node and banks (uncommitted there at the time of writing); keep one copy.

Repo (`/home/raven/Projects/omarchy-mobile`):

- `kernel/configs/omamobile.config`: `CONFIG_INPUT_CS40L26_VIBRA=m`, `CONFIG_LEDS_LM3644=m`.
- `device/cheetah/overlays/haptics-i2c.dtso`, `haptics.dtso`, `torch-i2c.dtso`, `torch.dtso`.
- `tools/extract-vendor-firmware`: also copies `cs40l26.wmfw`, `cs40l26.bin`,
  `cs40l26-svc.bin`, `cs40l26-dvl.bin`, `cs40l26-calib.wmfw` to
  `/usr/lib/firmware/updates/` (format checks: Halo WMFW with
  `FIRMWARE_CS40L26` and a buzz generator; WMDR coefficient files). Run
  against `cheetah-cp2a.260705.006`'s image zip: all files extracted.
  Output layout is now `updates/brcm/...` plus `updates/cs40l26*`.
- `tools/ff-rumble`: plays one FF_RUMBLE effect through EVIOCSFF (the
  feedbackd path), no dependencies; `--ms` (max 2000) and `--strength` (%).

---

## 4. Runbook (on the phone; each step has its rollback)

From the omamobile repo, phone in Arch over USB, a second terminal running
`tools/phone-ssh dmesg -w`. Overlays are applied as in `BLUETOOTH-PLAN.md` 4:

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-haptics KERNEL_OUT=$HOME/android/mainline/out-haptics
O=$KERNEL_OUT D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb
ov() {  # ov NAME...: rebuild the DTB from default + overlays, then images
  cp -n "$D" "$D.default"; local o= n
  for n; do $O/scripts/dtc/dtc -q -I dts -O dtb -o out/$n.dtbo device/cheetah/overlays/$n.dtso; o="$o out/$n.dtbo"; done
  $O/scripts/dtc/fdtoverlay -i "$D.default" -o "$D" $o
  bin/omamobile images
}
# rollback for every overlay step: cp "$D.default" "$D"; bin/omamobile images && bin/omamobile push
```

### H0/T0 new kernel, default DTB, firmware installed (nothing new enabled)

```sh
bin/omamobile modules && bin/omamobile initramfs && bin/omamobile images   # already done once
tools/extract-vendor-firmware -o out/vendor-firmware ~/android/factory/cheetah-cp2a.260705.006/image-cheetah-cp2a.260705.006.zip
tar -C out/vendor-firmware -cf - usr | tools/phone-ssh 'tar -C / -xf -'
# keep both drivers from loading on their own while the overlays are on
tools/phone-ssh 'printf "blacklist cs40l26_vibra\nblacklist leds_lm3644\n" > /etc/modprobe.d/omamobile-haptics-bringup.conf'
bin/omamobile modules-push && bin/omamobile push          # slot B, reboots
tools/phone-ssh 'uname -r; ls /usr/lib/firmware/updates/cs40l26*; pacman -Q i2c-tools || pacman -S --noconfirm i2c-tools'
```

Expect: boots as before; the five `cs40l26*` files present. Rollback: previous images.

### H1 haptics bus, read-only ID check

```sh
ov haptics-i2c && bin/omamobile push
tools/phone-ssh 'B=$(ls /sys/bus/platform/devices/10970000.i2c | sed -n "s/^i2c-//p"); echo bus $B
  i2ctransfer -y $B w4@0x43 0x00 0x00 0x00 0x00 r4; i2ctransfer -y $B w4@0x43 0x00 0x00 0x00 0x04 r4'
```

Expect: `10970000.i2c` probes, and either `0x00 0x40 0xa2 0x60` / `0x00 0x00
0x00 0xa1` (DEVID/REVID), or a NAK ("Remote I/O error") if ABL leaves the chip
in reset (gpp24-3 low): that is fine, H2 releases reset. The two transfers
only set the register address and read; nothing is written to a register.
Anything else (bus timeout, a hang): stop and report. Rollback: default DTB.

### H2 driver probe (loads the RAM firmware)

```sh
ov haptics && bin/omamobile push
tools/phone-ssh 'modprobe cs40l26_vibra; sleep 2; dmesg | grep -iE "cs40l26|cs_dsp|0043" ; cat /proc/bus/input/devices | grep -A4 cs40l26_vibra'
```

Expect, in order: "Cirrus Logic CS40L26 ID 0x40a260, revision 0xa1";
cs_dsp "cs40l26.wmfw: format 3 timestamp ..." and wavetable lines (coefficient
version warnings like stock's "Coeff. rev. mismatches" are harmless);
"Firmware 0x1800d4 rev 7.2.91 running"; `input: cs40l26_vibra as ...`.
Failure points and what they mean: "No answer at 0x43" (reset/bus),
"ROM firmware not running" / "DSP state ..." (ROM handshake, stop),
"Firmware control X not found" (firmware differs from the one checked
offline), "Boost converter shorted at startup" (**stop, do not retry**).
Rollback: `rmmod cs40l26_vibra` (puts the chip back into reset).

### H3 a 100 ms vibration

```sh
tools/phone-ssh 'python3 - --ms 100 --strength 25' < tools/ff-rumble
tools/phone-ssh 'python3 - --ms 300 --strength 60' < tools/ff-rumble
```

Expect: a short, light buzz, then a longer, stronger one; no new dmesg
errors ("Mailbox ... not acknowledged" = firmware not running). Rollback:
`rmmod cs40l26_vibra`.

### H4 feedbackd

The device package needs a udev rule so feedbackd finds and can open the
device (check the property name against the installed feedbackd's own rules
in `/usr/lib/udev/rules.d/*feedbackd*` first):

```
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="cs40l26_vibra", ENV{FEEDBACKD_TYPE}="vibra", TAG+="uaccess"
```

Then `fbcli -E phone-incoming-call` (or any feedback event) should vibrate.
After H4 passes: remove the blacklist file and make the overlay's nodes
`okay` in `gs201-cheetah.dts` (main kernel).

### T1 torch bus, read-only

```sh
ov torch-i2c && bin/omamobile push
tools/phone-ssh 'B=$(ls /sys/bus/platform/devices/10da0000.i2c | sed -n "s/^i2c-//p"); echo bus $B
  i2cget -y $B 0x50 0x00; i2cget -y $B 0x63 0x0c; true'
```

Expect: a byte from the camera EEPROM at `0x50` (proves the bus), and **no
answer** from `0x63` (HWEN low = shutdown). Rollback: default DTB.

### T2 driver probe (ID and reset values, nothing written)

```sh
ov torch && bin/omamobile push
tools/phone-ssh 'modprobe leds_lm3644; dmesg | grep -i lm3644; ls /sys/class/leds; cat /sys/class/leds/white:torch/max_brightness'
```

Expect: "LM3644TT (ID 0x04)", "torch: 17 steps, 2550-49110 uA per channel",
`white:torch`, max_brightness 17. "unexpected reset values" or "unknown
device ID": **stop** and report the values (the register map would be wrong).

### T3 torch at the lowest level for 1 s

```sh
tools/phone-ssh 'L=/sys/class/leds/white:torch; echo 1 > $L/brightness; sleep 1; echo 0 > $L/brightness; dmesg | tail -3'
```

Expect: a faint glow from the rear flash for one second (2 × 2.55 mA), no
"fault flags" line. Then a mid level (`echo 9`, ~26 mA per channel) for 1 s.
Rollback: `echo 0 > brightness` / `rmmod leds_lm3644` (HWEN low).

### T4 shell tile

See section 5. Combined DTB for daily use until merged:
`ov haptics torch && bin/omamobile push`.

### T5 (optional, on stock Android) reference torch current

With stock Android rooted (slot A), turn the torch on in quick settings and
note the brightness; the camera HAL owns the bus there, so the codes cannot
be read safely. Use the visual comparison to decide whether to raise
`led-max-microamp` (never above the chip default 186 mA without a measured
stock value).

---

## 5. What the Omamobile shell needs

`packages/omamobile-shell/plugins/omamobile.quicksettings/QuickSettings.qml`,
the `torch` stub (around line 221), should become:

- **available**: a `*:torch` LED exists: `/sys/class/leds/white:torch`.
- **enabled**: `/sys/class/leds/white:torch/brightness` > 0 (re-read after
  each toggle; the LED core keeps the value).
- **toggle()**: `brightnessctl -d white:torch set 100%` / `set 0`.
  brightnessctl writes sysfs directly when it can and otherwise goes through
  systemd-logind's `SetBrightness`, which allows the active session to set
  `leds` devices, so no udev permission rule is needed. 100% is our DT cap
  (~49 mA per channel), not the chip maximum.
- **status**: "On"/"Off"; keep "No flash LED" when the LED is missing (any
  kernel without the torch overlay).

Haptics need nothing in the shell itself: feedbackd (once the udev rule of
H4 is in `omamobile-device-cheetah`) gives touch/notification feedback to
anything that uses libfeedback.
