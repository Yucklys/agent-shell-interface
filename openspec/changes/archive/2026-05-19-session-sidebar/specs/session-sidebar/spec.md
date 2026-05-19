## ADDED Requirements

### Requirement: Sidebar toggle command
The system SHALL provide an interactive command `agent-shell-interface-toggle` that shows or hides the session sidebar. When shown for the first time, it SHALL create the sidebar buffer and display it in a side window. Subsequent calls SHALL toggle the sidebar window visibility.

#### Scenario: First invocation shows sidebar
- **WHEN** the user invokes `agent-shell-interface-toggle` and no sidebar window exists
- **THEN** the system SHALL create a sidebar buffer and display it in a side window on the configured side (`agent-shell-interface-position`)

#### Scenario: Second invocation hides sidebar
- **WHEN** the user invokes `agent-shell-interface-toggle` and the sidebar window is visible
- **THEN** the system SHALL delete the sidebar window without killing the buffer

#### Scenario: Third invocation shows sidebar again
- **WHEN** the user invokes `agent-shell-interface-toggle` after hiding the sidebar
- **THEN** the system SHALL re-display the existing sidebar buffer in a side window

### Requirement: Sidebar displays sessions grouped by project
The sidebar SHALL enumerate all live agent-shell buffers via `agent-shell-buffers`, extract each buffer's project root via `agent-shell-cwd`, and group sessions under their project root heading. Each project group SHALL be foldable/collapsible.

#### Scenario: Multiple sessions in same project
- **WHEN** two agent-shell buffers have the same project root (via `agent-shell-cwd`)
- **THEN** the sidebar SHALL display both sessions under a single project heading

#### Scenario: Sessions in different projects
- **WHEN** agent-shell buffers have different project roots
- **THEN** the sidebar SHALL display each project as a separate group with its sessions listed underneath

#### Scenario: Session without a project
- **WHEN** an agent-shell buffer's `default-directory` is not inside a detected project
- **THEN** the session SHALL appear under a group labeled with its `default-directory`

### Requirement: Session status indicators
The sidebar SHALL display a status indicator next to each session entry. The system SHALL determine status by inspecting `agent-shell--state` in each live buffer: checking comint process liveness, `:client :process` liveness, `:tool-calls` for pending permissions, `shell-maker-busy` for working state, `:session :id` for session readiness, and `:initialized` flag.

Status indicators SHALL use:
- `●` for ready (session active, process alive, not busy)
- `◐` for working (active tool calls, no pending permission)
- `◆` for waiting (pending permission request)
- `○` for initializing (not yet initialized)
- `✕` for killed (process dead)

#### Scenario: Agent is idle and ready
- **WHEN** an agent-shell buffer has an active session and no in-flight requests
- **THEN** the sidebar SHALL display `●` with `success` face next to the session

#### Scenario: Agent is processing a request
- **WHEN** an agent-shell buffer has active tool calls with no pending permission
- **THEN** the sidebar SHALL display `◐` with `warning` face next to the session

#### Scenario: Agent is waiting for user permission
- **WHEN** an agent-shell buffer has a tool call with a `:permission-request-id`
- **THEN** the sidebar SHALL display `◆` with `font-lock-keyword-face` next to the session

#### Scenario: Agent process has been killed
- **WHEN** the comint process in an agent-shell buffer is not alive
- **THEN** the sidebar SHALL display `✕` with `error` face next to the session

### Requirement: Session entry display
Each session entry SHALL display: status indicator, agent type name (from config `:mode-line-name` or `:buffer-name`), and session mode (from `agent-shell--state` `:session :mode-id`). The project group heading SHALL display the project directory basename.

#### Scenario: Session with all information
- **WHEN** a session is active with mode-line-name "Claude Code" and session mode "plan"
- **THEN** the sidebar SHALL display the entry as `● Claude Code [plan]`

#### Scenario: Session without mode information
- **WHEN** a session has no `:session :mode-id`
- **THEN** the sidebar SHALL display the entry without the mode bracket, e.g., `● Claude Code`

