;;; python-config.el -*- lexical-binding: t; -*-

(require 'cl-lib)

;; Default to Black for Python; projects can override `apheleia-formatter'.
(after! apheleia
  (set-formatter! 'black :modes '(python-mode python-ts-mode)))

;; This lsp-mode version checks semantic capabilities under synthetic feature
;; names, but sends real protocol methods without filtering their recipients.
;; Register the actual methods too, so ty's token requests cannot reach Ruff
;; (including while Ruff is still waiting for its initialized notification).
(after! lsp-mode
  (dolist (entry '(("textDocument/semanticTokens/range"
                   . "textDocument/semanticTokensRangeProvider")
                  ("textDocument/semanticTokens/full"
                   . "textDocument/semanticTokensFull")
                  ("textDocument/semanticTokens/full/delta"
                   . "textDocument/semanticTokensFull/Delta")))
    (unless (assoc (car entry) lsp-method-requirements)
      (when-let ((requirement (assoc (cdr entry) lsp-method-requirements)))
        (push (cons (car entry) (cdr requirement)) lsp-method-requirements)))))

(defvar my-python-lsp-preference 'auto
  "Session-wide local Python server choice; auto, ty, pyrefly, basedpyright or pyright.
Use `my/python-lsp-switch' to change it and reconnect active Python buffers.")

(defconst my-python-lsp-executables
  '((ty . "ty") (pyrefly . "pyrefly")
    (basedpyright . "basedpyright-langserver") (pyright . "pyright-langserver")))

