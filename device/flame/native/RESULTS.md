<!-- SPDX-License-Identifier: MIT -->
# Pixel 4 native-install validation — 2026-10-19

The handset ran Linux `7.0.0-sm8150`, native Arch on ext4 `userdata`,
Hyprland/Quickshell with software rendering, and a storage-loading U-Boot in
`boot_b`. Results below describe that measured development installation,
not a release claim for every Pixel 4 or the new recipe's exact output.
The review split was refreshed against main on 2026-10-26; no new hardware
result is implied by that rebase.
Private logs, backup manifests, device identifiers, credentials, NV data and
firmware are retained off-repository. No such input or binary is published.

## Measured handset procedure

| Check | Observed result | Scope / limit |
| --- | --- | --- |
| Native root handoff | Arch, PID 1 watchdog, storage guard and mobile home/PIN UI reached from ext4 userdata | The root was assembled locally, including owner inputs and matching external firewall modules |
| Installed loader bytes | Full reviewed image prefix matched, including zero-valued header fields | Boot B was erased before the small header-v0 image was written; payload-only comparison previously missed stale header bytes |
| Boot-success correction | Four sectors, backup table/header first, then primary table/header; each read back; only B success bit and required CRCs changed | Explicit owner-approved one-time GPT exception; no automatic boot-success service; no calibration writes |
| Normal connected starts | Initial normal installed-loader start plus three further connected restarts passed | Different boot IDs; guard/desktop/Wi-Fi services active and protected hashes matched; not an endurance run |
| Deliberate abrupt restart | After stopping the display manager and syncing data, one intentional kernel panic returned automatically to Linux | Wi-Fi association, interface-bound HTTPS 200 and protected hashes passed; this was a deliberate test, not an observed spontaneous fault |
| Unplugged restart | A one-shot trigger requested one normal restart after charger-offline detection; owner saw a clear PIN screen before reconnecting | Fresh USB login verified new boot, Wi-Fi/HTTPS and protected hashes; trigger was transient and cannot repeat after reboot |
| Display power cycles | One earlier on/off/on check and five additional cycles passed at the existing 90 Hz mode | Reported off/on state and same boot checked; independent RAM recovery login passed and timer was cancelled; final PIN image was readable |
| Paced load / idle | Two 64 MiB hash workers at approximately 50% duty for 120 s, then 180 s without synthetic load; 301 s elapsed; same boot | Highest sampled sensor 60.8°C; hash loops, services, protected data and Wi-Fi HTTPS passed; not a full-load endurance pass |
| Full-duty stress attempt | Stopped at the first 10 s temperature check, processor sensor 71.7°C | Conservative test cutoff was 70°C, below the kernel's existing CPU thermal-control trips; workers stopped, temperature recovered and no reboot occurred; cooling settings unchanged |
| Protected data | Seven current calibration/modem hashes matched; complete 12-partition backup set verified off-device | Counts/results only; no real hashes, partition contents or device identifiers are published |
| Chrome license / scrolling | Native Wayland, disabled GPU and scale factor 0.6 fit the license dialog; owner accepted it and confirmed finger scrolling on a webpage | Chrome was owner-installed; no license was accepted automatically; profile retained; Chrome is not added as a project dependency |
| Agent app | The owner signed in and a short prompt replied normally | Controlled retry passed; an earlier full reset remains unexplained |
| Final state | Both GPT CRCs valid, B success set, other metadata/reserved bytes preserved outside B attributes/required CRCs; fresh SSH, Wi-Fi/HTTPS and protected hashes passed | No failed system units or active test/recovery timers; temporary IPv6 recovery listener removed; Docker builders stopped after work |

