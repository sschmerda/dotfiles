;;; themes-config.el --- Local themes and diagnostic compatibility -*- lexical-binding: t; -*-

(require 'seq)

;; Remove obsolete family paths when reloading an existing Emacs session.
(dolist (relative '("themes/landscape/" "themes/custom/"))
  (let ((directory (expand-file-name relative doom-user-dir)))
    (dolist (path (list directory (directory-file-name directory)))
      (setq load-path (delete path load-path)
            custom-theme-load-path (delete path custom-theme-load-path)))))

;; Helpers and selectable theme entries share this directory, but Emacs uses
;; separate search paths for Lisp libraries and themes.
(let ((directory (expand-file-name "themes/" doom-user-dir)))
  (add-to-list 'load-path directory)
  (add-to-list 'custom-theme-load-path directory))

;; This lsp-ui version renders informational diagnostics with `success'. Keep
;; their color aligned with Flycheck/Flymake without recoloring DONE/success.
(defun my--theme-diagnostic-face (face)
  "Replace only the informational diagnostic FACE, preserving other styles."
  (cond ((eq face 'success) 'landscape-diagnostic-info)
        ((and (listp face) (not (keywordp (car face))))
         (mapcar #'my--theme-diagnostic-face face))
        (t face)))

(defvar lsp-ui-sideline--ovs)
(defun my--theme-sideline-diagnostics-h (buffer &rest _)
  "Align informational sideline colors in BUFFER while custom themes are active."
  (when (and (buffer-live-p (get-buffer buffer))
             (seq-some (lambda (theme) (string-prefix-p "custom-" (symbol-name theme)))
                       custom-enabled-themes))
    (with-current-buffer buffer
      (when (boundp 'lsp-ui-sideline--ovs)
        (dolist (overlay lsp-ui-sideline--ovs)
          (when (and (overlayp overlay) (eq (overlay-get overlay 'kind) 'diagnostics))
            (let ((original (overlay-get overlay 'after-string)))
              (when (stringp original)
                (let ((string (copy-sequence original)) (position 0))
                  (while (< position (length string))
                    (let* ((end (next-single-property-change position 'face string (length string)))
                           (face (get-text-property position 'face string)))
                      (when face
                        (put-text-property position end 'face
                                           (my--theme-diagnostic-face face) string))
                      (setq position end)))
                  (overlay-put overlay 'after-string string))))))))))

(with-eval-after-load 'lsp-ui-sideline
  (advice-add 'lsp-ui-sideline--diagnostics :after #'my--theme-sideline-diagnostics-h))
