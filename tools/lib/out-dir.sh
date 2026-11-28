# SPDX-License-Identifier: MIT
# Resolve an extractor's -o output directory and refuse any path that resolves
# to / (including a symlink or a bind mount of /). tools/extract-vendor-firmware,
# tools/extract-vendor-chroot and tools/extract-fingerprint-vendor source this
# beside their resolved script path; tools/make-bundle ships it at
# tools/lib/out-dir.sh beside them in every release bundle.
#
#   source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib/out-dir.sh" || exit 1
#   resolve_out_dir VAR PATH ROOT_MSG || exit 1
#     resolves PATH byte-for-byte (realpath -mz --, NUL-delimited read, so
#     trailing newlines are kept) and refuses a path that cannot be resolved
#     or resolves to / (-ef /), printing one "error: ..." line on stderr
#     (ROOT_MSG for /) and returning 1. Stores the resolved path in VAR (or
#     discards it when VAR is "-").

resolve_out_dir() {
  local _out_dir_var=${1:?} _out_dir_raw=$2 _out_dir_msg=${3:?} _out_dir_real
  if ! IFS= read -r -d '' _out_dir_real < <(realpath -mz -- "$_out_dir_raw" 2>/dev/null); then
    printf "error: can't resolve -o '%s'\n" "$_out_dir_raw" >&2
    return 1
  fi
  if [[ $_out_dir_real -ef / ]]; then
    printf 'error: %s\n' "$_out_dir_msg" >&2
    return 1
  fi
  [[ $_out_dir_var == - ]] || printf -v "$_out_dir_var" '%s' "$_out_dir_real"
}
