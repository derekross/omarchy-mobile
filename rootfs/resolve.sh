# SPDX-License-Identifier: MIT
# Sourced by rootfs/build-inside (and tests/rootfs-resolve): why pacman
# can't install a package. Two different problems look the same to a bare
# `pacman -Sp`: a package no repository has (not built for aarch64, or a
# typo) and one that is there but whose dependencies can't be met, usually
# because two repositories are out of step (#433: [omarchy]'s aquamarine
# against Arch Linux ARM's hyprtoolkit). The first is a fact about the
# repositories; the second breaks the build and needs pacman's reasons.

# resolve PACKAGE: sets verdict to ok, absent (no package or provider of that
# name in any repository) or unmet (it is there, but pacman can't resolve
# what it needs), and why to pacman's own reasons for unmet
resolve() {
  local out
  why=""
  if out=$(pacman -Sp --print-format %n "$1" 2>&1); then verdict=ok; return 0; fi
  if ! pacman -Sp -dd --print-format %n "$1" >/dev/null 2>&1; then verdict=absent; return 0; fi
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
