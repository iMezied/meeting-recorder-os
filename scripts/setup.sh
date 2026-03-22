#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

MODELS_DIR="$HOME/Library/Application Support/MeetingRecorder/models"

echo ""
echo "============================================"
echo "  Meeting Recorder — Setup"
echo "============================================"
echo ""

# ----------------------------------------------------------
# 1. Check for Homebrew
# ----------------------------------------------------------
echo -n "Checking Homebrew... "
if command -v brew &>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}Not found${NC}"
    echo "Install Homebrew first: https://brew.sh"
    exit 1
fi

# ----------------------------------------------------------
# 2. Install whisper.cpp
# ----------------------------------------------------------
echo -n "Checking whisper-cpp... "
if command -v whisper-cli &>/dev/null || [ -f /opt/homebrew/bin/whisper-cli ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}Installing...${NC}"
    brew install whisper-cpp
    echo -e "${GREEN}Installed${NC}"
fi

# ----------------------------------------------------------
# 3. Install BlackHole (virtual audio driver)
# ----------------------------------------------------------
echo -n "Checking BlackHole... "
if [ -d "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" ] || [ -d "/Library/Audio/Plug-Ins/HAL/BlackHole.driver" ]; then
    echo -e "${GREEN}OK (already installed)${NC}"
else
    echo -e "${YELLOW}Not found${NC}"
    echo ""
    echo -e "${YELLOW}BlackHole is needed to capture meeting audio (what others say).${NC}"
    echo "Without it, only your microphone will be recorded."
    echo ""
    echo "The Homebrew cask is currently broken. Choose an install method:"
    echo ""
    echo "  [1] Build from source (recommended, no email required)"
    echo "  [2] Download from website (requires email signup)"
    echo "  [3] Skip for now (mic-only recording)"
    echo ""
    read -p "Choose [1/2/3]: " -n 1 -r
    echo

    case $REPLY in
        1)
            echo "Building BlackHole from source..."
            BH_TMPDIR=$(mktemp -d)
            git clone https://github.com/ExistentialAudio/BlackHole.git "$BH_TMPDIR/BlackHole"
            cd "$BH_TMPDIR/BlackHole"
            xcodebuild \
                -project BlackHole.xcodeproj \
                -configuration Release \
                CODE_SIGN_IDENTITY="-" \
                CODE_SIGNING_REQUIRED=NO \
                CODE_SIGNING_ALLOWED=NO \
                MACOSX_DEPLOYMENT_TARGET=10.13 \
                GCC_PREPROCESSOR_DEFINITIONS="\$GCC_PREPROCESSOR_DEFINITIONS kNumber_Of_Channels=2 kDriver_Name=\\\"BlackHole2ch\\\" kPlugIn_BundleID=\\\"audio.existential.BlackHole2ch\\\"" \
                2>&1 | tail -5

            DRIVER_PATH=$(find "$BH_TMPDIR/BlackHole/build" -name "*.driver" -type d 2>/dev/null | head -1)
            if [ -n "$DRIVER_PATH" ]; then
                sudo cp -R "$DRIVER_PATH" /Library/Audio/Plug-Ins/HAL/
                sudo killall coreaudiod 2>/dev/null || true
                echo -e "${GREEN}BlackHole installed successfully!${NC}"
            else
                echo -e "${RED}Build failed. Try option 2 instead.${NC}"
            fi
            cd - > /dev/null
            rm -rf "$BH_TMPDIR"
            ;;
        2)
            echo ""
            echo "Go to: https://existential.audio/blackhole/"
            echo "Enter your email -> download the .pkg -> install it."
            echo ""
            read -p "Press Enter after you've installed BlackHole..." -r
            ;;
        3)
            echo -e "${YELLOW}Skipping BlackHole. You can install it later.${NC}"
            echo "The app will record from your microphone only."
            ;;
    esac

    if [ -d "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" ] || [ -d "/Library/Audio/Plug-Ins/HAL/BlackHole.driver" ]; then
        echo ""
        echo -e "${YELLOW}IMPORTANT: Set up audio routing in Audio MIDI Setup:${NC}"
        echo "  1. Open 'Audio MIDI Setup' (Spotlight -> Audio MIDI Setup)"
        echo "  2. Click '+' -> Create Multi-Output Device"
        echo "     - Check: BlackHole 2ch + your speakers/AirPods"
        echo "  3. Click '+' -> Create Aggregate Device"
        echo "     - Check: BlackHole 2ch + your microphone"
        echo "  4. In Meeting Recorder Settings -> Audio, select the Aggregate Device"
        echo ""
    fi
fi

# ----------------------------------------------------------
# 4. Download Whisper models
# ----------------------------------------------------------
echo ""
echo "Downloading Whisper models..."
mkdir -p "$MODELS_DIR"

download_model() {
    local size=$1
    local filename="ggml-${size}.bin"
    local filepath="$MODELS_DIR/$filename"

    if [ -f "$filepath" ]; then
        echo -e "  ${GREEN}✓${NC} $filename (already exists)"
        return
    fi

    echo -n "  Downloading $filename... "
    local url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${filename}"
    if curl -L --progress-bar -o "$filepath" "$url"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
        rm -f "$filepath"
    fi
}

download_model "base"

echo ""
read -p "Download 'small' model (466 MB, better accuracy)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    download_model "small"
fi

read -p "Download 'large-v3' model (3.1 GB, best for Arabic)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    download_model "large-v3"
fi

# ----------------------------------------------------------
# 5. Summary
# ----------------------------------------------------------
echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "Models directory: $MODELS_DIR"
echo ""
echo "Available models:"
ls -lh "$MODELS_DIR"/*.bin 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'
echo ""
echo "Next steps:"
echo "  1. brew install xcodegen  (if not installed)"
echo "  2. cd MeetingRecorder && xcodegen generate"
echo "  3. open MeetingRecorder.xcodeproj"
echo "  4. In Xcode: Target -> Info -> add 'Privacy - Microphone Usage Description'"
echo "  5. Build and run (⌘R)"
echo "  6. Grant microphone permission when prompted"
echo ""
