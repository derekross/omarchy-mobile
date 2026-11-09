# SPDX-License-Identifier: MIT
# Shared by tools/build-packages and tools/build-rootfs (sourced, not run):
# an Arch Linux ARM aarch64 container on this x86 laptop, through Docker and
# the laptop's aarch64 binfmt handler. Debian and Arch register it as
# qemu-aarch64 (qemu-user-static-binfmt). NixOS registers it as aarch64-linux.
# That node has to be enabled and carry the F (fix-binary) flag: without F
# its interpreter is a /run/binfmt wrapper that does not exist in the
# container. boot.binfmt.preferStaticEmulators turns the flag on.
#
# The container starts from Arch Linux ARM's official root tarball, checked
# against its MD5 file and its detached signature from the Arch Linux ARM
# build key (fingerprint pinned below). Everything is cached under
# $ALARM_CACHE (default ~/.cache/omamobile-rootfs):
#   ArchLinuxARM-aarch64-latest.tar.gz{,.md5,.sig}   the tarball, verified
#   alarm-builder.asc                                the build key, as fetched
#   pkg/                                             pacman's package cache
#   src/                                             makepkg's source cache
# Docker images: omamobile-alarm-base:<tarball sha256> (the plain tarball)
# and omamobile-alarm-build:<hash> (keyrings, repositories, base-devel).

