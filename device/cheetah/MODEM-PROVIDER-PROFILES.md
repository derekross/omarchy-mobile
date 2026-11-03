# Provider profiles, APNs and the stock bring-up order (cheetah, S5300)

Status (2026-11-02, offline research, nothing run): what stock Android does
for a SIM from modem boot to IMS registration, where its APN and carrier
data comes from, what our RIL (`omamobile-modem-sit`) does differently, and a
design for doing it the stock way on every carrier. Sources: the owner's
factory image (read on the laptop, never committed), libsitril and the SIT
stream library (function names and offsets), Shannon's IMS service APK
(class and key names), Google's CarrierSettings protobufs and the modem's
carrier-config database. Only field names and short values such as APN
names are quoted. Confidence is given per finding.

## 1. Two separate carrier databases

Stock keeps carrier data in two places, read by two different consumers.

| | AP side: CarrierSettings | CP side: modem carrier config |
|---|---|---|
| Files | `product/etc/CarrierSettings/*.pb` (about 620 files) and `carrier_list.pb` | `vendor/firmware/carrierconfig/`: `cfg.db`, `manifests/`, `confseqs/` |
| Format | protobuf, one file per carrier (`<name>_<country>.pb`) | SQLite (matching) plus protobuf manifests and configuration sequences |
| Matched by | `carrier_list.pb`: MCC/MNC plus optional GID1, SPN, IMSI prefix | `cfg.db` `carrier_info`: MCC/MNC plus GID1, GID2, SPN, IMSI and ICCID patterns, ranked |
| Holds | APNs with types, protocols, bearers, profile IDs; Android carrier config keys (IMS settings, SIP domain, signal thresholds, 5G icons ...) | NV settings for the modem: hashed NV item IDs and values (protocol timers, CA/ENDC band combinations, SRS, PLMN mapping, carrier-specific items) |
| Consumer | Android telephony (DataProfileManager, ImsService via CarrierConfigManager) | the CP, through `OEM_SET_CARRIER_CONFIG_MANIFEST` (0x4600) and rfsd |

**APNs are only on the AP side.** The modem's manifests and confseqs carry
no APN strings: they are NV item settings (`confseqs` decode as protobuf:
version, name such as `vzw.sim1`, then repeated `{hashed item ID, value}`).
Confidence high.

### 1.1 This SIM's entries

- **AP (CarrierSettings):** `carrier_list.pb` maps the SIM's MVNO GID1 on
  the Verizon codes to `tracfoneverizon_us`. Its APN list is identical to
  `verizon_us` (decoded, field by field):

  | APN | types | bearers | protocol (home/roaming) | profile ID | modem-cognitive |
  |---|---|---|---|---|---|
  | `internet` | default, mms, supl, dun, fota, cbs | CDMA/EVDO only | IPv4v6 | - | - |
  | `VZWINTERNET` | default, supl, dun | GSM/UMTS/LTE/IWLAN/NR | IPv4v6 | 0 | yes |
  | `VZWADMIN` | fota | as above | IPv4v6 | 3 | yes |
  | `IMS` | **ia**, ims | LTE, IWLAN, NR | IPv4v6 / IPv6 | 2 | yes |
  | `VZWAPP` | cbs, mms | as above | IPv4v6 | 4 | yes |
  | `VZWEMERGENCY` | emergency | - | IPv4v6 / IPv6 | - | - |

  So stock's **initial attach APN is `IMS`** (the `ia` type), not `vzwims`,
  and the internet APN is `VZWINTERNET`. The carrier config also sets the
  IMS phone-context domain to the carrier's IMS domain and the usual
  Verizon IMS keys.
- **CP (cfg.db):** the same GID1 ranks `Tracfone-VZW` (carrier ID 10008,
  manifest `us_tracfone`) above plain Verizon (1839, `us_vzw`). The two
  manifests share 32 configuration sequences. `us_tracfone` adds
  `tracfone.sim1/sim2` (one NV item each) and drops `vzw-only.sim1/sim2/
  multislot` and `vzw-0x18F.sim1/sim2` (Verizon-only timers and items).
  Neither contains APNs.

