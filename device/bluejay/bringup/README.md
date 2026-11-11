<!-- SPDX-License-Identifier: MIT -->
# Bluejay development startup, outside the device package

These files were split from #543. They are not installed by the passive device
package and no service is enabled by this source tree. The original tested
snapshot remains at commit 6ad4651f8ac151333345c72db99f1fd83259696f in the
contributor's omarchy-mobile fork. The revised files have not run on a phone.

The hardware, Wi-Fi and GPU helpers retain their exact tested release/module
pins and explicit opt-ins. They target the tested kernel source `c934e316b`
(release `7.3.0-rc6-omamobile-bluejay-input-gated0`), including its USI probe
hold and ALIX stage parameter. They intentionally refuse the
revised kernel topics. Removing a check or changing a hash is not qualification.
The new ALIX topic drops both staging knobs: a separate next-run helper must
be prepared and reviewed before testing that stack.

`bringup/kernel.config` is the historical fragment for rebuilding `c934e316b`.
Apply it by hand with `scripts/kconfig/merge_config.sh` after the shared config,
then run `olddefconfig` in that build's own output directory. It is deliberately
outside `device/bluejay/kernel.config`, so ordinary Bluejay builds keep their
own kernel release, commit suffix and SPI configuration.


`device/bluejay/overlays/input-controller.dtso` replaces the whole
`/chosen/bootargs` string; it does not append its USI probe-hold argument.
Before combining it with other overlays, inspect the final bootargs in both
DT variants and retain every argument the matching boot/recovery policy needs.
It is a historical overlay for the tested kernel, not the revised ALIX path.
These overlays name labels from that development tree and do not apply to the
published kernel. Rebuild and validate a matched set before another trial.

The retained-display startup no longer reads or writes registers with devmem.
Use `SIMPLEFB_TRIG_CON="0x1c300030 0x3061"` in the Bluejay descriptor and rebuild
with the shared init; its COMPATIBLE check owns the trigger. Native panel
modesetting is still unqualified. Confirm actual refresh visually in a gated
trial instead of claiming that the sysfs framebuffer check proves it.

The proposed neutral root policy needs `INITRAMFS_ROOT_LABEL=omamobile-root`,
`INITRAMFS_ROOT_MODE=persistent-development` and, for a deliberately host-free
development boot, `INITRAMFS_USB_RECOVERY=no`. The SSH-ready helper now clears
`/var/lib/omamobile/root-boot-pending` after checking the USB address and sshd.
Do not install it against the historical Bluejay-specific selector/marker;
change the init and companion together, with a retained RAM rescue image.

## Next-run gate (not executed)

1. Offline: build a complete matching kernel/modules/initramfs/root set. Inspect
   both A0/B0 DT variants, the descriptor trigger, root mode/label and marker,
   module hashes, blacklists, opt-ins and `AUTO_WRITE=no`. Stop at any mismatch.
   Rollback: keep the original tested outputs. Risk: low, laptop files only.
2. Read-only at the bench: establish actual slot/boot identity, USB transport,
   storage guard and watchdog ownership. Take a fresh protected-data backup and
   independently verify it. Stop on missing guard, transport or backup evidence.
   Do not restore NV/devinfo or repeat the held slot-success write. Risk: read-only.
3. A phone boot or install needs the owner's approval and a phone-specific
   runbook. Stream logs before driver load, use the owned watchdog and durable
   markers, and make one hardware change per boot. Stop on lost USB, missing
   acknowledgment, SPI/CRC faults, a stale marker or unexpected firmware state.
   Rollback: buttons/fastboot and retained B RAM images. Never reset userdata
   as a shortcut. Risk: hardware-dependent; no revised-stack approval implied.

The Wi-Fi DT revision additionally introduces a disabled `regulator-wlan`.
Its future link-stage overlay must enable it; these historical overlays do not.
No prospective overlay should be copied into the working phone as-is.

## Install and undo the root gates (not executed)

