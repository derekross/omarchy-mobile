#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/apps.sh on a scratch HOME and XDG_DATA_DIRS, with stub pacman and gtk-launch on PATH: the same filters as
# Omarchy's hidden-entries.sh, the first file of an ID wins, launcher.hides, sorting, escaping, the cache, info, open.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
tmp=$(cd -P -- "$tmp" && pwd -P)
H=$tmp/home S1=$tmp/sys1 S2=$tmp/sys2
mkdir -p "$H/.local/share/applications" "$S1/applications/sub" "$S2/applications" "$tmp/bin" "$tmp/omarchy/default/omarchy"
entry() { printf '[Desktop Entry]\nType=Application\n%s\n' "$2" > "$1"; }
entry "$S1/applications/zeta.desktop" $'Name=Zeta\nIcon=zeta'
entry "$S1/applications/alpha.desktop" $'Name=alpha "one" \\x\nIcon=/opt/a.png'
entry "$S1/applications/nodisp.desktop" $'Name=NoDisp\nNoDisplay=true'
entry "$S1/applications/hidden.desktop" $'Name=Hid\nHidden=true'
entry "$S1/applications/kde.desktop" $'Name=KdeOnly\nOnlyShowIn=KDE;'
entry "$S1/applications/hypr.desktop" $'Name=HyprOnly\nOnlyShowIn=GNOME;Hyprland;'
entry "$S1/applications/nothypr.desktop" $'Name=NotHypr\nNotShowIn=Hyprland;'
entry "$S1/applications/noname.desktop" 'Icon=x'
entry "$S1/applications/sub/nested.desktop" 'Name=Nested'
entry "$S1/applications/hideme.desktop" 'Name=HideMe'
entry "$S1/applications/shadow.desktop" 'Name=Shadow system'
entry "$S2/applications/shadow.desktop" 'Name=Shadow later dir'
entry "$S1/applications/useroff.desktop" 'Name=UserOff system'
entry "$H/.local/share/applications/useroff.desktop" $'Name=UserOff\nNoDisplay=true'
# a NoDisplay key outside [Desktop Entry] does not count, a Name in an action group neither
printf '[Desktop Entry]\nName=Acts\n[Desktop Action new]\nName=New window\nNoDisplay=true\n' > "$S1/applications/acts.desktop"
# a tab in the name, a file called just ".desktop", a symlinked entry, an ID with a space, a dangling symlink
entry "$S1/applications/tab.desktop" $'Name=Tab\tbed'
entry "$S1/applications/.desktop" 'Name=Empty id'
entry "$tmp/real-link.desktop" 'Name=Linked'
ln -s "$tmp/real-link.desktop" "$S1/applications/linked.desktop"
ln -s "$tmp/nowhere.desktop" "$S1/applications/dangling.desktop"
entry "$S1/applications/My App.desktop" 'Name=My App'
printf 'hideme.desktop\n\n' > "$tmp/omarchy/default/omarchy/launcher.hides"
cat > "$tmp/bin/pacman" <<'EOT'
#!/bin/bash
[[ $LC_ALL == C ]] || { echo "no LC_ALL=C" >&2; exit 1; }
case $1 in
  -Qqo) [[ $2 == -- && $3 == */sys1/applications/zeta.desktop ]] && { echo zeta-pkg; exit 0; }; echo "error: No package owns $3" >&2; exit 1 ;;
  -Qi) [[ $2 == -- && $3 == zeta-pkg ]] || exit 1
       printf 'Name            : zeta-pkg\nVersion         : 1.2-3\nDescription     : Zeta\nInstalled Size  : 4.50 MiB\n' ;;
  *) echo "unexpected pacman: $*" >&2; exit 1 ;;
