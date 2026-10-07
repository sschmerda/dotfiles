;;; browsing-config.el --- Browser display settings -*- lexical-binding: t; -*-

(after! eww
  ;; Use EWW's normal current-window display instead of Doom's bottom popup.
  (set-popup-rule! "^\\*eww\\*" :ignore t)
  ;; Doom renames loaded pages, so also match existing buffers by their mode.
  (set-popup-rule!
   (lambda (buffer _action)
     (with-current-buffer buffer
       (derived-mode-p 'eww-mode)))
   :ignore t))

;;; browsing-config.el ends here
