#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/keyboard.sh in a fixture HOME (XDG dirs under a temp dir) with a fake hyprctl and a fake
# omamobile-keyboard-languages that log their arguments. The host's own files and tools are never touched.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/run" "$tmp/home/.config/hypr" "$tmp/keyboards" "$tmp/opts"
cat > "$tmp/bin/hyprctl" <<'EOT'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LOG"
case "$1 $2" in
  "-j devices") cat "$FAKE_DEVICES" ;;
  "-j getoption") k=${3#input:}; [[ -e $FAKE_OPTS/$k ]] || { [[ $k == kb_options ]] && printf 'omarchy:shift_caps_compose' > "$FAKE_OPTS/$k"; }
    printf '{"option":"%s","str":"%s","set":true}\n' "$3" "$(cat "$FAKE_OPTS/$k" 2>/dev/null)" ;;
  eval*) [[ -n ${FAKE_EVAL_FAIL:-} ]] && { echo "error: no eval"; exit 0; }
    # store what the eval set, so getoption reads it back
    for k in kb_layout kb_variant kb_options; do
      v=$(printf '%s' "$2" | sed -n "s/.*$k = \"\([^\"]*\)\".*/\1/p"); printf '%s' "$v" > "$FAKE_OPTS/$k"
    done; echo ok ;;
esac
EOT
cat > "$tmp/bin/langs" <<'EOT'
#!/bin/bash
printf 'langs %s\n' "$*" >> "$FAKE_LOG"
[[ -n ${FAKE_LANGS_OLD:-} ]] && exit 2
[[ -z ${FAKE_LANGS_FAIL:-} ]]
EOT
chmod +x "$tmp/bin/hyprctl" "$tmp/bin/langs"
cat > "$tmp/rules.lst" <<'EOT'
! layout
  us              English (US)
  gr              Greek
  de              German
  ru              Russian
  ua              Ukrainian
  by              Belarusian
  bg              Bulgarian
  jp              Japanese

! variant
  polytonic       gr: Greek (polytonic)
  rus             us: Russian (US, phonetic)
  intl            us: English (US, intl., with dead keys)
EOT
echo '{"keyboards":[{"name":"hl-virtual-keyboard-squeekboard","active_layout_index":0},{"name":"dell-kb7120w","layout":"us,gr","active_layout_index":1,"main":true}]}' > "$tmp/devices.json"
for f in gr de ru; do : > "$tmp/keyboards/$f.yaml"; done
export PATH="$tmp/bin:$PATH" FAKE_LOG="$tmp/log" FAKE_DEVICES="$tmp/devices.json" FAKE_OPTS="$tmp/opts"
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_STATE_HOME="$tmp/home/.local/state"
export XDG_RUNTIME_DIR="$tmp/run" HYPRLAND_INSTANCE_SIGNATURE=test
export OMAMOBILE_KBD_RULES="$tmp/rules.lst" OMAMOBILE_KEYBOARDS_DIR="$tmp/keyboards" OMAMOBILE_KBD_LANGUAGES=langs
unset FAKE_EVAL_FAIL FAKE_LANGS_FAIL
store="$XDG_CONFIG_HOME/omarchy/keyboard-layouts"; input="$XDG_CONFIG_HOME/hypr/input.lua"
run() { bash "$src/backends/keyboard.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }
has() { grep -qF -- "$2" "$1" || { echo "FAIL: $1 lacks $2" >&2; cat "$1" >&2; exit 1; }; }
hasnt() { ! grep -qF -- "$2" "$1" || { echo "FAIL: $1 has $2" >&2; exit 1; }; }
j() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))' "$1" "$2"; }

# Omarchy 4.5's stock user input.lua: kb_* only in comments
cat > "$input" <<'EOT'
-- Overwrite parts of the omarchy-default input config
-- hl.config({ input = { kb_layout = "us,dk", kb_options = "compose:caps" } })
hl.config({ input = { repeat_rate = 40 } })
EOT
cp "$input" "$tmp/stock.lua"
printf 'us' > "$tmp/opts/kb_layout"

