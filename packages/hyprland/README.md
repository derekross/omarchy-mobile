<!-- SPDX-License-Identifier: MIT -->
# hyprland (Omarchy Mobile build)

This is Omarchy's Hyprland 0.57.0-2 recipe (`hyprland` and `hyprpm`), built
for aarch64 with two changes. Hyprland gave up on a refused DPMS commit after
a single retry, and aquamarine refuses commits while a page flip is in
flight. So when a client kept rendering, DPMS off was lost: Hyprland
reported the screen off, but the CRTC never turned off. See
`device/cheetah/DISPLAY-PLAN.md`, D3b-1.

| File | What it is |
| --- | --- |
| `PKGBUILD` | Omarchy's `pkgbuilds/hyprland/PKGBUILD` at `347f3d791489` (omacom-io/omarchy-pkgs), changes in its header |
| `nvidia-egl-teardown.patch`, `wl-output-global-grace.patch`, `monitor-rule-vrr.patch` | Omarchy's patches from the same commit, unchanged (what they fix: their comments in `prepare()`) |
| `0001-dpms-keep-retrying-a-refused-dpms-commit.patch` | The Omarchy Mobile change to `src/output/Monitor.cpp` |
| `0002-render-hold-the-last-frame-across-a-rotation.patch` | The Omarchy Mobile change to `src/render/Renderer.cpp` and `src/render/OpenGL.cpp` (the rotation hold, below) |

## What differs from Omarchy's `hyprland` 0.57.0-2

- The DPMS patch. A refused DPMS commit is retried every two frames for up
  to a second instead of once.
- The rotation hold (0002). After a transform change the output keeps its
  last frame until every mapped layer surface has drawn at its new size
  (its buffer too, and a second buffer or 50 ms more), or 500 ms; layers
  and the active workspaces get their frame callbacks once per refresh
  meanwhile. Then the new frame turns in on Android's (0.2, 0, 0, 1) curve,
  over 283 ms for a quarter turn and 383 ms for a half turn, and the old one,
  kept where it was on the glass, turns with it and fades out over 116 ms on
  Android's alpha-out curve (0.57, 0, 0.71, 0.43). On a Pixel 7 the holds took
  106 to 228 ms; without the patch the old buffers showed stretched for
  200 ms to a second. It is off unless `OMAMOBILE_ROTATION_HOLD=1` is in
  Hyprland's environment (read once at startup): `omamobile-device-panther`
  sets it in `environment.d`, and the other phones rotate as before until
  it has run on them.
- `pkgrel=3.3`: the higher of Omarchy's (0.57.0-2) and Arch Linux ARM's
  (`extra/hyprland` 0.57.0-3, a rebuild for aquamarine 0.16.0 and
  hyprgraphics 0.6.0) release, plus `.1`, so it sorts above both; `.2` for
  the rotation hold, since 3.1 is published; `.3` for the half turn's
  383 ms and the alpha-out curve, since 3.2 is published.
- `arch=(aarch64)` only.
- `build()` runs the two cmake steps of `make release` itself:
  - with Arch's `-DCMAKE_SKIP_RPATH=ON` (Arch's PKGBUILD seds it into the
    Makefile);
  - with the job count from `MAKEFLAGS` (default 4) instead of `nproc`.
- Same package names, `provides=(wayland-compositor)`, dependencies and
  split as Omarchy's, so it replaces it in place. Nothing conflicts. The
  library sonames (`libaquamarine.so`, `libhyprgraphics.so`, ...) are
  versioned by makepkg from the libraries it was built against, so the
  build must run against the current Arch Linux ARM libraries (below).

On 0.56.2 we also carried Omarchy's `software-renderer.patch`, the backport
of hyprwm/Hyprland#16343. 0.57.0 includes that change
(`StringUtils::containsCaseInsensitive` in `src/render/GLRenderer.cpp`), and
Omarchy dropped the patch, so it is gone here too.

## Status

**0.57.0-3.1, built natively on the phone (2026-11-02), not installed yet.**
Arch Linux ARM moved `extra` to aquamarine 0.16.0 (`libaquamarine.so=15`)
and hyprgraphics 0.6.0 (`libhyprgraphics.so=5`) and dropped the old
libraries, so 0.56.2-5.1 (`libaquamarine.so=14`, `libhyprgraphics.so=4`)
could no longer be installed: the root image failed to build, and phone
updates would have failed. Omarchy's own aarch64 `hyprland` was in the same
state that day (stable still had 0.56.2-7).

The phone itself still had the old libraries installed, so this build ran in
a throwaway Arch Linux ARM root on the phone (`systemd-nspawn`, from the
official aarch64 tarball, makedepends and depends from `extra`), not in the
phone's own system; see "Building on the phone" below. It took about
24 min at `-j4` with the session running, on the charger. The package
depends on `libaquamarine.so=15` and `libhyprgraphics.so=5`; its soname
list is the same as `extra/hyprland` 0.57.0-3's.

