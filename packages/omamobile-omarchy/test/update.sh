#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-update and its stand-ins against fakes: no sudo, pacman, network,
# systemd or Omarchy command of this machine is run. Uses the real `script`
# (util-linux) for the pty.
set -uo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
PKG=$PWD
failures=0
ok() { if eval "$2"; then echo "ok - $1"; else echo "not ok - $1"; failures=$((failures + 1)); fi; }

t=$(mktemp -d)
trap 'pkill -f "$t/" 2>/dev/null; rm -rf "$t"' EXIT
fake=$t/fake
mkdir -p "$fake" "$t/home" "$t/run" "$t/real" "$t/power"
export HOME=$t/home XDG_RUNTIME_DIR=$t/run XDG_STATE_HOME=$t/home/.local/state
export OMAMOBILE_OMARCHY_LIB=$PKG/lib OMAMOBILE_OMARCHY_LOG=$t/omarchy-update.log
export OMAMOBILE_SUDO=$fake/sudo OMAMOBILE_SYSTEMD_RUN=$fake/systemd-run OMAMOBILE_SYSTEMCTL=$fake/systemctl
export OMAMOBILE_CHECKUPDATES=$fake/checkupdates OMAMOBILE_PACMAN=$fake/pacman OMAMOBILE_OMARCHY_UPDATE=$fake/omarchy-update
export OMAMOBILE_PACMAN_CONF=$t/pacman.conf OMAMOBILE_POWER_SUPPLY=$t/power OMAMOBILE_PATCH_STATUS=$t/patch-status.json
export OMAMOBILE_REAL_BIN=$t/real OMAMOBILE_MODULES_DIR=$t/modules OMAMOBILE_NOTIFY=$fake/notify
export OMARCHY_PATH=$t/omarchy CHECKUPDATES_DB=$t/checkup-db
export PATH=$fake:/usr/bin:/bin
calls=$t/calls

# ---------------------------------------------------------------- fakes
cat >"$fake/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >>"$calls"
if [[ \$1 == -S ]]; then read -r pw; [[ \$pw == 1234 ]] || exit 1; touch "$t/sudo-ok"; exit 0; fi
if [[ \$1 == -n ]]; then [[ -f "$t/sudo-ok" ]] || exit 1; shift; fi
[[ \${1:-} == -v ]] && exit 0
"\$@"
EOF
cat >"$fake/systemd-run" <<EOF
#!/bin/bash
echo "systemd-run \$*" >>"$calls"
while [[ \$1 != -- ]]; do shift; done; shift
setsid "\$@" </dev/null >"$t/unit.out" 2>&1 &
EOF
printf '#!/bin/bash\nexit 3\n' >"$fake/systemctl"
cat >"$fake/checkupdates" <<EOF
#!/bin/bash
cat "$t/updates" 2>/dev/null
[[ -s "$t/updates" ]] || exit 2
EOF
cat >"$fake/pacman" <<EOF
#!/bin/bash
case "\$1" in
  -Q) [[ \$2 == omarchy ]] && echo "omarchy 4.0.4-2" || exit 1 ;;
  -Sup) cat "$t/plan" 2>/dev/null ;;
  -Qmq) echo some-aur-thing ;;
  -Qtdq) echo orphan-lib ;;
  *) echo "pacman \$*" >>"$calls" ;;
esac
EOF
# Omarchy's update, reduced to the calls it makes by name
cat >"$fake/omarchy-update" <<EOF
#!/bin/bash
echo "omarchy-update \$* OMARCHY_UPDATE_LOGGED=\$OMARCHY_UPDATE_LOGGED OMAMOBILE_UPDATE=\$OMAMOBILE_UPDATE" >>"$calls"
for c in omarchy-snapshot omarchy-update-aur-pkgs omarchy-update-orphan-pkgs omarchy-migrate omarchy-update-restart sudo; do
  echo "resolve \$c \$(command -v \$c)" >>"$calls"
