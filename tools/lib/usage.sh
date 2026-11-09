# SPDX-License-Identifier: MIT
# A tool's --help from its own header comment: the comment lines from line 3
# (after the shebang and the SPDX line) up to the first line that isn't a
# comment. The range comes from the file, so it can't drift from the header
# the way hard-coded line ranges did (#287): a header that gained a line cut
# its last one, and one that lost a line printed code. Tools load it only
# for --help, so a copy of a tool runs without it; the ones the bundle
# ships alone (install-phone, phone-provision, nv-backup) keep the same awk
# line inline. tests/tools-help checks them all.
#
#   source tools/lib/usage.sh
#   usage_from_header [--raw] FILE [PARAGRAPHS]
#     prints the header of the tool named FILE, in the tools directory
#     above this file, with each line's "#" and one space after it taken
#     off (--raw keeps them). With PARAGRAPHS, only that many paragraphs of
#     it (a bare "#" line ends one), for a tool whose help is the first part
#     of a longer header.
#
# Only FILE's name is used. A tool that cds to the repository first and
# passes "$0" passes a path relative to the directory it left
# (`cd ..; omarchy-mobile/tools/build-packages --help`, #559), while this
# file's own path is still good: the tool has just sourced it from where it
# is now.

usage_from_header() {
  local raw=0
  [[ ${1:-} == --raw ]] && { raw=1; shift; }
  local name=${1:?usage_from_header FILE [PARAGRAPHS]}
  awk -v raw="$raw" -v paras="${2:-0}" '
    NR <= 2 { next }
    !/^#/ { exit }
    /^#[ \t]*$/ && ++blank == paras { exit }
    { if (!raw) sub(/^# ?/, ""); print }' "$(dirname -- "${BASH_SOURCE[0]}")/../${name##*/}"
}
