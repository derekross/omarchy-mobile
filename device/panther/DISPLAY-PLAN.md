<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 (panther) display: DCS brightness, then flip-only KMS

Status (2026-11-01): G1, D1, D2 and D3 passed. Brightness and display off/on work over DCS ([linux-omarchy-mobile#177](https://github.com/derekross/linux-omarchy-mobile/pull/177), merged), and gs-decon drives the screen: Hyprland flips at 60 Hz, DPMS off stops the frames and puts the panel to sleep, and the panel's cold init wakes it ([linux-omarchy-mobile#181](https://github.com/derekross/linux-omarchy-mobile/pull/181), in review). device-panther 0.1.5 ships `screen_off=2`, and the bring-up file is gone. Next: D4 (90 Hz).

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

**The changes** ([linux-omarchy-mobile#181](https://github.com/derekross/linux-omarchy-mobile/pull/181)):
1. `drm/panel: samsung-s6e3fc3: support sleep and a cold restart from KMS`.
   A panel taken over from the bootloader is marked prepared and enabled,
   so gs-decon's `drm_panel_disable()`/`unprepare()` reach it. While the
   panel is asleep, backlight changes are only recorded, and the panel's
   lock covers every command sequence. This mirrors the S6E3HC4 change.
2. `drm: google: gs-dsim-cmd: recognise the Pixel 7's link`. The
   bootloader's 60 Hz pair (UNDERRUN_CTRL 0x1cf8, CMD_TE_CTRL1 0x2a82306d,
   read in D1) gets no second rate, so gs-decon gets the link and the panel
   but never switches the rate.
3. `drm: google: gs-decon: pick the modes by the bootloader's scanout size`.
   Each SoC gets a list of mode sets, one per panel, chosen by the size ABL
   scans out. gs201 gains the S6E3FC3 P10 at 1080x2400, 60 Hz.
4. `arm64: dts: ... gs201-panther: enable DECON0 for gs-decon`. DECON0
   gets a `display_pool` (0x3800000, five 1080x2400 XRGB8888 buffers, below
   4 GiB, reusable) and the boot framebuffer.
5. `drm: google: gs-decon: scan out padded rows on gs201 too`. This one was
   found in D3c: buffers allocated for 1080-pixel rows are padded to 64
   bytes (pitch 4352), and gs201 only took the boot pitch (4320).

**Kernel D3** = D1 plus that branch. It is built
(`7.3.0-rc6-omamobile-push1-gdc3f0ce5e425`), and D1's image set is kept as
its rollback.

Without a module option, gs-decon goes straight to stage 2 at boot. So the
first boot holds it at stage 0 with a bring-up file on the phone,
`/etc/modprobe.d/omamobile-display-bringup.conf`:
`options gs_decon stage=0`. That file is deleted once D3 passes (AGENTS.md §2).

#### D3a. Stage 0, read-only (low risk)

**Before the boot:**
1. Write the bring-up file.
2. `modules-push` D3.
3. Fastboot (Power + Volume Down), then flash D3. The flash puts slot B
   back at 3 retries.

**Pass:**
- **0.1.4 at boot:** `allow_tx` reads Y with no hand-written option, and
  the slider changes the brightness.
- `gs_decon` binds and logs DECON0 and DPP0 as ABL left them: command
  mode, 1080x2400, DPP0 at 0xfac00000. It also logs "link timers for
  60 Hz" from gs-dsim-cmd.
- simpledrm still owns `card0`, and the screen looks as before.

**Stop if:** "unexpected scanout size", "DPP0 scans …", or a DSIM error.
**Rollback:** stage 0 changes nothing, so keeping the bring-up file is
enough to go on with simpledrm; otherwise flash D1's set by fastboot.

#### D3b. Stage 1, frame count (low risk)

On the running D3 kernel: `rmmod gs_decon; modprobe gs_decon stage=1`.

**Pass:** the frame start and frame done interrupts count at about 60 per
second (the driver's `stats` in sysfs and `/proc/interrupts`), with no
interrupt storm. The screen is unchanged.

**Stop if:** a storm warning, or the count is far from 60.
**Rollback:** `rmmod gs_decon`.

#### D3c. Stage 2, KMS (medium-high risk; the screen goes through gs-decon)

Hyprland runs on simpledrm, and taking its device away at runtime would
end the session. So stage 2 comes with a reboot:
1. Change the bring-up file to `options gs_decon stage=2 screen_off=0`.
2. Push or reboot. Slot B goes from 2 retries to 1.

**Pass:**
- gs-decon registers its DRM device, and simpledrm goes away (the aperture
  is handed over).
- Hyprland and the Omarchy shell come up on gs-decon at 1080x2400, 60 Hz.
- Touch, the brightness slider and animations work, and vblank events
  arrive (`modetest` or Hyprland's frame timing).
- There are no flip timeouts.

**Stop if:** a black or frozen screen, flip timeouts, or Hyprland failing
to start.
**Rollback:**
- over SSH, set the bring-up file back to `stage=0` and reboot;
- or flash D1's set by fastboot.

USB and SSH don't depend on the screen.

#### D3d. Screen off (medium risk; the screen turns off and on)

On D3c, with Hyprland's Lua dispatchers (AGENTS.md: `hl.dsp.dpms({ action
= "disable" })`, then `"enable"`):
1. `screen_off=0`: DPMS off sends black frames, and DPMS on shows the
   desktop again.
2. `screen_off=1`: DECON stops sending frames while dark.
3. `screen_off=2`: the panel goes to sleep (display off, sleep in, reset)
   and wakes through the panel driver's cold init (reset, Google's init at
   60 Hz, TE2, DSC). **That cold init has never run before this step.**

Announce each step before running it. On a pass of `screen_off=2`,
device-panther ships `options gs_decon screen_off=2`, and the bring-up file
goes.

**Stop if:**
- the screen stays dark after DPMS on;
- the picture is scrambled after the cold init, which would point to the
  DSC or PPS;
- a DSIM timeout.

**Rollback:** `screen_off=0` (written at runtime) avoids the panel sleep. A
reboot restores ABL's state.

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

### 2026-11-01: the package's boot

Booted from a fastboot flash (so it didn't spend slot B's last try), on
kernel `7.3.0-rc6-omamobile-push1-gdc3f0ce5e425` with device-panther 0.1.4
installed:

- `/sys/module/gs_dsim_cmd/parameters/allow_tx` read `Y` with no
  hand-written option, and the shell's slider changed the brightness.
- On a later boot, `ls /etc/modprobe.d` listed only `hid_apple.conf` (no
  hand-made `omamobile-display.conf` hiding the package's file), and
  `allow_tx` read `Y`.

### 2026-11-01: D3

**D3a, stage 0.** Kernel `7.3.0-rc6-omamobile-push1-gdc3f0ce5e425` (D1
plus the D3 branch's first four commits), flashed after its modules with
the bring-up file at `stage=0`:
- **0.1.4 at boot:** `allow_tx` read Y with no hand-written option, and the
  slider worked.
- **gs-dsim-cmd** logged "link timers for 60 Hz".
- **gs-decon bound** (so the 1080x2400 mode set matched) and logged
  GLOBAL_CON 0x133 (command mode), TRIG_CON 0x3061 (TE trigger on),
  RDMA_IMG_SIZE and SRC_SIZE 0x09600438 (1080x2400), and DPP0 at
  0xfac00000.
- simpledrm kept `card0`, and the screen was unchanged.

**D3b, stage 1.** After `rmmod gs_decon; modprobe gs_decon stage=1`: 601
frame starts and 601 frame dones in 10.0 s, **60.02 Hz**, with no storm. MIF
was at 2028 MHz and DISP at 400 MHz. The screen was unchanged.

**D3c, stage 2, first try.** The bring-up file was set to `stage=2
screen_off=0`, then a reboot:
- gs-decon took the screen over: simpledrm went, `card2` is gs-decon, and
  it reported "flip-only KMS on DECON0, 1080x2400, up to 60 Hz".
- **Every Hyprland modeset failed with -EINVAL**, and the screen froze on
  the boot console's last line. DRM's debugfs showed why: Hyprland's
  framebuffers had a pitch of 4352 (1080 pixels padded to 64 bytes), where
  gs201's plane check took only the boot pitch, 4320. The Pixel 7 Pro's
  1440-pixel rows (5760 bytes) need no padding.
- **Fix:** gs-decon's fifth commit lets gs201 take padded rows, as G4 does.
  DPP0's source width is the row length in pixels, and on gs201 the
  source height shares that register.

**D3c, stage 2, with the fix.** Kernel
`7.3.0-rc6-omamobile-push1-g53fab72d1489`, flashed after its modules:
- Hyprland's modesets all passed, and `hyprctl monitors` showed
  1080x2400@60.00000.
- **The desktop showed, and it was smooth.** In the first ~37 s there were
  162 flips with no timeouts and no late flips, and flip latency averaged
  12.2 ms (16.5 ms at most). Frame start ran at 59.96 Hz.
- 10 minutes later: 2624 flips, still no timeouts (8.9 ms on average).

**D3d, screen off,** with Hyprland's DPMS dispatcher, each step seen on the
phone:

| `screen_off` | While off | After DPMS on |
| --- | --- | --- |
| 0 | black frames (frames still counted) | desktop back |
| 1 | no frames (frame_start unchanged over 3 s), trigger masked | desktop back |
| 2 | no frames, trigger masked, **panel asleep** | **panel cold init**, desktop back with the picture correct |

With `screen_off=2`, the power key's lock turned the screen off, a tap woke
it, and the PIN could be entered. There were no DSIM timeouts, no "cold
init failed" and no gs-decon errors (`dmesg` was cleared before the
`screen_off=2` step).

**0.1.5 with no bring-up file.** device-panther 0.1.5 was installed on
the phone, the bring-up file deleted, and the phone rebooted on the same
kernel. After the reboot:
- `allow_tx`, `stage` and `screen_off` read Y, 2 and 2 from the package
  alone, and gs-decon owned the screen.
- Hyprland ran at 1080x2400@60 (163 flips, no timeouts, frames at
  59.99 Hz), and the desktop was smooth.
- The slider worked. The power key's lock turned the screen off, a tap
  turned it on, and the PIN could be entered.
