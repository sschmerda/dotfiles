;;; spell-config.el -*- lexical-binding: t; -*-

;; Keep spell checking off by default; use SPC t s to toggle it per buffer.
(after! flyspell
  (defun my/disable-flyspell-h ()
    (flyspell-mode -1))
  (remove-hook 'org-mode-hook #'flyspell-mode)
  (remove-hook 'markdown-mode-hook #'flyspell-mode)
  (remove-hook 'TeX-mode-hook #'flyspell-mode)
  (remove-hook 'rst-mode-hook #'flyspell-mode)
  (remove-hook 'mu4e-compose-mode-hook #'flyspell-mode)
  (remove-hook 'message-mode-hook #'flyspell-mode)
  (remove-hook 'git-commit-mode-hook #'flyspell-mode)
  (add-hook 'git-commit-mode-hook #'my/disable-flyspell-h)
  (add-hook 'magit-mode-hook #'my/disable-flyspell-h))
