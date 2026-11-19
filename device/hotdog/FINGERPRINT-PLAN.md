<!-- SPDX-License-Identifier: MIT -->
# Fingerprint plan (hotdog / SM8150): fingerprint unlock on the lock screen

**Status (2026-11-05): works** from the kernel and the package, with no hand
steps (§7 Results). The rest of this section is the plan as written before
the first run.

**Status (2026-11-04): theoretical. Written and compile-checked on the
laptop; nothing has run on the phone, and nothing may until the owner
approves each step below.** Kernel branch `omamobile-hotdog-fingerprint`
(worktree `~/omamobile-kernel/wt-hotdog-fingerprint`, output
`~/omamobile-kernel/out-hotdog-fingerprint`), on top of `omamobile-hotdog`
@ `970d093a4`. Userspace staging in [`fingerprint/`](fingerprint/), not
packaged. Overlays in [`overlays/`](overlays/).

The phone itself is not ready for this yet: [BRINGUP-M1](BRINGUP-M1.md) H2-H4
(the Arch root on userdata, booted from `boot_a`) come first. Every step
below assumes a phone that boots Omarchy Mobile with USB SSH.

**Goal.** Omarchy's lock screen accepts a finger on the under-display sensor
as an alternative to the PIN, exactly as on the Pixel 7 Pro
([cheetah FINGERPRINT-PLAN](../cheetah/FINGERPRINT-PLAN.md)). The top of the
chain is the same: Omarchy's lock runs `pam_fprintd` when
`fprintd-list $USER` shows a finger, fprintd uses libfprint's
`omamobile_udfps` driver, and that driver speaks a line protocol to a bridge.
Everything below the bridge is new for this phone:

```
Omarchy lock (PAM "omarchy-lock-fingerprint") / sudo / polkit
  -> fprintd -> libfprint omamobile_udfps            packages/libfprint (unchanged)
       | /run/omamobile-fp/sock/bridge.sock (root only, the cheetah line protocol)
  -> omamobile-fp-hotdog-bridge (bionic, in the chroot)  fingerprint/omamobile-fp-hotdog-bridge.cpp
       | HIDL android.hardware.biometrics.fingerprint@2.1 over hwbinder
  -> OnePlus's Goodix HAL, qseecomd (from the owner's own OxygenOS vendor image)
       | libQSEEComAPI: /dev/qseecom + /dev/ion        | /dev/goodix_fp, netlink 25
       |   ion -> omamobile-fp-ion-shim (LD_PRELOAD)   |
  -> qcom_qseecom_compat (kernel, NEW)               goodix-fp (kernel, existing + hotdog compatible)
       | SCM calls (QSEE app manager, listeners)       | gpio101 supply, gpio131 reset, gpio118 IRQ
  -> QSEE: the Goodix trusted app (capture, matching, templates) -> secure SPI -> sensor
       + the panel lit at full brightness above the sensor (panel driver "hbm")
```

---

## 0. Facts, from our own captures

All from the stock DT in `~/android/reference/hotdog` (`dtbo_b.img.gz`
entry 0, `dtb/lineage17-base-0.dtb`), decoded on the laptop. Nothing below
came from the phone at runtime.

| What | Stock | Used here |
| --- | --- | --- |
| Sensor node | `goodix_fp`, `compatible = "goodix,fingerprint"`, no SPI parent | `fingerprint` node, `oneplus,hotdog-udfps`, goodix-fp driver |
| IRQ | `fp-gpio-irq` tlmm 118; `fp_irq_init`: gpio, 2 mA, no bias, input | `interrupts-extended = <&tlmm 118 IRQ_TYPE_EDGE_RISING>` |
| Reset | `fp-gpio-reset` tlmm 131; `fp_reset_init`: 8 mA, pull-up | `reset-gpios = <&tlmm 131 GPIO_ACTIVE_LOW>` |
| Supply | `fp-gpio-enable` tlmm 101; `fp_vdd_init` output-high pull-up, `fp_vdd_dis_init` output-low pull-down | `regulator-fixed` `fp_vdd` on gpio101 |
| Sensor ID | `fingerprint_detect` (`oneplus,fpdetect`): tlmm 90 and PM8150 GPIO 3 | not used (one sensor type assumed; F2 reads them) |
| SPI | not in Linux's DT: owned by QSEE | nothing; **which QUP serial engine it is, is unknown** (§2) |
| QSEECOM | `qseecom@87900000`: `qcom,commonlib64-loaded-by-uefi`, `qcom,appsbl-qseecom-support`, `qcom,qsee-reentrancy-support = <2>`, `qcom,no-clock-support` | cmnlib is never loaded and no app-region notification is sent; re-entrancy phase 2 handling |
| Shared buffers | `qseecom_region` 0x9e400000, 0x1400000, no-map | mainline's `qseecom_mem` (same address), the compat driver's pool |
| smcinvoke | `smcinvoke@87900000` exists | mainline's `qcomtee` probes smcinvoke itself; not used by this design (§2) |
| Panel HBM | `hbm-on-command-5` (ends `51 0f ff`), `hbm-off-command` | replayed byte for byte by the panel driver's `hbm` attribute |

