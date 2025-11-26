#!/bin/bash
#
# install.sh - Install mise update notification
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/Bin}"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "🚀 Installing mise-update-notification..."

# Check dependencies
if ! command -v mise &>/dev/null; then
    echo "❌ mise not found. Install from https://mise.jdx.dev/"
    exit 1
fi

if ! command -v terminal-notifier &>/dev/null; then
    echo "❌ terminal-notifier not found. Run: brew install terminal-notifier"
    exit 1
fi

# Create directories
mkdir -p "$BIN_DIR"
mkdir -p "$LAUNCH_AGENTS_DIR"

# Build SwiftUI app
echo "🔨 Building MiseUpdater..."
cd "$SCRIPT_DIR/MiseUpdater"
swift build -c release
cd "$SCRIPT_DIR"

# Create app bundle
echo "📦 Creating app bundle..."
mkdir -p "$BIN_DIR/MiseUpdater.app/Contents/MacOS"
cp "$SCRIPT_DIR/MiseUpdater/.build/release/MiseUpdater" "$BIN_DIR/MiseUpdater.app/Contents/MacOS/"

cat > "$BIN_DIR/MiseUpdater.app/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MiseUpdater</string>
    <key>CFBundleIdentifier</key>
    <string>com.mise.updater</string>
    <key>CFBundleName</key>
    <string>Mise Updater</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Copy notifier script
echo "📁 Copying scripts to $BIN_DIR..."
cp "$SCRIPT_DIR/mise-update-notifier.sh" "$BIN_DIR/"
chmod +x "$BIN_DIR/mise-update-notifier.sh"

# Update plist with correct paths
echo "⚙️  Configuring launchd service..."
PLIST_FILE="$LAUNCH_AGENTS_DIR/com.mise.update-notifier.plist"
sed "s|/Users/cvalentin|$HOME|g" "$SCRIPT_DIR/com.mise.update-notifier.plist" > "$PLIST_FILE"

# Load service
echo "🔄 Loading launchd service..."
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load "$PLIST_FILE"

echo ""
echo "✅ Installation complete!"
echo ""
echo "Commands:"
echo "  $BIN_DIR/mise-update-notifier.sh  # Check for updates"
echo "  open $BIN_DIR/MiseUpdater.app     # Open updater directly"
echo ""
echo "Service status:"
launchctl list | grep mise || echo "  (not running yet)"
