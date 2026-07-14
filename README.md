# SSHPortBar

A macOS menu bar app for editing SSH host ports and connecting via iTerm2 or VS Code Remote-SSH.

## Requirements

- macOS 14.0+
- Swift toolchain (Xcode or Command Line Tools)
- iTerm2 (for "Open in iTerm" feature)
- VS Code with `code` CLI (for "Open in VS Code" feature)

## Build (no Xcode needed)

```sh
./build.sh
open build/SSHPortBar.app
```

## Build with Xcode

```sh
brew install xcodegen
xcodegen generate
open SSHPortBar.xcodeproj   # then Build & Run in Xcode
```

## Usage

1. Click the terminal icon in the menu bar
2. Select a host from your `~/.ssh/config`
3. Edit the port number
4. Click **Open in iTerm** or **Open in VS Code**

The port change is saved to `~/.ssh/config` (with a backup at `~/.ssh/config.bak`), so both iTerm and VS Code use the same port.
# anyport
