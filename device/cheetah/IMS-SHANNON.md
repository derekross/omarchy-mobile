# IMS-SHANNON: how stock's IMS service drives the CP's IMS stack

Status: research note, 2026-11-02 (offline). Source: Shannon's IMS service
APK from the cheetah vendor tree (`system_ext/priv-app/ShannonIms`,
versionName `000000.000000.b9d325b79`, sha256 prefix `dd3889d95e280717`),
decompiled with jadx 1.5.1 on the laptop. Nothing of it is in the
repository; this note gives class and method names, request IDs, field names
and offsets only. Consumer: `packages/omamobile-modem-sit` (`lib/ims.py`,
`lib/bringup.py`, `lib/data_call.py`).

Question this answers: why cheetah's CP answers our ADD_PDN_INFO on
Tracfone/Straight Talk on Verizon (311480) with IND_AIMS_REGISTRATION state
1, features 0, status 5 and never registers, while the same sequence
registers on T-Mobile.

**Short answer.** Status 5 is `IMS_SERVICE_REGISTER_FAIL`, the permanent
registration failure. Stock never puts the CP in that position on this
path: it **never sends AIMS_ADD_PDN_INFO for IMS without a P-CSCF**. When
the IMS PDN's link properties carry none and no ISIM P-CSCF resolved, stock
stops ("stop registration for invalid pcscf", reason `NO_PCSCF`) and tears
the PDN down; `BLOCK_PDN_BY_INVALID_PCSCF` (0 for Verizon) only decides
whether the PDN is also blocked until a power cycle. ADD_PDN_INFO has no
FQDN field and no "P-CSCF from SIM" flag: the list is binary IPv4 and IPv6
addresses only, so the CP doesn't resolve or discover anything itself. On
Verizon stock's P-CSCF comes from the IMS PDN's PCO (the RIL's data-call
response), or from the ISIM's EF_PCSCF name resolved **on the default
network** (the internet APN without Wi-Fi). Our IMS bearer request differs
from stock's for Verizon's IPv4v6 IMS APN; see section 7.

## 1. Where things live

| Role | Class (package `com.shannon.imsservice`) |
| --- | --- |
| Stack start/stop, hidden menu, ADD_PDN order | `conn.StackControl` (`startCpModules`, `startCpImsModules`, `sendHiddenMenu`, `sendPdnInfo`, `isRequiredOmaDmHiddenMenu`, `updateNtpTime`) |
| Request encoders | `network.adaptor.RegistrationAdaptor` (`sendStackStartReq`, `sendHiddenMenu`, `sendHiddenMenuCpImsConfiguration`, `sendHiddenMenuOmaDm`, `sendAddPdnInfo`, `sendDelPdnInfo`, `sendDeregistration`, `sendSetHiddenMenuItem`, `sendImsTestModeState`, `sendSetPdnEstStatus`, `sendRegistrationState`, `updateNtpTime`) |
| Hidden-menu TLVs | `network.adaptor.HiddenMenuBuilder` (and its enum `CpImsConfiguration`) |
| Wire layouts | `network.adaptor.data.RilReq*` / `RilInd*` (`getBytes`, `update`) |
| P-CSCF selection | `conn.ApnEntity.updatePcscfAddresses`, its network callback `handleNetworkAvailable`; `conn.ImsConnectivityMgr.getPcscfAddressFromSim` / `addPcscfFromSim` / `getHostNameFromSim`; `conn.DefaultNetworkCallback.onAvailable` |
| Registration indication | `network.adaptor.data.RilIndRegistration` (`RegState`, `RegFeature`), `conn.RegistrationReason` |
| Per-carrier policy | assets `sim_configurations/sim_configuration_311.xml`, `sim_operator_list.xml`, `operator_config.xml`; defaults `config.configuration.ImsSimConfigDefaults` |
| Message IDs | `network.oem.helper.ImsRilHelper.RilMessageId` (RIL-OEM numbers; the RIL maps them to SIT IDs) |

The service talks to the RIL with RIL-OEM message numbers, not SIT IDs. The
payloads are the RIL-OEM structures below (little-endian, `DataWriter`).
Our daemon sends these structures as the SIT payloads of the IDs in
`lib/sit_names.py`; for HIDDEN_MENU and ADD_PDN_INFO that is proven on the
phone (T-Mobile registered). For the others the pass-through is assumed,
not verified in the RIL.

