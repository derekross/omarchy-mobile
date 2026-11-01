<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): GPU

Status (2026-10-20): **the Mali-G78 renders Omarchy through Panfrost**
(GLES 3.1, Hyprland on top), panfrost loads at boot, and GPU DVFS runs
through ACPM. Upstream PR: `omamobile-gs101-gpu-pr` (derekross/
linux-omarchy-mobile#3); DVFS and GPU cooling on `omamobile-gs101-gpu-dvfs`.
Mesa from `packages/mesa` with the G78 patch (merged). PanVK refuses the
G78. G5 passed (2026-10-20): panfrost works without the
`GPU_COHERENCY_ENABLE` write.

## 1. Goal

1. Hyprland and Chromium on the GPU instead of llvmpipe (done).
2. GPU DVFS through ACPM, as cheetah's [GPU-PLAN](../cheetah/GPU-PLAN.md).
3. Vulkan (PanVK), once Mesa supports the G78 there.

## 2. Facts

- [V] Mali-G78 MC20, GPU_ID 0x9202 r0p1 (Arm's tBEx): a Valhall v9.2
  job-manager GPU, so **Panfrost, not Panthor** (cheetah's G710 is a CSF
  GPU on Panthor).
- [V] The G3D power domain is up after ABL: panfrost reads the GPU's
  registers at probe without a power-domain driver.
- [V] Neither upstream panfrost nor postmarketOS's knew the G78 (the only
  Valhall model was the G57): `GPU model not found: mali-unknown id rev
  0x9202 0x10`. Arm's kbase lists nearly the same features and issues for
  tBEx and tNAx (the G57).
- [V] Mesa 26.2.4 has no G78 in its model table either, so the Gallium
  driver refuses the GPU and the session falls back to llvmpipe.

## 3. What was built

| Where | Change |
| --- | --- |
| `omamobile-raven-gpu` `94a571672` | gs101 GPU node (raven) and panfrost's gs101 match |
| `fbb7b6c75` (+ fixup `7ba71bf34`) | drm/panfrost: add the Mali-G78, matched on its masked ID 0x9002 with G57's features and `TTRX_2968_TTRX_3162` |
| `c91469c1c` | drm/panfrost: gs101 uses the AArch64 page table format |
| `e01f31ddd` | drm/panfrost: program `GPU_COHERENCY_ENABLE` |
| `packages/mesa` 0003 | the G78 (and upstream's G68) in Panfrost's model table |
| `omamobile-device-raven` | panfrost loads at boot (no longer blacklisted) |

## 4. Results

- **First probe** (kernel `g94a5716728ce`, log streamed, watchdog feeder
  armed): panfrost probed, read the GPU's registers and stopped at the
  unknown model. Parked with panfrost blacklisted until the model entries
  existed.
- **First render** (2026-10-14, `g4fd3f0dd1ecf`): Hyprland on the G78,
  much faster than llvmpipe, but black lines and no wallpaper, with
  `DATA_INVALID_FAULT` on every fragment job. A headless GLES probe
  (`PAN_MESA_DEBUG=sync,trace`) showed the faulting job header read back
  with job type 0; no Mesa debug option changed it, nor did disabling
  flush reduction.
- **Cause:** gs101 used panfrost's legacy Mali LPAE page tables. Every
  G57 SoC entry (mt8188, mt8192, mt8370) sets
  `GPU_QUIRK_FORCE_AARCH64_PGTABLE`. With it on gs101, clears, solid,
  blended and textured draws up to 4096x4096 give the right pixels and no
  faults. Also, `GPU_COHERENCY_ENABLE` read 0 (ACE-Lite) at probe and
  panfrost never wrote it; it now programs the selected mode (NONE).
- **Now:** `Mali-G78 MC20 (Panfrost)`, GLES 3.1; panfrost loads at boot.
  PanVK still refuses the G78 (`panvk_physical_device.c:421`).
- Mesa was built for the phone in an emulated arm64 container on the
  laptop, in about 1 h (`tools/build-packages --all` does the same).

- **GPU DVFS (2026-10-16, `gb4d96e9c3ab7`):** panfrost scales the ACPM
  G3D clock over Google's 11 levels (151-762 MHz), with G3DL2 following
  each level's `l2-hz` (302-996 MHz). Idle 151/302 MHz; under touch load it
  went to 762 and back to 151 within about 0.7 s, no faults. Kernel
  `551e8b261` (panfrost GPU_PM_FW_DVFS + l2 clock) and `b4d96e9c3` (gs101
  DT) on merge-test.

## 5. Open

- PanVK support for the G78 in Mesa.

## 6. G5: panfrost without the coherency write (boot A)

The PR review (#3) dropped `drm/panfrost: program GPU_COHERENCY_ENABLE`:
it reached every panfrost GPU, and the 0 read at probe is most likely the
register's reset value, since `panfrost_gpu_init()` soft-resets first. It
landed in the same step as the page-table quirk, which is what fixed the
faults; no result above isolates it. G5 checks that nothing breaks
without it.

Kernel: the first `omamobile-gs101-int` rebuilt from the rebased subsystem
branches (2026-10-20), which has no coherency write. It also carries a NOT
FOR MERGE commit that keeps raven's old USB 2 peripheral description, so
USB is as on the running kernel (the USB change is [USB-PLAN](USB-PLAN.md)
U1, a separate boot). Built offline 2026-10-20:
`7.3.0-rc6-omamobile-push1-g675676713161` (`-int` `675676713`), images in
`~/android/mainline/out-gs101-int/images`, modules tarball beside them,
the initramfs with the same files and splash as the running one. Its
overlaid DTB matches the running kernel's in every node and property;
only four new regulator labels (from the GPU review) differ.
Rollback: `~/android/mainline/out-gs101-cpif/images`
(`g6efb2b9205c1`, the running kernel).

**G5.1 (read-only, now):** record the GPU's state on the running kernel.

```sh
tools/phone-ssh 'uname -r; dmesg | grep -E "panfrost|mali" | head -8
cat /sys/class/devfreq/*.gpu/cur_freq'
```

- **Pass:** the `mali-g78 id 0x9202 major 0x0 minor 0x1` line and a GPU
  devfreq frequency.

**G5.2 (push, reboot; the human approves):** push the boot A images.

```sh
cd ~/projects/omarchy-mobile-raven-device
sg docker -c "env DEVICE=raven KERNEL_DIR=$HOME/android/mainline/wt-gs101-int \
    KERNEL_OUT=$HOME/android/mainline/out-gs101-int TMPDIR=$HOME/android/tmp-build \
    bin/omamobile push"
```

- **Screen:** the phone reboots; the splash and the lock screen come back.
- **Expect:** SSH back within about 60 s; `uname -r` reads the new
  release; `omamobile-boot-success` marks slot B good.
- **Stop:** no SSH after 3 minutes. Ask the human to hold Power about
  30 s; if it comes back on the old images or not at all, roll back.
- **Rollback:** `bin/omamobile push` with `KERNEL_OUT=~/android/mainline/out-gs101-cpif`
  (and `KERNEL_DIR=~/android/mainline/wt-gs101-cpif`), or, without SSH,
  Volume Down + Power about 20 s for fastboot and `bin/omamobile flash`
  with the same variables.
- **Risk:** low to medium: every subsystem branch was rebased and merged
  afresh, but the DTB is the running one's; the change is in the code.

**G5.3 (read-only):** the GPU without the coherency write, and the rest.

```sh
tools/phone-ssh 'dmesg | grep -E "panfrost|mali|FAULT|fault" | head -20
cat /sys/class/devfreq/*.gpu/trans_stat | tail -3
systemctl --failed --no-legend; journalctl -b -p err --no-pager | tail -20'
```

Then on the phone: unlock, open a few apps, scroll, rotate, run the
shell for about two minutes. Rerun the dmesg line.

- **Pass:** no `DATA_INVALID_FAULT` or other GPU fault, Hyprland draws
  correctly (no black lines, wallpaper present), devfreq moves between
  151 and 762 MHz, no failed units. Wi-Fi, Bluetooth, sound, sensors,
  touch and the modem behave as before.
- **Stop:** any GPU fault or rendering damage: the coherency write is
  needed after all. Roll back, then bring it back as a gs101
  `vendor_quirk` that writes only `COHERENCY_NONE` (Derek's suggestion).


**G5 result (2026-10-20, `7.3.0-rc6-omamobile-push1-g675676713161`): passed.**
G5.1 on `g6efb2b9205c1`: GPU devfreq at 151 MHz. G5.2: pushed, SSH back
within about 40 s, slot B marked good. G5.3: panfrost probed as before
(`mali-g78 id 0x9202 major 0x0 minor 0x1`), no GPU fault after the owner
used the shell for about two minutes (unlock, apps, scrolling, rotation;
"all good"), devfreq moved across 151-762 MHz (101 transitions), no failed
units, 0 `ufshcd_err_handler`, and the boot check passed every component.
The coherency write isn't needed: the PR keeps it dropped. The touch
controller's `s6sy79x: failed to read events` lines (53 this boot) appear
on the previous kernel too (18), so they predate this kernel.
The modem on the same boot (the reworked `omamobile-gs101-cpif` import):
CP ONLINE, the eSIM registered on LTE on stack 1, and a text to its own
number came back; 0 `ufshcd_err_handler`.
