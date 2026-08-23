# PersonalIsland — Product Spec (MVP)

Native macOS app turning the area around the MacBook notch into a personal Dynamic Island.
Not a clone of any existing product. Working name `PersonalIsland` (must be easy to rename).

## Environment
- macOS 26.6.2 (Tahoe), Xcode 26.6, Swift 6.3, Apple Silicon.
- Unsandboxed, personal use, NOT App Store. No signing/notarization needed for local run.
- Project generated with XcodeGen (`/opt/homebrew/bin/xcodegen`), must build with `xcodebuild`.
- Deployment target: macOS 14.0 or higher (pick what APIs require; 15.0 acceptable).

## Stack rules
- Swift + SwiftUI; AppKit where SwiftUI is insufficient (window/panel, drag sessions, event monitors).
- Minimum third-party dependencies (bundled single-file adapters OK; no SPM packages unless unavoidable).
- No Electron/WebView. No analytics/telemetry/network/cloud. Images never leave the Mac.
- No Screen Recording permission. Do not request permissions that aren't strictly needed.

## Island shell
Borderless transparent `NSPanel` anchored top-center of the active display, visually continuing the physical notch. No title bar, no traffic lights, no window frame, no Dock icon (accessory activation policy). Above normal windows, does not steal focus unless needed, survives Spaces switches, behaves on fullscreen apps, smooth resize, never jumps.

### States
- COLLAPSED: essentially just the notch area; barely enlarges the notch.
- COMPACT: small horizontal info island (e.g. `[artwork] Track/Artist [⏮][▶][⏭]`).
- EXPANDED: large panel `sidebar (left, icon-only) + module content (right)`.
Transitions collapsed↔compact↔expanded, spring-like animation without excessive bounce; width/height/cornerRadius/opacity/content all animate smoothly.

### Interaction
- Click compact island → expand. Click outside → collapse. `Esc` → collapse.
- Hover near island → subtle response only (no giant auto-expand).
- Menu bar keeps working; island sits around the notch, does not replace the menu bar.

### Geometry — `NotchGeometryProvider`
Computes compact/expanded frames from `NSScreen`: safeAreaInsets.top + auxiliaryTopLeftArea/auxiliaryTopRightArea for real notch; no-notch displays get a fake island centered at top edge. No hardcoded coordinates. React to `didChangeScreenParametersNotification`.

## Module system
`IslandModule`-style abstraction: id, title, SF Symbol icon, content view. Sidebar (very narrow, icon-only buttons: hover, selected, tooltip) lists modules; MVP registers exactly two. Architecture must allow adding future modules (AI monitor, clipboard, timers, widgets…) WITHOUT implementing them now.

## Module 1 — Screenshot Buffer
Visual buffer of recent screenshots.

Sources:
- A. Clipboard: watch `NSPasteboard.general` via `changeCount`; new PNG/TIFF image → add. Never re-add same item per poll; ignore self-written ⌘C copies (marker type).
- B. Disk: detect new macOS screenshots (⌘⇧3/⌘⇧4). Resolve real screencapture location from `com.apple.screencapture location` preference; fallback Desktop. Event-based monitoring (NSMetadataQuery kMDItemIsScreenCapture or FSEvents per research doc) — no heavy periodic scans.

Model `ScreenshotItem`: id, source (clipboard|screenshotFile), originalURL?, creationDate, thumbnail (separate from full-size; small memory footprint), pinned flag reserved. Selection state lives in view-model, not domain model.