Only after the next-run gate above has passed, stage the check and ready pair
on the prepared development root. The neutral root policy from #562 and this
ready helper must be installed together. These commands enable the pair for
the next boot; they do not start hardware or prove a successful handover.
Announce any subsequent boot or screen interruption separately.

From the repository root, as root on the prepared handset, choose a fresh
backup directory and record the previous enabled state. Stop if the directory
already exists, a copy fails, or the root/image/kernel checks disagree:

```sh
(
set -eu
backup=/var/lib/omamobile/bluejay-root-gates-before-test
[ ! -e "$backup" ]
mkdir -p /var/lib/omamobile
mkdir -m 700 "$backup"
systemctl is-enabled omamobile-bluejay-check.service > "$backup/check.enabled" 2>&1 || true
systemctl is-enabled omamobile-bluejay-boot-ready.service > "$backup/ready.enabled" 2>&1 || true
for path in /usr/bin/omamobile-bluejay-check /usr/bin/omamobile-bluejay-boot-ready \
  /usr/lib/systemd/system/omamobile-bluejay-check.service \
  /usr/lib/systemd/system/omamobile-bluejay-boot-ready.service \
  /usr/lib/systemd/system/sddm.service.d/bluejay-check.conf; do
  if [ -e "$path" ] || [ -L "$path" ]; then cp -a --parents "$path" "$backup/"; fi
done
touch "$backup/snapshot-complete"
install -Dm755 device/bluejay/bringup/bin/omamobile-bluejay-check /usr/bin/omamobile-bluejay-check
install -Dm755 device/bluejay/bringup/bin/omamobile-bluejay-boot-ready /usr/bin/omamobile-bluejay-boot-ready
install -Dm644 device/bluejay/bringup/vendor/systemd/system/omamobile-bluejay-check.service /usr/lib/systemd/system/omamobile-bluejay-check.service
install -Dm644 device/bluejay/bringup/vendor/systemd/system/omamobile-bluejay-boot-ready.service /usr/lib/systemd/system/omamobile-bluejay-boot-ready.service
install -Dm644 device/bluejay/bringup/vendor/systemd/system/sddm.service.d/bluejay-check.conf /usr/lib/systemd/system/sddm.service.d/bluejay-check.conf
systemctl daemon-reload
systemctl enable omamobile-bluejay-check.service omamobile-bluejay-boot-ready.service
)
```

Expect both units enabled and their installed `ExecStart` paths present. A real
boot must show the check passing, SSH available, the pending marker cleared
and the desktop ready. Stop on any failed prerequisite; do not clear the
marker merely to make a failing boot repeat.

To undo on the installed development root before another boot, restore the
saved files below. If only RAM rescue is available, first recover access to
the installed root using PERSISTENCE-PLAN; these absolute paths must not be
run against the RAM filesystem. A missing or incomplete backup stops before
any unit is disabled or any file removed:

```sh
(
set -eu
backup=/var/lib/omamobile/bluejay-root-gates-before-test
[ -d "$backup" ]
[ -f "$backup/check.enabled" ]
[ -f "$backup/ready.enabled" ]
[ -f "$backup/snapshot-complete" ]
systemctl disable omamobile-bluejay-check.service omamobile-bluejay-boot-ready.service
for path in /usr/bin/omamobile-bluejay-check /usr/bin/omamobile-bluejay-boot-ready \
  /usr/lib/systemd/system/omamobile-bluejay-check.service \
  /usr/lib/systemd/system/omamobile-bluejay-boot-ready.service \
  /usr/lib/systemd/system/sddm.service.d/bluejay-check.conf; do
  rm -f "$path"
  if [ -e "$backup$path" ] || [ -L "$backup$path" ]; then cp -a "$backup$path" "$path"; fi
done
systemctl daemon-reload
)
```

Restore each unit's recorded enabled/masked state from `check.enabled` and
`ready.enabled` (enable only a unit recorded as enabled; restore any prior
mask). Keep the backup. These root-gate commands do not stage the rest of the
historical hardware stack and do not qualify a revised kernel.