| RIL-OEM name (number) | SIT ID / `sit_names.py` |
| --- | --- |
| `RILC_REQ_AIMS_STACK_START_REQ` (137) | 0x0d39 AIMS_STACK_START_REQ |
| `RILC_REQ_AIMS_XCAPM_START_REQ` (139) | 0x0d3b AIMS_XCAPM_START_REQ |
| `RILC_REQ_AIMS_SET_FRAME_TIME` (108) | 0x0d0b AIMS_SET_FRAME_TIME |
| `RILC_REQ_AIMS_HIDDEN_MENU` (104) | 0x0d07 AIMS_HIDDEN_MENU |
| `RILC_REQ_AIMS_ADD_PDN_INFO` (105) | 0x0d08 AIMS_ADD_PDN_INFO |
| `RILC_REQ_AIMS_DEL_PDN_INFO` (136) | 0x0d38 AIMS_DEL_PDN_INFO |
| `RILC_REQ_AIMS_SET_HIDDEN_MENU_ITEM` (146) | 0x0d36 |
| `RILC_REQ_AIMS_SET_PDN_EST_STATUS` (145) | 0x0d71 |
| `RILC_REQ_AIMS_SET_SELF_CAPABILITY` (129) | 0x0d27 |
| `RILC_REQ_AIMS_COMMON_IMS_SVC_INFO` (161) | 0x0d88 |
| `RILC_REQ_SET_IMS_TEST_MODE` (38) | 0x0614 SET_IMS_TEST_MODE |
| `RILC_REQ_SET_IMS_REGISTRATION_STATE` (48) | not in `sit_names.py` |
| `RILC_REQ_MISC_SET_PREFERRED_CALL_CAPA` (20) / `SET_VOICE_OPERATION` (45) | 0x092f / 0x091a |
| `RILC_UNSOL_AIMS_REGISTRATION` (3012) | 0x0d05 IND_AIMS_REGISTRATION |
| `RILC_UNSOL_CP_CARRIER_CONFIG_CHANGED` (9000) | the 0x4601 status (u32 status, u32 cause; status 1 releases the stack start) |

## 2. The sequence, stack start to registered (cellular)

1. SIM loaded, carrier config status received (`onCarrierConfigManifestStatusReceived`)
   → `StackControl.startCpModules(slot, simReady)`:
   - **AIMS_STACK_STOP_REQ** first if a previous stop failed, 50 ms;
   - **AIMS_STACK_START_REQ** `[u8 sim status (1 ready), u8 stack type (slot + 1)]` = `01 01`;
   - **AIMS_XCAPM_START_REQ** (same two bytes), when the XCAP stack may start;
   - **AIMS_SET_FRAME_TIME** (`updateNtpTime`): `[u8 call id 0, u8 operation 2, u64 time]`, the time being the AP's wall clock in milliseconds since 1970.
2. The service asks Android for the IMS network (APN `IMS` on Verizon, the
   attach PDN). On `handleNetworkAvailable`: `updatePcscfAddresses(linkProperties)`.
   Link properties' P-CSCF list empty → the list resolved from the ISIM
   (section 4); still empty → **stop: no ADD_PDN**, `NO_PCSCF`, PDN
   disconnected. Otherwise → `updateStartImsStack`, then
   `onApnEnabled` → `StackControl.sendPdnInfo`.
3. `sendPdnInfo`, first IMS PDN after a stack start:
   - **AIMS_HIDDEN_MENU** part 1, more-expected 1 (section 5);
   - **AIMS_HIDDEN_MENU** CP IMS configuration segments, only when the
     carrier config enables AOSP IMS configuration (section 6);
   - **AIMS_HIDDEN_MENU** part 2, more-expected 0: the video media
     description (`MediaConfig.getMediaInfo`, else a built-in default);
   - then `RegistrationAdaptor.sendAddPdnInfo`, which first sends the
     **OMA-DM AIMS_HIDDEN_MENU** (more-expected 0) once after SIM load, when
     no ADD_PDN has been sent yet (`isRequiredOmaDmHiddenMenu`, static
     `setOmaDm`);
   - **AIMS_ADD_PDN_INFO** (section 3).
