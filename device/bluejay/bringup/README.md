<!-- SPDX-License-Identifier: MIT -->
# Bluejay development startup, outside the device package

These files were split from #543. They are not installed by the passive device
package and no service is enabled by this source tree. The original tested
snapshot remains at commit 6ad4651f8ac151333345c72db99f1fd83259696f in the
contributor's omarchy-mobile fork. The revised files have not run on a phone.

The hardware, Wi-Fi and GPU helpers retain their exact tested release/module
pins and explicit opt-ins. They target the OLD development kernel, including
its USI probe hold and ALIX stage parameter. They intentionally refuse the
revised kernel topics. Removing a check or changing a hash is not qualification.
The new ALIX topic drops both staging knobs: a separate next-run helper must
be prepared and reviewed before testing that stack.

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
