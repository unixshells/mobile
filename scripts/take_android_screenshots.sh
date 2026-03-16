#!/bin/bash

# Android Screenshot Automation Script
#
# Captures 4 screenshots from an Android emulator by monitoring Flutter logs
# for signal messages. Uses adb screencap for capture.
#
# Usage:
#   ./scripts/take_android_screenshots.sh [emulator_avd_name]
#
# If no emulator is given, uses the first available Pixel phone emulator.
# For tablet screenshots, pass a tablet AVD name.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCREENSHOTS_DIR="$PROJECT_DIR/fastlane/screenshots/en-US"
EMULATOR_ID="${1:-}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Android Screenshot Automation ===${NC}"
echo ""

mkdir -p "$SCREENSHOTS_DIR"

# Find ADB
ADB=$(which adb 2>/dev/null || echo "")
if [ -z "$ADB" ]; then
    for dir in "$ANDROID_HOME" "$ANDROID_SDK_ROOT" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
        if [ -x "$dir/platform-tools/adb" ]; then
            ADB="$dir/platform-tools/adb"
            break
        fi
    done
fi

if [ -z "$ADB" ]; then
    echo -e "${RED}Error: adb not found. Set ANDROID_HOME or add adb to PATH.${NC}"
    exit 1
fi
echo -e "${BLUE}ADB:${NC} $ADB"

# Find emulator binary
EMULATOR_BIN=""
for dir in "$ANDROID_HOME" "$ANDROID_SDK_ROOT" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    if [ -x "$dir/emulator/emulator" ]; then
        EMULATOR_BIN="$dir/emulator/emulator"
        break
    fi
done

# If no emulator specified, pick the first Pixel phone AVD
if [ -z "$EMULATOR_ID" ]; then
    if [ -n "$EMULATOR_BIN" ]; then
        EMULATOR_ID=$("$EMULATOR_BIN" -list-avds 2>/dev/null | grep -i "pixel.*pro\|pixel_[0-9]" | grep -iv tablet | head -1)
    fi
fi

if [ -z "$EMULATOR_ID" ]; then
    echo -e "${RED}Error: No Pixel phone emulator found.${NC}"
    echo "Available emulators:"
    "$EMULATOR_BIN" -list-avds 2>/dev/null || true
    exit 1
fi

echo -e "${BLUE}Emulator:${NC} $EMULATOR_ID"

# Check if emulator is already running
DEVICE_SERIAL=$("$ADB" devices | grep "emulator-" | head -1 | awk '{print $1}')

if [ -z "$DEVICE_SERIAL" ]; then
    echo -e "${YELLOW}Starting emulator...${NC}"
    "$EMULATOR_BIN" -avd "$EMULATOR_ID" -no-audio -no-boot-anim &
    EMULATOR_PID=$!

    # Wait for device to come online
    echo -e "${YELLOW}Waiting for emulator to boot...${NC}"
    "$ADB" wait-for-device
    while [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
        sleep 1
    done
    sleep 2
    DEVICE_SERIAL=$("$ADB" devices | grep "emulator-" | head -1 | awk '{print $1}')
    echo -e "${GREEN}Emulator booted: $DEVICE_SERIAL${NC}"
else
    echo -e "${GREEN}Using running emulator: $DEVICE_SERIAL${NC}"
    EMULATOR_PID=""
fi

cd "$PROJECT_DIR"

# Determine if phone or tablet for filename prefix (retry a few times since
# wm size can return empty right after boot)
SCREEN_WIDTH=""
for i in $(seq 1 10); do
    SCREEN_WIDTH=$("$ADB" -s "$DEVICE_SERIAL" shell wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | head -1 | cut -d'x' -f1)
    if [ -n "$SCREEN_WIDTH" ]; then break; fi
    sleep 1
done
if [ -n "$SCREEN_WIDTH" ] && [ "$SCREEN_WIDTH" -gt 1600 ]; then
    PREFIX="android_tablet"
else
    PREFIX="android_phone"
fi

echo -e "${BLUE}Type:${NC} $PREFIX (width: ${SCREEN_WIDTH}px)"

# Function to capture screenshot via adb
capture_screenshot() {
    local output_file=$1
    "$ADB" -s "$DEVICE_SERIAL" exec-out screencap -p > "$output_file"
    echo -e "${GREEN}Saved: $output_file${NC}"
}

# Clear logcat before starting
"$ADB" -s "$DEVICE_SERIAL" logcat -c 2>/dev/null || true

# Run flutter in background
echo -e "${YELLOW}Building and launching app...${NC}"
flutter run --target=lib/screenshot_main.dart -d "$DEVICE_SERIAL" --no-hot 2>&1 &
FLUTTER_PID=$!

# Wait for the flutter app to start
echo -e "${YELLOW}Waiting for app to start...${NC}"
for i in $(seq 1 600); do
    if "$ADB" -s "$DEVICE_SERIAL" logcat -d 2>/dev/null | grep -q "Screenshot data setup complete"; then
        echo -e "${GREEN}App started${NC}"
        break
    fi
    sleep 0.5
done

# Monitor logcat for each screenshot signal sequentially
for screen_num in 1 2 3 4; do
    case $screen_num in
        1) FILE="${PREFIX}_01_connections.png" ;;
        2) FILE="${PREFIX}_02_terminal_claude.png" ;;
        3) FILE="${PREFIX}_03_terminal_server.png" ;;
        4) FILE="${PREFIX}_04_sessions.png" ;;
    esac

    OUTPUT="$SCREENSHOTS_DIR/$FILE"
    SIGNAL="SCREENSHOT_SIGNAL: Screen $screen_num ready"

    echo -e "${YELLOW}Waiting for screen $screen_num...${NC}"

    FOUND=0
    for i in $(seq 1 600); do
        if "$ADB" -s "$DEVICE_SERIAL" logcat -d 2>/dev/null | grep -q "$SIGNAL"; then
            echo -e "${GREEN}Screen $screen_num ready${NC}"
            sleep 0.5
            capture_screenshot "$OUTPUT"
            # Clear logcat so we don't re-match this signal
            "$ADB" -s "$DEVICE_SERIAL" logcat -c 2>/dev/null || true
            FOUND=1
            break
        fi
        sleep 0.2
    done

    if [ "$FOUND" -eq 0 ]; then
        echo -e "${RED}Timeout waiting for screen $screen_num${NC}"
    fi
done

# Cleanup
kill $FLUTTER_PID 2>/dev/null || true
pkill -f "flutter run" 2>/dev/null || true

echo ""
echo -e "${GREEN}=== Android Screenshots Complete ===${NC}"
ls -la "$SCREENSHOTS_DIR"/${PREFIX}_*.png 2>/dev/null || echo "No screenshots found"
