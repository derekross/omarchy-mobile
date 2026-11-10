<!-- SPDX-License-Identifier: MIT -->
# Pixel 9 Pro XL: installation and evidence history

These are sanitized observations from one development phone, not a new install
recipe or permission to repeat historical operations. Raw captures, images,
calibration backups and identifiers remain private. A retained note is evidence
of what the previous session recorded; where a transaction transcript has not
been recovered, that limitation is stated explicitly.

## 2026-11-02: Android and stock-derived facts

The retained pre-Linux Android capture identified vendor build
`CP3A.261005.005`, vendor security patch `2026-10-05`, and bootloader
`ripcurrentpro-17.0-15819938`. Android was running on slot A. These are historical
vendor-build facts; they do not establish the complete Android OS build or
prove that the currently retained slot-A images are unchanged factory images.
A fresh read-only capture on 2026-11-09 independently identifies that software
base in slot-A boot/init_boot properties, as described below; it still does not
attest the whole Android system's integrity.

The matching vendor_boot header was v4 with page size `0x800` and an empty
vendor command line. The previous Pixel 8 Pro splash/plymouth/cursor options
were not Komodo evidence and are removed. The shared image loader refuses an
empty VENDOR_CMDLINE; the descriptor retains only the existing G4 bring-up
flags (`console=tty0 clk_ignore_unused pd_ignore_unused printk.devkmsg=on
bootconfig`). Those are development boot arguments, not claimed stock header
contents. Whether Komodo's ABL forwards them remains unverified, and the base
DTS chosen bootargs must be reviewed separately.

