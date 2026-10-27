<!-- SPDX-License-Identifier: MIT -->
# Pixel 4 XL (coral): direct ABL boot and guarded storage bring-up

Status (2026-10-22): direct Android Bootloader (`ABL`) boot to native Arch Linux
ARM / Omarchy 4.0.4 + Hyprland on `6.17.0-sm8150`. The kernel is
[the SM8150 kernel tree at commit `6963e3800a8e`][sm8150-kernel] (three commits
past tag [`v6.17.0-sm8150` (`379d8fe35c7c`)][sm8150-tag]) plus the two ordered
`coral` kernel patch series. The series, device trees, userspace patches and
initramfs are published in
[`HemangKumawat/omarchy-mobile-coral`, tag `v0.2.3`][coral-repo]
(`78f77e861cfed7cbb57aea7eedc3c539ae1c8e81`). Its [`PROVENANCE.md`][coral-provenance] gives the byte-level check
of the installed kernel `Image` and 12-entry DTB, and lists what cannot be
rebuilt from that repository.

This bring-up is not yet built by `bin/omamobile` in this repository, and
`coral` does not yet have a `CONTRIBUTING.md` §3.1 GPT boot-success exception or
`tools/install-phone` integration. The `device/coral/device.conf` descriptor
sets `BOOT_METHOD=android-v2` and `COMPATIBLE="google,coral"` (the first
compatible string in [`sm8150-google-coral.dts`][coral-dts]) so `bin/omamobile` and
`tools/install-phone` refuse `DEVICE=coral` before touching a phone (`coral`
uses Android boot image header v2 with `boot` and `dtbo` partitions only; there
is no `vendor_boot`, `init_boot`, or `vendor_kernel_boot`).

[sm8150-kernel]: https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux/-/commit/6963e3800a8e8059c5f01b01dd8e2a5e6a28209a
[sm8150-tag]: https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux/-/tree/v6.17.0-sm8150
[coral-repo]: https://github.com/HemangKumawat/omarchy-mobile-coral/tree/v0.2.3
[coral-provenance]: https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/PROVENANCE.md
[coral-dts]: https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/dts/sm8150-google-coral.dts

## 1. Sources and provenance

- **Kernel base:** [the SM8150 kernel tree at commit `6963e3800a8e`][sm8150-kernel]
  ("power: supply: idtp9418: remove unused variable"), which is three commits
  ahead of tag [`v6.17.0-sm8150` (`379d8fe35c7c`)][sm8150-tag] on `sm8150/6.17`
  (`53a8b55839d1`, `01fc3dd3c831`, `6963e3800a8e`, each the parent of the next).
