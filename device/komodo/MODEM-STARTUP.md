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

## Unresolved configuration payload and hardware evidence

`SET_MODEM_CONFIG` (`0x093f`) currently proposes the single byte `0x00`.
Its Komodo-specific meaning, stock-builder provenance and persistence across
boots remain unresolved. The name `configure_single_modem` does not establish
that byte zero means one active stack. Other recorded Tensor modem starts use
different values; those records must not be silently generalized to Komodo.
This is a merge blocker requiring the maintainer's review, not permission to
test configuration writes or compare values on a live modem.

A future hardware entry must supply the actual date and `uname -r`, the six
off-repository NV-backup comparisons and protected partitions' read-only state
before cbd/rfsd, what the default startup showed, and the result of the proposed
order including registration after the SIT cycle. Keep identifiers, subscriber
details, raw logs, partition images and vendor binaries private. No such result
is invented by the simulator tests or by this documentation.
