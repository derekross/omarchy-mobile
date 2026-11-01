#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-setup-user against a scratch home and fake commands (omarchy-done,
# gsettings, systemctl, chromium): run twice, as two logins would, and check
# what it leaves in the user's files.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
pkg=$PWD
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

F=$t/fakes; H=$t/home; mkdir -p "$F" "$H/.config/hypr" "$H/.config/omarchy/extensions"
fake() { printf '#!/bin/bash\n%s\n' "$2" >"$F/$1"; chmod +x "$F/$1"; }
# omarchy-done: ensure succeeds once per name, mark records it
fake omarchy-done 'd=$HOME/.local/state/omarchy/done; mkdir -p "$d"
case $1 in
  ensure) [[ -e $d/$2 ]] && exit 1; touch "$d/$2" ;;
  check) [[ -e $d/$2 ]] ;;
  mark) touch "$d/$2" ;;
esac'
# gsettings: logs calls; list-keys answers for Nautilus (click-policy unless
# GSETTINGS_NO_CLICK_POLICY plays a Nautilus without the key)
fake gsettings 'echo "gsettings $*" >>"$HOME/calls"
if [[ $1 == list-keys && $2 == org.gnome.nautilus.preferences ]]; then
  printf "default-folder-viewer\n"; [[ -n ${GSETTINGS_NO_CLICK_POLICY:-} ]] || printf "click-policy\n"
fi'
fake systemctl 'echo "systemctl $*" >>"$HOME/calls"'
fake chromium 'echo "Chromium 153.0.0.0"'
fake omamobile-keyboard-theme 'echo "omamobile-keyboard-theme $*" >>"$HOME/calls"'
for f in monitors looknfeel autostart; do echo "-- $f" >"$H/.config/hypr/$f.lua"; done
printf 'local omarchy_gdk_scale = 2\nlocal omarchy_monitor_scale = "auto"\n' >"$H/.config/hypr/monitors.lua"
# Omarchy's shipped foot.ini, in the parts the phone changes
mkdir -p "$H/.config/foot"
printf '[main]\nfont=JetBrainsMono Nerd Font:size=9\npad=14x14\n\n[scrollback]\nlines=10000\nmultiplier=7.0\n\n[cursor]\nstyle=block\n' \
  >"$H/.config/foot/foot.ini"
# Omarchy's shipped extension file starts like this
printf '{\n  // Extend the Quickshell Omarchy menu with JSONC.\n  // "personal": {"icon":"","label":"Personal"},\n}\n' \
  >"$H/.config/omarchy/extensions/omarchy-menu.jsonc"

# The system's desktop entries: some of the apps the phone hides, one of them
# marked NoDisplay=false, and one app it keeps
A=$t/applications; mkdir -p "$A"
for id in org.gnome.DiskUtility org.gnome.Evince cups; do
  printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n' "$id" "$id" >"$A/$id.desktop"
done
printf '[Desktop Entry]\nType=Application\nName=Disks\nNoDisplay=false\nExec=gnome-disks\n' >"$A/org.gnome.DiskUtility.desktop"
printf '[Desktop Entry]\nType=Application\nName=Papers\nExec=papers\n' >"$A/org.gnome.Papers.desktop"

# The board, from a fake device tree so the host's own doesn't matter: the
# Pixel 7 Pro by default, the Pixel 9a where a test asks for it
for b in gs201-cheetah:gs201 zumapro-tegu:zumapro; do
  mkdir -p "$t/dt-${b%%:*}"; printf 'google,%s\0google,%s\0' "${b%%:*}" "${b#*:}" >"$t/dt-${b%%:*}/compatible"
done
run() {
  env -i HOME="${RUN_HOME:-$H}" PATH="$F:/usr/bin:/bin" XDG_RUNTIME_DIR="$t" OMAMOBILE_SHELL_SHARE="$pkg" OMAMOBILE_SYSTEM_APPLICATIONS="$A" \
    OMAMOBILE_DT="${RUN_DT:-$t/dt-gs201-cheetah}" OMAMOBILE_SQUEEKBOARD_SHARE="$pkg/squeekboard/keyboards" \
    GSETTINGS_NO_CLICK_POLICY="${GSETTINGS_NO_CLICK_POLICY:-}" \
    bash bin/omamobile-setup-user "$@" >"$t/out" 2>&1 || { cat "$t/out"; fail "omamobile-setup-user runs"; }
}
run
# A user who wants Logout back gives the row their own entry
ext=$H/.config/omarchy/extensions/omarchy-menu.jsonc
sed -i 's|^  "system.logout": {"when": "false"},$|  "system.logout": {"when": "true"},|' "$ext"
run

