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
#
# Nothing here reads, prints or copies secret key material.

signing_key_load() {
  local root=${1:?signing_key_load needs the repository root}
  local home=$root/keys/gnupg.release file=$root/keys/fingerprint.release
  local keyring=$root/packages/omamobile-keyring fpr
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
  if ! cut -d: -f1 "$keyring/omamobile-trusted" 2>/dev/null | grep -qx "$fpr"; then
    echo "error: omamobile-keyring does not trust $fpr (keys/fingerprint.release): phones would refuse what it signs" >&2
    return 1
  fi
  if cut -d: -f1 "$keyring/omamobile-revoked" 2>/dev/null | grep -qx "$fpr"; then
    echo "error: $fpr (keys/fingerprint.release) is revoked in omamobile-keyring" >&2
    return 1
  fi
  export GNUPGHOME=$home
  SIGNING_KEY=$fpr
}
