<!-- SPDX-License-Identifier: MIT -->
# Files

A native touch file manager for Omarchy Mobile. It runs as the normal desktop
user in a separate Quickshell window and follows Omarchy's palette, font family
and corner-rounding tokens. Reopening Files activates its existing instance.
Installing the package does not change MIME defaults, launcher pins or another
file manager's visibility.

## Features

Browse Home and standard user folders, show hidden entries, search filenames,
sort lists, select multiple items, create folders, rename, copy, move on the
same filesystem and use GIO's reversible Trash/restore. Recently modified sorts
by actual modification time; it is not an opened-file history. Collisions offer
Keep both or Cancel and never silently replace existing items. Long operations
report progress and can be cancelled.

The backend uses argument arrays, rejects root execution, keeps symlinks as
links and revalidates captured selections. Unsupported special files cannot be
copied, opened or previewed. Copies are staged
on the destination filesystem and published without replacement. Interrupted
batches report the items already completed. There is no permanent-delete UI.

## Installation and use

Build the package with the project's normal package workflow. It requires
Omarchy's Commons library, Quickshell, Qt Quick, Python, GIO and xdg-utils.
PySide6 is optional for bounded local raster thumbnails. The bundled fallback
font retains its OFL license and pinned source provenance; a theme's font
family takes precedence.

Launch `omamobile-files [LOCAL_PATH_OR_FILE_URL]` or `omafiles`. The desktop
entry advertises directory handling but is not selected as the default by
installation. URI and Unicode paths are passed literally without a shell.

## Image-picker interface

`omamobile-files --capabilities` advertises the explicit image-picker protocol.
`omamobile-files --pick-image --initial-dir /absolute/folder` starts an isolated
read-only picker instance and returns exactly one JSON object on stdout:
`{"ok":true,"path":"/absolute/image.png"}` or
`{"ok":false,"cancelled":true}`. Errors exit nonzero and do not imply selection.
The caller must decode the returned image before applying it and retain its
current setting on Cancel or failure. This package does not add a Settings or
wallpaper consumer.

Each picker uses a private runtime directory, owned child process, request
nonce and bounded result file. Selected raster files are checked for stable
identity and a supported header; this is not a complete image decoder. The
picker has no file-management controls and never changes the normal Files
window. The supported extensions are PNG, JPEG, GIF, BMP and WebP.

## Checks and device qualification

`./build` checks Python syntax and frontend inputs. `./test/all` exercises real
filesystem operations only in temporary fixtures, the actual JSON backend,
wrapper activation through stubs, picker isolation and DESTDIR staging. It
does not launch a real app, alter a user's documents or set MIME defaults.

The PR's visual evidence must identify neutral offscreen fixtures separately
from phone captures. Source/package tests and example screenshots do not by
themselves qualify target-device launch performance or touch behavior. A phone
run should use a newly created fixture folder, check same-window activation,
Back, touch selection, collisions, cancellation and Trash/restore, then include
its smoke report and kernel release. Stop if a second app window appears, a
write targets anything outside the fixture, input stalls or a result is stale.
Remove only that fixture afterwards; remove the package with pacman to roll
back the application installation.

Cross-filesystem moves and restores are currently unsupported; use Copy.
Search and recent scans are bounded filename/metadata scans, not an index.
Thumbnails reject SVG, remote input, special files and oversized raster input.

## Credits and license

Omarchy Mobile was created by Derek Ross and is built by its contributors.
Original MIT notices are retained in [LICENSE](LICENSE). The fallback font's
OFL terms and source record are in `ui/fonts/`. Omarchy's Commons library keeps
its own authorship and license. Default-handler replacement and launcher
migration are separate opt-in integrations and are not included here.

Optional haptics use `feedbackd` through guarded `fbcli -E button-pressed` calls and respect its configured profile. Without `fbcli`, the action has no haptic effect. Long presses and newly opened context menus trigger one event; repeated opening of the same menu does not.
