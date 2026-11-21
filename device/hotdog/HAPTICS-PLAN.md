<!-- SPDX-License-Identifier: MIT -->
# Haptics plan (hotdog / SM8150): the AW8697 vibrator

**Status (2026-11-18): done. First with the driver loaded by hand on the
running kernel (`-gf38b21c1fdb9`, runtime overlay): ticks, notification pulses and
long buzzes are felt (owner), and feedbackd drives it. The kernel with the
driver and the DT node in it (`-g3ae752f99c6a`) passes a RAM boot (H5) and
a sleep (H6) and is on `boot_a` with slot A marked (H7).** Kernel branch `omamobile-hotdog-haptics` (worktree
`~/omamobile-kernel/wt-hotdog-haptics`, output
`~/omamobile-kernel/out-hotdog-haptics`), three commits on top of
`omamobile-hotdog-sleep` @ `f38b21c1fdb9` (the kernel on `boot_a`).
`CONFIG_INPUT_AW8695_HAPTICS=m` in [kernel.config](kernel.config).
No userspace change: feedbackd 0.8.9's udev rules already tag an input
device named `aw8695-haptics` as its vibra device, with `uaccess`.

**Goal.** Notifications, calls, the alert slider's Vibrate position and the
shell's button ticks vibrate the phone through feedbackd.

## 1. Facts

| What | Source |
| --- | --- |
| Vendor node `aw8697_haptic@5A` (`awinic,aw8697_haptic`) on `qupv3_se7_i2c`: `reset-gpio` TLMM 116, `irq-gpio` TLMM 24. Its pin states are named the other way round (`aw_irq` configures gpio116, `aw_reset` gpio24), both 2 mA, gpio24 `bias-disable`. No supply | stock DTBO entry 18 (`MTP 19801 MP`), fragments 97 and 102 |
| The PM8150B's own haptics block (`qcom,haptics@c000`) is in the stock DT too but the phone's actuator hangs off the AW8697 | stock DTBO entry 18 |
| `qupv3_se7_i2c` pins are gpio98/99 `qup7`, 2 mA, `bias-disable`: the same as mainline's `qup_i2c7_default` | stock base DTB |
| Before the driver: gpio116 (reset) an input reading high with ABL's pull-up, so the chip is out of reset; gpio24 (interrupt) reads high under a pull-down, so the chip drives it | `/sys/kernel/debug/gpio`, 2026-11-18 |
| With the bus on (runtime overlay) the chip answers at 0x5a: ID 0x97 (AW8697). `SYSCTRL` 0x41 (standby, boost bypassed), data gain (0x39) 0x80 | `i2cget`, 2026-11-18 |
| The AW8697 has the AW8695's register map (Luca Weiss's 2022 AW8695 driver works unchanged apart from the ID); RAM mode plays 24 kHz: 60,000 and 28,000 samples of a looped silent waveform took 2,507 ms and 1,174 ms (23.9 kHz) | timed by polling `GLB_STATE`, 2026-11-18 |
| The chip measures the LRA's resonance at 175.7-176.1 Hz (three probes). Stock ships waveform libraries for 166, 168, 170, 172 and 174 Hz (`/vendor/firmware/aw8697_haptic_*.bin`, base 0x800, 18 waveforms), picked per phone by its measured f0 | probe log; owner's OxygenOS 10.0.14 vendor image (never committed) |
| feedbackd's `quiet` profile: `button-pressed` is a 7 ms `VibraPattern` at 0.2, `window-close` a 25 ms rumble, `message-new-instant` 150 ms, `phone-incoming-call` a 1 s `VibraPeriodic` at 0.5 | `/usr/share/feedbackd/themes/default.json` |

## 2. Design

The driver, `drivers/input/misc/aw8695-haptics.c`, builds on Luca Weiss's
AW8695 driver from linux-input (2022-04-08, never merged), with that
series' review applied, and accepts the AW8697's ID. It keeps the input
name `aw8695-haptics`, which feedbackd knows.