# The extension file as the menu reads it: JSONC with trailing commas
menu=$(python3 -I - "$ext" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
text = re.sub(r',(\s*[}\]])', r'\1', text)
for key, value in json.loads(text).items():
    print(key, value.get("when", ""))
PY
) || fail "the menu extension file stays valid JSONC"
for id in update.channel update.channel.stable update.channel.rc update.channel.edge update.channel.dev \
          update.config.hyprland update.config.shell setup.direct-boot update.password.drive \
          learn.keybindings learn.tmux-keybindings learn.herdr-keybindings \
          style.bar.position.left style.bar.position.right style.bar.position.bottom \
          trigger.toggle.top-bar trigger.toggle.one-window-ratio trigger.toggle.workspace-layout \
          install.windows install.browser.chrome install.gaming.steam; do
  grep -qx "$id false" <<<"$menu" || fail "Menu row $id is hidden"
  [[ $(grep -c "\"$id\"" "$ext") == 1 ]] || fail "Menu row $id is named once after two logins"
done
grep -qx 'system.logout true' <<<"$menu" || fail "a row the user set is left as they set it"
for id in style.bar.position.top update.omarchy install.gaming.retroarch; do
  grep -q "^$id false" <<<"$menu" && fail "Menu row $id stays"
done
pass "menu rows that break the phone are hidden once, by content, and a user's own entry is kept"

U=$H/.local/share/applications
for id in org.gnome.DiskUtility org.gnome.Evince cups; do
  [[ $(grep -c '^NoDisplay=true$' "$U/$id.desktop") == 1 ]] || fail "$id is hidden from the launcher"
  grep -c '^NoDisplay=false' "$U/$id.desktop" >/dev/null && fail "$id loses its NoDisplay=false"
  grep -qx "Exec=$id" "$U/$id.desktop" || [[ $id == org.gnome.DiskUtility ]] || fail "$id keeps its entry"
done
[[ ! -e $U/org.gnome.Papers.desktop ]] || fail "Papers stays in the launcher"
[[ ! -e $U/foot-server.desktop ]] || fail "an app that isn't installed gets no override"
# The user brings Disks back; an app installed later is hidden at the next login
rm "$U/org.gnome.DiskUtility.desktop"
printf '[Desktop Entry]\nType=Application\nName=Foot Server\nExec=foot --server\n' >"$A/foot-server.desktop"
run
[[ ! -e $U/org.gnome.DiskUtility.desktop ]] || fail "an override the user removed stays removed"
grep -qx 'NoDisplay=true' "$U/foot-server.desktop" || fail "an app installed later is hidden"
pass "desktop and admin apps are hidden once each, when installed, and a user's choice is kept"

