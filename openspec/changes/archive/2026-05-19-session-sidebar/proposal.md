## Why

agent-shell provides a powerful multi-session workflow where users can run multiple agent instances across different projects simultaneously. However, there is no unified way to see all active sessions, understand their current status (idle, working, waiting for permission), quickly switch between them, or manage sessions grouped by project. Users must rely on buffer switching (`C-x b`) which doesn't show project context, agent type, or session state — making multi-project workflows cumbersome.

## What Changes

- Add a sidebar panel that displays all agent-shell sessions grouped by project root directory
- Show real-time per-session status indicators: ready, working, waiting (for permission), initializing, or killed
- Provide quick actions: switch to session (RET), kill session (k), start new session (c), restart (r), interrupt (C-c C-c), set session mode (m), set model (M)
- Support sidebar width/position customization (left/right, absolute or percentage width)
- Auto-refresh session state on a timer and on agent-shell events
- Integrate with `agent-shell-project-buffers` and `agent-shell-buffers` APIs to enumerate sessions
- Read agent config, session state, and status from `agent-shell--state` buffer-local variable

## Capabilities

### New Capabilities
- `session-sidebar`: A treemacs-style persistent sidebar that lists all agent-shell buffers grouped by project, with real-time status indicators and keyboard-driven session management

### Modified Capabilities

## Impact

- New file: `agent-shell-interface.el` (the main package file)
- Depends on: `agent-shell` (for session enumeration, state access, starting sessions), `agent-shell-project` (for project root detection)
- Integrates with existing `agent-shell-buffers` and `agent-shell-project-buffers` APIs
- Reads buffer-local `agent-shell--state` for status/session info (internal API, may need forward declarations)
- Complements `agent-shell-sidebar` (cmacrae's package) — this package focuses on session management across projects rather than embedding a single session in a side panel