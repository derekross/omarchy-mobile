<!-- SPDX-License-Identifier: MIT -->
# hotdog fingerprint userspace (staged, theoretical)

**Untested: nothing here has run on a phone, and nothing here has been
built against the owner's vendor image.** These files are staged in
`device/hotdog/fingerprint/`. No package ships them and no unit enables
them. The plan, its gated runbook and the kernel side are in
[../FINGERPRINT-PLAN.md](../FINGERPRINT-PLAN.md).

The design follows the Pixel stack (`fingerprint/`,
`packages/omamobile-fingerprint`). The bridge speaks the same line
protocol on the same socket path and writes the same `--ui-state` file, so
libfprint's `omamobile_udfps` driver, fprintd's drop-in and the shell's
`omamobile.fingerprint` plugin need no change.

## Files

| File | What |
| --- | --- |
| `omamobile-fp-ion-shim.c` | LD_PRELOAD library: `/dev/ion` for libQSEEComAPI and libion, made from `qcom_qseecom_compat`'s `QSEECOM_COMPAT_IOCTL_ALLOC` dma-bufs. It handles the new (4.12+) and the legacy handle ion ABI, and only the `qsecom` and `qsecom_ta` heaps |
| `omamobile-fp-hotdog-bridge.cpp` | Client of HIDL `android.hardware.biometrics.fingerprint@2.1`. It serves the Pixel bridge's line protocol, reads the touchscreen, switches the panel's HBM and sends goodix-fp `notify` events |
| `Makefile` | Builds the shim with the NDK. The shim and the bridge build with an AOSP or LineageOS tree, its prebuilt clang, its libc++ and hidl-gen headers. Both link against the extracted chroot |
| `omamobile-fp-hotdog-chroot` (in `packages/omamobile-device-hotdog/lib/`) | The runner: preconditions and the safety refusals, the chroot in private mount and PID namespaces, and the start order hwservicemanager -> qseecomd -> HAL -> bridge. It stops in reverse order and starts once per boot |
| `omamobile-fp-hotdog.service` (in the package's `vendor/systemd/system/`) | The unit, enabled by the package; inert until the owner's files are in `/usr/lib/omamobile-fp-hotdog/root` |
| `props-hotdog.conf` (in the package's `lib/`) | Property placeholders for the chroot |

## Data flow

```
Omarchy lock (PAM omarchy-lock-fingerprint) / sudo / polkit
  -> fprintd -> libfprint omamobile_udfps                 (unchanged)
       | /run/omamobile-fp/sock/bridge.sock (root only, line protocol)
  -> omamobile-fp-hotdog-bridge (bionic C++, in the chroot)
       | HIDL fingerprint@2.1 over hwbinder        touchscreen (evdev, read-only)
       |                                          panel  /sys/.../backlight/*/hbm
       |                                          sensor /sys/.../goodix-fp/*/notify
  -> OnePlus Goodix HAL  (owner's vendor image)
       | libQSEEComAPI: /dev/qseecom + "/dev/ion" (ion shim -> qseecom dma-bufs)
       | /dev/goodix_fp (power, reset, IRQ; netlink 25 events)
  -> qcom_qseecom_compat (our kernel) -> SCM -> QSEE: the Goodix TA
       ^ listener requests (TA files) answered by qseecomd, in the chroot,
         into /var/lib/omamobile-fp-hotdog/{persist,data}; no block devices
```

Capture sequence for a finger inside the circle during ENROLL or AUTH:
`notify touchdown` -> `hbm 1` -> `--hbm-settle-ms` (60) -> `notify
ui_ready`. With `--hbm-first 1` the order is `hbm 1`, settle, `touchdown`,
`ui_ready`. On lift the bridge sends `notify touchup`, then `hbm 0`. It
refreshes HBM every 2 s while the finger stays, and the panel driver turns
HBM off by itself after 3 s.

## Protocol coverage

| Command | HIDL calls | Answer |
| --- | --- | --- |
| ENROLL | `preEnroll`, `enroll(hat, 0, 60)`, `postEnroll` at the end | FINGER NEEDED, ACQUIRED, PROGRESS, ENROLLED |
| AUTH | `authenticate(0, 0)` | MATCH, or NOMATCH (the bridge cancels) |
| LIST | `enumerate` | LIST, after 3 s at most |
| DELETE id | `remove(0, id)` | DELETED, or ERROR 2 after 3 s |
| CANCEL | `cancel` | ERROR 5 |
| STATUS | none | READY, OK |
| RESETLOCKOUT | none: HIDL 2.1 has no resetLockout | ERROR 2 |

The HIDL `ERROR_LOCKOUT` error becomes LOCKOUT 30000. HIDL acquired codes
0-6 become the protocol's AIDL codes 1-7. HIDL `ERROR_VENDOR` (8) becomes 7.

## Names to confirm (unverified until checked against the owner's image)

Each name below is an expectation from how Android 10/11 Qualcomm vendors
are usually laid out. Confirm each one read-only, from the owner's image,
before the plan's HAL step. The runner takes overrides from
`/var/lib/omamobile-fp-hotdog/paths.conf`.

- the HAL binary: `/vendor/bin/hw/android.hardware.biometrics.fingerprint@2.1-service` (OnePlus may name it differently, for example a `vendor.oneplus...` or `vendor.goodix...` service)
- that the HAL serves `IBiometricsFingerprint/default` over hwbinder, and whether it also needs OnePlus extension interfaces
- `qseecomd` at `/vendor/bin/qseecomd`, and that it sets `vendor.sys.listeners.registered=true` (older builds: `sys.listeners.registered`)
- the Goodix TA's name and files (`.mdt`/`.bNN`), and where libQSEEComAPI looks for them (`/vendor/firmware_mnt/image`, `/vendor/firmware`, `/firmware/image`). Its name goes into `qcom_qseecom_compat`'s `app_allowlist`
- the ion heap ids libQSEEComAPI asks for (`qsecom` 27, `qsecom_ta` 19), and the ion ABI it speaks (new vs legacy). Overrides: `OMAMOBILE_FP_ION_HEAPS`, `OMAMOBILE_FP_ION_ABI`
- which goodix-fp netlink events the HAL waits for (touchdown, ui_ready), their numbers (module parameters in the kernel) and their order (`--hbm-first`)
- whether the HAL writes OnePlus sysfs nodes of its own (display dim layer, HBM) that do not exist here
- the properties the HAL reads (`props-hotdog.conf`)
- the TA's and HAL's file paths that stock kept on persist and data (the runner offers `/persist`, `/mnt/vendor/persist`, `/data/vendor/tzstorage`, `/data/vendor_de/0/fpdata`)
- whether the TA accepts the unsigned `--hat-mode zero` auth token. `gatekeeper` mode is a TODO stub: it needs the QSEE keymaster and gatekeeper TAs (`OMAMOBILE_FP_KEYS=1`), whose first run provisions keys in the secure world
- the sensor circle: `720,2700,110` in 1440x3120 panel pixels is a placeholder. Pass the calibrated value with `--sensor` or `SENSOR=` in `paths.conf`
- libfprint's enrollment stage count (`OMAMOBILE_UDFPS_ENROLL_STAGES` 20 assumes the Pixel's G7). This sensor's count is unknown
- the touchscreen's input name (`s6sy761`, mainline driver)

## Build

The shim needs an NDK, r27 or later:

```sh
make shim NDK=/opt/android-ndk CHROOT=<extracted OxygenOS root>
```

The shim and the bridge need an AOSP or LineageOS tree of the vendor's
Android version. Make the HIDL headers once, then build both:

```sh
hidl-gen -o $GEN -L c++-headers \
  -r android.hardware:$AOSP/hardware/interfaces \
  -r android.hidl:$AOSP/system/libhidl/transport \
  android.hardware.biometrics.fingerprint@2.1
make AOSP=$AOSP GEN=$GEN CHROOT=<extracted OxygenOS root>
```

The props, logging and SELinux shim is the Pixel one, built from
`fingerprint/Makefile` against this chroot. Preload it first:
`LD_PRELOAD="omamobile-fp-shim.so omamobile-fp-ion-shim.so"`. The shim's
header explains how the two `ioctl()` wrappers chain.

The install layout: `omamobile-device-hotdog` (0.1.2+) installs
`/usr/lib/omamobile-fp-hotdog/{omamobile-fp-shim.so,omamobile-fp-ion-shim.so,omamobile-fp-hotdog-bridge,omamobile-fp-hotdog-chroot,props-hotdog.conf}`,
the unit (enabled), the compat driver's modprobe options, fprintd's drop-in
and the lock screen's PAM file. Build the three programs into the package
first: `make NDK=... OUT=$PWD/../../../packages/omamobile-device-hotdog/prebuilt`.
Only `root/`, the owner's OxygenOS files, is copied by hand.

## What was checked offline (2026-11-04)

- `clang -fsyntax-only -Wall -Wextra -Werror` on the ion shim, with host
  glibc headers. No NDK was installed, so there was no bionic build.
- `clang++ -std=c++17 -fsyntax-only -fno-exceptions -fno-rtti -Wall
  -Wextra -Werror` on the bridge, against hand-written stand-ins for the
  HIDL headers (signatures as in AOSP's fingerprint@2.1). This checks the
  C++ only, not the real ABI.
- `bash -n` on the runner; `systemd-analyze verify` on the unit (only the
  not-yet-installed ExecStart path was reported); `make -n` for both
  targets.
