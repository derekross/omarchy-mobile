<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): display driver

Status (2026-10-15): **D3 and D6 pass: gs-decon runs the display at 120 Hz**
(60 Hz available),
with the G78 rendering straight to scanout and no CPU copy. The cause of
D3-D3g was the panel rails: the simple-framebuffer node holds vci (ldo22m)
and vddi (bucka), and removing simpledrm released them. Brightness and
display off/on go through the S6E3HC3 driver (gs-dsim-cmd). Next: the
panel's idle auto mode (down to 10 Hz on static content). Kernel branch
`omamobile-gs101-display`.


**2026-10-15: no more phantom simpledrm output** (`omamobile-gs101-display`
`3b3915975`, kernel `g58ea90ae478d`). gs-decon evicted simpledrm from the
boot framebuffer, but simpledrm probed about 30 ms after gs-decon registered
(on every raven kernel so far), found the aperture free and stayed: `card2`
with an `Unknown-1` connector that Hyprland drove as a second, invisible
monitor beside the panel. gs-decon now also acquires the range after the
eviction; simpledrm then fails (`could not acquire memory range … -16`),
there is no `card2`, and Hyprland lists only DSI-1 (120 Hz). Rotation is a
transform change with a single blink, as on cheetah: Hyprland has no
rotation animation.
## 1. Approach

Port cheetah's flip-only KMS driver (`device/cheetah/DISPLAY-PLAN.md`), from
the integration snapshot `ebe48386d`:

- `drivers/gpu/drm/google/gs-decon.c` (1425 lines);
- `gs-dsim-cmd.c` (571);
- `gs-dsim.h`.

It keeps the display that ABL brought up (DECON0 -> DSIM0 -> panel, DSI
command mode, DSC). It only points DPP0's DMA at new buffers, counts frame
starts as vblanks, and (later) sends panel commands for brightness and
screen-off. Its register layout comes from Google's `cal_9845`, which is
gs101's own (raven's `soc_id` is 0x9845), so the driver code should need
compatibles and DT data, not new register logic.

## 2. Facts

`G/` is Google's raviole device tree (`gs101-drm-dpu.dtsi`,
`gs101-raven-display.dtsi`); `C/` is cheetah's `gs201.dtsi` at `ebe48386d`.

| Block | gs101 (raven) | gs201 (cheetah) | Source |
| --- | --- | --- | --- |
| DECON0 main | `0x1c300000` (0x6000) | `0x1c240000` | G/drm-dpu:237 |
| DPP0 DMA | `0x1c0b0000` (0x1000) | same | G/drm-dpu:20 |
| DSIM0 | `0x1c2c0000` (0x300), D-PHY `0x1c2e0100` (0x700), PHY bias `0x1c2e0000` (0x100) | same | G/drm-dpu:176 |
| DECON0 IRQs | frame_start 338, frame_done 337, extra 336 | 241, 240, 239 | gs101 IRQ header (SPI = header number on gs101) |
| DSIM0 IRQ | 345 | 250 | same |
| ACPM DVFS floors | `GS101_CLK_ACPM_DVFS_MIF` (0), `_DISP` (12) | MIF, DISP | `google,gs101-acpm.h` |
| Panel | Samsung S6E3HC3 (`samsung_s6e3hc3: panel@0`) | S6E3HC4 | G/raven-display:10 |

The DECON trigger that our initramfs writes (`0x1c300030`, from pmOS)
sits inside DECON0's main block, which matches.

## 3. Differences to handle

- **Compatibles:** `google,gs101-decon` and `google,gs101-dsim` (and their
  bindings), DT nodes in `gs101.dtsi`, disabled; raven enables them.
- **Panel:** stages 0-2 never talk to the panel. Brightness, screen-off
  and the 60/120 Hz switch need a S6E3HC3 driver. Cheetah's
  `panel-samsung-s6e3hc4.c` (812 lines) is the template. The command sets
  come from Google's GPL `panel-samsung-s6e3hc3.c`, which still has to be
  fetched.
- **Refresh rate:** keep raven at ABL's mode (60 Hz) until the panel
  driver exists. (Done since: the S6E3HC3 driver runs 120 Hz, D6.)

## 4. Runbook (each step gated; read-only first)

