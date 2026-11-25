<!-- SPDX-License-Identifier: MIT -->
# Pixel 9 Pro XL (komodo) bring-up notes

Sanitized observations from one development phone. These notes are evidence,
not a device-support claim or authorization to repeat any operation. Raw
captures, boot images, calibration backups, identifiers, and account content
remain private and out of this repository.

## 2026-11-25: package storage rule and post-reboot smoke

Installed the candidate `omamobile-device-komodo` package with the storage
rule on the development phone, then rebooted once. The local test build used
package release `0.0.4-2` to replace the earlier development install; it is
not a published package version. The installed rule makes `/dev/sda`
inaccessible and tells desktop disk tools to ignore it. After reboot, the rule
was present and `/dev/sda` did not exist.

`tools/phone-smoke` ran on kernel
`7.3.0-rc6-omamobile-push1-g061ebcf504d5`, slot B. Its required boot, storage,
root, kernel-health, USB-gadget, and session checks passed. It reported no
Oops, BUG, or WARN. Five new dmesg errors remain: four Samsung pinctrl IRQ
messages and one initramfs decode failure. No systemd units failed on this
boot; `systemd-firstboot.service` is recorded as having failed on the first
boot. The DSI display, Omarchy session, lock, and buttons were present, but no
touch input device or GPU render node appeared. The guarded GPU service skipped
its probe because the expected GPU device-tree path was absent. Wi-Fi,
Bluetooth, battery, sound, sensors, and cameras were unavailable. No real
messages or account content were accessed.

## 2026-11-20: synthetic notification check

A local `notify-send` test with placeholder text appeared in the logged-in
session; the owner later confirmed it also appeared on the lock screen. Whether
a notification wakes the display, WhatsApp delivery, and vibration remain
unverified. No real messages or account content were accessed.

## 2026-11-20: USB internet and guarded GPU

The development system booted persistently from slot B into Omarchy with USB
networking and internet. Touch input, flip-only KMS, and the Mali-G715 render
node were observed. The USB network configuration is installed by
`omamobile-device-komodo`; USB forwarding was isolated from the home LAN.

The attended GPU test enabled the kernel-described GPU and G3D clock nodes.
With `/dev/watchdog0` armed, Panthor bound, created `/dev/dri/renderD128`,
identified Mali-G715, and loaded CSF firmware. The kernel logged that no Mali
regulator was found, but initialization completed. Only the 150 and 302 MHz
operating points were enabled; higher rates and thermal behavior are untested.
The package writes a persistent attempt marker before loading Panthor, blocks
modalias autoload, and leaves the GPU disabled on the next boot if probing does
not complete. Idle CPU samples improved after acceleration, but this was not a
controlled benchmark.

Internal Wi-Fi is not working. WhatsApp Web returned HTTP 200 over USB internet;
its pairing page was shown for owner testing, no account was linked, and no
message content was viewed. Cellular, Bluetooth, full panel control, suspend,
charging, sensors, audio, and other peripherals remain unqualified.

## 2026-11-20: Wi-Fi host and driver probe

The experimental Wi-Fi host overlay enumerated PCI `14e4:4438` with a Gen3 x1
link. A private `bcmdhd` module failed its first coherent DMA ring allocation;
its cleanup path then oopsed. Firmware, board calibration, driver sources, and
that private cleanup guard are not included here. A proposed shared DMA pool
was not verified with the driver. The unqualified Wi-Fi overlay is not selected
by the device descriptor; do not enable it without a reviewed DMA and driver
safety path.

## Recovery, backups, and slot state

The historical first-light work used the supported project paths for slot-B
boot images and `userdata`. A stock fallback was followed by Linux being unable
to mount `userdata`; a subsequent supported reinstall restored the development
root. These observations are not a recovery procedure and do not authorize a
new write. Preserve the stock slot and use only the documented, currently
approved write paths.

The retained records include an NV backup from 2026-11-02 and a read-only
partition inventory from 2026-11-09. Stock Android booted after that backup, so
it is not a verified current baseline. No fresh post-stock-boot NV backup or
checksum comparison is recorded here. Before radio, PMIC, AoC, or Trusty work,
rediscover the exact `PARTNAME`s and read-only state, verify the off-repository
backup checksums, and take a fresh read-only backup as required by `AGENTS.md`.
Backup contents and hashes stay private.

The last retained fastboot inventory, dated 2026-11-18, reported two remaining
tries for each slot. That is historical only; the current retry count has not
been read. Read it with `fastboot getvar slot-retry-count:b` during the next
owner-approved fastboot session. Do not mark slot B successful or change slot
metadata by hand.
