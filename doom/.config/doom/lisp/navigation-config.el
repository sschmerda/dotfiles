;;; navigation-config.el -*- lexical-binding: t; -*-

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
