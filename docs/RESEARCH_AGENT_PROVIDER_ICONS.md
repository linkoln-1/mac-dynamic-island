# Research: Agent Provider Icons (PASS 3 §130, probed 2026-08-23)

Rule: ORIGINAL icons only — resolved dynamically from installed official apps
via `NSWorkspace.urlForApplication(withBundleIdentifier:)` + `icon(forFile:)`.
Never bundled copies, never recreated/recolored/AI-generated. Cached NSImage
per provider (`AgentProviderIconResolver`).

## Claude Code
- Source: installed official **Claude.app**, bundle id
  `com.anthropic.claudefordesktop` (verified via mdls on this machine).
- No Claude-Code-specific local icon asset ships with the CLI (`~/.local/bin/
  claude` is a bare executable) → the official Claude app icon is the correct
  local-official source (§49 priority 2).

## Codex
- Source: installed official **ChatGPT.app**, bundle id `com.openai.codex`
  (verified via mdls — this IS the Codex desktop app; its config even carries
  `dock-icon-preference = "codex-system"`). Dynamic resolution keeps the icon
  current if OpenAI updates it.
- CodexBar.app (`com.steipete.codexbar`) is a third-party app — NOT used as an
  icon source.

## Fallback
No official app installed → resolver returns nil and the UI shows a neutral
SF Symbol placeholder (`app.dashed`). No invented logos, ever. Both providers
resolve successfully on this machine (unit-tested).

## Modification policy
Only aspect-preserving system scaling in SwiftUI (`resizable + scaledToFit`).
No tint/recolor/crop/glow/masking.
