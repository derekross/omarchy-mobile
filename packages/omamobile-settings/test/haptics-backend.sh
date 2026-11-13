#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/haptics.sh against a temporary feedbackd theme (XDG_CONFIG_HOME), in a copy of the script with dry=1,
# so feedbackd, gsettings and fbcli are never called.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/config/feedbackd/themes"
dir=$tmp/config/feedbackd/themes
export XDG_CONFIG_HOME=$tmp/config
sed 's/^dry=0/dry=1/' "$src/backends/haptics.sh" > "$tmp/haptics.sh"
grep -q '^dry=1' "$tmp/haptics.sh"
cat > "$dir/custom.json" <<'EOT'
{"name":"custom","profiles":[{"name":"full","feedbacks":[
 {"event-name":"button-pressed","type":"VibraPattern","magnitudes":[0.015],"durations":[15]},
 {"event-name":"key-pressed","type":"VibraPattern","magnitudes":[0.015],"durations":[15]},
 {"event-name":"message-new-instant","type":"Sound","effect":"message-new-instant"}]}]}
EOT
run() { bash "$tmp/haptics.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }

eq "$(run get)" '{"level":"low"}'
eq "$(run set level medium)" '{"level":"medium"}'
eq "$(run get)" '{"level":"medium"}'
eq "$(run set level high)" '{"level":"high"}'
# "off" is not a level here: it would be the phone-wide silent profile, which this page never touches
eq "$(run set level off)" '{"error":"bad value"}'
eq "$(run get)" '{"level":"high"}'
eq "$(run set level low)" '{"level":"low"}'
eq "$(run get)" '{"level":"low"}'
eq "$(run set level loud)" '{"error":"bad value"}'
eq "$(run set level 0.5)" '{"error":"bad value"}'
eq "$(run set strength low)" '{"error":"unknown key"}'
eq "$(run nonsense)" '{"error":"usage: probe|get|set"}'
# nothing above the cap is ever in the theme, and the sound entry is left alone
python3 - "$dir/custom.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
fb = d["profiles"][0]["feedbacks"]
assert all(f["magnitudes"][0] <= 0.125 and f["durations"][0] <= 60 for f in fb if f["type"] == "VibraPattern")
assert any(f["type"] == "Sound" for f in fb)
PY
# the mode of the file is kept, and the first theme is saved once
[[ $(stat -c %a "$dir/custom.json") == 644 ]] || { chmod 644 "$dir/custom.json"; run set level high >/dev/null; [[ $(stat -c %a "$dir/custom.json") == 644 ]]; }
[[ -e $dir/custom.json.bak-haptics ]]
# a theme with one key entry is refused before anything is touched, and the profile stays as it was
cp "$dir/custom.json" "$tmp/good.json"
python3 - "$dir/custom.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["profiles"][0]["feedbacks"] = [f for f in d["profiles"][0]["feedbacks"] if f["event-name"] != "key-pressed"]
json.dump(d, open(sys.argv[1], "w"))
PY
before=$(sha256sum "$dir/custom.json")
eq "$(run set level medium)" '{"error":"the haptics theme does not have the two key entries"}'
[[ $(sha256sum "$dir/custom.json") == "$before" ]]
cp "$tmp/good.json" "$dir/custom.json"
# a theme that is not there: a plain message, no crash, and no level can be set (the profile is never touched)
rm "$dir/custom.json"
eq "$(run get)" '{"error":"no keyboard haptics theme on this phone"}'
eq "$(run set level medium)" '{"error":"theme file not writable"}'
[[ ! -e $dir/.profile-dry ]]
echo "haptics backend: ok"
