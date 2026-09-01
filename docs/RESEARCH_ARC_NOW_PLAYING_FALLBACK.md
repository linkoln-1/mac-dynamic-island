# Research: Arc Now Playing Fallback (PASS 2.2, verified live 2026-08-23)

## Problem reproduced
Arc plays YouTube (no PiP) → `navigator.mediaSession` in the tab: playing, full
metadata. MediaRemote (perl adapter `get`) intermittently loses the session
(user report) and even while holding it reports a broken elapsed anchor
(elapsedTime 0.02 s vs real 354 s at probe time). PiP toggling re-registers the
session, which explains the user's "PiP fixes it" observation.

## Arc capabilities (all VERIFIED on this machine)
- Bundle id: `company.thebrowser.Browser` (Arc running, 1 window).
- AppleScript dictionary (sdef): classes `application / window / space / tab`;
  tab properties `id (UUID string) / title / URL / loading`; commands include
  Chromium-suite `execute` (`CrSuExJa`): `execute <tab> javascript <text>` →
  text result.
- Tab enumeration across windows: WORKS read-only (`repeat with w in windows /
  tabs of w`).
- JavaScript execution in a tab: WORKS — no Chrome-style "Allow JavaScript from
  Apple Events" developer gate blocked it. Returned live media element state +
  `navigator.mediaSession.metadata` (title, artist, artwork list, playbackState)
  from a YouTube tab.
- Background behavior: enumeration + JS run against tab specifiers, not the
  active tab; Chromium executes Apple-Events JS in background tabs (DOM reads
  are synchronous, unaffected by timer throttling). Live check of a fully
  background tab left to user acceptance (non-destructive probe rule).
- Automation permission: Apple Events to Arc require TCC Automation consent per
  requesting app. Error `-1743` = denied, `-600` = Arc not running. The app
  bundle already carries `NSAppleEventsUsageDescription`.

## Chosen production mechanism
`/usr/bin/osascript` subprocess per probe (bounded, ~1 Hz max while acting as
authority), AppleScript that:
1. iterates windows → tabs, considers only tabs whose URL is a playback page
   (`youtube.com/watch`, `/shorts/`, `/live/`, `/embed/`, `music.youtube.com` —
   `ArcPlaybackPages`) plus the previously chosen tab id (fast path). The
   YouTube home page, feeds, search results and channel pages are skipped on
   purpose: they carry muted hover-preview `<video>` elements that stay paused
   with `mediaSession` metadata for days and would otherwise be reported as
   "now playing" forever;
2. runs one compact JS returning JSON: media elements (`paused/ended/
   currentTime/duration/readyState/muted/playbackRate`), `mediaSession`
   metadata + `playbackState`, `document.title`;
3. `with timeout of 4 seconds` inside AppleScript + hard `Process` kill at 6 s.

Paused media is not "now playing" forever: `NowPlayingArbiter` drops any
source (MediaRemote or Arc) whose item has sat paused at the same position for
longer than `Config.pausedRetention` (10 min). Resuming or seeking brings it
back immediately.
Cheap pre-check via `NSRunningApplication` avoids spawning osascript when Arc
is not running.

## Rejected alternatives
- Accessibility tree scraping: fragile, needs AX permission — forbidden path.
- Browser extension / remote debugging port: out of policy (§9C).
- NSAppleScript in-process: main-thread-ish, no hard timeout, hangs risk.
- Downloading `mediaSession` artwork URLs: network egress — violates privacy
  policy; browser artwork stays `nil` (placeholder UI).

## Privacy scope
Only tabs on media hosts are scripted; only media/metadata fields above are
read; no page text, cookies, storage, history. Logs carry counts/states, never
URLs or titles.
