<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a: connect Phone and Messages to sitd

Status (2026-11-03): offline investigation on `origin/main` at `31fbcf9`.
The owner reports texts both ways and calls through `omamobile-sit` on the
palmtop. No phone contact in this investigation. This is an integration
plan, not a record of app or call-audio qualification on hardware.

The app protocol already exists. The immediate missing layer in the
recorded tegu setup is `omamobile-mmd`, installed and running. A normal
package install is blocked by the cheetah-only dependency still on main;
sitd's packaged modem-unit dependency also needs the tegu startup work.
Those are existing, separate changes. Do not duplicate them or install
with dependency checks disabled. The first app test can use an already
running, attended sitd; it need not wait for modem startup at boot.

## The existing path

```text
Phone / Messages
    | session bus: org.omamobile.Phone1, org.omamobile.Messages1
omatel-agent (the logged-in user's service)
    | system bus: org.freedesktop.ModemManager1
omamobile-mmd (root, ModemManager-compatible API)
    | /run/omamobile-sit/socket: JSON requests and status subscription
omamobile-sitd (the only owner of the modem channels)
    | SIT / AT
modem
```

| Layer | What the repository already supplies |
| --- | --- |
| Apps | `omamobile-apps` depends on `omaphone` and `omamessages`; both pull in `omatel-agent`. Contacts is supplied with Phone and does not need a modem. #361 puts all three packages in the image. |
| Agent | `packages/omatel` packages the agent, its user unit and both session-bus activation files. Opening an app activates it. The disabled user unit is intentional; no root agent and no generic enablement change are needed. |
| Bridge | `packages/omamobile-mmd` owns the system-bus name normally used by ModemManager, exports modem/call/SMS objects, and checks polkit for operations. It conflicts with the real `modemmanager`; installing both is not the solution. |
| Commands | `Voice.CreateCall` plus `Call.Start` maps to sitd `dial`; `Accept`, `Hangup` and `SendDtmf` map to sitd requests. `Messaging.Create` plus `Sms.Send` maps to `sms-send` with a durable request ID. |
| Incoming events | The bridge subscribes to sitd, exports calls, reads `sms-list`, and maps deletion to `sms-delete`. The agent stores SMS before deleting them from the bridge and handles notifications and call history. |
| Privileges | Apps and agent use D-Bus. Only the bridge needs sitd's private socket. Keep socket permissions and the current polkit policy; no wheel-group workaround is needed for app access. |

Sources: [app package](../../packages/omamobile-apps/PKGBUILD),
[agent packaging and activation](../../packages/omatel/README.md),
[bridge mappings](../../packages/omamobile-mmd/lib/bridge.py),
[socket subscription](../../packages/omamobile-mmd/lib/sitd_link.py), and
[the shared telephony plan](../../docs/TELEPHONY-APPS-PLAN.md), especially
sections 1.5 and 10.1b. The requested old cheetah plan path has moved to
`docs/TELEPHONY-APPS-PLAN.md`.

Contacts uses the shared local vCard address book; it does not need a modem
or an additional cellular service.

## What tegu is missing

1. **A dependency-correct install.** `omamobile-mmd` depends on
   `omamobile-modem-sit`, which depends on `omamobile-modem`, which still
   depends on `omamobile-device-cheetah`. That conflicts with tegu's device
   package. The existing `modem-policy-virtual` change replaces that last
   dependency with `omamobile-modem-policy` and adds tegu's provider. It is
   not in this base. Land/build that prerequisite first.
2. **The bridge package and its start.** The common rootfs list deliberately
   omits mmd and modem-sit. Tegu's `ROOTFS_PACKAGES` does not include them.
   `omamobile-mmd.service` ships disabled, has no D-Bus activation file,
   and its installer creates no wants link. Merely opening an app cannot
   start it. The recorded SIM runbook says mmd was not installed; current
   hardware state must be checked by the human rather than inferred here.
3. **The right modem service for later automatic integration.** The shipped
   `omamobile-sitd.service` requires `omamobile-modem.service`; the recorded
   tegu run uses its own starter and an `/etc` copy of sitd's unit that
   removes this dependency. A bridge-only test must retain the already
   qualified, running stack. Do not start or restart the stock sitd unit
   to attach the bridge. Package tegu's starter/order separately before
   making this an image default.
4. **The tested tegu RIL and release safety.** Main still carries the older
   RIL; use the independently reviewed tegu SIM fixes and safe unconfirmed
   call-release behavior. Do not replace a running test RIL as part of
   installing the bridge. An unconfirmed hang-up must not stop the tegu
   modem in place. Call audio remains its separate route/qualification.

There is no evidence that SMS needs an mmd APN, a tegu-specific socket
path, an extra bridge SMS transport, or a second modem daemon. The bridge
forwards SMS through sitd; sitd chooses the transport. Its modem state is
based on SIM/radio/registration and can be REGISTERED without a data bearer.
The hard-coded MM model string `Exynos Modem 5300` is misleading on tegu,
but is display metadata, not a routing selector or a reason to block SMS.

## The smallest durable changes after the prerequisites

- Keep `omamobile-apps` modem-independent, as #361 intends. Do not make all
  images depend on the modem stack to get Phone or Contacts.
- After tegu's packaged modem start is qualified, add mmd and modem-sit to
  tegu's board package list (and its packaged descriptor copy), with a
  test that the descriptors agree and resolve against tegu's policy
  provider without installing the cheetah device package.
- Enable only the bridge's existing relationship to sitd:
  `systemctl enable omamobile-mmd.service` creates
  `omamobile-sitd.service.wants/omamobile-mmd.service`. This follows a sitd
  start without enabling sitd or starting the CP. Tegu's setup can do this
  conditionally when mmd is installed; it need not use `--now`.
