## Context

agent-shell is an Emacs package for interacting with LLM agents via ACP (Agent Client Protocol). It supports multiple simultaneous sessions across different projects, each running in its own buffer with its own agent (Claude, Gemini, Codex, etc.). The existing `agent-shell-sidebar` package by cmacrae embeds a single agent-shell session in a side panel — but it does not provide a cross-project session overview.

The new `agent-shell-interface` package targets a different need: a **session management sidebar** that lists all running agent-shell buffers grouped by their project root, showing status at a glance and enabling quick switching/management. It builds on the same public/internal APIs that agent-shell-manager and agent-shell-sidebar use.

Key APIs available:
- `agent-shell-buffers` — returns all shell buffers ordered by recent access
- `agent-shell-project-buffers` — returns shell buffers in the current project
- `agent-shell-cwd` — returns the CWD (project root) for a given shell buffer
- `agent-shell--state` — buffer-local alist with session, client, tool-calls, and other state
- `agent-shell-subscribe-to` — event subscription system (events: init-started, prompt-ready, session-selected, tool-call-update, file-write, init-finished, etc.)
- `agent-shell-make-agent-config` / `agent-shell--start` — for creating new sessions
- `agent-shell-get-config` — retrieve agent config from a buffer

Current constraints:
- `agent-shell--state` is an internal variable (no public API for reading status), so we use forward declarations and access it directly, same as agent-shell-manager does
- The sidebar should work with both `projectile` and `project.el` for project detection (via `agent-shell-cwd`)

## Goals / Non-Goals

**Goals:**
- Provide a persistent sidebar showing all agent-shell sessions grouped by project
- Display real-time status per session (ready, working, waiting, initializing, killed)
- Offer quick keyboard-driven operations: switch, kill, restart, new, interrupt, set mode/model
- Auto-refresh status on a timer and reactively on agent-shell events
- Support customization: sidebar position (left/right), width, auto-refresh interval
- Work alongside existing packages (agent-shell-sidebar, agent-shell-manager) without conflicts

**Non-Goals:**
- Embedding the agent-shell interaction within the sidebar (that's agent-shell-sidebar's job)
- Managing non-agent-shell buffers or projects without sessions
- Replacing `ibuffer` or general buffer management
- Persisting sidebar state across Emacs sessions (future consideration)

## Decisions

### D1: Sidebar implementation via `display-buffer-in-side-window`
**Choice**: Use Emacs built-in side window API (`display-buffer-in-side-window`)
**Rationale**: This is the standard approach used by treemacs, dired-sidebar, and agent-shell-sidebar. It provides dedicated side windows that are resilient to `other-window` navigation, support `window-size-fixed`, and integrate with `window-configuration-change-hook`.
**Alternative considered**: Using a dedicated frame (like calc) — rejected because it's jarring and doesn't integrate with standard Emacs window workflows.

### D2: Grouping by project root
**Choice**: Group sessions by the value of `(agent-shell-cwd)` in each buffer, which resolves to the project root (projectile or project.el) or `default-directory`.
**Rationale**: `agent-shell-cwd` is the canonical way agent-shell determines a session's project context. It's used by `agent-shell-project-buffers` and matches the naming convention in buffer names (`"Claude Code Agent @ my-project"`).
**Alternative considered**: Grouping by `project-current` — rejected because agent-shell may not be in a project root, and `agent-shell-cwd` already handles the fallback.

### D3: Status detection approach
**Choice**: Read `agent-shell--state` buffer-locally, same as agent-shell-manager. Check `:client` process liveness, `:tool-calls` for pending permissions, `shell-maker-busy` for working state, and `:session :id` for session readiness.
**Rationale**: This is the proven approach used by agent-shell-manager. There is no public status API in agent-shell, so we depend on internal state similar to other extension packages.
**Alternative considered**: Subscribing to agent-shell events only — rejected because events are asynchronous and don't give a complete snapshot; we need both polling (timer) and events for responsiveness.

### D4: Tree-style display using text properties (not tree-widget or tabulated-list)
**Choice**: Render the sidebar as a specialized buffer with text properties and button-like keymaps, using indentation for project groups.
**Rationale**: tree-widget.el is heavyweight and not well-suited for simple two-level hierarchies. tabulated-list-mode is what agent-shell-manager uses but works better as a full-window list than a sidebar tree. A custom buffer with text properties gives us full control over appearance, fold/unfold of project groups, and inline status indicators.
**Alternative considered**: Using `tabulated-list-mode` — rejected because it doesn't support tree-style grouping well and prefers full-window layouts.

### D5: Auto-refresh strategy
**Choice**: Dual approach — a configurable timer (default 2 seconds) plus event-driven refresh via `agent-shell-subscribe-to` subscriptions when sessions are created.
**Rationale**: Timer ensures stale state is eventually corrected. Event subscriptions give immediate feedback on state changes (session start, tool calls, completion).
**Alternative considered**: Timer-only — rejected because it introduces up to 2s latency for status changes.

## Risks / Trade-offs

- **Internal API dependency**: `agent-shell--state` is not a public API and may change between agent-shell versions. → Mitigation: Use defensive coding with `Map-nested-elt` and fallback values; document the dependency.
- **Timer overhead**: A 2-second timer refreshing the sidebar could cause flickering or performance issues with many sessions. → Mitigation: Only refresh when the sidebar buffer is visible; use `buffer-live-p` checks before accessing state.
- **Buffer-local state access**: Reading `agent-shell--state` from another buffer requires `with-current-buffer`, which can trigger mode hooks. → Mitigation: Minimize work inside `with-current-buffer`; cache extracted values.
- **Side-window conflicts**: If the user also runs agent-shell-sidebar, both may want the same side window slot. → Mitigation: Use different `window-parameters` (slot values) and clear `no-delete-other-windows` only for our sidebar.