;;; terminal-config.el -*- lexical-binding: t; -*-

;; Fullscreen plain/tmux clients share a frame; Doom's other terminals are independent.
(defvar-local my-terminal-popup-buffer nil
  "Non-nil in a terminal managed by either fullscreen terminal command.")

(defvar my-terminal-popup-padding 8
  "Inset in pixels on all four sides of the fullscreen terminal.")

(defvar my-terminal-tmux-program "tmux"
  "Tmux executable used for fullscreen project sessions.")

(defconst my-terminal-tmux-owner "doom-project-terminal-v1"
  "Ownership tag for sessions managed by this terminal feature.")

(defvar-local my-terminal-popup-project-root nil
  "Canonical project root associated with this fullscreen terminal.")

(defvar-local my-terminal-popup-tmux-id nil
  "Tmux session ID attached to this fullscreen terminal.")

(defvar-local my-ghostel-zoom-keys nil
  "Non-nil in Ghostel buffers with zoom shortcuts reserved for Emacs.")

(defvar my-ghostel-zoom-keymap
  (let ((map (make-sparse-keymap)))
    (dolist (key '("C-=" "C-+"))
      (define-key map (kbd key) #'text-scale-increase))
    (define-key map (kbd "C--") #'text-scale-decrease)
    (dolist (key '("s-=" "s-+"))
      (define-key map (kbd key) #'doom/increase-font-size))
    (define-key map (kbd "s--") #'doom/decrease-font-size)
    map)
  "Zoom keys reserved for Emacs in every Ghostel input mode.")

(defvar my-ghostel-zoom-keymap-alist
  `((my-ghostel-zoom-keys . ,my-ghostel-zoom-keymap))
  "Ghostel-only overrides ahead of its direct terminal input map.")

(after! ghostel
  (add-to-list 'emulation-mode-map-alists 'my-ghostel-zoom-keymap-alist))

(defvar-local my-terminal-popup-canvas-color nil
  "Application background currently used for the fullscreen frame's canvas.")

(defvar-local my-terminal-popup-canvas-tick nil
  "Buffer modification tick of the last terminal edge-colour update.")

(defun my--terminal-popup-extend-rows (fallback)
  "Extend row backgrounds to the right edge; return the dominant colour.
Use FALLBACK for cells without an explicit terminal background.  A status
bar's colour must not paint the surrounding fullscreen frame padding."
  (let ((background fallback)
        (counts (make-hash-table :test #'equal))
        (dominant fallback)
        (largest 0))
    (save-excursion
      (goto-char (or (ghostel--viewport-start) (point-min)))
      (with-silent-modifications
        (let ((inhibit-read-only t))
          (while (< (point) (point-max))
            (let* ((end (line-end-position))
                   ;; Empty rows must not reuse our previous newline face.
                   (face (and (> end (point))
                              (get-text-property (1- end) 'face))))
              (setq background
                    (or (and (listp face)
                             (plist-get face (if (plist-get face :inverse-video)
                                                 :foreground :background)))
                        fallback))
              (puthash background (1+ (gethash background counts 0)) counts)
              (when (< end (point-max))
                (put-text-property end (1+ end) 'face
                                   `(:background ,background :extend t)))
              (forward-line 1))))))
    (maphash (lambda (color count)
               (when (> count largest)
                 (setq dominant color largest count)))
             counts)
    dominant))

