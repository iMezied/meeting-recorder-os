# Meeting Recorder — macOS

100% local meeting recording and transcription for macOS. No cloud services, no subscriptions.

## Quick Start

```bash
# 1. Install dependencies + download whisper models
chmod +x scripts/setup.sh && ./scripts/setup.sh

# 2. Generate Xcode project
brew install xcodegen
xcodegen generate

# 3. Build and run
open MeetingRecorder.xcodeproj
# Press ⌘R
```

**Important:** After opening in Xcode, go to **Target → Info** and verify these keys exist under "Custom macOS Application Target Properties":
- `Privacy - Microphone Usage Description` → "Meeting Recorder needs microphone access to record meeting audio."
- `Privacy - AppleEvents Sending Usage Description` → "Meeting Recorder needs Automation access to detect Google Meet in your browser."
- `Application is agent (UIElement)` → YES

If XcodeGen set them from Info.plist they should already be there. If not, add them manually.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+
- Apple Silicon or Intel Mac
- whisper-cpp (`brew install whisper-cpp`, provides `whisper-cli`)

## Architecture

```
SwiftUI Menu Bar App
├── AVFoundation Recording (16kHz mono WAV)
├── Process Monitor (Zoom / Teams detection)
├── AppleScript (Google Meet detection via browser tabs)
└── whisper-cli (local speech-to-text)
```

## Usage

### Menu Bar
- Click the mic icon in the menu bar for quick controls
- Red pulsing dot = recording in progress
- "Meeting Library" opens the full window
- "Settings..." opens preferences

### Auto-Detection
- Monitors for Zoom, Microsoft Teams, and Google Meet
- Recording starts/stops automatically when meetings begin/end
- Toggle with the eye icon in the toolbar

### Transcription
- Uses whisper-cli (from whisper-cpp) with the selected model
- **base** model: Fast, good for English
- **large-v3** model: Best for Arabic and mixed Arabic/English
- Language can be set to auto-detect, English, or Arabic

## Project Structure

```
MeetingRecorder/
├── App/
│   ├── MeetingRecorderApp.swift    # Entry point + AppDelegate
│   └── AppState.swift              # Central state management
├── Models/
│   └── Models.swift                # Meeting, Transcript, data types
├── Services/
│   ├── AudioRecordingService.swift # AVFoundation audio capture
│   ├── MeetingDetectorService.swift# Process monitoring + AppleScript
│   ├── TranscriptionService.swift  # whisper-cli integration
│   └── StorageService.swift        # File I/O and persistence
├── Views/
│   ├── MenuBarView.swift           # Menu bar dropdown UI
│   ├── MainWindowView.swift        # Library window with sidebar
│   ├── MeetingDetailView.swift     # Transcript viewer + details
│   └── SettingsView.swift          # App configuration
├── Utilities/
│   └── NotificationHelper.swift    # macOS notifications
└── Resources/
    ├── Info.plist                   # App metadata + permissions
    └── MeetingRecorder.entitlements # Security entitlements
```

## Data Storage

```
~/Library/Application Support/MeetingRecorder/
├── meetings.json
├── models/
│   ├── ggml-base.bin
│   └── ggml-large-v3.bin
└── recordings/
    └── 2026-03-22/
        └── zoom-0900/
            ├── audio.wav
            └── transcript.json
```

## Audio Setup (for system audio capture)

To record what others say (not just your mic):

1. Install **BlackHole** (build from source or from existential.audio)
2. Open **Audio MIDI Setup**
3. Create **Multi-Output Device** (BlackHole + speakers/AirPods)
4. Create **Aggregate Device** (BlackHole + your mic)
5. Set macOS output to Multi-Output Device
6. In Meeting Recorder Settings → Audio, select the Aggregate Device

## Roadmap

- [x] Phase 1: MVP — Menu bar, recording, whisper-cli transcription
- [ ] Phase 2: Auto-detection hardening + auto start/stop
- [ ] Phase 3: Python backend (faster-whisper, pyannote, Ollama summaries)
- [ ] Phase 4: Full UI polish, search, calendar integration

## Troubleshooting

**"whisper-cli not found"** → `brew install whisper-cpp`

**"Model not found"** → Download models:
```bash
mkdir -p ~/Library/Application\ Support/MeetingRecorder/models
curl -L -o ~/Library/Application\ Support/MeetingRecorder/models/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

**App crashes on launch** → Add `Privacy - Microphone Usage Description` in Xcode Target → Info

**Windows don't open from menu bar** → Make sure you're running the latest code with AppDelegate window management