- RAM mode only: one period of a sine (peak 84 of 127, as the vendor's and
  Luca's waveforms) at the measured f0 is written to SRAM at probe and
  looped while a rumble plays. The rumble magnitude is the chip's data gain
  (0x80 = 1.0), changed in place when ff-memless changes the level.
- The f0 comes from the chip's own detection at probe (a short CONT-mode
  drive, about 0.15 s, felt as one buzz at boot), checked against
  `awinic,f0-hz` (170 in the DT): more than 10 % away and the DT value is
  used.
- The boost converter stays bypassed: the actuator runs from VBAT. The owner
  found full magnitude strong enough (H3).
- A playback lasts at least four periods (about 23 ms). feedbackd's 7 ms
  tick was ended by ff-memless before the driver's work item started it, so
  the first driver version played it at gain 0 and the tick was lost.
- Stop writes GO = 0 (a read-modify-write skipped the write when GO already
  read 0, which left the motor running after short pulses in H3) and waits
  for standby; if the chip still plays, the driver resets it and sets it up
  again rather than leave the motor on.

## 3. Runbook

Bring-up files on the phone (remove after H7): `/root/haptics/`,
`/usr/lib/firmware/omamobile/haptics/`; the overlay module is
`~/omamobile-kernel/ext-haptics/omamobile_dtoverlay.ko`, built against
`out-hotdog-sleep`.

**H1. Bus and ID (read-only), runtime overlay.** Risk: low.
`insmod omamobile_dtoverlay.ko name=omamobile/haptics/hap-i2c7.dtbo`
(i2c@89c000 `okay`, no child), then `i2cdetect -y -r <bus> 0x58 0x5c` and
`i2cget` of 0x00. Pass: 0x5a answers 0x97. Stop: no device, or an I2C
error. Rollback: `rmmod omamobile_dtoverlay`.
*2026-11-18: pass, bus i2c-8, ID 0x97 (§1).*

**H2. RAM sample rate (silent).** Risk: low. A zero waveform of 4,000
samples written to SRAM by `i2ctransfer`, looped 15 and 7 times in RAM
mode with the boost bypassed, timed until `GLB_STATE` reads 0. Pass:
about 24 kHz. *2026-11-18: 23.9 kHz.*

