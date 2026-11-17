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
  "-j binds") cat "$FAKE_BINDS" 2>/dev/null || exit 1 ;;
  "-j getoption") case $3 in
      input:kb_options) printf '{"option":"input:kb_options","str":"%s","set":true}\n' "${FAKE_OPTIONS:-}" ;;
      input:kb_layout) printf '{"option":"input:kb_layout","str":"%s","set":true}\n' "${FAKE_LAYOUT:-us}" ;;
      *) printf '{"option":"%s","str":"","set":false}\n' "$3" ;;
    esac ;;
  eval*) [[ -n ${FAKE_EVAL_FAIL:-} ]] && echo "error: no eval" || echo ok ;;
  --batch*) [[ -n ${FAKE_KEYWORD_FAIL:-} ]] && echo "error: bad" || echo ok ;;
esac
EOT
cat > "$tmp/bin/gsettings" <<'EOT'
#!/bin/bash
printf 'gsettings %s\n' "$*" >> "$FAKE_LOG"
[[ -z ${FAKE_GSETTINGS_FAIL:-} ]] || exit 1
case $1 in
  get) cat "$FAKE_SOURCES" 2>/dev/null || echo "@a(ss) []" ;;
  set) printf '%s\n' "$4" > "$FAKE_SOURCES" ;;
esac
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
export PATH="$tmp/bin:$PATH" FAKE_LOG="$tmp/log" FAKE_DEVICES="$tmp/devices.json" FAKE_SOURCES="$tmp/sources"
export OMAMOBILE_KEYBOARDS_DIR="$tmp/nokeyboards"
export XDG_RUNTIME_DIR="$tmp/run" HYPRLAND_INSTANCE_SIGNATURE=test
export OMAMOBILE_KBD_INPUT="$tmp/input.lua" OMAMOBILE_KBD_RULES="$tmp/rules.lst" OMAMOBILE_KBD_BINDS="$tmp/omamobile-keyboard.lua"
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
# no bind file yet: phone.lua binds the default, Alt+Shift
eq "$(run get)" '{"layouts":[{"layout":"us","variant":""}],"switchKey":"alt_shift","active":1}'

: > "$tmp/log"
eq "$(run set layouts us,gr:polytonic)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":"polytonic"}],"switchKey":"alt_shift","active":1}'
has "$tmp/input.lua" 'kb_layout = "us,gr",'
has "$tmp/input.lua" 'kb_variant = ",polytonic",'
# the old grp: option is removed (it never switched on the phone), grp_led and the rest stay
has "$tmp/input.lua" 'kb_options = "compose:caps,grp_led:caps", -- keep me'
# both key orders bound on every keyboard but squeekboard's, in the file and live
b=$tmp/omamobile-keyboard.lua
has "$b" '-- switch-key: alt_shift'
has "$b" 'hl.bind("ALT + SHIFT + SHIFT_L", hl.dsp.exec_cmd("omamobile-keyboard-switch next"), { description = "Keyboard: next layout", device = { inclusive = false, list = { "hl-virtual-keyboard-squeekboard" } }, release = true, non_consuming = true })'
has "$b" 'hl.bind("SHIFT + ALT + ALT_L", hl.dsp.exec_cmd("omamobile-keyboard-switch next")'
has "$b" 'b[2]:set_enabled(b[1] == "alt_shift")'
has "$tmp/log" 'hl.bind("SHIFT + ALT + ALT_L", hl.dsp.exec_cmd("omamobile-keyboard-switch next")'
hasnt "$tmp/log" 'unbind'
hasnt "$tmp/log" 'grp:'
has "$tmp/input.lua" '-- kb_layout = "fr", a comment, never touched'
has "$tmp/input.lua" 'hl.config({ input = { kb_layout = "de" } })'
has "$tmp/input.lua" '     kb_options = "grp:caps_toggle" ]]'
eq "$(grep -c 'hl.config' "$tmp/input.lua")" 2
eq "$(stat -c %a "$tmp/input.lua")" 640
has "$tmp/input.lua.bak-omamobile" 'kb_layout = "us",'
has "$tmp/log" 'eval hl.config({ input = { kb_layout = "us,gr", kb_variant = ",polytonic", kb_options = "compose:caps,grp_led:caps" } })'
has "$tmp/log" "gsettings set org.gnome.desktop.input-sources sources [('xkb', 'us'), ('xkb', 'gr+polytonic')]"
# gsettings is written before the live apply
g=$(grep -n '^gsettings set' "$tmp/log" | cut -d: -f1); e=$(grep -n '^eval' "$tmp/log" | head -1 | cut -d: -f1)
(( g < e )) || { echo "FAIL: gsettings ($g) after the live apply ($e)" >&2; exit 1; }
hasnt "$tmp/log" 'reload'
eq "$(run get)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":"polytonic"}],"switchKey":"alt_shift","active":1}'

