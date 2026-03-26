#!/bin/bash
set -e

APP_NAME="OnAir"
APP_PATH="$(cd "$(dirname "$0")" && pwd)/OnAir.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/OnAir"
PLIST_NAME="com.on-air.countdown"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

# Remove from Login Items
osascript -e "
    tell application \"System Events\"
        try
            delete login item \"$APP_NAME\"
        end try
    end tell
" >/dev/null 2>/dev/null || true

# Remove any older LaunchAgent install and stop the app bundle instance.
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
rm -f "$LAUNCH_AGENT_PATH"
osascript -e "tell application id \"$PLIST_NAME\" to quit" >/dev/null 2>/dev/null || true
pkill -f "$APP_EXECUTABLE" 2>/dev/null || true

echo "On Air stopped and removed from login items."
