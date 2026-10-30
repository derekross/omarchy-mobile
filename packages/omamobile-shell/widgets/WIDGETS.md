<!-- SPDX-License-Identifier: MIT -->
# Omarchy Mobile home-screen widgets

This is the contract for writing your own widgets for Omarchy Mobile's home
screens, by hand or with a coding agent. It is installed as
`/usr/share/omamobile/shell/WIDGETS.md` and linked from
`~/.config/omamobile/widgets/WIDGETS.md`.

A widget is a folder with a `manifest.json` and a QML file, like an Omarchy
shell plugin. It draws inside a card on the home screen, takes its colours
and fonts from the current Omarchy theme, and can be placed, resized and
configured in edit mode like the built-in widgets.

**If you are a coding agent:** you were started in one widget's folder.
Work only inside that folder: don't create, change or delete files anywhere
else, don't run `sudo` or any other root tool, don't install packages, and
don't fetch widget code from the network. You run unattended (Omarchy starts
agents with their "don't ask" flags), so these limits are yours to keep.
Keep the manifest's `id`. When you are done, run `omamobile-widget check .`
and fix every error it reports. The home screen applies the same checks.

## Where widgets live

| Path | What |
| --- | --- |
| `~/.config/omamobile/widgets/<id>/` | Your widgets, one folder each; the folder name is the manifest's `id` |
| `/usr/share/omamobile/shell/widget-examples/<id>/` | Installed examples. They aren't loaded from there: placing one copies it into your widgets |
| `/usr/share/omamobile/shell/widget-template/` | The starter that **Create a widget with AI** copies |
| `~/.local/share/omamobile/removed-widgets/` | Where **Remove** moves a widget folder (nothing is deleted) |

The home screen watches your widgets folder (the way Omarchy's shell watches
`~/.config/omarchy/plugins`) and reloads a widget a moment after any of its
files change. Hidden files and folders (`.name`) are ignored. Nothing is
loaded from anywhere else.

## Making one from the phone

In edit mode (long-press the home screen), **Widgets**, then **Create a
widget with AI**. Describe the widget and tap **Create**. The phone then:

1. makes `~/.config/omamobile/widgets/<you>.<words>/` from the template and
   places it on the page (it shows "Hello" until the agent changes it);
2. starts the coding agent you chose in Omarchy's menu (**Setup > Default
   agent**, `omarchy-default-agent`) through Omarchy's own launcher
   (`omarchy-agent-prompt`), in a terminal, in that folder, with your
   description and a pointer to this file as its prompt;
3. reloads the widget as the agent saves its files.

With no default agent chosen, Omarchy's agent chooser opens instead; choose
one and tap **Create** again (the same folder is used). If the chosen agent
isn't installed, its message is shown on the sheet.

**Edit with AI** (the robot button next to one of your widgets in the
Widgets sheet, or in a placed widget's settings) starts the agent in that
widget's folder, with what you typed and the widget's current errors.
**Remove** (the bin, tapped twice) moves the folder out and takes the widget
off every page.

## manifest.json

The manifest is Omarchy's plugin manifest (`schemaVersion`, `id`, `name`,
`version`, `kinds`, `entryPoints`) with kind `home-widget` and a
`homeWidget` block, as `barWidget` is for bar widgets:

```json
{
  "schemaVersion": 1,
  "id": "alice.tea-timer",
  "name": "Tea timer",
  "version": "0.1.0",
  "author": "alice",
  "description": "Counts down a steeping time.",
  "kinds": ["home-widget"],
  "entryPoints": { "homeWidget": "Widget.qml" },
  "homeWidget": {
    "icon": "󰔟",
    "size": [2, 1],
    "min": [1, 1],
    "max": [4, 2],
    "capabilities": [],
    "defaults": { "minutes": 4 },
    "schema": [
      { "key": "minutes", "type": "integer", "label": "Minutes", "min": 1, "max": 15, "defaultValue": 4 }
    ]
  }
}
```

| Field | Rules |
| --- | --- |
| `schemaVersion` | `1` |
| `id` | Lower-case letters, digits, `-`, `_` and dots, at most 64 characters, the same as the folder name. `omarchy.` and `omamobile.` are reserved. New widgets get `<your user name>.<name>`, Omarchy's convention for plugins you make |
| `name` | Shown in the Widgets sheet and on error cards (at most 40 characters) |
| `version`, `author`, `description` | Free text; `version` is required, as in Omarchy |
| `kinds` | Must include `"home-widget"` |
| `entryPoints.homeWidget` | A `.qml` file inside the folder |
| `homeWidget.icon` | One Nerd Font glyph for the Widgets sheet |
| `homeWidget.size`, `min`, `max` | `[columns, rows]` in grid cells. The default grid is 4 x 6 (up to 6 x 8); values are clamped to that, `size` is kept between `min` and `max`, and the user resizes within `min..max` |
| `homeWidget.capabilities` | What the widget does beyond drawing: `"commands"` (runs programs) and `"network"` (talks to the internet). Declare each one it uses, and nothing it doesn't |
| `homeWidget.defaults` | Initial settings |
| `homeWidget.schema` | Settings the user can change, in Omarchy's `barWidget.schema` format: `key`, `type`, `label`, optional `description`, `defaultValue`; `min`, `max` for numbers, `options` for `enum` |

