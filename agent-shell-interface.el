;;; agent-shell-interface.el --- Session management sidebar for agent-shell  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Yucklys

;; Author: Yucklys
;; URL: https://github.com/Yucklys/agent-shell-interface
;; Package-Requires: ((emacs "29.1") (agent-shell "0.47"))
;; Version: 0.1.0

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A session management sidebar for agent-shell that displays all active
;; agent-shell sessions grouped by project, with real-time status
;; indicators and keyboard-driven management.
;;
;; Features:
;; - Project-grouped view of all agent-shell sessions
;; - Status indicators: ready, working, waiting, initializing, killed
;; - Quick actions: switch (RET), kill (k), new (c), restart (r),
;;   interrupt (C-c C-c), set mode (m), set model (M)
;; - Auto-refresh via timer and agent-shell event subscriptions
;; - Foldable project groups (SPC to fold/unfold)
;;
;; Usage:
;;   M-x agent-shell-interface-toggle      - Show/hide sidebar
;;   M-x agent-shell-interface-toggle-focus - Toggle focus sidebar/other
;;
;; Key bindings in sidebar:
;;   RET       - Switch to session at point
;;   n / p     - Next/previous session
;;   TAB       - Next project group
;;   S-TAB     - Previous project group
;;   SPC       - Toggle project group fold
;;   k         - Kill session
;;   c         - Create new session
;;   r         - Restart session
;;   C-c C-c   - Interrupt session
;;   m         - Set session mode
;;   M         - Set session model
;;   g         - Refresh sidebar
;;   q         - Quit sidebar

;;; Code:

