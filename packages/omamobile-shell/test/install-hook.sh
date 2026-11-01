#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-shell.install's post_upgrade: every running Hyprland (a socket
# under /run/user/<uid>/hypr/<signature>/) reloads its config as its own
# user, so a new hypr/phone.lua takes effect without a login; a directory
# with no socket is left alone. Stand-ins for hyprctl and runuser record
# what was asked.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/run"
printf '#!/bin/bash\necho "hyprctl $*" >>%s/calls\n' "$t" >"$t/bin/hyprctl"
printf '#!/bin/bash\necho "runuser $*" >>%s/calls\n' "$t" >"$t/bin/runuser"
chmod +x "$t"/bin/*
uid=$(id -u); user=$(id -nu)
mkdir -p "$t/run/$uid/hypr/sigA" "$t/run/$uid/hypr/stale"
python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$t/run/$uid/hypr/sigA/.socket.sock"
out=$(PATH="$t/bin:$PATH" OMAMOBILE_RUNTIME_ROOT="$t/run" bash -c 'source "$1"; post_upgrade' sh "$here/omamobile-shell.install")
grep -c "omamobile-setup-user" <<<"$out" >/dev/null || fail "post_upgrade still says how settings arrive"
[[ $(cat "$t/calls") == "runuser -u $user -- env XDG_RUNTIME_DIR=$t/run/$uid HYPRLAND_INSTANCE_SIGNATURE=sigA hyprctl reload" ]] \
  || { cat "$t/calls" >&2; fail "the running Hyprland reloads, as its user; the stale directory is skipped"; }
rm -f "$t/calls"
PATH="$t/bin:$PATH" OMAMOBILE_RUNTIME_ROOT="$t/empty" bash -c 'source "$1"; post_upgrade' sh "$here/omamobile-shell.install" >/dev/null \
  || fail "no Hyprland running is fine"
[[ ! -e $t/calls ]] || fail "nothing to reload, nothing run"
echo "ok - post_upgrade reloads every running Hyprland, so a new phone.lua's binds take effect"
