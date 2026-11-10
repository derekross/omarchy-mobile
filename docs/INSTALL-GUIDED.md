<!-- SPDX-License-Identifier: MIT -->
# The guided install: design of milestone M1

Status (2026-11-10): **built and tested against stand-ins; not yet run on a
phone, and not in any release bundle.** This is the design of M1 in the
[install experience plan](INSTALL-EXPERIENCE-PLAN.md) §11: one command that
runs the whole install with today's tools. The code is
[`tools/install-guided`](../tools/install-guided), a repository tool for
now, with [`tools/factory-index`](../tools/factory-index) and
[`tools/camera-requirements.txt`](../tools/camera-requirements.txt); the
tests are `tests/install-guided` and `tests/factory-index`. §8 is the
runbook for its first run on a phone, and §10 says what has to be true
before it becomes a bundle's `install`.

## 1. What it is, and what it isn't

`tools/install-guided` walks a person through the install and runs each of
today's tools in turn. It adds no way to write a phone:

- **Every write to the phone is `tools/install-phone`'s**: slot B's boot
  images and `userdata`, after its checks, with the codename typed. The
  guided installer runs it three times: `--verify-only` (the files, no
  phone), `--dry-run`, then for real, the last two with `--serial`, so
  `install-phone` refuses every phone but the one the guided installer
  looked at.
- **What the guided installer itself sends to a phone:** `fastboot devices`,
  `fastboot getvar all` and `fastboot flashing get_unlock_ability` (all
  read-only); `adb devices -l` (asks the adb server) and, after the owner
  presses Enter, `adb reboot bootloader`; and over USB SSH read-only checks
  (is anything there, which phone it is, the first start's marker, the boot
  id, `systemctl is-system-running`) and the restart of step 10.
- **It never sends `fastboot flashing unlock`** (decided 2026-11-10): it
  shows the command, and the owner types it. The unlock erases the phone,
  and no tool of ours sends a `flashing` command.
- **It never downloads Google's factory image and never shows Google's
  terms** (plan D2). It opens Google's page; the owner accepts the terms
  there and saves the file; the installer takes the saved file and checks
  its SHA-256 against the signed build index.
- **After the write, every step is for the phone that was written.** Steps
  7 to 11 talk to whatever answers at the phone's USB address, so each
  first asks that phone which one it is (§3a) and stops unless it is the
  one this install wrote.
- **Device rules come from `device.conf` and `manifest.json`.** The key
  combinations and the disk space are descriptor keys (§6); the writes are
  `install-phone`'s reading of the manifest.

## 2. The steps

Read-only steps run every time; a step that changes something runs once and
is recorded. "Reads" and "writes" are on the computer unless they say the
phone.

| # | Step | Reads | Changes | Recorded | On a rerun |
| --- | --- | --- | --- | --- | --- |
| 1 | Preflight | every program a later step runs (below), the SSH public key, free space (`INSTALL_FREE_GB`), the download through `install-phone --verify-only` (signature, checksums, `manifest.json`, root image) | nothing | nothing | always runs |
| 2 | The warning | the release's label | nothing | `warning` (date, release) | skipped once acknowledged |
| 3 | The phone | `fastboot devices`, `getvar all`, `get_unlock_ability`, `adb devices -l` | `adb reboot bootloader` after Enter | `phone` (SHA-256 of the serial) | runs until the phone is written; then skipped |
| 4 | Factory image | the build index, the phone's bootloader and baseband, the saved zip | opens Google's page | `factory_*` (build, name, page, size, SHA-256, path) | skipped while the file is there with its size; taken again from the record otherwise |
| 5 | Write | whether anything answers at the phone's USB address; the owner's answers (memory only) | `install-phone --dry-run --serial S`, then `install-phone --serial S`: slot B and `userdata` | `write=started`, then `done` | skipped when `done`; `started` runs it again, whole |
| 6 | USB connection | `phone-ssh true`, `nmcli connection show` | `nmcli connection add …` after Enter (§5a) | `network` | skipped |
| 7 | First start | the phone: `/var/lib/omamobile/firstboot/done`, then which phone it is | nothing | `first_start` | waits again |
| 8 | Radio backup | which phone it is; the phone, through `nv-backup` (read-only) | a new folder `~/omamobile-backup/<codename>-radio-backup-<date>` | `backup_dir`, `backup` | skipped while its `SHA256SUMS` is there |
| 9 | Firmware | the zip's SHA-256 again; which phone it is | optional Python folder after Enter (below); `phone-provision -d <codename> --first-install --nv-backup DIR ZIP` | `camera_tools` (only `skipped`, only for a typed `no`), `provision` | runs again (it is idempotent) |
| 10 | Restart | which phone it is, before and after; its boot id | stops the modem's unit, `reboot-to omamobile` | `restart_from` before sending, `restart` | waits for the restart already sent; sends none twice |
| 11 | Check | which phone it is; `phone-smoke --json` | saves `report.json` | `check`, `finished` | runs again |

