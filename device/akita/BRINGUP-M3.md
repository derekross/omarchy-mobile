<!-- SPDX-License-Identifier: MIT -->
# akita M3: input (buttons, then touch)

**Status (2026-11-11):** **M3 is complete on the phone.** The buttons passed gate (f) and touch passed gate (g): Power wakes the screen, the PIN pad unlocks by touch, and the shell and on-screen keyboard work by hand ([Results](#results)).

The kernel side:
- linux-omarchy-mobile#238 (the buttons and `mem_sleep_default=s2idle`), merged on 2026-11-11;
- #240 (a voltage setter for the S2MPG14's two touch supplies), open as of 2026-11-11;
- #241 (the touch supplies, the touchscreen and the panel size, stacked on #240), open as of 2026-11-11; it lands #240's commit with it.

M2 is complete ([BRINGUP-M2](BRINGUP-M2.md)).

## Goal

Make the 8a usable by hand:
- Power wakes the screen;
- the volume keys work;
- touch unlocks with the PIN and drives the shell.

That's the Pixel 8 Pro's (husky's) "boots and unlocks by touch" bar.

Slot A stays stock. Only slot B's boot images are written. `userdata` keeps M2.7's Omarchy image, and nothing reinstalls it. Each module set for a new kernel release is added under `/usr/lib/modules` by `bin/omamobile modules-push`, and the older sets stay.

## What akita inherits

- **From husky (same SoC, merged on `omamobile`):**
  - the `gpio-keys` node (kernel #148);
  - the ACPM PMIC (S2MPG14) regulators (kernel #163);
  - USI2_HSI0 and its SPI, `spi20` (kernel #153);
  - the disabled `panel0` node that gives simpledrm the panel's size (kernel #154).

  The shared `zuma-pinctrl.dtsi` already has `key_power`, `key_voldown`, `key_volup`, `ts_irq` and `ts_reset`.
- **From lynx (Pixel 7a):** the same touch controller, a Goodix GT9895 on `goodix_berlin_spi`. The driver takes its 14-byte contact records from the `goodix,gt9895` match data ([lynx NOTES](../lynx/NOTES.md#2026-10-24-touchscreen-rtc-and-slot-retries)).
- **The kernel config:** `KEYBOARD_GPIO=y`, `SPI_S3C64XX=y` and `TOUCHSCREEN_GOODIX_BERLIN_SPI=m` were already in akita's build. No config change was needed.

## Facts

From G/ `zuma-akita-touch.dtsi` and `zuma/zuma-common-touch.dtsi`, checked against R/ (the stock live tree, `/proc/interrupts`, input devices and `dumpsys display`, captured before the wipe) and F/ (the factory image's vendor partition):

| Item | akita | husky (merged) | Source |
| --- | --- | --- | --- |
| Volume down / up / power | `gpa4-1` / `gpa6-2` / `gpa4-0`, codes 114 / 115 / 116, wake sources | the same pins and codes | [V] G/ `zuma-common.dtsi`; R/ interrupts (`gpio-keys: KEY_*`) |
| Touch bus | `spi_20` = USI2_HSI0 at `0x111d0000`, 10 MHz | `spi20`, 10 MHz | [V] G/, R/ |
| Touch interrupt | `gpn0-0`, falling edge | `gpn0-0` (level low) | [V] G/ (`irq-flags = 2`); R/ interrupts (`gpn0 0 Edge goodix_ts`) |
| Touch reset | `gpp21-2` | `gpp21-2` | [V] G/, R/ |
| vdd (I/O) | S2MPG14 `LDO25M`, 1.8 V | `LDO25M`, 1.8 V | [V] R/ live tree |
| avdd | S2MPG14 `LDO4M`, **3.0 V** | `LDO4M`, **3.3 V** | [V] R/ live tree (`0x2dc6c0`) |
| What ABL leaves | `LDO4M` **3.3 V**, `LDO25M` 1.8 V, both off | (3.3 V, 1.8 V) | [V] test 29 below; husky's is inferred from its probe succeeding without a setter |
| Chip | **Goodix GT9895** (Berlin), Google's `goodix,nottingham` | ST SALIXP | [V] F/ `goodix_firmware_ak3a.bin` and `goodix_firmware_ak3b.bin` (one per panel) both start `BERLIN` … `9895`; R/ modules (`goodix_brl_touch`) |
| Panel size | **64 × 141 mm** (the lit area). Stock's figure is 70 × 149 mm, larger than the glass | 70 × 155 mm | [V] measured with a ruler; a 6.1-inch 20:9 panel is 63.6 × 141.3 mm; G/ touch node `goodix,panel-height-mm = <141>`. Stock's: Google's `panel-google-ak3b.c` (`width_mm`, `height_mm`) and R/ `dumpsys display` (xDpi 391.885, yDpi 409.127 for 1080x2400) |

So the buttons are a copy of husky's node, and touch is husky's bus and pins with lynx's chip driver. The one value that must **not** be copied from husky is avdd: akita's is 3.0 V.

## Design

1. **Kernel:**
   - **#238 (merged):** `zuma-akita.dts` gets husky's `gpio-keys` node and `mem_sleep_default=s2idle` in its bootargs, as the 7 Pro and the 7 do.
   - **#240:** `s2mps11` gets a `set_voltage_sel` for LDO4M and LDO25M only. The selector tables are Google's (`s2mpg14-regulator.c`: LDO4M group 5, 1.8 V + 25 mV steps; LDO25M group 4, 0.7 V + 25 mV steps; 64 steps each). The core calls it only to bring a voltage into a board's constraint, so the 9a (no constraint) and husky (constraint equal to ABL's) see no write.
   - **#241:**
     - the S2MPG14 with LDO4M fixed at 3.0 V and LDO25M at 1.8 V;
     - the GT9895 on `spi20`;
     - a disabled `panel0` with the measured 64 × 141 mm, its comment naming stock's 70 × 149.
2. **No firmware upload.** The Berlin driver runs the firmware already on the chip and loads nothing, so no Google file is needed.
3. **No package change.** `omamobile-keys` and the lock's wake already handle `KEY_POWER`, and the shell's touch path is the same as husky's.

## Runbook

Each boot needs the human's go and changes one thing. Every boot is from slot B: check the tries, and `--set-active=b` as needed. **Each step's results end with slot B's tries left.**

### M3.0 Before anything (laptop only)
- Rebase onto `omamobile`, which has linux-omarchy-mobile#209 (the zuma clkout entry), and build M3.1's kernel.
- Find which Berlin IC the 8a has: the stock firmware's header.

### M3.1 Buttons and the sleep default (gate f)
- **Flash:** a kernel with only the `gpio-keys` node and `mem_sleep_default=s2idle` added.
- **Pass:**
  - `/proc/interrupts` shows the three `gpio-keys` lines;
  - each short press raises its interrupt twice (press and release);
  - a short Power press wakes the screen through the lock;
  - `/sys/power/mem_sleep` reads `[s2idle] deep`;
  - the kernel log has no `exynos-clkout` lines (#209).
- **Watch for:**
  - **Long-pressing Power is the PMIC reset.** Use short presses only.
  - Both volume keys have no internal pull and are wake sources, as on the 8 Pro. When s2idle is first tried, check those two pins first if the phone wakes by itself.

### M3.2 The touch supplies, read only
- **Flash:** a kernel with the S2MPG14 regulators and no touch node.
- **Pass:**
  - the rails register at 3.0 V and 1.8 V and stay off;
  - nothing else in the kernel log changes.

### M3.3 Touch probe
- **Before the boot:** the touch node is added, and the touch driver is held back by a modprobe blacklist.
- **After the boot:**
  - read the rails back (3.0 V, 1.8 V, off);
  - load `goodix_berlin_spi` by hand;
  - remove the blacklist.
- **Pass:**
  - the probe succeeds;
  - interrupts on `gpn0-0` rise with touches;
  - the four corners come in near (0,0), (1079,0), (0,2399) and (1079,2399).

### M3.4 In the session (gate g)
- **Pass:**
  - the lock takes the PIN by touch;
  - an app opens, and the shell swipes;
  - the on-screen keyboard works at its normal height;
  - Power locks and wakes;
  - `tools/phone-smoke` reads touch ok and buttons ok.
- **A second boot** comes up the same way.

## Risks

- **The touch supplies.** Powering the GT9895 at ABL's 3.3 V instead of stock's 3.0 V would put 0.3 V too much on it. The supplies are fixed at 3.0 V. Test 31 read them back in a boot with no consumer, before the chip was ever powered.
- **PMIC writes go through ACPM.** Only LDO4M's and LDO25M's selector and enable bits are written. The other S2MPG14 outputs keep firmware-owned selectors.
- **Slot B's tries.** Each step counts them, and resets with `--set-active=b` before they run out.
- **Nothing here writes outside slot B,** apart from module sets and one temporary modprobe file on `userdata`. Nothing reinstalls `userdata`.

## Open questions

- ~~Which Berlin IC?~~ A GT9895, from the stock firmware's header (M3.0), and the probe and 14-byte records confirm it (test 32).
- ~~The panel size?~~ 64 × 141 mm, the lit area measured with a ruler (test 35). Google's driver and stock's DPI say 70 × 149 mm, which is larger than the glass (#241's review).
- **Does touch survive a long idle with the screen off?** husky saw one failure on 2026-11-04. Not tried on akita.
- **The app-switcher disconnect** (below): once, not reproduced.

## Results

Test numbers continue from [BRINGUP-M2](BRINGUP-M2.md)'s.

### 2026-11-10: the touch chip and the buttons (M3.0, M3.1, gate f)

- **M3.0:**
  - **The kernel:** `omamobile` at `253208c11`, which has linux-omarchy-mobile#209.
  - **The chip:** F/'s vendor image carries `goodix_firmware_ak3a.bin` (215552 bytes) and `goodix_firmware_ak3b.bin` (231936 bytes), one per panel. Both start with the Berlin header `BERLIN` … `9895`, so the chip is a **GT9895**.
- **M3.1's kernel:** `7.3.0-rc6-omamobile-push1-g23120efb6488`: the buttons and the sleep default on `253208c11`, the same tree #238 merged.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 27 | `bin/omamobile modules-push`, then `bin/omamobile fastboot` and `flash` | 1825 modules installed for the new release, the old set kept. SSH 28 s after the flash. `running`, no failed units | The modules-push, fastboot, flash loop works on akita |
| 28 | Buttons and the sleep default | `gpio-keys` is `event0` with three interrupt lines. One short press of each: volume down 2 interrupts, volume up 2, power 4 (two presses, logind "Power key pressed short" twice). Power woke the screen through the lock. `/proc/cmdline` has `mem_sleep_default=s2idle`, and `/sys/power/mem_sleep` reads `[s2idle] deep`. No `exynos-clkout` lines. `tools/phone-smoke`: buttons ok, 2 known error lines, 0 new | **Gate (f) passed.** The mem_sleep default holds, and #209 fixes the clkout lines on the 8a too |

Slot B: 2 tries left.

### 2026-11-10 and 11: the touch supplies (M3.2)

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 29 | The S2MPG14 with LDO4M and LDO25M fixed at 3.0 V and 1.8 V, no setter | `touch-avdd: failed to apply 3000000-3000000uV constraint: -EINVAL`, then the regulator probe fails with -22. Nothing is enabled. A test-only kernel, with each rail's whole range (no setter, so no write) and `regulator_ignore_unused`, then read ABL's selectors: **LDO4M 3.3 V, LDO25M 1.8 V, both off** | The 9a-era driver can't set a voltage, and ABL leaves 3.3 V where stock runs 3.0 V |
| 30 | The PMIC's other function | `s5m-rtc s2mpg14-rtc: registered as rtc0` and `setting system clock to …` at 0.27 s, with the right time. No alarm, since the PMIC has no interrupt | **The phone keeps time across reboots** from M3.2 on |
| 31 | With #240's setter, the same 3.0 V and 1.8 V, no consumer | `touch-avdd: Bringing 3300000uV into 3000000-3000000uV`. The rails read back 3000000 and 1800000 uV, disabled, with 0 users. They were the same at 41 s, past the unused-regulator cleanup. The PMIC regmap has no cache, so that's the register | The setter and Google's table are right on hardware (#240's condition 1) |

Slot B: 2 tries left.

### 2026-11-11: touch (M3.3) and the session (M3.4, gate g)

The kernel: `omamobile` at `fc7086a68`, plus #240 and #241. Release `…g6063302504d6` for M3.3, `…g7b13e4166249` (adds stock's panel size) for M3.4, and `…g3933790300a1` (the measured size) for test 35.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 32 | The touchscreen, driver held back, then loaded by hand | **Before:** the rails read 3.0 V and 1.8 V, off. **After `modprobe goodix_berlin_spi`:** "Goodix Berlin Capacitive TouchScreen" on `spi0.0`, with the rails enabled at 3.0 V and 1.8 V. **The four corners** came in at (110,121), (1004,118), (118,2311) and (971,2298). **A swipe** down the middle ran from (528,824) to (564,1892). 842 interrupts, no checksum errors. The blacklist was then removed | **Touch works.** The chip is powered only after its supply was read at 3.0 V. No axis swap or inversion is needed |
| 33 | A reboot (`--set-active=b`) | The driver loads by itself at 3.6 s. `running`, no failed units. Hand tests: the PIN pad unlocks by touch, an app opens, the shell swipes, the on-screen keyboard types | Touch in the session |
| 34 | The panel size (the next boot, a flash) | Hyprland's monitor was 285 × 635 mm without the `panel0` node (simpledrm's 96 dpi guess), and the keyboard was tiny. With stock's 70 × 149 mm it's 70 × 149, and the keyboard is close to its normal height. Power locks and wakes. Closing an app from the app switcher works. `tools/phone-smoke` (main `c3cfd86`): every required row ok, touch ok, buttons ok, 2 known error lines, 0 new | **Gate (g) passed**, on a second boot of touch |
| 35 | The measured size (#241's review), a flash | The lit area measures 64 × 141 mm. With that in `panel0`, Hyprland reports 64 × 141 mm, and the keyboard is at its normal height, about 9 % taller than with 70 × 149. `running`, no failed units. `tools/phone-smoke` (main `2db3f2b`): every required row ok, touch ok, buttons ok, 0 new | The size is the glass's, not stock's |

Slot B: 2 tries left.

Findings:

- **The session is slow.** There's no GPU driver (no render node, so Hyprland and the shell render in software) and no cpufreq (the cores stay at ABL's rates). Both wait for akita's GPU and DVFS work, after husky's.
- **The app-switcher disconnect, seen once.** In test 33, closing an app from the app switcher made Hyprland log `error in client communication` for the shell. The shell logged `The Wayland connection experienced a fatal error: Invalid argument`, exited with 255, and its wrapper relaunched it a second later. There was no core dump, and Hyprland's log has nothing but its no-renderer messages. It didn't happen in test 34. That's userspace, and worth an issue if it comes back.
- **A lockout, seen once.** While the screen was being measured, the clipboard panel opened by accident. Then:
  - the session stopped reacting: swipes didn't close the panel or open the quick settings;
  - Power locked and woke the screen, but swiping up on the lock screen no longer showed the PIN pad;
  - the touches still reached the kernel (raw events recorded), but the lock screen got none;
  - closing the clipboard panel over SSH (`omarchy-shell shell hide omarchy.clipboard`) didn't help, and a reboot did.

  Opening the panel on purpose and locking over it unlocks normally, so the panel wasn't the cause. The journal has only leads, just before the lock:
  - three on-screen-keyboard keymap reloads (`xkbcomp`: "Virtual modifier Squeekboard multiply defined");
  - Qt text-input warnings ("Trying to disable … but … is focused").

  There was no crash or shell restart. That's userspace, and worth an issue if it comes back.
- **`dmesg -c` clears the kernel's ring buffer.** One read in M3.3 used it, so that boot's kernel log is only in the journal. Read with plain `dmesg` or `journalctl -k`.
- Slot B ended test 35 with 2 tries, after a `--set-active=b` reboot for the lockout and test 35's flash.
- The logs are private (`~/android/reference/akita-m3.*-2026111*/` and `akita-lockout-20261111/`). The goodix files from F/ are in `~/android/reference/akita-goodix-cp3a.261005.005/` and are never committed. M3.4's images and modules (with 70 × 149) are kept as `~/omamobile-kernel/known-good/akita-m3.4-g7b13e4166249`.