**H3. Driver by hand (vibrates; announce it).** Risk: low.
`rmmod omamobile_dtoverlay`, overlay `hap-all.dtbo` (adds `vibrator@5a`
with the TLMM phandle of `-gf38b21c1fdb9`'s DTB), `modprobe ff-memless`,
`insmod aw8695-haptics.ko`. Pass: `AW8697, LRA at 17x.x Hz`, an input
device `aw8695-haptics` with `FEEDBACKD_TYPE=vibra`; rumbles of 7 ms to
1 s at 0.2 to 1.0 felt; ten `fbcli -E button-pressed` in the `quiet`
profile each felt and each leaves `GLB_STATE` 0. Stop: `GLB_STATE` stays
non-zero after a rumble ends: `i2cset -f -y 8 0x5a 0x00 0xaa` (soft
reset) stops the motor. *2026-11-18: pass with the second driver version
(owner: "all felt, strength OK"). The first version left the motor
running after a feedbackd tick (twice, stopped by the soft reset); see §2.*

**H4. Build (laptop).** As [KEYS-PLAN](KEYS-PLAN.md) K0 with
`wt-hotdog-haptics`/`out-hotdog-haptics` and
`DTB_OVERLAYS="mic torch camera popup camera-main camera-af voice"`.
Pass: the overlaid DTB has `/soc@0/geniqup@8c0000/i2c@89c000/vibrator@5a`;
`aw8695-haptics.ko` is in the modules tarball; checkpatch `--strict` shows
only the missing Signed-off-by and MAINTAINERS; `dt_binding_check` of
`awinic,aw8695.yaml` is clean.
*2026-11-18: done. `7.3.0-rc6-omamobile-push1-g3ae752f99c6a`; the image
takes `boot_a`'s command line (`clk_ignore_unused pd_ignore_unused
panic=10 splash`, through a build-only `CMDLINE` in device.conf), `boot.img`
sha256 `ead839df…1c40` (`boot-console.img` beside it has `console=tty0`);
the overlaid DTB has `vibrator@5a`; the driver builds without warnings at
`W=1`; checkpatch and `dt_binding_check` (dtschema 2026.9, yamllint not
installed) as expected.*

**H5. Modules and RAM boot (owner: fastboot by the buttons).** Risk:
medium (a new kernel). Stop the modem first (AGENTS.md §2), unload the
bring-up modules (`rmmod aw8695_haptics omamobile_dtoverlay`), then
`DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-haptics bin/omamobile modules-push`
and `fastboot -s <serial> boot ~/omamobile-kernel/out-hotdog-haptics/images/boot.img`.
A RAM boot spends no slot-A try. Pass: Arch up as on `boot_a` (cameras,
fingerprint, mics, modem, keys, sleep); `dmesg` shows `AW8697, LRA at`
175-176 Hz with one short buzz during boot; the alert slider's Vibrate
position plus a test SMS or `fbcli -E message-new-instant` vibrates.
Stop: no SSH in 2 minutes (bad RAM boots happen: retry once, then hold
Power: `boot_a` comes back).
*2026-11-18: pass. `systemctl reboot --reboot-argument=bootloader` reached
fastboot in 12 s, the RAM boot SSH 12 s later; `AW8697, LRA at 175.4 Hz`
at 6.7 s, the module loaded from the DT; 16 video nodes, fingerprint, keys,
alert slider, touch, three sound cards, the modem in ModemManager, three
remote processors running, no failed units. feedbackd's `button-pressed`
and `message-new-instant` (`quiet`) played and ended with `GLB_STATE` 0.
The quickshell GPU hangcheck at 24 s is old (6 to 211 per boot on the
earlier kernels).*

**H6. Sleep.** A `systemctl suspend` while a 1 s rumble plays, woken by
the power key. Pass: the motor stops at the sleep, and the next
`fbcli` event after the wake vibrates.
*2026-11-18: pass, cable in, RTC wake. A 10 s rumble from a detached unit,
`GLB_STATE` sampled every 0.1 s against `/proc/uptime`: 0x07 for 6 s up to
the freeze, a 20 s sleep, 0x00 at the first sample after the wake although
ff-memless's effect had not ended (its timer stops in s2idle); a rumble
after the wake played and ended normally. With the cable in, a sleep entered
straight after a rumble resumed in 0.3 s (dwc3 "HS-PHY not in L2"), as
before this driver.*

**H7. Flash `boot_a`** with the H5 image once H5 and H6 pass, as
[KEYS-PLAN](KEYS-PLAN.md) K6; this clears slot A's successful mark, so
re-run `device/hotdog/slot-a-mark` status/dump/write with the owner's yes
after it boots ([BRINGUP-M1](BRINGUP-M1.md)). Rollback image: the current
`boot_a`, `~/omamobile-kernel/out-hotdog-sleep/images/boot.img`
(`-gf38b21c1fdb9`). Then remove the bring-up files above.
*2026-11-18: done (owner's yes). `boot_a` = `-g3ae752f99c6a`
(`~/omamobile-kernel/boot-haptics-g3ae752f99c6a-2026-11-18.img`, read back
from `sde11` by sha256 `ead839df…`); the rollback image
`boot-sleep-gf38b21c1fdb9-quiet.img` matched the old `boot_a` byte for
byte. Booted from flash in 9 s (f0 173.7 Hz this time), no failed units,
modem up. `slot-a-mark`: GPT `3466da83…` after the flash (tries 6,
successful 0), dump to `~/android/reference/hotdog/gpt/`, write: `boot_a`
successful 1, tries 6, `boot_b` unchanged, GPT `361c9ccc…` as after this
morning's mark. Bring-up files removed.*

## 4. Open

- Waveform effects (FF_PERIODIC shapes, a braked click) instead of a
  looped sine: feedbackd emulates them through ff-memless as rumbles today.
- The boost converter, for a stronger drive, would need the vendor's boost
  settings; not needed so far.
