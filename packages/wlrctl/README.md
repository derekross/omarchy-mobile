# wlrctl

[wlrctl](https://git.sr.ht/~brocellous/wlrctl) 0.2.2, the command line for the wlroots virtual keyboard and virtual pointer protocols, with one patch so that `click` and `scroll` work on a phone. Arch Linux ARM doesn't package it. Opt-in: only `omamobile-remote` depends on it and no image installs either.

## Why the patch

wlrctl creates a new virtual pointer for every command and exits. A phone has no other pointer, so Hyprland has none between commands, and a button only goes to a surface that has pointer focus, which comes from motion. A stock `wlrctl pointer click left` is therefore not delivered, although `wlrctl pointer move` works. The patch makes `click` and `scroll` move the pointer first (a 1 px wiggle, then a second round of motion so the app sees real motion), and hold the button for 80 ms. A click or a scroll takes 0.6 to 0.7 s.

Measured on a Pixel 8 Pro with a terminal reporting mouse events (the header of the patch has the table): stock click, nothing arrives; one wiggle, the press arrives at the wrong cell; the patch, the click arrives where the pointer is, scroll up gives button 64 and down 65. The reason a button is dropped without focus is read from the Hyprland 0.56.2 source, not from a Hyprland log.

Delete the patch when upstream wlrctl or Hyprland handles this. It has not been sent upstream yet.

## Build

`-Dwerror=false` is needed on aarch64: upstream builds with `-Werror` and `keyboard.c` compares a `char` with 0, which is always false where `char` is unsigned.
