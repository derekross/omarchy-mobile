#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-update and its stand-ins against fakes: no sudo, pacman, network,
# systemd or Omarchy command of this machine is run. Uses the real `script`
# (util-linux) for the pty. The one socket opened is to a web server this
# test starts on 127.0.0.1, for the index probe's own answers.
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
export OMAMOBILE_MIRRORLIST=$t/omamobile-mirrorlist OMAMOBILE_LOCAL_REPO=$t/localrepo
export OMAMOBILE_PACMAN_SYNC=$t/sync OMAMOBILE_CHECKUP_DBS="$t/checkup-db*"
# The device packages' mirrorlist, as shipped (stable on)
packaged_mirrorlist() {
  printf '# Where pacman gets packages\nServer = https://pkgs.omamobile.org/stable/$arch\n#Server = https://pkgs.omamobile.org/development/$arch\n#Server = file:///var/lib/omamobile/repo/$arch\n'
}
packaged_mirrorlist >"$OMAMOBILE_MIRRORLIST"
export OMAMOBILE_BOOT_UPDATE=$fake/omamobile-boot-update OMAMOBILE_BOOT_UPDATE_CONF=$t/boot-update.conf
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
if [[ -e "$t/sync-fail" ]]; then cat "$t/sync-fail" >&2; exit 1; fi
cat "$t/updates" 2>/dev/null
[[ -s "$t/updates" ]] || exit 2
EOF
cat >"$fake/pacman" <<EOF
#!/bin/bash
case "\$1" in
  -Q) [[ \$2 == omarchy ]] && echo "omarchy 4.0.4-2" || exit 1 ;;
  -Sup) if [[ -s "$t/plan-fail" ]]; then cat "$t/plan-fail" >&2; exit 1; fi; cat "$t/plan" 2>/dev/null ;;
  -Qmq) echo some-aur-thing ;;
  -Qtdq) echo orphan-lib ;;
  *) echo "pacman \$*" >>"$calls" ;;
esac
EOF
# Omarchy's update, reduced to the calls it makes by name
cat >"$fake/omarchy-update" <<EOF
#!/bin/bash
echo "omarchy-update \$* OMARCHY_UPDATE_LOGGED=\$OMARCHY_UPDATE_LOGGED OMAMOBILE_UPDATE=\$OMAMOBILE_UPDATE" >>"$calls"
echo "omarchy-update OMARCHY_PATH=\${OMARCHY_PATH-unset}" >>"$calls"
for c in omarchy-snapshot omarchy-update-aur-pkgs omarchy-update-orphan-pkgs omarchy-migrate omarchy-update-restart omarchy-update-boot sudo; do
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
# omamobile-boot-update's read-only preflight, answering from $t/preflight
cat >"$fake/omamobile-boot-update" <<EOF
#!/bin/bash
echo "boot-update \$*" >>"$calls"
[[ \$1 == preflight ]] || exit 9
cat "$t/preflight"
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["ok"] else 1)' "$t/preflight"
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
# Mock host disk capacity inside the fixture interpreter, not through a new
# production bypass flag. The runtime's 10 GiB rule stays unchanged.
export OMAMOBILE_UPDATE_REAL_SOURCE=$PKG/bin/omamobile-update
cat >"$t/update-fixture.py" <<'PYCODE'
#!/usr/bin/python3 -I
import os, runpy, sys
scope = runpy.run_path(os.environ["OMAMOBILE_UPDATE_REAL_SOURCE"], run_name="update_fixture")
scope["check"].__globals__["free_bytes"] = lambda: 20 * 1024 ** 3
# The channel's index is never asked of a real server here: the probe logs
# the address and answers from the fixture's index-answer file ("missing":
# the server says 404). OMAMOBILE_TEST_REAL_PROBE leaves the real probe in,
# for the checks that aim it at this test's own web server.
def fake_index_missing(url, t=os.environ["OMAMOBILE_TEST_DIR"]):
    with open(os.path.join(t, "probes"), "a") as f:
        f.write(url + "\n")
    try:
        with open(os.path.join(t, "index-answer")) as f:
            return f.read().strip() == "missing"
    except OSError:
        return False
if not os.environ.get("OMAMOBILE_TEST_REAL_PROBE"):
    scope["check"].__globals__["index_missing"] = fake_index_missing
