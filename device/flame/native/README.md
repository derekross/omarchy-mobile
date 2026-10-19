<!-- SPDX-License-Identifier: MIT -->
# flame: experimental permanent installation

Status: 2026-10-19, measured on Pixel 4 with Linux `7.0.0-sm8150`.
Native Arch on ext4 `userdata` and a U-Boot loader in `boot_b` passed the
[recorded restart, display and app checks](RESULTS.md). This is an opt-in
contributor workflow, **not a release installer**. The published loader recipe
has additional host-only changes and needs a fresh approved RAM test.

The ordinary `device/flame/device.conf` remains RAM-only. Only
`DEVICE=flame FLAME_NATIVE=1` selects [native/device.conf](device.conf).
The generic `tools/install-phone` still refuses flame. Native `push` and the
Tensor initramfs/image layout are refused; native boot writes go through
`bin/omamobile flash`. Nothing here automatically repairs GPT metadata,
selects a slot, restores calibration, or installs a separate Codex desktop app.

## Prerequisites and source

Read [BOOT-PLAN](../BOOT-PLAN.md) and the repository safety rules first.
Obtain the owner's approval for every hardware reboot or write. Keep a current
verified private backup set, matching factory image, physical Fastboot access,
and the exact stock boot/DTBO backups. The tested handset's stock A is
**unbootable**; it is not an available fallback. Restoring Android after this
installation also needs a factory data reset. Never relock the bootloader.

