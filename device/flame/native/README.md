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

## Prepare an owner-only image copy

Keep all output outside Git. Make a local copy of the clean raw ext4 image.
Prepare `firstboot.conf` using the documented keys/validation in
`packages/omamobile-firstboot/bin/omamobile-firstboot`; it is data, never
shell-source it. Use a password **hash**, the owner's public SSH key and local
preferences. Do not put secrets on a command line or in a public log.

Using the same local `debugfs` copy-and-verify approach as `tools/install-phone`,
place the following into the **image copy**, not a phone block device:

- the built native Linux payload at `/boot/omamobile/boot.img`;
- the private first-boot configuration at `/etc/omamobile/firstboot.conf`,
  owned by root with mode 0600;
- the supplied public SSH key at `/root/.ssh/authorized_keys`, with directory
  mode 0700, file mode 0600 and root ownership, for the initial guarded login.

Read each file back with `debugfs` and compare it with its input. Require a
clean `e2fsck -fn` and `tests/rootfs-smoke` on the clean build before adding
owner data. Keep `ftm5_fw.ftb` absent before a touch test. Do not use the old
local development image as a current image: later handset changes are not
retroactively included in it. Match root modules to the supplied kernel.

The native package enables only the storage guard. Its dependencies include
Foot, `xdg-terminal-exec` and `udiskie`. SDDM/user services use the tested
software-rendering fallback. Normal user setup selects 2.5 scale and merges
the tested 0.6 Chrome scale only if Chrome is already installed. Chrome is
optional, not a dependency, and the helper never accepts its license. The
existing AI Agent entry uses upstream's chooser/default-agent path.

## Stage and write, one approved gate at a time

All variables below name local, reviewed files. Every write is high risk.
The staged role determines whether `flash` writes **userdata** or **boot_b**;
it never writes both in one call. The ordinary RAM-only profile cannot enter
these paths. The tests use fake Fastboot, never a connected phone.

```sh
# Stage the owner-prepared RAW ext4 image. No phone access here.
DEVICE=flame FLAME_NATIVE=1 FLAME_BOOT_ROLE=userdata \
  FLAME_ROOT_IMAGE=/private/owner-root.img FLAME_ROOT_SHA256=<verified-sha256> \
  KERNEL_OUT=/private/native-stage bin/omamobile images

# After separate owner approval: erases Android userdata, stays in Fastboot.
DEVICE=flame FLAME_NATIVE=1 FLAME_ERASE_USERDATA=flame \
  KERNEL_OUT=/private/native-stage bin/omamobile flash

# Only after the temporary storage boot passed: stage its EXACT loader.
DEVICE=flame FLAME_NATIVE=1 UBOOT_IMAGE=/private/output/loader/boot.img \
  UBOOT_SHA256=<verified-sha256> KERNEL_OUT=/private/loader-stage \
  bin/omamobile images
DEVICE=flame FLAME_NATIVE=1 KERNEL_OUT=/private/loader-stage bin/omamobile flash
```

The userdata phase verifies a raw ext4 label, complete filesystem size,
checksum, read-only filesystem check and Android Fastboot capacity. Sparse
input must be converted locally first. It requires unlocked flame, active
already-successful B and the explicit erasure acknowledgement. It never
reboots after writing.

The loader phase verifies the staged hash/header, product, unlocked state
and already-active successful B, erases only `boot_b`, and flashes only that
partition. It does **not** call `set_active`. A clear post-flash success bit
is an expected stop: remain in Fastboot and follow the separately authorized
[boot-success procedure](../BOOT-PLAN.md). Never repeatedly boot unsuccessful B.
`FLAME_REPAIR_BOOT_B=1` is only for an active, bootable B with attempts left;
it does not authorize the GPT transaction or bypass the installed-byte check.

| Gate | Expect / pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- |
| Offline root and loader inspection | Correct source/config, checksums, matching modules, guard package, clean ext4, retained recovery evidence | Missing input, data or protection | Discard local outputs | Low |
| Approved userdata write | Only userdata written; exact product/capacity checks; remain in Android Fastboot | Any mismatch/write error | Stay in Fastboot; correct local image or restore verified stock B and reset Android data | High |
| Approved temporary loader/native boot | Owner-approved RAM boot; correct root, `/dev/sda` absent, protected nodes RO, PID 1 watchdog, fresh SSH and clear UI | Missing control, wrong root, storage/display fault | Physical Android Fastboot | Medium |
| Optional guarded Wi-Fi start | Current firmware/NV checks, association, interface-bound HTTPS, fresh SSH, hashes unchanged | Firmware/storage fault or failed start marker | Stop; independent RAM recovery timer / physical Fastboot | Medium |
| Approved loader install | Exact reviewed loader; only boot B erased/written; stop on clear success | Identity/hash/erase/write/metadata mismatch | Stay in Fastboot; stock recovery role if separately authorized | High |
| Explicit boot-success exception | Four reviewed sectors, backup first, each read back; one B success bit plus CRCs only | Any failed precondition or readback | Stop and retain both snapshots; no blind retries | High |
| Normal/repeated/battery restarts | New boot IDs, clear UI, Wi-Fi traffic and protected hashes pass | Recovery loop, unreadable display, missing control | Physical Android Fastboot | Medium |

Stream logs to the host and verify an independent RAM recovery connection
before a risky step. Keep PID 1's watchdog active. For a step that can cut USB,
arm a RAM recovery timer and cancel it only after a fresh recovery login.
The initial rescue listener is IPv4-only; do not assume it works on a host
that has only USB IPv6. Verify/add a USB-only IPv6 RAM listener from the
trusted Arch connection, verify its public key through that connection, and
pin it separately. It must not depend on the root filesystem connection.

Use `OMAMOBILE_SSH_HOST=root@<usb-link-local>%<host-usb-interface>`,
`OMAMOBILE_SSH_KEY` and `OMAMOBILE_SSH_KNOWN_HOSTS` for a known scoped USB
address. Supplied known-host files enforce strict checking. There is no LAN
scan. USB link-local addresses can change across boots; rediscover only on
the physical USB link and keep the established persistent Arch host key.

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