Details that matter:

- **Step 1** asks for every program the later steps run, so a missing one
  stops the install before the phone is erased, not after: `fastboot`,
  `debugfs`, `dumpe2fs`, `e2fsck`, `zstd`, `lz4`, `cpio`, `openssl`, `gpg`,
  `python3`, `unzip`, `ssh`, `sha256sum`, `tar`, and for step 9's extract
  tools `lpunpack`, `simg2img`, `fsck.erofs` and `readelf` (or
  `llvm-readelf`). Two things are said there and are not stops: a computer
  without NetworkManager (step 6 then asks the owner to set the address),
  and a Python that can't make a module folder (step 9's cameras).
- **Step 2, the warning, comes before the phone step** (decided 2026-11-10,
  plan D9): for a locked phone, the unlock that step 3 guides is what
  erases it. It is acknowledged once and recorded once, and nothing asks
  again. A record without the acknowledgement shows it, whatever else the
  record holds (one made before the order changed could name the phone
  and no warning).
- **Step 3** shows only the steps left for the state it finds (plan §4.2):
  no phone; Android asking "Allow USB debugging?"; Android allowing the
  computer; Fastboot Mode locked with OEM unlocking off; locked with it on;
  unlocked. One phone only, on adb as in Fastboot Mode; a phone on adb is
  named (model, codename, the last four characters of its serial) before
  the question that restarts it, and another model is not restarted. It
  stops early, in plain words, for what `install-phone` would refuse later:
  another model, two phones, a phone running from slot B without
  `--reinstall`, and a bootloader that reports one slot's version only
  (below). `install-phone` stays the one that decides.
- **The bootloader's two slots (G4).** Decided 2026-11-10 (plan D4): on a
  first install the installer measures the other slot itself, in
  `tools/install-phone`; that is being built separately. Until the
  `install-phone` this script runs does it, a phone that reports only the
  current slot's version stops at step 3. The stop says a rerun will stop
  again, offers two safe ways on (the next release, or an issue) and
  prints no option and no command: `--bootloader-slots-match VERSION`
  stays an option of the tool, for a version someone has read from the
  phone, and the stop doesn't hand it out. `slots_check` is the one
  function to change when `install-phone` measures.
- **Step 5** first looks whether anything already answers at the phone's
  USB address: the phone being installed is in Fastboot Mode and can't, so
  whatever does is another phone, and the install stops until it is
  unplugged (before the owner's questions, and again just before the
  write). Then it asks the owner's questions once and feeds them to
  `install-phone` on standard input, for the dry run with the codename
  filled in (a dry run writes nothing) and for the real run with the
  codename the owner typed. Nothing typed is put in a file, an argument or
  the record. The name rules are read from `install-phone` itself, so the
  two can't disagree. The git name and email are left empty. Before each
  of the two runs the installer checks that the one phone in Fastboot Mode
  is still the one step 3 looked at, and hands `install-phone` that serial.
- **Step 6** adds the connection of §5a, which [INSTALL.md](INSTALL.md)
  step 5 gives word for word (a test compares them). Without
  NetworkManager it says which address to set and stops. A connection of
  that name already saved is left as it is; if it is a shared one, the
  installer says so.
- **Step 9, the camera's Python modules.** `tools/extract-camera-data`
  needs `unicorn` and `pyelftools`. They are code that `phone-provision`
  then runs as the owner, so they are fetched only by exact version and
  SHA-256, from `tools/camera-requirements.txt`, with
  `pip install --require-hashes --only-binary :all:`: pip refuses a file
  whose digest isn't in the list. The prompt names the versions. Enter or
  `yes` fetches; only a typed `no` goes on without the cameras and is
  recorded (`camera_tools=skipped`); anything else asks again. A fetch
  that fails stops the step with how to try again and how to go on
  without, records nothing, and adds no firmware, so an install never ends
  "ready" without cameras the owner asked for. The digests are the ones
  pypi.org's index lists for those files (compared 2026-11-10). `unicorn`
  is listed for Linux on 64-bit Intel/AMD and 64-bit ARM, with glibc or
  musl, and `pyelftools` needs Python 3.10 or later; on another system
  pip finds no file with a listed digest, and the step stops (§9).
