#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-gnss.install's post_upgrade against a stand-in systemctl: what it
# enables follows the Location switch (the socket), and nothing else.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
cat > "$t/bin/systemctl" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
[[ $1 == is-enabled ]] && { [[ $SOCKET_ENABLED == 1 ]]; exit; }
exit 0
STUB
# vercmp answers -1, 0 or 1 like pacman's (the pkgrel is ignored here), so
# the "older than" branches really run
cat > "$t/bin/vercmp" <<'STUB'
#!/bin/bash
a=${1%-*} b=${2%-*}
[[ $a == "$b" ]] && { echo 0; exit; }
[[ $(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1) == "$a" ]] && echo -1 || echo 1
STUB
# Two logins: root's (never touched) and the owner's
printf '#!/bin/bash\n[[ $1 == list-users ]] && printf "   0 root no -\\n1000 owner no active\\n"\n' > "$t/bin/loginctl"
chmod +x "$t/bin/systemctl" "$t/bin/vercmp" "$t/bin/loginctl"
fail() { echo "not ok - $1"; exit 1; }
# run SOCKET_ENABLED [OLD_VERSION]: an upgrade to 0.2.11-1
run() { : > "$t/calls"; SOCKET_ENABLED=$1 OLD=${2:-0.2.8-1} CALLS=$t/calls PATH=$t/bin:$PATH bash -c '. ./omamobile-gnss.install; post_upgrade 0.2.11-1 "$OLD"' >/dev/null; }
line() { grep -nxF -- "$1" "$t/calls" | head -1 | cut -d: -f1; }

[[ $("$t/bin/vercmp" 0.2.10-1 0.2.11) == -1 && $("$t/bin/vercmp" 0.2.11-1 0.2.11) == 0 && $("$t/bin/vercmp" 0.2.12-1 0.2.11) == 1 ]] ||
  fail "the stand-in vercmp answers -1, 0 and 1"

run 1
grep -cxF -- '--global enable omamobile-geoclue-agent.service' "$t/calls" >/dev/null ||
  fail "Location on (socket enabled): the upgrade enables GeoClue's agent for every user"
grep -cxF -- '--user -M owner@.host restart omamobile-geoclue-agent.service' "$t/calls" >/dev/null ||
  fail "Location on, from before 0.2.11: the agent restarts in the owner's running session"
s=$(line 'stop geoclue.service') r=$(line '--user -M owner@.host restart omamobile-geoclue-agent.service')
[[ $s && $r && $s -lt $r ]] || fail "from before 0.2.11: geoclue stops before the agent restarts"
run 1 0.2.10-1
[[ $(line 'stop geoclue.service') ]] || fail "from 0.2.10 (the version on the repository): geoclue stops"
[[ $(line '--user -M owner@.host restart omamobile-geoclue-agent.service') ]] || fail "from 0.2.10: the agent restarts"
run 1 0.2.11-1
grep -c 'stop geoclue.service\|restart omamobile-geoclue-agent' "$t/calls" >/dev/null &&
  fail "from 0.2.11 on: geoclue is left running and the agent is not restarted"
grep -cxF -- '--user -M owner@.host start omamobile-geoclue-agent.service' "$t/calls" >/dev/null ||
  fail "from 0.2.11 on: the agent starts in the owner's running session, not only at the next login"
run 1
grep -c -- '-M root@' "$t/calls" >/dev/null && fail "the agent is never started for root"
grep -cxF 'enable --now omamobile-gnss-lto.timer' "$t/calls" >/dev/null || fail "Location on: the orbit timer follows too"
run 0
grep -c 'geoclue-agent\|lto.timer' "$t/calls" >/dev/null && fail "Location off (socket disabled): the upgrade enables nothing"
echo "ok - the upgrade hook turns GeoClue's agent on with the Location switch, starts it in the running session, and leaves a switched-off phone alone"