# Idle: a new user gets the profile's block and the screensaver toggle
idle() { python3 -I -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1])).get("idle")))' "$1/.config/omarchy/shell.json"; }
toggle() { [[ -e $1/.local/state/omarchy/toggles/screensaver-off ]]; }
[[ $(idle "$H") == '{"screensaver": 0, "lock": 60}' ]] || fail "a new user's profile has the phone's idle block"
toggle "$H" || fail "a new user's screensaver is off"
# Users set up before this: one without an idle block, one with their own
for who in plain own; do
  h=$t/$who; mkdir -p "$h/.config/hypr" "$h/.config/omarchy" "$h/.local/state/omarchy/done"
  cp "$H"/.config/hypr/*.lua "$h/.config/hypr/"
  touch "$h/.local/state/omarchy/done/omamobile-shell-profile"
  echo '{"version": 1, "plugins": []}' >"$h/.config/omarchy/shell.json"
done
echo '{"version": 1, "plugins": [], "idle": {"screensaver": 300, "lock": 0}}' >"$t/own/.config/omarchy/shell.json"
RUN_HOME=$t/plain run
RUN_HOME=$t/own run
[[ $(idle "$t/plain") == '{"screensaver": 0, "lock": 60}' ]] && toggle "$t/plain" || fail "an earlier user without an idle block gets the phone's"
[[ $(idle "$t/own") == '{"screensaver": 300, "lock": 0}' ]] && ! toggle "$t/own" || fail "a user's own idle block is kept, and their screensaver"
pass "idle: lock after a minute, no screensaver, unless the user set their own"

# The phone rules land where Hyprland reads them: looknfeel.lua under
# Omarchy's hyprland.lua, hyprland.lua itself when the user's own file never
# loads looknfeel.lua (a bring-up gate); never twice.
grep -c 'dofile(".*hypr/phone.lua")' "$H/.config/hypr/looknfeel.lua" >/dev/null || fail "the phone rules are loaded from looknfeel.lua"
[[ $(grep -c 'hypr/phone.lua' "$H/.config/hypr/looknfeel.lua") == 1 ]] || fail "the phone rules are added once"
mkdir -p "$t/gate/.config/hypr" "$t/gate/.config/omarchy/extensions"
printf 'dofile("/usr/share/omarchy/default/hypr/bootstrap.lua")\nrequire("default.hypr.omarchy")\n' >"$t/gate/.config/hypr/hyprland.lua"
for f in monitors looknfeel autostart; do echo "-- $f" >"$t/gate/.config/hypr/$f.lua"; done
printf 'local omarchy_gdk_scale = 2\nlocal omarchy_monitor_scale = "auto"\n' >"$t/gate/.config/hypr/monitors.lua"
cp "$H/.config/omarchy/extensions/omarchy-menu.jsonc" "$t/gate/.config/omarchy/extensions/"
RUN_HOME=$t/gate run
grep -c 'dofile(".*hypr/phone.lua")' "$t/gate/.config/hypr/hyprland.lua" >/dev/null || fail "a hyprland.lua that skips looknfeel.lua gets the phone rules itself"
grep -c 'hypr/phone.lua' "$t/gate/.config/hypr/looknfeel.lua" >/dev/null && fail "the phone rules aren't put where Hyprland never reads them"
pass "the phone rules go to the file Hyprland loads, once"

# GDK_SCALE follows the phone's monitor scale (TOUCH-PLAN 2.8)
grep -cx 'local omarchy_monitor_scale = 3' "$H/.config/hypr/monitors.lua" >/dev/null || fail "the monitor scale is 3"
grep -cx 'local omarchy_gdk_scale = 3' "$H/.config/hypr/monitors.lua" >/dev/null || fail "GDK_SCALE is 3 with it"
# Foot for touch (TOUCH-PLAN 2.9), after two logins
foot=$H/.config/foot/foot.ini
grep -cx 'pad=6x6' "$foot" >/dev/null && ! grep -c '^pad=14x14' "$foot" >/dev/null || fail "foot's padding is 6x6"
grep -cx 'multiplier=3.0' "$foot" >/dev/null || fail "foot's scrollback multiplier is 3"
[[ $(grep -c '^\[touch\]$' "$foot") == 1 && $(grep -cx 'long-press-delay=300' "$foot") == 1 ]] || fail "foot's [touch] long press is 300 ms, once"
grep -cx 'style=block' "$foot" >/dev/null || fail "the rest of foot.ini is kept"
# Chromium's input method flags (TOUCH-PLAN 3.1), once each
flags=$H/.config/chromium-flags.conf
for flag in --enable-wayland-ime --wayland-text-input-version=3 --force-device-scale-factor=0.83; do
  [[ $(grep -cx -- "$flag" "$flags") == 1 ]] || fail "chromium-flags.conf has $flag once"
done
grep -c '^"--user-agent=.*Mobile Safari/537.36"$' "$flags" >/dev/null || fail "the mobile user agent stays quoted on its line"

# An earlier user with their own values: a monitor scale of 2, their own
# foot padding, multiplier and long press, and one of the flags already;
# their foot.ini appears only after the first login.
h=$t/custom; mkdir -p "$h/.config/hypr" "$h/.config/omarchy" "$h/.local/state/omarchy/done"
cp "$H"/.config/hypr/{looknfeel,autostart}.lua "$h/.config/hypr/"
printf 'local omarchy_gdk_scale = 2\nlocal omarchy_monitor_scale = 2\n' >"$h/.config/hypr/monitors.lua"
touch "$h/.local/state/omarchy/done/omamobile-monitor-scale"
printf -- '--enable-wayland-ime\n' >"$h/.config/chromium-flags.conf"
RUN_HOME=$h run
[[ ! -e $h/.local/state/omarchy/done/omamobile-foot-touch ]] || fail "the foot step waits for a foot.ini"
mkdir -p "$h/.config/foot"
printf '[main]\npad=10x10\n\n[scrollback]\nmultiplier=5.0\n\n[touch]\nlong-press-delay=500\n' >"$h/.config/foot/foot.ini"
cp "$h/.config/foot/foot.ini" "$t/custom-foot.ini"
RUN_HOME=$h run
grep -cx 'local omarchy_gdk_scale = 2' "$h/.config/hypr/monitors.lua" >/dev/null || fail "GDK_SCALE stays with a user's own monitor scale"
cmp -s "$h/.config/foot/foot.ini" "$t/custom-foot.ini" || fail "a user's own foot values stay theirs"
[[ -e $h/.local/state/omarchy/done/omamobile-foot-touch ]] || fail "the foot step runs once foot.ini is there"
[[ $(grep -cx -- --enable-wayland-ime "$h/.config/chromium-flags.conf") == 1 ]] || fail "a flag the user has isn't added twice"
grep -cx -- --wayland-text-input-version=3 "$h/.config/chromium-flags.conf" >/dev/null || fail "the missing flag is added"
pass "GDK scale, foot and Chromium's input method, once each, and a user's own values are kept"

# The Pixel 9a: a new user gets 8 / 3 (405x909 logical), and GDK_SCALE stays
# Omarchy's 2 (its step only follows a monitor scale of exactly 3)
h9=$t/tegu; mkdir -p "$h9/.config/hypr" "$h9/.config/omarchy/extensions"
cp "$H"/.config/hypr/{looknfeel,autostart}.lua "$h9/.config/hypr/"
printf 'local omarchy_gdk_scale = 2\nlocal omarchy_monitor_scale = "auto"\n' >"$h9/.config/hypr/monitors.lua"
RUN_HOME=$h9 RUN_DT=$t/dt-zumapro-tegu run
grep -cx 'local omarchy_monitor_scale = 8 / 3' "$h9/.config/hypr/monitors.lua" >/dev/null || fail "the 9a's monitor scale is 8 / 3"
grep -cx 'local omarchy_gdk_scale = 2' "$h9/.config/hypr/monitors.lua" >/dev/null || fail "the 9a's GDK_SCALE step is skipped"
pass "the Pixel 9a's scale: 8 / 3, GDK_SCALE left at 2"

# Voxtype (phase 3): base.en stays the model, and Whisper's context is cut to
# the clip (context_window_optimization) once; 0.2.58-0.2.62's tiny.en is
# undone once if nobody changed the config since; a user's model and a
# user's own context setting stay; voxtype restarts only when something changed.
vc() { sed -n '/^\[whisper\]$/,/^\[/p' "$1/.config/voxtype/config.toml"; }
vhome() {
  mkdir -p "$1/.config/hypr" "$1/.config/omarchy/extensions" "$1/.config/voxtype" "$1/.local/share/voxtype/models" "$1/.local/state/omarchy/done"
  cp "$H"/.config/hypr/{looknfeel,autostart,monitors}.lua "$1/.config/hypr/"
  touch "$1/.local/share/voxtype/models/ggml-tiny.en.bin" "$1/.local/share/voxtype/models/ggml-base.en.bin"
}
hv=$t/voice; vhome "$hv"
printf 'state_file = "auto"\n\n[audio]\nmodel = "base.en"\n\n[whisper]\nmodel = "base.en"\nlanguage = "en"\n# context_window_optimization = true\n' >"$hv/.config/voxtype/config.toml"
RUN_HOME=$hv run
[[ $(grep -cx 'model = "base.en"' "$hv/.config/voxtype/config.toml") == 2 ]] || fail "tiny.en on disk: the model stays base.en"
[[ $(vc "$hv" | grep -cx 'context_window_optimization = true') == 1 ]] || fail "the context cut goes under [whisper] once (a commented line isn't a setting)"
sed -n '/^\[audio\]$/,/^\[/p' "$hv/.config/voxtype/config.toml" | grep -c context_window >/dev/null && fail "only [whisper] changes"
[[ $(grep -c 'systemctl --user try-restart voxtype.service' "$hv/calls") == 1 ]] || fail "voxtype restarts once, for the new setting"
sed -i '/^context_window_optimization = true$/d' "$hv/.config/voxtype/config.toml"
RUN_HOME=$hv run
if vc "$hv" | grep -cx 'context_window_optimization = true' >/dev/null; then fail "a user who removed the setting keeps it removed"; fi
[[ $(grep -c 'systemctl --user try-restart voxtype.service' "$hv/calls") == 1 ]] || fail "voxtype isn't restarted for nothing"
# 0.2.62's switch to tiny.en, untouched since: back to base.en, once
h2=$t/voice-tiny; vhome "$h2"
printf '[whisper]\nmodel = "tiny.en"\ncontext_window_optimization = false\n' >"$h2/.config/voxtype/config.toml"
touch "$h2/.local/state/omarchy/done/omamobile-voxtype-tiny"
hc=$t/voice-chosen; cp -r "$h2" "$hc"
h3=$t/voice-nobase; cp -r "$h2" "$h3"; rm "$h3/.local/share/voxtype/models/ggml-base.en.bin"
RUN_HOME=$h2 run
vc "$h2" | grep -cx 'model = "base.en"' >/dev/null || fail "setup's own tiny.en goes back to base.en"
vc "$h2" | grep -cx 'context_window_optimization = false' >/dev/null || fail "a user's own context setting stays"
[[ $(grep -c 'try-restart voxtype' "$h2/calls") == 1 ]] || fail "voxtype restarts once, for the model"
sed -i 's/^model = "base.en"$/model = "tiny.en"/' "$h2/.config/voxtype/config.toml"
RUN_HOME=$h2 run
vc "$h2" | grep -cx 'model = "tiny.en"' >/dev/null || fail "tiny.en chosen after the switch back stays (it happens once)"
# tiny.en chosen after 0.2.62's switch (the config is newer than the marker): it stays
touch -d '-1 hour' "$hc/.local/state/omarchy/done/omamobile-voxtype-tiny"
RUN_HOME=$hc run
vc "$hc" | grep -cx 'model = "tiny.en"' >/dev/null || fail "a model the user chose since stays"
if grep -c 'try-restart voxtype' "$hc/calls" >/dev/null 2>&1; then fail "voxtype isn't restarted for nothing"; fi
RUN_HOME=$h3 run
vc "$h3" | grep -cx 'model = "tiny.en"' >/dev/null || fail "without base.en on disk, tiny.en stays"
python3 -I - "$hv/.config/omarchy/extensions/omarchy-menu.jsonc" <<'PY' || fail "Setup > Voice opens the voice settings"
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r"(?m)^\s*//.*$", "", text)
text = re.sub(r",(\s*[}\]])", r"\1", text)
voice = json.loads(text)["setup.voice"]
assert voice["action"] == "omarchy-shell shell summon omamobile.voice '{\"page\":\"settings\"}'", voice
assert voice["label"] == "Voice" and voice["icon"] == "\U000f036c", voice
PY
pass "voxtype: base.en with the context cut, 0.2.62's tiny.en undone once, a user's choices kept"

