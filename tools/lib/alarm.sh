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
# The keyring that signs [omarchy], taken from this (Omarchy) laptop, which
# already trusts it: the container can't bootstrap that trust on its own.
OMARCHY_KEYRING_DIR=${OMARCHY_KEYRING_DIR:-/usr/share/pacman/keyrings}

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
# Omarchy's from this laptop, Omarchy Mobile's from packages/), the build
# pacman.conf, base-devel, arch-install-scripts and a "builder" user with
# this laptop's uid. Prints its tag. $1: the repository root.
alarm_build_image() {
  local root=$1 base tag hash ctx name
  base=$(alarm_base_image)
  for f in omarchy.gpg omarchy-trusted omarchy-revoked; do
    [[ -f $OMARCHY_KEYRING_DIR/$f ]] || alarm_die "no $OMARCHY_KEYRING_DIR/$f: this needs Omarchy's keyring (omarchy-keyring) on the build machine"
  done
  ctx=$(mktemp -d)
  cp "$OMARCHY_KEYRING_DIR"/omarchy{.gpg,-trusted,-revoked} "$ctx/"
  cp "$root"/packages/omamobile-keyring/omamobile{.gpg,-trusted,-revoked} "$ctx/"
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
