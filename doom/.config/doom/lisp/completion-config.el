;;; completion-config.el -*- lexical-binding: t; -*-

;; Keep automatic completion responsive without requesting it on every keypress.
(after! corfu-auto
  (setq corfu-auto-delay 0.15))

;; Show completion documentation sooner, with a short pause when changing items.
(after! corfu-popupinfo
  (setq corfu-popupinfo-delay '(0.25 . 0.5)))

;; Reduce the idle wait for documentation in the echo area as well.
(after! eldoc
  (setq eldoc-idle-delay 0.3))

(defun my--vertico-pad-fixed-height-a (args)
  "Reserve empty display rows in fixed-height Vertico sessions.
Emacs can refit the minibuffer to the overlay's actual height after a theme
preview. Padding its display keeps that height consistent with `vertico-count'
without adding selectable candidates or changing dynamic-height sessions."
  (let ((lines (car args)))
    (if (and (minibufferp) (null vertico-resize)
             (< (length lines) vertico-count))
        (list (append lines (make-list (- vertico-count (length lines)) "\n")))
      args)))

(after! vertico
  (advice-add 'vertico--display-candidates :filter-args #'my--vertico-pad-fixed-height-a))
