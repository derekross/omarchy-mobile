#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/appmgr.sh (state and Stop) on a scratch HOME and XDG dirs, with stub pacman and systemctl on PATH: nothing
# on the host is read or stopped.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
tmp=$(cd -P -- "$tmp" && pwd -P)
H=$tmp/home S=$tmp/sys P=$tmp/pac
mkdir -p "$H/.local/share/applications" "$S/applications" "$tmp/bin" "$P"
entry() { printf '[Desktop Entry]\nType=Application\n%s\n' "$2" > "$1"; }
entry "$S/applications/org.test.Toy.desktop" $'Name=Toy\nExec=/usr/bin/toyapp --x'
entry "$S/applications/needed.desktop" $'Name=Needed\nExec=needed'
printf '%s\n' "$S/applications/org.test.Toy.desktop toy-pkg" "$S/applications/needed.desktop needed-pkg" "$tmp/bin/toyapp toy-pkg" > "$P/owners"
cat > "$tmp/bin/pacman" <<'EOT'
#!/bin/bash
[[ $LC_ALL == C ]] || { echo "no LC_ALL=C" >&2; exit 1; }
case $1 in
  -Qqo) o=$(awk -v f="$3" '$1==f{print $2}' "$PAC/owners"); [[ -n $o ]] && { echo "$o"; exit 0; }; exit 1 ;;
  -Qi) printf 'Name            : %s\nVersion         : 1.0-1\nInstalled Size  : 1.00 MiB\n' "$3" ;;
  *) echo "unexpected pacman: $*" >&2; exit 1 ;;
esac
EOT
printf '#!/bin/bash\nsleep 1\n' > "$tmp/bin/toyapp"
printf '#!/bin/bash\n[[ -e $DOZE_ON ]]\n' > "$tmp/bin/omarchy-toggle-enabled"
# systemctl: --user units from $UNITS ("unit slice cgroup" lines); anything else is unexpected
cat > "$tmp/bin/systemctl" <<'EOT'
#!/bin/bash
args=("$@")
[[ $1 == --user ]] || { echo "unexpected systemctl ${args[*]}" >&2; exit 1; }
shift; [[ $1 == --no-ask-password ]] && shift
case $1 in
  list-units) awk '{print $1" loaded active running x"}' "$UNITS" ;;
  # the unit name through ENVIRON: awk -v would turn its \x2d into a dash
  show) if [[ $3 == ControlGroup ]]; then U=$5 awk '$1==ENVIRON["U"]{print $3}' "$UNITS"; else U=$5 awk '$1==ENVIRON["U"]{print $2}' "$UNITS"; fi ;;
  stop) echo "$3" >> "$PAC/stopped"; grep -v "^$3 " "$UNITS" > "$UNITS.n"; mv "$UNITS.n" "$UNITS" ;;
  *) echo "unexpected systemctl ${args[*]}" >&2; exit 1 ;;
