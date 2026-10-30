<!-- SPDX-License-Identifier: MIT -->
# Fingerprint plan (tegu / zumapro): fingerprint unlock on the palmtop

Status (2026-10-29): **works on the owner's kernel: F0-F10 passed. The enrolled finger matches and other fingers don't, through the HAL and through fprintd, and the lock screen unlocks by fingerprint.** It runs on `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`, the integration tree, with tg4c's LHBM loaded by hand. That LHBM isn't in the published tree yet: it's open as derekross/linux-omarchy-mobile#126, on the panel's own bands, which need no DSI reads (the reads are derekross/linux-omarchy-mobile#125, used only for the overdrive experiments). It also needs the bridge and runner fixes in #135. (F4, the first RPMB write, ran on 2026-10-27 under D1 = A.) Earlier: **research and plan only, nothing run on the palmtop for
fingerprint.** Stage 16 of ALL-HARDWARE-PLAN (private). The
Pixel 7 Pro stack works ([cheetah FINGERPRINT-PLAN](../cheetah/FINGERPRINT-PLAN.md),
opt-in); this plan says what carries over to the Pixel 9a and what is new.
`[V]` is verified (stock vendor image, stock DT overlays, Google's GPL tree,
our captures); `[I]` is an inference still to test.

Sources (private, never committed): the stock `vendor_a.img` and `dtbo_a`
entries in `~/android/reference/tegu-vendor-a-20261026/` (read with `debugfs`
and the decompiled overlays), the stock getprop in
`~/android/reference/tegu-20261020-1349/`, and Google's GPL tree on maclab
(`lima-omb:~/tegu/kernel/private`): `devices/google/tegu/dts/zumapro-tegu-udfps.dtsi`,
`google-modules/soc/gs/drivers/input/fingerprint/` (gf_spi.c, platform.c,
netlink.c), `google-modules/fingerprint/goodix/fps_touch_handler/`, and the
panel driver `panel-gs-tg4c.c` (copy in `~/android/reference/tegu-gpl-panel/`).

## 1. The hardware

| Fact | Value | Source |
|---|---|---|
| Sensor | Goodix optical under-display sensor, same HAL family as cheetah (`vendor/goodix/udfps/g7_trusty/...` source paths, `Delmar*` algorithm classes) [V]. TA `g7a.app` (cheetah: `g7.app`), so a newer G7 variant [I] | HAL and `libgf_hal.so` strings; `ro.vendor.fingerprint.ta.name=g7a.app` in vendor `build.prop` |
| Bus | SPI owned by the secure world, as on cheetah: the node sits under `/odm`, not under an SPI controller; `spi-max-frequency = 1 MHz` is read by the TA side only [V] | stock `dtbo_a-*` fragment@97 (target `odm`), GPL `zumapro-tegu-udfps.dtsi` |
| AP-side driver | Google's `goodixfp.ko` (`CONFIG_GOODIX_FINGERPRINT=m`), compatible `goodix,fingerprint`: the same gf_spi/platform/netlink code as gs201 (`/dev/goodix_fp`, GF_IOC_* ioctls, netlink 25) [V]. Google's zumapro build does **no** regulator handling in it [V] | `zumapro_defconfig`, `soc/gs/drivers/input/fingerprint/gf_spi.c` |
| Interrupt | `gpa7-6`, EINT function, `interrupts = <6 0>` on `gpa7`; the driver requests it rising-edge [V] | overlay fragment@95/@97, GPL dtsi |
| Reset | `gpp1-0`, output, no pull, power-down state "previous", active low [V]. **Same bank as the touchscreen reset `gpp1-1`** [V] | overlay fragment@96, GPL dtsi, `overlays/public-touch-bus.dtso` |
| Supply | S2MPG15 **LDO15S**, 3.3 V fixed, `regulator-always-on` (GPL dtsi `&s_ldo15_reg`; stock calls it `L15S_SPARE`) [V]. No supply on the sensor node [V]. LDO22S is named `L22S_UDFPS` in the PMIC table but has no consumer on tegu: it belongs to the ultrasonic boards of the zuma family (`zuma-board-ultrasonic-udfps.dtsi`) [V source, I for tegu] | GPL `zumapro-tegu-udfps.dtsi`, `zumapro-pmic.dtsi`, `zuma/*udfps*.dtsi` |
| Touch helper | `google,fps-touch-handler` node; driver `fps_touch_handler.ko` (`CONFIG_FPS_TOUCH_HANDLER=m`, GPL): a generic `input_handler` on any multitouch device that hands touches over the sensor to the HAL through `/dev/fth_fd` (ioctls 101-115, event struct v6) [V] | `fps_touch_handler.{c,h}` |
| Board revisions | All ten stock `dtbo` entries (board IDs 0x60b01-0x60b06) carry the identical node [V] | `dtbo_a-0..9.dts` |
| Panel | `tg4c` (`ro.boot.primary_panel_drv=panel-google-tg4c...`, our `probes/panel-tegu-tg4c.c`) [V] | stock getprop, NOTES (private), 2026-10-27 |

Notes for our kernel: the tegu config already has `CONFIG_GOODIX_FP=m`
(our platform driver `drivers/misc/goodix-fp.c`, binding
`goodix,g7-udfps`), `CONFIG_CHR_DEV_SG=m`, `CONFIG_DMABUF_HEAPS_SYSTEM=y` and
the Trusty modules [V, `device/tegu/kernel.config`]. Our driver's
`vdd-supply` is optional, which fits: on tegu the node gets none and LDO15S
must simply be on. The gpa7 EINT bank is in the offline integration DT
(`patches/zumapro-tegu-int-20261026.dtsi`, NFC uses gpa7-5) [V]; gpp1 is in
the PERIC0 bank nodes [V].

## 2. The software path on stock

```
Android: FingerprintService / SystemUI (touch, LHBM request)
  -> android.hardware.biometrics.fingerprint-service.goodix (AIDL IFingerprint v3)
       libgf_hal.so, fp_utils.so, biometricsuez.so
       | /dev/trusty-ipc-dev0   /dev/goodix_fp + netlink 25   /dev/fth_fd
       | IDisplay (com.google.hardware.pixel.display) for LHBM
  -> KeyMint (rust, Trusty), Gatekeeper (Trusty), storageproxyd
       | RPMB (/dev/sg1) + trusty_userdata + trusty_persist (raw UFS partitions)
  -> Trusty: g7a.app, KeyMint, Gatekeeper, storage
```

From the vendor init files [V]:

- `fingerprint-goodix.rc`: service `vendor.fingerprint-goodix`
  (`/vendor/bin/hw/android.hardware.biometrics.fingerprint-service.goodix`,
  user system, groups system input, priority -20, disabled); on
  `ro.vendor.trusty.storage.fs_ready=1` it runs
  `trusty_apploader /vendor/firmware/${ro.vendor.fingerprint.ta.name}` and
  then enables the HAL. Same shape as cheetah; new: `chown system /dev/fth_fd`.
- `android.hardware.gatekeeper-service.trusty.rc`: `--dev /dev/trusty-ipc-dev0`.
- `android.hardware.security.keymint-service.rust.trusty.rc`: the **Rust**
  KeyMint HAL, `oneshot` ("not allowed to restart; if it crashes, a device
  restart is required"), port `com.android.trusty.keymint`. Cheetah ran the
  C++ `keymint-service.trusty` (port `.keymaster`). A StrongBox KeyMint
  (`keymint-service.citadel`, Titan M) also runs on stock; the bridge
  agrees the auth-token key with Trusty KeyMint only, as on cheetah, so
  citadel is not needed [I].
- `init.zumapro.board.rc`, the storage proxy:

  ```
  service storageproxyd /vendor/bin/storageproxyd -d /dev/trusty-ipc-dev0 -r /dev/sg1 \
      -p /data/vendor/ss -t ufs \
      -f 0:/dev/block/platform/13200000.ufs/by-name/trusty_userdata \
      -f persist/0:/dev/block/platform/13200000.ufs/by-name/trusty_persist \
      -m /dev/block/platform/13200000.ufs/by-name/trusty_userdata
  ```

  This is **new against cheetah**: Trusty's tamper-detect store (`0`) and
  its persistent store (`persist/0`) are mapped onto two raw UFS partitions
  (`-f`, "maps secure storage files like `0` and `persist/0` to block
  devices"), and `-m` caps file-backed stores at a block device's size
  (storageproxyd's own usage text). `init.persist.rc` also links
  `/mnt/vendor/persist/ss` to `/data/vendor/ss/persist` (with `nsp`, the
  non-secure persistent files) and `trusty_persist` to `persist/0`.
- Port names in the binaries: `com.android.trusty.apploader`,
  `.keymint`, `.gatekeeper`, `.storage.proxy`, `com.goodix.fingerprint.test`.

Partitions (tegu partition map; sizes in 512-byte units) [V]: `persist` sda1
(262144, f2fs), `trusty_persist` sda8 (131072, 64 MiB), `trusty_userdata`
sda9 (262144, 128 MiB), `mfg_data` sdd4 (6560). All read-only under the
storage guard today [V, guard audit]. None of `trusty_persist`,
`trusty_userdata` or `mfg_data` is in the protected backup set yet [V].

HAL dependencies beyond cheetah's (`readelf -d`) [V]:
`com.google.hardware.pixel.display-V4` (LHBM through `IDisplay`), the
sensor NDK bridge (ambient light feed-forward, the LPTW "long press" sensor),
power and HIDL `android.hardware.thermal@2.0`, and
`com.google.hardware.biometrics.fingerprint.fingerprint-ext-V1`. It reads
`/dev/block/by-name/mfg_data` (factory calibration), `/dev/goodix_fp`,
`/dev/fth_fd`, `/dev/trusty-log0` and `/sys/firmware/devicetree/base/chosen/plat`.

Stock vendor properties that matter [V, vendor `build.prop`]:
`persist.vendor.udfps.lhbm_controlled_in_hal_supported=true`,
`set_lhbm_in_advance=true`, `fps_touch_handler_supported=true`,
`fps_touch_handler.handle_down_up_events=true`,
`fth.touch_resolution_scaling_factor=10`, `als_feed_forward_supported=true`.
So on stock the HAL itself reads touches from `/dev/fth_fd` and asks the
display HAL for LHBM. On cheetah the same HAL ran with all of those off
(our `props.conf`), with the bridge doing touch and LHBM; the code paths are
the same HAL source tree, so the overrides should still work [I].

## 3. The display: capture needs the panel

Yes: the sensor images the finger by the panel's own light. The HAL asks for
the local high brightness mode (LHBM: a bright circle over the sensor) before
it captures:

- **Stock route** [V]: `fp_utils::DisplayController::SetLhbm` calls
  `IDisplay::setLhbmState` on `com.google.hardware.pixel.display.IDisplay/default`
  (the HWC service), "in advance" of the capture, and the panel driver sends
  the commands.
- **Our route** (as cheetah) [I]: `lhbm_controlled_in_hal_supported=false`,
  so the HAL reports that its client lights the sensor; the bridge writes the
  panel driver's `local_hbm_mode` on finger down, waits, then `onUiReady`.
  The fallback, if the HAL refuses that mode on tegu: a small `IDisplay`
  service in the bridge that implements `setLhbmState` with the same sysfs
  write.

What `panel-gs-tg4c.c` does (Google's GPL driver) [V]:

- LHBM on: set the LHBM brightness groups (register `0xD1` through `0x6F`
  offsets) and an LHBM gamma set chosen by the current DBV, then DCS
  `0x87 0x05`; off: `0x87 0x00`.
- **LHBM works only at 120 Hz**: a switch away from 120 Hz turns it off
  ("switch to %dhz will fail when LHBM is on"). So the panel must be at
  120 Hz while a capture runs. Our tg4c module can switch 60/120 Hz
  (`0x2f 0x00/0x02`) [V, NOTES 2026-10-27].
- `lhbm_on_delay_frames = 2`, `effective_delay_frames = 2` (3 with IRC off),
  `post_cmd_delay_frames = 2`.
- At init it reads the panel's normal LHBM brightness from the panel and
  derives "overdrive" sets for dim backlight levels (0, 6, 50, 300 nit
  groups). A first port can use the normal set only; dark captures at low
  brightness are then expected [I].
- A histogram region comment puts the LHBM circle 540 px below the active
  area's centre, radius 100 px: about (540, 1752) on 1080x2424 [I: the HAL's
  sensor location at F6 is authoritative].

Panel work for us: add `local_hbm_mode` / `local_hbm_max_timeout` to
`probes/panel-tegu-tg4c.c` on the backlight device, with cheetah's guards
(prepared, lit, unblanked, brightness > 0, `allow_lhbm` module parameter,
3 s self-timeout, off on blank/disable/brightness 0), plus: refuse or force
120 Hz while LHBM is on, and turn LHBM off before any switch to 60 Hz.

## 4. What carries over from cheetah, and what is new

Carries over unchanged or nearly [I unless marked]:

- The architecture: vendor HAL, Trusty KeyMint and Gatekeeper and
  storageproxyd in the bionic chroot (`omamobile-fp-chroot`), the preload
  shim, `omamobile-fp-bridge`, libfprint `omamobile_udfps`, fprintd, PAM,
  and the shell's target, enrollment screen and inhibit logic.
- The Trusty transport: bound on tegu, API 5, eight NOP threads, used for the
  AoC [V, GSA-PLAN T1/T2]. The tegu Trusty import keeps the CPU-hotplug and
  DMA-buf fixes [V, GSA-PLAN N1]; F0 confirms the memref fix
  (`trusty_transfer_mapped_memory`) is in the running kernel.
- Our `goodix-fp` driver and `/dev/goodix_fp` + netlink ABI (the HAL is the
  same family).
- The RPMB well-known LUN path through `sg` (stock waits for `/dev/sg1`) [V].
- `mfg_data` served from a read-only copy.

New for tegu:

| Item | Work |
|---|---|
| Storage mapping | storageproxyd's `0` and `persist/0` live on `trusty_userdata` and `trusty_persist` (section 2). Decision D1 (section 6) before F4 |
| TA name | `g7a.app` (runner, extractor checks) |
| KeyMint | Rust HAL, port `.keymint`, oneshot; `omamobile-tipc-probe` and the runner learn the port; likely new props for its version/patch-level reporting |
| Vendor extractor | `tools/extract-fingerprint-vendor` is cheetah-only (`DEVICE="cheetah"`, the C++ KeyMint binary, `g7.app`): add a tegu file list |
| Props | per-device `props.conf`: `ro.hardware=tegu`, `ro.boot.hardware.platform=zumapro`, the same overrides as cheetah (LHBM, ALS, LPTW, sensor listener, touch handler off) |
| Fake sysfs | panel name `google-tg4c` (from `exynos_drm.panel_name`), `op_hz` 120 during captures, `chosen/plat` |
| Touch scale | the Synaptics firmware reports 10800x24240, ten times the panel [V, TOUCH-POWER-PLAN]; the bridge assumes panel pixels: scale by the evdev ABS maxima |
| Sensor geometry | from the HAL's SensorProps at F6, not cheetah's (720, 2360) |
| Panel LHBM | tg4c commands, 120 Hz only (section 3) |
| DT | new disabled node (`goodix,g7-udfps`, gpa7-6 rising, gpp1-0 active low) plus the two pin states; LDO15S on (always-on in our S2MPG15 description, or claimed) |
| Shell | the lock's PIN pad clearance and the target position for the 9a's sensor and 8/3 scale |
| Optional | `fps_touch_handler` (GPL, generic input handler) if the HAL needs the stock touch path; an `IDisplay` stub if it needs the stock LHBM path |

## 5. Rules for this subsystem

- **Nothing writes `persist`, `trusty_persist`, `trusty_userdata` or the RPMB
  without the human's explicit go, recorded here with the date.** Dave's
  standing rule is that the palmtop never needs permission; F4 is still
  kept as one separate, backed-up step with its own record, because it
  cannot be undone and it changes what stock Android on slot A finds.
- Every start of storageproxyd after F4 is normal operation; before F4 it is
  F4. Keep `omamobile-fp.service` disabled until F10.
- `persist`, `trusty_persist`, `trusty_userdata` and `mfg_data` are only read
  (`dd` from the node found by `PARTNAME`), and `persist` is read from the
  off-phone backup image, not mounted on the palmtop (f2fs: a read-only
  mount can still run recovery). Never add them to `UFS_RW`.
- `fastboot oem udfps update-cal`, or any other `oem` command that writes,
  doesn't run without Derek's explicit go and a named exception: it writes
  `mfg_data`, outside slot B and `userdata`. Every `fastboot oem` step in a
  runbook pins the serial with `-s`.
- `sg` stays blacklisted from autoload; the runner loads it and binds only
  the RPMB LUN's node.
- `gpp1` is shared with the touchscreen reset (`gpp1-1`): the fingerprint pin
  state must touch only pin 0, and a touch check follows every change there.
- Announce before F7 and later: a very bright circle on the panel, and a
  refresh-rate switch.
- Nothing takes CPUs offline while Trusty is bound (`allow_cpu_offline=0`).
- Never commit vendor files, partition images or their contents, enrolled
  ids, or logs with serials. Quote only lines.

## 6. Decision D1, before F4: where Trusty's stores live

- **A (default: nothing written outside userdata).** storageproxyd runs
  without `-f`: `0` is a fresh file under `/var/lib/omamobile-fp/data/vendor/ss`
  (Trusty starts a new tamper-detect store, as on cheetah), `persist/0` is a
  read-only F3 copy of `trusty_persist` served as a file, `persist/nsp` a copy
  from the persist backup; `-m` points at a 128 MiB file (or is left out if
  this storageproxyd accepts that) [I]. The real partitions go stale against
  the RPMB, so a later stock Android on slot A will find its Trusty stores
  inconsistent: expect a factory reset, and possibly lost persistent Trusty
  state (cheetah accepted the same for `persist/ss`) [I].
- **B.** Map `0` and `persist/0` onto the real `trusty_userdata` and
  `trusty_persist`, as stock does. Linux and stock stay consistent, at the
  cost of a storage-guard allowlist change and writes to two Google
  partitions outside slot B and userdata (AGENTS.md section 1). Only with
  the human's explicit go.

Neither choice can roll back the RPMB: its write counter and superblocks move
at the first run either way.

**Decision (2026-10-27): A, with the stores as block devices.** Taken by
the owner (W4HO) at the console on 2026-10-27, evening: he never runs
stock Android, so nothing is written outside `userdata` and stock on slot A
is left to need a factory reset if it's ever booted. Within A, the stores
are loop devices of Linux-owned images in `/var/lib/omamobile-fp`
(`td.img`, `tdp.img`; step F4b), so storageproxyd gets its `-m` limit from
a block device and maps `0` and `persist/0` the way stock does, but onto
those images, never onto `trusty_userdata` or `trusty_persist`.

## 7. Runbook

Each step: commands, Expect/Pass, **Stop**, Rollback, risk. Read-only steps
first; one change per boot. Exact commands are filled in when the step's
pieces are built, as on cheetah.

### F0: backups and read-only facts (risk none)

1. Backups: the protected set plus `persist`, `trusty_persist`,
   `trusty_userdata`, `mfg_data`, read with `dd` from the nodes found by
   `PARTNAME` in `/sys/class/block/*/uevent`, hashed on the palmtop and on
   the laptop, stored in a new `~/android/reference/tegu-protected-fp-<date>/`
   (mode 600). Compare the existing ones against
   `tegu-protected-post-recovery-20261026T185656Z`. **Stop** if any hash
   differs between the palmtop and the laptop, or a protected partition
   changed with no stock boot to explain it.
2. Trusty: `/dev/trusty-ipc-dev0`, `allow_cpu_offline` = N,
   `grep -c trusty_transfer_mapped_memory /proc/kallsyms` > 0 (the memref
   fix). **Stop** if the fix is missing: port it before F5.
3. LDO15S: on and 3.3 V at hand-off? Read it once through the S2MPG15
   provider (`regulator_summary`, or one register with the read-only
   `probes/tegu-s2mpg15-provider-read.c`). **Stop** if it is off and our
   S2MPG15 description would turn it off as unused: describe it always-on
   first (as Google's dtsi does).
4. The gpp1 and gpa7 pin states as the bootloader left them (read-only pin
   dump): pin 0 output high (reset released) is expected [I].
5. The RPMB node: `modprobe sg`, list `/sys/class/scsi_generic/*/device`
   (expect one at LUN 49476), `modprobe -r sg`. Low risk (loads a driver,
   no I/O).

Rollback: none needed.

### F1: offline build (laptop and maclab; no palmtop)

- `tools/extract-fingerprint-vendor` with a tegu file list (Rust KeyMint,
  `g7a.app`, `fp_utils.so`, `biometricsuez.so`, the display and
  fingerprint-ext NDK libraries) from the owner's own factory image; the
  tree stays in `out/`.
- Runner and props per device (TA name, KeyMint port, panel name, touch
  scale, no `-f`/`-m` under D1 = A); `omamobile-tipc-probe` port table.
- Bridge: touch scaling from the evdev ABS maxima; 120 Hz request around LHBM
  (through the panel driver or Hyprland) [I: which owns the switch].
- Kernel: disabled tegu DT node and pins, LHBM in `panel-tegu-tg4c.c`;
  checkpatch, `W=1`, `dt-validate` against the binding (add a tegu example or
  compatible if review asks for it).
- `packages/omamobile-fingerprint/test/all`, `packages/libfprint/test/run`
  pass.

F1 progress (2026-10-27, night): the file list is in
`tools/extract-fingerprint-vendor -d tegu` and the runner picks the phone
from the device tree (omamobile-fingerprint 0.1.9, PR #71: g7a.app, the
Rust KeyMint, `props-tegu.conf` with `ro.hardware=tegu` and platform
zumapro; g7a.app answers on the same `com.goodix.fingerprint.test` port).
The bridge scales touches by the touchscreen's axis maxima and takes the panel size (1080x2424) from the runner. Still open: the 120 Hz request around LHBM.

### F2: Trusty ports (read-only; risk low)

Connect-and-close to `apploader`, `keymint` (`.keymint`), `gatekeeper` with
`omamobile-tipc-probe`; never `storage.proxy` (that looks like storageproxyd
arriving). Expect `open` for all three. **Stop** on a refused or hung port.
Rollback: none.

### F3: read-only copies on the palmtop (no writes outside userdata; risk low)

`mfg_data` and `trusty_persist` copied into `/var/lib/omamobile-fp/`
(0700) from F0's images; `persist/ss/nsp` extracted from the persist backup on
the laptop (loop mount read-only of the copy) and copied in. **Stop** if a
size differs from the partition. Rollback: delete the copies.

### F4: secure storage, IRREVERSIBLE (the first RPMB write from Linux)

**Separate step. Before it:** F0 backups fresh and matching, F3 done, D1
recorded above, the go and the date recorded here (Dave's standing
permission noted, and a status line to him by `ask-w4ho` before running).
Install the package and the vendor tree (installing writes nothing to
Trusty), run `omamobile-fp-chroot check`, then once:

```sh
tools/phone-ssh 'systemd-run --unit=omamobile-fp-stage -p KillMode=control-group /usr/lib/omamobile-fp/omamobile-fp-chroot start storage'
```

Expect: servicemanager, vndservicemanager, storageproxyd handling RPMB
requests, `fs_ready`, Trusty's log mounting its stores (TD new under A).
**Stop** on authentication failures, MAC mismatches or storage errors: no
retry loop, collect the logs. Rollback: stop the unit; the RPMB cannot be
rolled back. Risk: irreversible for the RPMB; low for the running system.

### F4b: the store images (TD and TDP as block devices; risk: low)

Only on the 9a (the runner maps them only there, and only when the files
exist). Both live in `/var/lib/omamobile-fp` (0700, root), are made on the
palmtop and are **never committed or copied off it** (they hold Trusty's
secure-storage state):

```sh
# TD: a fresh, empty 128 MiB store; storageproxyd takes its -m limit from it
truncate -s 128M /var/lib/omamobile-fp/td.img && chmod 600 /var/lib/omamobile-fp/td.img
# TDP: the F3 copy of trusty_persist (read-only copy, same size). Before the
# first mapped run it is persist-ss/0; after it, that path is the link and the
# copy is persist-ss/0.before-map.<time>.
install -m 600 /var/lib/omamobile-fp/persist-ss/0 /var/lib/omamobile-fp/tdp.img
```

The runner then maps each to a loop device bound to `/dev/block/ss-td` and
`/dev/block/ss-tdp` in the chroot, links `data/vendor/ss/0` and
`persist-ss/0` to them before storageproxyd starts (an existing store there
is moved aside with a timestamp, never deleted), and passes `-f 0:...`,
`-f persist/0:...` and `-m`. Expect "secure storage ready" with "Using
0x8000000 as max file size". Rollback: stop the runner, `losetup -d` both,
delete the two images (Trusty's state in them is lost; the RPMB is not
rolled back), then remove the two links (`data/vendor/ss/0`,
`persist-ss/0`) and move any `*.before-map.*` file back to its own name, so
the next unmapped run doesn't find links to nothing.

### F5: the TA (risk low)

`start apploader`: "g7a.app loaded" within seconds, the `goodix` test port
`open`, no oops. **Stop** on a 60 s loader timeout (storage not up), an oops
in the memref path, or a Trusty policy error. Rollback: stop the unit (the app
stays loaded until reboot).

### F6: the sensor and the HAL (one boot for the DT; risk low-medium)

F6a: boot with the sensor node (driver blacklisted): pins as F0, touch still
works (shared gpp1). F6b: `modprobe goodix_fp`, one open/close: an interrupt
on reset, no touch disturbance. F6c: `start hal` with the props overrides:
"HAL/TA version is match", "Initialization successful", and **the sensor's
location and radius**, recorded here. **Stop** on a service lookup that
waits (one shim or prop change per run), a HAL crash, or the Rust KeyMint
exiting (oneshot: next try needs a fresh boot). Rollback: stop the unit,
`modprobe -r goodix_fp`, DTB without the node.

### F7: LHBM on tg4c (announce: a very bright circle and a 120 Hz switch; risk medium)

Unlocked, screen lit, panel at 120 Hz: `allow_lhbm=1`, `local_hbm_mode=1`,
3 s, self-off. Expect a circle at F6's location and size. **Stop**: circle
elsewhere, wrong size, flicker that stays, a panel that misbehaves after off,
or LHBM accepted at 60 Hz. Rollback: `local_hbm_mode=0`, blank and unblank,
`allow_lhbm=0`, reboot.

### F8-F10: enroll, verify, fprintd, lock screen (as cheetah F8-F10)

Enroll through the bridge (writes a template to Trusty storage), verify a
match and a non-match, then libfprint and fprintd, then the PAM file and
`omamobile-fp.service` enabled. Tune the LHBM settle time for tg4c's two-frame
delay at 120 Hz. **Stop** on auth-token refusals, lockouts or TOO_DARK on
every capture (then the overdrive brightness sets, section 3).
Rollback: delete the enrolled id, remove the PAM file, disable the service.

### F11: shell and polish

Target position and PIN pad clearance for the 9a's sensor at scale 8/3;
the touch-handler or `IDisplay` alternatives only if F6-F8 show the HAL
needs them.

## 8. Risks

| Risk | Note |
|---|---|
| Storage mapping (D1) | New on tegu; either choice leaves stock on slot A with work to do |
| Rust KeyMint | oneshot; unknown props; a crash costs a reboot |
| LHBM on tg4c | 120 Hz only; brightness sets read from the panel; dim captures without overdrive |
| Touch scale and geometry | 10x touch coordinates; sensor location unknown until F6 |
| gpp1 shared with touch reset | a wrong pin write drops the touchscreen |
| LDO15S | always-on on stock; our S2MPG15 description must not switch it off as unused |
| HAL dependencies | display, sensors, power, HIDL thermal; expect a few shim/prop iterations at F6c |

## F0 results (2026-10-27, night)

- **F0.1 passed.** Read-only copies of `persist`, `trusty_persist`,
  `trusty_userdata` and `mfg_data` went to
  `~/android/reference/tegu-fp-backup-20261027/` (off-repo, mode 600), each
  hashed on the palmtop while read and again on the laptop: all four match.
  All four were `ro=1`. `persist` also matches the 2026-10-26 protected
  backup.
- **F0.2 passed.** `trusty_transfer_mapped_memory` is in `/proc/kallsyms`.
- **F0.3.** LDO15S isn't a regulator our S2MPG15 description names, so the
  regulator core won't turn it off as unused; its state wasn't read.
- **F2 passed.** `omamobile-tipc-probe` (installed with
  omamobile-fingerprint 0.1.8) connects and closes on
  `com.android.trusty.apploader`, `.keymint`, `.gatekeeper` and
  `.keymaster`: all four open. F3 waits for D1.
- **F7, first part (2026-10-27).** `probes/panel-tegu-tg4c.c` has LHBM:
  `local_hbm_mode` on the backlight device, opt-in `allow_lhbm=1`, 0x87 0x05
  / 0x87 0x00 with the panel's own LHBM brightness and gamma, refused at
  60 Hz or with the panel asleep, a 3 s timeout, off on disable, sleep and a
  switch to 60 Hz. On the palmtop at 120 Hz: refused without the opt-in,
  accepted with it, and off again after the timeout. Not yet seen by eye.

## F6a and F6b results (2026-10-27, night, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`)

- **F6a passed.** DTB round fp1 (DTB only) adds the `goodix,g7-udfps` node
  to `patches/zumapro-tegu-int-20261026.dtsi`: event line gpa7-6 (EINT,
  rising), reset gpp1-0 (active low), pin states from Google's GPL
  `zumapro-tegu-udfps.dtsi` (reset: output, no pull, previous state in
  power-down), no supply (LDO15S stays on). Booted to the desktop; the
  bring-up's every step OK; the node exists unbound; touch (gpp1-1) works.
- **F6b passed.** The tegu integration kernel has no goodix-fp, so the
  cheetah driver (`drivers/misc/goodix-fp.c` from `omamobile-int`) is built
  out of tree against it (W=1 clean) and kept at
  `/var/lib/omamobile-tegu/audio/goodix-fp.ko`, where nothing autoloads it.
  `insmod`: bound, irq 88 on gpa7-6, both pin states applied, `/dev/goodix_fp`
  and the `goodix_fingerprint` input device. Opening it (reset pulse) gave
  **one interrupt**: the sensor is alive on these lines. Further reset
  pulses gave none, as a sensor that latches its interrupt until the TA
  reads it over SPI would. Touch, keys and haptics unaffected.
- F6c (the HAL) needs the TA, which needs secure storage (F4), so it waits
  for D1 like F3-F5.

## F3-F6c results (2026-10-27, evening, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`)

- **F3 passed.** `mfg_data`, `trusty_persist` and `persist` read with the
  sha256 of the 10-27 backup. Stock's `persist/ss` holds only `0` (a link to
  `trusty_persist`) and an empty `nsp`. **`mfg_data` is all zeros** on this
  palmtop; `persist` has no fingerprint files.
- **F4 ran (irreversible, D1 = A).** storageproxyd without `-f`/`-m`:
  "secure storage ready" (fs_ready and fs_ready_rw), no RPMB errors.
- **F5 passed.** g7a.app loaded; `com.goodix.fingerprint.test` open.
- **F6c, sensor.** With LDO15S off (not described), the TA read chip id 0
  ("SENSOR_NOT_AVAILABLE"). LDO15S is off at hand-off, as on cheetah: round
  fp2 describes it (`S2MPG15_PMIC_L15S_CTRL` 0x3d in the regmap table, an
  `ldo15s` descriptor, DT always on; reads 3.3 V). Then the sensor answers
  and the HAL reports sensor0 at (540, 1769), radius 113.
- **F6c, still failing: secure objects and calibration.** Every TA write
  fails ("transaction would leave fs too full, abort", WRITE_SECURE_OBJECT),
  the calibration objects (`GHBM_*`, `autoCalibrationParams`) don't open on
  TD or TDP, and the TA says "spmt is not pass": no factory calibration, so
  init ends in CALIBRATION_NOT_READY. Tried: `-m` (needs a block device:
  TD now on a loop device of a 128 MiB Linux image, `0 -> /dev/block/ss-td`,
  max 0x8000000; Trusty reads it, writes nothing); TDP mapped to a loop
  device of the F3 copy (fs_ready never came); TD seeded from a copy of
  stock's `trusty_userdata` (fs_ready never came: Trusty refuses it, so the
  first F4 run moved its anchor). Back on the empty 128 MiB TD; the runner
  with the loop store is `/root/omamobile-fp-chroot.td-loop` on the palmtop.
- Open question: where the 9a's factory fingerprint calibration lives. It
  isn't in `mfg_data` (zeros) or `persist`; stock's TD (`trusty_userdata`,
  intact, read-only copy in `td.img.stock-copy`) is the likely place, now
  unreadable to Trusty after F4. Next: find which file system is "too full"
  (TP on the RPMB is the suspect), and whether the HAL can run SPMT-free
  calibration (Google's `gf_cali` "default cali data" is disabled by the TA).
- 2026-10-27, night: with TD and TDP both mapped as stock maps them
  (`-f 0:` and `-f persist/0:` on loop devices of `td.img` and `tdp.img`,
  `-m` the TD device) storageproxyd reports fs_ready; it first answered
  "Pending symlink: forcing read result 0" for both (Trusty saw them empty)
  until the symlinks `ss/0` and `ss/persist/0` existed, as on stock. Then
  the "too full" commits stop, but every TA object open fails
  (OPEN_SECURE_OBJECT, 1035), on TDP too: Trusty reads both devices (about
  100 reads each) and finds no objects. The calibration (`GHBM_*`,
  `autoCalibrationParams`) is the open question; Trusty's storage service
  logs nothing at this log level. Runner copies on the palmtop:
  `/root/omamobile-fp-chroot.td-loop` and the live one (TD+TDP maps).
- 2026-10-27, night, later: with the symlinks in place, a copy of stock's
  `trusty_userdata` as TD mounts too (fs_ready; it failed earlier only
  because storageproxyd's pending-symlink reads showed Trusty an empty TD).
  Trusty then wrote 13 blocks to the TDP copy and none to TD. The TA still
  finds no calibration: "so(autoCalibrationParams.so_0_0) not exist", and
  the `GHBM_*` bases don't open on TD or TDP. So the 9a's fingerprint
  calibration isn't in `mfg_data` (zeros), `persist` (an empty `ss/nsp`),
  stock's TD or the TDP. The HAL also names `/data/device_cali/` and
  `/data/vendor_de/0/fpdata`, both on stock's userdata, which Arch replaced:
  the likely home, and gone. Without it the TA refuses enrollment ("spmt is
  not pass": the factory sensor test). Open: whether the TA can run on
  default calibration (it logs "disable using default cali data") and what
  enables that. The live runner maps TD (`td.img`, now the stock copy) and
  TDP (`tdp.img`) as block devices with the symlinks.
- 2026-10-28: the calibration's home is in ABL. Its strings carry
  `oem udfps status`, `oem udfps get-cal-url`, `oem udfps update-cal`,
  "udfps data is not valid", "Calibration signature matches/mismatch",
  `udfps` next to `mfg_data`, and the URL template
  `https://storage.googleapis.com/hardware-mfg-data-ext-sacal/%s.signed.cal`.
  So Google keeps each sensor's factory calibration as a signed file on its
  manufacturing bucket, and `update-cal` writes it into `mfg_data`; the zeros
  there mean this palmtop's calibration was never written (or was wiped).
  Next (needs the owner's hands at fastboot, Volume Down + Power: reaching
  fastboot from Linux can fall back to stock on slot A): `fastboot oem udfps
  status` and `get-cal-url` (read-only), fetch the file, then feed it to the TA from Linux (no partition write;
  `update-cal` writes `mfg_data` and is under the rule in section 5). The URL's `%s` is presumably the device serial, so fetching it
  sends the serial to Google: the owner's call.
  With the owner's go, the URL with the serial (either case) answers 404,
  so the id is something else, presumably the sensor's own id that ABL
  reads at `udfps_init`. `fastboot oem udfps get-cal-url` will name it.
- 2026-10-28, morning: at fastboot by the buttons, `fastboot oem udfps
  status` answers "invalid sentinel 0x0" (no calibration stored) and
  `get-cal-url` names the file on Google's bucket; its id isn't the serial.
  With the owner's go the file was fetched (472,368 bytes, HTTP 200). It
  and its id stay in the owner's private reference folder, never in the
  repository or a log. Next: hand it to the TA from Linux, without writing
  `mfg_data`.
- 2026-10-28, afternoon: the HAL injects the calibration itself
  (`DataSynchronizer::injectMtCali`). It reads a 112-byte header from offset
  0 of `/dev/block/by-name/mfg_data` and logged "No SA calibration present"
  on the zeros. The file `get-cal-url` names has exactly that layout: magic
  `0xca11ca11`, version 1, and at 0x6c the payload length (file size − 112).
  With the file written at offset 0 of the chroot's private `mfg_data.img`
  copy (the real partition untouched), the "No SA calibration" line is gone
  and the HAL sets `vendor.gf.cali.state = 1`. Next: enrollment (F8/F9, the
  owner's finger).

## F7-F8 results (2026-10-28, evening, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`)

- **F7 seen by eye.** LHBM, ported into the upstream-form `panel-google-tg4c`
  (`allow_lhbm=1`, `local_hbm_mode` and `local_hbm_max_timeout` on the
  backlight device), lit
  the circle at 120 Hz, and the owner saw a white circle at the sensor.
- **F8 passed: a finger is enrolled.** With the factory calibration in
  the chroot's `mfg_data.img`, the bridge (rebuilt for the runner's
  `--panel`) and `omamobile-fp-ctl enroll`: FINGER DOWN, ACQUIRED, and
  PROGRESS counting down from 12 to 0, then ENROLLED.
- **F9 doesn't match yet.** Every authenticate touch comes back ACQUIRED 2
  (PARTIAL), with the HAL logging `valid_area=100` but `image_quality=29`.
  A 300 ms LHBM settle changed nothing. Lead: the port wrote only `0x87 0x05`.
  Google's tg4c first writes the LHBM brightness, the panel's own RGB values
  per band read from 0xD1 on CMD2 page 2 plus an overdrive offset chosen by
  the gray level under the circle, and then the LHBM gamma
  (`0x6F 0x07; 0x87 0x01-0x04` by brightness).
- **F9, later that evening.**
  DSI reads now work (`gs-dsim-cmd` read support: the read request needs
  `DSIM_PKTHDR_BTA`, bit 24), so the LHBM brightness bands are read from the
  panel and written with overdrive group 0 and the gamma. PARTIAL stayed.
  The HAL's log then showed three bridge and runner bugs (omamobile-fingerprint
  0.1.11, PR #135): the HAL got raw touchscreen positions (10x panel pixels,
  5432,17847 for the 540,1756 circle), it captures at
  `onPointerDownWithContext` (before `onUiReady`, while the circle was still
  dark), and it parses the refresh rate after the `@` in
  `panel0-backlight/state` (`on: 1080x2424@120`; a bare `on` logged "Failed
  to parse refresh rate"). With all three fixed, enrollment completes and
  authenticate captures come back GOOD and reach the matcher, but every one
  is NOMATCH at `image_quality` 15-26, at screen brightness 1500 and 3628
  alike. Lead one: Google overdrives only the first stage. After the
  effective delay (2 frames, 3 with IRC off) `tg4c_set_local_hbm_mode_post`
  writes the normal bands, so stock captures under the normal circle, while
  the port kept overdrive group 0 the whole time. From 2026-10-29 the
  palmtop runs `lhbm_od=4` (the normal bands, read from the panel), and the
  next step is to re-enroll and match under it. Other leads: whether the circle reaches LHBM luminance at all (nobody has yet
  compared it with the shell's drawn target); the HAL's raw capture dump
  (`vendor.gf.debug.dump_data=1` wrote nothing). Many misses lock the sensor
  out (`LOCKOUT -1`); `omamobile-fp-ctl resetlockout` clears it.

## F9-F10 results (2026-10-29, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`)

- **F9 passed.** With `lhbm_od=4` (the normal LHBM bands read from the
  panel, which is where Google's tg4c sits after its first-stage
  overdrive) and a fresh enrollment, `omamobile-fp-ctl auth` gave MATCH on
  the first touch twice. A different finger gave NOMATCH.
- **F10 passed.** fprintd was masked on the palmtop's own root: a link
  to `/dev/null` from the same batch as the 9a's other bring-up masks
  (ModemManager, NetworkManager, omamobile-aoc, omamobile-fp), made by the
  private bring-up root it was installed from. Nothing in this repository
  masks it. Unmasked, it
  finds the bridge's device, `fprintd-enroll` completes (20 stages), and
  `fprintd-verify` matches. Locked with `omarchy-shell lock lock`, the
  palmtop unlocked with the enrolled finger, and refused a different finger
  several times. The libfprint driver still names the device "Pixel 7 Pro
  under-display fingerprint sensor".
