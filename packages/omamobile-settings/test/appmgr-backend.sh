#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/appmgr.sh, libexec/app-guard and libexec/app-remove on a scratch HOME, XDG dirs and root, with stub pacman,
# systemctl and Omarchy commands on PATH: nothing on the host is read, removed or started. Then mutation checks: copies
# of the helper without the per-target protection check or without the hash compare must make this test fail.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
tmp=$(cd -P -- "$tmp" && pwd -P)
H=$tmp/home S=$tmp/sys P=$tmp/pac R=$tmp/root L=$tmp/lib
mkdir -p "$H/.local/share/applications" "$S/applications" "$tmp/bin" "$P" "$R" "$L"
entry() { printf '[Desktop Entry]\nType=Application\n%s\n' "$2" > "$1"; }
entry "$S/applications/org.test.Toy.desktop" $'Name=Toy\nExec=/usr/bin/toyapp --x'
entry "$S/applications/needed.desktop" $'Name=Needed\nExec=needed'
entry "$S/applications/shellish.desktop" $'Name=Shellish\nExec=hyprlockui'
entry "$S/applications/depdrag.desktop" $'Name=DepDrag\nExec=depdrag'
entry "$S/applications/flat.desktop" $'Name=Flat\nExec=flatpak run x'
entry "$S/applications/def.desktop" $'Name=Def\nExec=defapp'
entry "$S/applications/dep.desktop" $'Name=Dep\nExec=depapp'
entry "$S/applications/wrap.desktop" $'Name=Wrap\nExec=wrapapp'
entry "$S/applications/noentry.desktop" $'Name=NoEntry\nExec=noentry'
entry "$H/.local/share/applications/WebThing.desktop" $'Name=WebThing\nExec=omarchy-launch-webapp https://x'
entry "$H/.local/share/applications/Mine.desktop" $'Name=Mine\nExec=mine'
entry "$H/.local/share/applications/shadowed.desktop" $'Name=Mine copy\nExec=sh'; entry "$S/applications/shadowed.desktop" $'Name=Sys\nExec=sh'

# pacman database: name version reason requiredby optionalfor (| separated), owners, file lists, -Rns plans
cat > "$P/db" <<'EOT'
toy-pkg|1.0-1|Explicitly installed|None|None
libtoy|2.0-1|Installed as a dependency for another package|toy-pkg|None
needed-pkg|1.0-1|Explicitly installed|other-app|None
hyprlock|0.9-1|Explicitly installed|None|None
depdrag-pkg|1.0-1|Explicitly installed|None|some-viewer
defpkg|1.0-1|Explicitly installed|None|None
deppkg|1.0-1|Installed as a dependency for another package|None|None
wrappkg|1.0-1|Explicitly installed|WRAP|None
noentry-pkg|1.0-1|Explicitly installed|None|None
leave-pkg|1.0-1|Explicitly installed|None|None
leftdep|1.0-1|Installed as a dependency for another package|leave-pkg|None
omaphone|1.0-1|Explicitly installed|None|None
omamessages|1.0-1|Explicitly installed|None|None
omacam|1.0-1|Explicitly installed|None|None
EOT
printf '%s\n' "$S/applications/org.test.Toy.desktop toy-pkg" "$S/applications/needed.desktop needed-pkg" \
  "$S/applications/shellish.desktop hyprlock" "$S/applications/depdrag.desktop depdrag-pkg" "$tmp/bin/toyapp toy-pkg" \
  "$S/applications/def.desktop defpkg" "$S/applications/dep.desktop deppkg" "$S/applications/wrap.desktop wrappkg" \
  "$S/applications/noentry.desktop noentry-pkg" > "$P/owners"