# the switch key: the old binds go, the new ones come; input.lua and gsettings are not touched
cp "$tmp/input.lua" "$tmp/before"; : > "$tmp/log"
eq "$(run set switch-key ctrl_shift)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":"polytonic"}],"switchKey":"ctrl_shift","active":1}'
cmp -s "$tmp/input.lua" "$tmp/before" || { echo "FAIL: a switch-key change wrote input.lua" >&2; exit 1; }
has "$b" '-- switch-key: ctrl_shift'
has "$b" 'b[2]:set_enabled(b[1] == "ctrl_shift")'
has "$tmp/log" 'b[2]:set_enabled(b[1] == "ctrl_shift")'
hasnt "$tmp/log" 'unbind'
hasnt "$tmp/log" 'gsettings'
hasnt "$tmp/log" 'kb_options'
run set switch-key caps >/dev/null
has "$b" 'hl.bind("code:66", hl.dsp.exec_cmd("omamobile-keyboard-switch next"), { description = "Keyboard: next layout", device = { inclusive = false, list = { "hl-virtual-keyboard-squeekboard" } } })'
has "$b" 'set_enabled(b[1] == "caps")'
eq "$(run set switch-key none | grep -o '"switchKey":"[^"]*"')" '"switchKey":"none"'
has "$b" 'set_enabled(b[1] == "none")'
has "$b" '-- switch-key: none'
run set switch-key alt_shift >/dev/null
# one layout left: the binds stay (the switch script does nothing then); the variant goes; grp_led stays
eq "$(run set layouts us)" '{"layouts":[{"layout":"us","variant":""}],"switchKey":"alt_shift","active":1}'
has "$b" 'set_enabled(b[1] == "alt_shift")'
has "$b" '-- switch-key: alt_shift'
has "$tmp/input.lua" 'kb_options = "compose:caps,grp_led:caps",'
has "$tmp/input.lua" 'kb_variant = "",'

# a non-Latin first layout is refused, nothing written
cp "$tmp/input.lua" "$tmp/before"; cp "$tmp/sources" "$tmp/sources.before"
eq "$(run set layouts gr,us)" '{"error":"the first layout must be a Latin one (passwords on the lock screen are typed in it)"}'
eq "$(run set layouts gr)" '{"error":"the first layout must be a Latin one (passwords on the lock screen are typed in it)"}'
cmp -s "$tmp/input.lua" "$tmp/before" && cmp -s "$tmp/sources" "$tmp/sources.before" || { echo "FAIL: a refused set wrote" >&2; exit 1; }
eq "$(run set layouts us,gr | grep -c warn || true)" 0

# OSK merge: the OSK's own languages and its current (first) entry stay, new ones are added,
# removed hardware layouts are dropped; only names squeekboard has a file for, when the dir exists
echo "[('xkb', 'gr'), ('xkb', 'fr'), ('ibus', 'x')]" > "$tmp/sources"
mkdir -p "$tmp/kbds"; touch "$tmp/kbds/us.yaml" "$tmp/kbds/gr.yaml"
OMAMOBILE_KEYBOARDS_DIR=$tmp/kbds run set layouts us,gr,de >/dev/null
eq "$(cat "$tmp/sources")" "[('xkb', 'gr'), ('xkb', 'fr'), ('ibus', 'x'), ('xkb', 'us')]"
run set layouts us,de >/dev/null
eq "$(cat "$tmp/sources")" "[('xkb', 'fr'), ('ibus', 'x'), ('xkb', 'us'), ('xkb', 'de')]"
: > "$tmp/log"; run set layouts us,de >/dev/null
hasnt "$tmp/log" 'gsettings set'
run set layouts us,gr >/dev/null

# per-device blocks and variables named kb_layout are not the global setting
cat > "$tmp/input.lua" <<'EOT'
local kb_layout = "ru"
hl.config({
  input = {
    kb_layout = "us",
    kb_options = "compose:caps",
    touchpad = { kb_layout = "fr" },
  },
})
hl.device({ name = "x", kb_layout = "de" })
EOT
eq "$(run get | grep -o '"layouts":[^]]*]')" '"layouts":[{"layout":"us","variant":""}]'
run set layouts us,gr >/dev/null
has "$tmp/input.lua" '    kb_layout = "us,gr",'
has "$tmp/input.lua" 'local kb_layout = "ru"'
has "$tmp/input.lua" 'touchpad = { kb_layout = "fr" },'
has "$tmp/input.lua" 'hl.device({ name = "x", kb_layout = "de" })'

# a symlinked input.lua stays a link, its target is written
mkdir -p "$tmp/dots"; mv "$tmp/input.lua" "$tmp/dots/input.lua"; ln -s "$tmp/dots/input.lua" "$tmp/input.lua"
run set layouts us,de >/dev/null
[[ -L $tmp/input.lua ]] || { echo "FAIL: the symlink was replaced" >&2; exit 1; }
has "$tmp/dots/input.lua" '    kb_layout = "us,de",'
rm "$tmp/input.lua"; mv "$tmp/dots/input.lua" "$tmp/input.lua"

# an effective grp: option (input.lua has no kb_options) is dropped by a switch-key change too
printf 'hl.config({\n  input = {\n    kb_layout = "us,gr",\n  },\n})\n' > "$tmp/input.lua"
FAKE_OPTIONS=compose:caps,grp:alt_shift_toggle run set switch-key alt_shift >/dev/null
has "$tmp/input.lua" '    kb_options = "compose:caps",'
printf 'hl.config({\n  input = {\n    kb_layout = "us,gr",\n  },\n})\n' > "$tmp/input.lua"

# bad input never reaches the file
cp "$tmp/input.lua" "$tmp/before"
eq "$(run set layouts us,gr,de,ru,us:intl)" '{"error":"give 1 to 4 layouts"}'
eq "$(run set layouts us,xx)" '{"error":"unknown layout: xx"}'
eq "$(run set layouts us,gr:intl)" '{"error":"unknown layout: gr:intl"}'
eq "$(run set layouts 'us,gr"')" '{"error":"bad layout name"}'
eq "$(run set layouts us,us)" '{"error":"layout listed twice: us"}'
eq "$(run set layouts '')" '{"error":"give 1 to 4 layouts"}'
eq "$(run set switch-key grp:alt_shift_toggle)" '{"error":"unknown switch key"}'
eq "$(run set switch-key 'caps"')" '{"error":"unknown switch key"}'
eq "$(run set numlock on)" '{"error":"unknown key"}'
eq "$(run nonsense)" '{"error":"usage: get|list|set"}'
cmp -s "$tmp/input.lua" "$tmp/before" || { echo "FAIL: a rejected set changed input.lua" >&2; exit 1; }

# Omarchy's stock file: kb_* only in comments. get reports Hyprland's effective values; set appends
# one hl.config() block and leaves the commented example alone (the phone's file, 0.57, 2026-11-17)
cat > "$tmp/input.lua" <<'EOT'
hl.config({
  input = {
    -- Use multiple keyboard layouts and switch between them with Left Alt + Right Alt
    --     kb_layout = "us,dk,eu",
    --     kb_options = "compose:caps,grp:alts_toggle",
    repeat_rate = 40,
  },
})
EOT
FAKE_OPTIONS="compose:caps,shift:both_capslock_cancel"
export FAKE_OPTIONS
eq "$(run get)" '{"layouts":[{"layout":"us","variant":""}],"switchKey":"alt_shift","active":1}'
run set layouts us,gr >/dev/null
has "$tmp/input.lua" '--     kb_layout = "us,dk,eu",'
has "$tmp/input.lua" '    kb_layout = "us,gr",'
has "$tmp/input.lua" '    kb_options = "compose:caps,shift:both_capslock_cancel",'
eq "$(run get)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":""}],"switchKey":"alt_shift","active":1}'
eq "$(grep -c 'hl.config' "$tmp/input.lua")" 2
run set layouts us,de >/dev/null
eq "$(grep -c 'hl.config' "$tmp/input.lua")" 2
has "$tmp/input.lua" '    kb_layout = "us,de",'
unset FAKE_OPTIONS
rm "$tmp/input.lua"
eq "$(run get)" '{"error":"input.lua is missing"}'