# The keyboard: every layout the package carries linked (the terminal's, and
# each language's from squeekboard/generate), the theme written at every
# login, its gtk.css import and theme-set hook added once (H ran three times).
for layout in terminal/us.yaml terminal/us_wide.yaml us.yaml us_wide.yaml de.yaml fr_wide.yaml url/us.yaml terminal/de.yaml; do
  [[ $(readlink "$H/.local/share/squeekboard/keyboards/$layout") == "/usr/share/omamobile/squeekboard/keyboards/$layout" ]] \
    || fail "the $layout layout is linked"
done
[[ $(find "$H/.local/share/squeekboard/keyboards" -type l | wc -l) == $(find squeekboard/keyboards -type f -name '*.yaml' | wc -l) ]] \
  || fail "every layout in the package is linked"
[[ $(grep -c '^omamobile-keyboard-theme --import --restart$' "$H/calls") == 1 && $(grep -c '^omamobile-keyboard-theme --restart$' "$H/calls") -ge 1 ]] \
  || fail "the keyboard theme: --import at the first login, a rewrite after; a running squeekboard restarts when either is new"
[[ $(readlink "$H/.config/omarchy/hooks/theme-set.d/50-omamobile-keyboard") == "$pkg/hooks/theme-set-keyboard" ]] \
  || fail "the keyboard's theme-set hook is linked"
