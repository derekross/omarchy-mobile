#!/bin/bash
# SPDX-License-Identifier: MIT
# Accessibility settings for the Settings app. Prints one line of JSON. Both controls drive Omarchy's own commands, so
# Settings is never a second writer:
#   accessibility.sh get                 {"text":{"available":true,"size":12,"sizes":[12,14,16,18]},
#                                         "animations":{"available":true,"on":true}}
#   accessibility.sh set text N          N is 12 (the default), 14, 16 or 18. omarchy-display-text-size N, or `reset`
#                                        for 12: the Omarchy shell's font base-size (~/.config/omarchy/shell.toml
#                                        [font]), GNOME/GTK's text-scaling-factor and the terminals' font size, together.
#                                        The answer is read back from shell.toml.
#   accessibility.sh set animations on|off
#                                        Omarchy's no-animations Hyprland flag (omarchy-hyprland-toggle, the same file
#                                        `omarchy toggle animations` writes; on = animations, so the flag is the
#                                        opposite). It also turns off blur and shadows, and Hyprland reloads its config.
#                                        The answer is read back from the running Hyprland (animations:enabled), else
#                                        from the flag file when no Hyprland answers; then the flag is kept for the next
#                                        start and the answer carries "no running Hyprland answered" as its error.
# A control whose Omarchy command is missing reads {"available":false}. A set that does not read back as asked
# answers with the value read and an "error". Only what is named above is read back: the GTK factor and the terminal
# sizes are Omarchy's command's own business and are not checked here. Every command runs under `timeout`.
# The environment may hold stand-ins for hyprctl, omarchy-hyprland-toggle and omarchy-display-text-size first on PATH
# (tests); HOME is where the files are read.
set -euo pipefail
set +x
verb=${1:-}; key=${2:-}; value=${3:-}
fail() { printf '{"error":"%s"}\n' "$1"; exit 2; }
sizes=(12 14 16 18)
case $verb in
  get) [[ $# -eq 1 ]] || fail "usage: get | set text N | set animations on|off" ;;
  set)
    [[ $# -eq 3 ]] || fail "usage: get | set text N | set animations on|off"
    case $key in
      text) [[ " ${sizes[*]} " == *" $value "* ]] || fail "text size must be 12, 14, 16 or 18" ;;
      animations) [[ $value == on || $value == off ]] || fail "animations must be on or off" ;;
      *) fail "usage: get | set text N | set animations on|off" ;;
    esac ;;
  *) fail "usage: get | set text N | set animations on|off" ;;
esac
export OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}

# Settings started outside the graphical session (for example over SSH) has no HYPRLAND_INSTANCE_SIGNATURE: take the
# newest $XDG_RUNTIME_DIR/hypr/<sig>/.socket.sock, as display.sh does.
find_hypr() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && return 0
  local d best='' sig
  for d in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/; do
    [[ -S $d.socket.sock ]] || continue
    if [[ -z $best || $d.socket.sock -nt $best.socket.sock ]]; then best=$d; fi
  done
  [[ -n $best ]] || return 0
  sig=${best%/}; sig=${sig##*/}
  export HYPRLAND_INSTANCE_SIGNATURE=$sig
}
find_hypr

have() { command -v "$1" >/dev/null 2>&1; }
flagfile=$HOME/.local/state/omarchy/toggles/hypr/no-animations.lua

