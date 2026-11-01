# Voice input plan

Status: 2026-10-31. Phase 1 is built and tested offline in omamobile-shell 0.2.57 (branch `shell-voice`): the model and argv tests, the pill and mic key under touch (qmltestrunner) and the offscreen review shots pass. On its first run on the phone (0.2.57), taps on the home screen's search pill did nothing, and the hold gesture couldn't be found. Dictated text never arrived, and tiny.en was ignored. 0.2.58 fixes all four (below). With 0.2.58, dictation typed correctly into Claude Code (foot) and into a Chromium web app on the phone. Phase 2 is built and tested offline in 0.2.59 (below) and has not been run on the phone yet. Phase 3 is design only.

Design (approved by the maintainer): the voice canvas, <https://claude.ai/artifact/K93k88TFaqyKvChsdk2ugK>. It has five artboards: Main (dictation strip above the keyboard), Ask (listening sheet), Confirm (check and send), FollowUp (phase 2) and Settings (phase 2). The mockups use Tokyo Night hex colours as a stand-in. The shell draws with the applied theme's tokens (`Commons.Color`, `Style`, `Border`) and the update sheet's components, and the recording colour is the theme's `urgent`.

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

- **Follow-up inside the agent (artboard FollowUp).** While an agent's terminal is in front (`org.omarchy.agent`, the one app id `omarchy-agent` gives every agent through `omarchy-launch-tui`; read from the Wayland toplevel's app id) and the keyboard is down, a round mic (60 px, the theme's popup colours, the recording colour while listening) sits at the bottom right above the home strip. Hold it to talk, or tap to start and tap again to stop. Voxtype types into the agent (`record start --no-osd --type`), adding `--smart-auto-submit` when "Say 'send' to press Enter" is on, so a prompt that ends in "send" is submitted. The mic hides over other apps and while the keyboard is up (the keyboard strip's mic key covers that case). It stays on screen during its own recording, because unmapping a surface under a held finger would lose the release.
- **Voice settings (artboard Settings).** Opened from a long press on the Dictation tile, from Omarchy's Setup > Voice (added to the menu extension by `omamobile-setup-user`), or with `omarchy-shell shell summon omamobile.voice '{"page":"settings"}'`. The sheet has:
  - the local-only notice;
  - the speech model: Fast tiny.en 75 MB, Balanced base.en 142 MB, or Accurate small.en 466 MB. A model that isn't downloaded yet downloads through Voxtype itself (`voxtype setup --download --model X --no-post-install --progress-format json`, progress on the row). The switch is `voxtype config set whisper.model X` followed by `systemctl --user try-restart voxtype.service`;
  - the triggers: hold the home pill, the mic key under the keyboard, the mic over agents, and Power + Volume Up (off by default);
  - "Say 'send' to press Enter" (on);
  - "Ask before sending to an agent" (on; when off, the transcript goes straight to the agent).

  The settings are stored in `~/.config/omamobile/voice.json`, beside quicksettings.json and home.json. The search pill's mic always works, so voice can't be switched off by accident.
- **Power + Volume Up push-to-talk** (`omamobile-keys`). Hold Power, then Volume Up, or the other way round: it dictates into the app in front, or opens the agent sheet on the home screen. Letting go stops it. The volume doesn't change, and Power's own gesture is skipped for that press, as with the screenshot chord. It is off unless `powerVolumeUp` is true in voice.json, and it never runs on the lock screen. A new Volume Up release bind ends it; every other release does nothing. Hyprland drops a key's release bind once another key goes down after it, so Power's release ends it too.
- **Haptic ticks** at the start and end of listening, through feedbackd (`fbcli -E button-pressed`, the same event the OWL widgets use), so the user's feedback profile (silent, quiet) decides. Nothing happens without fbcli.

## Phase 3

- **Live partial text** once the 7 Pro has CPU frequency scaling, which it lacks today: Voxtype's streaming engines, or a faster Whisper model on a faster CPU.
- **A Talk key inside squeekboard.** A keysym bound in Hyprland would be the most natural trigger. squeekboard's text layouts are its own, one per language (see the hide key's history in omamobile.keyboard), so for now the key lives in the strip.
- **Power + Volume Up on the lock screen**, for example to ask the agent hands-free. It needs its own design for what may run while locked.

## Risks

- **wtype vs squeekboard:** both register a zwp virtual keyboard with their own keymap. Text typed while the keyboard is up may come out with the wrong keymap, or upset squeekboard's. Test with the keyboard visible (check 6). The fallback is `--clipboard` followed by a paste.
- **Agents run with auto permissions** (`claude --permission-mode auto`, and the same for the others). A misheard prompt is acted on without another question, so the check-and-send step always shows, and the setting to skip it (phase 2) defaults to asking.
- **Layer order:** the listening strip and squeekboard are both top-layer surfaces that reserve space. If squeekboard maps after the strip, the strip can end up under the keyboard rather than above it. It still works there, but it is not where the design puts it.
- **No CPU frequency scaling:** a long recording takes a while to transcribe on base.en (about 0.9 s per second of speech), which is why setup switches the daemon to tiny.en once it's downloaded.
