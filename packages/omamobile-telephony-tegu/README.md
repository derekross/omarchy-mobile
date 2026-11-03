<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a: attach Phone and Messages to a running sitd

This opt-in package installs `omamobile-mmd`, `omatel-agent`, and the tegu
bridge policy. It enables and starts no services. It does not package a
modem starter: the attended tegu modem and RIL must already be running.
Apps speak to the session agent, the agent speaks ModemManager's system
D-Bus API, and mmd forwards requests to sitd's private socket.

Install the built `omamobile-telephony-tegu` package with ordinary pacman
dependency checking. Inspect the transaction first. Its device/RIL minima
carry the packaged unit policies, the dependency fix, the tegu SIM fixes,
safe unconfirmed-release handling and the opt-in tegu audio route. Prepare
those upgrades before a modem session; never replace a running test RIL
with older code. No firmware or private provisioning comes in this package.

The common `omamobile-sitd.service` name is preserved for the CLI, bridge
and data helper. Its modem dependency now comes from the device package:

- Cheetah and raven retain `Requires=omamobile-modem.service` and its order.
- Tegu uses `Requisite=omamobile-tegu-modem.service` plus ordering, and
  checks CP ONLINE with the existing state helper before starting sitd.
  Requisite fails if that starter is inactive; it never starts it.
- The device packages provide `omamobile-sitd-policy`, which the RIL now
  requires, so an upgrade cannot silently omit its device unit dependency.
- The opt-in bridge uses `Requisite=omamobile-sitd.service` and a read-only
  service preflight. Starting the bridge cannot pull in sitd or either modem unit.

## Migrate the old sitd unit (attended preparation)

The old `/etc/systemd/system/omamobile-sitd.service` copy overrides the
packaged base unit. The attach script refuses it. The package never deletes
or rewrites a human's unit. Prefer migration with the modem off, before
starting the next approved session. For an already running session, only
continue after checking the versions, active tegu starter and unchanged
process IDs; `daemon-reload` changes definitions without restarting them.

1. Read-only: `systemctl cat omamobile-sitd.service` and
   `systemctl show omamobile-sitd.service omamobile-tegu-modem.service -p ActiveState -p MainPID`.
   Save those PIDs privately. Stop if the service/starter differs from the
   approved tegu setup, or if a call is in progress. Risk: none; rollback:
   none.
2. After the new packages are installed, inspect
   `/usr/lib/systemd/system/omamobile-sitd.service` and its
   `omamobile-sitd.service.d/10-device-modem.conf`. Expect tegu Requisite,
   no cheetah Requires, CP ONLINE precheck, and `Restart=no`. Stop on a
   mismatch. Risk: none; rollback: none.
3. Only for the legacy full copy, root:
   `install -d -m700 /var/lib/omamobile-telephony-tegu`, then
   `mv -n /etc/systemd/system/omamobile-sitd.service /var/lib/omamobile-telephony-tegu/omamobile-sitd.service.before-attach`.
   Verify the source is gone (an existing backup makes `mv -n` skip; do
   not overwrite it), then `systemctl daemon-reload`. Do not use restart,
   enable or `--now`. Risk: low (unit definitions). Expect the same PIDs
   and `FragmentPath=/usr/lib/systemd/system/omamobile-sitd.service`.
   Stop if a PID changes or a service leaves active. Rollback: restore
   the saved file and daemon-reload, without restarting the modem or RIL.

The attach script also refuses pending daemon-reload, unexpected start
relationships, an inactive tegu starter/RIL, another ModemManager, a
non-ready SIM, an unregistered radio, and a live call. It obtains a live
status RPC; it never trusts the public state.json as proof of readiness.
It reads no modem device and sends no radio-control request. IMS or a
mobile-data bearer is not required just to attach. The unit's separate
`--service-check` permits an existing call or registration loss, so the
bridge can recover without dropping call visibility. The attended initial
attachment keeps the stricter no-live-call and registered-SIM checks.

Mmd 0.1.1 removes the service-level `Conflicts=ModemManager.service`: a
bridge start must not stop another modem daemon. Package conflicts and
exclusive D-Bus name ownership still prevent two managers from serving the
same API; tegu's preflight refuses another owner before starting mmd.

## Attach (human in the graphical user's terminal)

Keep the existing, approved sleep inhibitor for the modem session. This
package does not qualify CP-on suspend or change auto-sleep. Confirm the
NV checks and once-per-boot rule from the modem startup runbook; nothing
here repeats the modem start or accesses NV partitions.

Read-only preflight:

```sh
omamobile-tegu-mmd-attach --check
```

Expect existing running tegu modem and sitd, a registered SIM and no live
calls. This uses sudo for read-only system checks and the private sitd
socket. Stop on any failure; it never attempts recovery. Risk: low; no
rollback is needed because no service is changed.

Attach, after announcing that incoming calls and message notifications may
now appear on the screen and sound:

```sh
omamobile-tegu-mmd-attach --attach
```

Run as the existing graphical user, not root, in a terminal. Type `ATTACH`
at its prompt. The complete set of service-start commands is:

```sh
sudo -- systemctl start omamobile-mmd.service
systemctl --user start omatel-agent.service
```

The script rechecks the modem/RIL PIDs immediately before the bridge start,
after it, and after the agent start. Repeating it starts already active
services without restarting them. It never enables services or starts,
restarts or stops the modem/RIL. Risk: low (apps begin importing SMS into
the user's store and observing incoming calls). Expect both services
active and unchanged modem/RIL PIDs. Stop on any failure and inspect;
there is no automatic retry or modem recovery.

Open Messages, then do one agreed SMS each way. Record only outcomes and
counts; number, text and network identities stay private. Stop on duplicate
or uncertain delivery; do not resend automatically. Calls follow the
separate safe-release/audio qualification. This package does not qualify
speech, mute/speaker controls, MMS, emergency calls or suspend.

Rollback for services started by this test, once there is no live call:
close the apps, `systemctl --user stop omatel-agent.service`, then
`sudo systemctl stop omamobile-mmd.service`. Leave either service running
if it was already active before the test. A partial failure intentionally
leaves a started bridge in place for inspection. Never stop the modem or
restart sitd to recover an app failure. Any reboot is separately attended
and approved. Removing this package also requires stopping the bridge
first; it removes only the opt-in policy/helper, not private message data.
