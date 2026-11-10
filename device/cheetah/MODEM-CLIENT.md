<!-- SPDX-License-Identifier: MIT -->
# Modem client: the SIT RIL, its interface, and the user-facing path

Status (2026-10-25): **`omamobile-modem-sit` 0.3.3, built and tested
offline against `tools/sit-sim`.** On our phone, without a SIM: the
read-only probe (MODEM-PLAN M4.1h-M4.1k) and sitd behind the ModemManager
bridge (T1, 0.3.0). Nothing with a SIM yet: the first SIM test is
MODEM-PLAN's "M4.2-M4.7: the first SIM test"; section 1.4 says which SIM. The RIL is a port of a SIT stack that registered on LTE, made and
answered IMS calls with two-way audio, sent and received SMS and carried
LTE data **on this phone model** (Pixel 7 Pro, the same stock firmware
family, the same architecture: stock `cbd`/`rfsd` in a RAM-only chroot plus
a Python SIT client). Its owner permits the reuse; the copied files keep
their SPDX headers. Our 0.1 client was built from the protocol research only
and had never met real firmware; where the two disagree, the hardware-tested
layouts win (for example the data call: the stock 983-byte version-2 setup
request, the initial attach APN being essential, and the DNS offsets in the
setup response). The runtime it needs is `omamobile-modem`
([MODEM-PLAN.md](MODEM-PLAN.md) M3.4); the first runs on our phone are the
M4 runbook in MODEM-PLAN.md.

---

## Transport deadlines (0.3.34; offline validation only)

SIT transport waits use Linux `CLOCK_BOOTTIME`, which counts time spent
suspended. A request whose reply is observed at or after its deadline
raises `TimeoutError`, including when the reply was read before a scheduling
pause and processed afterwards. Indications encountered during a request
remain queued, and unread buffered packets remain available. A timeout does
not cancel a modem operation or prove that it did not execute; the transport
does not retransmit it. Token matching continues to reject old responses.

The socket tests hold `CLOCK_MONOTONIC` still and advance BOOTTIME across
real socket reads. They cover replies before, at and after the deadline,
a late modem error, indication retention and a pause after packet receipt.
These are host tests with a simulated clock jump, not a real suspend test.

`select()` still uses a relative wait: this change rechecks deadlines when
execution returns, but does not arrange a wake alarm or guarantee immediate
expiry on resume without socket activity. The modem sleep inhibitor stays
in place. CPIF/PCIe suspend, incoming-call/SMS wake, IMS continuity and
battery consumption still need attended hardware qualification under
[MODEM-PLAN](MODEM-PLAN.md) M6 and section 6.3.

Before promoting this package change, a device owner must run the existing
awake modem smoke/telephony checks on a qualified build and attach
`tools/phone-smoke` with its kernel release. Stop on lost registration,
missing indications or unexpected timeouts; retain logs with identifiers
removed and restore the previous package through the normal update path
with an approved reboot (never restart the modem in place). Risk: changed
request timeout classification. Do not bypass the sleep inhibitor to test
this patch; modem-on suspend remains a separate hardware gate.

## 1. What is built

Two packages:

| Package | What |
|---|---|
| `packages/omamobile-modem` 0.1.0 (new) | The runtime: `omamobile-modem.service` loads CPIF and runs the `modem` vendor-chroot profile (rfsd, then a one-shot cbd, on RAM copies of NV); `omamobile-modem-cp` (CP state, crash record, power-off for the unit's stop, the baseband version, the stock NV checksum); the M0.5 read-only udev rule |
| `packages/omamobile-modem-sit` 0.3.3 | The RIL: `omamobile-sitd` (registration, calls, SMS), `omamobile-sit-data` (the cellular route), `omamobile-sit` (CLI) |

`omamobile-modem-sit/lib/` (installed to `/usr/lib/omamobile-sit/`):

| File | Origin | What |
|---|---|---|
| `sit.py` | ported | The single-owner IPC0 transport: framing, token matching, indication queue (signal and physical-channel snapshots coalesced so telemetry can't crowd out an SMS reply). Two guards: the allow-list of requests this stack sends, and our do-not-send list (NV, identity, carrier lock, AT forwarding, VSIM, satellite) checked first, so an edit to the allow-list can't let one through. Dial and SMS sends need the owner's flags |
| `sit_names.py` | ours | The 602 message names, for logs |
| `bringup.py` | ported, carrier values moved to the config | The start-up order (section 1.1) |
| `carrier_apn.py` | ours | The SIM's carrier settings from its home network code (GET_IMSI's MCC/MNC, the rest dropped): the package's `apn-overrides.conf` first, then mobile-broadband-provider-info's `serviceproviders.xml`; the internet and attach APNs, `ims_apn`, `ims_first`, `internet_cid` and the data profiles, each only where `[network]` leaves it `auto` or empty (0.3.29, TELEPHONY-APPS-PLAN 7.6) |
| `omamobile-sit-config` | ours | The pkexec helper behind the shell's Mobile network page (polkit action `org.omamobile.modem-sit.configure`): `set apn\|attach_apn\|roaming` and `get`, nothing else in `modem-sit.conf`; an APN must be a plain carrier APN, and the file is rewritten atomically with its comments kept |
| `data_call.py` | ported, APN from the config | Setup (983 bytes; no PDU session ID on cellular, as stock), initial attach (251), data profile (246); bearer ownership recorded in RAM before each setup, never retried blindly |
| `ims.py` | ported (identity strings ours) | IMS stack start, hidden-menu configuration, ADD_PDN_INFO from the IMS bearer, the registration indication |
| `radio_settings.py` | ported | NR mode byte (3 -> 0 keeps LTE; the original kept in RAM) |
| `sms_codec.py` | ported | GSM 7-bit / UCS-2 SMS-SUBMIT with concatenation, SMS-DELIVER with the SMSC prefix the modem adds, WAP push kept as bytes |
| `calls.py`, `inbox.py` | ported | IMS dial/ring/status layouts; received SMS written and fsynced before the ACK |
| `voice_audio.py` | ported, card lookup ours | AoC call routes: PCM 4 playback (EP5), PCM 11 capture (EP4), `TDM_0_RX Mixer EP5`, `EP4 TX Mixer INTERNAL_MIC_TX`, mic gain 130 cB + 6 dB; every changed control restored at the end of the call |
| `service.py` | ported (app service), access and status ours | The daemon: one IPC0 owner for start-up, SMS and calls; the socket API (section 2); `state.json` |
| `data_network.py` | ported, resolved support ours | rmnet0's /32, metric-700 default route behind Wi-Fi, carrier DNS only while cellular is the only way out, dead-bearer detection |
| `at.py` | ported (fixed commands only) | `AT+CFUN=0/1` on `/dev/umts_router` for radio power during start-up (SIT radio state and AT CFUN were seen to disagree; the working sequence used AT) |
| `cp.py`, `paths.py` | ours | CP state ioctl; the one power-off path; paths and config |

Units (`systemd/`), none enabled by the package:

- `omamobile-sitd.service`: `Type=notify`, `Requires=`/`After=omamobile-modem.service`,
  `ExecStart=omamobile-sitd --bringup`, `Restart=no` (a second start-up on
  the same CP is not supported: reboot), `TimeoutStartSec=15min`.
- `omamobile-sit-data.service`: after the RIL is ready; `omamobile-sit data
  on|off` starts and stops it.
- `/usr/lib/NetworkManager/conf.d/90-omamobile-rmnet.conf`: `rmnet*` unmanaged.

Config: `/etc/omamobile/modem-sit.conf` (`[network] apn` is required; `ims`,
`ims_apn`, `ims_required` (default no: an IMS failure keeps data, 0.3.2),
`nr`, timeouts including `ims_timeout`; `[control] group`; `[audio] card`
(built-in default `none`; from 0.3.30 a device package's `[audio]` defaults in
`/usr/lib/omamobile/modem-sit.conf.d/*.conf` come first and `/etc` wins over them),
`mic_boost_db`).

Tests: `packages/omamobile-modem-sit/test/all` (about 10 s): 53 unit tests
(most ported with the code: transport, layouts, bearer lifecycle failure
cases, SMS codec, audio cleanup, the route watch), then three runs of the
real daemon against `tools/sit-sim`: start-up to IMS registration with the
request order checked, SMS both ways, a call through the CLI, no
identifiers in the logs; a rejected bearer ends start-up before any IMS
request; no APN means no radio command. `packages/omamobile-modem/test/all`
checks the CP helper's parsers on made-up inputs.

### 1.1 The start-up order (bringup.py)

What registered this phone model, kept as is:

1. Wait (`sim_timeout`, 120 s) for GET_SIM_STATUS to show the USIM
   application READY (type 2, state 5). Only card and application
   type/state are logged.
2. `AT+CFUN=0`; SET_INITIAL_ATTACH_APN with the APN; SET_DATA_PROFILE
   (default profile, the APN, enabled).
3. `AT+CFUN=1`; wait (`register_timeout`, 180 s) for GET_PS_REG_STATE home
   or roaming.
4. `nr = off` (default): NR mode 3 -> 0, then wait for registration on LTE
   (RAT 14). On this phone NR registered but carried no traffic; LTE did.
5. Internet bearer: CID 1 (rmnet0), IPv4v6, a fresh PDU session.
6. IMS (`ims = yes`): stack start, the IMS bearer (CID 2, IPv6, P-CSCF
   requested), hidden-menu settings, ADD_PDN_INFO; wait for an IMS
   registration with voice and SMS (state 2, features 3). SMS and voice need
   IMS on LTE-only carriers.

SMS received during start-up are stored and acknowledged; calls are never
auto-answered. Any failed or uncertain step up to the internet bearer ends
start-up: the service exits, the modem stays up, nothing is retried. A SIM
whose PIN, PUK or network lock holds for 10 s ends it at once with what to
do (0.3.1). From 0.3.2 a failed IMS step leaves the service running with
data only (status `ims: failed`; calls and SMS refused until a later
registration indication), unless `ims_required = yes`.

### 1.2 Safety

- **No NV writes from Linux, by construction.** The RIL speaks only SIT on
  `umts_ipc0` and fixed AT on `umts_router`; there is no raw-request path.
  NV lives in rfsd's RAM copies (MODEM-PLAN M3).
- **No identity reads, but one.** GET_IMEI, SIM I/O, PIN and APDU requests
  are not on the allow-list; GET_IMEI/IMEISV are on the do-not-send list too.
  From 0.3.29 GET_IMSI is, sent once at start-up when any of `[network]`
  `apn`, `attach_apn`, `ims_apn`, `ims_first` or `internet_cid` is `auto`
  or empty. Those are the shipped defaults, so by default it is sent at
  every boot, and typing `apn` and `attach_apn` alone still sends it (for
  the bearer order); only typing all five reads no IMSI. Only its MCC/MNC
  is used, to choose the APNs, the bearer order and the data profiles
  (`carrier_apn.py`, TELEPHONY-APPS-PLAN 7.6); the IMSI is never logged,
  stored or published, and the simulator tests fail if it reaches the log.
- **Logs.** Requests by name and status code; SIM card/app state; data-call
  status/CID/type; IMS registration state/features. Never numbers, message
  text, addresses or the IMSI. The simulator tests fail if a number or a
  message appears in the daemon's log.
- **Outgoing SMS** carry a durable 32-hex request id; an interrupted or
  uncertain send is marked `unknown`, never repeated automatically.
- **Calls**: a hangup whose release isn't confirmed within 12 s, or a call
  left over from a previous run, turns the radio off (best effort, AT+CFUN=0)
  and stops sitd with the call still recorded as its own, for an attended
  reboot. The journal says "Call release not confirmed: <reason>", the radio
  and CP states, and "attended reboot required". The RIL no longer stops the
  modem unit or powers the CP off: an in-place power-off reset the 9a once,
  and on the 7 Pro every power-off costs a UFS error-handler pass. The unit
  has `Restart=no`, so a manual restart in the same boot finds the recorded
  call, turns the radio off again and exits. This path has run only in the
  simulator.
- **Storage**: received SMS in `/var/lib/omamobile-sit` (0700, files 0600):
  numbers and text, never to be copied into the repository.

### 1.3 Known gaps

| Gap | Effect |
|---|---|
| Call audio | On by default on the Pixel 7 Pro from `omamobile-modem-sit` 0.3.30 with `omamobile-device-cheetah` 0.1.44 (its `/usr/lib/omamobile/modem-sit.conf.d/50-cheetah.conf` sets `card = auto`), each call in the protection service's earpiece mode and refused without it (the call goes on silent); `none` on phones whose device package sets nothing (from 0.3.3 to 0.3.29 the default was `none` everywhere) |
| Speakerphone | Not routed; calls use the stock voice path (EP5 to TDM 0) |
| Call waiting, conference, emergency and short codes, MMS download | Refused or not implemented (emergency numbers are refused by the dialer check: **this phone cannot call emergency services under Linux**) |
| Signal strength | Reported as 0 |
| Operator name | GET_OPERATOR decoded with the research note's layout, display only, not yet seen on hardware |
| IPv6 on rmnet0 | The bearer is IPv4v6 but only IPv4 is configured |
| Warm CP restart | None: about one fresh start in twenty crashed during registration on this phone model; the crash is recorded and the phone needs a reboot |
| Carrier values | The IMS hidden-menu items and IMS PDN layout are the ones that registered on a T-Mobile-network MVNO; other carriers may need different values |
| Suspend with the modem on | Not handled (CPIF's suspend refusal, the pull on cp2ap-wakeup, the receive-ring check after link wake: MODEM-PLAN 6) |
| SIM PIN entry, the eSIM | None: take the PIN lock off in another phone; the RIL speaks only to the physical slot (`umts_ipc0`; `umts_ipc1` is the eSIM's) |

### 1.4 Which SIM for the first test

What the repository can justify, for a temporary US prepaid SIM:

- **A physical nano-SIM on the T-Mobile network** (T-Mobile's own prepaid
  or an MVNO that uses its network). The IMS values this RIL sends
  (hidden-menu items, the ADD_PDN_INFO layout) are the ones that
  registered this phone model, with calls, SMS and data, on a
  T-Mobile-network MVNO (1.3, "Carrier values"). No other network has
  been tried with them. Not verified: that T-Mobile's own prepaid
  behaves as that MVNO did, and which IP type its internet bearer gets.
- **Why IMS decides it:** on LTE-only networks SMS and voice go over IMS
  (1.1, step 6), and most networks have no 2G/3G left to fall back to
  (ROADMAP section 2, "Calls"). Without IMS registration the phone gets
  data at best. Since 0.3.2 an IMS failure still leaves data running, so
  another network can still pass SIM detection, registration and data
  (the attach APN and data profile are the generic 3GPP requests);
  its IMS, SMS and calls are unverified and likely need other values.
- **IPv4 on the internet bearer.** rmnet0 is configured IPv4 only (1.3);
  a bearer that comes back IPv6-only fails MODEM-PLAN S8 until that gap
  is closed. Prefer a plan whose APN is documented as IPv4 or IPv4v6.
- **Physical, not eSIM;** PIN lock off (or turned off in another phone);
  a plan with voice, SMS and data.

Write down, off the repository (TELEPHONY-APPS-PLAN Q8): the internet APN
exactly as published and its IP type if stated; the MMS APN, MMSC and
proxy (for T3); the IMS APN if the carrier names one (the default is
`ims`); the SIM's PIN and PUK; the phone number; the activation steps.

---

## 2. The socket API (`/run/omamobile-sit/socket`)

A stream Unix socket; one JSON object per line each way. Root and members
of `[control] group` (default `wheel`, checked with `SO_PEERCRED`) may
connect. Replies are `{"ok": true, "result": ...}` or `{"ok": false,
"error": "..."}`; errors from wire data never carry raw values.

| Request | Result |
|---|---|
| `{"action": "status"}` | `modem` (`stage`, `registration`, `tech`, `operator`, `plmn`, `operator_name`, `voice`, `sms`, `data`; from 0.3.0 also `radio` on/off/unavailable, `sim` (`state` absent/detected/pin/puk/network-locked/ready/error, PIN and PUK retries; never an AID, label, ICCID or IMSI) and `emergency_numbers`), `calls` (id, number, direction, state, reason), `sms` (`received`: the IDs not yet deleted), `audio` (running, mute) |
| `{"action": "subscribe"}` (0.3.0) | `{"subscribed": true}`, then the connection stays open: `{"event": "status", "status": {...}}` (the status above) at once and after every change. At most 8 subscribers; one that stops reading is dropped and resynchronises by reconnecting. `omamobile-mmd` is its client |
| `{"action": "dial", "number": "+1..."}` | `{"call": id}`; needs IMS voice registration; international form |
| `{"action": "accept"\|"hangup"\|"delete-call", "id": ...}` | `{}` |
| `{"action": "dtmf", "id": ..., "keys": "12#"}` | `{}` |
| `{"action": "audio", "what": "mute", "value": "on"\|"off"}` | the audio state |
| `{"action": "sms-send", "request_id": <32 hex>, "number": ..., "text": ...}` | `state` sent/failed/unknown; the same id never sends twice |
| `{"action": "sms-status", "request_id": ...}`, `{"action": "sms-list"}`, `{"action": "sms-delete", "id": ...}` | |
| `{"action": "screen-state", "on": bool}` | SIT screen state and the indication filter (fewer wakeups with the screen off); refused during a call |

`/run/omamobile-sit/state.json` holds the same status without numbers
(calls as direction and state only, an unread SMS count), rewritten on
every change, for pollers.

## 3. The user-facing path for calls, SMS and data

**Today: the `omamobile-sit` CLI and the socket above.** `omamobile-sit
status`, `dial`, `answer`, `hangup`, `dtmf`, `mute`, `sms send|list|delete`,
`data on|off`, `watch`. Mobile data needs nothing from the user once
`omamobile-sit-data` runs: rmnet0 is a fallback route behind Wi-Fi, so any
application uses it when Wi-Fi is down.

The stack this is ported from has **no ModemManager plugin, no oFono driver
and no D-Bus API**: its own phone and messaging apps talk to exactly this
socket protocol (JSON lines, the same actions). So:

- The shell's quick-settings "Mobile data" tile (`omamobile-shell`) can
  read `omamobile-sit status --json` or `state.json` and toggle with
  `omamobile-sit data on|off`, as section 2.1 of the 0.1 note planned.
- An incoming call shows up in `status`/`state.json` (`ringing-in`); a
  shell overlay that polls `watch` and offers answer/hang-up is the
  smallest useful UI. Not built yet.
- Desktop apps that expect ModemManager (GNOME Calls, Chatty) can't use it.
  The options are unchanged from the 0.1 note: an oFono `sitmodem` driver
  (the natural fit: SIT families map one to one onto oFono atoms; port
  `sit.py`'s layouts to C and test it against `tools/sit-sim`) or a
  ModemManager SIT port type upstream. Either replaces `omamobile-sitd` as
  the IPC0 owner (`Conflicts=` between the units), because SIT has no
  multiplexing.
