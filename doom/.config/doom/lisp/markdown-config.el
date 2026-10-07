;;; markdown-config.el -*- lexical-binding: t; -*-

;; Proportional prose with monospace code; also applies to derived GFM buffers.
(add-hook! 'markdown-mode-hook
  (defun my/markdown-enable-mixed-pitch-h ()
    (mixed-pitch-mode 1)))

(after! markdown-mode
  (map! :map markdown-mode-map
        :localleader
        :desc "Toggle mixed pitch" "v" #'mixed-pitch-mode))