The command line already has `clk_ignore_unused pd_ignore_unused`
([device.conf](device.conf)), so the QUP clock that QSEE's SPI uses is not
turned off as unused. A Linux node that claims that QUP would still take it
(§2, U2).

## 1. What is reused, what is new

| Piece | State | Where |
| --- | --- | --- |
| fprintd, PAM, Omarchy lock | reused | stock packages, `packages/omamobile-fingerprint/vendor/pam.d` |
| libfprint `omamobile_udfps` | reused unchanged | `packages/libfprint` |
| Shell target (`omamobile.fingerprint`) | reused; reads the bridge's `state.json` | `packages/omamobile-shell` |
| goodix-fp kernel driver | **changed**: `oneplus,hotdog-udfps` compatible, root-only `notify` attribute for the HAL's display/touch events (event numbers are module parameters, unconfirmed) | `drivers/misc/goodix-fp.c` |
| Panel HBM | **new**: `hbm` attribute on the DSI device (`/sys/bus/mipi-dsi/devices/*/hbm`), stock sequences, off by itself after `hbm_timeout_ms` (3 s), refused while the panel is off, backlight restored after | `drivers/gpu/drm/panel/panel-samsung-oneplus-dsc.c` |
| `/dev/qseecom` | **new**: `qcom_qseecom_compat`, a subset of downstream's ioctl ABI on mainline SCM calls, buffers from `qseecom_mem` as dma-bufs; allow-lists for TAs and listeners, empty by default; RPMB listener refused unless `allow_rpmb` | `drivers/firmware/qcom/qcom_qseecom_compat.c`, `qcom_scm.c` (raw call export) |
| DT | **new**, all `disabled` | `sm8150-oneplus-hotdog.dts`; enabled by [`overlays/fp-sensor.dtso`](overlays/fp-sensor.dtso) and [`overlays/qseecom-compat.dtso`](overlays/qseecom-compat.dtso) |
| ion | **new**: LD_PRELOAD shim, `/dev/ion` allocations become compat dma-bufs | `fingerprint/omamobile-fp-ion-shim.c` |
| Bridge | **new**: HIDL 2.1 client, same line protocol and `state.json` as cheetah's | `fingerprint/omamobile-fp-hotdog-bridge.cpp` |
| Runner, unit | **new**, staged, enabled nowhere | `fingerprint/omamobile-fp-hotdog-chroot`, `fingerprint/omamobile-fp-hotdog.service` |
| Vendor files | **missing**: the HAL, qseecomd, libQSEEComAPI, the Goodix TA, from the owner's own OxygenOS image | F1 |

## 2. Unknowns (each one can sink the design; resolved read-only first)

- **U1. The vendor files and their names.** The HAL binary, its libraries,
  the TA's name and files (`.mdt` + `.bNN`), qseecomd and its listener set.
  The `.ops` in `~/android/reference/hotdog/msm/` is encrypted; the
  vendor image is on the phone's `super` partition (read-only copy) or in an
  OTA zip of the same build. F1.
- **U2. Which QUP serial engine QSEE's SPI uses,** and that no mainline
  node claims it. If Linux owns it, the TA's SPI transfers fail or collide.
  From the TA's strings or QSEE's log (`qcom_tzlog`), F1/F5.
