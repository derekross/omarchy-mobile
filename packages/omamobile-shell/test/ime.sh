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
: > "$t/mozc.conf"
run() {
  HOME=$t/home XDG_CONFIG_HOME=$t/home/.config IME_LOG=$t/log OMAMOBILE_SYSTEMCTL=$t/bin/systemctl \
    OMAMOBILE_MOZC_ADDON=${MOZC:-$t/mozc.conf} OMAMOBILE_IME_NO_OSK=1 bin/omamobile-ime "$@"
}
c=$t/home/.config

[[ $(run status | head -1) == "japanese input: off" ]] || fail "off by default"
MOZC=$t/none run on 2>/dev/null && fail "on refuses without fcitx5-mozc"
[[ ! -e $c/omamobile/fcitx5 ]] || fail "a refused on leaves the switch off"

run on >/dev/null
[[ -e $c/omamobile/fcitx5 ]] || fail "on sets the switch"
grep -qx 'DefaultIM=mozc' "$c/fcitx5/profile" || fail "on writes a Mozc profile"
grep -qx 'ActiveByDefault=True' "$c/fcitx5/config" || fail "Mozc is active from the start"
grep -qx -- '--user restart omarchy-fcitx5.service' "$t/log" || fail "on restarts fcitx5"
[[ $(run status | head -1) == "japanese input: on" ]] || fail "status reads the switch"

# A profile or config of the user's own is never overwritten.
printf 'mine\n' > "$c/fcitx5/profile"; printf 'mine\n' > "$c/fcitx5/config"
run on >/dev/null
[[ $(cat "$c/fcitx5/profile") == mine && $(cat "$c/fcitx5/config") == mine ]] || fail "the user's fcitx5 files are kept"

: > "$t/log"
run off >/dev/null
[[ ! -e $c/omamobile/fcitx5 ]] || fail "off clears the switch"
grep -qx -- '--user stop omarchy-fcitx5.service' "$t/log" || fail "off stops fcitx5"
run bogus 2>/dev/null && fail "unknown commands refused"

u=systemd/user/omamobile-ime.service
grep -qx 'ConditionPathExists=%h/.config/omamobile/fcitx5' $u || fail "the login unit is inert while off"
grep -q '^After=.*omarchy-fcitx5.service' $u || fail "the login unit runs after fcitx5"
grep -qx 'ConditionPathExists=%h/.config/omamobile/fcitx5' systemd/user/omarchy-fcitx5-omamobile.conf ||
  fail "fcitx5 reads the same switch"
echo "ok - omamobile-ime: off by default, on writes Mozc's profile once and starts fcitx5, off stops it"
