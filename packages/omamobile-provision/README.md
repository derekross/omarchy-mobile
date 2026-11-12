<!-- SPDX-License-Identifier: MIT -->
# omamobile-provision

Provisioning on the phone itself: stage L4 of
[the install link](../../docs/INSTALL-LINK-PLAN.md) (its section 6). The
owner's computer hands the phone Google's factory image; the phone extracts
what it needs from it and installs it. This package is what runs then. It
is `tools/phone-provision --first-install` with the pushes over SSH
replaced by local installs.

It is not in any root image yet (stage L5), nothing runs it yet (the link's
daemon is stage L2), and it has not run on a phone (runbook step R1).

## What it installs

| Path | Mode | What |
| --- | --- | --- |
| `/usr/bin/omamobile-provision` | 755 | the provisioning command (Python, standard library only) |
| `/usr/bin/phone-smoke` | 755 | runs the packaged `phone-smoke`, adding `--here` and the descriptor's codename when they are missing |
| `/usr/lib/omamobile-provision/extract-vendor-firmware`, `extract-vendor-chroot`, `extract-fingerprint-vendor`, `extract-camera-data` | 755 | the repository's `tools/extract-*`, unchanged |
| `/usr/lib/omamobile-provision/phone-smoke`, `lib/usage.sh` | 755, 644 | the repository's `tools/phone-smoke` and the help it loads, unchanged |
| `/usr/share/omamobile/provision/version`, the README and the licence | 644 | |

No unit, no pacman hook, no install script, no file under `/etc`: installing
or updating the package runs nothing and starts, stops and enables nothing.

**One copy of each tool.** The tools live in `tools/` and nowhere else in
the repository. `./stage-tools` copies them into `tools-staged/`
(gitignored) with their checksums; `./install` runs it whenever the
repository is around the package and refuses a staged copy that fails its
checksums. `tools/build-packages`, `tools/phone-install-package` and
`tools/repo-build` copy the package directory alone into their build, so
each runs `stage-tools` first. No tool was changed for the phone.

## The command

```
omamobile-provision first-install [--development] [--progress-fd N] [--result FILE] FACTORY.zip NV-SUMS
omamobile-provision extract -o OUTDIR FACTORY.zip
omamobile-provision listing DIR
```