# get with no store: Hyprland's value, default switch key, the main real keyboard's index
r=$(run get)
eq "$(j "$r" 'd["layouts"]')" "[{'layout': 'us', 'variant': ''}]"
eq "$(j "$r" 'd["switchKey"], d["active"], d["override"]')" "('default', 1, '')"

# a layouts save writes Omarchy's store only; input.lua stays byte-identical; live via one eval
: > "$tmp/log"
r=$(run set layouts us,gr:polytonic,de)
eq "$(j "$r" 'd.get("error")')" "None"
eq "$(cat "$store")" $'XKBLAYOUT=us,gr,de\nXKBVARIANT=,polytonic,'
cmp -s "$input" "$tmp/stock.lua" || { echo "FAIL: input.lua changed on a layouts save" >&2; exit 1; }
has "$tmp/log" 'eval hl.config({ input = { kb_layout = "us,gr,de", kb_variant = ",polytonic,", kb_options = "omarchy:shift_caps_compose,grp:alts_toggle" } })'
hasnt "$tmp/log" reload
# only the new ones squeekboard has a file for go to the OSK, through add; nothing is removed
has "$tmp/log" 'langs add de'; hasnt "$tmp/log" 'langs add gr+polytonic'; hasnt "$tmp/log" 'langs add us'
: > "$tmp/log"; run set layouts us >/dev/null
hasnt "$tmp/log" 'langs'
eq "$(cat "$store")" $'XKBLAYOUT=us\nXKBVARIANT='
has "$tmp/log" 'kb_options = "omarchy:shift_caps_compose" } })'

# Latin rule from Omarchy's list: us goes first, an existing Latin us moves, us:rus counts as non-Latin
r=$(run set layouts gr,de); eq "$(cat "$store")" $'XKBLAYOUT=us,gr,de\nXKBVARIANT=,,'
eq "$(j "$r" '"note" in d')" "True"
run set layouts ru,us:intl >/dev/null; eq "$(cat "$store")" $'XKBLAYOUT=us,ru\nXKBVARIANT=intl,'
run set layouts us:rus,de >/dev/null; eq "$(cat "$store")" $'XKBLAYOUT=us,us,de\nXKBVARIANT=,rus,'
r=$(run set layouts jp,us); eq "$(cat "$store")" $'XKBLAYOUT=jp,us\nXKBVARIANT=,'; eq "$(j "$r" '"note" in d')" "False"
r=$(run set layouts ru,ua,by,bg); has <(echo "$r") 'no room'
eq "$(cat "$store")" $'XKBLAYOUT=jp,us\nXKBVARIANT=,'
for bad in "" us,us xx gr:nope "us;rm" us,gr,de,ru,ua; do r=$(run set layouts "$bad"); has <(echo "$r") error; done
eq "$(cat "$store")" $'XKBLAYOUT=jp,us\nXKBVARIANT=,'
# get reads the store, quotes and comments stripped as Omarchy's keyboard.lua does
printf 'XKBLAYOUT="us,gr"  # mine\nXKBVARIANT=,\n' > "$store"
eq "$(j "$(run get)" '[l["layout"] for l in d["layouts"]]')" "['us', 'gr']"