The U-Boot driver correction is [cefacc22](https://github.com/wirelessjoe/u-boot/commit/cefacc22d1377071d70e5bc93e48ddbaf40fe65a):
missing `rot` no longer leaves a stack value in console selection, and the
probe honors and bounds framebuffer stride. The installed test image used
that driver plus the same peripheral USB DT and two-second storage path.
The later generic invalid-width guard and smaller configuration are separated
below; they were not silently substituted for the measured installed image.

The standalone Linux payload used `console=tty0` only, and the journal did
not forward to ttyGS0. Earlier journal-only changes were insufficient while
USB remained the last Linux console. The final battery restart passed after
USB was removed from the console path. A USB replug/SSH failure alone was
not counted as a spontaneous reboot: a fresh boot-ID check distinguished a
large-transfer stall from an actual reset.

## Host checks for this PR

- `tests/all`: passed, including retained shared guard/USB-product/boot-method
  tests and new native loader staging/role refusal, serial selection, first-guard
  fail-fast, GPT failure/readback/padding, PARTNAME discovery and scoped/shared-SSH fixtures.
  Container provisioning and root-image smoke cases skip when their optional
  fixtures are unavailable; a new signed complete root image was not built.
- `packages/omamobile-device-flame/test/all`: guard-only activation, disabled
  Wi-Fi unit, standalone journal and owner configuration merge/backup/repeat
  checks passed. The browser helper preserves unrelated flags and refuses an
  unknown monitor layout rather than overwriting it by guesswork.
- `packages/omamobile-shell/test/all`: passed with the documented optional
  tool-dependent skips. The refreshed hooks are shell 0.2.24 and first-boot 0.1.3;
  those package versions have host checks, with no fresh phone install.
- ShellCheck passed for added scripts. Changed legacy scripts were checked
  with their pre-existing diagnostics excluded; no new warning was retained.
- `tools/build-flame-loader`: complete `W=1` build, generated configuration
  and compiled environment inspection, Android header/payload checks and
  output checksums passed. Inherited platform DTS/missing-prototype warnings
  remain; the changed simplefb driver produced no new warning.
- The actual simplefb probe ran under host ASan/UBSan for missing/explicit
  rotation, packed/padded/16-bit rows, invalid stride/buffer size and overflow.
  The original driver is rejected by the regression fixture. Strict checkpatch
  passed with sign-off omitted (human DCO still required for upstream) and
  only the new-file MAINTAINERS advisory excluded for the new board/test files.
- `tools/build-flame-system --wifi`: rebuilt and inspected on the host with
  the supplied matching kernel/watchdog and local public key. The resulting
  image/key material stays private; nothing was booted or flashed in PR prep.

### Changes requiring a new hardware gate

The pinned U-Boot source is
[`e210c6956ce90e48b667eb15a8c6f20bc292b52e`](https://github.com/wirelessjoe/u-boot/tree/e210c6956ce90e48b667eb15a8c6f20bc292b52e).
Compared with the handset's tested image, it removes unused EFI/FAT-write,
DFU, mass-storage, environment-save and fastboot OEM facilities/menu entries
and adds an invalid-width arithmetic guard. Its healthy boot sequence and
USB role remain the measured ones. The new package explicitly supplies the watchdog/USB network policy measured
on the hand-built root, and first-boot 0.1.3 scopes recovery/DHCP firewall
rules to native flame on USB. The native init also now exits on the
first storage-guard failure and leaves USB getty startup explicit rather
than automatic. These outputs were host-built/checked only. Package assembly was host-fixture tested. The proposed userdata writer
is held out of the low-risk split pending the maintainer's policy decision. Perform the native runbook's new approved
RAM boot and recovery gates before installing any new output image.

## Reproducing the bounded load check

After owner approval, protected-data preflight, a fresh independent recovery
login and an external host kernel-log stream, stage `validation/load-idle.sh`
in RAM. PID 1 must hold the watchdog. Run it in a transient unit so an SSH
loss cannot leave workers running indefinitely:

```sh
systemd-run --wait --pipe --collect --unit=flame-native-validation \
  --property=RuntimeMaxSec=340 --property=KillMode=control-group \
  /bin/bash /run/load-idle.sh
```

Keep output private. Stop on a temperature cutoff or new error. Require the
same boot, final service/Wi-Fi/protected-data checks and an inactive unit.
Screen cycles and each restart remain separate human-approved gates; never
turn the deliberate panic test into an automatic startup hook.

## Open limits

### Intermittent runtime reset

One owner-reported full reset near agent sign-in remains unexplained. A
controlled sign-in and prompt retry passed on the same boot, with host
capture and unchanged protected hashes. No implementation change explains
that pass; sustained use and the reset investigation remain open.

The original spontaneous runtime-reset cause is **not conclusively identified**.
The bounded tests did not reproduce an unplanned reset. Hardware GPU
acceleration remains disabled, Bluetooth firmware download/pairing has not
passed, and large phone-to-host USB output can stall (64 KiB verified
retrievals worked). Calls, audio/cameras, full Android rollback/factory reset,
release power management and long-term stability are not established.
A successful temporary boot or one working app does not close those gates.