esac
EOT
cat > "$tmp/bin/gtk-launch" <<'EOT'
#!/bin/bash
printf '%s\n' "$*" > "$LAUNCHED"
EOT
chmod +x "$tmp/bin/pacman" "$tmp/bin/gtk-launch"
# OMAMOBILE_LAUNCH points at a stub, or at nothing, so the real /usr/bin/omamobile-launch is never used
cat > "$tmp/omamobile-launch" <<'EOT'
#!/bin/bash
printf 'oml %s\n' "$*" > "$LAUNCHED"
EOT
chmod +x "$tmp/omamobile-launch"
LAUNCH=$tmp/no-omamobile-launch
run() { env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$H" XDG_DATA_DIRS="$S1:$S2" XDG_CACHE_HOME="$tmp/cache" XDG_CURRENT_DESKTOP=Hyprland \
  OMARCHY_PATH="$tmp/omarchy" LAUNCHED="$tmp/launched" OMAMOBILE_LAUNCH="$LAUNCH" bash -p "$src/backends/apps.sh" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

out=$(run cached); [[ $out == '{"apps":null}' ]] || fail "cached before a list: $out"
out=$(run list)
ids=$(python3 -I -c 'import json,sys; print(" ".join(a["id"] for a in json.loads(sys.argv[1])["apps"]))' "$out")
# by name: Nested before noname
[[ $ids == "acts alpha hypr linked My App sub-nested noname shadow tab zeta" ]] || fail "list ids: $ids"
python3 -I - "$out" <<'EOF' || fail "list fields: $out"
import json, sys
apps = {a["id"]: a for a in json.loads(sys.argv[1])["apps"]}
assert apps["alpha"]["name"] == 'alpha "one" \\x' and apps["alpha"]["icon"] == "/opt/a.png"
assert apps["noname"]["name"] == "noname"            # no Name=: the ID
assert apps["shadow"]["name"] == "Shadow system"     # the first data dir wins
assert apps["acts"]["name"] == "Acts"                # action groups are not read
assert apps["sub-nested"]["name"] == "Nested"
assert apps["tab"]["name"] == "Tabbed"               # control characters dropped
assert apps["My App"]["open"] is False and apps["zeta"]["open"] is True
assert json.loads(sys.argv[1])["partial"] is False
EOF
[[ $(run cached) == "$out" ]] || fail "cached is not the last list"
ln -sf /etc/passwd "$tmp/cache/omamobile/apps.json.lnk"; mv -f "$tmp/cache/omamobile/apps.json.lnk" "$tmp/cache/omamobile/apps.json"
[[ $(run cached) == '{"apps":null}' ]] || fail "cached follows a symlink"

out=$(run info zeta)
[[ $out == '{"id":"zeta","name":"Zeta","icon":"zeta","path":"'"$S1"'/applications/zeta.desktop","package":"zeta-pkg","version":"1.2-3","size":"4.50 MiB"}' ]] || fail "info zeta: $out"
out=$(run info alpha); [[ $out == *'"package":null,"version":null,"size":null}' ]] || fail "info of an unowned entry: $out"
for id in nodisp hidden kde nothypr hideme useroff nosuch; do
  out=$(run info "$id" || true); [[ $out == '{"error":"no such app"}' ]] || fail "info $id: $out"
done
for id in ../zeta -zeta .zeta a/b a..b 'a b' 'My App' ''; do
  out=$(run info "$id" || true); [[ $out == '{"error":"bad app id"}' ]] || fail "bad id $id accepted: $out"
done
out=$(run info linked); [[ $out == *'"name":"Linked"'* ]] || fail "info of a symlinked entry: $out"
out=$(run list extra || true); [[ $out == *usage* ]] || fail "extra argument accepted"

launched() { for _ in $(seq 50); do [[ -s $tmp/launched ]] && break; sleep 0.1; done; cat "$tmp/launched" 2> /dev/null || true; }
# omamobile-launch when it is there
rm -f "$tmp/launched"; LAUNCH=$tmp/omamobile-launch
out=$(run open zeta); [[ $out == '{"ok":true}' ]] || fail "open: $out"
[[ $(launched) == "oml app zeta" ]] || fail "omamobile-launch not called with the ID: $(launched)"
# gtk-launch without it
rm -f "$tmp/launched"; LAUNCH=$tmp/no-omamobile-launch
out=$(run open zeta); [[ $out == '{"ok":true}' ]] || fail "open via gtk-launch: $out"
[[ $(launched) == zeta ]] || fail "gtk-launch not called with the ID"
# neither: an error, not {"ok":true}
# (only where the system has no gtk-launch of its own on /usr/bin:/bin)
if [[ ! -e /usr/bin/gtk-launch && ! -e /bin/gtk-launch ]]; then
  mv "$tmp/bin/gtk-launch" "$tmp/gtk-launch.off"
  out=$(run open zeta || true); [[ $out == '{"error":"no app launcher found"}' ]] || fail "open with no launcher: $out"
  mv "$tmp/gtk-launch.off" "$tmp/bin/gtk-launch"
fi
# a launcher that is not executable is not used
chmod -x "$tmp/omamobile-launch"; rm -f "$tmp/launched"; LAUNCH=$tmp/omamobile-launch
out=$(run open zeta); [[ $out == '{"ok":true}' && $(launched) == zeta ]] || fail "non-executable omamobile-launch used: $out"
chmod +x "$tmp/omamobile-launch"; LAUNCH=$tmp/no-omamobile-launch
out=$(run open nodisp || true); [[ $out == '{"error":"no such app"}' ]] || fail "opened a hidden entry: $out"
# a huge list is cut below the 64 KiB the app reads, and says so
mkdir -p "$tmp/big/applications"
for i in $(seq 700); do printf '[Desktop Entry]\nName=App %04d with a fairly long name to fill the answer quickly\n' "$i" > "$tmp/big/applications/org.example.App$i.desktop"; done
out=$(env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$H" OMARCHY_PATH="$tmp/omarchy" XDG_DATA_DIRS="$tmp/big" XDG_CACHE_HOME="$tmp/cache2" bash -p "$src/backends/apps.sh" list)
(( ${#out} < 65536 )) || fail "list is ${#out} bytes"
python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["partial"] is True and 100 < len(d["apps"]) < 700' "$out" || fail "big list not cut cleanly"
# XDG_DATA_HOME is the user dir (as in omamobile-launch); a symlinked applications dir is followed
mkdir -p "$tmp/dh/real"; entry "$tmp/dh/real/dhapp.desktop" 'Name=DataHomeApp'
mkdir -p "$tmp/dh2"; ln -s "$tmp/dh/real" "$tmp/dh2/applications"
out=$(env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$H" OMARCHY_PATH="$tmp/omarchy" XDG_DATA_HOME="$tmp/dh2" XDG_DATA_DIRS="$tmp/none" XDG_CACHE_HOME="$tmp/cache3" bash -p "$src/backends/apps.sh" list)
[[ $out == *'"id":"dhapp"'* ]] || fail "XDG_DATA_HOME / symlinked dir not read: $out"
# a huge Name= cannot push the sort key (and the row) over the budget
mkdir -p "$tmp/huge/applications"
{ printf '[Desktop Entry]\nName='; head -c 100000 /dev/zero | tr '\0' x; printf '\n'; } > "$tmp/huge/applications/huge.desktop"
out=$(env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$H" OMARCHY_PATH="$tmp/omarchy" XDG_DATA_DIRS="$tmp/huge" XDG_CACHE_HOME="$tmp/cache4" bash -p "$src/backends/apps.sh" list)
python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); assert len(sys.argv[1]) < 1000 and d["partial"] is False and len(d["apps"]) == 1' "$out" || fail "huge name: ${#out} bytes"
echo "apps backend: ok"
