;;; spacing-config.el -*- lexical-binding: t; -*-

;; Add interface spacing with a thin visible divider between split windows.
(use-package! spacious-padding
  :demand t
  :init
  (map! :leader :desc "Spacious padding" "t P" #'spacious-padding-mode)
  (setq spacious-padding-widths
        '(:internal-border-width 8
          :header-line-width 4
          :mode-line-width 4
          :custom-button-width 3
          :tab-width 4
          :right-divider-width 1
          :scroll-bar-width 8
          :fringe-width 8))
  :config
  (defun my/spacious-padding-visible-dividers-h (&rest _)
    "Keep a contrasting thin separator while spacious padding is enabled."
    (when spacious-padding-mode
      (let ((color (face-attribute 'shadow :foreground nil t))
            custom--inhibit-theme-enable)
        ;; Disabling the mode clears these overrides and restores theme faces.
        (dolist (face '(window-divider window-divider-first-pixel
                        window-divider-last-pixel))
          (custom-theme-set-faces 'spacious-padding
            `(,face ((t (:foreground ,color :background ,color)))))))))
  (advice-add 'spacious-padding-set-faces :after
              #'my/spacious-padding-visible-dividers-h)
  (spacious-padding-mode 1))