# The run starts itself again (the unit, then inside script's pty) by its
# own path: that is this fixture, so those processes get the stand-ins too
scope["check"].__globals__["__file__"] = os.path.abspath(__file__)
globals().update({k: v for k, v in scope.items() if not k.startswith("__")})
if __name__ == "__main__":
    sys.exit(scope["main"](sys.argv[1:]))
PYCODE
U=$t/update-fixture.py
chmod +x "$U"   # the unit runs it by path
export OMAMOBILE_TEST_DIR=$t

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

# The [omamobile] channel: reported by check, switched by "channel"
out=$(python3 -I "$U" check --json --offline)
ok "channel: check reports stable" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d[\"channel\"][\"name\"] == \"stable\" and d[\"channel\"][\"server\"] == \"https://pkgs.omamobile.org/stable/\$arch\"" "$out"'
ok "channel: check prints it" 'python3 -I "$U" check --offline | grep -cx "Channel: stable (https://pkgs.omamobile.org/stable/\$arch)" >/dev/null'
mkdir -p "$t/sync" "$t/checkup-db/sync"
touch "$t/sync/omamobile.db" "$t/sync/omamobile.db.sig" "$t/sync/omarchy.db" "$t/checkup-db/sync/omamobile.db"
python3 -I "$U" channel development >/dev/null
ok "channel: development turns its line on and stable off" '[[ $(grep "^Server" "$OMAMOBILE_MIRRORLIST") == "Server = https://pkgs.omamobile.org/development/\$arch" ]] && grep -cx "#Server = https://pkgs.omamobile.org/stable/\$arch" "$OMAMOBILE_MIRRORLIST" >/dev/null'
ok "channel: the old channel's index is dropped, other repositories' kept" '[[ ! -e $t/sync/omamobile.db && ! -e $t/sync/omamobile.db.sig && ! -e $t/checkup-db/sync/omamobile.db && -e $t/sync/omarchy.db ]]'
ok "channel: with no name it reports" '[[ $(python3 -I "$U" channel --json) == "{\"error\": \"\", \"name\": \"development\", \"server\": \"https://pkgs.omamobile.org/development/\$arch\"}" ]]'
rc=0; python3 -I "$U" channel local 2>"$t/err" || rc=$?
ok "channel: local needs a repository on the phone" '[[ $rc == 1 ]] && grep -c "tools/repo-push" "$t/err" >/dev/null && grep -c "^Server = https://pkgs.omamobile.org/development/" "$OMAMOBILE_MIRRORLIST" >/dev/null'
mkdir -p "$t/localrepo/aarch64" && touch "$t/localrepo/aarch64/omamobile.db"
python3 -I "$U" channel local >/dev/null
ok "channel: local, once there is a repository" '[[ $(python3 -I "$U" check --json --offline | python3 -c "import json,sys; print(json.load(sys.stdin)[\"channel\"][\"name\"])") == local ]]'
python3 -I "$U" channel stable >/dev/null
ok "channel: back to stable gives the packaged file again (pacman then sees it unchanged)" 'cmp -s "$OMAMOBILE_MIRRORLIST" <(packaged_mirrorlist)'
rc=0; python3 -I "$U" channel edge 2>/dev/null || rc=$?
ok "channel: only stable, development or local" '[[ $rc == 2 ]] && cmp -s "$OMAMOBILE_MIRRORLIST" <(packaged_mirrorlist)'
printf '# Where pacman gets packages\nServer = file:///var/lib/omamobile/repo/$arch\n' >"$OMAMOBILE_MIRRORLIST"
python3 -I "$U" channel development >/dev/null
ok "channel: an old-style file gains the line, the old one commented" '[[ $(grep -c "^Server" "$OMAMOBILE_MIRRORLIST") == 1 ]] && grep -cx "Server = https://pkgs.omamobile.org/development/\$arch" "$OMAMOBILE_MIRRORLIST" >/dev/null && grep -cx "#Server = file:///var/lib/omamobile/repo/\$arch" "$OMAMOBILE_MIRRORLIST" >/dev/null'
printf 'Server = https://mirror.example/omamobile/$arch\n' >"$OMAMOBILE_MIRRORLIST"
ok "channel: a custom server is reported as custom" '[[ $(python3 -I "$U" channel --json | python3 -c "import json,sys; print(json.load(sys.stdin)[\"name\"])") == custom ]]'
printf '# nothing\n' >"$OMAMOBILE_MIRRORLIST"
out=$(python3 -I "$U" check --json --offline)
ok "channel: a mirrorlist without a Server line blocks the update" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"ok\"] and d[\"channel\"][\"name\"] == \"none\"" "$out"'
packaged_mirrorlist >"$OMAMOBILE_MIRRORLIST"

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
# A plan pacman can't make (#433: [omarchy]'s aquamarine 0.15.1 without the so=15
# our Hyprland needs) is a refusal with pacman's reason, never the plain list
printf "error: failed to prepare transaction (could not satisfy dependencies)\n:: unable to satisfy dependency 'libaquamarine.so=15-64' required by hyprland\n" >"$t/plan-fail"
out=$(python3 -I "$U" check --json)
ok "check: a plan pacman can't make blocks, with pacman's reason" 'python3 -c "
import json,sys; d=json.loads(sys.argv[1]); b=\" \".join(d[\"blockers\"])
assert not d[\"ok\"] and \"can\x27t plan this update\" in b and \"libaquamarine.so=15-64\" in b, d[\"blockers\"]
" "$out"'
rm -f "$t/plan-fail"

# The phone's own kernel package goes through omamobile-boot-update
printf 'omarchy 4.0.5-1\nlinux-omamobile 7.3.0rc6.r453.g0123456789ab-1\nomamobile-boot-update 0.1.0-1\n' >"$t/plan"
echo '{"auto_write": "yes", "ok": true, "problem": ""}' >"$t/preflight"
out=$(python3 -I "$U" check --json)
ok "kernel: linux-omamobile with a ready slot B passes, and will be written" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d[\"ok\"], d[\"blockers\"]; assert d[\"boot_packages\"] == [] and d[\"kernel\"][\"boot_update\"] == \"write\" and d[\"kernel\"][\"version\"].startswith(\"7.3.0rc6\")" "$out"'
ok "kernel: the check is omamobile-boot-update preflight (read-only)" 'grep -c "^boot-update preflight --json$" "$calls" >/dev/null && ! grep -cE "^boot-update (write|hook|rollback)" "$calls" >/dev/null'
echo '{"auto_write": "yes", "ok": false, "problem": "/dev/sda8 (vendor_boot_b) is read-only"}' >"$t/preflight"
out=$(python3 -I "$U" check --json)
ok "kernel: a slot B the hook would refuse blocks the update, naming why" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"ok\"] and any(\"vendor_boot_b\" in b and \"slot B\" in b for b in d[\"blockers\"]), d[\"blockers\"]" "$out"'
echo '{"auto_write": "no", "ok": false, "problem": "no /usr/lib/omamobile/twelve/dtbo.img"}' >"$t/preflight"
out=$(python3 -I "$U" check --json)
ok "kernel: AUTO_WRITE off (a development phone): installs, slot B left alone" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d[\"ok\"], d[\"blockers\"]; assert d[\"kernel\"][\"boot_update\"] == \"skip\"" "$out"'
out=$(OMAMOBILE_BOOT_UPDATE=$t/no-such-tool python3 -I "$U" check --json)
ok "kernel: the first kernel package with no config passes (the hook will skip)" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d[\"ok\"], d[\"blockers\"]" "$out"'
echo 'AUTO_WRITE=yes' >"$t/boot-update.conf"
out=$(OMAMOBILE_BOOT_UPDATE=$t/no-such-tool python3 -I "$U" check --json)
ok "kernel: AUTO_WRITE=yes but no omamobile-boot-update to ask: blocked" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"ok\"] and any(\"AUTO_WRITE=yes\" in b for b in d[\"blockers\"])" "$out"'
echo 'AUTO_WRITE=perhaps' >"$t/boot-update.conf"
out=$(OMAMOBILE_BOOT_UPDATE=$t/no-such-tool python3 -I "$U" check --json)
ok "kernel: an unreadable boot-update.conf blocks" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"ok\"] and any(\"be read\" in b for b in d[\"blockers\"])" "$out"'
rm -f "$t/boot-update.conf"
printf 'omarchy 4.0.5-1\nmesa 26.1-1\n' >"$t/plan"
ok "a check that works never asks the server for the channel's index" '[[ ! -e $t/probes ]]'

# A channel with nothing published yet (stable before a first release, local
# before the first repo-push): pacman can't fetch its index, so the check for
# updates fails. That is a normal state, with no blocker and exit 0, when
# the channel's server says the index isn't there; any other failure stays one
printf "error: failed retrieving file 'omamobile.db' from pkgs.omamobile.org : The requested URL returned error: 404\nerror: failed to synchronize all databases (failed to retrieve some files)\n" >"$t/sync-fail"
echo missing >"$t/index-answer"
rc=0; out=$(python3 -I "$U" check --json) || rc=$?
ok "empty channel: check is ok (exit 0), no blocker, nothing to update, and says so" '[[ $rc == 0 ]] && python3 -c "
import json,sys; d=json.loads(sys.argv[1])
assert d[\"ok\"] and d[\"blockers\"] == [] and d[\"update_count\"] == 0 and d[\"updates\"] == [], d
assert d[\"channel\"][\"empty\"] is True and d[\"channel\"][\"name\"] == \"stable\"
assert \"The stable channel has no updates yet\" in d[\"channel\"][\"note\"], d[\"channel\"]
" "$out"'
ok "empty channel: the index asked for is the channel's own, for aarch64" '[[ $(cat "$t/probes") == https://pkgs.omamobile.org/stable/aarch64/omamobile.db ]]'
rc=0; out=$(python3 -I "$U" check) || rc=$?
ok "empty channel: the plain check says no updates yet, never Blocked" '[[ $rc == 0 ]] && grep -c "^No updates yet: The stable channel has no updates yet" <<<"$out" >/dev/null && ! grep -c "Blocked" <<<"$out" >/dev/null'
echo present >"$t/index-answer"; rm -f "$t/probes"
rc=0; out=$(python3 -I "$U" check --json) || rc=$?
ok "a failed check with the index there (offline, a server error) still blocks" '[[ $rc == 1 && -s $t/probes ]] && python3 -c "
import json,sys; d=json.loads(sys.argv[1])
assert not d[\"ok\"] and d[\"channel\"][\"empty\"] is False and d[\"channel\"][\"note\"] == \"\"
assert any(b.startswith(\"could not check for updates\") and \"404\" in b for b in d[\"blockers\"]), d[\"blockers\"]
" "$out"'
echo missing >"$t/index-answer"; rm -f "$t/probes"
printf 'Server = https://mirror.example/omamobile/$arch\n' >"$OMAMOBILE_MIRRORLIST"
rc=0; out=$(python3 -I "$U" check --json) || rc=$?
ok "a custom Server line is never read as an empty channel, nor asked" '[[ $rc == 1 && ! -e $t/probes ]] && python3 -c "
import json,sys; d=json.loads(sys.argv[1]); assert not d[\"ok\"] and d[\"channel\"][\"empty\"] is False" "$out"'
# local: the repository on the phone, no server to ask
printf '#Server = https://pkgs.omamobile.org/stable/$arch\nServer = file:///var/lib/omamobile/repo/$arch\n' >"$OMAMOBILE_MIRRORLIST"
rm -rf "$OMAMOBILE_LOCAL_REPO"
rc=0; out=$(python3 -I "$U" check --json) || rc=$?
ok "empty channel: local with no repository pushed yet is ok too, no server asked" '[[ $rc == 0 && ! -e $t/probes ]] && python3 -c "
import json,sys; d=json.loads(sys.argv[1]); assert d[\"ok\"] and d[\"channel\"][\"empty\"] and \"The local channel\" in d[\"channel\"][\"note\"]" "$out"'
mkdir -p "$OMAMOBILE_LOCAL_REPO/aarch64"; : >"$OMAMOBILE_LOCAL_REPO/aarch64/omamobile.db"
rc=0; out=$(python3 -I "$U" check --json) || rc=$?
ok "local with its index there: a failed check still blocks" '[[ $rc == 1 ]] && python3 -c "
import json,sys; d=json.loads(sys.argv[1]); assert not d[\"ok\"] and not d[\"channel\"][\"empty\"]" "$out"'
rm -rf "$OMAMOBILE_LOCAL_REPO"
packaged_mirrorlist >"$OMAMOBILE_MIRRORLIST"

# The probe itself, against a web server of this test's on 127.0.0.1: 404 is
# "not there"; a file that is served, a server error and no server at all
# are not
mkdir -p "$t/www/stable/aarch64" "$t/www-code"
: >"$t/www/stable/aarch64/omamobile.db"
cat >"$t/www-code/server.py" <<'PYCODE'
import http.server, os, sys
root = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        code = 500 if self.path.startswith("/broken/") else 200 if os.path.isfile(root + self.path) else 404
        self.send_response(code); self.send_header("Content-Length", "0"); self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(sys.argv[2] + ".new", "w") as f: f.write(str(s.server_address[1]))
os.rename(sys.argv[2] + ".new", sys.argv[2])
s.serve_forever()
PYCODE
python3 -I -B "$t/www-code/server.py" "$t/www" "$t/www-port" & www=$!
for _ in $(seq 50); do [[ -s $t/www-port ]] && break; sleep 0.1; done
port=$(cat "$t/www-port" 2>/dev/null)
probe() { OMAMOBILE_TEST_REAL_PROBE=1 python3 -I -B -c "import runpy,sys; s=runpy.run_path(sys.argv[1], run_name='probe'); print(s['index_missing'](sys.argv[2]))" "$U" "$1"; }
ok "probe: HTTP 404 is an index that isn't there" '[[ -n $port && $(probe "http://127.0.0.1:$port/development/aarch64/omamobile.db") == True ]]'
ok "probe: an index that is served is there" '[[ $(probe "http://127.0.0.1:$port/stable/aarch64/omamobile.db") == False ]]'
ok "probe: a server error is not an empty channel" '[[ $(probe "http://127.0.0.1:$port/broken/aarch64/omamobile.db") == False ]]'
kill "$www" 2>/dev/null; wait "$www" 2>/dev/null
ok "probe: no answer (offline) is not an empty channel" '[[ $(probe "http://127.0.0.1:$port/development/aarch64/omamobile.db") == False ]]'
rm -f "$t/sync-fail" "$t/index-answer" "$t/probes"

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
for c in omarchy-snapshot omarchy-update-aur-pkgs omarchy-update-orphan-pkgs omarchy-migrate omarchy-update-restart omarchy-update-boot sudo; do
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

# The kernel package with a slot B the hook would refuse: refused after sudo,
# before Omarchy's update; with a ready one the update runs
printf 'omarchy 4.0.5-1\nlinux-omamobile 7.3.0rc6.r453.g0123456789ab-1\n' >"$t/plan"
echo '{"auto_write": "yes", "ok": false, "problem": "this board is another phone"}' >"$t/preflight"
rm -f "$t/sudo-ok"; : >"$calls"
printf '1234\n' | python3 -I "$U" start >/dev/null; wait_done
ok "kernel, slot B not ready: Omarchy's update never ran" '! grep -c "^omarchy-update" "$calls" >/dev/null'
ok "kernel, slot B not ready: result refused, naming the reason" 'python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"refused\" and \"another phone\" in d[\"message\"], d"'
echo '{"auto_write": "yes", "ok": true, "problem": ""}' >"$t/preflight"
rm -f "$t/sudo-ok"; : >"$calls"
printf '1234\n' | python3 -I "$U" start >/dev/null; wait_done
ok "kernel, slot B ready: the update runs" 'grep -c "^omarchy-update -y" "$calls" >/dev/null && python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"ok\", d"'
ok "kernel, slot B ready: the run says the hook writes it" 'grep -c "its pacman hook writes it to slot B" "$HOME/.local/state/omamobile/update/update.log" >/dev/null'
printf 'omarchy 4.0.5-1\nmesa 26.1-1\n' >"$t/plan"

# The restart step reads the boot-update hook's result from this update only
rs() { rm -rf "$t/rs"; OMAMOBILE_UPDATE_DIR=$t/rs OMAMOBILE_BOOT_UPDATE_STATUS=$t/bu.json OMAMOBILE_UPDATE_STARTED=$1 bash lib/update-bin/omarchy-update-restart >/dev/null 2>&1; cat "$t/rs/restart.json"; }
now=$(date +%s)
printf '{"result": "written", "release": "7.3.0-rc6-omamobile-g0123456789ab", "kernel_changed": true, "message": "x", "time": %d}\n' "$now" >"$t/bu.json"
out=$(rs $((now - 5)))
ok "restart: slot B written during the update asks for a restart" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d[\"needs_reboot\"] and \"kernel was updated\" in d[\"reasons\"][0] and \"7.3.0-rc6-omamobile-g0123456789ab\" in d[\"reasons\"][0], d" "$out"'
printf '{"result": "written", "release": "7.3.0-rc6-omamobile-g0123456789ab", "kernel_changed": false, "message": "x", "time": %d}\n' "$now" >"$t/bu.json"
out=$(rs $((now - 5)))
ok "restart: a rewrite of the running kernel's set says boot images, not kernel" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d[\"needs_reboot\"] and \"boot images were updated\" in d[\"reasons\"][0] and not any(\"kernel was updated\" in r for r in d[\"reasons\"]), d" "$out"'
out=$(rs $((now + 60)))
ok "restart: a result from before this update is ignored" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"needs_reboot\"], d" "$out"'
printf '{"result": "refused", "release": "", "message": "battery at 12%%", "time": %d}\n' "$now" >"$t/bu.json"
out=$(rs $((now - 5)))
ok "restart: a kernel the hook could not write is a warning, not a restart" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"needs_reboot\"] and any(\"battery at 12%\" in w and \"omamobile-boot-update write\" in w for w in d[\"warnings\"]), d" "$out"'
printf '{"result": "skipped", "release": "", "message": "AUTO_WRITE is off", "time": %d}\n' "$now" >"$t/bu.json"
out=$(rs $((now - 5)))
ok "restart: a skipped write (development phone) asks for nothing" 'python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert not d[\"needs_reboot\"] and not any(\"kernel\" in w for w in d[\"warnings\"]), d" "$out"'

# Omarchy 4.5 runs the restart step in two halves. The first restarts the
# marked services and the shell and decides nothing; the second decides and
# restarts nothing, and still knows which service failed to restart
half() { OMAMOBILE_UPDATE_DIR=$t/rs OMAMOBILE_BOOT_UPDATE_STATUS=$t/bu.json OMAMOBILE_UPDATE_STARTED=$((now - 5)) bash lib/update-bin/omarchy-update-restart "$@" >/dev/null 2>&1; }
printf '{"result": "written", "release": "7.3.0-rc6-omamobile-g0123456789ab", "kernel_changed": true, "message": "x", "time": %d}\n' "$now" >"$t/bu.json"
mkdir -p "$HOME/.local/state/omarchy"
touch "$HOME/.local/state/omarchy/restart-waybar-required" "$HOME/.local/state/omarchy/restart-broken-required"
rm -rf "$t/rs"; : >"$calls"
half --services-only
ok "restart, first half: the marked service and the shell restart, once each" '[[ $(grep -c "^restart-waybar$" "$calls") == 1 && $(grep -c "^restart-shell$" "$calls") == 1 ]]'
ok "restart, first half: no verdict yet" '[[ ! -e $t/rs/restart.json ]]'
: >"$calls"
half --reboot-only
ok "restart, second half: nothing restarts again" '! grep -c "^restart-" "$calls" >/dev/null'
ok "restart, second half: the verdict, with the first half's failed service as a warning" 'python3 -c "import json; d=json.load(open(\"$t/rs/restart.json\")); assert d[\"needs_reboot\"] and \"kernel was updated\" in d[\"reasons\"][0] and d[\"warnings\"] == [\"Restarting broken failed\"], d"'
half --reboot-only
ok "restart, second half alone: no warning left over from an earlier run" 'python3 -c "import json; d=json.load(open(\"$t/rs/restart.json\")); assert d[\"warnings\"] == [], d"'
rc=0; half --sideways || rc=$?
ok "restart: an option it doesn't know is refused" '[[ $rc == 2 ]]'
: >"$calls"; rm -rf "$t/rs"
half
ok "restart, no argument (Omarchy 4.0): both halves in one run" 'grep -c "^restart-shell$" "$calls" >/dev/null && [[ -e $t/rs/restart.json ]]'
rc=0; out=$(bash lib/update-bin/omarchy-update-boot 2>&1) || rc=$?
ok "boot check (Omarchy 4.5): the phone's stand-in passes, silently, without sudo" '[[ $rc == 0 && -z $out ]]'
rc=0; bash lib/update-bin/omarchy-update-boot extra 2>/dev/null || rc=$?
ok "boot check: an argument is refused as Omarchy's is" '[[ $rc == 2 ]]'
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

# The update on a channel with nothing published yet: done with nothing to
# do (exit 0, result ok), Omarchy's update not started; with the index there,
# the same failed check is still a refusal
printf "error: failed retrieving file 'omamobile.db' from pkgs.omamobile.org : The requested URL returned error: 404\n" >"$t/sync-fail"
echo missing >"$t/index-answer"; : >"$calls"
out=$(python3 -I "$U" -y </dev/null 2>&1); rc=$?
ok "empty channel, terminal run: exit 0 and says the channel has no updates yet" '[[ $rc == 0 ]] && grep -c "omamobile-update: The stable channel has no updates yet" <<<"$out" >/dev/null'
ok "empty channel, terminal run: Omarchy's update never started" '! grep -c "^omarchy-update" "$calls" >/dev/null'
ok "empty channel, terminal run: result ok, marked channel_empty, no restart" 'python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"ok\" and d[\"exit\"] == 0 and d[\"channel_empty\"] is True and not d[\"needs_reboot\"], d"'
rm -f "$t/sudo-ok"
printf '1234\n' | python3 -I "$U" start >/dev/null; wait_done
ok "empty channel, the sheet's run: result ok with the same message" 'python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"ok\" and \"no updates yet\" in d[\"message\"], d"'
echo present >"$t/index-answer"; touch "$t/sudo-ok"; : >"$calls"
out=$(python3 -I "$U" -y </dev/null 2>&1); rc=$?
ok "a failed check with the index there: the update is refused (exit 5), as before" '[[ $rc == 5 ]] && ! grep -c "^omarchy-update" "$calls" >/dev/null && python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"refused\" and \"channel_empty\" not in d, d"'
rm -f "$t/sync-fail" "$t/index-answer" "$t/probes"
touch "$t/sudo-ok"; : >"$calls"
out=$(python3 -I "$U" -y </dev/null 2>&1); rc=$?
ok "the update after an empty-channel run is an ordinary one again" '[[ $rc == 0 ]] && grep -c "^omarchy-update" "$calls" >/dev/null && python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"message\"] == \"Updated\" and \"channel_empty\" not in d, d"'
touch "$t/sudo-ok"
out=$(FAKE_UPDATE_RC=6 python3 -I "$U" -y </dev/null 2>&1); rc=$?
ok "Omarchy's update stopping with exit 6 later is a failure, not an empty channel" '[[ $rc == 6 ]] && python3 -c "import json; d=json.load(open(\"$last\")); assert d[\"result\"] == \"failed\" and \"channel_empty\" not in d, d"'

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

# A root login over SSH (or a TTY) has no Omarchy session environment, and
# Omarchy's update scripts read OMARCHY_PATH under set -u: it still arrives
: >"$calls"
rc=0; out=$(printf '1234\n' | env -u OMARCHY_PATH python3 -I "$U" start) || rc=$?
ok "no OMARCHY_PATH in the environment: the update starts (exit 0, '$out')" '[[ $rc == 0 && $out == started ]]'
wait_done
ok "no OMARCHY_PATH in the environment: omarchy-update still gets Omarchy's (omarchy-update-dev)" 'grep -c "^omarchy-update OMARCHY_PATH=/usr/share/omarchy$" "$calls" >/dev/null'

# As root (a root login over SSH, 2026-11-09) Omarchy's per-user migration
# record is empty and every migration ran again as root: refused, nothing runs
: >"$calls"
for c in run start run-migration; do
  rc=0; out=$(printf '1234\n' | OMAMOBILE_UPDATE_TEST_EUID=0 python3 -I "$U" $c 2>&1) || rc=$?
  ok "as root: $c refused (exit 5) and says why" '[[ $rc == 5 && $out == *"not as root"* ]]'
done
ok "as root: nothing reached omarchy-update or sudo" '[[ ! -s $calls ]]'
rc=0; OMAMOBILE_UPDATE_TEST_EUID=0 python3 -I "$U" check --json >/dev/null || rc=$?
ok "as root: check still answers (read-only, exit $rc)" '[[ $rc == 0 || $rc == 1 ]]'

exit $((failures > 0))
