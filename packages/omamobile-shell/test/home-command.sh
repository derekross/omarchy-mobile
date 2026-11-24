#!/bin/bash
# SPDX-License-Identifier: MIT
# bin/omamobile-home, the command an app runs when Back reaches its top
# level: one Hyprland dispatch to an empty workspace, then the home screens'
# home page, the same two calls as the home pill and the switcher's Home.
# Stand-ins for hyprctl and omarchy-shell record what was called; the real
# ones are never run (they would move the desktop this test runs on).
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin"
log=$t/calls
cat >"$t/bin/hyprctl" <<STUB
#!/bin/bash
printf 'hyprctl' >>"$log"; printf ' [%s]' "\$@" >>"$log"; echo >>"$log"
echo ok
[[ ! -e "$t/hyprctl-fails" ]]
STUB
cat >"$t/bin/omarchy-shell" <<STUB
#!/bin/bash
printf 'omarchy-shell' >>"$log"; printf ' [%s]' "\$@" >>"$log"; echo >>"$log"
echo 2
[[ ! -e "$t/shell-fails" ]]
STUB
chmod +x "$t"/bin/*
export PATH="$t/bin:$PATH"
unset OMAMOBILE_HYPRCTL
home() { bash "$here/bin/omamobile-home" "$@"; }
fail() { echo "not ok - omamobile-home: $1" >&2; exit 1; }

focus="hyprctl [dispatch] [hl.dsp.focus({ workspace = \"empty\" })]"
page="omarchy-shell [-q] [shell] [call] [omamobile.home] [goHome] []"

# Home: the empty workspace first, then the home page; nothing printed.
: >"$log"
out=$(home) || fail "going home succeeds"
[[ -z $out ]] || fail "prints nothing ($out)"
[[ $(sed -n 1p "$log") == "$focus" ]] || fail "first the empty workspace ($(sed -n 1p "$log"))"
[[ $(sed -n 2p "$log") == "$page" ]] || fail "then the home page ($(sed -n 2p "$log"))"
[[ $(wc -l <"$log") -eq 2 ]] || fail "two calls and no more"

# The same dispatch and the same home-screen call as the pill and the
# switcher, so the three ways home can't drift apart.
for qml in plugins/omamobile.launcher/Launcher.qml plugins/omamobile.switcher/Switcher.qml; do
  grep -cF '"hl.dsp.focus({ workspace = \"empty\" })"' "$here/$qml" >/dev/null || fail "$qml goes to the same empty workspace"
  grep -cF '"call", "shell", "call", "omamobile.home", "goHome", ""' "$here/$qml" >/dev/null || fail "$qml calls the same goHome"
done

# The home page is best effort: a shell that doesn't answer isn't a failure.
: >"$log"; touch "$t/shell-fails"
home || fail "a silent shell is not a failure"
[[ $(wc -l <"$log") -eq 2 ]] || fail "still both calls"
rm "$t/shell-fails"

# No Hyprland: status 1 (the app stays where it is), the page still asked.
: >"$log"; touch "$t/hyprctl-fails"
if home; then fail "without Hyprland the status is 1"; fi
[[ $(sed -n 2p "$log") == "$page" ]] || fail "the home page is still asked"
rm "$t/hyprctl-fails"

# OMAMOBILE_HYPRCTL names another hyprctl.
: >"$log"
cat >"$t/other" <<STUB
#!/bin/bash
echo "other \$*" >>"$log"
STUB
chmod +x "$t/other"
OMAMOBILE_HYPRCTL="$t/other" home || fail "another hyprctl"
[[ $(sed -n 1p "$log") == 'other dispatch hl.dsp.focus({ workspace = "empty" })' ]] || fail "OMAMOBILE_HYPRCTL is used ($(sed -n 1p "$log"))"

# Arguments: --help prints the header and calls nothing; anything else is refused.
: >"$log"
home --help | grep -c 'show the home screen' >/dev/null || fail "--help explains"
if home sideways 2>/dev/null; then fail "an unknown argument is refused"; fi
[[ ! -s $log ]] || fail "help and a bad argument call nothing"

echo "ok - omamobile-home: the empty workspace, then the home page; status, help"
