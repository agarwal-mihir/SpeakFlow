# SpeakFlow (Swift Native)

SpeakFlow is a local-first macOS dictation app built in Swift (SwiftUI + AppKit bridges).

## Current V1 Scope

- Dictation-first workflow: record -> transcribe -> cleanup -> insert
- Global hold-to-talk: `Fn` or `Fn+Space`
- Global paste-last fallback: `Option+Cmd+V`
- Floating recording indicator (recording/transcribing/done/error)
- Permissions onboarding + re-check
- Desktop UI pages: Home, History, Settings, Permissions
- History: search/copy/delete + stats
- Background service on window close, quit on `Cmd+Q`
- Cleanup chain: `Groq -> LM Studio -> deterministic fallback`
- Local STT: WhisperKit/CoreML

## Requirements

- macOS (Apple Silicon recommended)
- Full Xcode (recommended)
- LM Studio (optional)
- Groq API key (optional)

## Project Layout

- Swift package: `/Users/mihiragarwal/Desktop/Whisper/swift/SpeakFlow`
- App source: `/Users/mihiragarwal/Desktop/Whisper/swift/SpeakFlow/Sources`
- Tests: `/Users/mihiragarwal/Desktop/Whisper/swift/SpeakFlow/Tests`

## Build App

```bash
cd /Users/mihiragarwal/Desktop/Whisper
bash scripts/build_swift_app.sh
```

Installs to:
`/Applications/SpeakFlow.app`

## Build DMG

```bash
cd /Users/mihiragarwal/Desktop/Whisper
bash scripts/build_swift_dmg.sh
```

Output:
`~/Desktop/SpeakFlow-1.0.0.dmg`

## Notarize DMG

```bash
cd /Users/mihiragarwal/Desktop/Whisper
APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... \
  bash scripts/notarize_swift_dmg.sh /absolute/path/to/SpeakFlow-1.0.0.dmg
```

## Dev/Test Workflow

Run tests:

```bash
cd /Users/mihiragarwal/Desktop/Whisper/swift/SpeakFlow
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox -c debug
```

Open in Xcode:

```bash
cd /Users/mihiragarwal/Desktop/Whisper/swift/SpeakFlow
xcodegen generate
open /Users/mihiragarwal/Desktop/Whisper/swift/SpeakFlow/SpeakFlow.xcodeproj
```

## Runtime Behavior

- Launch opens desktop window + status bar item.
- Closing window hides app to background; dictation stays active.
- `Cmd+Q` fully quits.
- If auto-paste fails and fallback is enabled, last dictation stays in clipboard.

## Permissions Required

- Microphone
- Accessibility
- Input Monitoring
- Automation (System Events)

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
bash /Users/mihiragarwal/Desktop/Whisper/scripts/install_launch_agent.sh
```

Uninstall launch agent:

```bash
bash /Users/mihiragarwal/Desktop/Whisper/scripts/uninstall_launch_agent.sh
```
