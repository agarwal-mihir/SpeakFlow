# SpeakFlow (Swift Native)

SpeakFlow is a local-first macOS dictation app built in Swift (SwiftUI + AppKit bridges).

## Current V1 Scope

- Dictation-first workflow: record -> transcribe -> cleanup -> insert
- Global hold-to-talk: `Fn` or `Fn+Space`
- Global paste-last fallback: `Option+Cmd+V`
- Floating recording indicator (recording/transcribing/done/error)
- Permissions folded into the dictation page
- Desktop UI pages: Dictation, Models
- Recent dictation list with copy action
- Background service on window close, quit on `Cmd+Q`
- Cleanup chain: `Groq -> LM Studio -> deterministic fallback`
- Local STT: WhisperKit/Core ML with selectable model and Auto/CPU/GPU compute
- NVIDIA Parakeet model choices aligned with OpenWhispr, invoked through a local MLX runner executable when installed

## Requirements

- macOS (Apple Silicon recommended)
- Full Xcode (recommended)
- LM Studio (optional)
- Groq API key (optional)

## Project Layout

- Swift package: `/Users/mihiragarwal/Desktop/SpeakFlow/swift/SpeakFlow`
- App source: `/Users/mihiragarwal/Desktop/SpeakFlow/swift/SpeakFlow/Sources`
- Tests: `/Users/mihiragarwal/Desktop/SpeakFlow/swift/SpeakFlow/Tests`

## Build App

```bash
cd /Users/mihiragarwal/Desktop/SpeakFlow
bash scripts/build_swift_app.sh
```

Installs to:
`/Applications/SpeakFlow.app`

## Build DMG

```bash
cd /Users/mihiragarwal/Desktop/SpeakFlow
bash scripts/build_swift_dmg.sh
```

Output:
`~/Desktop/SpeakFlow-1.0.0.dmg`

## Notarize DMG

```bash
cd /Users/mihiragarwal/Desktop/SpeakFlow
APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... \
  bash scripts/notarize_swift_dmg.sh /absolute/path/to/SpeakFlow-1.0.0.dmg
```

## Dev/Test Workflow

Run tests:

```bash
cd /Users/mihiragarwal/Desktop/SpeakFlow/swift/SpeakFlow
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox -c debug
```

Open in Xcode:

```bash
cd /Users/mihiragarwal/Desktop/SpeakFlow/swift/SpeakFlow
xcodegen generate
open /Users/mihiragarwal/Desktop/SpeakFlow/swift/SpeakFlow/SpeakFlow.xcodeproj
```

## Runtime Behavior

- Launch opens desktop window + status bar item.
- Closing window hides app to background; dictation stays active.
- `Cmd+Q` fully quits.
- If auto-paste fails and fallback is enabled, last dictation stays in clipboard.
- The Models page selects the speech engine, model, compute device, and cleanup chain.

## NVIDIA Parakeet MLX Runner

SpeakFlow can use NVIDIA Parakeet through an external local runner named `speakflow-parakeet-mlx`. The app searches these locations:

- `SPEAKFLOW_PARAKEET_MLX_RUNNER`
- `/opt/homebrew/bin/speakflow-parakeet-mlx`
- `/usr/local/bin/speakflow-parakeet-mlx`
- `~/.local/bin/speakflow-parakeet-mlx`

Runner invocation contract:

```bash
speakflow-parakeet-mlx --audio /path/to/audio.wav --model parakeet-tdt-0.6b-v3 --device auto --format json
```

The audio file is mono 16 kHz PCM WAV. The runner should print JSON like:

```json
{"text":"transcribed text","language":"en","confidence":0.91}
```

Plain stdout text is accepted as a fallback. CPU/GPU selections are passed as `--device cpu|gpu|auto`, and `MLX_DEVICE` is set for explicit CPU/GPU choices.

## Permissions Required

- Microphone: required for recording
- Input Monitoring: required for the global hold-to-talk hotkey
- Accessibility: optional, enables automatic paste; without it, dictation stays in the clipboard for manual paste

## Data Paths

- Config: `~/Library/Application Support/SpeakFlow/config.json`
- History DB: `~/Library/Application Support/SpeakFlow/history.sqlite3`
- Logs: `~/Library/Logs/SpeakFlow/app.log`

## Keychain

- Service: `com.speakflow.desktop`
- Account: `groq_api_key`

## Launch at Login

Install launch agent:

```bash
bash /Users/mihiragarwal/Desktop/SpeakFlow/scripts/install_launch_agent.sh
```

Uninstall launch agent:

```bash
bash /Users/mihiragarwal/Desktop/SpeakFlow/scripts/uninstall_launch_agent.sh
```
