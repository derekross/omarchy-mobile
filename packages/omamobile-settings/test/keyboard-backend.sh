#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/keyboard.sh against fake input.lua files, a small xkb rules list and a fake hyprctl and gsettings
# first on PATH that log their arguments. The host's own files and tools are never touched.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/run"
cat > "$tmp/bin/hyprctl" <<'EOT'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LOG"
case "$1 $2" in
  "-j devices") cat "$FAKE_DEVICES" 2>/dev/null || exit 1 ;;
  "-j getoption") printf '{"option":"input:kb_options","str":"%s","set":true}\n' "${FAKE_OPTIONS:-}" ;;
  eval*) [[ -n ${FAKE_EVAL_FAIL:-} ]] && echo "error: no eval" || echo ok ;;
  keyword*) [[ -n ${FAKE_KEYWORD_FAIL:-} ]] && echo "error: bad" || echo ok ;;
esac
EOT
cat > "$tmp/bin/gsettings" <<'EOT'
#!/bin/bash
printf 'gsettings %s\n' "$*" >> "$FAKE_LOG"
[[ -z ${FAKE_GSETTINGS_FAIL:-} ]]
EOT
chmod +x "$tmp/bin/hyprctl" "$tmp/bin/gsettings"
cat > "$tmp/rules.lst" <<'EOT'
! layout
  us              English (US)
  gr              Greek
  de              German
  ru              Russian

! variant
  polytonic       gr: Greek (polytonic)
  intl            us: English (US, intl., with dead keys)

! option
  grp                  Switching to another layout
  grp:alt_shift_toggle Alt+Shift
  grp:caps_toggle      Caps Lock
  grp_led:caps         Caps Lock
EOT
cat > "$tmp/devices.json" <<'EOT'
{"keyboards":[{"name":"hl-virtual-keyboard-squeekboard","active_layout_index":0,"main":false},
{"name":"dell-kb7120w","active_layout_index":1,"main":true}]}
EOT
export PATH="$tmp/bin:$PATH" FAKE_LOG="$tmp/log" FAKE_DEVICES="$tmp/devices.json"
export XDG_RUNTIME_DIR="$tmp/run" HYPRLAND_INSTANCE_SIGNATURE=test
export OMAMOBILE_KBD_INPUT="$tmp/input.lua" OMAMOBILE_KBD_RULES="$tmp/rules.lst"
unset FAKE_OPTIONS FAKE_EVAL_FAIL FAKE_KEYWORD_FAIL FAKE_GSETTINGS_FAIL
run() { bash "$src/backends/keyboard.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }
has() { grep -qF -- "$2" "$1" || { echo "FAIL: $1 lacks $2" >&2; cat "$1" >&2; exit 1; }; }
hasnt() { ! grep -qF -- "$2" "$1" || { echo "FAIL: $1 has $2" >&2; exit 1; }; }

# Omarchy-style file: comments, an earlier overridden block, grp_led:caps and another option
cat > "$tmp/input.lua" <<'EOT'
-- kb_layout = "fr", a comment, never touched
hl.config({ input = { kb_layout = "de" } })
--[[ kb_layout = "ru",
     kb_options = "grp:caps_toggle" ]]
hl.config({
  input = {
    kb_layout = "us",
    kb_options = "compose:caps,grp:caps_toggle,grp_led:caps", -- keep me
    repeat_rate = 40,
  },
})
EOT
chmod 640 "$tmp/input.lua"
eq "$(run get)" '{"layouts":[{"layout":"us","variant":""}],"switchKey":"grp:caps_toggle","active":1}'

: > "$tmp/log"
eq "$(run set layouts us,gr:polytonic)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":"polytonic"}],"switchKey":"grp:caps_toggle","active":1}'
has "$tmp/input.lua" 'kb_layout = "us,gr",'
has "$tmp/input.lua" 'kb_variant = ",polytonic",'
has "$tmp/input.lua" 'kb_options = "compose:caps,grp_led:caps,grp:caps_toggle", -- keep me'
has "$tmp/input.lua" '-- kb_layout = "fr", a comment, never touched'
has "$tmp/input.lua" 'hl.config({ input = { kb_layout = "de" } })'
has "$tmp/input.lua" '     kb_options = "grp:caps_toggle" ]]'
eq "$(grep -c 'hl.config' "$tmp/input.lua")" 2
eq "$(stat -c %a "$tmp/input.lua")" 640
has "$tmp/input.lua.bak-omamobile" 'kb_layout = "us",'
has "$tmp/log" 'eval hl.config({ input = { kb_layout = "us,gr", kb_variant = ",polytonic", kb_options = "compose:caps,grp_led:caps,grp:caps_toggle" } })'
has "$tmp/log" "gsettings set org.gnome.desktop.input-sources sources [('xkb', 'us'), ('xkb', 'gr+polytonic')]"
hasnt "$tmp/log" 'reload'
eq "$(run get)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":"polytonic"}],"switchKey":"grp:caps_toggle","active":1}'

