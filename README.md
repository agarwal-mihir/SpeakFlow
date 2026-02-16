# SpeakFlow Local (macOS)

Local-first Wispr Flow style dictation app for macOS with:
- Desktop window UI (Dashboard + History)
- Full navigation pages: Home, History, Dictionary, Snippets, Style, Notes, Settings, Permissions
- Dock app + menu bar app running together
- Close window to keep dictation running in background
- Quit only with `Cmd+Q`
- Global hold-to-talk (`Fn` or fallback `Fn+Space`)
- English and Hinglish (Roman) output
- Optional LM Studio cleanup via local OpenAI-compatible endpoint
- Optional Groq cleanup via OpenAI-compatible API
- Auto paste into focused chat box with clipboard restore
- Automatic speaker-bleed reduction by ducking system output volume while dictating
- Floating recording indicator with live level meter
- Global fallback paste shortcut `Option+Cmd+V` (while service is running)

## Requirements

- macOS (Apple Silicon recommended)
- Python 3.9+
- LM Studio (optional)
- Groq API key (optional)

## Build Native App

```bash
cd /path/to/SpeakFlow
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -e '.[dev,app]'
bash scripts/build_app.sh
open /Applications/SpeakFlow.app
```

App bundle path:
`/Applications/SpeakFlow.app`

If you prefer user-local install instead:
`APP_INSTALL_DIR="$HOME/Applications" bash scripts/build_app.sh`

## Build DMG Installer

Create a drag-and-drop installer DMG:

```bash
cd /path/to/SpeakFlow
bash scripts/build_dmg.sh
```

Notes:
- `build_dmg.sh` only packages an existing `.app` bundle. It does not build/install the app.
- It picks `SpeakFlow.app` from `/Applications`, `~/Applications`, or `dist/` (in that order).
- You can override with `APP_BUNDLE=/absolute/path/to/SpeakFlow.app`.

Output pattern:
`~/Desktop/SpeakFlow-<version>.dmg`

Set a custom output directory:
`OUTPUT_DIR=/absolute/path bash scripts/build_dmg.sh`

## Runtime Behavior

- On launch, SpeakFlow opens a desktop window.
- Closing the window hides it and keeps background dictation alive.
- Reopen from Dock click or menu bar item `Open SpeakFlow`.
- Use `Cmd+Q` to fully quit.
- During dictation, a draggable floating indicator appears near the bottom of the screen.
- Indicator behavior:
  - Recording: live mic level meter
  - Transcribing: flatline meter + transcribing state
  - Success/Error: short status flash then auto-hide (default 1s)

## Permission Onboarding

On first launch, a guided setup window asks for:
- Microphone
- Accessibility
- Input Monitoring
- Automation (System Events)

The app blocks dictation until all required permissions are granted.
For Input Monitoring, macOS requires manual toggle in System Settings.

If automatic paste fails:
- The latest dictation is intentionally left in clipboard (default behavior).
- You can immediately press `Cmd+V` in your target app.
- You can also press `Option+Cmd+V` to re-paste the most recent dictation while service is on.

## Data Storage

Successful dictations are stored in:
`~/Library/Application Support/SpeakFlow/history.sqlite3`

UI content pages are stored in:
`~/Library/Application Support/SpeakFlow/content.sqlite3`

History supports:
- Search
- Copy selected transcript
- Delete selected transcript
- Quick stats (count/latest/top app)

Dictionary, Snippets, Style, and Notes support:
- Create
- Edit
- Delete
- Local-only persistence

## Config

Config file:
`~/Library/Application Support/SpeakFlow/config.json`

Important keys:
- `hotkey_mode`: `fn_hold` or `fn_space_hold`
- `language_mode`: `auto`, `english`, `hinglish_roman`
- `lmstudio_enabled`: `true`/`false`
- `cleanup_provider`: `lmstudio`, `groq`, `deterministic`
- `lmstudio_auto_start`: `true`/`false` (auto-launch LM Studio if it is closed)
- `lmstudio_start_timeout_ms`: wait budget for LM Studio to come online (default `8000`)
- `groq_base_url`: default `https://api.groq.com/openai/v1`
- `groq_model`: default `meta-llama/llama-4-maverick-17b-128e-instruct`
- `duck_system_audio_while_recording`: `true`/`false`
- `duck_target_volume_percent`: `0..100` (default `8`)
- `close_behavior`: `hide_to_background`
- `login_window_behavior`: `open`
- `floating_indicator_enabled`: `true`/`false`
- `floating_indicator_hide_delay_ms`: `200..10000` (default `1000`)
- `floating_indicator_origin_x`: float or null
- `floating_indicator_origin_y`: float or null
- `paste_last_shortcut_enabled`: `true`/`false`
- `paste_failure_keep_dictation_in_clipboard`: `true`/`false`
- `ui_last_tab`: last selected page
- `ui_density`: `comfortable` or `compact`
- `ui_show_welcome_card`: `true`/`false`

Groq key storage:
- Set from `Settings -> Set Groq API Key`.
- Key is stored in macOS Keychain service `com.speakflow.desktop` (account `groq_api_key`).
- Env var `GROQ_API_KEY` is also supported and takes precedence.

## Launch on Login

```bash
bash /path/to/SpeakFlow/scripts/install_launch_agent.sh
```

Remove launch-on-login:

```bash
bash /path/to/SpeakFlow/scripts/uninstall_launch_agent.sh
```

## Tests

```bash
cd /path/to/SpeakFlow
python3 -m pytest
```
