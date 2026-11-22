#!/bin/bash
# SPDX-License-Identifier: MIT
# Installed apps for the Settings app's Apps page. Prints one line of JSON. Read-only, except `open`, which starts the app.
#   apps.sh list       {"apps":[{"id":"org.foo.Bar","name":"Bar","icon":"bar","open":true},...],"partial":false,"at":EPOCH_SECONDS}
#                      sorted by name; "open":false for an ID info/open refuse (a space in it); "partial":true when the
#                      list was cut to stay under the 64 KiB the app reads
#   apps.sh cached     the last `list` answer (same line), or {"apps":null}; instant
#   apps.sh info ID    {"id":..,"name":..,"icon":..,"path":..,"package":"name"|null,"version":".."|null,"size":".."|null}
#   apps.sh open ID    {"ok":true}: starts the app with omamobile-launch (gtk-launch without it), detached;
#                      $OMAMOBILE_LAUNCH names another omamobile-launch (tests use it; default /usr/bin/omamobile-launch)
# The list is what the shell's app drawer shows: desktop entries from $XDG_DATA_HOME/applications (default ~/.local/share), then
# $XDG_DATA_DIRS/applications (default /usr/local/share:/usr/share), then ~/.nix-profile/share/applications; the
# first file of an ID wins (ID = path under the folder, .desktop dropped, / turned into -). An entry is left out when
# its [Desktop Entry] says Hidden=true or NoDisplay=true, when OnlyShowIn does not name, or NotShowIn names, one of
# $XDG_CURRENT_DESKTOP:$XDG_SESSION_DESKTOP:$DESKTOP_SESSION, or when Omarchy's launcher.hides lists its ID: the same
# rules as Omarchy's shell/services/hidden-entries.sh and AppLibrary.qml. Name is the plain Name= (the ID without one).
# info asks pacman which package owns the entry file (pacman -Qo, then -Qi for its version and installed size); a
# file no package owns (a web app, a Flatpak export) has "package":null. Nothing is ever installed or removed.
# list runs at nice 10 and idle I/O priority and is saved to $XDG_CACHE_HOME/omamobile/apps.json (default ~/.cache).
set -euo pipefail
set +x
export LC_ALL=C
verb=${1:-}
fail() { printf '{"error":"%s"}\n' "$1"; exit 2; }
case $verb in
  list | cached) [[ $# -eq 1 ]] || fail "usage: list|cached|info ID|open ID" ;;
  info | open) [[ $# -eq 2 ]] || fail "usage: list|cached|info ID|open ID" ;;
  *) fail "usage: list|cached|info ID|open ID" ;;
esac
id_re='^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'
if [[ $verb == info || $verb == open ]]; then
  want=$2
  [[ $want =~ $id_re && $want != *..* ]] || fail "bad app id"
fi

# JSON string body into the variable named $1: cut to 200 bytes, backslash and quote escaped, control characters
# dropped. No fork per call (the list escapes three fields per app); invalid UTF-8 is dropped once, on the whole answer.
esc_to() {
  local -n _out=$1
  local s=${2:0:${3:-200}} c i
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  _out=''
  for ((i = 0; i < ${#s}; i++)); do c=${s:i:1}; [[ $c < ' ' || $c == $'\177' ]] || _out+=$c; done
}
esc() { local r; esc_to r "$1"; printf '%s' "$r"; }
utf8() { if command -v iconv > /dev/null 2>&1; then iconv -c -f UTF-8 -t UTF-8 2> /dev/null || true; else cat; fi; }
cache_dir=${XDG_CACHE_HOME:-}
[[ $cache_dir == /* ]] || cache_dir=${HOME:-/nonexistent}/.cache
cache_dir=$cache_dir/omamobile

if [[ $verb == cached ]]; then
  line=''
  if [[ -f $cache_dir/apps.json && ! -L $cache_dir/apps.json ]]; then
    line=$(head -c 65536 -- "$cache_dir/apps.json" 2> /dev/null | head -n 1) || line=''
  fi
  re='^\{"apps":\[.*\],"partial":(true|false),"at":[0-9]+\}$'
  if [[ $line =~ $re ]]; then printf '%s\n' "$line"; else printf '{"apps":null}\n'; fi
  exit 0
fi

[[ $verb == list ]] && { renice -n 10 -p $$ > /dev/null 2>&1 || true; command -v ionice > /dev/null 2>&1 && ionice -c3 -p $$ 2> /dev/null || true; }

desktops=()
for v in "${XDG_CURRENT_DESKTOP:-}" "${XDG_SESSION_DESKTOP:-}" "${DESKTOP_SESSION:-}"; do
  IFS=":" read -ra parts <<< "$v"
  for p in "${parts[@]}"; do [[ -n $p ]] && desktops+=("$p"); done
done
# a ;-list from OnlyShowIn/NotShowIn names one of our desktops
desktop_matches() {
  local e d entries
  IFS=";" read -ra entries <<< "$1"
  for d in "${desktops[@]}"; do for e in "${entries[@]}"; do [[ -n $e && $e == "$d" ]] && return 0; done; done
  return 1
}
data_home=${XDG_DATA_HOME:-}
[[ -n $data_home ]] || data_home=${HOME:-/nonexistent}/.local/share
dirs=("$data_home/applications")
IFS=":" read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for d in "${data_dirs[@]}"; do [[ -n $d ]] && dirs+=("$d/applications"); done
dirs+=("${HOME:-/nonexistent}/.nix-profile/share/applications")

# reads one entry file into e_name, e_icon, e_hidden (true/false)
read_entry() {
  local file=$1 line key value in=0 only='' not='' hidden=false n=0
  e_name='' e_icon=''
  while IFS= read -r line || [[ -n $line ]]; do
    ((++n <= 4000)) || break
    line=${line%$'\r'}
    if [[ $line =~ ^\[(.*)\]$ ]]; then [[ ${BASH_REMATCH[1]} == "Desktop Entry" ]] && in=1 || in=0; continue; fi
    ((in)) || continue
    [[ $line == *=* ]] || continue
    key=${line%%=*} value=${line#*=}
    case $key in
      Name) [[ -z $e_name ]] && e_name=$value ;;
      Icon) [[ -z $e_icon ]] && e_icon=$value ;;
      Hidden | NoDisplay) [[ $value == true ]] && hidden=true ;;
      OnlyShowIn) only=$value ;;
      NotShowIn) not=$value ;;
    esac
  done < <(head -c 262144 -- "$file" 2> /dev/null)   # a huge entry (one endless line) is read only up to 256 KiB
  [[ -n $only ]] && ! desktop_matches "$only" && hidden=true
  [[ -n $not ]] && desktop_matches "$not" && hidden=true
  e_hidden=$hidden
}

# Omarchy's launcher.hides: one ID per line, .desktop optional
declare -A hides=()
hides_file=${OMARCHY_PATH:-/usr/share/omarchy}/default/omarchy/launcher.hides
if [[ -f $hides_file ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line#"${line%%[![:space:]]*}"}; line=${line%"${line##*[![:space:]]}"}; line=${line%.desktop}   # trimmed, as AppLibrary does
    [[ -n $line ]] && hides[$line]=1
  done < <(head -c 65536 -- "$hides_file")
fi

declare -A seen=()
rows=() bytes=0 partial=false
found=''
for dir in "${dirs[@]}"; do
  [[ -d $dir ]] || continue
  while IFS= read -r -d '' file; do
    [[ -f $file && -r $file ]] || continue    # a symlink counts when it points at a readable file
    id=${file#"$dir"/}; id=${id%.desktop}; id=${id//\//-}
    [[ -n $id ]] || continue
    [[ -n ${seen[$id]+set} ]] && continue
    seen[$id]=1
    if [[ $verb != list ]]; then
      [[ $id == "$want" ]] && { found=$file; break 2; }
      continue
    fi
    [[ -n ${hides[$id]+set} ]] && continue
    read_entry "$file"
    [[ $e_hidden == true ]] && continue
    name=${e_name:-$id}
    esc_to j_id "$id"; esc_to j_name "$name"; esc_to j_icon "$e_icon"
    key=${name:0:200}; key=${key,,}; key=${key//[[:cntrl:]]/ }
    # "open":false: an ID the app (and `info`/`open`) does not accept, e.g. one with a space; shown, but not opened from here
    [[ $id =~ $id_re && $id != *..* ]] && ok=true || ok=false
    printf -v row '%s\t{"id":"%s","name":"%s","icon":"%s","open":%s}' "$key" "$j_id" "$j_name" "$j_icon" "$ok"
    # the app reads at most 64 KiB of a backend's answer: stop before that
    ((bytes += ${#row} + 1, bytes < 60000)) || { partial=true; break 2; }
    rows+=("$row")
  done < <(find -H "$dir" \( -type f -o -type l \) -name '*.desktop' -print0 2> /dev/null | sort -z)
done

if [[ $verb == list ]]; then
  body=''
  if ((${#rows[@]})); then body=$(printf '%s\n' "${rows[@]}" | sort -t $'\t' -k1,1 -s | cut -f2- | paste -sd, -); fi
  answer=$(printf '{"apps":[%s],"partial":%s,"at":%d}' "$body" "$partial" "${EPOCHSECONDS:-0}" | utf8)
  printf '%s\n' "$answer"
  if [[ $cache_dir != /nonexistent/* ]]; then
    parent=${cache_dir%/omamobile}
    if [[ ! -L $parent && ! -L $cache_dir ]]; then
      t=''
      # a failed write (full disk) leaves no temp file behind
      { mkdir -p -- "$cache_dir" && t=$(mktemp -- "$cache_dir/.apps.XXXXXX") && printf '%s\n' "$answer" > "$t" && mv -f -- "$t" "$cache_dir/apps.json"; } 2> /dev/null \
        || { [[ -n $t ]] && rm -f -- "$t"; } 2> /dev/null || true
    fi
  fi
  exit 0
fi

[[ -n $found ]] || fail "no such app"
read_entry "$found"
[[ $e_hidden == false && -z ${hides[$want]+set} ]] || fail "no such app"

if [[ $verb == open ]]; then
  launch=${OMAMOBILE_LAUNCH:-/usr/bin/omamobile-launch}
  gtk=$(command -v gtk-launch 2> /dev/null) || gtk=''
  if [[ $launch == /* && -f $launch && -x $launch ]]; then cmd=("$launch" app "$want")
  elif [[ -n $gtk ]]; then cmd=("$gtk" "$want")
  else fail "no app launcher found"; fi
  # setsid -f answers 0 even when the program then cannot run: check it is a runnable file first
  [[ ${cmd[0]} == /* && -f ${cmd[0]} && -x ${cmd[0]} ]] || fail "the app could not be started"
  setsid -f "${cmd[@]}" < /dev/null > /dev/null 2>&1 || fail "the app could not be started"
  printf '{"ok":true}\n'
  exit 0
fi

pkg='' version='' size=''
if command -v pacman > /dev/null 2>&1; then
  pkg=$(timeout 5 pacman -Qqo -- "$found" 2> /dev/null | head -n 1) || pkg=''
  if [[ -z $pkg ]]; then
    real=$(readlink -f -- "$found" 2> /dev/null) || real=''
    [[ -n $real && $real != "$found" ]] && { pkg=$(timeout 5 pacman -Qqo -- "$real" 2> /dev/null | head -n 1) || pkg=''; }
  fi
  if [[ -n $pkg ]]; then
    while IFS= read -r line; do
      case $line in
        Version*:*) [[ -z $version ]] && { version=${line#*: }; } ;;
        "Installed Size"*:*) [[ -z $size ]] && { size=${line#*: }; } ;;
      esac
    done < <(timeout 5 pacman -Qi -- "$pkg" 2> /dev/null)
  fi
fi
js() { if [[ -n $1 ]]; then printf '"%s"' "$(esc "$1")"; else printf null; fi; }
printf '{"id":"%s","name":"%s","icon":"%s","path":"%s","package":%s,"version":%s,"size":%s}\n' \
  "$(esc "$want")" "$(esc "${e_name:-$want}")" "$(esc "$e_icon")" "$(esc_to r "$found" 1024; printf '%s' "$r")" "$(js "$pkg")" "$(js "$version")" "$(js "$size")" | utf8
