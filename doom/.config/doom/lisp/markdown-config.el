;;; markdown-config.el -*- lexical-binding: t; -*-

;; The pre-31 Tree-sitter mode does not inherit markdown-mode's hooks or map.
(defun my--markdown-enable-mixed-pitch-h ()
  "Use proportional prose with monospace code in either Markdown mode."
  (mixed-pitch-mode 1))
(dolist (hook '(markdown-mode-hook markdown-ts-mode-hook))
  (add-hook hook #'my--markdown-enable-mixed-pitch-h))

(after! markdown-mode
  (map! :map markdown-mode-map
        :localleader
        :desc "Toggle mixed pitch" "v" #'mixed-pitch-mode))

(after! markdown-ts-mode
  (map! :map markdown-ts-mode-map
        :localleader
        :desc "Toggle mixed pitch" "v" #'mixed-pitch-mode))
