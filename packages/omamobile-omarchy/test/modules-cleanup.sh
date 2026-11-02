#!/bin/bash
# SPDX-License-Identifier: MIT
# lib/modules-cleanup against a scratch module root: fake trees with set
# mtimes, a stub uname and pacman on PATH, and a fake /proc/stat for the boot
# time. Run from the package directory (test/all does).
set -euo pipefail
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
tool=$PWD/lib/modules-cleanup
mkdir -p "$t/bin"
cat > "$t/bin/uname" <<'EOF'
#!/bin/bash
[[ ${1:-} == -r ]] && { echo 7.3.0-running; exit 0; }
exec /usr/bin/uname "$@"
EOF
# Owns 6.0.0-pkg and nothing else; -Qq lists packages
cat > "$t/bin/pacman" <<'EOF'
#!/bin/bash
case $1 in
  -Qq) echo linux; exit 0 ;;
  -Qqo) [[ ${@: -1} == */6.0.0-pkg ]] && { echo linux; exit 0; }
        echo "error: No package owns ${@: -1}" >&2; exit 1 ;;
esac
exit 1
EOF
chmod +x "$t/bin/uname" "$t/bin/pacman"
cp "$t/bin/pacman" "$t/pacman.good"

boot=$(( $(date +%s) - 3600 ))   # the trees' times count back from here

# tree NAME AGE_BEFORE_BOOT_SECONDS [marker]: a tree whose files and marker
# carry that time.
tree() {
  local d=$t/root/$1 when=$(( boot - $2 ))
  mkdir -p "$d/kernel"
  echo x > "$d/kernel/a.ko"
  [[ ${3:-} == marker ]] && echo sha > "$d/.omamobile-tarball"
  find "$d" -mindepth 1 -exec touch -h -d "@$when" {} +
  touch -d "@$when" "$d"
}
setup() {
  rm -rf "$t/root"; mkdir -p "$t/root"
  tree 7.3.0-running 90000 marker
  tree 7.3.0-pushed 99999 marker              # the marker is rewritten below
  tree 6.0.0-pkg 99999
  tree 7.2.0-new1 1000 marker
  tree 7.2.0-new2 2000                        # no marker: the tree's mtime
  tree 7.1.0-old1 3000 marker
  tree 7.0.0-old2 4000 marker
  mkdir -p "$t/root/.old/6.9.0-moved" "$t/root/.7.4.0.new/7.4.0"
  mkdir -p "$t/outside/6.8.0-target/kernel"
  ln -s "$t/outside/6.8.0-target" "$t/root/6.8.0-link"
  echo keep > "$t/outside/6.8.0-target/kernel/b.ko"
}
# ctime can't be set, and every scratch tree's is "now", so each run boots
# one second from now: no ctime counts as "arrived during this boot", and
# the pushed tree's marker, 600 s after that boot, does.
run() {
  local b=$(( $(date +%s) + 1 ))
  if [[ -e $t/root/7.3.0-pushed ]]; then touch -d "@$(( b + 600 ))" "$t/root/7.3.0-pushed/.omamobile-tarball"; fi
  printf 'cpu 1 2 3\nbtime %s\nprocesses 1\n' "$b" > "$t/stat"
  PATH=$t/bin:$PATH OMAMOBILE_MODULES_ROOT=$t/root OMAMOBILE_PROC_STAT=$t/stat "$tool" "$@"
}
left() { (cd "$t/root" && ls -A | LC_ALL=C sort | tr '\n' ' '); }

setup
before=$(left)
out=$(OMAMOBILE_MODULES_CLEANUP_DRY_RUN=1 run) || fail "dry run exits 0"
[[ $(left) == "$before" ]] || fail "dry run removes nothing: $(left)"
grep -qxF 'modules-cleanup: would remove 7.1.0-old1 (dry run)' <<<"$out" || fail "dry run names old1: $out"
out=$(run --dry-run) || fail "--dry-run exits 0"
[[ $(left) == "$before" ]] || fail "--dry-run removes nothing"
pass "a dry run names what it would remove and removes nothing"

out=$(run) || fail "cleanup exits 0: $out"
want='.7.4.0.new .old 6.0.0-pkg 6.8.0-link 7.2.0-new1 7.2.0-new2 7.3.0-pushed 7.3.0-running '
[[ $(left) == "$want" ]] || fail "kept set: got '$(left)', want '$want'"
grep -qxF 'modules-cleanup: keep 7.3.0-running: running' <<<"$out" || fail "logs the running tree"
grep -qxF 'modules-cleanup: keep 7.3.0-pushed: arrived during this boot (the next boot'"'"'s kernel)' <<<"$out" \
  || fail "logs the pushed tree"