pass "the keyboard: every layout, the theme at each login, its import and hook once"

# A layout of the user's own stays theirs
hk=$t/keyboard-own; mkdir -p "$hk/.config/hypr" "$hk/.config/omarchy/extensions" "$hk/.local/share/squeekboard/keyboards"
cp "$H"/.config/hypr/{looknfeel,autostart,monitors}.lua "$hk/.config/hypr/"
printf '# mine\n' >"$hk/.local/share/squeekboard/keyboards/de.yaml"
RUN_HOME=$hk run
[[ ! -L $hk/.local/share/squeekboard/keyboards/de.yaml && $(cat "$hk/.local/share/squeekboard/keyboards/de.yaml") == "# mine" ]] \
  || fail "a layout the user wrote stays"
[[ -L $hk/.local/share/squeekboard/keyboards/fr.yaml ]] || fail "the others are linked beside it"
pass "the keyboard: a layout of the user's own stays"

# --adopt: a user set up by hand, with no markers, keeps the files the
# overwriting steps would change (shell.json, the scale, the cursor and
# keyboard lines, the screensaver), while the steps that check before they
# change still run (Chromium's flags among them); a login afterwards changes
# nothing more
ha=$t/home-adopt; mkdir -p "$ha/.config/hypr" "$ha/.config/omarchy/extensions" "$ha/.config/foot" "$ha/.config/omarchy/branding"
printf '[main]\npad=10x10\n\n[touch]\nlong-press-delay=500\n' >"$ha/.config/foot/foot.ini"
printf '{\n}\n' >"$ha/.config/omarchy/extensions/omarchy-menu.jsonc"
printf '{"plugins": [{"id": "mine"}]}\n' >"$ha/.config/omarchy/shell.json"
printf -- '-- mine\nhl.config({ cursor = { invisible = true } })\ndofile("%s/hypr/phone.lua")\n' "$pkg" >"$ha/.config/hypr/looknfeel.lua"
printf -- '-- mine\n' >"$ha/.config/hypr/autostart.lua"
printf 'local omarchy_gdk_scale = 2\nlocal omarchy_monitor_scale = 2\n' >"$ha/.config/hypr/monitors.lua"
printf 'mine\n' >"$ha/.config/omarchy/branding/screensaver.txt"
snap() { (cd "$ha/.config" && cat hypr/looknfeel.lua hypr/autostart.lua hypr/monitors.lua omarchy/branding/screensaver.txt foot/foot.ini) | sha256sum; }
before=$(snap)
RUN_HOME=$ha run --adopt; out=$(cat "$t/out")
[[ $(snap) == "$before" ]] || fail "--adopt changed a file an overwriting step owns"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert {"id":"mine"} in d["plugins"]' "$ha/.config/omarchy/shell.json" || fail "--adopt reseeded shell.json"
for s in omamobile-shell-profile omamobile-monitor-scale omamobile-hide-cursor omamobile-osk omamobile-screensaver; do
  [[ -e $ha/.local/state/omarchy/done/$s ]] || fail "--adopt did not mark $s"
  grep -c "adopted $s" <<<"$out" >/dev/null || fail "--adopt did not say it adopted $s"
