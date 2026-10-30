<!-- SPDX-License-Identifier: MIT -->
# Widget interop plan: OWL widgets on the Omarchy Mobile home screen

**Status (2026-10-14):** merged into main after the owner's review on the phone: P1-P5, P8, P9 (the 47 built-ins are the OWL originals; layouts migrate) and P11, parts of P6-P7; the user's own OWL folders and the Store tab sit behind `{"owlWidgets": true}` in `~/.config/omamobile/features.json`. Review package and runbook in [owl-review/](owl-review/README.md). Left: phone measurements, the first haptic and torch tests, OWL Input with squeekboard, P7 and P10. Originally design only. Written 2026-10-13 and revised the same day: we write our own OWL runtime instead of vendoring Simon Schubert's. Implementation starts after the installer and reinstall work ([RELEASES](RELEASES.md) §6).
**Goal:** one widget catalogue for Omalauncher and Omarchy Mobile. A widget written for one runs on the other, and a person who uses both phones has one set of widgets.
**Recommendation in one line:** write **our own OWL runtime for Quickshell** from the language specification, held to Simon's runtime by a conformance suite that runs on the laptop (§7). Make OWL the default format for new and AI-made widgets, and keep QML widgets for power users. Replace our 47 hand ports with the upstream `.owl` files as our runtime passes conformance for each one.

Sources read for this plan (all MIT, Copyright (c) 2026 Simon Schubert and contributors):

