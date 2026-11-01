<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 (panther) display: DCS brightness, then flip-only KMS

Status (2026-11-01): G1, D1 and D2 passed (kernel: [linux-omarchy-mobile#177](https://github.com/derekross/linux-omarchy-mobile/pull/177), in review): the panel driver takes the panel over, and brightness and display off/on work over DCS, including from the shell's slider. device-panther 0.1.4 ships `allow_tx=1` (installed; its first boot is still to come). Next: D3 (flip-only KMS).

Today the Pixel 7 shows the bootloader's framebuffer through simplefb and
simpledrm: no brightness control, no screen off, no vsync. The Pixel 7 Pro
solved the same with three drivers on top of the pipeline ABL leaves
running (device/cheetah/DISPLAY-PLAN.md):

- **`gs-dsim-cmd`**: a MIPI DSI host on DSIM0 that sends DCS packets through
  the DSIM FIFOs, interleaved with frames. It sends only with `allow_tx=1`.
- **A panel driver** that takes the running panel over and sends nothing
  until the brightness or the power state changes.
- **`gs-decon`**: flip-only KMS that keeps ABL's DECON, DSIM and DSC
  configuration, flips DPP0 between buffers, reports frame starts as
  vblanks, and replaces simpledrm.

This plan brings them to panther, one change per boot. The display path
and DSIM are the same as the Pixel 7 Pro's. The panel is different, and
so is the size.

[V] is verified on this phone or in the source; [I] is inferred.

Every gate keeps the last good image set and its modules for its Rollback:
the previous kernel's images are kept beside the new build, and its
modules stay on the phone until `linux-modules-cleanup` moves them.

## What is known

| Fact | Evidence |
| --- | --- |
| ABL leaves DECON0 → DSIM0 → panel running in command mode, with DPP0 scanning 0xfac00000 | BRINGUP-M1.md, first light [V] |
| The panel is the Samsung S6E3FC3 "P10": compatible `samsung,s6e3fc3-p10` under DSIM0's `panel@0`, and stock's command line names `sdc-s6e3fc3-p10` | stock live DT and `/proc/cmdline` [V] |
| Reset on gpa7-1, as on the Pixel 7 Pro; supplies vci (S2MPG12 LDO27M) and vddi (S2MPG13 BUCKA), as in Google's `gs201-panther-display.dtsi`; TE on DSIM0's `te-gpio` | stock live DT [V] |
| 1080x2400, 66x146 mm, 60 and 90 Hz (plus a 30 Hz AOD mode); DSC with two 540x48 slices, 8 bpc, 8 bpp; four lanes, non-continuous clock | Google's GPL `panel-samsung-s6e3fc3-p10.c` (`kernel/google-modules/display/samsung`, branch `android-gs-pantah-6.1-android16`) [V] |
| Brightness is DCS 0x51 with an 11-bit value MSB first: 4-2047 normal, 2048-4095 HBM, default 1023 | the same driver and its common `exynos_panel_set_brightness()` [V] |
| Cold init: sleep out (120 ms), TE on, column and page address, then level-2 registers (TE width, FQ CON, V-total, source, LTPS, EM off), 60 Hz (0x60 0x00), TE2, DSC on with the vendor PPS, MIC off (0xc2 0x14), DSC decoder on (0x9d 0x01), WRCTRLD 0x20, display on | `s6e3fc3_p10_enable()` and `s6e3fc3_p10_init_cmds` [V] |
| `gs-dsim-cmd` works with any panel; it switches the refresh rate only on a link it has timers for, so on panther it stays at 60 Hz | `drivers/gpu/drm/google/gs-dsim-cmd.c` (`gs_dsim_rates[]`) [V] |
| `gs-decon` on gs201 offers only the Pixel 7 Pro's 1440x3120 modes, and refuses to run when ABL's size differs | `gs-decon.c` (`gs201_decon_data`, the size check at probe) [V] |
| The DSI command path, the panel driver and `gs-decon` are modules autoloaded from the DT; `allow_tx` and `screen_off` are set by the Pixel 7 Pro's device package | `kernel/configs/omamobile.config`, `omamobile-device-cheetah` `modprobe.d/omamobile-display.conf` [V] |

## The changes ([linux-omarchy-mobile#177](https://github.com/derekross/linux-omarchy-mobile/pull/177))

1. `dt-bindings: display: panel: add Samsung S6E3FC3 P10`.
2. `drm/panel: add Samsung S6E3FC3 command-mode panel`. It follows the
   Pixel 7 Pro's S6E3HC4 driver:
   - **Takeover.** At probe, if reset reads released, the driver holds the
     supplies and leaves the line alone.
   - **Brightness.** A backlight device over DCS 0x51, 4-2047.
   - **Blanking.** It turns the display off with the panel out of sleep.
   - **Cold path for KMS.** Prepare runs the reset and Google's init at
     60 Hz, enable sends display on, disable display off, and unprepare
     sleep in and reset.
   - **Left out:** local HBM (it needs panel reads), AOD and the panel
     revision reads. Only EVT1 and later panels are covered.
3. `arm64: dts: ... gs201-panther: add the DSI command path to the panel`.
   It enables `cmu_disp`, `cmu_dpu` and `dsi0` with the panel node. DECON0
   stays disabled.

`CONFIG_DRM_PANEL_SAMSUNG_S6E3FC3=m` goes into `kernel/configs/omamobile.config`.

Later, for D3: `gs-decon` picks its mode table by the size ABL left (adding
the S6E3FC3's 1080x2400 timings), panther's DT gets DECON0 with a
`display_pool`, and device-panther gets the `modprobe.d` options.

## Gates

### G1. The new `omamobile` base alone (low risk)

`omamobile` moved from b0d62d9e7 to caf5f8a2b. It brought #166 and #167,
which are already in kernel F, and also gs201's ACPM TMU, thermal zones,
CPU DVFS and cooling. Kernel G1 is the same feature set as F on that base:
#133, #171 and #170 merged. It changes nothing in the display path. Flash
it through fastboot (slot B is at 1 retry).

**Pass:**
- Touch, GPU, haptics, battery and the USB rescue are as on F.
- The thermal zones read sensible temperatures.
- cpufreq lists its policies, with no ACPM errors.

**Stop if:** the phone resets, ACPM errors, or thermal throttling at idle.
**Rollback:** fastboot (Power + Volume Down), then flash kernel F's image
set, whose modules are still on the phone.

### D1. DSI command path, read-only (low risk)

Kernel G2 = G1 + the display branch. Modules first, then a push.

**Pass:**
- `gs_dsim_cmd` and `panel_samsung_s6e3fc3` bind, and the panel logs
  "taken over from the bootloader".
- `/sys/class/backlight/*` exists.
- **The screen keeps showing the desktop**: nothing is sent, because
  `allow_tx` is 0.
- simplefb and simpledrm stay in charge.
- No DSIM errors in `dmesg`, and everything else is as on G1.

**Stop if:** the screen blanks or freezes. **Rollback:** fastboot, then
flash G1's image set (its modules stay on the phone); USB and SSH don't
depend on the screen.

### D2. DCS brightness (low-medium risk; the screen changes)

On the running G2: `echo 1 > /sys/module/gs_dsim_cmd/parameters/allow_tx`.
Then:
1. Write the brightness at 1023 (the default), then 400, 2047 and 4.
2. Blank the backlight (`bl_power` 4), then unblank it (0).

Announce each step before running it.

**Pass:** the screen dims and brightens at each step, turns off when
blanked and comes back when unblanked, with the picture intact, and there
are no DSIM timeouts.

**Stop if:** the picture breaks or stays dark after unblank. **Rollback:**
`allow_tx=0` stops further packets; a reboot restores ABL's state.

On a pass, device-panther ships `options gs_dsim_cmd allow_tx=1`, and the
shell's brightness slider drives the backlight.

### D3. Flip-only KMS (medium-high risk; staged)

`gs-decon` with the S6E3FC3 modes at 60 Hz, in three stages:
- **Stage 0:** log DECON and DPP0, read-only.
- **Stage 1:** count frame starts. The measured rate should be about 60 Hz.
- **Stage 2:** take the screen over from simpledrm, then test DPMS off/on
  and the panel sleep (`screen_off=2`).

Each stage is its own boot or module reload. The plan gets its own
runbook before D3 starts, with a Rollback for each stage: D2's image set
by fastboot, and `gs_decon` blacklisted so that simpledrm keeps the
screen.

### D4. 90 Hz (medium risk)

DSIM timers for panther's link in `gs_dsim_rates[]`, and the panel's
0x60 0x08. Written after D3.

## Results

### 2026-11-01: G1

Kernel `7.3.0-rc6-omamobile-push1-g53710bb094e3` (`omamobile` caf5f8a2b with
#133, #171 and #170), flashed after its modules:

- **Thermal:** `gs101-acpm-tmu` registered 6 thermal zones (big, mid,
  little, GPU, ISP, TPU). They read 44-52 °C just after boot and 49-50 °C
  20 s later. Every cooling device was at state 0.
- **cpufreq:** three policies (0, 4, 6) on `schedutil`, at 300-1803,
  400-1999 and 500-2252 MHz.
- **Unchanged from F:** ACPM 14 of 15 channels, touch, GPU, haptics, the
  battery and the USB rescue.
- **New warning:** `cpu cpuN: EM: invalid perf. state: -22` on the three
  clusters, from the new CPU DVFS. It is still there on D1.
- **The gauge reloaded its model** at this boot (`battery model loaded`),
  so it had been in POR: this was the first boot after a stop in fastboot,
  and pushed reboots haven't done that.

The phone was then put in fastboot before D1's modules were on it, so G1
was flashed again and booted the same way.

### 2026-11-01: D1

Kernel `7.3.0-rc6-omamobile-push1-g54fb87ae5295` (G1 plus the display
branch), pushed after its modules:

- `gs_dsim_cmd` and `panel_samsung_s6e3fc3` bound. The panel logged
  "taken over from the bootloader", attached with 4 lanes and mode flags
  0x400 (non-continuous clock), and its supplies are dummies.
- `/sys/class/backlight/1c2c0000.dsi.0`: 1023 of 2047, `bl_power` 0,
  `allow_tx` N. simpledrm kept the screen (`card0`), and **the screen looked
  the same**.
- **ABL's DSIM:** VERSION 0x02060000, DPHY_STATUS 0x10f, CLK_CTRL
  0x06131f04, CONFIG 0x04887cff, CMD_TE_CTRL1 0x2a82306d, UNDERRUN_CTRL
  0x1cf8. The underrun isn't in `gs_dsim_rates[]`, so the driver logs "no
  rate switching" and stays at 60 Hz.
- No DSIM errors. Everything from G1 still works.

### 2026-11-01: D2

On the running D1 kernel, with `allow_tx` set to 1:

| Step | Seen on the phone |
| --- | --- |
| brightness 1023 | a little brighter than ABL left it |
| 400 | darker |
| 2047 | clearly brighter |
| 4 | very dark, still visible |
| `bl_power` 4 | display off |
| brightness 1023, then `bl_power` 0 | back on, picture intact, touch working |

Each write returned 0, and `actual_brightness` followed. There were no DSIM
timeouts or errors in `dmesg`. **The shell's brightness slider then
drove the panel** through the backlight device.

device-panther 0.1.4 was then installed on the running D1 kernel (no
reboot): `modprobe -c` lists `options gs_dsim_cmd allow_tx=1` from
`/usr/lib/modprobe.d/omamobile-display.conf`. Whether `allow_tx` reads Y
by itself is checked at the next boot.
