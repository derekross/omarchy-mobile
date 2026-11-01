<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): torch and haptics

Status (2026-10-15): **the torch works** (kernel `gd2521ee96675`, branch
`omamobile-gs101-torch`); the owner tested the LED and the quick-settings
tile. **Haptics work** (2026-10-28): the CS40L25A B1 (cheetah has a
CS40L26A) through `cs40l25-vibra` (kernel derekross/linux-omarchy-mobile#114)
and feedbackd; key presses tick (section 2, H5).
Cheetah's plan: [device/cheetah/HAPTICS-TORCH-PLAN.md](../cheetah/HAPTICS-TORCH-PLAN.md).

## 1. Torch: TI LM3644TT

| Item | raven (gs101) | cheetah (gs201) | Source |
| --- | --- | --- | --- |
| Chip | TI LM3644TT dual flash LED driver (device ID 0x04) | LM3644TT | stock `flash@0`, node-name `flash-lm3644`; our driver's ID read |
| Stock driver | none in the kernel: LWIS (`google,lwis-i2c-device`) gives the camera HAL raw access | the same | stock raven DVT overlay, `lwiscamera` fragment |
| Bus | PERIC0 USI7 HSI2C (`hsi2c@10960000`, Google's I2C 7, also the cameras' bus), 370 kHz on stock | USI15 HSI2C | stock `hsi2c_7` |
| Address | `0x63`, 8-bit registers | `0x63` | stock `i2c-addr` |
| HWEN | gpp23-6, active high | gpp8-2 | stock `enable-gpios` |
| STROBE | gpp27-0; not used (strobe-enable stays 0) | gpp27-0 | stock `enable-gpios` |

**Port:** cheetah's torch-only `leds-lm3644` (`ff72cdbd3`, imported, NOT FOR
MERGE) and raven's node (`705ef993f`): `white:torch`, both LEDs
(`led-sources = <1 2>`), capped at 50 mA per channel (cheetah's bring-up
limit, not a stock value).

**Results (2026-10-15, `gd2521ee96675`):** `lm3644 0-0063: LM3644TT (ID
0x04)`, `torch: 17 steps, 2550-49110 uA per channel`; step 1 on and off by
hand, then the owner's test of the LED and the shell's torch tile
(brightnessctl through logind, no udev rule needed).

## 2. Haptics: Cirrus CS40L25A (not started)

From stock raven's DT: `cs40l25a@43` on I2C 8 at `0x43`, interrupt on
gpa6, with its own codec node on the AoC card's haptics back end
(`dai_be_haptic_rx`). The vendor partition has `cs40l25a_cal.wmfw`,
`cs40l25a_clab.wmfw`, `cs40l25a_par.wmfw` and their `.bin` files.
Mainline has no CS40L25A driver; cheetah's CS40L26 work is the starting
point (both are Cirrus haptic DSPs, different register maps).

**H0 (2026-10-27, `g64b532aaf7e8`, read-only):** stock's `hsi2c_8` is
`i2c@10970000`, which our DT already enables (`i2c-1`, a camera EEPROM at
0x50); there's no node at 0x43 yet. The reset line `gpp24-0` is an output
driven high (the bootloader leaves the chip out of reset), the trigger
`gpp24-3` an output low. Two reads over I2C (32-bit registers at 32-bit
addresses, `i2ctransfer -f -y 1 w4@0x43 0 0 0 <reg> r4`): `DEVID` (0x0)
`0x0040A25A`, a CS40L25A; `REVID` (0x4) `0xB1`. The vendor image's
`/firmware` has `cs40l25a_cal`, `_clab` and `_par` (`.wmfw` and `.bin`)
and `cs40l20.bin`; `extract-vendor-firmware -d raven` doesn't stage them
yet. Stock's node (`gs101-raviole-audio.dtsi`): IRQ gpa6-5, reset gpp24-0,
trigger gpp24-3, boost 1000 nH / 4 uF / 4500 mA peak, 7.5 V (CLAB 7.5 V),
OVP 12 V, f0 153 Hz (140-165), `fw-id-remap` 0x1400CB.

**Next:** a driver. Nothing in our tree or mainline supports the
CS40L25 (cs40l26-vibra and mainline's cs40l50 are the newer Halo-core
parts); Google's GPL `cs40l2x` (its raviole kernel's amplifiers modules) is
the citable reference for the boot, firmware and wavetable interface.
Read alongside Google's GPL `cs40l2x` (Cirrus Logic's driver in Google's
raviole kernel, `kernel/google-modules/amplifiers`, branch
`android-gs-raviole-mainline`, `cs40l25/`; GPL-2.0; local reference copy
in `~/android/google/amplifiers-raviole`, never committed).

