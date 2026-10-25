;;; lookup-config.el --- Dictionary display settings -*- lexical-binding: t; -*-

;; Cover all dictionary backends selected by Doom's lookup module.
(set-popup-rule! "^\\*\\(?:osx-dictionary\\|WordNut\\|Dictionary\\)\\*$"
  :side 'bottom :size 0.35 :select t :quit t :ttl nil)

(defun my--dictionary-display-results (output)
  "Display online dictionary OUTPUT in a dedicated bottom popup."
  (let ((buffer (get-buffer-create "*Dictionary*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'special-mode)
        (special-mode))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert output)
        (goto-char (point-min)))
      (visual-line-mode 1))
    (pop-to-buffer buffer)))

(after! define-word
  ;; Route every service, including services added later, through the same UI.
  (defun my--dictionary-display-function-a (_service)
    #'my--dictionary-display-results)
  (advice-add 'define-word-displayfn :override
              #'my--dictionary-display-function-a))

;; WordNut already uses `pop-to-buffer', so the shared popup rule is enough.
(after! osx-dictionary

  ;; The package's other-window switch bypasses Doom's popup placement.
  ;; Keep its saved layout so its own quit command still restores the windows.
  (defun my--osx-dictionary-display-bottom-a (word)
    (setq osx-dictionary-previous-window-configuration
          (current-window-configuration))
    (pop-to-buffer (osx-dictionary--get-buffer word)))
  (advice-add 'osx-dictionary--goto-dictionary :override
              #'my--osx-dictionary-display-bottom-a))

;;; lookup-config.el ends here
