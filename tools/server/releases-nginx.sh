#!/bin/bash
# SPDX-License-Identifier: MIT
# Serve /releases/ on pkgs.omamobile.org for installers and a browser web
# flasher (docs/RELEASES.md §6, §12.7). Run ON THE SERVER, by the maintainer,
# with sudo; it is staged there and never run by tools/release-upload:
#
#   scp -P 1022 tools/server/releases-nginx.sh raven@nostr01.derekross.me:/tmp/
#   ssh -t -p 1022 raven@nostr01.derekross.me 'sudo DRY_RUN=1 bash /tmp/releases-nginx.sh'
#   ssh -t -p 1022 raven@nostr01.derekross.me 'sudo bash /tmp/releases-nginx.sh 2>&1 | tee /tmp/releases-nginx.log'
#   ssh -t -p 1022 raven@nostr01.derekross.me 'sudo bash /tmp/releases-nginx.sh revert'   (undo)
#
#   DRY_RUN=1  print the snippet and the changed vhost, touch nothing
#
# What it changes, and nothing else: writes /etc/nginx/snippets/
# omamobile-releases.conf (one `location ^~ /releases/`) and adds one
# `include` of it to the HTTPS server block of
# /etc/nginx/sites-available/pkgs.omamobile.org, after its request-method rule.
# The rest of the vhost (setup-site.sh, PLAIN_FILES=1, 2026-10-26) stays as
# it is: /releases/ is already plain files (a missing path is a 404, never an
# HTML page), with byte ranges and Content-Length; what it lacks is CORS, the
# right MIME types, exact sizes (no gzip), a long cache for versioned files,
# and a file listing for a folder's own address (a link to
# /releases/<codename>/<version>/ was a 404 for people, 2026-11-10).
#
# Before: backups of both files. After: nginx -t, a reload verified against
# the error log, then live checks over HTTPS (the new headers on /releases/,
# an OPTIONS preflight, and the package repository and the front page still
# answering as before). Any failure restores both files and reloads, so a
# config that fails nginx -t never stays in place (nginx 1.24 here: a bad
# config would only bite at the next restart, and take every site down).
set -euo pipefail

SITE=pkgs.omamobile.org
AVAIL=/etc/nginx/sites-available/$SITE
SNIP=/etc/nginx/snippets/omamobile-releases.conf
HEADERS=/etc/nginx/snippets/security-headers.conf
ELOG=/var/log/nginx/error.log
STAMP=$(date +%Y%m%d-%H%M%S)
DRY_RUN=${DRY_RUN:-0}
INCLUDE="    include $SNIP;"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# The headers every /releases/ response carries. Repeated in each location:
# add_header does not inherit into a location that declares its own.
cors_block() {
  cat <<EOF
        include $HEADERS;
        # Any page may read these files: they're public, signed and
        # checksummed, and a web flasher runs on another origin.
        add_header Access-Control-Allow-Origin   "*" always;
        add_header Access-Control-Allow-Methods  "GET, HEAD, OPTIONS" always;
        add_header Access-Control-Allow-Headers  "Range, If-Range, If-None-Match, If-Modified-Since" always;
        add_header Access-Control-Expose-Headers "Content-Length, Content-Range, Accept-Ranges, ETag" always;
        add_header Access-Control-Max-Age        "86400" always;
        # Fetchable from a cross-origin-isolated page (COEP require-corp)
        add_header Cross-Origin-Resource-Policy  "cross-origin" always;
EOF
}

write_snippet() {
  cat <<EOF
# /releases/ on $SITE: Omarchy Mobile release bundles and root images
# (omarchy-mobile docs/RELEASES.md §6), uploaded by tools/release-upload.
# Written by tools/server/releases-nginx.sh on $STAMP; included from the HTTPS
# server block of $AVAIL.
#
# ^~ keeps the vhost's regex locations (the .json cache rule among them) out
# of /releases/, so this block repeats their dotfile and backup-file denies.
# Range requests and Content-Length come from nginx's static file handler.
location ^~ /releases/ {
    # Exact Content-Length and byte ranges for every client: never compress.
    gzip off;
    # Replaces the global map in here only.
    default_type application/octet-stream;
    types {
        application/json          json;
        application/zstd          zst;
        application/octet-stream  img;
        application/pgp-signature sig asc;
        application/pgp-keys      gpg;
        text/plain                txt sha256 manifest;
    }

    # A folder's own address lists its files, as download servers do, so a
    # link to a release leads somewhere. nginx leaves dotted names (upload
    # staging) out of a listing; sizes are shown rounded, times in UTC.
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime off;

    # Upload staging (releases/<codename>/.<version>.partial) and anything
    # else dotted or left behind is never served.
    location ~ /\\. { deny all; }
    location ~* \\.(env|bak|old|orig|swp|sql|partial|new)\$ { deny all; }

    # A version directory never changes once it is published
    # (tools/release-upload refuses to overwrite one): cache it for a year.
    location ~ ^/releases/[a-z0-9]+/20[0-9][0-9]\\.[0-9][0-9]\\.[0-9][0-9](\\.[0-9]+)?/ {
        if (\$request_method = OPTIONS) { return 204; }
$(cors_block)
        # Not "always": a 404 (asked for before the upload) must not be cached
        add_header Cache-Control "public, max-age=31536000, immutable";
        try_files \$uri \$uri/ =404;
    }

    # Everything else, releases/<codename>/latest.json above all, moves:
    # revalidate every time (ETag/Last-Modified make that a 304).
    if (\$request_method = OPTIONS) { return 204; }
$(cors_block)
    add_header Cache-Control "no-cache";
    try_files \$uri \$uri/ =404;
}
EOF
}

