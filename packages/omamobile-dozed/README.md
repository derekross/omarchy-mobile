# omamobile-dozed

Doze for Omamobile. While the screen is off behind a secure lock, background apps are frozen with the cgroup freezer, so they stop waking the CPU. They are thawed for a 60 s maintenance window every hour and when the screen comes on (at the next poll, within 5 s).

It is a user unit for every graphical session, like `omamobile-sleepd`, and does nothing until:

    omarchy-toggle omamobile-doze on

No image installs this package yet. s2idle stays `omamobile-sleepd`'s job.

## Stages

| Stage | When | What |
|---|---|---|
| SCREEN_OFF | the screen goes off behind a secure lock | apps set to Restricted in Settings > Apps are frozen (checked once a minute until LIGHT, with the full checks below) |
| LIGHT | 300 s later (`OMAMOBILE_DOZE_LIGHT_AFTER`) | every freezable unit is frozen |
| DEEP | 1800 s after screen off (`OMAMOBILE_DOZE_DEEP_AFTER`), on battery, no SSH session | freezes the same as LIGHT; it is the place where platform savers hook in later |
| maintenance | every 3600 s (`OMAMOBILE_DOZE_MAINT_EVERY`), for 60 s (`OMAMOBILE_DOZE_MAINT_LEN`) | everything thawed, a sleep block inhibitor holds `omamobile-sleepd` off; Restricted apps are frozen again |

