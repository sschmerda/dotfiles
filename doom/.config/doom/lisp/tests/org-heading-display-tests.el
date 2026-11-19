;;; org-heading-display-tests.el -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(let ((build (expand-file-name (format "~/.emacs.d/.local/straight/build-%d.%d/"
                                      emacs-major-version emacs-minor-version))))
  (dolist (directory (directory-files build t "^[^.]"))
    (when (file-directory-p directory) (add-to-list 'load-path directory))))
(require 'org)
(require 'org-indent)
(require 'org-modern)
(with-temp-buffer
  (insert-file-contents (expand-file-name "../org-config.el"
                                         (file-name-directory load-file-name)))
  (condition-case nil
      (while t
        (let ((form (read (current-buffer))))
          (when (and (eq (car-safe form) 'defun)
                     (memq (cadr form) '(my--org-blank-leading-stars-a my--org-blank-indent-stars-a)))
            (eval form t))))
    (end-of-file nil)))

(ert-deftest my-org-heading-stars-remain-hidden-over-highlights ()
  (advice-add 'org-modern--star :after #'my--org-blank-leading-stars-a)
  (advice-add 'org-indent--compute-prefixes :after #'my--org-blank-indent-stars-a)
  (unwind-protect
      (with-temp-buffer
        (insert "* One\n** Two\n*** Three\nbody\n")
        (org-mode)
        (org-indent-mode 1)
        (org-modern-mode 1)
        (font-lock-ensure)
        (let ((original (buffer-string)))
          (goto-char (point-min))
          (while (re-search-forward "^\\(\\**\\)\\* " nil t)
            (let ((begin (match-beginning 1)) (end (match-end 1)))
              (cl-loop for pos from begin below end do
                       (should (equal (get-text-property pos 'display) " ")))
              (should (get-text-property end 'display))
              (let ((prefix (get-text-property begin 'line-prefix)))
                (when prefix (should-not (string-match-p "\\*" prefix))))))
          ;; Refilling and highlighting must never rewrite the Org source.
          (should (equal (substring-no-properties original)
                         (buffer-substring-no-properties (point-min) (point-max))))
          (org-modern-mode -1)
          (setq-local org-hide-leading-stars nil)
          (font-lock-flush)
          (font-lock-ensure)
          (goto-char (point-min))
          (search-forward "** Two")
          (should-not (get-text-property (- (point) 6) 'display))))
    (advice-remove 'org-modern--star #'my--org-blank-leading-stars-a)
    (advice-remove 'org-indent--compute-prefixes #'my--org-blank-indent-stars-a)))