(defun my--python-detect-lsp-setup (&optional preference)
  "Select one local primary server and optional Ruff from PATH.
PREFERENCE defaults to auto: ty, Pyrefly, BasedPyright, then Pyright.
Explicit choices fail if missing, rather than silently selecting another server."
  (let* ((preference (or preference 'auto))
         (backend (if (executable-find "basedpyright-langserver") "basedpyright" "pyright"))
         (server (if (eq preference 'auto)
                     (cl-loop for (name . executable) in my-python-lsp-executables
                              when (executable-find executable) return name)
                   (let ((executable (alist-get preference my-python-lsp-executables)))
                     (unless (and executable (executable-find executable))
                       (user-error "Python LSP executable unavailable: %s" (or executable preference)))
                     preference)))
         (client (pcase server ('ty 'ty-ls) ('pyrefly 'pyrefly)
                        ((or 'basedpyright 'pyright) 'pyright))))
    (when (memq server '(basedpyright pyright)) (setq backend (symbol-name server)))
    (list :server server :backend backend
          :clients (or (append (when client (list client))
                               (when (executable-find "ruff") '(ruff)))
                       '(my-python-no-server)))))

(defvar my-python-lsp-clients nil "Selected local Python LSP clients.")
(defvar my-python-lsp-backend nil "Selected local Pyright executable prefix.")

;; Select before lsp-pyright registers its settings and remote fallback.
(let* ((default-directory "/")
       (setup (my--python-detect-lsp-setup my-python-lsp-preference)))
  (setq my-python-lsp-clients (plist-get setup :clients)
        my-python-lsp-backend (plist-get setup :backend)
        lsp-pyright-langserver-command my-python-lsp-backend))

(defun my--python-enable-semantic-tokens-h ()
  "Configure local Python clients and semantic colors for this buffer."
  (setq-local lsp-semantic-tokens-enable t)
  (unless (file-remote-p default-directory)
    (setq-local lsp-enabled-clients (copy-sequence my-python-lsp-clients))
    (setq-local lsp-pyright-langserver-command my-python-lsp-backend)))

(dolist (hook '(python-mode-hook python-ts-mode-hook))
  (add-hook hook #'my--python-enable-semantic-tokens-h))

(after! lsp-mode
  ;; The installed lsp-mode has no Pyrefly client. Prefer a native one if present.
  (unless (gethash 'pyrefly lsp-clients)
    (lsp-register-client
     (make-lsp-client :new-connection (lsp-stdio-connection '("pyrefly" "lsp"))
                      :major-modes '(python-mode python-ts-mode)
                      :priority 1 :server-id 'pyrefly))))

(after! lsp-pyright
  ;; The stock client's dependency captures one executable when it loads.
  ;; Resolve the selected local backend on connection; retain the remote client.
  (setf (lsp--client-new-connection (gethash 'pyright lsp-clients))
        (lsp-stdio-connection
         (lambda () (cons (concat my-python-lsp-backend "-langserver")
                         lsp-pyright-langserver-command-args))))
  ;; Both backends must receive their settings after a runtime switch.
  (dolist (backend '("pyright" "basedpyright"))
    (lsp-register-custom-settings
     `((,(concat backend ".disableLanguageServices") lsp-pyright-disable-language-services t)
       (,(concat backend ".disableOrganizeImports") lsp-pyright-disable-organize-imports t)
       (,(concat backend ".disableTaggedHints") lsp-pyright-disable-tagged-hints t)
       (,(concat backend ".typeCheckingMode") lsp-pyright-type-checking-mode)
       (,(concat backend ".analysis.diagnosticSeverityOverrides")
        (lambda () (ht-from-alist lsp-pyright-diagnostic-severity-overrides)))))))

(defun my/python-lsp-switch (preference)
  "Select a local Python language server for this Emacs session.
Choose auto (ty -> Pyrefly -> BasedPyright -> Pyright), or an installed server.
Ruff remains an optional companion. Reconnect all active local Python buffers;
new Python buffers use the same selection. Remote buffers are unchanged.
This changes server selection, not the Python environment or formatter."
  (interactive
   (list (intern
          (completing-read "Python language server: "
                           (cons "auto" (cl-loop for (name . executable) in my-python-lsp-executables
                                                  when (executable-find executable)
                                                  collect (symbol-name name)))
                           nil t nil nil (symbol-name my-python-lsp-preference)))))
  (when (file-remote-p default-directory)
    (user-error "Python server switching currently supports local buffers only"))
  (let ((setup (my--python-detect-lsp-setup preference))
        (origin (current-buffer)) buffers workspaces)
    ;; Validate before shutting down anything.
    (require 'lsp-mode)
    (require 'lsp-pyright)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and (derived-mode-p 'python-mode 'python-ts-mode)
                   (not (file-remote-p default-directory)))
          (when (or (lsp-workspaces) (and (eq buffer origin) buffer-file-name))
            (push buffer buffers))
          (dolist (workspace (lsp-workspaces))
            (when (memq (lsp--client-server-id (lsp--workspace-client workspace))
                        '(ty-ls pyrefly pyright basedpyright pylsp ruff))
              (cl-pushnew workspace workspaces))))))
    (setq my-python-lsp-preference preference
          my-python-lsp-clients (plist-get setup :clients)
          my-python-lsp-backend (plist-get setup :backend))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (and (derived-mode-p 'python-mode 'python-ts-mode)
                   (not (file-remote-p default-directory)))
          (my--python-enable-semantic-tokens-h))))
    ;; Detach hidden buffers explicitly: exit callbacks may otherwise leave old
    ;; workspace references until those buffers become visible again.
    (dolist (buffer buffers)
      (with-current-buffer buffer
        (when (bound-and-true-p lsp-mode) (lsp-disconnect))))
    (dolist (workspace workspaces) (lsp-workspace-shutdown workspace))
    (dolist (buffer buffers)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (lsp-deferred))))
    (message "Python LSP: %s%s" (or (plist-get setup :server) "none available")
             (if (memq 'ruff my-python-lsp-clients) " + Ruff" ""))))

;; Keep Conda reactivation valid and refresh Python LSP after switching environments.
(after! conda
  (require 'conda)

  (defun my--conda-repair-prefix-a (&rest _)
    "Recover activation variables lost by conda.el's old switching order."
    (when (and conda-env-current-path
               (not (getenv "CONDA_PREFIX")))
      (setenv "CONDA_PREFIX" (directory-file-name
                              (expand-file-name conda-env-current-path)))
      (setenv "CONDA_DEFAULT_ENV" conda-env-current-name))
    (when (and conda-env-current-path
               (let ((level (string-to-number (or (getenv "CONDA_SHLVL") "0"))))
                 (or (< level 1)
                     (cl-loop for index from 1 below level
                              thereis (not (getenv (format "CONDA_PREFIX_%d" index)))))))
      ;; A stack with missing prefixes cannot be deactivated. Retain the known
      ;; current environment as the only level; leave valid inherited stacks alone.
      (dolist (entry (copy-sequence process-environment))
        (when (string-match "\\`\\(CONDA_\\(?:PREFIX\\|STACKED\\)_[0-9]+\\)\\(?:=\\|\\'\\)" entry)
          (setenv (match-string 1 entry) nil)))
      (setenv "CONDA_SHLVL" "1")))

  (defun my--conda-switch-in-order-a (original &optional path)
    "Deactivate before computing the new environment's activation delta."
    (let ((target (or path (read-directory-name "Conda environment directory: "))))
      (unless (conda--env-dir-is-valid target)
        (user-error "Invalid conda environment path: %s" target))
      ;; Upstream computes the delta first, then deactivates, invalidating that
      ;; delta (including omitted unchanged variables and saved stack prefixes).
      ;; Switching has an intermediate deactivation; restart only after activation.
      (let ((conda-postdeactivate-hook
             (remq #'my--conda-restart-python-lsp-h conda-postdeactivate-hook)))
        (conda-env-deactivate))
      (funcall original target)))

  (defun my--conda-restart-python-lsp-h ()
    "Refresh the current buffer's Python servers after an environment change."
    (when (bound-and-true-p lsp-mode)
      (dolist (workspace (lsp-workspaces))
        (when (memq (lsp--client-server-id (lsp--workspace-client workspace))
                    '(ty-ls pyrefly pyright pyright-remote basedpyright pylsp ruff))
          (lsp-workspace-restart workspace)))))

  (advice-add 'conda-env-activate-path :around #'my--conda-switch-in-order-a)
  (advice-add 'conda-env-deactivate :before #'my--conda-repair-prefix-a)
  (add-hook 'conda-postactivate-hook #'my--conda-restart-python-lsp-h)
  (add-hook 'conda-postdeactivate-hook #'my--conda-restart-python-lsp-h)

  (provide 'my-conda-switching))

;; Older Pyright versions need this explicitly to navigate untyped libraries like pandas.
(after! lsp-pyright
  (defvar my-pyright-use-library-code-for-types t)
  (lsp-register-custom-settings
   '(("python.analysis.useLibraryCodeForTypes" my-pyright-use-library-code-for-types t))))