| Repository | Commit | What was read |
| --- | --- | --- |
| [omarchy-widgets](https://github.com/SimonSchubert/omarchy-widgets) | `b63886b` (2026-10-14 00:13 +0200) | `README.md`, `docs/LANGUAGE.md`, `order.txt`, `w/index.html`, `tools/verify-pr.sh`, all of `runtimes/quickshell/`, the 105 `widget.owl` files as data |
| [omalauncher](https://github.com/SimonSchubert/omalauncher) | `d355bdb` (2026-10-14 00:01 +0200) | `README.md`, `app/src/main/assets/widgets/README.md` (the full language guide), `owl/.../market/Review.kt` and `Catalog.kt` |

Nothing from either repository was built or run. `tools/owl.jar` was not run.

On our side: [`packages/omamobile-shell/plugins/omamobile.home`](../packages/omamobile-shell/plugins/omamobile.home) (`Home.qml`, `HomeModel.js`, `WidgetHost.qml`, `PortedWidget.qml`, `UserWidgetCell.qml`, `UserWidgets.js`, `ported/`), [`bin/omamobile-widget`](../packages/omamobile-shell/bin/omamobile-widget), [`widgets/WIDGETS.md`](../packages/omamobile-shell/widgets/WIDGETS.md) and [`plugins/README.md`](../packages/omamobile-shell/plugins/README.md), with `omamobile-shell` at 0.1.47.

### Our own code, Simon's runtime as a reference only

The MIT licence would let us copy Simon's runtime. We choose not to: if he stopped maintaining it, we would be left with code we don't know. These rules apply to every phase:

* **Specification first.** The runtime is written from the full guide (Omalauncher's `app/src/main/assets/widgets/README.md`, level 7) and the store's `docs/LANGUAGE.md`.
* **The reference runtime is read for meaning, not copied.** Where the guide is silent or ambiguous, we read Simon's `runtimes/quickshell/` (and run it as a black box in the conformance container, §7) to learn what a construct *does*. Then we write the answer in our own words in `owl/SPEC-NOTES.md`, one numbered entry per decision, with the guide section it clarifies. That way our implementation follows a written rule, not someone else's code.
* **No file, function or block from his runtime enters our tree.** His repository is checked out only inside the test container, at a pinned commit. Reviews of runtime patches check for copied code.
* **Test data is not code.** The store's widgets, and his `test/edge.owl` and fixtures, are inputs to the conformance suite. They are fetched into the container at the pinned commit and never committed to our repository.

---

## 1. OWL and our widget contract

### 1.1 How OWL works

OWL ("a small declarative language in the spirit of QML") describes one widget per file. The Android launcher draws it with Jetpack Compose. Simon's `runtimes/quickshell/` draws the same file with Quickshell. The reference implementation is the Kotlin `owl` module in Omalauncher, and `tools/owl.jar` is built from it.

**There are two language documents, and they differ.** The store's `docs/LANGUAGE.md` (288 lines) is an older subset. The launcher's `widgets/README.md` (529 lines) documents level 7 in full: `http`, `file`, `status`, `optional`, triggers, screens, `Slider`, `Input`, `Terminal`, `android.media`/`notifications`/`volume`/`alarm`/`modes`, and the `owl:` version table. Simon's Quickshell runtime implements level 7. **Our runtime is specified by the full guide**, and §8 proposes that it become the published, versioned spec in the store repository.

| Area | What OWL has |
| --- | --- |
| Structure | `widget "name" { … }`, with declarations at the top and then one node tree. Properties are live expressions: when a source updates, only what reads it redraws. `component Name(a, b = 1) { … }` defines reusable nodes. `if`/`else` and `for x, i in list key k` work inside nodes |
| Values | Numbers, durations (`5m`), `3x2` sizes, interpolated strings `"${x}"`, raw `'…'`, `"""…"""`, lists, maps. A missing path is `null`, never an error, and `null` shows as `…`. Numeric text acts as a number. Arrow functions work, and methods are functions (`x.map(f)`) |
| Builtins | Math, text, `fmtBytes`/`fmtDuration`/`fmtTime`, `match`/`matchAll`/`parseJson`, list operations, colours (`rgb`, `hsl`, `alpha`, `mix`), gradients, `weatherIcon`, and `sh(x)`, which quotes a value as one shell word (owl 6) |
| Data sources | `cmd("…") every 5s [json] [timeout 30s] [status] [optional]`: `bash -c`, default every 60 s, 10 s timeout. `stream("…")`: one line is one value, at most 4 streams. `http(url, headers) every 10m`: GET only, at most 1 MB, an interval of at least 5 s. `file("~/…")`: watched, at most 1 MB. `clock every 1s`. `android.battery`/`device`/`system`/`media`/`notifications`/`volume`/`alarm`/`modes` |
| State | `state x = 0 [persist]`, `let`, `history(x, n) [persist]` and `prev(x)`. Persisted state belongs to the host and is keyed by file name |
| Triggers (owl 4) | `every 10s { }`, `at t { }` (fires at a Unix time even while off screen), `when cond { }`, `on x { }`. A trigger that runs more than 10 times a second is held back |
| Nodes | `Column` `Row` `Flow` `Box` `Grid` `Text` `Button` `Progress` `Ring` `Sparkline` `Image` `Canvas` (drawing calls, `sprite` pixel art) `Shader` (AGSL, with a `fallback`) `Spacer` `Slider` `Input` `Terminal` |
| Every node | Size, `fill`, `weight`, `padding`, `background`, `border`, `radius`, `clip`, `opacity`, `rotation`, `scale`, `offset`, `visible`, `onTap(x, y)`, `onDrag(dx, dy, x, y)`, `animate prop: spring()/tween()` |
| Actions | `run(cmd)` and `x = run(cmd)`, `terminal(cmd)`, `app(cmd)`, `url(link)`, which also takes `tel:`/`geo:`/`mailto:`, `copy`, `notify`, `share`, `haptic`, `torch`, `media(op)`, `volume(v)`, `androidApp(pkg)`, `notification(op, key)`, `launcher(screen)`, `refresh()`, and `screen()`/`close()` |
| Screens (owl 5) | `screen { title: …; … }`: one full-screen view of the same widget, with up to 1000 nodes |
| Theming | Theme colour names: `accent foreground background muted surface border red green yellow blue magenta cyan orange`, plus `bright_*` and `color0`-`color15`. Hex and functions also work. `corners` is the user's corner style as a multiplier, 0, 0.5 or 1 |
| Sizing | Phone grid of 6 columns by about 12 rows, with roughly square 69 dp cells. `size: 3x4` and `minSize: 2x3` are in those cells. `cols`/`rows`/`tileWidth`/`tileHeight`/`screenWidth`/`screenHeight` are readable, so a widget can change layout with its size |
| Settings | None as such. A widget keeps its configuration in `state … persist`, usually set from an `Input` on its `screen`. The store forbids personal values hard-coded in the file |
| Dependencies | `requires { pacman: ["jq", "curl"] }`. A missing package turns the tile into "needs jq" with an **install** button that runs `pacman -Syu --needed` |
| Metadata | `meta { description; version; license; category; owl: N }`. `owl: N` is the language level the widget needs. Using a newer feature without declaring it is a compile error, and an older launcher says "update the launcher" |
| Limits | 500 nodes per tile and 1000 per screen. 2000 drawing calls per frame, lists of 1000, and a step budget per update (200,000 in the reference runtime). Errors show `…` and go to `.errors/<file>.txt`. "Errors never take the home screen down" |
| Scripts | `owl-send file.owl set state value` and `refresh`, from any process (launcher only) |
| Sharing | The reviewed store, plus links: `https://simonschubert.github.io/omarchy-widgets/w#owl1.<raw DEFLATE, base64url>` (about 2.9 KB per QR code) or `#dpaste.<id>` for larger widgets |
| Review | `owl.jar review` (CI): `meta` rules, `requires` checked against Arch, values in commands only through `sh()` or numbers, and a list of risky command patterns (download piped to a shell, `rm -rf`, `sudo`, `base64 -d`, `eval`, `dd`/`mkfs`, reads of `.ssh`/tokens, commands built at run time, notification access…). The compiler lists every command a widget can run, every `http GET` and every file it reads |
| Versioning | Two separate numbers: the language level `owl: 1..7`, and each widget's `meta.version`, which the store requires to rise. If an update changes commands or packages, the app asks the user to approve it again |

How the 105 store widgets use it (from a grep of `b63886b`): language levels: 31 undeclared (level 1), one at level 3, two at 4, 44 at 5, 24 at 6, and three at 7. They use `cmd` 60 times, `Canvas` 38, `url()` 38, `requires` 65, `persist` 47, `Input` 29, `http` 22, `terminal()` 18, `android.*` 14, `file` 11, `androidApp` 9, `Terminal` 3, `Shader` 2, `stream` 2 and `onDrag` 3.

### 1.2 The reference Quickshell runtime, for orientation

What Simon's runtime is made of, as far as we need it to design ours and to drive it as an oracle. We use it, and do not copy it.

| File | Lines | Role |
| --- | --- | --- |
| `Owl.js` | 3080 | Language core with no QML (it also runs under node). `compile()` returns name, sizes, sources, triggers, an `animated` flag and **`commands`**, a static list of what the widget can run |
| `OwlWidget.qml`, `OwlSource.qml` | 412 + 257 | A live widget (file watch, persisted state, triggers, frame clock, `.errors/`), and its sources |
| `OwlNode.qml`, `OwlLayout.js`, `OwlCanvas.qml`, `OwlTerminal.qml` | 784 + 307 + 55 + 202 | Rendering, with Compose's Row/Column measure rules, a 69 dp cell and monospace text |
| `OwlHost.qml`, `owl-source` | 115 + 231 | Embedding: fonts, `dp`, `stateDir`, actions, media, a keyboard hook. `android.*` answered from Linux |
| `test/run.sh`, `walk.js`, `OwlOracle.java` | | Hold `Owl.js` to `owl.jar` with JSON walks of evaluated properties and drawing calls: 198 edge expressions, fixtures, and every store widget |

The last row is what makes conformance possible without copying: **a widget, the data its sources returned, and a JSON dump of every evaluated property and drawing call.** We build the same kind of dump for our runtime and compare (§7).

The reference behaviour on Linux, according to its README: `Shader` draws its `fallback`, `Terminal` is a pseudo-terminal of its own, `android.notifications` is empty, `androidApp()` and `notification()` report that there is no Android, and `android.alarm` is never set. We match these behaviours unless we have a better answer on the phone (`androidApp` through Waydroid, §3.3).

### 1.3 Our contract, for comparison

A user widget is a folder `~/.config/omamobile/widgets/<id>/` with an Omarchy-style `manifest.json` (kind `home-widget`, a `homeWidget` block with `size`/`min`/`max` cells, `capabilities`, `defaults` and a settings `schema`) and a `Widget.qml`. The QML gets a narrow `host` (`WidgetHost.qml`): theme text colours, `timeFormat`, `saveSettings`/`openSettings`, `cached`/`setCached`, `run(argv, cb, {timeout})` (argv with no shell, at most 30 s, one command at a time, one start per 2 s, output cut at 64 KiB), `launch` (once a second) and `openUrl` (http(s) only, once a second). `omamobile-widget scan|check` validates the manifest, keeps files inside the folder (at most 64 files and 1 MiB), detects use of commands and network by regex and **refuses widgets that use an undeclared capability**, refuses root tools, `Qt.createQmlObject` and remote imports, and runs `qmllint`. `UserWidgetCell.qml` compiles each widget synchronously into its own cell, turns failures into an error card, and records each load in `widget-guard.json`. A widget whose load crashed the shell is held back at the next start until the user acts. Built-ins are `REGISTRY` entries in `HomeModel.js`. The 47 ports in `ported/<id>/Widget.qml` (11,541 lines in total) use the same host, through `PortedWidget.qml`. Ports that use the network stay off until the user turns them on.

### 1.4 Gap table

**What OWL has that our contract lacks:**

| OWL feature | Our side today | Needed for interop |
| --- | --- | --- |
| A declarative, budgeted language | Arbitrary QML | Our runtime (§2) |
| Static list of every command, URL and file | Regex detection plus a declaration | Our compiler emits the same list, and approval uses it (§3) |
| Live sources with intervals, `stream`, `file` watch | `host.run` with callbacks | Runtime data sources (§2.5) |
| Triggers (`every`/`at`/`when`/`on`) | Hand-written timers | Runtime scheduler (§2.6). `at` keeps one 1 s timer running off screen |
| `screen { }` full-screen view | Settings sheet only | A host surface for screens (§4.4) |
| `Input`, `Slider`, `Terminal` | Any QML | Renderer nodes. `Terminal` comes last and is opt-in (§2.4) |
| `requires { pacman }` with an install button | None, since agents may not install | No silent root install (§3.3) |
| `android.media/battery/volume/modes` | Media and battery widgets of our own | Host sources from MPRIS, UPower, `wpctl`, DND and the torch |
| `notify`, `copy`, `share`, `haptic`, `torch`, `volume`, `media` | Not in `host` | Host actions (§3.4) |
| `meta.version`, `owl:` level, categories | `version` is free text | Read them from `meta` |
| Store, review CI, shared links, previews per theme | Examples folder only | §5 |
| `owl-send` from scripts | None | Later, through `omarchy-shell shell call omamobile.home owlSend …` |

**What our contract has that OWL lacks:**

| Our feature | OWL today | Interop approach |
| --- | --- | --- |
| A settings `schema` per widget, a settings sheet, **settings per placement** | No schema. State is per file name, so the same widget placed twice shares its state | Our runtime keys persisted state by placement. Propose a `settings { }` declaration upstream (Q4) |
| A capability declaration, refused when missing | Commands are listed, not declared | Approval stores a capability set derived from the list (§3) |
| Network ports off until turned on | Network runs at once | The same opt-in for OWL widgets that use the network (§3) |
| `host.timeFormat`, the system's 12/24-hour setting | `fmtTime(now, "HH:mm")` with a fixed pattern | Propose a `timeFormat` tile variable (Q5). Not overridden by us: that would change rendering against the reference |
| Location from GeoClue, rounded to about 1 km (`useLocation` in 7 ports) | IP location through wttr.in, or a typed city | Propose a coarse `location` source (Q6). Keep those ports until it exists |
| Commands as argv with no shell | `bash -c` strings, with values safe only through `sh()` | Accept `bash -c` for OWL, since the commands are static and listed, and refuse store-rule violations (§3.2) |
| A crash guard per widget (`widget-guard.json`) | "Errors never take the home screen down" (evaluator level) | Our runtime isolates errors and reuses the guard (§2.7) |
| Cache that survives layout edits (`host.cached`) | Not needed | Our runtime instances outlive cell rebuilds (§2.7) |
| `editing` mode (taps go to the editor) | Long-press belongs to the home screen, the same model | Handlers disabled while editing |
| 120 Hz performance rules (no endless animation, no effects) | `time` animates every frame | Our scheduler: 20 fps, 30 while touched, paused when hidden (§2.6) |
| Card look: rounded, mostly opaque theme background | Square 2 dp `muted` frame | Our card, with Omarchy's corners (`Style.cornerRadius`: square by default) and the widget's `padding` inside |

---

## 2. Integration options and our runtime

### 2.1 Options

| Option | What | Verdict |
| --- | --- | --- |
| **(a) Vendor Simon's Quickshell runtime** at a pinned commit, or depend on a package of it | Copy `runtimes/quickshell/` into our plugin folder and embed it through `OwlHost` | **Rejected** (decided 2026-10-13). The fidelity would be the best possible on day one, but our widget platform would rest on code we didn't write and can't steer: if upstream stopped maintaining it, we would own 5,000 lines we don't know, with no oracle that tracks new levels. Being able to copy legally (MIT) doesn't change that risk |
| **(b) Translate OWL to QML at install time** | A compiler from `.owl` to `Widget.qml` and `manifest.json` | **Rejected.** OWL's meaning lives in an evaluator (null propagation, numeric text, budgets, `history`/`prev`, triggers, keyed lists, Compose layout). A translator either embeds an evaluator anyway, which is (c) with extra steps, or emits arbitrary QML again with all its crash risk, and every upstream change would mean re-translating installed widgets |
| **(c) Our own OWL runtime for Quickshell**, written from the spec, checked against the reference runtime by a conformance suite | §2.2-2.7 and §7 | **Chosen** |
| **(d) Converge on OWL** as the main format for user and AI widgets, with QML for power users | Policy on top of (c) | **Chosen** with (c) |

### 2.2 Why our own runtime, and OWL by default

1. **Safety.** OWL can't instantiate arbitrary QML types, reach the shell's objects, call `Qt.createQmlObject` or import code. Our evaluator caps nodes, drawing calls, list sizes and steps per update, so a runaway widget becomes an error in one tile, not a hung shell. A QML widget can do all of those things. OWL is **not** harmless: `cmd()` is `bash -c` with the user's rights. The gain is that every command is fixed text in the file (or flagged as built at run time), so the user can see and approve exactly what runs (§3). For AI-made widgets this is the main reason: an agent's mistake in OWL is a `…` on a tile, while in QML it can be a crash loop.
2. **Control.** Our runtime is ours to design for the phone: dependency tracking so only changed bindings re-evaluate, frame pacing, the panel-off pause and our host capabilities. It has no assumptions from a launcher to patch around, and its life doesn't depend on another project's.
3. **Interop.** The file format, not the runtime, is what has to be shared. The conformance suite (§7) keeps us faithful to how Omalauncher and the reference runtime draw the same file, and §8 makes the spec something both projects own.
4. **Maintenance.** We maintain one language implementation of about 5-6k lines instead of hand-porting widgets (11,541 lines of ports today, growing with each store widget).

### 2.3 Architecture

```
widget.owl ──▶ lexer ──▶ parser ──▶ AST ──▶ compiler ──▶ IR (Program)
                                               │            ├─ declarations: sources, state, lets, triggers, components, assets
                                               │            ├─ node templates with compiled expressions (closures)
                                               │            ├─ level used / declared, the commands list, capabilities
                                               │            └─ errors with line, column and a caret
                                               ▼
                                 Instance (one per placement)
          sources ──values──▶  evaluator: state, lets, history/prev, dependency graph, budgets
          scheduler ──ticks──▶       │
          taps/drags ──────▶  handlers: assignments and actions ──▶ host (capability-checked)
                                     ▼
                              render tree (plain objects, stable keys)
                                     ▼
                   renderer: one QML item per node, updated in place
```

Layers, from the bottom, each in its own file under `plugins/omamobile.home/owl/`:

| Layer | Files (planned) | Rules |
| --- | --- | --- |
| **Lexer and parser** | `lexer.js`, `parser.js` | Pure JS (ES5, which the QML V4 engine and node both run), no QML imports, so node can test it. A hand-written recursive-descent parser. Comments, `;` or newline separators, the string kinds, durations and `NxM` sizes. Errors carry a position, and `format.js` prints them with a caret, the form agents are told to read |
| **Compiler and IR** | `compiler.js`, `ir.js` | Resolves names (sources, state, lets, components, theme names, tile variables), checks arity and node and property names against tables generated from the spec, computes the **level used** by each feature and refuses a widget that uses more than it declares (`… needs owl N: add meta { owl: N }`) or declares more than we support. Builds the **commands list**, the same strings the reference compiler lists (§3.1). Compiles expressions to closures once. Counts nodes against the 500 and 1000 caps |
| **Evaluator** | `eval.js`, `builtins.js`, `values.js` | Value semantics from the guide (null pass-through, numeric text, paths, `??`, methods as functions). Builtins table. `let` dependency graph, so a source update re-evaluates only the lets and properties that read it. `history`/`prev` sampling. **Resource caps**: a step budget per update (the same 200,000 as the reference, so widgets that pass there pass here), lists of 1000, 2000 drawing calls per frame, a maximum string length, recursion depth for components, and a trigger rate limit of 10 per second. A cap that is hit throws a widget error: the value shows `…`, and the message goes to `.errors/` |
| **Renderer** | `OwlView.qml`, `nodes/*.qml`, `layout.js` | Maps each render-tree node to one QML item, keyed by position and `key` so that updates set properties instead of rebuilding. Layout follows the guide's rules (Row/Column gap and weight, `fill`, `justify`, `align`, `wrap`, the default sizes, the "Text without width takes the full width" rule) in `layout.js`, so node can check measurements apart from fonts. Text uses our font metrics. `Canvas` replays drawing calls onto a QML `Canvas`. `sprite` draws to whole pixels. `Shader` draws its `fallback`. `animate` uses QML spring and number animations with the guide's curves. **No live effects:** an `Image` `tint` is drawn once into a cached recoloured copy for each image and colour |
| **Data sources** | `sources/*.qml` | `cmd`, `stream`, `http`, `file`, `clock` and `android.*`, each calling **our host** (`OwlPhoneHost`), never `Process` directly, so the capability and limit checks live in one place (§3) |
| **Scheduler** | `scheduler.qml` | One shared timer wheel for source intervals, triggers and animation frames, rather than a `Timer` per source. **Animation at 20 fps, 30 while touched** (a frame clock, not 120 Hz `FrameAnimation`). Sources and frames run only for the page on screen (its neighbours only while the pages are swiped), and are paused when an app, the drawer, recent apps or the call card covers the home surface, or the panel is off (gs-decon `screen_off`); shown again, what fell due runs once. A neighbour kept live cost a hidden koi pond about 118 % CPU (0.2.44). `at` triggers keep running while paused, as the guide requires, through one coarse timer (10 s). Identical commands across widgets run once, as the guide says |
| **Host** | `OwlPhoneHost.qml` | Theme palette, fonts, `dp`, tile variables, persisted state per placement, actions, the `fieldFocused` keyboard hook and `.errors/` writing |

**Where the core runs.** The core is JS in the shell's QML engine, as our home-screen logic already is (`HomeModel.js`, tested under node). It needs no compiled module, which Omarchy plugins don't support. The IR is kept plain data, so that if the phone measurements in P5 (§9) show the evaluator is too slow, the evaluator can move into a Qt C++ QML module later without changing the parser, compiler, tests or renderer.

### 2.4 Scope by level

| Level | Features | Our first release |
| --- | --- | --- |
| 1 | Core language, nodes, `cmd`/`stream`/`clock`/`android.battery`/`device`, actions | Yes |
| 2 | `Terminal` | **Later** (P11). Store widgets that use it (3) show "not supported on this phone yet" |
| 3 | `sprite` | Yes |
| 4 | Triggers, `file`, `Slider`, `Input`, `android.notifications`/`volume`, `volume`, `notification` | Yes. `android.notifications` reads our notification history only after approval (§3.1) |
| 5 | `screen { }`, `screen()`/`close()`, `screenWidth`/`screenHeight`, `optional`, `http` (documented with level 5 examples) | Yes |
| 6 | `Input.focus`, `sh()`, `corners` | Yes |
| 7 | `android.alarm`/`modes`, `torch`, `share`, `haptic` | Yes. `alarm` is never set, as in the reference |

We ship at **level 7 minus `Terminal`**, which covers 102 of the 105 store widgets.

### 2.5 Data sources and host capabilities

| Source | Our implementation | Host check |
| --- | --- | --- |
| `cmd` | `bash -c` through the host, which applies the clamps in §3.3. `stderr` is kept apart, so a warning can't break `json`. `status` gives `{out, err, code, ok}` | `commands` approved |
| `stream` | A long-running process with a line splitter, restarted after 5 s if it exits. At most 2 streams across the home screen | `commands` approved |
| `http` | `XMLHttpRequest` GET with headers, a timeout and a size cap | `network` approved and turned on |
| `file` | `FileView` with a change watch, at most 1 MB | `files` approved. Private paths need a separate confirmation |
| `clock` | The scheduler's second and minute boundaries | None |
| `android.battery` | UPower's display device (what our status bar reads) | None |
| `android.media` | MPRIS (what our media widget reads) | None |
| `android.device`/`system` | `/proc`, `/sys` and the device tree (model, SoC, memory, storage, display Hz from DRM), plus a `linux` part from pacman's database | None |
| `android.volume` | `wpctl` on the default sink | None |
| `android.modes` | `dnd` from Omarchy's notification daemon, `torch` from the LED class device. `ringer` stays `normal` until there are calls, and `saver` is `false` | None |
| `android.notifications` | Our notification history, newest first, in the guide's item shape | `notifications` approved |
| `android.alarm` | `{set: false}` | None |

### 2.6 Scheduler and timing

* One clock for everything. Source intervals are aligned to their period. The clock source turns over on the boundary (`every 1m` ticks on the minute).
* Animation (`time`, springs, tweens, Canvas that reads `time`) runs from a frame clock **at 20 fps, 30 for 3 s after a touch**, and only while a node that reads `time` is visible, as the guide describes ("only while it reads it"). A widget that misses its 20 ms frame budget (its JS, layout and Canvas paints) drops to half rate, matching the guide's "animates at half rate".
* **Paused when hidden.** The scheduler stops sources, `every` triggers and frames when the page and its neighbours are off screen, an app covers the home surface, or the panel is off. It resumes with one refresh, so a widget never shows hours-old data after waking. `at` triggers fire on resume if their time has passed, as the guide requires after a restart.

### 2.7 Error isolation and the crash guard

* **Compile errors** turn that cell into the error card, with the caret message and "Tap to fix with AI", and write `.errors/<id>.txt`.
* **Run-time errors** (a cap that was hit, a bad value) show `…` in place and are appended to `.errors/` (deduplicated, the last 20 kept), as the guide describes.
* **Renderer faults** that could still take the shell down (a QML binding loop in our node code, a huge image, a Canvas that stalls the scene graph) are covered by the **existing crash guard**: `OwlCell` calls `guardBegin(id, hash)` before the first render and `guardEnd` after it has run for 3 s, as `UserWidgetCell` does. A widget whose load crashed the shell is held back at the next start. Every crash we find this way becomes a conformance test and a fix in our runtime.
* **Instances outlive cells.** Layout edits rebuild Home's cells. The OWL instance (state, source values, history) lives in a per-placement registry in `Home.qml`, so a rebuild reattaches without re-running sources, which is what `host.cached` does for QML.

---

## 3. Safety model

### 3.1 From "declare or refuse" to "listed, derived and approved"

For QML we can't know statically what a widget does, so the manifest declares capabilities and the scan refuses code that uses an undeclared one. For OWL, our compiler produces the exact list, so capabilities are **derived**, and the user approves the list once per content hash:

| OWL construct | Listed by our compiler as (the same strings as the reference) | Capability |
| --- | --- | --- |
| `cmd`, `stream`, `run`, `x = run`, `terminal`, `app`, `Terminal` | The command text, or "built from widget values" | `commands` |
| `http(url)` | `http GET <url>` | `network` (with the hosts listed) |
| `cmd("curl …")`, `wget`, or `requires` with `curl`/`wget` | The command text | `network` too: our existing regex runs over the listed commands |
| `file(path)`, and `Image { src: "~/…" }` | `read file <path>` | `files` (new, shown, not refused) |
| `android.notifications` | `read Android notifications` | `notifications` (new). Our notification history counts as private |
| `notify`, `copy`, `share`, `haptic`, `torch`, `volume`, `media`, `url` | Not listed | Allowed, but rate-limited (§3.3) |

`omamobile-widget scan` gains an OWL branch. It compiles with our runtime's core under node (§6.2), stores `{hash, level, commands, capabilities, risks}`, and the cell loads the widget only when `~/.config/omamobile/widget-approvals.json` holds an approval for that hash. An update that changes the command list asks again, as Omalauncher does. An update that changes only layout doesn't. Widgets the user or their agent wrote in the user's folder are approved by the act of creating them, but are still shown with their list in the Widgets sheet.

### 3.2 Refused or flagged at install

* **Refused**, whatever the source: the compile fails; the declared `owl:` level is above ours; the widget uses a feature we don't support yet (`Terminal` until P11); a command names a root tool (`sudo`, `pkexec`, `doas`, `run0`, `su`), as our QML rule already does.
* **Flagged** with a second confirmation: our own list of risky patterns, written from the store's published rules (download piped to a shell, `rm -rf`, `base64 -d`, `eval`, `dd`/`mkfs`/`shred`, reads of `.ssh`/`.gnupg`/tokens, a command, URL or file path built from widget values, notification access). Store widgets have passed the store's review in CI. Shared links have not ("nobody reviewed it"), and the sheet says so.

### 3.3 Limits on the phone (enforced by `OwlPhoneHost`)

| Thing | Guide | On the phone | Why |
| --- | --- | --- | --- |
| `cmd` interval | Any (default 60 s) | At least 2 s, which matches `host.run`. `clock` is exempt | Battery, and the same rule as QML |
| Timeout | Default 10 s, `timeout` has no cap | Default 10 s, at most 30 s | Same as `host.run` |
| Output | `http`/`file` at most 1 MB | 64 KiB for `cmd` and each `stream` line, 1 MB for `http`/`file` | Same as `host.run`. JSON feeds need more |
| `stream` | 4 | 2 across the home screen, all stopped when hidden | Each is a resident process |
| `run()` / actions from taps | No limit | One start per second per widget | Same as `launch` |
| `http` | At least 5 s | At least 60 s unless the user allows faster | Mobile data, once the modem works |
| Network | Runs at once | **Off until turned on** in the widget's settings, as for our network ports, with the listed hosts shown | Our privacy rule |
| `requires` install button | `pacman -Syu --needed` | **No silent install.** The tile says "needs jq". Its button opens a terminal running Omarchy's package install for those names, so the user sees the prompt and types the password | No widget triggers root |
| `file()` of private paths | Flagged in review | Refused unless the user confirms per path | Same risk list |
| `androidApp(pkg)` | Opens the app | `waydroid app launch <pkg>` once [Waydroid](../device/cheetah/WAYDROID-PLAN.md) is installed. Until then, a "no Android here" report | Interop bonus |
| `launcher("store")` etc. | Launcher screens | `store` and `drawer` map to our Widgets sheet and app grid, `style`/`themes` to Omarchy's Style menu, `agents` to `omarchy-agent --pick`. `linux` does nothing | |

### 3.4 Actions

`terminal`/`app` go through `omamobile-launch` (one app per screen, as `host.launch` does). `url` goes through `host.openUrl` for http(s). `tel:`/`geo:`/`mailto:` go through `xdg-open` only once handlers exist. `notify` uses `notify-send`, `copy` uses `wl-copy`, `share` copies and notifies, `haptic` uses feedbackd (a short event, respecting the user's feedback setting), `torch` uses the quick-settings torch path, `volume` uses `wpctl`, and `media` uses `playerctl`. **Announce before the first test of `haptic` and `torch` on the phone** (AGENTS.md §1).

### 3.5 What stays out of reach

Neither format is a sandbox: both run as the user, inside the shell. OWL makes what a widget does **visible and reviewable**. QML can only make it **declared**. WIDGETS.md's sentence "these checks are guard rails, not a sandbox" stays true and goes into the OWL contract too. Because our host funnels every command through one place, a real sandbox (commands under `systemd-run --user` with `ProtectHome=read-only` or a Landlock wrapper, and network through a per-widget proxy) can be added later without touching widgets. It is out of scope here.

---

## 4. Theming, sizing and touch

### 4.1 Colours

The palette is built from the same `colors.toml` that Omarchy's shell reads (`~/.local/state/omarchy/current/theme/colors.toml`), watched, so a theme switch restyles OWL tiles at the same moment as `qs.Commons`. Names the theme doesn't carry are derived with **our own documented rules** in `owl/SPEC-NOTES.md` (the same idea as the reference: terminal colours from the hues, `surface` as the background mixed toward the foreground). The conformance suite checks that our derived palette matches the reference's for every bundled Omarchy theme, because a mismatch would shift colours in snapshots. The names that must read on **our card** come from the shell:

| OWL name | Ours |
| --- | --- |
| `foreground` | `host.foreground` (Home's card text colour) |
| `muted` | `host.dimForeground` |
| `background`, `surface` | `Commons.Color.menu.background`, and that colour mixed toward the foreground |
| `border` | `Commons.Color.menu.border` |
| `accent` | `Commons.Color.accent` |
| `red` | `Commons.Color.urgent` when the theme has no `red` |
| `color0`-`color15`, `bright_*`, the other hues | Derived from `colors.toml` |

In the conformance runs (§7) both runtimes get the **same raw palette**, so the card overrides don't count as differences.

### 4.2 Fonts and corners

Text uses `Style.font.family` (Omarchy's Nerd Font), monospace by default as the guide's launcher draws it. `font: icon` uses the same Nerd Font. `corners` comes from `Style.cornerRadius`: 0 maps to 0, at most 6 px maps to 0.5, otherwise 1. On a square Omarchy theme it is 0, which is what the reference runtime always reports.

### 4.3 Grid, sizes and dp

| | Omalauncher | Our home screen |
| --- | --- | --- |
| Grid | 6 columns, about 12 rows, square 69 dp cells | 4x6 by default (3-6 by 4-8), cells about 120x150 logical px on 480x1040 |
| Sizes | `size: 3x2`, `minSize` | `size`/`min`/`max` in our cells |

Approach: **one OWL dp per phone**, from the width: `dp = (gridWidth / 6) / 69`, about 1.16 logical px on the Pixel 7 Pro. Every OWL tile then draws at the proportions it was designed with, whatever our grid. Sizes convert with that pitch:

* our `w = clamp(round(owlW × columns / 6), 1, columns)`, and our `h = clamp(round(owlH × owlPitch / ourCellHeight), 1, rows)`;
* `min` from `minSize` the same way (rounded up), and `max` equal to the grid;
* the widget reads `cols = round(cardWidth / owlPitch)`, `rows = round(cardHeight / owlPitch)`, and `tileWidth`/`tileHeight` = card size / dp, so its own `if cols < 3` layouts pick the right variant;
* `screenWidth`/`screenHeight` = the screen surface / dp.

Checked against our existing ports: upstream `forecast` is `6x3` and our port is `4x2`. `3x2` tiles become `2x1`. A user who sets a 6-column grid in Pages gets an exact column match.

### 4.4 Screens and the keyboard

`screen()` opens a full-screen sheet in Home's overlay layer (the same layer as the Widgets sheet), titled with the screen's `title`, with a close button. Back, the home gesture and `close()` close it. While it is open, its sources keep running even if the tile's page is off screen, as the guide says. When an `Input` gets focus, the host shows squeekboard (the launcher field's path). The home surface takes keyboard focus while a screen is open and gives it back when the screen closes.

### 4.5 Touch and editing

* **Tap** is a `TapHandler` with release-within-bounds. **Long-press** belongs to the home screen in both projects, so edit mode is entered the same way. While `editing` is on, OWL handlers are disabled, so taps move and resize.
* **`onDrag`** (3 store widgets) competes with the sideways page swipe. It gets the drag only after the first 10 px are more vertical than horizontal, or after a tap has armed the tile.
* **Touch targets:** OWL `Button`s are sized in dp, and at 1.16 px/dp a 28 dp button is about 32 px, under our 44 px rule. Our renderer gives each tappable node a **hit area of at least 44 px**, centred on its drawn bounds, without changing the layout, so snapshots stay comparable. `check` warns about targets that are smaller.

---

## 5. Catalogue

### 5.1 The store as our source of built-ins

* A new data package, **`omamobile-owl-widgets`**, pinned to an omarchy-widgets commit. It holds every `widgets/<author>/<name>/widget.owl` (1.4 MB for 105 widgets, all `license: "MIT"`), `order.txt`, and an index built locally from the files (`id`, `version`, `owl`, `size`, `requires`, `commands`, `sha256`, `category`). **`preview.png` (2.6 MB) only after Simon answers Q10** about how previews are licensed. Previews per theme (67 MB) are left out either way: we render previews in the user's theme on the phone with our own renderer, offscreen, and cache them, which also needs no licence answer.
* Only widgets that **pass our conformance suite** at the pinned commit go into the package. The rest are listed in the Store tab as "not yet supported here", with the reason (`Terminal`, a failed snapshot).
* The Widgets sheet gets a **Store** tab: categories (`news dev productivity time world fun home system`), store order (`order.txt`: listed ids first, the rest by name, the ids after `...` last), a preview, the description, the author, and a "runs N commands / uses the network" line.
* **Placing a store widget** copies its `widget.owl` into `~/.config/omamobile/widgets/<author>.<name>/widget.owl`, through the approval in §3.1. The user's widgets folder stays the one place code is loaded from, and editing a placed store widget with AI changes the copy, not the package.
* **Updates.** The package update (`omarchy update`) ships new store files. For placed copies, the Widgets sheet shows "update available" when the package has a higher `meta.version` for an unmodified copy (the hash matches an older release's). Accepting re-runs the approval when the commands changed. A copy the user changed is never overwritten. **No network fetch of widget code without the user's action:** a later "Check the store now" button may fetch the store's `index.json` and the widget files from GitHub Pages, but only when tapped, with each file verified against the index's `sha256` and still through approval and our compiler.

### 5.2 Retiring the 47 hand ports

Simon's `widgets/simonschubert/` has 48 widgets (it now includes `whats-new`, which we never ported). For each port, once its upstream widget passes conformance:

| Verdict | When | Expected |
| --- | --- | --- |
| **Replace** with the upstream `.owl` | Our runtime draws it as well as the port, and our additions are only settings that OWL keeps in `state … persist` with an `Input` | The large majority: the sports leagues, news feeds, clocks, `koi-pond`, `lava-lamp`, `owl`, `focus`, `habits`, `todo`, `year-progress`… |
| **Keep the port** for now | It depends on GeoClue `useLocation` (`air-and-pollen`, `forecast`, `today`, `sun-and-moon`, `planes-overhead`), or on our notification history (`notifications`) | Until a `location` source exists in the spec (Q6), or we add it |
| **Upstream our change** | The port fixed something real (theme colours instead of fixed hues, XHR instead of `curl \| jq`) | A pull request to the widget, so both sides benefit |

**Layout migration:** `HomeModel.normalize()` maps the old type (`earthquakes`) to the new one (`owl:simonschubert.earthquakes`) and moves known config keys into the widget's per-placement persisted state (`city` goes to `state city`, for example). The opt-in `enabled: true` carries over into the network approval. Ports stay in the package for one release after their replacement ships, so a bad replacement can be rolled back by setting a flag in `home.json`.

### 5.3 Shared links (`w/#owl1.…`)

The phone's Chromium sends a mobile user agent. If the page sees "Android", its **Open in Omalauncher** button becomes `intent://simonschubert.github.io/omarchy-widgets/w#Intent;…;S.widget=owl1.<data>;end`. Today `omamobile-open-intent` swallows every `intent://` link. Teach it one case: an intent whose host and path are the widget page and that carries `S.widget=owl1.…` decodes (raw inflate plus base64url, with the inflated size capped) and opens the home screen's **Import widget** sheet, which shows the source, every command and the risk flags, and installs into `shared.<name>` only on approval. Also:

* **Paste a link** in the Widgets sheet (the same decoder);
* `#dpaste.<id>` links need a network fetch of widget code, so they are fetched only after the user taps "Fetch from dpaste.com", with the same review after;
* **Share** from our side produces the same `owl1` link (and a QR code later), so a widget made on our phone opens on Omalauncher.

### 5.4 One catalogue for someone who uses both

Same files, same store ids (`author/name`), same `meta.version`. Omalauncher keeps `~/.config/omalauncher/widgets/*.owl`, and we keep a folder per widget (`<author>.<name>/widget.owl`, which leaves room for `.errors/` and a cached preview). Moving between them is a link, a copy, or a pull request to the store. Syncing a person's set between devices is out of scope. A shared "my widgets" list format would be a later conversation with Simon (Q9).

---

## 6. Creating widgets with AI

### 6.1 OWL by default

**Create a widget with AI** creates `~/.config/omamobile/widgets/<user>.<words>/widget.owl` from an OWL template (a `meta { owl: 7 }` header, a `size`, a `Text`). It starts Omarchy's default agent as today (`omamobile-widget agent`, `omarchy-agent-prompt`) with a prompt that points to:

1. **The OWL language guide**, installed as `/usr/share/omamobile/shell/OWL.md`. Until the spec is published in the store repository (§8), this is the launcher's `widgets/README.md` at the pinned commit (MIT, credited), installed as documentation, not code. After that, it is the published spec at the level we support;
2. **`WIDGETS-OWL.md`, our phone notes**, kept short: the folder rules (stay in the folder, no `sudo`, no package installs, no fetching widget code), "sizes in OWL cells, design for `3xN` and `6xN`", the network opt-in, the features we don't serve (`Terminal` for now, `android.notifications` without approval, `alarm`, `androidApp` without Waydroid), "no endless `time` animation unless it is the point of the widget", touch targets, and `omamobile-widget check .` to finish;
3. QML remains available: "Create a QML widget (advanced)" keeps today's template and `WIDGETS.md`.

**Edit with AI** works the same for both formats. For OWL it passes `.errors/<id>.txt` instead of the scan's QML errors.

### 6.2 The checker on the phone

The launcher's `owl-check` compiles the file, waits for the live tile, reports run-time problems and **renders a preview PNG for the agent**. Ours does the same with our own code:

| Path | Compile and list commands | Run-time problems | Preview | Needs |
| --- | --- | --- | --- | --- |
| **IPC to the running shell** (`omarchy-shell shell call omamobile.home owlCheck <id>`) | Yes | **Yes**: it waits for the cell to load and returns `.errors/` | **Yes**: `grabToImage` of the live card into `.preview/<id>.png` | Only IPC. The home screen is always running on the phone |
| **Our core under node** (`omamobile-owl-check`, which loads `lexer.js`/`parser.js`/`compiler.js`) | Yes, the same code the shell runs | No | No | `nodejs` as an optional dependency (usually present on Omarchy for agent CLIs) |

`omamobile-widget check .` tries IPC first and falls back to node (for the scan at boot before the shell is up, and in CI). It prints the same shape as `owl-check`: `compiles`, the problems, and `preview: <path> (3x2 cells, WxH px)`. The agent is told to open the preview, as Omalauncher's guide already tells it. `owl.jar` is never needed on the phone: it would mean a JRE of about 200 MB, and the conformance suite already checks our compiler against the reference on the laptop.

---

## 7. Conformance suite

**Where it runs:** on the laptop only, in a container (Docker, as `bin/omamobile kernel` already uses), never on the phone, and **never as a nested Hyprland or a Quickshell session on the laptop's desktop**. The container has Qt 6 and Quickshell from Arch, node, Java 17 (only for the optional `owl.jar` oracle), the Omarchy fonts, and the two upstream repositories checked out at the pinned commits **inside the container**. Their files never enter our tree.

### 7.1 What is compared

For each of the 105 store widgets, with fixed inputs:

| Level | Our side | Reference side | Pass rule |
| --- | --- | --- | --- |
| **L1 Compile** | Our compiler under node | Reference `Owl.js` `compile()` under node, and optionally `owl.jar check` | Same accept or reject. For rejects, the same line and column, and the message compared by category (exact wording isn't required) |
| **L2 Capabilities** | Our `commands` list and derived capabilities | The reference `commands` list | **Exactly the same strings**, in the same order. The capability set derived from them by one shared function must match |
| **L3 Evaluation** | A walk of our render tree: every evaluated property and every Canvas drawing call, as JSON | The same walk of the reference instance | Equal JSON, with numbers equal to 1e-9 and colours as ARGB |
| **L4 Layout** | Our renderer's item tree, headless: per node, `{path, kind, x, y, w, h}` in dp | The reference renderer's `OwlNode` tree, the same way | Each box within ±1 dp, with text boxes within ±2 dp, because font hinting differs |
| **L5 Pixels** | `grabToImage` of the tile | The same of the reference tile | Perceptual diff under a threshold (for example 1% of pixels beyond ΔE 5). Failures are kept as images for review, never auto-accepted |

**Inputs:** each widget runs at its own `size` and at `minSize`, with a fixed palette (three Omarchy themes: one dark, one light, one square), a fixed `dp` (our phone's 1.16), `TZ=Europe/Berlin` and a fixed clock, and, for every source, a fixture (the source's value recorded once) or `null` ("not loaded"). Fixtures are recorded in the container by running the reference with sources **stubbed from saved responses**. No network or commands from widgets run during tests: `cmd`, `http`, `file` and `stream` are replaced by the fixture loader in both runtimes.

**Evaluator unit tests**, beyond the store: the guide's examples, the reference's `test/edge.owl` (198 expressions chosen to break a port; fetched into the container, used as input, not committed), and our own tests for each builtin, each operator with `null`, numeric text, paths, `sh()` quoting (with hostile inputs), budgets and caps (a widget that loops, one with 501 nodes, 2001 drawing calls, a trigger that feeds itself), the `owl:` level rules, error positions, and the size conversion and palette in §4. They run under node in our repository's normal test run, with no container.

### 7.2 Headless rendering

L4 and L5 need a Qt scene graph without a compositor:

1. **First choice: `QT_QPA_PLATFORM=offscreen` with a plain QML runner.** Our renderer's node layer is designed **not to depend on Quickshell types**: sources and the host are injected, so the harness (`tests/owl/harness.qml`) loads it in `qml6` (from `qt6-declarative`) with the offscreen platform, sets fixtures, waits for two frames, dumps the item tree and calls `grabToImage`. The offscreen platform renders with the software scene graph, or with OpenGL through EGL pbuffers when Mesa is present.
2. **The reference renderer imports Quickshell** (`Quickshell`, `Quickshell.Io`, `Quickshell.Services.*`). Options, in order: (a) run `quickshell -p <harness>` with `QT_QPA_PLATFORM=offscreen` and a harness that uses only an offscreen `Item` (not a `FloatingWindow` or layer shell). Whether Quickshell starts without a Wayland display has to be checked in P1. (b) Give the harness stub QML modules named `Quickshell` and `Quickshell.Io` that provide just the types the reference uses (`Process` reading fixtures, `FileView`, `Quickshell.env`), so plain `qml6` can load it. (c) As a last resort, a **headless Wayland compositor inside the container** (`weston --backend=headless` or `cage` with the headless wlroots backend), which is not a nested Hyprland and never touches the laptop's session.
3. **The same fonts and the same software rasteriser on both sides**, so pixel diffs measure layout, not hinting.

### 7.3 How it runs

* `tools/owl-conformance` builds the container, records or refreshes fixtures, runs L1-L5, and writes `logs/owl-conformance/<date>/report.md`, with a table per widget and diff images. It never writes to the phone.
* The **expected outputs are regenerated from the pinned reference** each run, as Simon's own suite does. Nothing is stored as "golden" in our tree except a short list of accepted, explained differences (`tests/owl/known-differences.md`, each entry pointing at a `SPEC-NOTES.md` decision).
* **Gates:** a widget ships in `omamobile-owl-widgets` only at L1-L4 pass, with L5 reviewed. The runtime's release gate is all evaluator unit tests plus no conformance regressions against the previous run.

---

## 8. Spec tracking and shared ownership

### 8.1 Pin and compatibility matrix

* We **pin a language level** (initially 7) and a pair of reference commits (omarchy-widgets and omalauncher). The runtime exposes `LEVEL = 7`. A widget that declares more is refused with "needs owl N; update Omarchy Mobile".
* `owl/COMPATIBILITY.md` is the matrix, one row per feature: the level that introduced it, our status (supported, partial, not yet, never on Linux), the phase that delivers it, the conformance tests that cover it, and the `SPEC-NOTES` decisions that touch it. The **store coverage** (how many of the 105 widgets pass L1-L4) is the headline number.

### 8.2 Following new levels

1. **Watch** both repositories by hand (a laptop task, about monthly, or when Simon announces a level): diff the guide since the last pin and list the new features and any changed wording.
2. **Write tests first**: guide examples and edge cases for each new feature, then refresh the fixtures from the new reference.
3. **Implement, then run conformance**, and bump `LEVEL` only when the new features pass and nothing older regressed.
4. **Ship** in an `omamobile-shell` release. Until then, store widgets that need the new level appear as "needs a newer Omarchy Mobile" in the Store tab.
5. **Ambiguities** go to Simon as an issue on the spec (below), not just into our notes.

Expect a new level every few weeks while the language is young (it went from 1 to 7 within weeks). Each one costs us roughly 1-3 days.

### 8.3 Proposal to Simon: one published spec

* Move the full guide (the launcher's `widgets/README.md`) into the store repository as `docs/LANGUAGE.md`, **versioned per level**, with a changelog that names each level's features and promises that a level never changes meaning once released.
* Publish the conformance fixtures in a runtime-neutral form (a widget, its source data, the expected render-tree JSON), so every runtime (Compose, his Quickshell runtime, ours) tests against the same files. We'd contribute ours.
* **Shared ownership**: spec changes as pull requests to that file, with both runtimes' maintainers reviewing; Omarchy Mobile-specific needs (phone sizes, location, settings, time format, touch targets) proposed there instead of as private extensions.

---

## 9. Phases, effort and risks

The effort figures assume one developer, with the human approving phone steps. They are estimates. No phase reboots or flashes anything. Every phone step is a package install and a shell restart (`omarchy-restart-shell`), **announced before it runs** because it redraws the screen. The first plan (vendoring the runtime) came to about 20-25 days. Writing our own runtime adds the language core, the renderer and the conformance suite.

| Phase | Work | Effort | Tests and exit criteria |
| --- | --- | --- | --- |
| **P0** Agree | Send §10.2 to Simon, with the spec proposal (§8.3). Pin commits and the level | 0.5 d plus waiting | Answers recorded here (Q1, Q2 and Q10 at least) |
| **P1** Conformance harness | Container, fixture recorder with stubbed sources, the reference walks (L1-L3 under node, L4-L5 headless, §7.2: settle which headless option works), report format | 4-5 d | The reference passes against itself. The 105 widgets have fixtures. The headless method is chosen and documented |
| **P2** Language core | Lexer, parser, error format, compiler to IR, name resolution, level rules, node and property tables, the commands list | 6-7 d | L1 and L2 pass for all 105 widgets. Unit tests for syntax and errors |
| **P3** Evaluator | Values, operators, builtins, `let` dependency graph, `history`/`prev`, state and persistence, triggers, components, budgets and caps | 6-7 d | L3 passes for all 105 widgets and `edge.owl`. Unit tests for every builtin and cap |
| **P4** Renderer and layout | Node items, keyed updates, the layout rules, text styles, Canvas and sprite, Image, Progress, Ring, Sparkline, animations, Slider, Input, screens, the `Shader` fallback, hit areas | 9-11 d | L4 passes and L5 is reviewed for at least 95 of the 102 non-`Terminal` widgets. Each remaining difference is explained in `known-differences.md` |
| **P5** Sources, scheduler and host | `OwlPhoneHost`, all sources (§2.5), the shared scheduler (30 fps, paused when hidden), clamps, actions, `.errors/` | 4-5 d | Node tests for clamps and the scheduler. On the phone: frame times at 120 Hz with 6 OWL tiles, CPU while hidden (about 0), and an A/B battery drain with `tools/power-ab` (8 OWL tiles against 8 ports) |
| **P6** Home integration | `OwlCell`, the palette and card overrides, dp and size conversion, `editing`, instances that outlive cells, per-placement state, the crash guard, the screen sheet, the keyboard | 3-4 d | Desktop harness (`phone/dev/run-desktop`, when allowed). Screenshots on the phone for each widget class. A deliberately crashing test widget is held back by the guard |
| **P7** Scan, check and approval | OWL branch in `omamobile-widget`, node checker, IPC check with preview, risk patterns, `widget-approvals.json`, approval sheet, re-approval | 3 d | Crafted bad widgets (a `sudo`, `curl \| sh`, a built URL, `owl: 99`, `Terminal`) are refused or flagged. Approval survives restarts and resets on command changes |
| **P8** Catalogue package and Store tab | `omamobile-owl-widgets` (conformance-gated), local index, Store tab, previews rendered in the user's theme, copy-on-place, "update available" | 3-4 d | Package builds. Place, update (unmodified, then modified), approval prompt on command changes. No network during install (ufw logging) |
| **P9** Replace the ports | Per-port verdicts, side-by-side screenshots, `normalize()` migration, rollback flag, upstream pull requests for port fixes | 4-5 d | A migration test over sample `home.json` files. Screenshot review by the human. One release with both, then the ports are removed |
| **P10** AI creation and links | OWL template, `OWL.md`, `WIDGETS-OWL.md`, prompt, the "QML (advanced)" path, Edit with AI with `.errors/`. Intent handling, Import sheet, paste-a-link, dpaste on tap, Share | 4 d | Five prompts made end to end with the default agent (the human watches), each passing `check` with a preview the agent looked at. Decoder unit tests. A link from Omalauncher installs here, and one from here opens on Omalauncher |
| **P11** `Terminal` (level 2) | A pseudo-terminal tile with the keyboard, opt-in | 3-4 d | The 3 store widgets that use it pass L1-L3 and look right on the phone |
| **P12** Spec and upstream | Spec proposal, shared fixtures, new levels as they come (§8.2) | Ongoing, about 1-3 d per level | Store coverage stays at 95% or more |

**Total: about 50-60 days** (P1-P11 add up to 49-59 d; P0 adds waiting time and P12 is ongoing), against 20-25 days with the vendored runtime. **A useful first release comes after P1-P8: about 38-46 days.** It has store widgets on the home screen with approval, and AI creation can follow at once.

### 9.1 Migrating existing user QML widgets

Nothing breaks: QML user widgets keep loading through `UserWidgetCell` and `WIDGETS.md`. The Widgets sheet labels them "QML". **Convert to OWL with AI** (an action on each QML widget) starts the agent in a **new** folder (`<id>-owl`) with both contracts and the QML as input. The user compares the two and removes one. Nothing is converted automatically: the QML side may use APIs OWL lacks, and the agent should say so instead of guessing.

### 9.2 Risks

| Risk | Mitigation |
| --- | --- |
| **Rendering differs from Omalauncher.** Our oracle is Simon's Quickshell runtime, which is itself a port of the Compose renderer, so we inherit its differences from Android and add our own | L4 tolerances are stated, and L5 is reviewed by eye. A few store widgets checked on a real Omalauncher phone each release (Simon's help, or a borrowed Android phone). Differences we can't remove are listed per widget in the Store tab |
| **Spec ambiguity.** The guide is prose, and the reference implementation is the real definition | `SPEC-NOTES.md` records each decision with what the reference does. Ambiguities go upstream (§8.3). Conformance catches the rest |
| **Spec churn** (7 levels within weeks) | Pin, and update deliberately (§8.2). Refuse widgets above our level. Ask for stability (Q1) |
| **Reference runtime disappears or stalls** (the reason for this plan) | Our runtime doesn't depend on it at run time. Without it, conformance falls back to `owl.jar` (the Kotlin reference, L1-L3 only) and to the guide. Our fixtures and walks stay valid at the last pinned commit |
| **Performance on the phone.** JS evaluation, layout in JS and Canvas on the GUI thread, at 120 Hz | Dependency tracking (only changed bindings), keyed in-place updates, 30 fps animation, paused when hidden, and the measurements in P5 before OWL becomes the default. The core is kept movable to a C++ module (§2.3) |
| **Effort** (2.5x the vendoring plan) | The first release is cut after P8. `Terminal` and polish come later. Each phase has a pass rule that stops it from growing |
| **`bash -c` commands**, as opposed to our argv rule | Commands are static and listed, with approval per hash, the risk flags, refused root tools and clamps. The "not a sandbox" sentence stays in both contracts |
| **Store widgets assume Android** (`android.notifications`, `androidApp`, alarm) | Hide widgets whose sources we can't serve, using the compiled source list, or mark them "partial" in the Store tab |
| **Preview licensing unclear** | Ship `preview.png` only after Q10. Theme previews are rendered locally anyway |
| **Agent quality in OWL compared with QML** | P10 exit criteria, the preview loop, and keeping the QML path open |
| **`intent://` handling widens what the browser can push into the shell** | Accept only the exact host and path and the `owl1` payload, cap the inflated size, and never install without the approval sheet |

---

## 10. Upstream contributions and questions for Simon

### 10.1 What we'd contribute

* **The spec work** (§8.3): pull requests that turn the guide into a versioned spec, clarifications from `SPEC-NOTES.md`, and runtime-neutral conformance fixtures.
* **Findings from a second runtime**: every reference-runtime bug the conformance suite turns up, as issues with a minimal widget.
* **Phone needs as spec proposals**: settings, location, time format, minimum touch targets, and gesture rules for `onDrag` against page swipes.
* **Our built-ins as OWL widgets in the store**: Clock (with the system time format, once Q5 lands), Battery, Calendar (khal), Note, and our ports' fixes as pull requests to the original widgets (§5.2).

### 10.2 Questions for Simon

| # | Question |
| --- | --- |
| Q1 | **Spec home and stability.** The store's `docs/LANGUAGE.md` lags the launcher's guide (level 7). Can the full guide become the versioned spec in the store repository, with a changelog per `owl:` level, and the promise that a released level never changes meaning? Would you take us as co-maintainers of that document (§8.3)? |
| Q2 | **Conformance fixtures.** Would you publish runtime-neutral fixtures (widget, source data, expected render-tree JSON) from `owl.jar`, so every runtime tests against the same data? Is the render-tree JSON from `OwlOracle.java` stable enough to be that format? |
| Q3 | **Permissions model.** The store reviews commands and the app asks again on changes. Would you accept a machine-readable capability summary in `index.json` (`commands`, `network` hosts, `files`, `notifications`) so both hosts show the same approval screen? Would you consider `http` hosts as a declared allow-list? |
| Q4 | **Settings.** Would a typed `settings { city: text; units: choice("C", "F") }` declaration (rendered by the host as a settings sheet, read as values, persisted per placement) fit OWL? |
| Q5 | **Time format.** A `timeFormat` tile variable (the user's 12/24-hour choice), or `fmtTime(now, "time")`? |
| Q6 | **Location.** A coarse `location` source (`{lat, lon}` rounded to about 1 km, null until the user allows it), from Android on the launcher and GeoClue here? |
| Q7 | **Theme tokens.** Is the reference `themeFromToml` derivation the specified mapping for Omarchy themes? May hosts override `foreground`/`muted`/`surface` for the card they draw? May `corners` be non-zero on Linux hosts whose theme rounds? |
| Q8 | **Shared links.** May the `w/` page offer a non-Android "open" path (a custom scheme or `web+owl:`) that a Linux phone can register? |
| Q9 | **Catalogue governance.** Can widgets that only make sense on Linux phones live in the same store (a `hosts:` or `needs:` field)? Who reviews pull requests from our users, and can we co-maintain? A shared "my widgets" list format for people who use both? |
| Q10 | **Licensing of previews.** Are `preview.png` and `previews/*.webp` covered by the widget's licence or by the repository's MIT licence? They show theme wallpapers and third-party content (sports crests, comics). |
| Q11 | **Naming.** Can we say "OWL widgets" and "works with the Omalauncher widget store" in our UI and README? Is there a mark you'd rather we avoid? |
