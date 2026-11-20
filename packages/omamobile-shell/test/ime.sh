#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-ime against a scratch home and a fake systemctl.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail() { echo "not ok - ime: $*" >&2; exit 1; }
mkdir -p "$t/bin" "$t/home"
cat > "$t/bin/systemctl" <<'SH'
#!/bin/bash
echo "$*" >> "$IME_LOG"
echo "systemctl $*" >> "$IME_ORDER"
[[ $* == "--user is-active omarchy-fcitx5.service" ]] && echo active
exit 0
SH
chmod +x "$t/bin/systemctl"
cat > "$t/bin/gsettings" <<'SH'
#!/bin/bash
[[ $1 == get ]] && cat "$IME_SOURCES"
[[ $1 == set ]] && printf '%s\n' "$4" > "$IME_SOURCES"
[[ $1 == monitor && -n ${IME_MONITOR:-} ]] && echo "sources: changed"
exit 0
SH
printf '#!/bin/bash\necho "remote $*" >> "$IME_LOG"\n[[ -z ${IME_REMOTE_FAIL:-} ]]\n' > "$t/bin/fcitx5-remote"
printf '#!/bin/bash\necho restart >> "$IME_OSK"\necho osk-start >> "$IME_ORDER"\n' > "$t/bin/osk-restart"
printf '#!/bin/bash\necho osk-stop >> "$IME_ORDER"\n' > "$t/bin/osk-stop"
chmod +x "$t/bin/gsettings" "$t/bin/fcitx5-remote" "$t/bin/osk-restart" "$t/bin/osk-stop"
mkdir -p "$t/run"
: > "$t/mozc.conf"
printf "[('xkb', 'us'), ('xkb', 'jp')]\n" > "$t/sources"
run() {
  HOME=$t/home XDG_CONFIG_HOME=$t/home/.config XDG_DATA_HOME=$t/home/.local/share IME_LOG=$t/log IME_SOURCES=$t/sources OMAMOBILE_SYSTEMCTL=$t/bin/systemctl \
    OMAMOBILE_GSETTINGS=$t/bin/gsettings OMAMOBILE_FCITX5_REMOTE=$t/bin/fcitx5-remote \
    OMAMOBILE_MOZC_ADDON=${MOZC:-$t/mozc.conf} OMAMOBILE_IME_OSK_RESTART=$t/bin/osk-restart IME_OSK=$t/osk \
    OMAMOBILE_IME_OSK_STOP=$t/bin/osk-stop IME_ORDER=$t/order OMAMOBILE_IME_SETTLE=0 \
    XDG_RUNTIME_DIR=$t/run OMAMOBILE_IME_OSK_WAIT=0 OMAMOBILE_IME_REMOTE_WAIT=${REMOTE_WAIT:-0} bin/omamobile-ime "$@"
}
c=$t/home/.config
k=$t/home/.local/share/squeekboard/keyboards
S=/usr/share/omamobile/squeekboard/keyboards
mkdir -p "$k"; ln -s $S/us.yaml "$k/us.yaml"; printf 'mine\n' > "$k/us_wide.yaml"

[[ $(run status | head -1) == "japanese input: off" ]] || fail "off by default"
MOZC=$t/none run on 2>/dev/null && fail "on refuses without fcitx5-mozc"
[[ ! -e $c/omamobile/fcitx5 ]] || fail "a refused on leaves the switch off"

run on >/dev/null
[[ -e $c/omamobile/fcitx5 ]] || fail "on sets the switch"
# fcitx5 asks Hyprland for the input method once, at start: squeekboard must
# not hold it then, so it is stopped first and started after fcitx5.
[[ $(grep -v is-active "$t/order" | head -4 | tr '\n' ,) == "osk-stop,systemctl --user restart omarchy-fcitx5.service,osk-start,systemctl --user restart omamobile-ime.service," ]] ||
  fail "on starts fcitx5 with squeekboard stopped, then squeekboard: $(tr '\n' , < "$t/order")"
grep -qx 'DefaultIM=mozc' "$c/fcitx5/profile" && grep -qx '1=Japanese' "$c/fcitx5/profile" || fail "on writes English and Japanese (Mozc) groups"
grep -qx 'ActiveByDefault=False' "$c/fcitx5/config" || fail "Mozc starts off (the language turns it on)"
grep -qx -- '--user restart omarchy-fcitx5.service' "$t/log" || fail "on restarts fcitx5"
grep -qx -- '--user restart omamobile-ime.service' "$t/log" || fail "on starts the language follower"
[[ $(cat "$t/sources") == "[('xkb', 'us'), ('xkb', 'jp'), ('xkb', 'jp+romaji')]" ]] || fail "on adds Japanese (romaji) last"
[[ $(run status | head -1) == "japanese input: on" ]] || fail "status reads the switch"
[[ $(readlink "$k/us.yaml") == $S/terminal/us.yaml ]] || fail "on gives English the US terminal layout"
[[ ! -L $k/us_wide.yaml && $(cat "$k/us_wide.yaml") == mine ]] || fail "on keeps a layout of the user's own"