4. The CP registers and sends IND_AIMS_REGISTRATION (section 8). On state 2
   the service sends SET_IMS_REGISTRATION_STATE `[u32 1, u32 RAT]` (a
   report to the RIL, not a precondition) and, with RCS, SET_SELF_CAPABILITY.
5. Later, only on events: SET_HIDDEN_MENU_ITEM 519 (the user agent, when it
   changes), SET_PDN_EST_STATUS `[u8 status]` (2 when the IMS registration
   timer expires or Verizon's throttling outlasts it; 1 for AT&T's
   not-subscribed), COMMON_IMS_SVC_INFO (Wi-Fi calling button, VoLTE switch),
   SET_IMS_TEST_MODE `[u32]` (only when the `IMS_TEST_MODE` policy changes;
   default 0, never sent at start-up).

Our sequence (0.3.19) was: STACK_START `01 01` → SETUP_DATA_CALL (IMS, IPv6) →
HIDDEN_MENU (one segment, more-expected 0) → ADD_PDN_INFO (empty list) →
status 5. Missing against stock: XCAPM_START, SET_FRAME_TIME, the OMA-DM
menu, hidden-menu part 2, and above all a P-CSCF.

## 3. AIMS_ADD_PDN_INFO (0x0d08) layout

`RilReqAddPdnInfo.getBytes`, filled by `RegistrationAdaptor.sendAddPdnInfo`.
Offsets for a cellular PDN with `n4` IPv4 and `n6` IPv6 P-CSCF addresses
(the list position makes everything after it move).

| Offset | Size | Field | Stock value on cellular IMS |
| --- | --- | --- | --- |
| 0 | 1 | PDN type | `ApnNetType.getApnCategory`: IMS 2 |
| 1 | 1 | IP type | `ApnEntity.getIpType`: bit 0 IPv4, bit 1 IPv6 (3 for both) |
| 2 | 4 | PDN IPv4 address | 0.0.0.0 when none |
| 6 | 16 | PDN IPv6 address | :: when none |
| 22 | 1 | HD internet enabled | 17 |
| 23 | 1 | operator ID | 0 |
| 24 | 1 | registration style | `getRegStyle`: 0 normal, 1 for handover/re-registration |
| 25 | 1 | PDN new | 1 new, 0 for handover/re-registration |
| 26 | 1 | VoLTE auto-config | 0 |
| 27 | 1 | RCS auto-config | 0 |
| 28 | 2 | offering type | `getOfferingType`: capability bits (VoLTE 1, SMS-IP 2, RCS 4, PSVT 8, RTT 16, mobile data 32, Wi-Fi data 64, ViCE 256) |
| 30 | 1 | registration type | `ApnNetType.getRegType` (IMS 0; 3 with RCS on) |
| 31 | 1 | init type | 0, 1 handover, 2 re-registration |
| 32 | 1 | IMS net type | transport: 1 cellular, 2 Wi-Fi |
| 33 | 6 | Wi-Fi MAC | zero on cellular |
| 39 | 1 | IPv4 P-CSCF count `n4` | at most 8 |
| 40 | 4·n4 | IPv4 P-CSCF addresses | |
| 40+4n4 | 1 | IPv6 P-CSCF count `n6` | at most 8 |
| 41+4n4 | 16·n6 | IPv6 P-CSCF addresses | |
| then | 4, 16, 4, 16 | primary DNS IPv4, IPv6; secondary DNS IPv4, IPv6 | from the link properties |
| then | 23 | last access network, two 8-byte timestamps, TAC (u16), cell ID (u32) | Wi-Fi only; zero on cellular |
| then | 4 | remaining emergency registration timer | 0 |
| then | 10 | network MCC/MNC digits (6), country code (2), MTU (2) | Wi-Fi only; zero on cellular |
| then | 4, 2, 4 | RCS capability mask, vendor capability mask, extended RCS mask | 0 without RCS |
| then | 1 + 32 | VoWiFi E911 AID length and text | empty |
| then | 2 | additional-field length | 12 on cellular |
| then | 500 | additional fields, fixed buffer: TLV `u16 tag 1, u16 len 8, u64 SIP delegate capability`; on Wi-Fi also band (tag 2), cell ID (4), TAC (5), interface index (6) | |