# kb_options and kb_variant absent: added on the kb_layout line's table, Omarchy's effective options kept
printf 'hl.config({\n  input = {\n    kb_layout = "us",\n  },\n})\n' > "$tmp/input.lua"
FAKE_OPTIONS='compose:caps' eq "$(FAKE_OPTIONS=compose:caps run set layouts us,gr:polytonic | grep -o '"switchKey":"[^"]*"')" '"switchKey":"alt_shift"'
has "$tmp/input.lua" '    kb_layout = "us,gr",'
has "$tmp/input.lua" '    kb_variant = ",polytonic",'
has "$tmp/input.lua" '    kb_options = "compose:caps",'
eq "$(grep -c 'hl.config' "$tmp/input.lua")" 1
# a kb_layout that is not followed by a comma: refused rather than guessed
printf 'hl.config({ input = { kb_layout = "us" } })\n' > "$tmp/input.lua"
eq "$(run set layouts us,gr:polytonic)" '{"error":"input.lua: cannot add kb_variant next to kb_layout"}'
eq "$(run set layouts us,gr)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":""}],"switchKey":"alt_shift","active":1}'
# a value this editor does not handle is refused
printf 'hl.config({ input = { kb_layout = [[us]], } })\n' > "$tmp/input.lua"
eq "$(run get)" '{"error":"input.lua: kb_layout is not a plain string"}'

