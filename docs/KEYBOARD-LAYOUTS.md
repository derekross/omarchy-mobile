<!-- SPDX-License-Identifier: MIT -->
# Keyboard layouts

The on-screen keyboard is squeekboard. Omarchy Mobile ships its own copies of squeekboard's layouts, with an action row and a globe key that opens the shell's language sheet. This page says what ships, how a user picks a language, how a user adds a layout file of their own, and how a contributor changes the shipped set. Greek is the example throughout: English first, Greek second, the globe opens the language sheet, and one tap on a row switches.

Everything here is from the `omamobile-shell` package (`packages/omamobile-shell/`). Paths below are relative to it unless they start with `docs/`, `tools/` or `tests/`, or are `AGENTS.md`.

## What ships

- The layouts are in `squeekboard/keyboards/`: one portrait file and one landscape (`_wide`) file per language, named as squeekboard names them, `layout` or `layout+variant`: `us.yaml`, `us_wide.yaml`, `us+dvorak.yaml`, `gr.yaml`, `gr_wide.yaml`, `gr+polytonic.yaml`, `gr+polytonic_wide.yaml`, and so on (104 files at the top level), plus `email/`, `url/` and `terminal/` subdirectories for squeekboard's purpose-specific layouts.
- Each language file is squeekboard 1.43.1's own file (tag `v1.43.1`) with two changes, made by `squeekboard/generate` (its docstring, lines 3-20): an action row (Mic, Paste, Emoji, Hide) on top of every view, and the globe key sending `keysym: "XF86MediaLanguageMenu"` instead of squeekboard's `action: "show_prefs"` (`squeekboard/generate` lines 56-58; `squeekboard/keyboards/gr.yaml` line 75). Only `terminal/us.yaml` and `terminal/us_wide.yaml` are written by hand (`HAND_MADE`, `squeekboard/generate` line 59); the other `terminal/` files are generated like the rest.
- Greek (`gr.yaml`, `gr_wide.yaml`) has one more change, also made by `squeekboard/generate`: a row of the accented vowels under the action row, `ά έ ή ί ό ύ ώ ϊ ϋ ΐ ΰ`, and with shift the capitals `Ά Έ Ή Ί Ό Ύ Ώ Ϊ Ϋ` and the quotes `« »`. Each is one key that types its own letter, so one tap gives `ά` where the accents view (`άΐ`) took two: open it, then tap the letter (the view closes itself after one key, like shift). That view is still there for the rest. Squeekboard's shift is latched: it applies to one key and the keyboard returns to the lowercase row. Dead keys for the tonos and dialytika, as on a Greek keyboard, were tried first and do not work: on a Pixel 8 Pro a key with `keysym: "dead_acute"` typed the character `´` and the letter after it stayed plain, so they are not used. Tried on a Pixel 8 Pro in a text editor; terminals use squeekboard's `terminal/` layouts, which have no Greek (`terminal/gr.yaml` does not exist), so Greek users get the English terminal layout there. An existing `gr.yaml` of your own in `~/.local/share/squeekboard/keyboards/` is never replaced by `omamobile-setup-user`: to get the accent row, remove it and log in again, or `ln -sf` the shipped file there.
- `hypr/phone.lua` binds `XF86MediaLanguageMenu`, for squeekboard's virtual keyboard only, to the shell's language sheet (`omarchy-shell shell call omamobile.keyboard languages ''`; checked by `test/all` line 449).
- The generated files are GPL-3.0-or-later, derived from squeekboard. The generator writes that header into each file (`squeekboard/generate` lines 150-160; see the top of `squeekboard/keyboards/gr.yaml`). The package's `PKGBUILD` lists both licences, `MIT` and `GPL-3.0-or-later`.
- `install` copies every `*.yaml` under `squeekboard/keyboards/` to `/usr/share/omamobile/squeekboard/keyboards/` (`install` lines 28-30).

## Picking a language (user)

