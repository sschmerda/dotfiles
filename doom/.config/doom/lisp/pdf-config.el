;;; pdf-config.el -*- lexical-binding: t; -*-

;; Show full PDF pages by default so each page fits vertically without scrolling.
(after! pdf-view
  (setq-default pdf-view-display-size 'fit-height)
  (add-hook! 'pdf-view-mode-hook
    (defun my/pdf-fit-height-h ()
      (pdf-view-fit-height-to-window))))