**H0b (the same day, read-only, the boot checks Google's probe makes):**
`IRQ1_STATUS4` (0x1001C) 0x3, OTP boot done; `IRQ1_STATUS3` (0x10018)
0x2000002f, no OTP error (bit 31 clear); `BASIC_AMP_STATUS` (0x280018C)
0x1, basic-mode boot done; `BASIC_HALO_HEARTBEAT` (0x2800158) 0x4bace,
0x4bb9e 200 ms later, about 1 kHz. So the bootloader leaves the chip in
basic mode with its ROM firmware running, which is what Google's probe
expects. The B1 core is Halo, as the CS40L26's, so mainline `cs_dsp`
covers its DSP.

**What Google's probe does on a CS40L25A B1** (`cs40l2x_part_num_resolve`
and the `B1ROM` paths): wait for OTP boot; read DEVID and REVID; exit
basic mode (`cs40l2x_basic_mode_exit`: wait for basic boot done and a
moving heartbeat, then hand the chip to the driver); apply and sequence
the B0 errata. On a CS40L25A the firmware ID is the DT's remap (stock:
`CLAB`, 0x1400CB; `B1ROM` 0x1400BA is refused as a remap), and probe
always ends by loading that RAM firmware (`cs40l25a_clab.wmfw` and its
coefficient files). The ROM heartbeat seen in H0b is basic mode, a
stand-alone ROM program the handover shuts down: nothing plays until the
RAM firmware runs. (An earlier version of this plan said the B1 could play
from ROM; it can't, through this driver's path.) A waveform plays by writing its index to the firmware's mailbox
(`MBOX_TRIGGERINDEX`, DSP virtual mailbox 1): 0 the vibration, 0x1-0x7FFF
clicks, 0x8000-0xFFF6 continuous; `MBOX_POWERCONTROL` (mailbox 4) wakes
and hibernates it.

**Runbook (each step gated; read-only first; a step that writes is the
human's call):**

| Step | What | Writes | Pass | Stop | Risk |
| --- | --- | --- | --- | --- | --- |
| H1 | a driver probe that reads only: IDs, OTP and basic-mode status, the heartbeat | none | `CS40L25A revision B1`, heartbeat moving | any read error | low |
| H2 | reset pulse, basic-mode handover and the B0 errata, as Google's probe | reset, the handover, the errata | state machine SHUTDOWN, no OTP or amplifier error, the basic-mode heartbeat stopped | any error flag, no acknowledge (rollback: a reset pulse returns basic mode) | low-medium |
| H3 | the RAM firmware (`cs40l25a_clab.wmfw` and coefficients) through `cs_dsp`, as stock | firmware | firmware ID 0x1400CB, heartbeat moving, DSP scratch 0 | load error, scratch non-zero | medium |
| H4 | boost from stock's DT (1000 nH, 4 uF, 4.5 A peak, 7.5 V), one short click at a low gain | boost, gain, one mailbox write | one tick felt, no fault IRQ | a fault IRQ, a buzz that doesn't stop (rollback: reset pulse) | medium |
| H5 | FF_RUMBLE through the input layer, feedbackd's udev rule as cheetah's | as H4 | the shell's haptic feedback | as H4 | low |

**H1 result (2026-10-27, `g64b532aaf7e8`):** passed. The read-only probe
(`omamobile-gs101-haptics`, NOT FOR MERGE `cs40l25-h1`, an out-of-tree
module bound by hand through `new_device`) logged `devid 0x40a25a revid
0xb1, OTP boot done, basic mode booted, heartbeat 420111 -> 420133 in 20
ms`; unbound and unloaded afterwards.

**H2 result (the same day, `g64b532aaf7e8`):** passed (`cs40l25-h2`, the
same branch, bound the same way; `libgpiod` installed on the phone first
so a reset pulse on gpp24-0 can undo it). `basic mode shut down (state
4), no error flags; revert and errata written (trim12 0x002f0065, trim13
0x00002b4f); basic-mode heartbeat stopped`. Read by hand after it: state
4, `BASIC_AMP_STATUS` 0x1, the heartbeat still 0xadacb 200 ms later.
`IRQ1_STATUS3` went 0x2000002f to 0x2000003f: bit 4, PLL unlock in the
CS35L41's layout of the same block, latched by the PLL errata (no error
bit). (Later the same day: the PLL errata keep the lock; what unlocks the
PLL is the revert's `PWR_CTRL1` = 0, global enable off; see H3.) The
chip stays shut down until a reset.

**H3 and H4 (the same day, `g64b532aaf7e8`): the firmware runs and the
motor buzzes.** `cs40l25-h3` (the same branch; the owner's
`cs40l25a_clab.wmfw` and the wavetable `cs40l20.bin` from the factory
image, copied to the phone's `/usr/lib/firmware/updates/` for the test,
never into the repo), in this order, as Google's probe:

1. the basic-mode handover and B0 errata (H2);
2. `cs40l2x_init()`: stock's boost (K1/K2 0x24, slope 0x75, peak 0x4a,
   7.5 V 0x64, OVP 0x130) and its short test (passed, `IRQ1_STATUS1`
   0x01c00000), the PCM routing, wake sources 0x98 (I2C SDA and GPIO1);