- **Step 9** checks the zip's SHA-256 again just before it is unpacked:
  days can pass between steps 4 and 9. `run_provision` is the one function
  that knows `phone-provision`'s command line, and `tests/install-guided`
  hands exactly those arguments to the real tool's `--dry-run`.
- **Step 10** stops `omamobile-modem` first because `reboot-to` stops no
  unit (AGENTS §2). The stop's result isn't used: it ends "failed" today
  even when it worked (#532).
- **The waits** (Fastboot Mode after the adb restart, the first start, the
  restart, systemd settling) are measured on the clock, not in passes of
  their loops: a pass lasts as long as its SSH attempts, and one that
  times out takes seconds, so a count of passes made "20 minutes" last up
  to an hour. A test gives the stand-in SSH a three-second delay.
- **Step 11** waits until systemd has finished starting (three minutes at
  most), then shows each row of the report in plain words. A failed
  required row fails the install and keeps the report. Rows that failed
  without being required are counted in the closing line ("ready, with N
  thing(s) not working") and are not all put down to the release: a row
  may be a fault. The report is made to name no phone, but its "new dmesg
  errors" row quotes the phone's messages, and the installer says to read
  that row before posting the file.

**What each stop says.** No stop ends with a fixed reassurance. Each ends
with what is true of the phone at that moment, read from the record:
nothing has been written; an earlier write began and didn't finish, so
what was on the phone may already be erased; or Omarchy Mobile is written
and what was done stays done. A stop that a rerun can get past adds "Run
this command again to go on from here"; one that a rerun can't get past as
things are (another model, another phone than the record's, slot B, the
bootloader slots, another release's record, a phone that tells no serial,
a failed required check) doesn't, and its own text says what has to
change. A write that fails partway has its own message: the data may be
gone, Android on slot A is untouched but may ask for a factory data reset,
and running the command again writes the same things again, whole.

## 3. The record

`~/.local/state/omamobile-install/<codename>/state` (`--state DIR`), mode
600; the default folder is made with mode 700, and a folder given with
`--state` keeps its own mode. `KEY=value` lines, read as data and never
sourced, rewritten whole (to a new file, then renamed) after each step.

```
format=1
codename=cheetah
release=2026.11.15
started=2026-11-15T14:02Z
warning=acknowledged 2026-11-15T14:02Z for release 2026.11.15
phone=<sha256 of the fastboot serial>
factory=done
factory_build=CP2A.260705.006
factory_name=cheetah-cp2a.260705.006-factory-<8 hex>.zip
factory_page=https://developers.google.com/android/images#cheetah
factory_size=<bytes>
factory_sha256=<64 hex>
factory_zip=/home/alex/Downloads/cheetah-cp2a.260705.006-factory-<8 hex>.zip
write=done
network=done (added omamobile-phone)
first_start=done
backup=done
backup_dir=/home/alex/omamobile-backup/cheetah-radio-backup-20261115-1421
camera_tools=skipped
provision=done
restart_from=<the boot id before the restart>
restart=done
check=passed
finished=2026-11-15
```

It holds no PIN, password hash, Wi-Fi name or key, and not the serial
number itself. It does hold `phone`, the SHA-256 of the serial, unsalted:
that is a stable identifier of the phone, so the record is private like
the radio backup, and the installer says not to attach it to an issue.
Beside it, `report.json` is the last `phone-smoke --json`.

**How a rerun decides:**

1. No record: a new install.
2. A record for another model (`codename`): refused.
3. A record with `finished`: it says when the phone was installed and
   stops, running nothing. `--start-over` forgets the record (never the
   backup or the zip).
4. A record for another release: it stops and says so. An install is
   finished with the download it was started with.
5. A record without an acknowledged `warning`: the warning is shown, first.
6. Before the write is done, a record whose `phone` is not the connected
   phone's: it stops, and says which phone is which. Nothing was sent to
   the one connected. If a write had begun, the other phone may be
   half-written and is the one to plug back in; `--start-over` is offered
   with what it forgets (that install) and when it is right.
7. After the write, a phone answering over USB SSH whose serial doesn't
   digest to the record's `phone`: it stops (§3a).
8. Otherwise each step looks at its own key, as the table's last column
   says. `write=started` with no `done` means a write stopped partway: the
   phone step says so, and the write runs again, whole (`install-phone`'s
   writes are the same each time). What the record says of the factory
   image (size, SHA-256, Google's page) is checked against the same
   patterns again before it is used.

`--status` prints the record in words. `--dry-run` goes as far as
`install-phone --dry-run`, shows the connection it would add, and records
nothing. A dry run reads the phone in Fastboot Mode (the three queries),
sends nothing over adb or USB SSH, and looks for a newer build index on
omamobile.org unless `--offline`.

### 3a. Which phone answers

A serial pinned in Fastboot Mode says nothing about who answers at
172.16.42.1 afterwards: on a desk with two phones that run Omarchy Mobile,
or with a record left by an install that was given up, the steps after
the write could back up, provision and restart another phone, and file
its radio backup as this one's.

So, twice over:

- **Before the write**, nothing may answer at the USB address (step 5).
- **Before each SSH step** (the first start counting as finished, the
  backup, provisioning, the restart and its return, the check) the
  installer runs one read-only script on the phone that answers. It finds
  the serial the bootloader handed the kernel (`androidboot.serialno` in
  `/proc/bootconfig`, else on `/proc/cmdline`, else the device tree's
  `serial-number`), and prints its SHA-256, so what crosses the link is
  what the record holds (for tidiness, not secrecy: the computer read the
  serial from fastboot in step 3). The digest must equal the record's
  `phone`. Another phone gets nothing else: nothing is copied from it,
  put on it or restarted. A phone that shows no serial in any of the
  three places stops the install too, with an issue link: the installer
  won't touch a phone it can't be sure of.

Checked on a Pixel 7 Pro (§8 step 0, 2026-11-10): the serial is in
`/proc/bootconfig`, the first place looked, and its digest equals that of
the serial fastboot reports. Other phones get the same read-only step
before their first guided install. What this doesn't close: a cable moved between the identity check and the
tool's own SSH calls a moment later; `nv-backup` and `phone-provision`
would need to take the expected digest themselves.

## 4. Every question

Asked in this order; a rerun asks only those of the steps left. An empty
answer where "Enter" isn't offered, or the end of input, stops the install
without changing anything.

| Step | Question | Accepts |
| --- | --- | --- |
| 2 | `Type yes to go on, or press Enter to stop:` | `yes` only |
| 3 | `Press Enter when that is done, to check the phone again:` | Enter |
| 3 | `Press Enter to restart the phone into Fastboot Mode:` | Enter; then `adb reboot bootloader` |
| 4 | `Press Enter to open Google's page:` | Enter |
| 4 | `Press Enter when the download has finished, or type where you saved the file:` | Enter (looks in Downloads) or a path; asked again until the file's size and SHA-256 match |
| 5 | `Your user name on the phone (lower-case, for example alex):` | `install-phone`'s `USERNAME_RE`, not reserved |
| 5 | `A PIN or password to unlock the phone (digits only gives a PIN pad):` | not empty; not shown |
| 5 | `The same again:` | equal |
| 5 | `The phone's name [<user>-phone]:` | `install-phone`'s `HOSTNAME_RE` |
| 5 | `Time zone [<this computer's>]:` | a zone in `/usr/share/zoneinfo` |
| 5 | `Wi-Fi network name (Enter to skip):` | at most 32 characters |
| 5 | `Wi-Fi password (Enter if it has none):` | 8 to 63 characters; not shown |
| 5 | `Type the phone's codename (<codename>) to write it now, or press Enter to stop:` | the codename, passed to `install-phone` as typed |
| 6 | `Press Enter to add it, or type no to set it up yourself:` | Enter or `yes` adds; anything else stops |
| 9 | `Press Enter to get them, or type no to go on without the cameras:` | Enter or `yes` fetches the pinned unicorn and pyelftools from pypi.org into `~/.cache/omamobile-venv`; `no` goes on without; anything else asks again |

**The warning** (step 2), shown once, before the unlock steps and before
any write:

```
Read this once. It is the only warning; nothing will ask again.

1. The phone is erased. Everything on it is lost: photos, messages, apps,
   accounts and two-factor codes. Copy off what you want to keep first.
   If its bootloader is still locked, unlocking it (the next step) is what
   erases it, before anything of Omarchy Mobile is written.

2. Omarchy Mobile replaces Android as the phone's system. There are no
   Google apps and no Play Store, and Android apps don't run on it. This
   release is a <label>: some things a phone normally does
   are missing or unfinished. The list for this phone:
   https://omamobile.org/devices/<codename>

3. You can go back. Android stays on the phone, unused, as a quick way
   back, and Google's own tools can put the phone back as it was sold.
   INSTALL.md, "Going back to Android", has the steps.
```

What this release lacks is a link, not text taken from the release notes:
the notes' "Known issues" are written for developers, and a list for this
screen needs writing first (§9).

**On Google's page** (step 4) the installer says: accept Google's terms,
find the row for the build, click "Link" and save the file, with the
build id, the file's name and its size.

Every other message is in `tools/install-guided`; `tests/install-guided`
checks that each question above is in this file.

## 5. The build index

`device/<codename>/factory-builds.json`, format 1, newest build first:

```json
{
  "format": 1,
  "codename": "cheetah",
  "updated": "2026-11-10",
  "builds": [
    {
      "build": "CP2A.260705.006",
      "bootloader": "<require version-bootloader>",
      "baseband": "<require version-baseband>",
      "zip": "cheetah-cp2a.260705.006-factory-<8 hex>.zip",
      "url": "https://dl.google.com/dl/android/aosp/cheetah-cp2a.260705.006-factory-<8 hex>.zip",
      "page": "https://developers.google.com/android/images#cheetah",
      "sha256": "<64 hex>",
      "size": 0,
      "tested": true,
      "tested_with": "2026.11.08"
    }
  ]
}
```

- **Metadata only.** `url` is recorded for the day D2 allows a download; the
  installer never fetches it. `page` is what it opens.
- **Read as data, every field against a pattern.** `url` must be on
  `dl.google.com` and end in the zip's name; `page` must be Google's factory
  images page; the zip's name must be `<codename>-<build>-factory-<8 hex>`
  with the first eight digits of its SHA-256; a tested build names the
  release it was tested with. A file that breaks a rule is refused whole.
- **Signed by the release key, two ways.** In a bundle, the copy is covered
  by the bundle's signed `SHA256SUMS`. A newer copy may be published as
  `pkgs.omamobile.org/releases/<codename>/factory-builds.json` with a
  detached `factory-builds.json.sig` (`tools/factory-index sign`); the
  installer uses it only when the signature is by a key `install-phone`
  pins and its `updated` is later than the local one. `--offline` skips the
  lookup. A missing or refused published copy is not an error.
- **The match: both versions, or nothing** (decision D-a, applied as the
  safe default). The build whose bootloader and baseband both equal the
  phone's is used; an exact build that isn't marked tested is used with a
  line saying so. There is no fallback to a build with the same bootloader
  and another baseband: the plan's §6.2 allows one "only for builds the
  index marks tested with that pair", and the index has one `tested` mark
  per build, earned with that build's own baseband. A phone whose pair
  isn't listed stops and is asked to update Android first (or to open an
  issue so the build can be added). A fallback can come back when the
  index records tested pairs.
- **A match is of two versions, not of a build.** Fastboot tells the
  bootloader and the baseband; builds that share both (carrier variants)
  can't be told apart. The installer says "matches", uses the first such
  build in the file, and names the others; `factory-index check` lists
  such groups for the maintainer.

`tools/factory-index add [-d CODENAME] [--tested RELEASE] FACTORY.zip` adds
a build from a factory zip on the maintainer's computer: the name, size and
SHA-256, and the board, bootloader and baseband from `android-info.txt`
inside its `image-<codename>-<build>.zip`. `tested`, `untested`, `check`
and `sign` do what they say.

Checked against two real cheetah factory zips (2026-11-10): the zip's name
carries the first eight digits of its SHA-256; it holds one directory with
`image-cheetah-<build>.zip`, whose `android-info.txt` has `require
board=`, `require version-bootloader=` and `require version-baseband=`;
the bootloader and radio image names agree with them; and for one of the
two the versions equal a saved `getvar all` of a phone on that build. Not
checked: Google's page itself (the `#<codename>` anchor, the "Link"
column) and the download address `https://dl.google.com/dl/android/aosp/<name>`,
which were not fetched.

### 5a. The USB connection

Decided 2026-11-10 (plan D10): **a plain link, not a shared one.**

```
nmcli connection add type ethernet con-name omamobile-phone match.driver cdc_ncm \
  ipv4.method manual ipv4.addresses 172.16.42.2/24 ipv4.never-default yes ipv6.method disabled \
  connection.autoconnect-priority -100
```

- `ipv4.method manual` with the computer's address on the phone's USB
  subnet, and `ipv4.never-default yes`: no DHCP or DNS server, no
  forwarding, no NAT, no default route through the phone. The earlier
  profile (`ipv4.method shared`) started all three on the owner's computer
  for a link the install only uses for SSH.
- `connection.autoconnect-priority -100`: below every connection the owner
  has saved (0 unless changed), so it never wins over one of theirs.
- `match.driver cdc_ncm`: the narrowest match available before the phone
  has started. NetworkManager matches a connection by interface name,
  driver, kernel command line, the port's path, or the interface's
  hardware address (`802-3-ethernet.mac-address`); it has nothing for a
  USB vendor, product or product string. The interface's name isn't known
  in advance, the path is whichever socket the cable is in, and the
  address is the phone's own: since `omamobile-device-cheetah` 0.1.49 the
  gadget keeps one locally administered pair per phone, made on the phone
  at its first start, so nobody can know it before that start, and the
  first seconds of every boot (the initramfs's gadget) still use a random
  one.

**What it costs, and what the prompt says** (step 6 shows the command and
this, before the question): the computer gets one address on the link and
nothing else changes; the phone gets no internet through the cable and
uses its Wi-Fi; another `cdc_ncm` device (the Ethernet port of some USB-C
docks and adapters, a phone sharing its internet over USB) that has no
saved connection of its own would be given this one, with that address
and no internet, until the owner gives it its own; where one of the
owner's connections fits a device, theirs is used; it stays saved; and how
to delete it.

**Does any step need the phone to reach the internet through the cable?**
None found, by reading (2026-11-10): the guided installer's own SSH
commands, `tools/nv-backup`, `tools/phone-provision` and
`tools/phone-smoke` read and write local files only (no `pacman -S`, no
fetch on the phone; the firmware is extracted on the computer and pushed);
`omamobile-firstboot`'s essential steps (the user, SSH keys, services and
firewall, login) are local, its `done` marker doesn't wait for the
optional ones, and of those the pacman keyring is made from the image's
own keyrings (its test seeds an offline clock first), while Omarchy's
setup leaves that install a package are each for hardware a phone doesn't
match. Omarchy's side was read in the pinned 4.0.6 package, the one
`rootfs/packages.pinned` names (by the second review, 2026-11-10). One
step there does try the network: `omarchy-provision-user` runs
`install/user/mise-work.sh`, which runs `mise use -g node@latest` and goes
on with "Node.js install deferred (no network)" when that fails. With the
shared profile that fetch went through the cable; with a plain link, on a
phone whose owner gave no Wi-Fi, it has to time out first. How long that
holds the first start can only be seen on a phone (§8 step 5). The
camera's modules are fetched on the computer. What else changes for the
owner: without Wi-Fi the phone has no internet during or after the
install, so its clock isn't set from the network and `omarchy update`
needs Wi-Fi.

**What could not be narrowed, and what could later.** Not before the first
start: see `match.driver` above. After the first start the installer could
read the gadget's host-side address (over SSH from the phone, or from the
interface that carries 172.16.42.2) and pin the saved connection to it,
which would end the driver match's reach to docks. That is not built: a
wrong pin cuts the only link to a phone that has just been erased, a
reinstall makes a new pair (the old pin would then match nothing), the
initramfs's first seconds use another address, and none of it can be
tried against a real NetworkManager from the tests. §8 step 8 is the
maintainer's read-only look at what would be pinned.

