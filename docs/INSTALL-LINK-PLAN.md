<!-- SPDX-License-Identifier: MIT -->
# Install link plan: the phone finishes its setup with the installer, over USB

Status (2026-11-12): **design accepted by the maintainer, with its twelve decisions (§12). Nothing here has been built or run on a
phone, and no code, package, image or partition has changed.** This is
milestone M2 of [INSTALL-EXPERIENCE-PLAN](INSTALL-EXPERIENCE-PLAN.md): the
USB channel a freshly installed phone offers at its first start, and what
runs behind it. The reference device is the Pixel 7 Pro (`cheetah`). The
computer side is the Rust installer (its `docs/DESIGN.md` §11 and §12, and
`docs/APP.md`); this document is the specification both sides implement.

The safety model in [CONTRIBUTING](../CONTRIBUTING.md) §3 and
[AGENTS](../AGENTS.md) §1 is unchanged. §13 lists each rule this design
touches and how it is kept.

Facts are marked **[V]** (verified in this repository, file named),
**[D]** (stated in public documentation) or **[I]** (inferred, to be
checked; each has a runbook step in §11).

Decisions this design implements and does not reopen:

| Date | Decision |
| --- | --- |
| 2026-11-09 (D1) | Provisioning happens on the phone. The computer hands Google's factory image over the install link at first boot; the phone checks and extracts it. |
| 2026-11-12 | The owner's answers also go over the install link at first start. The installer never edits an image: what is flashed is byte for byte what the release signed. |
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
12. [Open questions and decisions for the maintainer](#12-open-questions-and-decisions-for-the-maintainer)
13. [Safety rules this design touches](#13-safety-rules-this-design-touches)

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
  setup (§2.2).
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

### 2.2 When it exists

| Condition | Link |
| --- | --- |
| The root image carries `/etc/omamobile/install-link` (written by `tools/build-rootfs` for a release image, so it is part of what the release signed), and no `firstboot.conf`, no `/var/lib/omamobile/firstboot/done` and no account with a uid of 1000 or more exist | Offered: first start |
| The link's own state file exists and its stage is not `finished` | Offered again after a restart or a cable pull, up to the limits below |
| `finish` was received, or the limits ran out | Gone: the marker is deleted and `/var/lib/omamobile/install-link/done` written. No unit starts, no USB function is added |
| A phone installed before the link existed, or with `tools/install-phone` (its image copy has `firstboot.conf`) | Never offered. With a marker and a `firstboot.conf` both present, the daemon deletes the marker, writes `done` and exits |

Limits: once provisioning is done (stage `provisioned`), the link is
offered for 10 minutes after the session is up in each of at most three
boots, then finishes itself. The smoke report is a report, not a
requirement, so a phone whose computer never came back is complete.

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
| A write outside named files | The daemon writes `firstboot.conf`, its own state directory and the factory image's one file (and `boot-update.conf`, if Q3 is accepted). The provisioning worker writes the directories `tools/phone-provision` writes today (§6.3). Each unit's `ReadWritePaths=` lists exactly these **[D]** (systemd.exec) |
| A write to a block device | The daemon's unit has `DevicePolicy=closed` and `DeviceAllow=block-sd r`: UFS block devices can be opened for reading only, whatever the code does **[D]**. The worker's unit allows no block device |
| Anything before the peer is confirmed | Unpaired, the phone answers `hello`, `status`, `pair`, `resume`, `ping` and `bye` only (§5.3) |

### 2.5 How the phone knows the peer

**A six-digit code on the phone's screen, typed on the computer.** The
phone draws a random code (from `getrandom`) at each first-start boot. The
installer asks the owner for it and sends it in `pair`. The phone compares
in constant time.

- Five wrong codes replace the code and lock pairing for 30 s, doubling to
  10 minutes; 20 wrong tries in one boot lock it until a restart. A wrong
  `resume` token or a malformed frame counts as a wrong try.
- A correct code gives the host a random 32-byte **session token**. The
  phone keeps its SHA-256. `resume` with the token pairs again without a
  code: after a cable pull, and after the planned restart, when the
  session owns the screen and no code can be shown.
- The `paired` reply carries a **serial proof**: SHA-256 over a fixed
  label, the session nonce and the phone's `androidboot.serialno`. The
  installer computes the same from the serial it pinned in fastboot and
  stops if they differ, so the phone being set up is the phone that was
  flashed. The serial itself never crosses the link. **[I]**: that
  `/proc/bootconfig` carries `androidboot.serialno` on our kernel
  (`androidboot.cdt_hwid` is read from there today, `tools/phone-provision`
  **[V]**); step R0.

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
| `answers`, before the reply | Either no `firstboot.conf` was written (stage `waiting`) or it was and first-boot setup runs (stage `firstboot`) | `resume`; `status` says which. The installer sends `answers` again only at `waiting` |
| First-boot setup | Carries on; it needs no host | `resume`, `status` |
| Radio backup | Stops reading. Nothing was written on the phone. The partial copy is on the computer | `resume`, then `backup-read` from the offset the computer holds |
| Factory image | Keeps the bytes up to the last synced offset | `resume`, `factory-begin` again: the phone answers with that offset |
| Extraction and provisioning | Carries on; it needs no host. On an error it stops and keeps the image | `resume`, `status`; `provision` again reruns it (every step is idempotent, as in `tools/phone-provision` **[V]**) |
| `restart`, before the reply | Restarts or not; the stage is `provisioned` either way | The installer waits for the link, then `resume` |
| Smoke report, `finish` | Finishes itself within the limits of §2.2 | Nothing is lost but the report |

On the Pixel 7 Pro the MAX77759 opens the USB2 data switch at an unplug and
`omamobile-usb-rescue` closes it again within its 2 s poll while VBUS is
valid (`packages/omamobile-device-cheetah/bin/omamobile-usb-rescue`)
**[V]**. The link's unit wants that service, so a replug comes back in the
root. It does not come back in fastboot's place or in the initramfs on a
phone without the descriptor's `USB_SWITCH`; neither matters here.

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
- `omamobile-install-link.service`: `ConditionPathExists=` the marker and
  not `done`; `After=omamobile-usb-mac.service omamobile-boot-success.service`
  (one gadget change at a time; `devinfo` read-only again before the
  backup); `Wants=omamobile-usb-rescue.service`. While no account exists it
  is ordered `Before=display-manager.service` and does not finish starting,
  so SDDM (enabled in the image **[V]**) shows no greeter on a phone with
  no user, as `omamobile-firstboot.service` holds it back today **[V]**.
  From stage `firstboot-done` on it no longer holds the display manager.

**A new package, `omamobile-provision`** (any), owns the extraction tools,
the on-phone provisioning command and `phone-smoke` (§6).

**`omamobile-firstboot`:** `--check --porcelain FILE`, which prints one
`KEY<TAB>reason-code` line per objection and echoes no value, so the link
can report problems per field in fixed words. Its unit and the rest of the
script are unchanged: the link writes the same `firstboot.conf` that
`tools/install-phone` writes, and starts the unit. A version bump.

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

Either way the composition lasts one boot: the next boot's initramfs
composes NCM and ACM again, as it always does. After `finish`, and when the
daemon stops for any reason, `omamobile-link-gadget remove` puts the gadget
back as the initramfs made it.

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
| FunctionFS | Descriptors in the v2 format with full-, high- and super-speed sets and one string table; events `BIND`, `UNBIND`, `ENABLE`, `DISABLE`, `SUSPEND`, `RESUME` **[D]** (`include/uapi/linux/usb/functionfs.h`). `DISABLE` ends the session (§5.3) |
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

### 5.1 Framing

One frame is one USB bulk transfer. A frame is a 56-byte header, the
payload, and at most one pad byte.

| Offset | Size | Field | Value |
| --- | --- | --- | --- |
| 0 | 4 | magic | `4f 4d 49 4c` ("OMIL") |
| 4 | 1 | frame version | 1 |
| 5 | 1 | kind | 1 = message (JSON), 2 = data (raw bytes) |
| 6 | 2 | flags | bit 0 = a pad byte follows the payload; other bits 0 |
| 8 | 4 | seq | 0 for the first frame a side sends after `ENABLE`, then +1 per frame, per direction |
| 12 | 4 | len | payload bytes: at most 262144 for a message, at most `max_data` (§5.3) for data |
| 16 | 8 | offset | data: the payload's position in the open stream; message: 0 |
| 24 | 32 | sha256 | SHA-256 of the payload (of zero bytes when `len` is 0) |

- **Pad.** When 56 + `len` is a multiple of 64, the sender sets flag bit 0
  and appends one zero byte, which is neither counted in `len` nor hashed.
  Every transfer therefore ends in a short packet at each of the three
  packet sizes, and neither side depends on zero-length packets.
- **Reading.** Each side reads with a buffer of at least 56 + `max_data`
  + 1 bytes, rounded up to a multiple of 1024, and gets one frame per
  completed read **[I]** (FunctionFS returns at the short packet; step L3).
- **A frame that is wrong** (magic, version, kind, a reserved bit, `seq`
  not the expected one, `len` over the limit or not the bytes that
  arrived, a digest that does not match, a data frame with no open stream
  or the wrong `offset`) is a protocol error: the phone sends `error` with
  `code: "protocol"`, ends the session (§5.3) and counts a wrong try
  (§2.5). An open stream is kept as it was at its last acknowledged offset.
- **Flow control** is the bus's own: a side that is not reading is not
  sent to. The phone reads the next data frame only after it has written
  the previous one. Acknowledgements (§5.6) mark what is on disk; they are
  the resume points, not a window.

### 5.2 Messages

A message is one JSON object with a `t` (type). The host's messages carry
`id`, a whole number that goes up by one; the phone's answer carries
`re` with that number. The phone answers every message exactly once, with
the reply named below or with `error`. Messages the phone sends by itself
(`progress`, `ack`, and the events that end a long step) carry no `re`.
Unknown keys are ignored. An unknown `t` is answered `error`,
`code: "unknown"`, and changes nothing.

`error` is `{t, re?, code, message, stage}`. `message` is fixed English
text for a log; the installer shows its own words chosen by `code`. Codes:
`protocol`, `version`, `unknown`, `not-allowed` (the message is not allowed
now; nothing changed), `not-paired`, `bad-code` (with `left`), `locked`
(with `wait_s`), `bad-token`, `problems` (see `answers`), `busy`,
`backup-precondition`, `backup-mismatch`, `no-space` (with `need`, `free`),
`too-large`, `factory-mismatch`, `provision-failed` (with `step`),
`firstboot-failed` (with `steps`), `battery`, `internal`.

**Anything unexpected changes nothing.** A message out of turn gets
`not-allowed` and the phone stays where it was. Only §5.1's frame errors
end the session.

### 5.3 Session, version and pairing

| Message | Direction | Allowed | Fields | Reply |
| --- | --- | --- | --- | --- |
| `hello` | host to phone | First, and again at any time (it starts a new session: unpaired, open stream suspended) | `proto`: list of numbers the host speaks; `installer`: {`name`, `version`}; `max_data`: at most 4194304 | `hello`: `proto` (the highest in both lists), `link` (daemon version), `device` (codename), `max_data` (the smaller; 1048576 by default), `nonce` (64 hex digits, new per session), `stage`, `pair` (`code`, `token` or `locked`), `wait_s`. No common number: `error`, `code: "version"`, with the phone's list; the screen says the installer is too old or too new |
| `ping` | host to phone | Any time | | `pong` |
| `pair` | host to phone | Unpaired, `pair` is `code` | `code`: six digits | `paired`: `token` (64 hex digits), `serial_proof` (64 hex digits). Wrong: `bad-code` or `locked` |
| `resume` | host to phone | Unpaired, a token exists | `token` | `paired`: `serial_proof`. Wrong: `bad-token` |
| `bye` | host to phone | Any time | | `bye`; the session ends, the stage stays |

`serial_proof` = SHA-256("omil-serial-v1" ‖ the 32 nonce bytes ‖ the
serial's bytes).

A session ends at `bye`, a new `hello`, a frame error, FunctionFS's
`DISABLE` or `UNBIND` (the cable, a host reset), or 10 minutes with no
frame from the host. Ending a session never changes the stage.

Timeouts: the phone answers a message within 10 s, or sends `progress` at
least every 5 s until it does. The host takes 60 s of silence during a
step as a lost link and starts again from `hello`. The phone suspends an
incoming stream after 120 s without a frame.

### 5.4 Status

| Message | Direction | Allowed | Reply |
| --- | --- | --- | --- |
| `status` | host to phone | Any time after `hello`, paired or not | `status` |

`status` fields: `stage`; `boot` (1 before the planned restart, 2 after);
`release` (from `/usr/share/omamobile/rootfs/MANIFEST`); `kernel`
(`uname -r`); `device`; `firstboot`: {`state`: none, running, done or
failed; `step`: the step's name as `omamobile-firstboot` logs it; `n`,
`of`; `failed`: names}; `backup`: {`state`, `parts`: [{`name`, `size`,
`verified`}]}; `factory`: {`state`, `have`, `size`}; `provision`:
{`state`, `step`, `n`, `of`}; `battery` (percent), `charging`; `free`
(bytes on the root). It names no user, host name, network, serial or
address, so it is safe unpaired.

The stages, in order, each recorded on disk before the reply that
announces it:

```
waiting -> firstboot -> firstboot-done -> provisioned -> finished
              |               (the radio backup and the factory image are
              v                sub-states: any order, any time after pairing)
        firstboot-failed
```

### 5.5 The owner's answers, and the radio backup

| Message | Direction | Allowed | Fields | Reply and effect |
| --- | --- | --- | --- | --- |
| `answers` | host to phone | Paired, stage `waiting` | `username` (at most 32 bytes), `password_hash` (sha512-crypt, at most 128), `credential` (`pin` or `password`), `hostname` (63), `timezone` (64), `wifi_ssid` (32, optional), `wifi_psk` (64, optional), `ssh_keys` (at most 8, each at most 8192), `full_name` (128), `email` (254) | The phone writes the fields as a `firstboot.conf` candidate (mode 600) on a tmpfs and runs `omamobile-firstboot --check --porcelain` on it: the rules are first boot's own (`USERNAME_RE`, the reserved names, `HASH_RE`, the zone file's existence, the key formats) **[V]**, and nothing the host says about validity is used. Objections: `error`, `code: "problems"`, `problems`: [{`field`, `reason`}]; nothing is kept. None: the file is renamed to `/etc/omamobile/firstboot.conf`, the stage becomes `firstboot`, `omamobile-firstboot.service` is started, and the reply is `answers-ok` |
| `firstboot-retry` | host to phone | Paired, stage `firstboot-failed` | | Starts the unit again with the kept file (`omamobile-firstboot` reruns safely **[V]**); `answers-ok` |
| `backup-list` | host to phone | Paired, stage before `provisioned` | | The phone checks what `tools/nv-backup` checks **[V]**: the board's first compatible string equals the descriptor's `COMPATIBLE`; each of `NV_PARTS` and `NV_BACKUP_EXTRA` is found exactly once by `PARTNAME` in `/sys/class/block/*/uevent`, is a block device, reads `ro` 1 and is not mounted. All hold: `backup-parts`, `parts`: [{`name`, `size`, `checked`}] (`checked`: in `NV_PARTS`). Otherwise `backup-precondition` with the partition names, and nothing is read |
| `backup-read` | host to phone | After `backup-parts` | `name`, `offset` (a multiple of `max_data`) | `data-begin` {`name`, `size`, `offset`}, then data frames from the partition, opened read-only, then `data-end` {`name`} |
| `backup-verify` | host to phone | After `data-end` for that name | `name`, `sha256`: of the computer's whole copy | The phone reads the whole partition a second time and compares, as `nv-backup` does **[V]**: `backup-verified`, or `backup-mismatch` (the computer discards its copy and reads again) |
| `backup-commit` | host to phone | Every part verified | | The phone runs `backup-list`'s checks again and compares device names with the first run. Then it keeps the `NV_PARTS` lines, in `sha256sum`'s format, as the pending `/etc/omamobile/modem-nv.sha256`; reply `backup-done`. That file reaches `/etc` only in `provision`, so the modem cannot start before the computer has confirmed a verified copy |

`abort` (host to phone, any time a stream is open) ends the stream at its
last acknowledged offset; reply `aborted`.

The computer writes the backup as `tools/nv-backup` does: `NAME.img` files,
`SHA256SUMS`, `partitions.txt` and `NV-BACKUP`, directory mode 700, files
600, into a new directory **[V]**, so `tools/nv-backup --check DIR` reads it
later.

### 5.6 The factory image, provisioning, the report and the end

| Message | Direction | Allowed | Fields | Reply and effect |
| --- | --- | --- | --- | --- |
| `factory-begin` | host to phone | Paired, stage before `provisioned`, no stream open | `size` (at most 8 GiB), `sha256`, `build`, `name` (shown only) | The phone needs `size` plus the working space of §6.4 free, or `no-space`. `factory-ready` {`offset`}: 0, or the last synced offset of a kept partial file with the same `size` and `sha256` (another file's partial is deleted). The host then sends data frames from that offset |
| `ack` | phone to host | During the stream | `offset` | Sent after each 64 MiB is written and synced: the resume point |
| `factory-end` | host to phone | All `size` bytes sent | | The phone reads the whole file back and hashes it (`progress`, `what: "factory-check"`). Equal: `factory-verified`. Different: the file is deleted, `factory-mismatch`, and a wrong try is counted |
| `provision` | host to phone | Paired; first boot `done`; `backup-done`; `factory-verified`; charging or battery at least 30 % | | `provision-started`, then `progress` {`what: "provision"`, `step`, `n`, `of`} and at the end the event `provision-done` {`steps`: [{`step`, `state`}]} or `error`, `provision-failed`. On success the stage is `provisioned` and the factory image and the working directory are gone (§6.4) |
| `restart` | host to phone | Paired, stage `provisioned` | | `restarting`; then `systemctl reboot`, never `reboot-to` (the unit stops run) |
| `smoke` | host to phone | Paired, stage `provisioned`, `boot` 2 | | The phone waits up to 180 s for the session, runs `phone-smoke --here --json` and replies `smoke-report` {`report`} |
| `finish` | host to phone | Paired, stage `provisioned` | | `finished`; the stage is `finished`, the marker, the token and the state are deleted, `done` is written, the gadget is put back (§3.3) |

`progress` is {`what`, `step`, `done`, `total`}; `total` 0 means unknown.

The integrity of each payload: every frame's digest (§5.1); the factory
image's whole-file SHA-256, checked on the phone before anything opens the
file; each radio partition's SHA-256, computed independently on both sides
from separate reads; each installed file's SHA-256 against the extraction's
own list (§6.3).

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
  `unicorn` module included; stage L4. (It carries them, but its `unicorn`
  aborts in the camera tool: the module comes from `omamobile-unicorn`,
  stage L4's first finding.)
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
| camera | `/usr/lib/firmware/omamobile/camera` | merged; a failed camera step is reported in `provision-done` and does not fail the rest |
| modem data | `/etc/omamobile/modem-nv.sha256` from the pending file; `/var/lib/omamobile-vendor/modem/props.conf` from bootconfig | written, then read back |

Each tree is checked against its SHA-256 list after it is installed, as
`push_tree` checks it **[V]**. The worker starts and stops no service: the
firmware loads at the restart, `omamobile-fp` starts once per boot by its
own unit, and the modem starts at the next boot from its own unit.
The worker's unit has `ProtectSystem=strict`, `ReadWritePaths=` the six
targets and the working directory, no network and no device access; the
extraction itself (which parses the image) runs inside it as an
unprivileged user that can write the working directory only.

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
provisioning succeeds, at `finish`, and when the link finishes itself. A
start of the daemon removes a working directory left by a crash.

Kept: the installed files of §6.3, `/usr/lib/omamobile-provision/SOURCE`
(the build id and the image's SHA-256, for M5), and `done`. Not kept: the
image, anything unpacked, the token, the code, the answers
(`omamobile-firstboot` deletes `firstboot.conf` **[V]**).

## 7. The computer side

### 7.1 The core

| Piece | What it is |
| --- | --- |
| The protocol crate | Framing, the message types and the limits of §5, with no I/O: bytes in, bytes out. The phone's daemon builds on the same crate, pinned by version, so there is one implementation of the wire. Which repository holds it is Q8 |
| A second transport | `Link`, next to fastboot's: find the interface (§4), claim it, bulk out and in. Native through the USB library the core already uses; in the browser through WebUSB's `transferOut` and `transferIn`. A loopback transport and a pretend phone for tests, as fastboot has |
| The states after `installed` | `first-start` (wait for the link) -> `pair` (the code) -> `setup` (answers sent, first boot running) -> `radio-backup` -> `factory-send` -> `provision` -> `restart` -> `check` (the smoke report) -> `ready`, each with stops. `write_done` no longer ends the flow |
| The answers | Asked before the write, as today, and kept in memory until the link is paired. `core/src/firstboot.rs` already hashes the password as `openssl passwd -6` does; it now fills `answers`' fields instead of making file bytes. The form gains the SSH key, full name and email (`AnswersInput`) |
| The closed list | The link's send path takes a typed message, never bytes from a caller, as fastboot's command layer does. There is no "send raw" |
| The record | The token, the backup directory and the stage reached, so a second run of the installer goes on. In memory and in the work directory (mode 600); never in a report |

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
- **The tab must stay open** and in front; a reload loses the token. In
  boot 1 the owner types the code again. After the restart the report is
  skipped and the phone finishes itself (§2.2).
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
| Pair | Wrong code; locked | The code; "Wrong code" with the wait | The same, in the core's words | Type again; a restart gives a new code |
| Pair | The serial proof differs | Nothing changes | "This is not the phone that was just installed." Stop | Connect the right phone |
| Answers | First boot's rules object | Nothing changes | The form, with the problem under its field | Send again |
| First-boot setup | An essential step fails (`firstboot.conf` kept **[V]**) | "Setup stopped at: <step>" | The step's name; "try again" sends `firstboot-retry` | The unit also reruns at the next boot **[V]** |
| Radio backup | A partition is writable, mounted, missing or doubled | Nothing changes | Stop: "the phone's storage guard isn't holding", with the names. No workaround is offered | Not until a person has looked: ask in an issue |
| Radio backup | A read fails, or the second read differs | Nothing changes | Retries that partition up to five times, then stops; nothing partial is kept on the computer | Any time |
| Factory image | No space; too large | "Not enough space" | Stop with the numbers | After a reinstall |
| Factory image | The whole-file check differs | "The file from the computer was damaged. Sending again." | Sends again once from zero; a second mismatch stops and deletes the computer's copy too | Downloads again |
| Provisioning | A step fails | "Setup stopped at: <step>" | The step; "try again" sends `provision` | Idempotent. The image is still there |
| Provisioning | The camera step alone fails | Goes on | A line in the final list: "Cameras: not set up" | `provision` again before `finish`. After it, `tools/phone-provision` over SSH (§10) |
| Restart | The phone does not come back | Whatever the boot shows | After 10 minutes: restart by the buttons; then fastboot and flash again | The stage is `provisioned`: a later boot offers the link within its limits |
| Check | A required row fails | The lock screen | "Something went wrong", the rows, and a report to save (§9) | The phone is installed; the report is for an issue |
| Any | The installer or the computer is gone for good | Boot 1: the code. Later boots: the session | | Before the answers: flash again. After first boot: the phone works without Google's files (no Wi-Fi, sound or cameras); reinstall to finish |

## 9. Privacy

| Crosses the link | Direction | Then |
| --- | --- | --- |
| The code | computer to phone | Compared, forgotten |
| The token | phone to computer, and back at `resume` | Computer: memory and the work directory. Phone: its SHA-256, deleted at `finish` |
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
| L1 | The protocol crate: frames, messages, limits | Golden frames (bytes in this document's layout) checked in both repositories; a loopback transport; every frame error; every message out of turn | This document accepted; Q8 |
| L2 | `omamobile-linkd` against a socket pair in place of the endpoint files, and a scratch root (as `OMAMOBILE_FIRSTBOOT_ROOT` and `NV_PHONE_ROOT` do today **[V]**) | The whole flow against stand-in partitions that are regular files; the read-only preconditions each refused; a pulled "cable" before every frame; lockout; the stage file after a kill at every point | L1; `omamobile-firstboot --check --porcelain` |
| L3 | The daemon on real FunctionFS over `dummy_hcd`, on a laptop or VM kernel that has it (the phone's kernel does not: `CONFIG_USB_DUMMY_HCD` is not set **[V]**); `omamobile-link-gadget` against a fake configfs tree and against `dummy_hcd` | The descriptors as a host reads them; one frame per read; the pad rule at 64, 512 and 1024; unbind and bind; the OS descriptor requests; the hang marker | L2 |
| L4 | `omamobile-provision`: the tools packaged for aarch64 | The byte-for-byte comparison of §6.2 in the aarch64 container against the laptop's run, for each factory build the index lists; the existing `tests/extract-*` against the packaged copies | The maintainer's own factory images, never committed |
| L5 | The root image with both packages and the marker; `manifest.json`'s `install_link` | `tests/rootfs-smoke`, `tests/build-rootfs`, `tests/make-bundle`; the unit's conditions in a scratch root: marker with and without `firstboot.conf`, with `done`, with an existing account | L2 to L4 |
| L6 | The installer: the `Link` transport, the states, the pretend phone that speaks §5 | The write path's tests extended through `ready`; an interrupted run at every state, rerun; app protocol 2 against the stand-in | L1 |

**Stage L4: built on 2026-11-12, offline. Nothing of it has run on a
phone, and one of its results is a stop: the camera step does not run with
Arch Linux ARM's `python-unicorn` (below).**

It was built against the revision of this plan corrected after stage L1
(the `install-link-plan-l1` branch), whose §6.3 to §6.6 and §11.3 the
section numbers below are.

Built (`packages/omamobile-provision` 0.1.0, its `README.md` has the
detail):

- The four extraction tools and `phone-smoke`, packaged from `tools/`
  unchanged: one copy in the repository (`stage-tools` copies them for a
  build, and the three builders run it), none edited for the phone.
- `omamobile-provision first-install FACTORY.zip NV-SUMS`:
  `tools/phone-provision --first-install` with local installs, the same
  places, modes and owner, the checksum file its last write before the
  result file, nothing started or stopped, the extraction as `nobody`, the
  optional step's one retry (§6.6), `progress` lines, the first-start
  check, and `extract` and `listing` for R1.
- The whole-or-untouched install of §6.3, with two differences from what
  §6.3 says, both forced by where the trees live:
  - the gnss, modem and fingerprint trees share their directory with their
    package's own files, so the directory can't be exchanged. Their new
    entries are staged inside it; an older `root/` is renamed out, the
    other entries renamed in, and `root/`, which every user of these trees
    looks for, renamed in last. A cut leaves the old tree, no `root/`, or
    the new tree, never a mix; over an older tree that is "whole or absent
    until the rerun", not "whole or untouched". A first install has no
    older tree;
  - the sensor registry is exchanged as §6.3 says, which needs its parent
    writable: the worker's unit must allow `/usr/share/omamobile/sensors`,
    not only the registry, and `/usr/lib/omamobile-provision` for `SOURCE`.
- The first-start state is read from files, since the daemon's state file
  is L2's: the marker, the link's directory without `done`, first boot's
  `done`, and no `modem-nv.sha256` but this run's own. L2 should confirm
  or replace that reading.
- No descriptor names `PROVISION_STEPS` or `PROVISION_OPTIONAL` yet (a
  change to `device.conf` changes the staged boot files): the worker's
  defaults are cheetah's seven steps with `camera` optional, and every
  other device is refused.

Verified without a phone:

| What | Result |
| --- | --- |
| The dependencies on Arch Linux ARM (§6.2's **[I]**) | All resolve, and `pacman -U` installs the built package with them in the aarch64 build container: `unzip` 6.0, `android-tools` 37.0.0 (`simg2img`, `lpunpack`), `e2fsprogs` 1.47.4, `erofs-utils` 1.9.4, `binutils`, `python` 3.14.10, `python-unicorn` 2.1.4-2, `python-pyelftools` 0.33-1 |
| The build | `tools/build-packages --local cheetah` with a local key; the package's `test/all` passes natively and, as `check()`, in the container |
| A kill between any two installs | The run killed at each of 45 checkpoints on a first install and 48 over an older generation, each followed by a rerun: no half tree at a final path, the checksum file never before the rest, every rerun finishes. Three deliberately broken workers each fail the test |
| §11.3's F5 | The camera step made to fail once (all `ok`) and twice (`ok` true, `camera` `failed`, `optional_failed`); never a third try |
| The tools' own tests on the packaged copies | `tests/extract-vendor-firmware`, `tests/extract-camera-data`, `tests/phone-smoke` pass; `tests/extract-camera-sve.py` passes on the laptop |
| Byte for byte (§6.2), on this laptop (x86-64), packaged tools run the worker's way against `tools/` run `phone-provision`'s way | Equal for both builds the index lists: CP2A.260705.006 (1778 files, 27 symlinks) and CP3A.261005.002.A1 (1761 files, 27 symlinks), the camera data included |
| Byte for byte, the phone side in the aarch64 container (qemu-user), the package installed by pacman, the extraction as `nobody` | CP2A.260705.006 and CP3A.261005.002.A1: firmware, registry, both chroots with `MANIFEST`, `SOURCE` and `STUBS`, and the fingerprint tree are equal. **The camera step fails there** |

Found, each needing a decision before L5:

1. **The camera step aborts with Arch Linux ARM's `python-unicorn`
   2.1.4-2.** `extract-camera-data` dies in unicorn itself
   (`sve_zcr_get_valid_len: Assertion 'end_len < start_len' failed`,
   `qemu/target/arm/helper.c`), on a real camera APEX and in the
   repository's own `tests/extract-camera-sve.py`, which needs no factory
   image. The same test and the same version from PyPI's wheel pass on the
   laptop. The distribution's build has assertions on; **[I]** the wheel is
   built without them, and the assertion is about the emulated CPU's
   vector lengths, not the host, so the phone is expected to abort the
   same way (seen under qemu-user only; R1 checks it on the phone). No
   setting in the tool can avoid it. Until a `python-unicorn` that passes
   `tests/extract-camera-sve.py` on aarch64 is in `[omamobile]` (or the
   camera step runs natively, §6.2), every install over the link ends
   "Cameras: not set up", and by §6.6 such a build is not offered.

   **Answered on 2026-11-12, offline: `packages/omamobile-unicorn`.** The
   **[I]** above is now checked. The distribution's library is configured
   with `-DCMAKE_BUILD_TYPE=None` (its PKGBUILD), which keeps `assert()`;
   upstream's wheel is a `Release` build (`bindings/python/setup.py`),
   which compiles it out: the distribution's library imports
   `__assert_fail` and holds the assertion's text, the wheel's does
   neither. Built twice in the aarch64 container from upstream's 2.1.4
   tarball with only the build type changed, `None` aborts in
   `tests/extract-camera-sve.py` with that line and `Release` passes all
   five checks. Behind the assertion is a gap in Unicorn 2.1.4 itself (the
   emulated CPU's table of SVE vector lengths is never filled), which no
   setting of the tool reaches. `omamobile-unicorn` 2.1.4-1 is that
   `Release` build, AArch64 target only, with the binding, under
   `/usr/lib/omamobile-unicorn/python`: it provides and conflicts with
   nothing, and the distribution's packages install beside it.
   `omamobile-provision` 0.1.1 depends on it in place of `python-unicorn`
   and runs `extract-camera-data` with that directory as its
   `PYTHONPATH`. In the container, with both packages installed by pacman
   and no distribution `unicorn`: `tests/extract-camera-sve.py` passes as
   `nobody`; with the distribution's packages added beside them it still
   passes on the private copy and still aborts on theirs.
   The byte for byte comparison with the phone side in the container, the
   two packages installed and the extraction run as `nobody`, is now equal
   with the camera data included, for CP3A.261005.002.A1 (1761 files, 27
   symlinks) and CP2A.260705.006 (1778 files, 27 symlinks).
   Not run on a phone: R1 now also checks this package's library there
   (`packages/omamobile-unicorn/test/all --installed`). Unicorn is
   GPL-2.0-only: the package's README says what publishing it asks for,
   and finding 3 below holds for it too.
2. **`MANIFEST` and `vendor-firmware.sha256` depend on the locale.** The
   three tools sort them with the locale's collation. The worker runs the
   tools under `LC_ALL=C`; a laptop in `en_US.UTF-8` writes the same lines
   in another order (seen on the real image: four files differ that way,
   and nothing else). The comparison above ran the laptop side under
   `LC_ALL=C`. Either the tools sort with `LC_ALL=C` (one line each; it
   changes the order on such a laptop) or §6.2's "byte for byte" is read
   as "under `LC_ALL=C`".
3. **The nightly build publishes every package in `packages/`.** This one
   is inert when installed, but it would reach the development repository
   before R1 unless it is held back.

Not verified: anything on the phone (R1: the same comparison there, the
time and the peak working space, the camera step on real aarch64); the
worker inside the unit L2 gives it (`ProtectSystem=strict`, its
capabilities); the result file and `progress` lines against the daemon
that will read them; an EROFS vendor image (the chroot tools refuse one
today); any device but cheetah.

### 11.2 On the reference phone

Before any step: the phone on the charger; `tools/nv-backup --check DIR`
against the newest backup says SAME for every `NV_PARTS` partition;
`tools/phone-smoke` passes its required rows. R2 to R6 run on the
development phone as it is, with SSH as the safety net. Every step that
draws on the screen or stops the display manager is announced first.

| Step | What | Expect / Pass | Stop | Rollback | Risk | Writes |
| --- | --- | --- | --- | --- | --- | --- |
| R0 | Read only: `zcat /proc/config.gz` for `CONFIG_USB_CONFIGFS_F_FS`; `ls` the gadget's `functions` and `configs/c.1`; `cat` its `UDC` and the UDC's `current_speed`; count (not print) the `androidboot.serialno` lines in `/proc/bootconfig`; `df` the root; `ls /dev/fb0` | `=y`; `ncm.usb0`, `acm.GS0`; one UDC; a speed; count 1; more than 40 GiB free; `fb0` exists | Any differs: the design's **[I]** for it is wrong; stop and revise | None needed | None | Nothing |
| R1 | Install `omamobile-provision` (`tools/phone-install-package`). Copy one factory image to a scratch directory over SSH; run the extraction into a scratch output, installing nothing; compare with the laptop's output | Every file's SHA-256, mode and link target equal; time and peak disk use recorded | Any difference; an error line from UFS in `dmesg` | Remove the scratch directories; `pacman -R` the package | Low | Files on the root (`userdata`) |
| R2 | Install `omamobile-install-link`. Ask the human; arm `systemd-run --unit=x-deadman --on-active=90 systemctl reboot` (the next boot's initramfs restores the gadget); run `omamobile-link-gadget add` with the daemon limited to `hello`, `ping` and `status`; from the laptop read `status`; confirm with `tools/phone-ssh --fresh`; stop the timer | The host lists NCM, ACM and the link interface with §4's values; `status` gives the release and the kernel; SSH answers on a fresh login; `dmesg` has no new error | No fresh SSH within 90 s: the dead-man restarts the phone. Wait 2 minutes, replug once, then ask for a forced restart | `omamobile-link-gadget remove`, or a restart | Medium: it unbinds the only link | Nothing persistent but the package |
| R3 | A boot with the link added by the unit (the marker placed by hand, the daemon still limited as in R2). One change: the unit at boot | The link is there after the boot with no hand step; SSH answers; the hang marker is gone | The phone is not on the bus 3 minutes after the boot: forced restart; the marker then skips the change, and SSH is back | Delete the marker file over SSH | Medium | The marker |
| R4 | Pull the cable for 10 s and replug, the daemon logging to a file | Within 10 s of the replug: SSH and `hello` both answer; the daemon logged `DISABLE` then `ENABLE` | Not back in 60 s: wait 2 minutes, replug once, then a forced restart | A restart | Low | Nothing |
| R5 | The screen. Announce it. Stop the display manager, run `omamobile-install-screen` with a test code for 30 s, start the display manager | The code is readable on the panel; the session comes back | Nothing drawn: the **[I]** in §3.3 is wrong; switch to the fallback and repeat | `systemctl start sddm`, or a restart | Low; the screen goes away for a minute | Nothing |
| R6 | The full daemon on the development phone, the code read from the journal: pair, `backup-list` through `backup-commit` into a new directory; then `factory-begin` through `factory-end` with one cable pull in the middle; no `answers`, no `provision` | The link's backup has the same `NV_PARTS` digests as the newest `tools/nv-backup` backup; `tools/nv-backup --check` on it says SAME; every partition still reads `ro` 1; the image's digest is right after the resume; the rate is recorded | Any `NV_PARTS` digest differs; any partition reads `ro` 0; `ufshcd_err_handler` in `dmesg` | Delete the phone's state directory and the new backup directory; remove the marker | Medium: it reads the radio partitions | The state directory and the image file on the root |
| R7 | **A full install with the link beside NCM and ACM.** A fresh `tools/nv-backup` into a new directory first, and a known-good bundle at hand. Flash a release whose image has the marker, unmodified (Q2 says with which tool); then the command-line installer through the link to `ready` | The code appears; every state passes; the installed trees equal R1's; after the restart the smoke report's required rows pass and Wi-Fi, sound and cameras show as evidence; the link is gone at the boot after `finish`; `tools/nv-backup --check` says SAME | Any stop in §8's table that a rerun does not clear; any radio partition DIFFERENT | Fastboot by the buttons, then `tools/install-phone` with the known-good bundle | **High. Writes slot B and `userdata`: the maintainer's go** | Slot B's five images, `userdata` |
| R8 | **The same with the link alone** (the release composition). One change from R7 | As R7; the computer shows no new network adapter | As R7. With no SSH, a silent phone is a forced restart, then fastboot | As R7 | **High. Writes slot B and `userdata`: the maintainer's go** | As R7 |
| R9 | Drills on R8's phone before its `finish`, and on one more install: five wrong codes; a wrong image digest; the cable pulled in each row of §2.6; the installer killed and run again at each state; no computer after the restart for 10 minutes | Each ends as §2.6 and §8 say; the phone finishes itself | Any state the tables do not name | Reinstall as R7 | High for the reinstall, with the maintainer's go; low otherwise | As R7 for the reinstall |
| R10 | Absence. On a phone installed with `tools/install-phone` from the same release, and on R8's phone after `finish` | No link interface on the bus, the unit's condition failed, no marker | The link is offered | Remove the package; fix before any release | Low | Nothing |

A release may carry the marker only after R8 to R10 have passed with that
release's packages.

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

## 13. Safety rules this design touches

Checked against AGENTS §1, rule by rule.

| Rule | How this design keeps it |
| --- | --- |
| Ask the human before every reboot, flash or irreversible write | Every runbook step is the human's; R7 to R9 name the maintainer's go. On an owner's phone the one restart is asked for by the installer the owner is driving |
| Announce anything that affects the screen | R5 and every install-mode boot draw on the screen: announced in the runbook. No haptics, torch, brightness or display-mode change anywhere |
| Only slot B and `userdata` | The link writes files on the root file system. It opens no partition for writing and cannot (§2.4). The flash stays fastboot's, through the tools that have the rule |
| Linux never writes the modem's NV partitions | Read-only opens, after the `ro` 1 and not-mounted checks, twice per backup. `modem-nv.sha256` is written only after the computer confirmed its copy. The NV overlay is not touched |
| Never weaken the storage guard | No `blockdev`, no `/dev/sda`, no change to `UFS_RW`. `initramfs/init` is unchanged. A partition that is not read-only stops the backup with no workaround |
| Check backups before radio work | The runbook starts with `nv-backup --check`; R7 takes a fresh backup first. On an owner's phone the link's own backup precedes the modem's first start |
| No PMU registers, `devmem`, or reads of unpowered blocks | None. The daemon reads sysfs, procfs, bootconfig and block devices |
| Read-only first, one change per boot | R0 reads; R1 to R6 add one thing each; R7 and R8 differ by one thing. No device-tree node, overlay or module is added |
| A safety net before every risky step | R2's dead-man timer and fresh SSH login; the gadget script's hang marker and `EXIT` trap; SSH kept beside the link until R8 |
| A stuck reboot | `restart` is `systemctl reboot`, so the reboot watchdog applies and the modem's unit stops cleanly; the runbook's stop conditions say wait, replug once, then ask |
| Fingerprint, AoC and modem services | Provisioning starts, stops and restarts no service; each starts once, by its own unit, at the next boot |
| Never commit or paste identifying data or vendor blobs | The backup stays on the owner's computer; the board id and serial never cross; logs and reports carry none of §9's list; L4's factory images are never committed. This document holds no address, serial, IMEI or network name |
| Citable sources; no other projects named | Upstream Linux's documentation, the USB specification, and this repository's files |