# switch key: one marked block with the full kb_options; default takes it out again
: > "$tmp/log"
r=$(run set switch-key alt_shift); eq "$(j "$r" 'd["switchKey"]')" "alt_shift"
has "$input" 'hl.config({ input = { kb_options = "omarchy:shift_caps_compose,grp:alt_shift_toggle" } })'
has "$input" 'repeat_rate = 40'
cmp -s "$XDG_STATE_HOME/omamobile/keyboard-input.lua.bak" "$tmp/stock.lua" || { echo "FAIL: no backup in the state dir" >&2; exit 1; }
[[ ! -e $XDG_CONFIG_HOME/hypr/input.lua.bak-omamobile ]] || { echo "FAIL: backup in ~/.config/hypr" >&2; exit 1; }
has "$tmp/log" 'kb_options = "omarchy:shift_caps_compose,grp:alt_shift_toggle" } })'
run set switch-key caps >/dev/null
has "$input" 'kb_options = "grp:caps_toggle,grp_led:caps"'
eq "$(grep -c 'omamobile-settings: switch key (begin' "$input")" 1
eq "$(j "$(run get)" 'd["switchKey"]')" "caps"
# the block sets no layouts, so a layouts save still works with it there
r=$(run set layouts us,de); eq "$(j "$r" 'd.get("error")')" "None"
run set switch-key default >/dev/null
cmp -s "$input" "$tmp/stock.lua" || { echo "FAIL: default does not give back the stock file" >&2; diff "$input" "$tmp/stock.lua" >&2; exit 1; }
r=$(run set switch-key bogus); has <(echo "$r") 'unknown switch key'
# an input.lua without a trailing newline comes back byte for byte, also after switching twice
printf 'hl.config({ input = { repeat_rate = 40 } })' > "$input"; cp "$input" "$tmp/nonl.lua"
run set switch-key caps >/dev/null; has "$input" 'grp:caps_toggle'
run set switch-key alt_shift >/dev/null; eq "$(j "$(run get)" 'd["switchKey"]')" "alt_shift"
run set switch-key default >/dev/null
cmp -s "$input" "$tmp/nonl.lua" || { echo "FAIL: no-newline input.lua not restored" >&2; od -c "$input" | tail -3 >&2; exit 1; }
cp "$tmp/stock.lua" "$input"

# the user's own live kb_layout: reported, layouts not written; own kb_options: switch key not written
printf 'hl.config({\n  input = {\n    kb_layout = "us,dk",\n    kb_options = "compose:caps",\n  },\n})\n' > "$input"
cp "$store" "$tmp/store.before"
r=$(run get); eq "$(j "$r" 'd["override"] != "", d["switchKey"]')" "(True, 'custom')"
r=$(run set layouts us,gr); has <(echo "$r") 'nothing written'; cmp -s "$store" "$tmp/store.before"
r=$(run set switch-key caps); has <(echo "$r") 'nothing written'; hasnt "$input" grp:caps_toggle
cp "$tmp/stock.lua" "$input"

# a failed live apply or OSK add is an error, the file stays saved
FAKE_EVAL_FAIL=1 r=$(FAKE_EVAL_FAIL=1 run set layouts us,gr); has <(echo "$r") 'next login'
eq "$(head -1 "$store")" 'XKBLAYOUT=us,gr'
r=$(FAKE_LANGS_FAIL=1 run set layouts us,gr,ru); has <(echo "$r") 'on-screen keyboard list was not updated'
eq "$(head -1 "$store")" 'XKBLAYOUT=us,gr,ru'
# an omamobile-shell without the add verb (usage, exit 2) is named in the error
r=$(FAKE_LANGS_OLD=1 run set layouts us,gr,ru,de); has <(echo "$r") 'omamobile-shell is too old'

# list: the layouts and the four switch choices
r=$(run list); eq "$(j "$r" '[k["option"] for k in d["switchKeys"]]')" "['alt_shift', 'ctrl_shift', 'caps', 'default']"
eq "$(j "$r" 'len(d["layouts"])')" 8

# the non-Latin copy matches Omarchy's installed input.lua (skipped where Omarchy is not installed)
omarchy=/usr/share/omarchy/default/hypr/input.lua
if [[ -r $omarchy ]]; then
  want=$(sed -n '/^local non_latin_layouts =/{n;p}' "$omarchy" | tr -s ' ' | sed 's/^ *"\? *//; s/ *"\? *$//')
  got=$(sed -n 's/^NON_LATIN = set("\(.*\)".split())$/\1/p' "$src/backends/keyboard.sh")
  eq "$got" "$want"
  grep -qF 'local non_latin_us_variants = " chr rus "' "$omarchy" || { echo "FAIL: Omarchy's us variants changed" >&2; exit 1; }
else
  echo "skip: Omarchy's input.lua not installed"
fi
echo "keyboard backend: ok"
