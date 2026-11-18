#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-onboarding's name and email step against fakes: with Omarchy
# 4.5's omarchy-setup-git it hands both over in one call; without it (Omarchy
# 4.0) it sets git itself and runs Omarchy's Compose script; a blank value is
# not written; and "Saved." is printed only when it was.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; [[ -f ${t:-}/out ]] && cat "$t/out" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
F=$t/fakes; mkdir -p "$F" "$t/home" "$t/omarchy/install/user"
log=$t/calls
fake() { printf '#!/bin/bash\n%s\n' "$2" >"$F/$1"; chmod +x "$F/$1"; }
# git: reads answer nothing; writes are recorded, and fail when told to
fake git '[[ $* == "config --global user."* && $# == 3 ]] && exit 0
printf "git" >>"$LOG"; printf " [%s]" "$@" >>"$LOG"; echo >>"$LOG"; [[ ! -e $T/git-fails ]]'
fake unix_chkpwd 'exit 1'
# gum: the name, then the email, from $T/answers
fake gum 'case $1 in input) n=$(cat "$T/asked" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$T/asked"; sed -n "${n}p" "$T/answers" ;; confirm) exit 1 ;; esac'
fake omamobile-set-pin 'case $1 in --type) echo PIN ;; esac'
fake timeout 'shift; "$@"'
fake omamobile-mobile-network 'true'
fake the-setup-git 'printf "setup-git" >>"$LOG"; printf " [%s]" "$@" >>"$LOG"; echo >>"$LOG"; [[ ! -e $T/setup-fails ]]'
printf 'echo "xcompose [$OMARCHY_USER_NAME] [$OMARCHY_USER_EMAIL]" >>"$LOG"\n' >"$t/omarchy/install/user/xcompose.sh"
ob() {  # ob SETUP_COMMAND NAME EMAIL
  : >"$log"; rm -f "$t/asked"; printf '%s\n%s\n' "$2" "$3" >"$t/answers"
  env -u XDG_STATE_HOME T="$t" LOG="$log" HOME="$t/home" USER=alice OMARCHY_PATH="$t/omarchy" OMAMOBILE_FP_RUNNER="$t/none" \
    OMAMOBILE_SETUP_GIT="$1" PATH="$F:/usr/bin:/bin" bash bin/omamobile-onboarding --inner >"$t/out" 2>&1
}

ob the-setup-git "Ada Lovelace" ada@example.com
[[ $(cat "$log") == "setup-git [--name] [Ada Lovelace] [--email] [ada@example.com]" ]] || fail "Omarchy 4.5: one call to its git setup with both values ($(cat "$log"))"
grep -c '^Saved\.$' "$t/out" >/dev/null || fail "Omarchy 4.5: says Saved."

ob the-setup-git "" ada@example.com
[[ $(cat "$log") == "setup-git [--email] [ada@example.com]" ]] || fail "Omarchy 4.5: a blank name is not passed ($(cat "$log"))"
ob the-setup-git "" "  "
[[ ! -s $log ]] && ! grep -c '^Saved\.$' "$t/out" >/dev/null || fail "nothing typed: nothing saved, and no Saved."
touch "$t/setup-fails"; ob the-setup-git "Ada Lovelace" ada@example.com; rm "$t/setup-fails"
! grep -c '^Saved\.$' "$t/out" >/dev/null && grep -c 'could not be saved' "$t/out" >/dev/null || fail "Omarchy 4.5: a failed save is not called Saved."
pass "setup: the name and email go to Omarchy 4.5's git setup in one call; blank values are left out; a failure isn't 'Saved.'"

ob no-such-setup-command "Ada Lovelace" ada@example.com
[[ $(cat "$log") == "git [config] [--global] [user.name] [Ada Lovelace]
git [config] [--global] [user.email] [ada@example.com]
xcompose [Ada Lovelace] [ada@example.com]" ]] || fail "Omarchy 4.0: git's name and email, then the Compose script ($(cat "$log"))"
grep -c '^Saved\.$' "$t/out" >/dev/null || fail "Omarchy 4.0: says Saved."
ob no-such-setup-command "Ada Lovelace" ""
[[ $(cat "$log") == "git [config] [--global] [user.name] [Ada Lovelace]
xcompose [Ada Lovelace] []" ]] || fail "Omarchy 4.0: a blank email is not written to git ($(cat "$log"))"
touch "$t/git-fails"; ob no-such-setup-command "Ada Lovelace" ada@example.com; rm "$t/git-fails"
! grep -c '^Saved\.$' "$t/out" >/dev/null || fail "Omarchy 4.0: a failed git write is not called Saved."
pass "setup: without that command (Omarchy 4.0) git is set directly and Omarchy's Compose script runs"
