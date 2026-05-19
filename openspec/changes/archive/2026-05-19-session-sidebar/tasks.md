## 1. Package Setup and Defcustoms

- [x] 1.1 Create `agent-shell-interface.el` with package headers, `defgroup`, `defcustom` for `agent-shell-interface-position`, `agent-shell-interface-width`, `agent-shell-interface-refresh-interval`
- [x] 1.2 Add `require` statements for `agent-shell`, `agent-shell-project`, `map`, `cl-lib`, `subr-x`; add `declare-function` forward declarations for internal agent-shell functions (`agent-shell--state`, `agent-shell-cwd`, `agent-shell-buffers`, `agent-shell--resolve-session-mode-name`, etc.)

## 2. Sidebar Buffer and Window Management

- [x] 2.1 Implement `agent-shell-interface--get-buffer` and `agent-shell-interface--get-window` helpers to find or create the sidebar buffer/window
- [x] 2.2 Implement `agent-shell-interface--calculate-width` for parsing percentage/integer width with min/max constraints
- [x] 2.3 Implement `agent-shell-interface-toggle` command: show/hide the sidebar via `display-buffer-in-side-window`, toggle visibility, handle first-show case
- [x] 2.4 Implement `agent-shell-interface-toggle-focus` command: switch focus between sidebar and last non-sidebar window
- [x] 2.5 Define `agent-shell-interface-mode` as a derived major mode with its keymap and `agent-shell-interface-mode-map` bindings (n, p, TAB, S-TAB, RET, k, c, r, m, M, C-c C-c, g, q)

## 3. Status Detection and Session Enumeration

- [x] 3.1 Implement `agent-shell-interface--get-status` to read `agent-shell--state` from a buffer and determine status: ready, working, waiting, initializing, or killed
- [x] 3.2 Implement `agent-shell-interface--format-status` to produce propertized status strings with appropriate faces and symbols (●, ◐, ◆, ○, ✕)
- [x] 3.3 Implement `agent-shell-interface--group-by-project` to call `agent-shell-buffers` and group results by `agent-shell-cwd`
- [x] 3.4 Implement `agent-shell-interface--session-label` to format a session entry line with status, agent name, and mode

## 4. Sidebar Rendering

- [x] 4.1 Implement `agent-shell-interface--render` to clear and redraw the sidebar buffer: project group headings (foldable), session entries with status indicators, and keybinding hints in a help section at the top
- [x] 4.2 Implement fold/unfold of project groups: `agent-shell-interface--toggle-project` on visibility state per project, stored in a buffer-local variable
- [x] 4.3 Add text properties and keymap properties to project headings and session entries so that `RET`, `k`, etc. work on the entry at point

## 5. Interactive Commands

- [x] 5.1 Implement `agent-shell-interface-goto`: switch to the agent-shell buffer at point in another window
- [x] 5.2 Implement `agent-shell-interface-kill`: send comint EOF to kill the session process at point
- [x] 5.3 Implement `agent-shell-interface-new`: start a new agent-shell session (using preferred config or `agent-shell-select-config`)
- [x] 5.4 Implement `agent-shell-interface-restart`: kill session at point and restart with same agent config
- [x] 5.5 Implement `agent-shell-interface-interrupt`: call `agent-shell-interrupt` on session at point
- [x] 5.6 Implement `agent-shell-interface-set-mode` and `agent-shell-interface-set-model` wrappers for `agent-shell-set-session-mode` and `agent-shell-set-session-model`

## 6. Auto-Refresh and Event Integration

- [x] 6.1 Implement timer-based auto-refresh using `run-with-timer` / `agent-shell-interface-refresh`, with guard to skip if sidebar window is not visible
- [x] 6.2 Start/stop timer in `agent-shell-interface-mode` body and `kill-buffer-hook`; cancel timer when sidebar buffer is killed
- [x] 6.3 Subscribe to agent-shell events (`init-finished`, `prompt-ready`, `session-selected`, `tool-call-update`) in sidebar mode activation and trigger refresh on event

## 7. Final Polish

- [x] 7.1 Add `(provide 'agent-shell-interface)` and proper Commentary section documenting usage and keybindings
- [x] 7.2 Add `;;;###autoload` cookies for `agent-shell-interface-toggle` and `agent-shell-interface-toggle-focus`
- [x] 7.3 Test: sidebar toggle, session listing, status changes, kill/restart, group folding, focus toggle