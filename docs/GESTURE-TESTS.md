# Gesture tests on the phone

`tools/phone-gesture-test` runs swipe scenarios on the quick-settings pages
(Wi-Fi, Bluetooth, the notification shade) on a real phone and checks each
one through the shell's own state. It came out of #553 (a swipe up closes the
shade card and the Wi-Fi and Bluetooth pages), where hand checks missed that
over an app a swipe from the very bottom edge reached the home strip instead
of the page.

```
tools/phone-gesture-test --list     # the scenarios
tools/phone-gesture-test            # all of them (asks for sudo once)
tools/phone-gesture-test 07 08 11   # some of them
tools/phone-gesture-test --record   # plus a screen recording per test
tools/phone-gesture-test --cleanup  # only put back what a cut-off run left
```

Run it on the phone, as the session user, from a checkout (it needs
`tools/phone-gesture-touch` next to it). To test a pull request's shell,
install its build first (`tools/phone-install-package packages/omamobile-shell`
or `pacman -U`); the suite tests whatever shell is running and records which
(package version and a hash of the quick-settings QML) in its results.

**It takes over the screen for a few minutes:** workspaces switch, a terminal
opens, notifications appear and go. Tell whoever holds the phone first.

It checks at its start that the commands it needs are there (`grim`,
`magick`, and `foot`, `notify-send`, `wf-recorder` or `sudo` when the chosen
tests need them) and names the package of any that is missing.

## The scenarios

| # | Screen | Gesture | Expected |
| --- | --- | --- | --- |
| 01, 02 | Wi-Fi / Bluetooth page, home screen | swipe up from the bottom edge | the page closes |
| 03 | Wi-Fi page, home screen | drag up from the last visible network | the list scrolls, the page stays |
| 04 | Wi-Fi page, home screen | drag up in the page body, above the strip | the page stays |
| 05 | quick settings, home screen | swipe up on the notification card's header | quick settings close |
| 06 | quick settings, home screen | drag up in the notification list | the list scrolls, quick settings stay |
| 07, 08 | Wi-Fi / Bluetooth page over an app | swipe up from the bottom edge | the page closes |
| 09, 10 | Wi-Fi / Bluetooth page over an app | swipe up from the page's own strip | the page closes |
| 11, 12 | Wi-Fi / Bluetooth page over an app | swipe up from 40 px above the edge, inside the home strip's 44 px zone | the page closes |
| 13 | Wi-Fi page, home screen | the same, 40 px above the edge | the page closes |

## No number of one device's

