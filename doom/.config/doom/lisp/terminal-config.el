;;; terminal-config.el -*- lexical-binding: t; -*-

;; This terminal has its own shell; Doom's SPC o t t and SPC o t T stay independent.
(defvar-local my-terminal-popup-buffer nil
  "Non-nil in a terminal managed by `my/terminal-popup-toggle'.")

(defvar my-terminal-popup-padding 8
  "Inset in pixels on all four sides of the fullscreen terminal.")

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
  "Extend row backgrounds to the right edge; return the last row's colour.
Use FALLBACK for cells without an explicit terminal background."
  (let ((background fallback))
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
              (when (< end (point-max))
                (put-text-property end (1+ end) 'face
                                   `(:background ,background :extend t)))
              (forward-line 1))))))
    background))

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

(defun my--terminal-popup-open (name root floating)
  "Show the persistent terminal NAME at ROOT, using FLOATING display when non-nil."
  (let* ((default-directory root)
         (ghostel-buffer-name name)
         (ghostel-buffer-name-function nil)
         ;; A floating shell must appear only in its child frame's root window.
         (display-buffer-overriding-action
          (when floating '(display-buffer-same-window)))
         (buffer (get-buffer name)))
    (when (and buffer
               (not (with-current-buffer buffer (process-live-p ghostel--process))))
      (kill-buffer buffer))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer (display-line-numbers-mode -1)))
    (setq buffer (ghostel))
    (with-current-buffer buffer
      (setq-local my-terminal-popup-buffer t)
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
SPC o t p is the leader-key alias for this command.
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
  (cond
   ((frame-parameter nil 'my--terminal-popup)
    (my--terminal-popup-hide (selected-frame)))
   ((and my-terminal-popup-buffer (+popup-window-p))
    (delete-window))
   (t
    (require 'ghostel)
    (let* ((root (file-name-as-directory (or (doom-project-root) default-directory)))
           (root (if (file-remote-p root) root (file-truename root)))
           (workspace (if (bound-and-true-p persp-mode)
                          (safe-persp-name (get-current-persp)) "main"))
           ;; Use the full root, so equally named projects get different shells.
           (name (format "*Floating Ghostel:%s:%s*"
                         (file-name-nondirectory (directory-file-name root))
                         (secure-hash 'sha1 (prin1-to-string (list root workspace))))))
      (if (display-graphic-p)
          (let* ((parent (selected-frame))
                 (window (selected-window))
                 (frame (my--terminal-popup-frame parent)))
            (set-frame-parameter frame 'my--terminal-return-window window)
            (my--terminal-popup-resize-h parent)
            (condition-case err
                (progn
                  ;; A hidden frame may hold a fallback file buffer after its
                  ;; terminal was killed. Do not display that buffer on entry.
                  (let ((inhibit-redisplay t))
                    (select-frame frame)
                    (my--terminal-popup-open name root t))
                  (make-frame-visible frame)
                  (select-frame-set-input-focus frame))
              (error
               (my--terminal-popup-hide frame)
               (signal (car err) (cdr err)))))
        (let ((window (get-buffer-window name)))
          (if window (select-window window)
            (my--terminal-popup-open name root nil))))))))

(map! "C-'" #'my/terminal-popup-toggle
      :leader
      ;; Replace the flat terminal commands with a shared submenu.
      "o t" nil
      "o T" nil
      (:prefix ("o t" . "terminal")
       :desc "Toggle bottom terminal" "t" #'+ghostel/toggle
       :desc "Open terminal buffer" "T" #'+ghostel/here
       :desc "Toggle fullscreen project terminal" "p" #'my/terminal-popup-toggle))
(set-popup-rule! "^\\*Floating Ghostel:"
  :side 'bottom :size 0.9 :select t :quit nil :ttl nil :modeline nil)
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
