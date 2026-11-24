<!-- SPDX-License-Identifier: MIT -->
# Pixel 11 Pro (grizzly) bring-up notes

Tracking [#26](https://github.com/derekross/omamobile/issues/26).
On November D1, the unlocked test phone boots stock Android from A
with verity enforcing. Attended slot B trials reached systemd and USB
SSH with a read-only RAM root and zero SCSI disks. The later UFS
diagnostics stop before PHY readiness. See the [bring-up plan](BRINGUP-M1.md)
and [trial sources and fixtures](bringup/README.md).

The first snapshot on 2026-11-22 used USB ADB on locked stock Android.
Factory-image analysis was done separately on the host.

## Live stock phone

| Item | Observed value | Source |
| --- | --- | --- |
| Model and SKU | Pixel 11 Pro, `GM45K`, `MP1.0` | Named ADB properties |
| Device and SoC | `grizzly`, `malibu` / Tensor G6 | `ro.product.device`, `ro.boot.hardware.platform`, `ro.soc.model` |
| Android build | Android 17, `CD1A.260905.001.A1`, patch `2026-09-01` | Named build properties |
| Bootloader and slot | `spacecraft-17.4-16075350`, locked, verified boot `green`, running from slot A | `ro.bootloader`, `ro.boot.flash.locked`, `ro.boot.verifiedbootstate`, `ro.boot.slot_suffix` |
| Kernel | `6.12.69-android16-6-g5c5f2fea42dd-ab15835541-4k` | `uname -r` |
| DT selection | `dtbo_idx=19`, `dtb_idx` empty | `ro.boot.dtbo_idx`, `ro.boot.dtb_idx` |
| Live SoC selector | `/proc/device-tree/soc_compatible` lists `B0`. The shell could not read its property values or `/sys/firmware/fdt`. | Named paths listed or read with ADB |
| Partition names | Both slots expose `boot`, `init_boot`, `vendor_boot`, `vendor_kernel_boot`, `dtbo` and `vbmeta`. Shared `userdata` is present. | Selected names from `/dev/block/by-name` |

The public Grizzly [factory](https://developers.google.cn/android/images?hl=en#grizzly)
and [full OTA](https://developers.google.cn/android/ota?hl=en#grizzly) lists
show the September `.B1` build. The exact `.A1` image was not found there.
The other retail Grizzly in #26 runs October `CD1A.261005.003`, boots from
slot B and reports DTBO entry 28. Both phones are reported as MP1.0.

## October factory-image comparison

Compared the published `CD1A.261005.003` archives for
[Grizzly](https://dl.google.com/dl/android/aosp/grizzly-cd1a.261005.003-factory-7c6dad8a.zip)
and [Kodiak](https://dl.google.com/dl/android/aosp/kodiak-cd1a.261005.003-factory-006d44d7.zip).
Read the boot-image ZIP members over HTTP ranges, checked their ZIP CRCs,
and matched the five boot-image payloads against their AVB hash descriptors.
This did not check whole-archive SHA-256 or authenticate AVB signatures.
Headers were read with AOSP `unpack_bootimg`, DTB nodes with `fdtdump` and
`fdtget`, overlays with `fdtoverlay`, and AVB metadata with Android 17's
[`avbtool`](https://android.googlesource.com/platform/external/avb/+/refs/heads/android17-release/avbtool.py).

- Both use v4 headers and `0x800` vendor page size. `boot` carries the kernel,
  `init_boot` reports OS `17.0.0` and patch month `2026-10`, and
  `vendor_kernel_boot` carries the base DTBs.
- The two concatenated base DTBs in `vendor_kernel_boot` are byte-identical
  across both archives. Each has root compatible `google,mbu`. The A0
  selector has product ID `0x06`, major `0`, minor `0`, package mode `0`.
  B0 has the same tuple with major `1`. The shared base DTBs are a reference
  for a common Malibu `.dtsi`.
- In Grizzly's October DTBO table, entry 19 is `0x80506` / `0x10000` and
  entry 28 is `0x80506` / `0x10001`. The latter matches the index reported
  in #26 and its overlay applies offline to both October base DTBs. Kodiak
  entry 37 is `0x80406` / `0x10000`. An index observed on `.A1` does not
  establish the corresponding October entry's ID or revision on `.A1`.
- October `vbmeta` chains `boot` (rollback location 2) and `init_boot`
  (location 4) and lists `vendor_boot`, `vendor_kernel_boot` and `dtbo` as
  hash descriptors. The two chained images have ML-DSA-65 AVB metadata,
  rollback index `1791158400` and patch property `2026-10-05`. Their factory
  image sizes are `0x4000000` and `0x800000` bytes. The existing image
  builder emits RSA-4096 footers. Unlocked D1 later booted the v38 bundle
  with two test RSA-4096 leaves. The stock handoff-only trial also reached
  PID 1 with a factory ML-DSA-65 `boot` and a test RSA-4096 `init_boot`.
- The stock tree points to a DesignWare UART at `0x3bdd6000` in `/chosen`.
  For USB, it describes a DWC3 core behind `google,dwc3-mbu`, with
  Malibu PHY, clock, reset and power-domain dependencies. Neither console
  path has been verified under the Omarchy kernel.

## November D1 recovery and first-light checks

On 2026-11-23, the retail Grizzly booted stock `CP4A.261105.040.D1`
from slot B after a same-build full OTA sideload from Recovery on
slot A. The OTA checksum and signature matched the official package
and stock Recovery certificate. Before unlock, both slots had
completed a locked D1 Android boot with green Verified Boot and the
same factory AVB chain digest.
[Grizzly full OTA](https://developers.google.cn/android/ota?hl=en#grizzly)

Locked bootloader Fastboot reported D1 ABL `spacecraft-17.4-16729013`,
both slots successful and bootable, two tries per slot, and snapshot
update status `none`. It rejected active-slot selection while locked.
Live sizes matched the D1 factory files and were identical on A and B.

| Partition | Bytes | MiB |
| --- | ---: | ---: |
| `boot` | 67,108,864 | 64 |
| `init_boot` | 8,388,608 | 8 |
| `vendor_boot` | 67,108,864 | 64 |
| `vendor_kernel_boot` | 67,108,864 | 64 |
| `dtbo` | 16,777,216 | 16 |

After the standard bootloader unlock, Fastboot reported
`unlocked:yes`. Normal boot attempts on A and B both showed the red
device corruption warning. At the next Fastboot check each slot was
still marked bootable, with one try and its successful flag cleared.
Stock D1 Recovery on B reached ADB after the warning was acknowledged.
It reported orange Verified Boot and `ro.boot.veritymode=eio`. Its
AVB digest still matched the factory chain
(`291428847dd4ceb93428928f14712738b2994281f10c212501ca42ab2fbcbd8b`).
A persistent managed-verity decision shared by the matching chains
could explain both warnings. The trigger remains unknown. The
device tests used stock images throughout.
[Android Verified Boot error handling](https://source.android.com/docs/security/features/verifiedboot/verified-boot#handle-verification-errors)

A second full stock D1 OTA from Recovery on B activated A with
three boot tries. The first stock boot on A still showed the red
warning. After acknowledging it, Android reached the home screen.
ADB confirmed a completed D1 boot on A with the factory AVB digest
and `ro.boot.veritymode=eio`. The same-build repair restored the
Android boot after acknowledgment. Managed EIO persisted through
that repair and the following Recovery round trip.

An Android bugreport from A still reported managed EIO. Its retained
kernel log began 3.210 seconds into the boot and showed no explicit
dm-verity block failure or block I/O error in the captured window.
The vendor bootloader attachment recorded red-warning acknowledgment
timeouts in earlier attempts on both slots. It did not identify a
failed partition.

Stock Recovery on A exposed the ADB sideload transport. The first
return to Android ended at a dark screen. After entering Fastboot and
rebooting A again with timely acknowledgment, ADB confirmed D1
completed boot with the same factory AVB digest and managed EIO still
active. This is a verified attended stock fallback.

The signed five-part M1 candidate passed host AVB signature, image
layout and checksum checks. A loopback Fastboot mock verified writes
to exactly the five slot-B destinations, a matching `vendor_boot_b`
readback prefix, and slot A remaining active after staging. In an
arm64 VM the experimental USB variant recovered early kernel records and all
three M1 markers through CDC ACM after a simulated disconnect and
reconnect. The host reader passed pseudo-terminal tests on macOS and
Linux. Physical USB enumeration, on-device M1 boot and capture
through AP UART or ramoops remain open.

The standard signed watchdog and ramoops M1 package was staged on
live Grizzly through the stage-only workflow. Fastboot returned
`OKAY` for all five B partitions. A remained active and successful.
B reported three tries and its successful flag cleared. A 64 MiB
`vendor_boot_b` readback matched all 8,192 bytes of the staged
`vendor_boot.img` prefix. The phone stayed in Fastboot with A active.

The USB-logging variant was then staged through the same workflow.
It changes only `vendor_kernel_boot.img` relative to the standard
package. All five Fastboot writes and the `vendor_boot_b` readback
passed again. A stayed active and successful, and B has three tries.
The physical USB console still needs validation during a boot.

The first attended B boot returned to Fastboot in about three
seconds with all three tries remaining. The Mac saw no USB logging
interface. ABL continued past the connector path warning, then
failed to resolve the `serial0` alias during its FDT fixups.
The UART disable operation returned `-5`, and ABL entered Fastboot
with reason `boot failure`. Linux handoff and USB enumeration remain
unverified. Returning to stock D1 on A completed successfully. ADB
reported the factory AVB digest and verity mode `enforcing`.

Fastboot reported `avb-hastree-error-mode:eio` before B was
selected and `restart` after that first failed B attempt, before
returning to A. The change therefore occurred in ABL before
Linux ran. D1 ABL can clear the shared managed-verity marker
when the loaded VBMeta digest differs. This is consistent with
the captured sequence. The exact branch taken and original EIO
trigger remain unverified.

The rebuilt diagnostic supplies the stock `serial0`, pinctrl and
UFS paths used by D1's FDT fixups, and preserves the expected USB-C
connector path. The three added controller nodes use stock
addresses and remain disabled without Linux driver bindings.
The USB ramdisk stays byte-identical. The corrected package passed
host schema, handoff and loopback staging checks. A live stage-only
pass then wrote the corrected package to B and verified the
`vendor_boot_b` image prefix again.

The corrected B trial reached the G logo and produced no M1 USB
gadget or ACM interface during a 145-second observation. Fastboot
returned after manual key entry with reason `vol down pressed` and
two B retries remaining.

The post-trial stock A bugreport records D1 ABL selecting diagnostic
DTB index 0 and reporting `serial0 disabled ret=0`. ABL passed the
board FDT fixup and recorded the initrd at
`0x86000000` through `0x8627bc51`. ABL reached its final
system-handoff callback. A missing AVB boot fingerprint logged a
message and took the fallback that rejoins the normal path. The
retained B trace ends during display PHY power-off in that
callback. The preceding 10-second gap matches the D1 warning
display timeout.

The recovery log records a cold reset with the long Power key
reason and APC watchdog subreason `0x00`. The retained traces lack
an explicit Linux entry message, and the bugreport has no pstore
console attachment or M1 markers. Linux entry and PID 1 liveness
remain unverified. Stock D1 finished booting again from A with the
factory AVB digest and verity mode `enforcing`.

A diagnostic variant uses a minimal PID 1 that requests normal
Linux shutdown 70 seconds after entry. It uses the same kernel and
corrected ABL paths, with the watchdog and ramoops overlays and
the USB overlay omitted. The exact kernel and initramfs shut down
an arm64 VM 70.009 seconds after PID 1 entry.

All five B writes for the timed variant passed on Grizzly. The
live `vendor_boot_b` readback matched the 8,192-byte image prefix.
Fastboot confirmed A active and successful and B bootable with
three tries.

During the attended timed trial the operator reported a restart
followed by a battery icon. The Mac recorded those reports 99
and 108 seconds after the reboot request. The stock recovery log
shows a normal B boot and a separate cold B boot with
`bootmode:charger`. Both loaded the timed fixture's initrd and
reached ABL's system-handoff callback. The charger boot records
`CHG_IN`, a main PMIC event and APC watchdog subreason `0x00`.
The retained candidate epochs include no RED EIO timeout.

The charger transition supports the timed shutdown. The
recovery log has no M1 marker or explicit PSCI shutdown record,
so the exact PID 1 execution and watchdog service are still
unconfirmed. Fastboot returned on manual key entry and stock A
again completed a D1 boot with verity enforcing.

The USB timed variant uses the corrected USB kernel, DTB and ACM
relay. Its PID 1 requests shutdown at 70 seconds, extended to
110 if the DWC3 UDC appeared in sysfs by the first deadline.
The VM confirmed both timings, using a simulated UDC path for
the later case. A hardware trial can capture the Linux log if
ACM enumerates or use a timed charger transition as indirect
evidence of controller registration.

The variant was staged on Grizzly. Fastboot acknowledged all
five B writes and the `vendor_boot_b` readback matched the
8,192-byte image prefix. A remained active and successful and
B reported three tries.

The attended USB timed boot produced no ACM port during the
155-second capture. The operator reported the charging screen
by 113.6 seconds after the reboot request. The recovery log
confirms a separate cold B boot into charger mode using the
same timed USB initrd. The first B boot reached late ABL
handoff at about 11.6 seconds, and the charger epoch matches
the earlier timed control's Main-PMIC event, `CHG_IN` and zero
APC watchdog subreason. Neither epoch records a RED EIO timeout.

DBL and ABL both recorded an 82-second interval between the
two B boots, matching the previous timed control. This fits
the 70-second branch plus ABL handoff. The recovery log lacks
a PID 1, UDC or shutdown marker to attribute the transition.
Following manual Fastboot entry, stock D1 booted again on A
with verity enforcing.

The DWC3 timing variant records the furthest USB stage observed
in the first 70 seconds of PID 1. It requests power-off at
70 seconds if neither path appeared, 110 seconds if it observed
the DWC3 platform child, or 150 seconds if it observed the UDC.
The Mac VM confirmed all three timers with simulated device
paths for the latter two. On Grizzly, the charger transition
can provide indirect evidence if the USB log port stays absent.

Fastboot acknowledged all five B writes for the DWC3 timing
variant. The live `vendor_boot_b` readback matched all
8,192 supplied image bytes. A remained active and successful,
and B reported three tries.

The attended DWC3 timing trial produced no USB logging port.
DBL and ABL record a cold charger-mode boot 82 seconds after
the first B boot, with the expected initrd on both. The
charger-mode PMIC and watchdog fields match the prior timed
trials. This fits the earliest timer and places the transition
before either extension could have fired.

The result points to the DWC3 child and UDC going unobserved.
No direct marker was recovered to establish PID 1 causation
or sysfs availability. The next trace target is the wrapper's
PHY and repeater prerequisites, including CPM regulator
registration. Stock A booted again with verity enforcing.

A CPM regulator diagnostic samples the three expected sysfs
rail names at 70 seconds after PID 1 and searches its retained
printk records for CPM's regulator rejection warning. The
shutdown timer is 70 seconds when the evidence is inconclusive,
110 seconds when it finds the rejection warning and an
incomplete name set, or 150 seconds when all three names are
visible. The Mac VM confirmed the three timings with simulated
warning and sysfs inputs.

Fastboot acknowledged all five B writes for the regulator
diagnostic. The live `vendor_boot_b` readback matched the
8,192 supplied bytes. Fastboot verified A active and successful
and B bootable with three tries.

The attended regulator trial produced no USB serial port.
DBL and ABL put the second B boot into charger mode 82 and
83 seconds after the first, respectively. Both boot records
identify the expected regulator diagnostic initrd. The timing
fits the inconclusive 70-second branch. No recovered marker
shows CPM regulator rejection or publication, leaving both
open. Stock D1 finished booting again on A with verity
enforcing.

The deferred-probe capture variant copies Linux's
`devices_deferred` into the ramoops console and requests an
ordinary warm restart after reading back the reboot mode.
The initramfs suppresses another request if the previous
console already contains its marker. An arm64 VM recovered a
verbatim simulated deferred-probe line across a RAM-preserving
kernel transition. D1's archive and stock readout still need
the attended hardware test.

Fastboot accepted all five B writes for this variant.
The live `vendor_boot_b` readback matched all 8,192 supplied
bytes. A remained active and successful and B had three tries.

The hardware trial recovered the actual slot B Linux console
from stock A's pstore and `SYSTEM_LAST_KMSG`. It records PID 1
entry, six deferred-probe snapshots and an orderly warm restart.
DBL reported a warm restart, ABL requested its automatic cold
follow-up, and Volume Down took that cold boot to Fastboot.
Stock D1 then booted on A with verity enforcing.

DWC3 `a200028.usb` reports `supplier system-controller not ready`.
Earlier in the same console, `google-malibu-cpm-io` failed with
`error -EBUSY: failed to get CPM response channel`. The mailbox
core reported the error from the MBA startup callback. This pins
the first failure to CPM RX mailbox startup, before regulator
registration. The captured log does not identify which mailbox
queue predicate returned `-EBUSY`.

The next kernel adds one warning at the MBA startup rejection.
It records the Linux `used` flag, the raw queue value at
`+0x10` and the raw interrupt status at `+0x08`. On this
board the CPM response queue is at `0x0ea61000`. Stock D1's
mailbox driver acknowledges pending RX and TX interrupts
before registering the controller. The new warning keeps the
existing startup guard and will show which conditions it saw.

The Mac VM confirmed the tagged warm restart used to recover
this diagnostic. On 2026-11-23, Fastboot accepted all five B
images, and the live `vendor_boot_b` readback matched the
8,192 supplied bytes. A remained active and successful. B was
bootable with three tries.

The attended trial recovered the tagged kernel console from
stock A's pstore and `SYSTEM_LAST_KMSG`. The first stock
bugreport corroborated the diagnostic and warm/cold sequence.
At `ea61000.mailbox`, startup recorded `used=0 outstanding=0x0
irq_status=0x1`.
The pending RX interrupt alone caused `-EBUSY`. DWC3 still
waited on CPM and the host saw no USB ACM port. Stock A booted
with verity enforcing after the trial.

The next targeted change is to mirror D1's masked interrupt
acknowledgement before mailbox controller registration and keep
the startup guard. A follow-up boot should check that CPM
acquires both channels and completes its handshake, then check
DWC3 probe and USB enumeration.

The v14 candidate applies that acknowledgement and adds
console markers for the CPM and DWC3 driver binds and for UDC
registration. Offline checks covered the observed RX state,
unrelated interrupt bits, and the existing startup guard. The
Mac VM confirmed the tagged warm restart.

On 2026-11-23, Fastboot accepted all five v14 slot B images.
The `vendor_boot_b` readback matched all 8,192 supplied bytes.
Stock A remained active and successful, and B was bootable with
three tries.

The attended v14 console records `ea61000.mailbox` acknowledging
IRQ status `0x1`. CPM and DWC3 stayed bound, the UDC was registered
in all six snapshots, and all six deferred-device samples were
empty. Linux bound the ACM gadget to `a210000.usb`. The Mac saw
no Grizzly USB enumeration. The warm restart returned to Fastboot,
and stock A booted with verity enforcing. Its pstore and
`SYSTEM_LAST_KMSG` returned the tagged v14 console, also present
in the first stock bugreport.

The remaining USB check is between gadget binding and host
enumeration. Capture the UDC state and speed, Type-C partner and
data role, and the Malibu wrapper's role callback together during
the next trial. The wrapper starts the PHY and repeater in the
disconnected role.

The v15 diagnostic records Type-C attachment and TCPM events,
MAX77779 data-gate readback, the Malibu role callback, and UDC
state and speed. Stock D1 reports a configured USB connection
on the same Mac cable in Type-C sink/device mode. The arm64
VM confirmed the diagnostic's tagged warm restart.

On 2026-11-23, Fastboot accepted all five v15 images on B.
The `vendor_boot_b` readback matched all 8,192 supplied bytes.
Stock A remained active and successful, and B was bootable with
three tries.

The attended v15 console records MAX77779 port and IRQ readiness
and an initial CC1 source advertisement. TCPM went from
`SNK_UNATTACHED` to `SNK_ATTACH_WAIT`, then the startup reset
returned it to `SNK_UNATTACHED` after the 920 ms wait. No later
CC or power alert or device-role request appeared in the capture.
The six snapshots show no Type-C partner and UDC `not attached`
with unknown speed despite the ACM gadget bind. The Mac saw no
USB enumeration. Stock A booted with verity enforcing and the
tagged console was verified in pstore, `SYSTEM_LAST_KMSG`, and
the first bugreport.

TCPM samples CC before it forces the startup reset. The Grizzly
sink sets Rd during reset and again on return to `SNK_UNATTACHED`.
An attended reconnect after reset can test whether a fresh CC
event gets the same v15 images past attach wait.

A v15 rerun kept the cable connected throughout. The bugreport
records the warm reboot, the cold follow-up handing off v15 on B
again, and a long-key master disconnect clearing nonsecure memory
before manual Fastboot entry. Stock A booted with verity enforcing.
Pstore had no console and `SYSTEM_LAST_KMSG` contained only
previous captures.

In the attended reconnect test, the same v15 images returned to
`SNK_UNATTACHED` after reset. Disconnecting produced CC open and
VBUS off. Reconnecting produced fresh CC and VBUS events, the
MAX77779 data gate read back `0x9`, and TCPM reached `SNK_READY`.
The UDC reported `configured` at `high-speed`. The Mac saw the
Grizzly ACM gadget, and the warm recovery returned to stock A.
Pstore, `SYSTEM_LAST_KMSG`, and the first stock bugreport contained
the new tagged console.

The next change can give this MAX77779 sink a fresh CC and VBUS
sample after startup reset, using the normal TCPM attach path.

The signed v16 candidate adds that opt-in and queues the existing
VBUS and CC events when the sink leaves reset. Offline tests
covered the guards, debounce, and missing CC or VBUS. The Mac
VM confirmed the tagged warm restart. On 2026-11-23, Fastboot
accepted all five B images and the `vendor_boot_b` readback
matched all 8,192 supplied bytes. A remained active and
successful and B was bootable with three tries.

On hardware, v16 attached with the USB cable continuously
connected. TCPM sampled VBUS present and unchanged CC1 Rp
after reset, used its normal 200 ms debounce, and reached
`SNK_READY`. The UDC reached `configured` at high speed. The
Mac enumerated the Grizzly ACM interface and read 29,950 bytes
of live kernel log. The warm recovery returned to stock A with
verity enforcing. Pstore, `SYSTEM_LAST_KMSG`, and the first stock
bugreport contained the tagged console.

The v17 trial uses the shared Omarchy initramfs in RAM rescue
mode with the proven v16 kernel and disabled UFS node. A VM
passed an authenticated SSH command over virtual NCM and the
exact phone payload passed the 90-second warm-restart check.
On 2026-11-23, Fastboot accepted all five images and the
`vendor_boot_b` readback matched all 8,192 supplied bytes. A
remained active and successful and B was bootable with three
tries.

The attended v17 hardware boot exposed NCM and ACM with the
cable continuously connected. The Mac verified the SSH host
key over ACM and authenticated over the NCM IPv6 link-local
route. The session observed `ram-rescue`, a `rootfs` mount at
`/`, and zero UFS disks, then retrieved the live kernel log.
The timed warm restart reached Fastboot and stock Android
booted again on A with verity enforcing. Pstore,
`SYSTEM_LAST_KMSG`, and the first stock bugreport contained
the tagged console. The bootloader archive recorded the DBL
warm boot with CDD reason `0xbaba` and the subsequent cold
boot entering Fastboot with Volume Down.

An arm64 VM running the v17 kernel booted the signed Omarchy
Mobile 2026.11.15 Cheetah reference root through `switch_root`.
Systemd ran as PID 1 with read-only ext4 on a RAM-backed loop
device and zero SCSI disks. The isolated target checked the
Omarchy packages and ran `Hyprland --version`. The reference
device's firstboot, slot-success and USB rescue units were
unavailable to PID 1. A truncated stream stopped before the
handoff.

The v18 phone trial moved the 3.08 GB reference stream over
authenticated USB NCM and decoded the full 11.54 GB ext4
image into tmpfs. The raw SHA-256 pass had read 7.20 GB as
the handoff window closed and systemd stayed pending. The
independent return helper requested a warm reset at 420.013
seconds. Fastboot returned and stock D1 booted again from
slot A with verity enforcing. Pstore, `SYSTEM_LAST_KMSG`
and the first stock bugreport matched the four tagged lines.
An off-device OpenSSL run verified the same raw SHA-256 in
6.952 seconds and reached the isolated systemd target. D1
advertises SHA-2 instructions on all seven CPU cores.

The v19 fixture uses OpenSSL for the same raw SHA-256 gate.
In the exact-kernel arm64 VM it verified the reference image
in 7.515 seconds, reached the isolated systemd target and
powered off on schedule. Rescue rejected a valid compressed
image with a wrong digest. The package passed the five-image
stage-only simulation.

On hardware, v19 verified the RAM image with OpenSSL in
37.199 seconds and reached Omarchy's systemd as PID 1. The
isolated service confirmed read-only ext4 on a RAM-backed
loop device, zero SCSI disks, and the return helper after
handoff. The warm reset fired at 420.013 seconds, and stock
D1 booted again from slot A with verity enforcing. Pstore,
`SYSTEM_LAST_KMSG`, and the first stock bugreport contain
the matching userspace check and reset markers.

The v20 trial started OpenSSH after systemd took over and
bound it to the USB IPv6 address on port 2222. The Mac used
the same pinned Ed25519 host key as in rescue and opened an
interactive PTY. The shell confirmed systemd PID 1, read-only
ext4 on the RAM-backed loop device, and zero SCSI disks.
The warm timer returned the device to Fastboot and stock D1
booted again on slot A with verity enforcing.
Pstore, `SYSTEM_LAST_KMSG`, and the first stock bugreport
contain the matching systemd, SSH PTY, and warm reset markers.

Stock D1 logs from that run show five direct-access UFS LUNs
and three well-known LUNs. The disabled Malibu resource
description now matches D1's eight register windows, HSIO-S
host interrupt, 16 direct IRQs, and AMB SMMU stream. The
LUN-only diagnostic keeps SCSI discovery while excluding block
and raw-command interfaces. An arm64 VM verified that policy
with a disposable USB-attached disk. Power sequencing and the
Malibu host/PHY variant remain the gates for the first phone
scan.

## Current UFS status

The host recorded these UTC times immediately before issuing each
Fastboot reboot request for slot B.

| Trial | Boot request (UTC) |
| --- | --- |
| v21 | 2026-11-23 18:02:12 |
| v22 | 2026-11-23 18:34:46 |
| v23 | 2026-11-23 19:00:52 |
| v24 | 2026-11-23 19:19:36 |
| v25 | 2026-11-23 19:36:58 |
| v26 | 2026-11-23 19:50:58 |
| v27 | 2026-11-23 20:11:07 |
| v28 | 2026-11-23 20:35:03 |

All eight requests preceded the 2026-11-24 01:11 UTC review.

v21 hit a CPM timeout before the rescue marker. ABL handed
off to it twice after one boot request and a warm crash reset.
v22–v28 reached RAM rescue and exercised the early Malibu
UFS sequence on D1. The v28 log records HC PSM
`0x10` and PHY PSM `0x11` before GPIO setup, through both
clock requests, PMIC decoupling and both domain votes.
The final PHY poll timed out at `0x11` (`-110`) after 10 ms.
The driver skipped the TOP bit 4 poll and retained its votes.
Stock A completed boot with verity enforcing and its original
VBMeta digest.

The full v29 fixture samples PSMs before the CPM startup
frame, around acquisition of HSIO-S, and around SGIA IRQ
setup. It reads HC and PHY after the wrapper reports `0x10`.
A handoff-only repack was requested at 05:43:57 UTC on 2026-11-24,
after that review. It
confirmed HSIO-S and HC at `0x10` and PHY at `0x11` before
the CPM startup frame, with the UFS driver blacklisted.
The [bring-up plan](BRINGUP-M1.md#v29-handoff-only-result)
records the live sample and retained logs.
The [maintainer later approved the v29 rail and backup ordering](BRINGUP-M1.md#maintainer-decision-on-the-first-nv-backup)
for a read-only rescue boot using stock voltage settings.

The v30 link diagnostic decoded LPCM8 PSM1 to the HC status
word at `0x3c00c210`. Before and after both issued votes, PSM1
was 0, HC was `0x10` and PHY was `0x11`. Both votes returned 0.
The PHY poll timed out and stock A completed boot after the warm
return. [v30 trial](BRINGUP-M1.md#v30-slot-b-result)

The v31 trial decoded PSM3 descriptor `0x00021325` to
`0x3c00e108` in all four samples. The address fell outside that
fixture's allowlist, leaving PSM3 state unknown. PSM1 remained 0,
HC `0x10` and PHY `0x11` across both votes. Stock A completed boot.
[v31 trial](BRINGUP-M1.md#v31-slot-b-result)

The v32 trial read PSM3 state `1` at `0x3c00e108` before and after
both votes. PSM1 remained `0`, HC `0x10` and PHY `0x11`. The PHY
poll timed out and stock A completed boot after the warm return.
[v32 trial](BRINGUP-M1.md#v32-slot-b-result)

v33 found BUCK11S and BUCK13S enabled at the stock selectors before
core-on and after the PHY timeout. Both retained consoles agree.
Stock A completed boot. [v33 trial](BRINGUP-M1.md#v33-slot-b-result)

v34 read PHY reset acknowledgment `0x1001` at `0x3c01b05c`.
Bit 12 showed reset released while PHY readiness timed out at
`0x11`. Stock A completed boot. [v34 trial](BRINGUP-M1.md#v34-slot-b-result)

v39 inherited the HSIO-S ON vote and issued the UFS prep and core
ON votes successfully. HC was `0x10` and PHY was `0x11` before
the CPM startup handshake, around each vote and through the
21.48-second sample. Stock A completed boot. A prepared
[stock consumer trace](BRINGUP-M1.md#stock-d1-ufs-consumer-trace)
captures existing UFS driver reads and MBFS events to compare
stock's later probe with v39. The stock trace recorded PHY
`0x11` then `0x10` 390 µs later, followed by the core ON notifier
reading TOP bit 4 set. Stock reached HS gear 5, and the inventory
and NV guard passed. Ring overwrite left the preceding votes
unresolved. [Stock trace result](BRINGUP-M1.md#stock-d1-slot-b-trace-result)

The corrected stock trace captured successful MBFS prep and core
ON requests. Later stock trials measured PSM1 `0x3` before prep ON
and `0x2` after it, with `0x2` still present before core ON. PHY
reached `0x10` 4 µs after the core reply, followed by TOP bit 4 and
HS gear 5. Genpd showed one completed idle transition each for
prep and core before UFS loaded. The NV guard passed and stock A
booted with enforcing verity.
[Prep PSM1 and genpd trial](BRINGUP-M1.md#d1-prep-psm1-and-genpd-hardware-result)

Coordinate device findings with [#26](https://github.com/derekross/omamobile/issues/26).
That report covers a second MP1.0 Grizzly on the October build.
