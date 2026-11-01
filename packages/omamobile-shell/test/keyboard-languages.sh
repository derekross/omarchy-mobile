#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-keyboard-languages against a fake gsettings: the list it gives
# the language sheet (squeekboard's names from xkeyboard-config, sorted, the
# current one first in `sources`), and that set moves a layout to the front
# as squeekboard's own popover does (src/popover.rs, set_layout), adds one
# that isn't there, and remove never takes the last one.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/fakes" "$t/keyboards"
cat >"$t/fakes/gsettings" <<'SH'
#!/bin/bash
[[ $2 == org.gnome.desktop.input-sources && $3 == sources ]] || exit 1
case $1 in
  get) cat "$T/sources" ;;
  set) printf '%s\n' "$4" >"$T/sources" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$t/fakes/gsettings"
cat >"$t/evdev.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<xkbConfigRegistry version="1.1">
  <layoutList>
    <layout><configItem><name>us</name><description>English (US)</description></configItem>
      <variantList><variant><configItem><name>colemak</name><description>English (Colemak)</description></configItem></variant></variantList>
    </layout>
    <layout><configItem><name>de</name><description>German</description></configItem></layout>
    <layout><configItem><name>fr</name><description>French</description></configItem></layout>
  </layoutList>
</xkbConfigRegistry>
XML
for f in us us_wide de de_wide fr fr_wide us+colemak us+colemak_wide; do : >"$t/keyboards/$f.yaml"; done
langs() { env T="$t" PATH="$t/fakes:$PATH" OMAMOBILE_XKB_RULES="$t/evdev.xml" OMAMOBILE_KEYBOARDS_DIR="$t/keyboards" \
  python3 -B bin/omamobile-keyboard-languages "$@"; }
sources() { cat "$t/sources"; }

echo "[('xkb', 'us'), ('xkb', 'de')]" >"$t/sources"
langs list | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["current"] == "us", d
assert d["configured"] == 2, d
assert [(r["name"], r["label"]) for r in d["sources"]] == [("us", "English (US)"), ("de", "German")], d
assert [(r["name"], r["label"]) for r in d["available"]] == [("us+colemak", "English (Colemak)"), ("fr", "French")], d
' || fail "list: squeekboard's names, sorted, the current one, the layouts to add"
pass "the list names each language as squeekboard does"

langs set de
[[ $(sources) == "[('xkb', 'de'), ('xkb', 'us')]" ]] || fail "set moves the layout to the front: $(sources)"
langs set fr
[[ $(sources) == "[('xkb', 'fr'), ('xkb', 'de'), ('xkb', 'us')]" ]] || fail "set adds a new layout at the front: $(sources)"
langs remove de
[[ $(sources) == "[('xkb', 'fr'), ('xkb', 'us')]" ]] || fail "remove keeps the order of the rest: $(sources)"
pass "set and remove change sources as squeekboard's popover does"

echo "[('xkb', 'fr')]" >"$t/sources"
langs remove fr 2>/dev/null && fail "remove refuses the last language"
[[ $(sources) == "[('xkb', 'fr')]" ]] || fail "the last language stays"
echo "@a(ss) []" >"$t/sources"
langs list | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["current"] == "us" and d["configured"] == 0 and [r["name"] for r in d["sources"]] == ["us"], d
' || fail "no sources: squeekboard's fallback, English (US)"
langs set de
[[ $(sources) == "[('xkb', 'de'), ('xkb', 'us')]" ]] || fail "adding to no sources keeps the fallback: $(sources)"
langs bogus 2>/dev/null && fail "an unknown command is refused"
pass "the last language stays, and no sources means English (US)"
