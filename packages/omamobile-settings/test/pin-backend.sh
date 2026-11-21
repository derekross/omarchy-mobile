#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/pin.sh against stand-ins for omamobile-set-pin and `passwd -S` (the paths are replaced in a copy of the
# script; nothing in the environment can do that). `change` is checked for each outcome of `omamobile-set-pin
# --change`: changed (0), refused with passwd's own text, refused by set-pin's own checks, status 75 ("may or may
# not have changed"), a helper that prints nothing, and a missing helper. The stand-in takes the three lines on
# stdin like the real one and fails if any of them reached it as an argument or through the environment. When the
# repository's omamobile-set-pin is next to this package, the same cases run once more through it and a passwd
# stand-in, so the two stay in step.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
# stand-in for omamobile-set-pin: --type prints $tmp/type; --change behaves by the new PIN
cat > "$tmp/set-pin" <<EOF
#!/bin/bash
[[ \${1:-} == --type ]] && { cat "$tmp/type"; exit 0; }
[[ \$# == 1 && \${1:-} == --change ]] || exit 99
env | grep -q '5061\|7384' && exit 98
IFS= read -r old; IFS= read -r new; IFS= read -r again
[[ \$new =~ ^[0-9]{4,}\$ ]] || { echo "The PIN must be at least 4 digits, digits only." >&2; exit 1; }
[[ \$new == "\$again" ]] || { echo "The two PINs do not match." >&2; exit 1; }
[[ \$old == 5061 ]] || { printf 'passwd: Authentication token manipulation error\npasswd: password unchanged\n' >&2; exit 10; }
case \$new in
  88888888) echo 'BAD PASSWORD: it is too simple "quoted" \\ back' >&2; exit 10 ;;
  77777777) echo "passwd did not finish after the retype" >&2; exit 75 ;;
  66666666) exit 3 ;;
esac
exit 0
EOF
chmod +x "$tmp/set-pin"
mkpinsh() { sed -e "s|/usr/bin/passwd|$tmp/passwd|g" -e "s|/usr/bin/omamobile-set-pin|$1|g" "$src/backends/pin.sh" > "$tmp/pin.sh"; grep -q "$1" "$tmp/pin.sh"; }
mkpinsh "$tmp/set-pin"
run() { printf '%s\n' "$2" "$3" "$4" | bash "$tmp/pin.sh" "$1" 2>"$tmp/err" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }
valid() { python3 -I -c 'import json,sys; json.loads(sys.argv[1])' "$1" || { echo "FAIL: not JSON: $1" >&2; exit 1; }; }

maybe='{"error":"passwd did not finish after the retype: the PIN may or may not have changed. Try the new PIN first, then the old one, and don'"'"'t change it again for a minute."}'
eq "$(run change 5061 7384 7384)" '{"changed":true}'
eq "$(run change 4417 7384 7384)" '{"error":"passwd: Authentication token manipulation error\npasswd: password unchanged"}'
out=$(run change 5061 88888888 88888888); valid "$out"
eq "$out" '{"error":"BAD PASSWORD: it is too simple \"quoted\" \\ back"}'
eq "$(run change 5061 77777777 77777777)" "$maybe"
eq "$(run change 5061 66666666 66666666)" '{"error":"the PIN was not changed (exit 3)"}'
eq "$(run change 5061 7384 9152)" '{"error":"The two PINs do not match."}'
eq "$(run change 5061 123 123)" '{"error":"The PIN must be at least 4 digits, digits only."}'
eq "$(run other 5061 7384 7384)" '{"error":"usage: change|status"}'
# a PIN never shows up in what the script prints, on stdout or stderr
out=$(run change 5061 7384 7384; cat "$tmp/err"; run change 4417 7384 7384; cat "$tmp/err")
[[ $out != *7384* && $out != *5061* && $out != *4417* ]] || { echo "FAIL: a PIN was printed" >&2; exit 1; }
# status: how the phone unlocks and whether the account has a password at all
cat > "$tmp/passwd" <<EOF
#!/bin/bash
[[ \${1:-} == -S ]] && { cat "$tmp/pwstatus"; exit 0; }
exit 1
EOF
chmod +x "$tmp/passwd"; mkpinsh "$tmp/set-pin"
status() { bash "$tmp/pin.sh" status 2>/dev/null || true; }
echo pin > "$tmp/type"; echo "lef P 2026-11-10 -1 -1 -1 -1" > "$tmp/pwstatus"
eq "$(status)" '{"type":"pin","hasPassword":true}'
echo password > "$tmp/type"
eq "$(status)" '{"type":"password","hasPassword":true}'
echo pin > "$tmp/type"; echo "lef NP 2026-11-10 -1 -1 -1 -1" > "$tmp/pwstatus"
eq "$(status)" '{"type":"pin","hasPassword":false}'
# fails closed: an answer that is neither pin nor password, a missing omamobile-set-pin, an empty passwd -S
echo "something odd" > "$tmp/type"; echo "lef P 2026-11-10 -1 -1 -1 -1" > "$tmp/pwstatus"
eq "$(status)" '{"error":"cannot tell how this phone unlocks"}'
echo pin > "$tmp/type"; : > "$tmp/pwstatus"
eq "$(status)" '{"error":"cannot tell how this phone unlocks"}'
echo "lef P 2026-11-10 -1 -1 -1 -1" > "$tmp/pwstatus"; mv "$tmp/set-pin" "$tmp/set-pin.off"
eq "$(status)" '{"error":"cannot tell how this phone unlocks"}'
eq "$(run change 5061 7384 7384)" '{"error":"omamobile-set-pin is missing; nothing was changed"}'
mv "$tmp/set-pin.off" "$tmp/set-pin"
eq "$(status)" '{"type":"pin","hasPassword":true}'

