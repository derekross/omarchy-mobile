# Voice input plan

Status: 2026-11-01. **omamobile-shell 0.2.65** (branch `keyboard-language-picker`): the keyboard's globe opens a language sheet in the shell instead of squeekboard's popover ([The language sheet](#the-language-sheet-0265-branch-keyboard-language-picker)). **Phase 3 is built in omamobile-shell 0.2.63** (branch `voice-phase3`, not on the phone yet; [Phase 3](#phase-3-0263-branch-voice-phase3)): live words in the bar while you speak (Voxtype 1.1.1 can't hand its partials over, so the shell transcribes a second capture in chunks with tiny.en), base.en back as the default with Whisper's context cut to the clip (12 s of speech in about 2.2 s), the keyboard's action row in every language squeekboard ships, and a design for voice on the lock screen. Before that: **one voice bar** (canvas row U1-U4: UApp, UAgent, UHome, UResult), approved by the maintainer, ships in omamobile-shell 0.2.61 (branch `shell-voice`, PR #241, not merged yet). It replaces the voice UIs of 0.2.57-0.2.60 (a dictation strip, an Ask sheet, a Confirm sheet, a mic and a hold on the search pill, a keyboard-strip mic key, an agent mic in the home strip), which had multiplied, each with its own look and rules. On the phone with 0.2.61, the maintainer confirmed that holding the pill and the keyboard's Mic key both work and insert text. 0.2.62 fixes what that run found ([below](#found-on-the-phone-0261-fixed-in-0262)): the keyboard flashing up as the drawer closed, and Hyprland keeping old binds until a reload. [The voice bar](#the-voice-bar-0261) is the current design. The sections from [History](#history-0257-0260) on record the earlier flows and what the phone taught at each step; don't follow them for how voice works today.

Design (approved by the maintainer): the voice canvas, <https://claude.ai/artifact/K93k88TFaqyKvChsdk2ugK>. It has five artboards: Main (dictation strip above the keyboard), Ask (listening sheet), Confirm (check and send), FollowUp (phase 2) and Settings (phase 2). The mockups use Tokyo Night hex colours as a stand-in. The shell draws with the applied theme's tokens (`Commons.Color`, `Style`, `Border`) and the update sheet's components, and the recording colour is the theme's `urgent`.

## The voice bar (0.2.61)

One bar, one set of rules, wherever voice starts.

- **Ways in.** As on Android, the bottom bar is just the pill. **Hold the pill in an app, or the search bar on the home screen** (the home screen has no pill; its search bar plays that part), for about 0.45 s without moving past the swipe threshold, and the bar opens listening, with a haptic tick. A swipe takes the touch first and cancels the hold, and a finger that moves after the hold fired is still a swipe (home or recent apps, the 0.2.56 gestures). **Double-tap the pill** to show or hide the keyboard. A second double tap now always hides it, even before the first show is reported: `KeyboardModel.toggleTarget` trusts the last request for 1.5 s. The keyboard's **Mic** key, **Power + Volume Up** (when turned on) and the **Dictation tile** open the same bar. One command, `omamobile-voice [toggle|start|done|cancel|settings|snapshot]`, is there for the tile and for scripts. The first time the pill-only bar shows over an app, a toast says "Hold the pill to talk · double-tap for the keyboard" (Omarchy's done store, `omamobile-pill-hint`). The Voice settings say it too.
  - Why no buttons: a mic at the right end of the bar and a keyboard key at its left end repeated the keyboard's own Mic and Hide keys while the keyboard was up, and fading them in and out only moved the problem. Android has no buttons there either: a hold is the assistant, and the keyboard brings its own controls.
- **The bar.** A top-layer surface that reserves its height, so the app's field ends above it. It rises above the keyboard when the keyboard is up, above the home strip over an app, and above the dock on the home screen (the dock reserves nothing, so the bar takes the dock's height from the launcher through DrawerLink.js). It never takes the keyboard focus while listening, so the app keeps it and the words go there. From the top:
  - the destination chip (top left);
  - a pulsing dot and the time (top right; "stops at 1:00" near Voxtype's cap);
  - the level from `voxtype-audio-bridge`, and its status word;
  - for Send, the hint line;
  - Cancel and the primary "Done · <verb>".

  The border and the primary button are the theme's urgent colour while it listens. Theme tokens only: `Commons.Color`, `Style`, `Border`, and the theme's colors.toml `yellow` (else `color3`, else the accent) for the warning colour.
- **Destinations,** from what is in front:
  - an agent's terminal (`org.omarchy.agent`): **Send to <Agent>**, typed into its prompt then Enter (`wtype`, then `wtype -k Return`; no trigger word), with the hint "Types what you say into the prompt and presses Enter.";
  - any other app: **Type here**, typed into the focused field;
  - the home screen: **Ask <Agent>**, a new prompt through the launcher's `promptArgv`.

  A tap on the chip lists, inside the bar, the context's own choices plus **Copy to clipboard** (`wl-copy`) and **Search apps** (the launcher, opened with the words as its query).
- **One recording mode.** Every recording is `voxtype record start --no-osd --file=$XDG_RUNTIME_DIR/omamobile-voice.txt`, and the shell delivers the transcript when it is text. The destination can therefore change while you speak, and Voxtype's per-recording output flags (`--type`, `--auto-submit`, `--smart-auto-submit`) are no longer used. A recording the bar didn't start (a desktop hotkey, F9 on a hardware keyboard) shows nothing and delivers nothing.
- **The result step,** only for Ask (UResult): the bar turns the warning colour and shows the editable transcript, "<Agent> runs with full permissions on this phone. Check the words before it starts.", and Discard / Again / Ask. Every other destination delivers the moment the words are text. "Check before asking the agent" off (in the settings) sends straight away.
- **Settings** (the Dictation tile's chevron, as on the Wi-Fi and Bluetooth tiles, with a long press as a silent alias; `omamobile-voice settings`; Setup > Voice): the speech model, Power + Volume Up and the check before Ask. voice.json is now version 3. Earlier keys (`holdPill`, `micKey`, `agentMic`, `agentSubmit`, `sayToSend`) are read past and dropped on the next write; the two that still mean something keep their values.
- **Kept from before:** the service and its state machine, haptic ticks (feedbackd `button-pressed`), Power + Volume Up in omamobile-keys, the home surface's input mask over the dock (0.2.58), tiny.en through the daemon's config, and the `which` dependency.

### Found on the phone (0.2.61), fixed in 0.2.62

- **Holding the pill works and inserts text.**
- **The keyboard flashed up as the drawer closed,** after the drawer was opened by a tap on the search pill, but not after a swipe. The tap focused the search field before the drawer's surface had the keyboard focus. The first touch on the drawer (the pull down to close it) gave the surface that focus, the focused field asked for the keyboard, and squeekboard came up over the closing drawer. Now every open leaves the field waiting for a tap, as a swipe already did (typed keys still search, through the sheet), and a closing drawer gives the field's focus back first.
- **The keyboard's Mic key did nothing.** Hyprland reads `hypr/phone.lua` at start and on `hyprctl reload`, so the running session kept 0.2.60's binds for calls that no longer exist. `omamobile-shell.install` now reloads every running Hyprland after an upgrade, as its own user. Mic stays press/release: a tap opens the bar listening (the release does nothing), a hold longer than 0.7 s stops on release (push-to-talk), and a press while the bar listens is Done.

### Checks on the phone (0.2.61, the bar)

Results on the Pixel 7 Pro, 2026-10-31, omamobile-shell 0.2.61 (the maintainer): holding the pill opens the bar and the text is typed; the keyboard's Mic key works once Hyprland has reloaded (see above); with the keyboard up, the words are typed into the field and Send sends them; Power + Volume Up opens the bar; the Dictation tile opens it, and its long press opens the settings (0.2.62 adds the chevron). The keyboard's Paste opens the clipboard manager, and Emoji inserts the emoji picked. Ask from a hold on the home screen's search bar showed the editable check with the full-permissions warning and sent the prompt; changing the chip to Copy to clipboard while listening put the text on the clipboard. Every check passed, apart from what 0.2.62 fixes.


1. `omamobile-voice snapshot` answers `"phase":"idle"`.
2. In Messages with the keyboard up, tap the keyboard's Mic, speak, then tap Done · type it: the text is typed into the field. The bar sits right above the keyboard.
3. In Claude Code (keyboard down), hold the pill: the bar says Send to Claude Code with the hint; speak, then Done · send. The text is typed and submitted.
4. On the home screen, hold the search bar: Ask Claude Code. Tap the chip: the list shows Ask, Copy, Search. Speak, then Done · ask: the warning-coloured check, then Ask opens a terminal with the prompt.
5. Hold the pill and swipe up without letting go: you go home, and the bar keeps listening (Cancel closes it). A quick swipe goes home with no bar. Double-tap the pill twice: the keyboard shows, then hides.

## History (0.2.57-0.2.60)

Superseded by [the voice bar](#the-voice-bar-0261). Kept for the facts and for what each phone run found. The sheets, strips and mic keys described below no longer exist.

## Facts (Pixel 7 Pro, 2026-10-31)

- **Engine:** Voxtype 1.1.1 (`voxtype-bin`; `wtype` installed) runs as a systemd user daemon (`voxtype.service`) with Omarchy's config (`/usr/share/omarchy/default/voxtype/config.toml`): Whisper `base.en` is the default model, output `type`, `max_duration_secs = 60`, `state_file = "auto"`, `[hotkey] enabled = false`.
- **Control:** `voxtype record start|stop|toggle|cancel`. `record start` takes `--type | --clipboard | --paste | --file[=PATH]`, `--model <name>` (for this recording only: any downloaded model; the daemon keeps it loaded), `--no-osd`, `--auto-submit` and `--smart-auto-submit` (`voxtype record start --help` on the phone).
- **State:** `$XDG_RUNTIME_DIR/voxtype/state` holds `idle`, `recording`, `streaming` or `transcribing`. `voxtype-audio-bridge` prints one NDJSON frame per audio block (`{"peak","rms","vad","ts_ms"}`) from the daemon's `audio.sock`. Voxtype's own `voxtype-shared/{StateReader,AudioBridge}.qml` show how to read both; the plugin follows them and doesn't import them.
- **OSD:** Voxtype's GTK overlay anchors bottom centre, over the dock and the home pill, so every recording the shell starts passes `--no-osd`.
- **Speed:** before CPU frequency scaling, `tiny.en` turned 10 s of speech into text in 3.9 s and `base.en` in 8.8 s; both were word-perfect. With cpufreq-dt on ACPM (kernel #169, merged), it is 2.36 s for tiny.en and 5.97 s for base.en per 12 s of speech, and with Whisper's context cut to the clip (`context_window_optimization`, 0.2.63) 1.0 s and 2.2 s ([Phase 3](#measurements)). Voxtype's text appears after the recording stops; the bar's live words come from its own preview (0.2.63). `tiny.en` is downloaded on the reference phone (`~/.local/share/voxtype/models/ggml-tiny.en.bin`).

## Architecture (phase 1, history)

| Piece | Where | What |
| --- | --- | --- |
| Voice service and sheets | `plugins/omamobile.voice/Voice.qml` (panel, keepLoaded) | Starts, stops and cancels recordings; follows the state file; runs `voxtype-audio-bridge` while listening, for the level meter; draws the Ask/Confirm sheet and the listening strip; keeps the screen on through an idle inhibitor while it listens and transcribes |
| Pure parts | `plugins/omamobile.voice/VoiceModel.js` | argv builders (`--no-osd` always; the model is the daemon's own), the phase machine (`idle → starting → listening → transcribing → review/error`), push-to-talk, the clock, the meter, the copy/type commands (text on stdin) |
| Link | `plugins/omamobile.voice/VoiceLink.js`, `VoiceLinkClient.qml` | A `.pragma library` script shared by the shell's one QML engine, as with DrawerLink.js. A long press and its release reach the service without starting a process, and the launcher falls back to the plugin's IPC when the service isn't loaded |
| Triggers | `plugins/omamobile.launcher/Launcher.qml` | The mic at the right end of the dock's search pill ("Ask by voice"): a tap calls `askTap` (listen hands free), a hold is push-to-talk. A long press (0.5 s) on the dock's search pill or on the home strip: `askPress`, then `askRelease` when the finger lifts. A one-time toast the first time the dock shows: "Tap the mic, or hold the search bar, to ask by voice". The strip's mic key (left end, only while the keyboard is up): hold to talk (0.3 s), tap to toggle |
| Dictation tile | `plugins/omamobile.quicksettings/tile-action.sh` | `voxtype record start --no-osd --type`; the listening strip shows for it, because the strip shows for any recording the sheet didn't start |
| Agent | `LauncherModel.promptArgv(text)` | `omamobile-launch cmd -- omarchy-agent-prompt "<text>"` (one argv element, no shell), then `omarchy-agent --prompt`, which starts the agent in a terminal. The chip shows the agent's name from `~/.config/omarchy/defaults/agent` (`LauncherModel.agentName`: Claude Code, Codex, OpenCode, and so on); tapping it opens `omarchy menu summon setup.default.agent` |

**Ask flow:** hold the pill. The sheet opens and runs `voxtype record start --no-osd --file=$XDG_RUNTIME_DIR/omamobile-voice.txt` (removing the old transcript first, in the same process). When the finger lifts, `record stop` runs. A press shorter than 0.7 s after listening starts keeps listening until you tap Stop. The phase goes from transcribing to idle, and the sheet reads the file. A transcript opens the check-and-send page; an empty one shows "Didn't catch that" with Say again. On the check-and-send page the transcript is editable (normal exclusion, so the field stays above the keyboard) and you have Send to <agent>, Say again, Cancel, Copy (`wl-copy`) and Type into last app (`wtype -`, half a second after the sheet closes, when the app has the keyboard focus again). Closing the sheet while it listens runs `record cancel`.

**Dictation flow:** the mic key or the tile runs `--type`, and Voxtype types into the focused app. The listening strip sits on the top layer with its own exclusive zone, so the app's field ends above it, and it never takes the keyboard focus. It shows "Listening", the time ("stops at 1:00" for the last 10 s), the level, Cancel and "Done · type it".

## Found on the phone (0.2.57, 2026-10-31, history)

- **Taps on the home screen's search pill did nothing.** Since 0.2.56 the dock reserves no space. The home screen's full-screen surface (Bottom layer, normal exclusion) therefore reaches down over the dock, and both sit on the Bottom layer. Whichever surface mapped last is on top. After a shell restart the home screen, which is slower to load, mapped after the dock and took every touch in the dock's strip. Coming back from an app re-maps the dock and hides the problem, which is presumably why 0.2.56 looked fine. 0.2.58 gives the home surface an input mask that ends above the dock (`dockInset`; the whole screen while the keyboard is up).
- **Nobody could find the hold gesture.** 0.2.58 adds a visible mic in the search pill and a one-time toast.
- **Dictated text never arrived** ("Output failed: All output methods failed"; debug log: "wtype not available … clipboard (wl-copy) not available"). Voxtype 1.1.1 checks for its output tools with `which`, and the phone image has no `which` package (Omarchy's desktop installs do). omamobile-shell now depends on `which`.
- **tiny.en was ignored** ("Requested model 'tiny.en' not in available models, falling back to default 'base.en'"). Voxtype only accepts a `--model` it has prepared (`whisper.model` or `whisper.secondary_model`), so the per-recording `--model tiny.en` did nothing. 0.2.58 drops it. Instead, `omamobile-setup-user` sets `[whisper] model = "tiny.en"` in `~/.config/voxtype/config.toml`, once, and only when `ggml-tiny.en.bin` is downloaded and the config still has Omarchy's base.en; a model the user chose stays. It then runs `systemctl --user try-restart voxtype.service`. Downloading tiny.en stays a phase-2 settings action (`omarchy-voxtype-model`).

## Phase 1 checks on the phone (history)

Read-only first; each step needs only the shell. Announce before starting, because the microphone opens and text gets typed.

1. `pacman -Q omamobile-shell` reads 0.2.58, and `omarchy-shell shell call omamobile.voice snapshot ''` answers with `"phase":"idle"`; `which which` finds it; `journalctl --user -u voxtype` shows tiny.en loaded.
2. Right after a shell restart, tap the home screen's search pill: the drawer opens with the keyboard. Tap its mic: the sheet listens until Stop. Then hold the search pill. The sheet opens listening; speak and let go. Expect "Transcribing" for about 2-4 s, then the check-and-send page with the text. No Voxtype overlay appears.
3. Over an app, hold the strip's pill: the same flow. A short press then release keeps listening until Stop. Cancel closes the sheet and `snapshot` returns to idle.
4. On the check-and-send page, tap the text: the keyboard comes up and the field stays above it. Edit it, then Send: a terminal opens with the agent and the prompt. Tap the chip: Omarchy's agent picker opens.
5. Copy, then paste somewhere. Type into last app types into the app that was open.
6. Open a text field (Messages) so the keyboard is up. Tap the mic key at the strip's left end, speak, then tap Done: the text is typed into the field. Hold the mic key, speak, let go: the same. **Risk:** wtype and squeekboard both use a virtual-keyboard keymap; check that typing works with the keyboard visible, and that squeekboard's keys still work afterwards.
7. Quick settings > Dictation: the listening strip shows, and Voxtype's overlay doesn't.
8. Leave the phone listening for over 60 s: the strip and sheet show "stops at 1:00", Voxtype stops itself, and the screen stays on throughout.

Stop condition: anything typed into the wrong window, squeekboard stops responding, or the shell restarts. Rollback: `voxtype record cancel`, then reinstall omamobile-shell 0.2.56.

## Phase 2 (0.2.59-0.2.60, history)

- **Follow-up inside the agent (artboard FollowUp).** While an agent's terminal is in front (`org.omarchy.agent`, the one app id `omarchy-agent` gives every agent through `omarchy-launch-tui`; read from the Wayland toplevel's app id) and the keyboard is down, the home strip carries a mic at its right end, in the hide key's place. Hold it to talk, or tap to start and tap again to stop. Voxtype types into the agent (`record start --no-osd --type`), then by default presses Enter (`--auto-submit`). The agent setting can change this to Enter only when the speech ends in "submit" (`--smart-auto-submit`) or never.
  - The first version (0.2.59) floated a 60 px round mic at the bottom right. A terminal agent's prompt line sits at the bottom of the screen, so the mic covered its right end. The strip already reserves its height, so apps end above it, and the mic fits inside without changing that height.
  - The strip's swipe and double tap skip the mic's area (`ownTaps`), as with the keyboard strip's keys.
  - The keyboard strip's mic key is unchanged, and keyboard dictation never submits.

- **Voice settings (artboard Settings).** Opened from a long press on the Dictation tile, from Omarchy's Setup > Voice (added to the menu extension by `omamobile-setup-user`), or with `omarchy-shell shell summon omamobile.voice '{"page":"settings"}'`. The sheet has:
  - the local-only notice;
  - the speech model: Fast tiny.en 75 MB, Balanced base.en 142 MB, or Accurate small.en 466 MB. A model that isn't downloaded yet downloads through Voxtype itself (`voxtype setup --download --model X --no-post-install --progress-format json`, progress on the row). The switch is `voxtype config set whisper.model X` followed by `systemctl --user try-restart voxtype.service`;
  - the triggers: hold the home pill, the mic key under the keyboard, the mic over agents, and Power + Volume Up (off by default);
  - talking to an agent: "Send automatically" (the default, `--auto-submit`), "Say 'submit' to send" (`--smart-auto-submit`: Voxtype strips a trailing "submit" and presses Enter; the word is fixed, `text.smart_auto_submit` is only on or off, so a spoken "send" is just typed, as it was on the phone), or "Don't submit". 0.2.59's on/off switch (`sayToSend`) migrates: on becomes Send automatically, which is what the first user wanted, and off becomes Don't submit. The choice applies to the agent mic, and to Power + Volume Up while an agent is in front. Dictation into other apps (the keyboard's mic key, the Dictation tile, the key chord over other apps) never submits;
  - "Ask before sending to an agent" (on; when off, the transcript goes straight to the agent).

  The settings are stored in `~/.config/omamobile/voice.json`, beside quicksettings.json and home.json. The search pill's mic always works, so voice can't be switched off by accident.
- **Power + Volume Up push-to-talk** (`omamobile-keys`). Hold Power, then Volume Up, or the other way round: it dictates into the app in front, or opens the agent sheet on the home screen. Letting go stops it. The volume doesn't change, and Power's own gesture is skipped for that press, as with the screenshot chord. It is off unless `powerVolumeUp` is true in voice.json, and it never runs on the lock screen. A new Volume Up release bind ends it; every other release does nothing. Hyprland drops a key's release bind once another key goes down after it, so Power's release ends it too.
- **Haptic ticks** at the start and end of listening, through feedbackd (`fbcli -E button-pressed`, the same event the OWL widgets use), so the user's feedback profile (silent, quiet) decides. Nothing happens without fbcli.

## The themed keyboard and its action row (0.2.61)

Artboard 6 of the voice canvas (Keyboard): squeekboard in the Omarchy theme, with a row of our own keys.

- **Theme.** `omamobile-keyboard-theme` reads the theme's `colors.toml` and Omarchy's monospace font (`omarchy-font-current`) and writes `~/.local/state/omamobile/keyboard.css`: `sq_view` on the theme's dark background with an accent line on top, square `sq_button` keys on its lighter background, modifier and layout keys a step lighter, the accent on Enter (`#Return`) and on a latched or locked modifier (Ctrl held), and the action row outlined (Mic in the theme's red, the recording colour, the rest in its muted colour). squeekboard loads its own stylesheet at GTK's APPLICATION priority and `~/.config/gtk-3.0/gtk.css` (USER priority) overrides it, so setup puts one `@import` line at the top of that file, once, leaving the user's own rules below it. The selectors match only squeekboard's widgets. GTK 3 reads gtk.css only at startup, so setup restarts a running squeekboard when the `@import` or the stylesheet is new (on the first install the old, unthemed keyboard otherwise stayed up), through Hyprland's exec (`hl.dsp.exec_cmd("uwsm-app -- squeekboard")`; a direct start from an SSH session didn't come back), and Omarchy's theme-set hook (`~/.config/omarchy/hooks/theme-set.d/50-omamobile-keyboard`, linked once) rewrites the stylesheet and restarts a running squeekboard, which blinks out for a moment. The stylesheet is also rewritten at every login.
- **Layouts.** The terminal layout (`terminal/us.yaml`) and, new, US English (`us.yaml`) and both in landscape (`_wide`; squeekboard would otherwise take its own landscape layout before our portrait one), each starting with the action row: **Mic, Paste, Emoji, Hide**, each a Nerd Font icon and a word (Hide is a keyboard over a down arrow, so it doesn't read as a drop-down). The first version had Talk and Ask and a caret; the maintainer found the three confusing. The terminal row is Esc, Tab, Ctrl, Alt, `|`, `~`, `/` and the arrows (Shift stays on the Shift view's row). Other languages keep squeekboard's own layouts, so they have neither row: carrying a copy of each is the cost noted in omamobile.keyboard.
- **Keys and binds.** squeekboard has no action that runs a command. Each action key sends an XF86 keysym (`XF86Dictate`, `XF86Paste`, `XF86EmojiPicker`, `XF86Keyboard`), and `hypr/phone.lua` binds them for squeekboard's virtual keyboard alone (`device = { inclusive = true, list = { "hl-virtual-keyboard-squeekboard" } }`): Mic is omamobile.voice's `press`/`release`: the voice bar with the destination from context, push-to-talk because squeekboard presses a keysym key on touch-down and releases it on lift-off (a short tap keeps listening until Done, and a tap while it listens is Done). Paste opens Omarchy's clipboard history (`omarchy-menu-clipboard`), Emoji its emoji picker (`omarchy-menu-emoji`), and Hide calls omamobile.keyboard's `hideKeyboard`.
- **Why the device resolves binds by keysym.** squeekboard puts each key on a keycode of a keymap it generates, and Hyprland resolves a bind's keysym through `kb_layout` unless the device sets `resolve_binds_by_sym` (`KeybindManager.cpp`, 0.56.2). `hl.device({ name = "hl-virtual-keyboard-squeekboard", resolve_binds_by_sym = true })` turns it on for squeekboard only. That also lets squeekboard's Ctrl, Alt, Tab, Delete and F9 reach Omarchy's binds for the first time: Ctrl + Alt + Delete would close every window, F9 would start Voxtype instead of reaching the terminal, Alt + Tab would switch windows. `phone.lua` re-binds those (Ctrl + Alt + Delete, Alt + Tab, Alt + Shift + Tab, Ctrl + Alt + Tab, Ctrl + Alt + Shift + Tab, and F9 when Voxtype is installed) for every keyboard but squeekboard. `hl.unbind` drops a user's own bind on one of those keys too. squeekboard has no Super key, so SUPER binds stay out of its reach.
- **The emoji picker.** Omarchy's (`omarchy.emojis`, an overlay with the menu's theme tokens) has 44 px cells, so tapping an emoji works; it types it through `wl-copy` and Shift + Insert into the app behind. Its search reads key presses into the overlay, which takes the keyboard focus exclusively, so squeekboard can't type into it: on a phone you scroll and tap. Omarchy's picker would need a text field (text-input) for squeekboard to raise itself over it. squeekboard's own emoji layout (the globe key's list) is touch-native and follows our stylesheet too, but no key can switch layouts.

### Checks on the phone (0.2.61)

Read-only first, then one change at a time. Announce before restarting squeekboard: the keyboard disappears for a moment.

1. After installing, log out and in (or run `omamobile-setup-user`): `ls -l ~/.local/share/squeekboard/keyboards/ ~/.local/share/squeekboard/keyboards/terminal/` shows four links; `head -1 ~/.config/gtk-3.0/gtk.css` is the import line; `ls -l ~/.config/omarchy/hooks/theme-set.d/` shows the hook. Expect the keyboard in theme colours after squeekboard's next start.
2. **Do the binds fire from squeekboard?** `hyprctl devices | grep -A2 squeekboard` names `hl-virtual-keyboard-squeekboard` (the name the binds use). Open a terminal, show the keyboard, and tap Hide: the keyboard goes away. Pass: hidden; the terminal received no key. Stop condition: nothing happens (check the device name; check `hyprctl binds | grep -A6 XF86Keyboard` lists the bind and the device). Rollback: the pill's double tap still hides it; reinstall 0.2.60.
3. Hold Mic, speak, let go: the text is typed into the field. Then tap Mic once, speak, and tap Done in the bar. Pass: press opens the bar listening, a hold's release stops it.
4. Paste: Omarchy's clipboard list opens; tap an entry, it is pasted. Emoji: the picker opens; tap an emoji, it is typed.
5. In the terminal, latch Ctrl, then press Alt and the actions view's Del: no windows close (Ctrl + Alt + Delete is kept from squeekboard). With Voxtype installed, F9 from the actions view reaches the terminal (no dictation starts).
6. Change the theme (Style > Theme): the keyboard blinks out and comes back in the new colours.
7. The home-screen keyboard: in an app with no text field, double-tap the pill to show the keyboard, then swipe home. Pass: the keyboard goes away (shell log: `omamobile.keyboard: home screen up, hiding the keyboard shown by hand`). A keyboard raised by a text field behaves as before.

Risk: low (userspace only). Rollback: reinstall omamobile-shell 0.2.60; remove the import line from gtk.css and the hook link to go back to squeekboard's own look.

## Phase 3 (0.2.63, branch `voice-phase3`)

Built offline; nothing was installed on the phone. The timings below are read-only runs on the Pixel 7 Pro (2026-10-31, kernel with cpufreq-dt on ACPM, on the charger) of `voxtype transcribe` on the 11.9 s clip from the CPUFREQ-PLAN C4 run (the maintainer's own recording, on the phone only, never in the repository) and on slices and repeats of it made on the laptop. No new recording was made and no microphone was opened.

### What Voxtype 1.1.1 can do for streaming

Read from the installed binary (`voxtype --help`, `voxtype record start --help`, `voxtype info engines`, the strings in `/usr/lib/voxtype/voxtype-cpu`) and Voxtype's source at tag v1.1.1 (`src/daemon.rs`, `src/output/streaming.rs`):

- **Engines.** The active binary (`voxtype-cpu`) has Whisper only; `voxtype-onnx` adds Parakeet, Moonshine and others. Parakeet's cache-aware streaming (`parakeet-unified-en-0.6b`) is the one native streaming engine; Whisper gets a sliding-window streaming mode (`[whisper] streaming = true`, tuned in a `[streaming]` section: `interval_secs` 0.8, `min_audio_secs` 1.0, `type_partials`, `revision_mode` and so on). It is marked experimental, needs toggle activation and `on_demand_loading = false`, and is a setting of the daemon, so it would apply to every recording, desktop hotkeys included.
- **Where partials go.** Into the focused window only. In type mode the daemon types each committed delta at the cursor (and backspaces in revision mode). With `--file`, which the bar uses so the destination can change while you speak, the partials are kept in memory (`observe_partial_delta`) and only the final text is written, at the end. The state file says `streaming` and nothing more; `voxtype status --follow` carries partials only for the Soniox cloud engine. So the shell can't read Voxtype's partial text, and typing partials into the app would break Ask, Copy and Search and the chip's change of mind mid-sentence.
- **Eager processing** (`[whisper] eager_processing`, 5 s chunks cut at quiet points) transcribes chunks while you speak, but combines them only when the recording stops: it would shorten the wait after Done, not show words earlier. Not turned on (below).
- **Context window optimization** (`[whisper] context_window_optimization`, off by default; Voxtype warns of repetition loops on large-v3 and turbo) runs Whisper's encoder on the clip's length instead of a full 30 s window, for clips under 22.5 s. This is the big lever on the phone (next section).

### Measurements

Each run is a fresh `voxtype transcribe` process, so the times include loading the model (about 0.07 s from the page cache); the daemon keeps its model loaded and is a little faster.

| Audio | tiny.en, full window | tiny.en, context cut | base.en, full window | base.en, context cut |
| --- | --- | --- | --- | --- |
| 1 s | 2.06 s | 0.46 s | | |
| 3 s | 2.05 s | 0.51 s | | 1.06 s |
| 6 s | 2.22 s | 0.66 s | | |
| 11.9 s | 2.21-2.36 s | 1.03 s | 5.01 s | 2.22 s |
| 23.8 s | | | | 5.24 s (over 22.5 s: full window) |
| 47.5 s | | 5.06 s (full window) | | 11.08 s (full window) |

With the full window every clip under 30 s costs the same, which is why a 1 s clip took as long as 12 s. Accuracy on the clip, as text: base.en with the full window "Open the voice plan. Check which tests still fail on the phone and send me a short summary before dinner."; base.en with the cut "... which test still fail ..."; tiny.en with the cut "Or open the voice plan, check which tests still fail on the phone and send me ..."; tiny.en with the full window "... fail in the phone ...". Both models hear an "or" in the first second when given only that second, so which start is right needs the speaker. One clip can't rank the models; it shows they differ by a word or so per sentence here.

**The live preview, end to end on the phone** (`omamobile-voice-preview --from -`, the clip fed at real time, no microphone): the first words after 1.2 s, then a pass every 1.2 s of new audio at 0.58-0.92 s each, the text 1.2-2 s behind the speech, and the preview's last text matched the final transcript word for word. On 47.5 s (the clip four times over): passes at 0.53-0.92 s throughout, one pass dropped by the timeout (below), and 1.8 CPU cores busy on average while listening (86.6 s of CPU time in 48 s, Python included). The daemon's own transcription starts after Done and isn't slowed: the preview is stopped first.

### What 0.2.63 does

1. **Live partial text in the bar.** `bin/omamobile-voice-preview` opens a second capture of the same microphone (`pw-record --raw`, 16 kHz mono, node `omamobile-voice-preview`, role Communication), keeps it in memory and never writes it to disk, and transcribes it in chunks with `voxtype transcribe`, tiny.en and the context cut (`-c` from a pipe: `context_window_optimization = true`, `threads = 4`, nice 10), while the daemon records the real thing.
   - Chunks: the audio since the last commit is transcribed again after each 1.2 s of new audio (2.5 s when only base.en is there; no preview with small.en, which would lag). At 8 s it is cut at its quietest 50 ms within 0.5-2.5 s of the end, that part's text is kept and the rest starts the next chunk, so a pass never sees more than 8 s whatever the length of the recording.
   - A chunk quieter than an RMS of 120 (int16) is skipped: Whisper makes up words for silence. Tags such as `[BLANK_AUDIO]` and `(music)` are dropped.
   - A pass that takes longer than 2 x step + 0.5 s is killed: with the short context Whisper once looped 5.9 s on a chunk that was mostly silence ("for alternatively."). The next pass catches up.
   - It stops on SIGTERM (killing the pass under way at once, so the daemon has the CPU), when its capture ends, and after 75 s whatever happens; its children get SIGTERM if it dies (`PR_SET_PDEATHSIG`), so the microphone is never left open.
   - The bar runs it only while its own recording listens (`VoiceModel.previewRuns`) and with **Show words as you speak** on in the settings (on by default; voice.json's new `livePreview`). The words sit between the meter and the buttons in the theme's `Commons.Color.muted`, the last two lines with an ellipsis in front (`partialTail`); they stay while the daemon transcribes, and the final text replaces them, in the text colour, for 0.9 s (phase `delivered`) before the bar closes. Ask keeps its editable check, which shows the final text.
2. **Model choice: base.en is the default again, with the context cut.** With the cut, base.en turns 12 s of speech into text in about 2.2 s: what tiny.en cost before (2.36 s), with the larger model. tiny.en stays the preview's model. `omamobile-setup-user`:
   - adds `context_window_optimization = true` under the user's `[whisper]` once, unless the config sets it already (a user's `false` stays; removing it keeps it removed);
   - no longer switches to tiny.en, and undoes 0.2.58-0.2.62's switch once: only when the `omamobile-voxtype-tiny` marker exists, base.en is downloaded, the model still reads tiny.en and the config is no newer than that marker (plus a minute). A model the user chose since then stays. The reference phone has no such marker (tiny.en was set there by hand or in the settings), so it keeps tiny.en until the maintainer picks Balanced;
   - restarts voxtype once, only if something changed and it was running.
   Above 22.5 s the cut doesn't apply and base.en takes 5-11 s for 24-48 s of speech. Eager processing would hide most of that wait; it is left for a phone check of its own (it changes how the daemon records).
3. **The action row for every language.** `squeekboard/generate` makes each of squeekboard 1.43.1's layouts (60 languages and variants, portrait and `_wide`, the email and URL layouts, and the German, Spanish, French, BÉPO and Dvorak terminal layouts: 118 files) from upstream's own file, keeping it byte for byte and adding a header, four outlines, the row at the top of every view and four buttons. The row is as wide as the layout's widest row (Mic and Paste 30 % each, Emoji and Hide 20 %) and 10/13 of a letter key's height. The US English files it makes are the 0.2.61 hand-made ones line for line, apart from the header. `--check` (in test/all) takes those lines out, runs the generator on what is left and compares, so the upstream copies needn't be in the repository. The emoji, number and PIN layouts get no row (a PIN pad must not start the microphone); terminal/us stays ours by hand. Setup links every installed layout unless the user has a file of their own by that name.
4. **Voice on the lock screen:** design only, [below](#voice-on-the-lock-screen-design).

### Checks on the phone (0.2.63)

Announce first: the microphone opens, the keyboard restarts once (new layouts), and the voxtype daemon restarts once (the new setting). Read-only steps first.

1. `pacman -Q omamobile-shell` reads 0.2.63. After a login (or `omamobile-setup-user`): `grep -n context_window_optimization ~/.config/voxtype/config.toml` shows it under `[whisper]`; `ls ~/.local/share/squeekboard/keyboards | wc -l` is about 100 (plus the subdirectories). Pass: both. Risk: none.
2. `omarchy-shell shell call omamobile.voice snapshot ''`: `"phase":"idle"`, `"preview":false`, `settings.livePreview` true.
3. Hold the pill in Messages and say a sentence of 10 s or so. Expect the first words in the bar about 1.5 s in, muted, growing every second or so; after Done, "turning it into text" with the words still there, then the final words in the text colour for under a second and the text in the field. Pass: words appear while speaking; the final text is typed. Stop condition: no words after 5 s of speech (check `journalctl --user -b | grep -i voice-preview` and `pw-dump | grep omamobile-voice-preview`), or the final text is missing or wrong (preview interfering with Voxtype's capture). Rollback: Show words as you speak off in Voice settings, or reinstall 0.2.62.
4. The wait after Done with base.en: settings > Balanced, then the same 10 s sentence. Expect 2-3 s of "turning it into text". Pass: under 3.5 s, and the text at least as good as tiny.en's. If not, keep Fast (the setting stays).
5. While listening, from SSH: `pgrep -a pw-record` shows one `omamobile-voice-preview` capture; after Done or Cancel it is gone within a second, and `pgrep -f "voxtype -q -c"` finds nothing.
6. Switch the keyboard to German (squeekboard's globe key): the action row is on top; Mic opens the bar. Then in landscape. Pass: row present, keys work.
7. Leave the bar listening past 60 s: Voxtype stops at 1:00; the preview is gone (step 5's checks).

Risk: low (userspace). Battery: about two cores while listening, nothing otherwise.

**Results, 2026-11-01** (`7.3.0-rc6-omamobile-push1-g8e6f0f3e3763`, omamobile-shell 0.2.63-1):

- 1, 2: pass after `omamobile-setup-user` and a shell restart (`context_window_optimization = true` under `[whisper]`, 107 layout files, `preview` in the snapshot). The restart waits for an unlocked phone: `omarchy-restart-shell` refuses while locked, so the old plugin kept running until then. The model stayed tiny.en: this phone had no `omamobile-voxtype-tiny` marker, so setup treats tiny.en as the owner's choice, as designed.
- 3: pass. Words appeared in the bar while speaking (31 characters three seconds in), the final text was typed.
- 5: pass. One `omamobile-voice-preview` capture while listening; after Done no `pw-record` and no `voxtype -q -c` left.
- 6: pass. German (input sources `us`, `de`): the action row on top, Mic opens the bar, upright and on its side. Found on the way: squeekboard's globe menu (a GTK popover) is drawn at mouse size and sticks out above the keyboard's surface, and taps on it don't land, so a layout can't be picked by touch. Not from 0.2.63; the follow-up replaces the globe's menu with a language picker in the shell.
- 4, 7: not run (base.en's wait after Done, the 60 s cap).

### Voice on the lock screen (design)

Not built. Today Power + Volume Up does nothing while locked (`omamobile-keys` checks `omarchy-shell lock isLocked`), and the voice bar, a Top-layer surface, can't show over Omarchy's lock anyway.

**The rule:** while the phone is locked, speech may be heard and turned into text on the phone, and nothing may act on it. Whoever holds a locked phone isn't known to be its owner, and the agent runs with full permissions.

May run while locked:
- **The trigger:** Power + Volume Up only, held (push-to-talk), and only with a second switch, "Also on the lock screen", off by default under Power + Volume Up. No pill hold, no tile and no keyboard key: the lock has none of them, and nothing starts the microphone on its own (no wake word).
- **Recording and transcription,** local as always, with the live preview, under Voxtype's 60 s cap; the haptic ticks as unlocked.
- **A lock-screen card** on the overlay layer, allowed over the lock the way the call screen is (`above_lock` in `hypr/phone.lua`, namespace `omamobile-voice-lock`): the meter, the words so far, Cancel and "Done · ask after unlock". It shows only what was just said: no agent output, no earlier transcripts, no notification text.
- **One pending ask,** kept in the session's runtime directory (`$XDG_RUNTIME_DIR/omamobile-voice-pending.json`, mode 0600, tmpfs, gone at logout), with its time. A new recording replaces it; it expires after 10 minutes; Cancel deletes it.

Must wait for unlock:
- **Anything that acts:** a prompt to the agent, typing (wtype would type into the app behind the lock), the clipboard, the launcher's search, starting an app. The destination chip isn't offered on the lock: the only destination is "ask after unlock".
- **The check before Ask always shows** for a pending ask, even with "Check before asking the agent" off: after unlock the bar opens in its result step with the text, the full-permissions warning and Discard / Again / Ask. An unlock more than 10 minutes later finds nothing.
- **Settings and model downloads**, as now.

Edges: the screen stays on while the card listens (the lock's own idle rules otherwise); a call ringing takes over (the call screen is above, and the recording is cancelled); unlocking while listening moves the recording to the ordinary bar with the "ask" destination, unchecked words still going to the check. Test plan when built: locked, chord held, speak, let go: the card shows the words; unlock: the check shows them; with the switch off the chord does nothing locked; after 10 minutes nothing pending; nothing typed or copied while locked (watch `wl-paste` and the app behind).

## The language sheet (0.2.65, branch `keyboard-language-picker`)

Found in check 6 of 0.2.63: squeekboard's globe key opens squeekboard's own GTK popover (English (US), German, Emoji, Terminal, Keyboard Settings). It is drawn at mouse size, sticks out above the keyboard's layer surface (`osk`, 480x280 logical at y=760 of 480x1040), and taps on it don't land, so the layout can't be changed by touch. Keyboard Settings asks for a GNOME settings panel the phone doesn't have. 0.2.65 replaces the popover with a sheet in the shell.

### How squeekboard 1.43.1 switches (source, tag v1.43.1, commit `15569da0`)

- **The globe key** is `preferences: { action: "show_prefs", icon: "keyboard-mode-symbolic" }` in every text layout (`src/data/parsing.rs:97`, `#[serde(rename="show_prefs")]`, mapped to `Action::ShowPreferences` at :387). On release, `src/layout.rs:1193` calls `popover::show` with the key's bounds; nothing else happens. Of the upstream layouts, all 120 text layouts plus `emoji/` and `number/` have it; `pin/` doesn't.
- **The popover** (`src/popover.rs:228`, `show`) lists `org.gnome.desktop.input-sources` `sources`, named by gnome-desktop's XkbInfo (xkeyboard-config's descriptions, `translate_layout_names`, :194), sorted by name, then the overlays `emoji` and `terminal` (`src/resources.rs:210`, `OVERLAY_NAMES`), then Keyboard Settings, which calls `org.gnome.Settings` over D-Bus (`src/popover.c:57`, `popover_open_settings_panel("keyboard")`).
- **Choosing a language** sends `state::Event::OverlayChanged(LayoutId::System)` (:330) and calls `set_layout` (:129): it rewrites `sources` with the chosen `(kind, name)` first and the rest in their order. squeekboard watches the whole schema (`eekboard/eekboard-context-service.c:234`, `change-event`) and on any change takes `sources[0]` ("current layout is always first", :123) as `Event::LayoutChoice`, which also clears an overlay (`src/state.rs:332-335`). `mru-sources` and `current` are never read. So **an external process switches the keyboard by rewriting `sources` with the layout first**, exactly as the popover does, and the switch is immediate.
- **Emoji and Terminal** are not sources. Choosing one sends `OverlayChanged(LayoutId::Local(name))` into squeekboard's state (:330), which only the popover's own action can do: the overlay lives in squeekboard's state (`src/state.rs:455`, `get_layout_names`) and the popover actor's cache (`src/actors/popover.rs`), not in any setting, and squeekboard's only D-Bus interface is `sm.puri.OSK0` (`SetVisible` and `Visible`, `data/dbus/sm.puri.OSK0.xml`). **Nothing outside squeekboard can select an overlay.** The alternatives we have: the action row's Emoji key opens Omarchy's emoji picker (`omarchy-menu-emoji`), and the terminal layout comes up on its own when the app's text field says it is a terminal (`src/data/loading.rs:126`, `ContentPurpose::Terminal`), from our `terminal/` layouts. A fake source to reach `emoji/us` is possible (squeekboard looks a name up as a path) but would leave a bogus xkb layout in a GNOME setting: not done.
- **A keysym key** can send any name xkbcommon knows (`keysym_valid`, `src/data/parsing.rs:301`); squeekboard puts it on a keycode of its own keymap, as for Mic, Paste, Emoji and Hide. There is no `XF86Language`; `XF86MediaLanguageMenu` (KEY_LANGUAGE, 0x10081170) is the language key, and nothing in Omarchy binds it.

### What 0.2.65 does

- `squeekboard/generate` changes the globe key in every generated layout to `keysym: "XF86MediaLanguageMenu"` (one changed line; `--check` puts `show_prefs` back before comparing), and the two hand-made terminal layouts get the same line. No layout we carry opens the popover. `emoji/` (an overlay we no longer offer) keeps upstream's; `number/` and `pin/` stay upstream's too (`number/us` has no globe).
- `hypr/phone.lua` binds `XF86MediaLanguageMenu`, for squeekboard's virtual keyboard only (`device = osk_only`, like the action row), to `omarchy-shell shell call omamobile.keyboard languages ''`.
- `omamobile.keyboard` draws the sheet (`LanguageWindow.qml`, overlay layer over the keyboard, no keyboard focus, so the text field keeps it and squeekboard stays up; `LanguageSheet.qml` in Omarchy's tokens, like the permission sheet): a 56 px row per source with xkeyboard-config's name (as squeekboard shows), the current one checked, a remove target on the others (never the last one), and "Add a language", a scrolling list of the layouts the keyboard carries that aren't on the list. A tap switches and closes; a tap outside or a swipe down closes. With one language the globe still opens the sheet.
- `bin/omamobile-keyboard-languages list|set|remove` reads and writes `sources` through `gsettings`; `set` is squeekboard's `set_layout` (an empty `sources`, squeekboard's `us` fallback, becomes `[us]` plus the new one).

### Checks on the phone (0.2.65)

Announce first: the keyboard changes layout during the test. Read-only first. Rollback for all: `pacman -U` the 0.2.63 package (or `gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'de')]"` for the list alone).

1. `pacman -Q omamobile-shell` reads 0.2.65; `grep -c XF86MediaLanguageMenu ~/.local/share/squeekboard/keyboards/us.yaml` is 1 and `grep -rl show_prefs ~/.local/share/squeekboard/keyboards` prints nothing; `hyprctl binds | grep -A3 XF86MediaLanguageMenu` shows the bind (after the package's Hyprland reload). Stop if the layouts still have `show_prefs` (setup-user hasn't relinked them). Risk: none.
2. `gsettings get org.gnome.desktop.input-sources sources` (note it for rollback); `omamobile-keyboard-languages list` prints JSON with both languages named (English (US), German). Risk: none.
3. In a text field, tap the globe. Expect: the sheet slides up over the keyboard, English (US) checked, German with an ×, Add a language; no GTK popover. Pass: rows are full width and a thumb tall. Stop if squeekboard's popover still appears (old layouts) or nothing happens (`omarchy-shell shell call omamobile.keyboard state ''`).
4. Tap German. Expect: the sheet closes, the keyboard is German (QWERTZ) at once, and `sources` starts with `de`. Tap the globe again: German is checked. Switch back to English.
5. Globe, then tap above the sheet: it closes. Globe, then swipe the card down: it closes. Neither changes the layout.
6. Add a language: pick French; the keyboard is AZERTY and French is on the list. Then × on French (while another is current): it goes. The current language has no ×. Risk: low (the list changes; rollback above).
7. On its side: the sheet keeps to 600 px, centred, and the list scrolls on the add page.

**Results, 2026-11-01** (`7.3.0-rc6-omamobile-push1-g8e6f0f3e3763`, omamobile-shell 0.2.65-1): all pass on the Pixel 7 Pro. The globe opens the sheet, English and German switch both ways, tapping outside and swiping down close it, a language can be added and removed, and the sheet works on its side. The first globe tap did nothing only because the phone was locked when the package went on, so `omarchy-restart-shell` refused and the old shell kept running until the restart after unlock.

## Risks

- **wtype vs squeekboard:** both register a zwp virtual keyboard with their own keymap. Text typed while the keyboard is up may come out with the wrong keymap, or upset squeekboard's. Test with the keyboard visible (check 6). The fallback is `--clipboard` followed by a paste.
- **Agents run with auto permissions** (`claude --permission-mode auto`, and the same for the others). A misheard prompt is acted on without another question, so the check-and-send step always shows, and the setting to skip it (phase 2) defaults to asking.
- **Layer order:** the listening strip and squeekboard are both top-layer surfaces that reserve space. If squeekboard maps after the strip, the strip can end up under the keyboard rather than above it. It still works there, but it is not where the design puts it.
- **Transcription time:** before CPU frequency scaling, base.en took about 0.9 s per second of speech, which is why setup switches the daemon to tiny.en once it's downloaded. With scaling merged (kernel #169) it is about 0.5 s per second, tiny.en about 0.2 s, and with the context cut (0.2.63) about 0.19 s and 0.09 s for clips under 22.5 s: a phone on an older kernel is still slow on base.en.
- **The live preview opens the microphone twice** (Voxtype's capture and `pw-record`). PipeWire shares the source, but this hasn't run on the phone yet: phase 3 check 3 watches for a final transcript that comes out wrong or empty. It costs about two CPU cores while listening; the setting turns it off.
