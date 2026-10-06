;;; olivetti-config.el -*- lexical-binding: t; -*-

;; Toggle Olivetti buffer centering without hiding modelines or other windows.
(use-package! olivetti
  :commands (olivetti-mode my/olivetti-toggle-all)
  :init
  (setq olivetti-body-width 120)
  (defvar my/olivetti-enabled nil)
  (defvar-local my/olivetti-border-face-cookie nil)
  (defun my/olivetti-buffer-eligible-p ()
    (and (not (minibufferp))
         (buffer-file-name)
         (not (derived-mode-p 'pdf-view-mode))
         (not (string-prefix-p " " (buffer-name)))
         (not (string-prefix-p "*" (buffer-name)))))
  (defun my/olivetti-enable-buffer (buffer)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (and (my/olivetti-buffer-eligible-p)
                   (not (bound-and-true-p olivetti-mode)))
          (olivetti-mode 1)))))
  (defun my/olivetti-disable-buffer (buffer)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (bound-and-true-p olivetti-mode)
          (olivetti-mode -1)))))
  (defun my/olivetti-disable-all-buffers ()
    (mapc #'my/olivetti-disable-buffer (buffer-list)))
  (defun my/olivetti-ignored-window-p (window)
    (with-current-buffer (window-buffer window)
      (derived-mode-p 'treemacs-mode)))
  (defun my/olivetti-refresh-visible-windows ()
    (walk-windows
     (lambda (window)
       (with-current-buffer (window-buffer window)
         (when (bound-and-true-p olivetti-mode)
           (olivetti-set-window window))))
     nil t))
  (defun my/olivetti-set-border-h ()
    (if olivetti-mode
        (progn
          (unless my/olivetti-border-face-cookie
            (setq my/olivetti-border-face-cookie
                  (face-remap-add-relative 'fringe :background "#2d2640")))
          (set-window-fringes nil 1 1 t))
      (when my/olivetti-border-face-cookie
        (face-remap-remove-relative my/olivetti-border-face-cookie)
        (setq my/olivetti-border-face-cookie nil))
      (set-window-fringes nil nil nil t)))
  (defun my/olivetti-vertical-split-p ()
    (let ((left-edges nil))
      (dolist (window (window-list nil 'no-minibuf))
        (unless (my/olivetti-ignored-window-p window)
          (push (window-left-column window) left-edges)))
      (> (length (delete-dups left-edges)) 1)))
  (defun my/olivetti-refresh-h (&rest _)
    (when (and my/olivetti-enabled
               (not (frame-parameter (selected-frame) 'my/time-popup)))
      (if (my/olivetti-vertical-split-p)
          (my/olivetti-disable-all-buffers)
        (mapc #'my/olivetti-enable-buffer (buffer-list))
        (my/olivetti-refresh-visible-windows))))
  (defun my/olivetti-toggle-all ()
    (interactive)
    (setq my/olivetti-enabled (not my/olivetti-enabled))
    (if my/olivetti-enabled
        (my/olivetti-refresh-h)
      (my/olivetti-disable-all-buffers)))
  (map! :leader
        :desc "Center buffers"
        "t o" #'my/olivetti-toggle-all)
  (add-hook 'olivetti-mode-hook #'my/olivetti-set-border-h)
  (add-hook 'buffer-list-update-hook #'my/olivetti-refresh-h)
  (add-hook 'window-state-change-functions #'my/olivetti-refresh-h)
  (add-hook! 'doom-first-buffer-hook
    (defun my/olivetti-enable-on-startup-h ()
      (setq my/olivetti-enabled t)
      (my/olivetti-refresh-h)))
  :config
  (setq olivetti-body-width 120))