There is **no FQDN, domain or "from SIM" field**. Every P-CSCF is a binary
address the AP resolved. Compared with our `add_pdn_payload` (0.3.19): the
layout matches field for field; differences were IP type fixed at 2 (IPv6
only, IPv4 address and IPv4 DNS always zero), at most 3 IPv6 P-CSCFs (stock 8)
and, by configuration, an empty list (stock: never). 0.3.20 announces an
IPv4v6 bearer with both families as stock does (section 9).

AIMS_DEL_PDN_INFO (0x0d38): `[u8 IMS net type, u8 PDN type, u8 reason]`.
AIMS_DEREGISTRATION (0x0d06): `[u8 PDN type, u16 feature 126, u8 cause 0]`.

## 4. P-CSCF handling in stock

`ApnEntity.updatePcscfAddresses(LinkProperties)`, for IMS, emergency and
RCS PDNs:

1. `linkProperties.getPcscfServers()`: the P-CSCF list Android's data stack
   got from the RIL's data-call response, which the CP fills from the PDN's
   PCO.
2. If empty: `ImsConnectivityMgr.mPcscfAddressFromSim`. That list is built by
   `getHostNameFromSim` (`TelephonyManager.getIsimPcscf()`: the ISIM's
   EF_PCSCF, non-alphanumeric characters stripped) and
   `getPcscfAddressFromSim`, which resolves each name with
   `InetAddress.getByName` on its own thread. That runs when the **default
   network** becomes available (`DefaultNetworkCallback.onAvailable`), so the
   name is resolved by the default network's DNS: the internet APN's DNS
   servers when there is no Wi-Fi, never the IMS PDN's. `getByName` returns
   one address per name, IPv4 or IPv6, whichever the resolver puts first.
3. Split into IPv4 and IPv6 lists by address family. Both empty → return
   false → `handleNetworkAvailable` logs "stop registration for invalid
   pcscf", sets `DeregiImsReasonInfo.NO_PCSCF` and disconnects; with
   `BLOCK_PDN_BY_INVALID_PCSCF` = 1 it also blocks the PDN
   (`blockPdnByInvalidPcscfIfNeeded`, `RETRY_COUNT_FOR_INVALID_PCSCF`).
   Verizon's 311480 entry sets it to 0, so stock just waits for the next PDN
   or default-network event; it still sends no ADD_PDN.

So for this SIM stock registers only if (a) the IMS PDN's PCO carries a
P-CSCF, or (b) `pcscf1.anyims.vzims.com` resolves through the internet APN's
DNS. Which of the two it is on this line can only be read from a stock
logcat (section 10, step 0).

## 5. AIMS_HIDDEN_MENU (0x0d07) and the provisioning requests

Request (`RilReqHiddenMenu`): `[u8 more-expected, u16 data length, data]`.
Data is a list of items (`HiddenMenuBuilder`): `u16 tag` then either a u32
integer (integers of -1 are skipped), or a string/byte string followed by
`##` (0x23 0x23). Segments at most 900 data bytes.

Part 1 (`RegistrationAdaptor.sendHiddenMenu`, more-expected 1):

| Tag | Value |
| --- | --- |
| 523, 527, 529, 531, 533 | 30 each (SIP timers A, E, G, I, K) |
| 772 / 773 / 774 / 775 / 776 | manufacturer / model / build ID / product name / OS version (`DeviceInfoUtil`) |
| 519 | the user agent (`SIP_USER_AGENT` template; Verizon `#MANUFACTURE#---#MODEL#---#BUILD#`) |
| 1044, 1045 | geolocation PIDF for VoWiFi / VoLTE emergency calls (Verizon: 1045 = 1) |
| 1080, 1081, 1082 | EPS-fallback silent-retry error code, VoLTE/VoWiFi silent-retry policy and codes (default 0) |
| 1084 | RTT supported |

Part 2 (more-expected 0): the video media description (`SetVideoMediaInfo`:
bandwidth, CVO, ECN, H.264/H.265 fmtp lines), a binary structure, not TLVs.
It configures video calls, not registration. Our single segment with
more-expected 0 registered on T-Mobile, so the CP accepts the menu without it.

