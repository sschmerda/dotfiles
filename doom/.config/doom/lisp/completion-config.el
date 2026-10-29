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
