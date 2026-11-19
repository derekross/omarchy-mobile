<!-- SPDX-License-Identifier: MIT -->
# OnePlus 7T Pro cameras: what is left

Status 2026-11-13 (`boot_a` = `g8da458f2d9a9`, cameras load at boot). All
four sensors stream; the main IMX586 over C-PHY, the three back cameras
focus (SEMCO module: LC898217XC at 0x72/0x74, AK7374 at 0x0c), and
libcamera's software ISP runs on the GPU at about 60 fps once
`CONFIG_DMABUF_DEBUG` is off. The history and the evidence are in
[CAMERA-PLAN.md](CAMERA-PLAN.md) §7. This file lists the open work, each
item with what is known, what to do and how to tell it is done.

## 1. omacam: a lens table for this phone

omacam reads a lens table from `--lens-table` or
`~/.config/omacam/lenses.toml` and otherwise uses its built-in Pixel 7 Pro
table, so on this phone it takes the first back camera it finds (the IMX481
ultrawide) as the main one and leaves the IMX586 and the telephoto unused.

- **Now:** the table below is in the owner's `~/.config/omacam/lenses.toml`.
  With it, omacam offers 0.5x / 1x / 3x and previews the main camera at
  1992x1500.
- **To do (omacam repository):** ship per-device tables and pick one by
  the board's compatible (`/proc/device-tree/compatible`, first entry
  `oneplus,hotdog`), with the user's file still taking precedence. The
  table's ids are the libcamera ids (`cam -l`).
- **Done when:** a fresh user on this phone gets the three back lenses
  without a file in `~/.config/omacam`.

The table (zoom from OnePlus's published 35 mm equivalents, not
calibrated; preview/still are whole sensor modes, because the software
ISP crops and never scales):

```toml
device = "hotdog"
max_zoom = 10.0

[[lens]]
role = "main"
name = "Main"
id = "/base/soc@0/cci@ac4a000/i2c-bus@1/camera@1a" # Sony IMX586
zoom = 1.0
f_number = 1.6
focal_length_35mm = 26
preview = [1992, 1500]
still = [3992, 3000]
autofocus = true

[[lens]]
role = "ultrawide"
name = "Ultrawide"
id = "/base/soc@0/cci@ac4b000/i2c-bus@1/camera@1a" # Sony IMX481
zoom = 0.5
f_number = 2.2
focal_length_35mm = 13
preview = [4648, 3496]
still = [4648, 3496]
autofocus = true

[[lens]]
role = "tele"
name = "Telephoto"
id = "/base/soc@0/cci@ac4a000/i2c-bus@0/camera@10" # Samsung S5K3M5
zoom = 3.0
f_number = 2.4
focal_length_35mm = 78
preview = [2096, 1184]
still = [4200, 3120]
autofocus = true

[[lens]]
role = "front"
name = "Front"
id = "/base/soc@0/cci@ac4b000/i2c-bus@0/camera@10" # Sony IMX471
zoom = 1.0
f_number = 2.0
focal_length_35mm = 25
preview = [1920, 1088]
still = [1920, 1088]
autofocus = false
mirror = true
```

Follow-ups in the same area:

- The ultrawide has only its full 4656x3496 mode (`sony-fwtable` takes the
  modes from the owner's tables), so it previews 16 MP per frame. A binned
  mode from stock's tables (if they carry one) would make its preview
  cheaper.
- The IMX586's 8000x6000 mode is skipped (`link 1166396875 Hz not in the
  device tree`): adding that link frequency to the DT endpoint gives the
  48 MP still.
- Calibrate `zoom` and `axis` per lens on our own frames (CAMERA-PLAN of
  cheetah describes the method).

## 2. Front camera: the pop-up (P3-P5)

The IMX471 streams (`cam -c 3`), but it sits in the motorised pop-up, which
has never been moved under Linux. P0-P2 passed: the hall sensors on i2c-0
answer and read "down" (`up=-11 down=-325`), the LPG is `pwmchip0`, and the
pop-up tool (`omamobile-hotdog-popup`, device-hotdog 0.1.6) refuses moves
from an unknown position.

- **To do:** CAMERA-PLAN §6 P3 (first move up), P4 (down, then five
  cycles), P5 (the front camera follows the pop-up), each announced, with
  the owner watching, the phone flat and the slot clear. Never write hall
  register 0x06.
- **Then:** wire the pop-up to the camera's open and close (omacam's front
  camera or a libcamera hook), with the camera closed whenever the pop-up
  is down.
- **Done when:** opening the front camera in omacam raises the pop-up and
  closing it lowers it, five times in a row, and the front picture is
  upright and mirrored.

## 3. The random bad RAM boots

Three of the RAM boots of camera kernels went bad (two on 2026-11-05, one
on 2026-11-12; the log of the last is `logs/hotdog/badboot-*.log`, not
committed). A retry of the same image booted clean each time it was tried.
Signs of a bad boot:

- everything is late from the first second (ufshcd re-probes at 22 s,
  `scsi host0` at 38 s, the partitions at 76 s; a good boot reaches Arch at
  9 s);
- the display controller times out (`frame done timeout`, `ctl 1 reset
  failure`, `vblank wait timed out`): the panel shows noise like an old TV;
- UFS stops answering its link commands (`pwr ctrl cmd 0x17 ... completion
  timeout`, hibern8 enter), and every read after that fails at once
  (`hostbyte=0x07`, the UFS interrupt count frozen), so the root never
  mounts and the initramfs stays up with SSH.

Nothing is written in a bad boot (the root is never mounted), and `boot_a`
boots from ABL have not shown it. The common factor of UFS and the display
failing together points at something shared: RPMh votes, the interconnect,
or the clocks ABL leaves running after its fastboot screen. The bad boot
of 2026-11-12 was sent within seconds of fastboot appearing, so the time
spent in fastboot is not the whole story.

- **To do:** compare a good and a bad boot's `dmesg` (ufshcd and DPU probe
  times, `sync_state` messages, which clocks and regulators are on);
  try `fastboot boot` right after reaching fastboot versus after minutes;
  look at `/sys/kernel/debug/interconnect/` and the RPMh votes in a bad
  boot (it answers SSH).
- **Done when:** the cause is named and either fixed or avoided (for
  example, a rule for how RAM boots are done).

## 4. Smaller open points

- **LC898217XC status:** both chips read 0xb3 = 0x20 after power-up where
  stock polls for 0 (10 ms). The lens moves, so it is harmless, but the
  driver warns at every power-up. Find the bit's meaning or poll for the
  bits stock means.
- **Upstream:**
  - the s5k3m5 crop fix (`eaa88b840` on `omamobile-hotdog-af`);
  - the AK7374 support, the LC898217XC driver and the `v4l2-fwnode` change;
  - msm's handling of imported dma-bufs under `DMABUF_DEBUG` (the upstream
    "drm/msm: DMABUF_DEBUG fixes" series covers it); once that lands, the
    option can go back to its default.
- **Pixel 4 (same SoC and GPU):** it was said to need the CPU debayer too.
  Check its kernel for `CONFIG_DMABUF_DEBUG=y`; turning it off should give
  it the GPU path as well.
- **Colour and noise tuning:** the tuning on the phone comes from the
  owner's stock files and stays private
  (`~/android/reference/hotdog/tuning/`). The packaged files in libcamera
  have identity colour matrices. A public calibration needs our own colour
  chart captures, or a tool that derives the tuning from each owner's own
  image on the phone (as `tools/hotdog-camera-tables` does for the sensor
  tables).
