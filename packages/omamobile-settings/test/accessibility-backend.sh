#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/accessibility.sh on a scratch HOME with stand-ins for omarchy-display-text-size, omarchy-hyprland-toggle and
# hyprctl. Nothing real is touched: PATH holds only a directory of the stubs and links to a few base tools (no real
# Omarchy command or Hyprland is reachable), and HYPRLAND_INSTANCE_SIGNATURE points at nothing.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
H=$tmp/home; mkdir -p "$H/.config/omarchy" "$tmp/bin" "$tmp/base"
for t in bash awk sed grep cat rm cp mkdir timeout sleep env id dirname; do
  p=$(command -v "$t") && ln -s "$p" "$tmp/base/$t"
done
export T=$tmp
# text size: writes base-size under [font] like the real command, `reset` drops the line; logs each call
cat > "$tmp/bin/omarchy-display-text-size" <<'EOT'
#!/bin/bash
echo "text $*" >> "$T/calls"
f=$HOME/.config/omarchy/shell.toml
[ -n "${TEXTFAIL:-}" ] && exit 1
[ -n "${TEXTSTUCK:-}" ] && exit 0
[ -n "${TEXTLATE:-}" ] && { printf '[font]\nbase-size = %s\n' "$1" > "$f"; exit 1; }
if [ "$1" = reset ]; then [ -f "$f" ] && sed -i '/^base-size/d' "$f"; exit 0; fi
printf '[font]\nbase-size = %s\n' "$1" > "$f"
EOT
cat > "$tmp/bin/omarchy-hyprland-toggle" <<'EOT'
#!/bin/bash
echo "toggle $*" >> "$T/calls"
f=$HOME/.local/state/omarchy/toggles/hypr/$1.lua
[ -n "${ANIMSTUCK:-}" ] && exit 0
case $2 in on) mkdir -p "${f%/*}"; echo x > "$f" ;; off) rm -f "$f" ;; esac
[ -n "${TOGGLEFAIL:-}" ] && [ ! -e "$T/failed-once" ] && { : > "$T/failed-once"; exit 1; }
exit 0
EOT
# hyprctl: answers like Hyprland 0.57 (`bool: true`), from the flag file; DOWN = no Hyprland
cat > "$tmp/bin/hyprctl" <<'EOT'
#!/bin/bash
[ -n "${DOWN:-}" ] && exit 1
[ -n "${STALE:-}" ] && { echo "bool: true"; exit 0; }
[ "$1 $2" = "getoption animations:enabled" ] || exit 1
if [ -n "${INTFORM:-}" ]; then p=int; y=1; n=0; else p=bool; y=true; n=false; fi
if [ -f "$HOME/.local/state/omarchy/toggles/hypr/no-animations.lua" ]; then echo "$p: $n"; else echo "$p: $y"; fi
echo "set: true"
EOT
chmod +x "$tmp/bin/"*
run() { env -i HOME="$H" PATH="$tmp/bin:$tmp/base" HYPRLAND_INSTANCE_SIGNATURE="${SIG-none}" XDG_RUNTIME_DIR="$tmp" T="$tmp" \
  TEXTFAIL="${TEXTFAIL:-}" TEXTSTUCK="${TEXTSTUCK:-}" TEXTLATE="${TEXTLATE:-}" INTFORM="${INTFORM:-}" ANIMSTUCK="${ANIMSTUCK:-}" DOWN="${DOWN:-}" STALE="${STALE:-}" TOGGLEFAIL="${TOGGLEFAIL:-}" bash "$src/backends/accessibility.sh" "$@"; }
check() { [[ $1 == "$2" ]] || { echo "FAIL ($3): got: $1 want: $2" >&2; exit 1; }; }
ok='{"text":{"available":true,"size":%s,"sizes":[12,14,16,18]},"animations":{"available":true,"on":%s}}'

check "$(run get)" "$(printf "$ok" 12 true)" "defaults"
check "$(run set text 16)" "$(printf "$ok" 16 true)" "set text 16"
grep -qx 'text 16' "$T/calls" || { echo "FAIL: text command not called with 16" >&2; exit 1; }
check "$(run set text 12)" "$(printf "$ok" 12 true)" "default is reset"
grep -qx 'text reset' "$T/calls" || { echo "FAIL: 12 must call reset" >&2; exit 1; }
check "$(run set animations off)" "$(printf "$ok" 12 false)" "animations off"
grep -qx 'toggle no-animations on' "$T/calls" || { echo "FAIL: off must turn the no-animations flag on" >&2; exit 1; }
check "$(DOWN=1 run get)" "$(printf "$ok" 12 false)" "no Hyprland: read the flag file"
check "$(run set animations on)" "$(printf "$ok" 12 true)" "animations on"
[[ ! -e $H/.local/state/omarchy/toggles/hypr/no-animations.lua ]] || { echo "FAIL: flag left behind" >&2; exit 1; }

