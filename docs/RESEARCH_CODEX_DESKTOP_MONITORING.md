# RESEARCH: Codex Desktop Monitoring (PASS 4.2)

Date: 2026-08-23. All probes read-only; the user's live Codex Desktop session was
never touched, prompted, or stopped.

## Installed inventory (OBSERVED)

- Codex Desktop: ChatGPT.app 26.818.41509 (build 6962), bundle `com.openai.codex`,
  agent runtime bundled in `Codex Framework.framework/Versions/151.0.7922.170`.
- Standalone CLI: `~/.local/bin/codex`, codex-cli **0.146.0**.
- The live Desktop session's rollout reports `cli_version: 0.149.0-alpha.4.1`,
  `originator: "Codex Desktop"`, `source: vscode` — the Desktop app ships its OWN
  newer runtime and does NOT use the user's 0.146 CLI.
- Shared state dir: `~/.codex` (config.toml, hooks.json, sessions/, session_index.jsonl,
  multiple SQLite stores: thread_history, state, logs — all actively written by Desktop).
- `notify` in config.toml is occupied by Codex Computer Use (`turn-ended`) — must not
  be touched (PASS 3 constraint, re-confirmed).

## Root cause (OBSERVED)

While a Desktop session was actively working for >1 minute:

- `~/.codex/hooks.json` contained valid PersonalIsland entries for all 8 events,
  correct stable helper path (`AgentBridge/bin/personal-island-agent-hook`),
  helper present and executable;
- the AgentBridge spool stayed empty, zero codex events reached the socket,
  AgentStore had zero codex sessions — while Claude hook events flowed normally
  through the same helper/socket/store pipeline.

Conclusion: the event loss point is the FIRST stage — **Codex Desktop's bundled
runtime (0.149.0-alpha) does not invoke the configured hooks at all**. Everything
downstream (helper, socket, spool, receiver, store, UI) is proven working via the
Claude path and unit/integration tests.

INFERRED (not proven): either the alpha bundled runtime lacks hooks.json support,
or hooks require the CLI `/hooks` trust step that has never been performed and the
Desktop offers no trust UI. Both variants have the same observable effect; neither
can be confirmed without upstream documentation.

## Local session store (OBSERVED)

- `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl` — append-only JSONL
  event stream per session, written live by Desktop (the active session's file grew
  in real time during observation, 8+ MB).
- Line schema: `{timestamp, ordinal, type, payload}`. Relevant payload types:
  - `session_meta` — session identity: `payload.id` (UUID), `cwd`, `originator`,
    `cli_version`;
  - `event_msg/task_started` — a turn begins (WORKING);
  - `event_msg/task_complete` — a turn ends (FINISHED); observed in completed
    sessions (2 started / 2 completed in a finished rollout);
  - `response_item/custom_tool_call` — tool activity; observed tool vocabulary on
    this machine: `exec` only → coarse activity;
  - noise: `token_count`, `reasoning`, `message`, `world_state`, `turn_context`.
- `~/.codex/session_index.jsonl` — session id index (append-only).

## Chosen fix: CodexLocalSessionProvider (read-only fallback)

- Source: FSEvents watch on `~/.codex/sessions` (2 s latency, file events) +
  offset-based tailing of rollout files with partial-line buffering. No polling,
  no full re-reads, no Accessibility/OCR/network, zero writes to Codex state.
- Mapping: `session_meta→SessionStart`, `task_started→UserPromptSubmit`,
  `custom_tool_call(exec)→PreToolUse(Shell)` ("Running a command" — honest coarse
  granularity, no fake file names), `task_complete/turn_aborted→Stop`.
  Prompts/responses/tool output are never read into the app — only the metadata
  fields above.
- Startup reconciliation: rollout files modified within 6 h are classified by
  turn counters; sessions with an open turn are imported as WORKING (cycle base =
  real turn count, no notifications); already-finished sessions are skipped —
  no historical cards, no delayed notifications.
- Arbitration: hook events (if the runtime ever starts delivering them) mark the
  session as hook-authoritative and the fallback mutes itself for that session —
  hooks stay primary, no double transitions.
- Identity: rollout `payload.id` is the primary session id (UI alias X-xxxx);
  cwd is metadata only.

## Rejected approaches

- Waiting for hook trust/restart as the only path — leaves Desktop sessions
  invisible today (the confirmed bug).
- SQLite thread stores as source — richer but riskier (schema churn in an alpha
  runtime, WAL contention); JSONL rollout is append-only and self-describing.
- `notify` config — occupied by Computer Use; modifying it is prohibited.
- Any UI automation/OCR of the Desktop app — outside policy.

## Known limitations

- Permission prompts are not represented in the rollout stream in any proven way —
  Codex permission attention is not produced by the fallback (honest gap).
- Activity granularity is coarse (`exec` → "Running a command").
- `turn_aborted` mapping to Stop is INFERRED from naming, not yet observed live.
- If Desktop hooks ever activate AND use a different session id namespace than
  rollout `payload.id`, arbitration would not match; considered unlikely
  (UNVERIFIED) and covered by hook-authority muting if ids match.