done
grep -cx -- --no-first-run "$ha/.config/chromium-flags.conf" >/dev/null || fail "--adopt skipped Chromium's flags"
[[ -L $ha/.config/omarchy/plugins/omamobile.home ]] || fail "--adopt still links the plugins"
before=$(snap); flags=$(sha256sum <"$ha/.config/chromium-flags.conf")
RUN_HOME=$ha run
[[ $(snap) == "$before" && $(sha256sum <"$ha/.config/chromium-flags.conf") == "$flags" ]] || fail "a login after --adopt changed the user's files"
pass "--adopt: the overwriting steps are marked and skipped, the checked steps (Chromium's flags) run, and later logins change nothing"
# Files opens folders with one tap (issue #261): set once (H ran three times),
# and not at all on a Nautilus without the click-policy key
[[ $(grep -c '^gsettings set org.gnome.nautilus.preferences click-policy single$' "$H/calls") == 1 ]] \
  || fail "Nautilus's click-policy is set to single once"
hn=$t/no-click-policy; mkdir -p "$hn/.config/hypr" "$hn/.config/omarchy/extensions"
cp "$H"/.config/hypr/{looknfeel,autostart,monitors}.lua "$hn/.config/hypr/"
RUN_HOME=$hn GSETTINGS_NO_CLICK_POLICY=1 run
grep -q '^gsettings set org.gnome.nautilus.preferences' "$hn/calls" && fail "nothing is set on a Nautilus without click-policy"
[[ ! -e $hn/.local/state/omarchy/done/omamobile-files-single-tap ]] || fail "the step isn't marked done when the key is missing"
pass "Files: one tap opens a folder, set once, skipped on a Nautilus without the key"
