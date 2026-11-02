#!/usr/bin/env bash
# Drive the real boot-time identity script against fake persist trees. No phone,
# no mounting, no root. Asserts it accepts a genuine address and refuses junk.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=$here/omamobile-dipper-identity
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fails=()

# Run the script with a persist tree holding the given raw wlan/bt bytes.
run_with() {  # run_with <wlan hex> <bt hex> <link path>
    local root=$tmp/p$RANDOM
    mkdir -p "$root/wlan_bt"
    python3 -c "import sys,pathlib; pathlib.Path(sys.argv[1]).write_bytes(bytes.fromhex(sys.argv[2]))" \
        "$root/wlan_bt/wlan.mac" "$1"
    python3 -c "import sys,pathlib; pathlib.Path(sys.argv[1]).write_bytes(bytes.fromhex(sys.argv[2]))" \
        "$root/wlan_bt/bt.mac" "$2"
    NOMOUNT=1 PERSIST="$root" MNT="$root" LINK="$3" sh "$script" 2>&1
}

# 1. a valid locally administered address must land in the link file, formatted
out=$(run_with 021042000001 021042000002 "$tmp/link1")
grep -q "MACAddress=02:10:42:00:00:01" "$tmp/link1" 2>/dev/null || fails+=("valid address not written to the link file")
grep -q "OriginalName=wlan0" "$tmp/link1" 2>/dev/null || fails+=("link file has no Match section")

# 2. junk must be refused, and no link file written
for name_hex in "000000000000:all-zero" "ffffffffffff:broadcast" "01005e000001:multicast"; do
    hex=${name_hex%%:*}; what=${name_hex##*:}
    out=$(run_with "$hex" "$hex" "$tmp/link-$what")
    grep -q "no usable WLAN address" <<<"$out" || fails+=("$what: not reported as unusable")
    [[ ! -f $tmp/link-$what ]] || fails+=("$what: wrote a link file anyway")
done

# 3. a short read must be refused too
out=$(run_with a45046 a45046 "$tmp/link-short")
grep -q "no usable WLAN address" <<<"$out" || fails+=("short read: not reported as unusable")
[[ ! -f $tmp/link-short ]] || fails+=("short read: wrote a link file anyway")

# 4. no persist at all: a quiet no-op, exit 0, nothing written
out=$(PERSIST=$tmp/none MNT=$tmp/m LINK=$tmp/link-none sh "$script" 2>&1) \
    || fails+=("exited non-zero with no persist")
grep -q "no persist partition" <<<"$out" || fails+=("missing persist not reported")
[[ ! -f $tmp/link-none ]] || fails+=("wrote a link file with no persist")

# 5. rewriting must be idempotent: the same input must not rewrite the file
run_with a45046ec5154 a45046ac5155 "$tmp/link1" >/dev/null
before=$(stat -c%Y "$tmp/link1"); sleep 1
out=$(run_with a45046ec5154 a45046ac5155 "$tmp/link1")
[[ $(stat -c%Y "$tmp/link1") == "$before" ]] || fails+=("rewrote an unchanged link file")
grep -q "wrote .*link1" <<<"$out" && fails+=("claimed a write when nothing changed")

if ((${#fails[@]})); then printf 'FAIL:\n'; printf '   %s\n' "${fails[@]}"; exit 1; fi
echo "test-identity OK: real script accepts a genuine MAC, refuses zero/broadcast/multicast/short, no-op without persist, idempotent"
