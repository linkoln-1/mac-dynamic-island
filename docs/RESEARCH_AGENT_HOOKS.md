# Research: Agent Hooks (PASS 3, probed live 2026-08-23)

## Installed runtimes
- Claude Code **2.1.240** at `~/.local/bin/claude`.
- codex-cli **0.146.0** at `~/.local/bin/codex`
  (standalone release `~/.codex/packages/standalone/releases/0.146.0-...`).
- Codex Desktop = **ChatGPT.app** (bundle `com.openai.codex`, app version
  26.818.32112). `CODEX_CLI_PATH` inside its bundle and `CODEX_HOME=~/.codex`
  prove desktop and CLI share ONE runtime and ONE config layer → hooks
  installed at user level cover both surfaces.

## Claude Code events (verified against the installed binary)
All names present in the 2.1.240 binary: SessionStart, UserPromptSubmit,
PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, Notification,
SubagentStart, SubagentStop, TaskCreated, TaskCompleted, Stop, StopFailure,
SessionEnd, PreCompact. Config: `~/.claude/settings.json` `hooks` section;
`"async": true` supported for observer command hooks.
Observed set installed by PersonalIsland: SessionStart, UserPromptSubmit,
PreToolUse, PermissionRequest, Notification, SubagentStart, SubagentStop,
Stop, StopFailure, SessionEnd (PostToolUse deliberately skipped — activity is
driven by PreToolUse; less hook traffic).

## Codex events (binary strings + official docs learn.chatgpt.com/docs/hooks)
Codex 0.146 adopted a Claude-compatible hooks system:
- Config: `~/.codex/hooks.json` (or inline `[hooks]` in config.toml; one
  representation per layer preferred). Project-level `.codex/hooks.json` also
  exists (trusted repos only).
- Document shape: `{"hooks": {"<Event>": [{"matcher": ..., "hooks":
  [{"type": "command", "command": ..., "timeout": ..., "async": true}]}]}}`.
- Events: SessionStart, SessionEnd, SubagentStart, SubagentStop, PreToolUse,
  PermissionRequest, PostToolUse, PreCompact, PostCompact, UserPromptSubmit,
  Stop. **No StopFailure / Notification** → Codex FAILED state has no reliable
  signal this pass.
- Stdin payload is Claude-shaped: `session_id`, `cwd`, `hook_event_name`,
  `tool_name`, `tool_input`, `turn_id`, `stop_hook_active`,
  `last_assistant_message`.
- Async: `"async": true`, up to 8 concurrent background hooks per session.
- **Hook trust**: non-managed command hooks must be reviewed and trusted by
  the user (`/hooks` in the CLI, hash-pinned; changed hooks are skipped until
  re-trusted). PersonalIsland documents this — the user confirms trust once
  after install; we never bypass it in production.
- `notify` in config.toml is already occupied by the user's Codex Computer Use
  client ("turn-ended") — PersonalIsland must NOT touch `notify`.
- PostToolUse: present in 0.146 strings and docs; not required by our design
  (CODEX_POST_TOOL_USE not part of the installed set).

## Transport decision
Helper executable at a stable app-owned path
(`~/Library/Application Support/PersonalIsland/AgentBridge/bin/`), one unix
domain socket (`AgentBridge/agent.sock`, 0600) — no TCP/HTTP ports. Helper
timeout ≈0.4 s; app absent → atomic single-file JSON spool
(`AgentBridge/spool/`, bounded 24 h / 500 events) → exit 0. Hooks are
observation-only: no decision output ever.