done
omarchy-snapshot create; echo "snapshot rc \$?" >>"$calls"
echo -e "\e[32m\nUpdate system packages\e[0m"
printf 'downloading 10%%\rdownloading 50%%\rdownloading 100%%\n'
sudo env OMARCHY_UPDATE_PACMAN=1 pacman -Syu --noconfirm || exit 1
omarchy-migrate
omarchy-update-aur-pkgs
omarchy-update-orphan-pkgs
omarchy-update-restart
exit \${FAKE_UPDATE_RC:-0}
EOF
printf '#!/bin/bash\necho "real-migrate $*" >>"%s"\n' "$calls" >"$t/real/omarchy-migrate"
printf '#!/bin/bash\necho "real-snapshot $*" >>"%s"\n' "$calls" >"$t/real/omarchy-snapshot"
printf '#!/bin/bash\necho "restart-shell" >>"%s"\n' "$calls" >"$fake/omarchy-restart-shell"
printf '#!/bin/bash\nrm -f "$HOME/.local/state/omarchy/$1"\n' >"$fake/omarchy-state"
printf '#!/bin/bash\necho "restart-waybar" >>"%s"\n' "$calls" >"$fake/omarchy-restart-waybar"
printf '#!/bin/bash\nexit 1\n' >"$fake/pgrep"
printf '#!/bin/bash\necho "notify $*" >>"%s"\n' "$calls" >"$fake/notify"
cat >"$fake/omarchy-update-available" <<EOF
#!/bin/bash
[[ -f "$t/available" ]] || { echo "Omarchy is up to date"; exit 1; }
cat "$t/available"
EOF
chmod +x "$fake"/* "$t/real"/*

battery() { # PERCENT STATUS ONLINE
  rm -rf "$t/power"/*
  mkdir -p "$t/power/battery" "$t/power/usb"
  echo Battery >"$t/power/battery/type"; echo 1 >"$t/power/battery/present"
  echo "$1" >"$t/power/battery/capacity"; echo "$2" >"$t/power/battery/status"
  echo USB >"$t/power/usb/type"; echo "$3" >"$t/power/usb/online"
}
good_conf() { printf '[options]\nArchitecture = aarch64\n\n[omamobile]\nInclude = x\n\n[omarchy]\nServer = y\n\n[core]\n[extra]\n[alarm]\n[aur]\n' >"$t/pacman.conf"; }
mkdir -p "$t/modules/$(uname -r)" "$t/omarchy/migrations" "$HOME/.local/state/omarchy/migrations"
printf 'echo "Rebuild the Limine entries"\nsudo limine-update\n' >"$t/omarchy/migrations/1790000001.sh"
printf 'echo "Tweak the bar"\ntrue\n' >"$t/omarchy/migrations/1790000002.sh"
printf 'echo "Prioritize the Omarchy package repository"\nif ! cmp -s /etc/pacman.conf "$pacman_config"; then\n  sudo cp -a /etc/pacman.conf /etc/pacman.conf.bak\n  sudo install -m 644 -o root -g root "$pacman_config" /etc/pacman.conf\nfi\n' >"$t/omarchy/migrations/1790000004.sh"
printf 'echo "Old one"\nsudo limine-update\n' >"$t/omarchy/migrations/1700000000.sh"
touch "$HOME/.local/state/omarchy/migrations/1700000000.sh"
echo "omarchy 4.0.4-2 -> 4.0.5-1" >"$t/updates"
printf 'omarchy 4.0.5-1\nmesa 26.1-1\n' >"$t/plan"
echo '{"result": "ok", "applied": ["0003-x.patch"], "upstream": ["0000-y.patch"], "omarchy": "omarchy 4.0.5-1"}' >"$t/patch-status.json"
U=$PKG/bin/omamobile-update

wait_done() {
  for _ in $(seq 150); do grep -cP '^state\tdone' "$XDG_RUNTIME_DIR/omamobile-update/events" >/dev/null 2>&1 && return 0; sleep 0.1; done
  return 1
}

# ---------------------------------------------------------------- checks
good_conf
ok "repository order: [omamobile] first passes" '[[ -z $(python3 -I -B -c "import importlib.machinery as m, importlib.util as u; l=m.SourceFileLoader(\"u\", \"$U\"); s=u.spec_from_loader(\"u\", l); x=u.module_from_spec(s); l.exec_module(x); print(x.repository_order())") ]]'
printf '[options]\n[omarchy]\n[omamobile]\n[core]\n' >"$t/pacman.conf"
out=$(python3 -I "$U" check --json --offline)
ok "repository order: [omarchy] before [omamobile] blocks" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"ok\"] and not d[\"repositories_ok\"]" "$out"'
printf '[options]\n[omamobile]\n[core]\n[omarchy]\n' >"$t/pacman.conf"
out=$(python3 -I "$U" check --json --offline)
ok "repository order: [core] before [omarchy] blocks" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert \"[core]\" in d[\"repositories\"]" "$out"'
for ch in edge rc; do
  printf '[options]\n[omamobile]\nInclude = x\n\n[omarchy]\nSigLevel = Optional TrustAll\nServer = https://pkgs.omarchy.org/%s/$arch\n\n[core]\n' "$ch" >"$t/pacman.conf"
  out=$(python3 -I "$U" check --json --offline)
  ok "channel: [omarchy] on $ch blocks, with the fix" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"ok\"] and \"pkgs.omarchy.org/stable/\" in d[\"repositories\"] and sys.argv[2] + \" channel\" in d[\"repositories\"]" "$out" "$ch"'
done
printf '[options]\n[omamobile]\nInclude = x\nServer = https://pkgs.omarchy.org/edge/$arch\n\n[omarchy]\nServer = https://pkgs.omarchy.org/stable/$arch\n\n[core]\n' >"$t/pacman.conf"
out=$(python3 -I "$U" check --json --offline)
ok "channel: stable passes, whatever another section points at" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d[\"repositories_ok\"]" "$out"'
good_conf

battery 20 Discharging 0
out=$(python3 -I "$U" check --json --offline)
ok "battery 20%, unplugged: blocked" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"battery_ok\"] and not d[\"ok\"] and \"20%\" in d[\"blockers\"][0]" "$out"'
# A paired controller's battery (scope Device) sorts first and is full: the
# phone's own 20 % still counts, and the controller doesn't make it "charging"
battery 20 Discharging 0
mkdir -p "$t/power/aa-controller-battery"
echo Battery >"$t/power/aa-controller-battery/type"; echo 1 >"$t/power/aa-controller-battery/present"
echo Device >"$t/power/aa-controller-battery/scope"
echo 100 >"$t/power/aa-controller-battery/capacity"; echo Full >"$t/power/aa-controller-battery/status"
out=$(python3 -I "$U" check --json --offline)
ok "battery 20% with a full controller paired: still blocked" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d[\"battery\"][\"percent\"] == 20 and not d[\"battery\"][\"charging\"] and not d[\"battery_ok\"]" "$out"'
battery 20 Discharging 1
out=$(python3 -I "$U" check --json --offline)
ok "battery 20%, charger in: fine" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d[\"battery_ok\"] and d[\"battery\"][\"charging\"]" "$out"'
battery 64 Discharging 0
out=$(python3 -I "$U" check --json)
ok "check: updates, omarchy line, patches, credential" 'python3 -c "
import json,sys; d=json.loads(sys.argv[1])
assert d[\"ok\"], d[\"blockers\"]
assert d[\"omarchy_update\"] == \"omarchy 4.0.4-2 -> 4.0.5-1\" and d[\"update_count\"] == 2
assert d[\"patches\"][\"upstream\"] == [\"0000-y.patch\"] and d[\"credential\"] == \"pin\"
assert d[\"omarchy\"] == \"4.0.4-2\" and d[\"release_notes\"].startswith(\"https://\")
" "$out"'
printf 'omarchy 4.0.5-1\nlinux-aarch64 7.3-1\nlimine 9.0-1\nlinux-firmware-other 1-1\nlinux-api-headers 7-1\n' >"$t/plan"
out=$(python3 -I "$U" check --json)
ok "check: kernels and bootloaders in the plan block, firmware and headers don't" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d[\"boot_packages\"] == [\"limine\", \"linux-aarch64\"] and not d[\"ok\"]" "$out"'
printf 'omarchy 4.0.5-1\nmesa 26.1-1\n' >"$t/plan"

# ---------------------------------------------------------------- the sheet's run
: >"$calls"
rc=0; out=$(printf '1234\n' | python3 -I "$U" start) || rc=$?
ok "start: the PIN is taken (exit 0, '$out')" '[[ $rc == 0 && $out == started ]]'
ok "start: the run finished" wait_done
last=$HOME/.local/state/omamobile/update/last.json
ok "result: ok, with the patch status" 'python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"ok\", d; assert d[\"patches\"][\"result\"] == \"ok\""'
ok "the PIN reached sudo -S on stdin, never argv" 'grep -c "^sudo -S -p  -v$" "$calls" >/dev/null && ! grep -c 1234 "$calls" >/dev/null'
ok "no password file left behind" '[[ ! -e $XDG_RUNTIME_DIR/omamobile-update/auth ]]'
ok "the unit runs as omamobile-update" 'grep -c -- "--unit=omamobile-update" "$calls" >/dev/null'
ok "omarchy-update -y, unlogged (script is ours), OMAMOBILE_UPDATE=1" 'grep -c "^omarchy-update -y OMARCHY_UPDATE_LOGGED=1 OMAMOBILE_UPDATE=1" "$calls" >/dev/null'
for c in omarchy-snapshot omarchy-update-aur-pkgs omarchy-update-orphan-pkgs omarchy-migrate omarchy-update-restart sudo; do
  ok "stand-in on PATH: $c" 'grep -c "^resolve $c $PKG/lib/update-bin/$c$" "$calls" >/dev/null'
done
ok "snapshot: skipped with 127, real Snapper never called" 'grep -c "^snapshot rc 127$" "$calls" >/dev/null && ! grep -c real-snapshot "$calls" >/dev/null'
ok "sudo during the update is non-interactive" 'grep -c "^sudo -n env OMARCHY_UPDATE_PACMAN=1 pacman -Syu" "$calls" >/dev/null'
ok "pacman -Syu went through Omarchy's call" 'grep -c "^pacman -Syu --noconfirm" "$calls" >/dev/null'
ok "migrations: Omarchy's migrate runs after the holds" 'grep -c "^real-migrate" "$calls" >/dev/null'
ok "migrations: the Limine one is held and marked done" '[[ -f $HOME/.local/state/omarchy/migrations/1790000001.sh ]] && grep -c "^1790000001.sh	limine" $HOME/.local/state/omamobile/update/held-migrations >/dev/null'
ok "migrations: one that replaces pacman.conf is held, for the install (not its backup)" '[[ -f $HOME/.local/state/omarchy/migrations/1790000004.sh ]] && grep -c "^1790000004.sh	install -m 644 -o root -g root \"\$pacman_config\" /etc/pacman.conf	" $HOME/.local/state/omamobile/update/held-migrations >/dev/null'
ok "migrations: the harmless one is left to Omarchy" '[[ ! -f $HOME/.local/state/omarchy/migrations/1790000002.sh ]]'
ok "migrations: one already done is not held again" '! grep -c "^1700000000.sh" $HOME/.local/state/omamobile/update/held-migrations >/dev/null'
ok "result lists the held migration" 'python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"held\"][0][:2] == [\"1790000001.sh\", \"limine\"]"'
ok "restart: shell restarted, no reboot asked" 'grep -c "^restart-shell$" "$calls" >/dev/null && python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"needs_reboot\"] is False"'
ev=$XDG_RUNTIME_DIR/omamobile-update/events
ok "events: Omarchy's green heading is a step" 'grep -cP "^step\tUpdate system packages$" "$ev" >/dev/null'
ok "events: \\r progress is a progress event, the final line a line" 'grep -cP "^progress\tdownloading" "$ev" >/dev/null && grep -cP "^line\tdownloading 100%$" "$ev" >/dev/null'
ok "events: auth ok, result, state done" 'grep -cP "^auth\tok$" "$ev" >/dev/null && grep -cP "^result\t\\{" "$ev" >/dev/null && grep -cP "^state\tdone$" "$ev" >/dev/null'
ok "events: no escape codes" '! grep -cP "\x1b" "$ev" >/dev/null'
ok "the full log is kept" 'grep -c "Update system packages" $HOME/.local/state/omamobile/update/update.log >/dev/null'
st=$(python3 -I "$U" status --json)
ok "status: done, unseen until acknowledged" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"running\"] and d[\"unseen\"]" "$st"'
python3 -I "$U" ack
st=$(python3 -I "$U" status --json)
ok "ack: seen" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"unseen\"]" "$st"'

# Omarchy asked for a restart; Hyprland replaced is the same path
mkdir -p "$HOME/.local/state/omarchy"; touch "$HOME/.local/state/omarchy/reboot-required" "$HOME/.local/state/omarchy/restart-waybar-required"
rm -f "$t/sudo-ok"; : >"$calls"
printf '1234\n' | python3 -I "$U" start >/dev/null; wait_done
ok "reboot-required: the result asks for a restart" 'python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"needs_reboot\"] and d[\"reasons\"] == [\"Omarchy asked for a restart\"]"'
ok "restart-*-required services are restarted" 'grep -c "^restart-waybar$" "$calls" >/dev/null'
rm -f "$HOME/.local/state/omarchy/reboot-required"

# Patches failed after the update: reported as such
echo '{"result": "failed", "failed": {"patch": "0003-x.patch"}, "log": "/var/log/omamobile/omarchy-patches.log"}' >"$t/patch-status.json"
rm -f "$t/sudo-ok"
printf '1234\n' | python3 -I "$U" start >/dev/null; wait_done
ok "patches failed: result patches-failed, with the log" 'python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"patches-failed\" and \"omarchy-patches.log\" in d[\"message\"]"'
echo '{"result": "ok"}' >"$t/patch-status.json"

# Omarchy's update failing
rm -f "$t/sudo-ok"
printf '1234\n' | FAKE_UPDATE_RC=1 python3 -I "$U" start >/dev/null; wait_done
ok "a failing update: result failed with the log path" 'python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"failed\" and d[\"log\"] in d[\"message\"]"'

# Wrong PIN
rm -f "$t/sudo-ok"; : >"$calls"
rc=0; out=$(printf '9999\n' | python3 -I "$U" start) || rc=$?
ok "wrong PIN: start exits 3" '[[ $rc == 3 && $out == auth-failed ]]'
wait_done
ok "wrong PIN: Omarchy's update never ran" '! grep -c "^omarchy-update" "$calls" >/dev/null'
ok "wrong PIN: result auth-failed" 'python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"auth-failed\""'

# A boot package in the plan: refused after sudo, before Omarchy's update
printf 'omarchy 4.0.5-1\nlinux-aarch64 7.3-1\n' >"$t/plan"
rm -f "$t/sudo-ok"; : >"$calls"
rc=0; out=$(printf '1234\n' | python3 -I "$U" start) || rc=$?
wait_done
ok "boot package: Omarchy's update never ran" '! grep -c "^omarchy-update" "$calls" >/dev/null'
ok "boot package: result refused, naming it" 'python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"refused\" and \"linux-aarch64\" in d[\"message\"]"'
printf 'omarchy 4.0.5-1\nmesa 26.1-1\n' >"$t/plan"

# Low battery and wrong repository order: refused before the PIN is used
battery 12 Discharging 0
rm -f "$t/sudo-ok"; : >"$calls"
rc=0; out=$(printf '1234\n' | python3 -I "$U" start) || rc=$?
ok "low battery: refused (exit 5) before sudo" '[[ $rc == 5 ]] && ! grep -c "^sudo" "$calls" >/dev/null'
ok "low battery: result names the battery" 'python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"refused\" and \"12%\" in d[\"message\"]"'
battery 64 Discharging 0
printf '[options]\n[core]\n[omamobile]\n[omarchy]\n' >"$t/pacman.conf"
rc=0; out=$(printf '1234\n' | python3 -I "$U" start) || rc=$?
ok "repository order: refused (exit 5)" '[[ $rc == 5 ]]'
good_conf

# Terminal run (what "omarchy update" becomes): same stand-ins, output echoed
rm -f "$t/sudo-ok"; touch "$t/sudo-ok"; : >"$calls"
out=$(python3 -I "$U" -y </dev/null 2>&1); rc=$?
ok "terminal run: exit 0, Omarchy's output shown" '[[ $rc == 0 ]] && grep -c "Update system packages" <<<"$out" >/dev/null'
ok "terminal run: sudo asked interactively once (sudo -v), not -S" 'grep -c "^sudo -v$" "$calls" >/dev/null && ! grep -c "^sudo -S" "$calls" >/dev/null'

# Stand-ins on their own
out=$(OMAMOBILE_UPDATE_DIR=$t/u bash lib/update-bin/omarchy-update-aur-pkgs)
ok "AUR stand-in: lists, never runs yay" 'grep -c "some-aur-thing" <<<"$out" >/dev/null'
out=$(bash lib/update-bin/omarchy-update-orphan-pkgs)
ok "orphan stand-in: lists, keeps" 'grep -c "kept: orphan-lib" <<<"$out" >/dev/null'
rc=0; bash lib/update-bin/omarchy-update-firmware 2>/dev/null || rc=$?
ok "firmware stand-in refuses" '[[ $rc == 1 ]]'
rc=0; OMAMOBILE_HOLD_MIGRATIONS=0 bash lib/update-bin/omarchy-migrate >/dev/null || rc=$?
ok "OMAMOBILE_HOLD_MIGRATIONS=0 holds nothing" '[[ ! -f $HOME/.local/state/omarchy/migrations/1790000002.sh ]]'
# A migration that reorders pacman.conf some other way: [omamobile] goes back on top
good_conf; cp "$t/pacman.conf" "$t/pacman.good"
mkdir -p "$t/reorder"
printf '#!/bin/bash\nsed -i "/^\\[omamobile\\]/,+2d" "%s"\nprintf "\\n[omamobile]\\nInclude = x\\n" >>"%s"\n' "$t/pacman.conf" "$t/pacman.conf" >"$t/reorder/omarchy-migrate"
chmod +x "$t/reorder/omarchy-migrate"
out=$(OMAMOBILE_HOLD_MIGRATIONS=0 OMAMOBILE_REAL_BIN=$t/reorder bash lib/update-bin/omarchy-migrate 2>&1); rc=$?
repos=$(sed -n 's/^\[\(.*\)\]$/\1/p' "$t/pacman.conf" | paste -sd" ")
ok "after migrate: a reorder is undone, [omamobile] first and the rest kept in order" '[[ $rc == 0 && $repos == "options omamobile omarchy core extra alarm aur" ]] && grep -c "moved \[omamobile\] back to the top" <<<"$out" >/dev/null'
good_conf; : >"$calls"
OMAMOBILE_HOLD_MIGRATIONS=0 bash lib/update-bin/omarchy-migrate >/dev/null 2>&1
ok "after migrate: a good order is left alone" 'cmp -s "$t/pacman.conf" "$t/pacman.good" && ! grep -c "^sudo tee" "$calls" >/dev/null'
out=$(bash lib/update-bin/omarchy-migrate --pending)
ok "migrate --pending passes straight through" 'grep -c "^real-migrate --pending" "$calls" >/dev/null'

# run-migration: runs one held migration and takes it off the list
printf 'echo "Held one"\ntouch "%s/ran"\n' "$t" >"$t/omarchy/migrations/1790000003.sh"
printf '1790000003.sh\tlimine\tHeld one\n' >>"$HOME/.local/state/omamobile/update/held-migrations"
python3 -I "$U" run-migration 1790000003.sh >/dev/null
ok "run-migration runs it and clears it from the held list" '[[ -f $t/ran ]] && ! grep -c "^1790000003.sh" $HOME/.local/state/omamobile/update/held-migrations >/dev/null'
rc=0; python3 -I "$U" run-migration '../../etc/x.sh' 2>/dev/null || rc=$?
ok "run-migration takes migration names only" '[[ $rc == 2 ]]'

# notify-check: once per release, tap opens the sheet
: >"$calls"; rm -f "$t/available"
python3 -I "$U" notify-check >/dev/null
ok "notify-check: up to date, no toast" '! grep -c "^notify" "$calls" >/dev/null'
echo "omarchy 4.0.4-2 -> 4.0.5-1" >"$t/available"
python3 -I "$U" notify-check >/dev/null; python3 -I "$U" notify-check >/dev/null
ok "notify-check: one toast per release, opening the sheet" '[[ $(grep -c "^notify" "$calls") == 1 ]] && grep -c "summon omamobile.update" "$calls" >/dev/null'

exit $((failures > 0))