The captured vendor_kernel_boot held six base DTBs. Four `google,zumapro`
selectors covered product `0x9875`, A0/A1 and package modes FOPLP `0`/IPOP `1`.
Those observed alternatives explain the descriptor's four tuples; they do not
identify this phone's physical package. The retained board overlay selected
board ID `0x60806`, revision `0x010000`. Google's GPL caimito source
independently matches both values in
[`zumapro-komodo-mp.dts` lines 17-18](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/dts/zumapro-komodo-mp.dts#17),
commit `38a058681d6cefbb95200dc8a5348939773eb9d6` on
`android-gs-caimito-6.1-android16`.

## 2026-11-02: first slot-B attempts and userdata loss

The first-light notes name `DEVICE=komodo bin/omamobile flash` as the slot-B
writer, for `boot_b`, `init_boot_b`, `vendor_boot_b`,
`vendor_kernel_boot_b` and `dtbo_b`. That is the retained runbook, not a
recovered transcript of the exact first transaction; the tool revision and
executed first command have not been independently reconstructed. Do not
upgrade this historical attribution into a verified transaction claim.

The tested kernel was `7.3.0-rc6-omamobile-push1-gcc144e3c9393-dirty`, built
from local `omamobile-komodo` on `cc144e3c9` with an uncommitted board DTS,
config and overlays. The local source worktree was `~/omamobile-kernel/mainline`.
The initial tests exhausted three ABL attempts and fell back to slot A. Later,
Linux found no ext4 signature on userdata and reported that its root could not
be mounted. The development Linux root was reinstalled from the locally
checked 2026.11.02 root image. A stock fallback can therefore cost the Linux
root before an owner chooses a recovery action.

The later first-light run returned USB SSH with the storage guard active.
That private development boot does not qualify the reduced descriptor's
separate public-kernel dependency or a new image cohort.

## 2026-11-02: historical boot-success operation

The retained notes record explicit owner approval for one boot-success
operation. An off-repository backup covered all 8192 bytes of devinfo. The
reported layout was 3.15; slot B was active and not successful. On 2026-11-10,
the executed laptop command and its completion output were recovered from the
2026-11-02 session. A laptop Python subprocess wrapper sent a `bash -s` script
that asserted the unique `PARTNAME=devinfo` was `/sys/class/block/sdd1/uevent`
and checked the complete before-image hash and bootctl's dry-run prediction.

The wrapper, not bootctl, made the target writable: it ran
`blockdev --setrw /dev/sdd` and then `blockdev --setrw /dev/sdd1`. Before those
commands it installed an EXIT restore trap and armed
`komodo-devinfo-relock` with a 30-second systemd timer, both restoring the
partition and its parent with `blockdev --setro`. It then ran the uploaded
`/run/omamobile-bootctl mark-successful /dev/sdd1 b --i-understand`, restored
read-only flags, checked the expected whole-image hash and stopped the timer.
The laptop read back all 8192 bytes and compared them to its predicted image.
The completion output reports success, only offset `0x35` changed from `0x14`
to `0x16`, and both read-only flags `1`. This names the historical guard bypass;
it does not add it to the storage allowlist or approve repeating it.

Independent offline comparison on 2026-11-09 of the retained approved-before/
after private files also confirms 8192 bytes each, DEVI version 3.15 and that
single-byte change. Slot A's four devinfo slot-metadata bytes are unchanged;
this is not an attestation of slot-A boot images or proof that the public 3.15
layout is independently qualified on G4. Current state must be read again
without writing. Maintainer review of the historical operation remains open.

The same notes record bootloader versions A `15819938` (the earlier Android
capture) and B `15199480` (the later fastboot capture). The recovered command
also explains the earlier local installer exception: a private copy of
`tools/install-phone` added a branch accepting unequal bootloaders only when
`OMAMOBILE_KOMODO_EXISTING_BOOTLOADERS=explicitly-accepted`, codename `komodo`,
current slot `b`, current bootloader `ripcurrentpro-17.0-15199480` and an empty
`slots_match` value all matched. It logged the previously captured A version
`ripcurrentpro-17.0-15819938` and explicitly did not claim matching slots. The
copy also changed development automatic boot writes to `AUTO_WRITE=no`.
This was a local installer preflight exception, not a bootloader update or a
public supported installation path; no bootloader write is recorded. The
mismatch remains a stop condition until the maintainer resolves recovery and
anti-rollback implications. Do not reuse that exception, change the public
installer's check, or write bootloaders to make them agree.

## Backups and later local development source

An off-repository backup directory dated 2026-11-02 21:30:37 contains a
SHA256SUMS manifest and retained copies of all six NV partitions. A separate
working-image backup dated 21:56:17 contains all five boot images. This review
checked their manifest coverage and file sizes, not a fresh partition checksum
comparison. The retained material does not yet establish a verified before/after
chain around every stock fallback. Old pre-fallback hashes cannot be treated
as current after Android ran.
Reconstruct the retained backup chronology and take/check a fresh read-only
set before radio, PMIC or Trusty work. A checksum match today alone does not
prove what changed during the historical stock boot.

A retained 2026-11-05 log records a later canonical `push` writing and verifying
only the five suffixed slot-B images and staging the matching modules. It is
not evidence of the first writer.

On 2026-11-09 the read-only identity capture reports
`7.3.0-rc6-omamobile-komodo-gnss-km4`. Its retained local source snapshot is
`out/komodo-display-km4-probehold-v2-20261105/source`, described by the private
artifact manifest SHA256
`e145e0cd65aa4ea1c679f3e9b7288bf6f6b6c8fab35741761f06cb91d5191031`.
This is a local development cohort with more changes than the reduced
first-light board. It is not claimed as a reproducible published kernel head.
The minimal public dependency remains separately identified in
[FIRST-LIGHT](FIRST-LIGHT.md); a public kernel PR and exact head are required
before that dependency is considered resolved.

## 2026-11-09: read-only partition inventory

A current unique-PARTNAME sysfs inventory confirms the six read-only NV labels
`efs`, `efs_backup`, `modem_userdata`, `persist`, `modem_a` and `modem_b`, and
the separate 8192-byte read-only `devinfo`. The retained 2026-11-02 Android
partition-name inventory also explicitly lists `metadata`, `trusty_persist`
and `trusty_userdata`; the same date's protected-backup inventory independently
records the two Trusty partitions as read-only. The 2026-11-09 targeted capture
selected only the six NV labels, boot images and devinfo, so its omission of
those other names is not evidence that they are absent.

`NV_PARTS` retains the six invariant NV checks. `NV_BACKUP_EXTRA` retains
devinfo and adds the three observed metadata/Trusty names for a separate backup
report; it does not add any of them to the writable allowlist. A future backup
must rediscover every exact PARTNAME and its read-only state. These historical
label observations are not a new current-state capture, a checksum check of
those extra partitions or a qualification of any Trusty write.

## 2026-11-09: current slot-A metadata and conditional slot state

The retained inspection captured the complete read-only `boot_a`, `init_boot_a` and 8192-byte
`devinfo` partitions without a write, bootctl execution, reboot or bootloader
transition. All three retained the same boot identity; unique PARTNAME, exact
sizes, block identity and read-only flags were checked before/after. Second
complete remote hashes and independent host readback hashes matched. The raw
images, fingerprints, hashes and capture receipts remain private.

AOSP `avbtool info_image` reports **Algorithm NONE**, rollback index **0** and
location **0** for both slot-A boot and init_boot. Both contain OS property
`17` and security-patch property `2026-10-05`; both Android v4 headers are
1584 bytes and encode `17.0.0` / `2026-10`. Software provenance properties
identify base `CP3A.261005.005`. Algorithm NONE is the observed footer metadata,
not proof of a factory signing chain or the complete Android system build.
The descriptor's rollback index is corrected to the observed slot-A `0`; its
OS/security fields now have actual slot-A evidence. None of this changes the
currently installed development images, whose older test-key/index policy is
separately described in FIRST-LIGHT. The currently booted slot-B images carry index
`1791158400` and were marked successful. A new set built with the descriptor's
`0` would therefore be the first index-0 footer cohort after that marked higher-
index boot. Whether ABL accepts that transition is unqualified, not established
by slot A's metadata or the Pixel 9a's footer-less images. The maintainer must
choose the intended rollback-index policy before any new image set is built
or booted; do not experimentally spend a retry to find out.

The actual devinfo header is DEVI version 3.15. Applying only the documented
public 3.15 byte-offset interpretation yields A and B successful, B active,
retry count 2 for each, and neither unbootable. Reserved fields are nonzero for
both. This is explicitly conditional: the public layout was verified on the
Pixel 7 Pro, not independently qualified for this G4 phone. It neither proves
the writer nor authorizes a new success/active write. A literal retry count of
2 is not a promise of two usable attempts when the layout/bootloader behavior
remains unresolved. No bootctl binary was executed for this inspection.

The exact first writer transcript, backup chronology, whole slot-A OS identity,
bootloader-side partition-size evidence, all-five footer necessity, public
kernel source and maintainer resolution remain explicit merge/boot
prerequisites. **Do not boot any new kernel/image set until these are resolved.**