## 2. The stock bring-up order

From libsitril's start-up hooks (MODEM-SIT-RESEARCH section 4), the IMS
service's state names and AOSP telephony's behaviour. Order across services
is inferred, not captured (a stock radio log would settle it).

1. **CP online** (cbd, rfsd). rild opens IPC0.
2. **Radio available** (`MiscService::OnRadioAvailable` and friends):
   SET_DEBUG_TRACE off, SET_MODEM_CONFIG, SET_LOGICAL_TO_PHYSICAL_SLOT_MAPPING,
   SET_SGC (`persist.vendor.radio.sgc`), the software version, SET_DEVICE_INFO,
   SET_AP_SYSTEM_TIME; `PsService::OnRadioAvailable` re-applies the stored
   initial attach APN; `NetworkService::OnRadioAvailable` sends
   **SET_RADIO_POWER on** (unless airplane mode). The radio is turned on
   once and stays on.
3. **SIM loads.** The CP sends `OEM_IND_CARRIER_CONFIG_SIM_INFO` (0x4602).
   `MiscService::OnOemCpCarrierConfigSimInfoInd` (0x137c90) queues
   `DoOemSetCpCarrierConfig` (0x137ed0): it matches the SIM in `cfg.db` and
   sends 0x4600 (directory string `/vendor/firmware/carrierconfig`, the
   manifest ID decoded from hex; built by
   `ProtocolMiscBuilder::BuildSetCpCarrierConfig`). Stock never sends 0x4600
   unprompted.
4. **The CP applies the profile** and answers `OEM_IND_CARRIER_CONFIG_STATUS`
   (0x4601, status and cause). `OnOemCpCarrierConfigStatusInd` (0x138e70)
   logs it and forwards it to the IMS service (`RilIndCpCarrierConfigChanged`,
   `MANIFEST_UPDATED` / `MANIFEST_NOT_UPDATED`). The selection is kept in
   `persist.vendor.radio.config.carrier_id` on the AP and, on the CP, in its
   NV.
5. **When a profile changes NV, the CP asks for a reset.** libsitril's
   `PhoneResetHandler` handles `IND_PHONE_RESET` (0x0804) with reasons
   including `GCONFIG`, `DEFAULT CONFIG`, `SGC CHANGE`, `UPDATE RSP`, `SIM`,
   `RADIO POWER`, and sends a device reset request. On stock the reset is a
   CP restart with the new NV in place; on the next start the manifest
   matches what NV holds and no reset is needed. (Confidence medium: the
   reasons and the handler are certain, the exact trigger after a manifest
   change is inferred.)
6. **Android telephony, after the carrier config is loaded:** the initial
   attach APN (`ia`: `IMS`) with SET_INITIAL_ATTACH_APN; **every
   modem-cognitive data profile** (IDs 0, 2, 3, 4 above) with
   SET_DATA_PROFILE; the preferred network type bitmap; data allowed
   (SET_PS_SERVICE / mobile data). Setup data calls follow as Android needs
   them: IMS first (by the IMS service), internet when mobile data is on.
