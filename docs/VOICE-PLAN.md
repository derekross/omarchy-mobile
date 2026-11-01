# Voice input plan

Status: 2026-10-31. Phase 1 is built and tested offline in omamobile-shell 0.2.57 (branch `shell-voice`): the model and argv tests, the pill and mic key under touch (qmltestrunner) and the offscreen review shots pass. Nobody has run it on the phone yet; the [phone checks](#phase-1-checks-on-the-phone) below are still open. Phase 2 is design only.

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
| Pure parts | `plugins/omamobile.voice/VoiceModel.js` | argv builders (`--no-osd` always, `--model tiny.en` when it is downloaded), the phase machine (`idle → starting → listening → transcribing → review/error`), push-to-talk, the clock, the meter, the copy/type commands (text on stdin) |
| Link | `plugins/omamobile.voice/VoiceLink.js`, `VoiceLinkClient.qml` | A `.pragma library` script shared by the shell's one QML engine, as with DrawerLink.js. A long press and its release reach the service without starting a process, and the launcher falls back to the plugin's IPC when the service isn't loaded |
| Triggers | `plugins/omamobile.launcher/Launcher.qml` | Long press (0.5 s) on the dock's search pill or on the home strip: `askPress`, then `askRelease` when the finger lifts. The strip's mic key (left end, only while the keyboard is up): hold to talk (0.3 s), tap to toggle |
| Dictation tile | `plugins/omamobile.quicksettings/tile-action.sh` | `voxtype record start --no-osd --type [--model tiny.en]`; the listening strip shows for it, because the strip shows for any recording the sheet didn't start |
| Agent | `LauncherModel.promptArgv(text)` | `omamobile-launch cmd -- omarchy-agent-prompt "<text>"` (one argv element, no shell), then `omarchy-agent --prompt`, which starts the agent in a terminal. The chip shows the agent's name from `~/.config/omarchy/defaults/agent` (`LauncherModel.agentName`: Claude Code, Codex, OpenCode, and so on); tapping it opens `omarchy menu summon setup.default.agent` |

**Ask flow:** hold the pill. The sheet opens and runs `voxtype record start --no-osd --file=$XDG_RUNTIME_DIR/omamobile-voice.txt` (removing the old transcript first, in the same process). When the finger lifts, `record stop` runs. A press shorter than 0.7 s after listening starts keeps listening until you tap Stop. The phase goes from transcribing to idle, and the sheet reads the file. A transcript opens the check-and-send page; an empty one shows "Didn't catch that" with Say again. On the check-and-send page the transcript is editable (normal exclusion, so the field stays above the keyboard) and you have Send to <agent>, Say again, Cancel, Copy (`wl-copy`) and Type into last app (`wtype -`, half a second after the sheet closes, when the app has the keyboard focus again). Closing the sheet while it listens runs `record cancel`.

**Dictation flow:** the mic key or the tile runs `--type`, and Voxtype types into the focused app. The listening strip sits on the top layer with its own exclusive zone, so the app's field ends above it, and it never takes the keyboard focus. It shows "Listening", the time ("stops at 1:00" for the last 10 s), the level, Cancel and "Done · type it".

## Phase 1 checks on the phone

Read-only first; each step needs only the shell. Announce before starting, because the microphone opens and text gets typed.

1. `pacman -Q omamobile-shell` reads 0.2.57, and `omarchy-shell shell call omamobile.voice snapshot ''` answers with `"phase":"idle"` and `"fast":true` (tiny.en present).
2. On the home screen, hold the dock's search pill. The sheet opens listening; speak and let go. Expect "Transcribing" for about 2-4 s, then the check-and-send page with the text. No Voxtype overlay appears.
3. Over an app, hold the strip's pill: the same flow. A short press then release keeps listening until Stop. Cancel closes the sheet and `snapshot` returns to idle.
4. On the check-and-send page, tap the text: the keyboard comes up and the field stays above it. Edit it, then Send: a terminal opens with the agent and the prompt. Tap the chip: Omarchy's agent picker opens.
5. Copy, then paste somewhere. Type into last app types into the app that was open.
6. Open a text field (Messages) so the keyboard is up. Tap the mic key at the strip's left end, speak, then tap Done: the text is typed into the field. Hold the mic key, speak, let go: the same. **Risk:** wtype and squeekboard both use a virtual-keyboard keymap; check that typing works with the keyboard visible, and that squeekboard's keys still work afterwards.
7. Quick settings > Dictation: the listening strip shows, and Voxtype's overlay doesn't.
8. Leave the phone listening for over 60 s: the strip and sheet show "stops at 1:00", Voxtype stops itself, and the screen stays on throughout.

Stop condition: anything typed into the wrong window, squeekboard stops responding, or the shell restarts. Rollback: `voxtype record cancel`, then reinstall omamobile-shell 0.2.56.

## Phase 2 (follow-up)

- **Follow-up inside the agent (artboard FollowUp):** a mic in the agent's terminal that types as you speak and submits on "send" (`--type --smart-auto-submit`), with "hold to talk" under the prompt.
- **Voice settings sheet (artboard Settings):** the speech model (Fast tiny.en / Balanced base.en / Accurate small.en, with download through `omarchy-voxtype-model`), the triggers (hold the home pill, the mic key, Power + Volume Up), "Say 'send' to press Enter", and "Ask before sending to an agent" (on by default).
- **Power + Volume Up push-to-talk** in `omamobile-keys`, with a release handler (it works with the screen locked; what that may do from the lock needs its own design).
- **Haptic ticks** at start and stop (CS40L26).
- **Live partial text** once the 7 Pro has CPU frequency scaling, which it lacks today: Voxtype's streaming engines, or a faster Whisper model.
- **A mic key inside squeekboard's layouts**: a keysym bound in Hyprland would be the most natural trigger, but the text layouts are squeekboard's own, one per language (the hide key's history in omamobile.keyboard), so the key lives in the strip for now.

## Risks

- **wtype vs squeekboard:** both register a zwp virtual keyboard with their own keymap. Text typed while the keyboard is up may come out with the wrong keymap, or upset squeekboard's. Test with the keyboard visible (check 6). The fallback is `--clipboard` followed by a paste.
- **Agents run with auto permissions** (`claude --permission-mode auto`, and the same for the others). A misheard prompt is acted on without another question, so the check-and-send step always shows, and the setting to skip it (phase 2) defaults to asking.
- **Layer order:** the listening strip and squeekboard are both top-layer surfaces that reserve space. If squeekboard maps after the strip, the strip can end up under the keyboard rather than above it. It still works there, but it is not where the design puts it.
- **No CPU frequency scaling:** a long recording takes a while to transcribe on base.en (about 0.9 s per second of speech), which is why tiny.en is used when it's downloaded.
