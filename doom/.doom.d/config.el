;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

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
(setq doom-theme 'doom-shades-of-purple)
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

;; Use visible-line relative numbers in Org so folded sections do not count hidden lines.
(add-hook! 'org-mode-hook
  (defun my/org-use-visual-line-numbers-h ()
    (setq-local display-line-numbers 'visual)))

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `with-eval-after-load' block, otherwise Doom's defaults may override your
;; settings. E.g.
;;
;;   (with-eval-after-load 'PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look them up).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

;; Custom Config

;; macOS modifier keys
(setq mac-option-modifier 'meta
      mac-command-modifier 'super
      ns-option-modifier 'meta
      ns-command-modifier 'super)

;; Make Doom's Command +/- font zoom use smaller steps.
(setq doom-font-increment 1)

;; frame customization
(add-to-list 'default-frame-alist '(undecorated . t))
(add-to-list 'default-frame-alist '(fullscreen . maximized))
(set-frame-parameter nil 'undecorated t)
(set-frame-parameter nil 'fullscreen 'maximized)

;; show a vertical guide at 80 characters
(setq-default display-fill-column-indicator-column 80
              display-fill-column-indicator-character ?│)
(set-face-attribute 'fill-column-indicator nil
                    :foreground "#3f444c"
                    :background nil)
(global-display-fill-column-indicator-mode 1)

;; Open Treemacs from Doom's open menu.
(map! :leader
      (:prefix ("o" . "open")
       :desc "Treemacs"
       "x" #'+treemacs/toggle))

;; Toggle Olivetti buffer centering without hiding modelines or other windows.
(use-package! olivetti
  :commands (olivetti-mode my/olivetti-toggle-all)
  :init
  (setq olivetti-body-width 120)
  (defvar my/olivetti-enabled nil)
  (defvar-local my/olivetti-border-face-cookie nil)
  (defun my/olivetti-buffer-eligible-p ()
    (and (not (minibufferp))
         (buffer-file-name)
         (not (string-prefix-p " " (buffer-name)))
         (not (string-prefix-p "*" (buffer-name)))))
  (defun my/olivetti-enable-buffer (buffer)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (and (my/olivetti-buffer-eligible-p)
                   (not (bound-and-true-p olivetti-mode)))
          (olivetti-mode 1)))))
  (defun my/olivetti-disable-buffer (buffer)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (bound-and-true-p olivetti-mode)
          (olivetti-mode -1)))))
  (defun my/olivetti-disable-all-buffers ()
    (mapc #'my/olivetti-disable-buffer (buffer-list)))
  (defun my/olivetti-ignored-window-p (window)
    (with-current-buffer (window-buffer window)
      (derived-mode-p 'treemacs-mode)))
  (defun my/olivetti-refresh-visible-windows ()
    (walk-windows
     (lambda (window)
       (with-current-buffer (window-buffer window)
         (when (bound-and-true-p olivetti-mode)
           (olivetti-set-window window))))
     nil t))
  (defun my/olivetti-set-border-h ()
    (if olivetti-mode
        (progn
          (unless my/olivetti-border-face-cookie
            (setq my/olivetti-border-face-cookie
                  (face-remap-add-relative 'fringe :background "#2d2640")))
          (set-window-fringes nil 1 1 t))
      (when my/olivetti-border-face-cookie
        (face-remap-remove-relative my/olivetti-border-face-cookie)
        (setq my/olivetti-border-face-cookie nil))
      (set-window-fringes nil nil nil t)))
  (defun my/olivetti-vertical-split-p ()
    (let ((left-edges nil))
      (dolist (window (window-list nil 'no-minibuf))
        (unless (my/olivetti-ignored-window-p window)
          (push (window-left-column window) left-edges)))
      (> (length (delete-dups left-edges)) 1)))
  (defun my/olivetti-refresh-h (&rest _)
    (when my/olivetti-enabled
      (if (my/olivetti-vertical-split-p)
          (my/olivetti-disable-all-buffers)
        (mapc #'my/olivetti-enable-buffer (buffer-list))
        (my/olivetti-refresh-visible-windows))))
  (defun my/olivetti-toggle-all ()
    (interactive)
    (setq my/olivetti-enabled (not my/olivetti-enabled))
    (if my/olivetti-enabled
        (my/olivetti-refresh-h)
      (my/olivetti-disable-all-buffers)))
  (map! :leader
        :desc "Center buffers"
        "t o" #'my/olivetti-toggle-all)
  (add-hook 'olivetti-mode-hook #'my/olivetti-set-border-h)
  (add-hook 'buffer-list-update-hook #'my/olivetti-refresh-h)
  (add-hook 'window-state-change-functions #'my/olivetti-refresh-h)
  (add-hook! 'doom-first-buffer-hook
    (defun my/olivetti-enable-on-startup-h ()
      (setq my/olivetti-enabled t)
      (my/olivetti-refresh-h)))
  :config
  (setq olivetti-body-width 120))
