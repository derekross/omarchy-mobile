<!-- SPDX-License-Identifier: MIT -->
# Telephony apps plan: omadialer, omamessages and the stack under them

**Status (2026-10-14):** **T0 and T1 done** without a SIM: `omamobile-modem-sit` 0.3.0 (event subscription, SIM and radio state) and `omamobile-mmd` 0.1.0, the ModemManager-compatible bridge, pass their tests, mmcli, GNOME Calls 51.1 and Chatty 0.8.9 in a container, and a no-SIM run on the phone (FAILED/sim-missing, as MM shows it; NetworkManager sees the modem). Results and runbook: [MODEM-PLAN](../device/cheetah/MODEM-PLAN.md) "T0/T1: the ModemManager bridge". T2 needs the SIM. Packaging decided: its own package `omamobile-mmd` (not `omamobile-mm`), `conflicts=(modemmanager)` and no `provides=` (nothing depends on `modemmanager`), no D-Bus activation file, Python with PyGObject's Gio rather than dbus-fast (on the phone already, and it gives the caller's bus name for polkit). The bridge owns the bus name from its start and shows the modem once sitd's socket answers. Hold, swap, conference, call waiting, signal strength and SIM PIN moved to T8 (new SIT requests, untestable without a SIM).

**T5, first part (2026-10-22), offline only: calls in the shell.** `omamobile-shell` 0.2.12 adds `omamobile.call` (plugins/README.md): a ringing call on a locked phone fills the screen over the lock, swipe up to answer and down to decline, with "Reply" sending one of omatel's canned messages; a heads-up card with Decline and Answer on an unlocked phone or for a waiting call; and in-call controls over the lock (time, mute, speaker, end), which fold to a strip so the lock's PIN pad is reachable. It contradicts §7.1 in one place: the card is our own plugin, not an Omarchy patch, because Hyprland's `above_lock = 2` lets a shell surface draw over the session lock and take touches (the on-screen keyboard already does). `omamobile-call-watch` follows the agent and lights the screen when a call rings; omatel-agent 0.2.1-2 depends on feedbackd and the sound theme, so calls ring and vibrate. Tested offline: the model under Node, the watcher against a fake agent on a private bus, and render shots of every state in a dark and a light theme. **Since (2026-10-23):** omatel 0.2.2 leaves ringing calls to the card while `org.omamobile.CallCard` is owned; omamobile-shell 0.2.13 adds the status bar's call chip and the mobile network (ModemManager's API: bars once a reading arrives, the network type, No SIM, SIM locked, radio off); omatel 0.2.3 silences every caller but starred contacts during Omarchy's Do Not Disturb and publishes `SilencedCalls`, which the card follows. omamobile-omarchy 0.1.5 (patch 0014) puts an "Emergency call" button on the lock under the number pad, and omamobile-shell 0.2.14 answers it with §3.2's warning over the lock, never a dialpad (§7.3's dialpad waits for §3.3). omamobile-omarchy 0.1.6 (patch 0015) adds §7.2's inline reply: Omarchy's notification server advertises `inline-reply`, and a toast whose sender asks for it gets Reply, then a field with Send and Cancel; Send emits `NotificationReplied` and then dismisses the toast, which is the order omatel's agent needs (it sends the SMS and marks the conversation read on the first). While the field is open the countdown stops and the toast surface takes keyboard focus on demand, as the polkit prompt does (patch 0010). History rows can't be answered and get no button. Tested offline: `test/notifications-reply` runs Omarchy's service with the patch on a private bus in the OWL container (a notification asking for a reply and a plain one, a blank reply, Send, the signals in order; a mutation of either the capability or the countdown pause fails it), and render shots in a dark and a light theme. Not yet seen on the phone: squeekboard showing for a field on the Overlay layer, and a reply typed on it. A toast the sender replaces while the field is open (a new message in that conversation) loses what was typed. **T5's offline work is done.** **On the phone, without a SIM:** P0-P5 below plus a simulated ring once omatel-agent runs there (the call card can be shown with the agent's mock).

**T6 and T7, first version (2026-10-14), offline only.** The apps are built as **omatel**: Phone (`omaphone`), Messages (`omamessages`) and `omatel-agent`, one headless agent for both (Q12), in one local repository (`~/Projects/omatel`, GPL-3.0-or-later, not published). They passed:
- 92 Rust tests (unit tests; the ModemManager proxies against a scripted MM; the agent end to end on private buses);
- a chain test in a container: agent, then `omamobile-mmd`, `omamobile-sitd` and `tools/sit-sim`;
- screenshots in a headless Weston.

Since 0.2.0 there are three repositories: `omatel` (the shared crates and the agent), `omaphone` and `omamessages`, each with its own package (`packages/omatel` builds `omatel-agent`; `packages/omaphone`, `packages/omamessages`), none in `omamobile-apps`' defaults. Nothing has run on the phone. Results, deviations from §9, what is stubbed, and the runbook for the first phone test are in [§10.1b](#101b-t6-and-t7-the-first-version-2026-10-14). Shell work (T5), call audio (T4) and MMS (T3) are not part of this.

The rest of this status line is the design snapshot: design only. Nothing is built and nothing on the phone has changed. The only phone queries were read-only: package versions, unit states, and the RTC's name and wake flag. Kernel on the phone: `7.3.0-rc6-omamobile-push1-00543-g1f83c16c0aba`. Installed: `omamobile-modem` 0.1.4 and `omamobile-modem-sit` 0.2.0, both units disabled, no SIM; `libmm-glib` 1.24.2 (pulled in by NetworkManager and GeoClue), `squeekboard` 1.43.1, `quickshell` 0.3.2, `omarchy` 4.0.4. Not installed: ModemManager, oFono, GNOME Calls, Chatty, mmsd-tng, evolution-data-server.

**Goal:** a phone that makes and takes calls and sends and receives SMS and MMS, through two apps of ours modelled on AOSP Dialer and AOSP Messaging and remade in Rust for Omarchy Mobile.

**Recommendation in one line:** **make our modem look like ModemManager.** A new system service, `omamobile-mmd`, owns `org.freedesktop.ModemManager1` and implements the part of ModemManager's D-Bus API that phone software uses, on top of `omamobile-sitd`, which stays the only owner of the SIT channel. Prove it with GNOME Calls, Chatty, mmsd-tng and NetworkManager before writing any UI of ours. Then build **omadialer** ("Phone": dialpad, call log, favourites, contacts, in-call) and **omamessages** ("Messages": SMS and MMS) in one Rust workspace with GTK 4 and libadwaita, as ordinary ModemManager clients. **RCS is not reachable** for an open client today (§4). **Other apps: reuse.** Camera, phone and messages are the only apps worth writing ourselves. Alarms need a small wake helper, not a new clock app (§8).

The owner's request: build omamessages (SMS, and RCS if possible) and omadialer (calls), modelled on the AOSP Messages and Dialer apps and remade in Rust for Omarchy Mobile; and say which other phone apps, if any, we should remake ("I think it's just camera, messages and dialer").

The decisions already taken for the camera app apply here too ([CAMERA-APP-PLAN](CAMERA-APP-PLAN.md) §7): Rust with GTK 4/libadwaita through gtk-rs; the Omarchy theme read from `colors.toml` the way [gliff](https://github.com/omacom/gliff)'s `crates/gliff/src/theme.rs` does it; GPL-3.0-or-later; apps in their own repositories.

### Sources read for this plan

Upstream projects were read as shallow clones or web pages on 2026-10-14. Nothing from them was built, run or copied into our tree.

| Project | Licence | Commit / release | What was read |
| --- | --- | --- | --- |
| [ModemManager](https://gitlab.freedesktop.org/mobile-broadband/ModemManager) | GPL-2.0-or-later (daemon), LGPL (libmm-glib) | 1.24.2 (2025-07-28); `main` @ `7f0bf17` (2026-10-04) | `introspection/*.xml`, `src/mm-plugin-manager.c`, `src/mm-filter.c`, `src/mm-base-call.c`, `include/ModemManager-enums.h`, `data/*.policy.in.in`, `data/*.service.in` |
| [GNOME Calls](https://gitlab.gnome.org/GNOME/calls) | GPL-3.0-or-later | v51.1, `d3a2a22` (2026-10-12) | `plugins/provider/mm/`, `plugins/provider/ofono/`, `src/meson.build` |
| [Chatty](https://gitlab.gnome.org/World/Chatty) | GPL-3.0-or-later | v0.8.9, `099dbea` (2026-10-06) | `src/mm/chatty-mm-account.c`, `src/mm/chatty-mmsd.c`, `src/meson.build` |
| [Phosh](https://gitlab.gnome.org/World/Phosh/phosh) | GPL-3.0-or-later | v0.58.0, `17aa099` | `src/wwan/phosh-wwan-mm.c`, `phosh-wwan-ofono.c` |
| [plasma-dialer](https://invent.kde.org/plasma-mobile/plasma-dialer), [spacebar](https://invent.kde.org/plasma-mobile/spacebar), [ModemManagerQt](https://invent.kde.org/frameworks/modemmanager-qt) | GPL/LGPL | v6.7.90 `120df4d`; v6.7.90 `2305f7e`; `0e7f71e` (2026-10-02) | `modem-daemon/src/mm-modem-controller.cpp`, `CMakeLists.txt`; `daemon/ecurl.cpp`; `src/manager.cpp` |
| [NetworkManager](https://gitlab.freedesktop.org/NetworkManager/NetworkManager) | GPL-2.0-or-later | 1.58.1, `7406dfb` (2026-08-21) | `src/core/devices/wwan/nm-modem-manager.c`, `nm-modem-broadband.c`, `meson_options.txt` |
| [ofono2mm (FuriLabs)](https://github.com/FuriLabs/ofono2mm) | GPL-2.0 | `2b1d012` (2026-08-12) | `main.py`, `ofono2mm/mm_modem.py`, `mm_sms.py`, `systemd/10-ofono2mm.conf` |
| [ofono2mm (Droidian, the original)](https://github.com/droidian/ofono2mm) | BSD-3-Clause | `97a792d` (2026-01-09) | README, licence, structure |
| [oFono](https://git.kernel.org/pub/scm/network/ofono/ofono.git), [mmsd](https://git.kernel.org/pub/scm/network/ofono/mmsd.git) | GPL-2.0 | oFono 2.19 (2025-11-21), last commit `00c3cb1` (2026-05-20); mmsd `f4b8b32` (2019-07-24) | `src/plugin.c`, `src/modem.c`, `drivers/`, `plugins/` |
| [mmsd-tng](https://gitlab.com/kop316/mmsd) | GPL-2.0 | 2.6.4, `3411171` (2025-11-30) | README, `plugins/modemmanager.c`, `src/service.c`, `src/main.c` |
| [vvmd](https://gitlab.com/kop316/vvmd) | GPL-2.0 | `main` | README |
| [PipeWire](https://gitlab.freedesktop.org/pipewire/pipewire) | MIT | 1.6.9, `8fa27ca` (2026-09-17) | `spa/plugins/bluez5/modemmanager.c`, `backend-native.c`, `meson_options.txt`, `README-Telephony.md`; Arch's and Arch Linux ARM's PKGBUILDs |
| [AOSP Messaging](https://android.googlesource.com/platform/packages/apps/Messaging/+/refs/heads/main/) | Apache-2.0 | `main` @ `de315b7` (2025-02-26) | README, `src/com/android/messaging/` |
| [AOSP Dialer](https://android.googlesource.com/platform/packages/apps/Dialer/+/refs/heads/main/) | Apache-2.0 | `main` @ `544da8b` (2025-02-25) | README, `java/com/android/{dialer,incallui,voicemail}/` |
| [AOSP Contacts](https://android.googlesource.com/platform/packages/apps/Contacts/+/refs/heads/main/), [Telephony](https://android.googlesource.com/platform/packages/services/Telephony/+/refs/heads/main/), [CarrierConfig](https://android.googlesource.com/platform/packages/apps/CarrierConfig/+/refs/heads/main/) | Apache-2.0 | `main` (2025-03) | `src/com/android/contacts/`; `EmergencyDialer.java`; `assets/carrier_config_carrierid_1_T-Mobile-US.xml` |
| GSMA RCS: [RCC.71 v4.0 (UP 4.0)](https://media.gsma.com/assets/2026/rcs/RCC.71+v4.0.pdf), RCC.07 v17.0, RCC.14 v13.0 | (specifications) | all dated 2026-02-19 | provisioning (RCC.14 §2.2, §2.4, §2.6-2.8, §2.11), client parameters (RCC.07 §2.3.2) |
| 3GPP [TS 22.101 §10.1.1](https://itecspec.com/3gpp/22.101/s/10.1.1); [47 CFR 9.10](https://www.law.cornell.edu/cfr/text/47/9.10) | (standards, US law) | Rel-20; current eCFR | emergency numbers; carriers' 911 duties |
| [pmaports](https://gitlab.postmarketos.org/postmarketOS/pmaports) | | `c8832bf` (2026-10-14) | `main/postmarketos-base-ui-gnome*/APKBUILD` (what a mobile GNOME install ships) |

On our side: [MODEM-PLAN](../device/cheetah/MODEM-PLAN.md) (M3.4-M4.1k, sections 4, 6.1, 6.3), [MODEM-CLIENT](../device/cheetah/MODEM-CLIENT.md), [MODEM-SIT-RESEARCH](../device/cheetah/MODEM-SIT-RESEARCH.md) (the message ID appendix), [AOC-PLAN](../device/cheetah/AOC-PLAN.md) (C7, C9, "Earpiece and calls"), [AUDIO-PLAN](../device/cheetah/AUDIO-PLAN.md) (1.5, 1.6, A1, A4), [BLUETOOTH-PLAN](../device/cheetah/BLUETOOTH-PLAN.md), [SUSPEND-PLAN](../device/cheetah/SUSPEND-PLAN.md) (section 3, S3b), [USB-C-PLAN](../device/cheetah/USB-C-PLAN.md) (B4b, B4c), [ROADMAP](ROADMAP.md) §3.1, `packages/omamobile-modem-sit`, `packages/omamobile-audio`, `packages/omamobile-shell`, Omarchy 4.0.4's `shell/plugins/{notifications,lock}`, and our stock captures (private; only facts are quoted here, §2.1).

---

## 1. The telephony stack underneath

### 1.1 What we have

`omamobile-sitd` (Python, `packages/omamobile-modem-sit` 0.2.0) is the only owner of the modem's SIT channel (`umts_ipc0`). It registers the modem on LTE with IMS, places and answers IMS voice calls, sends and receives SMS, and brings up the internet bearer (`rmnet0`). It serves a JSON-lines socket, `/run/omamobile-sit/socket`, to root and to members of the `[control] group` ([MODEM-CLIENT](../device/cheetah/MODEM-CLIENT.md) §2). The code is a port of a stack that did all of this on a Pixel 7 Pro. **On our phone it has reached M4.1k: the modem boots, answers SIT, idles its link, and reboots cleanly with the modem up.** Everything from M4.2 on needs a SIM.

What the socket API offers today, and what's missing for phone apps:

| Have | Missing (MODEM-CLIENT §1.3 and this plan) |
| --- | --- |
| status (registration, technology, operator, IMS voice/SMS, data), dial, accept, hangup, DTMF, mute, SMS send/list/delete with durable request IDs, screen state, radio | **an event stream** (the CLI's `watch` polls `state.json`); **signal strength** (reported as 0); **SIM state and PIN** (the RIL has no PIN entry); own number; **hold, swap, conference, call waiting**; USSD; **emergency calls (refused)**; short codes; **WAP push delivered as data** (the codec keeps it as bytes, nothing passes it on); SMS status reports to the sender; **cell broadcast (WEA)**; IPv6 on `rmnet0`; speakerphone routing |

SIT has messages for every missing item ([MODEM-SIT-RESEARCH](../device/cheetah/MODEM-SIT-RESEARCH.md) appendix). Among them: `SWITCH_WAITING_OR_HOLDING_AND_ACTIVE` (0x0502), `CONFERENCE` (0x0503), `AIMS_CALL_MANAGE` (0x0d09), `AIMS_CONF_CALL_ADD_REMOVE_USER` (0x0d12), `GET/SET_CALL_WAITING` (0x050b/c, 0x0d16/17), `SEND_USSD` (0x0505), `IND_EMERGENCY_CALL_LIST` (0x000d), `SET_EMC_MODE`/`EMC_NW_SCAN` (0x001f, 0x0021), `SET_EMERGENCY_CALL_STATUS` (0x0712), `IND_NEW_SMS_STATUS_REPORT` (0x010d, 0x0d20), `IND_NEW_BCST_SMS` (0x0110), `VERIFY_SIM_PIN` (0x0201), `GET_SIGNAL_STRENGTH` (0x0900), `IND_NITZ_TIME_RECEIVED` (0x0905). None of these has met our firmware yet. Each new request goes on `sit.py`'s allow-list deliberately, one at a time, and never onto the do-not-send list's ground (NV, identity, carrier lock).

### 1.2 Options for exposing the modem to apps

| Option | What it takes | What apps get | Verdict |
| --- | --- | --- | --- |
| **(a1) A ModemManager plugin** | MM's port types are fixed (`include/ModemManager-enums.h`: NET, AT, QCDM, GPS, QMI, MBIM, AUDIO, IGNORED and XMMRPC, new in 1.24). Plugins are `.so` files built against MM's internal headers, and `src/mm-plugin-manager.c` checks their major/minor version. **A SIT port type means patching MM upstream**: a new port type and probe, plus a SIT protocol library comparable to libqmi. The one shortcut is to fake an AT or QMI port over a pty, which would put a second protocol translator in the middle | Everything MM serves | **No.** Months of upstream work for a protocol only Pixel modems speak, and the hardware-tested RIL would have to be rewritten in C |
| **(a2) A standalone service that owns `org.freedesktop.ModemManager1`** | One daemon that exports MM's objects and interfaces (§1.4) from the RIL's state | **Every MM client without a patch**: GNOME Calls, Chatty, mmsd-tng, NetworkManager's mobile data, Phosh's status, plasma-dialer, spacebar, vvmd, PipeWire's Bluetooth HFP gateway (§1.3) | **Chosen** (§1.5) |
| **(b) oFono** | An out-of-tree C plugin and driver (oFono still `dlopen`s from `PLUGINDIR`, `src/plugin.c:116-128`, but the API isn't stable), with SIT's families mapped onto oFono atoms (voicecall, sms, netreg, gprs). `sit.py`'s layouts get ported to C | **Less every year.** GNOME Calls' oFono provider calls itself "(deprecated)". Chatty has no oFono path, **mmsd-tng supports only MM**, and NetworkManager's oFono support is off by default ("experimental"). oFono 2.19 (2025-11-21) has had two commits since October 2025 | **No.** MODEM-CLIENT §3 leaned this way before we checked the clients. The app side has since moved to MM |
| **(c) Our own D-Bus API** | Small and exactly what our apps need | Our apps only. Every existing app needs a backend for it | **No** as the main API. Our own apps can also read richer data from `omamobile-sitd` directly where MM has no equivalent, but nothing should *depend* on that |

### 1.3 What speaking MM buys us

From source (the tag in the table above), and every client below reaches MM the same way: it watches the bus name, then reads `GetManagedObjects` on `/org/freedesktop/ModemManager1`. **No client checks MM's `Version` property, and none calls `ScanDevices`, `SetLogging` or `InhibitDevice`.**

| Client | How it finds MM | What it uses |
| --- | --- | --- |
| GNOME Calls 51.1 | `plugins/provider/mm/calls-mm-provider.c:384`: `g_bus_watch_name`, `mm_manager_new`. A modem appears when an object gains `Modem.Voice` (`:167`) | Voice: create, list and delete calls, call waiting. Call: Start, Accept, Hangup, SendDtmf. USSD. `Sim.EmergencyNumbers`, `Sim.Imsi`, the 3GPP IMEI, Location 3GPP (the country code, for emergency numbers), `OwnNumbers` |
| Chatty 0.8.9 | `src/mm/chatty-mm-account.c:1173`: libmm-glib | Messaging create, list, delete and `Added`; Sms number, text, state, PDU type, delivery state, reference, timestamp; sets `DeliveryReportRequest` and validity. MMS through mmsd-tng on the session bus (`org.ofono.mms`, `/org/ofono/mms/modemmanager`, `src/mm/chatty-mmsd.c:38-42`) |
| mmsd-tng 2.6.4 | `plugins/modemmanager.c` (its only plugin) | WAP push: an Sms whose `Text` is empty and `Data` isn't (`:600-635`). Then a **connected Bearer** whose APN matches `MMS_APN`, while the modem's state is CONNECTED (`:1425-1480`). It takes that bearer's `Interface` and DNS |
| NetworkManager 1.58.1 | `src/core/devices/wwan/nm-modem-manager.c` | Modem enable and power state, device, drivers, ports, IP families, unlock; Sim.SendPin; `Simple.Connect`/`Disconnect`; Bearer `Interface` and `Ip4Config`/`Ip6Config`. **NM's `gsm` connections exist only for MM modems** (or with NM's `-Dofono=true`, off by default) |
| PipeWire 1.6.9 Bluetooth HFP gateway | `spa/plugins/bluez5/modemmanager.c`, its own D-Bus code (only MM's headers at build time) | Modem state, signal, own numbers; Voice.CreateCall, Calls; Call Accept, Hangup, SendDtmf. It turns a headset's answer, dial, hang-up and DTMF commands into these (`backend-native.c:1312-1507`). **Built only with `-Dbluez5-backend-native-mm=enabled`, which defaults to disabled and is off in Arch's and Arch Linux ARM's 1.6.9-1**, and enabled at runtime only by `bluez5.hfphsp-backend-native-modem` |
| Phosh 0.58 (reference only; we don't run Phosh) | `src/wwan/phosh-wwan-mm.c` | State, signal quality, access technology, unlock required, SIM, operator name, cell broadcasts: what a status bar needs |
| plasma-dialer and spacebar 6.7.90 | ModemManagerQt (`src/manager.cpp`: a service watcher and an ObjectManager proxy) | Voice, Call, USSD; Messaging, Sms `Data`, Bearer interface and IP. Spacebar fetches MMS itself with curl bound to the bearer's interface (`daemon/ecurl.cpp:36-41`) |
| vvmd (visual voicemail, §5.3) | MM, per its README | SMS to and from the voicemail server, a data bearer |

So **one service gives us a working phone with existing apps before we write a line of UI**, and our own apps are then plain MM clients. That also makes them work on any MM phone (postmarketOS, Mobian), which suits their own repositories.

**Precedent: ofono2mm.** Droidian wrote [ofono2mm](https://github.com/droidian/ofono2mm) (BSD-3-Clause, Python with dbus-next), and FuriLabs maintains a [fork](https://github.com/FuriLabs/ofono2mm) (GPL-2.0, Python with dbus-fast). It exports MM's API, with `Version` "1.24.0", in front of oFono, so Phosh, Calls and Chatty run on Android-HAL phones. Lessons from its source:

- **It takes over the unit.** `systemd/10-ofono2mm.conf` is a drop-in that replaces `ModemManager.service`'s `ExecStart`, so D-Bus activation (`SystemdService=dbus-org.freedesktop.ModemManager1.service`) starts it. Its Debian package still depends on `modemmanager` for the unit, the bus policy and libmm.
- **It drops and re-requests the bus name after the modem appears** (`mm_modem.py:695-715`, with a TODO saying it doesn't know why clients need this).
- **Its `Sms` has no `Data` property** (`mm_sms.py`), so mmsd-tng can't see WAP push and MMS can't work through it. We must not repeat that.

### 1.4 The API subset we implement, and where each piece comes from

`omamobile-mmd` exports one modem at `/org/freedesktop/ModemManager1/Modem/0`. "Phase" refers to §10.

| Interface (MM 1.24) | Members we implement | SIT source | MODEM-PLAN step | Phase |
| --- | --- | --- | --- | --- |
| Manager + `org.freedesktop.DBus.ObjectManager` | `GetManagedObjects`, `InterfacesAdded/Removed`, `Version` ("1.24.2"); `ScanDevices`/`SetLogging`/`InhibitDevice` answer "not supported" | (the daemon) | M4.1 | T1 |
| Modem | `State` (from radio and registration), `PowerState`, `Enable` (radio on/off through `AT+CFUN`, as sitd does), `UnlockRequired`, `Sim`, `SimSlots`, `SignalQuality`, `AccessTechnologies`, `OwnNumbers`, `Manufacturer`/`Model`/`Revision`, `Device`, `Drivers` (`["cpif"]`), `Plugin` (`"omamobile"`), `Ports`, `Bearers`, `CurrentModes`, `SupportedIpFamilies`, `MaxActiveBearers`. `EquipmentIdentifier` stays empty unless the owner decides otherwise (§10, Q9) | GET_SIM_STATUS, GET_PS_REG_STATE, GET_OPERATOR, GET_SIGNAL_STRENGTH, GET_BASEBAND_VERSION | M4.1, M4.2 | T1 |
| Modem3gpp | `RegistrationState`, `OperatorCode`, `OperatorName`, `PacketServiceState`, `InitialEpsBearerSettings` (read-only, from our config); `Imei` empty (Q9); `Register`/`Scan` "not supported" at first | GET_PS_REG_STATE, GET_OPERATOR | M4.2 | T1 |
| Sim | `Active`, `OperatorIdentifier`, `OperatorName`, **`EmergencyNumbers`** (112, 911, the SIM's and the network's lists), `SimType`; `SendPin`/`SendPuk`/`ChangePin`/`EnablePin` later (T8); `Imsi`/`SimIdentifier` empty (Q9) | GET_SIM_STATUS, IND_EMERGENCY_CALL_LIST, VERIFY_SIM_PIN | M4.1, M4.2 | T1, T8 |
| Signal | `Lte`, `Nr5g` (`rsrp`, `rsrq`, `snr`), `Rate`, `Setup` | GET_SIGNAL_STRENGTH, IND_SIGNAL_STRENGTH | M4.2 | T1 |
| Modem.Voice | `Calls`, `CallAdded/Deleted`, `CreateCall`, `DeleteCall`, `ListCalls`, `HangupAll`, `HoldAndAccept`, `HangupAndAccept`, `CallWaitingQuery/Setup`, **`EmergencyOnly`** | AIMS_DIAL/ANSWER/HANGUP, IND_AIMS_CALL_STATUS, AIMS_CALL_MANAGE, call waiting | M4.5 | T1 (basic), T8 (the rest) |
| Call | `Start`, `Accept`, `Hangup`, `SendDtmf`, `JoinMultiparty`, `LeaveMultiparty`, `Deflect` (later); `State`, `StateReason`, `Direction`, `Number`, `Multiparty`, `StateChanged`, `DtmfReceived`. MM has no per-call hold: hold is `Voice.HoldAndAccept`, and our in-call UI follows that | AIMS_*, AIMS_SEND_DTMF, AIMS_CONF_CALL_ADD_REMOVE_USER | M4.5 | T1, T8 |
| Modem.Messaging | `Messages`, `Added`, `Deleted`, `List`, `Create`, `Delete`, `SupportedStorages` (`me`), `DefaultStorage` | IND_NEW_SMS / IND_AIMS_NEW_SMS, SEND_SMS / AIMS_SEND_SMS | M4.4 | T1 |
| Sms | `Send`; `State`, `PduType`, `Number`, `Text`, **`Data`** (WAP push and other binary SMS, with `Text` empty), `Timestamp`, `DeliveryReportRequest`, `DeliveryState`, `MessageReference`, `Storage`, `Validity`, `Class` | sms_codec.py (concatenation, UCS-2, the WAP bytes it already keeps) | M4.4 | T1, T3 |
| Bearer | `Interface` (`rmnet0`), `Connected`, `Ip4Config`/`Ip6Config` (method `static`: address, prefix, gateway, DNS, MTU), `Properties` (APN, IP type), `Connect`/`Disconnect`; `Modem.Simple.Connect/Disconnect/GetStatus` | data_call.py, data_network.py | M4.3 | T3 |
| Modem3gpp.Ussd | `Initiate`, `Respond`, `Cancel`, `State`, `NetworkNotification` | SEND_USSD, IND_ON_USSD | M4.5 | T8 (balance and carrier codes) |
| Modem.Location | 3GPP location (MCC/MNC/LAC/CI) only; GPS stays with our GNSS stack and GeoClue | GET_PS_REG_STATE | M4.2 | T1 (Calls uses the MCC for emergency numbers) |
| CellBroadcast | the alert list (WEA) | IND_NEW_BCST_SMS, SET_BCST_SMS_CFG | after M4.4 | T9 |
| Time | network time | IND_NITZ_TIME_RECEIVED | after M4.2 | T9 |

Anything else (Firmware, Oma, Sar, ProfileManager, Cdma) isn't exported: clients check for an interface before they use it.

### 1.5 Recommendation: `omamobile-mmd`, a separate process in front of `omamobile-sitd`

```
GNOME Calls, Chatty, our apps ─┐
NetworkManager, mmsd-tng,      ├─ system bus: org.freedesktop.ModemManager1 ─> omamobile-mmd ──┐
PipeWire HFP gateway, vvmd ────┘                                                               │ JSON lines + event stream
shell status / quick settings ─────────────────────────────────────────────────────────────────┤ /run/omamobile-sit/socket
                                                                                     omamobile-sitd (the only IPC0 owner)
                                                                                       ├─ umts_ipc0 (SIT), umts_router (AT)
                                                                                       └─ AoC voice PCMs (EP5/EP4), rmnet0
```

- **Why a separate process.** `omamobile-sitd` holds the safety model: the allow-list, the do-not-send list, durable SMS sends that never repeat, and power-off when a hangup isn't confirmed. Keeping D-Bus out of it keeps that code small and keeps its tests (`tools/sit-sim`) as they are. A crash in the bridge can't drop a call, and the bridge can restart freely, which the RIL can't (a second start-up on the same CP isn't supported).
- **Why Python, with dbus-fast.** This differs from the apps, and it is Q3. The RIL is Python, and ofono2mm shows that Python with dbus-fast carries MM's whole API. The bridge is a translation layer with no performance load, and the same team reads both sides. Read Droidian's BSD-3-Clause original for structure (compatible with our MIT tree), and FuriLabs' GPL-2.0 fork for reference only. Rust with zbus is the alternative if the owner wants one language for everything new. It would add a toolchain to the system side, and the apps wouldn't share code with it anyway, since they use MM's public API.
- **Changes to `omamobile-sitd`'s socket API** (T0, offline, against `tools/sit-sim`):
  - `subscribe`: a long-lived connection that receives one JSON event per change, with call, SMS, registration, signal and SIM events. The bridge then doesn't poll `state.json`.
  - Full numbers and message text on this socket, for its authorised peers only. The logs stay free of numbers, as now.
  - The new requests from §1.1, each behind the allow-list: hold/swap/conference, call waiting, signal, SIM PIN, USSD, status reports, WAP push as data, emergency dial (§3), cell broadcast.
  - Received SMS handed over by ID: the bridge exports each one as an `Sms` object, and a client's `Messaging.Delete` deletes it in sitd's store. That is Chatty's pattern: it copies each message into its own database and deletes it from the modem.
- **Packaging, as built (T1, `packages/omamobile-mmd` 0.1.0; [MODEM-PLAN](../device/cheetah/MODEM-PLAN.md) "T0/T1: the ModemManager bridge"):**
  - Its own package, `omamobile-mmd`, with `conflicts=(modemmanager)` and **no `provides=`**: nothing in Arch or Arch Linux ARM hard-depends on `modemmanager` (gnome-calls, chatty, networkmanager and geoclue need only libmm-glib; mmsd-tng is AUR-only and also needs only libmm-glib).
  - It ships `omamobile-mmd.service`, not `ModemManager.service`, with no `dbus-org.freedesktop.ModemManager1.service` alias: `Type=dbus`, `BusName=org.freedesktop.ModemManager1`, `Conflicts=ModemManager.service`, `WantedBy=omamobile-sitd.service`, and not enabled by the package. It also ships the D-Bus bus policy (only root owns the name) and MM's polkit actions.
  - **No D-Bus activation file**, so no client can start the bridge. Enabled, it starts with `omamobile-sitd`.
  - No `mmcli` and no CLI of our own. Phone runbooks read the modem through libmm-glib with `test/libmm-status.py`; mmcli runs only in the conformance container (`test/conformance`).
- **Packaging, superseded (the design before T1, kept for history; not built):** a package named `omamobile-mm` with `provides=(modemmanager)` and `conflicts=(modemmanager)`, shipping `ModemManager.service` aliased `dbus-org.freedesktop.ModemManager1.service`, the bus policy, a D-Bus activation file, and `mmcli` or a small `omamobile-mm-cli`. T1 dropped `provides=` (no package needs it), the activation file (so no client can start the bridge) and the takeover of ModemManager's unit name.
- **Access control.** MM gates its methods with polkit actions: `org.freedesktop.ModemManager1.Control`, `.Device.Control`, `.Messaging`, `.Voice`, `.USSD`, `.Location`, `.Time`, `.CellBroadcast`, `.Contacts` (`data/org.freedesktop.ModemManager1.policy.in.in`). We check the same action IDs with the same defaults (the active local session allowed), so existing polkit rules mean the same thing. Reading properties stays open, as in MM.
- **Bus-name behaviour, as built (T1).** The bridge owns the name from its start (`lib/main.py`; it exits if it can't own the name) and exports the Manager at once. It connects to sitd's socket once it holds the name, and exports the modem, with `InterfacesAdded`, when sitd's first status arrives. When sitd's socket goes away it removes the modem and its objects with `InterfacesRemoved`, and keeps the name. The release-and-re-request trick (§1.3) is not implemented: T1's container run of GNOME Calls and Chatty passed without it, and it waits until a client is seen to need it (T2 checks Calls and Chatty against a modem that appears late).
- **Bus-name behaviour, superseded (the design before T1, kept for history):** own the name only once sitd reports the modem up. T1 owns it from the start instead, and only the modem object waits for sitd.

### 1.6 Mobile data: NetworkManager or our own route

Today `omamobile-sit-data` puts `rmnet0` behind Wi-Fi with metric 700, and NetworkManager leaves `rmnet*` unmanaged (`90-omamobile-rmnet.conf`). Once `omamobile-mmd` exports a modem, NM creates a modem device for it, and a `gsm` connection could drive the bearer through `Simple.Connect`, configuring `rmnet0` from the bearer's static `Ip4Config`/`Ip6Config`.

- **T1-T2:** export the modem but no NM connection. NM shows the device as disconnected and leaves it alone. `omamobile-sit-data` keeps the route. The Bearer object still has to exist, because mmsd-tng looks for a connected bearer (§1.7).
- **T3 (recommended, Q5):** hand data to NM. The quick-settings "Mobile data" tile becomes `nmcli`, roaming and metered flags come from NM, and `omamobile-sit-data`'s route logic retires. Keep its dead-bearer detection in sitd.

### 1.7 MMS

| Need | How | Ready? |
| --- | --- | --- |
| WAP push (the MMS notification) arrives as a binary SMS | sitd passes the PDU's user data through; the bridge exports an `Sms` with `Data` set and `Text` empty, which mmsd-tng picks up | No: the codec keeps the bytes but nothing passes them on (T0, T3) |
| An APN that carries MMS | mmsd-tng's `MMS_APN` must match the connected bearer's APN. mmsd-tng supports no separate MMS bearer ("limitations of Modem Manager", its README), so the carrier must allow MMS on the internet APN. Many US carriers do; check ours (Q8) | Our config has one APN (`[network] apn`) |
| Fetch from the MMSC over mobile data, even with Wi-Fi up | mmsd-tng binds HTTP to the bearer's interface (`SO_BINDTODEVICE`, `src/service.c:3720-3732`) and resolves through that interface's DNS (c-ares or systemd-resolved with the ifindex). Needs `CarrierMMSC`, `CarrierMMSProxy`, or `http://mms.invalid` to look them up in mobile-broadband-provider-info | **Depends on M4.3:** rmnet0 is configured IPv4 only (MODEM-CLIENT §1.3). If the carrier's bearer is IPv6-only (common on T-Mobile's network [I]), MMS needs IPv6 on rmnet0 first. The packet processor (MODEM-PLAN 6.3) is built but untested on hardware; the legacy buffers carry data meanwhile |
| Sending MMS | mmsd-tng posts the M-Send.req to the MMSC the same way | as above |
| Storage and UI | mmsd-tng stores messages and serves `org.ofono.mms` on the session bus; Chatty and our app are its clients | install `mmsd-tng` (T3) |
| Group MMS | MMS with several recipients; mmsd-tng handles the PDUs | with the above |

**What our data path still lacks for MMS** (MODEM-PLAN 6.3 and MODEM-CLIENT §1.3): M4.3 passing on the phone, IPv6 on `rmnet0` (or proof that the carrier gives IPv4), and the bearer exported as a Bearer object. Throughput isn't an issue for MMS (messages are a few hundred kB), so the packet processor isn't a prerequisite.

### 1.8 Requirements against MODEM-PLAN

| Requirement | MODEM-PLAN / other plan | State (2026-10-14) |
| --- | --- | --- |
| The CP boots, serves SIT and reboots cleanly | M3.4-M4.1k | **Passed** |
| Registration (LTE, IMS voice and SMS) | M4.2 | Needs a SIM with its PIN lock off and the APN |
| Data (`rmnet0`) | M4.3; 6.3 (pktproc, `CONFIG_CH_EXTENSION` done) | Needs M4.2. IPv6 is a gap |
| SMS both ways | M4.4 | Needs M4.2 |
| Voice with two-way audio (top amplifier) | M4.5 | Needs M4.2 and `omamobile-audio`'s stage `media` |
| The modem at every boot (needed to receive calls at all, and for emergency) | M4.6 | After M4.2-M4.5. One recovered UFS handler pass per reboot |
| Partitions unchanged after every run | M3.5 / M4.7 | Repeat after each phone phase here |
| The modem's DMA confined (before it is always on) | M3.6 | Design; 1 week |
| Suspend with the modem up (a phone must ring while asleep) | MODEM-PLAN 6.3 (CPIF's suspend refusal, the cp2ap-wakeup pull, the ring check after link wake); SUSPEND-PLAN (modem as a wake source, "Later"); ROADMAP M6 | Not started. **Until then the phone stays awake while the modem is on** |
| CP crash recovery | MODEM-PLAN 6.1 (about one fresh start in twenty crashed during registration; no warm restart) | Recorded only, recovered by a reboot. This matters for emergency availability (§3) |

---

## 2. Call audio

### 2.1 How stock routes voice (facts from our stock captures)

On gs201 the voice path never passes through the application processor. **The AoC and the modem exchange voice frames directly** (the `cp_aoc_rmem` region, which nothing on the AP maps). The host only configures the AoC's mixers and starts two "hostless" PCMs, which tell the AoC to run the call path (`voice_audio.py`: starting them sends the AoC's modem-start command). Stock's `mixer_paths.xml`, voice part:

| Path | Controls |
| --- | --- |
| `voice-callP` (downlink to handset or speaker) | `TDM_0_RX Mixer EP5` = 1 |
| `voice-callP bt` / `usb-headphone` / `hearing-aid`, `call-screen` | `BT_RX Mixer EP5` / `USB_RX Mixer EP5` / `INCALL_RX Mixer EP5` |
| `voice-callC` (uplink from the phone's mics) | `EP4 TX Mixer INTERNAL_MIC_TX` = 1 |
| `voice-callC usb-headset-mic` / `bt-mic` / `hearing-aid`, `call-screen` | `EP4 TX Mixer USB_TX` / `BT_TX` / `INCALL_TX` |
| `telephony-rx-captureC`, `incall-capture{1,2}C` | `Incall Capture Stream0..2` = DL / UL / UL_DL (call recording and call screening) |
| `handset` / `voice-handset` (the earpiece) | top amplifier only, `PCM Source` ASP (DSP bypassed), `AMP PCM Gain` 6 / 7; `voice-handset` raises `Boost Peak Current Limit` to 3.5 A |
| `voice-speaker` + `voice-speaker-post` (speakerphone) | both amplifiers at 3.5 A boost peak, TX slot positions swapped, then the "Enable FIR" delta files (`fast_switch1/2.txt`) and `Digital PCM Volume` 800 |

Beyond the mixer paths, the working stack on this phone model sets `Voice Call Audio Enable`, `Voice Call Mic Source` 1, `Incall Sink Mute` 0, `AoC Modem Downlink ASRC Mode` 1 and a mic gain of 130 cB plus 6 dB. It opens **PCM 4 playback (EP5)** and **PCM 11 capture (EP4)** (MODEM-PLAN 6.1). Our card numbers its PCMs as stock does (AGENTS.md), so those numbers hold. `omamobile-sitd`'s `voice_audio.py` does exactly this and restores every control after the call. Our sound card already describes the back ends these paths need: `BT_RX`/`BT_TX`, `USB_RX`/`USB_TX` and `INCALL_RX`/`INCALL_TX` (`device/cheetah/overlays/aoc-sound-test.dtso`).

### 2.2 The work, per audio route

| Route | What's needed | Depends on | Effort |
| --- | --- | --- | --- |
| **Earpiece** (the default in a call) | AOC-PLAN's design ("Earpiece and calls"): a request to `omamobile-speaker-protection` puts the top amplifier in earpiece mode (ASP, analog ≤ 6, the bottom one muted), and its watchdog expects that mode. Stock's in-call gain is 7 with a 3.5 A boost peak, above our earpiece ceiling of 6, so the ceiling stays until the protection work (C9) says otherwise. **Proximity:** blank the screen and ignore touch while the phone is at the ear. The proximity sensor works (C6, omamobile-sensors). The dialer asks the shell to blank, and the protection service's acoustic-shock mute follows AOC-PLAN | AoC C9 (protection), M4.5 | 5-8 d |
| **Microphone** | Works on the stack we ported (`INTERNAL_MIC_TX`, two-way audio). To check on our phone at M4.5: which mic `Voice Call Mic Source` 1 selects, and whether the AoC applies noise suppression and echo cancellation (the far end will say) | M4.5 | in M4.5 |
| **Speakerphone** | Both amplifiers on `TDM_0_RX Mixer EP5`. Stock uses 3.5 A and its FIR delta files, which mainline's CS35L41 driver lacks ("fast use case switch", AUDIO-PLAN §2). Under our limits: a protection-service "voice-speaker" mode at stage `media`. **Never stock's 800/17 without verified protection** (AGENTS.md) | AoC C9, earpiece mode | 3-5 d |
| **Bluetooth headset (HFP)** | Two candidate paths, to be tested in this order. (1) **Stock's:** SCO stays on the BCM4389's PCM pins into the AoC (the controller's default), and the call path switches to `BT_RX Mixer EP5`/`EP4 TX Mixer BT_TX`. That needs the AoC's BT back end configured as stock does (format and clock: a stock-capture item to read) and the HFP signalling to the headset. PipeWire's gateway does the signalling through MM (§1.3), but only in a PipeWire built with `-Dbluez5-backend-native-mm=enabled` (Q10). (2) **Through the host:** SCO over HCI (AUDIO-PLAN A1's `Write_SCO_PCM_Int_Param`) into PipeWire, with the AoC's in-call capture (`Incall Capture Stream0` DL) bridged to the headset, and the headset's mic into `INCALL_TX`, which stock uses for call screening. Path 2 adds latency and needs a loopback, but it is also how call recording would work | BLUETOOTH-PLAN (works), AUDIO-PLAN A1, M4.5, a PipeWire rebuild | 5-10 d |
| **Wired / USB-C** | The phone has no 3.5 mm jack; only USB audio devices and adapters with a DAC (AUDIO-PLAN 1.5). Stock offloads USB audio through the AoC (`USB_RX`/`USB_TX`, `aoc_usb_driver`), which mainline doesn't need for media. For calls, the host path is path 2 above with `snd-usb-audio` | USB-C B4b (role switch) and B4c (host mode, design only), and SSH off the USB link | 3-5 d after B4c |

### 2.3 UCM, PipeWire and who switches routes

- **The voice PCMs stay out of PipeWire.** EP5 playback and EP4 capture are triggers, not audio streams. The modem side owns them for the length of the call (`voice_audio.py`), and a WirePlumber rule in `omamobile-audio` hides PCMs 4 and 11 so PipeWire never opens them. M4.5's stop condition already checks that PipeWire doesn't hold them.
- **A "Voice Call" UCM verb** beside today's `HiFi` (which has only `Speaker` and `Mic`), with devices `Earpiece`, `Speaker`, `Headset` (Bluetooth) and `Mic`. Their enable and disable sequences set the AoC mixers above and `exec` a request to the protection service, as AOC-PLAN designs it. The verb names no PCM for the voice path, so PipeWire sees it as a profile with no streams. Its job is routing.
- **The routing client.** GNOME Calls expects [callaudiod](https://gitlab.com/mobian1/callaudiod) [I: its exact interface not re-read for this plan], which switches the card to a "Voice Call" profile through the PulseAudio API (PipeWire's pulse server) and selects the output. Using the same verb names means Calls works in T2 unchanged, and omadialer uses callaudiod too (one routing policy, not two). If callaudiod's assumptions don't fit hostless PCMs, the fallback is a small `omamobile-call-audio` service with the same D-Bus surface.
- **Ringtone and vibration** are ordinary PipeWire playback on the speaker (stage `media`) plus the haptics driver (HAPTICS-TORCH-PLAN, `tools/ff-rumble`). The ringer stops before the call path starts, because the amplifiers change mode.
- **Mute** stays in sitd (`audio mute`), exported as callaudiod's mic mute.

**Rough effort for call audio: 14-25 days** (earpiece mode 5-8, speakerphone 3-5, the verb and callaudiod 3-4, Bluetooth 5-10), plus 3-5 days for USB once B4c exists. The earpiece and speakerphone wait on AOC-PLAN's protection work; Bluetooth doesn't.

---

## 3. Emergency calling

**We can't promise that this phone reaches emergency services until it has been tested, and today it can't**: the RIL refuses emergency numbers (MODEM-CLIENT §1.3). Until the tests in §3.3 pass, the phone says so, everywhere a user would try.

### 3.1 What must work

| Case | What it takes |
| --- | --- |
| **Recognising an emergency number** | 3GPP TS 22.101 §10.1.1: "112 and 911 shall always be available. These numbers shall be stored on the ME." Also the SIM's list (EF_ECC), the network's list (sent at attach) and, without a SIM, 000, 08, 110, 999, 118 and 119. sitd merges the SIT emergency list indication (`IND_EMERGENCY_CALL_LIST`) with the fixed list; the bridge exports it as `Sim.EmergencyNumbers`. Every dial request is checked against it **in sitd**, so no UI can place an emergency call as an ordinary one |
| **Placing the call** | An IMS emergency call over the emergency PDN (TS 23.167), or CS fallback where the network has no IMS emergency. SIT has the pieces (`SET_EMC_MODE`, `EMC_NW_SCAN`, `SET_EMERGENCY_CALL_STATUS`, the AIMS emergency messages, the for-emergency flag on `SET_RADIO_POWER`, emergency callback mode). How stock sequences them is unknown, so it comes from the stock RIL's behaviour, read offline as MODEM-SIT-RESEARCH was. **The working stack we ported never implemented it** |
| **No SIM, or a locked SIM** | Limited-service emergency attach is modem firmware's job once the AP asks. sitd must start without a SIM (today start-up ends at `sim_timeout`) and keep the radio on for emergency only. The bridge sets `Voice.EmergencyOnly` true, and MM's clients then refuse other numbers (`src/mm-base-call.c:242` shows the rule) |
| **Airplane mode** | An emergency call turns the radio on (`SET_RADIO_POWER` with the emergency flag) and restores it afterwards |
| **Locked phone** | An "Emergency call" button on the lock screen with a dialpad that accepts only emergency numbers (§7.3). No US rule we found requires it: 47 CFR 9.10 binds the carriers, and Kari's Law and RAY BAUM's Act (FCC 19-76) bind multi-line systems and fixed and VoIP services. But every phone has one and users expect it, so we treat it as required |
| **Modem availability** | A call is only possible while the modem is up. That means M4.6 (the modem at boot, about 100 s after power-on, M4.1h) and no CP crash. About one fresh start in twenty crashed during registration, with no warm restart (MODEM-PLAN 6.1), so the status bar must show "No service" honestly, and a crash must be visible |
| **Location (E911)** | Under 47 CFR 9.10(h)-(i), location accuracy is the carrier's obligation. Carriers get part of it from the handset: Google's Emergency Location Service on Android, which we don't have. What remains: the network's own location, and the modem's control-plane positioning (LPP) or SUPL if the firmware does them without the OS [I: untested on this modem under Linux]. Our GNSS works through GeoClue (GNSS-PLAN G4b, G5). Feeding a fix to the modem (`AIMS_SET_GEO_LOCATION_INFO` exists; our IMS code fills only its Wi-Fi fields) is research. **We must not claim E911 location** |
| **Callback** | After an emergency call the PSAP may call back. Emergency callback mode (`IND_ENTER/EXIT_EMERGENCY_CB_MODE`) keeps the radio up and the phone reachable. The phone must not suspend or turn the radio off in that window |
| **Emergency alerts (WEA)** | Cell broadcast (`IND_NEW_BCST_SMS`, MM's CellBroadcast interface), shown as a full-screen alert. Later (T9). Not a call, but part of a phone's safety role |

### 3.2 The visible warning

- **Until §3.3 passes:**
  - **The dialer.** A persistent banner on the dialpad, and in the first-run dialog: "Emergency calls (911, 112) don't work on this phone yet. Keep another phone for emergencies."
  - **An emergency number dialled anyway.** The dialer shows a full-screen message saying the call can't be placed, with the same advice. The number never fails silently.
  - **The lock screen.** The emergency button opens the same message instead of a dialpad.
- **After it passes,** the banner becomes "Emergency calling tested on <carrier>, <date>. Location may be less precise than on Android." The answer is per carrier and network. Another carrier gets the warning back until it is tested (Q6).
- **The project's documentation** (README, `docs/DEVICES.md`) says the same, in the same words.

### 3.3 Test protocol (never dial 911 to test)

1. **Offline:** number recognition (fixed list, SIM list, network list, no SIM) and refusal of non-emergency numbers in emergency-only mode, against `tools/sit-sim`. Then the lock-screen dialpad in the shell's test harness (in a container, never a nested Hyprland on the laptop).
2. **On the phone, read-only:** with and without the SIM, sitd and the bridge report the emergency list and `EmergencyOnly` correctly. No call.
3. **A lab network (optional, if one is available to us):** an emergency attach and call against a test eNB and IMS in a shielded enclosure. It needs licensed or shielded RF, and we don't have it today.
4. **A live check of the route, only by arrangement.** The owner calls the local emergency centre's **non-emergency** line, agrees a time, and places one call, saying "this is a test" at once. Some state 911 offices publish exactly this procedure, for example [Tennessee's](https://www.tn.gov/commerce/e911/contact-information/how-to-test-your-telephone-with-911.html) and [MARC's guidelines](https://www.marc.org/sites/default/files/2022-05/911_Wireless_Testing_Guidelines.pdf). The human runs this step. An agent never places an emergency call. Record the date, carrier, network type (IMS or CS fallback), whether a location reached the PSAP if they can say, and the kernel release.
5. **933**, which reads back the registered address, is documented for VoIP and business lines ([Bandwidth](https://www.bandwidth.com/support/en/articles/12823286), [Lumen](https://voip.lumen.com/_bvoip/933_FAQ_Customer.pdf)), **not for US mobile carriers**. We found no evidence that T-Mobile, Verizon or AT&T mobile service answers it. Use it only if the carrier documents it.

---

## 4. RCS: a factual check

| Question | Answer, with sources |
| --- | --- |
| Does AOSP Messaging do RCS? | **No.** It sends through `SmsManager` and its bundled MMS library (`sms/SmsSender.java`, `sms/MmsSender.java`) and has no RCS code. A GrapheneOS maintainer said so on [GrapheneOS/Messaging#44](https://github.com/GrapheneOS/Messaging/issues/44) (2025-04-25). Google withdrew the RCS APIs planned for Android Q ([MobileSyrup, 2019-02-22](https://mobilesyrup.com/2019/02/22/google-hides-rcs-apis-developers/)) |
| Who runs RCS for US carriers? | Google Jibe. T-Mobile connected to Google's RCS servers in 2020 ([Android Police](https://www.androidpolice.com/2020/05/26/t-mobile-now-connects-to-googles-rcs-servers/)), Verizon announced its move to Jibe on 2024-02-01 ([9to5Google](https://9to5google.com/2024/02/01/verizon-rcs-google-jibe/)), and the carrier bundles behind iOS 18's RCS point at Jibe too ([9to5Mac](https://9to5mac.com/2024/06/25/us-carriers-rcs-iphone-ios-18-beta/)) |
| Can a third-party client sign up with Jibe? | **No public route.** Jibe Cloud is sold to carriers, and there is no client registration programme |
| What does provisioning require (GSMA)? | Universal Profile 4.0 ([RCC.71 v4.0](https://media.gsma.com/assets/2026/rcs/RCC.71+v4.0.pdf), 2026-02-19), with RCC.14 v13.0 and RCC.07 v17.0. The client fetches its configuration over HTTPS from `config.rcs.mnc<MNC>.mcc<MCC>.pub.3gppnetwork.org` (RCC.14 §2.2.1). It sends terminal vendor, model and software version, client vendor and version, and the IMSI or MSISDN, and authenticates by SMS one-time password, GBA, or EAP-AKA through OpenID Connect (§2.6-2.8). **RCC.14 §2.4:** those vendor and version values "should be agreed with the associated Service Provider prior to any device or client commercialization". **§2.11 (client authenticity):** the server may reject a client from its parameters (403) or demand a platform attestation (426) |
| Is a non-Google client let in? | **In practice, no.** In February 2024 Google Messages began refusing RCS on rooted phones and custom ROMs through Play Integrity ([Android Authority](https://www.androidauthority.com/google-silently-blocking-rcs-rooted-android-phones-custom-roms-3421652/), [9to5Google](https://9to5google.com/2024/02/29/google-messages-rcs-rooted/)). GrapheneOS's maintainer (#44, 2025-06-18): "We are not free to implement an equivalent to Google Messages without them explicitly permitting us." End-to-end-encrypted RCS (UP 3.0+, RCC.16) also needs a GSMA-assigned vendor identity and trust-list certificate |
| Is there any FOSS RCS client? | **None that works with Jibe or a US carrier.** [rcsjta](https://github.com/android-rcs/rcsjta) (Apache-2.0) is the GSMA/Orange RCS-e stack, last pushed around 2017, before Universal Profile. [rust-rcs-client](https://github.com/Hirohumi/rust-rcs-client) (Apache-2.0) is a library aimed at China's carriers, with no Jibe support stated. An [/e/OS feasibility probe](https://community.e.foundation/t/feasibility-probe-for-google-free-carrier-native-rcs-support-on-e-os/81458) (2026-04-27) and a [Sailfish request](https://forum.sailfishos.org/t/add-rcs-service-support-to-messages-app/708) are proposals only. Beeper reaches RCS only through a real Android phone running Google Messages. Our search found nothing in Chatty or libpurple |
| Does our modem matter? | SIT has `AIMS_RCS_CONFIG_MANAGE` (0x0d52), the modem side of stock's RCS configuration. The barrier is the provisioning server's acceptance of the client, not the modem |

**Conclusion:** RCS is a **non-goal** for omamessages. Messages to RCS users still arrive, because carriers fall back to SMS and MMS: group chats with RCS users become group MMS. Keep the message model open to a second transport (§9.3), and revisit only if a carrier or Google opens client registration. The owner should accept this (Q11).

---

## 5. AOSP Messaging and Dialer: what they do, and what we take

Both apps are Apache-2.0 and both READMEs now say: "This app is not actively supported and the source is only available as a reference. This project will be removed from the source manifest sometime in the future." (Messaging `main` @ `de315b7`, Dialer `main` @ `544da8b`; Dialer's tree dates from a 2018 code drop.) We take them as **the model for behaviour and layout**. We take no code: they are Java on Android's frameworks, and our apps are Rust on GTK. Paths below are under `src/com/android/messaging/` and `java/com/android/`.

### 5.1 Messaging

| Feature | AOSP Messaging | omamessages |
| --- | --- | --- |
| Conversation list (with archive, multi-select) | `ui/conversationlist/` | **Yes**, with pinning |
| Conversation view and compose | `ui/conversation/` | **Yes** |
| Group MMS | `ui/appsettings/GroupMmsSettingDialog.java`, `ui/conversationsettings/PeopleAndOptions*` | **Yes** (through mmsd-tng) |
| Attachments: images, video, audio, vCard | `ui/mediapicker/`, `ui/attachmentchooser/`, `ui/photoviewer/` | **Images, video, vCard first**; audio later. Pick through the portal file chooser or our camera (omacam) |
| Drafts | `datamodel/action/{Read,Write}Draft*Action.java` | **Yes** |
| Delivery reports | `datamodel/action/ProcessDeliveryReportAction.java`, `receiver/SendStatusReceiver.java` | **Yes** (MM's `DeliveryReportRequest`/`DeliveryState`) |
| Blocking | its own `participants.blocked` column (`datamodel/DatabaseHelper.java`), `ui/BlockedParticipants*`; it doesn't use Android's `BlockedNumberContract` | **Yes**, but one block list shared with the dialer (§9.3) |
| Search | **none** (the list menu has no search) | **Yes** (SQLite FTS5), better than the model |
| Notifications with direct reply | `datamodel/BugleNotifications.java` (`RemoteInput`), `ui/RemoteInputEntrypointActivity.java` | **Yes**, needs a shell change (§7.2) |
| MMS settings and APN | `ui/appsettings/Apn*`, `sms/ApnDatabase.java`, `res/xml/apns.xml` | **Settings page** for MMSC, proxy and APN (mmsd-tng's settings) |
| SIM selection | `ui/conversation/ConversationSimSelector.java` | No (one SIM slot in use; the eSIM is out of scope) |
| Storage | its own `bugle_db`, synced with the Telephony provider's `mmssms.db` | **Own SQLite** (§9.3) |
| Class-0 ("flash") SMS, low-storage warning, widgets | `ui/ClassZeroActivity`, `HandleLowStorageAction`, `widget/` | Class 0 as a dialog; a home-screen widget later (OWL) |
| Backup | none (`allowBackup="false"`) | **Export/import** (§9.4) |
| Not in AOSP, worth adding | emoji picker, location attachment, search | emoji through the keyboard; search (above) |

### 5.2 Dialer

AOSP Dialer's bottom navigation has four tabs: speed dial, call log, contacts and voicemail (`dialer/main/impl/bottomnav/BottomNavBar.java`, `TabIndex`). **So contacts are a tab of the phone app**, and omadialer follows that (§6).

| Feature | AOSP Dialer | omadialer |
| --- | --- | --- |
| Dialpad with smart dial (T9 matching of contact names) | `dialer/dialpadview/`, `dialer/smartdial/` | **Yes** |
| Call log and call details | `dialer/calllog/`, `dialer/calldetails/` | **Yes** (own SQLite) |
| Favourites / speed dial | `dialer/speeddial/` | **Yes** (starred contacts) |
| Contacts tab and search | `dialer/contactsfragment/`, `dialer/searchfragment/` | **Yes** (§6) |
| In-call UI: mute, speaker/audio route, keypad, hold, swap, add call, merge, manage conference | `incallui/`; buttons in `incall/protocol/InCallButtonIds.java`; `ConferenceManagerFragment`; `incallui/audioroute/` | **Yes**: mute, route (earpiece, speaker, Bluetooth), keypad (DTMF) first; hold/swap/merge in T8 (MM `HoldAndAccept`, `JoinMultiparty`) |
| Answer screen | `incallui/answer/` | **The shell** while locked; the app while unlocked (§7.1) |
| Proximity screen-off | `incallui/ProximitySensor.java`, `answerproximitysensor/` | **Yes**, through the shell (§2.2) |
| DTMF, post-dial pauses (`,` and `;`) | `DialpadFragment`, `PostCharDialog*` | **Yes** |
| Voicemail (OMTP, CVVM, VVM3) | `voicemail/impl/` (protocol, SMS, IMAP, sync); UI in `dialer/voicemail/listui/` | **Plain voicemail** (call the mailbox, long-press 1) first. **Visual voicemail through vvmd** later (§5.3) |
| Blocked numbers, spam | `dialer/blocking/` (uses `BlockedNumberContract`); `dialer/spam/` is a stub (Google's spam service isn't in AOSP) | **Block list yes** (shared). Spam: unknown-caller silencing as a setting; no spam database |
| RTT, assisted dialing, call composer, Duo | `dialer/rtt/`, `assisteddialing/`, `callcomposer/`, `duo/` | No. Assisted dialing (adding the country code when roaming) later, with the `phonenumber` crate |
| Call recording | none | No (path 2 of §2.2 would allow it; legality varies; not planned) |
| Emergency dialer | not in Dialer: `packages/services/Telephony/src/com/android/phone/EmergencyDialer.java` | **In the shell's lock screen** and in the app's dialpad (§3, §7.3) |
| USSD | through Telephony | **Yes** (codes like `*#...#` through `Modem3gpp.Ussd`), T8 |

### 5.3 Visual voicemail

OMTP VVM ([GSMA page for v1.3](https://www.gsma.com/newsroom/gsma_resources/omtp-visual-voice-mail-interface-specification-v-1-3/); successor TS.46) works by SMS commands to the carrier and STATUS/SYNC SMS back to an application port. The STATUS reply carries IMAP credentials, and voicemails are fetched over IMAP, by Android over **cellular** only (`voicemail/impl/sync/VvmNetworkRequestCallback.java`). AOSP's CarrierConfig gives T-Mobile US `vvm_type_cvvm`, port 1808, destination 122. On Linux, [vvmd](https://gitlab.com/kop316/vvmd) handles cvvm, vvm3 and AT&T's protocol through MM, and vvmplayer is its GUI (postmarketOS ships both). **Plan:** reuse vvmd behind our MM bridge, and show its messages in omadialer's voicemail tab through vvmd's D-Bus API (T9). That needs binary SMS on an application port (the same `Data` path as WAP push) and IMAP over the cellular bearer (the same interface binding as MMS).

---

## 6. Contacts

**One address book for every app**, and contacts as **a tab in omadialer**, as in AOSP Dialer. A "Contacts" launcher entry opens the dialer on that tab (`omadialer --contacts`), so the home screen still has a Contacts icon.

| Option | For | Against |
| --- | --- | --- |
| **(A) A vCard folder (vdir: one `.vcf` per contact) in `~/.local/share/contacts/<book>/`**, synced over CardDAV by a vdir sync tool (vdirsyncer, or pimsync, whose `libdav` is a Rust CardDAV client) | Plain files: easy to back up, import and export, and readable by other tools. Rust crates exist (`vcard4` 0.7.3, `calcard` 0.3.14, `libdav` 0.11.0). No daemon. Works offline | Neither GNOME Calls nor Chatty reads it (the T2 test apps show numbers only). No Google-account setup through a GUI; CardDAV is configured in a file |
| **(B) evolution-data-server**, with GNOME Online Accounts for Google and CardDAV | The GNOME stack's address book: Calls reads it through folks, Chatty through libebook, and GNOME Contacts and Calendar use it. Online accounts through a GUI | A set of D-Bus services resident on the phone. **No Rust bindings** (no EDS or folks crate on crates.io), so we would generate GObject bindings or speak its D-Bus API ourselves. Our apps would depend on GNOME's PIM stack |
| (C) Both: vdir as the source, mirrored one-way into a local EDS book | Calls and Chatty see names too | Two stores to keep consistent; only worth it if GNOME's apps stay in daily use |

**Recommendation: (A).** Our own apps are the daily drivers. GNOME Calls and Chatty are a T2 test bench, not the product. The `omatel-contacts` crate owns reading, writing, watching (inotify) and number matching: numbers normalised to E.164 with a libphonenumber port, for example the `phonenumber` crate [I: licence and maintenance to check]. A contact editor (name, numbers with labels, email, photo, notes, starred) lives in the dialer's contacts tab. Import a `.vcf` exported from Android. If the owner prefers GUI account setup or plans to use GNOME Calendar with an online account, (C) is the upgrade path, and EDS is installed by then anyway (Q4).

---

## 7. Shell integration

### 7.1 Incoming calls, over the lock screen and not

- **Locked phone.** Omarchy's lock is a session lock (`WlSessionLock` in `shell/plugins/lock/Service.qml`), and a session lock hides every other surface, as patch 0003 notes for the on-screen keyboard. **So an app can't draw over the lock screen: the incoming-call screen while locked has to be part of the lock plugin.**
  - It is a full-screen call card: caller name or number, Answer and Decline, "Reply with message" (a few canned SMS replies through omamessages), and silence on a volume key.
  - After answering, the lock shows in-call controls (mute, speaker, keypad, hang up) and stays locked. Unlocking opens omadialer's full in-call screen.
  - It is fed by omadialer's session-bus API (§9.1) through a small JSON-lines helper process, as `omamobile-osk-watch` does for the keyboard, because QML has no general D-Bus client.
  - This is a change to Omarchy's lock plugin, so it goes in our Omarchy patch series (`packages/omamobile-omarchy/patches`). It should be written to go upstream as a generic "lock-screen card" hook rather than a phone-only hack.
- **Unlocked phone.** omadialer raises its own full-screen answer page on the current workspace. While the user is in another app, a heads-up banner with Answer and Decline comes from the notification service (§7.2), and a tap opens the full page.
- **Screen off.** An incoming call wakes the panel (DPMS on through the shell's wake path, as `omamobile-keys` does) and shows the lock-screen card. Announce this in the runbooks: it changes the feel of the phone.
- **While the device is asleep.** It can't ring until the modem can wake the AP (§1.8). Until then, suspend stays off while the modem is on.

### 7.2 Notifications with reply

- Omarchy 4.0.4's `NotificationServer` (`shell/plugins/notifications/Service.qml`) sets `actionsSupported`, `imageSupported` and `persistenceSupported`, **but not `inlineReplySupported`**. Quickshell 0.3 has it (`inlineReplySupported`, `hasInlineReply`, `sendInlineReply` in its `Notifications` QML types).
- **Change (Omarchy patch, upstreamable):** advertise `inline-reply`, and give the toast and the shade a text field with Send that calls `sendInlineReply` and closes the notification. The on-screen keyboard has to appear for that field (the screensaver patch 0006 shows the gsettings key involved).
- **omamessages** sends its notifications to `org.freedesktop.Notifications` directly (zbus) with an `inline-reply` action and listens for `NotificationReplied`. That is the freedesktop extension Quickshell implements. GTK's `GNotification` has no reply field [I].
  - It uses one notification per conversation, replaced as messages arrive. The category is `im.received` and the hints are `sender-pid` and `desktop-entry`.
  - On the lock screen it shows only "New message", unless the owner turns on details (Q7).
- **Missed calls** are a notification from omadialer, with Call back and Message actions.
- **Do not disturb** (the existing quick-settings tile) silences ringing too. A "starred contacts and repeat callers ring anyway" exception follows Android's model (later).

### 7.3 The emergency dialer on the lock screen

An "Emergency call" button on the lock plugin's keypad page (patch 0003 added the number pad) opens a dialpad inside the lock surface. It accepts only numbers that sitd's emergency list accepts, places the call through MM (`Voice.CreateCall`) and shows the call's controls without unlocking. Until §3.3 passes, the button opens the warning instead (§3.2). This is the same lock-plugin work as §7.1, in the same patch.

### 7.4 Default apps

- **Desktop files.** omadialer declares `MimeType=x-scheme-handler/tel;x-scheme-handler/callto;`, and omamessages declares `x-scheme-handler/sms;x-scheme-handler/smsto;x-scheme-handler/mms;x-scheme-handler/mmsto;`.
- **Defaults.** `omamobile-apps` sets both as defaults in `/usr/share/applications/mimeapps.list`, or through `omamobile-setup-user` with `xdg-mime default`. A `tel:` link in Chromium then opens the dialer with the number filled in, and `sms:` opens a new conversation.
- **Other apps.** `omamobile-apps` moves `gnome-calls` and `chatty` out of `optdepends` once our apps pass their phase exits. Until then they can be installed for testing (T2).
- **App grid.** Desktop files carry `X-Purism-FormFactor=Workstation;Mobile;` as the camera's will. The home screen's default dock gets Phone and Messages.

### 7.5 Modem status and the quick-settings tile

- **Status bar.**
  - It shows signal bars (from `Signal.Lte.rsrp` or `Modem.SignalQuality`), the technology (LTE, 5G), roaming, and "No SIM", "SIM locked", "Emergency calls only" or "No service".
  - An open-call indicator returns to the call when tapped.
  - The plugin reads MM's properties through a small helper (`omamobile-modem-status --watch`, JSON lines, the osk-watch pattern) so the QML stays free of D-Bus. Phosh's `phosh-wwan-mm.c` is a reference for which properties matter.
- **Quick settings.** "Mobile data" (in the roadmap today, waiting on M4) toggles NM's `gsm` connection (`nmcli`) from T3, or `omamobile-sit data on|off` before that. A long press opens a sheet with the operator, signal, APN and a roaming switch. "Airplane mode" also turns the radio off (`Modem.Enable(false)`).
- **SIM PIN.** If the SIM asks for a PIN, the shell shows an unlock sheet (`Sim.SendPin`). Until T8 the RIL can't do this, so the SIM's PIN lock must stay off (as M4.2 already says).

---

## 8. The other apps: reuse or build

The owner's guess holds: **camera, phone and messages are the only apps to write.** Everything else exists, is adaptive, and is better spent as patches and settings.

| Need | Choice | Reason |
| --- | --- | --- |
| Camera | **Build:** omacam | [CAMERA-APP-PLAN](CAMERA-APP-PLAN.md) |
| Phone (dialer, call log, contacts) | **Build:** omadialer | This plan; nothing existing fits our stack and look while sharing a contacts store and our lock-screen design |
| Messages (SMS, MMS) | **Build:** omamessages | This plan |
| Contacts | **Tab in omadialer** plus a launcher entry | As on Android (§6); a separate app would duplicate the store and editor |
| Gallery | **Reuse:** GNOME Loupe plus omacam's small viewer | Owner's answer to CAMERA-APP-PLAN Q6; Loupe is adaptive and a postmarketOS default |
| Clocks and alarms | **Reuse GNOME Clocks, plus a wake helper** | Clocks is adaptive, but **its upstream alarms don't wake a suspended phone**: MR [!344](https://gitlab.gnome.org/GNOME/gnome-clocks/-/merge_requests/344) "alarm: Use wakeup timer" is an open draft (it needs `CAP_WAKE_ALARM`). KDE's KClock wakes through PowerDevil, which we don't run. **Our hardware can do it:** the S2MPG12 RTC is `rtc0` with a `wakealarm`, and `rtcwake -m freeze -s 30` woke the phone by itself (SUSPEND-PLAN S3b). Today it doesn't matter, because suspend isn't on by default (S8). Once it is, add `omamobile-alarm-wake`, a small root helper or a system `.timer` with `WakeSystem=` set from the next Clocks alarm, or carry MR !344 as a patch. Not a new clock app |
| Maps | **Reuse:** GNOME Maps (installed; GNSS through GeoClue, GNSS-PLAN G5) | Works today |
| Calendar | **Reuse:** GNOME Calendar (adaptive) | It brings EDS, which is relevant to Q4 |
| Notes | **Reuse:** a text editor (GNOME Text Editor, or an Omacom editor if the owner prefers) | Nothing phone-specific |
| Files | **Reuse:** Nautilus (adaptive; its chooser already serves our file dialogs) | Works today |
| Settings | **Reuse:** Omarchy's menus and our quick settings; add a **"Mobile network" sheet** (APN, MMS settings, roaming, SIM PIN) in the shell | The phone-only settings are few and belong next to the tile |
| App store | **Reuse:** Omarchy's own package install flow; GNOME Software only if the owner wants Flatpak browsing | Not a phone-specific need |
| Keyboard | **Reuse:** squeekboard (installed, with our hide-button plugin) | postmarketOS's Phosh moved to Stevia in 2025, but squeekboard works with our shell; revisit only for layout or prediction needs |
| Browser | **Reuse:** Chromium (Omarchy's), with our mobile flags | AGENTS.md's Chromium notes |
| Visual voicemail | **Reuse:** vvmd, shown inside omadialer | §5.3 |
| Weather, music, video | **Reuse** (GNOME apps or Omarchy's choices) | Nothing phone-specific |

---

## 9. Architecture of omadialer and omamessages

### 9.1 One repository, two apps, shared crates

**Superseded (0.2.0, the owner's request):** one repository per app. `omatel` keeps the shared crates and `omatel-agent`; [omaphone](https://github.com/derekross/omaphone) and [omamessages](https://github.com/derekross/omamessages) were split out of it with their history and use omatel's crates as git dependencies pinned to an omatel release tag (in their `Cargo.lock`). The layout below is the original design.

Working names as the owner gave them, shown as **"Phone"** and **"Messages"**. One repository, because the two apps share most of their non-UI code and are released together (Q1):

```
omatel/                       (GPL-3.0-or-later; own repository)
  crates/
    omatel-mm        zbus 5 proxies generated from MM 1.24's introspection XML (zbus-xmlgen),
                     plus typed wrappers: Modem, Voice, Call, Messaging, Sms, Sim, Signal, Bearer;
                     works against the real ModemManager and against omamobile-mmd alike
    omatel-contacts  vdir address book: read/write/watch, search, E.164 matching (§6)
    omatel-store     SQLite schemas and migrations (rusqlite): messages, call log, block list
    omatel-theme     the Omarchy theme from colors.toml (gliff's theme.rs approach; shared with omacam,
                     so possibly its own small crate repository later)
    omatel-notify    org.freedesktop.Notifications client with inline reply
  apps/
    omadialer        GTK 4/libadwaita: tabs Favourites, Recents, Contacts, Voicemail; dialpad; in-call
    omamessages      GTK 4/libadwaita: conversations, thread, compose, attachments, settings
  data/              desktop files, D-Bus activation files, systemd user units, icons
```

- **Each app runs in the background.** A systemd user unit starts `omadialer --service` and `omamessages --service` at login, as `gnome-calls --daemon` and Chatty do. Each is a `gtk::Application` with no window until it is needed.
  - The dialer has to show an incoming call within about a second, and a cold GTK start on the phone may take longer [I: measured in T6].
  - The messages service has to store every SMS the bridge announces, even when nobody opens the app.
  - The cost is two resident processes [I: memory measured in T6; target under 40 MB each]. Q12 asks whether that is acceptable or whether one headless agent should own both background jobs.
- **omadialer exports `org.omamobile.Phone1`** on the session bus: `IncomingCall`/`CallStateChanged` signals, and `Answer`, `Decline`, `Hangup`, `SetMute`, `SetRoute`, `SendDtmf`, `Dial(number, emergency)`. The shell's lock card (§7.1), the emergency dialpad (§7.3) and the status bar use it. It is a thin layer over MM's Call objects plus the audio routing (callaudiod), so the shell never talks to the modem directly.
- **omamessages exports `org.omamobile.Messages1`**, the same idea: `Send(number, text)` for the call card's canned replies, and `OpenConversation`.
- **Looks:** libadwaita's adaptive widgets (navigation views, bottom bars, breakpoints), coloured from Omarchy's theme through omatel-theme, following gliff. The in-call screen and the dialpad are our own large-touch layouts, as stock's are.

### 9.2 omadialer, as data flows

- **An incoming call** goes: MM `CallAdded` (Direction incoming, State ringing-in) → omadialer's service → ringtone and vibration → the shell's card (locked) or the app's answer page (unlocked) → `Call.Accept` → callaudiod routes to the earpiece → proximity blanking on.
- **The call log** is written from Call state changes: number, direction, start, duration, how it ended, and missed or rejected. It never comes from the modem, which keeps no history.
- **Blocking:** a blocked number's incoming call is hung up at once, logged as blocked and not shown. A setting can silence unknown callers instead.

### 9.3 Storage (SQLite, one file per app, WAL)

- **omamessages** (`~/.local/share/omamessages/messages.db`):
  - Tables: `conversations` (participants set, archived, pinned, muted, draft), `participants` (number E.164, contact link), `messages` (conversation, direction, transport `sms`/`mms`, text, timestamps sent/received/delivered, state, MM message reference, mmsd-tng message path), `parts` (MMS attachments as files under `parts/`, MIME type, size), and an FTS5 index over text.
  - **The transport column is what leaves room for RCS** (§4) or anything else later.
  - Incoming SMS: copy into the database (fsync), then `Messaging.Delete` from the bridge, so a crash between the two duplicates a message rather than losing one, and duplicates are filtered by reference and timestamp.
  - MMS live in mmsd-tng's store, and our database references them, as Chatty does.
- **omadialer** (`~/.local/share/omadialer/calls.db`): `calls`, `favourites` order.
- **Shared:** the block list (`~/.local/share/omatel/blocked.db`) is used by both apps.
- **Private data:** these files hold numbers and message text. They never go into the repository or a log, the same rule as sitd's store (`/var/lib/omamobile-sit`, 0600). Logs record states and IDs only.

### 9.4 Import and export

- Export and import of messages and the call log in our own documented JSON (versioned), with MMS parts alongside, as one archive.
- Import of an Android history: the XML that common Android SMS and call-log backup apps write [I: format to check before relying on it], and a `.vcf` for contacts. One-time migrations from the owner's current phone (Q9).
- Import from Chatty's database, if someone used Chatty during T2 (optional).

### 9.5 Build and test

- **Builds** as CAMERA-APP-PLAN §5.3: cross-compiled aarch64 in the container, vendored crates, `packages/omadialer` and `packages/omamessages` PKGBUILDs here pointing at the external repository.
- **Tests without a modem:** `omatel-mm` against a **mock MM service** (zbus server in the test, scripted calls and SMS). Then the whole chain in the container, with GTK under a headless compositor (never a nested Hyprland on the laptop): our apps → `omamobile-mmd` → `omamobile-sitd` → `tools/sit-sim`. That is the same chain as on the phone, minus the CP.
- **Tests with GNOME Calls and Chatty** run the same way, against the bridge in the container (T1 exit).

---

## 10. Phases, estimates, risks and questions

One developer, working days. The human approves every phone step, and each phone phase ends with MODEM-PLAN's M3.5 partition check. **Announce before running:** the radio transmits from M4.2, calls ring and play through the amplifiers, and the panel wakes on a call. Phases are ordered by dependency: **the MM-compatible service first, proven with GNOME Calls and Chatty before our apps exist.**

| Phase | Work | Needs | Effort | Exit criteria |
| --- | --- | --- | --- | --- |
| **T0** RIL extensions | sitd: event subscription; signal, operator, SIM info; WAP push and status reports passed on; hold/swap/conference and call waiting (behind the allow-list); tests against `tools/sit-sim` extended for each | none (offline) | 6-9 d | `packages/omamobile-modem-sit/test/all` passes with the new cases; no numbers in logs |
| **T1** `omamobile-mmd` | The bridge (§1.4 subset, §1.5): ObjectManager, Modem, 3gpp, Sim, Signal, Voice/Call, Messaging/Sms with `Data`, Bearer (read-only), polkit; the package with `conflicts=(modemmanager)` and no `provides=` (§1.5, as built); tests in the container with mmcli, GNOME Calls and Chatty against `sit-sim` | T0 | 10-14 d | In the container: Calls places, answers and hangs up a simulated call with DTMF; Chatty sends and receives a simulated SMS; no client errors on missing interfaces |
| **T2** On the phone | MODEM-PLAN M4.2-M4.5 (needs a SIM), then the bridge, GNOME Calls and Chatty on the phone; M4.6 (the modem at boot) | a SIM; owner's go | 3-5 d | A real call both ways and SMS both ways from Calls and Chatty; M3.5 unchanged |
| **T3** Data and MMS | Bearer export, NM `gsm` connection (Q5), IPv6 on rmnet0 if the carrier needs it, mmsd-tng with the carrier's MMSC; group MMS | T2 (M4.3) | 6-10 d | An MMS with an image received and sent over mobile data while Wi-Fi is up; a group MMS |
| **T4** Call audio | Earpiece mode in the protection service, the Voice Call UCM verb, callaudiod, the WirePlumber rule; speakerphone; Bluetooth HFP (path 1, then 2; the PipeWire rebuild, Q10) | AoC C9; T2 | 14-25 d | Earpiece at a comfortable level with the bottom amplifier silent; speakerphone within the stage's ceilings; a call on a Bluetooth headset with answer and hang-up from its button |
| **T5** Shell | Lock-screen call card and in-call controls, emergency button and dialpad (warning mode first), inline reply in notifications, status bar signal and states, the Mobile data tile and Mobile network sheet, `tel:`/`sms:` defaults | T1 (can start against the mock) | 8-12 d | Answering a call from the lock screen without unlocking; replying to an SMS from the notification; the status bar matches `mmcli` |
| **T6** omadialer + shared crates + contacts | The workspace (§9.1), theme, contacts store and editor, dialpad, call log, favourites, in-call screen (mute, route, keypad), proximity, missed-call notifications, `org.omamobile.Phone1` | T1; T4 for routing | 21-28 d | The owner uses it instead of Calls for a week; incoming-call UI within 1 s of the ring [I: measure] |
| **T7** omamessages | Conversations, threads, compose, attachments, delivery reports, search, blocking, notifications with reply, MMS through mmsd-tng, settings, export/import | T3, T5, T6's crates | 15-20 d | The owner uses it instead of Chatty for a week; no lost or duplicated message across a forced kill of the app |
| **T8** Emergency and calling extras | sitd: emergency dial (IMS emergency / CS fallback as the stock RIL sequences it), start without a SIM, emergency-only mode, radio on for emergency, callback mode; SIM PIN entry; USSD; hold/merge in the UIs. **Then the §3.3 test protocol** | T2; the owner and the local emergency centre for step 4 | 6-12 d + arranging the test | §3.3 steps 1-2 pass; step 4 recorded by the owner; the warning updated (§3.2) |
| **T9** Later | Visual voicemail via vvmd (2-4 d); WEA alerts (3-5 d); network time; USB call audio (3-5 d after USB-C B4c); suspend with the modem up (MODEM-PLAN/SUSPEND-PLAN work, not this plan's) | as listed | | Each its own runbook |

**Totals:**

| Milestone | Phases | Effort |
| --- | --- | --- |
| A working phone with existing apps: calls, SMS, data and MMS through GNOME Calls and Chatty, audio at the speaker's stage | T0-T3 | **25-38 days**, plus the SIM, and the M4 steps passing on hardware |
| Our own apps with proper call audio and shell integration | T4-T7 | another **58-85 days** |
| Emergency calling | T8 | **6-12 days** plus the arranged test |
| **Everything through T8** | T0-T8 | **about 90-135 days** |

T4 and T5 can run in parallel with T6 and T7 if a second person helps.

### 10.1 Risks

| Risk | Mitigation |
| --- | --- |
| **A client relies on an MM detail we don't emulate** (property types, object paths, signal order, the bus-name trick ofono2mm needed) | Test each client in the container first (T1). Read the client's libmm-glib calls when one misbehaves; ofono2mm's history is a map of what bit them |
| **A distribution package hard-depends on `modemmanager`** and pulls the real daemon in | None does at T1 (§1.5), so `omamobile-mmd` has `conflicts=(modemmanager)` and no `provides=`; add `provides=` only if a package comes to depend on `modemmanager`. Its unit has `Conflicts=ModemManager.service`, and the bridge exits if the name is already owned. The real daemon would find no port it supports anyway, but it must not own the name first |
| **M4.2-M4.5 don't pass on our phone** (registration, IMS, carrier differences: the captured IMS settings come from one carrier only) | Everything up to T1 is offline; T2 waits on the modem work, not the reverse |
| **No warm CP restart; one fresh start in twenty crashed** | An honest status bar; the crash record; a reboot is the recovery. A warm restart is modem-plan work |
| **The phone can't ring while suspended** | Suspend stays off while the modem is on, until MODEM-PLAN 6.3's PM paths and the modem wake source exist. That costs standby battery |
| **Earpiece and speakerphone levels wait on speaker protection** (C9) | Calls work at stage `media` meanwhile; the earpiece ceiling (analog ≤ 6) holds |
| **The MMS bearer is IPv6-only and rmnet0 has no IPv6** | T3 checks it first; IPv6 on rmnet0 is RIL work (the bearer is already IPv4v6) |
| **Emergency calling works partly** (no location, CS fallback missing, a crash at the wrong moment) | The warning stays until tested, per carrier; never "supported" without a recorded §3.3 step 4 |
| **PipeWire's MM gateway needs a rebuilt PipeWire** | Carry `-Dbluez5-backend-native-mm=enabled` in our package repo, or use path 2 (§2.2) with our own HFP glue |
| **Privacy:** numbers and texts in logs, databases or screenshots | sitd's rule extends to the bridge and the apps: states and IDs only in logs; runbook excerpts grep'd for digit runs (MODEM-PLAN M4) |
| **Licences:** ofono2mm (FuriLabs) is GPL-2.0, mmsd-tng and vvmd are GPL-2.0, Calls and Chatty are GPL-3.0-or-later | The bridge is ours (MIT, in this repository), structured after Droidian's BSD-3-Clause original; GPL projects are read, not copied, except into the GPL-3.0-or-later apps where licences allow |

### 10.1a The owner's answers (2026-10-14)

| # | Decision |
| --- | --- |
| 1 | Apps named "Phone" (`omaphone`) and "Messages" (`omamessages`), in one repository; since 0.2.0, one repository per app plus `omatel` for the shared crates and the agent |
| 2 | GPL-3.0-or-later |
| 3 | The ModemManager-compatible bridge (`omamobile-mmd`) in Python, like `omamobile-sitd` |
| 4 | Contacts as a vCard folder, synced over CardDAV |
| 5 | Mobile data handed to NetworkManager from T3 |
| 6 | Open: the warning texts and the arranged emergency test call |
| 7 | Lock-screen notifications show "New message" only by default; sender and text as an option |
| 8 | Open: carrier, SIM and APN (kept out of the repository) |
| 9 | IMEI and IMSI stay empty over D-Bus; a one-time import of the Android message and call history, if the owner wants it |
| 10 | Rebuild PipeWire for Bluetooth headset calls, when the call-audio phase gets there |
| 11 | RCS is a non-goal |
| 12 | One headless agent shared by both apps |
| 13 | Our own small wake helper for alarms |

The bridge (T0-T1) starts now, in parallel with the camera app.

### 10.1b T6 and T7: the first version (2026-10-14)

Everything here was built and tested on the laptop, offline, against a scripted ModemManager and the real bridge in a container. **Nothing has run on the phone and nothing on the phone changed.** The code is in a local repository, `~/Projects/omatel`, at version 0.1.0 (Rust, GTK 4 and libadwaita, GPL-3.0-or-later). It is not published: the owner decides that.

**0.1.1** is the release prepared for publishing:
- US English throughout, with `scripts/spelling.sh` in `check.sh` to keep it.
- `calls.db` schema 2 renames 0.1.0's `favourites` table to `favorites` (`ALTER TABLE ... RENAME`), so a 0.1.0 database keeps its order; a test opens a schema-1 database.
- NOTICE credits omacam and ModemManager's interface.
- The history audit found no private data.

`packages/omatel` now points at the GitHub tag's tarball. Its `sha256sums` is a placeholder until the repository and the `v0.1.1` tag exist.

**0.2.0 splits the repositories** (the owner's request): one per app, plus `omatel` for the shared core.

| Repository | Holds | Package | Depends on |
| --- | --- | --- | --- |
| `omatel` (v0.2.0) | the crates (`omatel-mm`, `-store`, `-contacts`, `-notify`, `-theme`, `-api`, `-mock`), `omatel-agent` with its user unit and D-Bus activation files, the agent and chain tests, the live screenshot run | `packages/omatel` → `omatel-agent` | - |
| `omaphone` (v0.2.0) | Phone, with its history from omatel (`git subtree split`), desktop files and icons, `scripts/ui-shots.sh` | `packages/omaphone` → `omaphone` | `omatel-agent>=0.2.0`; omatel's crates at v0.2.0 (git, `Cargo.lock`) |
| `omamessages` (v0.2.0) | Messages, likewise | `packages/omamessages` → `omamessages` | the same |

- The package names are unchanged and 0.2.0 sorts above 0.1.1, so a plain upgrade replaces the 0.1.1 split packages.
- The apps' `Cargo.lock` pins omatel's v0.2.0 commit. `cargo fetch --locked` in `prepare()` therefore needs the omatel tag pushed before an app's package can build.
- Results: `scripts/check.sh` passes in all three: omatel 73 tests, omaphone 7, omamessages 14. The chain test passes, and so do the screenshot runs: each app's own run, and omatel's live run with both apps.
- `bin/cross package` makes the three aarch64 packages.

**What is built:**

| Part | What it does |
| --- | --- |
| `omatel-agent` (one per user, a systemd user unit, D-Bus activatable) | Follows the modem through MM's API, through `omamobile-mmd` or the real ModemManager, as it comes and goes. Serves `org.omamobile.Phone1` and `org.omamobile.Messages1` (§9.1, with the interface moved from the dialer into the agent). Incoming calls: the IncomingCall signal, a critical notification with Answer and Decline, the feedbackd ringtone, and Phone's answer page. Blocked callers are hung up at once and logged. The call log is written from Call state changes, with a missed-call notification offering Call back and Message. Outgoing calls carry post-dial tones (`,`). SMS: committed to disk, then `Messaging.Delete`, with duplicates filtered; WAP push is left for mmsd-tng. One notification per conversation with an inline reply. Sends run in the background, with delivery reports and retry |
| Phone (`omaphone`) | Tabs Favorites, Recents, Contacts and Keypad (a bottom view switcher). A large dialpad with T9 smart dial and a persistent emergency banner. Call details. A contact page and editor, `.vcf` import and export, blocking. In-call: timer, mute, speaker, a touch-tone keypad, hang up. Answer page with "Reply with message". `tel:` and `callto:` links, and a Contacts launcher entry |
| Messages (`omamessages`) | The conversation list: pinned, archived, muted, unread, drafts, FTS5 search, and a long-press action sheet. Threads with bubbles, day separators, delivery states, and tap-to-retry. Compose to a contact or a number; blocked numbers; settings; JSON export and import (§9.4); `sms:`, `smsto:`, `mms:` and `mmsto:` links with `?body=`. MMS: the schema and a disabled attach button only |
| Shared crates | `omatel-mm` (zbus 5 proxies for MM 1.24), `omatel-store` (SQLite, WAL, `synchronous=FULL`, migrations, FTS5, a `transport` column), `omatel-contacts` (a vdir vCard folder; vCard 2.1-4.0 in, 3.0 out, keeping unknown lines; E.164 through the `phonenumber` crate, Apache-2.0, GPL-3-compatible), `omatel-notify` (inline reply through `NotificationReplied`), `omatel-theme` (Omarchy `colors.toml`, as omacam), `omatel-api` |

**Decisions that differ from §9:**

- **One agent, not two app services.** This is Q12. The apps are plain GTK apps that start when opened. The agent serves the Phone1 and Messages1 names, so the shell's lock card (T5) talks to the agent, not to the app.
- **Storage.** All three databases are in `~/.local/share/omatel/` (`messages.db`, `calls.db`, `blocked.db`), not in a directory per app: one agent writes them all. The apps write only their own changes (flags, drafts, deletions). Settings live in `~/.config/omatel/settings.toml`, shared by the three programs.
- **Packaging.** One PKGBUILD, `packages/omatel`, with `pkgbase=omatel` and `pkgname=(omatel-agent omaphone omamessages)`. That is one cargo build instead of two, and either app can be installed alone because both depend on the agent. This replaces the two PKGBUILDs §9.5 planned.
- **The enabled state.** The agent's user unit ships **not enabled**. The T6 runbook enables it (step P3). D-Bus activation starts it whenever an app needs it.

**Results:**

- **Rust tests (`scripts/check.sh`: rustfmt, clippy `-D warnings`): 92 pass, plus the chain test (below), which skips outside its container.** Of those:
  - 7 in `omatel-mm`'s own unit tests;
  - 5 run `omatel-mm` against the scripted MM: an incoming call with Accept and DTMF, an outgoing call answered and one refused, SMS in and out, a delivery report, a failed send, and a WAP push;
  - 11 run the agent end to end on two private buses:
    - calls: answered, missed, declined, blocked, outgoing with post-dial tones, busy;
    - **emergency numbers refused, and never reaching the modem**;
    - messages: SMS stored then deleted, a duplicate, WAP push left alone, an inline reply, a delivery report and a retry, "New message" only while locked, muted, blocked and disabled notifications;
    - a modem that appears late.
- **The chain test, `scripts/chain-test.sh`: passes.** The agent runs on `omamobile-mmd` 0.1.0, `omamobile-sitd` 0.3.0 and `tools/sit-sim` from this tree, in a container. It checks:
  - an incoming call announced, answered, with a DTMF tone, hung up and logged;
  - an outgoing call answered;
  - 911 refused, with no AIMS_DIAL;
  - an SMS stored and deleted from the bridge;
  - a reply from the notification sent through the RIL exactly once;
  - the WAP push left on the bridge;
  - no transcript violations;
  - no number or text in the agent's log.
- **A bug the chain test found, now fixed in the agent:** the bridge announces its first fetch with `Added(received=false)`, as MM does for messages it already had, and the agent first skipped those. The bridge itself is unchanged.
- **Screenshots** were taken in a headless Weston in a container, at 456x900:
  - `omaphone` (12) and `omamessages` (11) on fictional demo data;
  - 9 with the agent and the mock MM running: ringing, answered, muted through the agent's API, ended, then the call in Recents; a message arriving and a reply sent.
  - They are in `~/Projects/omatel/target/ui-shots/` and are not committed.
- **Measured on the laptop in the container** (the phone will be slower; P5 measures it there):

  | What | Value |
  | --- | --- |
  | Agent on the bus | 66 ms after its start |
  | Agent memory | 18 MB RSS, after a call and two messages (target under 40 MB) |
  | Phone, start to first frame saved | 0.6 s (warm) |
  | Messages, start to first frame saved | 0.3 s (warm) |
  | Apps with a call or a thread open | about 64-67 MB RSS each |
- **Cross-compile:** omatel's `bin/cross build` and `bin/cross package` use omacam's image and sysroot, and make the three aarch64 packages: 2.7 to 3.3 MB each, with 8 to 10 MB binaries.
- **The package under qemu:** `packages/omatel` built its three packages in **34 min**, with `check()`, in the same Arch Linux ARM image and the same steps as `tools/build-packages`. The output went to a scratch directory, not into the signed `out/repo`: another session was building libcamera into it at the time. The real run is P1.

**Stubbed or deferred:**

- **Call audio (T4).**
  - `SetMute` and `SetRoute` go to callaudiod when it runs. Without it they are recorded and reported (`AudioRouting` false), and the in-call screen says that routing arrives with call audio support.
  - Bluetooth is accepted as a route but does nothing.
  - Whatever voice path `omamobile-sitd` sets up itself (EP5/EP4) is outside the agent.
- **Ringing:** through feedbackd (`phone-incoming-call`) when it runs. It isn't installed on the phone, so the call is announced silently until it is installed or the shell plays a ringtone (T5).
- **MMS (T3):** schema and placeholders only. WAP pushes stay on the modem for mmsd-tng.
- **Shell (T5):**
  - The notification hints are in place: `category`, `desktop-entry`, and `x-omamobile-private` with `x-omamobile-public-summary`.
  - Inline reply needs the Omarchy patch from §7.2 (omamobile-omarchy 0.1.6, patch 0015). Without it, Messages shows a Reply button that opens the app.
  - The lock-screen call card is not built.
  - Lock-state detection uses logind's LockedHint and `org.freedesktop.ScreenSaver`. Omarchy's Quickshell lock may set neither. Then notifications show details unless the shell honours the public-summary hint, which is a T5 item.
- **Not built:**
  - **Emergency calls:** refused everywhere, with the §3.2 texts.
  - Hold, swap and conference (T8).
  - Visual voicemail (T9).
  - CardDAV sync: the vdir is ready for vdirsyncer or pimsync.
  - Re-showing notification details after unlock.
  - A UI for favourites order.
  - Contact photos (initials only).
- **A bridge gap, not a bug:** `omamobile-mmd` has no SMS status reports (T8). Sent messages therefore stay "Sent", and the agent keeps each sent `Sms` object on the bridge while it waits for a report, for up to 48 h.

**First phone test, without a SIM: UI and agent (P0-P7).** Every step needs the human's go, and the human holds the phone. Announce first: windows open on the phone.

| Step | Commands | Expect / Pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| P0 read-only | `tools/phone-ssh 'pacman -Q omamobile-mmd omamobile-modem-sit; systemctl is-active omamobile-mmd omamobile-sitd'` | Versions and states as recorded | anything unexpected | none | none |
| P1 build | `tools/build-packages packages/omatel` (laptop; the source tarball is described in the package README), or `bin/cross package` in omatel | three aarch64 packages | build fails | none | none |
| P2 install | `tools/repo-push`, then on the phone `pacman -S omatel-agent omaphone omamessages` | installed; no service started | pacman conflict | `pacman -R omaphone omamessages omatel-agent` | low (user-space only) |
| P3 agent | as the user: `systemctl --user enable --now omatel-agent`; `journalctl --user -t omatel-agent -b` | "serving org.omamobile.Phone1 ..."; modem state `no-sim` with the bridge running, `no-modem` without it; no warnings except the notification server's | a crash loop; any number in the log | `systemctl --user disable --now omatel-agent` | low |
| P4 apps | open Phone and Messages; the Contacts tab; import a `.vcf` from the owner's old phone (stays on the phone, private) | no "service isn't running" banner; the emergency banner on Keypad; Recents and Messages empty; contacts listed | a crash: `journalctl --user -t omaphone -t omamessages` | close the apps | low |
| P5 emergency UI and measurements | type 911 on Keypad and press call; then `systemd-run --user --pipe --wait /usr/bin/time -v omaphone --script "shot /tmp/p.png; quit"` | the full-screen "can't call emergency services yet" page; no `Dial` in the agent log; **no dial in sitd's state or log**; record the first-frame time and RSS, and the agent's RSS (`systemctl --user status omatel-agent`) | anything reaching sitd | none | none (the agent refuses emergency numbers; the app never sends them) |
| P6 settings | in Messages' Settings, turn "Sender and text on the lock screen" on and off | `~/.config/omatel/settings.toml` follows; the agent reads it at the next message (no restart) | none | delete the file | none |
| P7 inline reply (§7.2; announce: the shell restarts, a toast appears and the keyboard shows) | install omamobile-omarchy 0.1.6 (`omamobile-omarchy-patches status` lists 0015 applied), then `omarchy-restart-shell`; as the user, `dbus-monitor --session "member='NotificationReplied'" &` and `gdbus call --session -d org.freedesktop.Notifications -o /org/freedesktop/Notifications -m org.freedesktop.Notifications.Notify test 0 '' 'Test' 'Reply to me' "['inline-reply', 'Reply']" '{}' 0`; on the phone tap Reply, type on the keyboard, tap Send | the toast stays while the field is open; squeekboard shows when the field opens (or at the latest when it is tapped); `NotificationReplied` carries the typed text and the toast goes; a plain `notify-send` toast has no Reply | no keyboard after tapping the field (then it needs the polkit prompt's Top-layer treatment, patch 0010); a stuck keyboard focus in the app underneath | `omamobile-omarchy-patches status`; downgrade to 0.1.5 and restart the shell | low (shell only) |

**Results, 2026-10-23** (kernel `7.3.0-rc6-omamobile-push1-00570-g8cd00dcfc564`; omatel-agent 0.2.3, omaphone and omamessages 0.2.1, omamobile-shell 0.2.14, omamobile-omarchy 0.1.6, from `tools/build-packages` and `tools/repo-push`):

- **P0:** omamobile-mmd 0.1.0 and omamobile-modem-sit 0.3.0 installed, both inactive (no SIM, the bridge not started). omatel-agent 0.2.1, omaphone and omamessages 0.2.1 were already installed and the agent enabled, from an earlier unrecorded install.
- **P1, P2:** built on the laptop. The phone's repository matched the laptop's file for file except the three new packages. `pacman -U` of the three pulled in nothing else, and the hook applied all 14 Omarchy patches (0014 and 0015 included). omatel-agent 0.2.1's files are saved in `/var/lib/omamobile/rollback/` (its package wasn't in the cache).
- **P3: pass.** "serving org.omamobile.Phone1 and org.omamobile.Messages1"; `ModemState` `no-modem` with the bridge stopped; 8 emergency numbers; no warnings.
- **P4: pass** (the owner, on the phone). Phone and Messages opened with no service banner.
- **P5: pass.** The agent logged "emergency number dialled: warning shown, nothing placed", and nothing else mentions a dial. sitd wasn't running, so nothing could reach the modem.
- **P6: pass (the file half).** On the repeat the owner toggled the switch once and `~/.config/omatel/settings.toml` appeared within seconds, with `lockscreen_details = true` and the other defaults. Why the first run left no file is not known: nothing was logged then. The agent half ("reads it at the next message") needs a message, so it moves to C3.
- **P7: pass.** The server advertises `inline-reply` on the phone; the owner tapped Reply, typed on squeekboard and sent: `NotificationReplied(1, "yo")`, then `NotificationClosed(1, 2)`.
- **Found on the way:** the phone had only the seven shell plugins of 2026-10-14 linked. `omamobile-setup-user` links new plugins and switches them on, but it ran only at firstboot, so `omamobile.call` (the call card), `omamobile.switcher` and `omamobile.update` never reached this phone. omamobile-shell 0.2.15 adds `omamobile-setup-user.service`, which reruns it at every login before the compositor starts, for users firstboot has set up (every step is guarded by its `omarchy-done` marker).
- **omamobile-shell 0.2.15 on the phone:** `omamobile-setup-user.service` ran (condition met, `Result=success`), all ten plugins are linked and switched on, and after a shell restart the call card owns `org.omamobile.CallCard` on the session bus.

**After T2 (a SIM, M4.2-M4.5 passed; the radio transmits: announce it):**

- **C1:** an incoming call from the owner's other phone. Answer, then hang up. Check: the answer page shows within about 1 s of the ring (T6's exit criterion), Recents shows the call, and nothing is in the logs.
- **C2:** an outgoing call to the other phone. Check the timer and hang-up. Add touch tones to a test IVR only if the owner has one.
- **C3:** SMS both ways. Reply once from the notification (P7's inline reply). Turn "Sender and text on the lock screen" off and check the next message's notification hides them (P6's agent half). Check: Messages shows the message, `mmcli -m 0 --messaging-list-sms` is empty after storage, and there is no duplicate after `systemctl --user restart omatel-agent`.
- **C4:** block the other phone's number, call in, and check it is hung up and logged as blocked.
- **C5:** kill the agent mid-receive (`systemctl --user kill omatel-agent` while texts arrive). Check that nothing is lost or duplicated (T7's exit criterion).
- **Never:** an emergency number. That is §3.3, and the owner's.

### 10.2 Questions for the owner

| # | Question |
| --- | --- |
| Q1 | **Names and repository.** `omadialer` shown as "Phone" and `omamessages` as "Messages", in one repository (`omatel`?) with shared crates? Or two repositories? |
| Q2 | **Licence.** GPL-3.0-or-later for both apps, as omacam? The bridge `omamobile-mmd` stays MIT in this repository. |
| Q3 | **The bridge's language.** Python with dbus-fast (recommended: the RIL is Python, and ofono2mm proves the approach) or Rust with zbus (one language for all new code)? |
| Q4 | **Contacts store.** A vCard folder synced over CardDAV (recommended), or evolution-data-server with GNOME Online Accounts so that GNOME apps share it? Which accounts do your contacts live in today? |
| Q5 | **Mobile data through NetworkManager** from T3, retiring `omamobile-sit-data`'s own route handling? |
| Q6 | **Emergency calling.** Are the warning texts in §3.2 right? Do you agree that the per-carrier test in §3.3 step 4 is yours to arrange, and that nothing claims emergency support before it? |
| Q7 | **Lock-screen privacy.** Show sender and text in notifications on the lock screen, or only "New message" (our default)? |
| Q8 | **Carrier.** Which carrier and SIM for T2-T3, and does it allow MMS on the internet APN? (APN and MMSC go into the phone's config, never the repository.) |
| Q9 | **Identifiers over D-Bus.** MM exposes the IMEI and IMSI to clients; our RIL never reads them (MODEM-CLIENT §1.2). Keep them empty (recommended; Calls and Chatty cope), or read them for apps that want them? And: import your Android message and call history once? |
| Q10 | **Bluetooth calls.** Rebuild PipeWire with its ModemManager gateway for headset calls (path 1), or try the host path first? |
| Q11 | **RCS.** Accept it as a non-goal (§4), with group chats falling back to group MMS? |
| Q12 | **Background processes.** Two resident app services (as GNOME Calls and Chatty run), or one headless agent that owns ringing and SMS storage for both apps? |
| Q13 | **Alarms.** Carry GNOME Clocks' wake-timer MR as a patch, or a small wake helper of ours, once suspend is on by default? |
