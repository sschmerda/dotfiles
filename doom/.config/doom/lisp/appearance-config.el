;;; appearance-config.el -*- lexical-binding: t; -*-

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-gruvbox-light)
(setq doom-font (font-spec :family "Hack Nerd Font Mono" :size 16))

;; Match the VS Code Shades of Purple cursor color.
(when (eq doom-theme 'doom-shades-of-purple)
  (setq evil-normal-state-cursor '("#fad000" box)
        evil-insert-state-cursor '("#fad000" bar)
        evil-visual-state-cursor '("#fad000" box)
        evil-replace-state-cursor '("#fad000" hbar)
        evil-motion-state-cursor '("#fad000" box))
  (set-cursor-color "#fad000"))

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type 'relative)

;; Make Doom's Command +/- font zoom use smaller steps.
(setq doom-font-increment 1)

;; frame customization
(add-to-list 'default-frame-alist '(undecorated . t))
(add-to-list 'default-frame-alist '(fullscreen . maximized))
(set-frame-parameter nil 'undecorated t)
(set-frame-parameter nil 'fullscreen 'maximized)

;; Show the 80-column guide everywhere except in Ghostel terminals.
(setq-default display-fill-column-indicator-column 80
              display-fill-column-indicator-character ?│)
(set-face-attribute 'fill-column-indicator nil
                    :foreground "#3f444c"
                    :background nil)
(global-display-fill-column-indicator-mode 1)