OMA-DM menu (`sendHiddenMenuOmaDm`, more-expected 0, once before the first
ADD_PDN after SIM load, on every carrier): tag **777 = 1** (is-OMA-DM-update),
then the provisioned `OmaDmProvisionedDataType` values: 778 domain name
(skipped while it is the default "IMS"), 779 T1, 780 TF, 781 T2, 782 AMR-NB
mode set, 783 AMR-WB mode set, 784 session expiry, 785 Min-SE, 786
cancellation timer ("HVOLTE TVZW"), 787 Tdelay, 788 silent redial. Defaults
are -1 (skipped) for the integers and empty strings for 782/783 (sent as
`tag ##`). With nothing provisioned the menu is `777=1` plus the two empty
AMR items.

SET_HIDDEN_MENU_ITEM (0x0d36): `[u16 tag, u16 length, data padded to 100]`.
GET_HIDDEN_MENU_ITEM (0x0d37): the tag.

None of these carry a P-CSCF, domain, IMPI/IMPU or transport. The CP's IMS
stack reads IMPI, IMPU and the home domain from the ISIM itself (the service
only checks the ISIM domain isn't the placeholder "IMS",
`isValidIsimDomain`), and its SIP settings come from the CP's carrier
profile (the 0x4600 manifest), unless section 6 applies.

"VoLTE enabled", "SMS over IMS enabled": no request carries them at
registration. They become the offering type in ADD_PDN_INFO (VoLTE 1,
SMS-IP 2; `CapabilityManager`), and later SET_SELF_CAPABILITY
(`[u8 version 1, u16 feature, u32 mask, u32 extended mask, u64 delegate mask]`).

## 6. Carrier config: what reaches the CP

`sim_configuration_311.xml`, MNC 480 (Verizon; Tracfone-VZW matches it by
MCC/MNC, no MVNO override except Cellcom's GID). Keys there that change what
the CP sees or whether stock registers:

| Key | Verizon value | Effect |
| --- | --- | --- |
| `BLOCK_PDN_BY_INVALID_PCSCF` | 0 | no PDN block after a P-CSCF-less PDN; still no ADD_PDN |
| `SIP_USER_AGENT` | `#MANUFACTURE#---#MODEL#---#BUILD#` | hidden-menu tag 519 |
| `GEOLOCATION_PIDF_FOR_VOLTE_EMERGENCY_CALL` | 1 | tag 1045 |
| `IMS_SINGLE_REGISTRATION_REQUIRED` | 1 | RCS on the IMS registration (RCS off by default) |
| `SMS_FORMAT` | 1 (3GPP) | SMS over IMS format |
| `LTE_VOPS_POLICY`, `USE_VOPS_STATUS_ROAM` | 1, 0 | whether stock requests the IMS PDN without VoPS |
| `IMS_PDN_ACTIVATION_TIMEOUT`, `NR_TIMER_WAIT_IMS_REGISTRATION` | 120, 120 | timers that end in SET_PDN_EST_STATUS 2 |
| `ALLOWED_RAT` | LTE, LTE_CA, NR, IWLAN | |
| `DATA_CALL_PERMANENT_FAILURE_FOR_IMS` | causes 0x8, 0x1B-0x1D, 0x20, 0x23, 0x32, 0x33 | PDN causes that stop IMS on cellular |

The CP IMS configuration menu (`HiddenMenuBuilder.CpImsConfiguration`: SIP
port tag 10, registration expiry 11, retry timers 20/21, T1/T2/T4 534-536,
timers B-J, preferred transport 1049, IPsec 15/16 and 1031, phone-context
1025, URI type 1026, MTUs 1028/1029, GRUU 1046, reg-event 1047/1048, codecs
258 and 1060-1062, ...) is sent only when
`CarrierConfigManagerReceiver.isSupportAospImsConfiguration` holds: the
carrier config key `vendor.ims.carrier_config_use_aosp_ims_config_bool` (or a
persist property) and `UPDATE_IMSCONFIG_BY_CARRIERCONFIG`. Values come from
the `vendor.ims.*`/AOSP IMS keys. Whether Verizon's CarrierSettings sets the
key wasn't checked here (the decoded CarrierSettings in
MODEM-PROVIDER-PROFILES.md is the place). Without it the CP uses its own
carrier profile for all of these, which is the profile the 0x4600 manifest
selects (`us_tracfone`).

## 7. Status 5 and the other registration values

`RilIndRegistration.update`: `u8 state, u8 feature, u32 feature mask, u16
status, u16 URI length (≤1000), u16 reason length (≤256), URI + reason text,
[u32 feature mask ext], [u64 SIP delegate mask], [u16 feature ext]`. Our
`record_registration` reads the same fields.

