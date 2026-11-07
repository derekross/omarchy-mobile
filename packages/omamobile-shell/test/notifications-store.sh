#!/bin/bash
# SPDX-License-Identifier: MIT
# The notification shade's shell commands, taken out of QuickSettings.qml
# and run against both of Omarchy's layouts in a throwaway directory: the
# read (one file per notification under notifications/ and history/ on
# 4.0; live.json and history.json on 4.5, chosen by whether history.json
# exists) and Clear all (dismissAll then clear on 4.0; dismissAll, then
# forget for every notification read, on 4.5), with a fake qs that only
# records its calls. The rows come out through NotificationsModel.js.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
qs=plugins/omamobile.quicksettings/QuickSettings.qml
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# The script of `<id>.command = ["sh", "-c", "…" + "…",` as sh gets it: the
# QML string literals joined (they are JSON-compatible).
script() {
  python3 - "$qs" "$1" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
m = re.search(re.escape(sys.argv[2]) + r'\s*\[\s*"sh",\s*"-c",\s*((?:"(?:[^"\\]|\\.)*"\s*\+?\s*)+),', text)
if not m: sys.exit("no command for " + sys.argv[2])
print("".join(json.loads(s) for s in re.findall(r'"(?:[^"\\]|\\.)*"', m.group(1))), end="")
PY
}
read_sh=$(script 'command:') && [[ $read_sh == *history.json* ]] || fail "found the shade's read in $qs"
clear_sh=$(script 'clearProc.command =') || fail "found Clear all in $qs"

mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho "qs $*" >>"%s/calls"\n' "$tmp" >"$tmp/bin/qs"; chmod +x "$tmp/bin/qs"
rows() { node -e '
  const M = require(process.argv[1]); let raw = ""
  process.stdin.on("data", (d) => raw += d).on("end", () => {
    const v = M.shown(raw, {}, 0)
    console.log(v.entries.map((e) => e.summary).join(",") + " | " + v.files.join(","))
  })' "$PWD/plugins/omamobile.quicksettings/NotificationsModel.js"; }

# Omarchy 4.0.6: a toast on screen and two in history, one file each, as
# its serializePopup writes them (NotificationLogic.js).
d=$tmp/v40/notifications; mkdir -p "$d/history" "$d/images"
one() { printf '{"id":%s,"originalId":%s,"app":"App","appIcon":"","summary":"%s","body":"","image":"","glyph":"","execArgv":"","urgency":1,"expireTimeout":0,"timestamp":%s}\n' "$2" "$2" "$3" "$1"; }
one 3000 3 live >"$d/3000-3.json"
one 2000 2 newer >"$d/history/2000-2.json"
one 1000 1 older >"$d/history/1000-1.json"
got=$(sh -c "$read_sh" sh "$d" | rows)
[[ $got == "live,newer,older | 3000-3.json,2000-2.json,1000-1.json" ]] || fail "4.0: the shade reads the toasts and history/ ($got)"
: >"$tmp/calls"
PATH=$tmp/bin:$PATH sh -c "$clear_sh" sh /shell "$d" 3000-3.json 2000-2.json 1000-1.json
[[ $(cat "$tmp/calls") == $'qs ipc -p /shell call notifications dismissAll\nqs ipc -p /shell call notifications clear' ]] \
  || fail "4.0: Clear all is dismissAll, then clear, and nothing else ($(cat "$tmp/calls"))"
pass "notification shade on Omarchy 4.0: reads one file each, clears through dismissAll and clear"

# Omarchy 4.5.0: live.json and history.json, one JSON array each (Store.js),
# next to 4.0 leftovers its migration had not removed yet, which must not
# show; then the files as its service first creates them, empty.
d=$tmp/v45/notifications; mkdir -p "$d/history"
row() { printf '{"key":"%s","originalId":1,"senderPid":0,"execArgv":"","execActions":"","glyph":"","app":"App","appIcon":"","summary":"%s","body":"","rawBody":"","source":"App","groupKey":"app:app","urgency":1,"expireTimeout":0,"duration":0,"ts":%s%s}' "$@"; }
printf '[%s]\n' "$(row nlive live 3.5 '')" >"$d/live.json"
printf '[%s,%s]\n' "$(row nnew newer 2 ',"closed_ts":9,"closed_reason":"dismissed"')" "$(row nold older 1 ',"closed_ts":8,"closed_reason":"expired"')" >"$d/history.json"
one 5000 5 leftover >"$d/history/5000-5.json"
one 6000 6 stray >"$d/6000-6.json"
got=$(sh -c "$read_sh" sh "$d" | rows)
[[ $got == "live,newer,older | nlive,nnew,nold" ]] || fail "4.5: the shade reads live.json and history.json only ($got)"
: >"$tmp/calls"
PATH=$tmp/bin:$PATH sh -c "$clear_sh" sh /shell "$d" nlive nnew nold
[[ $(cat "$tmp/calls") == $'qs ipc -p /shell call notifications dismissAll\nqs ipc -p /shell call notifications forget nlive\nqs ipc -p /shell call notifications forget nnew\nqs ipc -p /shell call notifications forget nold' ]] \
  || fail "4.5: Clear all is dismissAll, then forget for each key ($(cat "$tmp/calls"))"
rm -rf "$d/history" "$d/6000-6.json"; : >"$d/live.json"; : >"$d/history.json"
got=$(sh -c "$read_sh" sh "$d" | rows)
[[ $got == " | " ]] || fail "4.5: empty files, no rows ($got)"
: >"$tmp/calls"
PATH=$tmp/bin:$PATH sh -c "$clear_sh" sh /shell "$d"
[[ $(cat "$tmp/calls") == "qs ipc -p /shell call notifications dismissAll" ]] || fail "4.5: Clear all with nothing read is dismissAll alone"
pass "notification shade on Omarchy 4.5: reads live.json and history.json, clears through dismissAll and forget"
