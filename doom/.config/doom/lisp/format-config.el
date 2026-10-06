;;; format-config.el -*- lexical-binding: t; -*-

;; Format R files on save via Apheleia; requires styler in the R environment Emacs uses.
(after! apheleia
  (setf (alist-get 'ess-r-mode apheleia-mode-alist) 'r-styler))