# A profile or config of the user's own is never overwritten.
printf 'mine\n' > "$c/fcitx5/profile"; printf 'mine\n' > "$c/fcitx5/config"
run on >/dev/null
[[ $(grep -o "jp+romaji" "$t/sources" | wc -l) == 1 ]] || fail "on adds the language once"
[[ $(cat "$c/fcitx5/profile") == mine && $(cat "$c/fcitx5/config") == mine ]] || fail "the user's fcitx5 files are kept"

: > "$t/log"
run off >/dev/null
[[ ! -e $c/omamobile/fcitx5 ]] || fail "off clears the switch"
grep -qx -- '--user stop omamobile-ime.service omarchy-fcitx5.service' "$t/log" || fail "off stops the follower and fcitx5"
[[ $(readlink "$k/us.yaml") == $S/us.yaml ]] || fail "off gives English its own layout back"
[[ $(cat "$k/us_wide.yaml") == mine ]] || fail "off keeps a layout of the user's own"
grep -q "jp+romaji" "$t/sources" && fail "off removes Japanese (romaji) from the keyboard's languages"
[[ $(cat "$t/sources") == "[('xkb', 'us'), ('xkb', 'jp')]" ]] || fail "off keeps the other languages"
# Removed from the front, the next language becomes current; alone, none is left.
for case in "[('xkb', 'jp+romaji'), ('xkb', 'de')]:[('xkb', 'de')]" "[('xkb', 'jp+romaji')]:@a(ss) []"; do
  printf '%s\n' "${case%%:*}" > "$t/sources"
  run off >/dev/null
  [[ $(cat "$t/sources") == "${case#*:}" ]] || fail "off turns ${case%%:*} into ${case#*:}, not $(cat "$t/sources")"
done
printf "[('xkb', 'us'), ('xkb', 'jp')]\n" > "$t/sources"
run bogus 2>/dev/null && fail "unknown commands refused"

# Mozc only while the keyboard's language (the first source) is Japanese
# (romaji); jp and jp+kana can't reach fcitx5 (too many keycodes).
for case in "us:-g English" "jp+romaji:-g Japanese" "jp:-g English" "jp+kana:-g English" "de:-g English"; do
  printf "[('xkb', '%s'), ('xkb', 'jp')]\n" "${case%%:*}" > "$t/sources"; : > "$t/log"
  run session
  [[ $(cat "$t/log") == "remote ${case#*:}" ]] || fail "the ${case%%:*} keyboard sends fcitx5-remote ${case#*:}"
done

# squeekboard is restarted once per login session, and again after "on".
: > "$t/osk"; rm -f "$t/run/omamobile-ime-osk-restarted"
run session; run session
[[ $(wc -l < "$t/osk") == 1 ]] || fail "session restarts squeekboard once per login session"
run on >/dev/null; run session
[[ $(wc -l < "$t/osk") == 2 ]] || fail "on restarts squeekboard itself, and the session doesn't again"

# fcitx5 not answering (a slow login, a restart) doesn't stop the follower:
# it retries, logs, and still applies the next change of language.
: > "$t/log"
REMOTE_WAIT=2 IME_REMOTE_FAIL=1 IME_MONITOR=1 run session 2>/dev/null || fail "a failing fcitx5-remote stops the follower"
[[ $(grep -c '^remote ' "$t/log") == 4 ]] || fail "the follower retries, then applies the next change ($(grep -c '^remote ' "$t/log") calls)"
REMOTE_WAIT=2 IME_REMOTE_FAIL=1 run session 2>&1 >/dev/null | grep -c "didn't take" >/dev/null || fail "a failed apply is logged"

# The Japanese (romaji) layouts are the US terminal ones under another name,
# in terminal/ and out of it (with the IME on, squeekboard never learns a
# field is a terminal, so Esc, Tab, Ctrl and the arrows must be on the plain
# layout): their bodies must stay the same as the US terminal files'.
for f in jp+romaji jp+romaji_wide terminal/jp+romaji terminal/jp+romaji_wide; do
  us=terminal/${f#terminal/}; us=${us/jp+romaji/us}
  cmp -s <(sed '1,/^---/d' "squeekboard/keyboards/$f.yaml") <(sed '1,/^---/d' "squeekboard/keyboards/$us.yaml") ||
    fail "squeekboard/keyboards/$f.yaml differs from $us.yaml: copy it again"
  grep -qx '# Language: Japanese (romaji)' "squeekboard/keyboards/$f.yaml" || fail "$f.yaml names its language"
done

u=systemd/user/omamobile-ime.service
grep -qx 'ConditionPathExists=%h/.config/omamobile/fcitx5' $u || fail "the login unit is inert while off"
grep -q '^After=.*omarchy-fcitx5.service' $u || fail "the login unit runs after fcitx5"
grep -qx 'ConditionPathExists=%h/.config/omamobile/fcitx5' systemd/user/omarchy-fcitx5-omamobile.conf ||
  fail "fcitx5 reads the same switch"
echo "ok - omamobile-ime: off by default, Mozc only with Japanese (romaji), the user's fcitx5 files kept, off stops it"
