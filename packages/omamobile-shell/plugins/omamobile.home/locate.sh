#!/bin/bash
# SPDX-License-Identifier: MIT
# The phone's position for the home screen's weather widgets, from GeoClue
# (the Location switch: omamobile-gnss on starts GeoClue's agent, without
# which GeoClue answers nobody). Asks at city accuracy, which GeoClue answers
# from its coarse sources without powering the GNSS receiver.
#
# Prints {"lat":..,"lon":..,"accuracy":..,"at":..} with the coordinates
# rounded to 0.01 degree (about 1 km), and keeps that answer in
# ~/.cache/omamobile/location.json for MAX_AGE seconds (default 1800) so
# several widgets share one question. Nothing here uses the network; the
# widgets send the rounded coordinates only once their internet use is on.
#
#   locate.sh [MAX_AGE]
# Exit 2: GeoClue isn't installed. Exit 3: no position (message on stderr).
set -u
export LC_ALL=C
max_age=${1:-1800}
[[ $max_age =~ ^[0-9]+$ ]] || max_age=1800
cache=${XDG_CACHE_HOME:-$HOME/.cache}/omamobile/location.json
if [[ -s $cache ]] && (( $(date +%s) - $(stat -c %Y "$cache") < max_age )); then
  cat "$cache"
  exit 0
fi
wai=${OMAMOBILE_WHERE_AM_I:-/usr/lib/geoclue-2.0/demos/where-am-i}
if [[ ! -x $wai ]]; then
  echo "GeoClue isn't installed" >&2
  exit 2
fi
# -a 4: city accuracy; -t: give up (and exit) after this many seconds.
# Without GTK_USE_PORTAL: the session sets it to 1 for the touch file chooser
# (20-omamobile-osk.conf), and GeoClue's client library then asks the desktop
# portal instead of GeoClue, which answers "Location services disabled".
out=$(env -u GTK_USE_PORTAL timeout -k 2 20 "$wai" -a 4 -t 12 2>&1)
lat=$(sed -n 's/^Latitude: *\(-\{0,1\}[0-9][0-9.]*\).*/\1/p' <<<"$out" | tail -n 1)
lon=$(sed -n 's/^Longitude: *\(-\{0,1\}[0-9][0-9.]*\).*/\1/p' <<<"$out" | tail -n 1)
acc=$(sed -n 's/^Accuracy: *\([0-9][0-9.]*\).*/\1/p' <<<"$out" | tail -n 1)
if [[ -z $lat || -z $lon ]]; then
  echo "No location: turn Location on (omamobile-gnss on)" >&2
  exit 3
fi
mkdir -p "${cache%/*}"
printf '{"lat":%.2f,"lon":%.2f,"accuracy":%.0f,"at":%s}\n' "$lat" "$lon" "${acc:-0}" "$(date +%s)" >"$cache.tmp" \
  && mv -f "$cache.tmp" "$cache"
cat "$cache"
