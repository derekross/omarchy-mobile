# SPDX-License-Identifier: MIT
# Sourced by rootfs/build-inside (and tests/rootfs-resolve): why pacman
# can't install a package. Two different problems look the same to a bare
# `pacman -Sp`: a package no repository has (not built for aarch64, or a
# typo) and one that is there but whose dependencies can't be met, usually
# because two repositories are out of step (#433: [omarchy]'s aquamarine
# against Arch Linux ARM's hyprtoolkit). The first is a fact about the
# repositories; the second breaks the build and needs pacman's reasons.

# resolve PACKAGE: sets verdict to ok, absent (pacman says "target not
# found": no package or provider of that name in any repository) or unmet
# (anything else that stops it, usually dependencies it can't resolve), and
# why to pacman's own reasons for unmet. Only pacman's own "target not found"
# counts as absent, so a package that fails for some other reason is never
# filed as missing. LC_ALL=C because pacman translates its messages.
resolve() {
  local out
  why=""
  if out=$(LC_ALL=C pacman -Sp --print-format %n "$1" 2>&1); then verdict=ok; return 0; fi
  if grep -qxF "error: target not found: $1" <<<"$out"; then verdict=absent; return 0; fi
  verdict=unmet
  # The ":: unable to satisfy dependency ..." lines; any error line if none
  why=$(grep '^:: ' <<<"$out" | grep -v '^:: There are' || true)
  [[ -n $why ]] || why=$(grep '^error: ' <<<"$out" || true)
  [[ -n $why ]] || why="pacman -Sp $1 failed with no reason given"
}

# resolve_all PACKAGE...: sets absent_pkgs, unmet_pkgs and unmet_why (each
# reason once, in order) for the packages that aren't ok, and ok_pkgs
resolve_all() {
  local p
  ok_pkgs=() absent_pkgs=() unmet_pkgs=() unmet_why=""
  for p in "$@"; do
    resolve "$p"
    case $verdict in
      ok) ok_pkgs+=("$p") ;;
      absent) absent_pkgs+=("$p") ;;
      unmet) unmet_pkgs+=("$p"); unmet_why+="$why"$'\n' ;;
    esac
  done
  unmet_why=$(awk 'NF && !seen[$0]++ { print "    " $0 }' <<<"$unmet_why")
}

# omarchy_packages INSTALL_DIR: Omarchy's default packages for a plain
# aarch64 computer, one name per line, each once, in list order. Omarchy 4.0
# had one list, omarchy-base.packages. Omarchy 4.5 composes it (as its
# omarchy-pkg-defaults does): the base list, plus omarchy-aarch64.packages
# (zram-generator, rtkit), minus omarchy-x86_64-only.packages. A phone is
# never one of its named platforms (Apple, Snapdragon laptops), so their
# lists are not read. Fails when the base list isn't there.
omarchy_packages() {
  local dir=$1 files=() names
  names() { sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$@"; }
  [[ -f $dir/omarchy-base.packages ]] || return 1
  files=("$dir/omarchy-base.packages")
  [[ ! -f $dir/omarchy-aarch64.packages ]] || files+=("$dir/omarchy-aarch64.packages")
  if [[ -f $dir/omarchy-x86_64-only.packages ]]; then
    names "${files[@]}" | awk -v skips=<(names "$dir/omarchy-x86_64-only.packages") '
      BEGIN { while ((getline name < skips) > 0) skip[name] = 1 }
      !skip[$0] && !seen[$0]++'
  else
    names "${files[@]}" | awk '!seen[$0]++'
  fi
}