grep -qxF 'modules-cleanup: keep 6.0.0-pkg: owned by linux' <<<"$out" || fail "logs the owned tree"
grep -q '^modules-cleanup: keep 7.2.0-new1: rollback' <<<"$out" || fail "logs rollback new1"
grep -q '^modules-cleanup: keep 7.2.0-new2: rollback' <<<"$out" || fail "logs rollback new2"
grep -qxF 'modules-cleanup: remove 7.1.0-old1' <<<"$out" || fail "logs the removal of old1"
grep -qxF 'modules-cleanup: remove 7.0.0-old2' <<<"$out" || fail "logs the removal of old2"
pass "keeps running, pushed-this-boot, owned and the two newest; removes the rest"

[[ -d $t/root/.old/6.9.0-moved && -d $t/root/.7.4.0.new/7.4.0 ]] || fail ".old and a push in progress untouched"
[[ -L $t/root/6.8.0-link && -f $t/outside/6.8.0-target/kernel/b.ko ]] || fail "a symlinked tree and its target untouched"
grep -qxF 'modules-cleanup: skip 6.8.0-link: not a directory' <<<"$out" || fail "logs the skipped symlink"
pass "dot-directories, symlinks and what they point to are left alone"

# A removed tree's symlink out of the root is not followed
setup
ln -s "$t/outside" "$t/root/7.0.0-old2/escape"
touch -d "@$(( boot - 4000 ))" "$t/root/7.0.0-old2"
run >/dev/null || fail "cleanup with an escape link"
[[ ! -e $t/root/7.0.0-old2 && -f $t/outside/6.8.0-target/kernel/b.ko ]] || fail "rm follows no symlink inside a removed tree"
pass "a link inside a removed tree is removed, not followed"

# Pacman can't read its database: nothing goes
setup
cat > "$t/bin/pacman" <<'EOF'
#!/bin/bash
exit 1
EOF
before=$(left)
run >/dev/null 2>&1 && fail "fails without pacman's database"
[[ $(left) == "$before" ]] || fail "nothing removed without pacman's database"
pass "without pacman's database nothing is removed"

# The incident's case: pushed in an earlier boot, so only .omamobile-next or
# its rank protects it, and here its marker was written under a 1970 clock
cp "$t/pacman.good" "$t/bin/pacman"
setup
rm -rf "$t/root/7.3.0-pushed"
tree 7.4.0-next 99999 marker
touch -h -d @100000 "$t/root/7.4.0-next/.omamobile-tarball" "$t/root/7.4.0-next"
echo 7.4.0-next > "$t/root/.omamobile-next"
out=$(run) || fail "cleanup with .omamobile-next"
[[ -d $t/root/7.4.0-next ]] || fail "the release named in .omamobile-next is kept: $out"
grep -qxF 'modules-cleanup: keep 7.4.0-next: pushed for the next boot (.omamobile-next)' <<<"$out" || fail "logs the next-boot tree: $out"
[[ -d $t/root/7.2.0-new1 && -d $t/root/7.2.0-new2 && ! -e $t/root/7.1.0-old1 ]] || fail "the rollback ranking is unchanged: $(left)"
pass "the release modules-push named for the next boot is kept, even pushed in an earlier boot"

setup
rm -rf "$t/root/7.3.0-pushed"
tree 7.4.0-reset 99999 marker
touch -h -d @100000 "$t/root/7.4.0-reset/.omamobile-tarball" "$t/root/7.4.0-reset"
out=$(run) || fail "cleanup with a 1970 stamp"
[[ -d $t/root/7.4.0-reset ]] || fail "a tree stamped before 2026 is kept: $out"
grep -qxF 'modules-cleanup: keep 7.4.0-reset: its time is before 2026 (a reset clock), so its age is unknown' <<<"$out" || fail "logs the reset-clock tree"
pass "a tree stamped under a reset clock is kept, not ranked oldest"

# An empty root and a missing one are fine
cp "$t/pacman.good" "$t/bin/pacman"
rm -rf "$t/root"; mkdir -p "$t/root"
run >/dev/null || fail "empty root"
rm -rf "$t/root"
run >/dev/null || fail "missing root"
pass "an empty or missing module root is not an error"
