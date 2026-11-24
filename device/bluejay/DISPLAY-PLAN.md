<!-- SPDX-License-Identifier: MIT -->
# Bluejay retained display

Status (2026-11-08): an actual Omarchy desktop renders at 1080x2400 on retained
simpledrm, approximately 60 Hz. Panfrost renders through a separate Mali-G78
node. Native panel/DSI modesetting remains unfinished.

The selected stock panel is Samsung S6E3FC3 Bluejay (`samsung,s6e3fc3_6a`),
not the Pixel 7 P10 variant handled by the existing similarly named driver.
Do not copy its reset, brightness or panel-command sequence without an audit.

Google's GS101 display source locates DECON0 at 0x1c300000. Its powered retained
path reported VERSION 0x06010000, GLOBAL_CON 0x133 and TRIG_CON 0x3070, with a
stationary frame counter. The qualified refresh operation changes only the
trigger mask/software-enable bits: TRIG_CON 0x3070 to 0x3061. It does not alter
DSI, panel reset, timing or brightness. Counter progress measured 60.06 Hz and
the owner observed numbered framebuffer alternation. The corrected whole-frame
readback matched all 10,368,000 bytes after stopping fbcon cursor repaint.

The installed hardware service restores this exact operation after USB SSH and
touch setup, under a persisted failure marker and deadline. The framebuffer is
1080x2400, stride 4320, 32 bpp. Never use the generic GS201 `tools/display-hz`
address unchanged on this GS101 board, and never sweep unpowered registers.

Aquamarine 0.16.0 needs the opt-in patch under `patches/` to avoid its unused
auxiliary EGL-device probe on display-only simpledrm. Without a GPU, Mesa GBM
software rendering works. With Panfrost, Aquamarine's existing sole-render-node
fallback pairs the separate GPU with simpledrm; no additional patch was needed.
See [GPU-PLAN](GPU-PLAN.md) for headless pixel and compositor results.

Before a new display test, announce the screen change, stream logs and require
the watchdog. Confirm the exact board/register state and touch/SPI health first.
Stop on a mismatch, loss of transport or new fault; recover with the retained B
images through the project helper. PMU registers are never accessed from userspace.

Sources: Google's Bluejay and GS101 display DT/driver at
`android-16.0.0_r0.9`, the owner's own captures and the upstream/project kernel.
