# SPDX-License-Identifier: MIT
# The key the maintainer's builds sign with (docs/RELEASES.md §10): the
# release key's signing subkey, alone and without a passphrase, in
# keys/gnupg.release, and its primary's fingerprint in keys/fingerprint.release
# (both made once by tools/release-key-init). tools/build-packages,
# tools/repo-build, tools/make-bundle and tools/repo-publish use it. The
# original key in keys/gnupg no longer signs anything; phones keep trusting it
# (omamobile-keyring) until a keyring update moves it to omamobile-revoked.
#
# Contributors' ports never come here: they sign with their own key in
# keys/<codename>/ (tools/local-key-init, --local).
#
#   source tools/lib/signing.sh
#   signing_key_load ROOT || exit 1
#     exports GNUPGHOME=ROOT/keys/gnupg.release and sets SIGNING_KEY to the
#     primary's fingerprint, after checking that omamobile-keyring trusts it
#     and hasn't revoked it; on failure says why on stderr and returns 1.
#   revoked_file_check ROOT || ...
#     checks ROOT/packages/omamobile-keyring/omamobile-revoked as a whole, in
#     the form docs/RELEASES.md §10 gives: empty, or one 40-digit fingerprint
#     in capitals on every line, each ending with a newline. If not, prints
#     why, naming the first wrong line, and returns 1; the same if it can't
#     be read as a file (a missing one revokes nothing).
#     signing_key_load and tools/release-upload run it before they read a
#     line of the file.
#
# Nothing here reads, prints or copies secret key material.

revoked_file_check() {
  local file=$1/packages/omamobile-keyring/omamobile-revoked bad= end= lines=0 rc=2
  # Missing: nothing revoked, as before. A link to nowhere is not missing.
  [[ -e $file || -L $file ]] || return 0
  # The first line that isn't a fingerprint (grep exits 1 when there is
  # none), else a last line without its newline. What isn't a regular file,
  # and any read here that fails, is refused, never taken as listing nothing.
  if [[ -f $file ]]; then
    rc=0
    bad=$(LC_ALL=C grep -anvxE -m1 '[0-9A-F]{40}' -- "$file" | cut -d: -f1
          exit $((PIPESTATUS[1] ? 2 : PIPESTATUS[0]))) || rc=$?
  fi
  if ((rc == 1)); then
    end=$(tail -c1 -- "$file") && lines=$(wc -l < "$file") && rc=0 || rc=2
    [[ -z $end ]] || bad=$((lines + 1))
  fi
  if ((rc)); then
    echo "packages/omamobile-keyring/omamobile-revoked cannot be read: it must be a file this user can read (docs/RELEASES.md §10)"
    return 1
  fi
  [[ -n $bad ]] || return 0
  echo "packages/omamobile-keyring/omamobile-revoked is malformed at line $bad: each line must be one 40-digit fingerprint in capitals, ending with a newline (docs/RELEASES.md §10)"
  return 1
}

signing_key_load() {
  local root=${1:?signing_key_load needs the repository root}
  local home=$root/keys/gnupg.release file=$root/keys/fingerprint.release
  local keyring=$root/packages/omamobile-keyring fpr why
  if [[ ! -d $home || ! -f $file ]]; then
    {
      echo "error: no release signing key: keys/gnupg.release and keys/fingerprint.release are missing."
      echo "  Maintainer only: tools/release-key-init makes them once (docs/RELEASES.md §10)."
      echo "  The original key in keys/gnupg no longer signs. A contributor's port builds with"
      echo "  --local CODENAME and its own key (tools/local-key-init CODENAME)."
    } >&2
    return 1
  fi
  fpr=$(tr -d '[:space:]' < "$file")
  if [[ ! $fpr =~ ^[0-9A-F]{40}$ ]]; then
    echo "error: keys/fingerprint.release does not hold a 40-digit fingerprint" >&2
    return 1
  fi
  if ! cut -d: -f1 "$keyring/omamobile-trusted" 2>/dev/null | grep -cx "$fpr" >/dev/null; then
    echo "error: omamobile-keyring does not trust $fpr (keys/fingerprint.release): phones would refuse what it signs" >&2
    return 1
  fi
  if ! why=$(revoked_file_check "$root"); then
    echo "error: $why" >&2
    return 1
  fi
  if cut -d: -f1 "$keyring/omamobile-revoked" 2>/dev/null | grep -cx "$fpr" >/dev/null; then
    echo "error: $fpr (keys/fingerprint.release) is revoked in omamobile-keyring" >&2
    return 1
  fi
  export GNUPGHOME=$home
  SIGNING_KEY=$fpr
}