- Preserve mmd's one-way relationship: `After=omamobile-sitd.service`, no
  `Requires=`, `Wants=` or activation path from the bridge to sitd or the
  CP. An app opening or a bridge restart must never power the modem on.
- Test the conditional enablement with a fake systemctl, absent-package
  handling, and a scratch unit root. Starting the bridge alone must not
  request a CP start; starting qualified sitd must pull in the bridge.

For the already running palmtop, the manual steps below are enough once
package dependencies are correct. The durable boot/image changes are not
prerequisites for that test.

## Attended first test (proposed, not executed)

Keep the existing modem sleep inhibitor throughout; suspend with the CP on
is not qualified by this work. Keep the existing once-per-boot start and
NV checks. No step below starts, stops or restarts the CP or sitd.
Run user commands in the existing graphical user's terminal, root commands
in the attended administrative session. These commands are a runbook for
the human, not authorization to contact the phone in this task.

| Step / risk | Commands or action | Expect / pass | Stop condition | Rollback |
| --- | --- | --- | --- | --- |
| 1. Read-only / none | `uname -r`; `pacman -Q omaphone omamessages omatel-agent omamobile-mmd omamobile-modem-sit omamobile-modem`; `systemctl is-active omamobile-sitd omamobile-mmd ModemManager`; `systemctl cat omamobile-sitd`; `systemd-inhibit --list` | Record kernel/package versions, actual sitd unit, active inhibitor and existing running sitd. Missing bridge is expected initially. | No confirmed running sitd, wrong starter, competing ModemManager, or no inhibitor. | None; end this session without starting the modem. |
| 2. Install bridge / low | First review `pacman -Sp --print-format '%n %v' omamobile-mmd`. After the dependency fix is available, `pacman -S omamobile-mmd`, only if the transaction adds the bridge/dependencies without changing the running RIL, modem or device package. | No cheetah package, no tegu removal, no modem/RIL upgrade, and nothing starts the CP. | Resolver conflict or any unexpected upgrade/removal. Never use `-dd`. | Cancel before accepting the transaction; if installed, remove only the bridge after stopping it. |
| 3. Start bridge / low | Root: `systemctl start omamobile-mmd.service`; `busctl --system list --no-pager org.freedesktop.ModemManager1`; use `packages/omamobile-mmd/test/libmm-status.py` for states only. | Bus name owned by mmd, a modem object with SIM ready and expected registration; sitd/CP remain the same running instances. | Bridge cannot own the name/connect; sitd exits; hardware warning. | `systemctl stop omamobile-mmd.service`. Do not restart sitd or stop the modem. |
| 4. Agent and apps / low, screen changes | Announce first, then open Phone and Messages as the session user. `systemctl --user is-active omatel-agent`; `busctl --user list --no-pager org.omamobile.Phone1 org.omamobile.Messages1`. | Agent activates, apps see the modem instead of no-modem; Contacts opens without requiring a live modem. | Activation or authorization error. Do not weaken polkit/socket permissions. | Close apps; stop the user agent if it was started only for this test; stop mmd. |
| 5. SMS / carrier charge possible | Human sends one agreed test text in Messages, then sends one back from the other device; reopen the conversation. | One send, one received message, preserved after closing/reopening; no duplicate send on retry/reconnect. | Duplicate, uncertain delivery, or missing inbound text. Do not retry an uncertain send automatically. | Stop testing and stop the bridge; keep private message stores for diagnosis. |
| 6. Calls / medium, screen and sound | Only after the separate safe-release and call-audio checks: announce, place one ordinary agreed call from Phone, receive one, answer/decline and hang up. | UI state follows the call, release is confirmed, and the approved audio route behaves as qualified separately. | Unconfirmed release, unexpected audio level, CP/AoC/UFS fault. No emergency-number test. | Follow the attended safe-release runbook; no modem stop or second start. A reboot needs separate approval. |
| 7. Optional persistence / low | After passing, root: `systemctl enable omamobile-mmd.service` without `--now`. Inspect the resulting sitd wants link. | Bridge follows future *approved* sitd starts; sitd and modem remain disabled at boot. | Any change enabling the modem or sitd itself. | Disable only mmd if this step enabled it, then stop mmd if ending the test. |

SMS/call numbers, contents, operator identities and object dumps remain
private. Record only states, counts, errors and test outcomes in this plan.
The read-only libmm status helper deliberately prints states and counts.

A session that has never opened either app needs an additional activation
check before claiming always-on incoming notifications. The shell's call
watcher checks whether the agent owns its name and does not itself start
it. For this first test, open an app before arranging incoming traffic.
Keep #361's app-triggered activation policy until cold-session reception
has a separate test and an explicit decision about login activation.

App mute/speaker controls are also separate: the shared plan records that
the agent uses callaudiod for those, while sitd owns its own voice PCMs.
A successful dial through mmd does not prove those controls affect tegu's
route. MMS and mobile-data control through ModemManager are outside this
SMS/basic-call integration; keep the existing sitd data ownership.

## Offline evidence from this investigation

`packages/omamobile-mmd/test/all` passed on this base with private D-Bus
and local simulator sockets. This covers API/bridge/libmm clients, the
real sitd-to-sit-sim call and SMS chain, and staged unit checks. One test
was skipped because ModemManager's reference introspection XML is absent.
The suite verifies that the bridge has no unit dependency that pulls in
the modem and no system-bus activation file.

`packages/omamobile-apps/test/all` also passed all 12 checks, including
Phone/Messages dependencies and the absence of a common modem dependency.

This does not run the packaged Rust agent or either GUI, does not test
tegu hardware or the current private carrier configuration, and does not
qualify polkit for the actual graphical session. The earlier full agent
chain result is recorded in the shared plan; it was not rerun here.
