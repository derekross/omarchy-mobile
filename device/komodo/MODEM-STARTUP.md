<!-- SPDX-License-Identifier: MIT -->
# Komodo modem startup profile

Status, 2026-11-12: source and simulator validation only. This note does not
record a successful hardware startup, SIM enumeration, LTE registration or
registration after a SIT radio off/on cycle. It does not qualify 5G/NR.

The proposed profile requires the public Komodo board binding and DTS to be
merged before the package change merges. No published kernel PR or qualified
head is substituted here for that pending dependency. The device policy that
would select this profile is also not supplied by this change.

## Explicit setting and default behavior

The configuration key is `[network] startup_profile` in
`/etc/omamobile/modem-sit.conf`. An unset key, or the exact value `default`,
keeps the existing AT radio startup and runtime control. The packaged file
does not add the key, so this proposal alone does not create a `.pacnew` on
phones whose configuration has been changed by Settings.

The proposed operation name is `sit-radio-before-sim`: radio power goes through
SIT and the initial radio-on precedes the SIM wait. The earlier explicit value
`komodo-s5400` remains a compatibility alias for the same operation. Neither is
automatically selected. Both require exactly the ordered device-tree tuple
`google,zumapro-komodo`, `google,zumapro`; no other board is currently admitted.
The allowlist is not a claim that this proposal has passed hardware testing.

The proposed order is the fixed configuration payload, SIT radio-on, physical
USIM readiness, attach configuration during a SIT radio off/on cycle, then
packet registration and data startup. Invalid explicit settings refuse before
the first setter, and an uncertain native setter is not retried through AT.

After an unconfirmed call release, an unknown profile or unavailable/wrong
board falls back to the existing best-effort AT radio-off. An uncertain SIT
radio-off does not switch to another transport. Neither accepted command proves
call release; the service preserves the modem for an attended recovery.

## Configuration payload and dated evidence

`SET_MODEM_CONFIG` (`0x093f`) uses one byte, `0x00`. The owned base-vendor
S5400 builder maps API integer 1 to wire byte 0 and API integer 2 to wire
byte 1. A bounded replay executed the original builder and header/ModemData
constructors with modeled allocation, copying and single-thread locking.
This establishes the encoding in that capture, not a complete Android RIL
execution or association with the currently merged Android OTA snapshot.

The dated [Komodo bring-up record in #567](https://github.com/marselnenaj/omarchy-mobile/blob/6aa3136ea51c506711fff29bec686b9525142f43/device/komodo/MODEM-BRINGUP.md)
records the actual kernel, protected-backup/read-only checks before modem
startup, absent SIM observations before native radio-on, configuration ACK,
USIM READY after native radio-on and emergency registration after the later
SIT off/on cycle. These were separate guarded component operations; the full
public startup profile and ordinary post-cycle registration remain unqualified.

Wire byte one was not tested on the phone by this work. Firmware persistence
across CP restarts or phone boots remains unknown. An ACK and unchanged
protected partition hashes do not establish volatility. The maintainer's
review of this limit and the public board-kernel dependency remain outstanding.
