# Agent Monitor Integration (PASS 3 §132)

## What PersonalIsland changes on Enable
Pressing **Enable Agent Monitoring** (AI Agents module):
1. Copies the bundled helper to
   `~/Library/Application Support/PersonalIsland/AgentBridge/bin/personal-island-agent-hook`
   (stable path — survives rebuilds; hook configs never point into DerivedData).
2. Backs up existing configs to `AgentBridge/backups/<name>.<timestamp>.bak`
   (once per install action, not per launch).
3. Merges observer hooks into:
   - `~/.claude/settings.json` → `hooks` (10 events; matcher `*`, async,
     timeout 10 s). All existing keys and foreign hooks are preserved.
   - `~/.codex/hooks.json` (8 events, same shape). `config.toml` is untouched
     (its `notify` belongs to Codex Computer Use).
4. Starts the local unix-socket receiver and requests notification permission
   (first time only; denial is safe — the monitor keeps working without alerts).

## Codex trust step (one-time, user action)
Codex requires reviewing new hooks: run `codex`, open `/hooks`, trust the two
PersonalIsland entries (hash-pinned). Until trusted, Codex skips them safely.

## Runtime contract
Hook → helper (`--provider claude|codex`, JSON on stdin) → normalize+redact →
unix socket `AgentBridge/agent.sock` → app. App not running → spool file in
`AgentBridge/spool/` (bounded 24 h / 500 events) → replayed and deleted on next
launch. Helper always exits 0 fast; agents are never blocked or broken.

## Repair / Uninstall
- Repair (button in the module when health shows a broken integration):
  re-copies the helper and re-merges missing entries. Idempotent.
- Uninstall: `AgentHookInstaller.uninstall(configURL:)` removes ONLY entries
  whose command references `personal-island-agent-hook`; foreign hooks and all
  other settings stay. Backups remain in `AgentBridge/backups/`.
