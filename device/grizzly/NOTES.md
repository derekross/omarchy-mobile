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

The signed five-part M1 candidate passed host AVB signature, image
layout and checksum checks. A loopback Fastboot mock verified writes
to exactly the five slot-B destinations, a matching `vendor_boot_b`
readback prefix, and slot A remaining active after staging. In an
arm64 VM the experimental USB variant recovered early kernel records and all
three M1 markers through CDC ACM after a simulated disconnect and
reconnect. The host reader passed pseudo-terminal tests on macOS and
Linux. Physical USB enumeration, on-device M1 boot and capture
through AP UART or ramoops remain open.

## Before first light

- Establish a clean stock Android boot with A available for recovery.
  Recheck slot flags and the stock Recovery transport before any M1
  writes. Verify the live board selector and bootloader-provided
  memory reservations during the first hardware trial.
- Bring up the shared Malibu kernel support and a Grizzly board DTS in
  [linux-omarchy-mobile](https://github.com/derekross/linux-omarchy-mobile).
  Use the B0 observation to guide the first candidate and keep the stock
  tree comparison tied to its build. Verify the timer, watchdog and one
  observable console path.
- Stage a descriptor and Grizzly selector overlay after those values are
  confirmed. Validate the five images offline before an attended first boot
  to the shared initramfs on slot B. Keep stock slot A available for recovery
  and leave `userdata` out of the first boot test.

The M1 candidate is host-validated and awaits its first device boot.
