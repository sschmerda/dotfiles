;;; python-config.el -*- lexical-binding: t; -*-

;; Keep Conda reactivation valid and refresh Python LSP after switching environments.
(after! conda
  (require 'conda)

  (defun my/conda-repair-prefix-a (&rest _)
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

  (defun my/conda-switch-in-order-a (original &optional path)
    "Deactivate before computing the new environment's activation delta."
    (let ((target (or path (read-directory-name "Conda environment directory: "))))
      (unless (conda--env-dir-is-valid target)
        (user-error "Invalid conda environment path: %s" target))
      ;; Upstream computes the delta first, then deactivates, invalidating that
      ;; delta (including omitted unchanged variables and saved stack prefixes).
      ;; Switching has an intermediate deactivation; restart only after activation.
      (let ((conda-postdeactivate-hook
             (remq #'my/conda-restart-python-lsp-h conda-postdeactivate-hook)))
        (conda-env-deactivate))
      (funcall original target)))

  (defun my/conda-restart-python-lsp-h ()
    "Refresh the current buffer's Python servers after an environment change."
    (when (bound-and-true-p lsp-mode)
      (dolist (workspace (lsp-workspaces))
        (when (memq (lsp--client-server-id (lsp--workspace-client workspace))
                    '(pyright basedpyright pylsp))
          (lsp-workspace-restart workspace)))))

  (advice-add 'conda-env-activate-path :around #'my/conda-switch-in-order-a)
  (advice-add 'conda-env-deactivate :before #'my/conda-repair-prefix-a)
  (add-hook 'conda-postactivate-hook #'my/conda-restart-python-lsp-h)
  (add-hook 'conda-postdeactivate-hook #'my/conda-restart-python-lsp-h)

  (provide 'my-conda-switching))

;; Older Pyright versions need this explicitly to navigate untyped libraries like pandas.
(after! lsp-pyright
  (defvar my/pyright-use-library-code-for-types t)
  (lsp-register-custom-settings
   '(("python.analysis.useLibraryCodeForTypes" my/pyright-use-library-code-for-types t))))
