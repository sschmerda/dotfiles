;;; python-lsp-selection-tests.el --- Python client selection tests -*- lexical-binding: t; -*-

;; Run with emacs -Q --batch -l this-file -f ert-run-tests-batch-and-exit.
(require 'ert)
(require 'cl-lib)
(defvar my--python-lsp-routing-configuration nil)

;; Load only the selection functions, without running Doom package configuration
;; or changing this process's environment/hooks.
(with-temp-buffer
  (insert-file-contents
   (expand-file-name "../languages/python-config.el"
                     (file-name-directory (or load-file-name buffer-file-name))))
  (goto-char (point-min))
  (condition-case nil
      (while t
        (let ((form (read (current-buffer))))
          (when (and (eq (car-safe form) 'after!) (eq (cadr form) 'lsp-mode))
            (setq my--python-lsp-routing-configuration (cons 'progn (cddr form))))
          (when (and (eq (car-safe form) 'defun)
                     (memq (cadr form)
                           '(my--python-detect-lsp-setup
                             my--python-enable-semantic-tokens-h)))
            (eval form t))))
    (end-of-file nil)))

(defvar my-python-lsp-clients)
(defvar lsp-enabled-clients)
(defvar lsp-semantic-tokens-enable)

(ert-deftest my-python-lsp-semantic-requests-skip-ruff ()
  (let ((build (or (getenv "DOOM_LSP_BUILD")
                   (expand-file-name
                    (format "~/.emacs.d/.local/straight/build-%d.%d/"
                            emacs-major-version emacs-minor-version)))))
    (dolist (directory (directory-files build t "^[^.]" t))
      (add-to-list 'load-path directory)))
  (require 'lsp-mode)
  (let ((lsp-method-requirements (copy-tree lsp-method-requirements)))
    (eval my--python-lsp-routing-configuration t)
    (with-temp-buffer
      (let* ((ty (make-lsp--workspace
                  :client (make-lsp-client :server-id 'ty-ls) :status 'initialized
                  :server-capabilities
                  (json-parse-string
                   "{\"semanticTokensProvider\":{\"range\":true,\"full\":{\"delta\":true}}}"
                   :object-type (if lsp-use-plists 'plist 'hash-table)))))
        (dolist (status '(starting initialized))
          (setq-local lsp--buffer-workspaces
                      (list (make-lsp--workspace
                             :client (make-lsp-client :server-id 'ruff)
                             :status status)
                            ty))
          (dolist (method '("textDocument/semanticTokens/range"
                            "textDocument/semanticTokens/full"
                            "textDocument/semanticTokens/full/delta"))
            (should (equal (lsp--find-workspaces-for method) (list ty)))))
        ;; Newer lsp-mode registrations must not be overwritten on reload.
        (setf (alist-get "textDocument/semanticTokens/range"
                         lsp-method-requirements nil nil #'equal)
              '(:capability :futureProvider))
        (eval my--python-lsp-routing-configuration t)
        (should (equal (cdr (assoc "textDocument/semanticTokens/range"
                                   lsp-method-requirements))
                       '(:capability :futureProvider)))))))

(ert-deftest my-python-lsp-selection-fallbacks ()
  ;; All combinations cover absent tools, Ruff alone and both Pyright variants.
  (dotimes (mask 16)
    (let* ((tools '("ty" "basedpyright-langserver" "pyright-langserver" "ruff"))
           (available (cl-loop for tool in tools for bit from 0
                               when (/= 0 (logand mask (ash 1 bit))) collect tool)))
      (cl-letf (((symbol-function 'executable-find)
                 (lambda (name &optional _remote)
                   (and (member name available) (concat "/tools/" name)))))
        (let* ((setup (my--python-detect-lsp-setup))
               (primary (cond ((/= 0 (logand mask (ash 1 0))) 'ty-ls)
                              ((or (/= 0 (logand mask (ash 1 1))) (/= 0 (logand mask (ash 1 2)))) 'pyright)))
               (expected (append (when primary (list primary))
                                 (when (/= 0 (logand mask (ash 1 3))) '(ruff)))))
          (should (equal (plist-get setup :clients)
                         (or expected '(my-python-no-server))))
          (should (equal (plist-get setup :backend)
                         (if (/= 0 (logand mask (ash 1 1))) "basedpyright" "pyright"))))))))

(ert-deftest my-python-lsp-allowlist-is-buffer-local ()
  (let ((my-python-lsp-clients '(ty-ls ruff))
        (lsp-enabled-clients '(unrelated-server)))
    (with-temp-buffer
      (let ((default-directory temporary-file-directory))
        (my--python-enable-semantic-tokens-h)
        (should (local-variable-p 'lsp-enabled-clients))
        (should (equal lsp-enabled-clients '(ty-ls ruff)))
        (should lsp-semantic-tokens-enable)))
    (should (equal lsp-enabled-clients '(unrelated-server)))))

(ert-deftest my-python-lsp-remote-selection-preserved ()
  (let ((my-python-lsp-clients '(ty-ls ruff))
        (lsp-enabled-clients '(pyright-remote)))
    (with-temp-buffer
      ;; Parsing a TRAMP name does not establish a connection.
      (let ((default-directory "/ssh:example.invalid:/project/"))
        (my--python-enable-semantic-tokens-h)
        (should-not (local-variable-p 'lsp-enabled-clients))
        (should (equal lsp-enabled-clients '(pyright-remote)))))))