`first-install` is what the link's daemon runs, as root, with the fixed
path of the verified factory image and of the pending NV checksums (one
`<sha256>  NAME.img` line for each of the descriptor's `NV_PARTS`). The
device comes from `/usr/share/omamobile/device.conf`; only `cheetah` is
supported. Its steps, in order:

| Step | To | How |
| --- | --- | --- |
| `firmware` | `/usr/lib/firmware/updates` | merged |
| `sensors` | `/usr/share/omamobile/sensors/registry` | replaced |
| `gnss`, `modem` | `/usr/lib/omamobile-vendor/<profile>/{root,MANIFEST,SOURCE,STUBS}` | replaced |
| `fingerprint` | `/usr/lib/omamobile-fp/{root,MANIFEST,SOURCE}` | replaced |
| `camera` (optional) | `/usr/lib/firmware/omamobile/camera/*.bin` | merged |
| `modem-data` | `/var/lib/omamobile-vendor/modem/props.conf` (mode 600: the board id from `androidboot.cdt_hwid` in `/proc/bootconfig`; other lines kept; the value is never printed), `/usr/lib/omamobile-provision/SOURCE` (the build and the image's SHA-256), then `/etc/omamobile/modem-nv.sha256` (mode 644) | written aside, synced, renamed, read back |

Everything is root's, with the modes the extraction gave it, as
`phone-provision`'s `tar` leaves it. All of the extraction runs before the
first install, so an image the tools refuse installs nothing.

**What it never does.** It starts, stops, enables and restarts nothing; it
loads no module; it opens no partition and no device node; it never touches
`persist`, `mfg_data`, the modem's NV partitions or the NV overlay. The
firmware loads at the next boot, and `omamobile-fp` and the modem start
there by their own units. `/etc/omamobile/modem-nv.sha256` is its last
write before the result file, so the modem has nothing to start from until
everything else is in place.

**Progress** goes to `--progress-fd` (default 1), one JSON object per line
in the shape of the link's `progress` message:
`{"what":"provision","step":"gnss","done":7,"total":13}`. The log is on
stderr.

**The result file** (default
`/var/lib/omamobile/install-link/provision.result`, mode 600; written
aside, synced, renamed) is its last act:

```
{"version":1,"ok":true,"failed":null,"optional_failed":["camera"],
 "steps":[{"step":"firmware","state":"ok"}, ... {"step":"camera","state":"failed"}, ...]}
```

`state` is `ok`, `failed` or `skipped` (not reached). A run that was killed
leaves no result file: a start removes the one before it.

**Exit status:** 0 every required step `ok`; 1 a required step failed (the
result names it); 2 refused, with nothing written.

**The camera step** is optional (`PROVISION_OPTIONAL`, default `camera`).
When it fails it is run once more, after every other step and before the
checksum file; when it fails twice the run is still a success, `ok` is
true, and `optional_failed` and the step's state say so (plan section 6.6).

**Not a first start.** Without `--development` it refuses unless all of
these hold, which is how this package reads "stage `firstboot-done`, not
yet `provisioned`" from the phone's files (it cannot see the daemon's
state file, whose format is stage L2's):

- `/etc/omamobile/install-link` exists (the release image's marker);
- `/var/lib/omamobile/install-link/` exists and holds no `done`;
- `/var/lib/omamobile/firstboot/done` exists;
- `/etc/omamobile/modem-nv.sha256` is absent, or already holds exactly
  NV-SUMS's lines (a run that was killed after its last write).

`--development` skips only that check, for a development phone
(`--result FILE` then says where the result goes). Replacing trees under a
running `omamobile-fp` or modem is as safe as `tools/phone-provision` is
today, no more: reboot afterwards.

## Whole or not at all

`tools/phone-provision`'s tree push removes each entry of a tree and then
moves the new one in. Here:

| Tree | How it is put in place | At every moment its path holds |
| --- | --- | --- |
| The sensor registry | Built beside its target (`.registry.omamobile-provision.new` in the same directory), every file and directory synced, read back and compared; then one `renameat2(RENAME_EXCHANGE)` with the target (a plain `rename` when there is none); then the old tree is removed | The old registry or the new one, whole. Never a mix, never nothing |
| gnss, modem, fingerprint | These share their directory with their package's own files, so the directory itself can't be exchanged. The new `root`, `MANIFEST`, `SOURCE` (and `STUBS`) are built in `.omamobile-provision.new/` inside it, synced, read back and compared, the tree also against its own `MANIFEST`. Then: an older `root` is renamed out; the other entries are renamed in; `root` is renamed in last. Every user of these trees looks for `root/` | The old tree whole; or no `root/` (the tree is not there, and its service is as inert as on a phone that was never provisioned); or the new tree whole. `root/` is never there with another generation's `MANIFEST`, `SOURCE` or `STUBS` beside it. On a first install there is no older tree, so: nothing, then the whole tree |
| firmware, camera | File by file: each written under a temporary name beside its place (`.NAME.omamobile-provision.tmp`), synced, renamed over the name, the directory synced | Each file is absent, the old file or the new file, whole. The set is **not** atomic: after a power cut some files of the tree may be new and others old or missing |
| `props.conf`, `SOURCE`, `modem-nv.sha256`, the result | Written aside, synced, renamed, the directory synced | The old file or the new, whole |

What is atomic is each rename: on ext4 (and every Linux file system) a
rename or an exchange within one directory is seen whole or not at all by
other processes, and after a crash the journal holds it or does not. What
makes that safe across a power cut is the order: every file and directory
of a staged tree is `fsync`ed before the rename that makes it visible, and
the parent directory is `fsync`ed after, before the next step.

What is not atomic:

- **The steps together.** A cut can leave the firmware installed and the
  fingerprint tree not. The services that start by themselves at the next
  boot then find each tree whole or absent, and the modem finds no checksum
  file.
- **A merged tree as a set** (above).
- **An older tree, for a moment.** When gnss, modem or fingerprint are
  installed over an older generation, a cut in the window between "older
  `root` out" and "new `root` in" leaves that tree absent until the rerun,
  not untouched. The first install has no such window.
- **The registry's other files.** It is replaced as a directory, so a file
  of an older build that the new build doesn't have goes. `phone-provision`
  leaves such a file; on a first install there is none.
- **Durability of the last step** before its directory sync returns.

A tree or file that is already exactly what this image gives is left
untouched (same inodes), so a rerun after a kill disturbs nothing a service
may have started on in the meantime.

**Temporary files.** The extraction works in
`/var/lib/omamobile/provision/work.XXXXXX` (mode 700, on `userdata`; the
tools' `TMPDIR` is inside it), removed however the run ends; a run removes
one a kill left. The staging names above live beside or inside their
targets and are removed at the end of each install and at the start of the
next run. `/var/lib/omamobile/provision/lock` keeps two runs apart.

## The extraction

The tools run as on the laptop, with two differences in how they are run,
neither in what they write:

- **Unprivileged.** As root, every tool runs as `nobody`, in its own
  session, with the working directory as its only writable place. Root
  then reads the output by descriptor without following any symlink, copies
  symlinks as symlinks, and refuses anything that is not a file, a
  directory or a symlink.
- **The inner zip, once.** `nobody` can't open the factory image (root's,
  mode 600, in a mode 700 directory), so it is handed over as an open
  descriptor, and the `image-*.zip` inside it is unpacked once into the
  working directory; the tools get that (they accept it, and each of them
  would otherwise unpack it for itself).

They run under `LC_ALL=C`. The tools sort `MANIFEST` and
`vendor-firmware.sha256` with the locale's collation, so a laptop in
another locale (`en_US.UTF-8`) writes the same lines in another order.

## For the daemon's unit (stage L2)

`ReadWritePaths=` must allow: `/usr/lib/firmware`,
`/usr/share/omamobile/sensors` (the registry is exchanged in its parent),
`/usr/lib/omamobile-vendor/gnss`, `/usr/lib/omamobile-vendor/modem`,
`/usr/lib/omamobile-fp`, `/usr/lib/omamobile-provision` (for `SOURCE`),
`/var/lib/omamobile-vendor/modem`, `/etc/omamobile`,
`/var/lib/omamobile/provision` and the result file's directory. It needs
`CAP_SETUID`, `CAP_SETGID` (to run the tools as `nobody`), `CAP_CHOWN`,
`CAP_FOWNER` and `CAP_DAC_OVERRIDE`, no network and no device.

## Tests

`test/all` (offline, no root, no phone) runs the command in a scratch root
with stand-in tools: the straight path, every refusal, every failure, the
camera step failing once and twice, and a kill at every checkpoint on a
first install and over an older generation, each followed by a rerun. With
`mke2fs`, `debugfs`, `unzip` and `readelf` it also runs the real tools on a
made-up factory image (`test/standin-factory`).

`tests/omamobile-provision` (the repository's) checks the packaged tools
against `tools/`, runs the tools' own tests on the packaged copies, and
runs the byte for byte comparison of plan section 6.2, `test/compare`: for
one factory image, the laptop's run and the phone side's run must give the
same files, modes and link targets. On a made-up image always; on real
ones when `OMAMOBILE_PROVISION_FACTORY` names them, printing only `equal`
or the names of files that differ. `test/compare --container PACKAGE` runs
the phone side in the aarch64 build container with the built package
installed.