Checked offline:

- The source tarball's sha256 matches Arch's and Omarchy's (`82d006ba…`).
- All four patches apply to it with `--fuzz=0`, in the PKGBUILD's order.
  None of Omarchy's three touches `Monitor.cpp`.

Earlier: 0.56.2-5.1 was built on the phone on 2026-10-12 (about 20 min at
`-j4`) and ran there from DISPLAY-PLAN.md D3b-1b until this update.

The phone's `/etc/makepkg.conf` sets `PKGEXT='.pkg.tar.xz'`, so packages
built there end in `.pkg.tar.xz`, not `.zst`. The commands below use a glob.

`hyprpm` isn't installed on the phone, so install only `hyprland`. The
`hyprpm` split is still built and published. pacman upgrades only installed
packages, so publishing it changes nothing.

## Building

**The default needs no phone:** `tools/build-packages packages/hyprland`
builds in a clean Arch Linux ARM container on the laptop, updated to the
current repositories, so the sonames come out right by construction. It
runs under qemu-user and takes hours. The nightly `tools/repo-publish` also
builds it (`--all` includes the slow packages whose version isn't in
`out/repo` yet). If that build fails to link, refresh the base image
(`ALARM_REFRESH=1`) before blaming the PKGBUILD.

**Faster, opt-in: a clean root on the phone.** Hyprland is C++ with heavy
templates (glaze, hyprutils). On the phone (8 cores: 2× X1, 2× A78, 4× A55;
about 12 GB RAM):

- **Time:** about 24 min at `-j4` with the session running, measured on
  2026-11-02 (0.57.0). Keep it on the charger.
- **Memory:** up to about 1.1 GB per compiler process, so about 4.5 GB at
  -j4. -j8 (makepkg's `nproc` default in upstream's Makefile) leaves too
  little for a running session.
- **Disk:** the root and the build need about 5 GB on `userdata`; check
  `df -h /home` first.

makepkg writes each soname dependency with the version of the library it
found at build time. **Build against the libraries the repositories carry
now**, not whatever the phone has installed: a phone still on the old
aquamarine produces a package that depends on `libaquamarine.so=14` again.
`tools/repo-build` builds in the phone's own system with `--nodeps`, so use
it only when the phone's aquamarine, hyprgraphics, hyprutils, hyprlang,
hyprwire and hyprcursor match `extra`'s (`pacman -Q` against `pacman -Si`).
Otherwise use a clean root, as on 2026-11-02.

The root comes from Arch Linux ARM's tarball, and `pacman-key --populate`
inside it is only as trustworthy as that tarball. Use the copy
`tools/lib/alarm.sh` has already checked: every `tools/build-packages` run
verifies `~/.cache/omamobile-rootfs/ArchLinuxARM-aarch64-latest.tar.gz`
(its MD5, and a signature by the pinned build key). To check it again by
hand on the laptop:

```sh
cd ~/.cache/omamobile-rootfs
md5sum -c ArchLinuxARM-aarch64-latest.tar.gz.md5
G=$(mktemp -d); GNUPGHOME=$G gpg -q --batch --import alarm-builder.asc
GNUPGHOME=$G gpg --batch --status-fd 1 --verify ArchLinuxARM-aarch64-latest.tar.gz.sig ArchLinuxARM-aarch64-latest.tar.gz 2>/dev/null |
  grep -E '^\[GNUPG:\] VALIDSIG .* 68B3537F39A313B3E574D06777193F152BDBE6A6$'   # must print a line
rm -rf "$G"
```

Then, from the laptop (`U` is the account logged in on the phone's screen;
nothing outside its `build/` directory changes on the phone):

```sh
U=$(tools/phone-ssh "loginctl list-users --no-legend | awk '\$2 != \"root\" {print \$2; exit}'")
R=/home/$U/build/hyprland-root
N="systemd-nspawn -q --register=no --resolv-conf=replace-uplink -D $R"
tools/phone-ssh "mkdir -p $R && bsdtar -xpf - -C $R" < ~/.cache/omamobile-rootfs/ArchLinuxARM-aarch64-latest.tar.gz
tools/phone-ssh "$N bash -c 'pacman-key --init && pacman-key --populate archlinuxarm &&
  pacman -Syu --noconfirm --needed base-devel cmake glaze hyprland-protocols hyprwayland-scanner meson ninja xorgproto <the PKGBUILD depends> &&
  useradd -m builder'"
tar cf - -C packages ./hyprland | tools/phone-ssh "tar xf - -C $R/home/builder --no-same-owner"
tools/phone-ssh "$N chown -R builder: /home/builder/hyprland"
tools/phone-ssh "systemd-run --unit=x-hyprland-build --collect $N su builder -c 'cd ~/hyprland && MAKEFLAGS=-j4 makepkg -f --noconfirm'"
```

