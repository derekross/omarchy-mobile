<!-- SPDX-License-Identifier: MIT -->
# SIT: the control protocol between the radio stack and the S5300

Status (2026-10-12): **offline research, nothing run on the phone.** This is
the protocol spec MODEM-PLAN M4 needs: what a client of our own (a small
daemon, then an oFono driver or a ModemManager plugin) has to send on the
IPC channel after M3 brings the modem ONLINE. Every fact below comes from
Google's GPL CPIF driver (`CP/`, as in MODEM-PLAN) or from static analysis of
the stock CP2A vendor libraries from the human's own factory image. No
decompiled code or disassembly is reproduced here: layouts are given as field
tables in our own words, with the function that shows them.

**2026-10-13:** the client we ship is no longer the one built from this
spec: `packages/omamobile-modem-sit` 0.2.0 is a port of a SIT stack that
registered, called, texted and carried data on this phone model, and its
hardware-tested layouts win where they differ from the tables below (the
data call is the 983-byte version-2 request, SET_INITIAL_ATTACH_APN is
essential, the start-up order needs IMS for SMS and voice).
[MODEM-CLIENT.md](MODEM-CLIENT.md) describes it; the M4 runbook is in
[MODEM-PLAN.md](MODEM-PLAN.md). The message names, the transport facts and
the do-not-send list here are still used.

Inputs (never committed; outside the repo):

- `V/` = `~/android/omamobile/vendor/google/cheetah/proprietary/vendor` (CP2A
  vendor tree): `lib64/libsitril.so` (the RIL), `lib64/libril_sitril.so` (the
  AIDL/HIDL front end), `bin/hw/rild_exynos`, and the protocol codec
  `lib64/vendor.radio.protocol.sit.{base,stream,json}.so`.
- `CP/` and the live DT `R/live.dts` as in MODEM-PLAN.

The codec libraries are the useful part: they export their C++ symbols, so
every request builder (`Protocol*Builder::Build*`) and every response or
indication parser (`Protocol*Adapter::Get*`) is named, and
`rcmMsgToString(int)` in `sit.base` is a complete message ID to name table.

Confidence levels: **high** = read directly from GPL source or from a
builder/parser whose code is unambiguous; **medium** = read from code, but
the meaning of a value is inferred from names or Android RIL conventions;
**low** = inferred from call structure or naming only, needs a capture.

---

## 1. Transport

### 1.1 Device nodes (high)

From `R/live.dts` (`cpif/iodevs`), `CP/modem_main.c:499-551` (a node with
`iod,ch_count = N` becomes N devices named `<name>0..N-1` on consecutive
channels) and the channel names in
`G/google-modules/soc/gs/include/dt-bindings/soc/google/exynos-cpif.h`:

| Node | Channel | Format | Use |
|---|---|---|---|
| `/dev/umts_ipc0` | 245 (`EXYNOS_CH_ID_FMT_0`) | IPC_FMT | **SIT, SIM slot 0 / RIL socket 0** |
| `/dev/umts_ipc1` | 246 (`FMT_1`) | IPC_FMT | SIT, SIM slot 1 (eSIM) / RIL socket 1 |
| `/dev/umts_boot0` | 241 | IPC_BOOT | cbd boot; libsitril's `ModemControl` uses it for CP status |
| `/dev/umts_rfs0` | 41 | IPC_RAW | rfsd (NV file service) |
| `/dev/oem_ipc0..7` | 129-136 | IPC_FMT | `libsit_oem` (protobuf OEM channel), not needed |
| `rmnet0..rmnet29` (netdevs) | 181-210 | packet | data calls (section 4) |
| `umts_router`, `umts_dm0`, `umts_loopback`, `umts_rcs*`, `umts_wfc*` | | | not needed |

`libsitril.so` opens `/dev/umts_ipc0` and `/dev/umts_ipc1` by name
(`RilApplication::OnInitialize()` builds one `RilContextParam` per RIL socket
with the channel path and the interface prefix `rmnet`), and reads each in
`RadioControlMessageMgr::Run()`. `IoChannel::Open/Read/Write` are a plain
`open(O_RDWR)`, `read()` and `write()`: **no extra userspace framing.**

### 1.2 Link framing: done by the kernel (high)

The 12-byte Exynos link header (`CP/include/exynos_ipc.h`, `struct
exynos_link_header`) is added by CPIF on write
(`CP/ipc_io_device.c:276-400`, `exynos_build_header()` in
`CP/modem_io_device.c:579`) and stripped on read
(`rx_frame_with_link_header()`, `CP/modem_io_device.c:317`). A SIT client
never sees it. For reference, little-endian:

| Off | Size | Field |
|---|---|---|
| 0 | 2 | sync 0xABCD |
| 2 | 2 | frame sequence (per io device, incremented per frame) |
| 4 | 2 | fragment config: 0xC000 = single frame; multi-frame uses bit 15 start, bit 14 last, bits 8-13 packet index, low byte frames left |
| 6 | 2 | frame length including this header |
| 8 | 1 | channel ID (245 for umts_ipc0) |
| 9 | 1 | per-channel sequence |
| 10 | 2 | (pad to 12) |

Frames are padded to 8 bytes. Messages over 2 KiB (including the header) are
split by the kernel and reassembled on receive (`gather_multi_frame_sit()`),
so **one `write()` is one SIT message and one `read()` returns one SIT
message**. libsitril reads with a 64 KiB + 32 byte buffer.

Kernel conditions a client must handle (`CP/ipc_io_device.c`):

- `write()` returns `-EPERM` while the CP is not ONLINE, and `-EAGAIN` until
  the link's INIT_END handshake is done (for SIT, `rild_ready()` is always
  true, so INIT_END follows the modem boot without waiting for rild:
  `CP/link_device.c:279-286`).
- CP state comes from `IOCTL_GET_CP_STATUS` (`_IO('o', 0x27)`,
  `CP/modem_prj.h:77`) on any CPIF node; values `STATE_OFFLINE` 0,
  `CRASH_RESET` 1, `CRASH_EXIT` 2, `BOOTING` 3, `ONLINE` 4
  (`CP/modem_prj.h:222-232`). libsitril's reader loop checks it before every
  read (`ModemControl::CheckModemStatus`) and reopens the channel after an
  error.
- `IOCTL_TRIGGER_CP_CRASH` on a SIT channel takes a reason string; never
  needed.

### 1.3 SIT message header (high)

From `vendor.radio.protocol.sit.base.so`: `ModemDataBuilder::Build()`,
`ProtocolBuilder::InitRequestHeader()` / `InitIndRequestHeader()`,
`ProtocolBaseAdapter::GetType/GetId/GetLength/GetToken/GetParameter*()`,
`ProtocolRespAdapter::GetErrorCode()`, `ProtocolIndAdapter::GetParameter()`.
All multi-byte fields little-endian, structures packed (fields are often
unaligned).

Requests and responses, 12 bytes (`RCM_HEADER`):

| Off | Size | Field |
|---|---|---|
| 0 | 1 | type: **0 request, 1 response** |
| 1 | 1 | reserved, 0 |
| 2 | 2 | message ID (section 3) |
| 4 | 2 | **total length including this header** |
| 6 | 4 | token (unaligned) |
| 10 | 1 | error code (response only; table below) |
| 11 | 1 | reserved, 0 |
| 12 | | parameters |

Indications, 8 bytes (`RCM_IND_HEADER`):

| Off | Size | Field |
|---|---|---|
| 0 | 1 | type: **2 indication** |
| 1 | 1 | reserved |
| 2 | 2 | message ID |
| 4 | 2 | total length including this header |
| 6 | 2 | reserved |
| 8 | | parameters |

Tokens: one process-wide counter (`TokenGen::GetNext()`), starting at 0,
incremented per request, skipping 0xFFFFFFFF. The response echoes the
request's token and ID; a client matches on the token. A request with no
parameters is a bare 12-byte header.

Response error codes (`rcmErrorToString`, mapped to RIL errors by
`ConvertProtocolErrorCodeToRilErrorCode`, table at `sit.base` 0x8094): 0
SUCCESS, 1 RADIO_NOT_AVAILABLE, 2 GENERIC_FAILURE, 3 PASSWORD_INCORRECT, 4
SIM_PIN2, 5 SIM_PUK2, 6 REQUEST_NOT_SUPPORTED, 7 CANCELLED, 8
OP_NOT_ALLOWED_DURING_VOICE_CALL, 9 OP_NOT_ALLOWED_BEFORE_REG_TO_NW, 10
SMS_SEND_FAIL_RETRY, 11 SIM_ABSENT, 12 SUBSCRIPTION_NOT_AVAILABLE, 13
MODE_NOT_SUPPORTED, 14 FDN_CHECK_FAILURE, 15 ILLEGAL_SIM_OR_ME, 16
MISSING_RESOURCE, 17 NO_SUCH_ELEMENT, 18 SIM_MEMORY_FULL, 19
PB_TOO_LONG_DATA, 20 SIM_PIN_REQ, 21 SIM_PUK_REQ, 22 UNDEFINED_CMD, 23/24
NOT_ALLOWED_DURING_PLMN_SEARCH, 25 SIMULTANEOUS_SMS_AND_CALL_NOT_ALLOWED, 26
ACCESS_BARRED, 27 BLOCKED_DUE_TO_CALL, 28 RF_HARDWARE_ISSUE, 29
NO_RF_CALIBRATION_INFO, 30 MODEM_ERR, 31 NOT_ALLOWED_DURING_CARRIER_CONFIG,
33 PARSING_FAILURE.

