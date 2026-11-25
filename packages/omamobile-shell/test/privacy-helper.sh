#!/bin/bash
# SPDX-License-Identifier: MIT
# libexec/privacy (the root helper of omamobile-privacy@.service) in a scratch
# root, with rfkill and systemctl as stubs that record their arguments.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/root"
for c in rfkill systemctl; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/log"\n' "$c" "$tmp" > "$tmp/bin/$c"; chmod 755 "$tmp/bin/$c"
done
run() { PATH="$tmp/bin:$PATH" OMAMOBILE_PRIVACY_ROOT=$tmp/root bash libexec/privacy "$@"; }
die() { echo "FAIL: $1" >&2; exit 1; }
state=$tmp/root/var/lib/omamobile/privacy/nfc
run nfc-off >/dev/null
[[ $(cat "$state") == off ]] || die "nfc-off writes off"
[[ $(stat -c %a "$state") == 644 ]] || die "the state file is readable by the session (644)"
[[ $(cat "$tmp/log") == $'rfkill block nfc\nsystemctl stop neard.service' ]] || die "nfc-off: write, block, stop neard"
: > "$tmp/log"
# nfc-on removes the file before it unblocks (the stub checks the order)
printf '#!/bin/sh\n[ -e "%s" ] && echo "unblocked while off" >> "%s/log"\necho "rfkill $*" >> "%s/log"\n' "$state" "$tmp" "$tmp" > "$tmp/bin/rfkill"
run nfc-on >/dev/null
[[ ! -e $state ]] || die "nfc-on removes the file"
[[ $(cat "$tmp/log") == $'rfkill unblock nfc\nsystemctl try-restart omamobile-nfc-open.service' ]] || die "nfc-on: file gone, then unblock (got: $(cat "$tmp/log"))"
run nfc-on >/dev/null || die "nfc-on twice is fine"
for bad in '' nfc mic-off 'nfc-off;x' nfc-offx; do
  : > "$tmp/log"
  if run "$bad" >/dev/null 2>&1; then die "accepted: '$bad'"; fi
  [[ ! -s $tmp/log && ! -e $state ]] || die "a refused argument changed something: '$bad'"
done
echo ok
