# Demo data, screenshots and the showcase video

Screenshots and videos of an empty phone don't show what it can do. `tools/phone-demo` fills the Phone, Contacts and Messages apps with clearly fictional data, sends a few notifications, and puts everything back afterwards. It also takes full-resolution screenshots and short screen recordings over USB.

Everything it writes is invented: ten made-up people, numbers in the 555-01xx range set aside for fiction (+1 814-555-0109 to -0199), emails at `example.com`, and friendly everyday threads (weekend plans, a parcel left with a neighbor, a family birthday dinner, a standup reminder). There are no photos: Contacts draws initials. Nothing touches the modem, the SIM, NV or system state, so it works without a SIM.

## Where the apps keep their data

| App | Store | What the demo adds |
| --- | --- | --- |
| Contacts (in `omaphone`), and the names in Phone and Messages | A vdir, one vCard per contact: `~/.local/share/contacts/<book>/*.vcf`. New contacts go in the `default` book. A favorite is `CATEGORIES:Starred` | `default/omamobile-demo-<name>.vcf`, ten contacts, three of them starred |
| Messages (`omamessages`) | `~/.local/share/omatel/messages.db` (SQLite, WAL): `conversations` (keyed by the E.164 `address`), `participants`, `messages` (`direction` in/out, `state`, `read`, times in ms), and an FTS5 index that triggers keep up to date | Six one-to-one threads over the last four days. Three incoming messages are unread, in two threads |
| Phone (`omaphone`) | `~/.local/share/omatel/calls.db`: `calls` (direction, outcome answered/missed/rejected/blocked/unanswered/failed, start, answer and end times, duration, `seen`) and `favorites` | Nine calls (incoming, outgoing, missed), one missed call not yet seen |
| Notifications | Omarchy's notification service keeps one JSON file per notification in `~/.local/state/omarchy/notifications/`, and in `history/` once the toast has gone (the newest ten). The quick-settings shade and the lock glance read these files | Five notifications, sent through `org.freedesktop.Notifications` as Messages, Phone, Calendar and Omarchy |

`omatel-agent` writes these stores and the apps read them directly, so the history shows without a modem or ModemManager. If the agent isn't running, the apps show a "service isn't running" banner, but the data still appears. With no SIM the status bar shows no cellular icon. The Call and Send buttons are live whenever the agent runs, but without a modem a call fails and a text is stored as failed, so don't press them during a take. A failed text typed into a demo thread is removed by clear along with the thread.

## Seeding and clearing

```sh
tools/phone-demo status              # what's there now; needs omatel-agent, omaphone, omamessages installed
tools/phone-demo seed --close-apps   # back up, seed, send the notifications
tools/phone-demo notify              # send the notifications again, for a retake
tools/phone-demo clear --close-apps  # remove exactly what seed added
```

- **seed** backs up first, into `/var/lib/omamobile-demo/backup-<time>/` on the phone (root only, mode 0700): `messages.db` and `calls.db` through SQLite's backup API, and the contacts and notification directories as tar files. It records what it added in `/var/lib/omamobile-demo/manifest.json`, and it won't seed again until you run clear. Messages and Phone must be closed while their data changes: seed refuses while they're open, and `--close-apps` closes them for you. If `omatel-agent` is running, seed restarts it so that the shell and the apps read the stores again. `--no-notify` seeds without sending the notifications.
- **notify** takes away any demo notifications still showing and sends them again: an Omarchy update notice, a Calendar reminder, a missed call (Phone), then two message notifications (Messages). On the lock glance they group as Messages (2 new), Phone and Calendar, with "1 more from Omarchy" underneath. Tapping one in the shade opens its thread in Messages, the call log in Phone, or the update sheet. Do Not Disturb hides the toasts and empties the glance, and status warns when it's on.
- **clear** deletes exactly the rows and files listed in the manifest: everything in the demo conversations, the demo calls, the demo contact files, and any demo contact the Phone app added to its favorites. It takes the demo notifications away and puts back any older history entries that the demo pushed out of Omarchy's ten. It then compares the databases with the backup and says whether they match. If something real arrived during the demo, clear keeps it and lists it. `clear --restore-backup` copies the backed-up databases back over the live ones instead, stopping the agent while it does. clear is safe to run twice. The backups stay on the phone until you delete them, because they hold copies of your messages and calls (clear prints the path).

## Screenshots

`tools/phone-demo shot NAME` runs `grim` as the session user, inside the Hyprland session's environment. It captures at the panel's full resolution and saves the image to `logs/demo/NAME.png` on the laptop (`logs/` is gitignored). If the display is off, grim gets nothing, so `shot` stops and tells you. Wake the phone first with the power key, or pass `--wake`, which runs `omarchy-shell lock wake` (or `omarchy-brightness-display on` when the phone isn't locked). Tell whoever is holding the phone before you wake it.

Doing it by hand on the phone, as root:

```sh
u=$(loginctl list-users --no-legend | awk '$2 != "root" {print $2; exit}'); id=$(id -u "$u")
env=$(tr '\0' '\n' < /proc/$(pgrep -u "$id" -x Hyprland | head -1)/environ | grep -E '^(WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE)=')
runuser -u "$u" -- env XDG_RUNTIME_DIR=/run/user/$id $env omarchy-shell lock wake   # only if the display is off
runuser -u "$u" -- env XDG_RUNTIME_DIR=/run/user/$id $env grim /tmp/shot.png
```

The shot list for the website and the README:

1. **Lock glance:** lock the phone, then wake it. Shows the time, the date, the weather (once the home screen's weather widget has a reading less than three hours old) and the grouped notifications.
2. **PIN pad:** swipe up on the glance.
3. **Notification shade:** pull down quick settings while it lists the demo notifications.
4. **Home screens:** each page, with its widgets.
5. **Widget picker:** hold the home screen.
6. **Messages:** the conversation list (two unread threads at the top), then a thread, for example the weekend plans with Priya.
7. **Phone:** the call log, with the missed and outgoing calls.
8. **Contacts:** the list, with initials and starred favorites.
9. **Camera:** omacam's viewfinder, pointed at something you're happy to publish.
10. **Quick settings:** the tiles and sliders.

Before you publish a screenshot, check that the status bar, the Wi-Fi panel and the notifications show nothing that identifies you: no SSID, account names or real notifications.

## Screen recordings

```sh
tools/phone-demo record 20 messages-tour                   # 20 s, 1080 px wide, to logs/demo/messages-tour.mp4
tools/phone-demo record --width native 15 lock-to-home     # the panel's own resolution
```

`record` runs `wf-recorder`, which `omamobile-shell` already depends on, with the same x264 settings (BT.709, full range) as the Screen record tile's `omamobile-screenrecord`. It doesn't show the tile's "Recording the screen" and "saved" toasts, so they stay out of the video. The phone encodes on its CPU: at native resolution, keep recordings short, or the frame rate drops. The clip is copied to the laptop and deleted from the phone. The Screen record tile in quick settings works too, saving to `~/Videos` on the phone, but its toasts will show in the recording.