Two payload encodings exist: **packed binary structs** (almost everything,
built in `sit.stream`) and, for a few newer messages (satellite, SA mode,
null cipher, cellular identifier disclosure, data call stats, IMEI mapping),
**a JSON body** after the same header (`sit.json`,
`ModemJsonBuilder::{Request,Response,Indication}::build`). Nothing on the
path to registration uses JSON.

---

## 2. Message families

`rcmMsgToString(int)` names 602 IDs. The high byte is the family; requests,
their responses and indications share one ID space, indications carry an
`IND_` name. The full list is in the appendix (high: names and IDs read
from the table). Families: 0x00 call, 0x01 SMS, 0x02 SIM, 0x03 STK, 0x04
device identity, 0x05 supplementary services, 0x06 PS data, 0x07 network,
0x08 radio power, 0x09 misc, 0x0a audio, 0x0c GPS/LPP, 0x0d IMS, 0x0e VSIM,
0x0f Wi-Fi calling, 0x10 eMBMS, 0x13 satellite (NTN), 0x41/0x44/0x46 OEM.

---

## 3. The messages a first client needs

Offsets are **absolute in the SIT message** (header included: request and
response parameters start at 0x0c, indication parameters at 0x08). "Len" is
the request's total length as the stock builder writes it. Evidence is the
builder or parser function in `sit.stream` unless noted.

### 3.1 Radio power

| ID | Name | Request | Response / indication | Conf. | Evidence |
|---|---|---|---|---|---|
| 0x0800 | SET_RADIO_POWER | len 18: 0x0c u32 **2 = on, 1 = off**; 0x10 u8, 0x11 u8 (the 2nd and 3rd builder arguments: for-emergency-call and preferred-for-emergency in the RIL API) | header only | high (layout), medium (meaning of 0x10/0x11) | `ProtocolRadioPowerBuilder::BuildRadioPower` |
| 0x0801 | GET_RADIO_POWER | bare header | state as below | medium | `BuildGetRadioState` |
| 0x0802 | IND_RADIO_STATE_CHANGED | | 0x08 u32: 0 INITIALIZED, 1 STOP_NETWORK, 2 START_NETWORK, 3 POWER_OFF, 4 RESET. Stock maps 0/1 to RIL OFF, 2 to ON, the rest to UNAVAILABLE | high | `ProtocolRadioStateAdapter::GetRadioState`, names in the adapter's string table |
| 0x0803 | IND_RADIO_READY | | starts `NetworkService::OnRadioReady` in libsitril | medium | libsitril |
| 0x0804 / 0x0805 | IND_PHONE_RESET / IND_MODEM_RESTART | | modem going away | medium | names |

The power values match the state names: SET_RADIO_POWER 2 asks for
START_NETWORK, 1 for STOP_NETWORK.

### 3.2 SIM

| ID | Name | Layout | Conf. | Evidence |
|---|---|---|---|---|
| 0x0200 | GET_SIM_STATUS | request: bare header. Response: 0x0c u8 card state, 0x0d u8 (universal PIN state, assumed), 0x0e u8 number of applications (at most 100), then 63-byte application records from 0x0f, then optional trailing slot data, read only when the message is long enough (not decoded yet) | high (offsets), medium (card state values: stock special-cases 3 and 4) | `ProtocolSimStatusAdapter::Init` and getters |
| | application record (63 bytes) | +0 u8 app type, +1 u8 app state, +2 u8 perso substate (the three by analogy with RIL_AppStatus, low), +3 u8 AID length, +4 AID (16 bytes), +20 u8 label length, +21 label (32 bytes), +53..+56 not read by the parser (pin1-replaced and padding, low), **+57 u8 PIN1 state, +58 u8 PIN2 state, +59 u8 PIN1 retries left, +60 u8 PUK1 retries left, +61 u8 PIN2 retries left, +62 u8 PUK2 retries left** | high for +3..+62, low for +0..+2 | `GetAID`, `GetApplicationLabel`, `GetPinState`, `GetPinRemainCount`, `GetPukRemainCount` |
| 0x0201 / 0x0203 | VERIFY_SIM_PIN / VERIFY_SIM_PIN2 | len 38: 0x0c u8 PIN length (at most 8), 0x0d PIN as ASCII digits (8 bytes), 0x15 u8 AID length, 0x16 AID binary (16 bytes; from the hex string Android passes). Response: the tries left as a 32-bit read at 0x0c, whatever the error; error 3 (RCM_E_PASSWORD_INCORRECT) is a wrong PIN, 0x15 SIM_PUK_REQ | high (request, retries offset, error 3), medium (u8 or u32 on the wire) | `ProtocolSimBuilder::BuildSimVerifyPin` (type 0 gives 0x0201, type 1 gives 0x0203); `ProtocolSimVerifyPinAdapter::Init`, `SimLockHandler::OnVerifyPinDone` |
| 0x0202 / 0x0204 | VERIFY_SIM_PUK / PUK2 | not read; same family as above | low | names |
| 0x0210 | IND_SIM_STATUS_CHANGED | re-read GET_SIM_STATUS | medium | name |
| 0x0400 | GET_IMSI | request len 29: 0x0c u8 AID length, 0x0d AID (16 bytes). Response: 0x0c u8 IMSI length (at most 15), 0x0d IMSI as ASCII digits | high | `ProtocolSimBuilder::BuildGetImsi`, `ProtocolSimImsiAdapter::Init` |
| 0x0208 | SIM_IO | ICCID is read the Android way, through SIM_IO on EF_ICCID (2FE2); layout not read yet | low | name; `SimIoService` in libsitril |
| 0x0401 / 0x0402 | GET_IMEI / GET_IMEISV | bare header (len 12) | high | `ProtocolDeviceInfoBuilder::GetIMEI/GetIMEISV` |
| 0x0250 | SET_LOGICAL_TO_PHYSICAL_SLOT_MAPPING | len 17: 0x0c u8 count, 0x0d.. one u8 physical slot per logical slot (4 bytes) | high (layout), medium (meaning) | `ProtocolRadioConfigBuilder::BuildSimSetLogicalSlotMapping` |

### 3.3 Network registration

| ID | Name | Layout | Conf. | Evidence |
|---|---|---|---|---|
| 0x0700 | GET_CS_REG_STATE | request bare. Response: 0x0c u8 reg state, 0x0d u8 reject cause, 0x0e u8 RAT, 0x0f u16 LAC, 0x13 u32 cell ID, 0x17 u8 PSC, 0x18 u32 TAC, 0x1c u32 PCI, 0x20 u32 ECI, 0x2c..0x3f CDMA fields (base station ID, lat/long, concurrent, SID/NID, roaming indicator, PRL); longer (v2) payloads add NR fields | high (offsets), medium (reg state values) | `ProtocolNetVoiceRegStateAdapter::*` |
| 0x0701 | GET_PS_REG_STATE | request bare. Response: 0x0c u8 reg state, 0x0d u8 reject cause, 0x0e u8 max simultaneous data calls, 0x0f u8 RAT, 0x10 u16 LAC, 0x14 u32 cell ID, 0x18 u8 PSC, 0x19 u32 TAC, 0x1d u32 PCI, 0x21 u32 ECI, 0x25 u32 CSG ID, 0x29 u32 timing advance, 0x2d u8 IMS VoPS, 0x2e u8 emergency service; payload of 0x2a+ bytes: ENDC available at 0x33, NR available at 0x35 | high (offsets), medium (values) | `ProtocolNetDataRegStateAdapter::*` |
| 0x070e | IND_NTW_STATE_CHANGED | re-poll 0x0700/0x0701/0x0702 | medium | name, stock Android behaviour |
| 0x0702 | GET_OPERATOR | request bare. Response: 0x0c PLMN, 6 ASCII digits ('#' pads a 5-digit PLMN), 0x12 short name (32 bytes), 0x32 long name (64 bytes), 0x72 u8 reg state and 0x73 u32 LAC (only when the payload is long enough) | high | `ProtocolNetOperatorAdapter::Init` |
| 0x0703 | GET_NTW_MODE (selection mode) | response 0x0c u8 mode (0 automatic, 1 manual, medium) | high (offset) | `ProtocolNetSelModeAdapter::GetNetworkSelectionMode` |
| 0x0704 | SET_NTW_MODE_AUTO | bare header | high | `BuildSetNetworkSelectionAuto` |
| 0x0705 | SET_NTW_MODE_MANUAL | len 22: 0x0c u32 RAT, 0x10 PLMN (ASCII, up to 6), 0x15 '#' | high | `BuildSetNetworkSelectionManual` |
| 0x0706 | GET_AVAILABLE_NETWORKS | scan; parser `ProtocolNetAvailableNetworkAdapter` not read | low | name |
| 0x070a | SET_PREFERRED_NTW_TYPE | len 16: 0x0c u32 SIT network type (RIL preferred type through a table at `sit.stream` 0x2b314: identity for 0-12, then a reshuffle; 10 is the fallback) | high | `BuildSetPreferredNetworkType` |
| 0x0710 | SET_PS_SERVICE ("allow data") | len 13: 0x0c u8 1 = allow | high | `BuildAllowData` |
| 0x074a | IND_REG_FAILED | | low | name |

