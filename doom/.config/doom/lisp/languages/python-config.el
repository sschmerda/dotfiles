;;; python-config.el -*- lexical-binding: t; -*-

;; Default to Black for Python; projects can override `apheleia-formatter'.
(after! apheleia
  (set-formatter! 'black :modes '(python-mode python-ts-mode)))

(defun my--python-detect-lsp-setup ()
  "Return local Python client selection from the current executable search path.
Prefer ty, then BasedPyright, then Pyright, with Ruff as an optional companion.
The Pyright backend is also returned when ty is selected, for remote clients."
  (let* ((backend (cond ((executable-find "basedpyright-langserver") "basedpyright")
                        ((executable-find "pyright-langserver") "pyright")))
         (server (cond ((executable-find "ty") 'ty-ls)
                       (backend 'pyright))))
    (list :backend (or backend "pyright")
          ;; A nonempty allowlist prevents unrelated Python servers from starting
          ;; even if none of the preferred executables are installed.
          :clients (or (append (when server (list server))
                               (when (executable-find "ruff") '(ruff)))
                       '(my-python-no-server)))))

(defvar my-python-lsp-clients nil
  "Local Python LSP clients selected at configuration load time.
Restart Emacs after installing or removing server executables.")

;; Choose before lsp-pyright registers executable paths and server settings.
;; Inspect the local Emacs PATH even if this file is loaded from a TRAMP buffer.
(let* ((default-directory "/")
       (setup (my--python-detect-lsp-setup)))
  (setq my-python-lsp-clients (plist-get setup :clients)
        lsp-pyright-langserver-command (plist-get setup :backend)))

(defun my--python-enable-semantic-tokens-h ()
  "Configure Python clients and semantic colors for the current buffer."
  (setq-local lsp-semantic-tokens-enable t)
  ;; Installed ty and Ruff clients are both add-ons. An explicit allowlist is
  ;; needed to prevent ty and Pyright starting together regardless of priority.
  ;; Keep the existing remote Pyright setup: these ty/Ruff clients are local.
  (unless (file-remote-p default-directory)
    (setq-local lsp-enabled-clients (copy-sequence my-python-lsp-clients))))

(dolist (hook '(python-mode-hook python-ts-mode-hook))
  (add-hook hook #'my--python-enable-semantic-tokens-h))

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
                    '(ty-ls pyright pyright-remote basedpyright pylsp ruff))
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
