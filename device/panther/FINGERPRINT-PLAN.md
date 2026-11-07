<!-- SPDX-License-Identifier: MIT -->
# Fingerprint plan (panther / gs201): what the Pixel 7 shares with the 7 Pro

Status (2026-11-07): **P1 to P5 passed on the phone** (section 5): a finger
enrolled and the lock screen unlocked with it, also after a reboot with the
unit starting the stack by itself. The sensor is the 7 Pro's; the panel and
the touchscreen are not. linux-omarchy-mobile#207 (merged 2026-11-07)
describes the sensor, its supply and pins, all disabled; this repo adds the
two bring-up overlays and the Pixel 7 to `omamobile-fingerprint` and
`tools/extract-fingerprint-vendor`. The 7 Pro's plan and research
([FINGERPRINT-PLAN](../cheetah/FINGERPRINT-PLAN.md),
[FINGERPRINT-RESEARCH](../cheetah/FINGERPRINT-RESEARCH.md)) apply to
everything below unless this file says otherwise.

## 1. The sensor: the same as the 7 Pro's

Sources: the stock dtbo from the Pixel 7's OTA (CP3A.261005.002.A1),
decompiled: `dtbo22_id30406` (PANTHER MP, the one ABL picks on this phone,
`ro.boot.dtbo_idx 22`) against `dtbo12_id30306` (CHEETAH MP); the OTA's
`vendor.img` read with debugfs; the phone, read only.

| What | Pixel 7 (panther) | Same as cheetah? |
|---|---|---|
| Sensor node | `goodixfp`, `compatible = "goodix,fingerprint"`, `interrupts = <2 0>` on `gpa9`, `fp-gpio-reset = <&gpp1 1 1>`, `spi-max-frequency = 1 MHz` (dtbo22 lines 4435-4446) | Yes: the fragment differs only in phandle numbers (dtbo12 4453-4464). All ten panther board dtbos (13-22) have the same node and reset pin |
| Reset pin | `gpp1-1`, function 1 (output), no pull (dtbo22 4419-4425) | Yes |
| Supply | S2MPG13 `LDO15S`, "L15S_UDFPS_AVDD", 2.5-3.3 V, `regulator-always-on` (dtbo22 1669-1677) | Yes, identical lines |
| Touch hook | `fps_touch_handler` (dtbo22 4447-4450) | Yes (our props.conf turns it off on both) |
| Trusted app | `/firmware/g7.app`, 13 537 619 bytes; `ro.vendor.fingerprint.ta.name=g7.app` (vendor `build.prop`) | Same name and loader; the bytes are not compared (no cheetah image on this computer) |
| HAL and Trusty services | `android.hardware.biometrics.fingerprint-service.goodix`, `gatekeeper-service.trusty`, `keymint-service.trusty` (C++), `storageproxyd`, `trusty_apploader`, `vndservicemanager`, `libgf_hal.so`, `fp_utils.so` | Same file names as the 7 Pro list in `tools/extract-fingerprint-vendor` |
| `fingerprint-goodix.rc` | apploader on `ro.vendor.trusty.storage.fs_ready=1`, then the HAL | Same flow |
| Partitions | `mfg_data` (sdd4, 6560 sectors), not blank: 35 525 of its 16-byte rows are non-zero; RPMB LUN `0:0:0:49476` present | As cheetah; whether `mfg_data` holds a valid calibration is not checked |
| Kernel config (running kernel) | `GOODIX_FP=m`, `TRUSTY=m` (+log, virtio, ipc), `CHR_DEV_SG=m`, `DMABUF_HEAPS_SYSTEM=y`, `ANDROID_BINDERFS=y`; `goodix-fp.ko` and the trusty modules installed | Yes |

So no new sensor driver and no new TA: the 7 Pro's `goodix-fp`, Trusty
drivers, chroot, bridge and libfprint driver are the ones to use.

## 2. What differs

