#!/bin/bash
# SPDX-License-Identifier: MIT
# App manager for the Settings app's Apps page: one app's running units and Stop. Prints one line of JSON.
#   appmgr.sh state ID             {"id","name","package","units":[..]}
#   appmgr.sh stop ID              systemctl --user stop of the app's own units (app*.slice, its ID or command in the name)
# The unit keys are the names systemd gives the app's units (app-<launcher>-<KEY>-<random>.scope or app-<launcher>-<KEY>@<random>.service).
# Stop never goes by process name and never touches anything outside app*.slice. Uninstall is not offered here.
set -euo pipefail
set +x
export LC_ALL=C
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
verb=${1:-}
fail() { printf '{"error":"%s"}\n' "$1"; exit 2; }
case $verb in
  state | stop) [[ $# -eq 2 ]] || fail "usage: state ID|stop ID" ;;
  *) fail "usage: state ID|stop ID" ;;
esac
id=$2
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && $id != *..* ]] || fail "bad app id"
esc() { local s=${1:0:600} c o=''; s=${s//\\/\\\\}; s=${s//\"/\\\"}; for ((i = 0; i < ${#s}; i++)); do c=${s:i:1}; [[ $c < ' ' ]] || o+=$c; done; printf '%s' "$o"; }
js() { printf '"%s"' "$(esc "$1")"; }
jarr() { local o='' x; for x in "$@"; do o+="${o:+,}$(js "$x")"; done; printf '[%s]' "$o"; }
sctl() { timeout -k 1 10 systemctl --user --no-ask-password "$@"; }
# state runs pacman on every app tap: low priority, as apps.sh list
[[ $verb == state ]] && { renice -n 10 -p $$ >/dev/null 2>&1 || true; command -v ionice >/dev/null 2>&1 && ionice -c3 -p $$ 2>/dev/null || true; }

# the app as the Apps page lists it (same scan, same filters): name, entry file, package
info=$(bash -p "$here/apps.sh" info "$id" 2>/dev/null) || info=''
jget() { python3 -I -c 'import json,sys; v=json.loads(sys.argv[1]).get(sys.argv[2]); print("" if v is None else v)' "$info" "$1" 2>/dev/null; }
[[ $info == '{"id":'* ]] || fail "no such app"
name=$(jget name) path=$(jget path) pkg=$(jget package)
[[ -f $path ]] || fail "no such app"
exec_line=$(sed -n '/^\[Desktop Entry\]/,/^\[/{/^Exec=/{s/^Exec=//p;q}}' -- "$path" 2>/dev/null) || exec_line=''

# unit keys: the ID, and the command's name when it is the app's own (not a shell or a launcher)
keys=("$(systemd-escape -- "$id")")
cmd=${exec_line%% *}; cmd=${cmd##*/}
case $cmd in '' | sh | bash | env | flatpak | uwsm | uwsm-app | app2unit | omamobile-launch | xdg-terminal-exec | *omarchy*) ;;
  *) # only when the command is the app's own program: the same package owns it (never a browser, interpreter or terminal
     # some other app shares)
     if [[ $cmd =~ ^[A-Za-z0-9._+-]{1,64}$ && -n $pkg ]] && cp=$(command -v -- "$cmd" 2>/dev/null) \
        && [[ $(timeout 5 pacman -Qqo -- "$cp" 2>/dev/null | sed -n 1p) == "$pkg" ]]; then
       keys+=("$(systemd-escape -- "$cmd")")
     fi ;; esac
# running units of this app: under app*.slice, and named app-<launcher>-<key>-<hex>.scope or app-<launcher>-<key>@<x>.service
app_units() {
  local u k mid hit
  sctl list-units --plain --no-legend --state=running 'app-*.scope' 'app-*.service' 2>/dev/null | awk '{print $1}' | while read -r u; do
    hit=0 mid=''
    if [[ $u =~ ^app-[^-]+-(.+)-[[:alnum:]]+\.scope$ || $u =~ ^app-[^-]+-(.+)@[^@]*\.service$ ]]; then
      mid=${BASH_REMATCH[1]}
      for k in "${keys[@]}"; do [[ $mid == "$k" ]] && { hit=1; break; }; done
    fi
    # the app drawer and Open start apps as `uwsm-app -- gtk-launch ID.desktop`: the unit is named after gtk-launch, and
    # gtk-launch puts the entry in the app's environment (GIO_LAUNCHED_DESKTOP_FILE)
    # only a unit named after gtk-launch: a browser or terminal scope can hold children that inherited the variable
    ((hit)) || { [[ ${mid:-} == 'gtk\x2dlaunch' ]] && [[ $(launched_id "$u") == "$id" ]] && hit=1; }
    ((hit)) || continue
    [[ $(sctl show -P Slice -- "$u" 2>/dev/null) == app*.slice ]] && echo "$u"
  done
}
# the desktop ID gtk-launch recorded for a unit's processes (folded as apps.sh folds IDs), or nothing
launched_id() {
  local found=''
  local cg procs p
  cg=$(sctl show -P ControlGroup -- "$1" 2>/dev/null) || return 0
  [[ -n $cg ]] || return 0
  procs=${OMAMOBILE_APPMGR_CGROOT:-/sys/fs/cgroup}$cg/cgroup.procs
  [[ -r $procs ]] || return 0
  while read -r p; do
    [[ $p =~ ^[0-9]+$ ]] || continue
    # only the process gtk-launch started (its own PID in GIO_LAUNCHED_DESKTOP_FILE_PID): children inherit the variable
    local v f='' fp=''
    { while IFS= read -r -d '' v; do
        case $v in GIO_LAUNCHED_DESKTOP_FILE=*) f=${v#*=} ;; GIO_LAUNCHED_DESKTOP_FILE_PID=*) fp=${v#*=} ;; esac
      done <"${OMAMOBILE_APPMGR_PROC:-/proc}/$p/environ"; } 2>/dev/null
    [[ $fp == "$p" && $f == */applications/*.desktop ]] || continue
    f=${f#*/applications/}; f=${f%.desktop}; f=${f//\//-}
    # two different apps in one unit: ambiguous, so none (never stop or freeze on a guess)
    [[ -n ${found:-} && $found != "$f" ]] && return 0
    found=$f
  done <"$procs"
  [[ -n $found ]] && printf '%s\n' "$found"
  return 0
}

if [[ $verb == stop ]]; then
  mapfile -t units < <(app_units)
  ((${#units[@]})) || fail "the app is not running in its own unit: nothing to stop"
  for u in "${units[@]}"; do sctl stop -- "$u" >/dev/null 2>&1 || fail "could not stop $(esc "$u")"; done
  printf '{"ok":true,"stopped":%s}\n' "$(jarr "${units[@]}")"
  exit 0
fi

# state
mapfile -t units < <(app_units)
printf '{"id":%s,"name":%s,"package":%s,"units":%s}\n' "$(js "$id")" "$(js "$name")" "$(js "$pkg")" "$(jarr "${units[@]}")"