| Step | What | Expect / pass | Stop if | Risk |
| --- | --- | --- | --- | --- |
| D0 | Offline: import the three files, add the gs101 compatibles, bindings and DT; build, checkpatch, `dt-validate` | Builds clean | - | none |
| D1 | `gs_decon stage=0` by hand (blacklisted at boot), kmsg streamed | Logs DECON/DPP0 state: running, 1440x3120, DPP0 address = simplefb base | any abort or hang | low (reads of a powered, clocked block) |
| D2 | `stage=1`: frame-start IRQ counting | `stats` shows about 60 Hz while the screen updates | IRQ storm, no counts | low |
| D3 | `stage=2`: KMS takes over from simpledrm, session restarted (**screen announced**) | Hyprland on the gs-decon card, the G78 rendering straight to scanout, no copy | black screen past 30 s: rmmod, simpledrm comes back at the next boot | medium |
| D4 | The S6E3HC3 panel driver, brightness only (`allow_tx`) | `brightnessctl` works | no answer from the panel | medium |
| D5 | Screen off/on (DPMS), power key | Panel off, wakes on the power key | panel stays off: reboot | medium |
| D6 | 120 Hz | `tools/display-hz` reads about 120 | flicker | medium |

Rollback for every step: the module is blacklisted at boot until D3 has
passed, so a reboot returns to simpledrm.

## 5. Results

- **D0 (2026-10-14):** branch `omamobile-raven-display` (`a79db1c9b`):
  cheetah's gs-decon, gs-dsim-cmd and `drm_panel_set_refresh_rate()`
  imported unchanged, gs101 compatibles, DT. Builds clean; checkpatch has
  no errors. dt-validate not run: the build container has no dtschema.
- **D1 (2026-10-14, `7.3.0-rc6-omamobile-push1-ga79db1c9b027`):**
  `modprobe gs_decon stage=0`, with kmsg streamed and the watchdog fed.
  - DECON0 VERSION `0x06010000`, GLOBAL_CON `0x133` (on, command mode),
    frame counter running, TRIG_CON `0x3061` (our initramfs's write).
  - DPP0 scans 1440x3120 (`0x0c3005a0`) from `0xfac00000`, the boot
    framebuffer.
  - DSIM0 in command mode with TE control; 60 Hz link timers.
  - No errors or aborts. The display pool sits at
    `0xf2c00000`-`0xf87fffff` (below 4 GiB).
- **D2 (2026-10-14, same kernel):** `stage=1`: 363 frame starts in 6.02 s
  (60.3 Hz) on SPI 338/337, `frame_done` one behind; `hw_te_cnt` advancing.
  ACPM left MIF at 2028 MHz and DISP at 400 MHz. No storm, no errors.
- **D3 (2026-10-14, `g9831e5bc64ba`): fails.** gs-decon waited for a panel
  on the DSIM port (no S6E3HC3 driver), so raven's DTB drops the port: "no
  DSIM on the output port: 60 Hz only". The takeover itself works
  (simpledrm gone, Hyprland on card2 with the G78), but after one frame
  start the display stalls:
  - `SHD_REG_UP_REQ` stays `0x8010003f`;
  - `hw_te_cnt` and the frame counter freeze;
  - every flip times out, and the panel goes dark.

  Restored by rebooting: gs-decon is blacklisted at boot.
  - D3a: the DPU SysMMU (`0x1c100000`, VERSION `0x80200001`) has CTRL `0`,
    so it is off and DPP0 reads physical addresses, as on cheetah.
  - D3b: with `keep_argb=1` (no XRGB8888 switch) it stalls the same way.
    The black frame from the boot framebuffer goes out; the first flip to a
    `display_pool` buffer (`0xf2c00000`+) does not.

  Suspect: DPP0 may read only the bootloader's splash region (an S2MPU, or
  a TZ memory filter, set by ABL). **Next:** check gs101's DPU S2MPU and
  Google's `cont_splash`/DPU memory setup; try a scanout buffer inside a
  larger boot framebuffer carve-out.
