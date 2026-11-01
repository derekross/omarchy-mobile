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
  mark) touch "$d/$2" ;;
esac'
fake gsettings 'echo "gsettings $*" >>"$HOME/calls"'
fake systemctl 'echo "systemctl $*" >>"$HOME/calls"'
fake chromium 'echo "Chromium 153.0.0.0"'
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
    OMAMOBILE_DT="${RUN_DT:-$t/dt-gs201-cheetah}" \
    bash bin/omamobile-setup-user >"$t/out" 2>&1 || { cat "$t/out"; fail "omamobile-setup-user runs"; }
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
