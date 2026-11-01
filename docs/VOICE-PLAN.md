# Voice input plan

Status: 2026-10-31. Phase 1 is built and tested offline in omamobile-shell 0.2.57 (branch `shell-voice`): the model and argv tests, the pill and mic key under touch (qmltestrunner) and the offscreen review shots pass. On its first run on the phone (0.2.57), taps on the home screen's search pill did nothing, and the hold gesture couldn't be found. Dictated text never arrived, and tiny.en was ignored. 0.2.58 fixes all four (below). With 0.2.58, dictation typed correctly into Claude Code (foot) and into a Chromium web app on the phone. Phase 2 shipped in 0.2.59. On its first run the agent mic typed into Claude Code, but nothing submitted: Voxtype submits on a spoken "submit", not "send", which it just typed, and the floating mic covered the right end of the agent's prompt box. 0.2.60, built offline, submits automatically and moves the mic into the home strip (below). Phase 3 is design only.

**0.2.61 replaces all of that with one voice bar** (canvas row U1-U4: UApp, UAgent, UHome, UResult), approved by the maintainer after the earlier UIs had multiplied: a dictation strip, an Ask sheet, a Confirm sheet, a mic in the search pill plus a hold on it, a keyboard-strip mic key and an agent mic in the home strip, each with its own look and its own rules. The sections after [The voice bar](#the-voice-bar-0261) record how the project got there, and what the phone taught at each step.

Design (approved by the maintainer): the voice canvas, <https://claude.ai/artifact/K93k88TFaqyKvChsdk2ugK>. It has five artboards: Main (dictation strip above the keyboard), Ask (listening sheet), Confirm (check and send), FollowUp (phase 2) and Settings (phase 2). The mockups use Tokyo Night hex colours as a stand-in. The shell draws with the applied theme's tokens (`Commons.Color`, `Style`, `Border`) and the update sheet's components, and the recording colour is the theme's `urgent`.

## The voice bar (0.2.61)

One bar, one set of rules, wherever voice starts.

- **Ways in.** As on Android, the bottom bar is just the pill. **Hold the pill** for about 0.45 s, without moving past the swipe threshold, and the bar opens listening, with a haptic tick. A swipe takes the touch first and cancels the hold, and a finger that moves after the hold fired is still a swipe (home or recent apps, the 0.2.56 gestures). On the home screen, a hold on the search pill does the same. **Double-tap the pill** to show or hide the keyboard. A second double tap now always hides it, even before the first show is reported: `KeyboardModel.toggleTarget` trusts the last request for 1.5 s. The keyboard's **Mic** key, **Power + Volume Up** (when turned on) and the **Dictation tile** open the same bar. One command, `omamobile-voice [toggle|start|done|cancel|settings|snapshot]`, is there for the tile and for scripts. The first time the pill-only bar shows over an app, a toast says "Hold the pill to talk · double-tap for the keyboard" (Omarchy's done store, `omamobile-pill-hint`). The Voice settings say it too.
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
- **Settings** (`omamobile-voice settings`, the Dictation tile's long press, Setup > Voice): the speech model, Power + Volume Up and the check before Ask. voice.json is now version 3. Earlier keys (`holdPill`, `micKey`, `agentMic`, `agentSubmit`, `sayToSend`) are read past and dropped on the next write; the two that still mean something keep their values.
- **Kept from before:** the service and its state machine, haptic ticks (feedbackd `button-pressed`), Power + Volume Up in omamobile-keys, the home surface's input mask over the dock (0.2.58), tiny.en through the daemon's config, and the `which` dependency.

### Checks on the phone (0.2.61, the bar)

1. `omamobile-voice snapshot` answers `"phase":"idle"`.
2. In Messages with the keyboard up, tap the keyboard's Mic, speak, then tap Done · type it: the text is typed into the field. The bar sits right above the keyboard.
3. In Claude Code (keyboard down), hold the pill: the bar says Send to Claude Code with the hint; speak, then Done · send. The text is typed and submitted.
4. On the home screen, hold the search pill: Ask Claude Code. Tap the chip: the list shows Ask, Copy, Search. Speak, then Done · ask: the warning-coloured check, then Ask opens a terminal with the prompt.
5. Hold the pill and swipe up without letting go: you go home, and the bar keeps listening (Cancel closes it). A quick swipe goes home with no bar. Double-tap the pill twice: the keyboard shows, then hides.

## Facts (Pixel 7 Pro, 2026-10-31)

- **Engine:** Voxtype 1.1.1 (`voxtype-bin`; `wtype` installed) runs as a systemd user daemon (`voxtype.service`) with Omarchy's config (`/usr/share/omarchy/default/voxtype/config.toml`): Whisper `base.en` is the default model, output `type`, `max_duration_secs = 60`, `state_file = "auto"`, `[hotkey] enabled = false`.
- **Control:** `voxtype record start|stop|toggle|cancel`. `record start` takes `--type | --clipboard | --paste | --file[=PATH]`, `--model <name>` (for this recording only: any downloaded model; the daemon keeps it loaded), `--no-osd`, `--auto-submit` and `--smart-auto-submit` (`voxtype record start --help` on the phone).
- **State:** `$XDG_RUNTIME_DIR/voxtype/state` holds `idle`, `recording`, `streaming` or `transcribing`. `voxtype-audio-bridge` prints one NDJSON frame per audio block (`{"peak","rms","vad","ts_ms"}`) from the daemon's `audio.sock`. Voxtype's own `voxtype-shared/{StateReader,AudioBridge}.qml` show how to read both; the plugin follows them and doesn't import them.
- **OSD:** Voxtype's GTK overlay anchors bottom centre, over the dock and the home pill, so every recording the shell starts passes `--no-osd`.
- **Speed:** with no CPU frequency scaling on this kernel yet, `tiny.en` turns 10 s of speech into text in 3.9 s and `base.en` takes 8.8 s; both were word-perfect. Text therefore appears after the recording stops, and phase 1 shows no live partial text. `tiny.en` is downloaded on the reference phone (`~/.local/share/voxtype/models/ggml-tiny.en.bin`).

## Architecture (phase 1)

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

## Found on the phone (0.2.57, 2026-10-31)

- **Taps on the home screen's search pill did nothing.** Since 0.2.56 the dock reserves no space. The home screen's full-screen surface (Bottom layer, normal exclusion) therefore reaches down over the dock, and both sit on the Bottom layer. Whichever surface mapped last is on top. After a shell restart the home screen, which is slower to load, mapped after the dock and took every touch in the dock's strip. Coming back from an app re-maps the dock and hides the problem, which is presumably why 0.2.56 looked fine. 0.2.58 gives the home surface an input mask that ends above the dock (`dockInset`; the whole screen while the keyboard is up).
- **Nobody could find the hold gesture.** 0.2.58 adds a visible mic in the search pill and a one-time toast.
- **Dictated text never arrived** ("Output failed: All output methods failed"; debug log: "wtype not available … clipboard (wl-copy) not available"). Voxtype 1.1.1 checks for its output tools with `which`, and the phone image has no `which` package (Omarchy's desktop installs do). omamobile-shell now depends on `which`.
- **tiny.en was ignored** ("Requested model 'tiny.en' not in available models, falling back to default 'base.en'"). Voxtype only accepts a `--model` it has prepared (`whisper.model` or `whisper.secondary_model`), so the per-recording `--model tiny.en` did nothing. 0.2.58 drops it. Instead, `omamobile-setup-user` sets `[whisper] model = "tiny.en"` in `~/.config/voxtype/config.toml`, once, and only when `ggml-tiny.en.bin` is downloaded and the config still has Omarchy's base.en; a model the user chose stays. It then runs `systemctl --user try-restart voxtype.service`. Downloading tiny.en stays a phase-2 settings action (`omarchy-voxtype-model`).

## Phase 1 checks on the phone

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

## Phase 2 (0.2.59, built offline)

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

## The themed keyboard and its action row (0.2.61, built offline)

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

## Phase 3

- **Live partial text** once the 7 Pro has CPU frequency scaling, which it lacks today: Voxtype's streaming engines, or a faster Whisper model on a faster CPU.
- **Talk and Ask keys for every language.** Only US English and the terminal layout carry the action row (above); the other languages would each need a carried copy of squeekboard's layout.
- **Power + Volume Up on the lock screen**, for example to ask the agent hands-free. It needs its own design for what may run while locked.

## Risks

- **wtype vs squeekboard:** both register a zwp virtual keyboard with their own keymap. Text typed while the keyboard is up may come out with the wrong keymap, or upset squeekboard's. Test with the keyboard visible (check 6). The fallback is `--clipboard` followed by a paste.
- **Agents run with auto permissions** (`claude --permission-mode auto`, and the same for the others). A misheard prompt is acted on without another question, so the check-and-send step always shows, and the setting to skip it (phase 2) defaults to asking.
- **Layer order:** the listening strip and squeekboard are both top-layer surfaces that reserve space. If squeekboard maps after the strip, the strip can end up under the keyboard rather than above it. It still works there, but it is not where the design puts it.
- **No CPU frequency scaling:** a long recording takes a while to transcribe on base.en (about 0.9 s per second of speech), which is why setup switches the daemon to tiny.en once it's downloaded.
