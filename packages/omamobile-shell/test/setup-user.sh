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
# systemctl: logs calls; fails while $HOME/systemctl-fails exists (no user manager)
# `show -p DropInPaths` prints $HOME/drop-ins; `is-active` is true while
# $HOME/active-<unit> exists
fake systemctl 'echo "systemctl $*" >>"$HOME/calls"; [[ ! -e $HOME/systemctl-fails ]] || exit 1
if [[ $2 == show ]]; then [[ -e $HOME/drop-ins ]] && cat "$HOME/drop-ins"; exit 0; fi
if [[ $2 == is-active ]]; then [[ -e $HOME/active-${4:-} ]]; exit; fi
exit 0'
ln -s "$pkg/bin/omamobile-browser-setup" "$F/omamobile-browser-setup"
fake hyprctl 'exit 1'
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
# The panel's modes, from a fake /sys/class/drm: the 7 Pro's by default, the
# 9a's, a 1080x2400 panel, and none at all
for p in 1440x3120 1080x2424 1080x2400; do
  mkdir -p "$t/drm-$p/card2-DSI-1" "$t/drm-$p/card2-DP-1"
  printf '%s\n%s\n' "$p" "${p%x*}x$((${p#*x} / 2))" >"$t/drm-$p/card2-DSI-1/modes"
  echo 3840x2160 >"$t/drm-$p/card2-DP-1/modes"   # an external display isn't the panel