# The vhost with one include added in the HTTPS server block, after its
# request-method rule (server level; where a location sits in the file doesn't
# change which one matches); fails if that line isn't there.
with_include() {
  awk -v inc="$INCLUDE" '
    { print }
    /listen 443/ { tls = 1 }
    tls && !done && /^[ \t]*if \(\$request_method !~/ {
      print ""; print "    # Release bundles and root images (omarchy-mobile tools/server/releases-nginx.sh)"; print inc; done = 1
    }
    END { if (!done) exit 1 }' "$1"
}

if [[ ${1:-} == revert ]]; then
  [[ $(id -u) == 0 ]] || die "run with sudo"
  last=$(ls -1t "$AVAIL".bak-releases-* 2>/dev/null | head -1 || true)
  [[ -n $last ]] || die "no backup of $AVAIL from this script"
  cp -a "$AVAIL" "$AVAIL.bak-before-revert-$STAMP"
  cp -a "$last" "$AVAIL"
  if nginx -t; then
    systemctl reload nginx
    say "Restored $AVAIL from $last and reloaded. $SNIP is left in place, unused."
  else
    cp -a "$AVAIL.bak-before-revert-$STAMP" "$AVAIL"
    die "nginx -t failed after the revert; put the current file back. Nothing changed."
  fi
  exit 0
fi

# ---------------------------------------------------------------- preflight
say "=== Preflight ==="
[[ $DRY_RUN == 1 || $(id -u) == 0 ]] || die "run with sudo (or DRY_RUN=1)"
[[ -f $AVAIL ]] || die "no $AVAIL: provision the site first (setup-site.sh PLAIN_FILES=1)"
[[ -f $HEADERS ]] || die "no $HEADERS: the security headers snippet must exist"
grep -c 'try_files $uri $uri/ =404;' "$AVAIL" >/dev/null ||
  die "$AVAIL is not a PLAIN_FILES vhost (no 'try_files \$uri \$uri/ =404;'); look before changing it"
say "  nginx $(nginx -v 2>&1 | sed 's|.*/||')"
already=0
grep -cF "include $SNIP;" "$AVAIL" >/dev/null && already=1
if ((already)); then
  say "  $AVAIL already includes $SNIP: only the snippet is rewritten"
else
  with_include "$AVAIL" > /dev/null || die "can't find the HTTPS server block's request-method rule in $AVAIL"
fi

if [[ $DRY_RUN == 1 ]]; then
  say "=== [dry-run] $SNIP would be ==="
  write_snippet | sed 's/^/    /'
  if ((already == 0)); then
    say "=== [dry-run] the change to $AVAIL ==="
    diff -u "$AVAIL" <(with_include "$AVAIL") | sed 's/^/    /' || true
  fi
  say "Dry run: nothing changed."
  exit 0
fi

# --------------------------------------------------------------- rollback
cp -a "$AVAIL" "$AVAIL.bak-releases-$STAMP"
SNIP_BACKUP=""
if [[ -f $SNIP ]]; then SNIP_BACKUP=$SNIP.bak-$STAMP; cp -a "$SNIP" "$SNIP_BACKUP"; fi
rollback() {
  say ""
  say "!! Rolling back: a config that fails must never stay in place."
  cp -a "$AVAIL.bak-releases-$STAMP" "$AVAIL"
  if [[ -n $SNIP_BACKUP ]]; then cp -a "$SNIP_BACKUP" "$SNIP"; else rm -f "$SNIP"; fi
  say "   restored $AVAIL$( [[ -n $SNIP_BACKUP ]] && echo " and $SNIP" || echo ", removed $SNIP")"
  if nginx -t >/dev/null 2>&1; then systemctl reload nginx && say "   nginx reloaded, previous state restored"
  else say "   !! nginx -t STILL failing: run 'sudo nginx -t' and fix it by hand NOW"; fi
}
trap 'rc=$?; [ $rc -ne 0 ] && rollback; exit $rc' EXIT

reload_verified() {
  nginx -t || return 1
  local mark emerg
  mark=$(wc -l < "$ELOG" 2>/dev/null || echo 0)
  systemctl reload nginx
  sleep 2
  emerg=$(tail -n "+$((mark + 1))" "$ELOG" 2>/dev/null | grep -i '\[emerg\]' || true)
  [[ -z $emerg ]] || { say "  reload did NOT apply:"; printf '%s\n' "$emerg" | tail -5 | sed 's/^/    /'; return 1; }
}

# ------------------------------------------------------------------ change
say "=== Change ==="
before_db=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$SITE/development/aarch64/omamobile.db" || echo 000)
before_root=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$SITE/" || echo 000)
write_snippet > "$SNIP.new"
chmod 644 "$SNIP.new"
mv -f "$SNIP.new" "$SNIP"
say "  wrote $SNIP"
if ((already == 0)); then
  with_include "$AVAIL" > "$AVAIL.new"
  [[ $(grep -cF "include $SNIP;" "$AVAIL.new") == 1 ]] || { rm -f "$AVAIL.new"; die "the include didn't land exactly once"; }
  cat "$AVAIL.new" > "$AVAIL"   # keep the file's owner and mode
  rm -f "$AVAIL.new"
  say "  added the include to $AVAIL (backup: $AVAIL.bak-releases-$STAMP)"
fi
reload_verified || die "the new config failed to load"
say "  nginx -t passed, reload applied"

# ------------------------------------------------------------ verification
say "=== Verification ==="
sleep 1
probe=https://$SITE/releases/cheetah/2026.01.01/no-such-file.json
hdrs=$(curl -sI --max-time 20 -H 'Origin: https://omamobile.org' "$probe" | tr -d '\r' || true)
fails=0
check() { if printf '%s\n' "$hdrs" | grep -ci "$1" >/dev/null; then say "  ok: $2"; else say "  FAIL: $2"; fails=1; fi; }
check '^HTTP/[0-9.]* 404' "a missing release file is a 404 (plain files, no HTML fallback)"
check '^access-control-allow-origin: \*' "Access-Control-Allow-Origin: *"
check '^access-control-expose-headers: .*content-range' "Content-Range is exposed to scripts"
check '^cross-origin-resource-policy: cross-origin' "Cross-Origin-Resource-Policy: cross-origin"
check '^strict-transport-security:' "the security headers snippet is included"
check '^x-content-type-options: nosniff' "nosniff"
if printf '%s\n' "$hdrs" | grep -ci '^cache-control:' >/dev/null; then
  say "  FAIL: a 404 carries a Cache-Control header"; fails=1
else
  say "  ok: a 404 isn't cached"
fi
hdrs=$(curl -s -o /dev/null -D - -X OPTIONS --max-time 20 -H 'Origin: https://omamobile.org' \
  -H 'Access-Control-Request-Method: GET' -H 'Access-Control-Request-Headers: range' \
  "https://$SITE/releases/cheetah/2026.01.01/manifest.json" | tr -d '\r' || true)
check '^HTTP/[0-9.]* 204' "an OPTIONS preflight answers 204"
check '^access-control-allow-headers: .*range' "the preflight allows Range"
check '^cache-control: public, max-age=31536000, immutable' "a version directory is cached for a year"
hdrs=$(curl -sI --max-time 20 "https://$SITE/releases/cheetah/.2026.01.01.partial/x" | tr -d '\r' || true)
check '^HTTP/[0-9.]* 403' "upload staging directories are refused"
# The listing, where a release exists (skipped on a server with none yet)
for dir in "releases/cheetah/" "releases/cheetah/$(curl -s --max-time 20 "https://$SITE/releases/cheetah/latest.json" | sed -n 's/.*"version": *"\([0-9.]*\)".*/\1/p' | head -1)/"; do
  [[ $dir == */ && $dir != *//* ]] || continue
  code=$(curl -s -o /tmp/releases-listing.$$ -w '%{http_code} %{content_type}' --max-time 20 "https://$SITE/$dir" || echo 000)
  if [[ $code == 404* ]]; then say "  skip: no $dir on this server yet"
  elif [[ $code == "200 text/html"* ]] && ! grep -c '\.partial' /tmp/releases-listing.$$ >/dev/null; then say "  ok: $dir lists its files, without upload staging"
  else say "  FAIL: $dir answered '$code' or lists a staging directory"; fails=1; fi
  rm -f /tmp/releases-listing.$$
done
after_db=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$SITE/development/aarch64/omamobile.db" || echo 000)
after_root=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$SITE/" || echo 000)
if [[ $after_db == "$before_db" && $after_root == "$before_root" ]]; then
  say "  ok: the package repository ($after_db) and the front page ($after_root) answer as before"
else
  say "  FAIL: the package repository answered $before_db, now $after_db; the front page $before_root, now $after_root"
  fails=1
fi
((fails == 0)) || die "verification failed"

trap - EXIT
say ""
say "/releases/ on $SITE is live with CORS. Undo: sudo bash $0 revert"