| Piece | Pixel 7 | Consequence |
|---|---|---|
| Trusty | Started on the Pixel 7 on 2026-11-03 with the sound bring-up's overlay, which enables `/trusty` (kernel `g89edef70d4d5`, 23:43): "trusty version: Project: cloudripper", "selected api version: 5", trusty_ipc virtio0 vrings, "trusty-virtio ... initializing done". `/dev/trusty-ipc-dev0` and the cpu 7 hotplug were not checked | Gate P2 is mostly seen already; what is left of it is in P2 |
| Sub-PMIC | Not described before linux-omarchy-mobile#207 (running regulators: `ldo*m` only) | #207 adds `pmic-2` with LDO15S only |
| Panel | Samsung S6E3FC3 (`panel-samsung-s6e3fc3`, `samsung,s6e3fc3-p10`), 1080x2400, ABL's `exynos_drm.panel_name=sdc-s6e3fc3-p10` | Local HBM is in a local kernel commit (branch `panther-lhbm`, not on the phone yet): section 4 |
| Touchscreen | FocalTech FT3658 (`focaltech_ft3658`, input "FocalTech FT3658") | The runner looked only for the Synaptics name: now per device |
| `omamobile-fp-chroot` | Any board but the 9a ran as cheetah | Now detects `google,gs201-panther`: g7.app, C++ KeyMint, 1080x2400 at 60 Hz, `sdc-s6e3fc3-p10`, FT3658 (untested) |
| Sensor position | Not known here: the bridge asks the HAL (`getSensorProps`), which has its own per-device data | Check in P5 that the circle lands on the sensor |
| `tools/phone-provision` | Accepts cheetah and raven only | Google's files go in by hand until it learns panther |
| Factory image | Ángel has the OTA (payload), not the factory zip the extractor reads | Repack `vendor.img` + `system.img` as a zip and use `-f`, or get the factory zip (a download: Ángel's call) |

## 3. Bring-up gates

Rules from the 7 Pro, unchanged: nothing writes `persist`, `mfg_data` or the
RPMB without Ángel's explicit "yes" in that session; `storageproxyd`'s first
run (cheetah F4) is irreversible. Before any reboot: Vol- + Power,
`fastboot --set-active=b` (slot B's retry counter). The NV backup of
2026-11-03 exists (`tools/nv-backup -d panther`, 7 partitions, `--check` SAME).

Kernel: the bring-up ran on a local branch with linux-omarchy-mobile#207's
commit on top (section 5 names the kernel). Overlays apply
with `DTB_OVERLAYS="..."` in `device/panther/device.conf` (a local edit for
the test, never committed) before `bin/omamobile images`.

**P1. New DTB, no overlay.** Expect: the phone as before;
`cat /proc/device-tree/fingerprint/status` = `disabled`; no `vdd_udfps` in
`/sys/class/regulator/*/name`. **Stop if** anything else changed (display,
touch, wifi, charging) or `fingerprint` is missing.

**P2. Trusty (`DTB_OVERLAYS="fingerprint-trusty"`).**
Trusty's start was already seen with the sound overlay (section 2); what is
new here is the device node and the cpu 7 line.
`tools/fingerprint-capture --watchdog trusty-core`, then `trusty-log`,
`trusty-ipc`, `hotplug`. Expect as cheetah F2: "trusty version", "selected
api version", `/dev/trusty-ipc-dev0`, "refusing to take cpu 7 offline".
**Stop if** the phone hangs or resets (the watchdog feeder catches it), any
SError/panic, or the version line is missing: back to the previous images.

**P3. Connect-only probe.** `omamobile-tipc-probe keymint gatekeeper
apploader` (connects and closes, sends nothing; never the storage proxy
port). Expect three "open". **Stop if** any fails: Trusty is up but not
serving.

**P4. Sensor power (`DTB_OVERLAYS="fingerprint-trusty fingerprint-sensor"`).**
Check `vdd_udfps` appears with 0 users, then `tools/fingerprint-capture
--watchdog goodix`. Expect "goodix-fp ... supply switched", LDO15S 1 user
while `/dev/goodix_fp` is open, 0 after. **Stop if** any other rail changes
state (`regulator_summary` before and after), or LDO15S is not the one
switched.

**P5. TA, HAL, enroll (the irreversible part: Ángel's "yes" first).**
Google's files from the Pixel 7's own image (`extract-fingerprint-vendor -d
panther`), then the 7 Pro's F3-F9 with the runner's stages. Expect "g7.app
loaded", "HAL/TA version is match", "Initialization successful". **Stop if**
the HAL reports a calibration error (the 9a's "spmt is not pass" /
CALIBRATION_NOT_READY): the calibration question is then panther's own.

## 4. Local HBM on the S6E3FC3

The optical sensor reads the finger lit by the panel's local HBM circle. The
bridge drives it through `local_hbm_mode`; without it the bridge logs "LHBM
on refused" and captures run unlit, which is expected to fail or match
poorly (not measured). The panel driver on `omamobile` has no
`local_hbm_mode` yet: a local kernel commit (branch `panther-lhbm`, not
proposed yet) adds it to
`panel-samsung-s6e3fc3`, from Google's GPL `panel-samsung-s6e3fc3-p10.c`
(android-gs-pantah-5.10-android15-qpr1): the 7 Pro's interface
(`local_hbm_mode`, `local_hbm_max_timeout` up to 3 s, `allow_lhbm`, off on
blank/unprepare), the gamma copy from 0xD8 to 0x65 and the circle centred
at x 540, y 1713. `omamobile-fingerprint-lhbm.conf` has the
`panel_samsung_s6e3fc3` line. Not run on the phone: check the circle's
place and the 3 s timeout before P5.

## 5. Results

On 2026-11-04, kernel `7.3.0-rc6-omamobile-push1-g44048a9aa795` with the
fingerprint DT commit (its LDO15S `disabled`, enabled by this overlay) and
the sound and camera overlays the phone already ran; only
`vendor_kernel_boot` was reflashed, rebuilt byte for byte the same way first.

| Gate | Result |
|---|---|
| P1 | Passed: `fingerprint` present and `disabled`, no `vdd_udfps`; modules, Wi-Fi, touch, sound, failed units as before; kernel errors the same kinds as the three boots before (60-72) |
| P2 | Passed (Trusty was on through the sound overlay): "trusty version: Project: cloudripper", "selected api version: 5", `/dev/trusty-ipc-dev0`, "refusing to take cpu 7 offline" |
| P3 | Passed: keymaster, gatekeeper and apploader "open" |
| P4 | Passed with goodix_fp blacklisted and loaded by hand: "irq 129, supply switched, netlink 25"; `vdd_udfps` 0 users before, 1 (enabled) while `/dev/goodix_fp` was open (152 sensor interrupts), 0 (disabled) after; `regulator_summary` otherwise identical (81 lines) |
| P5 | Passed (Ángel's yes, 2026-11-04 and 11-06): see below |

**P5.** The runner first refused: this phone's `persist:/ss/0` is a 0-byte
file with the factory date (1 Jan 2020), in the 11-03 and 11-04 backups
alike, so its Trusty never committed TDP, and stock's `storageproxyd`
serves that empty file on every boot (`init.gs201.rc` links
`/data/vendor/ss/persist` to persist's `/ss`). With the runner taking an
empty `/ss/0` as an empty TDP copy (its hash recorded, refused once either
side changes), the first start (11-04 18:24) copied `mfg_data` and
`persist:/ss`, ran `storageproxyd`, loaded `g7.app`, and brought up KeyMint,
Gatekeeper, the Goodix HAL and the bridge; the HAL reported the sensor at
(540, 1713), radius 100, and no calibration error ("injectMtCali:
Calibration file already sent" only). On 11-06, same kernel and DTB,
`omamobile-fp` started the stack again; `fprintd-list` showed "Under-display
fingerprint sensor (Omarchy Mobile)". A right index finger was enrolled from
the shell's enrollment screen (quick settings, Fingerprint) and the lock
screen unlocked with it (the bridge logged `MATCH`). The TDP copy was still
the empty file (`e3b0c442…`) two days and one enrollment later: Trusty did
not write TDP. Then, with `omamobile-fp` enabled and this package's
`omamobile-fingerprint.conf` in place of the hand-written blacklist, a
reboot (11-06 19:02): Trusty loaded from the DT, `/dev/trusty-ipc-dev0`
and `goodix_fp` were there, the unit started the stack by itself ("g7.app
loaded", the bridge ready), no unit failed, the finger was still enrolled,
the TDP copy still empty, and the lock screen unlocked with it (`MATCH`).
Not checked: the packages installed with `pacman -U` (their files were
copied by hand), a wrong finger, sudo through `pam_fprintd`, and stock
Android after a factory reset (cheetah's T2).

Before a Pixel 7 DTB turns `/trusty` on by default (not just the bring-up
overlay): Trusty loads straight from the DT here and calls into the secure
world at probe, while the 7 Pro loads it from a start script behind a hang
marker. The Pixel 7 gets the same guarded start first.