Nothing in a test depends on the device, its screen size or the user's setup
(so far it has run on a Pixel 9a, and in an aarch64 VM with the 9a's screen):

- **Pages open through the shell's IPC**, never by a tap on a tile:
  `shell call omamobile.quicksettings openWifi ''` ("the same as the tile's
  chevron"), `openBluetooth ''`, and `shell summon omamobile.quicksettings
  '{"expanded": false}'` for the sheet. The tile layout doesn't matter, and
  for the run quick settings use the package's default layout anyway (the
  user's `~/.config/omamobile/quicksettings.json` is moved aside and put
  back; `--keep-tiles` leaves it).
- **A known screen:** "home" is an empty workspace (4-9), "app" one with a
  terminal (`foot --app-id gesture-test`) that the suite opens and closes.
- **Only the gesture under test is a real touch,** through a virtual
  touchscreen (`tools/phone-gesture-touch`, `/dev/uinput`), at points in
  logical pixels taken from the output (`hyprctl monitors`) and the page's own
  window (`hyprctl layers`): the edge swipe starts 13 px above the screen's
  bottom, the page-strip swipe 16 px above the page window's bottom, and so on.
  The finger moves at panel resolution, through libinput and Hyprland's touch
  path, as a finger does.

## Verdicts are computed, never judged

- A test **passes** when the shell's state after the gesture is what the
  scenario expects (`shell call omamobile.quicksettings state`: `wifiPanel`,
  `bluetoothPanel`, `opened`) and Recents stayed shut, and **fails**
  otherwise. No scenario opens Recents, so its window
  (`omamobile-switcher`) after a gesture means the touch reached the home
  strip, whatever became of the page.
- A page that should **stay open** (03, 04, 06) would also stay open if the
  touch never arrived, so its pass also needs evidence from the pixels: the
  row profile of the list (the mean grey of each panel row) before and after
  the drag, and the upward shift that lines the two up best. The content must
  have moved up by at least 20 px and line up much better at that shift than
  unmoved; otherwise the result is **INCONCLUSIVE**, with the numbers in the
  log. (How far a list can go depends on how much of it is left below, so
  the rule doesn't ask for a share of the drag. A touch that never arrived
  moves nothing, and rows a scan adds push the list down, not up.) Rows that
  look alike (network names of one length, identical notifications) line up
  almost as well a whole number of rows apart: the suite then takes the
  shift nearest the drag, logs the others (`also_lines_up_at`), and passes
  only if every one of them is a move of at least 20 px. The fictional
  notifications differ in length, and one wraps onto a second line, so the
  shade's list never looks like that. Before such a drag the suite
  waits until the list stops changing, since a Wi-Fi scan adds rows for a few
  seconds after the page opens.
- Before the gesture each test checks that the screen is the one it claims,
  from the layers: on "home" no window and no home strip, with the page
  reaching the screen's bottom; over an "app" the home strip shown and the
  page ending where it begins; no on-screen keyboard and no Recents; the
  screen not locked and no call's screen up (`omamobile-call`,
  `omamobile-call-top`). These are checked before every gesture, since a run
  takes minutes. 03 and 04 also need the
  Wi-Fi list to reach the strip (they are about the end of the list); with
  only a few networks in range it doesn't. A failed precondition is a
  **SKIP**, neither a pass nor a fail.

`tests/phone-gesture-test` checks this arithmetic in CI, without a phone.

## What it changes, and puts back

- **Fictional notifications** for the shade's tests (05, 06), never more than
  the notification history has room for, less two slots for real ones that
  arrive during the run: the service keeps only its newest `historyLimit`
  (10) files and deletes the rest. Afterwards the suite takes its own out
  again the way a swipe on the shade does (`dismissNotification`) and puts
  the bar's unread mark back; `results.json` says whether every history file
  from before the run is still there.
- **Do-not-disturb** during the run (`--loud` leaves it off): no sound or
  popup for the fictional notifications, and no popup over a screen being
  measured. The previous setting is put back.
- **A cool phone:** above 75 °C the phone throttles and delivers touches late
  or in one burst, and a drag then looks like a jump (seen on the 9a at
  89-92 °C, with `--record`). Each test waits until the hottest thermal zone
  is below 75 °C at its start (up to two minutes) and again before the
  screen is measured (up to one), and is a SKIP if it is still above 75 °C
  then. Measuring warms it up again, so the touch itself comes somewhat
  hotter; both temperatures are in the log.
  `--record` heats the phone (x264 at 30 fps): leave it off for verdicts.

### A run that is cut off

Ctrl-C, SIGTERM and SIGHUP (what a run gets when its SSH session or the USB
link drops) all end a run through the same cleanup, which then runs to its
end: a second signal doesn't cut it short, and each of its commands has a
timeout. `results.json` is written all the same, with `interrupted` naming the
signal.

A run that never gets to its cleanup (SIGKILL, a crash, a power cut) leaves
its record, `~/.local/state/phone-gesture-test/run.json`. Each change is
written there before it is made (do-not-disturb as it was, the tile layout
moved aside, the terminal's process), and the file goes once everything is
back. The next run reads it first and puts back what is still changed:
do-not-disturb off again if it was off before, the tile layout, the terminal,
the fictional notifications, a page or the sheet left open, the workspace it
started on (only from one of the run's own, now empty), and the bar's unread
mark (only ever moved back, so a notification can show as unread that was
read, never the other way round). `--cleanup` does only that. A record whose run is still going stops
the new run.

## Output

`~/.cache/phone-gesture-test/run-TIME/` (or `--out DIR`):

- `results.json`: the device (output, panel pixels, scale, logical size), the
  shell that ran, do-not-disturb before, during and after, the notification
  bookkeeping, and each test's result, expectation, the state it got, its
  evidence and temperatures;
- per test: `log.json` (states and layers before and after, the touch in
  logical and panel pixels with its wall-clock times), `before.png`,
  `gesture.png` (the swipe drawn in red), `after.png`, and `raw.mp4` with
  `--record`.

The screenshots show what was on the screen, Wi-Fi network names and
notifications included: look before you share them.

## Limits

- 03 and 04 need more networks in range than fit on the page. A phone with
  only a few in range SKIPs them.
- 03 finds the last network row as the lowest line of light text in the list,
  so it assumes a dark theme.
- 05 starts at half the screen's height, where the shade card's header is
  with the sheet collapsed; `gesture.png` shows where it landed.
- One output, portrait (it refuses a rotated display or a locked screen).
- `sudo` for `/dev/uinput`: a ticket first (`sudo -v`, which asks once), then
  the helper under `sudo -n`, so its stdin only ever carries swipes.
  `GESTURE_TEST_SUDO_PW` gives the password for an unattended run; it is
  read once and taken out of the environment, so no child sees it (the
  terminal keeps its environment for its lifetime), and nothing is stored.

## Adding a scenario

A scenario is an entry in `TESTS` (id, name, `ctx` home or app, `page` wifi,
bluetooth or sheet, `gesture`, title, expectation and the state it wants) and,
for a new gesture, a case in `gesture_points`, in logical pixels relative to
the output or the page's window. Keep the pass condition in the shell's state;
if a pass could also mean that nothing happened, add pixel evidence the way
03, 04 and 06 do. [REMOTE-TESTING](REMOTE-TESTING.md) covers driving the
phone by hand over ssh.
