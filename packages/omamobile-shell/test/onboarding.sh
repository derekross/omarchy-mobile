#!/bin/bash
# SPDX-License-Identifier: MIT
# Tests for omamobile-onboarding and omamobile-set-pin's function-level
# entry points, the ones the setup sheet (omamobile.onboarding) calls, against
# fakes: a passwd that prompts as the real one does, a unix_chkpwd, an
# omarchy-shell, Omarchy's git.sh and xcompose.sh stand-ins. Each entry point
# must do what the terminal prompts did, and no secret may reach argv, the
# environment or the output. PATH holds only the fakes and a few basic
# tools, so nothing real can change a password here.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fake=$tmp/bin; basic=$tmp/basic; log=$tmp/log; home=$tmp/home; omarchy=$tmp/omarchy
mkdir -p "$fake" "$basic" "$home" "$omarchy/install/user/first-run" "$tmp/state"
for tool in bash sh cat head mkdir mv rm touch printf python3 grep; do
  ln -s "$(command -v "$tool")" "$basic/$tool"
done
command -v git >/dev/null && ln -s "$(command -v git)" "$basic/git"
: >"$log"

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$fake/$1"; chmod +x "$fake/$1"; }
run() { env -i HOME="$home" USER=owner OMARCHY_PATH="$omarchy" PATH="$fake:$basic" "$@"; }

