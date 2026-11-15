# omamobile-keyring

The public key that signs Omarchy Mobile's packages and the `[omamobile]` repository
database, in pacman's keyring format. Installing it runs
`pacman-key --populate omamobile`, which imports the key and marks it trusted
(`omamobile-trusted`), the same way `archlinux-keyring` works.

Two keys are trusted while phones move from the first to the second:

| Key | Fingerprint | Where its secret lives |
| --- | --- | --- |
| Release key (2026-10-26): an ed25519 primary that only certifies, with an ed25519 signing subkey that expires 2028-10-26 | `20567593566EEEE2DD8864608632C8075EB94673` | primary offline with the maintainer; the signing subkey alone on the build machine (`keys/gnupg.release`) |
| Original package key (2026-10-12) | `6C84FE3D240709E70E27CC94B301F5EA62B249FE` | the build machine (`keys/gnupg`) |

The original key signs this package, so a phone that trusts only it accepts the
release key with this update. Once packages are signed with the release key and
phones have this version, the original key moves to `omamobile-revoked` as a
bare fingerprint line ([RELEASES.md](../../docs/RELEASES.md) §10). Nothing in
`keys/` is ever committed.
