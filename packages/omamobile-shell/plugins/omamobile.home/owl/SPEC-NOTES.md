<!-- SPDX-License-Identifier: MIT -->
# OWL spec notes

Our OWL runtime is written from the language guide (Omalauncher's `app/src/main/assets/widgets/README.md` at `d355bdb`, level 7) and the store's `docs/LANGUAGE.md` (`b63886b`). Where the guide is silent or ambiguous, we learned what the reference runtime (Simon Schubert's `runtimes/quickshell/`, MIT) does by reading it for meaning and by running it as a black box in the conformance container (`tests/owl/`), and wrote the answer down here in our own words. Nothing from that runtime is in our tree. See [docs/WIDGET-INTEROP-PLAN.md](../../../../../docs/WIDGET-INTEROP-PLAN.md).

Each entry: the decision, the guide section it clarifies, and how it is tested.

## Values (`values.js`)

**N1. Numeric text.** (Expressions: "numeric text acts like a number".) Text is a number when, trimmed and with one trailing `%` removed, it is a decimal number in Java's syntax (`81`, `4.5`, `.5`, `1e3`, `NaN`, `Infinity`, an optional `f`/`d` suffix). `true` is 1 and `false` 0. Anything else is not a number, and arithmetic with it is `null`. `+` with text on either side joins text instead (`1 + "2"` is `"12"`); a non-text value beside text reads as it would on screen, so `"x" + null` is `"x…"`. Tests: `owl-probes/numbers.owl`, `text.owl`.

**N2. How values print.** (Expressions: "`null` shows as `…`".) On a tile, `null` is `…` and text loses trailing whitespace and leading line breaks (command output). Inside lists, maps and the conformance walk, `null` prints as `null`. Numbers print as the launcher's JVM prints them, except that whole numbers below 10^15 print without `.0`: `3`, `0.5`, `1.0E21`, `1.0E-4`, `1.00000005E7`, `-0` as `0`. Gradient coordinates print as 32-bit floats. Tests: probes.

**N3. `fixed()` rounds the shortest decimal form half up**, as Java's `String.format` does: `fixed(1.005, 2)` is `1.01` where JavaScript's `toFixed` gives `1.00`. `fixed(-0.04, 1)` is `-0.0`. Tests: `numbers.owl`, `owl-core.js`.

**N4. Colours keep their theme name.** (Expressions: colors.) `accent` is a colour that names the theme colour; the host resolves it when it draws, so a theme switch restyles the tile. `alpha(accent, 0.5)` keeps the name and multiplies the alpha (it prints as `accent`); `mix()` resolves both colours and gives a literal. `#rrggbbaa` puts alpha last, as CSS does. Text that names a theme colour (`"red"`) or is a hex colour works where a colour is expected. Tests: `colors.owl`.

**N5. Dividing by zero gives 0**, and so does `%` by zero; `%` takes the sign of the divisor (`-7 % 3` is 2). The guide promises errors never take the home screen down, and infinity would. Tests: `numbers.owl`.

**N6. Maps keep key order.** JSON objects are read in file order, so `{"10": 1, "2": 2}` lists `10` first; JavaScript objects would reorder integer keys. A path that doesn't exist is `null`; `list.0`, `list[-1]` and `text.length` work. Tests: `lists.owl`, `owl-core.js`.

**N7. Lists stop at 1000 items** wherever a list is made (functions, `+`, `range`), and a `for` draws at most 1000 items. Tests: `owl-core.js`.

## Runtime (`runtime.js`)

**N8. `on x { }` doesn't fire for x's first value, and a change to or from `null` doesn't count** (Triggers: "Not for its first value, and null (loading) doesn't count as a change"). Here we follow the guide's words; the reference also fires when a source first loads. `when` fires each time its condition turns true, including at start. A trigger that sets off triggers is cut off 4 deep, and the phone host holds a trigger back after 10 runs in a second. Tests: `owl-core.js`.

**N9. `at t { }` fires when the clock passes `t`; a `t` already past at the first tick fires then** (the guide's "a time that passed while the launcher wasn't running runs at the next start"). `0` and `null` mean none. `t` may also be `"HH:MM"`, today. Tests: `owl-core.js`.

**N10. The step budget is 200,000 per update**, the reference's figure, so a widget that passes there passes here. Function calls, list items mapped, filtered or sorted, and lambda calls spend steps. A widget over budget shows `…` where the value was and reports "too much work in one update"; the rest of the tile draws. A Canvas has its own budget per frame, and stops at 2,000 drawing calls (the calls before that are drawn). Tests: `owl-core.js`.

**N11. History and prev sample whenever a source updates.** `history(x, n)` keeps the last n (2 to 1000); `prev(x)` is the sample before. With `persist`, history comes back after a restart. Tests: `owl-core.js`.

## Functions (`builtins.js`)

**N12. `fmtTime` letters are java.time's**, in local time and English: `y u M L d E e c H k h K m s S a D Q q Z x X` and quoted `'text'`. `e`/`c` count from the first day of the week: Monday on the phone (the store's calendar widget is drawn for it), Sunday in the conformance walk, where the reference oracle runs in en_US. An unknown letter is an error ("bad time pattern"). Tests: `text.owl`.

**N13. Null in functions.** Math (`round floor ceil abs sqrt sin cos tan rad deg sign pow int`), `pad`, `fixed` and the `fmt*` functions pass `null` through. `clamp`, `lerp`, `atan2`, `min`, `max` treat a non-number as 0 (or skip it in a list). Text functions treat `null` as empty text; list functions treat it as an empty list. `num(x, default)` gives the default. Tests: `numbers.owl`.

**N14. `min`/`max` of one list** ignore its non-numbers and give `null` for none; of several values, a non-number never wins. Tests: `numbers.owl`.

**N15. `sh(x)`** single-quotes the text of x (`null` as empty) and escapes quotes inside, so the value is one shell word whatever it holds. Tests: `owl-core.js` runs it through bash with hostile inputs.

**N16. `match` gives the first match's groups as a list, or the whole match when the pattern has no groups, or `null`; `matchAll` gives every match that way.** Regular expressions are JavaScript's. Tests: `text.owl`.

## Phone (`phone.js`)

**N20. The palette.** OWL's names come from the Omarchy theme's `colors.toml`: `background`, `foreground`, `accent` (else `blue`/`color4`), `muted` (else `color8`); hues from their names or `color1`-`color6`, bright hues from `bright_*` or `color9`-`color14`; `orange` is red mixed with yellow, `brown` orange mixed with background, `surface` the background 8% toward the foreground, `border` 20%, `color0`-`color15` the terminal colours. This is the same derivation as the reference: the conformance suite checks every bundled Omarchy theme and all 22 match. On our card, `foreground`, `muted`, `background`, `surface`, `border` and `accent` come from the shell instead (plan §4.1).

**N21. Sizes.** One OWL dp is the phone's width over Omalauncher's 6 columns of 69 dp (1.16 logical px on the Pixel 7 Pro). An OWL size converts to our cells by columns (`round(w × ourColumns / 6)`) and by pitch (`round(h × 69 dp / ourCellHeight)`); `minSize` rounds up. `cols`, `rows`, `tileWidth` and `tileHeight` describe our card, so a widget's own `if cols < 3` layouts pick the right variant. `corners` is 0 for a square Omarchy theme, 0.5 up to 6 px of rounding, else 1.

**N22. Capabilities are derived, not declared.** The compiler lists every command, URL and file; `commands`, `network` (an `http` source, or a command that runs `curl`/`wget` and the like, or `requires` curl or wget), `files` and `notifications` follow from that list. A widget is approved for one exact list; a change to the list asks again, a change to the layout doesn't.

**N23. A page is live only while it is on screen.** (Triggers: "every 10s while the page is live (on screen or next to it)".) Sources, `every` and the frame clock run for the shown page, for its neighbours only while the pages are being swiped, and only while nothing covers the home screen (an app, the drawer, recent apps, the call card) and the panel is on. Keeping the next page live cost a hidden koi pond about 118 % CPU on the Pixel 7 Pro. When a widget shows again, a source whose period turned over runs once and an `every` that passed fires once; `time` jumps to the current value. `at` keeps running while hidden, on a 10 s tick. Frames come at 20 fps, 30 for 3 s after a touch, and a widget whose frame (its JS, the layout and the Canvas paint it causes) takes over 20 ms gets every other one. Tests: `test/owl-idle`, `test/home-model.js`, `owl-core.js`.

## Layout (`layout.js`)

**N30.** A node is as big as its content unless it fills. Text without `width`, `weight` or `fill` takes the full width; `Progress`, `Sparkline`, `Grid`, `Slider` and `Input` take the width unless sized; `Canvas`, `Shader` and `Terminal` take all the space unless sized. Defaults: `Progress` 60x8, `Ring` 64x64, `Sparkline` 80x48, `Slider` 120x28, `Button` its text plus 20x12.

**N31.** A Row or Column measures its unweighted children in order, each given what is left after the ones before it; weighted children then share the rest by weight. In a Column a child that fills the height counts as weight 1.

**N32.** `justify` places children only when none is weighted. `align` places them across: a Row centres them by default, a Column puts them at the start.

**N33.** Text lines are 1.17 em apart (Android's monospace spacing), wrap at spaces (anywhere inside a word longer than the line), and `title` and `huge` keep to one line unless `maxLines` says otherwise.

**N34.** Several root nodes stack as a Column with no gap, and the root fills the tile's content area (the card minus `padding`, 12 dp by default).

**N35.** A component used with layout properties (`weight`, `padding`, ...) is wrapped in a Box that carries them, and its content fills that Box. A Box never gives a child more room than it has, even a child with a fixed size.

**N36.** A Grid splits its width into `columns` equal cells (gap 6); each row is as tall as its tallest cell, rounded up to a whole pixel, as the reference renderer's grid draws it. Text lines are 1.17 em of the whole-pixel font size the text is drawn at.

**N37.** `Row { wrap: true }` and `Flow` place children at their own size and wrap at the width.

**N38.** A `scroll: true` Column lays out at its children's full height and scrolls inside the space it gets.

## Known differences

None at L1-L3 for the 105 store widgets at `b63886b` (without data) and the 14 milestone widgets (with data). Layout (L4) matches within 1 dp for the 14 with data and 104 of 105 without (the other one isn't compared); see [`docs/owl-review/`](../../../../../docs/owl-review/README.md).

**N39. `tileWidth`/`tileHeight` include the tile's padding**, as the guide says ("dp, including the tile padding"). The reference renderer reports the content area without it; the layout comparison gives both sides the reference's value. An open question for Simon.
