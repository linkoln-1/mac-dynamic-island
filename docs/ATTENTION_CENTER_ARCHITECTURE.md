# Attention Center Architecture (PASS 4)

## Pipeline

```
AgentStore (single state authority, PASS 3)
    │ transitions: AgentTransition (needsPermission / finished / failed)
    │ resolutions: AgentPermissionResolution (left needsPermission)
    ▼
AgentAttentionMapper (pure)  →  AttentionEvent
    ▼
AttentionStore (generic, @MainActor)
    ├─ items (deduped by dedupKey, persisted)
    ├─ notificationRequests → AgentNotificationManager.post(item:)  [max one per item]
    ├─ sidebar badge (unreadCount / highPriorityUnreadCount)
    └─ compact badge (CompactSurfacePlan)
```

One real event = one AttentionItem = at most one native notification.
The old direct `transitions → AgentNotificationManager.handle` path is disconnected;
`handle(_:)` remains only as a test-covered legacy entry. Notification identifiers
keep the PASS 3 format `sessionID|cycleID|kind`, so dedup is backward compatible.

## Generic model

`AttentionEvent`/`AttentionItem` carry `source: AttentionSource` (`.agent(provider)`
today; Downloads/Timers add cases later and call `AttentionStore.shared.publish(_:)`
without knowing AgentStore internals). No prompts, transcripts, tool output or raw
commands are stored — only normalized metadata (`AgentActivityFormatter` output).

## Dedup

`dedupKey = sessionID|workCycleID|kind` (from AgentTransition). Duplicate events
(hook retry, spool replay, PermissionRequest + permission_prompt pair) hit the same
key: the item's `updatedAt` refreshes, nothing else happens, no notification.
Persistence makes this survive relaunch: replayed Stop events find the stored item
and stay silent.

## State dimensions

- `isUnread` — cleared by row click or Mark as Read; never cleared by merely
  opening the module.
- `isResolved` — permission items start unresolved; resolved when the session
  leaves needsPermission for any reason (continuation, Stop, StopFailure,
  SessionEnd). Finished/failed items are born resolved (§148).
- `isDismissed` — hides from the list, never touches the agent session.

Priorities: needsPermission/failed → HIGH, finished → NORMAL. Resolution drops a
permission item to NORMAL, so `highPriorityUnreadCount` reflects only actionable
warnings (§147).

## Sorting

unresolved HIGH → unread failed → unread others → read/resolved; newest first
within each group.

## Persistence

`~/Library/Application Support/PersonalIsland/attention.json`, atomic write,
0.5 s debounce. Corrupted file → renamed to `attention.corrupted-<ts>.json`,
store starts clean, AgentStore untouched. Retention: 7 days / 200 items;
unresolved HIGH items are exempt from both.

## UI surfaces

- Attention module (sidebar `bell.badge`, unread badge, red when HIGH present).
- Compact: `CompactSurfacePlan` decides coexistence — media keeps its accepted
  layout, the ⚠ badge lives in the micro-cluster zone; without media the agent
  summary row hosts the badge; badge click navigates to the Attention module via
  `.islandNavigateToModule` (mouse only, panel never becomes key).
- Row click → mark read + navigate to the exact live session in the Agents module
  (provider filter reset, 1.6 s static highlight, Reduce Motion respected).
  Dead sessions: no navigation, project-level actions remain.

## Future sources (not implemented)

Downloads/Timers publish AttentionEvents with their own source case, dedup keys
and priorities; the store, badges, persistence and notification policy are already
source-agnostic.
