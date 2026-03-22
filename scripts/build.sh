#!/bin/bash
set -euo pipefail

# Build Meeting Recorder from the command line (no Xcode GUI needed)
# Usage: ./scripts/build.sh [run]

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Generate xcodeproj if missing
if [ ! -d "MeetingRecorder.xcodeproj" ]; then
    echo "Generating Xcode project..."
    if ! command -v xcodegen &>/dev/null; then
        echo "Installing xcodegen..."
        brew install xcodegen
    fi
    xcodegen generate
fi

echo "Building Meeting Recorder..."
xcodebuild \
    -project MeetingRecorder.xcodeproj \
    -scheme MeetingRecorder \
    -configuration Debug \
    -derivedDataPath ./build \
    build 2>&1 | tail -20

APP_PATH="./build/Build/Products/Debug/Meeting Recorder.app"

if [ -d "$APP_PATH" ]; then
    echo ""
    echo "✅ Build successful: $APP_PATH"
    
    if [ "${1:-}" = "run" ]; then
        echo "Launching..."
        # Kill existing instance
        pkill -f "Meeting Recorder" 2>/dev/null || true
        sleep 0.5
        open "$APP_PATH"
    fi
else
    echo "❌ Build failed"
    exit 1
fi
