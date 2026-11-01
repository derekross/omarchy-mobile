<!--
The OWL language guide, by Simon Schubert and contributors, shipped with
credit under its MIT licence (full text at the end of this file).
Source: https://github.com/SimonSchubert/omalauncher
  app/src/main/assets/widgets/README.md at commit d355bdb2789f7bd1023d88b17f8a2898dc0ffa2b
The guide below is unchanged. Omarchy Mobile's notes on it follow it.
-->

> **About this copy.** This is the OWL widget language guide written by **Simon Schubert** for [Omalauncher](https://github.com/SimonSchubert/omalauncher) (`app/src/main/assets/widgets/README.md` at commit [`d355bdb`](https://github.com/SimonSchubert/omalauncher/blob/d355bdb2789f7bd1023d88b17f8a2898dc0ffa2b/app/src/main/assets/widgets/README.md)), shipped here unchanged under its MIT licence, with thanks. It describes OWL as the Android launcher runs it. Omarchy Mobile runs the same files with its own runtime; where that differs on this phone, see [Omarchy Mobile's notes](#omarchy-mobiles-notes) after the guide.

# Home-screen widgets

Each `*.owl` file in this folder is a widget on the Android home screen,
written in OWL, a small declarative language in the spirit of QML. Save a file
and it appears within a second. Then run `owl-check <file>`:

```
$ owl-check 50-memory.owl
50-memory.owl: compiles
  preview: ~/.config/omalauncher/widgets/.preview/50-memory.owl.png (3x4 cells, 528x712 px, with live data); look at it to check the layout
```

A widget with a `screen { }` (see Screens) gets a second picture, of the screen as it opens.

It waits until the launcher has loaded the file as saved, prints compile errors
and problems found while running, and exits 1 if there are any. The preview is
the tile as it looks on the home screen, at its size there, after its sources
have loaded: open it to see whether text fits and the layout works, since you
can't see the phone. Terminal tiles aren't previewed. Errors also go to
`.errors/<file>.txt`, and the tile shows them.

Widgets sit on a 6-column grid of roughly square cells (a phone has about 12
rows), bordered like Omarchy windows and colored by the current Omarchy
theme. Users move and resize them on the phone.

`examples/` holds more widgets (clocks, system stats, processes, shaders, ...).
They aren't on the home screen; read them for patterns, or move one up into
this folder to add it.

```owl
widget "memory" {
  page: 1                 // home page, 1-based
  order: 2                // placement order on the page (lower = placed first)
  size: 3x4               // preferred size in grid cells: columns x rows
  minSize: 2x3            // users can't shrink it below this

  source mem = cmd("free -b | awk '/Mem:/ {print $2, $3}'") every 5s
  let used = num(words(mem)[1])
  let total = num(words(mem)[0])
  let pct = total ? used / total * 100 : null
  let hist = history(pct, 40)

  onTap: terminal("btop")

  Column {
    Text { text: "memory"; style: muted }
    Text { text: "${round(pct)}%"; style: title; color: pct > 85 ? red : foreground }
    Progress { value: pct; animate value: spring() }
    Sparkline { values: hist; min: 0; max: 100; area: true; fill: width; weight: 1 }
  }
}
```

Every property is a live expression: when a source updates, only the parts
that read it redraw. Properties are separated by newlines or `;`.

## Declarations (top of the widget)

| declaration | meaning |
|---|---|
| `source x = cmd("...") every 5s` | runs a bash command in this Arch system; `x` is its output (stdout, trimmed). Add `json` to parse JSON output, `timeout 30s` to allow more than 10 s, `status` to get `{out, err, code, ok}` instead (see below), `optional` to let the widget work without Linux (see Without Linux). Default interval: 60 s |
| `source x = stream("...")` | a long-running command; every line it prints becomes the new value. Add `json` for JSON lines. At most 4 different streams run at once |
| `source x = http("https://...") every 10m` | an HTTP GET from Android, no curl or shell needed. Takes `json`, `timeout` and `status` like cmd (with `status`, `code` is the HTTP status and `ok` means 2xx), and optionally headers: `http(url, {Accept: "application/json"})`. The response is capped at 1 MB and the interval at 5 s or more. Prefer it over `cmd("curl ...")` |
| `source x = file("~/.cache/x.json")` | a file in this system, read again whenever it changes (no polling, no shell). Add `json` to parse it. A missing file reads as `""`; at most 1 MB is read. Prefer it over `cmd("cat ...") every 5s` (owl 4) |
| `source now = clock every 1s` | Unix time in seconds, with no shell involved. Use `fmtTime(now, "HH:mm")` |
| `source bat = android.battery` | `{level, charging, status, temp, voltage, health, plugged, technology, cycles}` from Android, updated as it changes (`temp` in °C, `voltage` in V; `health`, `plugged`, `technology` and `cycles` are null when the phone doesn't say) |
| `source dev = android.device` | the phone: `{model, maker, android, sdk, soc}` (the Linux side can't see these) |
| `source sys = android.system every 5s` | the phone's state, polled: `{kernel, uptime, memory, storage, cpu, display, build, codename, patch, locale, timezone, launcher, theme, apps}`. `uptime` is in seconds; `memory` is `{total, used, available}` and `storage` `{total, used, free}`, in bytes; `cpu` is `{soc, maker, hardware, cores, abi, maxMhz}`; `display` is `{width, height, hz, dpi}`; `patch` is the security patch date, `launcher` this launcher's version, `theme` the Omarchy theme's name and `apps` how many Android apps are installed. See `20-fetch.owl` (owl 5) |
| `source m = android.media` | what's playing in any app on the phone: `{available, playing, title, artist, album, app, package, position, duration, art}`, updated as it changes (`position` and `duration` in seconds; `art` goes in `Image { src: m.art }`). `available` is false until the user grants notification access; `media(...)` opens that setting then. See `examples/97-now-playing.owl` |
| `source n = android.notifications` | the phone's notifications, newest first, updated as they come and go: `{available, count, items}`, each item `{key, app, package, profile, icon, title, text, time, clearable}` (`time` in Unix seconds; `profile` is `work` or `clone` for a notification from a work profile or a cloned app, else null; `icon` is the app's icon for `Image { src: i.icon }`, from that profile, owl 7). Ongoing ones (music, downloads) are left out. Needs the same notification access as media. See `examples/98-notifications.owl` (owl 4) |
| `source v = android.volume` | the media volume: `{level, muted, steps}` (`level` in percent, `steps` how many the phone has), updated as it changes. Set it with `volume(...)` (owl 4) |
| `source a = android.alarm` | the next alarm set in any clock app: `{set, time, app}`, updated as it changes. `time` is in Unix seconds (`fmtTime(a.time, "EEE HH:mm")`, or `at a.time`), `app` the clock app's package (`androidApp(a.app)`); both null when no alarm is set (owl 7) |
| `source m = android.modes` | the phone's modes: `{dnd, saver, ringer, torch}`, updated as they change. `dnd` is Do Not Disturb in any form, `saver` battery saver, `ringer` is `normal`, `vibrate` or `silent`, and `torch` is null on a phone without a flash. Switch the torch with `torch(...)` (owl 7) |
| `state x = 0` | a value that handlers can change. Add `persist` to keep it across restarts: `state endsAt = 0 persist` |
| `let x = expr` | a derived value, recomputed only when what it reads changes. It can use sources, state and earlier lets |
| `let h = history(x, 60)` | the last 60 values of `x`, sampled whenever a source updates (for Sparkline). With `persist` it survives restarts, unless it's older than it would take to fill |
| `let p = prev(x)` | the previous value of `x`, for rates: `let rate = (bytes - p) / 5` |
| `component Name(a, b = 1) { ... }` | a reusable node; use it as `Name { a: 1 }` |
| `asset logo = base64"iVBOR..."` | an embedded image (under 2 MB) for `Image { src: logo }`, so the widget is one self-contained file |
| `requires { pacman: ["jq", "curl"] }` | packages the widget's commands need; see Dependencies |
| `meta { description: "..."; version: "1.0"; license: "MIT"; category: "news" }` | needed to publish to the widget store (see Sharing) |
| `meta { owl: 7 }` | the language version the widget needs (this launcher has 7; the default is 1). Older launchers say "update the launcher" instead of failing on what they don't know. `Terminal` needs 2, `sprite` 3, triggers, `file`, `Slider`, `Input`, `android.notifications`, `android.volume`, `volume` and `notification` need 4, and `screen { }`, `screen()`, `close()`, `screenWidth` and `screenHeight` need 5, `Input`'s `focus`, `sh()` and `corners` 6, and `android.alarm`, `android.modes`, `torch`, `share` and `haptic` 7; using them without declaring it is an error |
| `onTap: ...` | runs when the tile (not a button inside it) is tapped |
| `screen { ... }` | a full-screen view of the widget, opened with `screen()`; see Screens (owl 5) |
| `every 10s { ... }`, `at t { ... }`, `when c { ... }`, `on x { ... }` | statements that run without a tap; see Triggers |
| `padding: 12` / `background: ...` | the tile's padding (dp) and background |

Sources only run while their page (or a neighbour) is on screen, and
identical commands in several widgets run once. A few commands run at the same
time, so a slow one doesn't hold up other widgets.

stderr never mixes into the output, so a warning can't break `json`. A
timeout, or a non-zero exit that printed to stderr, goes to `.errors/`. A quiet
non-zero exit (grep finding nothing) doesn't. To handle failures in the widget,
add `status`: then `x.out` is the output (parsed with `json`), `x.err` is stderr,
`x.code` is the exit code (124 means it timed out), and `x.ok` is `code == 0`.

```owl
source w = cmd("curl -sf wttr.in/?format=j1") every 30m json timeout 20s status
Text { text: w == null ? "…" : w.ok ? "${w.out.current_condition[0].temp_C}°" : "offline" }
``` Keep commands fast. A command
can depend on state (`cmd("curl wttr.in/${sh(city)}")`) and re-runs with the new
value at its next interval.

## Values in commands

Put a value into a command (`cmd`, `stream`, `run`, `terminal`, `Terminal`) with `sh(value)`,
on its own and outside any quotes. `sh()` single-quotes the value, so it stays one word and
can't run as code, whatever text it holds (owl 6):

```
onTap: run("notify-send ${sh(title)}")        // right
onTap: run("notify-send '${title}'")          // wrong: a ' in title ends the quote
onTap: run("notify-send \"${sh(title)}\"")    // wrong: sh() inside quotes doesn't hold
```

Work on the value inside `sh()`: `${sh(upper(title))}`. Numbers from `int`, `round`, `floor`,
`ceil`, `abs`, `fixed`, `len`, `count`, `sum`, `min`, `max` and `clamp` need no `sh()`. A command
with a heredoc (`<<`) can't take values. The widget store only takes commands built this way;
one shared as a link shows a warning instead.

## Triggers

Statements that run on their own, written like handlers, at the top of the widget (owl 4):

| trigger | runs |
|---|---|
| `every 10s { ... }` | every 10 seconds while the page is live (on screen or next to it), like a source. At least 1 s |
| `at endsAt { ... }` | when the clock reaches `endsAt`, a Unix time in seconds, even while the page is off screen. Again for each new time; 0 or null means none. A time that passed while the launcher wasn't running runs at the next start, so set it to 0 in the statements. While the phone sleeps it can run a little late, when it wakes |
| `when cond { ... }` | each time `cond` turns true, including when it's already true as the widget starts |
| `on x { ... }` | each time `x` changes, with `value` (the new one) and `old`. Not for its first value, and null (loading) doesn't count as a change |

```owl
widget "focus" {
  meta { owl: 4 }
  source now = clock every 1s
  source bat = android.battery
  state endsAt = 0 persist
  state slide = 0
  every 8s { slide = (slide + 1) % 3 }
  at endsAt { notify("focus", "time's up"); endsAt = 0 }
  when bat.level < 15 && !bat.charging { notify("battery", "${bat.level}% left") }
  on bat.charging { notify("battery", value ? "charging" : "unplugged") }
  Button { text: endsAt > now ? "${endsAt - now}s" : "start"; onTap: endsAt = now + 25 * 60 }
}
```

`when` and `on` react to what they read: a source only updates while its page is live, so
for a deadline use `at`, which doesn't need one. A trigger that runs more than 10 times a
second is held back and reported (one that changes what it watches would otherwise loop).

## Expressions

- Numbers `12`, `0.5`, `3x2`; durations `500ms`, `2s`, `5m`, `1h` (in seconds). Strings are
  `"hi ${name}"` (interpolated) or `'raw $text'` (handy for shell commands).
  Also `"""multi-line"""`, `true`/`false`/`null`, lists `[1, 2]` and maps `{a: 1}`.
- Operators: `+ - * / %`, `== != < <= > >=`, `&& || !`, `a ?? b` (b if a is null), `c ? a : b`.
- Paths: `info.list[0].name` or `info.list.0.name`. Anything missing is `null`, never an error.
- Command output is text, but numeric text acts like a number: `used > 80` works on `"81"`.
- `null` shows as `…` in text, meaning the value hasn't loaded yet. Math and formatting
  functions pass `null` through.
- Methods are functions: `x.map(f)` is `map(x, f)`. Functions take arrow functions:
  `procs.filter(p => p.cpu > 1).sortBy(p => -p.cpu).take(5)`.

| functions | |
|---|---|
| numbers | `min max clamp(x, lo, hi) lerp(a, b, t) round(x, digits) floor ceil abs sqrt pow sin cos tan atan2 rad deg sign num(x, default) int` |
| text | `sh(x)` (one shell word, see Values in commands) `str len trim upper lower lines words split(s, sep) join(list, sep) replace(s, a, b) contains startsWith endsWith sub(s, from, to) pad(x, width, char) fixed(x, digits)` |
| format | `fmtBytes(n)` → `1.5G`, `fmtDuration(seconds)` → `2h 5m`, `fmtTime(seconds, "EEE HH:mm")` |
| weather | `weatherIcon(code, night)`: omarchy's weather glyph for a wttr.in `weatherCode` (show it with `font: icon`) |
| parsing | `match(s, regex)` (groups of the first match), `matchAll(s, regex)`, `parseJson(s)` |
| lists | `range(n)` or `range(a, b, step)`, `map filter find any all count sum avg sort sortBy reverse take drop first last indexOf unique flatten`, `keys values entries get(obj, key, default)` |
| colors | theme names `accent foreground background muted surface border red green yellow blue magenta cyan orange` plus `bright_*`, `color0`…`color15`; `#7aa2f7`; `rgb(r, g, b, a)`, `hsl(h, s, l, a)`, `alpha(c, 0.5)`, `mix(a, b, t)` |
| gradients | `linear(x0, y0, x1, y1, [colors])`, `radial(cx, cy, r, [colors])`: fills in Canvas |

Prefer theme color names: widgets then follow theme changes.

Persisted values are kept by the launcher (not in the widget file), per file name, and
must be plain data: numbers, text, lists and maps (not colors). Store times as absolute
Unix seconds (`endsAt = now + 25 * 60`), not countdowns, so they're still right after a restart.

The tile's size is available as `cols` and `rows` (grid cells) and `tileWidth` and
`tileHeight` (dp, including the tile padding). They change when the user resizes the
tile, so a widget can pick a layout to fit (`if cols < 3 { ... } else { ... }`). They're
`null` for a moment before the tile is laid out. A widget's own declaration named
`rows` or `cols` takes precedence.

`corners` is the user's corner style as a multiplier, not a radius: 0 (edge, square), 0.5
(soft) or 1 (round). Multiply the radius a shape would have on round by it: `radius: 8 *
corners` for cards and album art, `3 * corners` for small chips, and the same in Canvas
(`rect(x, y, w, h, radius: 8 * corners)`). The tile, buttons and bordered elements without a
`radius` follow it on their own; a fixed `radius`, a clipped Box, an Image or a Canvas shape
doesn't. It needs `meta { owl: 6 }`.

## Nodes

`Name { prop: value; ...children }`. Structure: `if cond { } else { }`,
`for x in list { }`, `for x, i in list key x.id { }` (a key keeps rows stable
when lists reorder), and `let x = ...` inside any node.

| node | properties |
|---|---|
| `Column` | `gap` (dp, default 4), `align: start/center/end`, `justify: start/center/end/spaceBetween/spaceAround/spaceEvenly`, `scroll: true` |
| `Row` | `gap` (8), `align: top/center/bottom`, `justify`, `wrap: true` |
| `Flow` | a Row that wraps to new lines |
| `Box` | stacks children on top of each other; `align: center/top/bottom/start/end/topStart/topEnd/bottomStart/bottomEnd` |
| `Grid` | `columns` (2), `gap`; children fill cells left to right |
| `Text` | `text`, `style: huge/title/body/small/muted/label`, `color`, `fontSize`, `bold`, `italic`, `font: mono/sans/serif/icon` (`icon` draws the Nerd Font weather glyphs U+E300–E3E3, plus 󰄬 U+F012C and 󰅖 U+F0156), `align: start/center/end`, `maxLines` |
| `Button` | `text`, `color`, `onTap` |
| `Progress` | `value`, `max` (100), `color`, `track` |
| `Ring` | circular progress: `value`, `max` (1), `color`, `track`, `thickness` (6), `start`/`sweep` (degrees; `start: 225; sweep: 270` makes a gauge). 64 dp unless sized |
| `Sparkline` | `values` (a list, usually a `history`), `min` (0), `max`, `color`, `area: true` or a color, `thickness` |
| `Image` | `src`: an `asset`, a path in this system (`"~/pics/a.png"`) or an Android app's icon (`"app:org.pkg"`, as the drawer shows it, badge included; a silhouette in the foreground color with monochrome icons; `"app:org.pkg@work"` and `"@clone"` ask for the copy in a work profile or the clone, owl 7), `fit: contain/cover/fill`, `tint` |
| `Canvas` | free drawing, below. Fills the space unless sized |
| `Shader` | an AGSL shader, below. Fills the space unless sized |
| `Spacer` | empty space: `size`, `width`, `height` or `weight` |
| `Slider` | a horizontal slider: `value`, `min` (0), `max` (100), `step`, `color`, `track`, `live`. `onChange` gets the chosen `value` when the finger lifts, or at every step while dragging with `live: true`. Full width and 28 dp tall unless sized (owl 4) |
| `Input` | a one-line text field: `text` (what it shows; replaces what's typed when it changes), `placeholder`, `color`, `fontSize`, `clear: true` (empty it after submitting), `focus: true` (focus it and raise the keyboard when the screen opens, or when `focus` turns true; only in a `screen { }`, owl 6). `onChange` gets the text as `value` as it's typed, `onSubmit` when the keyboard's send key is pressed (owl 4) |
| `Terminal` | a live terminal (foot) in the tile: `command` (default: the login shell), `fontSize` (points; foot.ini has 8). Fills the space unless sized. See below |

Every node also takes:

- `width height size` (dp), `fill: true/width/height`, `weight` (share of the
  space left in a Row or Column), `padding` (`8`, `[h, v]` or `[l, t, r, b]`)
- `background`, `border` (dp), `borderColor`, `radius`, `clip: true`
  (without `radius`, bordered elements follow the launcher's corner style: 0 for edge, 4 for soft, 8 for round;
  anything else matches it with `radius: 8 * corners`)
- `opacity`, `rotation` (degrees), `scale`, `offset: [x, y]` (dp), `visible`
- handlers: `onTap` (with `x`, `y`) and `onDrag` (with `dx`, `dy`, `x`, `y`); `Slider` and `Input` also take
  `onChange`, and `Input` `onSubmit`, both with `value`. Long-press
  belongs to the home screen, which uses it to move and resize tiles
- `animate prop: spring()` or `tween(300ms, "linear"/"in"/"out"/"ease")`, for `value`,
  `opacity`, `rotation`, `scale`, `color` or `background`. For springs:
  `spring(damping, stiffness)`

`opacity`, `rotation`, `scale`, `offset`, colors and the contents of Canvas and
Shader apply at draw time. Changing them, even every frame, costs no layout.

Handlers assign state and run actions, separated by `;` or newlines. An action whose first
value hasn't loaded yet (`…`) does nothing. After an action,
the widget that ran it refreshes its sources; other widgets keep their own intervals:
`onTap: { count = count + 1; run("notify-send hi") }`

| action | does |
|---|---|
| `terminal("btop")` | opens the command in a terminal window; `terminal(cmd, "title")` |
| `app("gtk3-demo")` | starts a graphical Linux app |
| `run("cmd")` | runs in the background (on its own shell, never retried), then refreshes this widget |
| `x = run("cmd")` | the same, and puts the command's output into the state `x` when it finishes |
| `androidApp("org.pkg")` | opens an Android app by package name |
| `copy(text)` | copies text to the Android clipboard |
| `notify("title", "text")` | posts an Android notification (if the launcher may post them) |
| `url("https://...")` | opens in the Android browser. Other links open in the app that takes them: `tel:` the dialer, `geo:` maps, `mailto:` email |
| `share(text)` | opens Android's share sheet with the text (owl 7) |
| `haptic()` | a short tap of haptic feedback, if the user has touch feedback on (owl 7) |
| `torch(true)` | turns the torch on or off; also `torch("toggle")`. Does nothing on a phone without a flash, or while the camera app holds it (owl 7) |
| `launcher("style")` | opens a launcher screen: `style` (theme, background, home screen, terminal; `themes` too), `agents`, `store`, `drawer` or `linux` (the sheet that installs Linux) |
| `refresh()` | re-runs this widget's sources now |
| `screen()` / `close()` | opens the widget's `screen { }` full screen, or closes it (owl 5) |
| `media("toggle")` | controls what's playing: `toggle`, `play`, `pause`, `next`, `previous`, or `open` (brings up the player app) |
| `volume(50)` | sets the media volume in percent; or `volume("up")`, `"down"`, `"mute"`, `"unmute"`, `"toggle"` (owl 4) |
| `notification("open", key)` | opens a notification from `android.notifications` as tapping it in the shade would; `"dismiss"` clears it. Without notification access, opens the setting that grants it (owl 4) |

## Screens

A tile is small. For more, a widget can have one full-screen view, opened by a tap: a forecast
behind a weather tile, all processes behind a CPU tile, a log behind a build status (owl 5):

```owl
widget "weather" {
  meta { owl: 5 }
  source wx = http("https://wttr.in/?format=j1") every 30m json
  let days = wx.weather ?? []
  onTap: screen()

  Text { text: "${wx.current_condition[0].temp_C}°"; style: title }

  screen {
    title: "weather"
    Column {
      scroll: true
      for d in days key d.date {
        Row { Text { text: d.date; weight: 1 }  Text { text: "${d.maxtempC}°"; width: 48 } }
      }
      Button { text: "close"; onTap: close() }
    }
  }
}
```

- It opens in the launcher's window frame, titled with `title` (default: the widget's name),
  with a ✕. Back, Home and the ✕ close it; so does `close()`.
- It's the same widget: it reads the same sources, state, lets and components as the tile,
  and a tap that changes state there changes the tile too. While it's open its sources keep
  running, whichever page the tile is on.
- It holds the same nodes as a tile. It doesn't scroll by itself: put the content in a
  `Column { scroll: true }`. `screenWidth` and `screenHeight` are its size in dp, known from its
  first frame. The tile can read them too, but there they may be `null`: use `screenWidth ?? 0`.
- One screen per widget, with up to 1000 nodes (the tile still has its own 500). For views
  within it, use a state and `if`: `state tab = "hours"`, buttons that set it, and
  `if tab == "hours" { ... } else { ... }`.

Screens are for showing more, not for building apps: there's no navigation between screens, no
lists that load as they scroll, and only the nodes above (no maps, web pages or video).

## Components

```owl
component Stat(label, value, tint = accent) {
  Column { gap: 0
    Text { text: label; style: label }
    Text { text: value; style: title; color: tint }
  }
}
Row { Stat { label: "cpu"; value: "${cpu}%"; weight: 1 }  Stat { label: "mem"; value: mem; weight: 1 } }
```

Parameters are live expressions from the caller. Layout properties like
`weight` or `padding` at the use site wrap the component. Don't name a parameter after a
property value you use inside, like `icon` with `font: icon`: the parameter wins, and the
property gets its value instead.

## Canvas

Drawing calls in dp, with `width`, `height` and `time` available. Angles are
degrees, with 0 at 12 o'clock, running clockwise.

```owl
Canvas {
  let r = min(width, height) / 2 - 4
  circle(width / 2, height / 2, r, stroke: border, width: 2)
  arc(width / 2, height / 2, r, 0, load * 3.6, stroke: accent, width: 6, cap: round)
  for i in range(12) {
    rotate(i * 30, width / 2, height / 2) { line(width / 2, 6, width / 2, 12, stroke: muted) }
  }
  text("${load}%", width / 2, height / 2, size: 18, align: center, color: foreground)
}
```

| call | |
|---|---|
| `rect(x, y, w, h)` | `radius:` |
| `circle(cx, cy, r)` | |
| `arc(cx, cy, r, start, sweep)` | filled arcs are pie slices |
| `line(x1, y1, x2, y2)` | |
| `path(points)` | points are `[x, y]` or `{x, y}`; `closed: true` |
| `text(s, x, y)` | `size:`, `color:`, `align: start/center/end`, `bold:`; y is the text's middle |
| `image(src, x, y, w, h)` | |
| `sprite(rows, x, y, pixel)` | pixel art (owl 3): `rows` is a list of strings, or one `"""` string of lines, with one letter per art pixel and `.` for empty. `palette: {b: accent, e: background}` colors each letter; letters it doesn't name aren't drawn, so one art can be drawn in parts that move separately. Without a palette every letter takes `fill`/`color`. `pixel` is the size of an art pixel in dp; edges land on whole screen pixels, so no seams show |
| `translate(x, y) { }`, `rotate(deg, cx, cy) { }`, `scale(sx, sy, cx, cy) { }`, `clip(x, y, w, h) { }`, `layer(alpha) { }` | apply to the calls inside |

Styles: `fill:` (a color or gradient), `stroke:`, `width:` (stroke width),
`cap: round/butt/square`. Without either, a shape is filled with `color:` or
the foreground. A widget that reads `time` animates every frame while it's on
screen, and only while it reads it: a `time` under an `if` that's false, like a
backdrop drawn only while music plays, costs nothing (older launchers
animate whenever `time` appears at all).

## Shader

A GPU fragment shader in AGSL (Android 13+; older phones show `fallback`).
Write `half4 main(float2 p)`. `size` (pixels) and `time` (seconds) are
declared for you. Declare your own uniforms and pass them in `uniforms`:
numbers become `float`, lists become `float2`–`float4`, colors become `half4`.

```owl
Shader {
  fallback: surface
  uniforms: { tint: accent, speed: 0.5 }
  code: """
    uniform half4 tint;
    uniform float speed;
    half4 main(float2 p) {
      float w = sin(p.x / size.x * 6.0 + time * speed) * 0.5 + 0.5;
      return half4(tint.rgb * w, 1.0);
    }
  """
}
```

## Terminal

A real terminal inside the tile, with a shell or any program (`btop`, `htop`,
a REPL) that you can type into:

```owl
widget "shell" {
  size: 6x4
  padding: 0
  meta { owl: 2 }
  Terminal { }
}
```

- The tile is inert until tapped, so swipes still turn pages. Tapping it gives it
  the keyboard and its touches (drag scrolls, hold-and-drag selects). A tap
  outside it, Back or another page lets go. The ⌨ button toggles the soft keyboard.
- The terminal keeps running while its page is off screen. It ends when the widget
  is removed or its file changes. When `command` exits, the tile offers a restart;
  use `"btop; exec bash"` to fall back to a shell.
- `padding: 0` lets the terminal fill the tile's frame.

## From scripts

Anything in this system (a script, a cron job, a pacman hook, an agent) can reach a running widget:

```
$ owl-send build.owl set status passing     # sets the state `status`; a value that parses as JSON is JSON
$ owl-send build.owl set info - < info.json   # the value from stdin
$ owl-send build.owl refresh                  # runs its sources now
```

It waits for the launcher's answer and exits 1 if the widget isn't running or has no such
state. Setting a state works like a tap setting it: what reads it redraws, and triggers run.
For data a script writes anyway, a `file(...)` source is the other way: it updates the moment
the file changes.

```owl
widget "build" {
  meta { owl: 4 }
  state status = "unknown" persist
  source log = file("~/.cache/build.log")
  Column {
    Text { text: "build ${status}"; color: status == "passing" ? green : status == "failing" ? red : muted }
    Text { text: last(lines(log)) ?? "no log yet"; style: small; maxLines: 3 }
  }
}
```

## Without Linux

Linux (this Arch system) is an optional download in the launcher. A widget that runs commands,
declares packages or has a `Terminal` needs it: without Linux its tile offers to install Linux
instead of running. Widgets with only `http`, `clock` and `android.*` sources work on any phone.
Tapping `terminal(...)` or `app(...)` without Linux opens the install sheet, so those don't
make a widget need it.

A widget can also work both ways (owl 5). Mark its Linux sources `optional`: they stay `null`
until Linux is installed and running, and `linux` says whether it is:

```owl
widget "kernel" {
  meta { owl: 5 }
  source sys = android.system every 1m
  source pkgs = cmd("pacman -Qq | wc -l") every 10m optional
  Column {
    Text { text: "kernel ${sys.kernel}" }
    if linux {
      Text { text: "${pkgs} packages" }
    } else {
      Button { text: "install linux"; onTap: launcher("linux") }
    }
  }
}
```

`optional` works on `cmd`, `stream` and `file`. Keep such a widget's commands to base tools
(coreutils, grep, sed, awk, bash, pacman): `requires` makes a widget need Linux again.

## Dependencies

Declare every package your commands need, by package manager:

```owl
widget "grok" {
  requires { pacman: ["jq", "curl"] }
  source info = cmd('jq -c . ~/.cache/usage.json') every 5m json
  Text { text: "${info.use}%" }
}
```

- When a declared package is missing, the tile says `needs jq` with an **install** button
  instead of running the widget. That runs `pacman -Syu --needed`, the same way the system was
  set up. If it fails, the tile offers **fix with agent**.
- Names are package names, not program names (`dig` comes from `bind`). Find the owner of a
  program with `pacman -F dig` or `pacman -Qo $(command -v dig)`.
- Base tools (coreutils, grep, sed, bash) are always there; declaring them is optional.
- The launcher also reads the programs your fixed commands run. If one isn't installed and
  isn't covered by `requires`, `.errors/<file>.txt` gets a warning.
- While writing a widget, install what you declare with `pacman -S --needed <packages>`.

## Sharing

The **widget store** (long-press empty space on the home screen) installs reviewed widgets from
https://github.com/SimonSchubert/omarchy-widgets. To publish one you made, long-press it and tap
**publish**: the default agent opens a pull request there with the GitHub CLI (or an issue, if it
can't). By hand, open a pull request that adds it as `widgets/<github-username>/<name>/widget.owl`.
The store needs:

- `meta` with a `description` (10-200 characters), a `version` and a `license`, and ideally a `category`:
  `news`, `dev`, `productivity`, `time`, `world`, `fun`, `home` or `system`
- every package in `requires`
- values in commands passed through `sh()` (see Values in commands)
- nothing personal: no tokens, personal paths or hard-coded location
- a higher `version` for each update
- ideally a `preview.png` next to it: the one `owl-check` points to will do

The repo's CI checks the rules and summarizes every command for the reviewer. Store installs go on
the page you're on; `page:` and `order:` in the file only apply to widgets you add yourself.

To pass a widget on without the store, share it as a link or QR code: the whole file is in it,
after the `#` of `https://simonschubert.github.io/omarchy-widgets/w#owl1.<data>` (raw DEFLATE, then
unpadded base64url), so it never reaches a server. One code holds about 2.9 KB of that, which most
widgets under 6 KB fit. Scanning it opens the launcher, which lists every command the widget runs and
flags risky ones before it adds it as `shared-<name>.owl`: nobody reviewed it. On Omarchy, the Widgets
app's **Share…** shows the code, and `omarchy-widgets share` / `omarchy-widgets import` make and read
links.

## Limits

A widget has at most 500 nodes, 2000 drawing calls per frame, lists of 1000
items, and a step budget per update. A widget that draws slowly animates at
half rate. Errors never take the home screen down: the failing value shows `…`
and the message goes to `.errors/`.

## Tips

- One small, focused widget per file; name files `NN-name.owl` to order them.
- Test commands in a terminal first. For several values, print JSON and use `json`.
- The phone is portrait: 6 columns, ~12 rows. A full-width widget is `6xN`,
  half-width `3xN`. Set `minSize` to what the layout still fits in.
- Use `weight: 1` to fill leftover space and `fill: width` to stretch across.
- A `Text` without `width`, `weight` or `fill` takes the full width. In a `Row`, give the Texts
  next to a `weight: 1` one a `width`, or the weighted one is squeezed to nothing.
- Look at the example widgets in this folder for patterns: `90-analog-clock` (Canvas),
  `91-focus` (state, buttons and `at`), `92-aurora` (Shader), `93-latency` (stream),
  `88-notes` (Input), `98-notifications` (android.notifications), `99-volume` (Slider),
  and next to it `10-today` (a weather screen behind the tile), `20-fetch` (fastfetch as a dashboard), `45-terminal` (a live terminal) and
  `60-owl` (sprites).

---

## Omarchy Mobile's notes

Omarchy Mobile runs OWL widgets with its own runtime (`/usr/share/omamobile/shell/plugins/omamobile.home/owl/`), held to the reference runtime by a conformance suite. Where the guide is silent, the decisions are in [SPEC-NOTES.md](https://github.com/derekross/omarchy-mobile/blob/main/packages/omamobile-shell/plugins/omamobile.home/owl/SPEC-NOTES.md) (installed as `/usr/share/omamobile/shell/plugins/omamobile.home/owl/SPEC-NOTES.md`). Where this phone differs from the guide:

- **Where widgets live.** One folder per widget, `~/.config/omamobile/widgets/<author>.<name>/widget.owl`, not `NN-name.owl` files; `page:` and `order:` are ignored (the home screen places widgets). There is no `owl-check` or `owl-send` yet; `omarchy-shell shell call omamobile.home owlStatus <id>` reports whether a widget compiles, its problems, its commands and its approval.
- **Approval.** Nothing runs until the user approves the widget's exact list of commands, web addresses and files (and, separately, the internet, vibration and the torch). A widget that changes that list asks again.
- **Grid and sizes.** Our home screen's grid is 4x6 by default; sizes convert from the guide's 6-column grid, and `cols`, `rows`, `tileWidth` and `tileHeight` describe our card.
- **Limits.** Commands run at most every 2 s, time out after 30 s at most, and their output is cut at 64 KiB; `http` runs at most every 60 s, and only with the internet turned on; two `stream`s at most on the home screen; one action a second.
- **Dependencies.** `requires` is shown, never installed by the widget.
- **Screens** open in place of the tile (with "‹" to go back), as Omarchy Mobile's own widgets show their longer views.
- **Pictures** load from local files and embedded assets only, not from web addresses.
- **Android.** `android.notifications` and `android.alarm` are empty; `androidApp()` and `notification()` do nothing (no Android here); `android.media`, `volume`, `modes` and `system` come from MPRIS, PipeWire, the torch LED, mako and `/proc`. `Shader` draws its `fallback`.
- **`on x { }`** doesn't fire for x's first value, as the guide says.
- **Live means on screen.** Sources, `every` and animation run only while the widget's page shows (its neighbours too while the pages are being swiped) and no app, app drawer, recent apps or call card covers the home screen, with the screen on. Shown again, what fell due runs once. Animation runs at 20 fps, 30 while you touch the widget, and half that for a widget whose frames take too long.

---

## Licence of the guide above

MIT License

Copyright (c) 2026 Simon Schubert and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

This license does not cover the third-party files listed in THIRD_PARTY.md,
including the coding agents' logos, which remain the trademarks of their owners.
