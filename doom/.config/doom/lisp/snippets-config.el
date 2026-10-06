;;; snippets-config.el -*- lexical-binding: t; -*-

;; Doom snippets aliases `%` to `yas-selected-text`, making it dynamic. Doom's
;; `fn!` also uses `%` as a lexical argument; keep the alias but clear that
;; declaration so loading Doom documentation does not warn.
(with-eval-after-load 'doom-snippets-lib
  (when (and (fboundp 'internal-make-var-non-special)
             (eq (indirect-variable '%) 'yas-selected-text))
    (internal-make-var-non-special '%)))
