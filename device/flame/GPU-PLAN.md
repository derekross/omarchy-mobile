<!-- SPDX-License-Identifier: MIT -->
# flame: Adreno 640 contexts and first compositor fault

Status (2026-10-18): hardware EGL/OpenGL contexts verified with kernel
`7.0.0-sm8150` and Mesa `26.2.5-arch1.1`. The first Hyprland rendering
attempt faulted. A separate, out-of-tree RAM-resident Arch/Omarchy payload
ran a session with llvmpipe;
accelerated desktop rendering, suspend and reliable display power management
remain open.
Kernel source: [postmarketOS SM8150 Linux][dts], tag `v7.0.0-sm8150`.
Packaged kernel inputs and explicit output
directories are described in [BRINGUP-M1](BRINGUP-M1.md).

## Evidence and scope

- [V, source] The [flame DTS][dts] describes Adreno 640 and requests
  `qcom/sm8150/google/flame/a640_zap.mbn`. The upstream MSM driver handles
  firmware loading, clocks and power domains; no userspace register access
  is needed.
- [V, hardware] KMS registered `msmdrmfb` at 1080x2280. The initial boot log
  includes DSI/SMMU errors and a clock warning; a console alone does not
  establish reliable accelerated display operation.
- [V, local extraction] GPU firmware came from the test phone's matching
  Google factory image. These proprietary files remain outside the repo.
- [V, hardware] With all 74 UFS nodes read-only, the matching firmware staged
  privately, an external kernel log, the hardware watchdog, and a recovery
  timer, Arch's `eglinfo` created hardware contexts through GBM, surfaceless
  EGL and the EGL device platform. A fresh SSH connection succeeded before
  the recovery timer was canceled.
- [V, hardware] The hardware renderer was **freedreno / FD640**, with OpenGL
  4.6 and OpenGL ES 3.2. A separate software device was also enumerated;
  software rendering is not the evidence for the hardware result.
- [V, hardware] The kernel loaded `qcom/a630_sqe.fw` and `qcom/a640_gmu.bin`,
  reporting GMU firmware `v2.0.261`. No new GPU warning appeared in this
  context test. It did not draw a desktop or prove a successful KMS page flip.
- [V, hardware] A later Arch/systemd boot from an NFSv3 root started SDDM's
  Hyprland greeter (`0.56.2-7`). Rendering produced a GPU translation fault
  from the **CCU**, followed by MSM hang recovery and a compositor abort.
  The kernel log and GPU/DPU devcoredumps were saved privately. Do not
  interpret successful EGL context creation as successful rendering.
- [V, hardware] That boot also registered the FTS touchscreen input device.
  With `ftm5_fw.ftb` absent, the driver explicitly bypassed its automatic
  firmware update and enabled sensing. A later guarded probe captured 320
  physical tap/swipe events, and the owner unlocked the PIN screen and
  reached the home screen. The SPI controller's module name is `spi_geni_qcom`;
  `spi_qcom_geni` does **not** blacklist it.

[dts]: https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux/-/blob/v7.0.0-sm8150/arch/arm64/boot/dts/qcom/sm8150-google-flame.dts

## Rendering fault investigation

The software comparison passed on a RAM SquashFS/overlay root: a 32x32 EGL
triangle rendered and read back the expected green pixel with no GL error,
using llvmpipe (LLVM 23.1.3). Hyprland then displayed the mobile lock screen
and home screen at 1080x2280, 90 Hz, scale 2.5. No new GPU fault appeared in
that software session. `LIBGL_ALWAYS_SOFTWARE=1` and
`GALLIUM_DRIVER=llvmpipe` are a development workaround, not an acceleration
fix. The NFS hardware fault still needs a small hardware-render comparison.

Keep the first-light image unchanged and all phone storage read-only.
First isolate a small offscreen render from KMS and Hyprland, then compare
a software-rendered session with the hardware path. Change one variable
per temporary boot, retaining the watchdog, external log and recovery timer.
The [Mesa Freedreno debugging guide][debug] documents GPU devcoredumps and
the `FD_MESA_DEBUG` flags for narrowing rendering faults. No flag has yet
been validated as a fix on this phone.

[debug]: https://docs.mesa3d.org/drivers/freedreno.html

## Next gates

| Step | Expect / pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- |
| Verify backups, storage flags, watchdog and external log | Current backup anchor; every protected node read-only | Any missing protection | Stop | Low |
| Test an actual rendered frame and KMS flip | Hardware renderer and stable panel output | GPU fault, new warning, USB loss | Recovery timer / watchdog; temporary boot only | Medium |
| Start the Omarchy session | Visible shell and fresh SSH | Compositor crash or unstable display | Return to the RAM probe | Medium |
| Test touch separately | Registered input device and observed events | Controller error or firmware update attempt | Stop; reboot without the SPI module | Medium |

Keep touchscreen firmware absent during the first input probe. The imported
FTS driver contains an automatic firmware updater; controller firmware and
calibration are separate from the UFS read-only boundary. Inspect that path
before loading the SPI controller, and never add the factory touch firmware
just because a filename is reported missing.
