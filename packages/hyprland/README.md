<!-- SPDX-License-Identifier: MIT -->
# hyprland (Omarchy Mobile build)

This is Omarchy's Hyprland 0.57.0-2 recipe (`hyprland` and `hyprpm`), built
for aarch64 with one change. Hyprland gave up on a refused DPMS commit after
a single retry, and aquamarine refuses commits while a page flip is in
flight. So when a client kept rendering, DPMS off was lost: Hyprland
reported the screen off, but the CRTC never turned off. See
`device/cheetah/DISPLAY-PLAN.md`, D3b-1.

| File | What it is |
| --- | --- |
| `PKGBUILD` | Omarchy's `pkgbuilds/hyprland/PKGBUILD` at `347f3d791489` (omacom-io/omarchy-pkgs), changes in its header |
| `nvidia-egl-teardown.patch`, `wl-output-global-grace.patch`, `monitor-rule-vrr.patch` | Omarchy's patches from the same commit, unchanged (what they fix: their comments in `prepare()`) |
| `0001-dpms-keep-retrying-a-refused-dpms-commit.patch` | The Omarchy Mobile change to `src/output/Monitor.cpp` |

## What differs from Omarchy's `hyprland` 0.57.0-2

- The DPMS patch. A refused DPMS commit is retried every two frames for up
  to a second instead of once.
- `pkgrel=3.1`: the higher of Omarchy's (0.57.0-2) and Arch Linux ARM's
  (`extra/hyprland` 0.57.0-3, a rebuild for aquamarine 0.16.0 and
  hyprgraphics 0.6.0) release, plus `.1`, so it sorts above both.
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

## Building on the phone

Hyprland is C++ with heavy templates (glaze, hyprutils). Estimate for the phone (8 cores: 2× X1, 2× A78, 4× A55; about 12 GB RAM):

- **Time:** 30–60 min at -j4, longer if it throttles. Keep it on the
  charger.
- **Memory:** up to about 1.1 GB per compiler process, so about 4.5 GB at
  -j4. -j8 (makepkg's `nproc` default in upstream's Makefile) leaves too
  little for a running session.

makepkg writes each soname dependency with the version of the library it
found at build time. **Build against the libraries the repositories carry
now**, not whatever the phone has installed: a phone still on the old
aquamarine produces a package that depends on `libaquamarine.so=14` again.
`tools/repo-build` builds in the phone's own system with `--nodeps`, so use
it only when the phone's aquamarine, hyprgraphics, hyprutils, hyprlang,
hyprwire and hyprcursor match `extra`'s (`pacman -Q` against `pacman -Si`).
Otherwise build in a clean root, as on 2026-11-02 (as root on the phone; the
directory is the phone user's, and nothing outside it changes):

```sh
R=/home/<user>/build/hyprland-root
mkdir -p $R && bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C $R   # tarball verified as tools/lib/alarm.sh does
N="systemd-nspawn -q --register=no --resolv-conf=replace-uplink -D $R"
$N bash -c 'pacman-key --init && pacman-key --populate archlinuxarm &&
  pacman -Syu --noconfirm --needed base-devel cmake glaze hyprland-protocols hyprwayland-scanner meson ninja xorgproto <depends...> &&
  useradd -m builder'
# copy packages/hyprland to $R/home/builder/hyprland, then
$N su builder -c 'cd ~/hyprland && MAKEFLAGS=-j4 makepkg -f --noconfirm'
```

Check the result before publishing it:
`pacman -Qip hyprland-*.pkg.tar.* | grep -o 'lib\(aquamarine\|hyprgraphics\)\.so=[0-9]*'`
must name the sonames `extra` provides. Then copy the `hyprland` and
`hyprpm` files (not `-debug`) into `out/repo/aarch64` on the laptop, sign
them with the release key and rebuild the database (`tools/repo-build`'s
signing and database steps), and `tools/repo-push`. On the phone,
`omarchy update`.

To try it on one phone without the repository, copy the `hyprland` file to
the phone and `sudo OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -U` it together
with the new libraries (`pacman -S aquamarine hyprgraphics` in the same
transaction, so Hyprland and its libraries move together). Then restart the
session (`systemctl restart sddm`) and check `hyprctl version` and
`pacman -Q hyprland` (expect `0.57.0-3.1`).

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
(ours and Omarchy's) needs the aquamarine and hyprgraphics `extra` dropped.
A phone that hasn't updated yet keeps 0.56.2-5.1 and its libraries until it
does. After an update, the way back is the previous `hyprland`,
`aquamarine` and `hyprgraphics` together from the pacman cache:

```sh
# on the phone
cd /var/cache/pacman/pkg
sudo OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -U $(ls hyprland-0.56.2-5.1-aarch64.pkg.tar.* \
  aquamarine-0.15.1-*-aarch64.pkg.tar.* hyprgraphics-0.5.1-*-aarch64.pkg.tar.* | grep -v '\.sig$')
systemctl restart sddm
```

Hold it with `IgnorePkg = hyprland hyprpm aquamarine hyprgraphics` in
`/etc/pacman.conf` until a fixed build is published.
