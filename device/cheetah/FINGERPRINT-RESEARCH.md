<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 Pro (cheetah) fingerprint on Omarchy Mobile: plan

Status (2026-10-12): research and design. **The current status and the
runbook are in [FINGERPRINT-PLAN.md](FINGERPRINT-PLAN.md)**, which supersedes
section 7 below (Trusty now runs on int through the AoC work; the branch was
brought up to int; the bridge, the libfprint driver and the package exist):
run nothing from section 7.
Kernel branch `omamobile-fingerprint` in `~/android/mainline/wt-fingerprint`,
build in `~/android/mainline/out-fingerprint`.

**Goal.** Enroll a finger and unlock Omarchy's lock screen with it. Omarchy's
lock already supports fprintd through PAM (`/etc/pam.d/omarchy-lock-fingerprint`),
so the work is everything between fprintd and the sensor.

**Bottom line.** The sensor is a Goodix optical under-display sensor ("G7",
codename *Delmar*) whose bus, firmware, capture and matching all live in a
signed, encrypted Trusty application (`g7.app`). A native libfprint driver is
not possible. What works is Google's own stack, unchanged:

- Trusty runs from the bootloader's `tzsw` image whatever kernel boots, and
  Linux talks to it exactly as Android does, through Google's GPL Trusty
  driver. We port that driver to 7.3.
- Google's fingerprint HAL, Trusty's storage proxy and app loader, and the
  Trusty KeyMint and Gatekeeper HALs run unmodified in a **minimal chroot**
  with its own binderfs instance and a small preload shim of ours. No
  Waydroid, LXC or Android init.
- The HAL does not need Pixel's display HAL: told that it does not control
  illumination, it leaves lighting the sensor to its client, which writes a
  sysfs control in our panel driver. Our DSI command driver
  (`gs-dsim-cmd` + `panel-samsung-s6e3hc4`, already in the main kernel) sends
  Google's local high brightness mode (LHBM) commands.
- Trusty's secure storage reaches the UFS RPMB through SCSI generic
  (`/dev/sg*`), as on stock.
- A bridge daemon in the chroot talks AIDL to the HAL, and a libfprint driver
  talks to the bridge, so fprintd, PAM and Omarchy's lock work as on a laptop.

Two facts that differ from what stock Android shows: the sensor's supply
(S2MPG13 LDO15S) is **off** when the bootloader hands over to Linux, and the
Trusty driver needs care with **CPU hotplug** (section 3.2).

Path abbreviations:

