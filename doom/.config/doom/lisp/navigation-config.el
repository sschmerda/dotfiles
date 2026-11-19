;;; navigation-config.el -*- lexical-binding: t; -*-

(defvar my-window-resize-repeat-active nil)

(defun my/window-resize-help ()
  "Explain the active split-window resize keys."
  (interactive)
  (message "Resize: > wider, < narrower, + taller, - shorter, = balance; q/C-g exit; other keys exit and run normally"))

(defvar my-window-resize-repeat-map
  (let ((map (make-sparse-keymap)))
    (dolist (binding '((">" . evil-window-increase-width)
                       ("<" . evil-window-decrease-width)
                       ("+" . evil-window-increase-height)
                       ("-" . evil-window-decrease-height)
                       ("=" . balance-windows)
                       ("q" . ignore)
                       ("C-g" . keyboard-quit)
                       ("C-h" . my/window-resize-help)
                       ("C-c C-h" . my/window-resize-help)))
      (define-key map (kbd (car binding)) (cdr binding)))
    map)
  "Transient keys available after resizing a split window.")

(defun my--window-resize-repeat-a (&rest _)
  "Allow bare resize keys after an interactive Evil window resize."
  (when (and (memq this-command '(evil-window-increase-width evil-window-decrease-width
                                 evil-window-increase-height evil-window-decrease-height))
             (not my-window-resize-repeat-active))
    (setq my-window-resize-repeat-active t)
    (set-transient-map
     my-window-resize-repeat-map
     (lambda ()
       (memq this-command '(evil-window-increase-width evil-window-decrease-width
                            evil-window-increase-height evil-window-decrease-height
                            balance-windows my/window-resize-help)))
     (lambda () (setq my-window-resize-repeat-active nil)))
    (my/window-resize-help)))

(after! evil
  (dolist (command '(evil-window-increase-width evil-window-decrease-width
                     evil-window-increase-height evil-window-decrease-height))
    (advice-add command :after #'my--window-resize-repeat-a)))

(after! evil-snipe
  ;; Match literal whitespace so t<Space> stops before it, as in Vim.
  (setq evil-snipe-skip-leading-whitespace nil))

(defvar my-evil-word-syntax-table
  (let ((table (copy-syntax-table (standard-syntax-table))))
    (modify-syntax-entry ?_ "w" table)
    table)
  "Vim-style word syntax for Evil: letters, digits and underscores.
Major-mode syntax tables remain unchanged outside Evil word operations.")

(defun my--evil-vim-word-syntax-a (original &rest args)
  "Call ORIGINAL with ARGS using Vim-style word boundaries."
  (with-syntax-table my-evil-word-syntax-table
    (apply original args)))

(defun my--evil-vim-word-object-a (original &rest args)
  "Use Vim word syntax when ORIGINAL selects an `evil-word' from ARGS."
  (if (eq (car args) 'evil-word)
      (apply #'my--evil-vim-word-syntax-a original args)
    (apply original args)))

(after! evil
  ;; Cover motions, their shared word primitive, and operator/visual objects.
  ;; Keep uppercase WORD motions and Emacs's own word commands unchanged.
  (dolist (function '(forward-evil-word
                      evil-forward-word-begin evil-backward-word-begin
                      evil-forward-word-end evil-backward-word-end))
    (advice-add function :around #'my--evil-vim-word-syntax-a))
  ;; Keep text-object commands directly interactive: their Evil wrappers use
  ;; that distinction to adjust inclusive Visual selections correctly.
  (dolist (function '(evil-select-inner-restricted-object
                      evil-select-a-restricted-object))
    (advice-add function :around #'my--evil-vim-word-object-a)))

(defvar my-nav-flash-motion-threshold 10
  "Minimum Evil vertical motion count that flashes the destination line.")

(defvar my-nav-flash-in-motion nil
  "Non-nil while handling a vertical motion, to avoid nested flashes.")

(defun my--nav-flash-vertical-motion-a (original &rest args)
  "Flash after ORIGINAL moves point with a sufficiently large count in ARGS."
  (if (or my-nav-flash-in-motion
          (not (memq this-command
                     '(evil-next-line evil-previous-line
                       evil-next-visual-line evil-previous-visual-line
                       my/magit-previous-visible-line)))
          (< (abs (or (car args) 1)) my-nav-flash-motion-threshold))
      (apply original args)
    (let ((my-nav-flash-in-motion t)
          (buffer (current-buffer))
          (position (point)))
      (prog1 (apply original args)
        (when (and (eq buffer (current-buffer)) (/= position (point)))
          (+nav-flash-blink-cursor-maybe))))))

(when (modulep! :ui nav-flash)
  (after! evil
    (dolist (motion '(evil-next-line evil-previous-line
                      evil-next-visual-line evil-previous-visual-line))
      (advice-add motion :around #'my--nav-flash-vertical-motion-a)))
  (after! magit
    ;; This configuration uses a separate upward motion for folded sections.
    (advice-add 'my/magit-previous-visible-line :around
                #'my--nav-flash-vertical-motion-a))
  (after! avy
    ;; Run only after a target is chosen, not after cancelled Avy prompts.
    (advice-add 'avy-action-goto :after #'+nav-flash-blink-cursor-maybe)))