# the repository's own helper, with a passwd stand-in that asks like passwd does and knows only 5061
real="$src/../omamobile-shell/bin/omamobile-set-pin"
if [[ -f $real ]]; then
  cat > "$tmp/passwd" <<'EOF'
#!/usr/bin/python3
import getpass, sys
if getpass.getpass("Current password: ") != "5061":
    print("passwd: Authentication token manipulation error\npasswd: password unchanged"); sys.exit(10)
a = getpass.getpass("New password: ")
b = getpass.getpass("Retype new password: ")
if a == "88888888":
    print("BAD PASSWORD: it is too simple\npasswd: password unchanged"); sys.exit(10)
if a == "77777777":
    import time; time.sleep(20)
sys.exit(0 if a == b else 11)
EOF
  chmod +x "$tmp/passwd"
  sed -e "s|^passwd=/usr/bin/passwd|passwd=$tmp/passwd|" "$real" > "$tmp/real-set-pin"; chmod +x "$tmp/real-set-pin"
  grep -q "^passwd=$tmp/passwd" "$tmp/real-set-pin"
  mkpinsh "$tmp/real-set-pin"
  eq "$(run change 5061 7384 7384)" '{"changed":true}'
  out=$(run change 4417 7384 7384); valid "$out"
  [[ $out == '{"error":'*'password unchanged"}' ]] || { echo "FAIL: real helper refusal: $out" >&2; exit 1; }
  out=$(run change 5061 88888888 88888888); valid "$out"
  [[ $out == *'BAD PASSWORD'* ]] || { echo "FAIL: real helper refusal text: $out" >&2; exit 1; }
  eq "$(run change 5061 123 123)" '{"error":"The PIN must be at least 4 digits, digits only."}'
  eq "$(run change 5061 7384 9152)" '{"error":"The two PINs do not match."}'
  # status 75 through the real helper: passwd hangs after the retype, set-pin gives up after 1 s and pin.sh
  # returns at once (the detached cat set-pin leaves behind does not hold the output open)
  start=$SECONDS
  eq "$(printf '%s\n' 5061 77777777 77777777 | OMAMOBILE_PIN_DONE_WAIT=1 bash "$tmp/pin.sh" change 2>/dev/null || true)" "$maybe"
  (( SECONDS - start < 10 )) || { echo "FAIL: status 75 took too long" >&2; exit 1; }
  out=$(run change 5061 7384 7384; cat "$tmp/err"; run change 4417 7384 7384; cat "$tmp/err")
  [[ $out != *7384* && $out != *5061* && $out != *4417* ]] || { echo "FAIL: a PIN was printed (real helper)" >&2; exit 1; }
else
  echo "pin backend: omamobile-set-pin not found next to this package, real-helper cases skipped"
fi
echo "pin backend: ok"
