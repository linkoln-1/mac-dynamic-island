# RESEARCH: Agent Session Actions (PASS 4)

Date: 2026-08-23. All probes read-only; no prompts sent, no permissions answered.

## Claude Code — exact-session focus

Hook payload fields available (verified in AgentHookHelper mapper and live spool):
`hook_event_name`, `session_id`, `cwd`, `tool_name`, `tool_input`, `notification_type`.
No TTY, no terminal window id, no process ancestry that survives the hook process
(hooks run as short-lived children of the CLI, the helper sees only its own ppid chain
at event time, which identifies the CLI process but NOT the owning terminal tab).

Claude Code registers no URL scheme for sessions. `claude --resume <id>` exists but
spawns a NEW terminal process — that is "open a new session with old context",
not "focus the running session".

**Verdict: CLAUDE_FOCUS_SESSION_CAPABILITY=UNAVAILABLE.**
Mapping cwd → "open Terminal here" would be a fake Focus Session (§46) — rejected.

## Codex CLI — exact-session focus

Same hook transport, same metadata surface as Claude-compatible hooks
(`~/.codex/hooks.json`). No TTY/window identity. No documented resume-focus
mechanism for a live CLI session.

**Verdict: CODEX_CLI_FOCUS_SESSION_CAPABILITY=UNAVAILABLE.**

## Codex Desktop (ChatGPT.app) — deep link

Read-only probe of `/Applications/ChatGPT.app/Contents/Info` CFBundleURLTypes:
registered schemes are `codex`, `http`, `https`. The `codex://` scheme EXISTS,
but the URL format for opening a specific thread/session is not documented
anywhere official; hook payloads carry a session id whose mapping to desktop
thread ids is unverified. Guessing URL formats is prohibited (§47).

**Verdict: CODEX_DESKTOP_FOCUS_SESSION_CAPABILITY=UNAVAILABLE (scheme exists,
format unverified). Revisit if OpenAI documents the deep-link format.**

## Approve/Deny external channel (research only, NOT implemented)

Claude Code: the official mechanism for programmatic permission decisions is the
PreToolUse hook returning `{"permissionDecision": "allow"|"deny"|"ask"}` on stdout
SYNCHRONOUSLY. That is an in-process gate, not an external async channel: our
observer hook already returned by the time the user sees the prompt, so a later
external "approve" has no official delivery path. An interactive approval hook that
BLOCKS waiting for PersonalIsland input would hold the agent hostage to island UX
and is a safety/UX decision for a dedicated pass.

Codex: no documented external approval API; `notify` in config.toml is occupied by
Computer Use on this machine and must not be touched.

**Verdict: APPROVE_DENY_CAPABILITY_RESEARCH=DOCUMENTED_NO_SAFE_EXTERNAL_CHANNEL;
APPROVE_DENY_IMPLEMENTED=false.**

## Rejected approaches

- Accessibility scraping / UI scripting of Terminal, ChatGPT.app — outside policy (§49).
- OCR / screen coordinates — outside policy.
- Opening a new terminal in cwd labeled as "Focus Session" — fake capability (§46).
- Guessed `codex://thread/...` URLs — unverified scheme format (§47).

## Implemented safe actions

- Reveal Project in Finder — `NSWorkspace.activateFileViewerSelecting`.
- Copy Project Path — `NSPasteboard.general`, no keyboard focus required.
- Open Project — top-level `.xcworkspace` → `.xcodeproj` → repository root via
  `NSWorkspace.open`. Availability gated on path exists + is directory; worktree
  roots are used as-is (no canonicalization into the main worktree).