States (`RegState`): 1 VoLTE not registered, 2 VoLTE registered, 3 VoLTE
limited, 4 E911 not registered, 5 E911 registered, 6 RCS not registered, 7 RCS
registered, 8 E911 pseudo-registered. Features (`RegFeature`): 0 unknown, 1
VoLTE, 2 SMS-IP, 3 RCS, 4 PSVT.

Status (`RegistrationReason`, its CP reason; ImsReasonInfo code, extra):

| Status | Name | Code / extra | Stock reaction |
| --- | --- | --- | --- |
| 0 | REGISTER_SUCCESS | 132 | |
| 1 | DEREGISTER_FEATURE_MISMATCH | 132 | |
| 2 | DEREGISTER_NETWORK_TRIGGERED | 132 / 1513 | keep waiting |
| 3 | DEREGISTER_NO_RESP_FROM_NETWORK | 132 / 1503 | PDN torn down |
| 4 | DEREGISTER_INTERNAL | 132 / 131 | |
| **5** | **REGISTER_FAIL** | **1000 / 61442** | **PDN torn down (`isNeedPdnDeactivationReason`); not a CP retry reason** |
| 6 | REGISTER_FAIL_500 | 1000 / 352 | |
| 7 | REGISTER_FAIL_403 | 1000 / 332 | CP retries; PDN down unless 403 retry applies |
| 8 | REGISTER_FAIL_RETRY | 1000 / 61441 | CP retries, keep waiting |
| 9 | REGISTER_LIMITED | 132 / 121 | SMS-IP feature cleared |
| 10 | FAIL_TRY_AFTER_CELL_CHANGE | 1000 / 61442 | |
| 11 | FAIL_PLMN_BARR | 132 / 1000 | keep waiting |
| 12 | FAIL_FRESH_REG_START | 132 / 1000 | keep waiting |
| 13 | DEREGISTER_FAIL_ONGOING_CALL | 1000 | |
| 14 | FAIL_START_TIMER | | |
| 15 | FAIL_TRY_AFTER_WIFI_REASSOCIATE | 1000 | |
| 16 | FAIL_TRY_AFTER_RAT_CHANGE | 132 | |
| 18 | FAIL_SILENT_RETRY_FOR_CALL | 132 | |
| 254 | FAIL_NO_VALID_SIM | 1000 / 1501 | |
| 512 | RETRY_AFTER_PLMN_CHANGE | 132 / 1000 | |
| 255 | unspecified | | |

Status 5 arriving immediately after ADD_PDN, with no SIP exchange in
between, fits a stack with no P-CSCF to send REGISTER to: the CP gives up
for that PDN at once. A SIP failure would come back as 6, 7 or 8 after
seconds, usually with reason text.

## 8. Requests the AP owes the CP

- **No AP-answered identity requests.** The CP never asks the service for
  IMEI/IMEISV; the IMEISV only goes into the user agent if the template has
  `#IMEISV#` (Verizon's doesn't). `RILC_REQ_IMS_SIM_AUTH` and
  `GET_GBA_AUTH` are AP-to-CP requests for XCAP/GBA, not something the CP
  waits for.
- **Time:** AIMS_SET_FRAME_TIME operation 2 with the wall clock, right after
  stack start. We don't send it (0x0d0b isn't on `sit.py`'s allow-list).
  Registration doesn't obviously depend on it (T-Mobile registered without
  it), but it is the one start-up handshake we skip.
- **Carrier-config handshake:** the 0x4601 status before stack start; done
  since 0.3.19.
- **Location/country:** only for Wi-Fi registration (ADD_PDN's Wi-Fi fields,
  AIMS_SET_GEO_LOCATION_INFO for emergency); nothing on cellular.

## 9. omamobile-modem-sit 0.3.20 (implemented, uncommitted, tested offline)

- `data_call.setup_payload(..., ims=True, ip_type=...)`: the IMS bearer's PDP
  type and P-CSCF request now follow `ip_type` (0xda = IP type, 0xdb =
  `PCSCF_REQUEST`: IPv6 2, IPv4v6 3). `ip_type=None` keeps 0.3.19's IPv6/2.
