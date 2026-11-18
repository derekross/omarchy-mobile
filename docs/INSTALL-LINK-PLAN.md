<!-- SPDX-License-Identifier: MIT -->
# Install link plan: the phone finishes its setup with the installer, over USB

Status (2026-11-12): **design accepted by the maintainer, with its twelve
decisions (§12). Stage L1, the protocol crate, is built in the installer's
repository as a draft pull request (derekross/omamobile-installer#4) and
tested in memory only. This revision corrects the plan for what building
it found: the crate's twenty-six differences from the plan (§15), seven
design flaws (F1 to F7; §11.3 names each fix and the test that proves it)
and what stage L2 needs (§11.1). It asks the maintainer four new questions
(§13). Nothing here has run on a phone, and no code, package, image or
partition in this repository has changed.** (2026-11-13: stage L5, the
package `omamobile-install-link` and the root image's side, is built in this
repository as a draft pull request and tested offline only; §19 lists what
it found; N5 and N6 were decided on 2026-11-14. Still nothing has run on a phone.) This is
milestone M2 of [INSTALL-EXPERIENCE-PLAN](INSTALL-EXPERIENCE-PLAN.md): the
USB channel a freshly installed phone offers at its first start, and what
runs behind it. The reference device is the Pixel 7 Pro (`cheetah`). The
computer side is the Rust installer (its `docs/DESIGN.md` §11 and §12,
`docs/APP.md`, and `docs/LINK.md` for the crate); this document is the
specification both sides implement. Where the crate and this document
differ, this document holds, and §16 lists what the crate changes.

The safety model in [CONTRIBUTING](../CONTRIBUTING.md) §3 and
[AGENTS](../AGENTS.md) §1 is unchanged. §14 lists each rule this design
touches and how it is kept.

Facts are marked **[V]** (verified in this repository, file named),
**[D]** (stated in public documentation) or **[I]** (inferred, to be
checked; each has a runbook step in §11).

Decisions this design implements and does not reopen:

| Date | Decision |
| --- | --- |
| 2026-11-09 (D1) | Provisioning happens on the phone. The computer hands Google's factory image over the install link at first boot; the phone checks and extracts it. |
| 2026-11-12 | The owner's answers also go over the install link at first start. The installer never edits an image: what is flashed is byte for byte what the release signed. |
| 2026-11-13 | Until the link exists, the desktop installer and the web page put the answers into placeholders the release image keeps for them ([RELEASES](RELEASES.md) §6.1): the bytes they change are ones the signed manifest names, and only after those bytes match it. When the link takes the answers over, "no `firstboot.conf`" in the checks below means no file or the image's unfilled placeholder (`omamobile-firstboot --check` says "no answers"). |
| 2026-11-12 (D2, re-decided) | The computer downloads the factory image from Google after the owner accepts Google's terms in the installer. The project hosts none of Google's files. |
| Standing | Linux never writes the modem's NV partitions. Only slot B and `userdata` are ours. The radio backup is read-only, holds the IMEI and never leaves the owner's computer. The installer never sends the unlock command. Nothing identifying is committed. |

If the project were ever allowed to ship the extracted files itself
(undecided, out of scope), the link would lose §5.6's factory messages and
§6's extraction, and keep the answers, the radio backup, the smoke report
and the restart.

## Contents

1. [Goal and non-goals](#1-goal-and-non-goals)
2. [Threat model and trust](#2-threat-model-and-trust)
3. [Where the link lives in the boot](#3-where-the-link-lives-in-the-boot)
4. [The USB function](#4-the-usb-function)
5. [The protocol](#5-the-protocol)
6. [What runs on the phone behind the link](#6-what-runs-on-the-phone-behind-the-link)
7. [The computer side](#7-the-computer-side)
8. [Failure and recovery](#8-failure-and-recovery)
9. [Privacy](#9-privacy)
10. [Compatibility](#10-compatibility)
11. [Staged plan and runbook](#11-staged-plan-and-runbook)
12. [Decisions](#12-decisions)
13. [Decisions from building L1](#13-decisions-from-building-l1)
14. [Safety rules this design touches](#14-safety-rules-this-design-touches)
15. [What building L1 changed in this plan](#15-what-building-l1-changed-in-this-plan)
16. [For the crate to change](#16-for-the-crate-to-change)
17. [What bringing the crate to this plan found](#17-what-bringing-the-crate-to-this-plan-found)
18. [What building the daemon found](#18-what-building-the-daemon-found)
19. [What packaging the link found (L5)](#19-what-packaging-the-link-found-l5)

## 1. Goal and non-goals

From the owner's side: after the flash the phone starts by itself and shows
"Waiting for the installer on your computer" with a six-digit code. The
owner types the code into the installer. The installer then sends the
answers, saves the radio backup on the computer, sends Google's factory
image, waits while the phone extracts it, restarts the phone and shows the
check list. The owner sets up no USB network, runs no SSH and opens no
terminal.

Non-goals:

- **Not a remote shell or a file transfer service.** It carries the fixed
  messages of §5 and nothing else.
- **Not for a phone in use.** It exists on a first start and ends with the
  setup, or by itself when the setup is not finished (§2.2). Once an
  account exists it can do only what §2.7 lists.
- **Not secure mode.** Encryption, our boot key and the lock are
  [SECURITY-PLAN](SECURITY-PLAN.md)'s. §3.4 says how its setup mode reuses
  this protocol later.
- **Not firmware updates.** M5 reuses §6's extraction package, not the link.
- **No change to what is flashed, or to who flashes it.** Slot B's images
  and `userdata` are written in fastboot, before the link exists.

## 2. Threat model and trust

### 2.1 What the phone is at that moment

A freshly flashed development-mode phone: bootloader unlocked, `userdata`
plain ext4, no user account, `sshd` enabled with no authorized key
(`rootfs/build-inside`) **[V]**. Anyone holding it with a cable can put it
in fastboot and write slot B and `userdata`, and the initramfs runs a root
shell on its USB serial function for the seconds before it hands over
(`initramfs/init`, the `getty` on `ttyGS0`) **[V]**. The link can't make
that phone resistant to a person who holds it. What it must not do is add
a way to act on the phone **silently, from any USB host it happens to be
plugged into**: take the radio backup (the IMEI), plant an account or an
SSH key, or feed files to root.

### 2.2 When it exists, and when it ends

| Condition | Link |
| --- | --- |
| The root image carries `/etc/omamobile/install-link` (written by `tools/build-rootfs` for a release image, so it is part of what the release signed), and the phone has no state file of the link, no `firstboot.conf`, no `/var/lib/omamobile/firstboot/done` and no account with a uid of 1000 or more (a release image has none: `rootfs/build-inside` refuses to build one that does **[V]**) | Offered: first start. The daemon writes its state file (stage `waiting`) before it changes the gadget, so every later start can tell this phone from one it never set up (§6.5) |
| The state file says `waiting`: no account exists | Offered at every boot, with no limit. Such a phone holds no account and no data, and is of no use until it is set up |
| The state file says `firstboot`, `firstboot-failed`, `firstboot-done` or `provisioned`: an account exists | Offered within the setup budget below |
| `finish` was received, the budget ran out, or the start-up rules of §6.5 ended it | Gone: the marker is deleted and `/var/lib/omamobile/install-link/done` written with the reason. No unit starts, no USB function is added |
| A phone installed before the link existed, or with `tools/install-phone` (its image copy has `firstboot.conf`): a marker, and a `firstboot.conf`, a first-boot `done` or an account, but no state file | Never offered. The daemon deletes the marker, writes `done` (`not-first-start`) and exits, before any gadget change |

**The setup budget (F3).** Before this revision the only limit began at
stage `provisioned`, so a phone that stopped earlier offered the link at
every boot for good. Now every stage with an account has one:

- A **setup boot** is a boot in which the daemon's start-up rules (§6.5)
  end at stage `firstboot` or later. The boot in which the answers were
  taken is not one: the account is made during it. A boot is counted
  once, however often the daemon starts in it: the state file holds the
  kernel's boot id (§6.5). There are at most **three** setup boots. At the start of a fourth the daemon ends the link
  before it touches the gadget.
- In every boot, from the moment an account exists, the link stays open
  only while a host is paired, and for **10 minutes** without one. The 10
  minutes run from the latest of: the owner's session being up (§2.8), the
  end of the last paired session, and the end of first-boot setup or of
  provisioning. At `firstboot-failed` the display manager is held (§3.3)
  and no session comes up: the 10 minutes do not run in such a boot, the
  code stays on the first-start screen, and the limit of three boots is
  what ends it (§17, P3). They do not run while either of those jobs runs
  or a step owes an answer (so the link is never closed under an installer that just
  asked for something). They are counted on the monotonic clock: a phone's
  wall clock can be wrong at a first start.
- When they run out the daemon closes the link **for this boot**: it puts
  the gadget back (§3.3) and the notice in the session says so (§2.8). It
  leaves a mark on the tmpfs, and a daemon started again in that boot
  offers nothing (§18, E4). The next boot opens it again if a setup boot is
  left.
- When the budget is spent the link ends for good. At stage `provisioned`
  it ends as `finished`: the smoke report is a report, not a requirement
  (Q11), so a phone whose computer never came back is complete. At an
  earlier stage it ends as `expired`.

What `expired` leaves: no marker, no token, no factory image (partial or
whole) and no working directory; `done` with the word `expired` and what is
missing (`backup`, `firmware`, `cameras`: words, no values); the stage, and
the pending NV checksums if `backup-done` was reached. The phone then works
as a phone without Google's files works: no Wi-Fi, sound, cameras or
modem. §2.8 says what the owner sees and how they finish.

`done`'s reasons: `finished`, `expired`, `not-first-start`,
`state-unreadable`, `inconsistent` (the last two: §6.5).

### 2.3 Who can reach it

Only the USB host on the cable. The link has no network side: it is a USB
function with two bulk endpoints (§4), not a socket, and in its release
composition the USB network function is not on the bus at all (§3.3).

### 2.4 What it refuses

| Never | How it is kept |
| --- | --- |
| A shell, a command, a program name, an argument | No message carries one. The daemon runs four fixed programs with fixed arguments (§6.1) |
| A path | No message carries one. A file name in `factory-begin` is shown in a log line and never used to open anything. Partition names are matched whole against the descriptor's `NV_PARTS` and `NV_BACKUP_EXTRA` in `/usr/share/omamobile/device.conf` **[V]** |
| A read of user data | The only reads sent to the host are the descriptor's radio partitions, the status of §5.4 and the smoke report |
| An account, a password or an SSH key on a phone that has an account | `answers` is taken at stage `waiting` only, and that stage ends when the answers are placed (§2.7) |
| A write outside named files | The daemon writes `firstboot.conf`, its own state directory and the factory image's one file, and `boot-update.conf` (Q3). The provisioning worker writes the directories `tools/phone-provision` writes today (§6.3). Each unit's `ReadWritePaths=` lists exactly these **[D]** (systemd.exec) |
| A write to a block device | The daemon's unit has `DevicePolicy=closed` and `DeviceAllow=block-sd r`: UFS block devices can be opened for reading only, whatever the code does **[D]**. The worker's unit allows no block device |
| Anything before the peer is confirmed | Unpaired, the phone answers `hello`, `status`, `pair`, `resume`, `ping` and `bye` only (§5.3), and `pair` only while a code is shown |

### 2.5 How the phone knows the peer

**A six-digit code on the phone, typed on the computer.** The phone draws a
random code (from `getrandom`). The installer asks the owner for it and
sends it in `pair`. The phone compares in constant time. Where the code is
shown depends on who owns the screen:

| When | Where the code is |
| --- | --- |
| No account yet (stage `waiting`), and while first-boot setup runs | On the first-start screen (`omamobile-install-screen`), whenever no host is paired |
| An account exists and its session is up | Nowhere, until the owner asks for it: in the unlocked session the owner taps the link's notice, and a window shows a new code (§2.8) |

A code is used once. A right code, five wrong ones, ten minutes in the
session's window, or that window closing replace it.

**Only a wrong code counts toward the lock (F4).** Before this revision a
wrong `resume` token and every malformed frame counted too, and twenty
locked pairing until a restart. That let honest hosts spend the tries: a
laptop that slept during the image's transfer came back to a suspended
stream, and each data frame it then sent was a protocol error and a wrong
try; a damaged download cost one per `factory-mismatch`. And any host on
the cable could spend all twenty in four minutes without seeing the screen,
after which the owner's own installer, holding a valid token, was locked
out until a restart (after the planned restart, at the cost of the smoke
report). Now:

| Event | Answer | Counted | The session |
| --- | --- | --- | --- |
| A wrong code | `bad-code` with `left`; the fifth, tenth, fifteenth and twentieth: `locked` | Yes | Stays |
| `pair` while locked | `locked` with `wait_s` | No | Stays |
| `pair` while no code is shown | `not-allowed` | No | Stays |
| A wrong token in `resume` | `bad-token` | No. A token is 256 random bits: counting guesses protects nothing | Stays |
| A wrong frame or a malformed message (§5.1) | `error`, `protocol` | No | Ends |
| A data frame with no open stream (§5.1) | `not-allowed`, once | No | Stays |
| An image that fails its whole-file check | `factory-mismatch` | No | Stays |

| Wrong codes since the last act at the phone | The phone |
| --- | --- |
| 5 | Replaces the code and locks `pair` for 30 s |
| 10 | Replaces the code and locks `pair` for 60 s |
| 15 | Replaces the code and locks `pair` for 120 s |
| 20 | Shows no code and locks `pair` until someone acts at the phone, or it restarts (`locked` with `wait_s` 0) |

- **An act at the phone** is a press of a volume key while the first-start
  screen is up, or the owner's tap that opens the code window in the
  session. It sets the count to 0 and draws a new code. The screen says
  which: "Too many wrong codes from the computer. Press a volume key for a
  new code."
- A right code does not reset the count; a restart does.
- **`resume` is never locked.** The lock exists to protect a code of a
  million values from a host nobody is watching: twenty guesses for each
  act at the phone, two chances in a hundred thousand. A host that cannot
  see the screen can therefore keep the owner from typing a code for at
  most 120 s at a time, and never past the owner's next key press; it
  cannot keep out an installer that holds the token.
- A right code gives the host a random 32-byte **session token**. The
  phone keeps its SHA-256. Every right code makes a new token, and the one
  before stops working (D24). `resume` with the token pairs again without a
  code: after a cable pull, in a second run of the installer (which keeps
  the token in its work directory, §7.1), and after the planned restart.
  `resume` when the phone holds no token is `not-allowed`.
- The `paired` reply carries a **serial proof**: SHA-256 over a fixed
  label, the host's nonce, the phone's nonce (§5.3) and the phone's
  `androidboot.serialno`. The installer computes the same from the serial
  it pinned in fastboot and stops if they differ, so the phone being set up
  is the phone that was flashed. The serial itself never crosses the link.
  **[I]**: that `/proc/bootconfig` carries `androidboot.serialno` on our
  kernel (`androidboot.cdt_hwid` is read from there today,
  `tools/phone-provision` **[V]**); step R0. On a phone whose bootconfig
  has no serial the daemon offers nothing and writes nothing (§18, E9).

Once an account exists, a code also proves that whoever typed it could
unlock the phone: the window that shows it opens only in the unlocked
session (§2.8).

What the code protects against: a USB host the owner is not sitting at (a
charger with a computer behind it, a second computer on a hub, a machine
the phone was left plugged into) pairing with a waiting phone. It proves
that whoever drives the host can read this phone's screen.

What it does not protect against:

- **Software on the owner's own computer.** It can read the typed code or
  drive the installer.
- **A person holding the phone.** They read the code, and could reflash
  anyway (§2.1).
- **A device between the phone and the computer** (a tampered hub or
  cable). The link is not encrypted: such a device sees the password hash,
  the Wi-Fi passphrase and the radio backup, and can change frames. A
  sha512-crypt hash of a four-digit PIN is as good as the PIN to anyone who
  records it. Encrypting the link with a key derived from the code is
  decision Q4.
- **A wrong factory image from a paired host.** The phone checks the image
  against the SHA-256 the host sends, which the host took from the signed
  build index. A paired host that lies can feed its own files to root.
  Decision Q5 has the phone check against its own signed copy of the index.

### 2.6 A pulled cable

USB bulk transfers either complete or fail; nothing on the phone depends on
a transfer completing. The daemon records each stage on disk (written to a
temporary file, synced, renamed) before it answers.

| Pulled during | The phone | After the replug |
| --- | --- | --- |
| Waiting, unpaired | Keeps showing the code | `hello`, `pair` |
| `answers`, before the reply | Either no `firstboot.conf` was written (stage `waiting`), or it was and first-boot setup runs: the stage is `firstboot`, recorded at once or, after a crash between the two, by the daemon at its next start (§6.5) | `resume`; `status` says which. The installer sends `answers` again only at `waiting` |
| First-boot setup | Carries on; it needs no host | `resume`, `status` |
| Radio backup | Stops reading. Nothing was written on the phone. The partial copy is on the computer | `resume`, then `backup-read` from the offset the computer holds |
| Factory image | Keeps the bytes up to the last synced offset | `resume`, `factory-begin` again: the phone answers with that offset |
| Extraction and provisioning | Carries on; it needs no host. On an error it stops and keeps the image | `resume`, `status`; after a failure `provision` again reruns it (every step is idempotent, as in `tools/phone-provision` **[V]**). After a success there is nothing to rerun (§6.6) |
| `restart`, before the reply | Restarts or not; the stage is `provisioned` either way | The installer waits for the link, then `resume` |
| Smoke report, `finish` | Finishes itself within the budget of §2.2 | Nothing is lost but the report |
| Nothing is pulled: the installer is killed and run again, or the page is reloaded | Notices nothing until the next frame. The old session lasts until the new `hello` | `hello`, which always starts cleanly with no replug (§5.3), then `resume` with the kept token, or a new code (§2.8) |
| Nothing is pulled: the computer sleeps | FunctionFS reports `SUSPEND`; nothing changes. An incoming stream is suspended after 120 s | The same session if the computer is back within ten minutes, else `hello` and `resume`. The image goes on from the phone's offset; nothing is counted against the host (§2.5) |

On the Pixel 7 Pro the MAX77759 opens the USB2 data switch at an unplug and
`omamobile-usb-rescue` closes it again within its 2 s poll while VBUS is
valid (`packages/omamobile-device-cheetah/bin/omamobile-usb-rescue`)
**[V]**. The link's unit wants that service, so a replug comes back in the
root. It does not come back in fastboot's place or in the initramfs on a
phone without the descriptor's `USB_SWITCH`; neither matters here.

### 2.7 What a paired host can do once the account exists

From stage `firstboot` on the phone has an account, and from the first
unlock it has the owner's data. The link must never be a standing way into
that phone. An unpaired host gets `hello`, `ping`, `status` and `bye`
answered, `pair` only while a code is shown, and `resume`. A paired host
can do this and nothing else:

| A paired host can | Until | Why it is no more than setup needs |
| --- | --- | --- |
| Read `status`, and at `boot` 2 the smoke report | The link ends | Neither names a user, a host name, a network, a serial or an address (§5.4, §9) |
| Read the descriptor's radio partitions | Stage `provisioned` | The backup must exist before the modem's first start. The partitions hold the phone's identity and calibration, nothing of the owner's use of it |
| Send one file of at most 8 GiB and have it checked, extracted and installed as Google's files | Stage `provisioned` | This is the widest thing the link allows: what is installed runs as root from the next boot. The file must match the digest the host sent, and with Q5 the phone's own signed index |
| Start first-boot setup again with the answers the phone kept | Only at `firstboot-failed` | No message carries new answers |
| Restart the phone | Once: at `provisioned`, in the boot in which provisioning ended (`boot` 1) | The planned restart. **Tightened in this revision:** `restart` was taken at `provisioned` in any boot, so a paired host could restart a set-up phone again and again for three boots. At `boot` 2 it is `not-allowed` |
| End the link | `finish`, at `provisioned` | |

A paired host cannot, at any stage with an account: send answers (no
account, password, SSH key, host name or Wi-Fi network can be added or
changed: `answers` is taken at `waiting` only); read, write or name any
file; read anything under `/home` or any log; run anything but the fixed
programs of §6.1; install, remove or update a package; reach the network;
keep the link open past §2.2's budget; or pair without the token or a code
the owner asked for in the unlocked session.

### 2.8 Pairing again after first boot, and the end (F3)

**The case.** From stage `firstboot-done` the display manager owns the
screen (§3.3), so the first-start screen can show no code. An owner
reloads the installer's web page during the radio backup. The token was in
the page's memory only (Q12). Before this revision `hello` then said
`pair: "token"`, nothing could pair, and because the only limit began at
`provisioned` the phone offered the link at every boot from then on; in the
release composition (§3.3) it also had no USB network function in any of
those boots.

**The ways to pair again:**

| Way | For it | Against it |
| --- | --- | --- |
| A window in the owner's unlocked session, opened by the owner's tap on a notice, showing a new code | The same act as the first pairing. It proves the screen can be read and the phone unlocked. It works for the page after a reload. Nothing more is kept on the computer | One more program (a user unit) and a local socket between it and the daemon |
| The lock screen shows the code | No unlock needed | A code on show to anyone who can see a phone that now has data, for as long as the link lasts; any host could guess at it the whole time; and it means changing Omarchy's lock |
| A second code made at the first pairing, kept by the installer on the computer | No screen needed | That is the token. The native installers keep it already (§7.1). The page would have to put it in the browser's storage, which Q12 refused, and a reload is exactly when the page has lost what it kept in memory |
| Refuse, and tell the owner to finish with `tools/phone-provision` | Nothing to build | It needs a checkout of this repository and an SSH key the owner may not have given, on a phone with no Wi-Fi. That is not an install an owner can finish |

**The design is the first (decision N1).**

- `omamobile-install-link-agent` is a user unit of the link's package. It
  starts with the owner's graphical session while the marker exists and
  connects to the daemon's socket, `/run/omamobile-install-link/agent`. The
  daemon accepts one peer: the account first boot made (the peer's uid
  from `SO_PEERCRED` **[D]** (unix(7)), compared with the name in first
  boot's `/var/lib/omamobile/firstboot/user` **[V]**). The first connection
  in a boot is what "the session is up" means in §2.2; if none comes, three
  minutes after the display manager started count instead.
- The socket carries fixed lines and nothing else. Agent to daemon:
  `show`, `hide`. Daemon to agent: `open BOOTS_LEFT CLOSES_S`,
  `code DIGITS VALID_S`, `locked`, `paired`, `closed BOOTS_LEFT`,
  `ended REASON MISSING...`. `locked` is sent after the twentieth wrong
  code (§2.5): the window closes and the notice reads "Too many wrong
  codes. Tap to show a new code."; the tap is the act that clears it.
- While the link is open and no host is paired, the agent keeps one
  notification: "Setup is not finished. Tap to continue with the installer
  on your computer." It holds no code. A tap opens a small window (in
  Omarchy's own look) and sends `show`; the daemon draws a new code and
  the window shows it for ten minutes or until it is closed (`hide`). The
  code is never in a notification's text, a file or a log. **[I]**: that a
  notification cannot be acted on, and the window cannot be seen, while
  Omarchy's lock is up; step R5b. The session starts locked (first boot
  sets lock-on-start **[V]**), so the owner must unlock first.
- `hello`'s `pair` says which case holds (§5.3): `code` while a code is
  showing, `ask` when the owner can make the phone show one, `token` when
  none can be shown now (the session is not up) and a token exists.
- The installer, with no token and `ask`, tells the owner: "Unlock your
  phone and tap Setup is not finished." It says `hello` again every 5 s
  until `pair` is `code`, then asks for the code. With no token and
  `token` (a page reloaded after the planned restart, before the owner
  has logged in) it says the same and asks again the same way: unlocking
  is all it takes.
- Opening the window is an act at the phone (§2.5): it clears a lock.

**What the owner sees at the end.**

| The link | The notice in the session |
| --- | --- |
| Closed for this boot (10 minutes with no paired host), setup boots left | "Setup with the installer is paused. Restart the phone to continue (N restarts left)." |
| Ended as `expired` | At each of the next three logins: "Setup was not finished: no Wi-Fi, sound, cameras or mobile network." and how to finish, below. `omamobile-install-link status` prints the same at any time |
| Ended as `finished` | None |

**How the owner finishes after `expired`:**

| Way | What it takes |
| --- | --- |
| `sudo omamobile-install-link reopen` on the phone, a restart, then the installer | The owner's password on the phone itself. It grants one more setup boot under the same ten-minute rule, with pairing through the session's window. It is taken only after `expired`, and takes effect at the next boot, where the gadget change runs under its hang marker like any other: `reopen` records the boot id it ran in, in a file of its own and not the state file (there it would make that boot counted, §18, E5), and refuses when the boot id cannot be read; a daemon started in that same boot exits before any gadget change. Decision N3 |
| `tools/nv-backup`, then `tools/phone-provision --first-install --nv-backup DIR`, over USB SSH | A checkout and an SSH key on the phone: the development way, unchanged (§10) |
| Install again | It erases `userdata` |

## 3. Where the link lives in the boot

### 3.1 The two places

FunctionFS needs a userspace daemon that writes the descriptors and then
reads and writes the endpoint files **[D]** (upstream Linux,
`Documentation/usb/functionfs.rst`). Today the initramfs composes the
gadget (`g1`: NCM, then ACM, `1d6b:0104`, serial string `omamobile`) and
the kernel keeps it across `switch_root` (`initramfs/init`) **[V]**.
First-boot setup runs in the root, before the display manager
(`omamobile-firstboot.service`) **[V]**.

| | In the initramfs | In the root's first start |
| --- | --- | --- |
| Gadget | Composed there already; one more function at the same place | The root already takes the gadget apart and puts it back at every boot, to set the NCM addresses, under a hang marker (`omamobile-usb-mac`) **[V]**. The same sequence adds a function |
| Boot images | A new static binary, FunctionFS setup and a screen in `initramfs/init`: every device's boot image changes, and the Pixel 7 Pro's needs a boot test before each change ships | None. The daemon is a package in the root image |
| What the link must reach | First-boot setup, the extraction tools (`unzip`, `lpunpack`, `debugfs`, Python), the session for the smoke report: all in the root. The initramfs would have to mount the root and run them from there, as PID 1's child, with the storage guard loop and the no-USB-host panic beside it | All there |
| Failure | A daemon bug sits next to PID 1 and the storage guard, in the image that must always boot | A unit that fails. The boot goes on, the gadget is as the initramfs made it |
| Updates | Only with new boot images | An ordinary package update |
| Secure mode's setup | The only place it can run: a blank `userdata` has no root | Not possible |
| Kernel | `CONFIG_USB_CONFIGFS_F_FS=y` is in arm64's `defconfig` and in the local `out-int` and `out-kernel-release` configs **[V]**; on the phone's running kernel **[I]**, step R0 | The same |

### 3.2 Choice: the root's first start

Everything M2's link has to do needs the root, and placing it there
changes no boot image. The price is that secure mode's setup can't use
this daemon where it runs today. §3.4 keeps that door open without paying
for it now.

### 3.3 What changes, and what does not

**`initramfs/init`: nothing.** The gadget it composes, the storage guard,
the hand-over and the no-USB-host panic stay as they are. No change in
this plan alters the Pixel 7 Pro's boot images, so
`omamobile-device-cheetah`'s boot files and version do not move for it.

**A new package, `omamobile-install-link`** (aarch64), owns:

- `omamobile-linkd`, the daemon: Rust, built on the protocol crate the
  installer also uses (§7.1). Packages in this repository already build
  with cargo (`packages/omatel/PKGBUILD`) **[V]**.
- `omamobile-link-gadget add|remove`, a script modelled on
  `omamobile-usb-mac`: write and sync a hang marker; unbind the UDC; create
  `functions/ffs.link` and mount FunctionFS; let the daemon write the
  descriptors; link the functions; bind the UDC; remove the marker. A boot
  that finds the marker leaves the gadget as the initramfs made it for
  that boot, says so on the screen, and tries again at the next. An `EXIT`
  trap always links the previous functions and binds the UDC again.
- `omamobile-install-screen`: draws the status lines and the code. Display
  only; it reads no touch. A small C program on the kernel's framebuffer
  (`CONFIG_DRM_FBDEV_EMULATION=y` in the local configs **[V]**), the same
  drawing code SECURITY-PLAN §5.3 plans for its PIN pad. **[I]**: that a
  write to `/dev/fb0` reaches the command-mode panel in the root with no
  compositor running; step R5. The fallback is Plymouth's message line.
  It also reads the two volume keys, for one purpose: a press tells the
  daemon that a person is at the phone (§2.5). **[I]**: that the keys'
  input device can be read in the root before the display manager; step
  R5.
- `omamobile-install-link.service`: `ConditionPathExists=` the marker
  alone (not "and not `done`": the start that finds `done` is the one that
  completes an interrupted end, §6.5 and §18, E1); `After=omamobile-usb-mac.service omamobile-boot-success.service`
  (one gadget change at a time; `devinfo` read-only again before the
  backup); `Wants=omamobile-usb-rescue.service`. While no account exists it
  is ordered `Before=display-manager.service` and does not finish starting,
  so SDDM (enabled in the image **[V]**) shows no greeter on a phone with
  no user, as `omamobile-firstboot.service` holds it back today **[V]**.
  From stage `firstboot-done` on it no longer holds the display manager.
  The daemon decides at its start whether this boot offers the link at all
  (§2.2, §6.5), before `omamobile-link-gadget add` runs. While the link is
  open it holds one of logind's sleep inhibitor locks **[D]** (systemd's
  `org.freedesktop.login1` interface; taken over D-Bus, no program is
  run), so the phone does not suspend under a transfer or under
  provisioning; it drops the lock when the link closes for the boot.
- `omamobile-install-link-agent` and its user unit: the notice and the code
  window in the owner's session (§2.8).
- `omamobile-install-link status|reopen`: `status` prints the stage, the
  budget and, after the end, the reason and what is missing; it is
  read-only. `reopen` is root's and is §2.8's.
- `golden/`: the protocol's golden frames, copied from the crate at the
  pinned tag (§11.1).

**A new package, `omamobile-provision`** (any), owns the extraction tools,
the on-phone provisioning command and `phone-smoke` (§6).

**`omamobile-firstboot`:** `--check --porcelain FILE`, which prints one
`KEY<TAB>reason` line for every objection (not only the first: today's
`validate` stops at its first `die` **[V]**), in the fixed words of §5.5,
and echoes no value, so the link can report problems per field. Its unit
and the rest of the script are unchanged: the link writes the same
`firstboot.conf` that `tools/install-phone` writes, and starts the unit. A
version bump. §11.1 has the details.

**`tools/build-rootfs`:** a release image gets the two packages and the
marker `/etc/omamobile/install-link`. **`tools/bundle-manifest`:**
`manifest.json` says `install_link: {"protocol": 1}`, so an installer knows
before the flash whether the release has a link. That is a new key in a
closed format: installers older than it refuse such a release, which is
the wanted outcome.

**The storage guard:** untouched. The daemon runs after the initramfs's
last guard pass, opens only the descriptor's radio partitions, read-only,
after the checks `tools/nv-backup` makes (§5.5), and never calls
`blockdev`. It cannot open a UFS device for writing (§2.4).

**The USB network function:**

| Composition | When | Why |
| --- | --- | --- |
| NCM, ACM, link (the link added last) | Bring-up of this plan, and any image built with a development SSH key | SSH stays as the safety net while the link is new (§11, R2 to R6) |
| Link alone | Release images, once R7 has passed | The owner's computer sees no network adapter and no serial port: nothing for its network manager to configure or ask about, one interface for the browser and Windows to bind, and no network path to the phone during setup |

Either way the composition lasts at most one boot: the next boot's
initramfs composes NCM and ACM again, as it always does. After `finish`,
when the link closes for the boot or ends (§2.2), and when the daemon stops
for any reason, `omamobile-link-gadget remove` puts the gadget back as the
initramfs made it. A killed daemon runs nothing, so the daemon records on
the tmpfs that it changed the gadget, and a start that finds the record
puts the gadget back before anything else (§18, E3). So in the release composition a phone is without its
USB network function only while the link is open: at most the first start
and three setup boots, ten unpaired minutes each.

### 3.4 Secure mode's setup, later

SECURITY-PLAN §5.4 streams the root image "over the USB network into setup
mode" and then takes `firstboot.conf`. INSTALL-EXPERIENCE-PLAN §8 asks for
one protocol. This design provides it without building it now: the framing
(§5.1), the handshake and the pairing are the same; `omamobile-linkd` is one
static binary; setup mode packs it into the release initramfs with a
smaller message set (a `root-begin` stream checked against the digest built
into `init_boot`, then the hand-over to the root, where this plan's daemon
carries on). That is SECURITY-PLAN's S3 and S6, it changes boot images, and
it gets its own runbook there. In secure mode `answers` carries no
`password_hash`: the PIN is chosen on the phone (Q9).

## 4. The USB function

| Item | Value |
| --- | --- |
| Device | `idVendor` 0x1d6b, `idProduct` 0x0104, manufacturer, product and serial strings as today **[V]**. `bcdDevice` 0x0200 while the link is in the configuration, so a host that caches descriptors by version reads them again **[I]** |
| Interface | `bInterfaceClass` 0xff (vendor specific), `bInterfaceSubClass` 0x6f, `bInterfaceProtocol` 0x01, `iInterface` "Omarchy Mobile install link". The subclass and protocol are chosen here; fastboot's interface is 0xff/0x42/0x03 **[D]** and no collision is known **[I]** |
| Endpoints | One bulk OUT and one bulk IN. `wMaxPacketSize` 64 (full speed), 512 (high speed), 1024 (SuperSpeed, with its companion descriptor) **[D]** (USB specification). No interrupt endpoint |
| FunctionFS | Descriptors in the v2 format with full-, high- and super-speed sets and one string table; events `BIND`, `UNBIND`, `ENABLE`, `DISABLE`, `SUSPEND`, `RESUME` **[D]** (`include/uapi/linux/usb/functionfs.h`). `DISABLE` and `UNBIND` end the session (§5.3). `SUSPEND` and `RESUME` are logged and change nothing: a computer that sleeps comes back into the same session if it is back within the session's ten idle minutes |
| Windows | Microsoft OS descriptors through the gadget's `os_desc` directory (`use`, `b_vendor_code`, `qw_sign` "MSFT100") and the interface's compatible ID `WINUSB` **[D]** (`Documentation/usb/gadget_configfs.rst`), so Windows binds its generic USB driver with no driver file **[D]**. This is the 1.0 form of the descriptors; INSTALL-EXPERIENCE-PLAN names 2.0. The 1.0 form is what configfs generates and is enough for one vendor interface **[I]**; step L3 and a Windows test decide |
| WebUSB | A browser needs no special descriptor to open a vendor-class interface that no kernel driver holds; the WebUSB platform descriptor (`webusb/use`, `bVendorCode`, `landingPage` in configfs since Linux 6.3 **[D]**) only adds the "go to this page" notice. Off in the first version (Q7). Vendor class 0xff is not among the classes browsers keep from pages **[D]** (the WebUSB specification) |
| Linux hosts | No kernel driver binds 0xff/0x6f/0x01 **[I]**. The installer's udev rule (INSTALL-EXPERIENCE-PLAN §4.1) gains one line matching the interface triple |

**How the host finds it.** By the interface, never by vendor and product:
`1d6b:0104` is also what the phone shows with no link. The installer waits
for a device with an interface 0xff/0x6f/0x01 whose string is as above.

**Fastboot on the same cable.** The two are never on the bus together.
Fastboot is the bootloader's device and leaves at `reboot`; the initramfs's
NCM and ACM device appears for the seconds before the hand-over; then the
gadget is re-bound with the link. The installer's state after the write is
"wait for the link" with a timeout of 10 minutes (the first start grows
the root to about 110 GB, `docs/INSTALL.md` **[V]**); what the phone's
screen shows meanwhile is the boot animation, then the code.

## 5. The protocol

Protocol number **1**. All integers are little-endian. Text is UTF-8.
Protocol 1 becomes fixed at the crate's first tag (§11.1, L2). Until then
it is this section, which this revision changed in place (decision N4);
from the tag on, a change to the wire is a new number.

### 5.1 Framing

One frame is one USB bulk transfer. A frame is a 56-byte header, the
payload, and at most one pad byte.

| Offset | Size | Field | Value |
| --- | --- | --- | --- |
| 0 | 4 | magic | `4f 4d 49 4c` ("OMIL") |
| 4 | 1 | frame version | 1 |
| 5 | 1 | kind | 1 = message (JSON), 2 = data (raw bytes) |
| 6 | 2 | flags | bit 0 = a pad byte follows the payload; other bits 0 |
| 8 | 4 | seq | 0 for a `hello` and for the frame that answers it; then +1 per frame, per direction (§5.3) |
| 12 | 4 | len | payload bytes: at most 262144 for a message; 1 to `max_data` (§5.3) for data |
| 16 | 8 | offset | data: the payload's position in the open stream; message: 0 |
| 24 | 32 | sha256 | SHA-256 of the payload |

- **Pad.** When 56 + `len` is a multiple of 64, the sender sets flag bit 0
  and appends one zero byte, which is neither counted in `len` nor hashed.
  Every transfer therefore ends in a short packet at each of the three
  packet sizes, and neither side depends on zero-length packets.
- **One frame has one encoding (D8).** The reader refuses the pad flag
  where no pad is due, a pad byte that is not zero, bytes after the frame,
  a data frame with no payload, and an offset whose end does not fit 64
  bits.
- **Reading (D6).** Each side reads with a buffer of 56 + the larger of
  `max_data` and 262144 + 1 bytes, rounded up to a multiple of 1024 (a
  message may be 262144 bytes whatever `max_data` is), and gets one frame
  per completed read **[I]** (FunctionFS returns at the short packet; step
  L3).
- **A frame that is wrong:** the magic, the version, the kind, a reserved
  bit, a `seq` that is not the expected one, a `len` over the limit or not
  the bytes that arrived, a digest that does not match, a data frame at the
  wrong `offset` or past the stream's end, anything in the item above; and
  a message frame whose payload is not a message of protocol 1 (D5): not
  JSON, not an object, nested more than 32 deep, a key given twice, no `t`,
  or a known `t` with a missing, unknown or wrongly typed field (§5.2).
  In a session the phone sends `error` with `code: "protocol"` and no `re`,
  and ends the session (§5.3). An open stream is kept as it was at its last
  acknowledged offset. Nothing is counted toward the pairing lock (§2.5).
- **With no session open** (before the first `hello`, after `bye`, after a
  frame error, after the link went down, after ten quiet minutes) a frame
  that is not a valid `hello` is dropped: not answered and not counted
  (D4). After one frame error the frames already under way would otherwise
  each be answered.
- **A data frame with no open stream is not a frame error (F4).** It is
  what an honest host sends after its stream was suspended behind its back
  (§5.3). The phone drops it, answers the first such frame since the last
  message with `error`, `code: "not-allowed"` and no `re`, and keeps the
  session. The host then sends `factory-begin` again and goes on from the
  offset the phone answers.
- **Flow control** is §5.7.

### 5.2 Messages

A message is one JSON object with a `t` (type). The host's messages carry
`id`; the phone's answer carries `re` with that number. In a session the
phone answers every message exactly once, with the reply named below or
with `error`. Messages the phone sends by itself (`progress`, `ack`,
`data-end`, and the events that end a long step) carry no `re`.

- **Messages are read strictly (D1).** A key the reader does not know is a
  malformed message (§5.1), in every message but two: `hello`, in both
  directions, and the `version` error ignore unknown keys, because those
  two must stay readable across protocol numbers. A message that silently
  loses a key its sender meant is how two sides come to disagree about what
  was said; the protocol number is how the wire changes. An unknown `t` is
  answered `error`, `code: "unknown"`, and changes nothing.
- **`id` (D3)** is a whole number from 1 to 2^53 - 1. The host counts up.
  The phone echoes it and does not check its order: `seq` already orders
  the frames. What ties an answer to this run of the installer is the
  nonce in `hello` (§5.3), not `id`.
- **One step at a time (D15).** While a step owes the host an answer the
  phone still answers `ping`, `status`, `bye`, `abort` and a new `hello`;
  any other message is answered `busy`.
- **Anything unexpected changes nothing.** A message out of turn gets
  `not-allowed` and the phone stays where it was. Only §5.1's frame errors
  end the session.

`error` is `{t, re?, code, message, stage}` and the fields of its code,
which belong to that code and to no other (D21). `message` is fixed English
text for a log; the installer shows its own words chosen by `code`. An
`error` has no `re` when it ends a session (`protocol`, `internal` after a
fault), ends a long step (`provision-failed`) or answers a data frame.

| Code | Fields | Code | Fields |
| --- | --- | --- | --- |
| `protocol` | | `busy` | |
| `version` | `proto`: the phone's list; `host_nonce` | `backup-precondition` | `parts`: names |
| `unknown` | | `backup-mismatch` | |
| `not-allowed` | | `no-space` | `need`, `free` |
| `not-paired` | | `too-large` | |
| `bad-code` | `left` | `factory-mismatch` | |
| `locked` | `wait_s` | `provision-failed` | `step` |
| `bad-token` | | `firstboot-failed` | `steps` |
| `problems` | `problems`: [{`field`, `reason`}] | `battery` | |
| `internal` | | | |

The limits every reader holds to (D25):

| What | Limit |
| --- | --- |
| A partition name | 1 to 36 of `A-Z a-z 0-9 _ -` |
| The codename | 1 to 32 of `a-z 0-9 _ -` |
| A version, a release, a build, a step's name | At most 64 printable ASCII |
| `kernel` | At most 128 |
| `error.message` | At most 256 |
| A digest, a token, a nonce | 64 lower-case hex digits |
| Lists | At most 16 protocol numbers, 32 partitions, 64 steps, 32 problems |
| JSON | Nested at most 32 deep; a key at most once in an object |

### 5.3 Session, version and pairing

| Message | Direction | Allowed | Fields | Reply |
| --- | --- | --- | --- | --- |
| `hello` | host to phone | Any time; always frame 0 | `proto`: 1 to 16 numbers of 1 to 65535, none twice; `installer`: {`name`, `version`}, each 1 to 64 printable ASCII; `max_data`: 1024 to 4194304; `nonce`: 64 hex digits, drawn anew for every `hello` sent | `hello`: `proto` (the highest in both lists), `link` (daemon version), `device` (codename), `max_data` (the smaller of the host's and the phone's own, which is 1048576 unless the daemon is told otherwise), `nonce` (new per session), `host_nonce` (the host's, echoed), `stage`, `pair`, `wait_s`. No common number: `error`, `code: "version"`; the screen says the installer is too old or too new |
| `ping` | host to phone | In a session | | `pong` |
| `pair` | host to phone | Unpaired, a code is shown, not locked | `code`: six digits | `paired`: `token`, `serial_proof`. Wrong: `bad-code` or `locked` (§2.5) |
| `resume` | host to phone | Unpaired, the phone holds a token | `token` | `paired`: `serial_proof`, no `token`. Wrong: `bad-token` |
| `bye` | host to phone | In a session | | `bye`; the session ends, the stage stays |

**Starting a session (F1, F2).** The cases these rules close: an owner's
installer crashes during the radio backup and is started again, with the
cable untouched (drill R9). As first written, `seq` began again only at
`ENABLE`, so the new process's `hello`, its frame 0, met a phone expecting
frame 41: a protocol error, a wrong try, and so on for every later frame
until pairing locked, with only a replug to help and nothing to tell the
owner so (F1). And the first run's `hello` answer could still be waiting in
the phone's IN endpoint: the second run read it as the answer to its own
`hello`, kept its nonce, and computed a serial proof the phone no longer
agreed with, so the right phone was "not the phone that was just
installed" (F2).

1. **A `hello` is always frame 0, at any time, and starts the numbering
   again in both directions (D2).** The frame that answers it (the phone's
   `hello`, or the `version` error) is the phone's frame 0. A `hello` with
   another `seq` is a wrong frame. So a run of the installer that begins
   with `hello` always begins cleanly, whatever came before, with no
   replug.
2. **A `hello` ends the session before it.** The new session is unpaired.
   An open stream is suspended at its last acknowledged offset. A step
   that owes an answer runs on; its answer is applied where it changed
   something (a verified partition, a started first boot) and is not sent
   into the new session. The daemon cancels the old session's frames that
   the bus has not yet taken (§5.7).
3. **The host's nonce names the run.** The host draws 32 random bytes for
   every `hello` it sends. The phone echoes them as `host_nonce` in the
   frame that answers. From sending a `hello` until it reads a frame that
   is a `hello` or a `version` error with that `host_nonce`, the host
   discards every frame it reads, whatever its `seq`, `re` or digest, and
   counts none of them as an error. That frame is frame 0; from it on the
   host checks `seq`. An answer left over from another run can therefore
   never be taken for this one's, whatever its `id`.
4. **The serial proof is bound to both nonces:**
   `serial_proof` = SHA-256("omil-serial-v1" ‖ the host's 32 nonce bytes ‖
   the phone's 32 nonce bytes ‖ the serial's bytes).

`pair` in the phone's `hello`, and `wait_s`, which is always there and is 0
when nothing is locked (D9):

| `pair` | Means | `wait_s` |
| --- | --- | --- |
| `code` | A code is showing. `pair` is taken | 0 |
| `ask` | No code is showing; the owner can make the phone show one (§2.8) | 0 |
| `token` | No code can be shown now, and the phone holds a token | 0 |
| `locked` | `pair` is locked for `wait_s` seconds; 0 means until someone acts at the phone or it restarts (§2.5). Also, with 0: no code can be shown and no token exists | 0 or more; a timed lock says at least 1 |

`resume` is taken in every one of the four whenever the phone holds a
token.

A session ends at `bye`, a new `hello`, a frame error, FunctionFS's
`DISABLE` or `UNBIND` (the cable, a host reset), a write the bus did not
take for 30 s (§5.7), or 10 minutes with no frame from the host. Ending a
session never changes the stage.

Timeouts (D22): while a step owes an answer the phone sends `progress`
after every 5 s in which it sent nothing for that step. The host takes 60 s
of silence as a lost link only while it is waiting for the phone, not
while its own side is reading a file or the flow has asked for nothing;
it then starts again from `hello`. Three sessions in a row that the phone
ended over the protocol stop the installer. The phone suspends an incoming
stream after 120 s without a frame.

### 5.4 Status

| Message | Direction | Allowed | Reply |
| --- | --- | --- | --- |
| `status` | host to phone | In a session, paired or not | `status` |

`status`'s fields, every one always there (a `step` is empty and a number
0 when there is nothing to say) (D11):

| Field | Value |
| --- | --- |
| `stage` | Below |
| `boot` | 1 before the planned restart; 2 from the first boot that begins at `provisioned`, whatever restarted the phone (D23) |
| `release`, `kernel`, `device` | From `/usr/share/omamobile/rootfs/MANIFEST`; `uname -r`; the codename |
| `firstboot` | {`state`: `none`, `running`, `done` or `failed`; `step`: the step's name as `omamobile-firstboot` logs it, except the account step, which is `user` (the script logs "user NAME"); `n`, `of`; `failed`: names} |
| `backup` | {`state`: `none`, `listed` or `done`; `parts`: [{`name`, `size`, `verified`}]} |
| `factory` | {`state`: `none`, `partial` or `verified`; `have`, `size`} |
| `provision` | {`state`: `none`, `running`, `done` or `failed`; `step`, `n`, `of`; `optional_failed`: names of the optional steps that failed in a run that succeeded (§6.6)} |
| `link` | {`boots_left`: setup boots left (§2.2), 3 while none is counted; `closes_s`: seconds until the link closes for this boot, 0 while that clock is not running} |
| `battery`, `charging`, `free` | Percent; yes or no; bytes free on the root |

It names no user, host name, network, serial or address, so it is safe
unpaired.

The stages, in order, each recorded on disk before the reply that
announces it:

```
waiting -> firstboot -> firstboot-done -> provisioned -> finished
              |               (the radio backup and the factory image are
              v                sub-states: either first, after pairing,
        firstboot-failed       one stream and one step at a time)
```

The host learns how first-boot setup ended from `status`, which it asks
every 2 s while it waits (D18); no event says so, because no session may
be open when it ends.

### 5.5 The owner's answers, and the radio backup

| Message | Direction | Allowed | Fields | Reply and effect |
| --- | --- | --- | --- | --- |
| `answers` | host to phone | Paired, stage `waiting` | Required: `username`, `password_hash`, `ssh_keys` (a list, which may be empty). Optional: `credential`, `hostname`, `timezone`, `wifi_ssid`, `wifi_psk`, `full_name`, `email`. Their values are judged by the rules below | The phone writes the fields as a `firstboot.conf` candidate (mode 600) on a tmpfs and runs `omamobile-firstboot --check --porcelain` on it; nothing the host says about validity is used. Objections: `error`, `code: "problems"`, `problems`: [{`field`, `reason`}]; nothing is kept. None: the answers are placed and first-boot setup started in the order of §6.5, the stage becomes `firstboot`, and the reply is `answers-ok` |
| `firstboot-retry` | host to phone | Paired, stage `firstboot-failed` | | Starts the unit again with the kept file (`omamobile-firstboot` reruns safely **[V]**); `answers-ok` |
| `backup-list` | host to phone | Paired, stage before `provisioned` | | The phone checks what `tools/nv-backup` checks **[V]**: the board's first compatible string equals the descriptor's `COMPATIBLE`; each of `NV_PARTS` and `NV_BACKUP_EXTRA` is found exactly once by `PARTNAME` in `/sys/class/block/*/uevent`, is a block device, reads `ro` 1 and is not mounted. All hold: `backup-parts`, `parts`: [{`name`, `size`, `checked`}] (`checked`: in `NV_PARTS`). Otherwise `backup-precondition` with the partition names, and nothing is read |
| `backup-read` | host to phone | After `backup-parts`, a listed name | `name`; `offset`: a multiple of this session's `max_data`, at most the size (D7) | `data-begin` {`name`, `size`, `offset`}, then data frames from the partition, opened read-only, then `data-end` {`name`}. An offset equal to the size is answered with `data-begin` and `data-end` at once. A copy begun in a session with another `max_data` is read on from the multiple below its length |
| `backup-verify` | host to phone | After `data-end` for that name | `name`, `sha256`: of the computer's whole copy, read back from its disk | The phone reads the whole partition a second time and compares, as `nv-backup` does **[V]**: `backup-verified`, or `backup-mismatch` (the computer discards its copy; the partition must be read again before it can be verified again) |
| `backup-commit` | host to phone | Every listed partition verified | | The phone runs `backup-list`'s checks again and compares each partition's kernel device with the first run. Then it keeps the `NV_PARTS` lines, in `sha256sum`'s format, as the pending `/etc/omamobile/modem-nv.sha256`; reply `backup-done`. That file reaches `/etc` only in `provision`, so the modem cannot start before the computer has confirmed a verified copy |

`abort` (host to phone, any time a stream is open) ends the stream at its
last acknowledged offset; reply `aborted`.

**The answers' rules are first boot's own (D13)**
(`packages/omamobile-firstboot/bin/omamobile-firstboot`, `parse` and
`validate` **[V]**), and where this table and that script differ the script
holds:

| Field | Rule |
| --- | --- |
| `username` | Required; `USERNAME_RE`, not reserved, not a system account, not an account first boot did not make |
| `password_hash` | Required; sha512-crypt (`HASH_RE`) |
| `credential` | `pin` or `password`; left out or empty: `pin` |
| `hostname` | `HOSTNAME_RE` (1 to 63); left out or empty: `omamobile` |
| `timezone` | A zone under `/usr/share/zoneinfo`, at most 64 bytes; left out or empty: `UTC` |
| `wifi_ssid` | When given, 1 to 32 bytes |
| `wifi_psk` | Only with `wifi_ssid`; 8 to 63 printable ASCII, or 64 hex digits |
| `ssh_keys` | At most 8, each an OpenSSH public key of at most 8192 bytes |
| `full_name` | At most 128 bytes; no `:` or `,` |
| `email` | At most 254 bytes; one `@`, no white space |
| Every value | No control character |

The lengths first boot does not have (`timezone`, `full_name`, `email`, the
keys' number and size) are the link's own. Every problem with a value is
answered `problems` under its field, so the installer can show it there;
only a wrong JSON type, a missing required key or an unknown key is a
malformed message. The daemon judges with the crate's copy of these rules
first and with the script second, and the script's verdict is the one that
counts. `reason` is one of these words (D14), which `--porcelain` prints:

| Word | Means | Word | Means |
| --- | --- | --- | --- |
| `required` | Missing or empty | `length` | Too short or too long for its form (`wifi_ssid`, `wifi_psk`) |
| `format` | Not the form the rule asks | `without-ssid` | `wifi_psk` with no `wifi_ssid` |
| `reserved` | A name a person cannot take | `system-account` | The name of a system account in the image |
| `control-character` | A control character in the value | `exists` | An account of that name exists that first boot did not make |
| `too-long` | Over the link's own length | `no-such-zone` | Not under `/usr/share/zoneinfo` |
| `too-many` | More than 8 keys | | |

The last three only the phone can know. A reason is 1 to 32 of `a-z 0-9 -`.

**The backup's marks (D20).** The listing and each partition's "read" and
"verified" marks live for one boot, across sessions (§2.6 has the backup go
on after a cable pull); only `backup-done` is in the state file. A second
`backup-list` with the same answer keeps the marks; another answer
replaces them. `backup-read` takes a partition's verified mark away again.

The computer writes the backup as `tools/nv-backup` does: `NAME.img` files,
`SHA256SUMS`, `partitions.txt` and `NV-BACKUP`, directory mode 700, files
600, into a new directory **[V]**, so `tools/nv-backup --check DIR` reads it
later. It writes and syncs all of them **before** it sends `backup-commit`,
so a backup the phone has recorded as done is whole on the computer even
if the installer dies at the next instruction.

### 5.6 The factory image, provisioning, the report and the end

| Message | Direction | Allowed | Fields | Reply and effect |
| --- | --- | --- | --- | --- |
| `factory-begin` | host to phone | Paired, stage before `provisioned`, no stream open, provisioning not running | `size`: 1 to 2^53 - 1 (over 8 GiB: `too-large`); `sha256`; `build`: 1 to 64 printable ASCII; `name`: 1 to 255 bytes, no control character, shown only | The phone needs the bytes still to come plus the working space of §6.4 free, or `no-space`. `factory-ready` {`offset`, `ack_every`, `window`}: `offset` is 0, or the last synced offset of a kept file with the same `size` and `sha256` (another file's partial is deleted). A kept file that was already verified answers its size, loses its verified mark and is checked again at `factory-end` (D17). The host then sends data frames from that offset, inside the window (§5.7) |
| `ack` | phone to host | During the stream | `offset` | Sent after each `ack_every` bytes (67108864) are written and synced, and once more when the last byte is (D16). The offset is the end of the frame that crossed the line. It is the resume point: a transfer goes on from the last acknowledged offset, and bytes after it are sent again |
| `factory-end` | host to phone | The image's stream open, every byte sent | | The phone reads the whole file back and hashes it (`progress`, `what: "factory-check"`). Equal: `factory-verified`. Different: the file is deleted and the answer is `factory-mismatch`; nothing is counted (§2.5) |
| `provision` | host to phone | Paired; stage `firstboot-done`; `backup-done`; the image verified; provisioning not running; charging, or battery at least 30 % | | At `firstboot-failed`: `firstboot-failed` with `steps` (D18). At `provisioned`: `not-allowed` (D19, §6.6). Otherwise `provision-started`, then `progress`, and at the end the event `provision-done` {`steps`: [{`step`, `state`: `ok`, `failed` or `skipped`}]} or `error`, `provision-failed` with `step`. A run succeeds when every required step is `ok`. On success the stage is recorded as `provisioned`, then the factory image and the working directory are deleted, then the event is sent (§6.5) |
| `restart` | host to phone | Paired, stage `provisioned`, `boot` 1 | | `restarting`; then `systemctl reboot`, never `reboot-to` (the units' stops run). At `boot` 2: `not-allowed` (§2.7) |
| `smoke` | host to phone | Paired, stage `provisioned`, `boot` 2 | | The phone waits up to 180 s for the session, runs `phone-smoke --here --json` and replies `smoke-report` {`report`}: any JSON value, passed on as the test wrote it (D26). One that does not fit a message is answered `internal` |
| `finish` | host to phone | Paired, stage `provisioned` | | The stage is recorded as `finished`; the reply is `finished`; then the marker, the token and the state are deleted, `done` is written (`finished`) and the gadget is put back (§3.3) |

With the image's stream open the phone takes `factory-end`, `abort`,
`ping`, `status`, `bye` and `hello`, and answers any other message
`not-allowed` (D15). A host that wants the radio backup during the
transfer sends `abort` first; the image goes on later from its last
acknowledgement.

`progress` is {`what`, `step`, `done`, `total`} for every kind (D12);
`total` 0 means unknown. `what` is one of `factory-check`, `provision`,
`backup-verify`, `smoke`, `working`.

The integrity of each payload: every frame's digest (§5.1); the factory
image's whole-file SHA-256, checked on the phone before anything opens the
file; each radio partition's SHA-256, computed independently on both sides
from separate reads; each installed file's SHA-256 against the extraction's
own list (§6.3).

### 5.7 Flow control (F6)

**The case.** Bulk endpoints hold a sender back; they do not keep two
senders from waiting on each other. A plain write to a FunctionFS endpoint
file returns when its request has completed, which is when the host has
taken the data **[D]** (upstream Linux,
`drivers/usb/gadget/function/f_fs.c`), and a host's write completes when
the phone has read it. As first written, the phone wrote `ack` after 64 MiB and
read "the next data frame only after it has written the previous one". A
host that sends the image in a loop and reads afterwards never reads the
`ack`: the phone waits in its write, the host in its next write, for good,
at the first 64 MiB. The same the other way round for `abort` during a
partition's stream. The in-memory loopback of L1 cannot show it.

1. **Both sides read while they write.** The daemon's reads of the OUT
   endpoint and its writes to the IN endpoint are independent (two
   threads, or asynchronous I/O **[D]** (`tools/usb/ffs-aio-example` in
   upstream Linux)): it never waits for a write before it starts the next
   read. The host keeps one read pending on the IN endpoint whenever a
   session is open: a reader thread or an asynchronous transfer natively, a
   `transferIn` that is always outstanding in the browser.
2. **The image has a window the host must respect.** `factory-ready`
   carries `ack_every` (67108864) and `window` (twice that, 134217728). The
   host never has bytes sent beyond `acked` + `window`, where `acked` is the
   offset of the last `ack` it has **read** (before the first, the offset
   in `factory-ready`). At the window's edge it stops sending and waits for
   an `ack`; 60 s of that is a lost link (§5.3). A host that does not read
   therefore stalls itself, at 128 MiB, with its reader free; a host that
   reads never waits, because the phone acknowledges every 64 MiB.
3. **The phone's queue of frames to send is bounded.** At most 8 frames
   wait for the bus. When 8 wait, the daemon stops reading the OUT endpoint
   until a write completes, which holds the host back through the bus. A
   write the bus has not taken after 30 s is a lost link: the daemon
   cancels what it queued (`io_cancel`, which dequeues the request **[D]**
   (the same file); **[I]**: that the phone's USB controller driver
   dequeues cleanly, steps L3 and R4) and ends the session; frames queued
   after the lost write and before the daemon hears of it are cancelled
   with it (§18, E7). The stream stays at its last
   acknowledged offset. So a host that ignores the window cannot hold the
   daemon either.
4. **A partition's stream needs no window.** The phone hands the bus the
   next data frame when the bus has taken the one before, so the host's
   reads set the pace. The daemon reads the OUT endpoint throughout, so
   `abort` is always taken; it answers `aborted` after the frame in flight,
   and the host discards data frames until `aborted`.
5. **The host's writes have the same 30 s.** A write the phone has not
   taken by then is a lost link: cancel, then `hello`.
6. **The disk holds the host back too.** The phone reads the next data
   frame only after it has given the previous one to the file. An `ack`
   marks what is synced; it is the resume point and the window's base.

The test that proves it is L3's `flow` (§11.1), on real FunctionFS over
`dummy_hcd`.

## 6. What runs on the phone behind the link

### 6.1 The fixed programs

| Program | Run by | With |
| --- | --- | --- |
| `omamobile-firstboot --check --porcelain` | the daemon | the candidate file |
| `omamobile-firstboot.service` | the daemon, through systemd | nothing |
| `omamobile-provision first-install` | the daemon, as the transient unit `omamobile-provision-run.service` | the fixed path of the factory image and of the pending NV checksums |
| `phone-smoke --here --json` | the daemon | `SMOKE_DEVICE` from the descriptor |

### 6.2 The extraction tools on the phone

`omamobile-provision` packages `tools/extract-vendor-firmware`,
`extract-vendor-chroot`, `extract-fingerprint-vendor` and
`extract-camera-data` unchanged, copied from `tools/` at build time as
`tools/make-bundle` copies them into a bundle today **[V]**, so there is
one source. Its command `omamobile-provision first-install` is
`tools/phone-provision --first-install` with the SSH pushes replaced by
local installs.

- **Dependencies:** `unzip`, `android-tools` (`simg2img`, `lpunpack`),
  `e2fsprogs` (`debugfs`), `erofs-utils` (`fsck.erofs`), `binutils`
  (`readelf`), Python with `unicorn` and `pyelftools` for the camera step.
  **[I]**: that Arch Linux ARM carries all of them for aarch64, the Python
  `unicorn` module included; stage L4.
- **Per-phone inputs come from the phone itself:** the board id from
  `androidboot.cdt_hwid` in `/proc/bootconfig`, written to `props.conf`
  (root's, mode 600) and never printed, exactly as `phone-provision`'s
  `board_id` does today **[V]**. It never crosses the link.
- **The camera step** runs the HAL's functions under the emulator, as on
  the laptop. Running them natively in a chroot (INSTALL-EXPERIENCE-PLAN
  §5.2) is a later change with its own byte-for-byte check.
- **Byte for byte.** For one factory image, today's laptop run and the
  aarch64 run must give the same tree: every file's SHA-256, mode and
  symlink target, and the chroots' `MANIFEST` and `SOURCE` files. Stage L4
  does this in the aarch64 build container, R1 on the phone. A build for
  which they differ is not offered.

### 6.3 What provisioning writes

What `tools/phone-provision --first-install` writes today **[V]**, and
nothing else:

| Step | To | How |
| --- | --- | --- |
| firmware | `/usr/lib/firmware/updates` | merged |
| sensors | `/usr/share/omamobile/sensors/registry` | replaced |
| gnss, modem | `/usr/lib/omamobile-vendor/<profile>` | replaced |
| fingerprint | `/usr/lib/omamobile-fp/{root,MANIFEST,SOURCE}` | replaced |
| camera | `/usr/lib/firmware/omamobile/camera` | merged; optional: a camera step that fails is run once more, and one that fails twice is reported in `provision-done` and does not fail the rest (§6.6) |
| modem data | `/etc/omamobile/modem-nv.sha256` from the pending file; `/var/lib/omamobile-vendor/modem/props.conf` from bootconfig | written, then read back |

Each tree is checked against its SHA-256 list, as `push_tree` checks it
**[V]**, and **a power cut must leave each tree whole or untouched.**
`push_tree` removes each top-level entry of a replaced tree and then moves
the new one in **[V]**: over SSH with a person watching, that gap is
small. At an owner's first boot it must not exist, because `omamobile-fp`
and the modem start by themselves at the next boot and must never find
half a tree. So the worker unpacks a replaced tree beside its target on
the same file system, checks it there, and puts it in place by exchanging
the two names (`renameat2` with `RENAME_EXCHANGE` **[D]**, rename(2)), then
removes the old one. A merged tree is written file by file, each to a
temporary name and renamed. The modem's checksum file is the worker's last
write, so the modem has nothing to start from until everything before it
is in place.

The worker starts and stops no service: the firmware loads at the restart,
`omamobile-fp` starts once per boot by its own unit, and the modem starts
at the next boot from its own unit. Its last act is its result file,
`/var/lib/omamobile/install-link/provision.result` (each step and its
state; written to a temporary file, synced, renamed), which is what the
daemon reads when the worker ends and at its own start (§6.5).
The worker's unit has `ProtectSystem=strict`, `ReadWritePaths=` the six
targets, the result file and the working directory, no network and no
device access; the extraction itself (which parses the image) runs inside
it as an unprivileged user that can write the working directory only.

### 6.4 Space, time and what is kept

| | Value | Source |
| --- | --- | --- |
| Free on `userdata` after the first start | about 110 GB less the root image | `docs/INSTALL.md` **[V]** |
| The factory image | about 3.9 GB **[I]**, at `/var/lib/omamobile/install-link/factory.zip` (mode 600) | the build index holds each build's exact size |
| Working space | the unpacked image archive, `super.img` sparse then raw, and `vendor.img` (about 1 GB, `extract-vendor-firmware` **[V]**): at most about 24 GiB at the peak **[I]**; R1 measures it and sets the number `factory-begin` checks |
| Transfer | 2 to 4 minutes at USB 2.0 high speed (20 to 35 MiB/s) **[I]**; the link's speed is read in R0 and the rate measured in R6 |
| Extraction and provisioning | "several minutes" on a laptop (`docs/INSTALL.md` **[V]**); on the phone unknown, the emulated camera step the slowest **[I]**; R1 measures it |
| The radio backup | about 430 MB (INSTALL-EXPERIENCE-PLAN §4.7 **[V]**) |

Temporary files live in `/var/lib/omamobile/install-link/` (the image, the
state) and `/var/lib/omamobile/provision/work.*` (the extraction), both
mode 700 and on `userdata`, not in RAM. The working directory is removed
when the worker ends, however it ends. The factory image is removed when
provisioning succeeds (a camera-only failure included, §6.6), and when the
link ends, however it ends (§2.2). A start of the daemon removes a working
directory left by a crash (§6.5).

Kept: the installed files of §6.3, `/usr/lib/omamobile-provision/SOURCE`
(the build id and the image's SHA-256, for M5), and `done`. Not kept: the
image, anything unpacked, the token, the code, the answers
(`omamobile-firstboot` deletes `firstboot.conf` **[V]**).

### 6.5 What is written in which order, and what the daemon finds at its start (F7)

**The case.** As first written, the phone renamed the checked candidate to
`/etc/omamobile/firstboot.conf` and then recorded stage `firstboot`. Power
is lost between the two. At the next boot the marker and a `firstboot.conf`
are both present, and §2.2's last row had the daemon delete the marker,
write `done` and exit: a phone with an account and no radio backup, no
firmware and no link.

**Every write is a temporary file in the target's own directory, synced,
then renamed, then the directory synced.** The candidate is on a tmpfs, and
a rename cannot cross file systems, so "renamed to `firstboot.conf`" was
never possible as written: the candidate is copied.

**The state file exists from the first start.** The daemon writes it
(stage `waiting`) before it changes the gadget. A `firstboot.conf` on a
phone with no state file is therefore not the link's, and one on a phone
with a state file is.

| Step | The order | A crash before the next line leaves |
| --- | --- | --- |
| Taking the answers | 1. The candidate (mode 600) on a tmpfs; both checks pass | Nothing: stage `waiting` |
| | 2. `boot-update.conf` (Q3) | A `boot-update.conf` on a phone at `waiting`: harmless, and written again later |
| | 3. The candidate copied to `/etc/omamobile/firstboot.conf` (mode 600) | The state file at `waiting` and a `firstboot.conf`: the table below makes it `firstboot` |
| | 4. `omamobile-firstboot.service` started | The same; a start of the daemon that finds stage `waiting` made `firstboot` by the table below, a `firstboot.conf` and the unit not run in this boot starts it (§18, E2). The unit also starts by itself at the next boot, on its own condition **[V]** |
| | 5. The state file: stage `firstboot` | Stage `firstboot`; the host learns it from `status` |
| | 6. `answers-ok` | |
| The end of first-boot setup | The daemon records `firstboot-done` or `firstboot-failed` when the unit ends | The table below reads it from what first boot left |
| The image | Each `ack`: the file synced, then the state file's `synced`, then the `ack` | A file longer than `synced`: cut back |
| The end of provisioning | 1. The worker's result file. 2. The state file: stage `provisioned`. 3. The image and the working directory deleted. 4. `provision-done` | After 1: the daemon reads the result. After 2: an image at stage `provisioned`, deleted at the start |
| `finish` | 1. The state file: stage `finished`. 2. `finished` sent. 3. `done` written, the state deleted, the gadget put back, the marker deleted last (every end keeps this order: §18, E1) | Stage `finished` without `done`, or `done` with the marker still there: the start completes the end |

**The state file says which boot it was last written in.** It holds the
kernel's boot id (`/proc/sys/kernel/random/boot_id` **[D]**, random(4)),
written in the same write as everything else in it. A start that finds
another id is the first of a new boot: it counts the boot (§2.2) and sets
`boot` (§2.7) in the one write that records the new id. A mark kept
anywhere else (a file under `/run`, say) loses a boot: a daemon killed
after that mark and before the state file's write would start again in a
boot it believes counted, with `boot` still 1 (§17, P1).

**At its start the daemon squares its state file with the phone before it
offers anything.** First, in this order:

| # | It finds | It does |
| --- | --- | --- |
| 1 | `done` | Deletes the marker if it is there and exits. (The unit's condition normally keeps it from starting at all) |
| 2 | No state file; no `firstboot.conf`, no first-boot `done`, no account | A first start: writes the state file, then offers the link |
| 3 | No state file, and any of those three | Not a phone the link set up (§2.2): `done` (`not-first-start`), no gadget change |
| 4 | A state file it cannot read (damaged, or another version) and no account | As row 2. Nothing is lost: there is no account, and a code can be shown |
| 5 | A state file it cannot read, and an account | Ends the link: `done` (`state-unreadable`). It never guesses about a phone that has an account. The owner finishes as after `expired` (§2.8) |
| 6 | Stage `finished` | Completes the end: `done` (`finished`) |
| 7 | Anything else | The two tables below, in turn; then the budget of §2.2; then the result is recorded and the link offered, or ended |

For stage `waiting`, `firstboot` or `firstboot-failed`, the first row that
fits, from what first boot itself left on the phone:

| First boot's `done` | `firstboot.conf` | An account | The stage becomes |
| --- | --- | --- | --- |
| Yes | Either | | `firstboot-done`. (First-boot setup ran to its end, perhaps while the daemon was down) |
| No | Yes | Either | `firstboot` if the unit is running or has not run yet in this boot; `firstboot-failed`, with the steps its log marks `FAILED` **[V]**, if it ended failed in this boot. From `waiting` this is the case above: the answers were taken. `boot-update.conf` is written if it is missing. From `firstboot-failed` this is first boot's own retry at each boot **[V]** |
| No | No | The one first boot's `user` file names | `firstboot-done`. The script deletes `firstboot.conf` and then writes `done` **[V]**; power was lost between the two |
| No | No | Another one | None: the link ends, `done` (`inconsistent`) |
| No | No | None | `waiting`. From `firstboot`, the answers are gone; the installer sends them again, as it does at `waiting` |

Then, at any stage before `finished`:

| It finds | It does |
| --- | --- |
| A record of the image, no file | Drops the record |
| An image file, no record | Deletes the file |
| The file longer than the record's `synced` | Cuts it to `synced`: bytes after the last sync are not trusted |
| The file shorter than `synced` | A sync that did not hold: the file is emptied and `synced` set to 0 |
| "Verified", and the file's length is not `size` | Takes the mark away |
| Before stage `provisioned`: `backup-done`, no pending checksum file | Takes the mark away: the backup is taken again. At `provisioned` the mark stays whatever is found: the worker has used the file, and no backup may be taken at that stage (§17, P2) |
| A pending checksum file, no `backup-done` | Deletes the file |
| Provisioning "running", its unit active (the daemon alone restarted) | Goes on watching it |
| Provisioning "running", no unit, a result file in which every required step is `ok` | Stage `provisioned`; the image and the working directory deleted |
| Provisioning "running", no unit, any other result, one that cannot be read as a result, or none | Provisioning failed, at the result's step or at `interrupted`. The working directory is removed and the image kept; `provision` runs it again |
| A working directory and no unit | Removes it |
| Stage `provisioned` and an image file | Deletes the file |
| A candidate or a temporary file of its own | Deletes it |

The backup's listing and marks are in memory (§5.5): after a restart of
the daemon the host lists again.

### 6.6 A camera-only failure (F5)

**The case.** §8 said a failed camera step could be put right with
"`provision` again before `finish`". The stages make that impossible: a
run whose camera step alone failed is a success, the stage becomes
`provisioned`, the image is deleted, and no image may be sent at that
stage. There is nothing to provision again from.

**Decided here:**

- **What it is.** A success with a note. `camera` is an optional step (the
  descriptor's `PROVISION_OPTIONAL`); every other step is required. The
  stage is `provisioned`, `provision-done` lists `camera` as `failed`, and
  `status` keeps saying so in `provision.optional_failed`, so an installer
  that lost the event (a cable pull, a rerun) still shows "Cameras: not set
  up".
- **The one retry is the worker's own.** It runs a failed optional step a
  second time in the same run, after the other steps, when the causes that
  pass (memory under the emulator, a full working directory) may have
  passed. A cause that does not pass is a build whose camera step cannot
  work, and stage L4's byte-for-byte check keeps such a build from being
  offered at all.
- **The image is not kept.** It is deleted at a success, as before. Keeping
  about 4 GB and its working space until `finish` for a rerun that would
  fail the same way a third time is a poor trade.
- **`provision` at stage `provisioned` is `not-allowed`** (D19).
- **A later retry** is not the link's: an update of `omamobile-provision`
  followed by M5's firmware path (which reuses this extraction and knows
  the build from `SOURCE`), or `tools/phone-provision` over USB SSH with
  the image on the computer (§10).

## 7. The computer side

### 7.1 The core

| Piece | What it is |
| --- | --- |
| The protocol crate | Framing, the message types and the limits of §5, with no I/O: bytes in, bytes out. The phone's daemon builds on the same crate, pinned by version, so there is one implementation of the wire. Which repository holds it is Q8 |
| A second transport | `Link`, next to fastboot's: find the interface (§4), claim it, bulk out and in. Native through the USB library the core already uses; in the browser through WebUSB's `transferOut` and `transferIn`. It gives one frame per read, keeps a read pending while it writes and gives every write 30 s (§5.7). A loopback transport and a pretend phone for tests, as fastboot has |
| The states after `installed` | `first-start` (wait for the link) -> `pair` (the code) -> `setup` (answers sent, first boot running) -> `radio-backup` -> `factory-send` -> `provision` -> `restart` -> `check` (the smoke report) -> `ready`, each with stops. `write_done` no longer ends the flow |
| The answers | Asked before the write, as today, and kept in memory until the link is paired. `core/src/firstboot.rs` already hashes the password as `openssl passwd -6` does; it now fills `answers`' fields instead of making file bytes. The form gains the SSH key, full name and email (`AnswersInput`) |
| The closed list | The link's send path takes a typed message, never bytes from a caller, as fastboot's command layer does. There is no "send raw" |
| The record | The token, the backup directory and the stage reached, so a second run of the installer goes on. In memory and in the work directory (mode 600); never in a report. A second run starts with `hello` and a new nonce and needs no replug (§5.3) |
| The backup's files | `SHA256SUMS`, `partitions.txt` and `NV-BACKUP` are written and synced before `backup-commit` is sent (§5.5) |
| Randomness | The host draws the nonce of each `hello` from the operating system's source (`crypto.getRandomValues` in the page) |

### 7.2 The three front ends

| Front end | Uses the link | Limits |
| --- | --- | --- |
| Command-line tool | `install --write` runs on through the link's states. The backup goes to `--backup-dir DIR` (required; a new directory). The factory image is the file the download step verified | None new |
| Desktop app (`omainstall`, the tool's `json` mode) | Draws the new screens. **App protocol 2** adds: the states above in `Screen.state`; the actions `pair` (the code as typed), `backup-dir` (an absolute path from the file chooser), and `wait` (a step the phone is doing; cancel only where the core allows); `progress.what` values `link-wait`, `firstboot`, `backup`, `factory-send`, `factory-check`, `provision`; three more fields in `answers`. APP.md §3.6 already says a version that writes takes a new number, so the link arrives with or after the write, never in protocol 1 |
| Web page | The same core in WebAssembly over WebUSB | Below |

WebUSB's limits where they matter:

- **Two permission prompts.** The bootloader's fastboot device and the
  link's device are different USB devices, so the owner picks the phone
  twice, each on a click **[D]**. Whether the browser remembers the second
  across the planned restart (the same descriptors and serial string)
  **[I]**; if not, a third click.
- **The radio backup needs a place on disk.** The page writes it through
  the File System Access API's directory picker, as a stream. Where that
  API is missing the page stops before the write and names the desktop
  app; it does not hold 430 MB of the owner's radio data in the browser's
  storage.
- **The factory image.** The page streams it into the link as it arrives
  from Google or from the file the owner picked, and keeps none of it; the
  phone's whole-file check is the check. A broken transfer resumes from
  the phone's offset only if the source can be read from that offset (a
  picked file can; a download only if Google's server honours ranges
  **[I]**, installer DESIGN §9).
- **The tab must stay open** and in front; a reload loses the token (Q12).
  Before first boot has made the account, the code is on the first-start
  screen and the owner types it again. After it, the page tells the owner
  to unlock the phone and tap the notice, and takes the new code (§2.8).
  After the planned restart the same works, or the owner does nothing and
  the phone finishes itself (§2.2).
- **Windows** binds the link without a driver file if §4's descriptors
  work **[I]**; fastboot itself still needs its driver there
  (INSTALL-EXPERIENCE-PLAN M4).

## 8. Failure and recovery

The way back is always the same and always there: slot A still holds
stock Android, and the phone still reaches fastboot by its buttons (Volume
Down + Power, about 20 s). The installer can flash again; a reinstall
erases `userdata` and starts the link from the beginning.

| Step | What can fail | On the phone's screen | In the installer | A rerun |
| --- | --- | --- | --- | --- |
| Wait for the link | The phone never shows it: a boot that failed, a gadget change that hung (the marker), a cable | The boot animation, or "The install link could not start. Restart the phone." | After 10 minutes: what to check, then how to restart, then how to reach fastboot | Restart the phone: the link is tried again. If it never comes: flash again, or install with `tools/install-phone` |
| Pair | A wrong code | The code; "Wrong code", and after five a new code with the wait | The same, in the core's words | Type again |
| Pair | Twenty wrong codes | "Too many wrong codes from the computer. Press a volume key for a new code." In the session: the same, with "Tap to show a new code" | "Press a volume key on the phone", or "Tap the notice on the phone" | One key press or tap. An installer that holds the token is never kept out (§2.5) |
| Pair | The serial proof differs | Nothing changes | "This is not the phone that was just installed." Stop | Connect the right phone |
| Pair again after first boot | The installer has no token (a reloaded page, a lost work directory) | The notice; after a tap, the window with a new code | "Unlock your phone and tap Setup is not finished", then the code | Any time the link is open (§2.8) |
| Any | The installer is killed and run again, or the computer slept | Nothing changes | Starts with `hello`; no replug, nothing counted against it (§5.3, §2.5) | Any time the link is open |
| Answers | First boot's rules object | Nothing changes | The form, with the problem under its field | Send again |
| Answers | Power is lost while they are taken | The boot, then setup or the code again | `status` says `firstboot` or `waiting` (§6.5); it sends the answers again only at `waiting` | Any time |
| First-boot setup | An essential step fails (`firstboot.conf` kept **[V]**) | "Setup stopped at: <step>" | The step's name; "try again" sends `firstboot-retry` | The unit also reruns at the next boot **[V]**, which is then a setup boot (§2.2) |
| Radio backup | A partition is writable, mounted, missing or doubled | Nothing changes | Stop: "the phone's storage guard isn't holding", with the names. No workaround is offered | Not until a person has looked: ask in an issue |
| Radio backup | A read fails, or the second read differs | Nothing changes | Retries that partition up to five times, then stops; nothing partial is kept on the computer | Any time |
| Factory image | No space; too large | "Not enough space" | Stop with the numbers | After a reinstall |
| Factory image | The transfer paused (the computer slept, the installer was stopped) | Nothing changes | `factory-begin` again; goes on from the phone's offset | Any time the link is open |
| Factory image | The whole-file check differs | "The file from the computer was damaged. Sending again." | Sends again once from zero; a second mismatch stops and deletes the computer's copy too | Downloads again |
| Provisioning | A required step fails, or power is lost during it | "Setup stopped at: <step>" | The step; "try again" sends `provision` | Idempotent. The image is still there, and every installed tree is whole or untouched (§6.3) |
| Provisioning | The camera step alone fails, twice | Goes on | A line in the final list: "Cameras: not set up", also in a later run (§6.6) | None over the link. Later: an update of `omamobile-provision`, or `tools/phone-provision` over SSH (§10) |
| Restart | The phone does not come back | Whatever the boot shows | After 10 minutes: restart by the buttons; then fastboot and flash again | The stage is `provisioned`: a later boot offers the link within its budget |
| Check | A required row fails | The lock screen | "Something went wrong", the rows, and a report to save (§9) | The phone is installed; the report is for an issue |
| Any stage with an account | No paired host for 10 minutes | The notice: "Setup with the installer is paused. Restart the phone to continue (N restarts left)." | If it comes back in this boot: the link is not on the bus; "restart the phone" | A restart, while setup boots are left |
| Any stage with an account | The budget is spent before `provisioned` (`expired`) | The notice: what is missing and how to finish | No link on the bus | `sudo omamobile-install-link reopen` and a restart; or `tools/phone-provision` over SSH; or install again (§2.8) |
| Any | The installer or the computer is gone for good | First start: the code. Later: the session and the notice | | Before the answers: flash again, or pair from another computer by the code. After first boot: the phone works without Google's files (no Wi-Fi, sound, cameras or modem) and the link ends itself (§2.2) |

## 9. Privacy

| Crosses the link | Direction | Then |
| --- | --- | --- |
| The code | computer to phone | Compared, forgotten |
| The code, after first boot | daemon to the owner's session, over a local socket only that account can open | Shown in the window; never in a notification's text, a file or a log |
| The token | phone to computer, and back at `resume` | Computer: memory and the work directory. Phone: its SHA-256, deleted when the link ends |
| The two nonces | one each way, in `hello` | Random, used for one session, hashed into the serial proof |
| The serial proof (a digest) | phone to computer | Compared in memory. The serial itself does not cross |
| User name, password hash, host name, time zone, Wi-Fi name and passphrase, SSH public keys, name, email | computer to phone | `firstboot.conf`, mode 600, deleted by first boot; the Wi-Fi lines are removed from it as soon as NetworkManager's root-only file exists **[V]** |
| The radio partitions (the IMEI, serial numbers, calibration) | phone to computer | A directory the owner chose, mode 700. Nowhere else: not uploaded, not cached, not in the browser's storage |
| Google's factory image | computer to phone | One file, deleted after provisioning |
| Status and progress | phone to computer | Shown |
| The smoke report | phone to computer | Shown; saved only when the owner asks. It names no serial, MAC, IMEI, SSID, Bluetooth address, account or bootconfig value **[V]** (`tools/phone-smoke`) |

Never crosses: the board id, the phone's serial, any address, any file of
the user's, any log.

Never logged, on either side, at any level: the code, the token, the
password hash, the Wi-Fi name and passphrase, the SSH keys' comments, the
partition digests, payload bytes. The daemon's journal lines name a
message's type, its length and the stage. The installer's report (for an
issue) holds the stage reached, the error codes, the release, the kernel
and the smoke report, and nothing from the backup or the answers.

## 10. Compatibility

- **Phones installed before the link.** No marker, so no unit starts and
  nothing changes. A package update that brings `omamobile-install-link`
  to such a phone installs files that never run.
- **Development phones.** `tools/install-phone` keeps writing
  `firstboot.conf` and the SSH key into its image copy; such a phone never
  offers the link (§2.2). `tools/nv-backup` and `tools/phone-provision`
  over USB SSH keep working unchanged and remain the way to provision a
  development phone or to repair one. In the link's release composition
  there is no `usb0` during the first start, by design; from the next boot
  the network function is back.
- **A phone whose link ended unfinished** (`expired`, §2.2) is, to
  everything else, a phone installed before the link: no marker, no unit,
  the gadget as the initramfs makes it. `tools/nv-backup` and
  `tools/phone-provision --first-install` finish it over USB SSH, and
  `omamobile-install-link reopen` offers the link for one more boot.
- **A development phone that wants the link** (testing it) places the
  marker by hand in an approved runbook step (§11).
- **Other devices.** A device is offered the link when its descriptor says
  `INSTALL_LINK=yes`, and it may say so only when: its kernel has
  FunctionFS and a UDC in the root; a replug comes back in the root (its
  Type-C driver, or its USB switch rescue); it names `NV_PARTS` (or states
  that it has no radio step); `PROVISION_STEPS` lists the steps its
  extraction tools support (`-d <codename>` exists for cheetah, panther,
  raven, tegu and, for Wi-Fi only, husky **[V]**); one planned restart is
  safe for it; and this plan's runbook has passed on it. The Pixel 9a does
  not qualify today: with slot B unmarked every boot spends one of three
  bootloader tries (AGENTS §4), and the link's restart is a boot. A phone
  without `INSTALL_LINK=yes` is installed with `tools/install-phone`.

## 11. Staged plan and runbook

Order and dependencies only. Offline stages first; each ends with tests
that run without a phone. The phone runbook follows; the human runs or
approves every step, and results are recorded here with the date and
`uname -r`.

### 11.1 Offline

| Stage | What | Tests, no phone | Needs |
| --- | --- | --- | --- |
| L1 | The protocol crate: frames, messages, limits, and both sides as state machines with no I/O. **Built** (derekross/omamobile-installer#4, a draft): in memory only, for the host, the web page's target and the desktop targets; not yet for the phone's | Golden frames; a loopback that drops, repeats, swaps and damages frames and cuts the link; every frame error; every message out of turn in every state; random walks of both machines | §16's changes, then the first tag |
| L2 | `omamobile-linkd` (the daemon around the crate's phone machine) against a socket pair in place of the endpoint files, and a scratch root (as `OMAMOBILE_FIRSTBOOT_ROOT` and `NV_PHONE_ROOT` do today **[V]**); `omamobile-firstboot --check --porcelain`; the session agent and `omamobile-install-link status\|reopen`; the golden frames in this repository. The list below | The whole flow against stand-in partitions that are regular files; the read-only preconditions each refused; a pulled "cable" before every frame; the tests of §11.3 marked L2 | L1 tagged |
| L3 | The daemon on real FunctionFS over `dummy_hcd`, on a laptop or VM kernel that has it (the phone's kernel does not: `CONFIG_USB_DUMMY_HCD` is not set **[V]**); `omamobile-link-gadget` against a fake configfs tree and against `dummy_hcd` | The descriptors as a host reads them; one frame per read; the pad rule at 64, 512 and 1024; unbind and bind; the OS descriptor requests; the hang marker; `SUSPEND` and `RESUME` changing nothing; the tests of §11.3 marked L3, `flow` first | L2 |
| L4 | `omamobile-provision`: the tools packaged for aarch64, the whole-or-untouched install of §6.3, the result file, the optional step's one retry | The byte-for-byte comparison of §6.2 in the aarch64 container against the laptop's run, for each factory build the index lists; the existing `tests/extract-*` against the packaged copies; a kill of the worker between any two installs leaves every tree whole or untouched; §11.3's F5 | The maintainer's own factory images, never committed |
| L5 | The root image with both packages and the marker; `manifest.json`'s `install_link`. **Built 2026-11-13** (#743, a draft; §19): the package `omamobile-install-link` 0.1.0 (the daemon at a pinned commit of the installer's `linkd-ffs`, with one patch; the gadget script; the units, the login-screen hold, the session agent, `status`/`reopen`, tmpfiles); `tools/build-rootfs --install-link`; `install_link` in `manifest.json`. Untested on a phone; the first-start screen program and the golden frames are not in it | `tests/rootfs-smoke` (on small made-up images: `tests/rootfs-smoke-link`), `tests/build-rootfs`, `tests/make-bundle`; the package's `test/all`: the units' conditions evaluated by systemd on scratch roots, `systemd-analyze verify`, the real daemon on scratch roots with the marker and none, with the image's placeholder and a filled `firstboot.conf`, with `done` for each reason, with an existing account; the agent's unit conditioned on the marker or an end; the agent against a stand-in daemon and the real one; the gadget script on the installer's fake configfs | L2 to L4 |
| L6 | The installer: the `Link` transport (one frame per read, a read always pending, 30 s per write), the states, the pretend phone that speaks §5; the nonce; the backup's files before `backup-commit`; `hello` again every 5 s while `pair` is `ask` | The write path's tests extended through `ready`; an interrupted run at every state, rerun with no "replug"; a lost token at every state; app protocol 2 against the stand-in | L1 tagged |

**What L2 builds**, from what L1 found it would need:

1. **The crate's tag.** The crate is at the workspace's 0.0.1 with no tag.
   L2 starts when §16's changes are in the crate and the installer's
   repository has tagged it (`omamobile-link-1.0.0`: the first tag fixes
   protocol 1). `omamobile-install-link`'s `Cargo.lock` pins the tag and
   its commit.
2. **The crate for the phone's target.** L1 did not check
   `aarch64-unknown-linux-gnu`: its standard library was not on the machine
   it was written on. Two checks, both before the tag: the installer's CI
   runs `cargo check -p omamobile-link --target aarch64-unknown-linux-gnu`
   beside its check for the web page; and `tools/build-packages` builds the
   daemon in the aarch64 container, where the package's `test/all` runs the
   crate's golden, turn and flow tests natively. The crate uses no
   operating-system interface, so nothing is expected to differ **[I]**.
3. **The golden frames here.** `tools/pr-check` refuses `.bin` files and
   any binary file **[V]**, so the copy in this repository is text:
   `tools/link-golden TAG` copies the crate's `link/golden/` at that tag
   into `packages/omamobile-install-link/golden/`, each `NAME.bin` as
   `NAME.hex` (lower-case hex, 32 bytes a line) beside its unchanged
   `NAME.txt`, and writes `GOLDEN` (the tag, its commit, and the SHA-256 of
   each frame's bytes). The package's `test/all` fails if a file is
   missing or extra; turns every `.hex` back into bytes and compares them
   with `GOLDEN` and, byte for byte, with the `.bin` in the pinned crate's
   own source; and decodes each with the pinned crate as the message its
   name says and encodes it again to the same bytes. A golden file that
   changes under the same protocol number fails here.
4. **`omamobile-firstboot --check --porcelain FILE`.** One
   `KEY<TAB>reason` line per objection, all of them, in §5.5's words, under
   `firstboot.conf`'s key names; no value echoed; exit 0 for none, 1 for
   objections, 2 for a file that is not `firstboot.conf` at all (a line
   that is not `KEY=value`, an unknown key, a key twice: the daemon's own
   fault, answered `internal`). Plain `--check` is unchanged. The crate's
   204 cases of these rules run against the script in `test/all`
   (`OMAMOBILE_FIRSTBOOT_BIN`), so the crate's copy and the script cannot
   drift apart unnoticed.
5. **The start-up rules of §6.5**, which are not in the crate: its
   `Phone::start` takes the state file and nothing else. The daemon applies
   the three tables first and hands the machine the result.
6. **What the crate leaves to the daemon:** `boot-update.conf` inside the
   step that places the answers (Q3; the crate has no effect of its own
   for it); the working space `factory-begin` checks (§6.4's number, set by
   R1); the I/O rules of §5.7; the sleep inhibitor; FunctionFS's events
   (`ENABLE` is the link up, `DISABLE` and `UNBIND` the link down,
   `SUSPEND` and `RESUME` nothing); the screen's sentences and the
   journal's lines, which name a message's type and length and nothing
   else (§9).
7. **A test transport that keeps frame boundaries.** A socket pair of
   type `SOCK_SEQPACKET` **[D]** (socket(2)): one frame per read, as bulk
   transfers give. It does not block as USB does, which is why §5.7 is
   proved in L3 and not here.
8. **The session agent** and `omamobile-install-link status|reopen`
   (§2.8), tested against a stand-in notification service and a scratch
   root.

### 11.2 On the reference phone

Before any step: the phone on the charger; `tools/nv-backup --check DIR`
against the newest backup says SAME for every `NV_PARTS` partition;
`tools/phone-smoke` passes its required rows. R2 to R6 run on the
development phone as it is, with SSH as the safety net. Every step that
draws on the screen, stops the display manager or shows a notice is
announced first.

| Step | What | Expect / Pass | Stop | Rollback | Risk | Writes |
| --- | --- | --- | --- | --- | --- | --- |
| R0 | Read only: `zcat /proc/config.gz` for `CONFIG_USB_CONFIGFS_F_FS`; `ls` the gadget's `functions` and `configs/c.1`; `cat` its `UDC` and the UDC's `current_speed`; count (not print) the `androidboot.serialno` lines in `/proc/bootconfig`; `df` the root; `ls /dev/fb0` | `=y`; `ncm.usb0`, `acm.GS0`; one UDC; a speed; count 1; more than 40 GiB free; `fb0` exists | Any differs: the design's **[I]** for it is wrong; stop and revise | None needed | None | Nothing |
| R1 | Install `omamobile-provision` (`tools/phone-install-package`). Copy one factory image to a scratch directory over SSH; run the extraction into a scratch output, installing nothing; compare with the laptop's output | Every file's SHA-256, mode and link target equal; time and peak disk use recorded | Any difference; an error line from UFS in `dmesg` | Remove the scratch directories; `pacman -R` the package | Low | Files on the root (`userdata`) |
| R2 | Install `omamobile-install-link`. Ask the human; arm `systemd-run --unit=x-deadman --on-active=90 systemctl reboot` (the next boot's initramfs restores the gadget); run `omamobile-link-gadget add` with the daemon limited to `hello`, `ping` and `status`; from the laptop read `status`; confirm with `tools/phone-ssh --fresh`; stop the timer | The host lists NCM, ACM and the link interface with §4's values; `status` gives the release and the kernel; SSH answers on a fresh login; `dmesg` has no new error | No fresh SSH within 90 s: the dead-man restarts the phone. Wait 2 minutes, replug once, then ask for a forced restart | `omamobile-link-gadget remove`, or a restart | Medium: it unbinds the only link | Nothing persistent but the package |
| R3 | A boot with the link added by the unit (the marker and a state file at `firstboot-done` placed by hand, the daemon still limited as in R2; §19, K15). One change: the unit at boot | The link is there after the boot with no hand step; SSH answers; the hang marker is gone | The phone is not on the bus 3 minutes after the boot: forced restart; the marker then skips the change, and SSH is back | Delete the marker file over SSH | Medium | The marker |
| R4 | Pull the cable for 10 s and replug, the daemon logging to a file. Then, cable in: stop the laptop's reader for 40 s while the daemon has a `status` answer queued | Within 10 s of the replug: SSH and `hello` both answer; the daemon logged `DISABLE` then `ENABLE`. The queued write is cancelled after 30 s, the session ends, the next `hello` is answered, and `dmesg` has no new line from the USB controller | Not back in 60 s: wait 2 minutes, replug once, then a forced restart | A restart | Low | Nothing |
| R5 | The screen. Announce it. Stop the display manager, run `omamobile-install-screen` with a test code for 30 s, press each volume key once, start the display manager | The code is readable on the panel; each key press is logged as an act at the phone, and no other key is; the session comes back | Nothing drawn: the **[I]** in §3.3 is wrong; switch to the fallback and repeat. No key event: the lock of twenty then ends only at a restart; say so on the screen and revise §2.5 | `systemctl start sddm`, or a restart | Low; the screen goes away for a minute | Nothing |
| R5b | The session's notice and window. Announce it: a notification appears. With the marker and a state file at `firstboot-done` placed by hand, start the agent in the session. Lock the phone and try to act on the notice; unlock, tap it, read the test code, close the window | Locked: the notice cannot be acted on and no code is visible anywhere on the screen. Unlocked: the window shows the code and closes; the journal holds no code | A code visible on the lock screen, or a notice that acts while locked: the **[I]** in §2.8 is wrong; the window must ask the lock's state itself before it shows anything. Revise before R7 | Stop the agent; delete the marker and the state directory | Low; a notification and a small window | The state directory |
| R6 | The full daemon on the development phone, the code read from `screen-text` over SSH (never from the journal, §9; §19, K10): pair, `backup-list` through `backup-commit` into a new directory; then `factory-begin` through `factory-end` with one cable pull in the middle and one kill of the laptop's tool with the cable left in; no `answers`, no `provision` | The link's backup has the same `NV_PARTS` digests as the newest `tools/nv-backup` backup; `tools/nv-backup --check` on it says SAME; every partition still reads `ro` 1; the image's digest is right after both resumes; the rerun paired with no replug and no wrong count; the rate is recorded | Any `NV_PARTS` digest differs; any partition reads `ro` 0; `ufshcd_err_handler` in `dmesg` | Delete the phone's state directory and the new backup directory; remove the marker | Medium: it reads the radio partitions | The state directory and the image file on the root |
| R7 | **A full install with the link beside NCM and ACM.** A fresh `tools/nv-backup` into a new directory first, and a known-good bundle at hand. Flash a release whose image has the marker, unmodified (Q2 says with which tool); then the command-line installer through the link to `ready` | The code appears; every state passes; the installed trees equal R1's; after the restart the smoke report's required rows pass and Wi-Fi, sound and cameras show as evidence; the link is gone at the boot after `finish`; `tools/nv-backup --check` says SAME | Any stop in §8's table that a rerun does not clear; any radio partition DIFFERENT | Fastboot by the buttons, then `tools/install-phone` with the known-good bundle | **High. Writes slot B and `userdata`: the maintainer's go** | Slot B's five images, `userdata` |
| R8 | **The same with the link alone** (the release composition). One change from R7 | As R7; the computer shows no new network adapter | As R7. With no SSH, a silent phone is a forced restart, then fastboot | As R7 | **High. Writes slot B and `userdata`: the maintainer's go** | As R7 |
| R9 | Drills on R8's phone before its `finish`, and on one more install: twenty wrong codes, then a volume key; the installer `resume`s while `pair` is locked; a wrong image digest; the laptop asleep for 3 minutes during the image; the cable pulled in each row of §2.6; the installer killed and run again at each state with the cable untouched; the token deleted from the work directory after first boot (pair again through the session); a forced restart during first-boot setup; no computer for 10 minutes in a boot, then in three more | Each ends as §2.5, §2.6 and §8 say. With no computer: the link closes for the boot, the notice counts the restarts down, and the phone ends the link itself, as `finished` when provisioned and as `expired` when not, with the notice of §2.8 | Any state the tables do not name; a wrong count other than for a wrong code | Reinstall as R7 | High for the reinstall, with the maintainer's go; low otherwise | As R7 for the reinstall |
| R10 | Absence. On a phone installed with `tools/install-phone` from the same release, on R8's phone after `finish`, and on R9's phone after `expired`. Then on that last one, with the human's go for the restart: `omamobile-install-link reopen` | No link interface on the bus, the unit's condition failed, no marker. After `reopen` and a restart: the link for one boot, closed after 10 unpaired minutes, and absent again at the boot after | The link is offered where it should not be, or a second boot after one `reopen` | Remove the package; fix before any release | Low | The marker, for one boot |

A release may carry the marker only after R8 to R10 have passed with that
release's packages.

### 11.3 The seven flaws: each fix, and the test that proves it

| | The case it closes | The fix | Proved by |
| --- | --- | --- | --- |
| F1 | An installer killed during the backup and run again met a phone expecting frame 41: errors until pairing locked, and only a replug helped | A `hello` is always frame 0 and starts the numbering again (§5.3) | L2 `rerun`: at each of the host's states its machine is replaced by a new one with the link left up; it pairs within its first three frames, with no error and no wrong count. L3: the same with the host process killed and no unbind, 50 times. R6 and R9 with the cable untouched |
| F2 | The first run's `hello` answer, left in the IN endpoint, was read by the second run: the serial proof failed for the right phone | The host's nonce, echoed; the host discards everything until it reads its own (§5.3) | L2 `stale`: the transport holds the last session's `hello` answer with the same `id`, and three later frames, before the new `hello` is answered: four frames discarded, the proof equal. L3: the host killed between writing `hello` and reading, 50 times |
| F3 | A page reloaded after first boot could never pair again, and the phone offered the link at every boot for good | A code in the unlocked session on the owner's tap (§2.8); a budget for every stage with an account, and an end (§2.2); `restart` once (§2.7) | L2 `pair-again`: the token dropped at each stage from `firstboot` on; `ask`, `show`, the code, a new token, the old one `bad-token`. L2 `budget`: by the clock, 10 unpaired minutes close a boot, never while a job runs; the fourth setup boot ends as `expired` or `finished` before any gadget change; `reopen` gives one boot. L2 `rights`: every host message at every stage and both values of `boot` against §2.7. R5b, R9, R10 |
| F4 | A paused transfer and a damaged download spent wrong tries; any host could spend twenty in four minutes and lock the owner's installer out until a restart | Only wrong codes count; no lock on `resume`; a late data frame is `not-allowed`; the lock of twenty ends at an act at the phone (§2.5, §5.1) | L2 `count`: 100 frame errors, 100 wrong tokens, 3 mismatched images and a data frame after 121 s leave the count at 0 and the right code pairs; twenty wrong codes give 30, 60 and 120 s and then the lock; `resume` with the token pairs under each lock; an act clears it. R9 |
| F5 | "`provision` again" for the camera step, at a stage where no image exists or may be sent | A camera-only failure is a success with a note; the worker's own one retry; the image is not kept (§6.6) | L4: the camera step made to fail once (the run ends all `ok`) and twice (`provision-done` with `camera` `failed`, stage `provisioned`, the image gone, `optional_failed` in `status`). L2: `provision` at `provisioned` is `not-allowed`. L6: the line "Cameras: not set up" in a run that never saw the event |
| F6 | The phone waiting in its write of `ack`, the host in its next write, for good at 64 MiB; the same for `abort` | Both sides read while they write; a window; a bounded queue; 30 s per write (§5.7) | L3 `flow`, on FunctionFS over `dummy_hcd`: (a) a host that writes the whole image and never reads: the daemon ends the session within 30 s of its queue filling, the file is at its last acknowledged offset, and the next `hello` is answered with no unbind; (b) a host that keeps to the window and reads each `ack` 5 s late finishes the transfer; (c) `abort` in the middle of a partition with the host's reader stopped for 5 s gets `aborted`; (d) the host killed in each stream and run again resumes. R4's second half on the phone's own controller |
| F7 | Power lost between placing `firstboot.conf` and recording the stage: an account, no backup, no firmware, no link | The state file from the first start; the write order; the start-up tables (§6.5) | L2 `rows`: every row of §6.5's three tables as a scratch root, and what the daemon does to it. L2 `kill`: through a whole install, the daemon is killed after each single effect of each list the machine returns, and started again; the flow reaches `finished` every time and never `done` early. R9's forced restart during first-boot setup |

## 12. Decisions

**Decided by the maintainer on 2026-11-12: every recommendation below is accepted, Q1 to Q12.** The right-hand column is therefore what the design does. Three of them change a rule written elsewhere, and that text changes in the same pull request as the code that needs it, not before: Q3 (AGENTS §1 and CONTRIBUTING §3.1 name `tools/install-phone` as the only writer of `AUTO_WRITE=yes`), Q2 (`tools/install-phone` gains `--install-link`) and Q6 (the release composition, only after R7).

| | Question | Decided |
| --- | --- | --- |
| Q1 | The link runs in the root's first start, not the initramfs (§3). INSTALL-EXPERIENCE-PLAN §5.3 pictured the initramfs's gadget | Accept. No boot image changes for M2; setup mode gets the same binary later (§3.4) |
| Q2 | R7 needs a way to flash a release unmodified. The Rust installer's write path has never run on a phone, and the Pixel 7 Pro stops in it at the bootloader-slot rule | `tools/install-phone --install-link`: today's checks and writes, minus `firstboot.conf`, the key and the image copy. Then the link is the only new thing in R7, and the Rust write path gets its own first run |
| Q3 | `boot-update.conf`. AGENTS §1 and CONTRIBUTING §3.1 say only `tools/install-phone` writes `AUTO_WRITE=yes`. A phone installed through the link has no such file, so its kernel updates would never reach slot B | The daemon writes it at `answers-ok`, with the descriptor's `BOOT_UPDATE_AUTO_WRITE` (default `yes`), a value no message can set. It needs the two rule texts amended to name the install link beside `install-phone` |
| Q4 | Encrypt the link with a key agreed from the code (a password-authenticated exchange) | Not in protocol 1. It protects only against a device in the cable (§2.5). Revisit with secure mode, where the link carries the root image |
| Q5 | The phone checks the factory image against its own signed copy of the build index, not only the digest the host sends | Yes, once D6 of INSTALL-EXPERIENCE-PLAN puts the index in a package: the root image then carries it, and a paired host can't choose the file. Until then the host's digest |
| Q6 | The release composition drops NCM and ACM during the first start (§3.3) | Yes, after R7 has passed with them |
| Q7 | USB identity: keep `1d6b:0104` and match on the interface, or get a vendor and product ID of our own; and whether to advertise a WebUSB landing page | Keep it and match on the interface. No landing page in the first version |
| Q8 | Where the protocol crate lives | In the installer's repository, as its own crate with no dependency on the core; this repository's package pins a tag. The golden frames are in both |
| Q9 | Secure mode: the PIN is chosen on the phone, so `answers` there has no `password_hash` | Leave to SECURITY-PLAN S3; protocol 1 requires the field, the setup-mode message set makes it optional |
| Q10 | The screen: a framebuffer program, or Plymouth's message line | The framebuffer program if R5 passes; it is the PIN pad's code later |
| Q11 | Whether the link may finish itself without a smoke report (§2.2) | Yes: 10 minutes in each of three boots |
| Q12 | The token in the web page: memory only, or the tab's session storage | Memory only. A reload costs the report, not the install |

Existing documents that no longer match the decisions above, to be brought
in step when this lands: INSTALL-EXPERIENCE-PLAN §1 step 6, §6.3, §9 and
D2 still describe the owner's own download (the 2026-11-09 fallback);
RELEASES §5.2, §6 and §12.7 describe an installer that extracts on the
computer and writes the key and the answers into copies of the images;
SECURITY-PLAN §5.4 streams over the USB network.

## 13. Decisions from building L1

**Decided by the maintainer on 2026-11-12: all four recommendations below
are accepted, N1 to N4.** Section 12 stands as decided. Building stage L1
raised four points that were the maintainer's to decide; the document
above is written with each recommendation in place, and says where. Everything else this
revision changed is a design choice made here and written down in its
place (§15 and §11.3 list them).

1. **N1. How an owner pairs again after first boot (§2.8).** Recommended:
   a new code in a window of the owner's unlocked session, opened by the
   owner's tap on a notice; the native installers go on keeping the token
   in their work directory, and the page keeps it in memory only, as Q12
   decided. Reason: it is the one way that needs nothing more stored on the
   computer, works for the page after a reload, and asks more of the person
   than the first pairing did (the unlock), on a phone that now has data.
   The lock screen would show a code to anyone who can see the phone;
   refusing would leave an owner with a phone only a checkout of this
   repository can finish.
2. **N2. When the link ends for good (§2.2).** Recommended: no limit while
   no account exists; from then on at most three setup boots, in each of
   which the link closes after 10 minutes without a paired host; after the
   third it ends itself, as `finished` at `provisioned` and as `expired`
   before. Reason: the same two numbers Q11 accepted for the last stage,
   now for every stage with an account, counted in boots and monotonic
   minutes because a new phone's clock cannot be trusted. Three boots
   cover the planned restart, one retry of first-boot setup and one mishap.
3. **N3. `omamobile-install-link reopen` (§2.8).** Recommended: yes. After
   `expired`, root on the phone may grant one more setup boot. Reason:
   without it an owner whose computer failed halfway can only reinstall or
   use the development tools. It is the maintainer's because it brings the
   link back on a phone in use; it cannot be done from the cable, needs the
   owner's password on the phone, lasts one boot under the same ten-minute
   rule, and still needs the code from the unlocked session.
4. **N4. Protocol 1 changes in place.** This revision changes the wire
   (the nonce in `hello`, `ask`, two fields in `factory-ready`, two in
   `status`, the serial proof's input), so the crate's golden frames are
   written anew. Recommended: keep the number 1 and fix it at the crate's
   first tag. Reason: no tag, release or phone has ever spoken it; a number
   2 now would oblige every later reader to know a protocol 1 that never
   left a draft pull request. From the tag on, a change to the wire is a
   new number.

## 14. Safety rules this design touches

Checked against AGENTS §1, rule by rule, again after this revision.

| Rule | How this design keeps it |
| --- | --- |
| Ask the human before every reboot, flash or irreversible write | Every runbook step is the human's; R7 to R9 name the maintainer's go, and R10's restart the human's. On an owner's phone the one restart is asked for by the installer the owner is driving, and the link takes `restart` once only (§2.7). The daemon restarts the phone for no other reason, and `reopen` waits for a restart the owner makes |
| Announce anything that affects the screen | R5, R5b and every install-mode boot draw on the screen or show a notice: announced in the runbook. On an owner's phone the notice is one notification in the session. No haptics, torch, brightness or display-mode change anywhere |
| Only slot B and `userdata` | The link writes files on the root file system. It opens no partition for writing and cannot (§2.4). The flash stays fastboot's, through the tools that have the rule. `boot-update.conf` is Q3's, with the rule texts it amends |
| Linux never writes the modem's NV partitions | Read-only opens, after the `ro` 1 and not-mounted checks, twice per backup. `modem-nv.sha256` is written only after the computer confirmed its copy, and is the worker's last write. The NV overlay is not touched |
| Never weaken the storage guard | No `blockdev`, no `/dev/sda`, no change to `UFS_RW`. `initramfs/init` is unchanged. A partition that is not read-only stops the backup with no workaround |
| Check backups before radio work | The runbook starts with `nv-backup --check`; R7 takes a fresh backup first. On an owner's phone the link's own backup precedes the modem's first start, and is whole on the computer before the phone records it (§5.5) |
| No PMU registers, `devmem`, or reads of unpowered blocks | None. The daemon reads sysfs, procfs, bootconfig and block devices; the screen program reads two keys' input events |
| Read-only first, one change per boot | R0 reads; R1 to R6 add one thing each; R7 and R8 differ by one thing. No device-tree node, overlay or module is added. The gadget changes once per boot, at its start, under the hang marker; `reopen` changes nothing until the next boot |
| A safety net before every risky step | R2's dead-man timer and fresh SSH login; the gadget script's hang marker and `EXIT` trap; SSH kept beside the link until R8. A write the bus does not take ends the session after 30 s and never holds the daemon (§5.7) |
| A stuck reboot | `restart` is `systemctl reboot`, so the reboot watchdog applies and the modem's unit stops cleanly; the runbook's stop conditions say wait, replug once, then ask |
| Fingerprint, AoC and modem services | Provisioning starts, stops and restarts no service; each starts once, by its own unit, at the next boot. A power cut during provisioning leaves every installed tree whole or untouched, so no such service ever starts on half a tree (§6.3) |
| Suspend | The daemon's sleep inhibitor is held only while the link is open. Nothing in this design asks the phone to suspend, and no test here sleeps it |
| Never commit or paste identifying data or vendor blobs | The backup stays on the owner's computer; the board id and serial never cross; logs, reports, `done` and the state file carry none of §9's list; L4's factory images are never committed; the golden frames here are text and hold made-up values. This document holds no address, serial, IMEI or network name |
| Citable sources; no other projects named | Upstream Linux's documentation and source, the USB specification, the manual pages named, and this repository's files |

## 15. What building L1 changed in this plan

The crate's `docs/LINK.md` §6 lists twenty-six points where the crate
differs from the plan as it was, or chose where the plan was silent. For
each, what the plan now says. "Adopted" means the plan's text is now what
the crate does.

| | The point | Now | Where |
| --- | --- | --- | --- |
| D1 | Unknown keys refused, except in `hello` and the `version` error | Adopted | §5.2 |
| D2 | A `hello` is always frame 0 and restarts the numbering | Adopted; it is F1's fix | §5.1, §5.3 |
| D3 | The phone echoes `id` without checking its order; the host starts each run at another number | Adopted as to the phone. The host's nonce (F2) does what the differing start only made likely, so the start no longer matters | §5.2, §5.3 |
| D4 | With no session open, a frame that is not a `hello` is dropped | Adopted | §5.1 |
| D5 | A malformed message is a protocol error that ends the session and counts a wrong try | Adopted, except the count, which F4 takes away for every protocol error | §5.1, §2.5 |
| D6 | The read buffer holds the larger of `max_data` and a message | Adopted | §5.1 |
| D7 | `max_data` at least 1024, required from the host; offsets in multiples of the session's | Adopted | §5.3, §5.5 |
| D8 | One frame has one encoding | Adopted | §5.1 |
| D9 | `wait_s` always present; `locked` with 0 | Adopted, with a fourth value of `pair`, `ask` (F3), and 0 now meaning "until someone acts at the phone or it restarts" (F4) | §5.3 |
| D10 | Tries counted per boot, never reset by a right code; every fifth locks and replaces the code; the twentieth locks until a restart; `pair` and `resume` both answered `locked` meanwhile | Adopted for the counting of wrong codes and the timed locks. F4 changes what counts and how the last lock ends. **One clause is sent back: `resume` under the lock** (§16) | §2.5 |
| D11 | The values of `status`'s states; every field always present | Adopted; `status` gains `link` and `provision.optional_failed` | §5.4 |
| D12 | One form of `progress`, five values of `what` | Adopted | §5.6 |
| D13 | First boot's rules win for `answers`; the link's own lengths are `problems`, not frame errors | Adopted | §5.5 |
| D14 | The reason words | Adopted; `--porcelain` prints them | §5.5, §11.1 |
| D15 | One stream and one step at a time | Adopted | §5.2, §5.6 |
| D16 | An `ack` at the last byte too; offsets at frame ends | Adopted | §5.6 |
| D17 | `factory-begin` for a verified file checks it again | Adopted | §5.6 |
| D18 | `firstboot-failed` answers `provision`; the host asks `status` for first boot's end | Adopted | §5.4, §5.6 |
| D19 | `provision` at `provisioned` is `not-allowed` | Adopted; F5's decision agrees | §5.6, §6.6 |
| D20 | The backup's listing and marks live for a boot, across sessions | Adopted | §5.5 |
| D21 | The fields of each error code; when an `error` has no `re` | Adopted | §5.2 |
| D22 | `progress` after 5 s of nothing sent; the host counts silence only while waiting | Adopted | §5.3 |
| D23 | The ten minutes run from the session being up, in a boot that began at `provisioned`; `boot` is 2 from the first such boot; the end waits for a step that owes an answer; no limit in the boot provisioning ended in | Adopted, except the last clause: F3's budget gives every boot with an account the ten-minute rule | §2.2, §5.4 |
| D24 | A right code always makes a new token; `resume` with no token is `not-allowed` | Adopted | §2.5 |
| D25 | The limits of every string and list | Adopted | §5.2 |
| D26 | `smoke-report` carries any JSON value | Adopted | §5.6 |

Twenty-five are adopted, four of them (D3, D5, D9, D23) with a change one
of the flaws' fixes makes on top. One, D10, is adopted except for a clause
that goes back to the crate.

What this revision found that neither the plan nor `docs/LINK.md` had:

| Found | Where it is now |
| --- | --- |
| The candidate is on a tmpfs, so it cannot be renamed into `/etc` | §6.5: copied, synced, renamed |
| `omamobile-firstboot` deletes `firstboot.conf` before it writes its `done`; a crash between leaves an account and neither file | §6.5, second table, third row |
| `omamobile-firstboot --check` stops at its first objection; `--porcelain` must report all | §3.3, §11.1 |
| `tools/pr-check` refuses `.bin` files, so the golden frames cannot be copied here as they are | §11.1: as hex text, compared byte for byte |
| The crate's host writes the backup's `SHA256SUMS` after `backup-done`; killed between, the phone says done and the computer's directory is not a backup `nv-backup --check` can read | §5.5, §7.1, §16 |
| `push_tree` removes a tree's entries and then moves the new ones in; at an owner's first boot a power cut there leaves half a tree for services that start by themselves | §6.3: whole or untouched |
| `restart` was taken at `provisioned` in every boot | §2.7: once |
| A lock set off by wrong codes also kept out a host holding the token | §2.5: `resume` is never locked |
| Wrong tokens were counted, though a token cannot be guessed | §2.5 |
| Nothing kept the phone from suspending during a transfer or provisioning | §3.3: a sleep inhibitor |
| First boot reruns by itself at every boot while `firstboot.conf` exists, so a recorded `firstboot-failed` can be out of date at any start | §6.5, second table |
| The rules for `answers` exist twice, in the script and in the crate | §5.5: the script's verdict counts; §11.1: tested against each other in this repository |
| An installer that lost `provision-done` could not learn that the camera step failed | §5.4: `provision.optional_failed` |
| The contents' link to §12 pointed at a heading that does not exist | Fixed |

## 16. For the crate to change

The crate is a draft, and protocol 1 is not fixed until its first tag
(N4). Before that tag:

**Sent back: where the crate chose and the plan keeps another rule.**

| | The crate | The plan's rule | Why |
| --- | --- | --- | --- |
| D10, one clause | While `pair` is locked, `resume` is answered `locked` too | `resume` is never locked (§2.5) | The lock protects a six-digit code from guessing. A token is 256 random bits and needs no such protection. With `resume` locked, a host that cannot see the screen can keep the owner's installer, which holds the right token, out for the length of every lock, and after the twentieth wrong code for good. That is the lock-out F4 is about |

**What the fixes of F1 to F7 need in the crate.** These are not choices
the crate made wrongly: it implemented the plan as it was.

| For | Change |
| --- | --- |
| F2 | The host's `hello` carries `nonce`; the phone's `hello` and the `version` error carry `host_nonce`; the host machine takes randomness as the phone's does, and discards every frame until its own nonce comes back; the serial proof takes both nonces. `first_id` can go |
| F3 | `pair` gains `ask`. The limit of three boots counts boots that start at `firstboot` or later, and the ten minutes run in every boot with an account, from the latest of the session being up, the last paired session's end and a job's end, and not while a job runs. The end has two forms, `finished` and `expired`, as different effects; the state file's boot count is renamed for what it now counts. `restart` is `not-allowed` at `boot` 2. `status` gains `link`. The host says `hello` again every 5 s while `pair` is `ask`, or `locked` with no token |
| F4 | Only a wrong code is counted. A frame error, a malformed message, a wrong token and `factory-mismatch` are not. A data frame with no open stream is dropped, answered `not-allowed` once, and keeps the session. The twentieth wrong code locks until a new input, "an act at the phone", which also sets the count to 0 |
| F5 | `status.provision` gains `optional_failed`, kept in the state file. Nothing else: `provision` at `provisioned` is already `not-allowed` |
| F6 | `factory-ready` carries `ack_every` and `window`; the host machine holds to the window and treats 60 s at its edge as a lost link. The 30 s per write and the pending read are the shells' (L2, L6) |
| F7 | Nothing in the machine: the order it already asks for (place the answers and start the unit, then record the stage, then answer) is §6.5's. The start-up tables are the daemon's |
| Found in this revision | The host writes the backup's last files (`BackupFinish`) before it sends `backup-commit`, not after `backup-done` |
| L2 | `cargo check --target aarch64-unknown-linux-gnu` in CI; the golden frames written anew; then the tag |

## 17. What bringing the crate to this plan found

The crate was brought to §16 on 2026-11-12 (installer repository,
`link/`, `docs/LINK.md`). Its tests kill the daemon before each output of
a whole install and replace the host at every frame; seven places in this
plan did not hold or said nothing. Each is corrected above.

| | What the plan said | What was wrong | Now |
| --- | --- | --- | --- |
| P1 | Nothing on how a start knows it is the first of a boot | With the mark outside the state file, a daemon killed between the mark and the state file's write started again with `boot` still 1: `restart` was taken a second time and the boot was not counted | §6.5: the boot id is in the state file, in one write |
| P2 | `backup-done` with no pending checksum file: the mark is taken away, at any stage | Provisioning uses that file (§6.3). After it, every start would clear the mark on a phone whose backup is complete, at a stage where none can be taken, and `status` would say `backup: none` | §6.5: the row applies before `provisioned` only |
| P3 | The 10 minutes run from the session being up | At `firstboot-failed` the display manager is held, so no session comes up and there is nowhere to show "paused": the phone would show "Setup stopped at" with no link | §2.2: the 10 minutes do not run in such a boot; the three boots end it |
| P4 | The socket's lines were `open`, `code`, `paired`, `closed`, `ended` | After the twentieth wrong code the owner could not be told why the window closed | §2.8: a `locked` line and its notice |
| P5 | The host asks again every 5 s at `ask` | At `token` with no token the installer would have stopped, when unlocking the phone is all it takes | §2.8: the same sentence and the same asking |
| P6 | `reopen` takes effect at the next boot | Nothing kept a daemon started in the same boot from offering the link at once, a gadget change in a running session | §2.8: `reopen` records its boot id; a start in that boot exits |
| P7 | `restart` is taken once | "Once" can only be once per run of the daemon in `boot` 1: a daemon killed between `restarting` and the reboot takes it again, and must, to finish the job | Said here; §2.7's rule is unchanged in what an owner sees: one restart |

P3 and P4 change what an owner sees; the maintainer accepted both on
2026-11-12. The crate has P3 as written here; until it has P4 it sends
`open` where the `locked` line will be.

**Left for the crate:** the `locked` line (P4). **Left for L2:** `reopen`'s
boot id (P6), and the daemon's own reading of the phone into what the
start-up tables take, which the crate's tests assume correct.

The crate's remaining differences from this plan, all places where the
plan is silent, are listed in its `docs/LINK.md` §6: the window's lower
bounds (a `window` below `ack_every` is refused), a non-forward `ack`
ending the session, a suspended stream begun again at most five times,
an empty result counting as `interrupted`, and the effect that tells the
daemon to drop a dead session's unsent frames.

## 18. What building the daemon found

The daemon (`linkd/` in the installer repository, `docs/LINKD.md`) was
built on the crate on 2026-11-12, against a socket pair in place of the
USB function. Its tests kill it at every point of a whole install and
remove its guards one at a time. Nine places in this plan did not hold or
said nothing. Each is corrected above. Nothing here has run on a phone.

| | What the plan said | What was wrong | Now |
| --- | --- | --- | --- |
| E1 | `finish`: the marker deleted, then `done` written; the unit starts on "the marker and not `done`" | A daemon killed between the two left no marker and no `done`: nothing would start it again, and the link had neither ended nor could be reopened | §6.5: every end writes `done` first and deletes the marker last, and a start that finds `done` completes the end. §3.3: the unit's condition is the marker alone |
| E2 | Placing the answers ends with the unit started | A daemon killed between copying `firstboot.conf` and starting the unit left an installer waiting for a first boot that nothing starts before the next restart | §6.5: a start that finds the stage, the file and the unit not run in this boot starts it |
| E3 | `remove` runs "when the daemon stops for any reason" | A killed daemon runs nothing: the next start called `add` on a gadget that already had the function, or left the function on the bus with nothing behind it | §3.3: a record on the tmpfs; a start that finds it puts the gadget back first |
| E4 | After ten unpaired minutes the link is closed "for this boot" | A boot is counted once, so a daemon started again in that boot offered the link again | §2.2: a mark on the tmpfs; a start that finds it offers nothing |
| E5 | `reopen` records the boot id it ran in | In the state file it made that boot counted, and the start-up rules then offered the link at once | §2.8: a file of its own, read before the start-up rules; `reopen` refuses when the boot id cannot be read |
| E6 | `firstboot.step` is the step's name as the script logs it; `status` names no user | The script logs the account step as "user NAME", and `status` is answered unpaired | §5.4: that step is `user` |
| E7 | A write the bus did not take ends the session | Frames the daemon queued before it heard of the lost write would have reached the host numbered after the cancelled ones | §5.7: they are cancelled too |
| E8 | "A result file" | Said nothing of one that cannot be read | §6.5: it counts as a run that was interrupted, never as a success |
| E9 | Nothing on a phone whose bootconfig has no serial | The serial proof (§2.5) would be of nothing | §2.5: nothing is offered and nothing written |

**Left for L3** (the daemon's `docs/LINKD.md` §5): everything about real
blocking and `io_cancel` on FunctionFS, one frame per read and the pad
rule, the function's events in place of the stand-in's, a daemon that
dies with the function bound, the gadget script and its hang marker, the
real `systemctl` and `systemd-run` answers, and sizes: nothing has yet
moved a megabyte frame or a 4 GB file.

## 19. What packaging the link found (L5)

The package `omamobile-install-link` 0.1.0 and the root image's side were
built on 2026-11-13 (branch `install-link-package`, a draft pull request),
offline: the package's `test/all` runs the real daemon on scratch roots,
systemd's own evaluation of the units' conditions and `systemd-analyze
verify`; `tests/build-rootfs`, `tests/rootfs-smoke-link` and
`tests/make-bundle` cover the image and the bundle. **Nothing here has run
on a phone, and no root image was built.** Fifteen places where the plan
said nothing, or did not hold as written:

| | The plan | The package | Why |
| --- | --- | --- | --- |
| K1 | §3.3: the link's unit "is ordered `Before=display-manager.service` and does not finish starting" while no account exists | A second unit, `omamobile-install-link-hold.service`: `Type=oneshot`, `After=` the link's, `Before=display-manager.service`, with the marker and no first-boot `done` as its conditions. It finishes when first boot has made the account, the link has ended or its marker is gone, or the daemon has not been running for 30 s | The daemon tells systemd nothing when it is ready (no `sd_notify`), so its own unit finishes starting at once and holds nothing. A daemon that cannot run never leaves a phone without a login screen |
| K2 | §3.3: `After=omamobile-usb-mac.service omamobile-boot-success.service` | Kept; the link's units are wanted by `graphical.target` (vendor wants links), never by `multi-user.target` | `omamobile-boot-success.service` is `After=multi-user.target`, and a target is ordered after what it wants: wanted by `multi-user.target`, the unit would be in an ordering cycle. On a phone with the marker the login screen therefore also waits for `multi-user.target` and the boot-success mark |
| K3 | §3.3: the sleep inhibitor "taken over D-Bus, no program is run", held while the link is open | The unit runs the daemon under `systemd-inhibit --what=sleep --mode=block`, for the daemon's life | The daemon has no D-Bus client (LINKD §2). Its life is the link's: it exits when the link closes for the boot or ends. The program is systemd's, run by the unit, not by the daemon |
| K4 | The 2026-11-13 decision: "no `firstboot.conf`" means no file or the image's unfilled placeholder | `patches/0001` on the daemon: a file holds answers when it has a line that is neither blank nor a comment; the start-up rules and "`boot-update.conf` is written if it is missing" use that | The daemon tested existence: on a link image whose placeholder nobody filled, the first start ended as `not-first-start` before offering anything, and the placeholder `boot-update.conf` left `AUTO_WRITE` off. Its test fails without the change. For the daemon to take over (below) |
| K5 | §6.5: the daemon starts `omamobile-firstboot.service` after placing the answers | A drop-in, `ExecCondition=has-answers /etc/omamobile/firstboot.conf`, skips first boot on a file of comments only | The unit's condition is the file's existence. On the placeholder it runs, does nothing (`omamobile-firstboot` 0.1.6) and stays active (`RemainAfterExit=yes`) for the boot: the daemon's later start would start nothing, and the daemon would take first boot for running until the next boot. The drop-in belongs in `omamobile-firstboot` with the placeholders; it moves there |
| K6 | §2.4: each unit's `ReadWritePaths=` lists exactly the files it writes | `ReadWritePaths=/etc/omamobile /var/lib/omamobile`, `ProtectSystem=strict`, `PrivateTmp=yes`, `DevicePolicy=closed`, `DeviceAllow=block-sd r` | A path that does not exist yet cannot be listed, and the files are created by the daemon (`firstboot.conf`, `boot-update.conf`) or its gadget script (the hang marker, `/var/lib/omamobile/link-gadget-started`). A narrower list needs the hang marker under the link's own state directory (the script's `LINK_MARKER` default): for the installer |
| K7 | §6.4: the state directory is mode 700 | 0711 (`StateDirectory=`, created only when the unit starts, so only with the marker; tmpfiles `z` keeps the mode where it exists) | The session's agent and `omamobile-install-link status` as the owner read `done` (0644) by its name. The state file, the token's hash and the image stay 0600, and the directory cannot be listed |
| K8 | §2.8: after `expired`, the notice "at each of the next three logins" | The agent's unit runs with the marker or `done`; after an end other than `finished` or `not-first-start` it shows the notice and counts the login in the user's state directory, keyed by `done`'s text, so a `reopen` and another end count again | An end deletes the marker, so an agent conditioned on the marker alone could never show it |
| K9 | §2.8: the code window "in Omarchy's own look" | A standalone Quickshell window in plain Qt Quick; the code in its environment only, never on a command line (world-readable in `/proc`) | A standalone Quickshell configuration cannot import the shell's `qs.Commons`. An `omamobile.*` shell plugin that the agent asks over IPC would follow the theme: open, before R5b |
| K10 | §3.3: `omamobile-install-screen` draws the code before the session exists; R6 reads the code "from the journal" | Not built. `screen-text`, a development stand-in run by hand over SSH, prints the screen socket's lines (the code among them) to its terminal, and Enter stands for a volume key | The code is never logged (§9), so the journal never has it. Without the screen program a phone at stage `waiting` shows no code: no owner's install can pair before it exists |
| K11 | §3.3: "`tools/build-rootfs`: a release image gets the two packages and the marker" | `omamobile-install-link` is in every image (inert without the marker); `omamobile-provision` goes in once `[omamobile]` has it; `--install-link` adds the marker and needs both packages, and only for a descriptor saying `INSTALL_LINK=yes`, or `INSTALL_LINK=test` for a development or local image. The MANIFEST says `install link: protocol N (marker ...)` or `none` | §10 makes `INSTALL_LINK=yes` the gate, and R7 needs an image with the marker before any device may say yes: `test` is that image, and it can never be a signed release (those follow stable). Setting either in cheetah's descriptor is the maintainer's step. `tests/rootfs-smoke` refuses a marker the MANIFEST does not name, and the reverse |
| K12 | §3.3: `tools/bundle-manifest` writes `install_link` | It does, from `--install-link-protocol`, which `tools/make-bundle` reads from the image's MANIFEST; the key is absent otherwise, and an unknown `install link:` line stops the bundle | The protocol is the daemon's crate's (`PROTOCOL`), recorded by the package in `/usr/share/omamobile/install-link/SOURCE` and by the image build in its MANIFEST |
| K13 | §11.1: the package's `Cargo.lock` pins the crate's tag | The installer's archive at a commit of `linkd-ffs`, pinned by its SHA-256 (`source.conf`), with the installer's own `Cargo.lock` | There is no tag yet. When there is, `source.conf` moves to it |
| K14 | §11.2, R2: "the daemon limited to `hello`, `ping` and `status`" | The daemon has no such mode. Unpaired it answers only `hello`, `status`, `pair`, `resume`, `ping` and `bye` (§2.4): R2 and R3 run it unpaired, and nobody types the code | A limit would be a second code path to test; the unpaired rules are already the narrow ones |
| K15 | §11.2, R2 and R3: the marker placed by hand on the development phone | The marker alone is not enough there: that phone has an account and no state file, so the daemon's first start ends the link as `not-first-start` (§6.5, row 3) and deletes the marker. R2 and R3 also place a state file at `firstboot-done` (mode 600; the crate's format, as the package's tests write it), which the daemon counts as setup boot 1 of 3; the link then closes after 10 unpaired minutes in each boot. R2 starts the unit by hand (`systemctl start`) and removes the marker before any restart, or R2 becomes R3 | The same rules that keep the link off every installed phone (§2.2) keep it off the development phone |

**N5: `no_disconnect=1` (§18, E12). Decided by the maintainer on 2026-11-14: off.** A daemon that
dies with its function bound takes the whole gadget off the bus. The mount
option `no_disconnect=1` keeps the gadget bound and deactivates the link's
function instead.

| | Without it (as built) | With it |
| --- | --- | --- |
| The host | Sees the device leave the bus at once; the installer finds the link again and sends `resume` | Sees nothing: its transfers stall until its 30 s write limit (§5.7), then it says `hello` again into a function that answers nothing until the daemon is back |
| NCM and ACM (development composition) | Gone with the link until `ExecStopPost=` or the next start runs `remove` (seconds): SSH drops and comes back | Stay up: SSH is not interrupted |
| The release composition (the link alone) | No difference to the owner: there is nothing else on the bus | No difference |
| Getting the link back | `remove`, then `add` at the next start (as tested in L3) | The same: the instance must be unmounted and mounted again either way; untested |

Recommended: keep it off. In the release composition it changes nothing for
the owner, the disconnect is the clearer signal to the installer, and it is
the case L3 has run; the development composition's few seconds without SSH
are covered by R2's dead-man timer. Turning it on is one mount option in the
gadget script (`LINK_FFS_OPTS`). **Decided 2026-11-14: off, as recommended.**

**N6: the link on the Pixel 7 Pro (§19, K11). Decided by the maintainer on
2026-11-14:** cheetah's descriptor gets `INSTALL_LINK=yes` once the link's
phone runs (R0 to R8) have passed on the reference phone; until then its
release images carry the package without the marker.

**For the daemon to change** (the installer's `linkd/`, then the patch and
the drop-in go): `patches/0001` (K4); the hang marker under the link's state
directory (K6); optionally `sd_notify` readiness, which would let the link's
unit hold the display manager itself and drop K1's second unit.

**What the first phone runs must check, beyond their rows.** R0: that
`systemd-inhibit`, `python3`, `notify-send`, `gdbus` and `qs` are on the
phone; that first boot's `user` file names the development phone's account
(K15); `systemctl cat omamobile-firstboot.service` with the drop-in after the
package is installed. R2: with no marker every unit of the link's reports its
condition failed and the gadget is unchanged; the FunctionFS mount and the
endpoints work inside the unit's mount namespace (`ProtectSystem=strict`);
`DevicePolicy=closed` blocks nothing the gadget script needs (its `dmesg`
falls back to the journal); `systemctl stop` runs `ExecStopPost=`'s `remove`;
a `kill -9` of the daemon brings NCM and ACM back within seconds (E12);
`systemd-inhibit --list` shows the lock while the daemon runs. R3: the hold
does not start on the development phone (it has first boot's `done`); the
link's unit starts after `omamobile-boot-success`; the login screen comes as
before.
