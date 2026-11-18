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
  "-j getoption") [[ -z ${FAKE_GETOPTION_FAIL:-} ]] || exit 1
    case $3 in
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
unset FAKE_OPTIONS FAKE_GETOPTION_FAIL FAKE_EVAL_FAIL FAKE_KEYWORD_FAIL FAKE_GSETTINGS_FAIL
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
    kb_options = "compose:caps,grp:win_space_toggle,grp_led:caps", -- keep me
    repeat_rate = 40,
  },
})
EOT
chmod 640 "$tmp/input.lua"
# a grp: option that is none of ours: get says none
eq "$(run get)" '{"layouts":[{"layout":"us","variant":""}],"switchKey":"none","active":1}'

: > "$tmp/log"
eq "$(run set layouts us,gr:polytonic)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":"polytonic"}],"switchKey":"none","active":1}'
has "$tmp/input.lua" 'kb_layout = "us,gr",'
has "$tmp/input.lua" 'kb_variant = ",polytonic",'
# a layouts save leaves kb_options as it is, writes no state file and binds nothing
has "$tmp/input.lua" 'kb_options = "compose:caps,grp:win_space_toggle,grp_led:caps", -- keep me'
b=$tmp/omamobile-keyboard.lua
[[ ! -e $b ]] || { echo "FAIL: a layouts save wrote the state file" >&2; exit 1; }
hasnt "$tmp/log" 'hl.bind'
hasnt "$tmp/log" 'unbind'
has "$tmp/input.lua" '-- kb_layout = "fr", a comment, never touched'
has "$tmp/input.lua" 'hl.config({ input = { kb_layout = "de" } })'
has "$tmp/input.lua" '     kb_options = "grp:caps_toggle" ]]'
eq "$(grep -c 'hl.config' "$tmp/input.lua")" 2
eq "$(stat -c %a "$tmp/input.lua")" 640
has "$tmp/input.lua.bak-omamobile" 'kb_layout = "us",'
has "$tmp/log" 'eval hl.config({ input = { kb_layout = "us,gr", kb_variant = ",polytonic", kb_options = "compose:caps,grp:win_space_toggle,grp_led:caps" } })'
has "$tmp/log" "gsettings set org.gnome.desktop.input-sources sources [('xkb', 'us'), ('xkb', 'gr+polytonic')]"
# gsettings is written before the live apply
g=$(grep -n '^gsettings set' "$tmp/log" | cut -d: -f1); e=$(grep -n '^eval' "$tmp/log" | head -1 | cut -d: -f1)
(( g < e )) || { echo "FAIL: gsettings ($g) after the live apply ($e)" >&2; exit 1; }
hasnt "$tmp/log" 'reload'