Left as they are, and to be decided separately: the phone's side still
names 172.16.42.2 as a last-resort gateway
(`omamobile-device-cheetah`'s `20-usb-gadget.network`, with a comment that
describes the shared profile); with a plain link that route goes nowhere,
at the lowest priority. A connection saved from the earlier guide keeps
sharing until its owner replaces it; the installer leaves it alone and
says what it is.

## 6. Descriptor keys

| Key | Example | Meaning |
| --- | --- | --- |
| `INSTALL_KEYS_FASTBOOT` | `with the phone off, hold Volume Down, then also hold Power, until Fastboot Mode appears (up to about 20 seconds)` | How this phone's keys reach Fastboot Mode, as a phrase that ends a sentence. Without it the installer points to the phone's page |
| `INSTALL_KEYS_RESTART` | `hold Power for about 30 seconds, then press it again` | How its keys force a restart |
| `INSTALL_FREE_GB` | `35` | Free disk space the install needs on the computer. Without it nothing is checked |

`NV_PARTS` is `nv-backup`'s; a device without it can't finish a guided
install. `tools/phone-provision` knows cheetah and raven only.

## 7. What the tests cover

`tests/install-guided` runs the real `install-phone` against a fake
`fastboot`, with stand-ins for `adb`, `nmcli`, `curl`, `xdg-open` and the
phone's side of SSH, and stubs for `nv-backup`, `phone-provision` and
`phone-smoke`; `ssh` and `rsync` on its path only record that they were
called, and any call fails the test. The stand-in phone runs the
installer's own "which phone are you" script on files that stand in for
`/proc`. It covers a whole install in order; the dry run and exactly what
it calls; each state of the phone, the warning before the unlock steps,
one phone on adb; a phone swapped between each pair of looks in Fastboot
Mode (both of the installer's checks and `install-phone --serial`);
another phone at the USB address before the write; a stale record and
another phone at each step after it; the index (both versions or
nothing) and the factory image; a failure at each step followed by a
rerun; what each kind of stop says; the record; the camera's modules
(consent, `no`, a failed fetch, a list without digests); a missing program
at step 1; the real `tools/phone-provision` given the installer's exact
arguments in `--dry-run`; a bundle layout; and the script's own shape.
`tests/factory-index` covers the maintainer tool and the reader's refusals.

A stub for one of our own tools hides an option the real tool doesn't
have: the reviewed version of this installer passed a `phone-provision`
option that only an open pull request had, with every test green. The
real-tool test above is what keeps the two from drifting again.

## 8. First run on a phone: the maintainer's runbook

Step 0 has run (its result is below the table); nothing else has. Each
step is the maintainer's to run or approve. The connection of step 4 has
never been added to a real NetworkManager: that step is where it is first
tried.
Before step 3: stock boots from slot A, and `tools/nv-backup --check`
against the current backup passes. Steps 0 and 1 change nothing.

| # | Command | Expect | Stop if | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| 0 (done, below) | With the phone running Omarchy Mobile on USB: `tools/phone-ssh 'grep -c androidboot.serialno /proc/bootconfig; tr " " "\n" < /proc/cmdline \| grep -c "^androidboot.serialno="; test -e /proc/device-tree/serial-number && echo dt'`. Then compare digests, printing neither serial: on the phone `sed -n 's/^androidboot\.serialno[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' /proc/bootconfig \| tr -d '\n' \| sha256sum`, and later, in Fastboot Mode, `fastboot devices \| awk '{printf "%s", $1}' \| sha256sum` | at least one of the three places has the serial; the two digests are equal | none of the three has it, or the digests differ: §3a's assumption is wrong, and the install would stop at step 7. Don't start it; fix the script first | none needed (read-only) | none |
| 1 | `tools/factory-index add -d cheetah --tested <release> <the phone's factory zip>`, then `tools/factory-index check -d cheetah` | one build, with the bootloader and baseband `fastboot getvar` reports; the printed SHA-256 equals Google's page | the tool refuses the zip | `git checkout device/cheetah/factory-builds.json` | none (laptop only) |
| 2 | `tools/install-guided --dry-run` with the phone in Fastboot Mode | the warning first; steps 1 to 5 pass; the `would run` lines are slot B's five images and `userdata`, each with `-s` and the phone's serial; the connection it would add is §5a's; "nothing was written" | any other partition in the plan; the phone step misreads the phone's state; it stops at the bootloader slots (expected on the 7 Pro until `install-phone` measures them: then this runbook waits for that, or the maintainer reads the other slot and passes `--bootloader-slots-match`) | none needed (read-only) | low |
| 3 | `tools/install-guided` (with `--reinstall` if the phone runs Omarchy Mobile) | the warning once; nothing answering at 172.16.42.1; the zip found in Downloads; the codename asked after the dry run; then the writes | `install-phone` stops: read its message, the phone stays in fastboot. "Something already answers at the phone's USB address": unplug the other phone | `fastboot --set-active=a`, as INSTALL.md | medium (erases `userdata`, as every install) |
| 4 | at the connection question, read the command and its description, press Enter. This is the first time this profile meets a real NetworkManager. On a computer that already has `omamobile-phone` saved the question doesn't come: to try the new profile there, `nmcli connection delete omamobile-phone` before step 3 | `nmcli connection show omamobile-phone` has `ipv4.method manual`, `ipv4.never-default yes`, priority -100; `nmcli device` shows it on the phone's link; the phone answers; `sysctl net.ipv4.ip_forward` and the firewall's rules are as before | another saved connection takes the phone's link (the phone then doesn't answer); this computer's network changes in any other way | `nmcli connection delete omamobile-phone` | low |
| 5 | let it run: first start, backup, firmware | "the first start has finished" within minutes, with no internet on the phone but its Wi-Fi; `verified against the phone` per partition; each push `verified` | the first start doesn't finish and `/var/log/omamobile/firstboot.log` shows a step waiting for the network (§5a's reading is then wrong: say so, and the profile goes back to the maintainer); "is not the phone this install wrote" or "doesn't tell its serial number" (step 0 should have caught it); the backup names a writable or mounted partition; provisioning fails twice | rerun `tools/install-guided`; the backup only reads | low |
| 6 | the restart and the check | the phone comes back; every required row `[ok]`; "Your phone is ready" | the phone doesn't come back in ten minutes (Power held 30 s); `journalctl -b -1 -u omamobile-modem` shows the modem was up and not stopped | rerun `tools/install-guided` (it only checks again) | low |
| 7 | on a second run, unplug the cable once during step 5's wait, and rerun; and once, with a second phone that runs Omarchy Mobile on the cable instead, rerun | the first goes on from that step and `--status` agrees; the second stops with "is not the phone this install wrote" and `journalctl` on the second phone shows one SSH login and no change | it asks to write again; the second phone is backed up, provisioned or restarted | `--start-over` | low |
| 8 | read-only, for §5a's follow-up: `nmcli -g GENERAL.HWADDR device show <the phone's link>` on the computer, before and after a restart of the phone | the same address after the restart (the gadget's saved pair), another one for the first seconds | it changes at every restart: pinning by address is then not possible | none needed | none |

Record the results here with the date and `uname -r`, with no serial or
hardware address in them.

**Results.**

- **Step 0, done 2026-11-10** on the maintainer's Pixel 7 Pro,
  `7.3.0-rc6-omamobile-push1-gc7fb37460f84`, read-only: the serial is in
  `/proc/bootconfig` (`androidboot.serialno`); it is not on
  `/proc/cmdline`, and there is no `/proc/device-tree/serial-number`. Its
  SHA-256 equals that of the serial in a saved `fastboot getvar all` of
  the same phone (compared by digest; neither was printed). So the
  identity check's first source is right on this phone.

## 9. Open for the maintainer

- **G4.** Decided (D4), not yet in `tools/install-phone`; see §2. When it
  lands, `install-phone` asks one more question in a first install, and
  the guided installer has to ask it and feed the answer; `slots_check`
  then stops only where `install-phone` still asks for the option.
- **D3.** An exact build not marked tested is used with a note. The
  fallback to another baseband is off (§5) until the index records pairs.
- **D6.** The index is looked for at
  `releases/<codename>/factory-builds.json`; nothing uploads it there yet
  (`tools/release-upload` is unchanged), and a signed copy never expires,
  so an old one that is newer than the local one can be replayed. Low
  impact: it is bound to the codename, and a bad entry can only fail a
  match or a hash.
- **The camera's modules.** Of the four builds of `unicorn` listed in
  `tools/camera-requirements.txt`, only the one for Linux on 64-bit
  Intel/AMD with glibc has been installed and run; the real `pip` path has
  not run from the installer at all (the tests use a stand-in). A camera
  folder that already imports both modules is used as it is, pinned or
  not, and `tools/extract-camera-data`'s own header and INSTALL.md's
  by-hand step still give the unpinned command. And there is no simple way
  yet to add the cameras to a finished install whose owner typed `no`:
  running `phone-provision` again replaces the modem's files under a modem
  that may be running, so it isn't offered; the prompt says so.
- **The warning's list of what is missing** is a link (§4).
- **The SSH key.** M1 needs one and stops without it; the plan's own key
  for the installer is M2/M3.
- **A write that stopped, and a lost record.** `write=started` on a rerun
  always asks for Fastboot Mode again, even if the write had in fact
  finished. Looking for the phone over SSH first would save a second
  erase, but on a reinstall the system from before answers with the same
  serial, so the digest alone can't tell the two apart.
- **Running as root** isn't refused.
- **Narrowing the connection to this phone** after the first start (§5a).

## 10. Before it is a bundle's `install`

`tools/install-guided` finds its files when it sits at the top of a bundle
(`device.conf` and `images/` beside it, the tools in `tools/`), and the
tests run it that way. No bundle ships it yet. That switch (`make-bundle`,
`tools/release`, INSTALL.md leading with it) waits for:

1. §8 run on a Pixel 7 Pro, with the results recorded here (date,
   `uname -r`);
2. G4 in `tools/install-phone`, so a first install on a 7 Pro can finish
   without an option nobody should have to pass;
3. `device/cheetah/factory-builds.json` committed, with the maintainer's
   word on which builds are tested.