RAT values (SIT to Android RadioTechnology, `toRadioTech` table at
`sit.base` 0x55d4, high): 1-16 are identical to Android's (1 GPRS ... 14
LTE, 16 GSM); SIT 17 = Android 18 (IWLAN) and 18 = 17 (TD-SCDMA), 19 = 9
(HSPA), 20 = 14 (LTE, a CA variant), 21 = 20 (NR), 22 = 21.

Registration state values are passed to Android unchanged, so they are
Android's RegState: 0 not registered, 1 home, 2 searching, 3 denied, 4
unknown, 5 roaming (medium: no remapping found in libsitril's
`RadioConvUtils`; the parser's "invalid" default is 4).

### 3.4 Signal strength (medium)

| ID | Name | Layout | Conf. | Evidence |
|---|---|---|---|---|
| 0x0900 | GET_SIGNAL_STRENGTH | request bare | high | `ProtocolMiscBuilder::GetSignalStrength` |
| 0x0906 | IND_SIGNAL_STRENGTH | payload: u16 at 0x08, then a versioned block per RAT (GSM, WCDMA, CDMA, EVDO, LTE v1/v4, NR v2/v4), chosen by an "ssVer" the RIL is configured with (1, 4, 5 or default) | medium (framing), low (per-RAT fields) | `ProtocolSignalStrengthIndAdapter::GetSignalStrength`, `SignalStrengthAdapter::Fill*` |
| 0x0943 | SET_SIGNAL_STRENGTH_REPORTING_CRITERIA | len 67 | high (ID/len) | `BuildSetSignalReportCriteria` |

**The per-RAT layouts (read 2026-10-26, offline).** The parsers are in
`vendor.radio.protocol.sit.stream.so` (`SignalStrengthParserV1/V2/V4/V5::FillSignalStrength`).
The version choice and the HAL conversion are in `libsitril.so` and
`libril_sitril.so`. Confidence is high for the offsets read from the
parsers. It is medium for units, which are inferred from the HAL's range
checks.

- **Framing.** Parameters start with an s16 RAT-presence mask. The body
  follows (IND at absolute 0x0a, GET response at 0x0e) and is made of
  s32 LE fields at fixed offsets. A block is read only if its mask bit is
  set. INT_MAX means absent.
- **Version selection.** Stock does not choose by length. It reads the
  RIL property `SignalStrength`, which comes from the modem's
  **SET_DEVICE_INFO (0x0922) reply**, an ASCII `key=value,...` string.
  Without that property it uses the default for the HAL version, V2 on
  this phone's. V1, V4 and V5 have their own parsers; every other value
  uses V2. The minimum body lengths are V1 60, V2 108, V4 196, and V5
  exactly 196 (which parses as V4) or exactly 200.
- **Body offsets per version:**

  | Version | LTE | NR | Other |
  |---|---|---|---|
  | V2 | bit 2 at 0x3c: ss, rsrp, rsrq, rssnr, cqi, ta | bit 6 at 0x54: ss-rsrp, ss-rsrq, ss-sinr, csi-rsrp, csi-rsrq, csi-sinr | GSM bit 0 at 0x00, WCDMA bit 1 at 0x0c, CDMA bit 3 at 0x1c, EVDO bit 4 at 0x24, TD-SCDMA bit 5 at 0x30 |
  | V4 | at 0x3c: ss, rsrp, rsrq, rssnr, cqi-table, cqi, ta | at 0x58: the six above, then csi-cqi-table at 0x70; at 0x74 one CQI report, or INT_MAX followed by 19 at 0x78 | as V2 |
  | V5 | as V4, taken on mask bit 2 or 7 | as V4, plus NR timing advance at 0xc4 | as V2 |
  | V1 | bit 3 at 0x1c | none | GW, CDMA, EVDO and TD-SCDMA blocks first |

- **Units.** Nothing is scaled. The modem sends Android's convention: LTE
  RSRP 44-150 and RSRQ 3-20 as positive magnitudes, RSSNR in 0.1 dB, ss
  0-31 or 99; NR SS-RSRP 44-140, SS-RSRQ -20..43, SS-SINR -23..40. The
  HAL turns anything out of range into INT_MAX.
- **What we do with it.** `omamobile-modem-sit` 0.4.0 (`sit_signal.py`)
  never sends SET_DEVICE_INFO, so it chooses the layout by length. That
  choice is the part to confirm on hardware: MODEM-PLAN A8 compares it
  with the trace's body length and byte shape.

### 3.5 PS data

| ID | Name | Layout | Conf. | Evidence |
|---|---|---|---|---|
| 0x0603 | SET_INITIAL_ATTACH_APN | len 251, same front part as SETUP_DATA_CALL below; 0x0d carries the RAT (14 LTE or 22 for NR); a second PDP type and P-CSCF request for roaming at 0xf8/0xf9 | high (ID/len/APN fields), medium (rest) | `ProtocolPsBuilder::BuildSetInitialAttachApn` |
| 0x0600 | SETUP_DATA_CALL | legacy form len 246 (`sit_pdp_setup_data_call_req`): 0x0c u8 profile/CID, 0x0d u8 RAT, 0x0e u8 flag (1 when the context's mode is 1, low), 0x0f u8 APN type, **0x10 APN (ASCII, 101 bytes)**, **0x75 user name (50)**, **0xa7 password (50)**, **0xd9 u8 auth type** (0 none, 1 PAP, 2 CHAP, 3 PAP or CHAP), **0xda u8 PDP type** (1 IP, 2 IPv6, 3 IPv4v6, 5 non-IP), 0xdb u8 P-CSCF request type, 0xdc.. handover addresses, 0xf1 u32 (from the APN setting, low), rest 0. Newer forms are 638 and 983 bytes (traffic descriptors, slicing, match-all rules) | high (ID/len/APN/auth/PDP), medium (others) | `BuildSetupDataCall` (both overloads), `GetPdpType`, `ConvertAuthTypeToProtocolAuthType` |
| 0x0600 | (response) | total length 0x90 or more ("v11", what this firmware sends): the item starts at params+0. **Base item, offsets from the item start:** 0x00 u16 status, 0x02 CID, 0x03 active (modem 1 is up, 2 is dormant), 0x04 PDP type, 0x05 IPv4 address, 0x09 IPv6 address, **0x19 u8 DNS family** (1 v4, 2 v6, 3 both), 0x1a/0x1e DNS1 v4/v6, 0x2e/0x32 DNS2 v4/v6, 0x42 P-CSCF family, 0x43/0x47/0x4b IPv4 P-CSCF, 0x4f/0x5f/0x6f IPv6 P-CSCF, **0x7f u32 MTU**, 0x83 u8 (unknown). No prefix length (libsitril appends "/64" to IPv6) and no gateway (filled from fixed strings). Extended items (0xea/0xef/0xf6/0x118/0x124+ bytes): 0x84 version byte, more P-CSCFs, retry time at 0xeb, AMBR, then mtuV6 at 0xfa and the PDU session at 0xfe (medium). Shorter messages: a legacy form with 20-byte address slots | high (base item, read 2026-10-26; the offsets the working stack used are confirmed), medium (extensions) | `ProtocolPsSetupDataCallAdapter::Init` (stream library), `DataCallUtil::FillDataCallListFromModemPayload`, `DetermineDCTypeBySize`, libsitril `DataCallListResponse::SetDataCall` |
| 0x0601 | DEACT_DATA_CALL | len 14: 0x0c u8 CID, 0x0d u8 reason | high | `BuildDeactDataCall` |
| 0x0602 | GET_DATA_CALL_LIST | bare header; response is a list of the items above | high (request) | `BuildGetDataCallList` |
| 0x0604 | IND_DATA_CALL_LIST_CHANGED | list of items | medium | `ProtocolPsDataCallListChangedAdapter` |

**Which netdev carries the data (medium-high):** libsitril names the
interface for a call `rmnet<CID-1>` when the modem gives none (a `"%s%d"`
format with the prefix `rmnet` and CID minus one, libsitril around
0x1c9820, in the data-call code), and CPIF creates `rmnet0..rmnet29` on channels 181-210. The
packets are raw IP with no link header: CPIF's receive path looks at the
first nibble for 4 or 6 (`CP/modem_io_device.c`, `rx_multi_pdp`). So CID 1 is
`rmnet0`, an L3 interface we configure with the address, DNS and MTU from
the response (no DHCP). Socket 1 (SIM slot 1) may use a different start
index (`RilContextParam` has `ifstart`); not read.

### 3.6 SMS

| ID | Name | Layout | Conf. | Evidence |
|---|---|---|---|---|
| 0x0100 / 0x0101 | SEND_SMS / SEND_SMS_EXPECT_MORE | len 271: 0x0c u8 domain (property `vendor.radio.smsdomain`, 0-3, default 0), 0x0d u8 SMSC length, 0x0e SMSC (12 bytes, binary; length 1 and a 0x00 byte when there is none), **0x1a u8 TPDU length, 0x1b TPDU (up to 244 bytes, binary)** | high | `ProtocolSmsBuilder::BuildSendSms` |
| 0x0100 | (response) | 0x0c u8 message reference, 0x10 u8 PDU size, PDU after it, error code | medium | `ProtocolSendSmsRespAdapter` |
| 0x010c | IND_NEW_SMS | 0x08 u8 (format/type, low), **0x09 u8 PDU length, 0x0a PDU** (SMSC + TPDU as on the air) | medium | `ProtocolNewSmsIndAdapter` constructor |
| 0x0102 | SEND_SMS_ACK | len 21: 0x0c u32 result (1 success), 0x10 u8 failure cause, 0x11 u32 | medium | `BuildSmsAck(int,int,int)` |
| 0x010b | SEND_ACK_INCOMING_SMS | len 262: ack with a PDU | low | `BuildSmsAck(int,int,const char*,int)` |
| 0x0108 / 0x0109 | GET / SET_SMSC_ADDR | get: bare; set: len 25 | high (ID/len) | `BuildSmscAddress` |

### 3.7 Housekeeping requests stock sends at start

| ID | Name | Request | Conf. | Evidence |
|---|---|---|---|---|
| 0x093f | SET_MODEM_CONFIG | len 13: 0x0c u8 (number of active modem stacks, medium) | high (layout) | `BuildSetModemsConfig` |
| 0x090b | SET_DEBUG_TRACE | len 13: 0x0c u8 | high (layout) | `ProtocolMiscBuilder::SetDebugTrace` |
| 0x0949 | SET_AP_SYSTEM_TIME | len 18: six u8 from `localtime()`: 0x0c and 0x0d year and month (form not checked), 0x0e day, 0x0f hour, 0x10 minute, 0x11 second | high (layout), medium (year form) | `BuildSetApSystemTime` |
| 0x0922 | SET_DEVICE_INFO | len 140 | high (ID/len) | `SendDeviceInfo` |
| 0x0404 | SET_SGC | len 24 (a carrier-group value) | high (ID/len) | `SendSGCValue` |
| 0x4605 / 0x4412 | OEM_SET_SW_VERSION_NUMBER / OEM5_SET_SVN | len 14 | high (ID/len) | `BuildSvNumber`, `BuildOemSetSvn` |
| 0x0902 | SET_SCREEN_STATE | len 16: 0x0c u32 | high | `SetScreenState` |
| 0x0928 | SET_IND_CMD_FILTER | len 16: 0x0c u32 bitmask of indications to suppress | high (layout), low (bits) | `BuildSetUnsolicitedResponseFilter` |

---

## 4. What stock does after the modem boots (low to medium)

From the startup hooks in libsitril (the call structure only; the order
across services is not proven without a log):

1. cbd boots the CP over `umts_boot0` and rfsd serves NV (MODEM-PLAN M3).
2. rild's reader thread per RIL socket polls `IOCTL_GET_CP_STATUS` until
   ONLINE, then opens `/dev/umts_ipc0` (and `ipc1`) and reads.
3. "Radio available" hooks (`*::OnRadioAvailable`, `OnModemOnline`):
   - `MiscService`: SET_DEBUG_TRACE off (`SetDebugTraceOffOnBoot`),
     SET_MODEM_CONFIG (`SetModemsConfig`),
     SET_LOGICAL_TO_PHYSICAL_SLOT_MAPPING (`SetSlotMapping`), SET_SGC
     (`SendSGCValue`); and the software version (`SendSvnInfo`);
   - `DeviceInfoHandler`: SET_DEVICE_INFO;
   - `NetworkService::OnModemOnline`: SET_AP_SYSTEM_TIME;
   - `NetworkService::OnRadioAvailable`: SET_RADIO_POWER on, through
     `TrySetRadioPower`, unless airplane mode
     (`persist.radio.airplane_mode_on`) or a delayed-power flag says
     otherwise;
   - `PsService::OnRadioAvailable`: re-applies the initial attach APN when
     one is stored.
4. The modem answers with IND_RADIO_READY and IND_RADIO_STATE_CHANGED
   (START_NETWORK); `NetworkService::OnRadioReady` marks the radio on.
5. From here Android's telephony drives it in the usual RIL order: SIM
   status on IND_SIM_STATUS_CHANGED, IMSI, SIM_IO reads (ICCID, SPN),
   SET_INITIAL_ATTACH_APN, then CS/PS registration state and operator on
   every IND_NTW_STATE_CHANGED, SETUP_DATA_CALL for the default APN, SMS on
   IND_NEW_SMS with an ack.

A stock radio log would settle the order and the exact first messages: on
stock Android (slot A), `adb logcat -b radio` while the phone boots logs
each SIT message by name. That capture contains identifiers (IMSI, ICCID,
IMEI, phone number), so it stays in `~/android/reference/` and only message
names and layouts come into the repo. It needs a stock boot, and with it the
fresh read-only NV backup that AGENTS.md asks for after any stock boot.

---

## 5. The minimal client to first registration

A small daemon (`sitd`, C or Python first) on `/dev/umts_ipc0`, run only
after M3.4 reports ONLINE with rfsd serving the RAM copies:

1. Open `/dev/umts_ipc0` read-write. Check `IOCTL_GET_CP_STATUS` is 4; retry
   on `EAGAIN` (INIT_END not done yet).
2. Reader: one `read()` per message (64 KiB buffer); type 1 resolves a
   pending request by token, type 2 is an indication. Log every ID by name
   (the appendix as a table).
3. Wait for IND_RADIO_READY (or time out after a few seconds and go on).
4. SET_MODEM_CONFIG with 1 and SET_LOGICAL_TO_PHYSICAL_SLOT_MAPPING mapping
   logical 0 to physical 0 (only if the modem rejects radio power without
   them: try without first), SET_AP_SYSTEM_TIME.
5. SET_RADIO_POWER 2. Expect IND_RADIO_STATE_CHANGED 2.
6. GET_SIM_STATUS. If PIN1 state says "enabled, not verified", stop and ask
   the human: VERIFY_SIM_PIN only on their explicit go (three wrong tries
   lock the SIM; read the retry counter first).
7. GET_IMSI (to choose the attach APN; never logged in the repo).
8. SET_INITIAL_ATTACH_APN with the carrier's APN, PDP type IPv4v6.
9. SET_NTW_MODE_AUTO, SET_PS_SERVICE 1.
10. Poll GET_PS_REG_STATE / GET_CS_REG_STATE / GET_OPERATOR on each
    IND_NTW_STATE_CHANGED until reg state 1 or 5. **That is first
    registration.**
11. Then SETUP_DATA_CALL (CID 1), configure `rmnet0` from the response,
    ping. Then SEND_SMS / IND_NEW_SMS + SEND_SMS_ACK.

**Never send** from our client, and filter in the daemon: anything that
writes modem NV or changes identity or carrier state (SET_RADIO_NODE_VALUE,
SET_RADIO_NODE, EXEC_RADIO_NODE, SET_CFG_DEFAULT, SET_ENG_MODE,
SET_ENG_STRING_INPUT, SET_SELFLOG*, SET_MODEM_LOG_DUMP, SET_CARRIER_*,
OEM_SET_CARRIER_CONFIG_MANIFEST, SET_SIM_CARD_POWER, SET_FACILITY_LOCK,
CHG_SIM_PIN*, VERIFY_NETWORK_LOCK, SET_FORWARDING_AT_COMMAND, the VSIM and
satellite families). The NV is a RAM copy under the modem profile anyway,
but a SIM lock or a network-lock counter is on the card or in the modem, not
in that copy.

**Effort** (after M3.4 reaches ONLINE): the daemon to step 10, 3-5 days,
most of it confirming the start-up messages the modem insists on; data call
and `rmnet0` configuration, 1 week (the v11 data call item needs its own
read of the parser, or a capture); SMS, 2-3 days. Then the front end:
**an oFono driver** maps naturally (its atoms are sim, netreg, gprs-context,
sms, one per SIT family) and is about 2-3 weeks; a **ModemManager plugin**
is harder, because ModemManager talks AT, QMI or MBIM to a port and has no
place for a new binary protocol without either a new port type in its core
or a shim daemon that speaks one of those three: 3-4 weeks. That keeps
MODEM-PLAN's estimate (3-6 weeks to data and SMS, then the front end).

**Built offline (2026-10-12), replaced 2026-10-13:** steps 1-11 above
were `omamobile-sitd` 0.1. Version 0.2.0 replaces it with the
hardware-tested sequence (MODEM-CLIENT.md 1.1); the do-not-send list is
still enforced behind its allow-list, and `tools/sit-sim` now speaks the
0.2 layouts.

---

## 6. Open questions

1. Does the modem need SET_MODEM_CONFIG / slot mapping / SGC / device info
   before it accepts SET_RADIO_POWER? (Static code only shows stock sends
   them first.)
2. The card-state and application-type values in GET_SIM_STATUS, and
   which signal strength layout (V1/V2/V4/V5) this firmware sends without
   SET_DEVICE_INFO. The offsets per layout are known (3.4).
3. ~~The v11 data call item~~: read on 2026-10-26 (3.5). Still open: the
   byte at item 0x83, and whether the modem sends the extended item.
4. Socket 1's `ifstart`: does SIM slot 1 use `rmnet0` upwards too?
5. SET_FORWARDING_AT_COMMAND (0x0931) and IND_FORWARDING_AT_COMMAND (0x0932)
   look like an AT tunnel to the modem. If the modem has an AT parser behind
   it, a ModemManager shim gets much simpler. Unknown; read the builder and
   never send it without a plan.
6. The indication filter bits in SET_IND_CMD_FILTER (only for power saving
   later).

---

## Appendix: SIT message IDs (from `rcmMsgToString`, CP2A)

Names without the `SIT_` prefix.

**0x00xx Call** (31): `0000` GET_CURRENT_CALLS, `0001` DIAL, `0002` GET_LAST_CALL_FAIL_CAUSE, `0003` DTMF, `0004` ANSWER, `0005` DTMF_START, `0006` DTMF_STOP, `0007` SEND_EXPLICIT_CALL_TRANSFER, `0008` HANGUP, `0009` IND_CALL_STATE_CHANGED, `000a` IND_CALL_RING, `000b` SET_SRVCC_CALL_LIST, `000c` IND_SRVCC_HO, `000d` IND_EMERGENCY_CALL_LIST, `000e` CALL_CONFIRM_FEATURE_SET_REQ, `000f` CALL_CONFIRM, `0010` IND_CALL_PRESENT_IND, `0011` SET_CDMA_VOICE_PRIVACY_MODE, `0012` GET_CDMA_VOICE_PRIVACY_MODE, `0014` IND_ENTER_EMERGENCY_CB_MODE, `0015` CDMA_BURST_DTMF, `0016` IND_OTA_PROVISION_STATUS, `0017` IND_CDMA_INFO_REC, `0018` IND_EMERGENCY_SUPPORT_RAT_MODE, `0019` IND_EXIT_EMERGENCY_CB_MODE, `001a` EXIT_EMERGENCY_CB_MODE, `001f` SET_EMC_MODE, `0020` EXIT_EMC_MODE, `0021` EMC_NW_SCAN, `0022` IND_EMC_NW_SCAN_RESULT, `0023` CANCEL_EMC_NW_SCAN

**0x01xx SMS** (29): `0100` SEND_SMS, `0101` SEND_SMS_EXPECT_MORE, `0102` SEND_SMS_ACK, `0103` WRITE_SMS_TO_SIM, `0104` DELETE_SMS_ON_SIM, `0105` GET_BCST_SMS_CFG, `0106` SET_BCST_SMS_CFG, `0107` ACT_BCST_SMS, `0108` GET_SMSC_ADDR, `0109` SET_SMSC_ADDR, `010a` SEND_SMS_MEM_STATUS, `010b` SEND_ACK_INCOMING_SMS, `010c` IND_NEW_SMS, `010d` IND_NEW_SMS_STATUS_REPORT, `010e` IND_NEW_SMS_ON_SIM, `010f` IND_SIM_SMS_STORAGE_FULL, `0110` IND_NEW_BCST_SMS, `0111` CDMA_SEND_SMS, `0112` CDMA_SEND_SMS_ACK, `0113` CDMA_GET_BCST_SMS_CFG, `0114` CDMA_SET_BCST_SMS_CFG, `0115` CDMA_ACT_BCST_SMS, `0116` CDMA_WRITE_SMS_TO_RUIM, `0117` CDMA_DELETE_SMS_ON_RUIM, `0118` IND_CDMA_NEW_SMS, `0119` IND_CDMA_RUIM_SMS_STORAGE_FULL, `0120` IND_CDMA_VOICE_MSG_WAITING_INFO, `0121` GET_STORED_SMS_COUNT, `0122` CDMA_SEND_SMS_EXPECT_MORE

**0x02xx SIM** (43): `0200` GET_SIM_STATUS, `0201` VERIFY_SIM_PIN, `0202` VERIFY_SIM_PUK, `0203` VERIFY_SIM_PIN2, `0204` VERIFY_SIM_PUK2, `0205` CHG_SIM_PIN, `0206` CHG_SIM_PIN2, `0207` VERIFY_NETWORK_LOCK, `0208` SIM_IO, `0209` GET_FACILITY_LOCK, `020a` SET_FACILITY_LOCK, `020b` GET_SIM_AUTH, `020c` TRANSMIT_SIM_APDU_BASIC, `020d` OPEN_SIM_CHANNEL, `020e` CLOSE_SIM_CHANNEL, `020f` TRANSMIT_SIM_APDU_CHANNEL, `0210` IND_SIM_STATUS_CHANGED, `0211` GET_GBA_CONTEXT, `0212` GET_ATR, `0220` SAP_CONNECT, `0221` SAP_DISCONNECT, `0222` IND_SAP_DISCONNECT, `0223` SAP_TRANSFER_APDU, `0224` SAP_TRANSFER_ATR, `0225` SAP_POWER_SIM_OFF, `0226` SAP_POWER_SIM_ON, `0227` SAP_RESET_SIM, `0228` IND_SAP_STATUS, `0229` SAP_TRANSFER_CARD_READER_STATUS, `022a` SAP_SET_TRANPORT_PROTOCOL, `0240` READ_PB_ENTRY, `0241` UPDATE_PB_ENTRY, `0242` GET_PB_STORAGE_INFO, `0245` GET_3G_PB_CAPA, `0246` IND_SIM_PB_READY, `0247` OPEN_SIM_CHANNEL_WITH_P2, `0249` SET_UICC_SUBSCRIPTION, `024a` IND_UICC_SUBSCRIPTION_STATE_CHANGED, `024c` SET_SIM_CARD_POWER, `024d` GET_SLOT_STATUS, `024e` IND_SIM_SLOT_STATUS_CHANGED, `024f` IND_SIM_DATA_INFO, `0250` SET_LOGICAL_TO_PHYSICAL_SLOT_MAPPING

**0x03xx STK** (19): `0300` SEND_STK_ENVELOPE_CMD, `0301` SEND_STK_TERMINAL_RSP, `0302` SEND_STK_ENVELOPE_WITH_STATUS, `0303` IND_STK_PROACTIVE_COMMAND, `0304` IND_SIM_REFRESH, `0305` STK_CALL_SETUP, `0306` IND_STK_SESSION_END, `0307` IND_STK_CC_ALPHA_NOTIFY, `0309` IND_STK_WIFI_STATUS_REQUEST, `030a` SEND_STK_WIFI_STATUS_REPORT, `030b` SEND_STK_TCP_STATUS_EVENT, `030c` IND_STK_OPEN_CHANNEL_REQUEST, `030d` SEND_STK_WIFI_OPEN_CHANNEL_RSP, `030e` IND_STK_SEND_DATA_TO_WIFI, `0310` STK_SEND_WIFI_DATA_RESPONSE, `0311` IND_STK_RECEIVE_DATA_FROM_WIFI, `0312` STK_SEND_BIP_DATA_TO_SIM, `0313` IND_STK_CLOSE_CHANNEL_REQUEST, `0314` STK_SEND_CLOSE_CHANNEL_RESPONSE

**0x04xx Device identity** (9): `0400` GET_IMSI, `0401` GET_IMEI, `0402` GET_IMEISV, `0403` GET_DEVICE_ID, `0404` SET_SGC, `0406` SET_CARRIER_INFO_IMSI_ENCRYPTION, `0407` IND_CARRIER_INFO_IMSI_ENCRYPTION, `0413` GET_IMEI_MAPPING_INFO, `0414` IND_IMEI_MAPPING_INFO

**0x05xx Supplementary services** (23): `0500` HANGUP_WAITING_OR_BACKGROUND, `0501` HANGUP_FORGROUND_RESUME_BACKGROUND, `0502` SWITCH_WAITING_OR_HOLDING_AND_ACTIVE, `0503` CONFERENCE, `0504` UDUB, `0505` SEND_USSD, `0506` CANCEL_USSD, `0507` GET_CLIR, `0508` GET_COLP, `0509` GET_CALL_FORWARD_STATUS, `050a` SET_CALL_FORWARD, `050b` GET_CALL_WAITING, `050c` SET_CALL_WAITING, `050d` CHG_BARRING_PWD, `050e` SEPARATE_CONNECTION, `050f` GET_CLIP, `0510` IND_ON_USSD, `0511` IND_SUPP_SVC_NOTIFICATION, `0512` GET_COLR, `0513` IND_SS_RETURN_RESULT, `0514` SET_CDMA_FLASH_INFO, `0515` IND_CDMA_CALL_WAITING, `0516` IND_ON_SS

**0x06xx PS data** (35): `0600` SETUP_DATA_CALL, `0601` DEACT_DATA_CALL, `0602` GET_DATA_CALL_LIST, `0603` SET_INITIAL_ATTACH_APN, `0604` IND_DATA_CALL_LIST_CHANGED, `0605` SET_FD_INFO, `0607` IND_NAS_TIMER_STATUS, `0608` DETACH, `0609` IND_DATA_STATE_CHANGE, `060a` START_KEEPALIVE, `060b` STOP_KEEPALIVE, `060c` IND_KEEPALIVE_STATUS, `060d` IND_PCO_DATA, `060e` START_LCE_INFO, `060f` STOP_LCE_INFO, `0610` GET_LCE_DATA, `0611` IND_LCE_DATA, `0613` SET_DATA_PROFILE, `0614` SET_IMS_TEST_MODE, `0615` GET_PHONE_CAPABILITY, `0616` SET_PDN_IP_ADDRESS, `0617` IND_ADDR_STATUS, `0619` IND_PS_DATA_OFF_STATUS, `061a` ALLOC_PDU_SESSION, `061b` REL_PDU_SESSION, `061c` START_HANDOVER, `061d` CANCEL_HANDOVER, `061e` IND_UNTHROTTLE_APN, `0621` IND_DEDICATED_BEARER_INFO, `0622` GET_SLICING_CONFIG, `0623` IND_SLICING_CONFIG, `0624` SET_SLICING_CONFIG, `0625` SET_MOBILE_DATA_STATE, `0627` START_DATA_CALL_STATS_CHECK, `0628` GET_DATA_CALL_STATS

**0x07xx Network** (80): `0700` GET_CS_REG_STATE, `0701` GET_PS_REG_STATE, `0702` GET_OPERATOR, `0703` GET_NTW_MODE, `0704` SET_NTW_MODE_AUTO, `0705` SET_NTW_MODE_MANUAL, `0706` GET_AVAILABLE_NETWORKS, `0707` CANCEL_GET_AVAILABLE_NETWORKS, `0708` SET_BAND_MODE, `0709` GET_BAND_MODE, `070a` SET_PREFERRED_NTW_TYPE, `070b` GET_PREFERRED_NTW_TYPE, `070c` GET_CELL_INFO_LIST, `070d` SET_CELL_INFO_LIST_REPORT_RATE, `070e` IND_NTW_STATE_CHANGED, `070f` IND_CELL_INFO_LIST, `0710` SET_PS_SERVICE, `0711` GET_PS_SERVICE, `0712` SET_EMERGENCY_CALL_STATUS, `0713` IND_EMERGENCY_ACT_INFO, `0716` SET_DS_NTW_TYPE, `0717` IND_NET_CURRENT_LTE_MODE, `0718` GET_RADIO_CAPABILITY, `0719` SET_RADIO_CAPABILITY, `071a` GET_DUPLEX_MODE, `071b` SET_DUPLEX_MODE, `071c` IND_LTE_CA_CHANGED, `071d` GET_LTE_CA_INFO, `071e` GET_GSM_CELL_INFO, `071f` SET_MICRO_CELL_SEARCH, `0720` IND_AC_BARRING_INFO, `0721` SET_CDMA_ROAMING_PREFERENCE, `0722` GET_CDMA_ROAMING_PREFERENCE, `0723` SET_CDMA_HYBRID_MODE, `0724` GET_CDMA_HYBRID_MODE, `072b` SET_DUAL_NTW_AND_PS_TYPE, `072c` IND_TOTAL_OOS, `072d` IND_MCC, `072e` SET_CARRIER_RESTRICTIONS, `072f` GET_CARRIER_RESTRICTIONS, `0730` GET_MANUAL_BAND_MODE, `0731` SET_MANUAL_BAND_MODE, `0732` GET_RF_DESENSE_MODE, `0733` SET_RF_DESENSE_MODE, `0734` START_SCANNING_NETWORKS, `0735` STOP_SCANNING_NETWORKS, `0736` IND_SCANNING_NETWORKS, `0737` IND_RADIO_CAPABILITY, `0738` GET_MANUAL_RAT_MODE, `0739` SET_MANUAL_RAT_MODE, `073a` GET_FREQUENCY_LOCK, `073b` SET_FREQUENCY_LOCK, `073c` IND_B2_B1_CONFIG, `073d` SET_ENDC_MODE, `073e` GET_ENDC_MODE, `0740` SET_PREFERRED_DATA_MODEM, `0741` IND_FREQUENCY_INFO, `0742` IND_PHYSICAL_CHANNEL_CONFIG, `0744` SET_LOCATION_UPDATE_SETTING, `0746` GET_FREQUENCY_INFO, `0747` IND_RRC_INFO, `0748` SET_NR_MODE, `0749` GET_NR_MODE, `074a` IND_REG_FAILED, `074b` IND_BARRING_INFO_CHANGED, `074c` SET_SYSTEM_SELECTION_CHANNELS, `074d` GET_BARRING_INFOS, `074e` GET_SYSTEM_SELECTION_CHANNELS, `074f` SET_ALLOW_NETWORK, `0750` GET_ALLOW_NETWORK, `0753` IND_DSDS_STATUS, `0754` SET_SA_MODE, `0755` GET_SA_MODE, `0756` IMS_TRIGGER_EPSFB, `075c` SET_LTE_PREF_MODE, `0760` SET_SATELLITE_MODE_SERVICE, `0761` GET_SATELLITE_MODE_SERVICE, `0762` SET_SATELLITE_PLMN_LIST, `0766` SET_CARRIER_RESTRICTIONS_V2, `0767` GET_CARRIER_RESTRICTIONS_V2

**0x08xx Radio power** (8): `0800` SET_RADIO_POWER, `0801` GET_RADIO_POWER, `0802` IND_RADIO_STATE_CHANGED, `0803` IND_RADIO_READY, `0804` IND_PHONE_RESET, `0805` IND_MODEM_RESTART, `080f` SET_STACK_STATUS, `0810` GET_STACK_STATUS

**0x09xx Misc** (70): `0900` GET_SIGNAL_STRENGTH, `0901` GET_BASEBAND_VERSION, `0902` SET_SCREEN_STATE, `0903` SET_TTY_MODE, `0904` GET_TTY_MODE, `0905` IND_NITZ_TIME_RECEIVED, `0906` IND_SIGNAL_STRENGTH, `0907` SET_CFG_DEFAULT, `0908` SET_ENG_MODE, `0909` SET_SCREEN_LINE, `090a` IND_DISPLAY_ENG, `090b` SET_DEBUG_TRACE, `090c` GET_ACTIVITY_INFO, `090d` SET_OPERATOR_INFO, `090f` GET_CDMA_SUBSCRIPTION, `0910` SET_ENG_STRING_INPUT, `0911` GET_MSL_CODE, `091a` SET_VOICE_OPERATION, `091b` GET_VOICE_OPERATION, `0920` SET_PIN_CONTROL, `0921` IND_PIN_CONTROL, `0922` SET_DEVICE_INFO, `0927` IND_HW_CONFIG_CHANGED, `0928` SET_IND_CMD_FILTER, `0929` IND_CDMA_PRL_CHANGED, `092a` IND_SAR_CONTROL_STATE, `092b` SET_SENSOR_STATUS, `092f` SET_PREFERRED_CALL_CAPABILITY, `0930` GET_PREFERRED_CALL_CAPABILITY, `0931` SET_FORWARDING_AT_COMMAND, `0932` IND_FORWARDING_AT_COMMAND, `0933` SET_INTPS_SERVICE, `0935` SET_VOWIFI_HO_THRESHOLD, `0936` GET_RADIO_NODE, `0937` SET_RADIO_NODE, `0938` GET_VOLTE_PROVISION_UPDATE, `0939` SET_VOLTE_PROVISION_UPDATE, `093a` SET_SELFLOG, `093b` GET_SELFLOG_STATUS, `093c` IND_SELFLOG_STATUS, `093d` SET_ELEVATOR_SENSOR, `093f` SET_MODEM_CONFIG, `0940` SET_MODEM_LOG_DUMP, `0942` SET_SELFLOG_PROFILE, `0943` SET_SIGNAL_STRENGTH_REPORTING_CRITERIA, `0944` SET_LINK_CAPACITY_REPORTING_CRITERIA, `0945` IND_CURRENT_LINK_CAPACITY_ESTIMATE, `0946` GET_RADIO_NODE_VALUE, `0947` SET_RADIO_NODE_VALUE, `0948` EXEC_RADIO_NODE, `0949` SET_AP_SYSTEM_TIME, `094d` SET_DATA_THROTTLING, `0951` GET_CI_NUMBER, `0953` GET_VONR_CAPABILITY, `0954` SET_VONR_CAPABILITY, `0956` SET_DEVICE_SERVICE, `0957` GET_DEVICE_SERVICE, `0967` IND_NO_OTHER_IMS_RAT_AVAILABLE, `096d` SET_NULL_CIPHER_INTEGRITY_ENABLE, `096e` GET_NULL_CIPHER_INTEGRITY_ENABLE, `0974` SET_TIMING_PULSE, `0975` AAM_TIME_AIDING_PULSE_FORCE_WAKEUP, `0976` GET_BASEBAND_TIME_SHIFT_INFO, `0977` GET_NTN_FEATURE, `097b` SET_CELLULAR_IDENTIFIER_DISCLOSURE, `097c` GET_CELLULAR_IDENTIFIER_DISCLOSURE, `097d` IND_CELLULAR_IDENTIFIER_DISCLOSURE, `097e` SET_SECURITY_ALGORITHMS, `097f` GET_SECURITY_ALGORITHMS, `0980` IND_SECURITY_ALGORITHMS

**0x0axx Audio** (16): `0a00` SET_MUTE, `0a01` GET_MUTE, `0a02` IND_RINGBACK_TONE, `0a03` SET_VOLUME, `0a04` GET_VOLUME, `0a05` SET_AUDIOPATH, `0a06` GET_AUDIOPATH, `0a07` SET_MULTI_MIC, `0a08` GET_MULTI_MIC, `0a09` SWITCH_VOICE_CALL_AUDIO, `0a0a` SET_AUDIO_CLK, `0a0b` SET_AUDIO_LOOPBACK, `0a0c` IND_WB_AMR_REPORT, `0a0d` SET_WB_CAPABILITY, `0a0e` GET_WB_CAPABILITY, `0a0f` IND_RESEND_IN_CALL_MUTE

**0x0cxx GPS / LPP** (53): `0c00` SET_GPS_FREQUENCY_AIDING, `0c01` GET_LPP_SUPL_REQ_ECID_INFO, `0c02` GET_RRLP_SUPL_REQ_ECID_INFO, `0c03` IND_GPS_MEASURE_POS_REQ, `0c04` IND_GPS_MEASURE_POSITION_RSP, `0c05` IND_GPS_ASSIST_DATA, `0c06` IND_RELEASE_GPS, `0c07` GPS_MO_LOCATION_REQUEST, `0c08` IND_GPS_MT_LOCATION_REQUEST, `0c09` IND_RESET_GPS_ASSIST_DATA, `0c0a` GET_LPP_REQ_SERVING_CELL_INFO, `0c0b` IND_LPP_REQUEST_CAPABILITIES, `0c0c` LPP_PROVIDE_CAPABILITIES_IND, `0c0d` IND_LPP_REQUEST_ASSIST_DATA, `0c0e` IND_LPP_PROVIDE_ASSIST_DATA, `0c0f` IND_LPP_REQUEST_LOCATION_INFO, `0c10` LPP_PROVIDE_LOCATION_INFO_IND, `0c11` LPP_GPS_ERROR_IND, `0c12` IND_SUPL_LPP_DATA_INFO, `0c13` IND_SUPL_NI_MESSAGE, `0c14` SET_GPS_SUPL_NI_READY, `0c15` IND_3GPP_SEND_GANSS_ASSIT_DATA, `0c16` IND_GANSS_MEAS_POS_MSG, `0c17` SET_GANSS_MEAS_POS_RSP, `0c18` IND_GANSS_AP_POS_CAP_REQ, `0c19` IND_GANSS_AP_POS_CAP_RSP, `0c1a` GET_GSM_EXT_INFO_MSG, `0c1b` GPS_CONTROL_PLANE_ENABLE, `0c1c` GNSS_LPP_PROFILE_SET, `0c20` SET_GPS_LOCK_MODE, `0c21` GET_REFERENCE_LOCATION, `0c22` IND_CDMA_GPS_POWER_ON, `0c23` SET_PSEUDO_RANGE_MEASUREMENTS, `0c24` IND_CDMA_SEND_ACQUSITION_ASSIT_DATA, `0c25` IND_CDMA_SESSION_CANCELLATION, `0c26` GET_CDMA_PRECISE_TIME_AIDING_INFO, `0c27` GET_GPS_CDMA_FREQ_AIDING, `0c28` IND_GPS_LOCK_MODE, `0c29` IND_GPS_START_MDT_LOC, `0c2a` GPS_RETRIEVE_LOC_INFO, `0c2b` IND_LPP_UPDATE_UE_LOC_INFO, `0c2c` SET_GNSS_BLANKING, `0c2d` SET_GNSS_BLANKING_TDL, `0c30` SET_GPS_STATUS, `0c31` SET_GPS_LTE_BAND_INFO, `0c32` IND_GPS_LTE_BAND_INFO, `0c33` SET_GPS_NFW_STATUS, `0c34` IND_GPS_NFW_DATA, `0c35` IND_AP_EMC_STATE, `0c36` IND_GPS_NFW_MODE, `0c40` IND_UE_POSITION_UPDATE_REQ, `0c41` IND_UE_POSITION_INFO, `0c42` GET_NR_SUPL_REQ_ECID_INFO

**0x0dxx IMS (AIMS)** (126): `0d00` AIMS_DIAL, `0d01` IND_AIMS_CALL_RING, `0d02` AIMS_ANSWER, `0d03` AIMS_HANGUP, `0d04` IND_AIMS_CALL_STATUS, `0d05` IND_AIMS_REGISTRATION, `0d06` AIMS_DEREGISTRATION, `0d07` AIMS_HIDDEN_MENU, `0d08` AIMS_ADD_PDN_INFO, `0d09` AIMS_CALL_MANAGE, `0d0a` AIMS_SEND_DTMF, `0d0b` AIMS_SET_FRAME_TIME, `0d0c` AIMS_GET_FRAME_TIME, `0d0d` AIMS_CALL_MODIFY, `0d0e` IND_AIMS_CALL_MODIFY, `0d0f` AIMS_RESPONSE_CALL_MODIFY, `0d10` IND_AIMS_EXPIRE_INFO, `0d11` IND_AIMS_FRAME_TIME, `0d12` AIMS_CONF_CALL_ADD_REMOVE_USER, `0d13` AIMS_ENHANCED_CONF_CALL, `0d14` AIMS_GET_CALL_FORWARD_STATUS, `0d15` AIMS_SET_CALL_FORWARD_STATUS, `0d16` AIMS_GET_CALL_WAITING, `0d17` AIMS_SET_CALL_WAITING, `0d18` AIMS_GET_CALL_BARRING, `0d19` AIMS_SET_CALL_BARRING, `0d1a` IND_AIMS_SUPP_SVC_NOTIFICATION, `0d1b` AIMS_SEND_SMS, `0d1c` AIMS_SEND_EXPECT_MORE, `0d1d` AIMS_SEND_SMS_ACK, `0d1e` IND_AIMS_NEW_SMS, `0d1f` AIMS_SEND_ACK_INCOMING_SMS, `0d20` IND_AIMS_NEW_SMS_STATUS_REPORT, `0d21` IND_AIMS_ON_USSD, `0d22` AIMS_CHG_BARRING_PWD, `0d23` IND_AIMS_CONFERENCE_CALL_EVENT, `0d24` AIMS_SEND_USSD_INFO, `0d25` AIMS_GET_PRESENTATION_SETTINGS, `0d26` AIMS_SET_PRESENTATION_SETTINGS, `0d27` AIMS_SET_SELF_CAPABILITY, `0d28` AIMS_HO_TO_WIFI_READY_REQ, `0d29` AIMS_HO_TO_WIFI_CANCEL_IND, `0d2a` IND_AIMS_PAYLOAD_INFO_IND, `0d2b` AIMS_HO_TO_3GPP_REQ, `0d2c` IND_AIMS_VOWIFI_HO_CALL_INFO, `0d2d` IND_AIMS_NEW_CDMA_SMS, `0d2e` AIMS_SEND_ACK_INCOMING_CDMA_SMS, `0d2f` IND_AIMS_RINGBACK_TONE, `0d30` AIMS_MEDIA_STATE_IND, `0d31` IND_AIMS_CALL_MANAGE, `0d32` IND_AIMS_CONF_CALL_ADD_REMOVE_USER, `0d33` IND_AIMS_ENHANCED_CONF_CALL, `0d34` IND_AIMS_CALL_MODIFY_RSP, `0d35` IND_AIMS_DTMF_EVENT, `0d36` AIMS_SET_HIDDEN_MENU_ITEM, `0d37` AIMS_GET_HIDDEN_MENU_ITEM, `0d38` AIMS_DEL_PDN_INFO, `0d39` AIMS_STACK_START_REQ, `0d3a` AIMS_STACK_STOP_REQ, `0d3b` AIMS_XCAPM_START_REQ, `0d3c` AIMS_XCAPM_STOP_REQ, `0d3d` AIMS_RTT_SEND_TEXT, `0d3e` IND_AIMS_RTT_NEW_TEXT, `0d3f` IND_AIMS_RTT_FAIL_SENDING_TEXT, `0d40` AIMS_RCS_MULTI_FRAME, `0d41` IND_AIMS_RCS_MULTI_FRAME, `0d42` AIMS_RCS_CHAT, `0d43` IND_AIMS_RCS_CHAT, `0d44` AIMS_RCS_GROUP_CHAT, `0d45` IND_AIMS_RCS_GROUP_CHAT, `0d46` AIMS_RCS_OFFLINE_MODE, `0d47` IND_AIMS_RCS_OFFLINE_MODE, `0d48` AIMS_RCS_FILE_TRANSFER, `0d49` IND_AIMS_RCS_FILE_TRANSFER, `0d4b` IND_AIMS_RCS_COMMON_MESSAGE, `0d4c` AIMS_RCS_CONTENT_SHARE, `0d4d` IND_AIMS_RCS_CONTENT_SHARE, `0d4e` AIMS_RCS_PRESENCE, `0d4f` IND_AIMS_RCS_PRESENCE, `0d50` AIMS_RCS_XCAP_MANAGE, `0d51` IND_AIMS_RCS_XCAP_MANAGE, `0d52` AIMS_RCS_CONFIG_MANAGE, `0d53` IND_AIMS_RCS_CONFIG_MANAGE, `0d54` AIMS_RCS_TLS_MANAGE, `0d55` IND_AIMS_RCS_TLS_MANAGE, `0d56` AIMS_ENRICHED_CALLING, `0d57` IND_AIMS_ENRICHED_CALLING, `0d5a` AIMS_RCS_COMMON_MESSAGE, `0d60` AIMS_EXIT_EMERGENCY_CB_MODE, `0d61` IND_AIMS_EXIT_EMERGENCY_CB_MODE, `0d62` AIMS_SET_GEO_LOCATION_INFO, `0d63` IND_AIMS_DIALOG_INFO, `0d64` AIMS_CDMA_SEND_SMS, `0d65` IND_AIMS_SIP_MSG_INFO, `0d70` IND_AIMS_MEDIA_STATUS, `0d71` AIMS_SET_PDN_EST_STATUS, `0d72` AIMS_SET_RTP_RX_STATISTICS, `0d73` AIMS_IND_RTP_RX_STATISTICS, `0d74` IND_AIMS_VOICE_RTP_QUALITY, `0d75` IND_AIMS_FEAT_SUPP, `0d79` IND_AIMS_AT_CMD_FORWARDING, `0d80` REQ_AIMS_AT_CMD_FORWARDING, `0d81` REQ_AIMS_CALL_TRANSFER, `0d82` IND_AIMS_CALL_TRANSFER_RSP, `0d85` IND_AIMS_CALL_TRANSFER, `0d86` AIMS_CALL_DEFLECTION_REQ, `0d87` IND_AIMS_MWI_INFO, `0d88` REQ_AIMS_COMMON_IMS_SVC_INFO, `0d89` IND_AIMS_SIP_CONFIG, `0d8a` AIMS_SEND_UL_SIP_MSG_IND, `0d8b` IND_AIMS_UL_SIP_MSG_RESULT, `0d8c` IND_AIMS_SEND_DL_SIP_MSG, `0d8d` AIMS_DL_SIP_MSG_RESULT_IND, `0d8e` AIMS_REGISTER_IND, `0d8f` AIMS_COMPOSER_MMTEL, `0d90` IND_AIMS_COMPOSER_MMTEL, `0d91` AIMS_CANCEL_COMPOSER_MMTEL, `0d92` AIMS_SET_RTP_HEADER_EXTENSION_TYPE, `0d93` IND_AIMS_RTP_HEADER_EXTENSION_TYPE, `0d94` AIMS_SEND_RTP_HEADER_EXTENSION, `0d95` IND_AIMS_RTP_HEADER_EXTENSION, `0d96` AIMS_EMERGENCY_VOWIFI_CAPABILITY, `0d97` IND_AIMS_CODEC_INFO, `0d98` IND_AIMS_RELEASE_EPDN, `0d9e` AIMS_REQ_ENTER_EMERGENCY_CB_MODE, `0da2` IND_AIMS_ISIM_FILE_CHANGE

**0x0exx VSIM** (3): `0e00` VSIM_NOTIFICATION, `0e01` IND_VSIM_OPERATION, `0e02` VSIM_OPERATION

**0x0fxx WFC** (6): `0f00` SET_WFC_MEDIA_CONFIGURATION, `0f01` IND_WFC_RTP_RTCP_TIMEOUT, `0f02` WFC_DTMF_START, `0f03` IND_WFC_FIRST_RTP, `0f04` IND_WFC_RTCP_RX_SR, `0f05` IND_WFC_RCV_DTMF_NOTI

**0x10xx eMBMS** (11): `1000` SET_EMBMS_SERVICE, `1001` SET_EMBMS_SESSION, `1002` IND_EMBMS_COVERAGE, `1003` GET_EMBMS_SESSION_LIST, `1004` IND_EMBMS_SESSION_LIST, `1005` GET_EMBMS_SIGNAL_STRENGTH, `1006` IND_EMBMS_SIGNAL_STRENGTH, `1007` GET_EMBMS_NETWORK_TIME, `1008` IND_EMBMS_NETWORK_TIME, `1009` IND_EMBMS_SAI_LIST, `100a` IND_EMBMS_GLOBAL_CELL_ID

**0x13xx NTN (satellite)** (13): `1300` SET_NTN_MODE, `1301` GET_NTN_STATE, `1302` GET_NTN_CAPA, `1305` SET_NTN_SEND_DATA_OVER_CP, `1306` IND_NTN_INCOMING_DATA_OVER_CP, `1307` GET_NTN_MODE, `1308` SET_NTN_SATELLITE_CFG, `1309` IND_NTN_STATE, `130c` GET_NTN_SIGNAL_STRENGTH, `130d` IND_NTN_SIGNAL_STRENGTH, `130f` GET_NTN_METRIC, `1310` IND_NTN_MODEM_EVENT, `1312` IND_NTN_SAR_STATUS

**0x41xx OEM** (7): `4100` OEM_GET_SAR_STATE, `4101` OEM_SET_SAR_STATE, `4102` OEM_IND_RF_CONNECTION, `4103` OEM_SET_SVN, `4104` OEM_GET_SIM_LOCK_INFO, `4105` OEM_SET_CA_BW_FILTER, `4106` OEM_IND_CA_BW_FILTER

**0x44xx OEM** (14): `4403` OEM_SET_FORBID_LTE_CELL, `4405` OEM_SET_FUNC_SWITCH_REQ, `4406` OEM_SET_RTP_PKTLOSS_THRESHOLD, `4407` OEM_IND_RTP_PKTLOSS_THRESHOLD, `4408` OEM_SET_PDCP_DISCARD_TIMER, `4409` OEM_GET_CQI_INFO, `440a` OEM_SET_SAR_SETTING, `440b` OEM_SET_GMO_SWITCH, `440c` OEM_SET_TCS_FCI_REQ, `440d` OEM_GET_TCS_FCI_INFO, `440e` OEM_IND_ENDC_CAPABILITY, `440f` OEM_GET_ACTIVITY_INFO, `4410` OEM_IND_BASESTATION_INFO, `4412` OEM5_SET_SVN

**0x46xx OEM** (6): `4600` OEM_SET_CARRIER_CONFIG_MANIFEST, `4601` OEM_IND_CARRIER_CONFIG_STATUS, `4602` OEM_IND_CARRIER_CONFIG_SIM_INFO, `4603` OEM_VERIFY_SIM_PIN_ENC, `4604` OEM_IND_SIM_PIN_ENC, `4605` OEM_SET_SW_VERSION_NUMBER
