<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): torch and haptics

Status (2026-10-15): **the torch works** (kernel `gd2521ee96675`, branch
`omamobile-gs101-torch`); the owner tested the LED and the quick-settings
tile. **Haptics: not started** (a CS40L25A, where cheetah has a CS40L26A).
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