### Requirement: Sidebar navigation
The sidebar SHALL support standard navigation keybindings: `n`/`p` for next/previous session, `TAB` for next project group, and `S-TAB` for previous project group. `RET` SHALL switch to the session at point.

#### Scenario: Navigate to next session
- **WHEN** the user presses `n` in the sidebar
- **THEN** point SHALL move to the next session entry

#### Scenario: Navigate to previous project
- **WHEN** the user presses `S-TAB` in the sidebar
- **THEN** point SHALL move to the previous project group heading

### Requirement: Switch to session
The sidebar SHALL provide a `RET` keybinding that switches to the agent-shell buffer at point, displaying it in an adjacent window (not the sidebar window).

#### Scenario: Switch to visible session
- **WHEN** the user presses `RET` on a session entry whose buffer is already visible in another window
- **THEN** the system SHALL select that window and buffer

#### Scenario: Switch to hidden session
- **WHEN** the user presses `RET` on a session entry whose buffer is not currently visible
- **THEN** the system SHALL display it in the most recently used non-sidebar window

### Requirement: Kill session
The sidebar SHALL provide a `k` keybinding that kills the agent-shell process at point (sends EOF to comint and eventually kills the buffer).

#### Scenario: Kill an active session
- **WHEN** the user presses `k` on a live session entry
- **THEN** the system SHALL send comint EOF to the agent-shell process at point

#### Scenario: Kill a killed session
- **WHEN** the user presses `k` on a session that is already killed
- **THEN** the system SHALL kill the buffer and remove it from the list on next refresh

### Requirement: Create new session
The sidebar SHALL provide a `c` keybinding that starts a new agent-shell session, prompting for agent type if `agent-shell-preferred-agent-config` is not set. After creation, the sidebar SHALL refresh to show the new session.

#### Scenario: Start new session with preferred config
- **WHEN** the user presses `c` and `agent-shell-preferred-agent-config` is set
- **THEN** the system SHALL start a new agent-shell session with that config and refresh the sidebar

#### Scenario: Start new session without preferred config
- **WHEN** the user presses `c` and no preferred config is set
- **THEN** the system SHALL prompt the user to select an agent config and start the session

### Requirement: Auto-refresh
The sidebar SHALL automatically refresh its content on a configurable timer interval (default 2 seconds). Refreshing SHALL only occur when the sidebar window is visible. The timer SHALL be canceled when the sidebar buffer is killed.

#### Scenario: Timer refreshes visible sidebar
- **WHEN** the sidebar window is visible and 2 seconds have elapsed
- **THEN** the sidebar SHALL re-read all session states and update the display

#### Scenario: Timer skips invisible sidebar
- **WHEN** the sidebar window is not visible
- **THEN** the timer callback SHALL skip the refresh

#### Scenario: Buffer cleanup cancels timer
- **WHEN** the sidebar buffer is killed
- **THEN** the system SHALL cancel the refresh timer

### Requirement: Sidebar customization
The system SHALL provide the following customization options:
- `agent-shell-interface-position`: side window position, `left` or `right` (default `right`)
- `agent-shell-interface-width`: sidebar width, integer (columns) or string percentage like `"30%"` (default `"30%"`)
- `agent-shell-interface-refresh-interval`: timer interval in seconds (default 2)

#### Scenario: Configure left sidebar
- **WHEN** `agent-shell-interface-position` is set to `left`
- **THEN** the sidebar SHALL be displayed as a side window on the left of the frame

#### Scenario: Configure percentage width
- **WHEN** `agent-shell-interface-width` is set to `"30%"`
- **THEN** the sidebar window SHALL occupy 30% of the frame width, subject to min/max constraints

### Requirement: Sidebar focus toggle
The system SHALL provide a command `agent-shell-interface-toggle-focus` that switches focus between the sidebar and the last non-sidebar window.

#### Scenario: Focus sidebar when not in sidebar
- **WHEN** the user invokes `agent-shell-interface-toggle-focus` from a non-sidebar window
- **THEN** the system SHALL select the sidebar window

#### Scenario: Focus last window when in sidebar
- **WHEN** the user invokes `agent-shell-interface-toggle-focus` from the sidebar window
- **THEN** the system SHALL select the last non-sidebar window that had focus