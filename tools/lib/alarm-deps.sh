# SPDX-License-Identifier: MIT
# Sourced inside tools/build-packages' container (mounted read-only at
# /alarm-deps.sh), and by tests/build-packages-deps with a stand-in pacman:
# a package's dependencies into the build container, which pacman -Sy has
# just synced.
#
#   alarm_install_deps < srcinfo
#
# Every dependency a repository can provide goes in (the build-time ones
# always; runtime ones so check() can run). Ours that are not built yet are
# in no repository and are left out: makepkg runs with --nodeps.
#
# "Can provide" asks only whether a repository has the name (pacman -Sddp:
# no dependency resolution). The build image is made once and kept, so it
# falls behind the repositories, and a full resolution of a current package
# against it can fail: in Arch Linux ARM's openssl 3 to 4 change
# (2026-11-12 to 14) rust and systemd needed openssl 4, which broke the
# image's own curl, pacman and sudo, so `pacman -Sp cargo` failed, cargo
# was left out as if it were one of ours, and the build stopped in
# prepare() on "cargo: command not found".
#
# Installing current packages into the stale image is a partial upgrade.
# Usually that works; when the distribution moves a library ("openssl-3:
# /usr/lib/libcrypto.so.3 exists in filesystem (owned by openssl)", or
# "installing openssl (4.1.0-1) breaks dependency 'libcrypto.so=3-64'") it
# cannot: then the container is brought up to date (pacman -Su) and the
# install is tried once more. At the end every listed dependency must be
# met (pacman -T), so one that still isn't stops the build here, by name.
#
# A split package's own names are never installed: the srcinfo lists each
# package's depends, and one that depends on a sibling (hyprpm on hyprland)
# would otherwise pull the published build of the package being built. On
# 2026-11-27 that was hyprland 0.57.0-3.3 from [omamobile], whose
# libhyprgraphics.so=5 no repository had any more, so the rebuild meant to
# replace it (3.4, #1124) could not install its own dependencies.
alarm_install_deps() {
  local info wanted dep install=() missing own
  info=$(cat)
  own=" $(awk '$1 == "pkgname" {print $3}' <<<"$info" | tr '\n' ' ') "
  wanted=$(awk '$1 ~ /^(depends|makedepends|checkdepends)$/ {print $3}' <<<"$info" | sed 's/[<>=].*//' | sort -u)
  for dep in $wanted; do
    [[ $own == *" $dep "* ]] && continue
    pacman -Sddp --print-format %n "$dep" >/dev/null 2>&1 && install+=("$dep")
  done
  ((${#install[@]})) || return 0
  _alarm_deps() { pacman -S --noconfirm --needed --asdeps --overwrite "/usr/share/pacman/keyrings/*" "${install[@]}" >/dev/null; }
  if ! _alarm_deps; then
    echo "the build image is behind the repositories: upgrading it for this build, then installing again" >&2
    pacman -Su --noconfirm --overwrite "/usr/share/pacman/keyrings/*" >/dev/null || return 1
    _alarm_deps || return 1
  fi
  if ! missing=$(pacman -T "${install[@]}"); then
    echo "dependencies still not installed: $(tr '\n' ' ' <<<"$missing")" >&2
    return 1
  fi
}
