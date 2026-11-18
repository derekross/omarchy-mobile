#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/charge.sh against a scratch root (a copy of the script with `fake` set), and libexec/charge-limit,
# the root helper, in the same scratch root: no service is started and nothing real is written.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
root=$tmp/root
dir=$root/sys/class/power_supply/max77759-charger
end=$dir/charge_control_end_threshold start=$dir/charge_control_start_threshold
sed "s|^fake=.*|fake=$root|" "$src/backends/charge.sh" > "$tmp/charge.sh"
grep -q "^fake=$root" "$tmp/charge.sh"
run() { bash "$tmp/charge.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }

decl=$root/usr/share/omamobile/charge-limit.conf
declare_husky() { mkdir -p "${decl%/*}"; printf '# test\nsupply=max77759-charger\n' > "$decl"; }
# no charger: not available, and set refuses
mkdir -p "$root"
eq "$(run get)" '{"available":false}'
eq "$(run set limit 80)" '{"error":"this phone has no charge limit"}'

# a charger with the threshold but no declaration (the Pixel 7 Pro on a kernel with #266): not available, no write
mkdir -p "$dir"; echo 100 > "$end"; echo 7 > "$start"
eq "$(run get)" '{"available":false}'
eq "$(run set limit 80)" '{"error":"this phone has no charge limit"}'
eq "$(cat "$end")" 100
for bad in 'supply=../../x' 'supply=' 'supply=Max' 'supply=../power_supply/max77759-charger'; do
  mkdir -p "${decl%/*}"; echo "$bad" > "$decl"; eq "$(run get)" '{"available":false}'
done
declare_husky
eq "$(run get)" '{"available":true,"limit":100}'
eq "$(run set limit 80)" '{"available":true,"limit":80}'
eq "$(run set limit 75)" '{"error":"bad value"}'
eq "$(run set limit 101)" '{"error":"bad value"}'
eq "$(run set limit abc)" '{"error":"bad value"}'
eq "$(run set level 80)" '{"error":"unknown key"}'
eq "$(run nonsense)" '{"error":"usage: get|set"}'
echo junk > "$end"
eq "$(run get)" '{"error":"cannot read the charger"}'

# the root helper
helper=$src/libexec/charge-limit
export OMAMOBILE_CHARGE_ROOT=$root
file=$root/etc/omamobile/charge-limit
no() { if bash "$helper" "$@" >/dev/null 2>&1; then echo "FAIL: accepted: $*" >&2; exit 1; fi; }
echo 100 > "$end"
bash "$helper" >/dev/null || { echo "FAIL: no saved file is an error" >&2; exit 1; }
eq "$(cat "$end")" 100
[[ ! -e $file ]] || { echo "FAIL: a file appeared" >&2; exit 1; }
echo 7 > "$start"
bash "$helper" 85 >/dev/null
eq "$(cat "$file")" 85; eq "$(cat "$end")" 85; eq "$(cat "$start")" 0
for bad in 0 79 101 abc 8.5 '80;x'; do no "$bad"; done
eq "$(cat "$file")" 85; eq "$(cat "$end")" 85
# boot: udev runs it with no argument, the saved value goes to the charger
echo 100 > "$end"; echo 90 > "$file"
bash "$helper" >/dev/null; eq "$(cat "$end")" 90
echo 42 > "$file"; no; eq "$(cat "$end")" 90
# no declaration (another phone): both paths touch nothing, and N is refused without saving
echo 80 > "$file"; rm "$decl"
bash "$helper" >/dev/null || { echo "FAIL: boot without a declaration is an error" >&2; exit 1; }
eq "$(cat "$end")" 90
no 95; eq "$(cat "$end")" 90; eq "$(cat "$file")" 80
echo 'supply=../max77759-charger' > "$decl"; no 95; bash "$helper" >/dev/null; eq "$(cat "$end")" 90
# a name with a path in it that still reaches the real charger: only the name check refuses it
echo 'supply=../power_supply/max77759-charger' > "$decl"
no 95; eq "$(cat "$end")" 90; eq "$(cat "$file")" 80
bash "$helper" >/dev/null; eq "$(cat "$end")" 90
declare_husky
# a failed write saves nothing: a directory in place of the end file cannot be written
echo 85 > "$file"
mv "$end" "$tmp/end.bak"; mkdir "$end"; chmod 755 "$end"
no 95; eq "$(cat "$file")" 85
rmdir "$end"; mv "$tmp/end.bak" "$end"
# a start threshold that cannot be written stops before the end is touched
mv "$start" "$tmp/start.bak"; mkdir "$start"
echo 90 > "$end"; no 80; eq "$(cat "$end")" 90; eq "$(cat "$file")" 85
rmdir "$start"; mv "$tmp/start.bak" "$start"
# an end threshold that is not writable (read-only file; skipped as root, which can write anyway): refused, nothing saved
if (( EUID != 0 )); then
  chmod 444 "$end"; no 95; eq "$(cat "$file")" 85; chmod 644 "$end"
fi
# no charger: refused and nothing saved; the boot path just does nothing
rm -rf "$dir"
no 95; eq "$(cat "$file")" 85
bash "$helper" >/dev/null || { echo "FAIL: boot with no charger is an error" >&2; exit 1; }
OMAMOBILE_CHARGE_ROOT=relative bash "$helper" 80 && { echo "FAIL: relative root accepted" >&2; exit 1; } || true

# the polkit rule, the unit and the udev rule
v=$src/vendor
grep -qF '/^omamobile-charge-limit@(80|85|90|95|100)\.service$/' "$v/polkit/50-omamobile-charge-limit.rules" &&
  grep -qF 'action.lookup("verb") == "start"' "$v/polkit/50-omamobile-charge-limit.rules" &&
  grep -qF 'subject.local && subject.active' "$v/polkit/50-omamobile-charge-limit.rules" ||
  { echo "FAIL: polkit: the five charge-limit units, start only" >&2; exit 1; }
u=$v/systemd/system/omamobile-charge-limit@.service
grep -qx 'ExecStart=/usr/lib/omamobile-settings/charge-limit %i' "$u" && grep -qx 'Type=oneshot' "$u" &&
  grep -qx 'StartLimitIntervalSec=0' "$u" && ! grep -q '^\[Install\]' "$u" ||
  { echo "FAIL: unit: oneshot helper with the instance, no start limit, not enabled" >&2; exit 1; }
h=$src/../omamobile-device-husky
if [[ -d $h ]]; then
  r=$h/vendor/udev/rules.d/75-omamobile-charge-limit.rules
  [[ $(grep -v '^#' "$r" | grep -c .) == 1 ]] &&
    grep -qxF 'SUBSYSTEM=="power_supply", KERNEL=="max77759-charger", TAG+="systemd", ENV{SYSTEMD_WANTS}+="omamobile-charge-limit-apply.service"' "$r" &&
    ! grep -v '^#' "$r" | grep -c -e RUN -e ACTION >/dev/null ||
    { echo "FAIL: udev: one rule, no ACTION filter, pulls in the apply unit" >&2; exit 1; }
  a=$h/vendor/systemd/system/omamobile-charge-limit-apply.service
  grep -qx 'ExecStart=/usr/lib/omamobile-settings/charge-limit' "$a" && grep -qx 'Type=oneshot' "$a" &&
    grep -qx 'StartLimitIntervalSec=0' "$a" && ! grep -q '^\[Install\]' "$a" ||
    { echo "FAIL: apply unit: oneshot helper with no argument, not enabled" >&2; exit 1; }
  grep -qx 'supply=max77759-charger' "$h/charge-limit.conf" || { echo "FAIL: husky declares max77759-charger" >&2; exit 1; }
fi
[[ ! -e $v/udev/rules.d/75-omamobile-charge-limit.rules && ! -e $v/systemd/system/omamobile-charge-limit-apply.service ]] ||
  { echo "FAIL: the udev rule and the apply unit belong to the device package" >&2; exit 1; }
grep -q 'systemctl start --no-ask-password "omamobile-charge-limit@$value.service"' "$src/backends/charge.sh" ||
  { echo "FAIL: charge.sh starts the unit without asking" >&2; exit 1; }

# the real branch of charge.sh: a stand-in systemctl on PATH records its command line
mkdir -p "$dir" "$tmp/bin"; echo 100 > "$end"
cat > "$tmp/bin/systemctl" <<EOT
#!/bin/bash
printf '%s\\n' "systemctl \$*" >> "$tmp/systemctl.log"
EOT
chmod +x "$tmp/bin/systemctl"
sed -e "s|^decl=.*|decl=$decl|" -e "s|^end=.*|end=$end|" "$src/backends/charge.sh" > "$tmp/charge-real.sh"
grep -q "^fake=''$" "$tmp/charge-real.sh"
eq "$(PATH=$tmp/bin:$PATH bash "$tmp/charge-real.sh" set limit 80)" '{"available":true,"limit":100}'
eq "$(cat "$tmp/systemctl.log")" 'systemctl start --no-ask-password omamobile-charge-limit@80.service'
printf '#!/bin/bash\nexit 1\n' > "$tmp/bin/systemctl"
eq "$(PATH=$tmp/bin:$PATH bash "$tmp/charge-real.sh" set limit 80 || true)" '{"error":"could not set the charge limit"}'

# installed paths and modes (the binary is a stand-in: only the staging is checked)
stage=$tmp/stage; mkdir -p "$tmp/build"; : > "$tmp/build/omamobile-settings"
OMAMOBILE_SETTINGS_BUILD_DIR=$tmp/build "$src/install" "$stage"
while read -r mode f; do
  [[ -f $stage/$f ]] || { echo "FAIL: install stages $f" >&2; exit 1; }
  eq "$(stat -c %a "$stage/$f")" "$mode"
done <<'EOT'
755 usr/lib/omamobile-settings/backends/charge.sh
755 usr/lib/omamobile-settings/charge-limit
644 usr/lib/systemd/system/omamobile-charge-limit@.service
644 usr/share/polkit-1/rules.d/50-omamobile-charge-limit.rules
EOT
for f in usr/lib/systemd/system/omamobile-charge-limit-apply.service usr/lib/udev/rules.d/75-omamobile-charge-limit.rules \
         usr/share/omamobile/charge-limit.conf; do
  [[ ! -e $stage/$f ]] || { echo "FAIL: Settings stages $f, which is the device package's" >&2; exit 1; }
done
echo "charge backend: ok"