for p in defpkg deppkg wrappkg; do printf '%s 1.0-1\n' "$p" > "$P/plan.$p"; done
printf 'leave-pkg 1.0-1\nleftdep 1.0-1\n' > "$P/plan.leave-pkg"; printf 'leave-pkg 1.0-1\n' > "$P/dropplan.leave-pkg"; : > "$P/dropplan.leftdep"
echo /usr/share/applications/leave.desktop > "$P/files.leave-pkg"
printf 'noentry-pkg 1.0-1\n' > "$P/plan.noentry-pkg"; echo /usr/bin/noentry > "$P/files.noentry-pkg"
for p in omaphone omamessages omacam; do printf '%s 1.0-1\n' "$p" > "$P/plan.$p"; done
for p in toy-pkg needed-pkg hyprlock depdrag-pkg defpkg deppkg wrappkg omaphone omamessages omacam; do echo "/usr/share/applications/$p.desktop" > "$P/files.$p"; done
printf 'toy-pkg 1.0-1\nlibtoy 2.0-1\n' > "$P/plan.toy-pkg"
# a long file list with the entry first: a grep -q on a pipe would stop early and SIGPIPE pacman
seq -f '/usr/lib/toy/f%g' 1 50000 >> "$P/files.toy-pkg"
printf 'needed-pkg 1.0-1\n' > "$P/plan.needed-pkg"
printf 'hyprlock 0.9-1\n' > "$P/plan.hyprlock"
printf 'depdrag-pkg 1.0-1\nqt6-base 6.9-1\n' > "$P/plan.depdrag-pkg"
cat > "$tmp/bin/pacman" <<'EOT'
#!/bin/bash
[[ $LC_ALL == C ]] || { echo "no LC_ALL=C" >&2; exit 1; }
row() { grep -m1 "^$1|" "$PAC/db"; }
case $1 in
  -Qqo) o=$(awk -v f="$3" '$1==f{print $2}' "$PAC/owners"); [[ -n $o ]] && { echo "$o"; exit 0; }; exit 1 ;;
  -Qi) r=$(row "$3") || exit 1; IFS='|' read -r n v why req opt <<<"$r"
       # a long Required By wraps onto an indented line, as pacman prints it
       [[ $req == WRAP ]] && req=$'first-app  second-app\n                  third-app'
       printf 'Name            : %s\nVersion         : %s\nInstalled Size  : 1.00 MiB\nRequired By     : %s\nOptional For    : %s\nInstall Reason  : %s\n' "$n" "$v" "$req" "$opt" "$why" ;;
  -Q) row "$3" >/dev/null ;;
  -Qq) cut -d'|' -f1 "$PAC/db" ;;
  -Si) [[ $3 == toy-pkg ]] || { echo "error: package '$3' was not found" >&2; exit 1; } ;;
  -Qlq) cat "$PAC/files.$3" 2>/dev/null ;;
  -Rns) [[ $2 == --print ]] && { echo "error: invalid option: '--nosave' and '--print' may not be used together" >&2; exit 1; }; exit 1 ;;
  -Rs) [[ $2 == --print && $3 == --print-format && $4 == '%n %v' ]] || exit 1; cat "$PAC/plan.$6" 2>/dev/null || { echo "error: target not found: $6" >&2; exit 1; } ;;
  *) echo "unexpected pacman: $*" >&2; exit 1 ;;