# the switch key: only the grp: part changes
eq "$(run set switch-key grp:alt_shift_toggle)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":"polytonic"}],"switchKey":"grp:alt_shift_toggle","active":1}'
has "$tmp/input.lua" 'kb_options = "compose:caps,grp_led:caps,grp:alt_shift_toggle",'
eq "$(run set switch-key none | grep -o '"switchKey":"[^"]*"')" '"switchKey":""'
has "$tmp/input.lua" 'kb_options = "compose:caps,grp_led:caps",'
run set switch-key grp:caps_toggle >/dev/null
# one layout left drops the switch key and the variant; grp_led stays
eq "$(run set layouts us)" '{"layouts":[{"layout":"us","variant":""}],"switchKey":"","active":1}'
has "$tmp/input.lua" 'kb_options = "compose:caps,grp_led:caps",'
has "$tmp/input.lua" 'kb_variant = "",'

# a non-Latin first layout is saved with a warning
eq "$(run set layouts gr,us | grep -c "\"warn\":\"the first layout is not a Latin one")" 1
eq "$(run set layouts us,gr | grep -c warn || true)" 0

# bad input never reaches the file
cp "$tmp/input.lua" "$tmp/before"
eq "$(run set layouts us,gr,de,ru,us:intl)" '{"error":"give 1 to 4 layouts"}'
eq "$(run set layouts us,xx)" '{"error":"unknown layout: xx"}'
eq "$(run set layouts us,gr:intl)" '{"error":"unknown layout: gr:intl"}'
eq "$(run set layouts 'us,gr"')" '{"error":"bad layout name"}'
eq "$(run set layouts us,us)" '{"error":"layout listed twice: us"}'
eq "$(run set layouts '')" '{"error":"give 1 to 4 layouts"}'
eq "$(run set switch-key grp:nope)" '{"error":"unknown switch key"}'
eq "$(run set switch-key 'grp:caps_toggle"')" '{"error":"unknown switch key"}'
eq "$(run set numlock on)" '{"error":"unknown key"}'
eq "$(run nonsense)" '{"error":"usage: get|set"}'
cmp -s "$tmp/input.lua" "$tmp/before" || { echo "FAIL: a rejected set changed input.lua" >&2; exit 1; }

# no kb_layout: an error, nothing appended
printf -- '-- empty\nhl.config({ input = { repeat_rate = 40 } })\n' > "$tmp/input.lua"
cp "$tmp/input.lua" "$tmp/before"
eq "$(run get)" '{"error":"input.lua has no kb_layout"}'
eq "$(run set layouts us,gr)" '{"error":"input.lua has no kb_layout"}'
cmp -s "$tmp/input.lua" "$tmp/before" || { echo "FAIL: input.lua was changed" >&2; exit 1; }
rm "$tmp/input.lua"
eq "$(run get)" '{"error":"input.lua is missing"}'

# kb_options and kb_variant absent: added on the kb_layout line's table, Omarchy's effective options kept
printf 'hl.config({\n  input = {\n    kb_layout = "us",\n  },\n})\n' > "$tmp/input.lua"
FAKE_OPTIONS='compose:caps' eq "$(FAKE_OPTIONS=compose:caps run set layouts us,gr:polytonic | grep -o '"switchKey":"[^"]*"')" '"switchKey":""'
has "$tmp/input.lua" '    kb_layout = "us,gr",'
has "$tmp/input.lua" '    kb_variant = ",polytonic",'
has "$tmp/input.lua" '    kb_options = "compose:caps",'
eq "$(grep -c 'hl.config' "$tmp/input.lua")" 1
# a kb_layout that is not followed by a comma: refused rather than guessed
printf 'hl.config({ input = { kb_layout = "us" } })\n' > "$tmp/input.lua"
eq "$(run set layouts us,gr:polytonic)" '{"error":"input.lua: cannot add kb_variant next to kb_layout"}'
eq "$(run set layouts us,gr)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":""}],"switchKey":"","active":1}'
# a value this editor does not handle is refused
printf 'hl.config({ input = { kb_layout = [[us]], } })\n' > "$tmp/input.lua"
eq "$(run get)" '{"error":"input.lua: kb_layout is not a plain string"}'

# eval refused: the keyword fallback; both refused: says which half failed
printf 'hl.config({ input = {\n  kb_layout = "us",\n  kb_options = "grp_led:caps",\n} })\n' > "$tmp/input.lua"
: > "$tmp/log"
FAKE_EVAL_FAIL=1 run set layouts us,gr >/dev/null
has "$tmp/log" 'keyword input:kb_layout us,gr'
eq "$(FAKE_EVAL_FAIL=1 FAKE_KEYWORD_FAIL=1 run set layouts us,de)" '{"error":"saved to input.lua, but Hyprland did not take it live"}'
has "$tmp/input.lua" 'kb_layout = "us,de",'
eq "$(FAKE_GSETTINGS_FAIL=1 run set layouts us,gr)" '{"error":"saved and applied, but the on-screen keyboard list was not updated"}'
# no Hyprland: active is null
FAKE_DEVICES=$tmp/none eq "$(FAKE_DEVICES=$tmp/none run get)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":""}],"switchKey":"","active":null}'
echo "keyboard backend: ok"
