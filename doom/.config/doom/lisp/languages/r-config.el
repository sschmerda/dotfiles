;;; r-config.el -*- lexical-binding: t; -*-

;; Format R files with styler from the R environment Emacs uses.
(after! apheleia
  (setf (alist-get 'ess-r-mode apheleia-mode-alist) 'r-styler))
