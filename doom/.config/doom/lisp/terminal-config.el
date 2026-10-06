;;; terminal-config.el -*- lexical-binding: t; -*-

;; Docker TRAMP processes may lack LOGNAME, which Ghostel's built-in login-shell
;; lookup uses. Query the effective user ID instead, without assuming a username
;; or that Zsh is installed. Keep the configured fallback and shell arguments.
(defun my/ghostel-docker-login-shell-a (original method)
  (if (and (equal method "docker")
           (equal (file-remote-p default-directory 'method) "docker")
           (eq (cadr (assoc method ghostel-tramp-shells)) 'login-shell))
      (let* ((spec (cdr (assoc method ghostel-tramp-shells)))
             (shell
              (ignore-errors
                (with-temp-buffer
                  (when (zerop (process-file "/bin/sh" nil t nil "-c"
                                             "getent passwd \"$(id -u)\""))
                    (let* ((entry (string-trim (buffer-string)))
                           (fields (split-string entry ":"))
                           (path (nth 6 fields)))
                      (when (and (= (length fields) 7)
                                 (file-name-absolute-p path)
                                 (file-executable-p
                                  (concat (file-remote-p default-directory) path)))
                        path)))))))
        (if shell
            (cons shell (cddr spec))
          (funcall original method)))
    (funcall original method)))

;; Docker terminals use the container user's login shell, falling back to sh.
(after! ghostel
  (setf (alist-get "docker" ghostel-tramp-shells nil nil #'equal)
        '(login-shell "/bin/sh"))
  (advice-add 'ghostel--tramp-shell-spec :around
              #'my/ghostel-docker-login-shell-a))

;; Keep the code/text column guide out of terminal buffers.
(defun my/hide-terminal-column-guide-h ()
  (display-fill-column-indicator-mode -1))

(add-hook 'ghostel-mode-hook #'my/hide-terminal-column-guide-h)
