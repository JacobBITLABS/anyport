# AnyPort (SSHPortBar)

A native macOS menu bar app for managing the hosts in your `~/.ssh/config`: connect to machines in one click via Terminal, iTerm, or VS Code Remote-SSH, set ad-hoc ports on the fly, and organize hosts into draggable groups.

## Features

- **Menu bar popover** listing every host in `~/.ssh/config`, with inline search
- **One-click connect** — Terminal, iTerm (if installed), or VS Code Remote-SSH, shown with each app's real icon
- **Groups** — create, rename, collapse, and delete groups inline; drag hosts into groups or out again
- **Fully mixed drag & drop** — rows and groups are peers in one free-order list; drop a host between two groups, park a group above any row, reorder inside groups; every drop lands exactly where you let go
- **Pinning** — pinned hosts float above the stream
- **Adaptive port mode** — per-host setting to prompt for a port every time you connect (the prompt's field is focused; Return connects)
- **Edits write back** to `~/.ssh/config` (HostName, User, Identity File, Port), keeping a `config.bak` backup
- **Spotlight integration** — every host is indexed with CoreSpotlight; search its name in macOS Spotlight (⌘Space) and hit Enter to connect
- **Liquid Glass design** — glass surfaces, hover clusters, and toasts throughout

## Requirements

- macOS 26.0+
- Xcode (or Command Line Tools) with the macOS SDK
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iTerm2 (optional, for the iTerm connect target)
- VS Code with the `code` CLI (optional, for the VS Code connect target)

## Install (prebuilt)

Grab `AnyPort-<version>.dmg` from [Releases](https://github.com/JacobBITLABS/anyport/releases), open it, and drag **SSHPortBar** into Applications.

The app is ad-hoc signed (no Apple Developer ID), so the first launch needs one extra step:

```sh
xattr -cr /Applications/SSHPortBar.app
```

…or right-click the app → **Open** → **Open** once.

## Build from source

```sh
xcodegen generate
xcodebuild -project SSHPortBar.xcodeproj -scheme SSHPortBar -configuration Release -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/SSHPortBar-*/Build/Products/Release/SSHPortBar.app
```

Or open `SSHPortBar.xcodeproj` in Xcode and press ⌘R.

## Usage

1. Click the terminal glyph in the menu bar
2. Search or scroll to a host — hover for the action cluster: pin, Terminal, iTerm, VS Code
3. Click a row to open the editor (HostName, User, Identity File, Port, port mode, VS Code remote path)
4. Drag rows and groups anywhere to rearrange; drop onto a group header to join at the top

## Configuration

- All order/group state lives in `UserDefaults` under `com.jacobnielsen.SSHPortBar`
- Host fields live directly in `~/.ssh/config` (with `config.bak` beside it)
