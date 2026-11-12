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
[[ $* == "--user is-active omarchy-fcitx5.service" ]] && echo active
exit 0
SH
chmod +x "$t/bin/systemctl"
cat > "$t/bin/gsettings" <<'SH'
#!/bin/bash
[[ $1 == get ]] && cat "$IME_SOURCES"
[[ $1 == set ]] && printf '%s\n' "$4" > "$IME_SOURCES"
exit 0
SH
printf '#!/bin/bash\necho "remote $*" >> "$IME_LOG"\n' > "$t/bin/fcitx5-remote"
chmod +x "$t/bin/gsettings" "$t/bin/fcitx5-remote"
: > "$t/mozc.conf"
printf "[('xkb', 'us'), ('xkb', 'jp')]\n" > "$t/sources"
run() {
  HOME=$t/home XDG_CONFIG_HOME=$t/home/.config IME_LOG=$t/log IME_SOURCES=$t/sources OMAMOBILE_SYSTEMCTL=$t/bin/systemctl \
    OMAMOBILE_GSETTINGS=$t/bin/gsettings OMAMOBILE_FCITX5_REMOTE=$t/bin/fcitx5-remote \
    OMAMOBILE_MOZC_ADDON=${MOZC:-$t/mozc.conf} OMAMOBILE_IME_NO_OSK=1 bin/omamobile-ime "$@"
}
c=$t/home/.config

[[ $(run status | head -1) == "japanese input: off" ]] || fail "off by default"
MOZC=$t/none run on 2>/dev/null && fail "on refuses without fcitx5-mozc"
[[ ! -e $c/omamobile/fcitx5 ]] || fail "a refused on leaves the switch off"

run on >/dev/null
[[ -e $c/omamobile/fcitx5 ]] || fail "on sets the switch"
grep -qx 'DefaultIM=mozc' "$c/fcitx5/profile" && grep -qx '1=Japanese' "$c/fcitx5/profile" || fail "on writes English and Japanese (Mozc) groups"
grep -qx 'ActiveByDefault=False' "$c/fcitx5/config" || fail "Mozc starts off (the language turns it on)"
grep -qx -- '--user restart omarchy-fcitx5.service' "$t/log" || fail "on restarts fcitx5"
grep -qx -- '--user restart omamobile-ime.service' "$t/log" || fail "on starts the language follower"
[[ $(cat "$t/sources") == "[('xkb', 'us'), ('xkb', 'jp'), ('xkb', 'jp+romaji')]" ]] || fail "on adds Japanese (romaji) last"
[[ $(run status | head -1) == "japanese input: on" ]] || fail "status reads the switch"

# A profile or config of the user's own is never overwritten.
printf 'mine\n' > "$c/fcitx5/profile"; printf 'mine\n' > "$c/fcitx5/config"
run on >/dev/null
[[ $(grep -o "jp+romaji" "$t/sources" | wc -l) == 1 ]] || fail "on adds the language once"
[[ $(cat "$c/fcitx5/profile") == mine && $(cat "$c/fcitx5/config") == mine ]] || fail "the user's fcitx5 files are kept"

: > "$t/log"
run off >/dev/null
[[ ! -e $c/omamobile/fcitx5 ]] || fail "off clears the switch"
grep -qx -- '--user stop omamobile-ime.service omarchy-fcitx5.service' "$t/log" || fail "off stops the follower and fcitx5"
run bogus 2>/dev/null && fail "unknown commands refused"

# Mozc only while the keyboard's language (the first source) is Japanese
# (romaji); jp and jp+kana can't reach fcitx5 (too many keycodes).
for case in "us:-g English" "jp+romaji:-g Japanese" "jp:-g English" "jp+kana:-g English" "de:-g English"; do
  printf "[('xkb', '%s'), ('xkb', 'jp')]\n" "${case%%:*}" > "$t/sources"; : > "$t/log"
  run session
  [[ $(cat "$t/log") == "remote ${case#*:}" ]] || fail "the ${case%%:*} keyboard sends fcitx5-remote ${case#*:}"
done

u=systemd/user/omamobile-ime.service
grep -qx 'ConditionPathExists=%h/.config/omamobile/fcitx5' $u || fail "the login unit is inert while off"
grep -q '^After=.*omarchy-fcitx5.service' $u || fail "the login unit runs after fcitx5"
grep -qx 'ConditionPathExists=%h/.config/omamobile/fcitx5' systemd/user/omarchy-fcitx5-omamobile.conf ||
  fail "fcitx5 reads the same switch"
echo "ok - omamobile-ime: off by default, Mozc only with Japanese (romaji), the user's fcitx5 files kept, off stops it"
