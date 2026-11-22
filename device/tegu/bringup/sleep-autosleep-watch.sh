#!/bin/bash
# SPDX-License-Identifier: MIT
# Laptop watcher for sleep-autosleep-series.sh: the palmtop is asleep most of the
# time and awake for a few seconds every S seconds, so poll by ping, read the
# series log in the awake window, and call it a hang after HANG seconds of silence.
cd "$(dirname "$0")/../../.."
PS=tools/phone-ssh; H=logs/tegu-linkwait-20261107; L=/var/log/omamobile/sleep-autosleep-20261108.log
S=${S:-1800}; HANG=${HANG:-$((S + 900))}
send() { "${SLEEP_NOTIFY:-ask-w4ho}" "$1" >/dev/null 2>&1; echo "$(date +%T) sent: $1" >> $H/autosleep-watch.log; }
log() { echo "$(date +%T) $*" >> $H/autosleep-watch.log; }
last_ok=$(date +%s); n=0
while :; do
  if ping -c1 -W1 172.16.42.1 >/dev/null 2>&1; then
    out=$(timeout 10 $PS --fresh "cat $L; grep -c emergency_ro /proc/mounts" 2>/dev/null)
    if [[ -n $out ]]; then
      last_ok=$(date +%s); echo "$out" > $H/autosleep-series.log
      m=$(grep -c '^cycle' <<<"$out"); dead=$(tail -1 <<<"$out")
      if (( m > n )); then n=$m; log "$(grep '^cycle' <<<"$out" | tail -1 | cut -c1-120)"; fi
      [[ $dead != 0 ]] && { log "disk dead"; send "Palmtop auto-sleep series: storage dead after $n wakes; capturing."; timeout 60 $PS --fresh "journalctl -b -k --no-pager | tail -400" > $H/autosleep-dead-k.txt 2>&1; exit 1; }
      grep -q '^done' <<<"$out" && { send "Palmtop auto-sleep series done: $n wakes of ${S}s sleeps, all clean."; log "done"; exit 0; }
      grep -q 'stop' <<<"$out" && { send "Palmtop auto-sleep series stopped after $n wakes (UFS errors); see the log."; log "stop"; exit 1; }
      sleep 20
    fi
  fi
  if (( $(date +%s) - last_ok > HANG )); then send "Palmtop auto-sleep series: no answer for $((HANG/60)) minutes after $n wakes. A silent no-wake; needs Power + Volume Up, no rush."; log "hang"; exit 2; fi
  sleep 2
done