(require 'agent-shell)
(require 'agent-shell-project)
(require 'map)
(require 'cl-lib)
(require 'subr-x)

;;;; Forward declarations for internal agent-shell symbols

(defvar agent-shell--state)
(defvar agent-shell-agent-configs)
(defvar agent-shell-preferred-agent-config)
(defvar agent-shell-session-strategy)
(defvar agent-shell-display-action)

(declare-function agent-shell--resolve-session-mode-name "agent-shell")
(declare-function agent-shell--start "agent-shell")
(declare-function agent-shell--format-buffer-name "agent-shell")
(declare-function agent-shell--display-buffer "agent-shell")
(declare-function shell-maker-busy "shell-maker")

;;;; Customization

(defgroup agent-shell-interface nil
  "Session management sidebar for agent-shell."
  :group 'agent-shell
  :prefix "agent-shell-interface-")

(defcustom agent-shell-interface-position 'right
  "Position of the sidebar window.
Valid values are `left' or `right'."
  :type '(choice (const :tag "Left" left)
                 (const :tag "Right" right))
  :group 'agent-shell-interface)

(defcustom agent-shell-interface-width "30%"
  "Width of the sidebar window.
Can be an integer (absolute columns) or a string with % suffix
for percentage of frame width."
  :type '(choice (integer :tag "Absolute width in columns")
                 (string :tag "Percentage of frame width (e.g., \"30%\")"))
  :group 'agent-shell-interface)

(defcustom agent-shell-interface-minimum-width 40
  "Minimum width of the sidebar in columns.
Applied after calculating the configured width."
  :type 'integer
  :group 'agent-shell-interface)

(defcustom agent-shell-interface-maximum-width "50%"
  "Maximum width of the sidebar.
Can be an integer (columns) or a string with % suffix.
When minimum > maximum, minimum takes precedence."
  :type '(choice (integer :tag "Absolute width in columns")
                 (string :tag "Percentage of frame width (e.g., \"50%\")"))
  :group 'agent-shell-interface)

(defcustom agent-shell-interface-refresh-interval 2
  "Interval in seconds for auto-refreshing the sidebar.
Set to 0 or nil to disable timer-based refresh."
  :type 'number
  :group 'agent-shell-interface)

;;;; Internal variables

(defconst agent-shell-interface--buffer-name "*Agent-Shell Sessions*"
  "Name of the sidebar buffer.")

(defvar-local agent-shell-interface--refresh-timer nil
  "Timer for auto-refreshing the sidebar.")

(defvar-local agent-shell-interface--folded-projects nil
  "Alist of (PROJECT-ROOT . t) for projects whose sessions are folded.")

(defvar-local agent-shell-interface--project-overlays nil
  "Alist of (PROJECT-ROOT . (START-POS . END-POS)) for foldable regions.")

(defvar agent-shell-interface--last-window nil
  "Last selected window before entering sidebar.")

;;;; Width calculation

(defun agent-shell-interface--parse-width-value (value frame-width)
  "Parse width VALUE into absolute columns.
VALUE can be an integer or a string ending in % (percentage of FRAME-WIDTH)."
  (cond
   ((integerp value) value)
   ((and (stringp value) (string-suffix-p "%" value))
    (let* ((pct-str (substring value 0 -1))
           (pct (string-to-number pct-str)))
      (if (and (numberp pct) (> pct 0))
          (round (* frame-width (/ pct 100.0)))
        (error "Invalid percentage value: %s" value))))
   (t (error "Width value must be an integer or percentage string: %s" value))))

(defun agent-shell-interface--calculate-width ()
  "Calculate the sidebar width in columns.
Applies minimum and maximum constraints to the configured width."
  (let* ((frame-width (frame-width))
         (configured (agent-shell-interface--parse-width-value
                      agent-shell-interface-width frame-width))
         (min-width (agent-shell-interface--parse-width-value
                     agent-shell-interface-minimum-width frame-width))
         (max-width (agent-shell-interface--parse-width-value
                     agent-shell-interface-maximum-width frame-width)))
    (cond
     ((> min-width max-width) min-width)
     (t (max min-width (min configured max-width))))))

;;;; Buffer and window management

(defun agent-shell-interface--get-buffer ()
  "Get or create the sidebar buffer."
  (let ((buf (get-buffer agent-shell-interface--buffer-name)))
    (if buf
        buf
      (let ((new-buf (get-buffer-create agent-shell-interface--buffer-name)))
        (with-current-buffer new-buf
          (agent-shell-interface-mode))
        new-buf))))

(defun agent-shell-interface--get-window ()
  "Get the window displaying the sidebar buffer, if any."
  (let ((buf (get-buffer agent-shell-interface--buffer-name)))
    (when (and buf (buffer-live-p buf))
      (get-buffer-window buf))))

(defun agent-shell-interface--buffer-p (&optional buffer)
  "Return non-nil if BUFFER is the sidebar buffer.
If BUFFER is nil, check `current-buffer'."
  (with-current-buffer (or buffer (current-buffer))
    (derived-mode-p 'agent-shell-interface-mode)))

(defun agent-shell-interface--non-sidebar-window ()
  "Find the most recently used non-sidebar window."
  (or
   (when (and agent-shell-interface--last-window
              (window-live-p agent-shell-interface--last-window)
              (not (agent-shell-interface--buffer-p
                    (window-buffer agent-shell-interface--last-window))))
     agent-shell-interface--last-window)
   (let ((mru (get-mru-window (selected-frame) nil :not-selected)))
     (if (and mru (not (agent-shell-interface--buffer-p (window-buffer mru))))
         mru
       (get-window-with-predicate
        (lambda (w) (not (agent-shell-interface--buffer-p (window-buffer w))))
        nil nil)))))

;;;; Status detection

(defun agent-shell-interface--get-status (buffer)
  "Determine the status of agent-shell BUFFER.
Returns one of: `ready', `working', `waiting', `initializing', `killed'."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (if (not (derived-mode-p 'agent-shell-mode))
          'killed
        (let* ((state agent-shell--state)
               (comint-proc (get-buffer-process (current-buffer)))
               (comint-alive (and comint-proc
                                  (processp comint-proc)
                                  (memq (process-status comint-proc)
                                        '(run open listen connect stop))))
               (acp-proc (when (map-elt state :client)
                           (map-nested-elt state '(:client :process))))
               (acp-alive (and acp-proc
                               (processp acp-proc)
                               (memq (process-status acp-proc)
                                     '(run open listen connect stop))))
               (process-alive (and comint-alive acp-alive)))
          (cond
           ((or (not comint-proc)
                (and (processp comint-proc) (not comint-alive)))
            'killed)
           ((and (map-elt state :client)
                 (or (not acp-proc)
                     (and (processp acp-proc) (not acp-alive))))
            'killed)
           ((and process-alive
                 (map-elt state :tool-calls)
                 (> (length (map-elt state :tool-calls)) 0))
            (let ((has-pending
                   (seq-find
                    (lambda (tc)
                      (map-elt (cdr tc) :permission-request-id))
                    (map-elt state :tool-calls))))
              (if has-pending 'waiting 'working)))
           ((and process-alive
                 (fboundp 'shell-maker-busy)
                 (shell-maker-busy))
            'working)
           ((and process-alive
                 (map-nested-elt state '(:session :id)))
            'ready)
           ((not (map-elt state :initialized))
            'initializing)
           (t 'unknown)))))))

(defun agent-shell-interface--format-status (status)
  "Return a propertized status string for STATUS symbol."
  (pcase status
    ('ready
     (propertize "●" 'face 'success
                 'font-lock-face 'success))
    ('working
     (propertize "◐" 'face 'warning
                 'font-lock-face 'warning))
    ('waiting
     (propertize "◆" 'face 'font-lock-keyword-face
                 'font-lock-face 'font-lock-keyword-face))
    ('initializing
     (propertize "○" 'face 'font-lock-comment-face
                 'font-lock-face 'font-lock-comment-face))
    ('killed
     (propertize "✕" 'face 'error
                 'font-lock-face 'error))
    (_
     (propertize "?" 'face 'font-lock-comment-face
                 'font-lock-face 'font-lock-comment-face))))

(defun agent-shell-interface--status-priority (status)
  "Return a numeric priority for STATUS, for sorting.
Lower = more important (shown first)."
  (pcase status
    ('waiting 0)
    ('working 1)
    ('initializing 2)
    ('ready 3)
    ('killed 4)
    (_ 5)))

;;;; Session enumeration and grouping

(defun agent-shell-interface--group-by-project ()
  "Return an alist of (PROJECT-ROOT . BUFFER-LIST) from agent-shell buffers."
  (let ((buffers (agent-shell-buffers))
        (groups (make-hash-table :test 'equal)))
    (dolist (buf buffers)
      (when (buffer-live-p buf)
        (let* ((project-root (with-current-buffer buf (agent-shell-cwd)))
               (existing (gethash project-root groups)))
          (puthash project-root
                   (if existing (append existing (list buf)) (list buf))
                   groups))))
    (let (result)
      (maphash
       (lambda (root bufs)
         (push (cons root bufs) result))
       groups)
      (sort result
            (lambda (a b)
              (string<
               (file-name-nondirectory (directory-file-name (car a)))
               (file-name-nondirectory (directory-file-name (car b)))))))))

(defun agent-shell-interface--get-agent-name (buffer)
  "Get the agent display name for BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((config (agent-shell-get-config buffer)))
        (or (and config (map-elt config :mode-line-name))
            (and config (map-elt config :buffer-name))
            (replace-regexp-in-string " Agent @.*$" ""
                                      (buffer-name buffer)))))))

(defun agent-shell-interface--get-session-mode (buffer)
  "Get the session mode name for BUFFER, or nil if not available."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (map-nested-elt agent-shell--state '(:session :mode-id))
        (condition-case nil
            (agent-shell--resolve-session-mode-name
             (map-nested-elt agent-shell--state '(:session :mode-id))
             (map-nested-elt agent-shell--state '(:session :modes)))
          (error nil))))))

(defun agent-shell-interface--session-label (buffer)
  "Format a session label string for BUFFER.
Includes status indicator, agent name, and optional mode."
  (let* ((status (agent-shell-interface--get-status buffer))
         (status-str (agent-shell-interface--format-status status))
         (name (or (agent-shell-interface--get-agent-name buffer) "?"))
         (mode (agent-shell-interface--get-session-mode buffer))
         (label (if mode
                    (format "%s %s [%s]" status-str name mode)
                  (format "%s %s" status-str name))))
    (propertize label 'agent-shell-interface-session-buffer buffer)))

;;;; Rendering

(defun agent-shell-interface--render ()
  "Clear and redraw the sidebar buffer content."
  (let* ((inhibit-read-only t)
         (groups (agent-shell-interface--group-by-project))
         (point-pos (point))
         (prev-folded (when (derived-mode-p 'agent-shell-interface-mode)
                        agent-shell-interface--folded-projects)))
    (erase-buffer)
    (setq agent-shell-interface--project-overlays nil)

    ;; Help section
    (insert (propertize " Agent Shell Sessions\n" 'face 'bold))
    (insert (propertize
             (concat " RET:goto  k:kill  c:new  r:restart\n"
                     " m:mode  M:model  g:refresh  q:quit\n"
                     " SPC:fold  n/p:nav  TAB/S-TAB:project\n\n")
             'face 'font-lock-comment-face))

    (if (not groups)
        (insert (propertize " No active sessions\n"
                            'face 'font-lock-comment-face))
      (dolist (group groups)
        (let* ((project-root (car group))
               (buffers (cdr group))
               (project-name (file-name-nondirectory
                              (directory-file-name project-root)))
               (project-path (abbreviate-file-name project-root))
               (folded (assoc project-root prev-folded))
               (sorted-buffers
                (sort buffers
                      (lambda (a b)
                        (< (agent-shell-interface--status-priority
                            (agent-shell-interface--get-status a))
                           (agent-shell-interface--status-priority
                            (agent-shell-interface--get-status b)))))))

          ;; Project heading
          (let ((heading-start (point)))
            (insert
             (propertize
              (concat "\302\257 " project-name)
              'face 'font-lock-function-name-face
              'font-lock-face 'font-lock-function-name-face
              'agent-shell-interface-project-root project-root
              'agent-shell-interface-heading t
              'keymap
              (let ((kmap (make-sparse-keymap)))
                (define-key kmap [mouse-1]
                            #'agent-shell-interface--mouse-toggle-fold)
                (define-key kmap (kbd "RET")
                            #'agent-shell-interface--heading-toggle-fold)
                kmap)
              'mouse-face 'highlight
              'help-echo "Click to fold/unfold"))
            (insert
             (propertize
              (concat "  " project-path "\n")
              'face 'font-lock-comment-face
              'font-lock-face 'font-lock-comment-face))
            (add-text-properties
             heading-start (point)
             (list 'agent-shell-interface-project-root project-root)))

          ;; Session entries
          (let ((entries-start (point)))
            (if folded
                (insert (propertize "  ...\n"
                                    'face 'font-lock-comment-face))
              (dolist (buf sorted-buffers)
                (when (buffer-live-p buf)
                  (let* ((label (agent-shell-interface--session-label buf))
                         (line-start (point)))
                    (insert "  ")
                    (insert label)
                    (let ((status (agent-shell-interface--get-status buf)))
                      (when (eq status 'killed)
                        (add-text-properties
                         line-start (point)
                         (list 'face 'font-lock-comment-face
                               'font-lock-face 'font-lock-comment-face))))
                    (insert "\n")))))
            (push (cons project-root (cons entries-start (point)))
                  agent-shell-interface--project-overlays)))))

    ;; Restore fold state
    (setq agent-shell-interface--folded-projects prev-folded)

    ;; Restore point (roughly)
    (goto-char (min point-pos (point-max)))))

(defun agent-shell-interface--toggle-fold (project-root)
  "Toggle the fold state for PROJECT-ROOT."
  (if (assoc project-root agent-shell-interface--folded-projects)
      (setq agent-shell-interface--folded-projects
            (assoc-delete-all project-root agent-shell-interface--folded-projects))
    (push (cons project-root t) agent-shell-interface--folded-projects))
  (agent-shell-interface--render))

(defun agent-shell-interface--mouse-toggle-fold (event)
  "Toggle fold on mouse click EVENT."
  (interactive "e")
  (let ((pos (posn-point (event-start event))))
    (save-excursion
      (goto-char pos)
      (let ((project-root (get-text-property (point)
					     'agent-shell-interface-project-root)))
        (when project-root
          (agent-shell-interface--toggle-fold project-root))))))

(defun agent-shell-interface--heading-toggle-fold ()
  "Toggle fold on the project heading at point."
  (interactive)
  (let ((project-root (get-text-property (point)
					 'agent-shell-interface-project-root)))
    (when project-root
      (agent-shell-interface--toggle-fold project-root))))

;;;; Navigation

(defun agent-shell-interface--next-session-entry ()
  "Move point to the next session entry line.
Return the new point, or nil if none found."
  (let ((pos (next-single-property-change (point)
					  'agent-shell-interface-session-buffer)))
    (when pos
      (goto-char pos)
      (point))))

(defun agent-shell-interface--prev-session-entry ()
  "Move point to the previous session entry line.
Return the new point, or nil if none found."
  (let ((pos (previous-single-property-change (point)
					      'agent-shell-interface-session-buffer)))
    (when pos
      (goto-char (max (point-min) (1- pos)))
      (unless (get-text-property (point) 'agent-shell-interface-session-buffer)
        (let ((prev (previous-single-property-change (point)
						     'agent-shell-interface-session-buffer)))
          (when prev (goto-char (max (point-min) (1- prev)))))))))

(defun agent-shell-interface--next-project-heading ()
  "Move point to the next project heading."
  (let ((pos (next-single-property-change (point)
					  'agent-shell-interface-heading)))
    (when pos (goto-char pos))))

(defun agent-shell-interface--prev-project-heading ()
  "Move point to the previous project heading."
  (let ((pos (previous-single-property-change (point)
					      'agent-shell-interface-heading)))
    (when pos (goto-char (max (point-min) (1- pos))))))

(defun agent-shell-interface--session-buffer-at-point ()
  "Get the agent-shell buffer at point, or nil."
  (get-text-property (point) 'agent-shell-interface-session-buffer))

;;;; Interactive commands

(defun agent-shell-interface-goto ()
  "Switch to the agent-shell session at point."
  (interactive)
  (let ((buf (agent-shell-interface--session-buffer-at-point)))
    (unless buf (user-error "No session at point"))
    (unless (buffer-live-p buf) (user-error "Session buffer no longer exists"))
    (let ((existing-window (get-buffer-window buf t)))
      (cond
       (existing-window
        (select-window existing-window))
       (t
        (let ((target-window (agent-shell-interface--non-sidebar-window)))
          (if target-window
              (progn
                (set-window-buffer target-window buf)
                (select-window target-window))
            (agent-shell--display-buffer buf))))))))

(defun agent-shell-interface-kill ()
  "Kill the agent-shell session at point."
  (interactive)
  (let ((buf (agent-shell-interface--session-buffer-at-point)))
    (unless buf (user-error "No session at point"))
    (unless (buffer-live-p buf) (user-error "Session buffer no longer exists"))
    (when (yes-or-no-p (format "Kill session %s? " (buffer-name buf)))
      (with-current-buffer buf
        (when (and (boundp 'agent-shell--state)
                   (map-elt agent-shell--state :client)
                   (map-nested-elt agent-shell--state '(:client :process)))
          (let ((proc (map-nested-elt agent-shell--state '(:client :process))))
            (when (and proc (process-live-p proc))
              (kill-process proc))))
        (let ((comint-proc (get-buffer-process buf)))
          (when (and comint-proc (process-live-p comint-proc))
            (comint-send-eof))))
      (run-with-timer 0.3 nil #'agent-shell-interface-refresh))))

(defun agent-shell-interface-new ()
  "Start a new agent-shell session."
  (interactive)
  (let ((config (or agent-shell-preferred-agent-config
                    (agent-shell-select-config :prompt "Start new agent: "))))
    (when config
      (agent-shell--start :config config :no-focus nil :new-session t)
      (run-with-timer 0.5 nil #'agent-shell-interface-refresh))))

(defun agent-shell-interface-restart ()
  "Restart the agent-shell session at point with the same agent config."
  (interactive)
  (let ((buf (agent-shell-interface--session-buffer-at-point)))
    (unless buf (user-error "No session at point"))
    (unless (buffer-live-p buf) (user-error "Session buffer no longer exists"))
    (let ((config (agent-shell-get-config buf))
          (buf-name (buffer-name buf)))
      (when (yes-or-no-p (format "Restart session %s? " buf-name))
        (with-current-buffer buf
          (when (and (boundp 'agent-shell--state)
                     (map-elt agent-shell--state :client)
                     (map-nested-elt agent-shell--state '(:client :process)))
            (let ((proc (map-nested-elt agent-shell--state '(:client :process))))
              (when (and proc (process-live-p proc))
                (kill-process proc)))))
        (kill-buffer buf)
        (when config
          (agent-shell--start :config config :no-focus nil :new-session t))
        (run-with-timer 0.5 nil #'agent-shell-interface-refresh)))))

(defun agent-shell-interface-interrupt ()
  "Interrupt the agent-shell session at point."
  (interactive)
  (let ((buf (agent-shell-interface--session-buffer-at-point)))
    (unless buf (user-error "No session at point"))
    (unless (buffer-live-p buf) (user-error "Session buffer no longer exists"))
    (with-current-buffer buf
      (agent-shell-interrupt))
    (run-with-timer 0.1 nil #'agent-shell-interface-refresh)))

(defun agent-shell-interface-set-mode ()
  "Set session mode for the agent-shell at point."
  (interactive)
  (let ((buf (agent-shell-interface--session-buffer-at-point)))
    (unless buf (user-error "No session at point"))
    (unless (buffer-live-p buf) (user-error "Session buffer no longer exists"))
    (with-current-buffer buf
      (agent-shell-set-session-mode))
    (run-with-timer 0.1 nil #'agent-shell-interface-refresh)))

(defun agent-shell-interface-set-model ()
  "Set session model for the agent-shell at point."
  (interactive)
  (let ((buf (agent-shell-interface--session-buffer-at-point)))
    (unless buf (user-error "No session at point"))
    (unless (buffer-live-p buf) (user-error "Session buffer no longer exists"))
    (with-current-buffer buf
      (agent-shell-set-session-model))
    (run-with-timer 0.1 nil #'agent-shell-interface-refresh)))

;;;; Auto-refresh

(defun agent-shell-interface-refresh ()
  "Refresh the sidebar content."
  (interactive)
  (let ((buf (get-buffer agent-shell-interface--buffer-name)))
    (when (and buf (buffer-live-p buf))
      (with-current-buffer buf
        (agent-shell-interface--render)))))

(defun agent-shell-interface--maybe-refresh ()
  "Refresh sidebar if visible."
  (when (agent-shell-interface--get-window)
    (agent-shell-interface-refresh)))

(defun agent-shell-interface--start-timer ()
  "Start the auto-refresh timer if configured."
  (when (and agent-shell-interface-refresh-interval
             (> agent-shell-interface-refresh-interval 0))
    (setq agent-shell-interface--refresh-timer
          (run-with-timer agent-shell-interface-refresh-interval
                          agent-shell-interface-refresh-interval
                          #'agent-shell-interface--maybe-refresh))))

(defun agent-shell-interface--stop-timer ()
  "Stop the auto-refresh timer."
  (when agent-shell-interface--refresh-timer
    (cancel-timer agent-shell-interface--refresh-timer)
    (setq agent-shell-interface--refresh-timer nil)))

(defun agent-shell-interface--on-event (_event)
  "Callback for agent-shell events triggering a sidebar refresh."
  (agent-shell-interface--maybe-refresh))

(defun agent-shell-interface--subscribe-events ()
  "Subscribe to agent-shell events in all live sessions."
  (dolist (buf (agent-shell-buffers))
    (when (buffer-live-p buf)
      (condition-case nil
          (with-current-buffer buf
            (agent-shell-subscribe-to
             :shell-buffer buf
             :on-event #'agent-shell-interface--on-event))
        (error nil)))))

;;;; Toggle commands

;;;###autoload
(defun agent-shell-interface-toggle ()
  "Toggle the agent-shell session management sidebar.
When visible, hide it.  When hidden, show it."
  (interactive)
  (let ((window (agent-shell-interface--get-window)))
    (if window
        (progn
          (delete-window window)
          (agent-shell-interface--restore-last-window))
      (agent-shell-interface--save-last-window)
      (let* ((buf (agent-shell-interface--get-buffer))
             (win (display-buffer-in-side-window
                   buf
                   `((side . ,agent-shell-interface-position)
                     (slot . 0)
                     (window-width . ,(agent-shell-interface--calculate-width))
                     (dedicated . t)
                     (window-parameters . ((no-delete-other-windows . t)))))))
        (set-window-dedicated-p win t)
        (select-window win)
        (agent-shell-interface-refresh)
        (agent-shell-interface--subscribe-events)))))

;;;###autoload
(defun agent-shell-interface-toggle-focus ()
  "Toggle focus between sidebar and the last non-sidebar window."
  (interactive)
  (if (agent-shell-interface--buffer-p)
      (agent-shell-interface--restore-last-window)
    (agent-shell-interface--save-last-window)
    (let ((sidebar-win (agent-shell-interface--get-window)))
      (if sidebar-win
          (select-window sidebar-win)
        (agent-shell-interface-toggle)))))

(defun agent-shell-interface--save-last-window ()
  "Save the currently selected window if it is not the sidebar."
  (unless (agent-shell-interface--buffer-p)
    (setq agent-shell-interface--last-window (selected-window))))

(defun agent-shell-interface--restore-last-window ()
  "Restore focus to the last non-sidebar window."
  (let ((target (agent-shell-interface--non-sidebar-window)))
    (when target (select-window target))))

;;;; Major mode

(defvar agent-shell-interface-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'agent-shell-interface-goto)
    (define-key map (kbd "n") #'agent-shell-interface-next-session)
    (define-key map (kbd "p") #'agent-shell-interface-prev-session)
    (define-key map (kbd "TAB") #'agent-shell-interface-next-project)
    (define-key map (kbd "<tab>") #'agent-shell-interface-next-project)
    (define-key map (kbd "S-TAB") #'agent-shell-interface-prev-project)
    (define-key map (kbd "<backtab>") #'agent-shell-interface-prev-project)
    (define-key map (kbd "SPC") #'agent-shell-interface-fold-toggle)
    (define-key map (kbd "k") #'agent-shell-interface-kill)
    (define-key map (kbd "c") #'agent-shell-interface-new)
    (define-key map (kbd "r") #'agent-shell-interface-restart)
    (define-key map (kbd "C-c C-c") #'agent-shell-interface-interrupt)
    (define-key map (kbd "m") #'agent-shell-interface-set-mode)
    (define-key map (kbd "M") #'agent-shell-interface-set-model)
    (define-key map (kbd "g") #'agent-shell-interface-refresh)
    (define-key map (kbd "q") #'agent-shell-interface-quit)
    map)
  "Keymap for `agent-shell-interface-mode'.")

(define-derived-mode agent-shell-interface-mode fundamental-mode "AS-Interface"
  "Major mode for the agent-shell session management sidebar.

Key bindings:
\\{agent-shell-interface-mode-map}"
  :group 'agent-shell-interface
  (setq buffer-read-only t)
  (setq-local truncate-lines t)
  (setq-local word-wrap nil)
  (hl-line-mode 1)
  (agent-shell-interface--start-timer)
  (add-hook 'kill-buffer-hook #'agent-shell-interface--stop-timer nil t)
  (agent-shell-interface--render))

;;;; Movement commands

(defun agent-shell-interface-next-session ()
  "Move to the next session entry."
  (interactive)
  (unless (agent-shell-interface--next-session-entry)
    (message "No next session")))

(defun agent-shell-interface-prev-session ()
  "Move to the previous session entry."
  (interactive)
  (unless (agent-shell-interface--prev-session-entry)
    (message "No previous session")))

(defun agent-shell-interface-next-project ()
  "Move to the next project heading."
  (interactive)
  (unless (agent-shell-interface--next-project-heading)
    (message "No next project")))

(defun agent-shell-interface-prev-project ()
  "Move to the previous project heading."
  (interactive)
  (unless (agent-shell-interface--prev-project-heading)
    (message "No previous project")))

(defun agent-shell-interface-fold-toggle ()
  "Toggle fold on the project at point."
  (interactive)
  (let ((project-root (get-text-property (point)
					 'agent-shell-interface-project-root)))
    (if project-root
        (agent-shell-interface--toggle-fold project-root)
      (message "Not on a project heading"))))

(defun agent-shell-interface-quit ()
  "Quit the sidebar window."
  (interactive)
  (let ((win (agent-shell-interface--get-window)))
    (when win
      (delete-window win)
      (agent-shell-interface--restore-last-window))))

;;;; Integration with golden-ratio-mode

(with-eval-after-load 'golden-ratio
  (when (boundp 'golden-ratio-exclude-modes)
    (add-to-list 'golden-ratio-exclude-modes 'agent-shell-interface-mode)))

(provide 'agent-shell-interface)
;;; agent-shell-interface.el ends here
