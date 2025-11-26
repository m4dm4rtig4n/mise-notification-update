# macOS Mise Update Notification

Native macOS notifications when [mise](https://mise.jdx.dev/) packages have updates available.

![Demo](./demo.png)

## Features

- **Native notifications** via `terminal-notifier`
- **Interactive dialog** with [SwiftDialog](https://github.com/swiftDialog/swiftDialog) showing available updates
- **Real-time progress** during installation
- **Smart caching** to avoid duplicate notifications
- **Automatic scheduling** via launchd (hourly + on login)

## Requirements

- macOS 12+
- [mise](https://mise.jdx.dev/) - polyglot runtime manager
- [terminal-notifier](https://github.com/julienXX/terminal-notifier) - `brew install terminal-notifier`
- [SwiftDialog](https://github.com/swiftDialog/swiftDialog) - for interactive dialogs

### Install SwiftDialog

```bash
curl -L "https://github.com/swiftDialog/swiftDialog/releases/download/v2.5.5/dialog-2.5.5-4802.pkg" -o /tmp/swiftdialog.pkg
sudo installer -pkg /tmp/swiftdialog.pkg -target /
```

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/yourusername/macos-mise-update-notification.git ~/Git/macos-mise-update-notification
```

### 2. Install scripts

```bash
# Copy scripts to ~/Bin (or your preferred location)
mkdir -p ~/Bin
cp mise-update-notifier.sh mise-update-dialog.sh ~/Bin/
chmod +x ~/Bin/mise-update-*.sh
```

### 3. Configure launchd (automatic updates check)

Edit `com.mise.update-notifier.plist` and update paths if needed, then:

```bash
# Copy the plist
cp com.mise.update-notifier.plist ~/Library/LaunchAgents/

# Load the service
launchctl load ~/Library/LaunchAgents/com.mise.update-notifier.plist
```

## Usage

### Manual check

```bash
# Check for updates and show notification
~/Bin/mise-update-notifier.sh

# Open dialog directly
~/Bin/mise-update-dialog.sh
```

### Manage the service

```bash
# Check status
launchctl list | grep mise

# Stop the service
launchctl unload ~/Library/LaunchAgents/com.mise.update-notifier.plist

# Start the service
launchctl load ~/Library/LaunchAgents/com.mise.update-notifier.plist

# View logs
tail -f ~/.cache/mise-notifier.log
```

## Configuration

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MISE_BIN` | `~/.local/bin/mise` | Path to mise binary |
| `CACHE_FILE` | `~/.cache/mise-notifier-last` | Cache file for dedup |
| `DIALOG_SCRIPT` | `~/Bin/mise-update-dialog.sh` | Path to dialog script |

### launchd schedule

Default: runs at login + every hour. Edit `StartInterval` in the plist:

```xml
<key>StartInterval</key>
<integer>3600</integer>  <!-- seconds (3600 = 1 hour) -->
```

## How it works

```
┌─────────────────────┐
│  launchd (hourly)   │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐     no updates     ┌─────────────────┐
│ mise-update-notifier│ ─────────────────▶ │   (silent)      │
└──────────┬──────────┘                    └─────────────────┘
           │ updates found
           ▼
┌─────────────────────┐
│    Notification     │
│  "🔄 3 updates"     │
└──────────┬──────────┘
           │ click
           ▼
┌─────────────────────┐
│ mise-update-dialog  │
│  ┌───────────────┐  │
│  │ 🚀 Updates    │  │
│  │ • node 20→21  │  │
│  │ • go 1.21→22  │  │
│  │ [Install]     │  │
│  └───────────────┘  │
└──────────┬──────────┘
           │ confirm
           ▼
┌─────────────────────┐
│   mise upgrade      │
│   (with progress)   │
└─────────────────────┘
```

## Files

| File | Description |
|------|-------------|
| `mise-update-notifier.sh` | Main script, sends notification if updates available |
| `mise-update-dialog.sh` | Interactive SwiftDialog for viewing/installing updates |
| `com.mise.update-notifier.plist` | launchd service definition |

## License

MIT
