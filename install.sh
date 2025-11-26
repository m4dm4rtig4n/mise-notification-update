#!/bin/bash
#
# install.sh - Install mise update notification scripts
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

if [[ ! -x /usr/local/bin/dialog ]]; then
    echo "⚠️  SwiftDialog not found. Install from:"
    echo "   https://github.com/swiftDialog/swiftDialog/releases"
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Create directories
mkdir -p "$BIN_DIR"
mkdir -p "$LAUNCH_AGENTS_DIR"

# Copy scripts
echo "📁 Copying scripts to $BIN_DIR..."
cp "$SCRIPT_DIR/mise-update-notifier.sh" "$BIN_DIR/"
cp "$SCRIPT_DIR/mise-update-dialog.sh" "$BIN_DIR/"
chmod +x "$BIN_DIR/mise-update-notifier.sh"
chmod +x "$BIN_DIR/mise-update-dialog.sh"

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
echo "  $BIN_DIR/mise-update-dialog.sh    # Open update dialog"
echo ""
echo "Service status:"
launchctl list | grep mise || echo "  (not running yet)"