3. the firmware through `cs_dsp` (the CS40L50's Halo memory map, system
   info at 0x25e0000): `Firmware: 1400cb vendor: 0x2 v10.7.9, 2
   algorithms`, `cs40l20.bin (v2): v10.3.2`;
4. in `pre_run`, `cs40l2x_dsp_pre_config()`'s controls (an empty power-on
   sequence, GPIO1 button detection, GPIO1 and events off, the IRQ2 mask
   sequence and valid), the DSP errata, memory-ready and global enable.

`HALO_STATE` settles at **201**, not the 203 the cs40l2x tables give
(Google's mainline and Android 14 branches alike), and stays there. What
took a while: the firmware drops global enable itself, and the PLL,
locked to the MCLK on GPIO2 (`PLL_CLK_CTRL` 0x15: MCLK, enabled, 32 kHz;
locked in basic mode, so the clock is wired and running), unlocks with
it. So 201 is the firmware's idle state on this setup, not a hang;
neither `lock_regions`, the power-on sequence nor any other control
changed it.

H4: with the firmware idle, index 1 written to the trigger mailbox
(`MBOX_TRIGGERINDEX`, 0x13020) was taken within 5 ms; the firmware set
global enable, the PLL locked, no error flag came up (`IRQ1_STATUS1`
unchanged), and the owner felt **a strong vibration for about half a
second**, until the test's reset pulse 0.5 s later. So index 1 may not be
a short click in this wavetable, or nothing stopped it; and it played at
the firmware's default gain. Next: the waveform list and lengths
(`NUMBEROFWAVES`, the wavetable header), a stop, a low gain, then a short
click; then FF_RUMBLE.

The firmware files stay off the repo: `extract-vendor-firmware -d raven`
gets them from the owner's factory image when H3 needs them.

**H5 (2026-10-27/28, `g97f09c8cfada` and `g3ba8c15c89b8`): passed.** The
bring-up probes became one driver, `cs40l25-vibra` (kernel
`omamobile-gs101-haptics`, upstream as derekross/linux-omarchy-mobile#114,
with its binding and raven's node), which probes at boot from the DT and
exposes FF_RUMBLE through ff-memless:

- a start plays the continuous effect (index 0) through the trigger
  mailbox, a stop writes ENDPLAYBACK;
- the strength sets the firmware's trigger gain, mapped onto -8 to -18 dB;
- themes ask for 7-12 ms clicks, shorter than the actuator needs to build
  up, so a stop is held back to 30 ms (`min_on_ms`).

feedbackd drives it through `72-omamobile-feedbackd.rules` (FEEDBACKD_TYPE
vibra, as cheetah's CS40L26). The owner confirmed key-press haptics on
the on-screen keyboard.

**H5 again (2026-10-28/29, `ge1e6adb69bbf`): passed** on the reworked driver
that lands with #114 (reset active low, boost from the DT): the CS40L25A
(revision B1) probes at boot with firmware 0x1400cb running, and key
presses on the on-screen keyboard still tick.

**The boot race:** the motor's input device appears only once its
firmware has loaded, about 5 s into the boot. feedbackd, started by D-Bus,
only looks for haptics devices when it starts, so a boot where something
asked for feedback first ran without haptics until feedbackd was restarted
by hand. The rule now also starts `omamobile-feedbackd-rescan.service`
when the motor appears, which stops a running feedbackd; the next request
starts it again with the motor. Checked on the phone by replaying the
motor's arrival (`udevadm trigger --action=add`): feedbackd was stopped,
the next request started a new one, and it buzzed.

Not yet: the IRQ, hibernation, braking (the CLAB configuration
`cs40l25a_clab.bin` is extracted but not loaded), calibration and the codec
path.
