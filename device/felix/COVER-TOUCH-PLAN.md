<!-- SPDX-License-Identifier: MIT -->
# Pixel Fold cover touch: chip-id gate

The cover controller is an ST SALIXP (chip id `36 40`) on USI6 SPI. linux-omarchy-mobile#32 describes the node and leaves it disabled, and adds `drivers/input/touchscreen/salixp.c`. This plan is the one gated boot of that module. It does not load firmware or report touches. The inner panel, S2MPG13, and the inner reset stay off.

`kernel/configs/omamobile.config` builds `CONFIG_TOUCHSCREEN_SALIXP=m`. `device/felix/overlays/cover-touch.dtso` enables USI6, SPI6, PERIC0, the controller, and the main PMIC. It does not set `regulator-always-on`. `omamobile-device-felix` blacklists `salixp`, so the module does not autoload when the overlay is on. The descriptor leaves `DTB_OVERLAYS` empty. A normal image does not enable the node.

The earlier id reads are in [NOTES.md](NOTES.md). One was an unpublished tree with `regulator-always-on`. One was #32 head `b1b5f1fd6`, built in, with a kernel overlay that has since moved here. Neither is this gate.

## Gate

Risk: the overlay binds the S2MPG12 regulator driver, and the reader then enables LDO25M and LDO26M. Stop if any other rail changes state, if the UFS error handler runs, if USB drops, or if the chip id is not `36 40`. If the phone does not come back on USB, stop. Do not boot slot A: stock rewrites the calibration partitions. If ABL boots slot A anyway, stop this gate and take a fresh backup before going on. Do not mark slot B successful.

Rollback for the boot: slot B images built without `cover-touch`. The blacklist can stay.

Write slot B with `DEVICE=felix bin/omamobile flash` from fastboot, or `DEVICE=felix bin/omamobile push` from a phone that is already up. Both write only the allowlisted `_b` images, and `push` checks each image's sha256. Leave `userdata` alone. The initramfs panics if no USB host configures the gadget within 45 s, and ABL can then boot slot A once slot B is out of retries. That happens however the images were written. `push` only prints it when SSH never comes back.

### 0. Read-only, before the overlay image

Compare `efs`, `efs_backup`, `modem_userdata`, `persist`, `modem_a`, and `modem_b` with the 2026-10-16 backup. The sums stay off the repository.

**Expect / pass:** every sum matches the backup.

**Stop:** any mismatch. Take a fresh backup only after a slot A boot, and do not continue this gate on stale sums.

**Rollback:** none. Nothing was written.

**Risk:** read-only.

### 1. Blacklist, then the overlay image

From this repository, with `DEVICE=felix` and the kernel tree on the #32 branch. The blacklist has to be on the phone before the overlay boots. Copy `packages/omamobile-device-felix/vendor/modprobe.d/omamobile-cover-touch.conf` to `/etc/modprobe.d/omamobile-cover-touch.conf` on the phone, or install `omamobile-device-felix` 0.1.3, which ships the same file under `/usr/lib/modprobe.d/`. Confirm `blacklist salixp` is what modprobe will see.

Build the kernel so `salixp` is a module (`CONFIG_TOUCHSCREEN_SALIXP=m` in the fragment). For this pack only, set `DTB_OVERLAYS=cover-touch` in `device/felix/device.conf`, run `bin/omamobile images`, then remove that line. Do not commit it. The felix DTB is already built with `-@`.

**Expect / pass:** the pack prints `DTB overlays: cover-touch`. The committed descriptor has no `DTB_OVERLAYS`.

**Stop:** the overlay fails to apply, or the descriptor still sets `DTB_OVERLAYS` after the pack.

**Rollback:** remove the `DTB_OVERLAYS` line and pack again. Remove `/etc/modprobe.d/omamobile-cover-touch.conf` if the package is not installed.

**Risk:** low. No boot yet.

### 2. Boot slot B

`DEVICE=felix bin/omamobile flash` from fastboot, or `push` when the phone is already up. Do not mark the slot successful.

The reader defers until the S2MPG12 regulators exist. `sec_acpm` probes only after the mailbox and the ACPM protocol are loaded, or it skips its channels. On the laptop, start a log before the loads, so the last lines survive if the phone drops:

```sh
mkdir -p logs
tools/phone-ssh 'dmesg -w' > logs/felix-cover-touch-$(date +%s).log &
```

On the phone, after it is up and debugfs is mounted:

```sh
modprobe exynos_mailbox
modprobe acpm_protocol
modprobe sec_acpm
cp /sys/kernel/debug/regulator/regulator_summary /tmp/regulator-before.txt
modprobe salixp
cp /sys/kernel/debug/regulator/regulator_summary /tmp/regulator-after.txt
diff -u /tmp/regulator-before.txt /tmp/regulator-after.txt
dmesg | grep salixp
```

**Expect / pass:** dmesg has `salixp spi0.0: chip id 36 40`. The diff shows `vdd-outer-ts` (LDO25M) and `avdd-outer-ts` (LDO26M) enabled, with the touch device as their consumer. No other rail changed. `dmesg` has no `ufshcd_err_handler` line from this boot. The summary prints those regulator names.

**Stop:** any other chip id, a rail other than those two changing, a UFS error-handler run, or USB dropping. Do not request the attention interrupt. Do not load firmware.

**Rollback:** slot B images packed without `cover-touch`, then reboot slot B. Do not boot slot A.

**Risk:** the main PMIC regulator driver binds, and the reader enables LDO25M (1.8 V) and LDO26M (3.3 V).

### 3. Smoke, then unbind

Unbind is required. It is the remove path that asserts reset before the rails drop.

On the laptop:

```sh
tools/phone-smoke
```

On the phone:

```sh
echo spi0.0 > /sys/bus/spi/drivers/salixp/unbind
grep -A2 -E 'vdd-outer-ts|avdd-outer-ts' /sys/kernel/debug/regulator/regulator_summary
```

**Expect / pass:** `phone-smoke` reports no touch input. This reader does not create one. After unbind, both rails are disabled and have no users.

**Stop:** unbind leaves either rail enabled, or some other rail changes.

**Rollback:** reboot slot B on images without the overlay.

**Risk:** low. Unbind releases the two rails the driver holds.
