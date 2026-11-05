<!-- SPDX-License-Identifier: MIT -->
# OnePlus 6 (enchilada) bring-up notes

Findings from one retail OnePlus 6 (`ONEPLUS A6000`, `oneplus,enchilada`,
Qualcomm SDM845 / Snapdragon 845), newest first. Claim and discussion:
[#432](https://github.com/derekross/omarchy-mobile/issues/432). Captures
(`fastboot getvar all`, the partition map, command lines) stay off the
repository; facts from them are quoted here.

Every result below ran on one kernel, unless an entry says otherwise:
Linux `7.1.0-rc1-sdm845`, built from the
[sdm845-mainline tree at tag `sdm845-7.1-rc1-r0`][sdm845-tag]
(`85f1df2a4ec7`) with the qcom-sdm845 kernel configuration that tree is
distributed with, plus the netfilter matches in the 2026-11-05 entry, using
the upstream `qcom/sdm845-oneplus-enchilada.dtb`. Trying
linux-omarchy-mobile, which carries the same upstream DTS, is next.

[sdm845-tag]: https://gitlab.com/sdm845-mainline/linux/-/tree/sdm845-7.1-rc1-r0

## Slots and what is on them (CONTRIBUTING.md §3.1)

**Slot A does not hold stock Android.** This is a §3.1 event, recorded
here as the maintainer asked on #432. Until stock is back on slot A under
a plan approved on #432, this port stays RAM-only (`fastboot boot`).

| Where | What is there now | How it got there | Storage guard? |
| --- | --- | --- | --- |
| `boot_a`, `system_a` | a small Arch Linux ARM rescue root and its kernel | flashed by hand with `fastboot`, 2026-11-04, after a third-party Android build had replaced stock OxygenOS | yes: its init runs the shared guard (allowlist + `ro=1` on every other partition) |
| `boot_b` | a header-v0 boot image of this port | `fastboot flash boot_b`, 2026-11-04; re-flashed 2026-11-05 with the netfilter-match kernel | yes: the shared `initramfs/init` |
| `dtbo_b` | erased | `fastboot erase dtbo_b`, 2026-11-04: the third-party build's downstream overlays would not apply to a mainline DTB | - |
| `vendor`, `odm`, `system_b` | leftovers of the third-party Android build | that build's installer | - |
| `userdata` | an Arch root built by `bin/omamobile` | `fastboot flash userdata`, 2026-11-04 | - |
| bootloader firmware (`xbl`, `abl`, `tz`, `modem`, ...) | OxygenOS firmware, identical on `_a` and `_b` | never written by this port | - |

The slot flags were changed with `fastboot --set-active` while moving
between slots A and B; slot A is active. No slot flag is written again
until this phone has a per-device entry in CONTRIBUTING.md.

## 2026-11-05: complete backup

Every partition by GPT label except `userdata` (this phone has no
`super`), both slots: 100 images, taken from the slot-A rescue with
`persist`, `modemst1`, `modemst2` and `fsg` never mounted. The sha256 of
each raw partition was taken on the phone before the copy and checked
again after transfer and after decompression; 99/100 match all three
ways. The exception is `system_a`, which was the running rescue root, so
that copy is live; the image it was flashed from is kept beside it. The
backup is kept off the repository.

Every firmware partition is byte-identical between `_a` and `_b` (`xbl`,
`xbl_config`, `abl`, `aop`, `tz`, `hyp`, `devcfg`, `keymaster`,
`cmnlib`, `cmnlib64`, `qupfw`, `storsec`, `modem`, `dsp`, `bluetooth`,
`LOGO`), so the two slots' bootloader versions match.

## 2026-11-05: the firewall needs six netfilter matches

The first-light kernel configuration leaves out the xtables matches that
ufw's rules load through `nft_compat`. Without them `ufw-init` stops at
`before6.rules` (`-m rt`, `-m hl`) and `before.rules` (`-m limit`),
firstboot's "services and firewall" step never completes, and the
half-loaded ruleset blocks new SSH connections on `usb0`. Built as modules
(`NETFILTER_XT_MATCH_LIMIT`, `_HL`, `_STATE`, `_OWNER`, `_RECENT` and
`IP6_NF_MATCH_RT`), firstboot completed, `ufw status` was active with
`22/tcp on usb0 ALLOW IN` (IPv4 and IPv6), and fresh SSH sessions
worked. `kernel/configs/omamobile.config` already enables the same
matches, so linux-omarchy-mobile should not need this.

On the very first boot only, SSH on `usb0` was blocked for about 100 s:
`ufw.service` starts default-deny about 5 s into boot, and the `usb0`
rule arrives only when firstboot reaches its firewall step. Later boots
load the saved rule at once.

## 2026-11-05: Adreno 630 needs this phone's zap shader

With `linux-firmware-qcom`, `qcom/a630_sqe.fw` and `qcom/a630_gmu.bin`
load. The zap shader the DTB names,
`qcom/sdm845/OnePlus/enchilada/a630_zap.mbn`, is signed for this phone
and is not in linux-firmware, so `adreno_load_gpu` fails with `-2` and
the compositor cannot start. Like the modem's firmware, it has to come
from the phone's own partitions at install time and is never committed;
the modem/rmtfs plan will say how, before any radio step.

## 2026-11-04: RAM-only first light

A header-v0 boot image (gzip `Image` with the DTB appended, the shared
`initramfs/init`), booted with `fastboot boot`; nothing was written.

- The USB gadget came up about 4 s after `fastboot boot`, and
  `ssh root@172.16.42.1` worked.
- The storage guard held: allowlist `boot_b userdata`, every `sd*`
  partition `ro=1` except `userdata` (`sda17`), `/dev/sda` removed,
  nothing mounted. `omamobile.initramfs` kept it in the initramfs.
- **`boot_b` is on LUN `sde`, not `sda`.** The shared guard's `UFS_RW`
  only looks at `sda`, so `boot_b` and `dtbo_b` stay read-only (seen
  live). This is the same split as dodge; a LUN-aware `UFS_RW` will be its
  own shared pull request.
- msm DRM came up (`fb0` is `msmdrmfb`).
- ABL appends `root=PARTUUID=<system_a> skip_initramfs ro init=/init` to
  the command line even on `fastboot boot`. The shared init runs as PID 1
  regardless, so it needs no change.

## Stock facts (2026-11-04, before the port)

- Model `ONEPLUS A6000`; fastboot `product` `sdm845`, `variant` `SDM UFS`;
  `slot-count` 2; `max-download-size` 805306368 (768 MiB).
- Bootloader unlocked, EDK2-based ABL; `qcom,msm-id` 0x141
  (`androidboot.platform_id=321`).
- Boot images: Android boot image header v0, page size 4096, gzip kernel
  with the DTB appended; no `vendor_boot`, no `init_boot`. The header
  offsets are in `device.conf`.
- UFS: `userdata` is `sda17` (fastboot reports it as f2fs); `boot_*`, `dtbo_*`
  and `vbmeta_*` are on LUN `sde`.
- Panel: Samsung `sofef00` command-mode DSI, 1080x2280.