| Component | Source / role |
| --- | --- |
| U-Boot base | Andrew Gigena's GPL flame tree, `0c42ac323aea8368b0624e405ded403351022df2`, [source](https://gitlab.com/andrewgigena/u-boot/-/commit/0c42ac323aea8368b0624e405ded403351022df2) |
| Display fix and standalone configuration | [GPL source](https://github.com/wirelessjoe/u-boot/tree/e210c6956ce90e48b667eb15a8c6f20bc292b52e), pinned by `tools/build-flame-loader`; includes the missing-rotation/stride correction, overflow fixture and compiled-environment checks |
| Linux inputs | The matching kernel, DTB, watchdog and modules listed in [BRINGUP-M1](../BRINGUP-M1.md); documentary firewall additions remain in [kernel-extra.config](../kernel-extra.config) |
| Native root | `omamobile-device-flame` plus the normal Omarchy Mobile packages; the owner supplies local first-boot configuration and SSH keys |
| Wi-Fi | Separate firmware/NV gates below; no Google firmware or device data is distributed |

The automatic U-Boot path waits two seconds, scans UFS, resolves GPT
`userdata`, reads `/boot/omamobile/boot.img` through ext4 and runs `bootm`.
Healthy boots do not wait for USB. Failure enters download-only Fastboot.
The new configuration has a volatile environment and removes EFI/FAT writes,
DFU, USB mass-storage and fastboot OEM run facilities. It is not a hardware
storage guard: never issue interactive U-Boot storage-write commands.

## Build on the host

The loader tool needs a Linux environment with an aarch64 GCC cross compiler,
make, dtc, flex, bison, OpenSSL/UUID development headers and Python 3. Supply
AOSP `mkbootimg.py` together with its `gki/` helpers. It does not use the phone.

```sh
git clone https://github.com/wirelessjoe/u-boot /path/to/u-boot
cd /path/to/u-boot
git checkout e210c6956ce90e48b667eb15a8c6f20bc292b52e
cd /path/to/omarchy-mobile
tools/build-flame-loader --uboot /path/to/u-boot \
  --mkbootimg /path/to/mkbootimg.py --out /private/output/loader
```

Build the native Linux payload with `tools/build-flame-system`, using the
same input flags as `tools/build-flame-probe`. Use a fresh output directory.
It verifies Pixel 4/SM8150, ARM64 Image magic and watchdog vermagic. The
native init has a separate initial allowlist of `boot_b userdata`; it never
clears read-only flags or recreates `/dev/sda`. All other UFS nodes remain
protected through the handoff to Arch.

The default native payload disables all remote processors. `--wifi` enables
only `/soc@0/remoteproc@4080000` after checking that its compatible is
`qcom,sm8150-mpss-pas`. It does not supply firmware, start the radio or enable
its service. Keep the other DSPs disabled. The final Android command line
uses `console=tty0` only: a USB console or journal forwarding to ttyGS0 can
stall a restart after unplugging. ACM is available for explicit attached-only
debugging; it is not a standalone boot console.

`DEVICE=flame FLAME_NATIVE=1 tools/build-rootfs --keep-raw` selects the flame
package and ext4 features compatible with the storage loader. It still needs
the normal signed local package repository and the complete matching modules.
The image has no owner, credentials, SSH host keys or Google firmware. A full
new signed root build is not part of the recorded host validation.

## Root preparation and the current write boundary

The native builder selects `omamobile-device-flame`, with first-boot 0.1.3
and shell 0.2.24 hooks. Keep all images, owner configuration, public keys,
firmware and current backup manifests outside Git. Root image preparation
is host-only; this split does not add a userdata flash command. The proposed
userdata write and GPT transaction await the maintainer's policy decision
in [the original review](https://github.com/derekross/omarchy-mobile/pull/17#issuecomment-6428241495).
The generic installer remains unavailable for flame.

The loader plumbing accepts only the checked header-v0 loader or a verified
64 MiB stock header-v2 boot B backup. Every Fastboot query/write is pinned to
one selected handset, using current main's `FASTBOOT_SERIAL` selection. A
loader install requires already-active successful B, erases/writes only boot B,
and stops in Fastboot if the success flag is cleared. It never selects a slot
or starts a GPT repair. Do not repeatedly boot an unsuccessful B.

The native package enables only the storage guard. Its dependencies include
Foot, `xdg-terminal-exec` and `udiskie`. SDDM/user services use the tested
software-rendering fallback. Normal user setup selects 2.5 scale and merges
the tested 0.6 Chrome scale only if Chrome is installed. The helper preserves
other flags and backs up prior files. The upstream AI Agent chooser is used.

## Rescue SSH and its authority

The initramfs listener on `172.16.42.1:22` and the RAM rescue listener on
`172.16.42.1:2222` use the **same builder-supplied `key.pub`**, installed as
`/root/.ssh/authorized_keys` in each filesystem. The second listener survives
`switch_root` in a separate RAM root, with the real root bind-mounted
**read-write at `/realroot`**. Its key grants recovery write access to that
root; a separate process is not a separate credential or storage boundary.
The storage guard still protects other partitions.

The initial rescue listener is IPv4-only. A host using USB IPv6 needs an
explicit USB-only IPv6 RAM listener, a key verified through the trusted Arch
connection and a fresh independently pinned login. Do not assume the root
filesystem's SSH connection proves RAM recovery works.

The `phone-ssh` options support a known scoped USB endpoint, an explicit key
and a strict known-hosts file. Shared connections retain upstream's
`OMAMOBILE_SSH_SHARE=1`, `--fresh` and `--stop`; use `--fresh` to prove that
USB or firewall changes left a new connection possible. There is no LAN scan.

## Gates before another hardware test

These are separate owner-approved operations; the new split is host-tested.
Stock A is unbootable on the measured handset: recovery is **the buttons
alone** to reach Android Fastboot, with the verified stock B backups ready.

| Gate | Expect / pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- |
| Offline source/image check | Pinned sources, matching modules, checked image header/hash, clean ext4 and private backup set | Missing provenance or any mismatch | Discard local output | Low |
| Approved temporary boot of reviewed loader/native payload | Correct root, absent whole-disk node, protected partitions RO, PID 1 watchdog, clear UI and fresh root/rescue logins | Wrong root, storage/display fault or lost control | Physical Android Fastboot | Medium |
| Optional guarded Wi-Fi start | Current firmware/NV checks, association, bound HTTPS, hashes unchanged | Firmware/storage error or failed-start marker | Independent RAM recovery timer / physical Fastboot | Medium |
| Approved boot B loader write | One handset selected, exact reviewed bytes, active B; stop on clear success flag | Any identity/write/metadata error | Stay in Fastboot; separately approved stock B restoration | High |
| GPT success / userdata write | **Blocked pending a named maintainer policy exception** | No policy decision | Keep current installation and private backups | High |
| Approved connected/battery restart | New boot, clear UI, fresh SSH, Wi-Fi and protected hashes pass | Loop, unreadable display or missing control | Physical Android Fastboot | Medium |

Arm a host log stream, PID 1 watchdog and an independent RAM recovery timer
before a risky driver/USB test. Cancel the timer only after a **fresh** RAM
recovery login. Do not use U-Boot or SCSI writes to work around the pending
metadata policy. [Direct ABL boot](../ABL-PLAN.md) is a candidate from the
Pixel 4 XL report, with no flame hardware result yet.

## Wi-Fi provisioning remains a separate gate

Ship `flame-wifi.service` disabled. The owner supplies matching `rmtfs` and
`tqftpserv`, modem/WLAN firmware, API metadata, and raw factory
`ath10k/WCN3990/hw1.0/board.bin`. Keep generic `board-2.bin` (including
compressed and update-directory copies) outside every firmware search path:
API 2 takes precedence over the tested raw factory board file.

Create private manifests at `/etc/omamobile/flame-calibration.sha256` and
`flame-firmware.sha256`. Calibration paths use unique GPT-name links under
`/run/omamobile/flame-partitions`; LUN letters changed in a measured reboot.
Keep current protected NV copies, mode 0600, in root-only
`/var/lib/omamobile/flame/nv` as `modem_fs1`, `modem_fs2`, `modem_fsg`,
`modem_fsc`. Refresh the backup and copies after any stock Android boot.
The helper verifies current real-partition hashes before using RAM shadows;
rmtfs never gets the protected NV block nodes. Preserve its failed-start
marker until logs have been reviewed. Do not retry a failed radio loop or
load the untested UART pin overlay. Bluetooth stays blacklisted.

## Recovery and limits

To restore only the verified 64 MiB stock boot B backup, stage it with
`FLAME_BOOT_ROLE=stock-recovery`, `UBOOT_IMAGE`, `UBOOT_SHA256`, `DEVICE=flame`
and `FLAME_NATIVE=1`. The flash tool writes only boot B and stays in Android
Fastboot. Restoring Android requires the matching factory data-reset path;
this loses native userdata. Never restore calibration as a routine rollback.
This stock restore role has mock coverage; the full post-native Android
restore/factory-reset cycle has not been performed on the handset.

Hardware acceleration, Bluetooth pairing, modem calls, audio/camera and
release-quality power management are not established by these tests. Large
USB output still needs small verified transfers. The original spontaneous
runtime-reset cause remains unresolved. Read [RESULTS](RESULTS.md) before
interpreting the successful restart tests as general reliability evidence.
