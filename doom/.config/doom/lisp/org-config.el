;;; org-config.el -*- lexical-binding: t; -*-

;; Use visible-line relative numbers in Org so folded sections do not count hidden lines.
(add-hook! 'org-mode-hook
  (defun my/org-use-visual-line-numbers-h ()
    (setq-local display-line-numbers 'visual)))

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")

;; Use proportional prose while retaining monospace code and aligned tables.
(add-hook! 'org-mode-hook
  (defun my/org-enable-mixed-pitch-h ()
    (mixed-pitch-mode 1)))

(after! org
  (map! :map org-mode-map
        :localleader
        :desc "Toggle mixed pitch" "v" #'mixed-pitch-mode))
