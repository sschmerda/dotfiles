;;; text-layout-config.el -*- lexical-binding: t; -*-

(require 'whitespace)
(require 'cl-lib)
(require 'color)
(require 'face-remap)

;; Project-local fill-column values override these defaults after mode setup.
(setq-default fill-column 80)
(defvar-local my/text-layout-initialized nil)
(defvar-local my/text-layout-overflow-face nil)

(defun my/text-layout-prose-p ()
  "Return non-nil for Org and Markdown prose buffers."
  (derived-mode-p 'org-mode 'markdown-mode))

(defun my/text-layout-eligible-p ()
  "Restrict layout settings to source and prose files."
  (and buffer-file-name
       (or (derived-mode-p 'prog-mode) (my/text-layout-prose-p))
       (not (derived-mode-p 'special-mode 'comint-mode 'term-mode
                            'vterm-mode 'ghostel-mode))))

(defun my/text-layout-overflow-colour ()
  "Tint excess code columns using the active theme."
  (when my/text-layout-overflow-face
    (face-remap-remove-relative my/text-layout-overflow-face)
    (setq my/text-layout-overflow-face nil))
  (unless (my/text-layout-prose-p)
    (let* ((background (face-background 'default nil t))
           (warning (face-foreground 'error nil t))
           (amount 0.22)
           (bg-rgb (color-name-to-rgb background))
           (fg-rgb (color-name-to-rgb warning)))
      (when (and bg-rgb fg-rgb)
        (setq my/text-layout-overflow-face
              (face-remap-add-relative
               'whitespace-line
               :background
               (apply #'color-rgb-to-hex
                      (cl-mapcar (lambda (bg fg)
                                   (+ (* bg (- 1 amount)) (* fg amount)))
                                 bg-rgb fg-rgb))))))))

(defun my/text-layout-refresh (&rest _)
  "Refresh highlighting after local variables or EditorConfig changes."
  (when (my/text-layout-eligible-p)
    ;; Keep Doom's indentation checks while highlighting only excess columns.
    (setq-local whitespace-line-column nil
                whitespace-style
                (cl-union (if (my/text-layout-prose-p) '(face) '(face lines-tail))
                          (cl-set-difference
                           whitespace-style
                           '(lines lines-tail lines-char spaces space-mark newline newline-mark))))
    (whitespace-mode -1)
    (whitespace-mode 1)
    (my/text-layout-overflow-colour)))

(defun my/text-layout-setup-h ()
  "Set code widths and wrapping before project-local overrides load."
  (when (and (my/text-layout-eligible-p) (not (my/text-layout-prose-p)))
    (unless my/text-layout-initialized
      (setq my/text-layout-initialized t)
      (unless (or (assq 'fill-column dir-local-variables-alist)
                  (assq 'fill-column file-local-variables-alist))
        (setq-local fill-column
                    (cond ((derived-mode-p 'python-mode 'python-ts-mode) 88)
                          ((derived-mode-p 'rust-mode 'rust-ts-mode 'rustic-mode) 100)
                          (t 80))))
      (auto-fill-mode -1)
      (when (bound-and-true-p +word-wrap-mode) (+word-wrap-mode -1))
      (visual-line-mode -1))
    (my/text-layout-refresh)))

(defun my/text-layout-theme-h ()
  "Preserve syntax colours and update overflow backgrounds after theme changes."
  (set-face-attribute 'whitespace-line nil :foreground 'unspecified
                      :weight 'unspecified :inherit nil)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (my/text-layout-eligible-p)
        (my/text-layout-overflow-colour)))))

(add-hook 'after-change-major-mode-hook #'my/text-layout-setup-h t)
(add-hook 'hack-local-variables-hook #'my/text-layout-refresh t)
(add-hook 'editorconfig-after-apply-functions #'my/text-layout-refresh t)
(add-hook 'doom-load-theme-hook #'my/text-layout-theme-h)
(my/text-layout-theme-h)
