<!-- SPDX-License-Identifier: MIT -->
# Komodo modem bring-up record

## 2026-11-11: S5400 configuration, radio power and SIM status

Device: Pixel 9 Pro XL (`google,zumapro-komodo`). All observations in this
section ran on `7.3.0-rc6-omamobile-komodo-gnss-km4`, a local development
kernel, with GNSS disabled. They are individual guarded bring-up operations,
not qualification of a released device package or the complete startup
profile proposed in #669.

Before the cold modem starts, the recorded admission matched the complete
off-repository backups of `efs`, `efs_backup`, `modem_userdata`, `persist`,
`modem_a` and `modem_b`. All six partitions were read-only and unmounted;
the complete storage census found 56 read-only partition nodes. The checks
also matched five slot-B image prefixes, all 201 module files, 118 HAL files
and 1493 modem files before `cbd` and `rfsd` started. The tests
used an external kernel-log witness, one owned watchdog and a bounded
deadman. No protected-partition write or slot-state write was performed.

### Before native radio-on

With CP ONLINE, SIM queries on both formatted IPC channels reported absent
card/application state. A slot-status query reported zero configured
physical slots. These are pre-radio-on observations; they do not establish
an empty tray. IPC1's response was saved, but its independent finish rejected a
qualification-type mismatch. An authorized same-kernel recovery reboot
followed; this probe is not counted as a cleanly completed scope.

These observations are also not a completed execution of the default
service's whole AT startup. Its source waits for SIM readiness before
turning the radio on, which cannot progress from these observations.

One `SET_MODEM_CONFIG` request (`0x093f`, payload byte `0`) was then accepted.
The immediately following slot-status query still reported zero slots.
Configuration acceptance alone did not make the SIM ready.

### Native radio-on and the later off/on cycle

A separate guarded cold start sent the same configuration, then
`SET_RADIO_POWER` (`0x0800`) with the six-byte payload `02 00 00 00 00 00`.
The following observations reported radio state 10, card state 1 and
application type/state `[2, 5]` (USIM READY). The newer slot layout reported
two physical slots. No PIN, subscription or slot-mapping setter was sent.

A later, separately scoped continuation sent radio off, initial-attach APN,
default data profile and radio on through the same owned SIT connection.
All four requests were accepted. The immediate registration sample was
state 0/reject 0/RAT 14; four subsequent settled samples reported
state 20/reject 0/RAT 14. The owned S5400 state adapter maps state 20 to
emergency registration. This is not ordinary home/roaming registration,
data-bearer activation or 5G support. SIM service entitlement was not
established by those tests.

Each completed scope used a fresh SSH finish, closed its watchdog/log
ownership and preserved its consumed attempt. Subsequent full checks
confirmed the six protected backup matches and read-only state. These
results do not establish a successful registration after the SIT cycle;
that remains a hardware qualification requirement for the proposed profile.

## 2026-11-12: source of configuration byte zero

Byte zero comes from this phone's owned S5400 protocol builder, rather than
a trial in which wire byte one failed. The source material was recovered
read-only from this phone's base-vendor image. Association with a currently
merged Android OTA snapshot is not qualified.

The inspected host RIL selects API integer 1 for its single-phone-count
branch and forwards it to `ProtocolMiscBuilder::BuildSetModemsConfig(int)`.
A bounded offline replay of the original builder and header/ModemData
constructors produced:

| API integer | Wire payload byte | Request | Frame length |
| --- | --- | --- | --- |
| 1 | 0 | `0x093f` | 13 bytes |
| 2 | 1 | `0x093f` | 13 bytes |

The replay used modeled allocation, copying and single-thread mutex
operations; it did not run the complete Android RIL service or modem
firmware. The constructor received the bytes produced by the original
builder. No vendor instructions, binaries, identifiers or raw captures
are included here. The separate November 11 modem ACK establishes actual
acceptance of wire byte zero on this device. Wire byte one was not tested
on the phone by this work.

Whether this setting persists across CP restarts or phone boots remains
unknown. An error-zero ACK, a host callback without property/reset writes
and unchanged protected partition hashes do not establish volatility.
The opt-in startup profile therefore retains this limitation for review.
