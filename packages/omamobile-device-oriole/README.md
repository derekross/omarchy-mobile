<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 first-light policy

**This package alone is not yet a supported Pixel 6 install.** An image
built from `device/oriole/device.conf` receives this package without the
private integration safeguards described below. Do not use that image as a
standalone installation or replace an integration package with it alone.

Minimal first-light policy package, version 0.2.0. No kernel, rootfs integration or
hardware qualification is supplied. Installation stages files only and enables
no services. The optional system setup command configures locale/time and
enables timesyncd.

Portable helpers, build script, USB network policy and storage udev policy
come from the cheetah package. The storage rules continue an existing
initramfs guard: they do not set partitions read-only themselves. A guarded
initramfs and matching kernel remain prerequisites. USB gadget creation and
networkd activation are also external prerequisites. USB has fallback metric
2000, below ordinary Wi-Fi preference.

All four sleep modes are disabled. UPower selects PowerOff on critical
battery. Coldplug blocks alias and explicit modprobe for clk_acpm,
max77759_charger, gpio_max77759, arm_dsu_pmu, at24 and max17042_battery.
The [coldplug audit](../../device/oriole/NOTES.md) found matching unbound devices and confirmed that
modprobe dry runs refused these modules; it did not load them or establish
their behavior. This package does not qualify the underlying hardware.
Built-in drivers are outside modprobe policy.

No battery startup, staged boot checker, automatic boot-success, radio,
charging or GS201 hardware services are included. Boot-control tooling is
omitted while slot marking remains on hold. Native ARM64 build and
installation passed with a private companion preserving
existing integration safeguards; see the 2026-11-07 entries in
[NOTES](../../device/oriole/NOTES.md). Standalone installation and a boot of
this package combination remain unqualified.

The PowerOff action has not been qualified for oriole; Linux power-off on other
Pixels can restart instead.

Run test/all for a native helper build and
staged installation checks. Version 0.2.0 sorts above the local integration
package 0.1.9-2, satisfying existing hardware-package version dependencies.
That integration package carries
boot and battery safeguards absent here. Replacing it requires a separately
qualified migration and rollback; do not remove it as a routine upgrade.

## Omitted startup safeguards and boot-success marking

The private companion's boot check is a staged-start guard, not a slot-success
marker. Its opt-in unit requires private initramfs assets, a matching kernel
and a bounded handoff-watchdog process. It checks protected storage, the
compositor, shell and staged touch state before disarming that watchdog and
clearing the persistent boot-in-progress marker. The matching initramfs uses a
leftover marker to select guarded USB rescue before starting providers.
The checker writes Linux state files; it does not mark slot B successful or
write boot metadata. See the [guard audit in NOTES](../../device/oriole/NOTES.md).

Those private assets and the companion's battery/startup policy are not a
portable device-package service. A supported standalone image needs a public,
matched startup/recovery path and its boot qualification first; this PR does
not import the private stack or enable services to approximate it.

Boot-success marking is separate and remains outside this package, pending
[#252](https://github.com/derekross/omarchy-mobile/issues/252) and Oriole's
qualification. On an unmarked B slot, ABL can exhaust its retry budget
(normally three attempts) and select A. The staged-start guard does not reset
that budget. With native Linux on userdata, selecting stock A is not a usable
Android recovery without deliberate userdata restoration; do not rely on an
automatic stock fallback. If stock Android does come up, decline any offer
to reset and take fresh read-only backups of the protected radio partitions
after any stock boot (`efs`, `efs_backup`, `modem_userdata`, `persist` and
`modem_a/b`) before further radio work.

The private companion also preserves `RebootWatchdogSec=1min`. That setting
only bounds a stuck shutdown when a usable watchdog driver is bound; it does
not replace the startup guard or mark a slot successful. The recovered checker
requires an open `/dev/watchdog0` and verifies disarm, but this audit does not
establish a watchdog-binding/shutdown-reset qualification for a standalone
public-kernel image. The copied cheetah setting is therefore deferred with the
other omitted safeguards, rather than presented as a qualified recovery path.
