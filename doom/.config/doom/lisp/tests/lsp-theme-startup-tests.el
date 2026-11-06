;;; lsp-theme-startup-tests.el --- Cold theme/LSP initialization -*- lexical-binding: t; -*-

;; Run with emacs -Q --batch -l this-file -f ert-run-tests-batch-and-exit.
(require 'ert)
(require 'cl-lib)

(defconst my--lsp-test-doom-directory
  (expand-file-name "../../" (file-name-directory load-file-name)))

(ert-deftest my-theme-lsp-compiled-cold-start ()
  (let* ((build (or (getenv "DOOM_LSP_BUILD")
                    (expand-file-name
                     (format ".emacs.d/.local/straight/build-%d.%d/"
                             emacs-major-version emacs-minor-version)
                     "~/")))
         (temporary (make-temp-file "doom-theme-lsp-test-" t))
         (source (expand-file-name "themes-config.el" temporary))
         (emacs (expand-file-name invocation-name invocation-directory))
         (paths (append (directory-files build t "^[^.]" t) load-path))
         (setup `((setq load-path ',paths)
                  (setq doom-user-dir ,my--lsp-test-doom-directory))))
    (unwind-protect
        (progn
          (copy-file (expand-file-name "lisp/themes-config.el"
                                       my--lsp-test-doom-directory) source)
          (with-temp-buffer
            (should
             (= 0 (call-process
                   emacs nil (current-buffer) nil "-Q" "--batch" "--eval"
                   (prin1-to-string
                    `(progn ,@setup
                            (unless (byte-compile-file ,source)
                              (error "Theme configuration did not compile"))))))))
          ;; A separate process ensures lsp-mode's struct setters were not
          ;; incidentally loaded before the compiled configuration.
          (with-temp-buffer
            (let ((exit-code
                   (call-process
                    emacs nil (current-buffer) nil "-Q" "--batch" "--eval"
                    (prin1-to-string
                     `(progn
                        ,@setup
                        (load ,(concat source "c") nil t)
                        (require 'lsp-mode)
                        (require 'lsp-semantic-tokens)
                        (require 'lsp-pyright)
                        (let ((client (gethash 'pyright lsp-clients)))
                          (cl-assert
                           (eq (cdr (assoc "selfParameter"
                                           (plist-get
                                            (lsp--client-semantic-tokens-faces-overrides client)
                                            :types)))
                               'landscape-receiver)))
                        (with-temp-buffer
                          (let* ((client (gethash 'pyright lsp-clients))
                                 (ruff (make-lsp--workspace :client client))
                                 (ty (make-lsp--workspace
                                      :client client
                                      :server-capabilities
                                      '(:semanticTokensProvider
                                        (:legend (:tokenTypes ["variable"]
                                                  :tokenModifiers []))))))
                            (setq-local lsp--buffer-workspaces (list ruff ty))
                            (my--theme-refresh-receiver-faces-h)
                            (cl-assert (null (lsp--workspace-semantic-tokens-faces ruff)))
                            (cl-assert (= 1 (length (lsp--workspace-semantic-tokens-faces ty)))))))))))
              (ert-info ((buffer-string)) (should (= exit-code 0))))))
      (delete-directory temporary t))))
