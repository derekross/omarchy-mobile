<!-- SPDX-License-Identifier: MIT -->
# Rename: the steps outside git (history)

**Completed; kept as a record.** Nothing here is a prerequisite for a build.
The rename from Omandroid to Omarchy Mobile (`omamobile`) is done: the
repository's tools and configuration use the new names (the old one is kept
only where it is reserved or migrated from), the kernel branches and in-tree
strings moved on 2026-10-13 (see
[KERNEL-PUBLISH](../device/cheetah/KERNEL-PUBLISH.md)), and the GitHub
repositories are `derekross/omarchy-mobile` and
`derekross/linux-omarchy-mobile`. A host set up from the current
[CONTRIBUTING](../CONTRIBUTING.md) gets the new names from the start.

This page records what the one-off host steps renamed, for anyone reading
old logs or an old checkout. The repository doesn't record each host step
being run, only that the tools and configuration moved to the new names. If a host still
carries an old name, the mapping below says what it became.

`tools/rename-omamobile` did Phase 1 inside git (the old state is tagged
`omandroid-final`). This file names the old paths on purpose, so the rename
tool skips it.

## 1. Docker build image

`omandroid-build:24.04` became `omamobile-build:24.04` (`IMAGE` in
`omamobile.conf`), and `bin/omamobile` runs it with
`--hostname omamobile-build`.

## 2. LineageOS source tree (`SRC_DIR`)

`~/android/omandroid` became `~/android/omamobile` (`SRC_DIR` in
`omamobile.conf`). `bin/omamobile` takes `mkbootimg`, `mkdtboimg.py` and the
prebuilt clang from it.

## 3. Caches

| Old | New | Used by |
| --- | --- | --- |
| `~/.cache/omandroid-ccache` | `~/.cache/omamobile-ccache` | `CCACHE_DIR` in `omamobile.conf` |
| `~/.cache/omandroid-venv` | `~/.cache/omamobile-venv` | `tools/extract-camera-data`'s unicorn venv |
| `~/.cache/omandroid` | none | widget-lint scratch from the shell's tests, regenerated |

A venv records its own path in `bin/activate` and in its scripts' shebangs,
so a moved venv works only when called as `~/.cache/omamobile-venv/bin/python`
(as the docs do); recreating it at the new path avoids that.

## 4. NetworkManager profile for the USB link

The profile `omandroid-phone` became `omamobile-phone`, the name
`tools/phone-ssh` and the docs use. Its settings didn't change:
172.16.42.2/24, `ipv4.method shared`, match `enp0s20f0u*`. This read-only
check shows the name and settings:

```sh
nmcli -g connection.id,ipv4.method,ipv4.addresses connection show omamobile-phone
```

## 5. Ignored files in the working tree

At the rename, these gitignored files still carried the old names:

- `omandroid.local.conf` became `omamobile.local.conf` (none existed then).
- `out/repo/aarch64` held the old `omandroid.db` and `omandroid-*` packages.
  `tools/repo-build` adds every package it finds there to the database, so
  the old output was to be cleared before the first repository build under
  the new names.
- `out/fingerprint/` held old `omandroid-fp-*` builds.
- `keys/gnupg.bak-omandroid-final/` was a copy of the signing keyring from
  before the new user ID was added, to be dropped once a signed repository
  build had worked with the new keyring.

## 6. Signing key and bionic prebuilts (done in Phase 1)

- The package-signing key (fingerprint
  `6C84FE3D240709E70E27CC94B301F5EA62B249FE`, unchanged) got a new primary
  user ID, "Omarchy Mobile Package Signing <derekross@gmail.com>"; the old
  user ID was then deleted from the key (no package signed under it was
  ever installed from the repository), so the exported key carries only the
  new name. Signatures stay valid: they bind to the key, not the user ID.
  `packages/omamobile-keyring/omamobile.gpg` was re-exported; `-trusted` and
  `-revoked` didn't change. The keyring installs as
  `pacman-key --populate omamobile`. The later release key and the move
  from this key are in [RELEASES](RELEASES.md) §10.
- The gitignored bionic prebuilts were rebuilt on 2026-10-13 with the new
  names, against the source tree at its old path; nothing in a built file
  records that path:
  `packages/omamobile-fingerprint/prebuilt/omamobile-fp-{shim.so,bridge}`,
  `packages/omamobile-gnss/bionic/prebuilt/{omamobile-fp-shim.so,stubs/libomamobile-sitril-gps.so}`
  and `packages/omamobile-speaker-tuning/bionic/prebuilt/omamobile-waves-host`.
  The rebuild commands are in FINGERPRINT-PLAN, GNSS-PLAN and
  AOC-TUNING-RESEARCH, which use `~/android/omamobile`.

## 7. Couplings with the kernel tree (Phase 2)

Between Phase 1 and Phase 2 the kernel tree still used the old strings, so a
kernel built from it didn't match this repository in three places, and the
rule then was not to push a new boot image to the phone until Phase 2 had
reached `omamobile-int`:

- **Command-line flags.** The initramfs looks for `omamobile.debug`,
  `omamobile.ufs-probe` and `omamobile.initramfs`; the cheetah DTS's
  `/chosen/bootargs` had `omandroid.ufs-probe`.
- **Camera firmware.** `tools/extract-camera-data` writes
  `/usr/lib/firmware/omamobile/camera/`; the DTS `firmware-name` properties
  (5) said `omandroid/camera/`.
- **Kernel release.** `kernel/configs/omamobile.config` sets
  `CONFIG_LOCALVERSION="-omamobile-push1"`, and the modules marker is
  `.omamobile-tarball`, so the first push after the rename was expected to
  reinstall the modules.

Phase 2 renamed the kernel branches (`omandroid*` to `omamobile*`) and
merged the `omamobile.ufs-probe` bootargs and `omamobile/camera` firmware
paths into `omamobile-int`
([KERNEL-PUBLISH](../device/cheetah/KERNEL-PUBLISH.md)). The plan also
renamed the kernel's GitHub repository from `linux-omandroid` to
`linux-omarchy-mobile`, where `tools/publish-kernel` pushes and where the
kernel has been published since 2026-10-19. Where the kernel tree lives today is in
[CONTRIBUTING](../CONTRIBUTING.md) (`~/omamobile-kernel/linux`, or
`~/android/mainline` on older setups).

## 8. Phase 3 (GitHub and the working tree)

Phase 3 called for renaming the GitHub repository `derekross/omandroid` to
`derekross/omarchy-mobile` and moving the maintainer's checkout from an
`omandroid` directory to an `omarchy-mobile` one; the docs use the new
names. Checkouts made since clone `github.com/derekross/omarchy-mobile`
directly. The rename plan's Phase 3
also covered the maintainer's own notes and issue comments, which live
outside this repository.