# eval refused: the keyword fallback; both refused: says which half failed
printf 'hl.config({ input = {\n  kb_layout = "us",\n  kb_options = "grp_led:caps",\n} })\n' > "$tmp/input.lua"
: > "$tmp/log"
FAKE_EVAL_FAIL=1 run set layouts us,gr >/dev/null
has "$tmp/log" '--batch keyword input:kb_variant ; keyword input:kb_options grp_led:caps; keyword input:kb_layout us,gr'
eq "$(FAKE_EVAL_FAIL=1 FAKE_KEYWORD_FAIL=1 run set layouts us,de)" '{"error":"saved, but Hyprland did not take it live"}'
has "$tmp/input.lua" 'kb_layout = "us,de",'
eq "$(FAKE_GSETTINGS_FAIL=1 run set layouts us,gr)" '{"error":"saved and applied, but the on-screen keyboard list was not updated"}'
# no Hyprland: active is null
FAKE_DEVICES=$tmp/none eq "$(FAKE_DEVICES=$tmp/none run get)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":""}],"switchKey":"alt_shift","active":null}'
# list: layouts and grp: switch keys from the rules file, other options left out
eq "$(run list)" '{"layouts":[{"layout":"us","name":"English (US)"},{"layout":"gr","name":"Greek"},{"layout":"de","name":"German"},{"layout":"ru","name":"Russian"}],"switchKeys":[{"option":"alt_shift","name":"Alt+Shift"},{"option":"ctrl_shift","name":"Ctrl+Shift"},{"option":"caps","name":"Caps Lock"},{"option":"none","name":"None"}]}'
# The bind file under a stub hl: loaded twice in one Lua state (a second hyprctl eval) it binds
# the five keys once and enables only the chosen pair; a fresh state (phone.lua resets the table)
# binds them again
run set switch-key ctrl_shift >/dev/null
cat > "$tmp/stub.lua" <<'EOT'
local binds = {}
hl = { dsp = { exec_cmd = function(c) return c end } }
function hl.bind(k, d, o)
  local h = { key = k, enabled = true, opts = o }
  function h:set_enabled(v) self.enabled = v end
  binds[#binds + 1] = h
  return h
end
dofile(arg[1]); dofile(arg[1])
local on = {}
for _, h in ipairs(binds) do if h.enabled then on[#on + 1] = h.key .. (h.opts.release and "/r" or "") end end
print(#binds, table.concat(on, ";"))
omamobile_kbd_binds = nil; dofile(arg[1]); print(#binds)
EOT
eq "$(lua "$tmp/stub.lua" "$b")" "$(printf '5\tCTRL + SHIFT + SHIFT_L/r;SHIFT + CTRL + CTRL_L/r\n10')"
# phone.lua's default (no file) binds the same five key strings
for k in "ALT + SHIFT + SHIFT_L" "SHIFT + ALT + ALT_L" "CTRL + SHIFT + SHIFT_L" "SHIFT + CTRL + CTRL_L" "code:66"; do
  has "$b" "\"$k\""; has "$src/../omamobile-shell/hypr/phone.lua" "\"$k\""
done

# The handle table did not survive the eval (more of ours than five): keys with only our binds
# are unbound and bound again; a key that also has a user's bind is left alone and reported
ours='"description":"Keyboard: next layout"'
{ printf '['; for i in 1 2; do printf '{"modmask":9,"key":"Shift_L","keycode":0,%s},{"modmask":9,"key":"Alt_L","keycode":0,%s},' "$ours" "$ours"
  printf '{"modmask":5,"key":"Shift_L","keycode":0,%s},{"modmask":5,"key":"Control_L","keycode":0,%s},{"modmask":0,"key":"","keycode":66,%s},' "$ours" "$ours" "$ours"; done
  printf '{"modmask":64,"key":"Return","keycode":0,"description":"Terminal"}]\n'; } > "$tmp/binds.json"
: > "$tmp/log"
FAKE_BINDS="$tmp/binds.json" run set switch-key alt_shift | grep -q '"switchKey":"alt_shift"' || { echo "FAIL: duplicate cleanup" >&2; exit 1; }
has "$tmp/log" 'pcall(hl.unbind, "ALT + SHIFT + SHIFT_L")'
has "$tmp/log" 'pcall(hl.unbind, "code:66")'
has "$tmp/log" 'omamobile_kbd_binds = nil'
sed -i 's/"Terminal"/"Terminal"},{"modmask":9,"key":"SHIFT_L","keycode":0,"description":"Mine"/' "$tmp/binds.json"
: > "$tmp/log"
FAKE_BINDS="$tmp/binds.json" run set switch-key alt_shift | grep -q 'did not take it live' || { echo "FAIL: a user's bind on the key is reported" >&2; exit 1; }
hasnt "$tmp/log" 'unbind'

echo "keyboard backend: ok"
