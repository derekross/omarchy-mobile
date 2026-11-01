#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-keyboard-theme against a scratch home: the stylesheet from a
# sample colors.toml (Omarchy's keys), the gtk.css import kept once at the
# top with a user's own rules below it, the theme-set hook's restart only
# when something changed, and a missing theme leaving squeekboard alone.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
pkg=$PWD
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
H=$t/home F=$t/fakes; mkdir -p "$H" "$F"
# squeekboard "running", and what pkill/uwsm-app were asked to do
printf '#!/bin/bash\n[[ -e %s/running ]]\n' "$t" >"$F/pgrep"
printf '#!/bin/bash\necho "pkill $*" >>%s/calls; rm -f %s/running\n' "$t" "$t" >"$F/pkill"
printf '#!/bin/bash\necho "uwsm-app $*" >>%s/calls\n' "$t" >"$F/uwsm-app"
printf '#!/bin/bash\necho "JetBrainsMono Nerd Font"\n' >"$F/omarchy-font-current"
chmod +x "$F"/*
theme=$H/.local/state/omarchy/current/theme; mkdir -p "$theme"
cat >"$theme/colors.toml" <<'TOML'
mode = "dark"
accent = "#7aa2f7"
background = "#1a1b26"
dark_background = "#16161e"
lighter_background = "#24283b"
foreground = "#c0caf5"
muted = "#414868"
red = "#f7768e"
yellow = "#e0af68"
TOML
echo tokyo-night >"$H/.local/state/omarchy/current/theme.name"
run() { env -i HOME="$H" PATH="$F:/usr/bin:/bin" python3 -I "$pkg/bin/omamobile-keyboard-theme" "$@"; }

css=$H/.local/state/omamobile/keyboard.css
gtk=$H/.config/gtk-3.0/gtk.css
mkdir -p "$(dirname "$gtk")"
printf 'window { color: red; }\n' >"$gtk"   # a user's own rule
run --import
[[ -f $css ]] || fail "the stylesheet is written"
python3 -I - "$css" <<'PY' || fail "the stylesheet follows the theme"
import re, sys
css = open(sys.argv[1]).read()
def block(selector):
    m = re.search(r"(?m)^%s \{\n(.*?)\n\}" % re.escape(selector), css, re.S)
    assert m, selector
    return dict(l.strip().rstrip(";").split(": ", 1) for l in m.group(1).splitlines())
assert "tokyo-night" in css.splitlines()[0]
view = block("sq_view")
assert view["background"] == "#16161e" and view["box-shadow"] == "inset 0 2px 0 0 #7aa2f7", view
key = block("sq_button")
assert key["background"] == "#24283b" and key["color"] == "#c0caf5", key
assert key["border-radius"] == "0" and key["font-family"] == '"JetBrainsMono Nerd Font", monospace', key
latched = block("sq_button.latched, sq_button.locked")
assert latched["background"] == "#7aa2f7" and latched["color"] == "#1a1b26", latched
ret = block("#Return")
assert ret["background"] == "#7aa2f7" and ret["color"] == "#1a1b26", ret
assert block("sq_button.mic")["border-color"] == "#f7768e", "Mic in the recording colour"
assert "sq_button.talk" not in css and "sq_button.ask" not in css, "no Talk or Ask any more"
row = block("sq_button.mic, sq_button.paste, sq_button.emoji, sq_button.hide")
assert row["border"] == "2px solid #414868", row
special = [s for s in re.findall(r"(?m)^(sq_button\.special[^{]*) \{", css)][0]
for cls in ("term-key", "term-narrow", "small-row", "change-view", "special-3", "emoji-group"):
    assert "sq_button.%s," % cls in special + ",", cls
# no colour that isn't the theme's own or a mix of them: every literal is a hex
for value in re.findall(r"(?:background|color|border(?:-color)?|box-shadow): ([^;]+);", css):
    assert "@" not in value and "alpha(" not in value, value
PY
line="@import url(\"file://$css\"); /* omamobile-keyboard-theme */"
[[ $(head -1 "$gtk") == "$line" ]] || fail "gtk.css imports the stylesheet on its first line"
grep -cx 'window { color: red; }' "$gtk" >/dev/null || fail "a user's own gtk.css rules stay"
run --import
[[ $(grep -c 'omamobile-keyboard-theme' "$gtk") == 1 ]] || fail "the import is there once"

# The hook: a running squeekboard restarts when the theme changed, not otherwise
touch "$t/running"
run --restart
[[ ! -e $t/calls ]] || fail "no restart when nothing changed"
sed -i 's/^accent = .*/accent = "#ff0000"/' "$theme/colors.toml"
run --restart
grep -c 'background: #ff0000' "$css" >/dev/null || fail "a new theme rewrites the stylesheet"
[[ $(cat "$t/calls") == $'pkill -x squeekboard\nuwsm-app -- squeekboard' ]] || fail "a new theme restarts squeekboard as Omarchy started it"
rm -f "$t/calls"
sed -i 's/^accent = .*/accent = "#00ff00"/' "$theme/colors.toml"
run --restart
[[ ! -e $t/calls ]] || fail "a squeekboard that isn't running isn't started"
# Under Hyprland, through Hyprland's exec (from SSH or setup, a direct start
# didn't bring the keyboard back)
printf '#!/bin/bash\necho "hyprctl $*" >>%s/calls\n' "$t" >"$F/hyprctl"; chmod +x "$F/hyprctl"
touch "$t/running"; rm -f "$t/calls"
sed -i 's/^accent = .*/accent = "#0000ff"/' "$theme/colors.toml"
env -i HOME="$H" PATH="$F:/usr/bin:/bin" HYPRLAND_INSTANCE_SIGNATURE=x python3 -I "$pkg/bin/omamobile-keyboard-theme" --restart
[[ $(cat "$t/calls") == $'pkill -x squeekboard\nhyprctl dispatch hl.dsp.exec_cmd("uwsm-app -- squeekboard")' ]] || fail "under Hyprland, squeekboard restarts through its exec"
rm -f "$F/hyprctl" "$t/calls"

# Fallbacks: only Omarchy's three required colours
printf 'background = "#ffffff"\nforeground = "#000000"\naccent = "#0055ff"\nmode = "light"\n' >"$theme/colors.toml"
run
grep -c 'background: #0055ff' "$css" >/dev/null || fail "a minimal theme still gets its accent"
# No theme: nothing written, success
rm "$theme/colors.toml"; rm "$css"
run 2>/dev/null || fail "no theme is not an error"
[[ ! -e $css ]] || fail "no theme, no stylesheet"
echo "ok - the keyboard's stylesheet from the theme, its gtk.css import, the theme-set restart"