Buffer rules: last ~30 items (constant in config), newest first, dedup, evict oldest unpinned at limit. No persistence across restarts for MVP (but don't block adding it later).

Interactions:
- Single click = select; ⌘-click = toggle in multi-selection; click on already-selected = quick preview (Quick Look if reasonable); double-click = open in default app.
- `⌘C` = copy selected back to clipboard. `Delete` = remove from buffer.
- NEVER auto-delete the original file on disk when removing from buffer (critical). A separate explicit "Delete Original File" action may exist later but is not default.
- Drag & drop thumbnail out to Telegram/Slack/Finder/browser/IDE (temp file for clipboard-only items).
- Context menu: Copy, Reveal in Finder (if file), Open, Remove from Buffer.
- Selected card: brighter border + checkmark badge; hover must not conflict with selection. Multi-selection footer: `Selected: N` + Copy / Remove from Buffer / Clear Selection.
- Grid of small cards: thumbnail-dominant, rounded, thin border, name or timestamp, selection badge. Not huge.

## Module 2 — Now Playing
System-wide media session (Spotify, Apple Music, browsers — whatever macOS shows in system media controls).

Data: title, artist, album, artwork, playback state, position, duration. Controls: play/pause/toggle, prev, next, seek if supported.

Architecture: `protocol NowPlayingProviding` + isolated system adapter. Private API (MediaRemote via adapter technique) allowed for this personal build but MUST be confined to one adapter file/dir with a comment explaining the limitation; UI and the rest never touch it. See docs/RESEARCH.md for the concrete mechanism chosen.

Empty state: calm "Nothing Playing" (no broken player); compact may auto-collapse.
Artwork: rounded rect, async, placeholder, cached, off-main decoding, no unbounded storage.
Progress: elapsed/duration/progress; seek via click/drag if supported, else read-only.

Expanded layout ≈ `[art] TRACK / Artist / Album + progress bar + ⏮ ▶/❚❚ ⏭`.
Compact layout ≈ `[art] Track/Artist ⏮ ❚❚ ⏭`.

## Settings (minimal)
Only if actually needed for MVP: Launch at Login, buffer size, screenshot directory override + reset-to-detected. Placeholder acceptable.

## Menu bar item (optional, secondary)
Open Island / Settings / Quit. Island remains the primary UI. Dock icon hidden (accessory policy).

## Performance
Background-resident app: no render loops, no 60fps polling, no constant full-size decoding, no unnecessary timers, event-driven where possible, heavy image work off main thread, UI on MainActor. Sane memory at 30 screenshots.

## Keyboard
Esc collapse; ⌘C copy selection; Delete remove selection; arrow navigation nice-to-have.

## Logging
`os.Logger`, categories: island, screenshots, clipboard, filesystem, nowPlaying. No per-second spam.

## Tests (unit, required)
- screenshot dedup; buffer limit eviction; newest-first ordering; selection-independent domain behavior; screenshot location resolution; now-playing state mapping (if adapter testable).

## Explicitly OUT of MVP
AI agent monitor, terminal, calendar, weather, notes, notification center, full clipboard manager, widgets, iCloud/cloud/accounts, updater, App Store packaging.

## Suggested layout (adapt freely, keep files focused <400 lines)
```
PersonalIsland/
├── project.yml                # XcodeGen
├── App/          PersonalIslandApp, AppDelegate, AppState
├── Island/       IslandWindowController, IslandPanel, IslandState,
│                 IslandRootView, NotchGeometryProvider
├── Modules/
│   ├── ModuleDefinition.swift
│   ├── Screenshots/  ScreenshotItem, ScreenshotBuffer, ScreenshotMonitor,
│   │                 ClipboardImageMonitor, ScreenshotDirectoryMonitor,
│   │                 ScreenshotThumbnailService, ScreenshotBufferView
│   └── NowPlaying/   NowPlayingState, NowPlayingProvider(protocol),
│                     SystemNowPlayingProvider, NowPlayingViewModel, NowPlayingView
├── Shared/       Extensions/ Components/ Utilities/
└── Tests/        unit tests
```
Reusable components: IslandContainer, IslandSidebar, ModuleButton, ScreenshotCard, MediaArtworkView, MediaControls, IslandProgressBar (or equivalents). No 1500-line ContentView.

## Visual direction
Near-black background fused with the notch, large corner radii, macOS-like, minimalist, high info density, SF Symbols, careful hover, subtle transparency only where it helps, readable text. Aesthetic refs: Dynamic Island, Control Center, Apple HUD, Raycast, Arc — but its own product.

## Acceptance criteria (all must hold)
Island: launches; appears at notch; looks like one black island; 3 states work; outside-click/Esc collapse; animated resize.
Screenshots: clipboard auto-appear; disk screenshot auto-appear; thumbnails; grid; single+multi select visible; ⌘C works; drag-out works; open; reveal; remove-from-buffer; original never deleted; item cap enforced; no excessive memory.
Now Playing: track/artist/artwork/state shown; play/pause works; next/prev works; progress shown; empty state; compact player.
Quality: native, no Electron, no telemetry, no cloud, no unneeded permissions, project builds, tests pass.

## Safety rules for agents
- No `git push`, no destructive git, no deleting user files, never delete screenshots from disk.
- Build with a per-agent `-derivedDataPath` to avoid clashes (e.g. `build/dd-<agent>`).
