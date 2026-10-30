<!-- SPDX-License-Identifier: MIT -->
# Modem client: the SIT RIL, its interface, and the user-facing path

Status (2026-10-26): **`omamobile-modem-sit` 0.4.0 and `omamobile-mmd`
0.2.0 are built and tested offline against `tools/sit-sim`.** 0.4.0 adds:

- IPv6 on rmnet0, with a CLAT for IPv6-only bearers;
- signal strength;
- the carrier's IMS values in the config;
- a scrubbed SIT trace;
- SIM PIN entry (section 1.3).

On our phone, without a SIM, only two things have run: the read-only
probe (MODEM-PLAN M4.1h-M4.1k) and sitd 0.3.0 behind the ModemManager
bridge (T1). Nothing has run with a SIM yet. The first SIM test is
MODEM-PLAN's "M4.2-M4.7: the first SIM test", and section 1.4 says which
SIM to use. The RIL is a port of a SIT stack that registered on LTE, made and
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

## 1. What is built

Two packages:

| Package | What |
|---|---|
| `packages/omamobile-modem` 0.1.0 (new) | The runtime: `omamobile-modem.service` loads CPIF and runs the `modem` vendor-chroot profile (rfsd, then a one-shot cbd, on RAM copies of NV); `omamobile-modem-cp` (CP state, crash record, power-off for the unit's stop, the baseband version, the stock NV checksum); the M0.5 read-only udev rule |
| `packages/omamobile-modem-sit` 0.4.0 | The RIL: `omamobile-sitd` (registration, calls, SMS), `omamobile-sit-data` (the cellular routes), `omamobile-sit` (CLI) |
| `packages/omamobile-mmd` 0.2.0 | The ModemManager bridge (MODEM-PLAN T1) |
| `packages/tayga` 0.9.6 | The NAT64 translator for the CLAT. Optional, upstream build, nothing enabled |

`omamobile-modem-sit/lib/` (installed to `/usr/lib/omamobile-sit/`):

| File | Origin | What |
|---|---|---|
| `sit.py` | ported | The single-owner IPC0 transport: framing, token matching, indication queue (signal and physical-channel snapshots coalesced so telemetry can't crowd out an SMS reply). Two guards: the allow-list of requests this stack sends, and our do-not-send list (NV, identity, carrier lock, AT forwarding, VSIM, satellite) checked first, so an edit to the allow-list can't let one through. Dial and SMS sends need the owner's flags |
| `sit_names.py` | ours | The 602 message names, for logs |
| `bringup.py` | ported, carrier values moved to the config | The start-up order (section 1.1) |
| `data_call.py` | ported, APN from the config | Setup (983 bytes), initial attach (251), data profile (246), PDU sessions; bearer ownership recorded in RAM before each setup, never retried blindly |
| `ims.py` | ported (identity strings and the configurable values ours) | IMS stack start, hidden-menu configuration, ADD_PDN_INFO from the IMS bearer, the registration indication. From 0.4.0 the hidden-menu items and the ADD_PDN_INFO flags come from `[ims]`, or from a per-network profile kept on the phone. The defaults are byte-identical to 0.3.3 |
| `radio_settings.py` | ported | NR mode byte (3 -> 0 keeps LTE; the original kept in RAM) |
| `sms_codec.py` | ported | GSM 7-bit / UCS-2 SMS-SUBMIT with concatenation, SMS-DELIVER with the SMSC prefix the modem adds, WAP push kept as bytes |
| `calls.py`, `inbox.py` | ported | IMS dial/ring/status layouts; received SMS written and fsynced before the ACK |
| `voice_audio.py` | ported, card lookup ours | AoC call routes: PCM 4 playback (EP5), PCM 11 capture (EP4), `TDM_0_RX Mixer EP5`, `EP4 TX Mixer INTERNAL_MIC_TX`, mic gain 130 cB + 6 dB; every changed control restored at the end of the call |
| `service.py` | ported (app service), access and status ours | The daemon: one IPC0 owner for start-up, SMS and calls; the socket API (section 2); `state.json` |
| `data_network.py` | ported; resolved support, IPv6 and the MTU ours | rmnet0's IPv4 /32 and IPv6 address (SLAAC with the network's interface identifier, or the response's /64), one metric-700 default route per family behind Wi-Fi, carrier DNS only while cellular is the only way out, dead-bearer detection. It records what it configured for sitd's private status (`bearer-ip.json`, RAM, root only) |
| `clat.py` | ours | The CLAT for an IPv6-only bearer (section 1.3): TAYGA on `v4-rmnet0`, a /127 out of the bearer's /64, the NAT64 prefix from the config or RFC 7050, per-interface forwarding, two tagged ip6tables FORWARD rules |
| `sit_signal.py` | ours | IND_SIGNAL_STRENGTH decoded passively in the stock codec's layouts (MODEM-SIT-RESEARCH 3.4), giving LTE/NR RSRP, RSRQ, SNR and MM's quality |
| `sit_trace.py` | ours | The scrubbed SIT trace (`[trace] record`, off by default). It records IDs, lengths, error and status codes, and the zero/non-zero byte shape of a few messages that carry no identifier. It never records a payload value |
| `at.py` | ported (fixed commands only) | `AT+CFUN=0/1` on `/dev/umts_router` for radio power during start-up (SIT radio state and AT CFUN were seen to disagree; the working sequence used AT) |
| `cp.py`, `paths.py` | ours | CP state ioctl; the one power-off path; paths and config |

Units (`systemd/`), none enabled by the package:

- `omamobile-sitd.service`: `Type=notify`, `Requires=`/`After=omamobile-modem.service`,
  `ExecStart=omamobile-sitd --bringup`, `Restart=no` (a second start-up on
  the same CP is not supported: reboot), `TimeoutStartSec=15min`.
- `omamobile-sit-data.service`: after the RIL is ready; `omamobile-sit data
  on|off` starts and stops it.
- `/usr/lib/NetworkManager/conf.d/90-omamobile-rmnet.conf`: `rmnet*` unmanaged.

Config: `/etc/omamobile/modem-sit.conf`.

| Section | Keys |
|---|---|
| `[network]` | `apn` (required), `ims`, `ims_apn`, `ims_required` (default no: an IMS failure keeps data, 0.3.2), `nr`, timeouts including `ims_timeout` |
| `[data]` (0.4.0) | `ipv6`, `ra_timeout`, `clat` (`auto`/`off`), `clat_prefix` |
| `[ims]` (0.4.0) | `hidden_menu`, `add_pdn_flags`, `profile_dir` (default `/etc/omamobile/ims.d`, with files named `<MCCMNC>.conf`, on the phone only) |
| `[control]` | `group` |
| `[audio]` | `card` (default `none` since 0.3.3: calls route no audio until M5), `mic_boost_db` |
| `[trace]` (0.4.0) | `record` (default no), `directory`, `max_bytes` |

Tests: `packages/omamobile-modem-sit/test/all` takes about 40 s and runs
110 tests.

- **Unit tests,** most of them ported with the code: transport, layouts,
  bearer lifecycle failure cases, the SMS codec, audio cleanup and the
  route watch. 0.4.0 adds the IPv6 response fields, RFC 7050 prefix
  discovery, the CLAT addresses, signal layouts, and IMS values held to
  0.3.3's SHA-256 digests.
- **rmnet0 in a private network namespace** (`unshare -rn`, with a dummy
  rmnet0, a stub tayga and a stub ip6tables). These check addresses,
  routes, sysctls and that teardown restores everything. They are
  skipped where the machine can't create such a namespace.
- **The real daemon against `tools/sit-sim`:**
  - start-up to IMS registration, with the request order and the
    hidden-menu digest checked;
  - SMS both ways, a call through the CLI, and signal strength;
  - no identifiers in the logs;
  - a rejected bearer ends start-up before any IMS request;
  - no APN means no radio command;
  - an IPv6-only bearer through to `omamobile-sit-data` with a CLAT;
  - the scrub test of the trace;
  - SIM PIN entry and its last-try refusal.

`packages/omamobile-modem/test/all` checks the CP helper's parsers on
made-up inputs.

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
- **No identity reads.** GET_IMEI/IMSI/SIM I/O, PIN and APDU requests are
  not on the allow-list; GET_IMEI/IMEISV are on the do-not-send list too.
- **Logs.** Requests by name and status code; SIM card/app state; data-call
  status/CID/type; IMS registration state/features. Never numbers, message
  text, addresses or the IMSI. The simulator tests fail if a number or a
  message appears in the daemon's log.
- **Outgoing SMS** carry a durable 32-hex request id; an interrupted or
  uncertain send is marked `unknown`, never repeated automatically.
- **Calls**: a hangup whose release isn't confirmed within 12 s, or a call
  left over from a previous run, stops the modem unit (CP off, then rfsd):
  the only way to be sure the radio isn't still carrying a call. That is a
  CP power-off (one UFS handler pass) and is the one place the RIL powers
  the modem off.
- **Storage**: received SMS in `/var/lib/omamobile-sit` (0700, files 0600):
  numbers and text, never to be copied into the repository.

### 1.3 Known gaps

| Gap | Effect |
|---|---|
| Call audio | Off by default (`[audio] card = none`, 0.3.3): calls connect silent. TDM 0 feeds both amplifiers and the top one is the earpiece; until an earpiece mode exists (TELEPHONY-APPS-PLAN T4, MODEM-PLAN M5) a configured card is refused unless speaker protection runs at stage media or c8, the top amplifier is at analog 6 or less (AUDIO-PLAN section 4) and both are within the media stage |
| Speakerphone | Not routed; calls use the stock voice path (EP5 to TDM 0) |
| Call waiting, conference, emergency and short codes, MMS download | Refused or not implemented (emergency numbers are refused by the dialer check: **this phone cannot call emergency services under Linux**) |
| Signal strength | Decoded from IND_SIGNAL_STRENGTH (0.4.0). The stock codec's per-RAT offsets are read, but **which layout this firmware sends is unconfirmed** (MODEM-PLAN step A8). Stock chooses it from a version the modem announces in SET_DEVICE_INFO's reply, which we never send; here it is chosen by length. Readings outside stock's ranges count as absent |
| Operator name | GET_OPERATOR decoded with the research note's layout, display only, not yet seen on hardware |
| IPv6 on rmnet0 | Configured from 0.4.0, and an IPv6-only bearer gets a CLAT (below). Unverified on hardware: that the network's router advertisements reach the raw-IP rmnet0 and SLAAC forms the address. If the response carries a global address, that path doesn't need SLAAC |
| Warm CP restart | None: about one fresh start in twenty crashed during registration on this phone model; the crash is recorded and the phone needs a reboot |
| Carrier values | The default IMS hidden-menu items and ADD_PDN_INFO flags are the ones that registered on a T-Mobile-network MVNO. From 0.4.0 they are in `[ims]`, with per-network profiles on the phone, so another carrier can be tried after a reboot without a release. Which values another carrier needs is unknown. The identity strings (tags 772-776, 519) are still fixed (MODEM-PLAN W5) |
| Suspend with the modem on | Not handled (CPIF's suspend refusal, the pull on cp2ap-wakeup, the receive-ring check after link wake: MODEM-PLAN 6) |
| SIM PIN entry | From 0.4.0: `omamobile-sit sim-pin` (or MM's `Sim.SendPin`) sends one VERIFY_SIM_PIN, only while the SIM asks for its PIN and has two or more tries left. It never retries; PUK and PIN changes stay in another phone. Untested on hardware. Start-up (`--bringup`) still stops on a locked SIM, so for the first SIM test the PIN lock stays off |
| The eSIM | None: the RIL speaks only to the physical slot (`umts_ipc0`; `umts_ipc1` is the eSIM's) |

**The CLAT, and why it is ours.** On an IPv6-only bearer, `clat.py`
gives the phone IPv4 through the carrier's NAT64.

- **Translation:** TAYGA, a small C translator on a TUN device. Neither
  Arch Linux nor Arch Linux ARM packages it; `packages/tayga` builds the
  upstream release, and it is an optional dependency.
- **Addressing:** the IPv4 side is 192.0.0.1/29 on `v4-rmnet0` (RFC 7335).
  The IPv6 side is a /127 out of the bearer's /64, which the network
  routes to the phone.
- **NAT64 prefix:** from `[data] clat_prefix`, or else from the carrier's
  DNS64 (RFC 7050), asked over rmnet0 only.
- **Routing and firewall:** IPv6 forwarding is enabled on `rmnet0` and
  `v4-rmnet0` only (`force_forwarding`, Linux 6.17+), and two tagged
  ip6tables FORWARD rules let the /127 through ufw.
- **Routes:** the IPv4 default route sits behind Wi-Fi's (metric 700),
  like the others.

The ready-made option was the `clatd` script. Neither repository packages
it, it needs Perl modules that aren't packaged either, and it assumes an
Ethernet-like uplink, using proxy NDP or NAT66. It would also duplicate
what `omamobile-sit-data` already owns on rmnet0: the addresses, routes,
DNS, the dead-bearer watch and teardown. A translator written in Python
would be too slow per packet. So we use TAYGA for translation and about
200 lines of our own to configure it.

Unverified on hardware: the carrier's DNS64 answer, TAYGA's throughput,
and ufw's real chain order. If any of these fail, IPv6 keeps working
and the journal says why the CLAT didn't start.

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
- **The internet bearer's IP type.** From 0.4.0 an IPv6-only bearer is
  configured with a CLAT (1.3), but that path has never met a real
  network. An APN documented as IPv4 or IPv4v6 is the safer first test.
  T-Mobile's own APNs are often IPv6-only, which is now the case 0.4.0
  was built for.
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
| `{"action": "sim-pin", "pin": "1234"}` (0.4.0) | `{"accepted": true, "tries_left": n}`. One VERIFY_SIM_PIN. It is refused unless the SIM asks for its PIN with two or more tries left. A wrong PIN fails with the number of tries left. The PIN is never logged |

From 0.4.0 the `status` result also carries:

- `modem.signal`: MM's quality in percent, 0 when unknown;
- `modem.signal_detail`: the layout name and LTE/NR `rsrp`, `rsrq`,
  `snr` and `rssi` in dBm and dB, or null;
- `modem.bearer`, private only: what `omamobile-sit-data` configured
  (`ipv4`, `ipv6`, `clat`). It is never in `state.json`.

`/run/omamobile-sit/state.json` holds the same status without numbers
(calls as direction and state only, an unread SMS count), rewritten on
every change, for pollers.

## 3. The user-facing path for calls, SMS and data

**sitd is the only process that talks to the modem.** Everything else
reaches it through the socket in section 2.

| Layer | What it is | State |
|---|---|---|
| `omamobile-sit` CLI and the socket | `status`, `dial`, `answer`, `hangup`, `dtmf`, `mute`, `sms send\|list\|delete`, `data on\|off`, `sim-pin`, `radio`, `watch` | Tested against `tools/sit-sim`; never with a SIM |
| `omamobile-mmd` (MODEM-PLAN T1, TELEPHONY-APPS-PLAN T0/T1) | Serves ModemManager 1.24's D-Bus API (`org.freedesktop.ModemManager1`) from sitd's `subscribe` stream. It conflicts with ModemManager, enables nothing and has no D-Bus activation | Passed T1 on the phone without a SIM (2026-10-14). 0.2.0 adds bearer IP config, signal quality and `Sim.SendPin` |
| ModemManager clients | GNOME Calls 51.1 and Chatty 0.8.9 pass the bridge's conformance run in a container (`packages/omamobile-mmd/test/conformance`). NetworkManager sees a `gsm` device | Test bench only (TELEPHONY-APPS-PLAN, option A) |
| omatel | `omatel-agent`, Phone (`omaphone`) and Messages (`omamessages`) use the ModemManager API through the bridge (TELEPHONY-APPS-PLAN T6/T7) | Built offline; not run on the phone |
| `omamobile-shell` | The status bar's mobile network indicator (bars, network type, No SIM, SIM locked, radio off) and the call card come from ModemManager's API and omatel-agent (TELEPHONY-APPS-PLAN T5) | Offline; bars show once sitd reports a signal (0.4.0) |
| Mobile data | `omamobile-sit-data` keeps rmnet0 as a fallback behind Wi-Fi, so any application uses it when Wi-Fi is down. NetworkManager leaves `rmnet*` unmanaged, and the bearer object is read-only | NM-driven data through `Simple.Connect` is T3 (owner's Q5) |

Not there yet:

- call audio (M5 / T4);
- MMS (T3);
- emergency calls (refused everywhere; T8);
- hold, waiting and conference calls.

The 0.1 note weighed an oFono `sitmodem` driver and an upstream
ModemManager SIT port. Neither is needed for these clients any more: the
bridge serves them without a second IPC0 owner.
