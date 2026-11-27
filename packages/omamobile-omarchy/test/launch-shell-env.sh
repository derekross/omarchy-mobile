#!/bin/bash
# SPDX-License-Identifier: MIT
# Patch 0034 against the real omarchy-launch-shell (OMARCHY_PKG_ROOT, an
# extracted omarchy package), run against a fake systemd-cat and quickshell:
# the device's NAME=value lines reach the shell process literally (comments,
# blank lines and bad names skipped, a last line without a newline kept,
# nothing expanded or run), Omarchy's own variables and arguments are kept,
# and with no file the shell starts as before.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
package_root=${OMARCHY_PKG_ROOT:?an extracted omarchy package}
src=$package_root/usr/share/omarchy
[[ -f $package_root/.PKGINFO ]] || fail "the extracted package has no .PKGINFO version"
version=$(sed -n 's/^pkgver = //p' "$package_root/.PKGINFO")
case $version in
  4.5.0-*) ;;
  *) pass "the shell's device environment (0034) # SKIP not in the $version family"; exit 0 ;;
esac
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

mkdir -p "$t/omarchy/bin" "$t/fake" "$t/home" "$t/env.d" "$t/empty.d"
cp "$src/bin/omarchy-launch-shell" "$t/omarchy/bin/"
(cd "$t/omarchy" && patch -p1 --fuzz=0 -s) <patches/0034-launch-shell-a-device-environment-for-the-shell.patch \
  || fail "0034 applies to the real omarchy-launch-shell"
launch=$t/omarchy/bin/omarchy-launch-shell

# systemd-cat runs what follows its "--"; quickshell records its arguments
# and environment, and exits cleanly, which ends the launcher.
cat >"$t/fake/systemd-cat" <<'SH'
#!/bin/bash
while [[ $# -gt 0 && $1 != -- ]]; do shift; done
shift
exec "$@"
SH
cat >"$t/fake/quickshell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OUT.args"
env >"$OUT.env"
SH
chmod +x "$t/fake/"*

cat >"$t/env.d/50-gpu.conf" <<'EOF'
# The GPU workaround
FD_MESA_DEBUG=sysmem

1BAD=no
not a line
SPACED=a b  c
LITERAL=$(touch PWNED) `touch PWNED` $HOME
EOF
printf 'LAST=1' >"$t/env.d/60-last.conf"
printf 'IGNORED=1\n' >"$t/env.d/70-not-conf.txt"

run() {
  (cd "$t" && env -u FD_MESA_DEBUG HOME="$t/home" OMARCHY_PATH=/omarchy OUT="$t/out" \
    OMARCHY_SHELL_ENV_DIR="$1" PATH="$t/fake:$PATH" timeout 10 bash "$launch") || fail "the launcher ends cleanly ($1)"
}

run "$t/env.d"
[[ $(<"$t/out.args") == "-n -p /omarchy/shell" ]] || fail "quickshell's arguments kept ($(<"$t/out.args"))"
e=$t/out.env
grep -qx 'FD_MESA_DEBUG=sysmem' "$e" || fail "the device's variable reaches the shell"
grep -qx 'SPACED=a b  c' "$e" || fail "a value with spaces is kept whole"
grep -qxF 'LITERAL=$(touch PWNED) `touch PWNED` $HOME' "$e" || fail "a value is taken literally"
[[ ! -e $t/PWNED ]] || fail "nothing in a value runs"
grep -qx 'LAST=1' "$e" || fail "a last line without a newline is read"
grep -q '^1BAD=' "$e" && fail "a line whose name isn't a variable name is skipped"
grep -q '^IGNORED=' "$e" && fail "only *.conf files are read"
for v in QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1; do
  grep -qx "$v" "$e" || fail "Omarchy's own $v kept"
done
grep -q '^OMARCHY_STARTUP_BACKGROUND=' "$e" || fail "Omarchy's startup background variable kept"
pass "the shell's device environment reaches it literally (0034)"

rm -f "$t/out."*
run "$t/empty.d"
grep -q '^FD_MESA_DEBUG=' "$t/out.env" && fail "without a device file nothing is added"
grep -qx 'QS_DISABLE_FILE_WATCHER=1' "$t/out.env" || fail "without a device file the launch is as before"
rm -f "$t/out."*
run "$t/missing.d"
[[ -s $t/out.env ]] || fail "a missing directory still starts the shell"
pass "without a device file the shell starts as before (0034)"