(defun my--terminal-popup-set-background (frame parent color)
  "Use application COLOR for FRAME's canvas and insets.
With nil COLOR, restore the corresponding face colours from PARENT."
  (dolist (face '(default solaire-default-face fringe solaire-fringe-face
                 internal-border child-frame-border))
    (when (facep face)
      (let ((background
             (or color
                 (face-background
                  (if (memq face '(internal-border child-frame-border))
                      (if (memq 'solaire-default-face
                                (cdr (assq 'default face-remapping-alist)))
                          'solaire-default-face 'default)
                    face)
                  parent t))))
        (unless (equal background (face-background face frame t))
          (set-face-background face background frame))))))

(defun my--terminal-popup-fill-canvas (buffer)
  "Extend BUFFER's application backgrounds over unused fullscreen pixels."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and my-terminal-popup-buffer ghostel--term
                 (not ghostel--pending-redraw))
        (dolist (window (get-buffer-window-list buffer nil t))
          (let* ((frame (window-frame window))
                 (parent (frame-parameter frame 'parent-frame)))
            (when (and (frame-parameter frame 'my--terminal-popup)
                       (frame-live-p parent))
              ;; Buffer pickers can replace the root buffer without reopening
              ;; the popup, resetting its window-local fringe widths.
              (unless (equal (seq-take (window-fringes window) 2) '(0 0))
                (set-window-fringes window 0 0)
                (ghostel--adjust-size window))
              (if (not (ghostel-alt-screen-p))
                  (setq my-terminal-popup-canvas-color nil
                        my-terminal-popup-canvas-tick nil)
                (unless (equal my-terminal-popup-canvas-tick (buffer-modified-tick))
                  (let ((fallback (face-background
                                    (if (memq 'solaire-default-face
                                              (cdr (assq 'default face-remapping-alist)))
                                        'solaire-default-face 'default)
                                    parent t)))
                    (setq my-terminal-popup-canvas-color
                          (my--terminal-popup-extend-rows fallback)
                          my-terminal-popup-canvas-tick (buffer-modified-tick)))))
              ;; Apply per frame even when the shared buffer did not change:
              ;; a theme update or another terminal may have changed its faces.
              (my--terminal-popup-set-background
               frame parent my-terminal-popup-canvas-color))))))))

(defvar-local my-ghostel-saved-input nil
  "Shell input settings saved while an alternate-screen application runs.")

(defvar-local my-ghostel-shell-redraw-timer nil
  "Pending redraw recovery after returning from an alternate-screen app.")

(defun my--ghostel-cancel-redraw-h ()
  "Cancel this Ghostel buffer's pending shell redraw recovery."
  (when (timerp my-ghostel-shell-redraw-timer)
    (cancel-timer my-ghostel-shell-redraw-timer)
    (setq my-ghostel-shell-redraw-timer nil)))

(defun my--ghostel-setup-h ()
  "Enable shared input handling and zoom shortcuts in every Ghostel terminal."
  (setq-local my-ghostel-zoom-keys t)
  (add-hook 'kill-buffer-hook #'my--ghostel-cancel-redraw-h nil t))

(add-hook 'ghostel-mode-hook #'my--ghostel-setup-h)

(defun my--ghostel-redraw-shell-h (buffer)
  "Recover BUFFER's shell if an app left synchronized output enabled."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq my-ghostel-shell-redraw-timer nil)
      (when (and (derived-mode-p 'ghostel-mode)
                 ghostel--term (not (ghostel-alt-screen-p)))
        ;; A detached tmux client can leave DEC 2026 set in the emulator.
        ;; Clear it locally, not by sending input to the shell. Defer until
        ;; outside the native output callback and its final screen changes.
        (when (ghostel--mode-enabled ghostel--term 2026)
          (ghostel--write-vt ghostel--term "\e[?2026l"))
        (ghostel--redraw-now buffer t)))))

(defun my--ghostel-sync-input (buffer)
  "Suspend Evil in Ghostel BUFFER's alternate screen; restore it at the shell."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and (derived-mode-p 'ghostel-mode) ghostel--term)
        (cond
         ((ghostel-alt-screen-p)
          (my--ghostel-cancel-redraw-h)
          ;; Save first: changing input mode can trigger another redraw.
          (unless my-ghostel-saved-input
            (setq my-ghostel-saved-input
                  (list (bound-and-true-p evil-local-mode)
                        (bound-and-true-p evil-ghostel-mode)
                        (and (boundp 'evil-state) evil-state)
                        ghostel--input-mode)))
          (when (bound-and-true-p evil-ghostel-mode) (evil-ghostel-mode -1))
          (when (bound-and-true-p evil-local-mode) (evil-local-mode -1))
          (unless (eq ghostel--input-mode 'char) (ghostel-char-mode))
          (ghostel--apply-cursor-style))
         ((and (not (ghostel-alt-screen-p)) my-ghostel-saved-input)
          (pcase-let ((`(,evil ,integration ,state ,input)
                       my-ghostel-saved-input))
            (setq my-ghostel-saved-input nil)
            (pcase input
              ('char (ghostel-char-mode))
              ('copy (ghostel-copy-mode))
              ('emacs (ghostel-emacs-mode))
              ('line (ghostel-line-mode))
              (_ (ghostel-semi-char-mode)))
            (when evil (evil-local-mode 1))
            (when (and integration (not (bound-and-true-p evil-ghostel-mode)))
              (evil-ghostel-mode 1))
            (when evil
              (evil-normalize-keymaps)
              (when state (evil-change-state state)))
            (setq my-ghostel-shell-redraw-timer
                  (run-with-timer 0.1 nil #'my--ghostel-redraw-shell-h
                                  buffer)))))))))

(defvar-local my-ghostel-refreshing nil
  "Non-nil while updating terminal input and canvas after a redraw.")

(defun my--ghostel-after-redraw-a (buffer &rest _)
  "Update Ghostel BUFFER's input mode and any fullscreen popup canvas."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and (derived-mode-p 'ghostel-mode) (not my-ghostel-refreshing))
        ;; Input transitions may request another synchronous Ghostel redraw.
        (let ((my-ghostel-refreshing t))
          (my--ghostel-sync-input buffer)
          (my--terminal-popup-fill-canvas buffer))))))

(after! ghostel
  (advice-add 'ghostel--redraw-now :after #'my--ghostel-after-redraw-a))

(defvar consult-buffer-filter)

(defun my--terminal-popup-filter-workspace-buffers-a (original &rest args)
  "Omit floating terminals only while reading the workspace buffer picker."
  (require 'consult)
  (let ((consult-buffer-filter
         (cons "\\`\\*Floating Ghostel:" consult-buffer-filter)))
    (apply original args)))

(advice-add '+vertico/switch-workspace-buffer :around
            #'my--terminal-popup-filter-workspace-buffers-a)

(defun my--terminal-popup-hide (frame)
  "Hide terminal FRAME without stopping its shell, and return to its parent."
  (let ((parent (frame-parameter frame 'parent-frame))
        (window (frame-parameter frame 'my--terminal-return-window)))
    (make-frame-invisible frame t)
    (when (frame-live-p parent)
      (select-frame-set-input-focus parent)
      (when (window-live-p window)
        (select-window window)))))

(defun my--terminal-popup-buffer-killed-h ()
  "Hide any floating frame displaying this terminal when its shell exits."
  (dolist (frame (frame-list))
    (when (and (frame-parameter frame 'my--terminal-popup)
               (eq (window-buffer (frame-root-window frame)) (current-buffer)))
      (my--terminal-popup-hide frame))))

(defun my--terminal-popup-resize-h (parent)
  "Fill PARENT with its floating terminal frame."
  (let ((frame (frame-parameter parent 'my--terminal-popup-frame)))
    (when (frame-live-p frame)
      ;; `set-frame-size' specifies the text area, excluding the inset.
      (let ((frame-resize-pixelwise t)
            (inset (* 2 my-terminal-popup-padding)))
        (set-frame-size frame
                        (max 1 (- (frame-pixel-width parent) inset))
                        (max 1 (- (frame-pixel-height parent) inset)) t))
      (set-frame-position frame 0 0))))

(defun my--terminal-popup-theme-h ()
  "Refresh terminal canvas colours after a theme change."
  (dolist (frame (frame-list))
    (when (frame-parameter frame 'my--terminal-popup)
      (with-current-buffer (window-buffer (frame-root-window frame))
        (setq my-terminal-popup-canvas-tick nil)
        (my--terminal-popup-fill-canvas (current-buffer))))))

(defun my--terminal-popup-no-padding-h (&rest _)
  "Exclude spacious-padding, retaining the terminal's uniform inset."
  (dolist (frame (frame-list))
    (when (frame-parameter frame 'my--terminal-popup)
      (modify-frame-parameters
       ;; Emacs Mac aliases the child border and internal inset widths.
       ;; Its border face is canvas-coloured, so this adds no visible line.
       frame `((child-frame-border-width . ,(if (eq (window-system frame) 'mac)
                                               my-terminal-popup-padding 0))
               (internal-border-width . ,my-terminal-popup-padding)
               (left-fringe . 0) (right-fringe . 0)
               (right-divider-width . 0) (bottom-divider-width . 0)
               (scroll-bar-width . 0)))
      (dolist (window (window-list frame 'no-minibuffer))
        (set-window-fringes window 0 0)
        (set-window-margins window 0 0))
      (dolist (face '(mode-line mode-line-active mode-line-inactive
                     header-line tab-line tab-bar))
        (when (facep face) (set-face-attribute face frame :box nil)))
      (my--terminal-popup-fill-canvas (window-buffer (frame-root-window frame))))))

;; Spacious-padding is global. Reapply the frame-local exception after its
;; layout and face updates, including toggling the mode or changing themes.
(after! spacious-padding
  (advice-add 'spacious-padding-modify-frame-parameters :after
              #'my--terminal-popup-no-padding-h)
  (advice-add 'spacious-padding-set-faces :after
              #'my--terminal-popup-no-padding-h))

(defun my--terminal-popup-frame (parent)
  "Return or create PARENT's floating terminal frame."
  (or (let ((frame (frame-parameter parent 'my--terminal-popup-frame)))
        (and (frame-live-p frame) frame))
      (let ((frame (make-frame
                    `((parent-frame . ,parent)
                      (minibuffer . nil)
                      (name . "Project terminal")
                      (font . ,(frame-parameter parent 'font))
                      (undecorated . t)
                      (child-frame-border-width
                       . ,(if (eq (window-system parent) 'mac)
                              my-terminal-popup-padding 0))
                      (internal-border-width . ,my-terminal-popup-padding)
                      (left-fringe . 0)
                      (right-fringe . 0)
                      (right-divider-width . 0)
                      (bottom-divider-width . 0)
                      (menu-bar-lines . 0)
                      (tool-bar-lines . 0)
                      (tab-bar-lines . 0)
                      (vertical-scroll-bars . nil)
                      (horizontal-scroll-bars . nil)
                      (no-other-frame . t)
                      (skip-taskbar . t)
                      (unsplittable . t)
                      (my--terminal-popup . t)
                      (visibility . nil)))))
        (set-frame-parameter parent 'my--terminal-popup-frame frame)
        (my--terminal-popup-no-padding-h)
        (my--terminal-popup-resize-h parent)
        (my--terminal-popup-theme-h)
        frame)))

(defun my--terminal-tmux-run (program &rest arguments)
  "Run tmux PROGRAM with ARGUMENTS, returning (STATUS . OUTPUT)."
  (with-temp-buffer
    (let ((status (apply #'process-file program nil t nil arguments)))
      (cons status (string-remove-suffix "\n" (buffer-string))))))

(defun my--terminal-tmux-check (program &rest arguments)
  "Run tmux PROGRAM with ARGUMENTS or report its error."
  (let ((result (apply #'my--terminal-tmux-run program arguments)))
    (unless (eq (car result) 0)
      (user-error "tmux: %s" (cdr result)))
    (cdr result)))

(defun my--terminal-tmux-uuid ()
  "Generate a version-4 UUID for a managed tmux session."
  (let ((bytes (cl-loop repeat 16 collect (random 256))))
    (setf (nth 6 bytes) (logior #x40 (logand #x0f (nth 6 bytes)))
          (nth 8 bytes) (logior #x80 (logand #x3f (nth 8 bytes))))
    (apply #'format
           "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x"
           bytes)))

(defun my--terminal-tmux-sessions (program)
  "Return session metadata from local tmux PROGRAM as property lists."
  (let ((result (my--terminal-tmux-run
                 program "list-sessions" "-F"
                 (concat "#{session_id}\t#{session_name}\t#{@emacs-terminal-owner}\t"
                         "#{@emacs-terminal-uuid}\t#{@emacs-project-root}"))))
    (cond
     ((eq (car result) 0)
      (mapcar (lambda (line)
                (let ((fields (split-string line "\t" nil)))
                  (list :id (nth 0 fields) :name (nth 1 fields)
                        :owner (nth 2 fields) :uuid (nth 3 fields)
                        :root (mapconcat #'identity (nthcdr 4 fields) "\t"))))
              (split-string (cdr result) "\n" t)))
     ((string-match-p "no server running\\|No such file or directory" (cdr result)) nil)
     (t (user-error "tmux: %s" (cdr result))))))

(defun my--terminal-tmux-managed-p (session)
  "Return non-nil if SESSION has this feature's ownership, UUID and root."
  (and (equal (plist-get session :owner) my-terminal-tmux-owner)
       (string-match-p
        (rx string-start (= 8 xdigit) "-" (= 4 xdigit) "-4" (= 3 xdigit)
            "-" (any "89abAB") (= 3 xdigit) "-" (= 12 xdigit) string-end)
        (or (plist-get session :uuid) ""))
       (file-name-absolute-p (or (plist-get session :root) ""))))

(defun my--terminal-tmux-tag (program target root)
  "Record ownership and a new UUID on session TARGET for ROOT."
  (my--terminal-tmux-check program "set-option" "-t" target "@emacs-project-root" root)
  (my--terminal-tmux-check program "set-option" "-t" target "detach-on-destroy" "on")
  (my--terminal-tmux-check program "set-option" "-t" target
                           "@emacs-terminal-uuid" (my--terminal-tmux-uuid))
  ;; Write ownership last, so partially configured sessions are not removable.
  (my--terminal-tmux-check program "set-option" "-t" target
                           "@emacs-terminal-owner" my-terminal-tmux-owner))

(defun my--terminal-project-root ()
  "Return the canonical project root for the editor or fullscreen terminal."
  (let ((root (file-name-as-directory
               (or (and my-terminal-popup-buffer my-terminal-popup-project-root)
                   (doom-project-root) default-directory))))
    (if (file-remote-p root) root (file-truename root))))

(defun my--terminal-tmux-name (root sessions)
  "Choose a readable session name for ROOT, avoiding existing SESSIONS.
SESSIONS maps session names to their recorded project roots.  Add the
nearest differing parent directories when project names collide."
  (cl-labels ((suffix (path depth)
                (let* ((parts (or (split-string (directory-file-name path) "/" t)
                                  '("root")))
                       (name (mapconcat #'identity (last parts depth) "-")))
                  (concat "emacs-"
                          (replace-regexp-in-string "[^[:alnum:]_-]+" "-" name)))))
    (let ((depth 1)
          (limit (max 1 (length (split-string root "/" t))))
          name)
      (catch 'available
        (while (<= depth limit)
          (setq name (suffix root depth))
          (unless (or (assoc name sessions)
                      (seq-some
                       (lambda (session)
                         (and (string-prefix-p "emacs-" (car session))
                              (file-name-absolute-p (cdr session))
                              (equal name (suffix (cdr session) depth))))
                       sessions))
            (throw 'available name))
          (cl-incf depth))
        ;; Distinct paths can become identical after replacing punctuation.
        ;; Metadata keeps this rare numbered fallback stable on later visits.
        (let ((base name) (number 2))
          (while (assoc (setq name (format "%s-%d" base number)) sessions)
            (cl-incf number))
          name)))))

(defun my--terminal-tmux-session (root)
  "Find or create ROOT's local tmux session; return (PROGRAM NAME ID).
Reuse owned sessions by root, even if renamed.  Upgrade older emacs-prefixed
sessions that already record this exact root when explicitly reopened."
  (when (file-remote-p root)
    (user-error "Tmux project popups currently require a local project root"))
  (let ((program (executable-find my-terminal-tmux-program))
        (default-directory root)
        (process-environment (copy-sequence process-environment)))
    (unless program (user-error "Cannot find tmux executable: %s" my-terminal-tmux-program))
    (setenv "TMUX" nil)
    (setenv "TMUX_PANE" nil)
    (let* ((sessions (my--terminal-tmux-sessions program))
           (existing
            (or (seq-find (lambda (session)
                            (and (my--terminal-tmux-managed-p session)
                                 (equal root (plist-get session :root))))
                          sessions)
                (seq-find (lambda (session)
                            (and (string-prefix-p "emacs-" (plist-get session :name))
                                 (string-empty-p (plist-get session :owner))
                                 (string-empty-p (plist-get session :uuid))
                                 (equal root (plist-get session :root))))
                          sessions))))
      (if existing
          (progn
            (unless (my--terminal-tmux-managed-p existing)
              (my--terminal-tmux-tag program (plist-get existing :id) root))
            (list program (plist-get existing :name) (plist-get existing :id)))
        (let* ((names (mapcar (lambda (session)
                               (cons (plist-get session :name) (plist-get session :root)))
                             sessions))
               (name (my--terminal-tmux-name root names))
               (target (my--terminal-tmux-check program "new-session" "-d" "-P"
                                                "-F" "#{session_id}" "-s" name "-c" root)))
          (my--terminal-tmux-tag program target root)
          (list program name target))))))

(defun my--terminal-tmux-local-program ()
  "Return the local tmux executable, or report that it is unavailable."
  (or (executable-find my-terminal-tmux-program)
      (user-error "Cannot find tmux executable: %s" my-terminal-tmux-program)))

(defun my--terminal-tmux-reveal-editor ()
  "Hide a visible fullscreen terminal so lists and confirmations are visible."
  (let* ((selected (selected-frame))
         (parent (if (frame-parameter selected 'my--terminal-popup)
                     (frame-parameter selected 'parent-frame) selected))
         (popup (frame-parameter parent 'my--terminal-popup-frame)))
    (when (and (frame-live-p popup) (frame-visible-p popup))
      (my--terminal-popup-hide popup))))

(defun my--terminal-tmux-list-refresh-h (&rest _)
  "Refresh the table of locally managed tmux sessions."
  (let* ((default-directory (expand-file-name "~/"))
         (process-environment (copy-sequence process-environment))
         (_ (progn (setenv "TMUX" nil) (setenv "TMUX_PANE" nil)))
         (sessions (seq-filter #'my--terminal-tmux-managed-p
                               (my--terminal-tmux-sessions (my--terminal-tmux-local-program)))))
    (setq tabulated-list-entries
          (mapcar (lambda (session)
                    (list (plist-get session :uuid)
                          (vector (plist-get session :name)
                                  (plist-get session :root)
                                  (plist-get session :uuid))))
                  sessions))
    (tabulated-list-print t)))

(defun my/terminal-tmux-list ()
  "List this feature's managed tmux sessions on the local host.
Show their project roots and UUIDs in a bottom popup.
Press RET to open a session, g to refresh or q to quit.
Sessions without valid ownership and UUID metadata are excluded."
  (interactive)
  (require 'tabulated-list)
  (my--terminal-tmux-reveal-editor)
  (with-current-buffer (get-buffer-create "*Emacs tmux sessions*")
    (tabulated-list-mode)
    (use-local-map (copy-keymap (current-local-map)))
    (local-set-key (kbd "RET") #'my--terminal-tmux-open-session)
    (when (featurep 'evil)
      (dolist (state '(normal motion visual))
        (evil-local-set-key state (kbd "RET") #'my--terminal-tmux-open-session)))
    (setq tabulated-list-format [("Session" 30 t) ("Project root" 55 t) ("UUID" 36 t)]
          tabulated-list-sort-key '("Session" . nil))
    (setq-local revert-buffer-function #'my--terminal-tmux-list-refresh-h)
    (tabulated-list-init-header)
    (my--terminal-tmux-list-refresh-h)
    (pop-to-buffer (current-buffer))))

(defun my--terminal-tmux-open-session ()
  "Attach to the managed session at point in the fullscreen terminal.
Recheck its UUID before attaching.  A vanished session is not recreated."
  (interactive)
  (let* ((uuid (tabulated-list-get-id))
         (default-directory (expand-file-name "~/"))
         (process-environment (copy-sequence process-environment))
         (program (my--terminal-tmux-local-program)))
    (unless uuid (user-error "No session on this row"))
    (setenv "TMUX" nil)
    (setenv "TMUX_PANE" nil)
    (let ((session (seq-find
                    (lambda (entry)
                      (and (my--terminal-tmux-managed-p entry)
                           (equal uuid (plist-get entry :uuid))))
                    (my--terminal-tmux-sessions program))))
      (unless session
        (revert-buffer)
        (user-error "Session no longer exists; list refreshed"))
      ;; Close the list first so toggling back returns to the editor.
      (quit-window)
      (my--terminal-tmux-reveal-editor)
      (my--terminal-popup-toggle t (cons program session)))))

(defun my--terminal-tmux-kill-sessions (program sessions)
  "Confirm removal of owned SESSIONS through local tmux PROGRAM.
Revalidate each UUID after confirmation, and condition the kill on its
ownership and UUID inside tmux so reused session IDs cannot target others."
  (if (not sessions)
      (message "No managed tmux sessions found")
    (my--terminal-tmux-reveal-editor)
    (if (not (yes-or-no-p
              (format "Kill these tmux sessions and all their running programs: %s? "
                      (mapconcat (lambda (session) (plist-get session :name)) sessions ", "))))
        (message "Tmux cleanup cancelled")
      (let ((current (my--terminal-tmux-sessions program)))
        (dolist (session sessions)
          (let ((match (seq-find
                        (lambda (candidate)
                          (and (my--terminal-tmux-managed-p candidate)
                               (equal (plist-get candidate :uuid) (plist-get session :uuid))
                               (equal (plist-get candidate :root) (plist-get session :root))))
                        current)))
            (when match
              (let ((id (plist-get match :id)))
                (unless (string-match-p "\\`\\$[0-9]+\\'" id)
                  (user-error "Invalid tmux session ID: %s" id))
                (my--terminal-tmux-check
                 program "if-shell" "-F" "-t" id
                 (format "#{&&:#{==:#{@emacs-terminal-owner},%s},#{==:#{@emacs-terminal-uuid},%s}}"
                         my-terminal-tmux-owner (plist-get match :uuid))
                 (format "set-option -t '%s' detach-on-destroy on ; kill-session -t '%s'"
                         id id)
                 ""))))))
      (message "Managed tmux session cleanup finished"))))

(defun my/terminal-tmux-kill-project ()
  "Confirm and kill managed tmux sessions associated with the current project.
This terminates their shells and running programs.  Match the canonical
project root and recheck ownership and UUID before killing each session.
Only local projects are currently supported."
  (interactive)
  (let* ((root (my--terminal-project-root))
         (program (my--terminal-tmux-local-program)))
    (when (file-remote-p root)
      (user-error "Tmux project cleanup currently requires a local project root"))
    (let ((default-directory root)
          (process-environment (copy-sequence process-environment)))
      (setenv "TMUX" nil)
      (setenv "TMUX_PANE" nil)
      (my--terminal-tmux-kill-sessions
       program (seq-filter (lambda (session)
                             (and (my--terminal-tmux-managed-p session)
                                  (equal root (plist-get session :root))))
                           (my--terminal-tmux-sessions program))))))

(defun my/terminal-tmux-kill-all ()
  "Confirm and kill all UUID-tagged sessions managed by this feature locally.
The confirmation lists the affected names.  Their shells and running
programs terminate; other tmux sessions are excluded."
  (interactive)
  (let ((default-directory (expand-file-name "~/"))
        (program (my--terminal-tmux-local-program))
        (process-environment (copy-sequence process-environment)))
    (setenv "TMUX" nil)
    (setenv "TMUX_PANE" nil)
    (my--terminal-tmux-kill-sessions
     program (seq-filter #'my--terminal-tmux-managed-p
                         (my--terminal-tmux-sessions program)))))

(defun my--terminal-popup-open (name root floating &optional command)
  "Show persistent terminal NAME at ROOT, using FLOATING display when non-nil.
Optional COMMAND starts a dedicated process instead of the usual shell."
  (let* ((default-directory root)
         (ghostel-buffer-name name)
         (ghostel-buffer-name-function nil)
         (ghostel-shell (or command ghostel-shell))
         (ghostel-shell-integration (and (not command) ghostel-shell-integration))
         (ghostel-macos-login-shell (and (not command) ghostel-macos-login-shell))
         (process-environment (copy-sequence process-environment))
         ;; A floating shell must appear only in its child frame's root window.
         (display-buffer-overriding-action
          (when floating '(display-buffer-same-window)))
         (buffer (get-buffer name)))
    (when command
      (setenv "TMUX" nil)
      (setenv "TMUX_PANE" nil))
    (when (and buffer
               (not (with-current-buffer buffer (process-live-p ghostel--process))))
      (kill-buffer buffer))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer (display-line-numbers-mode -1)))
    (setq buffer (ghostel))
    (with-current-buffer buffer
      (setq-local my-terminal-popup-buffer t
                  my-terminal-popup-project-root root)
      (display-line-numbers-mode -1)
      (when (bound-and-true-p olivetti-mode) (olivetti-mode -1))
      ;; Switching buffers can reset window-local fringe widths.
      (when floating
        (my--terminal-popup-no-padding-h)
        (when-let ((window (get-buffer-window buffer (selected-frame))))
          (ghostel--adjust-size window)))
      (add-hook 'kill-buffer-hook #'my--terminal-popup-buffer-killed-h nil t)
      (my--ghostel-after-redraw-a buffer)
      ;; Avoid re-entering insert state before a new terminal has its cursor data.
      (when (and (bound-and-true-p evil-local-mode) (not (evil-insert-state-p)))
        (evil-insert-state)))
    buffer))

(defun my/terminal-popup-toggle ()
  "Toggle a persistent fullscreen Ghostel terminal for the current project.
Each project root and Doom workspace has its own shell.  Outside a project,
use the current directory.  Graphical Emacs displays a borderless child
frame with an 8-pixel inset; terminal Emacs uses a large bottom popup.

Calling this command from the terminal hides it and returns to the editor.
Hiding preserves its shell process, directory and environment.  Typing exit
or killing its buffer stops the shell instead.
SPC o t p is the leader-key alias for this command.  C-\" and
`my/terminal-tmux-toggle' provide the separate tmux-backed variant.
Either shortcut hides whichever fullscreen terminal is currently visible.
Use C-' to return to the editor before invoking minibuffer commands such
as M-x.  Doom's bottom popup and normal terminal use the standard minibuffer.

All Ghostel terminals suspend Evil and use direct input while an
alternate-screen application runs, including tmux, Neovim and Yazi.
The application controls its own cursor.  Returning to the shell restores
the previous Evil and input settings.  In the default shell input mode,
C-c C-c sends an interrupt; in direct input mode, a single C-c does so.

C-= or C-+ increases this buffer's text size; C-- decreases it.
On macOS, Command +/- retains Doom's global font zoom.  Zoom and this
terminal toggle remain available while an application has direct input.

The fullscreen terminal is omitted from the workspace buffer picker
(SPC b b) but remains available in the all-buffers picker (SPC b B).
For Doom's other terminal layouts, see `+ghostel/toggle' (SPC o t t) and
`+ghostel/here' (SPC o t T).  They share input and zoom handling but keep
their own shells and window layouts."
  (interactive)
  (my--terminal-popup-toggle))

(defun my/terminal-tmux-toggle ()
  "Toggle a fullscreen tmux terminal for the current local project.
Create an emacs-PROJECT session at the project root when needed, or attach
its existing session.  Full project roots, ownership and per-session UUIDs
are stored in tmux metadata; colliding names include differing parents.
Use `my/terminal-tmux-list' to inspect sessions, `my/terminal-tmux-kill-project'
to remove this project's session or `my/terminal-tmux-kill-all' for all
managed sessions.  Removal requires confirmation and terminates programs.

C-\" and SPC o t m invoke this command.  Either C-' or C-\" hides a visible
fullscreen terminal, keeping its process alive.  With the popup hidden,
C-' opens the independent plain shell and C-\" opens the tmux client.
Detaching closes the tmux client buffer; the session and its panes persist.
Projects in different Doom workspaces share their project tmux session.
For input, zoom and buffer-picker behaviour, see `my/terminal-popup-toggle'."
  (interactive)
  (my--terminal-popup-toggle t))

(defun my--terminal-popup-toggle (&optional tmux selected-session)
  "Hide a visible project terminal, or open the plain or TMUX variant.
SELECTED-SESSION is (PROGRAM . METADATA) for an explicitly selected session."
  (let* ((selected (selected-frame))
         (parent (if (frame-parameter selected 'my--terminal-popup)
                     (frame-parameter selected 'parent-frame) selected))
         (popup (frame-parameter parent 'my--terminal-popup-frame))
         (tty-popup (unless (display-graphic-p)
                      (seq-find (lambda (window)
                                  (and (+popup-window-p window)
                                       (buffer-local-value 'my-terminal-popup-buffer
                                                           (window-buffer window))))
                                (window-list nil 'no-minibuffer)))))
    (cond
     ((and (frame-live-p popup) (frame-visible-p popup))
      (my--terminal-popup-hide popup))
     (tty-popup (delete-window tty-popup))
     (t
      (require 'ghostel)
      (let* ((root (if selected-session
                       (plist-get (cdr selected-session) :root)
                     (my--terminal-project-root)))
             (workspace (if (bound-and-true-p persp-mode)
                            (safe-persp-name (get-current-persp)) "main"))
             (session (when tmux
                        (if selected-session
                            (list (car selected-session)
                                  (plist-get (cdr selected-session) :name)
                                  (plist-get (cdr selected-session) :id))
                          (my--terminal-tmux-session root))))
             (command (when session
                        (list (car session) "attach-session" "-t"
                              (nth 2 session))))
             ;; Preserve existing plain-shell names; tmux clients are separate.
             (name (format "*Floating Ghostel:%s%s:%s*"
                           (if tmux "tmux:" "")
                           (file-name-nondirectory (directory-file-name root))
                           (secure-hash 'sha1 (prin1-to-string (list root workspace))))))
        ;; Multiple owned sessions may share a root. Never reuse a client
        ;; attached to a different session when selecting a specific row.
        (when (and selected-session (get-buffer name)
                   (not (equal (buffer-local-value 'my-terminal-popup-tmux-id
                                                   (get-buffer name))
                               (nth 2 session))))
          (setq name (format "%s:%s*" (substring name 0 -1)
                             (plist-get (cdr selected-session) :uuid))))
        (if (display-graphic-p)
            (let* ((window (selected-window))
                   (frame (my--terminal-popup-frame parent)))
              (set-frame-parameter frame 'my--terminal-return-window window)
              (my--terminal-popup-resize-h parent)
              (condition-case err
                  (progn
                    ;; Do not redraw a fallback file buffer before its terminal.
                    (let ((inhibit-redisplay t))
                      (select-frame frame)
                      (with-current-buffer (my--terminal-popup-open name root t command)
                        (setq-local my-terminal-popup-tmux-id (nth 2 session))))
                    (make-frame-visible frame)
                    (select-frame-set-input-focus frame))
                (error
                 (my--terminal-popup-hide frame)
                 (signal (car err) (cdr err)))))
          (let ((window (get-buffer-window name)))
            (if window (select-window window)
              (with-current-buffer (my--terminal-popup-open name root nil command)
                (setq-local my-terminal-popup-tmux-id (nth 2 session)))))))))))

(map! "C-'" #'my/terminal-popup-toggle
      "C-\"" #'my/terminal-tmux-toggle
      :leader
      ;; Replace the flat terminal commands with a shared submenu.
      "o t" nil
      "o T" nil
      (:prefix ("o t" . "terminal")
       :desc "Toggle bottom terminal" "t" #'+ghostel/toggle
       :desc "Open terminal buffer" "T" #'+ghostel/here
       :desc "Toggle fullscreen project terminal" "p" #'my/terminal-popup-toggle
       :desc "Toggle project tmux terminal" "m" #'my/terminal-tmux-toggle))
(set-popup-rule! "^\\*Floating Ghostel:"
  :side 'bottom :size 0.9 :select t :quit nil :ttl nil :modeline nil)
(set-popup-rule! "^\\*Emacs tmux sessions\\*$"
  :side 'bottom :size 0.35 :select t :quit t :ttl nil)
(add-hook 'window-size-change-functions #'my--terminal-popup-resize-h)
(add-hook 'doom-load-theme-hook #'my--terminal-popup-theme-h)

;; Docker TRAMP processes may lack LOGNAME, which Ghostel's built-in login-shell
;; lookup uses. Query the effective user ID instead, without assuming a username
;; or that Zsh is installed. Keep the configured fallback and shell arguments.
(defun my--ghostel-docker-login-shell-a (original method)
  (if (and (equal method "docker")
           (equal (file-remote-p default-directory 'method) "docker")
           (eq (cadr (assoc method ghostel-tramp-shells)) 'login-shell))
      (let* ((spec (cdr (assoc method ghostel-tramp-shells)))
             (shell
              (ignore-errors
                (with-temp-buffer
                  (when (zerop (process-file "/bin/sh" nil t nil "-c"
                                             "getent passwd \"$(id -u)\""))
                    (let* ((entry (string-trim (buffer-string)))
                           (fields (split-string entry ":"))
                           (path (nth 6 fields)))
                      (when (and (= (length fields) 7)
                                 (file-name-absolute-p path)
                                 (file-executable-p
                                  (concat (file-remote-p default-directory) path)))
                        path)))))))
        (if shell
            (cons shell (cddr spec))
          (funcall original method)))
    (funcall original method)))

;; Docker terminals use the container user's login shell, falling back to sh.
(after! ghostel
  ;; Keep the shortcut available in terminal input modes as well as code buffers.
  (define-key ghostel-mode-map (kbd "C-'") #'my/terminal-popup-toggle)
  (define-key ghostel-char-mode-map (kbd "C-'") #'my/terminal-popup-toggle)
  (define-key ghostel-mode-map (kbd "C-\"") #'my/terminal-tmux-toggle)
  (define-key ghostel-char-mode-map (kbd "C-\"") #'my/terminal-tmux-toggle)
  ;; Emacs may inherit NO_COLOR from its launcher. Ghostel supports colours;
  ;; a bare environment entry unsets the variable for its shell processes.
  (add-to-list 'ghostel-environment "NO_COLOR")
  (setf (alist-get "docker" ghostel-tramp-shells nil nil #'equal)
        '(login-shell "/bin/sh"))
  (advice-add 'ghostel--tramp-shell-spec :around
              #'my--ghostel-docker-login-shell-a))

;; Keep the code/text column guide out of terminal buffers.
(defun my--hide-terminal-column-guide-h ()
  (display-fill-column-indicator-mode -1))

(add-hook 'ghostel-mode-hook #'my--hide-terminal-column-guide-h)