esac
EOT
# Omarchy's drop: removes the named packages and the plan's dependencies from the stub database
cat > "$tmp/bin/omarchy-pkg-drop" <<'EOT'
#!/bin/bash
echo "$*" >> "$PAC/dropped"
# (dropplan.PKG, when present, is what really goes: a dependency left behind)
for p in "$@"; do f=$PAC/plan.$p; [[ -f $PAC/dropplan.$p ]] && f=$PAC/dropplan.$p; [[ -f $f ]] || { sed -i "/^$p|/d" "$PAC/db"; continue; }; while read -r n _; do sed -i "/^$n|/d" "$PAC/db"; done < "$f"; done
EOT
printf '#!/bin/bash\nprintf "%%s\\n" base hyprland defpkg\n' > "$tmp/bin/omarchy-pkg-defaults"
printf '#!/bin/bash\nsleep 1\n' > "$tmp/bin/toyapp"
cat > "$tmp/bin/omarchy-webapp-remove" <<'EOT'
#!/bin/bash
[[ $OMARCHY_REMOVE_NOTIFY == false ]] || exit 1
rm -f "$HOME/.local/share/applications/$1.desktop"; echo "$1" >> "$PAC/webapp"
EOT
# systemctl: --user units from $UNITS ("unit slice" lines); system "start omamobile-app-remove@..." runs the helper
cat > "$tmp/bin/systemctl" <<'EOT'
#!/bin/bash
args=("$@")
if [[ $1 == --user ]]; then
  shift; [[ $1 == --no-ask-password ]] && shift
  case $1 in
    list-units) awk '{print $1" loaded active running x"}' "$UNITS" ;;
    # the unit name through ENVIRON: awk -v would turn its \x2d into a dash
    show) if [[ $3 == ControlGroup ]]; then U=$5 awk '$1==ENVIRON["U"]{print $3}' "$UNITS"; else U=$5 awk '$1==ENVIRON["U"]{print $2}' "$UNITS"; fi ;;
    stop) echo "$3" >> "$PAC/stopped"; grep -v "^$3 " "$UNITS" > "$UNITS.n"; mv "$UNITS.n" "$UNITS" ;;
    *) echo "unexpected systemctl ${args[*]}" >&2; exit 1 ;;
  esac
  exit 0
fi
[[ $1 == --no-ask-password && $2 == start && $3 == -- ]] || { echo "unexpected systemctl ${args[*]}" >&2; exit 1; }
echo "$4" >> "$PAC/started"
[[ $4 =~ ^omamobile-app-remove@(.*)\.service$ ]] || exit 1
inst=$(systemd-escape --unescape -- "${BASH_REMATCH[1]}")
OMAMOBILE_APPMGR_ROOT=$ROOT OMAMOBILE_APPMGR_GUARD=$LIBDIR/app-guard OMAMOBILE_APPMGR_PROTECTED=$PROT OMAMOBILE_APPMGR_LOCK=$LOCK \
  "$LIBDIR/app-remove" "$inst"
