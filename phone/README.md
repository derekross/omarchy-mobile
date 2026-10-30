# Omarchy phone profile

The Omarchy shell on a phone: Omarchy's own Quickshell shell (unchanged) plus
the phone plugins and profile, which now live in the `omamobile-shell` package
(`packages/omamobile-shell`). This directory holds the desktop harness and
screenshots.

## Develop on the desktop

```sh
phone/dev/run-desktop
```

This opens a nested Hyprland in a 600x1300 window (the Pixel 7 Pro's 13:6
shape, at 480x1040 logical pixels like the real phone) and runs the shell
inside it. It uses a private home directory under `~/android/phone-dev/home`
that links your current Omarchy theme and this directory's plugins, so your
real `~/.config/omarchy` is never touched. Plugin edits hot-reload.

Inside the window, `ALT+Return` opens a terminal. The window never locks on
its own, as in a phone emulator: the harness turns the profile's idle lock
off in its copy of `shell.json`.

The session has the package's `bin/` on `PATH`, so apps launch through
`omamobile-launch` as on the phone. The helpers that would act on this
computer (`omamobile-bt-agent`, `omamobile-fp-enroll`, `omamobile-set-pin`)
are replaced by stand-ins in `dev/bin` that refuse to run.

The session shares this computer's D-Bus, so an app that starts through
D-Bus activation (Files, for one) would open on the desktop. `dev/bin`'s
`gtk-launch` starts those without the session bus, so they open in the
window but lose what they do over it (for Files, the Trash, Recent and
Network locations), and what they open has no session bus either: a page
Files opens in the browser starts the browser without its keyring. An app
that hands off to an instance already open on the desktop still opens
there, and that includes the browser and so Omarchy's web apps; while one
started in the window is running, the desktop's own launches of it open in
the window instead.

The app list shows this computer's own entries too, Omarchy's web apps
among them, and hides what the desktop hides.

The shell runs from an Omarchy tree of its own, `~/android/phone-dev/omarchy`:
a copy of your Omarchy's shell, with everything else linked to your Omarchy.
`OMARCHY_PATH` points there in the session, so `omarchy-shell` (and the
panels it opens, such as recents) reaches the nested shell and never your
desktop's. A `dev/bin` stand-in keeps that working in a terminal, whose bash
resets `OMARCHY_PATH`, and another refuses `omarchy-restart-shell`, which
would restart your desktop's shell. From a desktop terminal, reach the
nested shell with
`OMARCHY_PATH=~/android/phone-dev/omarchy WAYLAND_DISPLAY=wayland-N omarchy-shell …`.
Harnesses from before this kept the copy in `~/android/phone-dev/shell`;
nothing uses it now, so it can be deleted.

## Layout

| Path | What it is |
| --- | --- |
| `profile/shell.json` | Phone layout for the shell (bar, plugins, idle) |
| `plugins/` | Phone plugins: status bar, quick settings, launcher and agent bar ([plugins/README.md](plugins/README.md)) |
| `screenshots/` | The phone profile in the desktop harness |
| `dev/` | Desktop harness: nested Hyprland config, launcher, and stand-ins for helpers that would act on the desktop (`dev/bin`) |
