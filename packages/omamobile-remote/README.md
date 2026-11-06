# omamobile-remote

Use an Omarchy Mobile phone over ssh the way a person would: look at the screen, type, move a pointer, click, scroll, unlock, start apps. A script or an AI agent can then test a phone (sound, camera, Wi-Fi, keyboards, apps) with nobody holding it, which is the slow part of bringing up a new device.

It is opt-in. No image installs it. The package enables nothing: no systemd unit, no udev rule, no group, and nothing listens. It does nothing until someone logs in to the phone over ssh and runs it. (`omamobile-cdp` opens a port on 127.0.0.1 while you run it.)

```
ssh phone omamobile-remote shot                 # screenshot, prints the path
ssh phone omamobile-remote unlock               # PIN from $OMAMOBILE_PIN or stdin
ssh phone omamobile-remote launch foot
ssh phone omamobile-remote type 'echo hello'
ssh phone omamobile-remote key Return
ssh phone omamobile-remote tap 158 750          # layout px, see below
ssh phone omamobile-remote keep-awake sleep 120 # no lock while the command runs
```

The full commands are in `omamobile-remote help`. A walk-through with screenshots, the on-screen keyboard geometry, and a guide for writing prompts for an agent is in `docs/REMOTE-TESTING.md` in the repository.

## What is in it

- `omamobile-remote`: the commands above. It finds the user's Wayland and Hyprland session itself, so a plain ssh login is enough.
- `omamobile-cdp`: a second Chromium with its own profile and the DevTools port on `127.0.0.1` only, for testing web pages. Start it by hand and close it when done.
- `cdp.py` (in `/usr/lib/omamobile-remote/`): a small DevTools client without dependencies: `list`, `eval`, `shot`.
- `omamobile-osk-switch`: moves a Stevia user drop-in for `omamobile-osk.service` aside and back, to test both on-screen keyboards. It does nothing when there is no such drop-in.

It depends on the `wlrctl` package in this repository, which is upstream wlrctl 0.2.2 with one patch. Stock wlrctl moves the pointer on a phone, but its clicks and scrolls are dropped, because it creates a pointer per command and a phone has no other pointer for Hyprland to focus. The patch is explained in its header and in the docs.

## Security

- Everything runs as the user who ran it. There is no new way in: the way in is the ssh login you already have, and that login is already as powerful as the unlocked screen, so keep ssh to a key and to USB or a network you trust.
- The PIN is read from stdin or `$OMAMOBILE_PIN` and typed through the virtual keyboard. It is never an argument, never in the journal, never written to a file, and `$OMAMOBILE_PIN` is removed from the environment as the script starts, so nothing `keep-awake`, `run` or `launch` starts has it. Do not put a real PIN in a shell history: use `read -s`.
- Only the command name goes to the journal (`journalctl -t omamobile-remote`), never its arguments.
- `omamobile-cdp` uses a separate profile, so none of the real browser's cookies or logins are exposed, and the port is bound to `127.0.0.1`. The port has no authentication: while it is open, any process on the phone can drive that browser, so start it for the test and close it. It refuses `--remote-debugging-*`, `--user-data-dir` and `--remote-allow-origins` on its command line. Reach it from a computer with `ssh -L 9222:127.0.0.1:9222 phone`. The `--remote-debugging-address` flag is placed after anything in `~/.config/chromium-flags.conf`, so it is the one that applies.
- `keep-awake` touches `~/.local/state/omarchy/indicators/stay-awake` (the file the shell's "stay awake" toggle uses) and removes it again when the command ends, unless it was already there. TERM and HUP go on to the command and the file is removed after it ends; only SIGKILL leaves it (`omarchy-toggle-idle allow-idle` removes it). It does not unlock a locked phone.
- Do not use a real PIN you care about on a phone that repeated wrong tries could lock out: `unlock` stops after one try.

## Limits, measured on a Pixel 8 Pro

Works: screenshots, typing, keys, pointer move, left and right click, two clicks in a row, scroll up and down, unlock, launching apps, both on-screen keyboards (squeekboard and Stevia), a second-profile Chromium with DevTools.
Not done: drag (the wlrctl command line has no press, move, release in one process), touch gestures (the phone's touchscreen cannot be driven: that needs `uinput`, which the kernel does not build yet), long-press on a key, pinch.
A click or a scroll takes 0.6 to 0.7 s because of the waits that make Hyprland deliver it. `shot` without a file name writes into `$XDG_RUNTIME_DIR` and leaves the picture there until you log out.
