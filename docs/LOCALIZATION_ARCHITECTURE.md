# Localization Architecture (PASS 4.1)

## Supported locales

`en` (fallback) and `ru`. Registered via `CFBundleLocalizations`, XcodeGen
`developmentLanguage: en`, and the compiled `Localizable.xcstrings` catalog
(`Shared/Localization/`), which produces `en.lproj`/`ru.lproj` with
`Localizable.strings` + `Localizable.stringsdict` (plural variations) in the app.

## Language modes

`AppLanguageMode`: `system` / `english` / `russian`, persisted in UserDefaults
(`appLanguageMode`). `system` is auto-selection, not a third language:
first preferred macOS language with prefix `ru` → ru, prefix `en` → en,
anything else → en. Selection UI lives in the status-bar menu
(Language → System / English / Русский, checkmark on the active mode).

## Runtime switching (no AppleLanguages hack)

`AppLanguageManager` (single authority) resolves the selected language to an
`.lproj` bundle and serves every user-facing string via `string(_:)`,
`format(_:)`, `plural(_:_:)` (plural categories resolved by
`String(format:locale:)` against the compiled stringsdict). Missing ru key →
English fallback + one-shot DEBUG log; the raw key is never shown when a
translation exists.

Live switching: every localized SwiftUI view observes the manager
(`@ObservedObject`), so `setMode` re-renders the whole hierarchy immediately —
no restart, no window reconstruction, no `AppleLanguages`. AppKit surfaces
(status menu, card NSMenus) build their items at open time, so they are always
in the current language. `UNUserNotificationCenter` content is produced through
the same manager at post time.

macOS system-language changes while in `system` mode are picked up on the next
`refreshResolvedLanguage()` call; there is no polling. A live distributed
notification for this is not guaranteed by macOS — documented limitation.

## What is never translated

Brands and products (PersonalIsland, Claude Code, Codex, Finder, Arc, Spotify…),
project names, session aliases, branch names, file names, commands, raw external
errors, media timecodes (`8:34`).

## Persistence stays language-neutral

Domain models persist enums and canonical data (`kind = finished`,
`detail = "Finished in 8:34"` in canonical form, canonical activity strings from
`AgentActivityFormatter`). User-facing text is computed at render by
`AttentionPresentation` / `ActivityPresentation`, so items created under one
language render correctly after switching — including items persisted before
PASS 4.1 (canonical English is parsed by exact prefix over our own finite
formatter vocabulary; unknown strings pass through untouched). No schema
migration was needed; `attention.json` decoding is unchanged.

## Tooltip contract

Any ambiguous icon-only control must carry a localized `.help` tooltip (native
timing, no layout change) and a matching accessibility label: sidebar module
buttons, the three Attention row actions (Mark as Read / Project actions /
Dismiss), the agent `•••` menu, media transport controls, compact ⚠ badge.
Obvious text buttons get no redundant tooltip.

## Contract for future passes

Every future pass (PASS 5 Clipboard, PASS 6 Downloads, PASS 7 Orchestrator…)
that adds user-facing strings MUST ship en + ru in `Localizable.xcstrings` in
the same pass, use `AppLanguageManager` for runtime strings, and keep persisted
state language-neutral. An English-only UI does not count as a finished pass;
the parity test (`testTranslationParityAndNoEmptyValues`) enforces key parity.