- `L/` = our kernel, branch `omamobile-fingerprint` (`~/android/mainline/wt-fingerprint`)
- `G/` = `~/android/omamobile/out-kernel/google/gs-6.1/private` (Google's GPL gs201 kernel)
- `R/` = `~/android/reference/cheetah-stock-cp2a-root` (stock live DT, dmesg)
- `V/` = the vendor partition of the factory image (CP2A.260705.006)

---

## 1. The sensor and how stock drives it

| Item | Value | Evidence |
|---|---|---|
| Sensor | Goodix optical UDFPS "G7", algorithm family "Delmar" | HAL source paths `vendor/goodix/udfps/g7_trusty/...` in the HAL binary; `[GF_HAL][DelmarSensor]` in `V/lib64/libgf_hal.so`; `ro.vendor.fingerprint.ta.name=g7.app` (`V/build.prop`) |
| Bus | SPI owned by the secure world. No REE SPI controller has a Goodix child; the TA reports its own SPI errors and the AP driver's clock ioctls are no-ops | `G/google-modules/soc/gs/drivers/input/fingerprint/gf_spi.h:105-106`; `R/live.dts` SPI nodes |
| AP-side driver | `goodixfp.ko`, a platform driver: `/dev/goodix_fp` (ioctls: reset, IRQ on/off), netlink protocol 25 for IRQ events, input device `goodix_fingerprint` | `gf_spi.c`, `netlink.c`, `gf_spi.h:82-113`; `R/dmesg.txt:646-650` |
| IRQ | `gpa9-2`, rising edge (GIC SPI 36) | `R/live.dts:12690-12700` (goodixfp), `:2862-2868` (gpa9) |
| Reset | `gpp1-1`, active low, on the PERIC0 pin controller (`0x10840000`) | `R/live.dts:4257-4263` (pins), `:3539-3558` (controller) |
| Supply | S2MPG13 LDO15S "L15S_UDFPS_AVDD", 2.5-3.3 V. Stock keeps it on only because Android's kernel marks it `regulator-always-on`; it is **off** at handover to Linux | `R/live.dts:14138-14147` |
| TA | `V/firmware/g7.app`, 13.5 MB, COSE_Sign1 `TrustyApp`, encrypted payload. Loaded by `trusty_apploader` once `ro.vendor.trusty.storage.fs_ready=1` | `V/etc/init/fingerprint-goodix.rc`; `R/dmesg.txt:6878-6990` |
| HAL | `V/bin/hw/android.hardware.biometrics.fingerprint-service.goodix`, AIDL `IFingerprint/default` **version 3**, with `libgf_hal.so`, `fp_utils.so`; talks to the TA over `/dev/trusty-ipc-dev0` | `V/etc/vintf/manifest/fingerprint-goodix.xml` |
| Secure storage | `storageproxyd -d /dev/trusty-ipc-dev0 -r /dev/sg1 -p /data/vendor/ss -t ufs`; `sg1` is the RPMB well-known LUN 49476 (0xC144) | `V/etc/init/hw/init.gs201.rc:747-750`; `R/dmesg.txt:2191` (`scsi 0:0:0:49476: Attached scsi generic sg1 type 30`) |
| Calibration | The HAL reads `/dev/block/by-name/mfg_data` | strings in `V/lib64/libgf_hal.so` |
| LHBM | `F0 5A 5A; B0 02 1E 92; 92 20 88 71 39 8A 01; B0 02 24 92; 92 2D 09 39; B0 02 27 92; 92 78; F0 A5 A5`, then `53 30` (WRCTRLD with the LHBM bit); off is `53 20`. Centre (0x2D0, 0x939) = (720, 2361), 6 mm radius. Times out after 3 s. Only on a lit panel | `G/google-modules/display/samsung/panel/panel-samsung-s6e3hc4.c:717-734,1235-1265`; `panel-samsung-drv.c:3520-3560,4852-4925`; `panel-samsung-drv.h:732` |
| Touch | Sensor at (720, 2360) in panel pixels | `G/devices/google/pantah/dts/gs201-cheetah-touch.dtsi:58` |

**Capture and matching happen in the TEE.** The TA does the SPI capture,
anti-spoofing, template extraction and matching, and returns a
HardwareAuthToken (HAT). Enrollment needs a HAT from Gatekeeper, so a
Gatekeeper enrollment comes first. Templates live in Trusty secure storage.

**Trusty itself.** Stock loads `trusty-core`, `trusty-log`, `trusty-ipc`, then
`trusty-virtio` (`R/dmesg.txt:679-890`): "trusty version: Project: cloudripper",
"selected api version: 5", two vrings, "trusty_ipc virtio0: is online". It
uses one interrupt, GIC SGI 13 (`R/interrupts.txt:150`), i.e. Trusty IPI 13
through `ipi-range = <8 15 8>` (`R/live.dts:346-360`).

---

## 2. Architecture

```
 Omarchy lock (PAM omarchy-lock-fingerprint)
   -> fprintd -> libfprint driver "omamobile_udfps"      (host, glibc)
        | Unix socket /run/omamobile-fp/bridge.sock
 ---------------------------- chroot (private mount + PID namespace,
 |  omamobile-fp-bridge  (bionic, libbinder_ndk)          own binderfs,
 |    | AIDL IFingerprint v3 / IGatekeeper / ISharedSecret  host netns)
 |  Goodix HAL   Gatekeeper HAL   KeyMint HAL   storageproxyd   servicemanager x2
 |    all with LD_PRELOAD=omamobile-fp-shim.so
 ----------------------------
        | /dev/trusty-ipc-dev0   /dev/goodix_fp + netlink 25   /dev/sg (RPMB)
 kernel: trusty_core/log/ipc/virtio, goodix_fp, sg, panel local_hbm_mode
        | SMC                                  | DSI (LHBM)
 Trusty (tzsw): g7.app, KeyMint, Gatekeeper, storage   panel S6E3HC4
```

The bridge also reads the touchscreen (finger on the sensor area) and drives
LHBM, because the HAL's touch and illumination inputs come from its client
(section 4.7).

---

## 3. Kernel (built, all disabled by default)

Branch `omamobile-fingerprint` on `omamobile` @ `e7cb10fe5`, one commit per
subsystem: `d50eb73ae` kthread export, `0fa5efc32` vendor prefix `android`,
`210377ee6` Trusty binding, `edae3bf75` Trusty driver, `5a9cf359f` Trusty CPU
hotplug, `35dc73b3e` Goodix binding, `f43b95ea4` Goodix driver, `40c4e1090`
panel LHBM, `0c28d9948` gs201 Trusty node, `4d4c7bef5` PERIC0 pinctrl,
`0c81eda5b` cheetah fingerprint node. Built with `bin/omamobile kernel`,
`modules` and `images` (`logs/fingerprint-*.log`, all exit 0): release
`7.3.0-rc6-omamobile-push1-00066-g0c81eda5bfde`, 1717 modules, images in
`~/android/mainline/out-fingerprint/images`.
The new C builds with `W=1` and no warnings; the bindings pass
`dt-doc-validate` and yamllint; `dt-validate` (dtschema 2026.9) of the default
DTB and of the DTB with both fingerprint overlays reports only the existing
`soc_id` and framebuffer `post-init-providers`.
Config: `kernel/configs/omamobile.config` (`TRUSTY=m`, `TRUSTY_LOG=m`,
`TRUSTY_VIRTIO=m`, `TRUSTY_VIRTIO_IPC=m`, `GOODIX_FP=m`, `CHR_DEV_SG=m`;
binder and binderfs were already built in). `omamobile-device-cheetah` gains
`modprobe.d/omamobile-fingerprint.conf`, which blacklists every one of these
modules from autoload (and orders `trusty_ipc` before `trusty_virtio`, as
stock loads them).

### 3.1 Trusty driver (`L/drivers/trusty/`)

Google's GPL driver from `G/google-modules/trusty` (the version that runs on
the stock kernel and negotiates API version 5), ported to 7.3:

- `trusty-core` (`trusty.c`, `trusty-irq.c`, `trusty-mem.c`,
  `trusty-sched-share.c`, `trusty-smc-arm64.S`): SMC calls, FF-A memory
  sharing, per-CPU nop threads, IRQ forwarding.
- `trusty-log`, `trusty-virtio`, `trusty-ipc` (`/dev/trusty-ipc-dev0`, the
  `tipc` character device the HALs open). `trusty-test` is left out.
