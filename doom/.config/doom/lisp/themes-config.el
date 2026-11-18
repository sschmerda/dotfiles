;;; themes-config.el --- Local theme highlighting compatibility -*- lexical-binding: t; -*-

(require 'seq)

;; The client slot setter is a generalized-variable macro from lsp-mode's
;; struct definition. Doom must know it when compiling this configuration.
(eval-when-compile (require 'lsp-mode nil t))

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

;; lsp-ui uses diagnostic levels as faces. Resolve generated/tagged levels to
;; their registered Flycheck faces; they are levels, not face names themselves.
;; Custom themes also align ordinary info colors without recoloring DONE/success.
(defun my--theme-diagnostic-face (face)
  "Resolve tagged diagnostic FACE and apply custom themes' info color."
  (cond ((and (symbolp face) (not (facep face)) (get face 'flycheck-error-level))
         (let ((registered (get face 'flycheck-error-list-face)))
           (if (facep registered) registered 'shadow)))
        ((and (eq face 'success)
              (seq-some (lambda (theme) (string-prefix-p "custom-" (symbol-name theme)))
                        custom-enabled-themes))
         'landscape-diagnostic-info)
        ((and (listp face) (not (keywordp (car face))))
         (mapcar #'my--theme-diagnostic-face face))
        (t face)))

(defvar lsp-ui-sideline--ovs)
(defun my--theme-sideline-diagnostics-h (buffer &rest _)
  "Repair diagnostic face references in BUFFER and align custom theme info colors."
  (when (buffer-live-p (get-buffer buffer))
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
                  (unless (equal-including-properties original string)
                    (overlay-put overlay 'after-string string)))))))))))

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

(defconst my-theme-python-constant-regexp
  "\\_<_*[A-Z][A-Z0-9]*\\(?:_[A-Z0-9]+\\)*\\_>"
  "Python names conventionally used for constants.")

(defun my--theme-python-constant-face (face)
  "Use the constant role for neutral FACE, preserving specific classifications.
Static and declaration modifiers remain intact. Types, modules, functions,
parameters, enum members, comments and strings keep their existing faces."
  (let* ((faces (if (listp face) face (list face)))
         (neutral '(nil default font-lock-variable-name-face
                    font-lock-variable-use-face font-lock-property-use-face
                    lsp-face-semhl-variable lsp-face-semhl-property
                    lsp-face-semhl-member font-lock-constant-face
                    lsp-face-semhl-static landscape-semhl-declaration)))
    (if (seq-every-p (lambda (item) (memq item neutral)) faces)
        (cons 'font-lock-constant-face
              (seq-filter (lambda (item)
                            (memq item '(lsp-face-semhl-static
                                         landscape-semhl-declaration)))
                          faces))
      face)))

(defun my--theme-python-constant-at-point-face ()
  "Return the constant fallback face for the current Font Lock match."
  (let* ((position (match-beginning 0))
         (face (get-text-property position 'face)))
    (if (and (seq-some (lambda (theme)
                        (string-prefix-p "custom-" (symbol-name theme)))
                      custom-enabled-themes)
             (not (nth 8 (save-excursion
                           (save-match-data (syntax-ppss position))))))
        (my--theme-python-constant-face face)
      face)))

(defun my--theme-python-constant-font-lock-h ()
  "Add a theme-aware uppercase constant fallback to Python syntax highlighting."
  (font-lock-add-keywords
   nil `((,my-theme-python-constant-regexp
          (0 (my--theme-python-constant-at-point-face) t))) 'append))

(dolist (hook '(python-mode-hook python-ts-mode-hook))
  (add-hook hook #'my--theme-python-constant-font-lock-h))

(defun my--theme-python-fontify-constants (start end)
  "Apply the uppercase fallback after semantic highlighting from START to END."
  (when (derived-mode-p 'python-mode 'python-ts-mode)
    (save-excursion
      (save-match-data
        (goto-char start)
        (let ((case-fold-search nil))
          (while (re-search-forward my-theme-python-constant-regexp end t)
            (let ((begin (match-beginning 0)) (finish (match-end 0)))
              (put-text-property begin finish 'face
                                 (my--theme-python-constant-at-point-face)))))))))

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
            ;; Inspect server roles before parameter references are neutralized.
            (my--theme-python-fontify-constants start limit)
            (while (< position limit)
              (let* ((next (next-single-property-change position 'face nil limit))
                     (face (get-text-property position 'face))
                     (faces (if (listp face) face (list face))))
                (when (and (memq 'lsp-face-semhl-parameter faces)
                           (not (or (memq 'landscape-semhl-declaration faces)
                                    (memq 'lsp-rust-analyzer-declaration-modifier-face faces)))
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
    (if (lsp--semantic-tokens-as-defined-by-workspace workspace)
        (let ((lsp--cur-workspace workspace))
          (lsp--semantic-tokens-initialize-workspace workspace))
      ;; Ruff has no semantic tokens. Empty vectors are truthy and would mask
      ;; ty's real face maps when lsp-mode chooses the first workspace map.
      (setf (lsp--workspace-semantic-tokens-faces workspace) nil
            (lsp--workspace-semantic-tokens-modifier-faces workspace) nil)))
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