done
mkdir -p "$t/drm-none"
# Omarchy's default-keyring step, as Omarchy ships it (only what's missing)
mkdir -p "$t/omarchy/install/user"
cat >"$t/omarchy/install/user/default-keyring.sh" <<'KR'
d="$HOME/.local/share/keyrings"; mkdir -p "$d"
[[ -f $d/default ]] || echo Default_keyring >"$d/default"
KR
run() {
  env -i HOME="${RUN_HOME:-$H}" PATH="$F:/usr/bin:/bin" XDG_RUNTIME_DIR="$t" OMAMOBILE_SHELL_SHARE="$pkg" OMAMOBILE_SYSTEM_APPLICATIONS="$A" \
    OMAMOBILE_DT="${RUN_DT:-$t/dt-gs201-cheetah}" OMAMOBILE_DRM="${RUN_DRM:-$t/drm-1440x3120}" \
    OMAMOBILE_SQUEEKBOARD_SHARE="$pkg/squeekboard/keyboards" \
    GSETTINGS_NO_CLICK_POLICY="${GSETTINGS_NO_CLICK_POLICY:-}" \
    OMAMOBILE_VOICE_MODELS="${RUN_VOICE_MODELS:-$t/no-voice-models}" OMAMOBILE_VOXTYPE="${RUN_VOXTYPE:-voxtype}" \
    OMARCHY_PATH="${RUN_OMARCHY_PATH:-$t/omarchy}" \
    OMAMOBILE_USER_UNITS="${RUN_USER_UNITS:-$t/no-user-units}" \
    OMAMOBILE_AUTO_SLEEP_DEFAULT="${RUN_AUTO_SLEEP:-$t/no-auto-sleep-default}" \
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
          appearance.top-bar.position.left appearance.top-bar.position.right appearance.top-bar.position.bottom \
          appearance.top-bar.hide appearance.top-bar.show appearance.windows.one-window-ratio-on \
          appearance.windows.one-window-ratio-off appearance.workspace-layout appearance.workspace-layout.floating \
          appearance.unlock appearance.dock appearance.dock.position.left update.kernel \
          install.windows install.browser.chrome install.gaming.steam; do
  grep -qx "$id false" <<<"$menu" || fail "Menu row $id is hidden"
  [[ $(grep -c "\"$id\"" "$ext") == 1 ]] || fail "Menu row $id is named once after two logins"
done
grep -qx 'system.logout true' <<<"$menu" || fail "a row the user set is left as they set it"
# Typing shows only while fcitx5 is on, and a reused id replaces Omarchy's
# entry, so each row carries its own label, icon and action
typing=$(python3 -I - "$ext" <<'PY2'
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
text = re.sub(r',(\s*[}\]])', r'\1', text)
for key, value in json.loads(text).items():
    if key.startswith("setup.typing"):
        print(key, value["icon"] == "\uf11c", value["label"], value.get("action", "-"), value["when"], sep="|")
PY2
)
[[ $typing == $'setup.typing|True|Typing|-|test -e ~/.config/omamobile/fcitx5\nsetup.typing.keyboard|True|Keyboard Layouts|omarchy-setup-keyboard|test -e ~/.config/omamobile/fcitx5\nsetup.typing.input|True|Input Methods|omarchy-setup-input|test -e ~/.config/omamobile/fcitx5' ]] ||
  fail "Setup > Typing shows only with fcitx5 on, with its label, icon and action: $typing"
for id in setup.typing setup.typing.keyboard setup.typing.input; do
  [[ $(grep -c "\"$id\"" "$ext") == 1 ]] || fail "Menu row $id is named once after two logins"
done
for id in style.bar.position.top appearance.top-bar.position.top appearance.top-bar.indicators update.omarchy install.gaming.retroarch; do
  grep -q "^$id false" <<<"$menu" && fail "Menu row $id stays"
done
pass "menu rows that break the phone are hidden once, by content, Typing only without fcitx5, and a user's own entry is kept"

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

# Omarchy's "Image Viewer" (imv, the skeleton's copy in the user's
# applications) gives way to Loupe's, once, and only while Loupe is installed
printf '[Desktop Entry]\nName=Image Viewer\nExec=imv %%F\nType=Application\n' >"$U/imv.desktop"
run
grep -c '^NoDisplay' "$U/imv.desktop" >/dev/null && fail "imv stays in the drawer without Loupe"
printf '[Desktop Entry]\nType=Application\nName=Image Viewer\nExec=loupe %%U\n' >"$A/org.gnome.Loupe.desktop"
run
[[ $(sed -n 2p "$U/imv.desktop") == NoDisplay=true ]] && grep -qx 'Exec=imv %F' "$U/imv.desktop" \
  || fail "imv's entry is hidden once Loupe is installed, the rest kept"
sed -i '/^NoDisplay=true$/d' "$U/imv.desktop"
run
grep -c '^NoDisplay' "$U/imv.desktop" >/dev/null && fail "a user who shows imv again keeps it"
pass "imv's Image Viewer gives way to Loupe's, once"

# Tensaku's entry (drawer, Open With) runs without the on-screen keyboard, once
printf '[Desktop Entry]\nName=Tensaku\nTryExec=tensaku\nExec=tensaku %%f\nType=Application\n' >"$A/dev.tensaku.Tensaku.desktop"
run
grep -qx 'Exec=env GTK_IM_MODULE=gtk-im-context-simple tensaku %f' "$U/dev.tensaku.Tensaku.desktop" &&
  grep -qx 'TryExec=tensaku' "$U/dev.tensaku.Tensaku.desktop" || fail "Tensaku's entry gets GTK's simple input context"
rm "$U/dev.tensaku.Tensaku.desktop"
run
[[ ! -e $U/dev.tensaku.Tensaku.desktop ]] || fail "a user who removes the Tensaku override keeps Tensaku's own entry"
pass "Tensaku's entry opens without the on-screen keyboard, once"

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
[[ $(grep -cx 'selection-target=both' "$foot") == 1 ]] || fail "foot's selection goes to the clipboard too, once"
[[ $(sed -n '/^\[main\]$/{n;p;q}' "$foot") == selection-target=both ]] || fail "selection-target is in [main]"
# Chromium's input method flags (TOUCH-PLAN 3.1), once each
flags=$H/.config/chromium-flags.conf
for flag in --enable-wayland-ime --wayland-text-input-version=3 --force-device-scale-factor=0.83; do
  [[ $(grep -cx -- "$flag" "$flags") == 1 ]] || fail "chromium-flags.conf has $flag once"
done
python3 - "$flags" <<'PYUA' || fail "the mobile user agent parses as one argument"
import shlex, sys
flags = shlex.split(open(sys.argv[1]).read(), comments=True)
ua = [f for f in flags if f.startswith("--user-agent=")]
assert len(ua) == 1 and ua[0].endswith("Chrome/153.0.0.0 Mobile Safari/537.36"), ua
PYUA
# Grok Bot's flags: the 7 Pro's factor, once, after two logins
gflags=$H/.config/grok-bot-flags.conf
[[ $(grep -cx -- --force-device-scale-factor=0.83 "$gflags") == 1 ]] || fail "grok-bot-flags.conf has the 7 Pro's factor once"
[[ $(wc -l <"$gflags") == 1 ]] || fail "grok-bot-flags.conf holds only that"

# An earlier user with their own values: a monitor scale of 2, their own
# foot padding, multiplier and long press, and one of the flags already;
# their foot.ini appears only after the first login.
h=$t/custom; mkdir -p "$h/.config/hypr" "$h/.config/omarchy" "$h/.local/state/omarchy/done"
cp "$H"/.config/hypr/{looknfeel,autostart}.lua "$h/.config/hypr/"
printf 'local omarchy_gdk_scale = 2\nlocal omarchy_monitor_scale = 2\n' >"$h/.config/hypr/monitors.lua"
touch "$h/.local/state/omarchy/done/omamobile-monitor-scale"
printf -- '--enable-wayland-ime\n' >"$h/.config/chromium-flags.conf"
printf -- '--force-device-scale-factor=1\n--disable-gpu\n' >"$h/.config/grok-bot-flags.conf"
RUN_HOME=$h run
[[ ! -e $h/.local/state/omarchy/done/omamobile-foot-touch ]] || fail "the foot step waits for a foot.ini"
mkdir -p "$h/.config/foot"
printf '[main]\npad=10x10\n\n[scrollback]\nmultiplier=5.0\n\n[touch]\nlong-press-delay=500\n' >"$h/.config/foot/foot.ini"
cp "$h/.config/foot/foot.ini" "$t/custom-foot.ini"
RUN_HOME=$h run
grep -cx 'local omarchy_gdk_scale = 2' "$h/.config/hypr/monitors.lua" >/dev/null || fail "GDK_SCALE stays with a user's own monitor scale"
grep -v '^selection-target=both$' "$h/.config/foot/foot.ini" | cmp -s - "$t/custom-foot.ini" || fail "a user's own foot values stay theirs"
# selection-target: an existing one (spaces allowed) is kept, a file without [main] gets one on top
for c in 'selection-target = primary' '  selection-target=primary'; do
  hs=$t/home-sel; rm -rf "$hs"; mkdir -p "$hs/.config/hypr" "$hs/.config/omarchy" "$hs/.config/foot"
  cp "$H"/.config/hypr/{looknfeel,autostart,monitors}.lua "$hs/.config/hypr/"; printf '[main]\n%s\n' "$c" >"$hs/.config/foot/foot.ini"
  RUN_HOME=$hs run
  [[ $(grep -c 'selection-target' "$hs/.config/foot/foot.ini") == 1 ]] || fail "an existing selection-target ($c) is kept alone"
done
hs=$t/home-sel; rm -rf "$hs"; mkdir -p "$hs/.config/hypr" "$hs/.config/omarchy" "$hs/.config/foot"
cp "$H"/.config/hypr/{looknfeel,autostart,monitors}.lua "$hs/.config/hypr/"; printf 'font=x:size=9\n\n[colors]\nalpha=1\n' >"$hs/.config/foot/foot.ini"
RUN_HOME=$hs run
[[ $(head -2 "$hs/.config/foot/foot.ini") == $'[main]\nselection-target=both' ]] && grep -cx 'font=x:size=9' "$hs/.config/foot/foot.ini" >/dev/null || fail "a foot.ini without [main] gets one on top and keeps its keys"

# A foot.ini in a read-only directory (sed -i and mktemp can't make their temp file), with
# and without [main]: nothing is written, the marker is taken back and the login goes on
if [[ $(id -u) != 0 ]]; then
  for c in '[main]\nfont=x:size=9\n' 'font=x:size=9\n'; do
    hs=$t/home-sel; chmod -R u+w "$hs" 2>/dev/null || true; rm -rf "$hs"
    mkdir -p "$hs/.config/hypr" "$hs/.config/omarchy" "$hs/.config/foot" "$hs/.local/state/omarchy/done"
    cp "$H"/.config/hypr/{looknfeel,autostart,monitors}.lua "$hs/.config/hypr/"; printf "$c" >"$hs/.config/foot/foot.ini"
    : >"$hs/.local/state/omarchy/done/omamobile-screensaver"; : >"$hs/.local/state/omarchy/done/omamobile-foot-touch"
    cp "$hs/.config/foot/foot.ini" "$t/ro-foot.ini"; chmod a-w "$hs/.config/foot"
    RUN_HOME=$hs run || fail "a read-only foot directory doesn't stop the login ($c)"
    chmod u+w "$hs/.config/foot"
    cmp -s "$hs/.config/foot/foot.ini" "$t/ro-foot.ini" || fail "a failed foot write leaves foot.ini as it was ($c)"
    [[ ! -e $hs/.local/state/omarchy/done/omamobile-foot-selection ]] || fail "a failed foot write leaves the step for the next login ($c)"
    [[ -z $(find "$hs/.config/foot" -name '.foot.ini.*') ]] || fail "a failed foot write leaves no temp file ($c)"
  done
fi
[[ -e $h/.local/state/omarchy/done/omamobile-foot-touch ]] || fail "the foot step runs once foot.ini is there"
[[ $(grep -cx -- --enable-wayland-ime "$h/.config/chromium-flags.conf") == 1 ]] || fail "a flag the user has isn't added twice"
grep -cx -- --wayland-text-input-version=3 "$h/.config/chromium-flags.conf" >/dev/null || fail "the missing flag is added"
g=$h/.config/grok-bot-flags.conf
[[ $(grep -c -- '^--force-device-scale-factor=' "$g") == 1 ]] && grep -cx -- --force-device-scale-factor=1 "$g" >/dev/null \
  || fail "a user's own Grok Bot scale factor stays theirs"
[[ $(wc -l <"$g") == 2 ]] && grep -cx -- --disable-gpu "$g" >/dev/null || fail "Grok Bot's file keeps the user's other flags, unchanged"
pass "GDK scale, foot, Chromium's and Grok Bot's flags, once each, and a user's own values are kept"

# The Pixel 9a: a new user gets 8 / 3 (405x909 logical), and GDK_SCALE stays
# Omarchy's 2 (its step only follows a monitor scale of exactly 3)
h9=$t/tegu; mkdir -p "$h9/.config/hypr" "$h9/.config/omarchy/extensions"
cp "$H"/.config/hypr/{looknfeel,autostart}.lua "$h9/.config/hypr/"
printf 'local omarchy_gdk_scale = 2\nlocal omarchy_monitor_scale = "auto"\n' >"$h9/.config/hypr/monitors.lua"
RUN_HOME=$h9 RUN_DT=$t/dt-zumapro-tegu RUN_DRM=$t/drm-1080x2424 run
grep -cx 'local omarchy_monitor_scale = 8 / 3' "$h9/.config/hypr/monitors.lua" >/dev/null || fail "the 9a's monitor scale is 8 / 3"
grep -cx 'local omarchy_gdk_scale = 2' "$h9/.config/hypr/monitors.lua" >/dev/null || fail "the 9a's GDK_SCALE step is skipped"
grep -cx -- --force-device-scale-factor=0.70 "$h9/.config/grok-bot-flags.conf" >/dev/null || fail "Grok Bot's factor on the 9a (405 px) is 0.70"
pass "the Pixel 9a's scale: 8 / 3, GDK_SCALE left at 2, Grok Bot at 0.70"

# Grok Bot's factor follows the panel: 0.62 for a 1080 px panel at scale 3
# (360 px); no geometry defers only scale, keeping Chromium's other defaults
for c in 1080x2400:0.62; do
  hg=$t/grok-${c%%:*}; mkdir -p "$hg/.config/hypr" "$hg/.config/omarchy/extensions"
  cp "$H"/.config/hypr/{looknfeel,autostart,monitors}.lua "$hg/.config/hypr/"
  RUN_HOME=$hg RUN_DRM=$t/drm-${c%%:*} run
  grep -cx -- "--force-device-scale-factor=${c#*:}" "$hg/.config/grok-bot-flags.conf" >/dev/null \
    || fail "Grok Bot's factor with panel ${c%%:*} is ${c#*:}"
done
hg=$t/grok-none; mkdir -p "$hg/.config/hypr" "$hg/.config/omarchy/extensions"
cp "$H"/.config/hypr/{looknfeel,autostart,monitors}.lua "$hg/.config/hypr/"
RUN_HOME=$hg RUN_DRM=$t/drm-none run
[[ ! -e $hg/.config/grok-bot-flags.conf ]] || fail "no panel defers Grok's scale"
python3 - "$hg/.config/chromium-flags.conf" <<'PYDEFAULTS'
import shlex, sys
flags = shlex.split(open(sys.argv[1]).read(), comments=True)
assert '--no-first-run' in flags and '--enable-wayland-ime' in flags
assert '--wayland-text-input-version=3' in flags
assert len([f for f in flags if f.startswith('--user-agent=')]) == 1
assert not any(f.startswith('--force-device-scale-factor=') for f in flags)
PYDEFAULTS
RUN_HOME=$hg RUN_DRM=$t/drm-1080x2400 run
for app in grok-bot chromium; do
  grep -cx -- --force-device-scale-factor=0.62 "$hg/.config/$app-flags.conf" >/dev/null || fail "$app retries with geometry"
done
pass "Grok Bot's scale factor gives about 578 px of layout width on any panel"

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

# Voice out of the box (omamobile-voice): with voxtype and the shipped
# base.en, a new user gets Omarchy's config, a link to the model and the
# daemon enabled, once, and Omarchy's install invitation marked done; a
# user's own config and model stay; nothing without voxtype or the model.
VM=$t/voice-models; mkdir -p "$VM" "$t/omarchy/default/voxtype"
echo model >"$VM/ggml-base.en.bin"
printf 'state_file = "auto"\n\n[whisper]\nmodel = "base.en"\nlanguage = "en"\n' >"$t/omarchy/default/voxtype/config.toml"
fake voxtype 'echo "voxtype $*" >>"$HOME/calls"'
hn=$t/voice-new; vhome "$hn"; rm -rf "$hn/.config/voxtype" "$hn/.local/share/voxtype"
RUN_HOME=$hn RUN_VOICE_MODELS=$VM run
[[ $(readlink "$hn/.local/share/voxtype/models/ggml-base.en.bin") == "$VM/ggml-base.en.bin" ]] || fail "the shipped base.en is linked into Voxtype's models directory"
vc "$hn" | grep -cx 'model = "base.en"' >/dev/null || fail "Omarchy's Voxtype config is copied for a new user"
vc "$hn" | grep -cx 'context_window_optimization = true' >/dev/null || fail "the new config gets the context cut too"
[[ $(grep -cx 'systemctl --user enable voxtype.service' "$hn/calls") == 1 ]] || fail "voxtype.service is enabled once"
[[ -e $hn/.local/state/omarchy/done/voxtype-install-invitation ]] || fail "Omarchy's Install Dictation invitation is marked done"
[[ $(cat "$hn/.config/omarchy/defaults/dictation") == voxtype ]] || fail "Voxtype is recorded as the dictation default (Omarchy 4.5 asks)"
if grep -c '^voxtype ' "$hn/calls" >/dev/null 2>&1; then fail "nothing is downloaded (no voxtype setup)"; fi
rm "$hn/.local/share/voxtype/models/ggml-base.en.bin"
RUN_HOME=$hn RUN_VOICE_MODELS=$VM run
[[ ! -e $hn/.local/share/voxtype/models/ggml-base.en.bin ]] || fail "a model the user removed stays removed (once)"
[[ $(grep -cx 'systemctl --user enable voxtype.service' "$hn/calls") == 1 ]] || fail "voxtype.service is enabled only once"
# A user with Voxtype set up already: config and downloaded model stay
ho=$t/voice-own; vhome "$ho"; echo own >"$ho/.local/share/voxtype/models/ggml-base.en.bin"
mkdir -p "$ho/.config/omarchy/defaults"; echo superwhisper >"$ho/.config/omarchy/defaults/dictation"
printf '[whisper]\nmodel = "tiny.en"\n' >"$ho/.config/voxtype/config.toml"
RUN_HOME=$ho RUN_VOICE_MODELS=$VM run
[[ ! -L $ho/.local/share/voxtype/models/ggml-base.en.bin && $(cat "$ho/.local/share/voxtype/models/ggml-base.en.bin") == own ]] || fail "a downloaded model stays"
vc "$ho" | grep -cx 'model = "tiny.en"' >/dev/null || fail "the user's Voxtype config stays"
[[ $(cat "$ho/.config/omarchy/defaults/dictation") == superwhisper ]] || fail "a dictation default the owner chose stays"
rm "$hn/.config/omarchy/defaults/dictation"
RUN_HOME=$hn RUN_VOICE_MODELS=$VM run
[[ ! -e $hn/.config/omarchy/defaults/dictation ]] || fail "a dictation default the owner removed is not written again"
# A failed enable (firstboot without a user manager) is tried again at the
# next login, and only until it works; the once-only parts don't repeat
hr=$t/voice-retry; vhome "$hr"; rm -rf "$hr/.config/voxtype" "$hr/.local/share/voxtype"; touch "$hr/systemctl-fails"
RUN_HOME=$hr RUN_VOICE_MODELS=$VM run
[[ -L $hr/.local/share/voxtype/models/ggml-base.en.bin && -f $hr/.config/voxtype/config.toml ]] || fail "a failed enable still leaves the config and the link"
[[ ! -e $hr/.local/state/omarchy/done/omamobile-voxtype-enabled ]] || fail "a failed enable isn't marked done"
rm "$hr/systemctl-fails" "$hr/.config/voxtype/config.toml"
RUN_HOME=$hr RUN_VOICE_MODELS=$VM run
[[ $(grep -cx 'systemctl --user enable voxtype.service' "$hr/calls") == 2 ]] || fail "the enable is tried again at the next login"
[[ -e $hr/.local/state/omarchy/done/omamobile-voxtype-enabled ]] || fail "a working enable is marked done"
[[ ! -e $hr/.config/voxtype/config.toml ]] || fail "the retry doesn't copy the config again"
RUN_HOME=$hr RUN_VOICE_MODELS=$VM run
[[ $(grep -cx 'systemctl --user enable voxtype.service' "$hr/calls") == 2 ]] || fail "no enable after it worked"
# Dictation removed (voxtype gone) before an enable worked: nothing is retried
hd=$t/voice-removed; vhome "$hd"; rm -rf "$hd/.config/voxtype" "$hd/.local/share/voxtype"; touch "$hd/systemctl-fails"
RUN_HOME=$hd RUN_VOICE_MODELS=$VM run
rm -f "$hd/systemctl-fails"; rm -rf "$hd/.config/voxtype" "$hd/.local/share/voxtype"
RUN_HOME=$hd RUN_VOICE_MODELS=$VM RUN_VOXTYPE=$t/no-voxtype run
[[ $(grep -cx 'systemctl --user enable voxtype.service' "$hd/calls") == 1 ]] || fail "without voxtype the enable isn't retried"
[[ ! -e $hd/.local/share/voxtype && ! -e $hd/.config/voxtype ]] || fail "a user who removed Dictation gets nothing back"
# Without voxtype, or without the model package: nothing, and no marker
for case in novox nomodel; do
  hx=$t/voice-$case; vhome "$hx"; rm -rf "$hx/.config/voxtype" "$hx/.local/share/voxtype"
  if [[ $case == novox ]]; then RUN_HOME=$hx RUN_VOICE_MODELS=$VM RUN_VOXTYPE=$t/no-voxtype run; else RUN_HOME=$hx run; fi
  [[ ! -e $hx/.local/share/voxtype && ! -e $hx/.config/voxtype && ! -e $hx/.local/state/omarchy/done/omamobile-voxtype-setup ]] ||
    fail "$case: Voxtype is left alone"
  [[ ! -e $hx/.config/omarchy/defaults/dictation ]] || fail "$case: no dictation default is recorded"
  if grep -c 'enable voxtype' "$hx/calls" >/dev/null 2>&1; then fail "$case: voxtype.service isn't enabled"; fi
done
rm "$F/voxtype"
pass "voice out of the box: Omarchy's config and the shipped base.en once, the daemon enabled until it works, a removal kept"

# The keyboard: every layout the package carries linked (the terminal's, and
# each language's from squeekboard/generate), the theme written at every
# login, its gtk.css import and theme-set hook added once (H ran three times).
for layout in terminal/us.yaml terminal/us_wide.yaml terminal/gr.yaml terminal/gr_wide.yaml us.yaml us_wide.yaml de.yaml fr_wide.yaml url/us.yaml terminal/de.yaml; do
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

# Which keyboard: the start line runs omamobile-osk (the owner's choice), once, and squeekboard where
# omamobile-osk is gone (an older omamobile-shell installed over this one)
osk_line="o.launch_on_start(\"sh -c 'command -v omamobile-osk >/dev/null && exec omamobile-osk; exec squeekboard'\")"
[[ $(grep -cxF "$osk_line" "$H/.config/hypr/autostart.lua") == 1 ]] || fail "a new user's session starts the chosen keyboard, once"
if grep -c 'launch_on_start("squeekboard")' "$H/.config/hypr/autostart.lua" >/dev/null; then fail "a new user's start line names no keyboard"; fi
# What the line runs, with omamobile-osk there and gone (sh as Hyprland's exec gives it). Only
# the fakes and sh are on PATH: a machine with this package installed has /usr/bin/omamobile-osk,
# and with Tactus chosen there it would start the real keyboard and never return.
lt=$t/osk-line; mkdir -p "$lt/with" "$lt/without"
for d in with without; do
  printf '#!/bin/sh\necho squeekboard\n' >"$lt/$d/squeekboard"; chmod +x "$lt/$d/squeekboard"
  ln -s "$(command -v sh)" "$lt/$d/sh"
done
printf '#!/bin/sh\necho omamobile-osk\n' >"$lt/with/omamobile-osk"; chmod +x "$lt/with/omamobile-osk"
cmd=$(sed -E 's/^o\.launch_on_start\("(.*)"\)$/\1/' <<<"$osk_line")
[[ $(PATH="$lt/with" "$lt/with/sh" -c "$cmd") == omamobile-osk && $(PATH="$lt/without" "$lt/without/sh" -c "$cmd") == squeekboard ]] \
  || fail "the start line runs omamobile-osk, and squeekboard without it"
python3 -I - "$H/.config/omarchy/extensions/omarchy-menu.jsonc" <<'PY' || fail "Setup > Keyboard offers the keyboards"
import json, re, sys
text = open(sys.argv[1]).read()
text = re.sub(r"(?m)^\s*//.*$", "", text)
text = re.sub(r",(\s*[}\]])", r"\1", text)
menu = json.loads(text)
top = menu["setup.keyboard"]
assert top["label"] == "Keyboard" and top["icon"] == "\U000f030c" and top["when"] == "command -v tactus", top
assert "action" not in top, top
for name, label in (("squeekboard", "Standard"), ("tactus", "Tactus")):
    row = menu["setup.keyboard." + name]
    assert row["label"] == label and row["action"] == "omamobile-osk use " + name, row
    assert row["checked"] == "[[ $(omamobile-osk which) == %s ]]" % name, row
PY
[[ $(grep -c '"setup.keyboard"' "$H/.config/omarchy/extensions/omarchy-menu.jsonc") == 1 ]] || fail "Setup > Keyboard is added once"
# A user from before 0.2.134: the line this script wrote is changed once, a line of their own is not
ho2=$t/keyboard-old; mkdir -p "$ho2/.config/hypr" "$ho2/.config/omarchy/extensions" "$ho2/.local/state/omarchy/done"
cp "$H"/.config/hypr/{looknfeel,monitors}.lua "$ho2/.config/hypr/"
printf -- '-- autostart\n\n-- Omarchy Mobile: on-screen keyboard\no.launch_on_start("squeekboard")\no.launch_on_start("squeekboard --mine")\n' >"$ho2/.config/hypr/autostart.lua"
touch "$ho2/.local/state/omarchy/done/omamobile-osk"
RUN_HOME=$ho2 run
[[ $(grep -cxF "$osk_line" "$ho2/.config/hypr/autostart.lua") == 1 ]] || fail "the old start line now runs the chosen keyboard"
grep -cx 'o.launch_on_start("squeekboard --mine")' "$ho2/.config/hypr/autostart.lua" >/dev/null || fail "a start line of the user's own is kept"
printf 'o.launch_on_start("squeekboard")\n' >>"$ho2/.config/hypr/autostart.lua"
RUN_HOME=$ho2 run
grep -cx 'o.launch_on_start("squeekboard")' "$ho2/.config/hypr/autostart.lua" >/dev/null || fail "the start line is changed once: put back by the user, it stays"
# An autostart file that is a link (a dotfile setup): left a link, unchanged, with a line saying what to change
ho3=$t/keyboard-linked; mkdir -p "$ho3/.config/hypr" "$ho3/.config/omarchy/extensions" "$ho3/.local/state/omarchy/done" "$ho3/dotfiles"
cp "$H"/.config/hypr/{looknfeel,monitors}.lua "$ho3/.config/hypr/"
printf -- '-- autostart\n\n-- Omarchy Mobile: on-screen keyboard\no.launch_on_start("squeekboard")\n' >"$ho3/dotfiles/autostart.lua"
ln -s "$ho3/dotfiles/autostart.lua" "$ho3/.config/hypr/autostart.lua"
touch "$ho3/.local/state/omarchy/done/omamobile-osk"
before=$(sha256sum <"$ho3/dotfiles/autostart.lua")
RUN_HOME=$ho3 run
[[ -L $ho3/.config/hypr/autostart.lua && $(sha256sum <"$ho3/dotfiles/autostart.lua") == "$before" ]] || fail "a linked autostart file is left as it is"
grep -c 'autostart.lua is a link, left as it is' "$t/out" >/dev/null || fail "the setup says what a linked autostart file needs"
# One whose new copy can't be written (a folder in the way, so as root too): said, the setup goes
# on to its end, and the next login tries again
ho4=$t/keyboard-ro; mkdir -p "$ho4/.config/hypr/autostart.lua.new" "$ho4/.config/omarchy/extensions" "$ho4/.local/state/omarchy/done"
cp "$H"/.config/hypr/{looknfeel,monitors}.lua "$ho4/.config/hypr/"
printf -- '-- autostart\n\n-- Omarchy Mobile: on-screen keyboard\no.launch_on_start("squeekboard")\n' >"$ho4/.config/hypr/autostart.lua"
touch "$ho4/.local/state/omarchy/done/omamobile-osk"
RUN_HOME=$ho4 run
grep -c "could not change the keyboard's start line" "$t/out" >/dev/null || fail "an autostart file that can't be written is reported"
grep -cx 'o.launch_on_start("squeekboard")' "$ho4/.config/hypr/autostart.lua" >/dev/null || fail "nothing is half-written there"
[[ -f $ho4/.local/state/omarchy/done/omamobile-menu-keyboard ]] || fail "the setup goes on past it"
rmdir "$ho4/.config/hypr/autostart.lua.new"
RUN_HOME=$ho4 run
[[ $(grep -cxF "$osk_line" "$ho4/.config/hypr/autostart.lua") == 1 ]] || fail "the next login changes the line"
# A start line the owner changed (here: one that logs squeekboard's output): left alone, and the setup
# says once that the choice in Setup > Keyboard won't start at login with it. A file that starts no
# keyboard at all gets no such line.
ho5=$t/keyboard-own-line; mkdir -p "$ho5/.config/hypr" "$ho5/.config/omarchy/extensions" "$ho5/.local/state/omarchy/done"
cp "$H"/.config/hypr/{looknfeel,monitors}.lua "$ho5/.config/hypr/"
printf -- '-- autostart\no.launch_on_start([[sh -c '"'"'exec squeekboard >"$HOME/.cache/squeekboard.log" 2>&1'"'"']])\n' >"$ho5/.config/hypr/autostart.lua"
touch "$ho5/.local/state/omarchy/done/omamobile-osk"
before=$(sha256sum <"$ho5/.config/hypr/autostart.lua")
RUN_HOME=$ho5 run
[[ $(sha256sum <"$ho5/.config/hypr/autostart.lua") == "$before" ]] || fail "a start line the owner changed is left as it is"
grep -c 'starts squeekboard with a line of its own, left as it is' "$t/out" >/dev/null || fail "the setup says that the owner's own start line keeps squeekboard"
RUN_HOME=$ho5 run
if grep -c 'starts squeekboard with a line of its own' "$t/out" >/dev/null; then fail "that is said once, not at every login"; fi
ho6=$t/keyboard-none; mkdir -p "$ho6/.config/hypr" "$ho6/.config/omarchy/extensions" "$ho6/.local/state/omarchy/done"
cp "$H"/.config/hypr/{looknfeel,monitors}.lua "$ho6/.config/hypr/"
printf -- '-- autostart\n' >"$ho6/.config/hypr/autostart.lua"
touch "$ho6/.local/state/omarchy/done/omamobile-osk"
RUN_HOME=$ho6 run
if grep -c 'starts squeekboard with a line of its own' "$t/out" >/dev/null; then fail "a file that starts no keyboard gets no line about one"; fi
ho7=$t/keyboard-commented; mkdir -p "$ho7/.config/hypr" "$ho7/.config/omarchy/extensions" "$ho7/.local/state/omarchy/done"
cp "$H"/.config/hypr/{looknfeel,monitors}.lua "$ho7/.config/hypr/"
printf -- '-- autostart\n-- o.launch_on_start([[sh -c '"'"'exec squeekboard >/dev/null'"'"']])\n' >"$ho7/.config/hypr/autostart.lua"
touch "$ho7/.local/state/omarchy/done/omamobile-osk"
RUN_HOME=$ho7 run
if grep -c 'starts squeekboard with a line of its own' "$t/out" >/dev/null; then fail "a commented-out squeekboard line gets no line about it"; fi
pass "which keyboard: the session starts the owner's choice, an older start line is changed once (a linked file left as it is, an unwritable one tried again, the owner's own line left and named), Setup > Keyboard"

# A layout of the user's own stays theirs
hk=$t/keyboard-own; mkdir -p "$hk/.config/hypr" "$hk/.config/omarchy/extensions" "$hk/.local/share/squeekboard/keyboards"
cp "$H"/.config/hypr/{looknfeel,autostart,monitors}.lua "$hk/.config/hypr/"
printf '# mine\n' >"$hk/.local/share/squeekboard/keyboards/de.yaml"
RUN_HOME=$hk run
[[ ! -L $hk/.local/share/squeekboard/keyboards/de.yaml && $(cat "$hk/.local/share/squeekboard/keyboards/de.yaml") == "# mine" ]] \
  || fail "a layout the user wrote stays"
[[ -L $hk/.local/share/squeekboard/keyboards/fr.yaml ]] || fail "the others are linked beside it"
pass "the keyboard: a layout of the user's own stays"

# The Phone and Messages agent: enabled and started at every login where its
# user unit is installed (not once: a preset the session never applied left
# it disabled on a fresh install), nothing without the unit, and a login with
# no user manager (the enable fails) doesn't fail the setup
U=$t/user-units; mkdir -p "$U"; touch "$U/omatel-agent.service"
hm=$t/home-agent; mkdir -p "$hm/.config/hypr" "$hm/.config/omarchy/extensions"
cp "$H"/.config/hypr/{looknfeel,autostart,monitors}.lua "$hm/.config/hypr/"
RUN_HOME=$hm RUN_USER_UNITS=$U run
RUN_HOME=$hm RUN_USER_UNITS=$U run
[[ $(grep -cx 'systemctl --user enable --now omatel-agent.service' "$hm/calls") == 2 ]] || fail "omatel-agent.service is enabled and started at every login"
touch "$hm/systemctl-fails"
RUN_HOME=$hm RUN_USER_UNITS=$U run
grep -c 'could not enable omatel-agent.service' "$t/out" >/dev/null || fail "a failed enable is reported, not fatal"
rm "$hm/systemctl-fails"
if grep -c 'omatel-agent' "$H/calls" >/dev/null 2>&1; then fail "nothing is enabled without the agent's unit"; fi
pass "the Phone and Messages agent is enabled and started at each login where its unit is installed"

# Omarchy's auto-accepting bt-agent.service: the package's drop-in holds it
# off; a user manager that hasn't read the drop-in yet is reloaded, and a
# running agent stopped, at each login. The owner's opt-in file leaves it
# alone, and the unit's enabled state is never touched.
Ub=$t/user-units-bt; mkdir -p "$Ub"; touch "$Ub/bt-agent.service"
hb=$t/home-bt; mkdir -p "$hb/.config/hypr" "$hb/.config/omarchy/extensions"
cp "$H"/.config/hypr/{looknfeel,autostart,monitors}.lua "$hb/.config/hypr/"
touch "$hb/active-bt-agent.service"
RUN_HOME=$hb RUN_USER_UNITS=$Ub run
grep -cx 'systemctl --user daemon-reload' "$hb/calls" >/dev/null || fail "a user manager without the bt-agent drop-in is reloaded"
grep -cx 'systemctl --user stop bt-agent.service' "$hb/calls" >/dev/null || fail "a running bt-agent is stopped"
if grep -E 'systemctl --user (enable|disable|mask)[^|]*bt-agent' "$hb/calls" >/dev/null; then fail "bt-agent's enabled state is left alone"; fi
# Drop-in read and the agent stopped: nothing more at the next login.
rm "$hb/active-bt-agent.service" "$hb/calls"
echo /usr/lib/systemd/user/bt-agent.service.d/omamobile.conf >"$hb/drop-ins"
RUN_HOME=$hb RUN_USER_UNITS=$Ub run
if grep -E 'daemon-reload|stop bt-agent' "$hb/calls" >/dev/null; then fail "nothing more once the drop-in is read and the agent is off"; fi
# The owner's opt-in: no reload, no stop.
rm "$hb/calls" "$hb/drop-ins"; touch "$hb/active-bt-agent.service"; mkdir -p "$hb/.config/omamobile"; touch "$hb/.config/omamobile/bt-agent"
RUN_HOME=$hb RUN_USER_UNITS=$Ub run
if grep -E 'daemon-reload|stop bt-agent' "$hb/calls" >/dev/null; then fail "the owner's ~/.config/omamobile/bt-agent keeps bt-agent running"; fi
# No user manager (firstboot): not fatal.
rm -f "$hb/.config/omamobile/bt-agent"; touch "$hb/systemctl-fails"
RUN_HOME=$hb RUN_USER_UNITS=$Ub run || fail "setup-user survives a login without a user manager (bt-agent step)"
rm "$hb/systemctl-fails"
if grep -c 'bt-agent' "$H/calls" >/dev/null 2>&1; then fail "nothing about bt-agent without its unit"; fi
pass "Omarchy's bt-agent: reloaded and stopped where the drop-in isn't in effect yet, kept for the owner's opt-in"

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
for s in omamobile-shell-profile omamobile-monitor-scale omamobile-hide-cursor omamobile-osk omamobile-screensaver omamobile-files-single-tap; do
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

# The default keyring: Omarchy's own step runs, and a user's keyring is kept
hk=$t/keyring; mkdir -p "$hk/.config/hypr"; cp "$H"/.config/hypr/*.lua "$hk/.config/hypr/"
RUN_HOME=$hk run
[[ $(cat "$hk/.local/share/keyrings/default" 2>/dev/null) == Default_keyring ]] || fail "a new user gets Omarchy's default keyring"
echo mine >"$hk/.local/share/keyrings/default"
RUN_HOME=$hk run
[[ $(cat "$hk/.local/share/keyrings/default") == mine ]] || fail "a user's own default keyring is kept"
pass "the default keyring: Omarchy's step runs, and a user's own keyring is kept"

# Without Omarchy's step (a later Omarchy may move it), the setup still succeeds
he=$t/no-keyring-step; mkdir -p "$he/.config/hypr" "$t/empty-omarchy"; cp "$H"/.config/hypr/*.lua "$he/.config/hypr/"
RUN_HOME=$he RUN_OMARCHY_PATH=$t/empty-omarchy run
[[ ! -e $he/.local/share/keyrings/default ]] || fail "no keyring is made without Omarchy's step"
pass "without Omarchy's keyring step the setup still succeeds"

# Omarchy's remote-session service (a gliff remote desktop, probed at every
# screencast event): off on every phone, once, gliff installed or not
off() { python3 -I -c 'import json, sys; print(" ".join(json.load(open(sys.argv[1])).get("disabledPlugins", [])))' "$1/.config/omarchy/shell.json"; }
[[ $(off "$H") == omarchy.remote-session ]] || fail "a new user's disabledPlugins has omarchy.remote-session once, after several logins"
python3 -I -c 'import json, sys; p = sys.argv[1]; d = json.load(open(p)); d["disabledPlugins"] = []; json.dump(d, open(p, "w"))' "$H/.config/omarchy/shell.json"
run
[[ -z $(off "$H") ]] || fail "a user who takes the remote session out of disabledPlugins keeps it on"
for gliff in no yes; do
  hg=$t/remote-$gliff; mkdir -p "$hg/.config/hypr" "$hg/.config/omarchy/extensions" "$hg/.local/state/omarchy/done"
  cp "$H"/.config/hypr/*.lua "$hg/.config/hypr/"
  touch "$hg/.local/state/omarchy/done/omamobile-shell-profile"
  echo '{"version": 1, "plugins": [], "disabledPlugins": ["mine"]}' >"$hg/.config/omarchy/shell.json"
  rm -f "$F/gliff-server"; [[ $gliff == no ]] || fake gliff-server 'exit 0'
  RUN_HOME=$hg run; RUN_HOME=$hg run
  [[ $(off "$hg") == 'mine omarchy.remote-session' ]] || fail "an earlier user gets the remote session off once, and keeps their own entries (gliff-server: $gliff)"
done
rm -f "$F/gliff-server"
pass "Omarchy's remote session is off on every phone, once, with or without gliff, and a user can turn it back on"

# Auto-sleep: on once where the device package says suspend is verified;
# off by default elsewhere; a user who turns it off keeps it off.
ha=$t/auto-sleep; mkdir -p "$ha/.config/hypr" "$ha/.local/state/omarchy/done"
cp "$H"/.config/hypr/*.lua "$ha/.config/hypr/"
touch "$ha/.local/state/omarchy/done/omamobile-shell-profile"
RUN_HOME=$ha run
[[ ! -e $ha/.local/state/omarchy/toggles/omamobile-sleep ]] || fail "no device flag: auto-sleep stays off"
touch "$t/auto-sleep-default"
RUN_HOME=$ha RUN_AUTO_SLEEP=$t/auto-sleep-default run
[[ -e $ha/.local/state/omarchy/toggles/omamobile-sleep ]] || fail "the device flag turns auto-sleep on"
rm "$ha/.local/state/omarchy/toggles/omamobile-sleep"
RUN_HOME=$ha RUN_AUTO_SLEEP=$t/auto-sleep-default run
[[ ! -e $ha/.local/state/omarchy/toggles/omamobile-sleep ]] || fail "a user who turns auto-sleep off keeps it off"
pass "auto-sleep: on once where the device says suspend is verified, a user's off kept"

# Power profiles: a source with nothing saved gets Balanced at every login;
# an owner's saved choice stays. Then Omarchy's own
# omarchy-powerprofiles-set, when its package is at hand, run on AC with a
# daemon that offers all three (omamobile-omarchy's fake driver): with no
# state it picks Performance, after this step Balanced.
hp=$t/power; mkdir -p "$hp/.config/hypr" "$hp/.local/state/omarchy/done"
cp "$H"/.config/hypr/*.lua "$hp/.config/hypr/"
touch "$hp/.local/state/omarchy/done/omamobile-shell-profile"
RUN_HOME=$hp run
pps=$hp/.local/state/omarchy/powerprofiles
[[ $(cat "$pps/ac") == balanced && $(cat "$pps/battery") == balanced ]] || fail "no saved profile: both sources start on Balanced"
echo power-saver >"$pps/battery"
RUN_HOME=$hp run
[[ $(cat "$pps/battery") == power-saver ]] || fail "a profile picked later stays"
rm "$pps/ac"
RUN_HOME=$hp run
[[ $(cat "$pps/ac") == balanced ]] || fail "a source whose choice is gone gets Balanced again at the next login"
ho=$t/power-owner; mkdir -p "$ho/.config/hypr" "$ho/.local/state/omarchy/done" "$ho/.local/state/omarchy/powerprofiles"
cp "$H"/.config/hypr/*.lua "$ho/.config/hypr/"
touch "$ho/.local/state/omarchy/done/omamobile-shell-profile"
echo performance >"$ho/.local/state/omarchy/powerprofiles/ac"
RUN_HOME=$ho run
[[ $(cat "$ho/.local/state/omarchy/powerprofiles/ac") == performance ]] || fail "an owner's saved AC choice is kept"
[[ $(cat "$ho/.local/state/omarchy/powerprofiles/battery") == balanced ]] || fail "the source with nothing saved starts on Balanced"
pass "power profiles: a source with nothing saved gets Balanced at every login, an owner's choice kept"
opkg=${OMARCHY_PKG:-$(ls ~/.cache/omamobile-rootfs/pkg/omarchy-[0-9]*-aarch64.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | sort | tail -1 || true)}
if [[ -n $opkg ]] && command -v bsdtar >/dev/null &&
   bsdtar -xf "$opkg" -C "$t" usr/bin/omarchy-powerprofiles-set 2>/dev/null; then
  P=$t/pp-fakes; mkdir -p "$P"
  printf '#!/bin/bash\nprintf "power-saver\\nbalanced\\nperformance\\n"\n' >"$P/omarchy-powerprofiles-list"
  printf '#!/bin/bash\necho "b false"\n' >"$P/busctl" # on AC
  printf '#!/bin/bash\necho "$*" >>"$HOME/powerprofilesctl"\n' >"$P/powerprofilesctl"
  printf '#!/bin/bash\nexit 0\n' >"$P/omarchy-shell"
  chmod +x "$P"/*
  ppset() { env -i HOME="$1" PATH="$P:/usr/bin:/bin" bash "$t/usr/bin/omarchy-powerprofiles-set" autodetect; }
  hn=$t/power-none; mkdir -p "$hn"
  ppset "$hn"; [[ $(cat "$hn/powerprofilesctl") == "set performance" ]] || fail "Omarchy with no state picks Performance on AC: $(cat "$hn/powerprofilesctl")"
  hs=$t/power-step; mkdir -p "$hs/.config/hypr" "$hs/.local/state/omarchy/done"
  cp "$H"/.config/hypr/*.lua "$hs/.config/hypr/"
  touch "$hs/.local/state/omarchy/done/omamobile-shell-profile"
  RUN_HOME=$hs run
  ppset "$hs"; [[ $(cat "$hs/powerprofilesctl") == "set balanced" ]] || fail "after the step Omarchy starts on Balanced on AC: $(cat "$hs/powerprofilesctl")"
  pass "a session that starts on AC: Omarchy's own omarchy-powerprofiles-set picks Balanced after the step, Performance without it"
else
  pass "a session that starts on AC, against Omarchy's omarchy-powerprofiles-set # SKIP no omarchy package or bsdtar"
fi

# Browser setup is optional: a broken helper must not skip later login steps.
rm "$F/omamobile-browser-setup"
fake omamobile-browser-setup 'exit 1'
rm -f "$H/.local/state/omarchy/done/omamobile-menu-hide-unlock"
run
grep -q 'browser setup failed; continuing' "$t/out" || fail "browser helper failure is reported"
[[ -f $H/.local/state/omarchy/done/omamobile-menu-hide-unlock ]] || fail "user setup continues after browser helper failure"
pass "browser helper failure does not stop later user setup"