Settings types: `string`, `path`, `integer`, `number`, `boolean`, `enum`.
The settings sheet shows a field for each, and the values arrive in the
widget's `settings` with those types. Settings are stored per placed widget
in `~/.config/omamobile/home.json`, so the same widget placed twice has two
sets of settings.

## Widget.qml

The root item fills the card; the home screen draws the card (a rounded,
mostly opaque rectangle of the theme's background), clips to it, and puts
it on the grid. Leave a margin of `Style.spacing.xl` inside it. The width
and height are the item's own `width` and `height` and change while the
user resizes.

Declare these properties. The home screen sets them before
`Component.onCompleted` and keeps them up to date:

| Property | What |
| --- | --- |
| `property var host` | The widget's link to the home screen (below) |
| `property var settings` | The manifest's defaults overlaid with the user's values |
| `property bool editing` | Edit mode is on: don't act on taps (the home screen takes them to move and resize) |
| `property int cellsWide`, `property int cellsHigh` | The size in grid cells, for layouts that change with the size |
| `property bool shown` (optional) | Someone can see the widget: its page shows, no app, app drawer or recent apps covers the home screen, and the screen is on. Run timers and animations only while it is `true` (`running: widget.shown`), and catch up once when it turns `true` again. A widget that doesn't declare it works as before |

`host` gives you:

| Member | What |
| --- | --- |
| `host.foreground`, `host.dimForeground` | Text colours that read on the card |
| `host.timeFormat` | The system's clock format (`"HH:mm"` or `"h:mm AP"`), from the status bar's 12/24-hour setting |
| `host.widgetId`, `host.instanceId`, `host.dir` | The manifest id, this placement's id, the widget's folder |
| `host.saveSettings({ key: value })` | Store settings for this placement (the user's settings sheet does the same) |
| `host.openSettings()` | Open this placement's settings sheet |
| `host.cached`, `host.setCached(value)` | A value kept across layout edits (every edit rebuilds the page and your widget with it): show the last result at once instead of fetching again |
| `host.run(argv, callback, { timeout })` | Run a program (needs `"commands"`); see below |
| `host.launch(argv)` | Start something detached, such as an app (needs `"commands"`, at most once a second). A window it opens gets a new screen (workspace) of its own, as every launch on the phone does |
| `host.openUrl(url)` | Open an `http(s)` link in the browser, on the browser's own screen (no capability needed, at most once a second). Use it instead of `Qt.openUrlExternally`, which opens the link wherever the browser happens to be |
| `host.busy`, `host.canRunCommands` | A command is running; the manifest declares `"commands"` |
| `host.shown` | The same as `shown`, for code that only has `host` |

A minimal widget:

```qml
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

Item {
  id: widget

  property var host: null
  property var settings: ({})
  property bool editing: false
  property int cellsWide: 1
  property int cellsHigh: 1

  SystemClock { id: clock; precision: SystemClock.Minutes }

  Text {
    anchors.fill: parent
    anchors.margins: Style.spacing.xl
    textFormat: Text.PlainText
    text: Qt.formatTime(clock.date, widget.host ? widget.host.timeFormat : "HH:mm")
    color: widget.host ? widget.host.foreground : Commons.Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.display
    fontSizeMode: Text.Fit
    minimumPixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

  MouseArea {
    anchors.fill: parent
    enabled: !widget.editing
    onClicked: if (widget.host) widget.host.openSettings()
  }
}
```

Several files are fine: `Widget.qml` can use `Gauge.qml` from the same
folder as `Gauge { }`, and `.js` files with `import "Logic.js" as Logic`.
Only files inside the folder.

## The Omarchy look

Widgets follow the user's Omarchy theme, and a theme switch restyles them
at once, as long as nothing is hard-coded:

* **Colours only from `qs.Commons`**: `host.foreground` and
  `host.dimForeground` for text, `Commons.Color.accent` for highlights and
  values, `Commons.Color.urgent` for warnings, `Commons.Color.muted`,
  `Commons.Color.menu.background` / `.text` / `.border`, and
  `Util.alpha(color, 0.15)` for tints and tracks. No `"#rrggbb"`, no
  `"white"`.
* **Fonts**: `Style.font.family`, sizes from `Style.font.caption`,
  `bodySmall`, `body`, `subtitle`, `title`, `heading`, `display`,
  `displayLarge`; icons are Nerd Font glyphs in the same family at
  `Style.font.icon` / `iconLarge`.
* **Spacing and shape**: `Style.spacing.xs` ... `xxl`, `huge`;
  `Style.cornerRadius` for rounding (it may be 0: square themes stay
  square).
* Import the palette as `import qs.Commons as Commons` and write
  `Commons.Color...`: Qt 6.12's own `Color` type shadows a bare `Color`.
* Text from settings, commands or the network is shown with
  `textFormat: Text.PlainText`.
* Touch targets are at least 44 logical pixels; the phone is 480 x 1040
  logical, so a cell is about 120 x 150.
* Widgets that show a time use `host.timeFormat`, so they follow the
  system's 12/24-hour choice like the built-in clock (which uses
  `HomeModel.systemTimeFormat` on the same setting).

## Performance

The panel runs at 120 Hz and the home screen is always there under the
apps. Keep a widget cheap when nothing changes:

* No blur, drop shadows, `layer.enabled`, `MultiEffect` or shader effects.
* No animation that runs forever; short transitions on a change are fine.
* Update only as often as the data changes: `SystemClock` with
  `precision: SystemClock.Minutes` (or `Hours`) rather than a fast `Timer`;
  timers no faster than once a second, and polls of commands or the network
  every few minutes at most.
* `Image` with `sourceSize` set to the size it is drawn at, and
  `asynchronous: true`.

`omamobile-widget check` warns about effects, fast timers and endless
animations.

## Running commands

Declare `"commands"`. Then use `host.run()`:

```qml
host.run(["df", "--output=pcent", "-h", Quickshell.env("HOME")], function(result) {
  // result: { code, stdout, stderr, timedOut }
  if (result.code === 0) widget.used = result.stdout.trim().split("\n")[1]
}, { timeout: 5 })
```

* `argv` is a list: no shell, so nothing in a setting or a file is ever
  run as shell code. If you really need a pipeline, `["sh", "-c", "fixed
  script", "sh", value]` passes the value as `$1`, never spliced into the
  script.
* Every command is killed after `timeout` seconds (default 10, at most 30).
* One command at a time per widget, and at most one start every 2 s: a call
  that would break either returns `false` and runs nothing. Check
  `host.busy` first if you start commands from more than one place.
* Output is cut at 64 KiB.
* Commands run as you. Never `sudo`, `pkexec`, `doas`, `run0` or `su`: the
  check refuses a widget that names them.
* Without `"commands"` declared, `run` and `launch` refuse.

A Quickshell `Process` or `Quickshell.execDetached` also works (and also
needs `"commands"`), but then the timeout and the rate limit are yours to
keep: wrap the command in `timeout 10`.

## Network

Declare `"network"` for `XMLHttpRequest`, `WebSocket`, `http(s)://` URLs
(images too) or programs such as `curl`. Ask only for what the widget
shows, send nothing about the user that the widget doesn't need, poll
slowly, and keep the last answer in `host.setCached()` so a layout edit
doesn't fetch again. Widget code itself is never fetched: no QML, JS or
`import` from a URL.

## What is checked

`omamobile-widget scan` (the home screen) and `omamobile-widget check .`
(you) apply the same checks before a new or changed widget is loaded:

* the manifest is valid (above);
* the entry point and every file are inside the folder (no links out), at
  most 64 files and 1 MiB;
* every capability the code uses is declared: a widget that runs commands
  or uses the network without declaring it is **not loaded**, and the user
  sees which one is missing;
* no root tools, no QML or components loaded from outside the folder or
  from a URL, no `Qt.createQmlObject`;
* `qmllint` (from `qt6-declarative`) finds no syntax errors, unknown types,
  unknown properties or failed imports. Its other remarks are warnings.

Then the home screen compiles the QML. Anything that fails turns that one
widget into an error card with the message; the home screen and the other
widgets carry on, and a fixed file loads again on its own. Ask the running
home screen what it thinks of a widget:

```sh
omarchy-shell shell call omamobile.home widgetStatus <id>
omarchy-shell shell call omamobile.home widgets ''
```

These checks are guard rails, not a sandbox: a widget runs inside the
Omarchy shell, with your user's rights, like any Omarchy plugin. Keep
widgets you didn't write to ones you have read.

## Examples

Copy one from the Widgets sheet (**Examples**), or by hand:

```sh
cp -r /usr/share/omamobile/shell/widget-examples/countdown ~/.config/omamobile/widgets/
```

| Example | Shows |
| --- | --- |
| `countdown` | Settings of three types, a layout that changes with the size, `SystemClock` at hour precision; no capabilities |
| `disk-space` | `host.run()` with a timeout, `host.cached`, a slow poll, a bar drawn with plain rectangles; `"commands"` |