ALARM_URL=${ALARM_URL:-http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}
# Arch Linux ARM Build System <builder@archlinuxarm.org>
ALARM_KEY=68B3537F39A313B3E574D06777193F152BDBE6A6
ALARM_KEYSERVER=${ALARM_KEYSERVER:-hkps://keyserver.ubuntu.com}
ALARM_CACHE=${ALARM_CACHE:-$HOME/.cache/omamobile-rootfs}
ALARM_TARBALL=$ALARM_CACHE/ArchLinuxARM-aarch64-latest.tar.gz
# Omarchy's aarch64 packages (omarchy, omarchy-settings, quickshell, its
# hyprland). Stable, the release the phone's Omarchy patches follow; edge
# carries release candidates (4.5.0rc1 on 2026-10-20) they may not apply to.
OMARCHY_CHANNEL=${OMARCHY_CHANNEL:-stable}
# The keyring that signs [omarchy]. On an Omarchy machine it is the host's
# (/usr/share/pacman/keyrings, kept current by pacman), which already trusts
# it: the container can't bootstrap that trust on its own. A host without it
# (a build server on another distribution) fetches omarchy-keyring from
# Omarchy's repository instead, checked like the tarball: its detached
# signature must be by Omarchy's packaging key, pinned below, and its
# SHA-256 the one the repository's index lists. The three files are cached
# in $ALARM_CACHE/omarchy-keyring with the package and its signature, which
# are verified again at every use; the cache is refreshed when the index
# names a newer version and kept when it names an older one (a rollback is
# refused). Setting OMARCHY_KEYRING_DIR uses that folder and nothing else.
OMARCHY_KEYRING_DIR_SET=${OMARCHY_KEYRING_DIR:+1}
OMARCHY_KEYRING_DIR=${OMARCHY_KEYRING_DIR:-/usr/share/pacman/keyrings}
# Omarchy <pkgs@omarchy.org>: the key omarchy-keyring's omarchy-trusted names
OMARCHY_KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571
OMARCHY_PKGS_URL=${OMARCHY_PKGS_URL:-https://pkgs.omarchy.org}
# A contributor's local signing key (tools/local-key-init; --local in
# build-packages and build-rootfs): the path of its exported public key.
# When set, the build image also trusts that key, locally signed, and only
# there: phones and the published repository never see it.
ALARM_LOCAL_KEY=${ALARM_LOCAL_KEY:-}

alarm_say() { printf '\e[1m==> %s\e[0m\n' "$*"; }
alarm_die() { printf '\e[31merror:\e[0m %s\n' "$*" >&2; exit 1; }

# Debian/Arch: the qemu-aarch64 node is enough. NixOS: aarch64-linux must be
# enabled and its flags: line must contain F, or the container cannot run it.
alarm_require_binfmt() {
  local node=/proc/sys/fs/binfmt_misc/aarch64-linux
  if [[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
    return 0
  fi
  if [[ -e $node ]] && grep -qx enabled "$node" && grep -q '^flags:.*F' "$node"; then
    return 0
  fi
  alarm_die "no usable aarch64 binfmt handler: install qemu-user-static-binfmt, or enable boot.binfmt.emulatedSystems with boot.binfmt.preferStaticEmulators so aarch64-linux is enabled and its flags: line contains F"
}

# Download (once) and verify the tarball. ALARM_REFRESH=1 fetches the newest.
alarm_fetch() {
  local gnupg status
  mkdir -p "$ALARM_CACHE/pkg" "$ALARM_CACHE/src"
  command -v docker >/dev/null || alarm_die "docker is needed"
  alarm_require_binfmt
  if [[ ! -f $ALARM_TARBALL || ${ALARM_REFRESH:-} == 1 ]]; then
    alarm_say "Downloading the Arch Linux ARM aarch64 root tarball"
    curl -fsSL -o "$ALARM_TARBALL.part" "$ALARM_URL"
    curl -fsSL -o "$ALARM_TARBALL.md5" "$ALARM_URL.md5"
    curl -fsSL -o "$ALARM_TARBALL.sig" "$ALARM_URL.sig"
    mv "$ALARM_TARBALL.part" "$ALARM_TARBALL"
  fi
  (cd "$ALARM_CACHE" && md5sum -c --quiet "${ALARM_TARBALL##*/}.md5") || alarm_die "MD5 mismatch for $ALARM_TARBALL"
  gnupg=$(mktemp -d)
  if [[ ! -s $ALARM_CACHE/alarm-builder.asc ]]; then
    GNUPGHOME=$gnupg gpg -q --batch --keyserver "$ALARM_KEYSERVER" --recv-keys "$ALARM_KEY" ||
      { rm -rf "$gnupg"; alarm_die "could not fetch the Arch Linux ARM build key $ALARM_KEY"; }
    GNUPGHOME=$gnupg gpg -q --batch --armor --export "$ALARM_KEY" >"$ALARM_CACHE/alarm-builder.asc"
  else
    GNUPGHOME=$gnupg gpg -q --batch --import "$ALARM_CACHE/alarm-builder.asc"
  fi
  # VALIDSIG carries the primary key's fingerprint last: it must be the pinned one
  status=$(GNUPGHOME=$gnupg gpg --batch --status-fd 1 --verify "$ALARM_TARBALL.sig" "$ALARM_TARBALL" 2>/dev/null || true)
  rm -rf "$gnupg"
  grep -Eq "^\[GNUPG:\] VALIDSIG .* $ALARM_KEY\$" <<<"$status" ||
    alarm_die "bad or missing signature on $ALARM_TARBALL (expected key $ALARM_KEY)"
}

# Verify an omarchy-keyring package against its detached signature by the
# pinned packaging key $OMARCHY_KEY. $1: the package, $2: its .sig.
_omarchy_keyring_verify() {
  local gnupg status
  gnupg=$(mktemp -d)
  if [[ ! -s $ALARM_CACHE/omarchy-pkgs.asc ]]; then
    GNUPGHOME=$gnupg gpg -q --batch --keyserver "$ALARM_KEYSERVER" --recv-keys "$OMARCHY_KEY" ||
      { rm -rf "$gnupg"; alarm_die "could not fetch Omarchy's packaging key $OMARCHY_KEY"; }
    GNUPGHOME=$gnupg gpg -q --batch --armor --export "$OMARCHY_KEY" >"$ALARM_CACHE/omarchy-pkgs.asc"
  else
    GNUPGHOME=$gnupg gpg -q --batch --import "$ALARM_CACHE/omarchy-pkgs.asc"
  fi
  status=$(GNUPGHOME=$gnupg gpg --batch --status-fd 1 --verify "$2" "$1" 2>/dev/null || true)
  rm -rf "$gnupg"
  grep -Eq "^\[GNUPG:\] VALIDSIG .* $OMARCHY_KEY\$" <<<"$status"
}

# The cached keyring is used only while its package still verifies and the
# three files are the package's own, byte for byte. $1: the cache folder.
_omarchy_keyring_cached_ok() {
  local dir=$1 pkg f
  pkg=$(cat "$dir/PACKAGE" 2>/dev/null) || return 1
  [[ -n $pkg && -s $dir/$pkg && -s $dir/$pkg.sig ]] || return 1
  _omarchy_keyring_verify "$dir/$pkg" "$dir/$pkg.sig" || return 1
  for f in omarchy.gpg omarchy-trusted omarchy-revoked; do
    cmp -s "$dir/$f" <(bsdtar -xOf "$dir/$pkg" "usr/share/pacman/keyrings/$f") || return 1
  done
}

# The folder holding omarchy.gpg, omarchy-trusted and omarchy-revoked; prints
# it. The host's when it has all three or OMARCHY_KEYRING_DIR was set,
# otherwise the verified copy described at OMARCHY_KEYRING_DIR above: the
# package and its signature are kept beside it and checked again at every
# use, and an index naming an older keyring than the cached one is refused.
alarm_omarchy_keyring() {
  local f have=1 dir=$ALARM_CACHE/omarchy-keyring base want file sum tmp cached
  for f in omarchy.gpg omarchy-trusted omarchy-revoked; do [[ -f $OMARCHY_KEYRING_DIR/$f ]] || have=0; done
  if ((have)) || [[ -n $OMARCHY_KEYRING_DIR_SET ]]; then
    ((have)) || alarm_die "no Omarchy keyring in OMARCHY_KEYRING_DIR=$OMARCHY_KEYRING_DIR (omarchy.gpg, omarchy-trusted, omarchy-revoked)"
    echo "$OMARCHY_KEYRING_DIR"; return
  fi
  command -v bsdtar >/dev/null || alarm_die "fetching Omarchy's keyring needs bsdtar (libarchive-tools on Debian and Ubuntu)"
  cached=$(cat "$dir/VERSION" 2>/dev/null || true)
  if [[ -n $cached ]] && ! _omarchy_keyring_cached_ok "$dir"; then
    alarm_say "The cached Omarchy keyring no longer verifies: fetching it again" >&2
    rm -rf "$dir"; cached=
  fi
  base=$OMARCHY_PKGS_URL/$OMARCHY_CHANNEL/aarch64
  tmp=$(mktemp -d)
  if ! curl -fsSL -o "$tmp/omarchy.db" "$base/omarchy.db"; then
    rm -rf "$tmp"
    [[ -n $cached ]] || alarm_die "no Omarchy keyring on this host and $base/omarchy.db can't be fetched"
    alarm_say "Omarchy's index can't be fetched: using the cached keyring ($cached, verified)" >&2
    echo "$dir"; return
  fi
  # The index isn't signed: it only names the file; the package's own
  # signature and its listed SHA-256 are what's checked
  read -r want file sum < <(bsdtar -xOf "$tmp/omarchy.db" --include='omarchy-keyring-*/desc' |
    awk '/^%VERSION%$/ { getline; v = $0 } /^%FILENAME%$/ { getline; f = $0 } /^%SHA256SUM%$/ { getline; s = $0 } END { print v, f, s }')
  [[ -n $file && -n $sum ]] || { rm -rf "$tmp"; alarm_die "omarchy-keyring isn't in $base/omarchy.db"; }
  if [[ -n $cached && $want == "$cached" ]]; then
    rm -rf "$tmp"; echo "$dir"; return
  fi
  if [[ -n $cached && $(printf '%s\n%s\n' "$want" "$cached" | sort -V | tail -1) == "$cached" ]]; then
    rm -rf "$tmp"
    alarm_die "Omarchy's index names omarchy-keyring $want, older than the cached $cached: refusing a rollback (remove $dir to accept it)"
  fi
  alarm_say "Fetching Omarchy's keyring (omarchy-keyring $want)" >&2
  curl -fsSL -o "$tmp/$file" "$base/$file" && curl -fsSL -o "$tmp/$file.sig" "$base/$file.sig" ||
    { rm -rf "$tmp"; alarm_die "could not download $base/$file"; }
  [[ $(sha256sum <"$tmp/$file" | cut -d' ' -f1) == "$sum" ]] ||
    { rm -rf "$tmp"; alarm_die "$file doesn't match the SHA-256 Omarchy's index lists"; }
  _omarchy_keyring_verify "$tmp/$file" "$tmp/$file.sig" ||
    { rm -rf "$tmp"; alarm_die "bad or missing signature on $file (expected key $OMARCHY_KEY)"; }
  mkdir -p "$tmp/x" &&
    bsdtar -xf "$tmp/$file" -C "$tmp/x" usr/share/pacman/keyrings/omarchy.gpg \
      usr/share/pacman/keyrings/omarchy-trusted usr/share/pacman/keyrings/omarchy-revoked ||
    { rm -rf "$tmp"; alarm_die "$file holds no Omarchy keyring"; }
  f=$tmp/x/usr/share/pacman/keyrings
  echo "$want" >"$f/VERSION"; echo "$file" >"$f/PACKAGE"
  mv "$tmp/$file" "$tmp/$file.sig" "$f/"
  rm -rf "$dir.new" && mv "$f" "$dir.new" && rm -rf "$dir" && mv "$dir.new" "$dir"
  rm -rf "$tmp"
  echo "$dir"
}

# The plain tarball as a Docker image; prints its tag.
alarm_base_image() {
  local sum tag
  sum=$(sha256sum "$ALARM_TARBALL" | cut -c1-16)
  tag=omamobile-alarm-base:$sum
  if ! docker image inspect "$tag" >/dev/null 2>&1; then
    alarm_say "Importing the tarball as $tag" >&2
    docker import --platform linux/arm64 "$ALARM_TARBALL" "$tag" >/dev/null
  fi
  echo "$tag"
}

# The build image: the base plus initialised keyrings (Arch Linux ARM's,
# Omarchy's from this laptop, Omarchy Mobile's from packages/, and
# $ALARM_LOCAL_KEY when set, which is part of the image's hash), the build
# pacman.conf, base-devel, arch-install-scripts and a "builder" user with
# this laptop's uid. Prints its tag. $1: the repository root.
alarm_build_image() {
  local root=$1 base tag hash ctx name keyring
  base=$(alarm_base_image)
  keyring=$(alarm_omarchy_keyring) || exit 1
  ctx=$(mktemp -d)
  cp "$keyring"/omarchy{.gpg,-trusted,-revoked} "$ctx/"
  cp "$root"/packages/omamobile-keyring/omamobile{.gpg,-trusted,-revoked} "$ctx/"
  if [[ -n $ALARM_LOCAL_KEY ]]; then
    [[ -f $ALARM_LOCAL_KEY ]] || alarm_die "no local key $ALARM_LOCAL_KEY"
    cp "$ALARM_LOCAL_KEY" "$ctx/local.asc"
  fi
  cp "$root/tools/lib/alarm-setup" "$ctx/setup"
  hash=$( (echo "$base $OMARCHY_CHANNEL $(id -u)"; cat "$ctx"/*) | sha256sum | cut -c1-16)
  tag=omamobile-alarm-build:$hash
  if ! docker image inspect "$tag" >/dev/null 2>&1; then
    alarm_say "Preparing the build image $tag (keyrings, base-devel)" >&2
    name=omamobile-alarm-setup-$$
    docker run --platform linux/arm64 --name "$name" -v "$ctx:/setup:ro" -v "$ALARM_CACHE/pkg:/var/cache/pacman/pkg" \
      -e OMARCHY_CHANNEL="$OMARCHY_CHANNEL" -e BUILDER_UID="$(id -u)" -e BUILDER_GID="$(id -g)" \
      "$base" bash /setup/setup >&2 || { docker rm -f "$name" >/dev/null 2>&1; rm -rf "$ctx"; alarm_die "build image setup failed"; }
    # Not under set -e here (callers run this in a command substitution), so
    # a failed commit must be caught by hand or the build runs on no image.
    docker commit "$name" "$tag" >/dev/null ||
      { docker rm -f "$name" >/dev/null 2>&1; rm -rf "$ctx"; alarm_die "build image commit failed"; }
    docker rm "$name" >/dev/null
  fi
  rm -rf "$ctx"
  echo "$tag"
}