EOT
chmod +x "$tmp/bin/"*
cp "$src/libexec/app-guard" "$src/libexec/app-remove" "$L/"
export PAC=$P ROOT=$R LIBDIR=$L PROT=$src/vendor/app-protected LOCK=$tmp/db.lck UNITS=$tmp/units
: > "$UNITS"
run() { env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$H" XDG_DATA_DIRS="$S" XDG_CONFIG_HOME="$H/.config" XDG_CACHE_HOME="$tmp/cache" \
  XDG_CURRENT_DESKTOP=Hyprland PAC="$P" ROOT="$R" LIBDIR="$L" PROT="$PROT" LOCK="$LOCK" UNITS="$UNITS" \
  OMAMOBILE_APPMGR_CGROOT="${OMAMOBILE_APPMGR_CGROOT:-}" OMAMOBILE_APPMGR_PROC="${OMAMOBILE_APPMGR_PROC:-}" OMAMOBILE_APPMGR_LIB="$L" OMAMOBILE_APPMGR_RUN="$R/run/omamobile-settings" OMAMOBILE_APPMGR_PROTECTED="$PROT" OMAMOBILE_APPMGR_LOCK="$LOCK" \
  bash -p "$src/backends/appmgr.sh" "$@" || true; }
fail() { echo "FAIL: $*" >&2; exit 1; }
has() { [[ $1 == *"$2"* ]] || fail "$1 lacks $2"; }
lacks() { [[ $1 != *"$2"* ]] || fail "$1 has $2"; }
field() { python3 -I -c 'import json,sys; v=json.loads(sys.argv[1]); [v:=v[int(k)] if isinstance(v,list) else v[k] for k in sys.argv[2].split(".")]; print(json.dumps(v))' "$1" "$2"; }

# usage and ids
has "$(run)" '"error":"usage'
has "$(run state)" '"error":"usage'
has "$(run state ../x)" '"error":"bad app id"'
has "$(run state nosuch)" '"error":"no such app"'
has "$(run policy org.test.Toy restricted)" '"error":"usage'

# state of a removable package: targets from the dry run, hash, reinstall line, no protected target
out=$(run state org.test.Toy)
[[ $(field "$out" kind) == '"package"' ]] || fail "kind: $out"
[[ $(field "$out" removable) == true ]] || fail "removable: $out"
[[ $(field "$out" targets.0.name) == '"libtoy"' ]] || fail "targets: $out"
[[ $(field "$out" reinstall) == '"sudo pacman -S toy-pkg"' ]] || fail "reinstall: $out"
lacks "$out" '"policy"'; lacks "$out" '"doze"'
hash=$(field "$out" hash | tr -d '"'); [[ $hash =~ ^[0-9a-f]{16}$ ]] || fail "hash: $out"

# refusals, each with its reason: required by another package, a protected package, a protected dependency, no package
out=$(run state needed); [[ $(field "$out" removable) == false ]] || fail "needed: $out"; has "$out" 'Other packages need needed-pkg: other-app'
out=$(run state shellish); [[ $(field "$out" removable) == false ]] || fail "shellish: $out"; has "$out" 'hyprlock is protected: the lock screen'
out=$(run state depdrag); [[ $(field "$out" removable) == false ]] || fail "depdrag: $out"; has "$out" 'qt6-base is protected'
[[ $(field "$out" targets.1.protected) == true ]] || fail "dep not marked: $out"
has "$out" '"optional_for":"some-viewer"'
has "$(run state depdrag)" "not in pacman's cache"
out=$(run state def); has "$out" 'defpkg is protected: installed by Omarchy'
out=$(run state dep); has "$out" 'installed as a dependency'
out=$(run state wrap); has "$out" 'Other packages need wrappkg: first-app  second-app third-app'
out=$(run state noentry); has "$out" 'has no app entry'
mkdir -p "$S/applications/kde" "$tmp/nixh"
entry "$S/applications/kde/nest.desktop" $'Name=Nested sys\nExec=sh'; entry "$H/.local/share/applications/kde-nest.desktop" $'Name=Nested mine\nExec=sh'
has "$(run state kde-nest)" 'your own copy of a system launcher'
entry "$H/.local/share/applications/tuicopy.desktop" $'Name=T\nExec=xdg-terminal-exec -e btop'; entry "$S/applications/tuicopy.desktop" $'Name=T sys\nExec=btop'
has "$(run state tuicopy)" 'your own copy of a system launcher'
mkdir -p "$H/.nix-profile/share/applications"; entry "$H/.nix-profile/share/applications/nixed.desktop" $'Name=N\nExec=sh'; entry "$H/.local/share/applications/nixed.desktop" $'Name=N mine\nExec=sh'
has "$(run state nixed)" 'your own copy of a system launcher'
has "$(run remove kde-nest 0)" 'your own copy'; [[ -e $H/.local/share/applications/kde-nest.desktop ]] || fail "override deleted"
out=$(run state shadowed); [[ $(field "$out" removable) == false ]] || fail "override removable: $out"; has "$out" 'your own copy of a system launcher'
out=$(run state flat); [[ $(field "$out" kind) == '"other"' && $(field "$out" removable) == false ]] || fail "flat: $out"
# Omarchy's default list unreadable: everything protected (fails closed)
mv "$tmp/bin/omarchy-pkg-defaults" "$tmp/defaults.off"
has "$(run state org.test.Toy)" "Omarchy's default package list could not be read"
mv "$tmp/defaults.off" "$tmp/bin/omarchy-pkg-defaults"
# the protected list unreadable: the same
out=$(env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$H" XDG_DATA_DIRS="$S" PAC="$P" OMAMOBILE_APPMGR_PROTECTED="$tmp/none" \
  OMAMOBILE_APPMGR_LOCK="$LOCK" "$L/app-guard" toy-pkg); has "$out" 'could not read its protected list'
# the phone's own apps are protected by name (not only because omamobile-apps depends on them)
for p in omaphone omamessages omacam; do
  out=$(env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$H" PAC="$P" OMAMOBILE_APPMGR_PROTECTED="$PROT" OMAMOBILE_APPMGR_LOCK="$LOCK" "$L/app-guard" "$p")
  has "$out" "refuse	$p is protected: "
done
# pacman locked: refused
: > "$LOCK"; has "$(run state org.test.Toy)" 'pacman is locked'; rm -f "$LOCK"

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

# the helper itself refuses a wrong hash for an app it would otherwise remove
[[ $(OMAMOBILE_APPMGR_ROOT=$R OMAMOBILE_APPMGR_GUARD=$L/app-guard OMAMOBILE_APPMGR_PROTECTED=$PROT OMAMOBILE_APPMGR_LOCK=$LOCK \
  PATH="$tmp/bin:/usr/bin:/bin" "$L/app-remove" "toy-pkg:0000000000000000" 2>/dev/null) == *"changed since you confirmed"* ]] || fail "helper ignored a wrong hash"
[[ ! -e $P/dropped ]] || fail "dropped on a wrong hash"
# remove: a stale hash is refused before anything starts; the right one goes through the helper and Omarchy's drop
has "$(run remove org.test.Toy 0000000000000000)" 'changed since you confirmed'
[[ ! -e $P/started ]] || fail "a unit started on a stale hash"
has "$(run remove needed 0000000000000000)" 'Other packages need'
out=$(run remove org.test.Toy "$hash"); has "$out" '"ok":true'; has "$out" 'sudo pacman -S toy-pkg'
[[ $(cat "$P/dropped") == "libtoy toy-pkg" ]] || fail "dropped: $(cat "$P/dropped")"
[[ $(cat "$P/started") == "omamobile-app-remove@toy\x2dpkg:$hash.service" ]] || fail "unit: $(cat "$P/started")"
grep -q "removed libtoy 2.0-1 toy-pkg 1.0-1" "$R/var/log/omamobile-app-remove.log" || fail "log"
has "$(cat "$R/run/omamobile-settings/app-remove.$hash")" '"ok":true'
! grep -q '^toy-pkg|' "$P/db" || fail "still in db"

# the helper on its own (as root would run it): refuses a protected app, a wrong hash, a bad request, a required one
helper() { OMAMOBILE_APPMGR_ROOT=$R OMAMOBILE_APPMGR_GUARD=$L/app-guard OMAMOBILE_APPMGR_PROTECTED=$PROT OMAMOBILE_APPMGR_LOCK=$LOCK \
  PATH="$tmp/bin:/usr/bin:/bin" "${H2:-$L/app-remove}" "$@" >/dev/null 2>&1 && echo ok || echo refused; }
hh=$(PATH="$tmp/bin:/usr/bin:/bin" OMAMOBILE_APPMGR_PROTECTED=$PROT OMAMOBILE_APPMGR_LOCK=$LOCK "$L/app-guard" hyprlock | awk -F'\t' '$1=="hash"{print $2}')
[[ $(helper "hyprlock:$hh") == refused ]] || fail "helper removed a protected package"
dh=$(PATH="$tmp/bin:/usr/bin:/bin" OMAMOBILE_APPMGR_PROTECTED=$PROT OMAMOBILE_APPMGR_LOCK=$LOCK "$L/app-guard" depdrag-pkg | awk -F'\t' '$1=="hash"{print $2}')
[[ $(helper "depdrag-pkg:$dh") == refused ]] || fail "helper removed a protected dependency"
[[ $(helper "needed-pkg:0000000000000000") == refused ]] || fail "helper ignored the hash"
[[ $(helper "x") == refused && $(helper "../x:0000000000000000") == refused ]] || fail "helper took a bad request"
[[ $(cat "$P/dropped") == "libtoy toy-pkg" ]] || fail "helper dropped more: $(cat "$P/dropped")"
# pacman removing something that was not shown (the database changed in between) is reported, never "removed"
printf 'extra-pkg|1.0-1|Explicitly installed|None|None\nextra-dep|1.0-1|Installed as a dependency for another package|None|None\n' >> "$P/db"
printf 'extra-pkg 1.0-1\n' > "$P/plan.extra-pkg"; printf 'extra-pkg 1.0-1\nextra-dep 1.0-1\n' > "$P/dropplan.extra-pkg"
echo /usr/share/applications/extra.desktop > "$P/files.extra-pkg"
xh=$(PATH="$tmp/bin:/usr/bin:/bin" OMAMOBILE_APPMGR_PROTECTED=$PROT OMAMOBILE_APPMGR_LOCK=$LOCK "$L/app-guard" extra-pkg | awk -F'\t' '$1=="hash"{print $2}')
[[ $(helper "extra-pkg:$xh") == refused ]] || fail "helper hid an unconfirmed removal"
has "$(cat "$R/run/omamobile-settings/app-remove.$xh")" 'also removed packages that were not shown: extra-dep'
grep -q 'ALSO REMOVED (not confirmed) extra-dep' "$R/var/log/omamobile-app-remove.log" || fail "extra not logged"
# a target still installed after the drop is a failure, not "removed"
lh=$(PATH="$tmp/bin:/usr/bin:/bin" OMAMOBILE_APPMGR_PROTECTED=$PROT OMAMOBILE_APPMGR_LOCK=$LOCK "$L/app-guard" leave-pkg | awk -F'\t' '$1=="hash"{print $2}')
[[ $(helper "leave-pkg:$lh") == refused ]] || fail "helper said removed with leftdep still installed"
has "$(cat "$R/run/omamobile-settings/app-remove.$lh")" 'still installed after removal: leftdep'

# web app and own launcher: Omarchy's webapp remove, a plain delete
has "$(run state WebThing)" '"kind":"webapp"'
has "$(run remove WebThing 0)" '"ok":true'; [[ $(cat "$P/webapp") == WebThing ]] || fail webapp
has "$(run remove Mine 0)" '"ok":true'; [[ ! -e $H/.local/share/applications/Mine.desktop ]] || fail mine

# mutation checks (only from the top-level run): the helper without its target check or its hash compare must fail
if [[ -z ${APPMGR_MUTANT:-} ]]; then
  for m in protect hash defaults explicit entry wrap left; do
    mut=$tmp/mut-$m; mkdir -p "$mut/libexec" "$mut/backends" "$mut/test" "$mut/vendor"
    cp -r "$src/backends/." "$mut/backends/"; cp "$src/vendor/app-protected" "$mut/vendor/"; cp "$src/test/appmgr-backend.sh" "$mut/test/"
    cp "$src/libexec/app-guard" "$src/libexec/app-remove" "$mut/libexec/"
    case $m in
      protect) sed -i 's/^    \[\[ -z \$refuse \]\] && refuse="\$n is protected: \$w"$/    :/' "$mut/libexec/app-guard"
               ! grep -q 'is protected: \$w"' "$mut/libexec/app-guard" || fail "mutation protect not applied" ;;
      hash) sed -i 's/^\[\[ \$hash == "\$want" \]\] || result false/true || result false/' "$mut/libexec/app-remove"
            grep -q '^true || result false "what would' "$mut/libexec/app-remove" || fail "mutation hash not applied" ;;
      defaults) sed -i 's/^  \[\[ -n \${defaults\[\$n\]+set} \]\] && {/  false \&\& {/' "$mut/libexec/app-guard" ;;
      explicit) sed -i 's/ \&\& \$reason != "Explicitly installed" \]\]/ \&\& 0 == 1 ]]/' "$mut/libexec/app-guard" ;;
      entry) sed -i 's/|| refuse="\$pkg has no app entry: it is not an app"/|| :/' "$mut/libexec/app-guard" ;;
      wrap) sed -i 's/^  on \&\& \/\^ +\/ .*$/  on \&\& 0 { }/' "$mut/libexec/app-guard" ;;
      left) sed -i 's/^((\${#left\[@\]})) \&\& result false/false \&\& result false/' "$mut/libexec/app-remove" ;;
    esac
    cmp -s "$mut/libexec/app-guard" "$src/libexec/app-guard" && cmp -s "$mut/libexec/app-remove" "$src/libexec/app-remove" && fail "mutation $m not applied"
    if APPMGR_MUTANT=1 bash "$mut/test/appmgr-backend.sh" >/dev/null 2>&1; then fail "mutation $m was not caught"; fi
  done
fi
echo "appmgr-backend: ok"
