<!-- SPDX-License-Identifier: MIT -->
# Your own quick-settings tiles

Quick settings takes tiles of your own next to the built-in ones, the way the
home screen takes your own widgets ([WIDGETS.md](WIDGETS.md)). This file is
installed as `/usr/share/omamobile/shell/TILES.md`.

A tile is one JSON file, `~/.config/omamobile/tiles/<id>.json`. The id is the
file's name without `.json` and uses only `a-z`, `0-9` and `-`; files with
other names, and hidden files, are skipped. The commands in the file say what
the tile shows and what a tap does.

Once the file is there, open quick settings, tap the pencil and add the tile
from **Add tiles**. In the layout (`~/.config/omamobile/quicksettings.json`)
it is `user:<id>`, and `omarchy-shell shell call omamobile.quicksettings
setTiles 'wifi user:<id>'` places it from a script. Quick settings reads your
tiles each time it opens and after a tap on a tile, so a change to a file
shows on the next open.

## Fields

| Field | Type | What it does |
| --- | --- | --- |
| `label` | string, required | The tile's name |
| `icon` | one Nerd Font glyph | The tile's glyph; a generic one when left out |
| `status` | command | The first line it prints is the tile's status text |
| `active` | command | Exit code 0 shows the tile as on; otherwise, or without it, off |
| `choices` | command | Prints the choices, one per line: `value<TAB>label` (without a label the value is the label) |
| `choose` | command | Required with `choices`, and only with it: runs with the chosen value in place of the element `"{}"` |
| `action` | command | Runs on a tap, for a tile without `choices` |

A command is a JSON array of strings: the program and its arguments, as
`["timedatectl", "set-timezone", "{}"]`. It runs as you, from your home
folder, with no input, and with no shell unless the array starts one itself
(`["sh", "-c", "…"]`). `status`, `active` and `choices` get 3 seconds and
`choose` and `action` 15; a command still running then is stopped, with every
process it started. Any other field is an error.

A tap on a tile with `choices` opens a page that lists them; picking one runs
`choose` and puts the page away. The row whose value or label is the tile's
status text is marked as the current one. A tap on a tile with an `action`
runs it. A tile with neither only shows its status.

The chosen value is passed as one argument, never through a shell, and only
if `choices` lists it at that moment: `choose` can't be run with anything
else. Don't put `"{}"` inside a `sh -c` string to get around that; pass it as
its own element and read it as `$1` (`["sh", "-c", "do-something \"$1\"",
"sh", "{}"]`).

A file that can't be read or breaks one of these rules shows on its tile with
the reason ("unknown field colour", "choices needs a choose command"), and the
others work as before. A tile in the layout whose file is gone shows "Not
installed".

To see what quick settings sees:

```sh
python3 -I /usr/share/omamobile/shell/plugins/omamobile.quicksettings/user-tiles.py list
python3 -I /usr/share/omamobile/shell/plugins/omamobile.quicksettings/user-tiles.py run <id> [value]
```

## Example: Solar time

The time zone the system is on, from a set of zoneinfo files named
`/usr/share/zoneinfo/Tempus_Solaris_<House>`, with a tap to pick another.
`~/.config/omamobile/tiles/solar-time.json`:

```json
{
  "label": "Solar time",
  "icon": "󰖙",
  "status": ["sh", "-c", "timedatectl show -p Timezone --value | sed 's/^Tempus_Solaris_//; s/_/ /g'"],
  "choices": ["sh", "-c", "for f in /usr/share/zoneinfo/Tempus_Solaris_*; do n=${f##*/}; printf '%s\\t%s\\n' \"$n\" \"$(echo ${n#Tempus_Solaris_} | tr _ ' ')\"; done"],
  "choose": ["timedatectl", "set-timezone", "{}"]
}
```

The status turns `Tempus_Solaris_Bashley_Safe_House` into "Bashley Safe
House", the same text as that choice's label, so the page marks it.
`timedatectl set-timezone` asks for your password through the shell's prompt
(polkit) unless you have already given it in the last few minutes, and the
15 seconds include that prompt.
