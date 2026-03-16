#!/bin/bash

# App Store Screenshot Automation Script
#
# Captures 4 screenshots on the specified iOS simulator.
# Run once for iPhone, once for iPad.
#
# Usage:
#   ./scripts/take_screenshots.sh "iPhone 16 Pro Max"
#   ./scripts/take_screenshots.sh "iPad Pro 13-inch (M4)"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_DEVICE="iPhone 16 Pro Max"
DEVICE="${1:-$DEFAULT_DEVICE}"
SCREENSHOTS_DIR="$PROJECT_DIR/fastlane/screenshots/en-US"
SIGNAL_DIR="/tmp/screenshot_signals"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== App Store Screenshot Automation ===${NC}"
echo -e "${BLUE}Device:${NC} $DEVICE"
echo ""

mkdir -p "$SCREENSHOTS_DIR"

# Clean up any stale signals
rm -rf "$SIGNAL_DIR"

# Find simulator
UDID=$(xcrun simctl list devices available | grep "$DEVICE" | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')

if [ -z "$UDID" ]; then
    echo "Error: Could not find simulator '$DEVICE'"
    echo "Available devices:"
    xcrun simctl list devices available | grep -E "iPhone|iPad"
    exit 1
fi

echo "Simulator: $UDID"

# Boot if needed
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$UDID"
sleep 2

cd "$PROJECT_DIR"

# Function to wait for signal file and take screenshot
wait_and_capture() {
    local screen_num=$1
    local output_file=$2
    local signal_file="$SIGNAL_DIR/ready_$screen_num"

    echo -e "${YELLOW}Waiting for screen $screen_num...${NC}"

    # Wait up to 120 seconds for signal
    for i in $(seq 1 1200); do
        if [ -f "$signal_file" ]; then
            echo -e "${GREEN}Screen $screen_num ready${NC}"
            sleep 0.3  # Brief pause for UI to fully render
            xcrun simctl io "$UDID" screenshot "$output_file"
            rm -f "$signal_file"  # Signal that we captured it
            echo "Saved: $output_file"
            return 0
        fi
        sleep 0.1
    done

    echo -e "${YELLOW}Timeout waiting for screen $screen_num${NC}"
    return 1
}

# Determine device type for filename prefix
if [[ "$DEVICE" == *"iPad"* ]]; then
    PREFIX="ipad"
else
    PREFIX="iphone"
fi

# Run flutter in background
echo -e "${YELLOW}Building and launching app...${NC}"
flutter run --target=lib/screenshot_main.dart -d "$UDID" --no-hot 2>&1 &
FLUTTER_PID=$!

# Wait for each screenshot with signal coordination
wait_and_capture 1 "$SCREENSHOTS_DIR/${PREFIX}_01_connections.png"
wait_and_capture 2 "$SCREENSHOTS_DIR/${PREFIX}_02_terminal_claude.png"
wait_and_capture 3 "$SCREENSHOTS_DIR/${PREFIX}_03_terminal_server.png"
wait_and_capture 4 "$SCREENSHOTS_DIR/${PREFIX}_04_sessions.png"

# Cleanup
kill $FLUTTER_PID 2>/dev/null || true
pkill -f "flutter run" 2>/dev/null || true
rm -rf "$SIGNAL_DIR"

echo ""
echo -e "${GREEN}=== Screenshots Complete ===${NC}"
ls -la "$SCREENSHOTS_DIR"/${PREFIX}_*.png