The language list is `org.gnome.desktop.input-sources` `sources`, a GNOME setting. squeekboard 1.43 shows the first entry and re-reads the setting on every change (`bin/omamobile-keyboard-languages` lines 14-16, from squeekboard's `eekboard/eekboard-context-service.c`). So the first entry is the current layout, and switching means moving an entry to the front.

Two ways to do that:

**The language sheet.** In a text field, tap the keyboard's globe key. A sheet slides up over the keyboard with one row per language, the current one checked, a remove target on the others, and "Add a language" with the layouts the keyboard carries that are not on the list yet. A tap on a row switches and closes the sheet; a tap outside or a swipe down closes it without a change (`docs/VOICE-PLAN.md`, "The language sheet"; `plugins/omamobile.keyboard/Keyboard.qml` `pickLanguage` and `removeLanguage`, lines 78-92; the dismiss gestures are in `LanguageSheet.qml`). The globe itself only opens and closes the sheet.

**The command.** The sheet runs `bin/omamobile-keyboard-languages`, and it can be run by hand (its docstring, lines 6-12):

```
omamobile-keyboard-languages list          # JSON: sources, the current one, what can be added
omamobile-keyboard-languages set NAME      # NAME to the front of sources (added when missing)
omamobile-keyboard-languages remove NAME   # NAME off the list; never the last one
```

`NAME` is the xkb layout name, `gr`, `us`, or `layout+variant` such as `gr+polytonic` or `us+dvorak` (lines 9, 20-22). `set` keeps the other entries in their order, as squeekboard's own popover does (lines 137-141). With an empty `sources`, squeekboard falls back to `us`, and `set gr` then writes `gr, us` (lines 44-45, 139-141). `remove` refuses to empty the list (lines 144-148). The `list` output names each layout with xkeyboard-config's description from `/usr/share/X11/xkb/rules/evdev.xml`, so `gr` shows as the Greek entry there; what can be added is the set of portrait files in `/usr/share/omamobile/squeekboard/keyboards/` (or the directory in `OMAMOBILE_KEYBOARDS_DIR`) that are not already shown (lines 43, 101-109, 126-132). When `sources` is empty the shown list is the fallback `us`, so `us` is not offered either.

Greek as the second language, English staying first:

```
omamobile-keyboard-languages set gr    # sources: gr, us ...
omamobile-keyboard-languages set us    # sources: us, gr ...
```

Or in the sheet: globe, "Add a language", Greek, then globe, English. After that, the globe and a tap on the other language's row switch between the two. The same can be done with `gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'gr')]"`; the tool only reads and writes that key (lines 40-41, 70-75).

Tried on a Pixel 8 Pro, with a local key that rotated the list before the sheet existed there: with `sources` set to `us` then `gr`, the keyboard switched between English and Greek and the Greek layout typed into an app. The sheet itself was not tried on that phone.

## Your own layout file (user)

The package's layouts are linked into the user's data directory, which is where `omamobile-setup-user` says squeekboard reads them (its comment, lines 203-205). `omamobile-setup-user` links each shipped file into `~/.local/share/squeekboard/keyboards/` (`$XDG_DATA_HOME` when set) at login, one symlink per file, keeping the same relative name. The link target is the shipped file under `/usr/share/omamobile/squeekboard/keyboards/` (line 219). A file or link that is already there is left alone (`bin/omamobile-setup-user` lines 203-222: the `! -e && ! -L` test before `ln -s`). So a file of your own with a shipped name wins over the shipped one once the existing link is removed, and it then survives package updates and later setup runs. A link that is left in place keeps following the package's file.

To change the Greek layout for yourself:

1. Replace the link with a copy: `cd ~/.local/share/squeekboard/keyboards && rm gr.yaml && cp /usr/share/omamobile/squeekboard/keyboards/gr.yaml gr.yaml`. Do the same for `gr_wide.yaml` if landscape should change too.
2. Edit the copy. Keep the action row (`- "Mic Paste Emoji Hide"` as the first row of every view) and the globe key's `keysym: "XF86MediaLanguageMenu"`, or the Mic, Paste, Emoji, Hide and language keys stop working; nothing in the shell checks a user's file.
3. Make `gr` current (`omamobile-keyboard-languages set gr`, or the sheet). If `gr` was already current, switch away and back; whether that is enough for squeekboard to read the changed file was not checked here (see below).

To add a layout under a new name, say `mine.yaml`: put it in the same directory and run `omamobile-keyboard-languages set mine` (or set `sources` by hand). The sheet's "Add a language" does not offer it, because that list is read from the package's directory, not the user's (`bin/omamobile-keyboard-languages` lines 43, 101-109); once it is in `sources`, the sheet lists it under whatever name xkeyboard-config has for it, the form `Base (variant)` when the variant is not in the file, or the bare name.

Not verified in this repository: how squeekboard itself finds a layout file. This page says only what `omamobile-setup-user` does (link into `~/.local/share/squeekboard/keyboards/`) and that the shipped layouts work from there. Whether squeekboard looks at other directories, reloads an edited file without a layout switch, or accepts a name with no xkb counterpart was not checked here; `docs/VOICE-PLAN.md` ("The language sheet") notes that squeekboard looks a name up as a path, from a reading of its source, not from a test.

## Adding or changing a shipped layout (contributor)

Do not edit a generated file. Every file but the two hand-made terminal ones is made by `squeekboard/generate`, and `squeekboard/generate --check` fails when a file is not what the generator makes of its own upstream part (`squeekboard/generate` lines 7-10, 201-211). To change what every language gets (the action row, the globe), change the generator. To add a language, add the upstream file and regenerate.

1. Get squeekboard 1.43.1's `data/keyboards/` (tag `v1.43.1`, <https://gitlab.gnome.org/World/Phosh/squeekboard>). The upstream copies are not in this repository (generator docstring, lines 12-20). A new upstream file must have exactly one `show_prefs` key, or the generator stops (the assertion at lines 145-146).
2. Run `squeekboard/generate UPSTREAM_KEYBOARDS_DIR` from `packages/omamobile-shell/`. It writes every `*.yaml` under that directory except `emoji/`, `number/`, `pin/` and the hand-made terminal files, each with the header, the action row and the globe change (lines 59-64, 209-227). It needs PyYAML.
3. Run `squeekboard/generate --check`. It strips the generator's additions from each file, regenerates and compares (lines 170-189, 201-211).
4. Run the tests from `packages/omamobile-shell/`: `test/all` runs `python3 -B test/keyboard-layouts.py` (every layout as squeekboard 1.43.1 parses it, the action row in every view, the globe keysym, known keysyms when libxkbcommon is installed; it exits 77, a skip, without PyYAML) and, only when that passes, `squeekboard/generate --check`; then `bash test/keyboard-languages.sh` (`omamobile-keyboard-languages` against a fake `gsettings`) (`test/all` lines 428-436, 463). Each can also be run on its own.
5. From the repository root, run `tools/pr-check` and `tests/packages` before pushing (see the tools table in `AGENTS.md`).
6. Bump `version` and note the change in the package `README.md` and this page.

A new language is selectable once the package is installed with its portrait file in `squeekboard/keyboards/`: `omamobile-keyboard-languages list` then offers every top-level portrait file in the installed directory, and `omamobile-setup-user` links it at the next login. To try one before packaging, set `OMAMOBILE_KEYBOARDS_DIR` to the source directory for the list.