# Omarchy's steps, as its installer ships them (the real ones set git's
# identity and write ~/.XCompose from OMARCHY_USER_NAME/EMAIL).
cat >"$omarchy/install/user/git.sh" <<'SH'
if [[ -n ${OMARCHY_USER_NAME//[[:space:]]/} ]]; then git config --global user.name "$OMARCHY_USER_NAME"; fi
if [[ -n ${OMARCHY_USER_EMAIL//[[:space:]]/} ]]; then git config --global user.email "$OMARCHY_USER_EMAIL"; fi
SH
cat >"$omarchy/install/user/xcompose.sh" <<'SH'
printf '<Multi_key> <space> <n> : "%s"\n<Multi_key> <space> <e> : "%s"\n' "$OMARCHY_USER_NAME" "$OMARCHY_USER_EMAIL" >~/.XCompose
SH
printf '#!/bin/bash\necho invited >>%s\n' "$log" >"$omarchy/install/user/first-run/setup-agent.hook"
stub omarchy-default-agent 'cat '"$tmp"'/state/agent 2>/dev/null; exit 0'
# omamobile-onboarding asks omamobile-set-pin (the one under test) for the PIN's state.
stub omamobile-set-pin 'exec bash '"$PWD"'/bin/omamobile-set-pin "$@"'
stub omarchy-notification-send 'echo "notify $*" >>'"$log"
# unix_chkpwd: the account has no password while $tmp/state/nopin exists
# (an empty one is accepted, nullok).
stub unix_chkpwd '[ -e '"$tmp"'/state/nopin ] && exit 0; exit 1'
# passwd, as pam_unix prompts: the current one only when there is one; the
# new one twice; a new one under four characters is refused.
stub passwd '
exec </dev/tty 2>/dev/null || true
current=$(cat '"$tmp"'/state/secret 2>/dev/null || true)
if [ -n "$current" ]; then
  printf "Current password: "; IFS= read -r given; echo
  [ "$given" = "$current" ] || { echo "passwd: Authentication token manipulation error"; echo "passwd: password unchanged"; exit 10; }
fi
printf "New password: "; IFS= read -r new; echo
printf "Retype new password: "; IFS= read -r again; echo
[ "$new" = "$again" ] || { echo "Sorry, passwords do not match."; echo "passwd: Authentication token manipulation error"; exit 10; }
[ ${#new} -ge 4 ] || { echo "BAD PASSWORD: it is too short"; echo "passwd: Authentication token manipulation error"; exit 10; }
printf "%s" "$new" >'"$tmp"'/state/secret
echo "passwd: password updated successfully"
'

bash -n bin/omamobile-onboarding || fail "omamobile-onboarding parses"
bash -n bin/omamobile-set-pin || fail "omamobile-set-pin parses"
# The passwd driver is Python inside the script: it has to parse too.
sed -n "/^read -r -d '' PASSWD_DRIVER <<'PY'/,/^PY$/p" bin/omamobile-set-pin | sed '1d;$d' >"$tmp/driver.py"
[[ -s $tmp/driver.py ]] || fail "the passwd driver is found in omamobile-set-pin"
python3 -B -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$tmp/driver.py" || fail "the passwd driver parses"
pass "the scripts and the passwd driver parse"

# ---- status before anything is set
touch "$tmp/state/nopin"
status=$(run bash bin/omamobile-onboarding --status --json)
python3 -c '
import json, sys
s = json.loads(sys.argv[1])
assert s == {"name": "", "email": "", "identity": False, "pin": {"set": False, "type": "pin"}, "agent": ""}, s
' "$status" || fail "a fresh phone's status is empty (got: $status)"
[[ $(run bash bin/omamobile-set-pin --status) == '{"set": false, "type": "pin"}' ]] || fail "set-pin --status on a fresh phone"
pass "status: nothing set"

# ---- identity, as the prompts save it
if command -v git >/dev/null; then
  run bash bin/omamobile-onboarding --identity "Ada Lovelace" "ada@example.com" || fail "--identity runs"
  [[ $(run git config --global user.name) == "Ada Lovelace" ]] || fail "--identity sets git's name"
  [[ $(run git config --global user.email) == "ada@example.com" ]] || fail "--identity sets git's email"
  grep -cF '<Multi_key> <space> <n> : "Ada Lovelace"' "$home/.XCompose" >/dev/null || fail "--identity writes the XCompose shortcuts"
  run bash bin/omamobile-onboarding --identity "" "" || fail "--identity with nothing runs"
  [[ $(run git config --global user.name) == "Ada Lovelace" ]] || fail "--identity with nothing changes nothing"
  status=$(run bash bin/omamobile-onboarding --status --json)
  python3 -c '
import json, sys
s = json.loads(sys.argv[1])
assert s["name"] == "Ada Lovelace" and s["email"] == "ada@example.com" and s["identity"] is True, s
' "$status" || fail "status reads the identity back (got: $status)"
  pass "identity: git and XCompose, through Omarchy's own steps"
else
  pass "identity # SKIP no git"
fi

# ---- the first PIN: no current one, passwd asks for the new one twice
printf '\n1234\n' | run bash bin/omamobile-set-pin --apply pin >"$tmp/out" 2>&1 || fail "--apply pin sets the first PIN (exit $?: $(cat "$tmp/out"))"
[[ $(cat "$tmp/state/secret") == 1234 ]] || fail "passwd got the new PIN"
[[ $(cat "$home/.config/omamobile/credential") == pin ]] || fail "the choice is recorded as pin"
[[ -e $home/.local/state/omarchy/toggles/lock-keypad && -e $home/.local/state/omarchy/toggles/lock-on-start ]] || fail "the keypad and lock-on-start toggles are set"
[[ ! -e $home/.local/state/omarchy/toggles/credential-password ]] || fail "a PIN clears the password toggle"
if grep -c 1234 "$tmp/out" >/dev/null; then fail "the PIN never appears in the output"; fi
rm -f "$tmp/state/nopin"
[[ $(run bash bin/omamobile-set-pin --status) == '{"set": true, "type": "pin"}' ]] || fail "set-pin --status after the first PIN"
pass "the first PIN: passwd driven on a pty, the choice and the toggles recorded"

# ---- a change: the current one first; wrong, refused, then right
rc=0; printf '9999\n5678\n' | run bash bin/omamobile-set-pin --apply pin >"$tmp/out" 2>&1 || rc=$?
[[ $rc == 3 ]] || fail "a wrong current PIN exits 3 (exit $rc: $(cat "$tmp/out"))"
[[ $(cat "$tmp/state/secret") == 1234 ]] || fail "a wrong current PIN changes nothing"
rc=0; printf '1234\n12\n' | run bash bin/omamobile-set-pin --apply pin >"$tmp/out" 2>&1 || rc=$?
[[ $rc == 5 ]] || fail "a refused new PIN exits 5 (exit $rc: $(cat "$tmp/out"))"
grep -cx 'it is too short' "$tmp/out" >/dev/null || fail "the refusal's reason is printed (got: $(cat "$tmp/out"))"
printf '1234\nsecret-phrase\n' | run bash bin/omamobile-set-pin --apply password >"$tmp/out" 2>&1 || fail "--apply password changes it (exit $?: $(cat "$tmp/out"))"
[[ $(cat "$tmp/state/secret") == secret-phrase ]] || fail "passwd got the new password"
[[ $(cat "$home/.config/omamobile/credential") == password && -e $home/.local/state/omarchy/toggles/credential-password ]] || fail "the choice is recorded as password, with Omarchy's toggle"
[[ $(run bash bin/omamobile-set-pin --type) == password ]] || fail "--type reads password"
if grep -c 'secret-phrase' "$tmp/out" >/dev/null; then fail "the password never appears in the output"; fi
rc=0; printf '\n\n' | run bash bin/omamobile-set-pin --apply pin >/dev/null 2>&1 || rc=$?
[[ $rc == 1 ]] || fail "no new PIN at all exits 1 (exit $rc)"
rc=0; run bash bin/omamobile-set-pin --apply maybe </dev/null >/dev/null 2>&1 || rc=$?
[[ $rc == 2 ]] || fail "only pin and password are accepted (exit $rc)"
pass "a change: the current one checked, a refusal explained, the new type recorded"

# ---- the nudge, with everything set: Omarchy's agent invitation once
run bash bin/omamobile-onboarding --nudge || fail "--nudge runs"
grep -cx invited "$log" >/dev/null || fail "--nudge with everything set invites the agent"
if grep -c 'notify' "$log" >/dev/null; then fail "--nudge with everything set sends no nudge"; fi
run bash bin/omamobile-onboarding --invite-agent || fail "--invite-agent runs"
[[ $(grep -cx invited "$log") == 2 ]] || fail "--invite-agent runs Omarchy's hook"
pass "the nudge and the agent invitation"

# ---- opening: the sheet when the shell has it, else the terminal
stub omarchy-shell 'echo "shell $*" >>'"$log"'; cat '"$tmp"'/state/summon'
stub omarchy-launch-floating-terminal-with-presentation 'echo "terminal $*" >>'"$log"
echo ok >"$tmp/state/summon"
run bash bin/omamobile-set-pin || fail "omamobile-set-pin opens"
grep -cxF 'shell shell summon omamobile.onboarding {"page":"pin"}' "$log" >/dev/null || fail "omamobile-set-pin summons the sheet's PIN flow"
run bash bin/omamobile-onboarding || fail "omamobile-onboarding opens"
grep -cxF 'shell shell summon omamobile.onboarding {}' "$log" >/dev/null || fail "omamobile-onboarding summons the sheet"
if grep -c '^terminal' "$log" >/dev/null; then fail "no terminal while the shell has the sheet"; fi
echo unknown >"$tmp/state/summon"
run bash bin/omamobile-onboarding || fail "omamobile-onboarding falls back"
grep -cxF 'terminal omamobile-onboarding --inner' "$log" >/dev/null || fail "a shell without the plugin gets the terminal prompts"
echo ok >"$tmp/state/summon"
run OMAMOBILE_PROMPTS=terminal bash bin/omamobile-set-pin || fail "OMAMOBILE_PROMPTS=terminal runs"
grep -cxF 'terminal omamobile-set-pin --inner' "$log" >/dev/null || fail "OMAMOBILE_PROMPTS=terminal skips the sheet"
pass "opening: the sheet when the shell runs it, the terminal prompts otherwise"