7. **IMS:** the IMS service holds its stack start
   (`mImsStackStartBlocked`, "IMS stack start has been blocked during
   Carrier Config Manifest") until step 4 has reported, then
   AIMS_STACK_START_REQ, the IMS PDN (on Verizon: the attach PDN, APN `IMS`),
   AIMS_ADD_PDN_INFO with the P-CSCF list (from the PCO, with the ISIM's
   EF_PCSCF added: `addPcscfFromSim`, `getIsimPcscf`), and the modem's IMS
   stack registers. For this network the IMS service's own config
   (`sim_configuration_311.xml`, MNC 480) does not block the PDN on a
   missing P-CSCF (`BLOCK_PDN_BY_INVALID_PCSCF` 0) and requires a single
   registration.

## 3. What ours does differently (0.3.14)

| Step | Stock | omamobile-modem-sit |
|---|---|---|
| Radio | on once, stays on | AT+CFUN=0, attach APN, data profile, AT+CFUN=1: a radio cycle at every start |
| Carrier profile | 0x4600 on 0x4602, then a CP reset if NV changed | none by default; `carrier_manifest` sends it, but nothing handles the reset request, and a reset can't be done in place (it needs a reboot, which discards the NV RAM copy and with it the profile) |
| Attach APN | the `ia` APN from CarrierSettings (`IMS`) | `attach_apn` by hand (`vzwims` tonight) |
| Data profiles | every modem-cognitive profile with its profile ID | one default profile (ID 0) |
| NR | per carrier config | SET_NR_MODE 3 -> 0 **after** registration, which can make the CP re-register |
| IMS stack start | after the carrier-config status | immediately (0.3.14: waits only when `carrier_manifest` is set) |
| P-CSCF | PCO, plus the ISIM | PCO only; empty on this network |
| NV | persistent | a RAM copy of the backup, dropped at stop: every boot starts from the same old state |

0.3.15 (built offline, not yet run on a phone) takes three rows to stock's
way: it reads the radio state (AT+CFUN?) and sends the attach APN, every
profile in the new `[profiles]` section (profile 0 from `apn` unless
`[profiles]` has its own) and NR mode 0 before radio on, switching the radio
on once and never off; it logs IND_PHONE_RESET's first payload bytes raw and
the time from radio on to the first packet registration.

## 4. Why registration takes minutes

In order of likely weight:

1. **The NV RAM copy is the backup's state at every boot.** The CP keeps its
   acquisition data (recent PLMNs, bands, cells) and the carrier profile in
   NV. Ours starts each boot from the same backup, taken without this SIM,
   so the CP does a cold search every time, with whatever carrier profile
   the backup holds (not Verizon's). Stock's first boot with a new SIM is
   slow too; every later boot starts from the last cell. Confidence medium
   (the acquisition database's location is not read; the behaviour fits
   34 s to 10+ min with the same cell).
2. **The radio cycle and the late NR change.** AT+CFUN=0/1 at start and
   SET_NR_MODE after registration both make the CP search or re-register;
   stock does neither at start.
3. **A profile mismatch.** Without Verizon's NV settings the CP runs a
   generic profile; after the Tracfone manifest the CP applied it (status 1)
   and stopped searching (CEREG 0,0), consistent with it waiting for the
   reset of step 2.5 that sitd never answered (0x0804 is not logged yet).
4. **IND_REG_FAILED cause 10 after the data permission** (seen on both
   phones): the network detaches the phone once around the first data
   setup; the settle wait of 0.3.8 rides it out, but each costs a re-attach.

## 5. IMS on this network

- **The PDN:** IMS runs on the attach PDN (APN `IMS`, types `ia` and `ims`).
  A second IMS setup on the same APN returns that PDN.
- **The P-CSCF:** Verizon delivers it in the PCO of the IMS PDN when the UE
  asks for it; whether the CP asks, and in which PCO containers, is CP
  configuration (the carrier profile). With the generic profile the PCO
  comes back without it, even with the P-CSCF request bit set in our attach
  (0.3.11). The ISIM's EF_PCSCF is stock's second source.
- **What is missing, most likely:** the carrier profile in effect on the CP
  (step 2.3-2.5). Without it the CP's IMS stack has no carrier settings, and
  ADD_PDN with an empty P-CSCF list was accepted but never led to a
  registration (0.3.13).

## 6. Design for Omarchy Mobile (every carrier)

**Data sources (all from the owner's own factory image, extracted on the
laptop like the vendor chroot, never hosted or committed):**

- AP: CarrierSettings protobufs, read with a small decoder for the fields we
  use (APN name, types, protocols, bearer bitmask, profile ID,
  modem-cognitive; a handful of carrier config keys). This is the database
  stock uses; it has the `ia` APN for each carrier.
- CP: `vendor/firmware/carrierconfig` in the modem chroot (0.3.14's
  extractor already copies it).
- Fallback where the image has no entry: mobile-broadband-provider-info
  (no `ia` types, so its attach APN is a guess), then a small override file
  in the package, then the user's own setting.

**Matching, with minimal identity handling:** MCC/MNC, GID1 and SPN are what
both databases match on. Read them once, in sitd, keep only those fields in
memory, log only the matched carrier names. Options: GET_IMSI's first 5-6
digits plus GID1 through SIM I/O, or the CP's 0x4602 (which carries them, but
also full identities). This needs the maintainer's decision; until then the
carrier can be chosen by hand (the 0.3.14 `carrier_manifest` setting, and the
same for the CarrierSettings name).

**Order (stock's):**

1. CP online. Radio stays off.
2. Wait for 0x4602; answer with the CP manifest; wait for 0x4601.
3. If the CP asks for a reset (0x0804): this needs NV persistence (below).
4. SET_INITIAL_ATTACH_APN with the `ia` APN; SET_DATA_PROFILE with every
   modem-cognitive profile and its profile ID; preferred network type and NR
   mode **before** radio on.
5. Radio on, once. Wait for registration.
6. Data permission, settle, internet bearer.
7. AIMS stack start, IMS bearer (the attach PDN where `ia` = `ims`), ADD_PDN
   with PCO P-CSCFs, else the ISIM's.

**NV persistence: the decision this hinges on.** Stock's carrier profile and
acquisition data live in NV. Our profile works on a RAM copy that is dropped
at stop, which keeps the partitions safe but makes every boot a first boot
with the backup's carrier. Options, for the maintainer:

- (a) Keep RAM-only and seed NV from a stock boot with the SIM in: boot
  stock once with this SIM, let it register and apply the profile, take a
  fresh read-only backup (AGENTS.md section 1), update `modem-nv.sha256`.
  The RAM copy then starts every boot with Verizon's profile and a recent
  cell. No new write path; repeat per SIM change.
- (b) A persistent copy of the modem's NV kept off the partitions (for
  example under /var/lib), checksum-verified like the RAM copy, so the CP's
  changes survive reboots. The partitions are still never written; it
  changes the "loses what the modem writes" rule.
- (c) Never apply a profile and live with the generic one: no IMS on
  networks that need their profile.

**Where PR #373 fits:** its carrier lookup (MCC/MNC from GET_IMSI into
mobile-broadband-provider-info plus overrides) is the fallback layer above,
and its Mobile network page is the place to show and override the matched
carrier. Changes it needs: read CarrierSettings first (it has the `ia` APN:
`IMS` for Verizon, where the override guesses `vzwims`); send every
modem-cognitive profile, not only the default; match on GID1 too (MVNOs on
shared codes, as here); and order the requests as above.

## 7. Next steps, by expected gain

1. **Seed NV from a stock boot with the SIM** (option a) and boot ours
   without a manifest or radio cycle changes: tests whether registration
   gets fast and whether IMS registers once the CP carries the profile.
   Risk: medium (a stock boot rewrites efs, persist and modem_userdata; the
   backup and checksum steps of AGENTS.md section 1 are mandatory).
2. **Stock's order and APNs:** attach on `IMS` (not `vzwims`), all
   modem-cognitive profiles, NR mode set before radio on, no AT+CFUN cycle
   when the radio is already off at start. Risk: low.
3. **Handle and log 0x0804 (IND_PHONE_RESET)** with its type and reason, so
   the next manifest test shows whether the CP asked for a reset. Risk:
   none (logging only).
