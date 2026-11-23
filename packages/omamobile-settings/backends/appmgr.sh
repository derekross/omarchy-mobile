#!/bin/bash
# SPDX-License-Identifier: MIT
# App manager for the Settings app's Apps page: one app's battery policy, stop, and uninstall. Prints one line of JSON.
#   appmgr.sh state ID             {"id","name","kind","package","units":[..],"policy","doze","removable","why",
#                                   "targets":[{"name","version","protected","why"}],"required_by","optional_for","hash",
#                                   "reinstall"}
#       kind: package (pacman), webapp / tui (Omarchy's web app and TUI launchers), user (a launcher in your folder),
#       other (Flatpak and the rest: not removed here)
#   appmgr.sh policy ID unrestricted|optimized|restricted     saved in $XDG_CONFIG_HOME/omamobile/app-policy
#   appmgr.sh stop ID              systemctl --user stop of the app's own units (app*.slice, its ID or command in the name)
#   appmgr.sh remove ID HASH       uninstalls; HASH is state's "hash", the target list the user confirmed
# Battery policy (read by omamobile-dozed): unrestricted = never frozen, optimized = frozen in Doze (default),
# restricted = frozen as soon as the screen is off and locked, and kept frozen through Doze's maintenance windows.
# Lines in app-policy: "ID<TAB>policy<TAB>unit-key ..." (optimized is not written). The unit keys are the names
# systemd gives the app's units (app-<launcher>-<KEY>-<random>.scope or app-<launcher>-<KEY>@<random>.service).
# Uninstall reuses Omarchy's own scripts, as omarchy-remove-launcher-entry dispatches: a web app goes through
# omarchy-webapp-remove, a TUI through omarchy-tui-remove, a pacman package through omarchy-pkg-drop in the root helper
# (omamobile-app-remove@PKG:HASH.service, after app-guard allows it; see libexec/app-remove), a launcher in your own
# folder is deleted. Never by process name, never anything outside app*.slice.
set -euo pipefail
set +x
export LC_ALL=C
export OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
lib=${OMAMOBILE_APPMGR_LIB:-/usr/lib/omamobile-settings}
run_dir=${OMAMOBILE_APPMGR_RUN:-/run/omamobile-settings}
verb=${1:-}
fail() { printf '{"error":"%s"}\n' "$1"; exit 2; }
case $verb in
  state | stop) [[ $# -eq 2 ]] || fail "usage: state ID|policy ID P|stop ID|remove ID HASH" ;;
  policy | remove) [[ $# -eq 3 ]] || fail "usage: state ID|policy ID P|stop ID|remove ID HASH" ;;
  *) fail "usage: state ID|policy ID P|stop ID|remove ID HASH" ;;
esac
id=$2
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && $id != *..* ]] || fail "bad app id"
esc() { local s=${1:0:600} c o=''; s=${s//\\/\\\\}; s=${s//\"/\\\"}; for ((i = 0; i < ${#s}; i++)); do c=${s:i:1}; [[ $c < ' ' ]] || o+=$c; done; printf '%s' "$o"; }
js() { printf '"%s"' "$(esc "$1")"; }
jarr() { local o='' x; for x in "$@"; do o+="${o:+,}$(js "$x")"; done; printf '[%s]' "$o"; }
sctl() { timeout -k 1 10 systemctl --user --no-ask-password "$@"; }
# state runs pacman a few times on every app tap (1.9 s on the phone): low priority, as apps.sh list
[[ $verb == state ]] && { renice -n 10 -p $$ >/dev/null 2>&1 || true; command -v ionice >/dev/null 2>&1 && ionice -c3 -p $$ 2>/dev/null || true; }

# the app as the Apps page lists it (same scan, same filters): name, entry file, package
info=$(bash -p "$here/apps.sh" info "$id" 2>/dev/null) || info=''
jget() { python3 -I -c 'import json,sys; v=json.loads(sys.argv[1]).get(sys.argv[2]); print("" if v is None else v)' "$info" "$1" 2>/dev/null; }
[[ $info == '{"id":'* ]] || fail "no such app"
name=$(jget name) path=$(jget path) pkg=$(jget package)
[[ -f $path ]] || fail "no such app"
exec_line=$(sed -n '/^\[Desktop Entry\]/,/^\[/{s/^Exec=//p}' -- "$path" 2>/dev/null | head -n 1)
data_home=${XDG_DATA_HOME:-}; [[ $data_home == /* ]] || data_home=$HOME/.local/share
kind=other
own=false; [[ ${path%/*} == "$data_home/applications" ]] && own=true
# Omarchy's web apps and TUIs are launchers in your own folder (a packaged entry with such an Exec is a package)
if $own && [[ $exec_line =~ omarchy-launch-webapp|omarchy-webapp-handler ]]; then kind=webapp
elif $own && [[ $exec_line =~ (^|[[:space:]])(\$TERMINAL|xdg-terminal-exec)[[:space:]].*-e([[:space:]]|$) ]]; then kind=tui
elif $own; then kind=user
elif [[ -n $pkg ]]; then kind=package; fi

# unit keys: the ID, and the command's name when it is the app's own (not a shell or a launcher)
keys=("$(systemd-escape -- "$id")")
cmd=${exec_line%% *}; cmd=${cmd##*/}
case $cmd in '' | sh | bash | env | flatpak | uwsm | uwsm-app | app2unit | omamobile-launch | xdg-terminal-exec | *omarchy*) ;;
  *) # only when the command is the app's own program: the same package owns it (never a browser, interpreter or terminal
     # some other app shares)
     if [[ $cmd =~ ^[A-Za-z0-9._+-]{1,64}$ && -n $pkg ]] && cp=$(command -v -- "$cmd" 2>/dev/null) \
        && [[ $(timeout 5 pacman -Qqo -- "$cp" 2>/dev/null | head -n 1) == "$pkg" ]]; then
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

conf=${XDG_CONFIG_HOME:-}; [[ $conf == /* ]] || conf=$HOME/.config
pfile=$conf/omamobile/app-policy
policy_of() {
  local a p
  [[ -f $pfile && ! -L $pfile ]] || { echo optimized; return; }
  while IFS=$'\t' read -r a p _ || [[ -n $a ]]; do [[ $a == "$id" && $p =~ ^(unrestricted|restricted)$ ]] && { echo "$p"; return; }; done <"$pfile"
  echo optimized
}

if [[ $verb == policy ]]; then
  want=$3
  [[ $want =~ ^(unrestricted|optimized|restricted)$ ]] || fail "bad policy"
  [[ ! -L $conf/omamobile && ! -L $pfile ]] || fail "the policy file is a link; not written"
  mkdir -p -- "$conf/omamobile"
  # one writer at a time: two quick taps must not lose another app's line
  { exec 9>"$conf/omamobile/.app-policy.lock"; } 2>/dev/null || fail "cannot write the policy"
  flock -w 5 9 || fail "the policy file is busy"
  t=$(mktemp -- "$conf/omamobile/.app-policy.XXXXXX") || fail "cannot write the policy"
  if [[ -f $pfile ]]; then awk -F'\t' -v id="$id" '$1 != id' "$pfile" >"$t" || { rm -f -- "$t"; fail "cannot read the policy file"; }; fi
  [[ $want == optimized ]] || printf '%s\t%s\t%s\n' "$id" "$want" "${keys[*]}" >>"$t"
  mv -f -- "$t" "$pfile" || { rm -f -- "$t"; fail "cannot write the policy"; }
  printf '{"ok":true,"policy":"%s"}\n' "$(policy_of)"
  exit 0
fi

if [[ $verb == stop ]]; then
  mapfile -t units < <(app_units)
  ((${#units[@]})) || fail "the app is not running in its own unit: nothing to stop"
  for u in "${units[@]}"; do sctl stop -- "$u" >/dev/null 2>&1 || fail "could not stop $(esc "$u")"; done
  printf '{"ok":true,"stopped":%s}\n' "$(jarr "${units[@]}")"
  exit 0
fi

# uninstall plan
pkgver='' removable=false why='' hash='' reinstall='' targets_json='' reqby='' optfor=''
case $kind in
  package)
    verdict=''
    while IFS=$'\t' read -r k a b c d; do
      case $k in
        ok | refuse) verdict=$k; why=$a ;;
        hash) hash=$a ;;
        target) targets_json+="${targets_json:+,}{\"name\":$(js "$a"),\"version\":$(js "$b"),\"protected\":$([[ $c == 1 ]] && echo true || echo false),\"why\":$(js "$d")}"
                [[ $a == "$pkg" ]] && pkgver=$b ;;
        requiredby) reqby=$a ;;
        optionalfor) optfor=$a ;;
      esac
    done < <("$lib/app-guard" "$pkg" 2>/dev/null)
    [[ -n $verdict ]] || why="Settings could not check this package"
    [[ $verdict == ok ]] && removable=true
    # a repository package comes back with pacman -S; a local one (pacman -U) only from its file or pacman's cache
    if [[ -n $targets_json ]]; then
      rc=0; si=$(timeout 10 pacman -Si -- "$pkg" 2>&1 >/dev/null) || rc=$?
      if ((rc == 0)); then reinstall="sudo pacman -S $pkg"
      elif [[ $si == *"was not found"* ]]; then
        cached=$(compgen -G "/var/cache/pacman/pkg/$pkg-${pkgver:-*}-*.pkg.tar.*" | grep -v '\.sig$' | head -n 1) || cached=''
        if [[ -n $cached ]]; then reinstall="sudo pacman -U $cached"
        else reinstall="not in a repository and not in pacman's cache: keep its package file if you want it back"; fi
      else reinstall="sudo pacman -S $pkg (if it came from a repository)"; fi
    fi
    ;;
  webapp | tui | user)
    # your own copy of a launcher a system entry also has (an override, e.g. foot.desktop): deleting it is not an uninstall
    shadow=''
    IFS=: read -ra dd <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    dd+=("$HOME/.nix-profile/share")   # apps.sh scans it too
    # by desktop ID, as apps.sh folds it (sub/foo.desktop is sub-foo): a nested system entry is found too
    for d in "${dd[@]}"; do
      [[ -n $d && ${d%/} != "${data_home%/}" && -d $d/applications ]] || continue
      while IFS= read -r -d '' f; do
        fid=${f#"$d/applications/"}; fid=${fid%.desktop}; fid=${fid//\//-}
        [[ $fid == "$id" ]] && { shadow=$f; break 2; }
      done < <(find -H "$d/applications" \( -type f -o -type l \) -name '*.desktop' -print0 2>/dev/null)
    done
    if [[ -n $shadow ]]; then
      sp=$(timeout 5 pacman -Qqo -- "$shadow" 2>/dev/null | head -n 1) || sp=''
      why="this is your own copy of a system launcher ($shadow${sp:+, package $sp}); delete the copy in ${path%/*} to manage the system app here"
    else removable=true; why=''; fi ;;
  *) why="Settings cannot uninstall this kind of app (not from a pacman package or an Omarchy launcher)" ;;
esac

if [[ $verb == state ]]; then
  mapfile -t units < <(app_units)
  # doze: "missing" when no Doze daemon is installed (the page then shows no Battery choices), else on/off by its toggle
  doze=missing
  if command -v omamobile-dozed >/dev/null 2>&1 || [[ -x ${OMAMOBILE_APPMGR_DOZED:-/usr/local/bin/omamobile-dozed} ]]; then
    doze=off; omarchy-toggle-enabled omamobile-doze >/dev/null 2>&1 && doze=on
  fi
  printf '{"id":%s,"name":%s,"kind":"%s","package":%s,"units":%s,"policy":"%s","doze":"%s","removable":%s,"why":%s,"targets":[%s],"required_by":%s,"optional_for":%s,"hash":"%s","reinstall":%s}\n' \
    "$(js "$id")" "$(js "$name")" "$kind" "$(js "$pkg")" "$(jarr "${units[@]}")" "$(policy_of)" "$doze" "$removable" "$(js "$why")" \
    "$targets_json" "$(js "$reqby")" "$(js "$optfor")" "$hash" "$(js "$reinstall")"
  exit 0
fi

# remove
want=$3
[[ $removable == true ]] || fail "$(esc "$why")"
base=${path##*/}; base=${base%.desktop}
case $kind in
  webapp) OMARCHY_REMOVE_NOTIFY=false timeout 30 omarchy-webapp-remove "$base" >/dev/null 2>&1 || fail "omarchy-webapp-remove failed" ;;
  tui) OMARCHY_REMOVE_NOTIFY=false timeout 30 omarchy-tui-remove "$base" >/dev/null 2>&1 || fail "omarchy-tui-remove failed" ;;
  user) rm -f -- "$path" || fail "could not delete the launcher"; update-desktop-database "${path%/*}" >/dev/null 2>&1 || true ;;
  package)
    [[ $want =~ ^[0-9a-f]{16}$ && $want == "$hash" ]] || fail "what would be removed changed since you confirmed; open the app again"
    unit="omamobile-app-remove@$(systemd-escape -- "$pkg"):$want.service"
    rm -f -- "$run_dir/app-remove.$want" 2>/dev/null || true   # never read an earlier attempt's answer (root's file: may stay)
    mark=$(mktemp) || fail "cannot start the uninstall"
    timeout -k 5 330 systemctl --no-ask-password start -- "$unit" >/dev/null 2>&1 || true
    last=''
    # only an answer written for this run counts (an earlier run with the same hash leaves its file behind)
    [[ $run_dir/app-remove.$want -nt $mark ]] && { last=$(head -c 2048 -- "$run_dir/app-remove.$want" 2>/dev/null | head -n 1) || last=''; }
    rm -f -- "$mark"
    # pacman is the judge: the package must be gone, and the helper's line must be about this request
    if timeout 10 pacman -Q -- "$pkg" >/dev/null 2>&1; then
      w=$(python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["why"] if d.get("hash")==sys.argv[2] else "")' "$last" "$want" 2>/dev/null) || w=''
      fail "$(esc "${w:-the uninstall did not run (permission or service failure)}")"
    fi
    # the helper must report this request done (it checks every target is gone)
    okl=$(python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); print("yes" if d.get("hash")==sys.argv[2] and d.get("ok") is True else d.get("why",""))' "$last" "$want" 2>/dev/null) || okl=''
    [[ $okl == yes ]] || fail "$(esc "${okl:-the uninstall result could not be read}")"
    ;;
esac
[[ -e $path ]] && [[ $kind != package ]] && fail "the launcher is still there"
printf '{"ok":true,"kind":"%s","reinstall":%s}\n' "$kind" "$(js "$reinstall")"
