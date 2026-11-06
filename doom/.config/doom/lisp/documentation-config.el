;;; documentation-config.el --- Expand repeated documentation lookups -*- lexical-binding: t; -*-

(require 'cl-lib)
(defvar my-olivetti-inhibit-layout)
(defvar olivetti-mode)

(defvar my--documentation-source-mode nil
  "Source language mode while a synchronous documentation lookup renders.")
(defvar lsp-buffer-major-mode)

(defun my--documentation-render-markdown-a (original &rest args)
  "Render documentation with ORIGINAL and ARGS using the source language.
Explicitly labeled code blocks retain their own language. Unlabeled blocks
use the source mode, rather than the help buffer's mode. Prose remains Markdown."
  (let ((lsp-buffer-major-mode (or my--documentation-source-mode lsp-buffer-major-mode)))
    (apply original args)))

(with-eval-after-load 'lsp-mode
  ;; The renderer is called indirectly by lsp-mode inside a temporary buffer.
  (advice-add 'lsp--render-markdown :around #'my--documentation-render-markdown-a))

(defcustom my-documentation-repeat-delay 1.0
  "Seconds after a completed lookup during which another K expands its result."
  :type 'number :group 'convenience)

(defun my--documentation-window-p (window)
  "Return non-nil if WINDOW displays documentation supported by this feature."
  (and (window-live-p window)
       (with-current-buffer (window-buffer window)
         (derived-mode-p 'help-mode 'helpful-mode 'Info-mode 'Man-mode
                         'woman-mode 'devdocs-mode 'eww-mode))))

(defvar my--documentation-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "K") #'my/documentation)
    (define-key map (kbd "q") #'my/documentation-quit)
    (define-key map [remap quit-window] #'my/documentation-quit)
    map))

(define-minor-mode my--documentation-mode
  "Handle repeated K and q in documentation opened by `my/documentation'."
  :lighter nil :keymap my--documentation-mode-map)

(defun my--documentation-clear (frame)
  "Forget FRAME's last lookup and remove its temporary buffer bindings."
  (let* ((state (frame-parameter frame 'my-documentation))
         (buffer (plist-get state :buffer)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer (my--documentation-mode -1)))
    (set-frame-parameter frame 'my-documentation nil)))

(defun my/documentation-quit ()
  "Close the expanded documentation view and restore the pre-lookup layout.
In an ordinary documentation popup, use `quit-window' as usual."
  (interactive)
  (let* ((frame (selected-frame))
         (state (frame-parameter frame 'my-documentation))
         (buffer (plist-get state :buffer)))
    (if (and (plist-get state :expanded) (eq buffer (current-buffer)))
        (let ((my-olivetti-inhibit-layout t))
          (when (and (fboundp 'olivetti-mode) (buffer-live-p buffer))
            (with-current-buffer buffer
              (olivetti-mode (if (plist-get state :olivetti) 1 -1))))
          (my--documentation-clear frame)
          (set-window-configuration (plist-get state :configuration)))
      (my--documentation-clear frame)
      (quit-window))
    (when (fboundp 'my--olivetti-refresh-h) (my--olivetti-refresh-h))))

(defun my--documentation-expand (frame state)
  "Expand the tracked documentation window in FRAME using STATE."
  (let ((window (plist-get state :window))
        (buffer (plist-get state :buffer))
        (my-olivetti-inhibit-layout t))
    (unless (and (window-live-p window) (eq (window-buffer window) buffer))
      (user-error "The documentation window is no longer available"))
    (setq state (plist-put state :olivetti
                           (and (boundp 'olivetti-mode)
                                (buffer-local-value 'olivetti-mode buffer))))
    (select-window window)
    (when (and (fboundp '+popup-window-p) (+popup-window-p window))
      (+popup/raise window))
    ;; Keep the original help buffer, its buttons and its history.
    (delete-other-windows)
    (set-window-dedicated-p (selected-window) nil)
    (set-frame-parameter frame 'my-documentation (plist-put state :expanded t))
    (when (require 'olivetti nil t) (olivetti-mode 1))
    (when (bound-and-true-p evil-local-mode) (evil-motion-state)))
  (when (fboundp 'my--olivetti-refresh-h) (my--olivetti-refresh-h)))

(defun my/documentation (&optional arg)
  "Look up documentation; repeat K promptly to expand the resulting window.
The first invocation delegates to Doom's `+lookup/documentation'. LSP Markdown
code blocks use syntax colors: labeled blocks use their declared language,
unlabeled blocks use the source buffer's language. Prose keeps its normal
formatting; this does not run another language server for documentation.
A second
consecutive invocation within `my-documentation-repeat-delay' focuses that
lookup's result in a single window, centered with Olivetti. Press q to restore
the window layout from before the lookup. This is a normal Emacs window.

A prefix argument always performs a fresh lookup, preserving Doom's backend
selection. Delayed invocations from the result return to the original source
window for a fresh lookup. External browsers and asynchronous results that do
not display a documentation window during the lookup are not expanded."
  (interactive "P")
  (let* ((frame (selected-frame))
         (state (frame-parameter frame 'my-documentation))
         (window (plist-get state :window))
         (source (plist-get state :source))
         (buffer (plist-get state :buffer))
         (repeat (and (not arg) (eq last-command 'my/documentation)
                      state (not (plist-get state :expanded))
                      (window-live-p window) (eq (window-buffer window) buffer)
                      (or (eq (selected-window) window)
                          (and (eq (selected-window) source)
                               (eq (current-buffer) (plist-get state :source-buffer))
                               (= (point) (plist-get state :point))))
                      (<= (- (float-time) (plist-get state :time))
                          my-documentation-repeat-delay))))
    (if repeat
        (my--documentation-expand frame state)
      (when (and state (eq (current-buffer) buffer))
        (if (plist-get state :expanded)
            (my/documentation-quit)
          (when (and (window-live-p source)
                     (buffer-live-p (plist-get state :source-buffer)))
            (select-window source)
            ;; Some backends replace the source window rather than splitting.
            (when (eq (current-buffer) buffer)
              (switch-to-buffer (plist-get state :source-buffer))
              (goto-char (plist-get state :point))))))
      (my--documentation-clear frame)
      (let* ((configuration (current-window-configuration))
             (source (selected-window)) (source-buffer (current-buffer))
             (position (point))
             (before (mapcar (lambda (w)
                               (list w (window-buffer w)
                                     (buffer-chars-modified-tick (window-buffer w))))
                             (window-list frame 'no-minibuf))))
        (let ((current-prefix-arg arg)
              (my--documentation-source-mode major-mode))
          (call-interactively #'+lookup/documentation))
        (let* ((candidates
                (cl-remove-if-not
                 (lambda (w)
                   (let ((old (assq w before)))
                     (and (my--documentation-window-p w)
                          (or (null old)
                              ;; Cached help can select its existing window
                              ;; without changing any documentation text.
                              (and (eq w (selected-window)) (not (eq w source)))
                              (not (eq (window-buffer w) (nth 1 old)))
                              (/= (buffer-chars-modified-tick (window-buffer w))
                                  (nth 2 old))))))
                 (window-list frame 'no-minibuf)))
               (result (if (memq (selected-window) candidates)
                           (selected-window)
                         (and (= (length candidates) 1) (car candidates)))))
          (when result
            (set-frame-parameter
             frame 'my-documentation
             (list :configuration configuration :source source
                   :source-buffer source-buffer :point position :window result
                   :buffer (window-buffer result) :time (float-time)))
            (with-current-buffer (window-buffer result)
              (my--documentation-mode 1))))))))

(with-eval-after-load 'evil
  (define-key evil-normal-state-map (kbd "K") #'my/documentation)
  (define-key evil-visual-state-map (kbd "K") #'my/documentation)
  (evil-define-minor-mode-key '(normal motion visual) 'my--documentation-mode
    (kbd "K") #'my/documentation
    (kbd "q") #'my/documentation-quit))

(provide 'documentation-config)
;;; documentation-config.el ends here