- **Authoritative ordered kernel series ([`PROVENANCE.md`][coral-provenance]):**
  - [`kernel/series/coral-30/`](https://github.com/HemangKumawat/omarchy-mobile-coral/tree/v0.2.3/kernel/series/coral-30)
    (patches `0001`..`0007` + `config`) and then
    [`kernel/series/coral-fec40357/`](https://github.com/HemangKumawat/omarchy-mobile-coral/tree/v0.2.3/kernel/series/coral-fec40357)
    (patches `0008`..`0011` + `config`; the combined order is in
    [`kernel/patches/series`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/series)),
    applied with `git am` on `6963e3800a8e`, give git tree
    `6d4115553ae5a9aec7b9e4ae23f77b2e4c4d7c4e`.
  - Kernel `#30` (`6.17.0-sm8150 #30 SMP PREEMPT Mon Oct 19 21:29:48 CEST 2026`)
    was built from a worktree with exactly that content (patch `0011` was
    committed 27 minutes after the build). The installed `boot_a` `Image` equals
    that build output except byte 10 (`text_offset`, set to `0x80000` by
    `tools/pack-bootimg.py`) [V]. `coral-30` alone (tree `21eb1828b205`) does not
    give this `Image`, because `0010` (`max77826-regulator.c`) and `0011`
    (`dsi_host.c`) change built-in drivers. Nobody has rebuilt the `Image` from
    the published series yet.
  - The same tree built the installed 12-entry DTB (sha256
    `3efe241aa349ff260ef0312e1b0a3a611943f71b0939261729c42e3842c90058`, rebuilt
    byte-identical with `dtc` 1.8.1) [V] and the SLPI, audio and camera modules.
- **Per-topic kernel DTS and patches in [`HemangKumawat/omarchy-mobile-coral` (`v0.2.3`)][coral-repo]:**
  - Device trees:
    [`kernel/dts/sm8150-google-coral.dts`][coral-dts],
    [`kernel/dts/sm8150-google-coral-audio.dtsi`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/dts/sm8150-google-coral-audio.dtsi),
    [`kernel/dts/sm8150-google-coral-cameras.dtsi`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/dts/sm8150-google-coral-cameras.dtsi).
  - Base DTS & S6E3HC2 panel:
    [`0001-coral-base-dts-and-s6e3hc2-panel.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/0001-coral-base-dts-and-s6e3hc2-panel.patch),
    [`0002-coral-wifi-bt-firmware-dts.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/0002-coral-wifi-bt-firmware-dts.patch),
    [`coral-dt1.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-dt1.patch),
    [`coral-daily-dt.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-daily-dt.patch),
    [`coral-safety-dt.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-safety-dt.patch).
  - Early-boot PON Fastboot recovery latch:
    [`qcom-pon-recovery.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/qcom-pon-recovery.patch).
  - DSI & display:
    [`coral-dsi-clock.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-dsi-clock.patch),
    [`coral-dsi-transfer-clocks.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-dsi-transfer-clocks.patch),
    [`coral-panel-brightness.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-panel-brightness.patch),
    [`coral-panel-daily.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-panel-daily.patch),
    [`coral-panel-power-mode-daily.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-panel-power-mode-daily.patch).
  - Touchscreen read-only guard & wake:
    [`coral-fts-readonly.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-fts-readonly.patch),
    [`coral-touch-wake.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-touch-wake.patch).
  - Charger, fuel gauge & haptics:
    [`coral-charge.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-charge.patch),
    [`coral-fg-temp.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-fg-temp.patch),
    [`coral-gauge1730x.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-gauge1730x.patch),
    [`coral-cs40l2x-port.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-cs40l2x-port.patch).
  - SLPI, audio & cameras:
    [`coral-slpi.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-slpi.patch),
    [`coral-audio.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/coral-audio.patch),
    [`kernel/audio/sm8150-coral.h`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/audio/sm8150-coral.h),
    [`kernel/patches/camera/001..033`](https://github.com/HemangKumawat/omarchy-mobile-coral/tree/v0.2.3/kernel/patches/camera),
    [`kernel/patches/face/leds-lm3601x-coral-off.h`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/face/leds-lm3601x-coral-off.h).
- **Userspace patches, initramfs & self-contained build tools (`v0.2.3`):**
  - [`userspace/hexagonrpc/hexagonrpc-ram-registry.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/userspace/hexagonrpc/hexagonrpc-ram-registry.patch) (against [`linux-msm/hexagonrpc`](https://github.com/linux-msm/hexagonrpc) `da7a3742ab8d`),
  - [`userspace/tqftpserv/0001-translate-serve-readonly-vendor-mbn-Pixel-MCFG-from-.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/userspace/tqftpserv/0001-translate-serve-readonly-vendor-mbn-Pixel-MCFG-from-.patch) (against [`linux-msm/tqftpserv`](https://github.com/linux-msm/tqftpserv) `128cd6e0a397`),
  - [`initramfs/init`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/init) and [`initramfs/omarchy-userspace.sh`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/omarchy-userspace.sh),
  - [`tools/build-kernel.sh`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/tools/build-kernel.sh), [`tools/pack-matched-dtb.py`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/tools/pack-matched-dtb.py), [`tools/pack-bootimg.py`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/tools/pack-bootimg.py), [`tools/build-rootfs.py`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/tools/build-rootfs.py), and [`tools/battery-status.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/tools/battery-status.patch).

## 2. Slots, development handset state (do not copy), and guarded install path

- **Bootloader version [V]:** slot A runs bootloader **`c2f2-0.5-8906123`**
  (Android `getprop` on 12 October, running from slot A; Google's final Android 13
  build `TP1A.221005.002.B2`, `coral-tp1a.221005.002.b2`). Slot B's bootloader
  version was not recorded.

- **Development handset state — historical record, do not copy [V]:**
  - Stock Android ran from slot A (`ro.boot.slot_suffix=_a` on 12 October). The
    bring-up replaced `boot_a` and `dtbo_a` with the mainline `boot` and the
    matched 12-entry no-op `dtbo`, flashed `vbmeta_a` with `--disable-verity
    --disable-verification` early on 13 October, and formatted `userdata`
    (`sda15`) as unencrypted `ext4` (`LABEL=omarchy-root`).
  - **Do not copy this handset state.** Under `omarchy-mobile` rules
    ([`CONTRIBUTING.md` §3.1](../../CONTRIBUTING.md#31-stock-android-stays-on-slot-a)),
    `vbmeta` and slot A must never be modified. Because `userdata` on this
    development handset was formatted `ext4` and our kernel occupies `boot_a`,
    stock Android's untouched `boot_b`/`dtbo_b` on slot B cannot complete
    userspace boot without reformatting `userdata`. **This unit has no working
    stock fallback slot. Recovery means reaching Fastboot (Volume Down + Power,
    or by itself after a panic or watchdog bite through the `qcom-pon` latch)
    and flashing a Google factory image, which wipes the Arch root.**
  - Slot history on this unit:
    - 2026-10-13 01:55, right after `fastboot flash boot_a`, slot A only:
      `current-slot: a`, `slot-successful:a: no`, `slot-unbootable:a: no`,
      `slot-retry-count:a: 3`. `boot_a` then held a legacy-LZ4 (`02 21 4c 18`)
      test image from the 12–13 October trials.
    - Slot A was still current at 01:21 CEST on 18 October. A `fastboot reboot`
      then did not come back, and the phone was brought back to Fastboot with
      Volume Down + Power. At 12:32 CEST: `current-slot: b`,
      `slot-successful:a: no`, `slot-unbootable:a: yes`,
      `slot-retry-count:a: 0`, `slot-successful:b: yes`,
      `slot-unbootable:b: no`, `slot-retry-count:b: 0`. [I] Each boot of the
      legacy-LZ4 image used one of slot A's retries, until ABL marked slot A
      unbootable and selected slot B. The logs do not show whether stock
      Android, and its modem, started on slot B.
    - With the owner's approval, slot A was made active again with
      `fastboot --set-active=a` at 14:10 and 14:17 CEST. The bring-up then
      flashed `boot_a` and `dtbo_a` again.

- **How GPT attribute bit 54 on `boot_a` was set, 18–20 October (historical, do not repeat) [V]:**
  - On the Pixel 4 / 4 XL, slot flags live in the GPT entry attributes on UFS
    LUN 0 (`/dev/sda`; `boot_a` is partition 6, `boot_b` partition 7). Bits
    48–49 hold the priority, bit 50 active, bits 51–53 the retry count, bit 54
    successful and bit 55 unbootable. `fastboot flash boot_<slot>` clears bit 54
    and sets the retry count to 3.
  - A host-side script (`pixel4xl_slot_success.py`) set bit 54 on `/dev/sda6`
    over SSH (USB ECM) after each RAM-proven install of `boot_a`. The agent
    sessions doing the bring-up started it by hand from the build host, with the
    owner's authorization. It never ran from a service, a timer or a boot
    script. Each run:
    1. checked that `blockdev --getro` reads `1` on `/dev/sda` and `/dev/sda15`
       (`userdata`), and saved `sfdisk --json /dev/sda`;
    2. saved the GPT sectors with
       `sfdisk --backup-pt-sectors --backup-file /run/coral-slot-a-backup /dev/sda`
       and copied both to the build host before any write;
    3. under `trap 'blockdev --setro /dev/sda' EXIT HUP INT TERM`, ran
       ```sh
       blockdev --setrw /dev/sda
       test "$(blockdev --getro /dev/sda15)" = 1
       sfdisk --no-reread --no-tell-kernel --lock=yes \
         --part-attrs /dev/sda 6 "GUID:48,49,50,52,54"
       sync; blockdev --setro /dev/sda
       ```
       and checked that both nodes read `1` again;
    4. checked that the new `sfdisk --json` differs from the old one only in
       partition 6's `attrs`, then ran `sfdisk --verify /dev/sda`.
  - It ran 18 times between 18 October 14:20 and 20 October 01:36 CEST, after
    the `boot_a` installs of kernels `#6`, `#7`, `#8`, `#24`, `#25`, `#27` and
    `#30`. In 17 runs `boot_a` went from `GUID:48,49,50,52` (retry count 2) to
    `GUID:48,49,50,52,54`. One run found bit 54 already set. `boot_b` read
    `GUID:49,54` (successful, retry count 0) throughout.
  - `sfdisk` saved four sectors: LBA 0, 1, 2 and the last LBA (15593471). [I]
    `sfdisk` also saves the backup entry array and wrote no fifth file, so on
    this unit both GPT headers point at the one 15-entry array at LBA 2.
  - After a write, Fastboot read `current-slot: a`, `slot-successful:a: yes` and
    `slot-unbootable:a: no`. The retry count and slot B were not read in that
    state.
  - **This is not the current state.** `boot_a` was flashed twice more on 22
    October and bit 54 was not set afterwards. So slot A is not marked
    successful, and each normal boot since then has used one of its retries. The
    phone is away and these values have not been read since. The next power-on
    may fall back to slot B. If stock Android offers a **Factory data reset**,
    decline it and enter Fastboot (Volume Down + Power). The next session reads
    the slot variables in Fastboot before any normal boot.
  - **Policy note (`CONTRIBUTING.md` §3.1):** Writing GPT sectors on `/dev/sda`
    from Linux is **not** permitted until `coral` has its own explicit entry in
    [`CONTRIBUTING.md` §3.1](../../CONTRIBUTING.md#31-stock-android-stays-on-slot-a).
    That entry names the device (`coral`), the UFS LUN (`/dev/sda` on this
    unit, found by `PARTLABEL=boot_a`), the GPT sectors the write touches (on
    this unit LBA 1, LBA 2 and the last LBA), the attribute bit (`bit 54`), the
    header and entry-array CRCs it rewrites, the before/after slot flags, the
    GPT rollback procedure, and the recovery path. `coral` cannot inherit
    `flame`'s pending entry ([#58](https://github.com/derekross/omarchy-mobile/pull/58)).
    That entry also needs stock restored on slot A, or the owner's written
    acceptance of buttons-only recovery.

- **Guarded install and slot B recipe (untested on this handset; pending `CONTRIBUTING.md` §3.1 entry):**
  - Any permanent installation on a second `coral` phone must go through the
    guarded installer (`tools/install-phone`, which pins the device serial,
    requires typing the codename, checks an allowlist, and runs a `--dry-run`
    first) once `coral`'s `CONTRIBUTING.md` §3.1 entry and `android-v2` support
    land, keeping stock Android untouched on **slot A** (`boot_a`, `dtbo_a`, and
    stock `vbmeta` untouched) and flashing only **slot B** (`fastboot
    --set-active=b`, `fastboot flash boot_b boot.img`, `fastboot flash dtbo_b
    dtbo.img`) and `userdata`.
  - **Untested on this handset:**
    1. *Slot B installation:* Because this bring-up ran on `boot_a`/`dtbo_a`,
       the slot B recipe (`--set-active=b`, `boot_b`, `dtbo_b`) has **not** been
       tested on this `coral` unit.
    2. *Stock `vbmeta` verification with unsigned `boot.img`:* Our `boot.img`
       carries an unsigned 64 MiB AVB hash footer (`avbtool add_hash_footer
       --algorithm NONE`). Early in this bring-up (13 October) we flashed
       `vbmeta_a` with `--disable-verity --disable-verification`. So whether
       `c2f2-0.5-8906123` ABL accepts an unsigned `--algorithm NONE` `boot_b`
       image while stock `vbmeta_b` verification is still on was never tested
       on `coral`.
    3. *3-unmarked-boots ABL fallback and stock `userdata` prompt:* Flashing
       `boot_b` clears `slot-successful:b` (`no`) and sets `slot-retry-count:b`
       to `3`. Without a `CONTRIBUTING.md` §3.1 boot-success step, `c2f2` ABL
       allows 3 unmarked boots on slot B before marking `slot-unbootable:b: yes`
       and falling back to stock Android on slot A. If `userdata` holds an Arch
       `ext4` filesystem, stock Android on slot A cannot mount `userdata` and
       displays a recovery screen prompting for a **Factory data reset**—**decline
       it** and reboot to Fastboot so the Arch root is not wiped. If stock
       Android ever boots on slot A, take a fresh modem/persist backup afterwards
       ([`CONTRIBUTING.md` §3.3](../../CONTRIBUTING.md#33-back-up-and-checksum-before-anything-risky))
       because stock's modem stack writes `modemst1`, `modemst2`, and `persist`.

## 3. Why stock SM8150 ABL rejects unmodified mainline boot images (and the fix)

On the Pixel 4 / 4 XL bootloader (`c2f2-0.5-8906123`, `msmnile` / `SM8150`),
flashing or `fastboot boot`-ing a standard mainline `Image.gz` or legacy-LZ4
`boot.img` fails in `ABL` before the kernel reaches `earlycon`. Three distinct
bootloader invariants must be satisfied for direct `ABL` boot without a U-Boot
intermediate stage:

1. **ARM64 `Image` `text_offset` must be `0x80000`, not `0x0` [V]:**
   - Stock Android 13 (`4.14.276`) was built before Linux 5.8 changed the
     ARM64 `Image` header `text_offset` from `0x80000` to `0x0`.
   - With `text_offset = 0x0`, `fastboot boot` of a mainline image failed in
     ABL with `Error verifying the received boot.img: Invalid Parameter`.
   - We set the 64-bit little-endian `text_offset` field (byte offset `8` of
     `arch/arm64/boot/Image`) to `0x80000` in
     [`tools/pack-bootimg.py`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/tools/pack-bootimg.py)
     (`struct.pack_into('<Q', raw, 8, 0x80000)`), and ABL accepts the image. In
     the kernel source this is the `.quad 0` image-load-offset field in
     `arch/arm64/kernel/head.S`.

2. **Modern LZ4 frame magic (`04 22 4d 18`), not legacy LZ4 (`02 21 4c 18`) or gzip [V]:**
   - Stock `boot.img` on `coral` packs its kernel payload as a **modern LZ4 frame**
     (`lz4 -9 -q Image.offset80000 Image.offset80000.lz4`, magic bytes
     `04 22 4d 18`), whereas `lz4 -l` emits legacy framing (`02 21 4c 18`) used
     by later Tensor bootloaders.
   - `c2f2` ABL's decompressor expects the `04 22 4d 18` frame magic and rejects
     legacy `02 21 4c 18` payloads.

3. **Board-matched appended DTB (`qcom,msm-id` + `qcom,board-id`) and matched 12-entry no-op `dtbo.img` [V]:**
   - `c2f2` ABL selects the base DTB from the `boot.img` DTB payload by matching
     `qcom,msm-id` (`<0x153 0x20000>` for SM8150 v2 and `<0x153 0x10000>` for
     SM8150 v1) and `qcom,board-id`.
   - Each DTB is compiled with `dtc -@` so `/__symbols__` is present for ABL's
     `libufdt` overlay pass. In [`tools/pack-matched-dtb.py`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/tools/pack-matched-dtb.py)
     (and `tools/build-kernel.sh`), 12 copies of
     `sm8150-google-coral.dtb` are stamped with the 12 factory
     `(qcom,msm-id, qcom,board-id)` pairs from stock `dtbo.img`, in the same
     order (for example entry 6 `<0x153 0x10000>`/`<0x50005 0x0>` for SM8150 v1,
     and entry 11 `<0x153 0x20000>`/`<0x61e05 0x0>`), and paired with a 12-entry no-op `dtbo.img` (`fragment@0` targeting
     `target-path = "/"` with an empty `__overlay__ {}`) so ABL's `libufdt`
     merge succeeds cleanly without mutating any mainline DT node.

## 4. Boot image parameters (`mkbootimg` header v2)

| Parameter | Value | Source |
| --- | --- | --- |
| Header version | `2` | [V] stock `boot.img` header |
| Page size | `4096` | [V] stock `boot.img` header |
| Base / kernel / ramdisk / second / tags / dtb offsets | `0x00000000` / `0x00008000` / `0x01000000` / `0x00000000` / `0x00000100` / `0x01f00000` | [V] `unpack_bootimg` on stock `TP1A.221005.002.B2` |
| OS version / patch level | `13.0.0` / `2022-10` | [V] stock `boot.img` header |
| Kernel payload | `Image.offset80000.lz4` (`04 22 4d 18` frame, `text_offset=0x80000`) | [V] [`tools/pack-bootimg.py`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/tools/pack-bootimg.py) |
| DTB payload | 12-entry board-matched `sm8150-google-coral.dtb` (`qcom,msm-id` + `qcom,board-id`, built with `dtc -@`, `sha256: 3efe241a...`) | [V] [`tools/pack-matched-dtb.py`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/tools/pack-matched-dtb.py) |
| Command line (`CONFIG_CMDLINE_FORCE=y`) | `rootwait ro rdinit=/init console=ttyAMA0,115200 console=ttyMSM0,115200n8 console=tty0 clk_ignore_unused pd_ignore_unused loglevel=7 coral.rescue panic=10 panic_on_oops=1 softlockup_panic=1 hung_task_panic=1 hung_task_timeout_secs=30` | [V] `CONFIG_CMDLINE` in [`kernel/series/coral-30/config`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/series/coral-30/config) (line 576) |

*Note on root device discovery vs UFS LUN ordering:* Rather than trusting a
hardcoded `root=/dev/sda15` on the kernel command line,
[`initramfs/omarchy-userspace.sh`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/omarchy-userspace.sh)
resolves the root partition dynamically via **`findfs LABEL=omarchy-root`** (with
`PARTLABEL=userdata` / `UUID=` recommended over `/dev/sda15`). On SM8150 UFS,
SCSI disk letters can reorder across reboots (`userdata` was observed shifting
from `/dev/sda15` to `/dev/sdb15` during display gate testing).

## 5. Storage guard, watchdog across `chroot`, `qcom-pon` latch, and security notes

1. **Read-only UFS block guard (`blockdev --setro`) [V]:**
   - In [`initramfs/omarchy-userspace.sh`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/omarchy-userspace.sh),
     PID 1 runs a two-pass `for device in /dev/sd* /dev/vd* /dev/mmcblk*; do blockdev --setro "$device"; done`
     loop before starting `systemd`: once immediately after `findfs LABEL=omarchy-root`
     (before mounting `/lower`), and a second time after mounting the read-only
     radio/vendor layers right before `exec chroot`. (It is a two-pass boot
     guard rather than a continuous background uevent watcher for PID 1's whole
     life.)
   - `userdata` (`LABEL=omarchy-root`) is mounted `ro,noload` at `/lower` under
     a RAM `overlayfs` (`upperdir=/run/overlay/upper`,
     `workdir=/run/overlay/work`).
   - *Why the installed image stays on the RAM overlay rather than persistent
     `sda15` writes:* in an experimental persistent-overlay test on 2026-10-22,
     making `/dev/sda15` writable required clearing the kernel read-only flag on
     **both `/dev/sda15` and its parent whole-disk node `/dev/sda`** (`sda=0,
     sda15=0`, while `sda1`..`sda14` and `sdb`..`sdf` remained `ro=1`), because
     Linux's `bdev_read_only()` checks both the partition `bd_read_only` flag
     and the parent `gendisk` read-only flag. Because `sda=0` would leave raw
     whole-disk `/dev/sda` LBA writes unblocked by `bdev_read_only()`, the
     installed `boot_a` image keeps all 79 `sd*` nodes (including `sda` and
     `sda15`) at `ro=1`.
   - That test also wrote to `userdata`. Through a loop device, it created a
     second ext4 filesystem (`coral-persist`, 42 GiB) at byte offset 8 GiB
     inside `sda15`, after the Omarchy root, which ends at 7 GiB. The first RAM
     boot of the test image used it as the overlay upper and wrote a test file;
     the root superblock hash was unchanged and `e2fsck -fn` was clean. The
     second RAM boot reset to Fastboot about 12 s after `fastboot boot`, cause
     unknown, and the test did not finish.
   - Modem EFS serving uses `rmtfs -r -P -s` (`-r`: EFS served from RAM,
     nothing written back; `-P`: partitions found by name; `-s`: `rmtfs`
     starts and stops the modem remoteproc). The partitions were also `ro=1`
     at the block layer. With no earlier baseline, we cannot show that they
     are unchanged.

2. **Backups taken, and the read-only modem/EFS/`persist` dump still to do:**
   - Before the first flash on 12 October we kept Google's factory image for
     `TP1A.221005.002.B2` (`coral-tp1a.221005.002.b2`), `getprop`, the
     `/dev/block/by-name` listing and the phone's vendor firmware. **We took no
     raw copy of any partition, `persist` included, and no GPT dump; the owner
     approved skipping that backup.** Stock `boot`, `dtbo` and `vbmeta` can be
     restored from the factory image. `persist`, `modemst1`, `modemst2`, `fsg`
     and `fsc` are specific to this unit and have no copy from before the
     bring-up.
   - The handset has not been reachable since 22 October 21:28 (Berlin). That
     evening the persistent-overlay test image (RAM-booted, not installed)
     reset early in its second boot. After `fastboot reboot` into `boot_a`,
     the phone did not show up on USB again. It is away from the build host
     and its power state is unknown (a flat battery is suspected, not proven).
     `boot_a` still holds the 22 October RAM-overlay image.
   - Every boot of the installed `boot_a` starts the modem: the userspace
     script runs `coral_radio`, which starts `rmtfs -s`, which starts `mpss`.
     So the dump is taken from a RAM boot (`fastboot -s <serial> boot <image>`)
     of an image that skips `coral_radio`. From the host, with the copies kept
     in private storage off the repository:
     ```sh
     set -eu
     P='ssh root@172.16.42.1'
     for want in modemst1 modemst2 fsg fsc persist modem_a modem_b; do
       u=$($P "grep -lx 'PARTNAME=$want' /sys/class/block/sd*/uevent") || u=
       [ "$(printf '%s\n' "$u" | grep -c .)" = 1 ] ||
         { echo "$want: not exactly one partition" >&2; exit 1; }
       dev=/dev/$(basename "$(dirname "$u")")
       [ "$($P blockdev --getro "$dev")" = 1 ] || { echo "$want: $dev not ro" >&2; exit 1; }
       $P "dd if=$dev bs=4M status=none" > "$want.img"
       phone=$($P sha256sum "$dev" | cut -d' ' -f1)
       [ "$phone" = "$(sha256sum "$want.img" | cut -d' ' -f1)" ] ||
         { echo "$want: copy differs from the phone" >&2; exit 1; }
       echo "$phone  $want.img" >> SHA256SUMS
     done
     ```
     It stops on zero or several matches for a name, on any node that is not
     `ro`, and on any copy whose hash differs from the phone's. This baseline
     comes *after* the 12–22 October sessions, not before the first boot.

3. **Hardware watchdog (`qcom-wdt`) across `chroot` into Arch [V]:**
   - [`initramfs/init`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/init)
     starts BusyBox `watchdog -T 20 -t 5 /dev/watchdog0` (`17c10000.watchdog`
     built-in with `CONFIG_QCOM_WDT=y` and `CONFIG_WATCHDOG_NOWAYOUT=y`, 20 s
     hardware timeout, 5 s pet interval) in the initramfs root namespace.
   - Instead of `switch_root`, [`initramfs/omarchy-userspace.sh`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/omarchy-userspace.sh)
     transitions into Arch via
     `exec chroot /newroot /usr/lib/systemd/systemd --unit=graphical.target`.
     Because `chroot` keeps the initramfs root alive, the BusyBox `watchdog`
     daemon continues running under PID 1 for the entire lifetime of the Arch
     session and pets `/dev/watchdog0` every 5 seconds.

4. **Kernel `qcom-pon` Fastboot recovery latch and early vs standalone `initramfs/init` health loop [V]:**
   - **No userspace code writes PMIC registers.** In
     [`kernel/patches/qcom-pon-recovery.patch`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/kernel/patches/qcom-pon-recovery.patch),
     `qcom_pon_probe()` in `drivers/power/reset/qcom-pon.c` checks
     `of_machine_is_compatible("google,coral")` and immediately writes `2`
     (bootloader/Fastboot) to `PON_SOFT_RB_SPARE` (`0x88f`) via the kernel's
     SPMI `regmap`, logging `"coral Fastboot recovery armed before userspace"`.
   - The driver registers a kernel reboot notifier (`coral_reboot_notify`) and
     a boolean driver sysfs attribute `coral_healthy` (initialized to `0`). Any
     kernel panic, `emergency_restart`, hardware watchdog bite, or reboot while
     `coral_healthy == 0` leaves `PON_SOFT_RB_SPARE` at `2` so `c2f2` ABL stops
     in Fastboot.
   - **Health loop, before and after 22 October:**
     - The first rescue init (18 October, the one in `v0.1.0`) returned to
       Fastboot when its 120-second lease ran out.
     - From 18 October afternoon to 21 October, the installed init (generated
       by `tools/pack-bootimg.py`) waited a 300-second lease
       (`USB_TIMEOUT=$((T_PROBE * 30))`). After that, every 10 seconds it
       required `/sys/class/udc/*/state == configured`, `172.16.42.1` on
       `usb0`, `systemd` as PID 1 and a live `sshd`. If a check failed it
       returned to Fastboot, so an unplugged phone went to Fastboot.
     - The 22 October [`initramfs/init`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/init)
       (`v0.2.1` and later) waits 120 seconds. Then, every 10 seconds, it
       checks only that PID 1 is `systemd` and that the process named in
       `/run/sshd.pid` is `sshd`, and writes `1` to
       `/sys/bus/platform/drivers/qcom-pon/*/coral_healthy`. If the checks keep
       failing for 10 seconds, it still returns to Fastboot.
     - Tested with USB data switched off at the host (cable still attached;
       whether VBUS was cut is unknown): the installed image stayed up and set
       `coral_healthy=1` after the lease, and an orderly `systemctl reboot`
       came back over Wi-Fi in about 24 seconds. A cold boot without a cable is
       not recorded yet.

5. **Development image physical-access warning (unauthenticated `ttyGS0` root shell & empty root password in RAM) [V]:**
   - [`initramfs/init`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/init)
     spawns an unauthenticated root shell (`setsid /bin/sh </dev/ttyGS0 >/dev/ttyGS0 2>&1`)
     on the USB CDC ACM serial gadget (`ttyGS0`), and
     [`initramfs/omarchy-userspace.sh`](https://github.com/HemangKumawat/omarchy-mobile-coral/blob/v0.2.3/initramfs/omarchy-userspace.sh)
     sets an empty password for `root` in the RAM overlay copy of `/etc/shadow`
     (`root::...`). While network SSH (`sshd`) is restricted to key-only
     authentication (`PasswordAuthentication no`), **anyone with physical USB
     cable access to this development image has immediate root access.** Production
     packaging must disable the unauthenticated `ttyGS0` shell and lock the root
     account.

## 6. Evidence from the phone, kernel build provenance, and owner confirmation

**Owner confirmation:** `@HemangKumawat`, as the owner of the Pixel 4 XL
development handset, explicitly authorized and approved every flash performed
during this bring-up.

**Which kernel built what ([`PROVENANCE.md`][coral-provenance]):**
- **Installed `boot_a` kernel `#30` (`Mon Oct 19 21:29:48 CEST 2026`):** built
  from a worktree whose content was `6963e3800a8e` + `coral-30` +
  `coral-fec40357` (git tree `6d4115553ae5a9aec7b9e4ae23f77b2e4c4d7c4e`; §1).
  The installed `Image` equals that build output except byte 10
  (`text_offset`) [V]. The same tree built the 12-entry DTB (sha256
  `3efe241aa349ff260ef0312e1b0a3a611943f71b0939261729c42e3842c90058`) and the
  modules.
- **Earlier bring-up kernels** (local commits, not published; each equals the
  series patch of the same number by `git patch-id`; the working trees changed
  after each build, so these sources are not byte-proven):
  - `#3` (`Sun Oct 18 00:34:15 CEST 2026`, first rescue kernel) was built from
    `5a951e9017ef` (`0001`..`0002`) plus uncommitted changes, committed later
    (19 October 02:08) as `472bb39eac2a` (`0005`).
  - `#25` (`Mon Oct 19 06:07:50 CEST 2026`) was built from an uncommitted tree
    before `65adbcf4ac89` (`0007`, committed 06:18). It was installed in
    `boot_a` on 19 October and was also the kernel for the SLPI and audio
    sessions; that work was committed later as `f1613a5f4fd4` and
    `52f2c29b0a60`.
  - `#27` (`Mon Oct 19 12:30:58 CEST 2026`, five-camera kernel) was built from
    an uncommitted tree on `52f2c29b0a60`; the camera work was committed later
    as `d3dd05299ff8` (14:59). It was installed in `boot_a` on 19 October and
    replaced by `#30`.

Why `tools/phone-smoke` was not run: the bring-up ran from 18 to 22 October,
before this PR was opened. The image uses the SM8150 `chroot` overlay layout
without Tensor `devinfo`, and the handset has not been reachable since
22 October (§5 item 2). The lines below are copied from the bring-up logs on
the build host; user and host names are redacted.

- **Kernel banners:**
  ```
  Linux coral 6.17.0-sm8150 #3 SMP PREEMPT Sun Oct 18 00:34:15 CEST 2026 aarch64 GNU/Linux
  Linux version 6.17.0-sm8150 (<user>@<host>) (aarch64-linux-gnu-gcc (GCC) 16.1.0, GNU ld (GNU Binutils) 2.47) #30 SMP PREEMPT Mon Oct 19 21:29:48 CEST 2026
  ```

- **Root filesystem and read-only lower mount (`/proc/mounts`):**
  ```
  overlay / overlay rw,relatime,lowerdir=/lower,upperdir=/run/overlay/upper,workdir=/run/overlay/work,uuid=on 0 0
  /dev/sda15 /lower ext4 ro,relatime,norecovery 0 0
  ```

- **Read-only state of the UFS block nodes:** the guard in §5 item 1 sets every
  `sd*` node to `ro`. An `lsblk` of `sda`–`sdf` and the per-node count were not
  captured as a log; they will be captured when the phone is back.

- **USB gadget (from `initramfs/init`, not a capture):** `18d1:4ee3`, product
  `coral-safe-rescue`, functions `acm.usb0` + `ecm.usb0`; `usb0` at
  `172.16.42.1/30`.

- **PON recovery latch (kernel log):**
  ```
  qcom-pon c440000.spmi:pmic@0:pon@800: coral Fastboot recovery armed before userspace
  ```
  The init logs `[coral-safe] SoC watchdog armed` when it starts the BusyBox
  watchdog.

## 7. Gates and rollback

A record of the gates this bring-up used, corrected for this unit. On this
development handset slot A carries the mainline image and `userdata` is `ext4`
(see §2), so there is no stock fallback slot: the way back from every gate is
Fastboot and a Google factory image, which wipes the Arch root. Slot B is
untested on this unit.

| Gate | Expect / pass | Stop condition | Rollback (this unit) |
| --- | --- | --- | --- |
| Stock capture and backups | The Google factory image for `coral` (`TP1A.221005.002.B2`) is downloaded and its SHA-256 compared with Google's published value, off the phone, before any flash; the read-only modem/EFS/`persist` dump of §5 item 2, with `SHA256SUMS`, is taken before the next boot that starts `mpss` | Factory image missing or unverified; any partition unreadable or not `ro` | None needed (read-only). Note: on this unit no raw partition copy was taken before the first flash, and the 12–22 October radio sessions ran before that dump |
| Direct ABL boot and USB ECM | `uname -r` reports `6.17.0-sm8150`; `ssh root@172.16.42.1` connects over `usb0`; `qcom-wdt` active | Hang, watchdog reset loop, or no USB enumeration within 60 s | Reach Fastboot with Volume Down + Power (the combination used on this unit; holding Power alone has not been tested). A kernel panic, a watchdog reset, or any reboot before `coral_healthy=1` also stops in Fastboot through the `qcom-pon` latch. Then flash the factory image. Slot B is untested |
| Read-only storage boundary | Every `/sys/class/block/sd*/ro` reads `1`; `/` is `overlay` over a read-only `/lower` (`LABEL=omarchy-root`) | Any physical partition reports `ro=0` in the default mode | Stop at once; reach Fastboot and flash the factory image. Slot B is untested |
| KMS display, GPU and touch | `msm_dpu` + `S6E3HC2` at `1440x3040@60Hz`; Adreno 640 (`FD640`) renders Hyprland; `fts` touch events with the flash-write path disabled | Blank panel, FIFO underrun storm, or touch SPI fault | Reach Fastboot and flash the factory image. Slot B is untested |