- **D3a+ (same day):** the DPU0 S2MPU (`0x1c160000`, VERSION `0x11000001`)
  has CTRL0 `0`, so it is off. DPP0 is on AXI port 0 (Google's DT), whose
  SysMMU and S2MPU are both off. `display_pool` overlaps no stock
  reserved region except the modem's 4 KiB mailbox at `0xf6200000`.
- **D3c:** flips requesting only GLOBAL + window 0 (`shd_req=0x80000001`)
  stall the same way, so the compressor bit is not the cause either. In
  every attempt `frame_start` stays at 1-2 and `flips` at 0: the stall
  comes with the first shadow update, possibly before any flip to our
  buffers.
- **Next:** compare with Google's gs101 `cal_9845` DECON command-mode
  commit (shadow update, trigger, DSIM side), offline, before another
  try on the phone.
- **cal_9845 comparison (Google's GPL `decon_reg.c`, raviole android14):**
  - Same SHD_REG_UP_REQ bits (GLOBAL | CMP for DECON0, windows `0x3f`)
    and the same TRIG_CON mask/unmask as gs-decon.
  - The boot TRIG_CON `0x3061` is HW_TRIG_EN with DECON unmasked.

  Hypothesis: ABL programmed the active registers and left the shadow
  copies (DECON main `+0x800`, DECON_WIN `0x1c310000`, DECON_WINCON
  `0x1c330000`, DPP `+0x400`) stale, so the first update latches them and
  stalls. **D3d (read-only):** dump shadow next to active at stage 0.
- **D3d (read-only):** active vs shadow registers.
  - DECON main and DPP0 shadows match, apart from status bits.
  - ABL scans out through **window 5**: WINCON5 `0x1` (enabled, channel 0
    = DPP0), WIN5 end `0x0c2f059f` (1439,3119), the same in both copies.
  - Only `WIN_SECURE_CON` (`WIN n + 0x0`) differs: active `1`
    (non-secure), shadow `0`, on all six windows. Google's driver never
    writes it, so it is most likely unshadowed and reads 0.

  The shadow hypothesis is mostly ruled out. **Next (D3e):** take over
  once more and, while stalled, read INT_PEND/INT_PEND_EXTRA, GLOBAL_CON
  run/idle and SHD_REG_UP_REQ before rebooting.
- **D3e (2026-10-14):** the takeover again, with DECON and DPP0 read while
  stalled.
  - The frame counter ran on for about 230 frames after the takeover (the
    black frame from the boot framebuffer). It froze as Hyprland's first
    frame pointed DPP0 at `0xf3e00000` (`display_pool`).
  - While stalled: INT_PEND and INT_PEND_EXTRA are 0, GLOBAL_CON `0x133`
    (run + idle), SHD_REG_UP_REQ `0x8010003f` pending, `hw_te_cnt`
    frozen, DPP0 status unchanged.

  So DPP0's reads from the pool hang silently, while reads from the boot
  framebuffer at `0xfac00000` work. The SysMMU and S2MPU are off, so a
  DRAM-side filter probably limits the DPU master to some ranges.
  **Next (D3f):** move `display_pool` (`alloc-ranges`) out of the
  3.75-4 GiB carve-out area, for example to 0xa0000000-0xdfffffff, then
  repeat the takeover.
- **D3f (`g2c95d46a6603`):** `display_pool` moved to `0xda400000`: the
  same stall (DPP0 at `0xda400000`, flips 0). The range is not the cause.
  New hypothesis: `WIN_SECURE_CON` is shadowed after all. The first update
  latches the shadow `0` (secure) into window 5, and DPP0 then fetches as
  secure: it reaches the boot framebuffer but hangs on ordinary memory.
  This fits D3-D3f. **Next (D3g):** write `1` (non-secure) to
  `WIN_SECURE_CON(5)` at `0x1c315000`, check that its shadow reads 1, then
  take over.
- **D3g:** wrote `1` to `WIN_SECURE_CON(5)` (`0x1c315000`). Active
  stayed `1` and shadow `0`, and the takeover stalled the same way:
  either the secure world owns the register or its shadow reads 0.
  Open leads:
  - (a) Google's `samsung,tzmp` on DECON0, i.e. how stock tells the secure
    world that a window is non-secure;
  - (b) a DRAM-side filter (TZASC) that lets the DPU master read only the
    splash carve-out;
  - (c) scan out from a buffer inside a larger `cont_splash` carve-out
    (a stop-gap that would still remove simpledrm's copy).
- **D3 passes (2026-10-15, `gaca15175c4cb`):**
  - DPP0's `RDMA_MST_SECURITY` read 1, which means non-secure; an
    SMC_PROTECTION_SET enable/disable pair left it 1, so security was not
    the cause.
  - By hand with simpledrm running, DPP0 pointed at ordinary RAM
    (`0xf9800000`) and switched to XRGB8888 kept 48-61 frames/s.
  - The difference was simpledrm's removal: its node holds the panel's
    `vci-supply` (`s2mpg10_ldo22m`) and `vddi-supply` (`s2mpg11_bucka`).
    With both `regulator-always-on`, the takeover runs 60 Hz with 49 flips
    taken and no timeouts; Hyprland is on card2 (gs-decon).
  - gs-decon loads at boot now.
- **D6 passes (2026-10-15):**
  - The S6E3HC3 switches rate with the vendor's manual mode: F0 5A 5A,
    BD 21, 60 00 (120 Hz) or 60 01 (60 Hz), F7 0F, F0 A5 A5.
  - Raven's DSIM link timers at boot equal cheetah's 60 Hz entry
    (TE_CTRL1 `0x33eb3b26`), so its 120 Hz entry is reused.
  - With DECON0-DSIM0 linked again and `max_refresh=120`, Hyprland chose
    1440x3120@120: 124 frames/s, no late flips, no timeouts, no underruns.
    "Super smooth" on the phone. 120 Hz is the boot default.
  - gs-decon raises the MIF floor to 1352 MHz at 120 Hz. Since
    `fcf2e17da808` it puts MIF back to its probe-time rate (1014 MHz) when
    the CRTC drops to 60 Hz on screen off; read 1014 MHz with the display off.
