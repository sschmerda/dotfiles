;;; magit-config.el -*- lexical-binding: t; -*-

(after! code-review
  ;; Reuse Forge's auth-source entry rather than requiring a second token.
  (setq code-review-auth-login-marker 'forge
        code-review-new-buffer-window-strategy #'pop-to-buffer)
  ;; Both initial display and later refreshes use the same right-hand popup.
  (set-popup-rule! "^\\*Code Review\\*$"
    :side 'right :size 0.6 :select t :modeline t :quit nil :ttl nil)
  ;; Older code-review releases still call Ghub's relocated GraphQL API.
  (unless (fboundp 'ghub-graphql)
    (require 'ghub-legacy)))

(defvar magit-display-buffer-function)
(defvar magit-bury-buffer-function)
(defvar magit-previous-window-configuration)
(defvar my-olivetti-inhibit-layout)
(defvar my-olivetti-inhibit-centering nil)

(defvar-local my-magit-fullscreen-quit-state nil
  "Previous local-binding status and quit function before fullscreen Magit.")
(put 'my-magit-fullscreen-quit-state 'permanent-local t)
(defvar-local my-magit-fullscreen-centering-state nil
  "Previous local-binding status and centering exclusion before fullscreen.")
(put 'my-magit-fullscreen-centering-state 'permanent-local t)

(defun my--magit-fullscreen-quit (kill-buffer)
  "Quit fullscreen Magit, optionally KILL-BUFFER, restoring the saved layout."
  (let ((buffer (current-buffer))
        (state my-magit-fullscreen-quit-state))
    (unwind-protect
        (let ((my-olivetti-inhibit-layout t))
          (magit-restore-window-configuration kill-buffer))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (if (car state)
              (setq-local magit-bury-buffer-function (cdr state))
            (kill-local-variable 'magit-bury-buffer-function))
          (if (car my-magit-fullscreen-centering-state)
              (setq-local my-olivetti-inhibit-centering
                          (cdr my-magit-fullscreen-centering-state))
            (kill-local-variable 'my-olivetti-inhibit-centering))
          (setq my-magit-fullscreen-quit-state nil
                my-magit-fullscreen-centering-state nil))))))

(defun my/magit-status-fullscreen (&optional uncentered)
  "Open Magit status across the current frame; q restores the previous layout.
Use Doom's normal repository selection and prefix arguments. Olivetti may
center the single window unless UNCENTERED is non-nil. Other Magit entry
points retain Doom's display rules."
  (interactive)
  (require 'magit)
  (let ((configuration (current-window-configuration))
        (magit-display-buffer-function #'magit-display-buffer-fullframe-status-v1))
    (call-interactively #'magit-status)
    (with-current-buffer (window-buffer (selected-window))
      (when (derived-mode-p 'magit-status-mode)
        (unless my-magit-fullscreen-quit-state
          (setq-local my-magit-fullscreen-quit-state
                      (cons (local-variable-p 'magit-bury-buffer-function)
                            magit-bury-buffer-function))
          (setq-local my-magit-fullscreen-centering-state
                      (cons (local-variable-p 'my-olivetti-inhibit-centering)
                            my-olivetti-inhibit-centering))
          (setq-local magit-previous-window-configuration configuration))
        (setq-local magit-bury-buffer-function #'my--magit-fullscreen-quit
                    my-olivetti-inhibit-centering uncentered)
        (when (and uncentered (bound-and-true-p olivetti-mode))
          (olivetti-mode -1))
        (when (fboundp 'my--olivetti-refresh-h)
          (my--olivetti-refresh-h))))))

(defun my/magit-status-fullwidth ()
  "Open fullscreen Magit without Olivetti centering; q restores the layout."
  (interactive)
  (my/magit-status-fullscreen t))

(map! :leader
      :desc "Magit fullscreen" "g n" #'my/magit-status-fullscreen
      :desc "Magit full width" "g e" #'my/magit-status-fullwidth)

(defun my--magit-inherit-centering-a (original buffer &rest args)
  "Display Magit BUFFER through ORIGINAL with ARGS and the source's centering.
Propagate full-width status to logs, revisions, diffs and subsequent Magit
views. Reused buffers lose the exclusion when opened from a normal source."
  (let ((uncentered (and (derived-mode-p 'magit-mode)
                        my-olivetti-inhibit-centering)))
    (with-current-buffer buffer
      (setq-local my-olivetti-inhibit-centering uncentered)
      ;; Magit reinitializes reused buffers' modes; preserve the fullscreen exit
      ;; command when a navigation command returns to the status buffer.
      (when my-magit-fullscreen-quit-state
        (setq-local magit-bury-buffer-function #'my--magit-fullscreen-quit))
      (when (and uncentered (bound-and-true-p olivetti-mode))
        (olivetti-mode -1)))
    (prog1 (apply original buffer args)
      (when (fboundp 'my--olivetti-refresh-h)
        (my--olivetti-refresh-h)))))

(defun my--magit-enable-relative-line-numbers-h ()
  "Count visible lines for relative motions across folded Magit sections."
  (setq-local display-line-numbers-type 'visual)
  (display-line-numbers-mode 1))

(defun my/magit-clear-file-filter ()
  "Clear active and suspended file filters in the current Magit buffer."
  (interactive)
  (setq magit-buffer-diff-files nil
        magit-buffer-diff-files-suspended nil)
  (magit-refresh))

(defun my/magit-filter-directory (directory)
  "Limit the current Magit buffer to DIRECTORY inside this repository."
  (interactive
   (list (let ((default-directory (magit-toplevel)))
           (read-directory-name "Filter by directory: " default-directory nil t))))
  (let* ((root (magit-toplevel))
         (directory (file-name-as-directory (expand-file-name directory))))
    (unless (or (equal (file-truename directory) (file-truename root))
                (file-in-directory-p directory root))
      (user-error "Choose a directory inside this repository"))
    (setq magit-buffer-diff-files
          (unless (equal (file-truename directory) (file-truename root))
            (list (file-relative-name directory root)))
          magit-buffer-diff-files-suspended nil)
    (magit-refresh)))

(after! magit-diff
  ;; Add an explicit reset beside Magit's existing file-filter toggle.
  (unless (ignore-errors (transient-get-suffix 'magit-diff-refresh "C"))
    (transient-append-suffix 'magit-diff-refresh "F"
      '("C" "Clear file filter" my/magit-clear-file-filter)))
  (unless (ignore-errors (transient-get-suffix 'magit-diff-refresh "/"))
    (transient-append-suffix 'magit-diff-refresh "C"
      '("/" "Filter by directory" my/magit-filter-directory))))

(after! magit
  (advice-add 'magit-display-buffer :around #'my--magit-inherit-centering-a)
  ;; Doom disables numbers in Magit by default; replace that hook.
  (remove-hook 'magit-mode-hook #'doom-disable-line-numbers-h)
  (add-hook 'magit-mode-hook #'my--magit-enable-relative-line-numbers-h))

(after! magit-margin
  ;; Magit normally hides these overlays by giving the right margin no width.
  ;; Olivetti's padding also uses that margin, so skip disabled annotations.
  (defun my--magit-respect-margin-visibility-a (original &rest args)
    "Create margin annotations only when Magit's margin is enabled."
    (when (magit--right-margin-active)
      (apply original args)))
  (advice-add 'magit-make-margin-overlay :around
              #'my--magit-respect-margin-visibility-a)
  ;; Toggling the margin must rebuild annotations removed while disabled.
  (advice-add 'magit-toggle-margin :after #'magit-refresh))

(after! (evil magit)
  ;; On Emacs 29, multi-line visual motion can undercount folded boundaries.
  ;; Single screen-line steps consistently skip Magit's invisible overlays.
  (evil-define-motion my/magit-previous-visible-line (count)
    "Move COUNT visible lines up, including across folded Magit sections."
    :type exclusive
    (dotimes (_ (or count 1))
      (evil-previous-visual-line 1)))
  (map! :map magit-mode-map
        :nv "k" #'my/magit-previous-visible-line))