- API changes only: void `remove`, the `virtqueue_info` form of `find_vqs`,
  `class_create()` without owner, `MODULE_IMPORT_NS("DMA_BUF")`, the
  `_unlocked` dma-buf mapping calls, `MODULE_DEVICE_TABLE(of/virtio, ...)`.
- IPIs: Trusty IPI 8-15 map to GIC SGIs 8-15. Mainline GICv3 accepts a
  one-cell SGI specifier and keeps SGIs 0-7 for its own IPIs, so the stock
  `ipi-range` works unchanged.

DT: a `trusty` node at the root of `gs201.dtsi` with the `irq`, `log` and
`virtio` children of the stock DT, `status = "disabled"`; binding
`firmware/android,trusty-smc-v1.yaml` (and the `android` vendor prefix).
Enabled for bring-up by `device/cheetah/overlays/fingerprint-trusty.dtso`.

### 3.2 CPU hotplug

Trusty schedules its own threads only on the CPU whose nop thread calls into
it, and a trusted application may be pinned to one CPU. While that CPU is
offline the application never runs, and its client (the HAL) blocks forever.
Android never takes CPUs offline at runtime on this phone, so stock never
hits this; Linux userspace (power tuning, screen-off hooks) can. Two commits:

- **The nop threads must stay bound to their CPU.** Google's driver creates
  them with `kthread_create_on_cpu()` and marks them with
  `kthread_set_per_cpu()`, which mainline does not export. Without that
  mark, `kthread_unpark()` does not rebind a thread when its CPU comes back,
  and waking it while the CPU is online but not yet active lets the
  scheduler move it to another CPU for good: the binding is lost after the
  first hotplug cycle. We export `kthread_set_per_cpu()` (as Android
  kernels do), and the cpuhp callbacks now use the per-CPU state of the CPU
  going up or down (`per_cpu_ptr(..., cpu)`) instead of `this_cpu_ptr()`.
- `trusty_core.allow_cpu_offline` (default 0): while Trusty is bound, taking
  a CPU offline at runtime fails with `-EBUSY` and a rate-limited warning.
  Suspend, hibernation (`cpuhp_tasks_frozen`), shutdown, reboot and kexec
  (`system_state != SYSTEM_RUNNING`) and driver removal still take CPUs down.

Anything in Omarchy Mobile that wants to offline CPUs for power must instead use
cpufreq/idle states, or set `allow_cpu_offline=1` and accept that
fingerprint can hang.

### 3.3 Goodix sensor control (`L/drivers/misc/goodix-fp.c`)

Our own driver with the vendor driver's userspace interface (the HAL is the
ABI): `/dev/goodix_fp` with the `GF_IOC_*` ioctls (`'g'`, 0-14; clock and
power ioctls accepted and ignored as on stock), a netlink socket on protocol
25 that sends a one-byte event 1 to the last process that wrote to it for each
IRQ, and the `goodix_fingerprint` input device. Differences from stock: the
supply (`vdd-supply`) is enabled on first open and disabled on last close,
with the sensor held in reset while unpowered; no unbinding from sysfs while
open. The netlink socket is in the initial network namespace only, so the
chroot must not unshare the network namespace.

DT: `fingerprint` node in `gs201-cheetah.dts` (`goodix,g7-udfps`, IRQ
`<&gpa9 2 IRQ_TYPE_EDGE_RISING>`, `reset-gpios = <&gpp1 1 GPIO_ACTIVE_LOW>`),
plus the PERIC0 pin controller (`pinctrl@10840000`, GIC SPI 664, alias
`pinctrl4`, all 20 `gpp0`-`gpp19` banks; driver data was already upstream),
both disabled. Binding `misc/goodix,g7-udfps.yaml`. Enabled for bring-up by
`device/cheetah/overlays/fingerprint-sensor.dtso`.

**Supply dependency.** LDO15S can only be switched through ACPM (the PMIC is
behind the APM firmware; `ACPM-PLAN.md`). Until the S2MPG13 regulator driver
exists, the node has no `vdd-supply` and the driver warns that the rail must
be switched elsewhere. Never touch LDO14S (NFC) while testing LDO15S.

### 3.4 Panel: local high brightness mode (`L/drivers/gpu/drm/panel/panel-samsung-s6e3hc4.c`)

Two attributes on the panel's backlight device, named as in Google's driver
so the chroot can expose them as `panel0-backlight`:

- `local_hbm_mode` (0/1): on sends Google's LHBM sequence, then WRCTRLD
  `0x30`; off sends WRCTRLD `0x20`. Refused (`-EPERM`) while the panel is
  blanked, in display-off, at brightness 0 (pixel-off), and unless
  `panel_samsung_s6e3hc4.allow_lhbm=1`.
- `local_hbm_max_timeout` (ms, 1-3000, default 3000): LHBM switches itself off
  after this long; writing 1 again restarts the timer, as in Google's driver.
  Blanking, display off and brightness 0 turn LHBM off first.

A driver mutex now serializes brightness, power and LHBM commands.

Not reproduced from Google's driver: LHBM only at the panel's peak refresh
rate, and sending it right after a vblank so it lands in one frame. We have
neither modesetting nor vblank events; the bootloader's mode is what runs.
Stage F7 checks what that does on the panel.

---

## 4. Userspace

### 4.1 Vendor files: `tools/extract-fingerprint-vendor`

Never committed. The tool takes the user's factory image (outer zip or
`image-cheetah-*.zip`), reads `vendor.img` and `system.img` with `debugfs`
(no mount, no root), the bionic linker and libc from the
`com.android.runtime` APEX, and copies exactly:

- vendor: the Goodix HAL, `android.hardware.gatekeeper-service.trusty`,
  `android.hardware.security.keymint-service.trusty`, `storageproxyd`,
  `trusty_apploader`, `vndservicemanager`, `firmware/g7.app`, `build.prop`,
  `etc/vintf/`;
- system: `servicemanager`, `build.prop`, `etc/vintf/`;
- the `DT_NEEDED` closure of all of them, vendor copies first for vendor
  binaries and system first for system ones.

From CP2A.260705.006 that is 145 files, 30 MB (48 vendor libraries, 21 system
ones). Output: `root/{system,vendor,apex/com.android.runtime}`, a `MANIFEST`
with sha256 and mode per file, and `SOURCE` (the vendor build fingerprint).
Checked: every symlink resolves inside the tree, `g7.app` is a TrustyApp
package, the HAL is the G7 one, the image is for cheetah.

Not needed: `hwservicemanager` (without it, HIDL lookups fail at once), the
Titan M2 (citadel) KeyMint, secretkeeper, `trusty_metricsd`, the face TA.

### 4.2 The chroot: `omamobile-fp-chroot` (`packages/omamobile-fingerprint/lib/`)

Installed as `/usr/lib/omamobile-fp/` (image, shim, `props.conf`); state in
`/var/lib/omamobile-fp` (0700). `start` re-executes itself under
`unshare --mount --pid --fork --kill-child` (a private mount and PID
namespace; **not** a network namespace) and builds, on a tmpfs at
`/run/omamobile-fp/root`:

| Path in chroot | What |
|---|---|
| `/system`, `/vendor`, `/apex` | the extracted image, bind-mounted read-only |
| `/omamobile/omamobile-fp-shim.so` | the preload shim, read-only |
| `/dev` | tmpfs: `null zero full random urandom kmsg`, `trusty-ipc-dev0`, `trusty-log0`, `goodix_fp`, `sg-rpmb` (the RPMB LUN's sg node only, found by its SCSI address `*:49476`) |
| `/dev/binderfs` | a **private binderfs instance**; `/dev/binder`, `/dev/hwbinder`, `/dev/vndbinder` link into it |
| `/dev/__omamobile_props__` | tmpfs property store (section 4.4) |
| `/dev/block/by-name/mfg_data` | a read-only bind of `/var/lib/omamobile-fp/mfg_data.img`, a copy made once; the HAL never sees the partition |
| `/sys` | tmpfs skeleton, read-only: `devices/system/cpu`, `firmware/devicetree`, `class/thermal` (read-only binds), `module/trusty_core`, `module/trusty_virtio`, a fake `devices/platform/exynos-drm/primary-panel/panel_name` = `sdc-s6e3hc4` (the stock `exynos_drm.panel_name`, `R/dmesg.txt:111`), and `class/backlight/panel0-backlight/` with our real `local_hbm_mode` and `local_hbm_max_timeout` bound in |
| `/proc` | a new proc for the PID namespace |
| `/data` | `/var/lib/omamobile-fp/data`: `vendor/ss` (Trusty TD files), `vendor/ss/persist` (TDP files, section 5), `vendor_de/0/fpdata`, `vendor/fingerprint` |

Each Android process runs as `env -i LD_LIBRARY_PATH=... LD_PRELOAD=/omamobile/omamobile-fp-shim.so chroot ROOT ...`
with `LD_LIBRARY_PATH` `/vendor/lib64:/vendor/lib64/hw:/system/lib64` for
vendor binaries and `/system/lib64:/vendor/lib64` for system ones (there is no
linkerconfig, so the linker uses one namespace and this search order). Output
goes to the journal with a `[service]` prefix. If any service exits, the whole
stack stops and systemd restarts it.

Start order and stages (`start storage|apploader|keys|hal`):

1. `servicemanager` (`/dev/binder`), `vndservicemanager /dev/vndbinder`;
2. `storageproxyd -d /dev/trusty-ipc-dev0 -r /dev/sg-rpmb -p /data/vendor/ss -t ufs`,
   then wait for `ro.vendor.trusty.storage.fs_ready=1` (it sets it);
3. `trusty_apploader /vendor/firmware/g7.app` (blocks until storage is up);
4. KeyMint and Gatekeeper (`--dev /dev/trusty-ipc-dev0`);
5. the Goodix HAL;
6. the bridge (section 4.7).

### 4.3 Binder without SELinux

binderfs gives the chroot its own context manager. One kernel interaction
needs care: `servicemanager` asks for its callers' security context
(`BINDER_SET_CONTEXT_MGR_EXT` with `FLAT_BINDER_FLAG_TXN_SECURITY_CTX`).
Binder then calls `security_secid_to_secctx()` for every transaction to it,
and with our LSM list (`landlock,lockdown,yama,integrity,bpf`) that returns
`-EOPNOTSUPP`, so every transaction would fail (`L/drivers/android/binder.c`
around line 3366). The shim makes that ioctl fail, and libbinder falls back to
the plain `BINDER_SET_CONTEXT_MGR`; it also turns `setRequestingSid()` into a
no-op. (The same issue will meet Waydroid.)

### 4.4 The preload shim: `fingerprint/shim/omamobile-fp-shim.c`

Ours, MIT, about 600 lines of C, built for bionic with the NDK
(`fingerprint/Makefile`; it builds warning-free with `-Wall -Wextra -Werror`
against bionic). It replaces only what Android's init and system services
would provide:

- **Properties:** `__system_property_{find,get,read,read_callback,serial,area_serial,foreach,set,wait,wait_any}`
  on a directory with one file per property, shared by every process in the
  chroot. The runner fills it from both `build.prop` files, then
  `lib/props.conf`, then `/var/lib/omamobile-fp/props.conf`.
  `ro.*` properties are write-once. `storageproxyd`'s `fs_ready` goes through
  it, which is how the runner knows storage is up.
- **Logging:** liblog's entry points print `P tag[tid]: message` to stderr,
  filtered by `OMAMOBILE_FP_LOGLEVEL`.
- **SELinux:** fixed context, every check allowed (`getcon`, `getpidcon`,
  `selinux_check_access`, `selabel_lookup`, the `selinux_android_*_handle`
  calls, `selinux_status_*`). The chroot is the trust boundary.
- **Binder:** section 4.3.
- **Absent services:** `AServiceManager_{get,check,waitFor}Service` and
  `isDeclared` return nothing at once for power, Pixel power, sensors, stats,
  vold, suspend, thermal and Pixel display (otherwise each lookup waits about
  5 s, and the HAL's ambient-light path waits forever). More prefixes in
  `OMAMOBILE_FP_NO_SERVICES`.
- **Wake locks:** accepted and dropped.

`packages/omamobile-fingerprint/lib/props.conf` sets what makes the HAL fit:
`persist.vendor.udfps.lhbm_controlled_in_hal_supported=false` (the HAL then
reports `halControlsIllumination=false` and never asks for the display HAL),
`als_feed_forward_supported=false` and `sensor_listener_supported=false` (no
light sensor service), `fps_touch_handler_supported=false` (as stock cheetah:
touch comes from the client), plus `ro.hardware` and
`ro.boot.hardware.platform`.

### 4.5 Secure storage

`storageproxyd` serves Trusty's file systems: TP lives in the RPMB itself
(`/dev/sg-rpmb`, SCSI SECURITY PROTOCOL IN/OUT through SG_IO), TD files in
`/data/vendor/ss`, TDP files in `/data/vendor/ss/persist`. Each file system's
super block is anchored in the RPMB. Stock RPMB state is reused as it is;
the TD file system starts empty on Linux (Android's lived on userdata, which
now holds Arch). Section 5 covers what this means for slot A.

### 4.6 KeyMint, Gatekeeper and the auth token

The fingerprint TA accepts an enrollment only with a valid HAT, and HATs are
MAC'd with a key the Trusty KeyMint TA holds once the shared-secret protocol
has run. So before enrolling, the bridge does what keystore2 does on Android:

1. `ISharedSecret/default` (Trusty KeyMint): `getSharedSecretParameters()`,
   then `computeSharedSecret([params])`. Only Trusty takes part; StrongBox
   (Titan M2) is not needed.
2. `IGatekeeper/default`: `enroll(uid 0, -, -, secret)` once, keeping the
   password handle in `/var/lib/omamobile-fp/gatekeeper` (0600). The secret is
   32 random bytes kept next to it; it is not the user's password. fprintd's
   own polkit check (the user's password) is what guards enrollment.
3. Per enrollment: `ISession.generateChallenge()` ->
   `IGatekeeper.verify(0, challenge, handle, secret)` -> HAT ->
   `ISession.enroll(HAT)`.

### 4.7 The bridge and fprintd (written: `fingerprint/bridge/`, `packages/libfprint/`; the protocol in FINGERPRINT-PLAN.md replaces the one below)

**`omamobile-fp-bridge`** (ours, C, bionic, in the chroot, links the image's
`libbinder_ndk.so`). It speaks the frozen AIDL directly
(`hardware/interfaces/biometrics/fingerprint/aidl/aidl_api/.../3`, hash
`637371b53fb7faf9bd43aa51b72c23852d6e6d96`), with no generated code:

- `IFingerprint` (descriptor `android.hardware.biometrics.fingerprint.IFingerprint`):
  1 `getSensorProps`, 2 `createSession(sensorId, userId, ISessionCallback)`.
- `ISession`: 1 `generateChallenge`, 2 `revokeChallenge`, 3 `enroll(HAT)`,
  4 `authenticate(operationId)`, 6 `enumerateEnrollments`,
  7 `removeEnrollments`, 11 `close`, 12 `onPointerDown(id, x, y, minor, major)`,
  13 `onPointerUp(id)`, 14 `onUiReady`. Calls 3 and 4 return an
  `ICancellationSignal`; `cancel()` is its call 1.
- `ISessionCallback`, a local binder the bridge implements (not one-way):
  1 `onChallengeGenerated` ... 5 `onEnrollmentProgress(id, remaining)`,
  6 `onAuthenticationSucceeded(id, HAT)`, 7 `onAuthenticationFailed`,
  2-4, 8-16 as in the AIDL; plus `getInterfaceVersion` (0xFFFFFE -> 3) and
  `getInterfaceHash` (0xFFFFFD).

The HAL allows **one session at a time**; the bridge owns it for its whole
life and serializes requests. At start it reads `getSensorProps()` (sensor
centre and radius; expected near (720, 2360) and 120 px) and writes them to
`/run/omamobile-fp/sensor` for the lock screen to draw the target.

During enroll and verify the bridge reads the touchscreen
(`/dev/input/by-path/...-event`, bound into the chroot): when a finger lands
inside the sensor circle it writes `local_hbm_mode=1`, waits for the circle
to be on the panel (a few frames; tuned in F8), calls `onPointerDown` and
`onUiReady`; on lift, `onPointerUp` and `local_hbm_mode=0`. LHBM is never
left on: the panel driver's 3 s cap is the backstop.

Socket protocol (`/run/omamobile-fp/bridge.sock`, bound into the chroot as
`/dev/socket/omamobile-fp`, SOCK_SEQPACKET, root and the `fprintd` user
only), one text message per packet:

```
-> ENROLL | VERIFY | IDENTIFY | LIST | DELETE <id> | CANCEL
<- READY x y r | ACQUIRED <code> | PROGRESS <id> <remaining>
   MATCH <id> | NOMATCH | LIST <id>... | DELETED <id> | ERROR <code> | LOCKOUT <ms>
```

**libfprint driver `omamobile_udfps`** (in our libfprint package, like our
Mesa): a virtual-type device enabled when the bridge socket exists, features
VERIFY, IDENTIFY, STORAGE (list and delete). The print's driver data is the
HAL's enrollment id. Enroll stages map to the HAL's `remaining` count.
fprintd, `pam_fprintd` and `/etc/pam.d/omarchy-lock-fingerprint` are then
used unchanged. The password stays as the fallback.

Lock screen: draw a target at the sensor while waiting for a finger
(Omarchy Mobile's lock plugin). The screen must be lit (LHBM works only on a lit
panel), so unlock is "wake, then touch".

### 4.8 systemd

`omamobile-fp.service` (`ExecStart=/usr/lib/omamobile-fp/omamobile-fp-chroot start hal`,
`Restart=on-failure`, after the modules are loaded and `/dev/trusty-ipc-dev0`
exists) and fprintd's normal activation. Not enabled until stage F10.

---

## 5. Secure storage, the RPMB and dual boot

- **The first `storageproxyd` run (gate F4) is not reversible.** Trusty writes
  the RPMB (monotonic write counter, file-system super blocks). There is no
  backup or restore of RPMB content.
- **Slot A Android's TD state is already gone.** Its `/data/vendor/ss` lived
  on userdata, which holds Arch. When Linux brings up TD, Trusty starts a new
  TD file system and its RPMB anchor moves on. If Android ever runs again it
  has to be factory-reset anyway (its userdata is gone), and Trusty starts TD
  again for it then. Fingerprints, Gatekeeper state and anything else the TAs
  keep in TD do not cross between the two systems.
- **TDP (stock: `persist/ss`).** The `persist` partition stays read-only (the
  initramfs storage guard; the README's ground rules). At setup the runner's
  operator copies `persist/ss` once, read-only, into
  `/var/lib/omamobile-fp/persist-ss`, and Trusty then uses the copy. The copy
  and the RPMB stay consistent for Linux; the real `persist/ss` becomes
  stale, so a later Android may see its TDP state as rolled back. The
  alternative is to let Linux write the real `persist/ss` (add `persist` to
  the guard's allowlist): consistent for both systems, at the cost of writing
  a calibration partition. That is a decision for the user, not taken here.
  Back up `persist` (and `mfg_data`) to the laptop before F4 either way.
- **What the TAs keep in TP/TDP is not visible** (encrypted TAs). Treat any
  Android use of slot A after F4 as "factory reset first".
- **SCSI generic is a raw path to every UFS LUN.** `/dev/sgN` for the main LUN
  can write any partition past the block layer's read-only guard. `sg` stays
  blacklisted; the runner loads it, finds the RPMB LUN and binds only that
  node into the chroot. The host's sg nodes are root-only. A later
  improvement: a udev rule that removes every sg node but the RPMB one.

---

## 6. Risks and open questions

| Risk | Mitigation |
|---|---|
| Trusty probe hangs or crashes the secure world | It only issues fast SMCs that stock issues at boot. Gate F2 runs with the log streamed and the watchdog armed (`tools/fingerprint-capture --watchdog`) |
| PERIC0 pin controller first use | `cmu_peric0` already probes (its registers are live); the pin controller only gets GPIO and EINT setup |
| LDO15S switched wrongly | Waits for the ACPM regulator driver; never LDO14S; check the rail in `regulator_summary` before opening `/dev/goodix_fp` |
| LHBM at the bootloader's refresh rate, not on a TE edge | Gate F7 by eye, 3 s cap in the driver, `allow_lhbm` off by default |
| HAL waits on something we do not provide | Stage it alone (`start hal`) and read the log; extend the shim's absent-service list or `props.conf` |
| HAL/TA version mismatch | Both come from the same factory image; the HAL logs "HAL/TA version is match" |
| TA pinned to an offline CPU | `allow_cpu_offline=0` |
| Chroot binaries escaping | No SELinux; root in the chroot is root. Same trust as any root daemon: Google's signed binaries from the user's own image. Later: drop capabilities per service, seccomp |
| Enrollment lockout | The TA's own lockout; `resetLockout` needs a fresh HAT, which the bridge can get from Gatekeeper |
| `sg` raw access | Section 5 |

Open: the exact delay between LHBM on and `onUiReady` (F8); whether the HAL
needs `/sys/firmware/devicetree/base/chosen/plat` (the bootloader adds it to
our DTB too; F6 checks); whether `storageproxyd` waits on vold for
checkpointing (the shim says vold is absent).

---

## 7. Runbook (superseded by FINGERPRINT-PLAN.md section 6)

Each gate is one change, with its expected result, risk and rollback. Run
them in order; stop at the first surprise. `$O` = `~/android/mainline/out-fingerprint`,
`$D` = `$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb`.

### F0 (laptop, offline)

```sh
cd ~/Projects/omarchy-mobile
KERNEL_DIR=~/android/mainline/wt-fingerprint KERNEL_OUT=$O bin/omamobile kernel   > logs/fp-kernel.log 2>&1
KERNEL_DIR=~/android/mainline/wt-fingerprint KERNEL_OUT=$O bin/omamobile modules  > logs/fp-modules.log 2>&1
KERNEL_DIR=~/android/mainline/wt-fingerprint KERNEL_OUT=$O bin/omamobile initramfs > logs/fp-initramfs.log 2>&1
KERNEL_DIR=~/android/mainline/wt-fingerprint KERNEL_OUT=$O bin/omamobile images   > logs/fp-images.log 2>&1
tools/extract-fingerprint-vendor -o out/fingerprint-vendor ~/android/factory/cheetah-*/image-cheetah-*.zip
make -C fingerprint NDK=/opt/android-ndk OUT=$PWD/out/fingerprint
```

Install the device package with `omamobile-fingerprint.conf` (blacklist) first.
No risk to the phone.

### F1: new kernel, default DTB (all fingerprint nodes disabled)

```sh
KERNEL_DIR=... KERNEL_OUT=$O bin/omamobile modules-push && KERNEL_DIR=... KERNEL_OUT=$O bin/omamobile push
tools/phone-ssh 'uname -r; lsmod | grep -cE "^(trusty|goodix_fp|sg) "; ls /sys/class/backlight/*/local_hbm_mode; cat /sys/class/backlight/*/local_hbm_mode'
```

Expect: boots as before (touch, display brightness, USB); 0 of our modules
loaded; `local_hbm_mode` exists and reads 0. `echo 1 > .../local_hbm_mode`
fails with "Operation not permitted" (`allow_lhbm=0`).
Risk: the panel driver changed (a mutex around brightness). Rollback:
power-cycle (ABL falls back to slot A after its retries) or push the previous
out dir's images.

### F2: Trusty probes (overlay `fingerprint-trusty.dtso`)

```sh
cp "$D" "$D.default"
$O/scripts/dtc/dtc -q -I dts -O dtb -o out/fingerprint-trusty.dtbo device/cheetah/overlays/fingerprint-trusty.dtso
$O/scripts/dtc/fdtoverlay -i "$D.default" -o "$D" out/fingerprint-trusty.dtbo
bin/omamobile images && bin/omamobile push         # with KERNEL_DIR/KERNEL_OUT as above
tools/fingerprint-capture --watchdog trusty-core
tools/fingerprint-capture trusty-log
tools/fingerprint-capture trusty-ipc
tools/fingerprint-capture hotplug
```

Expect, as `R/dmesg.txt:737-890`: "trusty version: Project: cloudripper, Build:
...", "selected api version: 5" (a lower version means an older Trusty, still
fine); `/dev/trusty-log0`, Trusty's own log lines; two vrings and
"trusty_ipc virtio0: is online"; `/dev/trusty-ipc-dev0`; one `trusty` line in
`/proc/interrupts` on GICv3 13. `hotplug`: "refusing to take cpu 7 offline",
CPU 7 still online.
Risk: first SMCs into Trusty from our kernel; a hang resets through the
watchdog. Rollback: reboot (modules stay blacklisted), or
`cp "$D.default" "$D"` and re-push the images.

### F3: RPMB node

Historical (2026-10-12 design). **Run F3 from
[FINGERPRINT-PLAN.md](FINGERPRINT-PLAN.md) section 6, not from here.** The
copy commands this section first had are removed: they found the partitions
through `/dev/disk/by-partlabel`, which this root doesn't have, and mounted
`persist` plain `-o ro`, which can replay a dirty ext4 journal.

```sh
tools/fingerprint-capture sg
```

Expect: one sg node whose device is `0:0:0:49476` (the RPMB LUN). Risk:
none written; sg nodes exist for all LUNs until reboot. Rollback:
`modprobe -r sg`.

### F4: secure storage (irreversible: first RPMB write from Linux)

```sh
tar -C out/fingerprint-vendor -cf - root MANIFEST SOURCE |
  tools/phone-ssh 'install -d /usr/lib/omamobile-fp && tar -C /usr/lib/omamobile-fp -xf -'
for f in out/fingerprint/omamobile-fp-shim.so fingerprint/props.conf fingerprint/omamobile-fp-chroot; do
  tools/phone-ssh "cat > /usr/lib/omamobile-fp/${f##*/}" < "$f"; done
tools/phone-ssh 'chmod 755 /usr/lib/omamobile-fp/omamobile-fp-chroot; /usr/lib/omamobile-fp/omamobile-fp-chroot check'
tools/phone-ssh 'systemd-run --unit=omamobile-fp -p KillMode=control-group /usr/lib/omamobile-fp/omamobile-fp-chroot start storage'
tools/phone-ssh 'journalctl -u omamobile-fp -b --no-pager | tail -40; dmesg | grep -i trusty | tail -20'
```

Expect: `[servicemanager]` and `[vndservicemanager]` start; `[storageproxyd]`
connects, handles RPMB requests, sets `ro.vendor.trusty.storage.fs_ready=1`;
"secure storage ready". Trusty's log shows the storage service mounting
TP/TD/TDP; files appear in `/var/lib/omamobile-fp/data/vendor/ss`.
Risk: section 5: this is the point of no return for the RPMB. A failure here
(e.g. storageproxyd rejecting the sg node) writes nothing.
Rollback: `systemctl stop omamobile-fp`. RPMB contents cannot be rolled back.

### F5: the TA loads

```sh
tools/phone-ssh 'systemctl stop omamobile-fp; systemd-run --unit=omamobile-fp /usr/lib/omamobile-fp/omamobile-fp-chroot start apploader'
```

Expect: "loading g7.app", the apploader exits 0 in about a second
(`R/dmesg.txt:6990`: 0.32 s on stock), "g7.app loaded"; Trusty's log names
the app. Risk: apploader blocks if storage is not up (the runner times out at
60 s). Rollback: stop the unit; the TA stays loaded until reboot, harmless.

### F6: sensor power and the HAL (overlay `fingerprint-sensor.dtso`; needs the LDO15S regulator)

```sh
# with the ACPM regulator driver merged and vdd-supply = <&ldo15s> added to the node
$O/scripts/dtc/fdtoverlay -i "$D" -o "$D" out/fingerprint-sensor.dtbo && bin/omamobile images && bin/omamobile push
tools/phone-ssh 'grep -i ldo15 /sys/kernel/debug/regulator/regulator_summary; ls /sys/firmware/devicetree/base/chosen/plat'
tools/fingerprint-capture --watchdog goodix
tools/phone-ssh 'systemctl stop omamobile-fp; systemd-run --unit=omamobile-fp /usr/lib/omamobile-fp/omamobile-fp-chroot start hal'
```

Expect: `gpp0`-`gpp19` GPIO chips; "goodix-fp ... irq N, supply switched";
LDO15S 0 users before the HAL starts, 1 after. HAL log: "HAL/TA version is
match", "Initialization successful"; `goodix-fp` interrupts counting in
`/proc/interrupts` after its resets. The HAL registers
`IFingerprint/default` and keeps running.
Risk: PERIC0 pinctrl first enable (low, its CMU is live); the supply. If the
HAL hangs, the log shows which lookup it waits on (shim absent-service list,
`props.conf`). Rollback: stop the unit, `modprobe -r goodix_fp` (powers the
sensor down), restore the DTB.

### F7: LHBM lights

```sh
tools/phone-ssh 'echo 1 > /sys/module/panel_samsung_s6e3hc4/parameters/allow_lhbm;
  bl=$(dirname /sys/class/backlight/*/local_hbm_mode); echo 1 > $bl/local_hbm_mode; sleep 4; cat $bl/local_hbm_mode'
```

Expect, with the screen on: a bright circle around (720, 2361), about 6 mm
radius, for 3 s, then off by itself ("local HBM timed out" in dmesg), reads 0.
Write 0 early to turn it off; blank the screen while on: off first.
Risk: no peak-refresh or vblank alignment (section 3.4); possible flicker or a
torn first frame. Stop if the circle is wrong in place or brightness, or the
panel misbehaves after off. Rollback: `echo 0`, blank/unblank, reboot.
Keep `allow_lhbm=1` only from here on (device package `modprobe.d`).

### F8: enroll (needs the bridge)

```sh
omamobile-fp-bridge --enroll        # in the chroot, until fprintd is wired
```

Expect: shared secret computed; Gatekeeper enroll returns a handle; challenge,
HAT, `enroll()`; then for each touch: LHBM on, `onPointerDown`, `onUiReady`,
`onAcquired`, `onEnrollmentProgress(id, remaining)` down to 0. Tune the LHBM
to `onUiReady` delay here (start at 3 frames).
Risk: templates written to Trusty storage; repeated bad captures can lock the
sensor out for a while. Rollback: `removeEnrollments([id])`.

### F9: verify

Expect: `authenticate()`; touching with the enrolled finger gives
`onAuthenticationSucceeded(id, HAT)`; another finger gives
`onAuthenticationFailed`. Then with fprintd: `fprintd-enroll`, `fprintd-verify`.
Rollback: `fprintd-delete $USER`.

### F10: PAM unlock

Enable `omamobile-fp.service` and fprintd. Lock, wake the screen, touch the
target: unlocks. The password still unlocks; with the service stopped the
lock falls back to the password.
Rollback: `systemctl mask --now omamobile-fp` (from 0.1.14 the package's vendor wants link survives `disable`).

---

## 8. Files

| File | What |
|---|---|
| `L/drivers/trusty/`, `L/include/linux/trusty/`, `L/include/uapi/linux/trusty/ipc.h`, `L/kernel/kthread.c` | Trusty driver, `kthread_set_per_cpu` export |
| `L/drivers/misc/goodix-fp.c` | sensor control |
| `L/drivers/gpu/drm/panel/panel-samsung-s6e3hc4.c` | LHBM attributes |
| `L/arch/arm64/boot/dts/exynos/google/gs201.dtsi`, `gs201-pinctrl.dtsi`, `gs201-cheetah.dts` | trusty, PERIC0 pinctrl, fingerprint nodes (disabled) |
| `L/Documentation/devicetree/bindings/firmware/android,trusty-smc-v1.yaml`, `misc/goodix,g7-udfps.yaml` | bindings |
| `kernel/configs/omamobile.config` | the six options |
| `packages/omamobile-device-cheetah/vendor/modprobe.d/omamobile-fingerprint.conf` | blacklist |
| `device/cheetah/overlays/fingerprint-{trusty,sensor}.dtso` | gate overlays |
| `tools/extract-fingerprint-vendor` | vendor files from the factory image |
| `tools/fingerprint-capture` | gates F2-F6 with log streaming and watchdog |
| `packages/omamobile-fingerprint/lib/` | the chroot runner, props, `omamobile-tipc-probe`, `omamobile-fp-ctl` |
| `fingerprint/bridge/omamobile-fp-bridge.c` | the HAL client fprintd's driver talks to |
| `packages/libfprint/` | libfprint with the `omamobile_udfps` driver |
| `fingerprint/shim/omamobile-fp-shim.c`, `fingerprint/Makefile` | the preload shim |
