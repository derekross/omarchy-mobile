<!-- SPDX-License-Identifier: MIT -->
# omamobile-install-link

The install link's phone side ([INSTALL-LINK-PLAN](../../docs/INSTALL-LINK-PLAN.md)
§3.3, stage L5): a freshly installed phone finishes its setup with the
installer on the owner's computer over a USB function of its own, beside the
gadget's NCM and ACM. **Nothing here has run on a phone.** The first phone
runs are the plan's runbook, R0 to R10 (§11.2).

**Nothing runs without the marker** `/etc/omamobile/install-link`. Only a root
image built for the link carries it (`tools/build-rootfs --install-link`, for
a device whose descriptor says `INSTALL_LINK=yes`, or `test` for a development
or local image). The package is in every image; on a phone without the
marker its units' conditions fail and nothing changes. A development phone
places the marker by hand only in an approved runbook step (R3).

## What it installs

| Path | What |
| --- | --- |
| `/usr/lib/omamobile-install-link/omamobile-linkd` | The daemon (the installer's `linkd` crate, below) |
| `/usr/bin/omamobile-install-link` | `status` (read-only: the stage, the budget, after the end the reason and what is missing) and `reopen` (root's, after an `expired` end: one more setup boot from the next boot, §2.8) |
| `/usr/lib/omamobile-install-link/omamobile-link-gadget` | `add`/`remove`: the link's function on the gadget, beside NCM and ACM, under a hang marker (the installer's, unchanged) |
| `omamobile-install-link.service` | The daemon on FunctionFS. `ConditionPathExists=` the marker alone (§18 E1); after `omamobile-usb-mac` and `omamobile-boot-success`; wants `omamobile-usb-rescue`; started again after a crash; `ExecStopPost=` puts the gadget back; a sleep inhibitor for its life; block devices read-only (`DevicePolicy=closed`, `DeviceAllow=block-sd r`); writes `/etc/omamobile` and `/var/lib/omamobile` only |
| `omamobile-install-link-hold.service` | No login screen while the phone has no account: done when first boot has made one, the link has ended, or the daemon is not running |
| `omamobile-firstboot.service.d/50-omamobile-install-link.conf` | First boot skipped on a `firstboot.conf` of comments only (the release image's placeholder), so its unit stays inactive until the link writes the answers and starts it |
| `omamobile-install-link-agent` (user unit, Python) | The session's notice ("Setup is not finished. Tap to continue..."), the code window on a tap, the paused and unfinished notices (§2.8) |
| `/usr/share/omamobile-install-link/code-window/` | The code window (Quickshell); the code reaches it in its environment only |
| `/usr/lib/omamobile-install-link/screen-text` | A development stand-in for the first-start screen, for R2 to R6: prints the daemon's screen lines (the code among them) to the terminal it runs in; Enter is a volume key. No unit starts it |
| `/usr/lib/tmpfiles.d/omamobile-install-link.conf` | The state directory's mode (0711), where it exists |
| `/usr/share/omamobile/install-link/SOURCE` | The protocol, the installer commit and the patches it was built from |

Not here yet: `omamobile-install-screen`, the framebuffer program that shows
the code before the session exists (§3.3, R5), and the golden frames
(§11.1 item 3). Until the first exists, a phone at stage `waiting` shows no
code on its screen; R2 to R6 use `screen-text` over SSH.

## The source

The daemon, `omamobile-install-link` and the gadget script are the
installer's (derekross/omamobile-installer, `linkd/`, MIT), at the commit in
`source.conf`, pinned by the SHA-256 of GitHub's archive of it. The protocol
crate has no tag yet (plan §11.1, L2 item 1), so the pin is a commit of the
branch `linkd-ffs` (PR #15); it moves to the tag when there is one.
`patches/` applies on top until the installer has the change itself:

- `0001`: an unfilled answers placeholder is no `firstboot.conf` (and no
  `boot-update.conf`), as the plan's 2026-11-13 decision says.

`./fetch-source` fetches, checks and unpacks it (with the patches) into
`src-cache/` (gitignored) for `test/all`; makepkg fetches its own copy.

## The composition on the Pixel 7 Pro

The initramfs makes the gadget `g1` with NCM, then ACM, and the root keeps
it. `omamobile-link-gadget add` unbinds it, adds `functions/ffs.link`, links
NCM, ACM and then the link, sets `bcdDevice` 0x0200 and the Microsoft OS
descriptors, and binds it again; `remove` puts it back from the record
`add` made. That is the development composition (plan §3.3, "NCM, ACM,
link"), which keeps SSH over USB as the safety net through R2 to R7. The
release composition, the link alone, is R8's and is not built here.

**When the daemon dies** with its function bound, FunctionFS takes the whole
gadget off the bus (§18, E12): NCM and ACM go with the link until
`ExecStopPost=` (or the daemon's next start) runs `remove`, a few seconds.
The mount option `no_disconnect=1` would keep the gadget bound with the
link's function deactivated instead. That choice is the maintainer's
(the plan's §19, decision N5); the script mounts without it today.

## Tests

`test/all`, offline once the source is fetched, no phone, no root, no USB:
the installed layout; every unit's conditions and ordering, `systemd-analyze
verify`, and systemd's own evaluation of the conditions on scratch roots;
`has-answers`; `hold-login`; the agent against a stand-in daemon and against
the real one; the gadget script on the installer's fake configfs, as
shipped; the marker's rules with the real daemon on scratch roots (none, a
first start, the image's placeholder, a filled `firstboot.conf`, an account,
first boot's `done`, `done` for each reason), `status` and `reopen`.
`OMAMOBILE_LINK_BIN` points it at built binaries (makepkg's `check()` does);
without it, and with cargo here, it builds the daemon itself.

The root image's side is in the repository's tests: `tests/build-rootfs`
(`--install-link`), `tests/rootfs-smoke-link` (`tests/rootfs-smoke` on small
made-up images) and `tests/make-bundle` (`install_link` in `manifest.json`).
