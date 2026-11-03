# omaphone

Omarchy Mobile's Phone app
([TELEPHONY-APPS-PLAN](../../docs/TELEPHONY-APPS-PLAN.md) T6/T7, §10.1b), in
its own repository, [omaphone](https://github.com/derekross/omaphone)
(GPL-3.0-or-later). This package builds a pinned release from it.

- It depends on `omatel-agent` ([packages/omatel](../omatel)), the
  background service that talks to the modem.
- Its `Cargo.lock` pins omatel's crates to an omatel release tag; cargo
  fetches them from git in `prepare()`.
- Up to 0.1.1 the package was built from omatel. The name is unchanged, so
  a plain upgrade replaces it.
- `omamobile-apps` depends on it since 0.2.1, so every image and every
  updated phone has it. Without a modem it opens and keeps its data; the
  agent reports `ModemState` "no-modem".

## Releases

1. Tag the release `vX.Y.Z` in omaphone and push the tag. The omatel tag its
   `Cargo.lock` names must be pushed too.
2. Set `pkgver` here.
3. Put the sha256 of GitHub's tarball in `sha256sums`:
   `curl -sL https://github.com/derekross/omaphone/archive/refs/tags/vX.Y.Z.tar.gz | sha256sum`.
4. Run `tools/build-packages packages/omaphone`.

## Build

- `tools/build-packages packages/omaphone` builds under qemu-user.
- While developing, cross-compile with the app's `bin/cross package`.
- `check()` runs the app's unit tests.
