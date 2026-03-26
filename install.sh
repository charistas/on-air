#!/bin/bash
set -e
cd "$(dirname "$0")"

APP_NAME="OnAir"
APP_PATH="$(pwd)/OnAir.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/OnAir"
PLIST_NAME="com.on-air.countdown"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "=== On Air — Install ==="

if ! command -v swiftc >/dev/null 2>&1; then
    echo ""
    echo "ERROR: swiftc not found."
    echo "Install Xcode Command Line Tools with: xcode-select --install"
    exit 1
fi

echo "Building native app…"
rm -rf "$APP_PATH" build dist
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$PLIST_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>On Air</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>On Air needs calendar access to show meeting countdowns.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>On Air needs calendar access to show meeting countdowns before they begin.</string>
</dict>
</plist>
EOF

printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

swiftc -parse-as-library OnAir.swift \
    -framework AppKit \
    -framework AVFoundation \
    -framework EventKit \
    -framework UserNotifications \
    -o "$APP_EXECUTABLE"

chmod +x "$APP_EXECUTABLE"
plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null

# Check for audio file
if [ ! -f "countdown.mp3" ]; then
    echo ""
    echo "WARNING: No countdown.mp3 found."
    echo "Place your countdown audio file at: $(pwd)/countdown.mp3"
    echo ""
else
    cp "countdown.mp3" "$APP_PATH/Contents/Resources/countdown.mp3"
fi

codesign -f -s - "$APP_PATH" 2>&1 || echo "WARNING: ad-hoc codesign failed (non-fatal)"

# Clean up any old LaunchAgent-based installs before switching to a Login Item.
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
rm -f "$LAUNCH_AGENT_PATH"

# Add to Login Items (removes existing entry first to avoid duplicates)
osascript -e "
    tell application \"System Events\"
        try
            delete login item \"$APP_NAME\"
        end try
        make login item at end with properties {path:\"$APP_PATH\", hidden:true}
    end tell
" >/dev/null 2>/dev/null

# Stop any existing On Air instance before launching the rebuilt app bundle.
osascript -e "tell application id \"$PLIST_NAME\" to quit" >/dev/null 2>/dev/null || true
pkill -f "$APP_EXECUTABLE" 2>/dev/null || true

# Launch now
open "$APP_PATH"

echo ""
echo "On Air installed and running."
echo "It will start automatically on login."
echo ""
echo "Make sure your work calendar is synced:"
echo "  System Settings → Internet Accounts"
echo ""
echo "If prompted for Calendar access by On Air — click Allow."
echo "If you previously denied access, run: tccutil reset Calendar com.on-air.countdown"
echo "To uninstall: bash uninstall.sh"
