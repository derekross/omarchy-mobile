<!-- SPDX-License-Identifier: MIT -->
# Bluejay GPU bring-up

Status (2026-11-08): G1 headless rendering and the accelerated Omarchy desktop
pass. The owner confirms unlocking, opening an app and scrolling with correct
display and normal response. A subsequent normal reboot independently passed
automatic GPU, touch, Wi-Fi and desktop startup. Native panel modesetting remains separate: presentation still
uses the retained simpledrm framebuffer.

## Source and initial state

- Running kernel: `7.3.0-rc6-omamobile-bluejay-input-gated0`, built in
  `~/android/mainline/out-bluejay-input-20261107` from
  `~/android/mainline/wt-bluejay-input-20261107`. Keep those frozen.
- Its Panfrost already matches `google,gs101-mali`, identifies G78 and forces
  AArch64 page tables. See [raven's results](../raven/GPU-PLAN.md); those results
  establish driver provenance, not Bluejay qualification.
- The installed Mesa is `1:26.2.4-1.4`; its project build includes the G78 model.
  At the initial audit Bluejay's GPU node was disabled, no render node existed,
  and the GPU modules were absent from the installed tree. Software rendering
  was explicit in the session environment.
- GS101's GPU node defines its own job/MMU/GPU interrupts (420/421/419), register
  range and ACPM clock. G1 retains them. The four supplies follow Google's
  `gs101-pmic.dtsi`, included by Bluejay's own board source: BUCK2S (G3D),
  BUCK8S (G3D L2), LDO1S (G3D memory), BUCK7M (internal memory).

Sources: the exact local kernel sources above and the owner's already retrieved
[Google GS101 device sources](https://android.googlesource.com/kernel/devices/google/gs101/+/refs/tags/android-16.0.0_r0.9/dts/gs101-pmic.dtsi),
plus [Bluejay PMIC overrides](https://android.googlesource.com/kernel/devices/google/bluejay/+/refs/tags/android-16.0.0_r0.9/dts/gs101-bluejay-pmic.dtsi).

## G1: bounded driver and headless rendering qualification

`overlays/gpu-g1.dtso` enables only the GPU, adds its supply references and points
it at a single 151 MHz OPP. The existing ACPM driver pairs that shader rate with
302 MHz L2; the full frequency range is deliberately a later test.
`tools/bluejay-development-images.py --dt-overlay FILE` applies this overlay to
both silicon variants in the known persistent images. The kernel, packed RAM,
boot image, empty board DTBO, bootargs and every unrelated DT property must
remain identical. The exact matching Panfrost and gpu-sched modules are added
without replacing the installed module tree. Keep the boot blacklist.

1. **Read-only / low risk:** verify actual image structure and semantic DT delta,
   GPU/OPP schemas, overlay checkpatch, matching module release/hash and current
   USB SSH/watchdog state. Preserve the private results in the current GPU
   evidence directory. Stop on an unexpected DT/image/module delta. No protected-data write is part of this probe.
2. **B images and reboot / bounded boot risk:** announce the screen interruption;
   use the existing project `bin/omamobile push` with the candidate directory and
   the original matching module-archive marker, so it does not replace modules.
   Expect a new boot ID, the same kernel and working automatic desktop/input/
   Wi-Fi. Panfrost remains unloaded. Stop if USB does not return; request physical
   Fastboot recovery when necessary. Roll back through the same project helper
   using the retained persistent baseline or known RAM rescue images.
3. **Manual probe / hardware hang risk:** stream kernel logs to the host first.
   Require systemd's active 20-second watchdog. Run one bounded transient service
   with a persisted pending marker, startup/stop deadlines and reboot on failure.
   Load Panfrost once. Expect Mali-G78, a render node and 151 MHz devfreq; reject
   new faults or SPI/storage errors. A failed attempt stays marked and is not
   retried in the same boot. Never unload/rebind or read PMU registers.
4. **Headless GLES / bounded GPU-job risk:** use explicit GBM render-node EGL,
   require the renderer to identify G78, and check pixel readback for clear and
   shader draws under the same logging/deadline protection. Stop at the first
   job/MMU fault, timeout or wrong pixel. Probe success alone is insufficient.

Compositor acceleration is a later stage after headless rendering passes.
Changing its environment/restarting SDDM affects the screen and must be announced.
Native panel, suspend and full GPU DVFS remain unqualified by G1.

The tested handset owner authorized the staged B-image changes and reboots.
Bootloader and calibration remain preserved. Other handset owners must follow
the project installation/recovery policy before repeating a hardware step.

## G1 results and startup integration, 2026-11-08

The actual image checks prove that the kernel, boot image, empty board DTBO and
packed RAM archive retain their exact bytes. The semantic delta in both silicon
DT variants is confined to GPU status, four supply references and the one-entry
OPP table. GPU/OPP binding validation passes against the exact kernel's compiled
schemas; overlay checkpatch has zero errors/warnings/checks. The default image
tool path also reproduces the existing persistent vendor image byte-for-byte.

The first manual probe deferred (`get clock failed -517`): `clk_acpm` was absent
from the root. The guarded service then failed its render-node assertion and
requested an orderly reboot. This was not a GPU hang. Its saved journal, pending
marker and original host stream are retained privately. After recovery, the
exact matching clock module was added and blacklisted. Before its manual load,
`cpufreq-dt` received a driver override to hold that unrelated deferred consumer;
this keeps CPU DVFS out of the GPU qualification.

The corrected clock/Panfrost stage completed in 149 ms. GPU ID is `0x9202`,
Mali-G78 MC20, shader mask `0x779fff`; Panfrost initialized and exposed
`renderD128`. The only available devfreq rate is 151 MHz. The native build of
`tools/bluejay-gpu-smoke.c` passed `-Wall -Wextra -Werror` and explicitly opened
that render node. Mesa reports OpenGL ES 3.1 and `Mali-G78 MC20 (Panfrost)`.
All pixels passed clear, solid shader and alpha-blended shader checks at
64x64, 257x257 and 1024x1024, in 225 ms. No GPU/MMU fault, SPI error or timeout
appeared.

The compositor uses the existing Aquamarine library: its sole-render-node
fallback pairs the display-only simpledrm device with Panfrost. No additional
Aquamarine patch was needed. Hyprland opens the render node and has Panfrost
buffer allocations; software forcing was disabled and Quickshell uses RHI.
The lock screen rendered and the owner confirmed normal unlock/app/scroll use.
An initial capture during DPMS wake was black; the later capture from the same
process rendered the lock screen. Capture was stopped before local PIN entry.
For this installed Lua Hyprland, the working wake command is
`hyprctl dispatch 'hl.dsp.dpms("on")'`.

`omamobile-bluejay-gpu.service` now stages the same exact module hashes and CPU
hold before SDDM. It requires explicit `/etc/omamobile/bluejay-gpu-enable`, which
is present only on this qualified development root. A persisted attempt marker,
30-second startup deadline, five-second stop deadline and systemd watchdog
bound failure; a retained marker skips the GPU on the next boot. The session
environment selects Panfrost only with the service's volatile ready marker and
render node; otherwise it explicitly restores llvmpipe/software rendering.
Package tests cover the opt-in policy, stale/ready fast paths and both renderer
environment branches. Device package version is 0.1.3.

Private evidence is `~/android/reference/bluejay-gpu-20261108`; the candidate used
by the project helper is `candidate-g1-validated`. Three exact-build modules were
added without replacing the root's touch, Wi-Fi or netfilter modules. Full GPU
DVFS, CPU DVFS, Vulkan, suspend and native panel modesetting remain unqualified.

Final fresh boot: `f0708eb4-e748-4456-abe1-5cb3bd3aa8c5`, same kernel as above.
The actual Hyprland process has `GALLIUM_DRIVER=panfrost`,
`LIBGL_ALWAYS_SOFTWARE=0` and open Panfrost render-node descriptors. All four
startup services and SDDM are active, all pending markers are absent, compositor
config errors are empty, and there are no failed system units. Wi-Fi-bound HTTPS
returns HTTP 200 with TLS verification 0; touch SPI errors/timeouts are zero.
No GPU faults appeared. The watchdog remains owned by systemd at 20 seconds;
automatic boot writes remain off and boot-success remains masked. No host
capture/wait jobs remain. The owner interaction check preceded this final reboot;
it was not repeated afterward.
