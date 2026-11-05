;;; themes-config.el --- Local theme highlighting compatibility -*- lexical-binding: t; -*-

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

(defun my--theme-parameter-reference-face (face)
  "Replace the semantic parameter FACE with ordinary variable styling."
  (cond ((eq face 'lsp-face-semhl-parameter) 'lsp-face-semhl-variable)
        ((and (listp face) (not (keywordp (car face))))
         (mapcar #'my--theme-parameter-reference-face face))
        (t face)))

(defun my--theme-python-argument-label-p (position)
  "Return non-nil if POSITION is a Python Tree-sitter keyword argument name."
  (when (and (derived-mode-p 'python-ts-mode)
             (fboundp 'treesit-node-at) (treesit-parser-list))
    (let* ((node (treesit-node-at position))
           (parent (treesit-node-parent node)))
      (when (and parent (equal (treesit-node-type parent) "keyword_argument"))
        (let ((name (treesit-node-child-by-field-name parent "name")))
          (and name (<= (treesit-node-start name) position)
               (< position (treesit-node-end name))))))))

(defun my--theme-parameter-fontify-a (original end)
  "Keep parameter declarations accented after ORIGINAL fontifies through END.
Parameter references use ordinary variable colors in custom themes. Preserve
all other semantic faces, including types, modifiers and deprecation styles."
  (let ((start (point)))
    (prog1 (funcall original end)
      (when (seq-some (lambda (theme) (string-prefix-p "custom-" (symbol-name theme)))
                      custom-enabled-themes)
        (with-silent-modifications
          (let ((position start) (limit (min end (point-max))))
            (while (< position limit)
              (let* ((next (next-single-property-change position 'face nil limit))
                     (face (get-text-property position 'face))
                     (faces (if (listp face) face (list face))))
                (when (and (memq 'lsp-face-semhl-parameter faces)
                           (not (memq 'landscape-semhl-declaration faces))
                           (not (my--theme-python-argument-label-p position)))
                  (put-text-property position next 'face
                                     (my--theme-parameter-reference-face face)))
                (setq position next)))))))))

(defun my--theme-register-receiver-faces (client)
  "Register explicit receiver token roles on LSP CLIENT.
Use the client's supported override API rather than theme-dependent resolver
advice: workspace initialization may run before a theme becomes enabled."
  (let* ((overrides (copy-tree (lsp--client-semantic-tokens-faces-overrides client)))
         (types (plist-get overrides :types)))
    (dolist (entry '(("selfParameter" . landscape-receiver)
                     ("clsParameter" . landscape-receiver)
                     ("selfKeyword" . landscape-receiver)
                     ("selfTypeKeyword" . lsp-face-semhl-class)))
      (setf (alist-get (car entry) types nil nil #'equal) (cdr entry)))
    (setf (lsp--client-semantic-tokens-faces-overrides client)
          (plist-put overrides :types types))))

(defun my--theme-refresh-receiver-faces-h ()
  "Initialize receiver roles for workspaces attached to the current buffer.
This also repairs stale vectors when a new file joins an existing workspace."
  (dolist (workspace (lsp-workspaces))
    (my--theme-register-receiver-faces (lsp--workspace-client workspace))
    (let ((lsp--cur-workspace workspace))
      (lsp--semantic-tokens-initialize-workspace workspace)))
  (when (and (boundp 'semantic-token-modifier-cache)
             (hash-table-p semantic-token-modifier-cache))
    (clrhash semantic-token-modifier-cache))
  (when (bound-and-true-p font-lock-mode) (font-lock-flush)))

(with-eval-after-load 'lsp-semantic-tokens
  (require 'landscape-packages)
  ;; Remove the previous theme-dependent implementation when reloading live.
  (advice-remove 'lsp-semantic-tokens--type-faces-for 'my--theme-python-receiver-faces)
  (advice-add 'lsp--semantic-tokens-fontify :around #'my--theme-parameter-fontify-a)
  (advice-add 'lsp-register-client :after #'my--theme-register-receiver-faces)
  (maphash (lambda (_ client) (my--theme-register-receiver-faces client)) lsp-clients)
  (add-hook 'lsp-after-open-hook #'my--theme-refresh-receiver-faces-h)
  (add-hook 'lsp-after-initialize-hook #'my--theme-refresh-receiver-faces-h))