The build runs as a transient unit, so a dropped SSH connection doesn't
stop it (`systemctl status x-hyprland-build`, `journalctl -u
x-hyprland-build`). Remove `$R` when done.

**Publishing a build made outside `tools/build-packages`.** Check the
sonames first:
`bsdtar -xOf hyprland-*.pkg.tar.xz .PKGINFO | grep -o 'lib\(aquamarine\|hyprgraphics\)\.so=[0-9]*'`
must name what `extra` provides. Copy the `hyprland` and `hyprpm` files
(not `-debug`) into an empty directory on the laptop, then:

```sh
tools/build-packages --import <that directory>   # into out/repo, signed with the release key, indexed
tools/repo-publish                               # to development
```

Import the build that was tested on a phone, before the nightly publish
builds its own: otherwise the phone runs a different 0.57.0-3.1 from the
published one under the same version. (`tools/repo-push` only copies
`out/repo` to a connected phone; it doesn't publish.)

To try a build on one phone first, copy the `hyprland` file there and
install it in one transaction with the libraries it needs from `extra`:

```sh
# on the phone
sudo OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Sy
# pacman -Sp prints the libraries' download URLs, and pacman -U takes URLs
sudo OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -U ./hyprland-0.57.0-3.1-aarch64.pkg.tar.xz \
  $(pacman -Sp aquamarine hyprgraphics hyprtoolkit hyprland-guiutils)
```

Add any other installed package that `pacman -U` reports as breaking
(`hyprlock`, for example) to both lists. Then restart the session
(`systemctl restart sddm`) and check `hyprctl version` and `pacman -Q
hyprland` (expect `0.57.0-3.1`). After it's published, `omarchy update` is
the path users take.

## Pinning

`[omamobile]` comes before `[omarchy]` in the phone's `pacman.conf`
(`omamobile-device-cheetah`). pacman takes a package from the first
repository that has it, so with `hyprland` in `[omamobile]`, `omarchy update`
won't replace it, even when Omarchy ships a higher release. That means we
have to follow Omarchy's updates ourselves, and Arch Linux ARM's soname
rebuilds:

1. Take the new `pkgbuilds/hyprland` files.
2. Re-apply the header changes and set `pkgrel` to the higher of Omarchy's
   and Arch Linux ARM's plus `.1`.
3. Check that every patch still applies with `--fuzz=0`.
4. Rebuild whenever `extra` bumps a library's soname (aquamarine,
   hyprgraphics, hyprutils, ...), even with no new Hyprland: our build
   pins the old one, and `extra` drops it.

Drop the DPMS patch once upstream retries refused DPMS commits.

**`tools/repo-build`:**
- Packages are listed explicitly, so add `packages/hyprland` only when it
  should be rebuilt.
- The script recreates the database from every package file in
  `out/repo/aarch64`, so a previously built hyprland stays published.
- To unpublish it, delete its files from `out/repo/aarch64` before running
  it again.

## Rolling back

There is no older build that installs against today's libraries: 0.56.2
(ours and Omarchy's) needs the aquamarine and hyprgraphics that `extra`
dropped. A phone that hasn't updated yet keeps 0.56.2-5.1 and its libraries
until it does.

After an update, roll back every package the update moved onto the new
libraries, all in one `pacman -U`: aquamarine, hyprgraphics, and every
installed package that depends on `libaquamarine.so=15` or
`libhyprgraphics.so=5` (hyprland, hyprtoolkit, hyprlock if installed, ...),
plus hyprpm if installed. pacman refuses a partial set as a whole. Each
older version comes from `/var/log/pacman.log` and its file from the pacman
cache. Run as root on the phone (`bash rollback.sh`):

```sh
set -euo pipefail
cd /var/cache/pacman/pkg
pkgs=$( { echo aquamarine; echo hyprgraphics; pacman -Qq hyprpm 2>/dev/null || true
  pacman -Qi | awk '/^Name /{n=$3} /^[A-Z]/{f=$1}
    f=="Depends" && /lib(aquamarine\.so=15|hyprgraphics\.so=5)-/{print n}'; } | sort -u)
files=()
for p in $pkgs; do
  old=$(grep -E "\[ALPM\] upgraded $p \(" /var/log/pacman.log | tail -1 | sed -E 's/.*\((.*) -> .*/\1/')
  f=$(ls "$p-$old"-*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | head -1 || true)
  [[ -n $old && -n $f ]] || { echo "no cached older $p (${old:-not in pacman.log}): stop" >&2; exit 1; }
  files+=("$f")
done
printf '%s\n' "${files[@]}"
OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -U "${files[@]}"
echo "IgnorePkg = $(echo $pkgs)"
```

Check the list it prints before pacman's prompt, then put the printed
`IgnorePkg` line in `/etc/pacman.conf` (all of those packages, or the next
update moves them again) until a fixed build is published, and restart the
session (`systemctl restart sddm`).
