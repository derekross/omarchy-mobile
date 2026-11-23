<!-- SPDX-License-Identifier: MIT -->
# Pixel 11 Pro (grizzly) bring-up notes

Tracking [#26](https://github.com/derekross/omarchy-mobile/issues/26).
Stage 0, 2026-11-22. The retail phone was queried over USB ADB on locked
stock Android. Factory-image analysis was done separately on the host.

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
  builder emits RSA-4096 footers. Acceptance by unlocked Grizzly is open.
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
Android boot after acknowledgment. The EIO warning persists and its
trigger remains unknown.

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

## Before first light

- Keep stock A as the attended recovery path. Recheck slot flags
  and stock Recovery transport before activation. Verify the live
  board selector and bootloader-provided memory reservations during
  the first hardware trial.
- Bring up the shared Malibu kernel support and a Grizzly board DTS in
  [linux-omarchy-mobile](https://github.com/derekross/linux-omarchy-mobile).
  Use the B0 observation to guide the first candidate and keep the stock
  tree comparison tied to its build. Verify the timer, watchdog and one
  observable console path.
- Stage a descriptor and Grizzly selector overlay after those values are
  confirmed. Validate the five images offline before an attended first boot
  to the shared initramfs on slot B. Keep stock slot A available for recovery
  and leave `userdata` out of the first boot test.