- `bringup.ims_ip_type`: the IMS bearer uses the home IP type of the
  `[profiles]` entry with the `ims` type for `ims_apn` (read only), else IPv6.
  With the Verizon example profile (`2 = IMS; types=ia,ims; ip=ipv4v6;
  roaming_ip=ipv6`) the IMS setup becomes PDP type 3 with P-CSCF request 3,
  the same as the attach on that APN and as stock asks for Verizon's IMS APN
  at home. T-Mobile (no such profile) is unchanged.
- `ims.add_pdn_payload`: IP type from the bearer's addresses (stock's
  `getIpType`), so an IPv4v6 bearer is announced with its IPv4 address,
  IPv4 P-CSCFs (at 39) and IPv4 DNS. An IPv6 bearer gives the same bytes as
  0.3.19 (tested). The empty-list path stays behind `ims_pcscf_required = no`,
  now documented as something stock never does.
- `ims.oma_dm_menu` sent before ADD_PDN: `00 06 00 | 09 03 01 00 00 00`
  (tag 777 = 1). Stock's empty AMR items 782/783 are left out on purpose.
- ISIM name resolution adds stock's path: the **internet bearer's own DNS
  servers** (from its setup response, bound to its IPv6 address), after the
  IMS bearer and before the host resolver
  (`bringup.resolve_default_network`). The host resolver may be the USB
  link to the laptop, which is not what stock would ask.
- IND_AIMS_REGISTRATION is logged with the state and status names.
- `packages/omamobile-modem-sit/test/all` passes (unit tests and the RIL
  against `tools/sit-sim`).

## 10. Ranked changes and runbook

