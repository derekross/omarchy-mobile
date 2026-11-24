<!-- SPDX-License-Identifier: MIT -->
# omamobile-mirror

The phone's screen on a computer, over the USB cable, with the computer's
mouse and keyboard driving the phone: what scrcpy does for Android, done with
VNC. Use it for live demos (the viewer window goes into OBS), for screenshots,
or to type into the phone from a real keyboard.

```
computer                                   phone (USB gadget link, usb0)
tools/phone-mirror ──ssh──> omamobile-mirror on
                              ├─ omamobile-mirror-firewall.service (root):
                              │    ufw allow in on usb0 to 172.16.42.1 port 5900 proto tcp
                              └─ omamobile-mirror.service (user unit, the session's user):
                                   wayvnc --max-fps=30 --name="Omamobile phone" 172.16.42.1:5900
VNC viewer  <──────── 172.16.42.1:5900 ────────>  wayvnc (screencopy + virtual pointer/keyboard)
```

wayvnc captures Hyprland's output with the wlroots screencopy protocol and
sends input back through the virtual pointer and virtual keyboard protocols,
which Hyprland supports. It runs as the logged-in user inside the graphical
session (it needs that user's `WAYLAND_DISPLAY`); `omamobile-mirror` started
as root finds that user with `loginctl` and starts the unit in their manager
(`systemctl --user -M <user>@`).

## Use

On the computer, with the phone on the USB cable:

```sh
tools/phone-mirror                     # mirror on, viewer open; closing the viewer turns it off
tools/phone-mirror --keep              # leave mirroring on after the viewer closes
tools/phone-mirror --fit --height 1000      # the whole phone in a 461x1000 window (gamescope)
```

On the phone (root over `tools/phone-ssh`, or the user in a terminal):

```sh
omamobile-mirror on          # start; idempotent
omamobile-mirror status      # running?, the address, the firewall rule, the user
omamobile-mirror status --json
omamobile-mirror off         # stop and close the port; idempotent
```

Any VNC viewer then connects to `172.16.42.1:5900` (TigerVNC writes it
`172.16.42.1::5900`).

### On the computer

`tools/phone-mirror` picks the first viewer it finds and says what to install
if there is none:

| Viewer | Install (Arch) | Notes |
| --- | --- | --- |
| TigerVNC `vncviewer` (default) | `sudo pacman -S tigervnc` | fast, full quality; title "Omamobile phone - TigerVNC". It has no scaling, so the 1440x3120 picture scrolls in the window, unless `--fit` |
| TigerVNC in gamescope (`--fit`) | `sudo pacman -S tigervnc gamescope` | the whole phone in the window: gamescope scales TigerVNC's full-screen 1440x3120 picture into the window on the computer's GPU and scales the mouse back |
| `gvncviewer` | `sudo pacman -S gtk-vnc` | scales to the window, but slowly |
| Remmina | `sudo pacman -S remmina libvncserver` | only with `--viewer remmina`; its VNC plugin rejects the frame ("Rect too large") |

### Why the phone always sends 1440x3120

The phone can't send a smaller picture with Hyprland 0.56, so scaling
happens on the computer (`--fit`). Checked against the Hyprland v0.56.2
source (commit efb5099, the build on the phone and laptop) and wayvnc
v0.10.2:

- Hyprland can make a headless output and mirror the panel into it at
  another size: `hyprctl output create headless <name>` and
  `hyprctl eval 'hl.monitor({ output = "<name>", mode = "720x1560", mirror = "<panel>" })'`.
  But a mirrored output gets no `wl_output` global (ProtocolManager.cpp:
  "mirrored outputs should have their global removed, as they are not
  physical parts of the layout"; the global is skipped when the output
  appears as a mirror, and removed if it becomes one later). wlr-screencopy
  and ext-image-copy-capture name what they capture by `wl_output`, so
  wayvnc can't see the mirror, let alone capture it.
- wayvnc has no option to scale the picture (its options: `--output`,
  `--max-fps`, `--disable-resizing`, `--desktop`, ...).
- A headless output that is *not* a mirror is a second screen: Hyprland
  gives it a workspace, the shell's bar and wallpaper appear on it, and
  something (wl-mirror, fullscreen on it) would have to draw a scaled copy
  of the panel there. wayvnc's pointer would then land on that copy, not
  on the panel's apps: view-only, with a second screen the shell isn't
  built for. Not done.

## Settings

`~/.config/omamobile/mirror.conf` of the session's user, `KEY=value` lines
(the commented example is `/usr/share/omamobile/mirror/mirror.conf.example`).
Read when mirroring starts: `omamobile-mirror off; omamobile-mirror on` after
a change.

| Key | Default | |
| --- | --- | --- |
| `FPS` | 30 | wayvnc's frame-rate limit, 1-120 |
| `OUTPUT` | first output | the output to capture (the phone has one) |
| `VIEW_ONLY` | 0 | 1: the viewer can't send input |
| `CURSOR` | 0 | 1: draw the pointer into the picture |
| `KEYBOARD` | wayvnc's default | xkb layout for typed keys, e.g. `de` or `us-intl` |
| `PASSWORD_FILE` | none | ask for a password (below) |
| `USERNAME` | omamobile | the username that goes with it |
| `ADDRESS` | 172.16.42.1 | may only be 172.16.42.1: anything else is refused |

The listen address is fixed at the phone's end of the USB link,
172.16.42.1, port 5900. wayvnc is never started on `0.0.0.0` or on the Wi-Fi
address, and the script refuses to start when 172.16.42.1 is missing from
`usb0` (cable out) instead of falling back to anything.

### Authentication: none by default

By default the viewer gets in without a password. The listener is on a
point-to-point link that exists only while a cable is plugged into one
computer, and that computer already has root SSH to the phone over the same
link: a VNC password adds nothing against whoever holds the cable end.

Set `PASSWORD_FILE` when the computer on the other end is shared or not
yours, or you want the screen to need a second secret. The file holds the
password on its first line and must be `chmod 600` (the script refuses it
otherwise). wayvnc then requires a username and password with RSA-AES
encryption, and an RSA key is made next to the password file on first use
(`ssh-keygen`, or `openssl`). TigerVNC 1.13 and later speak RSA-AES; Remmina's
VNC plugin may not, so use `--viewer tigervnc` with a password. wayvnc also
offers TLS (a certificate) and PAM; this package doesn't set those up. The
password is copied into `$XDG_RUNTIME_DIR/omamobile-mirror/wayvnc.conf`
(tmpfs, mode 600) for wayvnc to read.

## Firewall

ufw is on on the phone (incoming denied, SSH allowed on `usb0`). While
mirroring runs, `omamobile-mirror-firewall.service` holds one rule:

```sh
ufw allow in on usb0 to 172.16.42.1 port 5900 proto tcp comment 'omamobile-mirror'
```

Stopping the unit (`omamobile-mirror off`, or shutdown) deletes it; `off` as
root also deletes a rule left by a crash. If ufw is inactive or missing,
nothing is changed. The active local user may start and stop that one unit
through polkit (`50-omamobile-mirror.rules`), so a quick-settings tile can run
`omamobile-mirror on|off` without root.

The first time on a phone, add the rule under a dead-man switch, as for any
firewall change (AGENTS.md): if the new rule somehow cuts SSH, ufw turns
itself off after 90 s.

```sh
tools/phone-ssh 'systemd-run --unit=fw-deadman --on-active=90 /usr/bin/ufw disable'
tools/phone-ssh 'omamobile-mirror on && ufw status verbose'
tools/phone-ssh true && tools/phone-ssh 'systemctl stop fw-deadman.timer'   # a fresh login works: disarm
```

## Recording

- **Live demos, streaming: OBS.** Add a *Window Capture (PipeWire)* source
  and pick the viewer window ("Omamobile phone"). On Hyprland the portal asks
  which window; the choice can be remembered.
- **The smoothest recordings: on the phone.** Omarchy's own screen recording
  (gpu-screen-recorder) records the panel at its real frame rate with no
  network in between, then you copy the file. From the phone's menu, or over
  SSH (replace `<user>`; `--list-capture-options` names the output):

  ```sh
  tools/phone-ssh 'systemd-run --user -M <user>@ --collect --unit=omamobile-rec \
      gpu-screen-recorder -w screen -f 60 -k h264 -fallback-cpu-encoding yes \
      -o /home/<user>/Videos/demo.mp4'
  # ... demo ...
  tools/phone-ssh 'systemctl --user -M <user>@ kill -s INT omamobile-rec'   # SIGINT finishes the file
  tools/phone-ssh 'cat /home/<user>/Videos/demo.mp4' > demo.mp4
  ```

  The phone has no hardware video encoder that Linux drives yet, so this is
  CPU encoding of a 1440x3120 picture; if it drops frames, try `-f 30` or
  `-s 720x1560`. That gpu-screen-recorder is built for aarch64 is not yet
  checked on the phone.

### What to expect

Each frame is 1440x3120 (see above), with or without `--fit`. wayvnc sends only the parts of the screen that
changed, so a still screen costs almost nothing, but a full-screen animation
is a large update on the phone's CPU and the USB link. At the default
30 fps limit expect a smooth-enough picture for demos with a delay of roughly
a frame or two plus encoding time, and lower frame rates during full-screen
scrolling. Input from the viewer is a mouse, not a touchscreen: a click is a
tap, and drags work where the app accepts a mouse drag; multi-touch gestures
don't. Hyprland may show a pointer on the phone while the viewer moves it. With
`--fit` the scaling costs the computer's GPU, not the phone's.
Rotation changes the shared picture's shape; the viewer follows it.

## Notes

- The units are not enabled; nothing runs until `omamobile-mirror on`.
- The user unit is `PartOf=graphical-session.target`: logging out ends
  mirroring (the firewall rule stays until `omamobile-mirror off`).
- If Hyprland's `ecosystem:enforce_permissions` is on, allow screencopy for
  `/usr/bin/wayvnc`.
- Logs: `journalctl --user -u omamobile-mirror` as the session's user.