On the charger (and with an SSH session or the charger's sleep inhibitor) it still goes to LIGHT, with the hourly window, but never DEEP. `OMAMOBILE_DOZE_PLUGGED=0` makes those refuse Doze altogether.

Doze is left (everything thawed) when the screen comes on, the lock is not secure, Stay awake is on, a logind sleep or idle block inhibitor is held, or any PipeWire sink or source (monitors aside) is RUNNING. `pactl` failing counts as playing. While anything is frozen, audio and inhibitors are checked at every poll (5 s). `omamobile-dozed check` prints what keeps Doze out now; `status` prints the stage and what is frozen; `restore` thaws everything it recorded.

## What is frozen, what is never frozen

Freezable: running `app-*.scope` and `app-*.service` units under `app*.slice` of the user manager (what `uwsm app`, the launcher and autostart create), plus the exact names in `OMAMOBILE_DOZE_EXTRA_UNITS` (none by default). The shell, lock, call path and the shell's own watchers run in the compositor's unit (`wayland-wm@*.service`), which is never a candidate; nothing in the system manager is touched.

Never frozen, even when a policy line says Restricted:

- a unit with a process named `phosh-osk-stevi` (the Stevia keyboard), `squeekboard`, `wvkbd`, `voxtype`, `pipewire` or `wireplumber` anywhere in its cgroup tree (`OMAMOBILE_DOZE_NEVER_COMM`); a cgroup that can't be read counts as protected;
- unit names matching quickshell, omamobile, mako, swaync, pipewire, wireplumber, lock, hypridle, polkit, portal, the keyboards, voxtype, omatel, omaphone, omamessages, clock, alarm, ModemManager, mmcli; for an app started from the drawer (a unit named after `gtk-launch`) the same names are checked against its app ID;
- a unit holding a logind sleep or idle inhibitor (a shutdown-only inhibitor doesn't protect it);
- a pattern in `~/.config/omamobile/doze-allow` (`$XDG_CONFIG_HOME` when set, as for `app-policy`) (one glob per line, `#` comments);
- an app set to Unrestricted in Settings > Apps.

A freeze is written to `$XDG_RUNTIME_DIR/omamobile-doze/applied` before it is made, and undone on exit, on stop (`ExecStopPost`) and on start. On start it also thaws any frozen `app-*` unit it finds, journal or not, so a crash can't leave an app frozen.

## Per-app policy (Settings > Apps > Battery)

`~/.config/omamobile/app-policy`, written by the Settings app's `appmgr.sh policy`: one line per app, `ID<TAB>unrestricted|restricted<TAB>unit keys`. Optimized (the default) writes no line. A unit is matched by the key in its name (`app-<launcher>-<KEY>-<hex>.scope`, `app-<launcher>-<KEY>@<x>.service`). Apps started from the drawer run in a unit named after `gtk-launch`; there the app ID comes from `GIO_LAUNCHED_DESKTOP_FILE` in the environment of the process whose own PID is in `GIO_LAUNCHED_DESKTOP_FILE_PID` (children inherit the variable and are not counted). With several apps in one unit, any Unrestricted one keeps it unfrozen, and Restricted applies only when it is the only app. For name keys too, an Unrestricted line wins over a Restricted one. The file is not read when it or its folder is a link. Known gap: dozed also reads keys from units named `app-<launcher>-<KEY>.service`, which the Apps page doesn't list as the app's units, so Stop doesn't see them.

## Superwhisper (opt-in)

Superwhisper isn't frozen by default: it isn't in this repository, and frozen it can't answer the keyboard's Mic. To freeze it while you are not dictating, add `OMAMOBILE_DOZE_EXTRA_UNITS=superwhisper.service` to the unit's environment and link the wrapper ahead of the real command in the session's PATH:

    ln -s /usr/lib/omamobile-dozed/superwhisper-thaw ~/.local/bin/superwhisper   # if ~/.local/bin comes first

The wrapper reads the unit's `cgroup.events` and, when it is frozen, thaws it (one `systemctl` call capped at 2 s) and runs the real `superwhisper`. Dozed doesn't freeze it again for at least 60 s (it looks every `OMAMOBILE_DOZE_REFREEZE_EVERY`, 300 s), and a running capture stream keeps Doze out while you dictate.

## What was tested on a phone, and what wasn't

All of it on a Pixel 8 Pro (husky), 2026-11-22 and 23, with the earlier copy of this script installed by hand in `/usr/local/bin` and short timers (LIGHT after 30 s). The cpufreq cap, radio and Wi-Fi parts that copy had are not in this package. The package layout (paths, the unit from the package, the tidy-up in this PR) has **not** run on a phone.

- Freezer by hand, screen off: a busy terminal app (herdr) went from 491 context switches in 30 s to 0 while frozen, three runs, and thawed fine.
- A Wayland client (foot in its own scope) frozen, screen woken while still frozen, then thawed, three runs: the lock screen drew normally on each wake (screenshots), no Hyprland "not responding" dialog.
- The daemon: LIGHT froze the monitor-watch, udiskie and geoclue agent units; it left Doze and thawed on screen on and while the speaker played, froze again after playback, thawed in the light maintenance window and froze again after it; after a `kill`, the restart thawed what the killed run had left frozen.
- Superwhisper frozen, with the wrapper: a Mic press thawed it in 322 ms and dictation recorded; the running capture stream then kept Doze out.
- Settings > Apps: a drawer-launched app set to Restricted froze about 10 s after screen off and lock, and thawed on unlock.
- ABAB, 60 s per arm, superwhisper frozen in the B arms: context switches of the top 40 processes 587, 546, 590, 529 per second (off, on, off, on), user.slice 158, 94, 159, 96.

Not tested on a phone: DEEP and its maintenance window (the runs never stayed off 30 minutes), the plugged LIGHT stage on a real charger, the SSH and inhibitor cases, battery current (no mA measured; only context switches and SoC temperature), and an overnight run. The last change to the drawer-launch match (reading every `cgroup.procs` line) had no phone run of its own, and neither had this PR's review fixes: Restricted apps thawed by audio or an inhibitor before LIGHT, a timed-out freeze thawed again, the freeze pass stopping when Hyprland says the screen is on (with no answer from Hyprland it runs to the end and the next poll thaws), the drawer app ID checked against the never-freeze names, `$XDG_CONFIG_HOME`.

Not covered by `test/dozed.sh` either: the screen-on stop inside the freeze pass, killing the maintenance window's inhibitor early, a drawer launch run as a `.service`, and the thaw without the journal lock.

`test/all` runs `test/dozed.sh`: the daemon against a fake sysfs, `/proc` and stand-ins for `systemctl`, `busctl`, `pactl`, `hyprctl` and the clock, covering the stages, the journal, the never-freeze rules, the policy matching and the wrapper.
