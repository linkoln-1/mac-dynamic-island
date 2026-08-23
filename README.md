# mac-dynamic-island

A Dynamic Island for the MacBook notch. A static borderless panel lives around
the physical notch and expands on hover into a modular workspace.

## Modules

- **Screenshot Buffer** — captures screenshots from the clipboard
  (`⌘⇧3/4` with clipboard target) and from disk, keeps the last 30, supports
  Finder-style multi-item drag-out into other apps. Originals are never deleted.
- **Now Playing** — global media card (artwork, title, controls, seek) built on
  the vendored `mediaremote-adapter` technique (Apple-signed `/usr/bin/perl`
  loads a helper framework, streams NDJSON), with an AppleScript fallback for
  Spotify / Music and a browser-tab probe fallback for Arc.
- **AI Agents** — real-time monitor of Claude Code and Codex CLI sessions via
  their hook systems (helper binary → unix socket → state machine). Cards show
  state (working / needs permission / finished / failed), activity, cycle
  duration; finished cards auto-clear after ~60 s. Per-provider tabs, manual
  Clear, native notifications on important transitions. Read-only: secrets are
  redacted in the hook helper before anything leaves the process.

## Interaction

- Rest the pointer on the island → it expands (short intent delay filters
  drive-by cursor passes). Move away → collapses after a grace period.
- Click works too; click outside collapses.
- The island never becomes the key window — your keyboard focus stays in the
  app you're typing in.
- When media plays, the island shows a compact player around the notch; agent
  activity joins as a micro-cluster.

## Requirements

- macOS 15.0+ (verified on macOS 26 "Tahoe"), Apple Silicon
  (the vendored `MediaRemoteAdapter.framework` binary is arm64-only).
- Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Build & Run

```bash
xcodegen
xcodebuild -project PersonalIsland.xcodeproj -scheme PersonalIsland \
  -configuration Debug build
open <derived-data>/Build/Products/Debug/PersonalIsland.app
```

Tests:

```bash
xcodebuild -project PersonalIsland.xcodeproj -scheme PersonalIsland test
```

The app is ad-hoc signed and runs as a menu-bar-less agent (`LSUIElement`).
Enabling the AI Agents module installs hooks into `~/.claude/settings.json`
and `~/.codex/hooks.json` (existing settings are merged, with backups); Codex
additionally requires trusting the hooks once via `/hooks` in the CLI.

## Architecture notes

- The `NSPanel` is a fixed 640×240 top-center window that never moves or
  resizes; all expand/collapse animation happens inside SwiftUI.
- Hit-testing accepts mouse input only over the visible island; the rest of
  the panel passes clicks through.
- A private CGS space keeps the island above fullscreen apps; the app degrades
  gracefully if that SPI breaks.
- `docs/` contains the spec and field-verified research notes on the notch
  window, MediaRemote, screenshots and agent hooks.

## License

MIT — see [LICENSE](LICENSE).

`Vendor/MediaRemoteAdapter` is from
[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter),
BSD-3-Clause (© Jonas van den Berg) — see its bundled LICENSE.