# the switch key is an xkb option: every grp: and grp_led:caps go, the chosen one comes, applied
# live; gsettings is not touched and no bind is made
: > "$tmp/log"
eq "$(run set switch-key alt_shift)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":"polytonic"}],"switchKey":"alt_shift","active":1}'
has "$tmp/input.lua" 'kb_options = "compose:caps,grp:alt_shift_toggle", -- keep me'
has "$tmp/log" 'kb_options = "compose:caps,grp:alt_shift_toggle" } })'
eq "$(run get)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":"polytonic"}],"switchKey":"alt_shift","active":1}'
eq "$(run set switch-key ctrl_shift | grep -o '"switchKey":"[^"]*"')" '"switchKey":"ctrl_shift"'
has "$tmp/input.lua" 'kb_options = "compose:caps,grp:ctrl_shift_toggle", -- keep me'
hasnt "$tmp/log" 'hl.bind'
hasnt "$tmp/log" 'unbind'
hasnt "$tmp/log" 'gsettings'
[[ ! -e $b ]] || { echo "FAIL: a state file without caps" >&2; exit 1; }
# caps: grp:caps_toggle + grp_led:caps, compose:caps goes (it takes the key)
: > "$tmp/log"
eq "$(run set switch-key caps | grep -o '"switchKey":"[^"]*"')" '"switchKey":"caps"'
has "$tmp/input.lua" 'kb_options = "grp:caps_toggle,grp_led:caps", -- keep me'
has "$tmp/log" 'kb_options = "grp:caps_toggle,grp_led:caps" } })'
hasnt "$tmp/log" 'gsettings'
eq "$(run get | grep -o '"switchKey":"[^"]*"')" '"switchKey":"caps"'
# a layouts change keeps caps and the marker
eq "$(run set layouts us,gr:polytonic | grep -o '"switchKey":"[^"]*"')" '"switchKey":"caps"'
has "$tmp/input.lua" 'kb_options = "grp:caps_toggle,grp_led:caps", -- keep me'
has "$b" '-- compose-caps: restore'
hasnt "$b" 'hl.'
# away from caps to none: both options go, no grp: at all, compose:caps (there before caps) comes back
eq "$(run set switch-key none | grep -o '"switchKey":"[^"]*"')" '"switchKey":"none"'
has "$tmp/input.lua" 'kb_options = "compose:caps", -- keep me'
[[ ! -e $b ]] || { echo "FAIL: the marker stayed after caps" >&2; exit 1; }
# caps then alt_shift restores compose:caps too
run set switch-key caps >/dev/null
has "$tmp/input.lua" 'kb_options = "grp:caps_toggle,grp_led:caps", -- keep me'
run set switch-key alt_shift >/dev/null
has "$tmp/input.lua" 'kb_options = "grp:alt_shift_toggle,compose:caps", -- keep me'
[[ ! -e $b ]] || { echo "FAIL: the marker stayed after caps" >&2; exit 1; }
# a user without compose:caps never gets it
sed -i 's/kb_options = "grp:alt_shift_toggle,compose:caps", -- keep me/kb_options = "", -- keep me/' "$tmp/input.lua"
run set switch-key caps >/dev/null
[[ ! -e $b ]] || { echo "FAIL: a marker without compose:caps" >&2; exit 1; }
run set switch-key ctrl_shift >/dev/null
has "$tmp/input.lua" 'kb_options = "grp:ctrl_shift_toggle", -- keep me'
# Omarchy 4.5's omarchy:shift_caps_compose takes Caps Lock too: it goes with caps and comes back after
sed -i 's/kb_options = "grp:ctrl_shift_toggle", -- keep me/kb_options = "omarchy:shift_caps_compose", -- keep me/' "$tmp/input.lua"
run set switch-key caps >/dev/null
has "$tmp/input.lua" 'kb_options = "grp:caps_toggle,grp_led:caps", -- keep me'
has "$b" '-- compose-caps: restore omarchy:shift_caps_compose'
run set layouts us,gr >/dev/null
has "$b" '-- compose-caps: restore omarchy:shift_caps_compose'
run set switch-key alt_shift >/dev/null
has "$tmp/input.lua" 'kb_options = "grp:alt_shift_toggle,omarchy:shift_caps_compose", -- keep me'
[[ ! -e $b ]] || { echo "FAIL: the marker stayed after caps" >&2; exit 1; }
# both Compose options at once: both go with caps, the marker names both, both come back
sed -i 's/kb_options = "grp:alt_shift_toggle,omarchy:shift_caps_compose", -- keep me/kb_options = "compose:caps,omarchy:shift_caps_compose", -- keep me/' "$tmp/input.lua"
run set switch-key caps >/dev/null
has "$tmp/input.lua" 'kb_options = "grp:caps_toggle,grp_led:caps", -- keep me'
has "$b" '-- compose-caps: restore compose:caps omarchy:shift_caps_compose'
run set switch-key none >/dev/null
has "$tmp/input.lua" 'kb_options = "compose:caps,omarchy:shift_caps_compose", -- keep me'
[[ ! -e $b ]] || { echo "FAIL: the marker stayed after caps" >&2; exit 1; }
# a Compose option added by hand while caps is on joins the marker, the earlier one stays in it
sed -i 's/kb_options = "compose:caps,omarchy:shift_caps_compose", -- keep me/kb_options = "compose:caps", -- keep me/' "$tmp/input.lua"
run set switch-key caps >/dev/null
has "$b" '-- compose-caps: restore'
hasnt "$b" 'omarchy:'
sed -i 's/kb_options = "grp:caps_toggle,grp_led:caps", -- keep me/kb_options = "grp:caps_toggle,grp_led:caps,omarchy:shift_caps_compose", -- keep me/' "$tmp/input.lua"
run set switch-key caps >/dev/null
has "$b" '-- compose-caps: restore compose:caps omarchy:shift_caps_compose'
run set switch-key alt_shift >/dev/null
has "$tmp/input.lua" 'kb_options = "grp:alt_shift_toggle,compose:caps,omarchy:shift_caps_compose", -- keep me'
sed -i 's/kb_options = "grp:alt_shift_toggle,compose:caps,omarchy:shift_caps_compose", -- keep me/kb_options = "grp:ctrl_shift_toggle", -- keep me/' "$tmp/input.lua"
run set switch-key alt_shift >/dev/null
# one layout left: the option stays (xkb has nowhere to switch then); the variant goes
eq "$(run set layouts us)" '{"layouts":[{"layout":"us","variant":""}],"switchKey":"alt_shift","active":1}'
has "$tmp/input.lua" 'kb_options = "grp:alt_shift_toggle",'
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

# an effective grp: option (input.lua has no kb_options) is replaced by a switch-key change too
printf 'hl.config({\n  input = {\n    kb_layout = "us,gr",\n  },\n})\n' > "$tmp/input.lua"
FAKE_OPTIONS=compose:caps,grp:alts_toggle run set switch-key ctrl_shift >/dev/null
has "$tmp/input.lua" '    kb_options = "compose:caps,grp:ctrl_shift_toggle",'
printf 'hl.config({\n  input = {\n    kb_layout = "us,gr",\n  },\n})\n' > "$tmp/input.lua"
# get reads the effective kb_options when input.lua has none
eq "$(FAKE_OPTIONS=grp:caps_toggle,grp_led:caps run get | grep -o '"switchKey":"[^"]*"')" '"switchKey":"caps"'
eq "$(FAKE_OPTIONS=compose:caps,grp:alt_shift_toggle run get | grep -o '"switchKey":"[^"]*"')" '"switchKey":"alt_shift"'
eq "$(FAKE_OPTIONS=grp:ctrl_shift_toggle run get | grep -o '"switchKey":"[^"]*"')" '"switchKey":"ctrl_shift"'
eq "$(FAKE_OPTIONS=compose:caps run get | grep -o '"switchKey":"[^"]*"')" '"switchKey":"none"'
# xkb option names with "-" (base.lst has compose:caps-altgr, fkeys:basic_13-24) are kept
FAKE_OPTIONS=compose:caps-altgr,fkeys:basic_13-24 run set switch-key alt_shift >/dev/null
has "$tmp/input.lua" '    kb_options = "compose:caps-altgr,fkeys:basic_13-24,grp:alt_shift_toggle",'
printf 'hl.config({\n  input = {\n    kb_layout = "us,gr",\n  },\n})\n' > "$tmp/input.lua"
# Hyprland cannot say its kb_options / kb_layout: a save writes nothing rather than guess
cp "$tmp/input.lua" "$tmp/before"
eq "$(FAKE_GETOPTION_FAIL=1 run set switch-key alt_shift)" '{"error":"cannot read Hyprland'"'"'s input:kb_options, nothing written"}'
eq "$(FAKE_GETOPTION_FAIL=1 run set layouts us,de)" '{"error":"cannot read Hyprland'"'"'s input:kb_options, nothing written"}'
cmp -s "$tmp/input.lua" "$tmp/before" || { echo "FAIL: a save without Hyprland's values wrote" >&2; exit 1; }
printf 'hl.config({\n  input = {\n    repeat_rate = 40,\n  },\n})\n' > "$tmp/before"; cp "$tmp/before" "$tmp/input.lua"
eq "$(FAKE_GETOPTION_FAIL=1 run set switch-key caps)" '{"error":"cannot read Hyprland'"'"'s input:kb_layout, nothing written"}'
cmp -s "$tmp/input.lua" "$tmp/before" || { echo "FAIL: a save without Hyprland's layout wrote" >&2; exit 1; }
[[ ! -e $b ]] || { echo "FAIL: a refused save wrote the marker" >&2; exit 1; }
# a live kb_options and kb_layout need no getoption
printf 'hl.config({\n  input = {\n    kb_layout = "us,gr",\n    kb_options = "compose:caps",\n  },\n})\n' > "$tmp/input.lua"
eq "$(FAKE_GETOPTION_FAIL=1 run set switch-key ctrl_shift | grep -o '"switchKey":"[^"]*"')" '"switchKey":"ctrl_shift"'
# migration: a bind file from earlier commits of this branch, no grp: option. get reports its choice,
# the next save writes the matching xkb option and removes the file
printf 'hl.config({\n  input = {\n    kb_layout = "us,gr",\n    kb_options = "compose:caps",\n  },\n})\n' > "$tmp/input.lua"
printf -- '-- switch-key: ctrl_shift\nhl.bind("CTRL + SHIFT_L")\n' > "$b"
eq "$(run get | grep -o '"switchKey":"[^"]*"')" '"switchKey":"ctrl_shift"'
eq "$(run set layouts us,gr | grep -o '"switchKey":"[^"]*"')" '"switchKey":"ctrl_shift"'
has "$tmp/input.lua" '    kb_options = "compose:caps,grp:ctrl_shift_toggle",'
[[ ! -e $b ]] || { echo "FAIL: the old bind file stayed after migrating" >&2; exit 1; }
# with a grp: option already there, the old file is not the truth; a switch-key save removes it
printf -- '-- switch-key: alt_shift\nhl.bind("ALT + SHIFT_L")\n' > "$b"
eq "$(FAKE_OPTIONS=grp:alts_toggle run get | grep -o '"switchKey":"[^"]*"')" '"switchKey":"ctrl_shift"'
sed -i 's/grp:ctrl_shift_toggle/grp:alts_toggle/' "$tmp/input.lua"
eq "$(run get | grep -o '"switchKey":"[^"]*"')" '"switchKey":"none"'
run set layouts us,gr >/dev/null
has "$tmp/input.lua" '    kb_options = "compose:caps,grp:alts_toggle",'
has "$b" 'switch-key: alt_shift'
run set switch-key none >/dev/null
[[ ! -e $b ]] || { echo "FAIL: the old bind file stayed" >&2; exit 1; }
# a switch-key save picks over an old file's choice
printf -- '-- switch-key: alt_shift\n' > "$b"
sed -i 's/kb_options = "[^"]*"/kb_options = ""/' "$tmp/input.lua"
eq "$(run set switch-key caps | grep -o '"switchKey":"[^"]*"')" '"switchKey":"caps"'
has "$tmp/input.lua" '    kb_options = "grp:caps_toggle,grp_led:caps",'
[[ ! -e $b ]] || { echo "FAIL: the old bind file stayed" >&2; exit 1; }
run set switch-key none >/dev/null
# input.lua cannot be written (its directory is read-only) while caps takes compose:caps: the error is
# reported, input.lua is unchanged and the marker written for it is removed again (none is left stale)
mkdir -p "$tmp/ro"
printf 'hl.config({\n  input = {\n    kb_layout = "us,gr",\n    kb_options = "compose:caps,grp:ctrl_shift_toggle",\n  },\n})\n' > "$tmp/ro/input.lua"
touch "$tmp/ro/input.lua.lock-omamobile"; chmod 555 "$tmp/ro"  # the lock opens, the backup copy cannot be made
eq "$(OMAMOBILE_KBD_INPUT=$tmp/ro/input.lua run set switch-key caps)" '{"error":"cannot write input.lua"}'
chmod 755 "$tmp/ro"
has "$tmp/ro/input.lua" '    kb_options = "compose:caps,grp:ctrl_shift_toggle",'
[[ ! -e $tmp/ro/input.lua.bak-omamobile ]] || { echo "FAIL: the write got further than expected" >&2; exit 1; }
[[ ! -e $b ]] || { echo "FAIL: a stale compose marker after a failed write" >&2; exit 1; }
# the marker goes to disk before input.lua loses compose:caps: when it cannot be written, input.lua is
# not touched
mv "$b" "$b.x" 2>/dev/null || true; mkdir "$b"  # a directory where the state file goes: it cannot be written
eq "$(OMAMOBILE_KBD_INPUT=$tmp/ro/input.lua run set switch-key caps)" '{"error":"cannot write omamobile-keyboard.lua"}'
has "$tmp/ro/input.lua" '    kb_options = "compose:caps,grp:ctrl_shift_toggle",'
rmdir "$b"; rm -f "$b.x"
# the retry goes through and later leaving caps brings compose:caps back
export OMAMOBILE_KBD_INPUT=$tmp/ro/input.lua
run set switch-key caps >/dev/null
has "$tmp/ro/input.lua" 'kb_options = "grp:caps_toggle,grp_led:caps",'
has "$b" '-- compose-caps: restore'
run set switch-key alt_shift >/dev/null
has "$tmp/ro/input.lua" 'kb_options = "grp:alt_shift_toggle,compose:caps",'
[[ ! -e $b ]] || { echo "FAIL: the marker stayed" >&2; exit 1; }
export OMAMOBILE_KBD_INPUT=$tmp/input.lua
mv "$tmp/ro/input.lua" "$tmp/input.lua"


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
eq "$(run get)" '{"layouts":[{"layout":"us","variant":""}],"switchKey":"none","active":1}'
run set layouts us,gr >/dev/null
has "$tmp/input.lua" '--     kb_layout = "us,dk,eu",'
has "$tmp/input.lua" '    kb_layout = "us,gr",'
has "$tmp/input.lua" '    kb_options = "compose:caps,shift:both_capslock_cancel",'
eq "$(run get)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":""}],"switchKey":"none","active":1}'
eq "$(grep -c 'hl.config' "$tmp/input.lua")" 2
run set layouts us,de >/dev/null
eq "$(grep -c 'hl.config' "$tmp/input.lua")" 2
has "$tmp/input.lua" '    kb_layout = "us,de",'
unset FAKE_OPTIONS
rm "$tmp/input.lua"
eq "$(run get)" '{"error":"input.lua is missing"}'

# kb_options and kb_variant absent: added on the kb_layout line's table, Omarchy's effective options kept
printf 'hl.config({\n  input = {\n    kb_layout = "us",\n  },\n})\n' > "$tmp/input.lua"
FAKE_OPTIONS='compose:caps' eq "$(FAKE_OPTIONS=compose:caps run set layouts us,gr:polytonic | grep -o '"switchKey":"[^"]*"')" '"switchKey":"none"'
has "$tmp/input.lua" '    kb_layout = "us,gr",'
has "$tmp/input.lua" '    kb_variant = ",polytonic",'
has "$tmp/input.lua" '    kb_options = "compose:caps",'
eq "$(grep -c 'hl.config' "$tmp/input.lua")" 1
# a one-line kb_layout with no comma after it: the keys go right after its string
printf 'hl.config({ input = { kb_layout = "us" } })\n' > "$tmp/input.lua"
eq "$(run set layouts us,gr:polytonic)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":"polytonic"}],"switchKey":"none","active":1}'
has "$tmp/input.lua" 'hl.config({ input = { kb_layout = "us,gr", kb_variant = ",polytonic" } })'
printf 'hl.config({ input = { kb_layout = "us,gr" } })\n' > "$tmp/input.lua"
eq "$(FAKE_OPTIONS=compose:caps run set switch-key caps | grep -o '"switchKey":"[^"]*"')" '"switchKey":"caps"'
has "$tmp/input.lua" 'hl.config({ input = { kb_layout = "us,gr", kb_options = "grp:caps_toggle,grp_led:caps" } })'
has "$b" '-- compose-caps: restore'
eq "$(run set switch-key none | grep -o '"switchKey":"[^"]*"')" '"switchKey":"none"'
has "$tmp/input.lua" 'kb_options = "compose:caps"'
[[ ! -e $b ]] || { echo "FAIL: the marker stayed" >&2; exit 1; }
printf 'hl.config({ input = { kb_layout = "us" } })\n' > "$tmp/input.lua"
eq "$(run set layouts us,gr)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":""}],"switchKey":"none","active":1}'
# a value this editor does not handle is refused
printf 'hl.config({ input = { kb_layout = [[us]], } })\n' > "$tmp/input.lua"
eq "$(run get)" '{"error":"input.lua: kb_layout is not a plain string"}'

# eval refused: the keyword fallback; both refused: says which half failed
printf 'hl.config({ input = {\n  kb_layout = "us",\n  kb_options = "compose:caps",\n} })\n' > "$tmp/input.lua"
: > "$tmp/log"
FAKE_EVAL_FAIL=1 run set layouts us,gr >/dev/null
has "$tmp/log" '--batch keyword input:kb_variant ; keyword input:kb_options compose:caps; keyword input:kb_layout us,gr'
eq "$(FAKE_EVAL_FAIL=1 FAKE_KEYWORD_FAIL=1 run set layouts us,de)" '{"error":"saved, but Hyprland did not take it live"}'
has "$tmp/input.lua" 'kb_layout = "us,de",'
eq "$(FAKE_GSETTINGS_FAIL=1 run set layouts us,gr)" '{"error":"saved and applied, but the on-screen keyboard list was not updated"}'
# no Hyprland: active is null
FAKE_DEVICES=$tmp/none eq "$(FAKE_DEVICES=$tmp/none run get)" '{"layouts":[{"layout":"us","variant":""},{"layout":"gr","variant":""}],"switchKey":"none","active":null}'
# list: layouts and grp: switch keys from the rules file, other options left out
eq "$(run list)" '{"layouts":[{"layout":"us","name":"English (US)"},{"layout":"gr","name":"Greek"},{"layout":"de","name":"German"},{"layout":"ru","name":"Russian"}],"switchKeys":[{"option":"alt_shift","name":"Alt+Shift"},{"option":"ctrl_shift","name":"Ctrl+Shift"},{"option":"caps","name":"Caps Lock"},{"option":"none","name":"None"}]}'
# phone.lua binds no switch key and loads no Settings file
for k in "switchxkblayout" "omamobile-keyboard-switch" "omamobile-keyboard.lua" "SHIFT_L" "ALT_L" "CTRL_L" "code:66"; do hasnt "$src/../omamobile-shell/hypr/phone.lua" "$k"; done

echo "keyboard backend: ok"