check "$(INTFORM=1 run set animations off)" "$(printf "$ok" 12 false)" "int form of the answer"
# no Hyprland session: the flag is saved, and the answer says nothing confirmed it took now
check "$(SIG= DOWN=1 run set animations on)" "$(printf "$ok" 12 true | sed 's/}$/,"error":"no running Hyprland answered; saved for its next start"}/')" "no Hyprland session: set saves the flag and says it is unconfirmed"
# a running Hyprland that does not answer: never the flag file just written, and the flag is put back
check "$(DOWN=1 run set animations off)" '{"text":{"available":true,"size":12,"sizes":[12,14,16,18]},"animations":{"available":true,"on":true},"error":"Hyprland did not change its animations"}' "Hyprland silent after set"
[[ ! -e $H/.local/state/omarchy/toggles/hypr/no-animations.lua ]] || { echo "FAIL: flag not put back (silent)" >&2; exit 1; }
# a reload that does not show: error, the flag is put back
check "$(STALE=1 run set animations off)" '{"text":{"available":true,"size":12,"sizes":[12,14,16,18]},"animations":{"available":true,"on":true},"error":"Hyprland did not change its animations"}' "stale live value"
[[ ! -e $H/.local/state/omarchy/toggles/hypr/no-animations.lua ]] || { echo "FAIL: flag not put back (stale)" >&2; exit 1; }
# the toggle wrote the flag, then failed (its reload): error, and the flag is put back
check "$(TOGGLEFAIL=1 run set animations off)" '{"text":{"available":true,"size":12,"sizes":[12,14,16,18]},"animations":{"available":true,"on":true},"error":"the animations toggle failed"}' "toggle fails"
[[ ! -e $H/.local/state/omarchy/toggles/hypr/no-animations.lua ]] || { echo "FAIL: flag not put back (toggle failed)" >&2; exit 1; }
# the command ends non-zero after doing its work: the read-back decides
check "$(TEXTLATE=1 run set text 14)" "$(printf "$ok" 14 true)" "late non-zero exit"
# Default from a hand-set size keeps the other [font] keys
printf '[font]\nfamily = X\nbase-size = 15\n' > "$H/.config/omarchy/shell.toml"
check "$(run set text 12)" "$(printf "$ok" 12 true)" "default from a hand-set size"
grep -qx 'family = X' "$H/.config/omarchy/shell.toml" || { echo "FAIL: other font keys lost" >&2; exit 1; }

# a shell.toml with other sections and a base-size set by hand
printf '[bar]\nheight = 3\n[font] # sizes\nbase-size = 15  # mine\n[other]\nbase-size = 99\n' > "$H/.config/omarchy/shell.toml"
check "$(run get)" "$(printf "$ok" 15 true)" "hand-set size under [font] only"
printf '[font]\nbase-size = big\n' > "$H/.config/omarchy/shell.toml"
check "$(run get)" "$(printf "$ok" -1 true)" "unreadable size"
rm -f "$H/.config/omarchy/shell.toml"

# errors: bad input never reaches a command
: > "$T/calls"
for args in "set text 13" "set text 1;rm" "set animations maybe" "set volume 1" "set text" "get x" "nope"; do
  out=$(run $args) && rc=0 || rc=$?
  check "$rc" 2 "rejects: $args"; [[ $out == '{"error":'* ]] || { echo "FAIL: $args gave $out" >&2; exit 1; }
done
[[ ! -s $T/calls ]] || { echo "FAIL: a rejected call ran a command" >&2; exit 1; }

# a set that does not take answers with the value read back and an error
check "$(TEXTSTUCK=1 run set text 18)" '{"text":{"available":true,"size":12,"sizes":[12,14,16,18]},"animations":{"available":true,"on":true},"error":"the text size did not change"}' "text stuck"
check "$(TEXTFAIL=1 run set text 18)" '{"text":{"available":true,"size":12,"sizes":[12,14,16,18]},"animations":{"available":true,"on":true},"error":"the text size command failed"}' "text fails"
check "$(ANIMSTUCK=1 run set animations off)" '{"text":{"available":true,"size":12,"sizes":[12,14,16,18]},"animations":{"available":true,"on":true},"error":"Hyprland did not change its animations"}' "animations stuck"

# without Omarchy's commands both controls read as unavailable, and a set says why
rm "$tmp/bin/omarchy-display-text-size" "$tmp/bin/omarchy-hyprland-toggle"
check "$(run get)" '{"text":{"available":false},"animations":{"available":false}}' "no Omarchy commands"
out=$(run set text 14) && rc=0 || rc=$?
check "$rc" 2 "set without the command"
check "$out" "{\"error\":\"Omarchy's text size command is not installed\"}" "set without the command says why"
echo "accessibility backend: ok"