esac
EOT
chmod +x "$tmp/bin/"*
export PAC=$P UNITS=$tmp/units DOZE_ON=$tmp/doze-on
: > "$UNITS"
run() { env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$H" XDG_DATA_DIRS="$S" XDG_CONFIG_HOME="$H/.config" XDG_CACHE_HOME="$tmp/cache" \
  XDG_CURRENT_DESKTOP=Hyprland PAC="$P" UNITS="$UNITS" DOZE_ON="$DOZE_ON" \
  OMAMOBILE_APPMGR_CGROOT="${OMAMOBILE_APPMGR_CGROOT:-}" OMAMOBILE_APPMGR_PROC="${OMAMOBILE_APPMGR_PROC:-}" \
  bash -p "$src/backends/appmgr.sh" "$@" || true; }
fail() { echo "FAIL: $*" >&2; exit 1; }
has() { [[ $1 == *"$2"* ]] || fail "$1 lacks $2"; }
lacks() { [[ $1 != *"$2"* ]] || fail "$1 has $2"; }

# usage and ids; there is no remove verb
has "$(run)" '"error":"usage'
has "$(run state)" '"error":"usage'
has "$(run state ../x)" '"error":"bad app id"'
has "$(run state nosuch)" '"error":"no such app"'
has "$(run remove org.test.Toy 0000000000000000)" '"error":"usage'
has "$(run policy org.test.Toy sometimes)" '"error":"bad policy'
has "$(run policy org.test.Toy)" '"error":"usage'
out=$(run state org.test.Toy); has "$out" '"package":"toy-pkg"'; has "$out" '"units":[]'
lacks "$out" '"removable"'; lacks "$out" '"hash"'
has "$out" '"policy":"optimized"'; has "$out" '"doze":"missing"'
# with omamobile-dozed installed (on PATH): off or on by its toggle
printf '#!/bin/bash\n' > "$tmp/bin/omamobile-dozed"; chmod +x "$tmp/bin/omamobile-dozed"
has "$(run state org.test.Toy)" '"doze":"off"'
: > "$DOZE_ON"; has "$(run state org.test.Toy)" '"doze":"on"'; rm -f "$DOZE_ON" "$tmp/bin/omamobile-dozed"
# policy: written per app with its unit keys, optimized removes the line, a link is not followed
pf=$H/.config/omamobile/app-policy
has "$(run policy org.test.Toy restricted)" '"policy":"restricted"'
grep -qxF "org.test.Toy	restricted	org.test.Toy toyapp" "$pf" || fail "policy file: $(cat "$pf")"
has "$(run state org.test.Toy)" '"policy":"restricted"'
has "$(run policy needed unrestricted)" '"policy":"unrestricted"'
has "$(run policy org.test.Toy optimized)" '"policy":"optimized"'
! grep -q '^org.test.Toy' "$pf" || fail "optimized left a line"
grep -q '^needed	unrestricted' "$pf" || fail "other app's line lost"
mv "$pf" "$tmp/pol"; ln -s "$tmp/pol" "$pf"
has "$(run policy needed restricted)" 'is a link'
rm "$pf"; mv "$tmp/pol" "$pf"
# stop: only this app's units in app*.slice; never another app's, never one outside app.slice
printf '%s\n' 'app-Hyprland-toyapp-1a2b3c4d.scope app-graphical.slice' 'app-Hyprland-org.test.Toy@5e6f.service app-graphical.slice' \
  'app-Hyprland-toyappx-11111111.scope app-graphical.slice' 'app-Hyprland-toyapp-22222222.scope session.slice' > "$UNITS"
out=$(run state org.test.Toy); has "$out" '"units":["app-Hyprland-toyapp-1a2b3c4d.scope","app-Hyprland-org.test.Toy@5e6f.service"]'
has "$(run stop org.test.Toy)" '"ok":true'
[[ $(cat "$P/stopped") == $'app-Hyprland-toyapp-1a2b3c4d.scope\napp-Hyprland-org.test.Toy@5e6f.service' ]] || fail "stopped: $(cat "$P/stopped")"
has "$(run stop org.test.Toy)" 'nothing to stop'
has "$(run stop needed)" 'nothing to stop'
# started from the drawer: `uwsm-app -- gtk-launch ID.desktop` names the unit after gtk-launch; the entry in the process
# environment (GIO_LAUNCHED_DESKTOP_FILE) says which app it is. Another app's gtk-launch unit is left alone.
mkdir -p "$tmp/cg/a" "$tmp/cg/b" "$tmp/proc/101" "$tmp/proc/202"
echo 101 > "$tmp/cg/a/cgroup.procs"; echo 202 > "$tmp/cg/b/cgroup.procs"
printf 'A=1\0GIO_LAUNCHED_DESKTOP_FILE=/usr/share/applications/org.test.Toy.desktop\0GIO_LAUNCHED_DESKTOP_FILE_PID=101\0' > "$tmp/proc/101/environ"
printf 'GIO_LAUNCHED_DESKTOP_FILE=/usr/share/applications/needed.desktop\0GIO_LAUNCHED_DESKTOP_FILE_PID=202\0' > "$tmp/proc/202/environ"
# a browser scope holding a child that inherited the toy's variable (its PID is not the one in the variable): never the toy
mkdir -p "$tmp/cg/c" "$tmp/proc/303"; echo 303 > "$tmp/cg/c/cgroup.procs"
printf 'GIO_LAUNCHED_DESKTOP_FILE=/usr/share/applications/org.test.Toy.desktop\0GIO_LAUNCHED_DESKTOP_FILE_PID=101\0' > "$tmp/proc/303/environ"
printf '%s\n' 'app-Hyprland-gtk\x2dlaunch-033ef4db.scope app-graphical.slice /a' 'app-Hyprland-gtk\x2dlaunch-6825102d.scope app-graphical.slice /b' 'app-Hyprland-gtk\x2dlaunch-7777aaaa.scope app-graphical.slice /c' 'app-Hyprland-chromium-8888bbbb.scope app-graphical.slice /a' > "$UNITS"
out=$(OMAMOBILE_APPMGR_CGROOT=$tmp/cg OMAMOBILE_APPMGR_PROC=$tmp/proc run stop org.test.Toy); has "$out" '"stopped":["app-Hyprland-gtk\\x2dlaunch-033ef4db.scope"]'
# two different apps, each with its own PID in the variable, in one gtk-launch unit: ambiguous, nothing to stop
mkdir -p "$tmp/proc/404"; printf 'GIO_LAUNCHED_DESKTOP_FILE=/usr/share/applications/needed.desktop\0GIO_LAUNCHED_DESKTOP_FILE_PID=404\0' > "$tmp/proc/404/environ"
mkdir -p "$tmp/cg/d"; printf '101\n404\n' > "$tmp/cg/d/cgroup.procs"
printf '%s\n' 'app-Hyprland-gtk\x2dlaunch-dddd0000.scope app-graphical.slice /d' > "$UNITS.amb"; cp "$UNITS" "$UNITS.keep"; cp "$UNITS.amb" "$UNITS"
has "$(OMAMOBILE_APPMGR_CGROOT=$tmp/cg OMAMOBILE_APPMGR_PROC=$tmp/proc run stop org.test.Toy)" 'nothing to stop'
cp "$UNITS.keep" "$UNITS"
grep -qE '6825102d|7777aaaa|8888bbbb' "$P/stopped" && fail "stopped another app's unit (other ID, inherited variable, or not a gtk-launch unit)"
echo "appmgr-backend: ok"