- **U3. The downstream qseecom ABI as the owner's libQSEEComAPI uses it:**
  ioctl numbers, struct layouts (pointer sizes on arm64), which ioctls the
  HAL and qseecomd call. Every one is marked `VERIFY` in
  `qcom_qseecom_compat.c`. Disassembly of the owner's `libQSEEComAPI.so`,
  offline (F1).
- **U4. The SCM command IDs** for app start/shutdown and the listener
  calls (`VERIFY` in the driver), and how re-entrancy phase 2 answers.
  Only the phone can answer that, and a wrong call can wedge QSEE: F5 is
  one call per boot.
- **U5. Which listeners the TA needs.** The Goodix TA probably keeps its
  templates in QSEE's secure file system, through the file-system listener
  (files on userdata) and the RPMB listener (anti-rollback counters).
  F6 runs with every listener refused and records what the TA asks for.
- **U6. The HAL's netlink events** for touch down, touch up and "UI ready"
  (the panel lit). Defaults 4, 5, 6 in goodix-fp are guesses; the HAL's
  disassembly gives the real numbers (F1).
- **U7. The auth token.** Enrollment on Android carries a hardware auth
  token from Gatekeeper, signed by a key the HAL shares with KeyMaster in
  QSEE. Whether this HAL accepts a token with a zero HMAC is unknown; if
  not, the bridge needs the QSEE Gatekeeper and KeyMaster TAs as well (the
  same allow-list, more listeners). F8.
- **U8. The sensor position** on the panel. The bridge's 720/2700/110 is a
  placeholder; F9 measures it on the screen.
- **U9. smcinvoke.** SM8150's QSEE has smcinvoke, and mainline's
  `qcomtee` may bind it. The Goodix HAL uses the legacy qseecom path, so
  this design leaves smcinvoke alone; if `qcomtee` and the compat driver
  both talk to QSEE, their calls are not serialized against each other.
  Keep `qcomtee` unloaded during these steps (F4).

## 3. Rules for this subsystem

These are AGENTS.md section 1 applied to this stack.

- **Nothing in the chroot sees a real Android partition.** No bind mount of
  `/persist`, `/mnt/vendor/persist`, `/dev/block/*` or `/dev/sd*`. The TA's
  file-system listener gets a private state directory on userdata
  (`/var/lib/omamobile-fp-hotdog/{persist,data}`). If the TA needs
  calibration data from `persist`, it is copied **read-only, on the laptop,
  from the existing backup image** (`partitions/persist.img.gz`) and never
  written back.
- **RPMB is a one-way door.** A write through the RPMB listener changes
  counters that can't be rolled back, and stock Android on this phone
  depends on them. `allow_rpmb` defaults to N, the runner also refuses
  without `/etc/omamobile/fp-hotdog-allow-rpmb`, and turning either on is the
  owner's decision, recorded in §7 first (F7).
- **No TA loads and no listener registers by default.** `app_allowlist` and
  `listener_allowlist` are empty, and the module parameters are read-only
  after load, so only a human's `modprobe` line sets them.
- **One QSEE change per boot.** The first app start, the first listener
  registration and the first send each get their own boot, with a log
  stream to the laptop and `--watchdog` armed. QSEE errors often show up as
  a hang or a reset into the bootloader's crash dump mode. On this phone
  that means the Volume and Power keys, and **no stock slot to fall back
  to** ([BRINGUP-M1](BRINGUP-M1.md) §1).
- **Never unload `qcom_qseecom_compat` with a TA loaded or a listener
  registered.** Reboot instead. As on cheetah with storageproxyd: QSEE keeps
  its state until a reset.
- **HBM is announced before it is used.** It lights the whole panel at full
  brightness. It turns off by itself after 3 s, but tell the owner first.
- **No vendor file is committed,** and no identifier: no partition dumps,
  no TA, no HAL, no `getprop`.

## 4. Decisions for the owner

1. **Where the vendor files come from** (F1): a read-only copy of `super`
   from the phone, or an OTA of the same build.
2. **RPMB** (F7): whether the TA may write it at all. Without it,
   fingerprint unlock may simply be impossible on this phone under Linux.
3. **Persist calibration** (F6): whether the TA may read a copy of
   `persist`'s fingerprint files, taken from the backup image.

## 5. Kernel build

From the omarchy-mobile checkout:

```sh
KERNEL_DIR=~/omamobile-kernel/wt-hotdog-fingerprint \
KERNEL_OUT=~/omamobile-kernel/out-hotdog-fingerprint \
  DEVICE=hotdog bin/omamobile kernel
```

