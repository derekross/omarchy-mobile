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
printf '#!/bin/bash\n[[ $1 == "$2" ]] && echo 0 || echo 1\n' > "$t/bin/vercmp"
# Two logins: root's (never touched) and the owner's
printf '#!/bin/bash\n[[ $1 == list-users ]] && printf "   0 root no -\\n1000 owner no active\\n"\n' > "$t/bin/loginctl"
chmod +x "$t/bin/systemctl" "$t/bin/vercmp" "$t/bin/loginctl"
fail() { echo "not ok - $1"; exit 1; }
run() { : > "$t/calls"; SOCKET_ENABLED=$1 CALLS=$t/calls PATH=$t/bin:$PATH bash -c '. ./omamobile-gnss.install; post_upgrade 0.2.9-1 0.2.8-1' >/dev/null; }

run 1
grep -cxF -- '--global enable omamobile-geoclue-agent.service' "$t/calls" >/dev/null ||
  fail "Location on (socket enabled): the upgrade enables GeoClue's agent for every user"
grep -cxF -- '--user -M owner@.host start omamobile-geoclue-agent.service' "$t/calls" >/dev/null ||
  fail "Location on: the agent starts in the owner's running session, not only at the next login"
grep -c -- '-M root@' "$t/calls" >/dev/null && fail "the agent is never started for root"
grep -cxF 'enable --now omamobile-gnss-lto.timer' "$t/calls" >/dev/null || fail "Location on: the orbit timer follows too"
run 0
grep -c 'geoclue-agent\|lto.timer' "$t/calls" >/dev/null && fail "Location off (socket disabled): the upgrade enables nothing"
echo "ok - the upgrade hook turns GeoClue's agent on with the Location switch, starts it in the running session, and leaves a switched-off phone alone"
