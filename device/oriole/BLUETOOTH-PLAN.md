<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 (Oriole): opt-in Bluetooth qualification

Status (2026-11-17): offline candidate only. `overlays/bluetooth-test.dtso`
turns on the existing APM USI1, UART16 and BCM4389 child; it does not add
hardware descriptions, change clocks, or become part of default images.
Kernel source: `derekross/linux-omarchy-mobile`, branch `omamobile`,
`26867fc4e826a03d1095341af50b6165d4ea5164`.

## Why this contribution

[Kernel #159](https://github.com/derekross/linux-omarchy-mobile/pull/159)
merged the disabled Oriole child. Its parent controllers and corrected APM
clock description already exist. This overlay fills the missing explicit
opt-in step using node paths, so it does not need exported DT symbols.
It preserves the UART's real CMU_APM baud clock and all upstream GPIOs,
interrupts, pin states and 3 Mbaud limit.

Current upstream Raven enables Bluetooth and has address provisioning and
BlueZ startup in its device package. Its
[Bluetooth plan](https://github.com/derekross/omarchy-mobile/blob/c4623572be1c141d602cf99a83ae0bf9e3eea09c/device/raven/BLUETOOTH-PLAN.md)
records intermittent startup failures even after reset timing changes;
Raven qualification cannot qualify Oriole. No Raven retry policy is copied.
Current Oriole packaging does not supply that Bluetooth lifecycle.

The retained private Oriole Bluetooth plan records working UART/HCI/BLE on
`4bd35d34abb9-dirty` with a fixed-factor clock workaround. That is historical
evidence, not a pass for the current CMU_APM path. Its old enable overlays
must not be combined with this one. The retained Wi-Fi plan involves private
PCIe drivers and startup/recovery machinery; porting it is a larger change
with additional dependencies. This candidate deliberately needs none of it.

## Offline check

Build the exact upstream Oriole DTB with `W=1` in a dedicated kernel output
(directory paths below are examples, never a shared build output):

```sh
make -C "$KERNEL_DIR" O="$KERNEL_OUT" ARCH=arm64 LLVM=1 defconfig
make -C "$KERNEL_DIR" O="$KERNEL_OUT" ARCH=arm64 LLVM=1 W=1 \
  exynos/google/gs101-oriole.dtb
dtc -@ -I dts -O dtb -o "$KERNEL_OUT/bluetooth-test.dtbo" \
  device/oriole/overlays/bluetooth-test.dtso
fdtoverlay -i "$KERNEL_OUT/arch/arm64/boot/dts/exynos/google/gs101-oriole.dtb" \
  -o "$KERNEL_OUT/oriole-bt-test.dtb" "$KERNEL_OUT/bluetooth-test.dtbo"
```

Pass: compare the decoded input and output trees. Only the three disabled
status properties named in the overlay should become okay. Validate the merged DTB with
the kernel's USI, Samsung UART and Broadcom Bluetooth schemas before a trial.
Stop on any check/build/schema error; rollback is discard the offline output.

Offline result (2026-11-17): pass. All 18 transitive DTS/header inputs
were fetched at the pinned kernel commit (including resolving the input-code
header symlink). A dedicated copy of the retained #159 kernel build harness,
with those current inputs, built the Oriole DTB with arm64 Clang `W=1`
without warnings. This is a targeted DT build, not a full current kernel build.
The overlay check passes with both retained and freshly built dtc tools;
real current Raven and already-enabled Oriole inputs are rejected.
`dt-validate` (dtschema 2026.9) passes for USI, Samsung UART and Broadcom
Bluetooth on the merged DTB, using current versions of those schemas and
retained supporting schemas. Strict checkpatch (`--no-signoff`) reports
zero errors/warnings/checks for the overlay. Hardware remains untested.

## Exact-device hardware gate (not run)

1. **Read-only, low risk:** require a physical Pixel 6, root compatible
   `google,gs101-oriole`, exact kernel/modules/config and DTB identities,
   current protected-partition backup checksums, healthy USB/storage and a
   known-good recovery image. Verify `CONFIG_BT`, `BT_BCM`, `BT_HCIUART`,
   `BT_HCIUART_BCM`, `BT_HCIUART_SERDEV`, `BT_LE`, Samsung UART and USI
   support. Resolve the actual `hci_bcm` firmware request against the owner's
   privately extracted factory firmware, and prepare private bootloader
   address provisioning (power on before setting it). Stop on any missing
   dependency; no guessed firmware, public address or vendor blob is shipped.
2. **Approved fresh boot, medium risk:** use the qualified Oriole deployment and rollback procedure. Before installing the opt-in DTB, blacklist `hci_uart`
   autoload, prepare a boot hang marker and recovery path. Stream kmsg to the
   laptop and arm the existing watchdog safely before one explicit driver
   load; do not contend with an existing watchdog owner. Pass: correct
   UART/serdev binding, firmware completion, valid private address, powered
   BlueZ controller, fresh USB login and unchanged protected hashes. Stop on
   timeout, silent UART, warning, USB loss or checksum change. Preserve logs;
   no unbind/rebind, repeated power cycle or module unload to retry.
3. **Attended use, medium risk:** on that same exact Pixel 6, prove peer
   discovery, fresh pairing and acknowledged bidirectional payloads or BLE
   keyboard input; remove only the test bond afterwards. If Wi-Fi was already
   independently qualified, repeat real Wi-Fi HTTPS during BT traffic; never
   enable Wi-Fi as a second new subsystem for this gate. Repeat after one guarded ordinary reboot. Stop on first failure, retaining failures even
   if a later boot succeeds. Rollback: restore the known-good slot-B image through the project tool
   and fresh boot, leaving stock slot A and storage guards intact.

Audio, suspend and automatic startup remain separate gates. No hardware
result is claimed for this overlay or current clock path.
