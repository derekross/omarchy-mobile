#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/pin.sh and pin.py against a stand-in for /usr/bin/passwd (the path and the deadline are replaced in
# copies of the two files, nothing in the environment can do that), and `status` against stand-ins for
# omamobile-set-pin and `passwd -S`. The stand-in asks for the current password, the new one and a
# retype on a terminal, as passwd does, and accepts only the current password 1111. New passwords with special
# behaviour: 00000000 is refused and asked for again (like pam_unix), 77777777 hangs at the retype, 88888888 is
# refused by exiting. It prints Greek prompts unless it was started with LC_ALL=C, and it fails when the script's
# own environment (its parent's) holds a PIN.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
cat > "$tmp/passwd" <<'EOT'
#!/usr/bin/python3
import getpass, os, sys, time
if sys.argv[1:] == ["-S"]:
    print(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "pwstatus")).read().strip()); sys.exit(0)
if os.environ.get("LC_ALL") != "C":
    print("Greek prompts: " + getpass.getpass("Τρέχων κωδικός: ")); sys.exit(13)
env = open("/proc/%d/environ" % os.getppid(), "rb").read()
if b"1111" in env or b"2222" in env: sys.exit(12)
if getpass.getpass("Current password: ") != "1111": sys.exit(10)
a = getpass.getpass("New password: ")
if a == "00000000":
    while True:
        print("BAD PASSWORD: it is too simple")
        getpass.getpass("New password: ")
b = getpass.getpass("Retype new password: ")
if a == "77777777": time.sleep(60)
if a != b or a == "88888888": sys.exit(11)
EOT
chmod +x "$tmp/passwd"
printf '#!/bin/bash\ncat "%s/type"\n' "$tmp" > "$tmp/set-pin"; chmod +x "$tmp/set-pin"
sed -e "s|/usr/bin/passwd|$tmp/passwd|g" -e 's/^DEADLINE = 12/DEADLINE = 3/' "$src/backends/pin.py" > "$tmp/pin.py"
sed -e "s|/usr/bin/passwd|$tmp/passwd|g" -e "s|/usr/bin/omamobile-set-pin|$tmp/set-pin|g" "$src/backends/pin.sh" > "$tmp/pin.sh"
grep -q "$tmp/passwd" "$tmp/pin.py"; grep -q '^DEADLINE = 3' "$tmp/pin.py"; grep -q "$tmp/set-pin" "$tmp/pin.sh"
run() { printf '%s\n' "$2" "$3" "$4" | LC_ALL=el_GR.UTF-8 bash "$tmp/pin.sh" "$1" 2>"$tmp/err" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }

eq "$(run change 1111 2222 2222)" '{"changed":true}'
eq "$(run change 9999 2222 2222)" '{"error":"the current PIN was not accepted"}'
eq "$(run change 1111 88888888 88888888)" '{"error":"the system refused the new PIN"}'
# a refusal that asks again does not hang: it is reported at once, not after the deadline
start=$SECONDS
eq "$(run change 1111 00000000 00000000)" '{"error":"the system refused the new PIN"}'
(( SECONDS - start < 3 )) || { echo "FAIL: the refusal waited for the deadline" >&2; exit 1; }
# a passwd that never finishes after the retype: said plainly, and passwd is gone afterwards
eq "$(run change 1111 77777777 77777777)" '{"error":"passwd did not finish in time; the PIN may or may not have changed, try the new PIN first and then the old one"}'
sleep 0.5
! pgrep -f "$tmp/passwd" >/dev/null || { echo "FAIL: passwd was left running" >&2; exit 1; }
eq "$(run change 1111 2222 3333)" '{"error":"the new PINs do not match"}'
eq "$(run change 1111 1111 1111)" '{"error":"the new PIN is the same as the current one"}'
eq "$(run change 1111 123 123)" '{"error":"new PIN must be 4 to 8 digits"}'
eq "$(run change 1111 123456789 123456789)" '{"error":"new PIN must be 4 to 8 digits"}'
eq "$(run change 1111 12a45 12a45)" '{"error":"new PIN must be 4 to 8 digits"}'
eq "$(run change abc 2222 2222)" '{"error":"current PIN must be digits"}'
eq "$(run change 1111 '' '')" '{"error":"new PIN must be 4 to 8 digits"}'
eq "$(run other 1111 2222 2222)" '{"error":"usage: change|status"}'
eq "$(printf '1111\n' | bash "$tmp/pin.sh" change 2>/dev/null || true)" '{"error":"no new PIN"}'
eq "$(printf '' | bash "$tmp/pin.sh" change 2>/dev/null || true)" '{"error":"no current PIN"}'
# a PIN never shows up in what the script prints, on stdout or stderr
out=$(run change 1111 2222 2222; cat "$tmp/err"; run change 9999 2222 2222; cat "$tmp/err")
[[ $out != *2222* && $out != *1111* && $out != *9999* ]] || { echo "FAIL: a PIN was printed" >&2; exit 1; }
# status: how the phone unlocks and whether the account has a password at all
status() { bash "$tmp/pin.sh" status 2>/dev/null || true; }
echo pin > "$tmp/type"; echo "lef P 2026-11-10 -1 -1 -1 -1" > "$tmp/pwstatus"
eq "$(status)" '{"type":"pin","hasPassword":true}'
echo password > "$tmp/type"
eq "$(status)" '{"type":"password","hasPassword":true}'
echo pin > "$tmp/type"; echo "lef NP 2026-11-10 -1 -1 -1 -1" > "$tmp/pwstatus"
eq "$(status)" '{"type":"pin","hasPassword":false}'
echo "something odd" > "$tmp/type"; echo "lef P 2026-11-10 -1 -1 -1 -1" > "$tmp/pwstatus"
eq "$(status)" '{"type":"pin","hasPassword":true}'
echo "pin backend: ok"
