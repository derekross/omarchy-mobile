# omatel

`omatel-agent`, the background service behind Omarchy Mobile's Phone
([packages/omaphone](../omaphone)) and Messages
([packages/omamessages](../omamessages)) apps
([TELEPHONY-APPS-PLAN](../../docs/TELEPHONY-APPS-PLAN.md) T6/T7, §10.1b).
It rings for calls, writes the call log, stores incoming SMS and raises
notifications, and serves `org.omamobile.Phone1` and
`org.omamobile.Messages1`. It comes from the
[omatel](https://github.com/derekross/omatel) repository
(GPL-3.0-or-later), which also holds the crates the apps share. This
package builds a pinned release from it.

- **Up to 0.1.1** this one PKGBUILD built all three packages. **Since 0.2.0**
  the apps have repositories and PKGBUILDs of their own. The package names
  stay the same, so a plain upgrade replaces the 0.1.1 packages.
- `omamobile-apps` depends on `omaphone` and `omamessages` since 0.2.1, and
  they pull this package in. Without ModemManager's API on the system bus
  (no modem stack installed, as in the first release's image) the agent
  waits for the name without polling and reports `ModemState` "no-modem";
  a dial is refused with `NoModem` and a sent SMS is marked failed.
- The agent's user unit ships disabled, and that is the design: D-Bus
  activation starts it when Phone or Messages opens. 0.2.4-2 changes only
  the install message, which used to tell users to enable it.

**Emergency calls are not supported.** The agent refuses emergency numbers
until the plan's §3.3 tests pass.

## Releases

1. Tag the release `vX.Y.Z` in omatel and push the tag.
2. Set `pkgver` here.
3. Put the sha256 of GitHub's tarball in `sha256sums`:
   `curl -sL https://github.com/derekross/omatel/archive/refs/tags/vX.Y.Z.tar.gz | sha256sum`.
4. Run `tools/build-packages packages/omatel`.

The apps pin omatel's crates to a tag in their `Cargo.lock`, so a release
that changes a crate's API is tagged here first, then picked up by the
apps.

## Build

- `tools/build-packages packages/omatel` builds under qemu-user (0.1.0,
  with both apps, took 34 minutes; the agent alone takes less).
- While developing, cross-compile with omatel's `bin/cross package`.
- `check()` runs the D-Bus-free unit tests. The D-Bus, agent and chain
  tests run on the laptop with omatel's `scripts/check.sh` and
  `scripts/chain-test.sh`.
