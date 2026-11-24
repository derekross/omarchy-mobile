#!/bin/bash
# SPDX-License-Identifier: MIT
# bin/omamobile-reboot, what the shell's Restart buttons run: Omarchy's own
# restart under the name the installed Omarchy has (4.5's "omarchy-system
# reboot", 4.0's omarchy-system-reboot), and systemd's when neither exists.
# PATH holds only stand-ins that record what was called, so nothing here can
# restart the machine the test runs on.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
log=$t/calls
bash=$(command -v bash)
fail() { echo "not ok - omamobile-reboot: $1" >&2; exit 1; }
stub() {  # stub DIR NAME
  mkdir -p "$1"
  printf '#!%s\nprintf "%%s" "%s" >>"%s"; (( $# )) && printf " [%%s]" "$@" >>"%s"; echo >>"%s"\n' "$bash" "$2" "$log" "$log" "$log" > "$1/$2"
  chmod +x "$1/$2"
}
run() {  # run DIR [args]: only DIR on PATH
  local dir=$1; shift
  : > "$log"
  env -i PATH="$dir" "$bash" "$here/bin/omamobile-reboot" "$@"
}

stub "$t/both" omarchy-system; stub "$t/both" omarchy-system-reboot; stub "$t/both" systemctl
run "$t/both"
[[ $(cat "$log") == "omarchy-system [reboot]" ]] || fail "with Omarchy 4.5's command it runs 'omarchy-system reboot' ($(cat "$log"))"

stub "$t/old" omarchy-system-reboot; stub "$t/old" systemctl
run "$t/old"
[[ $(cat "$log") == "omarchy-system-reboot" ]] || fail "with only Omarchy 4.0's command it runs that ($(cat "$log"))"

stub "$t/none" systemctl
run "$t/none"
[[ $(cat "$log") == "systemctl [reboot] [--no-wall]" ]] || fail "with neither it asks systemd ($(cat "$log"))"

rc=0; run "$t/both" --now 2>/dev/null || rc=$?
[[ $rc == 2 && ! -s $log ]] || fail "an unknown option runs nothing (exit $rc)"
ln -s "$(command -v sed)" "$t/both/sed"
run "$t/both" --help | grep -c 'restart the phone the way Omarchy does' >/dev/null || fail "--help prints the header"
[[ ! -s $log ]] || fail "--help runs nothing"
echo "ok - omamobile-reboot: Omarchy 4.5's command, then 4.0's, then systemd; an unknown option and --help run nothing"