| # | Change | Why | Risk |
| --- | --- | --- | --- |
| 0 | **Read stock's answer first** (human's call: needs a stock boot of slot A, and then a fresh read-only NV backup per AGENTS.md). With this SIM on stock, `adb logcat -b all` filtered for `ShannonIms`/`SLogger`: "Sending AddPdn Info IpType [...]", "P-CSCF address of LinkProperties is invalid. Use P-CSCF address received from SIM", "P-CSCF Address:", "stop registration for invalid pcscf", "pcscf-ip-address-6-num". Tells whether Verizon's PCO carries the P-CSCF on stock and whether the SIM name resolves | removes guessing | stock boot: medium (rewrites `efs`/`persist`/`modem_userdata`) |
| 1 | Set `ims_pcscf_required = yes` on the phone (the package default) | an empty list gets status 5 by construction; stock never sends it | none |
| 2 | 0.3.20: IMS bearer IPv4v6 from the IMS profile (SETUP_DATA_CALL `0xda=3, 0xdb=3`), and ADD_PDN with IP type 3 | matches stock's request on Verizon's IPv4v6 IMS APN, which is also the attach APN (attach already asks 3/3); a mismatched IPv6-only request on the attach PDN's APN may be why the CP reports no PCO P-CSCF | medium: changes the IMS bearer request on Verizon only |
| 3 | 0.3.20: resolve the ISIM's FQDN through the internet bearer's DNS | stock's `getPcscfAddressFromSim` path | low (DNS queries only) |
| 4 | 0.3.20: OMA-DM menu (777 = 1) before ADD_PDN | stock always sends it; a Verizon-profile CP may expect it | low |
| 5 | Log what the CP sends after attach: P-CSCF family/counts of every entry of GET_DATA_CALL_LIST (not only CID 2), and IND_PCO_DATA (0x060d) container IDs and lengths only | shows whether the attach PDN's PCO has a P-CSCF the CID 2 response drops | none (read-only) |
| 6 | AIMS_SET_FRAME_TIME `00 02 <u64 ms LE>` after STACK_START (needs 0x0d0b on the allow-list: maintainer's call) | stock's start-up handshake | low |
| 7 | Verizon user agent `Google---Pixel 7 Pro---<build>` in tag 519 | Verizon's template; matters only once SIP REGISTER goes out | low |
| 8 | Hidden-menu part 2 (video media) and XCAPM_START | completeness; not needed for registration | low |

Runbook for 0.3.20 on the phone (human approves each step; no reboot needed
beyond restarting the service, which the phone's owner should know about):

1. Read-only: confirm `[profiles]` has the IMS entry with `ip=ipv4v6` and
   `ims_pcscf_required = yes` in `/etc/omamobile/modem-sit.conf`.
   Pass: both present. Stop: no IMS profile (0.3.20 then behaves as 0.3.19).
2. Install 0.3.20 (`tools/phone-install-package` from this worktree), restart
   `omamobile-sitd` after an IMS-free boot (the daemon refuses a second IMS
   attempt in one boot). Expect in the journal: "IMS bearer PDP type ipv4v6",
   "data-call status 0 ... PDP type 3", "P-CSCF count IPv4 n IPv6 m".
   Pass: a count above 0, ADD_PDN sent, then IND_AIMS_REGISTRATION state 2.
   Stop: setup status non-zero, or counts 0 and the ISIM name unresolved
   (ADD_PDN is then not sent; no status 5). Rollback: reinstall 0.3.19.
   Risk: medium (new IMS bearer request; internet bearer untouched).
3. If counts stay 0: change 5 (logging), then step 0.

## 11. omamobile-modem-sit 0.3.21: stock's attach on a Verizon network

What stock did with a Verizon-network SIM (logcat, 2026-11-02, VoLTE
working): its RIL sent **no SET_INITIAL_ATTACH_APN for the SIM's slot** (the
only one was `null`, for the empty second slot), only SET_DATA_PROFILE; the
carrier manifest was applied; the modem attached with the manifest's settings
and listed the **attach bearer unsolicited** in IND_DATA_CALL_LIST_CHANGED
(CID 2, IPv6, QCI 5, three IPv6 P-CSCF, two IPv6 DNS); ShannonIms sent
ADD_PDN_INFO for it (IP type IPv6, its address and P-CSCFs) and registered.
0.3.20 sends an explicit attach APN, runs its own IMS setup (CID 2, no
P-CSCF) and saw no attach bearer listed: most likely our attach APN replaces
the manifest's attach and its P-CSCF request.

0.3.21 (tested offline):

- `[network] attach_apn = none`: no 0x0603; profiles and the internet bearer
  as before.
- After registration (attach_apn = none, IMS on): up to 20 s for an active
  IPv6/IPv4v6 bearer sitd didn't set up with a P-CSCF, from
  GET_DATA_CALL_LIST and the latest IND_DATA_CALL_LIST_CHANGED; each list is
  logged as CID, type, status, active, P-CSCF and DNS counts. Every bearer
  listed then is recorded as **modem-owned** (`modem-owned-bearers.json` in
  the run directory): `activate()` accepts it beside its own, never sets up
  its CID, and `deactivate()` refuses it.
- Found: no IMS setup of ours; ADD_PDN_INFO from the attach bearer's item
  (checked against a fresh list right before: still listed, active, same
  IPv6 address). Not found: one more look after the stack start, then
  0.3.20's path (own IMS bearer, ISIM fallback). With an explicit
  attach_apn the one look happens too, without recording unknown bearers.
- Not confirmed: that GET_DATA_CALL_LIST items carry the P-CSCF at the same
  offsets as the setup response (stock's `FillDataCallListFromModemPayload`
  reads both with one item decoder, per MODEM-SIT-RESEARCH §3.5, confidence
  low for the v11 item); that the 239-292-byte items keep the 234-byte
  item's extension at 0x84; and that the modem lists the attach bearer at
  all when no attach APN is sent. If the list item has no P-CSCF but the
  indication's has, the indication's item is used.

Runbook (human approves each step; changing the config needs a fresh CP, so
a reboot, which is the owner's call):

1. Read-only: `grep -E '^(apn|attach_apn|ims_apn|carrier_manifest) ='
   /etc/omamobile/modem-sit.conf`. Pass: carrier_manifest set, IMS profile
   present. Stop: no manifest (none without it is untested).
2. Install 0.3.21, set `attach_apn = none`, `ims_apn = IMS`, reboot.
   Expect: "initial attach APN not sent", "Radio on after carrier config",
   "data-call list: 1 item(s); CID 2 IPv6 ... P-CSCF 3 ...", "modem-owned
   attach bearer for IMS", internet "data-call status 0 CID 1", "IMS on the
   modem-owned attach bearer CID 2", IND_AIMS_REGISTRATION state 2.
   Pass: IMS registered with voice and SMS. Stop: no registration in
   `register_timeout`, or every internet setup answered 36. Rollback:
   `attach_apn = IMS` (0.3.20's setting) and reboot. Risk: medium (changes
   the attach; the internet bearer and NV untouched).

