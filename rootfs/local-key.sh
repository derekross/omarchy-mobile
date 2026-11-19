# SPDX-License-Identifier: MIT
# A contributor's local key in a --local root image. Sourced by
# rootfs/build-inside; tests/rootfs-local-key runs it on a stand-in root.
#
# A local channel's repository is signed with the contributor's local key
# (tools/local-key-init), which the build trusts only in its own keyring,
# and build-inside removes that keyring from the image. The key ships as a
# keyring of its own (omamobile-local), so firstboot's pacman-key --populate
# trusts it on the phone too; without it every refresh failed at
# [omamobile] with "key ... is unknown", and omarchy update with it (hotdog,
# 2026-11-04). Only an image of the local channel with a key gets it: a
# stable or development image (CHANNEL), or a local one built without a
# key, gets nothing, whatever LOCAL_KEY says.
#
#   ship_local_key ROOT CHANNEL KEY_FILE    prints the fingerprint it shipped

ship_local_key() {
  local root=$1 channel=$2 key=${3:-} fpr
  [[ $channel == local && -n $key ]] || return 0
  [[ -f $key ]] || { printf 'error: no local key %s\n' "$key" >&2; return 1; }
  fpr=$(gpg --show-keys --with-colons "$key" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}')
  [[ $fpr =~ ^[0-9A-F]{40}$ ]] || { printf 'error: no key fingerprint in %s\n' "$key" >&2; return 1; }
  install -Dm644 "$key" "$root/usr/share/pacman/keyrings/omamobile-local.gpg"
  printf '%s:4:\n' "$fpr" > "$root/usr/share/pacman/keyrings/omamobile-local-trusted"
  chmod 644 "$root/usr/share/pacman/keyrings/omamobile-local-trusted"
  printf '%s\n' "$fpr"
}