# The shell's base-size under [font] in ~/.config/omarchy/shell.toml, read the way omarchy-display-text-size reads it;
# 12 (Omarchy's default) when it is not set. A value that is not a whole number reads as -1 (set elsewhere by hand).
text_size() {
  local f=$HOME/.config/omarchy/shell.toml v=''
  if [[ -f $f ]]; then
    v=$(awk '
      /^[[:space:]]*\[/ { in_font = ($0 ~ /^[[:space:]]*\[font\]([[:space:]]|$)/); next }
      in_font && /^[[:space:]]*base-size[[:space:]]*=/ {
        v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]*(#.*)?$/, "", v); print v; exit
      }' "$f" 2>/dev/null || true)
  fi
  [[ -z $v ]] && { echo 12; return; }
  [[ $v =~ ^[0-9]{1,3}$ ]] && { echo $((10#$v)); return; }
  echo -1
}

# true or false: the running Hyprland's animations:enabled, else the flag file (the config Hyprland loads next).
# With `live` it reads only Hyprland and prints nothing when Hyprland does not answer.
animations_on() {
  local out
  if have hyprctl && out=$(timeout 2 hyprctl getoption animations:enabled 2>/dev/null) && [[ $out =~ (int|bool):\ *(1|0|true|false) ]]; then
    case ${BASH_REMATCH[2]} in 1|true) echo true ;; *) echo false ;; esac
    return
  fi
  [[ ${1:-} == live ]] && return 0
  [[ -f $flagfile ]] && echo false || echo true
}

text_json() {
  if have omarchy-display-text-size; then printf '{"available":true,"size":%s,"sizes":[12,14,16,18]}' "$(text_size)"
  else printf '{"available":false}'; fi
}

err=''; anim=''
if [[ $verb == set && $key == text ]]; then
  have omarchy-display-text-size || fail "Omarchy's text size command is not installed"
  if [[ $value == 12 ]]; then arg=reset; else arg=$value; fi
  # the read-back decides: the command can end non-zero after doing its work (its last step nudges open terminals)
  rc=0; timeout 12 omarchy-display-text-size "$arg" >/dev/null 2>&1 || rc=$?
  if [[ $(text_size) != "$value" ]]; then
    if ((rc != 0)); then err="the text size command failed"; else err="the text size did not change"; fi
  fi
elif [[ $verb == set && $key == animations ]]; then
  have omarchy-hyprland-toggle || fail "Omarchy's Hyprland toggle command is not installed"
  if [[ $value == on ]]; then flag=off; want=true; else flag=on; want=false; fi
  if [[ -f $flagfile ]]; then was=on; else was=off; fi
  # A running Hyprland must show the change: with one (a socket under $XDG_RUNTIME_DIR/hypr) only its own answer
  # counts, never the flag file the toggle just wrote. Without one, the flag file is what the next start loads.
  live=''; [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && have hyprctl && live=live
  # Within the app's 20 s kill: the toggle gets 7 s, the reads stop 13 s after the start, the rollback gets 3 s and
  # the last read 2 s (at most 18 s).
  SECONDS=0
  timeout 7 omarchy-hyprland-toggle no-animations "$flag" >/dev/null 2>&1 || err="the animations toggle failed"
  if [[ -z $err ]]; then
    while :; do
      anim=$(animations_on $live)
      [[ $anim == "$want" ]] && break
      ((SECONDS < 11)) || break
      sleep 0.5
    done
    [[ $anim == "$want" ]] || err="Hyprland did not change its animations"
  fi
  # no running Hyprland to ask: the flag is saved for the next start, but nothing confirmed it took now
  nolive=''; [[ -z $err && -z $live ]] && nolive=1
  if [[ -n $err ]]; then
    # put the flag back (the toggle writes it before its reload), so the next start does not bring up what the running
    # session did not take
    if [[ -f $flagfile ]]; then now=on; else now=off; fi
    if [[ $now != "$was" ]]; then timeout 3 omarchy-hyprland-toggle no-animations "$was" >/dev/null 2>&1 || true; fi
    anim=''
  fi
fi
anim_json() {
  if have omarchy-hyprland-toggle; then printf '{"available":true,"on":%s}' "${anim:-$(animations_on)}"
  else printf '{"available":false}'; fi
}
[[ -n ${nolive:-} ]] && err="no running Hyprland answered; saved for its next start"
if [[ -n $err ]]; then
  printf '{"text":%s,"animations":%s,"error":"%s"}\n' "$(text_json)" "$(anim_json)" "$err"
else
  printf '{"text":%s,"animations":%s}\n' "$(text_json)" "$(anim_json)"
fi