Since the plan passed (section 7), `device/hotdog/kernel.config` has
`CONFIG_QCOM_QSEECOM_COMPAT=m` (goodix-fp comes from `omamobile.config`),
and the DT enables the sensor, its supply switch and `qseecom-compat`, with
the sensor's SPI pins and clocks on the `fingerprint` node (goodix-fp keeps
them on while the sensor is powered). The bring-up overlays in `overlays/`
are no longer needed. Both modules autoload; the compat driver's
allow-lists come from `omamobile-device-hotdog`'s modprobe options, and the
stack starts from `omamobile-fp-hotdog.service`.

## 6. Runbook

Each step is the owner's to run or approve. Read-only first. Each has
Expect/Pass, a **Stop** condition, a Rollback and a risk level. Results go in
§7 with the date and `uname -r`.

### F0: preconditions (read-only; risk none)

- BRINGUP-M1 H4 done: Omarchy Mobile boots from `boot_a`, USB SSH works.
- The partition backups in `~/android/reference/hotdog/partitions/` check
  against `SHA256SUMS` (`sha256sum -c`), `persist` among them.
- **Stop** if either fails.

### F1: vendor files, offline (laptop; risk none for the phone)

1. Get the OxygenOS vendor image of the build the phone's firmware came from
   (owner's decision 1). Unpack it on the laptop under
   `~/android/reference/hotdog/vendor-fp/` (never in the repo).
2. Find: the fingerprint HAL service and its libraries, `qseecomd`,
   `libQSEEComAPI.so`, the Goodix TA (`*.mdt` + `*.b*`), its name as the
   HAL loads it, and any files the HAL reads from `/persist` or
   `/mnt/vendor/persist`.
3. Disassemble `libQSEEComAPI.so` and the HAL (REA, offline) for: the
   qseecom ioctls they issue (U3), the ion heap mask (shim), the netlink
   event numbers (U6), the TA name, the auth-token check (U7).
4. Fix every `VERIFY` the disassembly answers, in the driver, the shim and
   the bridge, and record what it said in §7.
- **Pass:** every name in `fingerprint/README.md`'s list is confirmed or
  corrected. **Stop** if the HAL needs an interface this design lacks
  (for example smcinvoke instead of qseecom: then the compat driver is the
  wrong tool, U9).

### F2: the sensor pins, read-only (risk low)

```sh
tools/phone-ssh 'cat /sys/kernel/debug/gpio | grep -E "gpio(90|101|118|131)\b"'
tools/phone-ssh 'grep -E "^ *(90|101|118|131):" /sys/kernel/debug/pinctrl/*tlmm*/pinmux-pins'
```

- **Expect:** none of the four is claimed. gpio101 is low (sensor
  unpowered).
- **Stop** if another driver owns one of them.

### F3: sensor power and goodix-fp (one boot; risk low)

Kernel of §5, `DTB_OVERLAYS=fp-sensor`, with `blacklist goodix_fp` in
`/etc/modprobe.d/omamobile-fp-hotdog-bringup.conf` before the boot. After
the boot, with a log stream to the laptop:

```sh
tools/phone-ssh 'modprobe goodix-fp && dmesg | tail -5 && ls -l /dev/goodix_fp'
tools/phone-ssh 'exec 3</dev/goodix_fp; sleep 2; cat /sys/kernel/debug/gpio | grep -E "gpio(101|131)\b"; exec 3<&-'
```

- **Expect:** `irq N, supply switched, netlink 25`; while the file is open,
  gpio101 high and gpio131 released; low and held after the close.
- **Stop** on any error, or if the IRQ storms (`/proc/interrupts`).
- **Rollback:** `rmmod goodix-fp` (nothing in the secure world is involved),
  then a boot without the overlay.

### F4: `/dev/qseecom` with nothing allowed (one boot; risk low)

`DTB_OVERLAYS="fp-sensor qseecom-compat"`, `blacklist qcom_qseecom_compat`
and `blacklist qcomtee` before the boot. Then:

```sh
tools/phone-ssh 'modprobe qcom_qseecom_compat && dmesg | tail -5 && ls -l /dev/qseecom'
tools/phone-ssh 'grep . /sys/module/qcom_qseecom_compat/parameters/*'
```

- **Expect:** the device exists, the version query worked (the dmesg line
  prints QSEE's version), every allow-list empty, `allow_rpmb` N.
- **Stop** on any SCM error, or if the version query hangs.
- **Rollback:** reboot (don't unload).

### F5: the first app lookup and start (IRREVERSIBLE only in that it starts QSEE code; one boot; risk medium)

Arm `--watchdog` and the log stream. A small test program (written in F1 from
what the disassembly showed) runs `APP_LOADED_QUERY` for the TA name, then
`LOAD_APP` with the TA's files, with
`modprobe qcom_qseecom_compat app_allowlist=<TA name>`. No listener is
allowed, no command is sent.

- **Expect:** an app id, and `qcom_tzlog` (if readable) shows the app
  loaded.
- **Stop** on a hang, a reset, `INCOMPLETE` at load (the TA wants a
  listener at start: record which), or any QSEE error code.
- **Rollback:** reboot. The TA is gone after the reset.

### F6: first commands, listeners still refused (one boot; risk medium)

The HAL in the chroot (runner `omamobile-fp-hotdog-chroot start hal`: qseecomd
and the HAL, no bridge), with the TA allowed and every listener refused, so
qseecomd's registrations fail by design. The HAL's init commands run.

- **Expect:** either the HAL's init completes (unlikely), or the driver logs
  which listener ids the TA asks for (`INCOMPLETE ... listener 0x...`) and
  answers each with a failure.
- **Record** the listener ids and what the HAL logged. **Stop** here and
  decide (owner) with that list: the file-system listener alone is low
  risk (files under `/var/lib/omamobile-fp-hotdog`); RPMB is F7.

### F7: RPMB (IRREVERSIBLE: needs the owner's written decision in §7)

Only if F6 showed the TA needs RPMB and the owner decided yes. Not written
out further until then.

### F8: the bridge and enrollment (announce: the panel goes to full brightness; risk medium)

Runner `omamobile-fp-hotdog-chroot start bridge`. `hbm` tested alone first:

```sh
tools/phone-ssh 'f=$(ls /sys/bus/mipi-dsi/devices/*/hbm); echo 1 > $f; sleep 1; echo 0 > $f'
```

Then an enrollment through the bridge socket (not fprintd yet), with the
auth-token mode from F1 (U7).

- **Pass:** `ENROLLED <id>`, then `AUTH` gives `MATCH <id>`.
- **Stop** on `ERROR` codes the HAL repeats, or HBM that doesn't turn off.

### F9: the sensor position (risk low)

Draw the target at the placeholder position, move it until the HAL reports
good captures in the middle, and record x, y and r in the bridge's options
and here.

### F10: fprintd and the lock screen

As cheetah F9-F10: `fprintd-enroll`, `fprintd-verify`, then the lock.
Packaging (a hotdog profile in `omamobile-fingerprint`, the unit enabled)
comes only after F10 passes.

## 7. Results

**2026-11-05, the stack from the kernel and the package**
(`7.3.0-rc6-omamobile-push1-g41a6c1235a0b`, `omamobile-device-hotdog`
0.1.2): `boot_a` flashed with that kernel (fastboot, tries back to 7), no
bring-up overlays or hand-loaded modules. At boot the DT's `/fingerprint`
and `/qseecom-compat` bound, `goodix-fp` switched the supply on,
`omamobile-fp-hotdog.service` started from its wants link and loaded
`gfp9558` (app id 3), and the HAL reported `spmt is pass`. The lock screen
asked fprintd at once; the first touch was `NOT_LIVE_FINGER` (quality 15),
the second matched (quality 36) and the owner was unlocked. On the old
kernel (`g5f2e6c289701`, nodes disabled) the same package's unit waited 90 s
for `/dev/goodix_fp` and `/dev/qseecom` and failed: the stack needs this
kernel.

**2026-11-04, owner's decision on RPMB (F7):** yes. Asked with the facts:
QSEE's Gatekeeper (in `keymaster64`, which the fingerprint TA trusts for
its enrollment tokens) keeps its records in an SFS file with anti-replay
data in RPMB, and without the RPMB listener every Gatekeeper enroll fails
(status -30, for any uid) before any listener request. RPMB writes are
permanent (an MSM restore does not undo them); calibration, IMEI and the
radio partitions are not in RPMB. The owner answered "Yes, enable RPMB".
Scope: `allow_rpmb=Y`, `/etc/omamobile/fp-hotdog-allow-rpmb`, and only the
UFS RPMB well-known LU for qseecomd; every partition stays read-only.

**2026-11-04, F2-F8 and fprintd: fingerprint unlock works**
(`7.3.0-rc6-omamobile-push1-g5f2e6c289701`, the compat driver as kernel
`6349bfc48`, built as an external module; the overlays applied at runtime).
The owner enrolled the right index finger through the shell's enrollment
screen (fprintd) and unlocked the lock screen with it. What it took, in
the order it was found:

- F2: gpio90/101/118/131 unclaimed, inputs pulled down. Pass.
- F3: `fp-sensor` applied at runtime; goodix-fp: `irq 187, supply
  switched, netlink 25`; opening `/dev/goodix_fp` raised gpio101 and
  released gpio131, the sensor's IRQ fired once. Pass.
- F4: `/dev/qseecom`, QSEE `0x1400000`, 20 MiB at `0x9e400000`, lists
  empty, `allow_rpmb` N. Pass.
- Driver ABI (kernel commit above): register/unregister/send were 2/3/1,
  the library uses 1/2/3; LOAD_APP's img_len includes the .mdt;
  GET_QSEOS_VERSION must answer 0x14 (or the library's
  QSEECom_receive_req never copies a listener's request); QSEE wants
  page-sized listener buffers.
- qseecomd: needs the runtime APEX (libandroidicu) and the VNDK paths, a
  private ssd file (it starts no listener without one), and to stay root
  (the shim ignores setuid/setgid/capset; the nodes are root 0600).
  Listeners it registers: 0xa FS, 0xb time, 0x7000 GP FS, 0x1100 request
  cancel, 0x9000 QISL, 0x3000 SSD (allowed), 0x2000 RPMB (allowed after
  the owner's decision), 0x4000 secure UI, 0xb000 SPL, 0xc000 output
  protection (refused).
- F5: `loaded TA gfp9558`; keymaster64 is found loaded (app id 1) and is
  never unloaded by the driver (not ours).
- The HAL: OnePlus's HIDL service only wraps the legacy module, so the
  bridge loads `hw/goodix.fod.msmnile.so` itself (fingerprint_device_t,
  no HIDL; built with the NDK). It needs servicemanager,
  vndservicemanager and hwservicemanager, heap 14 (4 MiB secure carve-out,
  CP_CDSP) besides qsecom 27/19, the factory calibration (persist's
  `data/{cali_data,caliParamsInfo,BMatrix,chartbase}.so`, copied from the
  verified backup into the private persist; the real one is untouched)
  or it reports `spmt is not pass`. CDSP isn't there
  (`GF_ERROR_DSP_NOT_AVAILABLE`); the HAL falls back to "normal
  authentication".
- Enrollment tokens: the TA checks them (`GF_ERROR_UNTRUSTED_ENROLL` for an
  unsigned one); keymaster's auth-token key reaches the TA only
  encapsulated (152 bytes). The bridge signs them with QTI's Gatekeeper
  (GatekeeperHalDevice, level 1, keymaster64), which keeps its records in
  RPMB: without the RPMB listener every enroll was -30.
- RPMB: librpmb reaches UFS RPMB as an sg node; the host loads no sg
  driver (it would expose every LU past the guard). The runner binds only
  the RPMB well-known LU's bsg node in, and the shim translates SG_IO
  v3 to bsg v4, GET_IDLUN and the three UFS descriptor fields librpmb
  reads (from sysfs). Gatekeeper enroll and verify then worked (a 58-byte
  handle, a 69-byte token).
- The sensor's SPI: QSEE drives QUP0 SE3 (gpio144-147), and nothing in
  Linux had its clocks on (an empty image: `GF_ERROR_PREPROCESS_FAILED`).
  `fp-spi3` enables the SE node for its pins (spi-geni defers: the SE is
  in GSI mode, no GPI DMA), and a bring-up module holds SE3's and the QUP0
  wrapper's clocks on. TODO: goodix-fp's GF_IOC_ENABLE_SPI_CLK.
- Light: an optical sensor needs the pixels under the finger lit. The
  panel has no LHBM: the shell draws a white disc over the sensor while a
  finger is down (`"illuminate": true` in the bridge's state), the bridge
  turns HBM on and waits 300 ms before `ui_ready`. The sensor's centre is
  720,2728 r 110 (LineageOS hotdog lineage-18.1: top-left 610,2618, size
  220). Dimming the rest of the screen (stock's notify_dim) made it worse
  (7 of 43 captures), and so did the real battery temperature for the
  algorithm (5 of ~40); disc alone at the default 0 C: 15 of 19 and 20 of
  20. Both are switches (OMAMOBILE_FP_DIM, OMAMOBILE_FP_BATTERY_TEMP).
- Vendor error 6 (one bad capture) no longer ends the operation, as
  LineageOS's FingerprintInscreen::handleError ignores it.
- Match: 2 of 4 attempts matched in a direct test (`Auth success`), the
  others `NOT_LIVE_FINGER`; the lock screen unlocked with the finger.

Open: the bring-up pieces (runtime overlays, the clock module, the module
built outside the tree, the test unit) go into the kernel and the device
package; liveness misses half the attempts (CDSP?); the bridge's id is
the HAL's 32-bit id as int32.

**2026-11-04, F1 (laptop only), part 1: the vendor files.** Source: the
owner's MSM package of OxygenOS 10.0.14 (`hotdog_14_O.22_210127`, build
`2101212101`), the one the phone was restored with on 2026-11-01, so its
TrustZone and modem images are the phone's. The `.ops` (md5 as in its
`md5sum_pack.md5`) decrypted with bkerler's `opscrypto.py` (MBox5);
`super.img` is sparse, LP 10.0 with `system_a`, `product_a`, `vendor_a`,
`odm_a`; `vendor_a` and `odm_a` are ext4. Everything is under
`~/android/reference/hotdog/ops/` and `vendor-fp/` (never in the repo).

- HAL: `vendor/bin/hw/android.hardware.biometrics.fingerprint@2.1-service`
  (init service `vendor.fps_hal`, user `system`, `class late_start`, starts
  `vendor.qseecomd`), which loads `hw/goodix.fod.msmnile.so` (needs
  `fp_hal_extension.so` and `vendor.oneplus.fingerprint.extension@1.0.so`),
  which uses `libgf_ud_hal.so` (`libQSEEComAPI.so`, `libion.so`,
  `vendor.goodix.hardware.biometrics.fingerprint@2.1.so`). The service
  checks `persist.vendor.oem.fp.version` against the module's version.
  `qseecomd` and `libQSEEComAPI.so` are in `vendor/`.
- **The TA is `gfp9558`** (U1). `goodix::initCustomizedParams` writes the
  name byte by byte (no plain string), and `CaEntry::startTap` tries
  `QSEECom_start_app(…, path, "gfp9558", 0x1000)` for each of
  `TA_PATH_LIST`: `/vendor/firmware_mnt/image`, `/system/etc/firmware`,
  `/firmware/image`, `/vendor/firmware`. Its files (`gfp9558.mdt`, `.b00`-`.b07`,
  6.5 MB) are in `NON-HLOS.bin`'s `image/`, beside `gfp9508`, `gfp9608`
  (other sensor models) and `fingerpr`. The runner's `TA_DIRS` and its
  `/firmware` bind already cover these paths.
- **The HAL starts a second app, `keymaster64`,** from `/firmware/image`
  (the same function, a second `QSEECom_start_app`). There is no
  `keymaster64.mdt` in `image/`: the keymaster app comes from the `km4`
  partition (`km4.mbn` in the package), which the boot chain loads, so the
  HAL most likely finds it already loaded. So `keymaster64` has to be on
  the compat driver's `app_allowlist` too (an owner's decision: it is the
  keymaster, not the fingerprint TA), and what the HAL sends it is open:
  probably the auth-token key (U7). Next in F1.
- U2: the TA drives the sensor through QSEE's secure SPI
  (`gf_bus_dc_secspi_*`); which QUP that is isn't in the TA. Still open.
- Still open for F1 step 3: the qseecom ioctls `libQSEEComAPI.so` issues
  (U3), the ion heap mask (`carveoutIonInit` in `libgf_ud_hal.so`), the
  netlink events (U6), the auth-token check (U7), and the system libraries
  the chroot needs from `system_a`.
