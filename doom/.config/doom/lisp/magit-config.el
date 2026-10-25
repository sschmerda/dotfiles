;;; magit-config.el -*- lexical-binding: t; -*-

(defun my--magit-enable-relative-line-numbers-h ()
  "Count visible lines for relative motions across folded Magit sections."
  (setq-local display-line-numbers-type 'visual)
  (display-line-numbers-mode 1))

(defun my/magit-clear-file-filter ()
  "Clear active and suspended file filters in the current Magit buffer."
  (interactive)
  (setq magit-buffer-diff-files nil
        magit-buffer-diff-files-suspended nil)
  (magit-refresh))

(defun my/magit-filter-directory (directory)
  "Limit the current Magit buffer to DIRECTORY inside this repository."
  (interactive
   (list (let ((default-directory (magit-toplevel)))
           (read-directory-name "Filter by directory: " default-directory nil t))))
  (let* ((root (magit-toplevel))
         (directory (file-name-as-directory (expand-file-name directory))))
    (unless (or (equal (file-truename directory) (file-truename root))
                (file-in-directory-p directory root))
      (user-error "Choose a directory inside this repository"))
    (setq magit-buffer-diff-files
          (unless (equal (file-truename directory) (file-truename root))
            (list (file-relative-name directory root)))
          magit-buffer-diff-files-suspended nil)
    (magit-refresh)))

(after! magit-diff
  ;; Add an explicit reset beside Magit's existing file-filter toggle.
  (unless (ignore-errors (transient-get-suffix 'magit-diff-refresh "C"))
    (transient-append-suffix 'magit-diff-refresh "F"
      '("C" "Clear file filter" my/magit-clear-file-filter)))
  (unless (ignore-errors (transient-get-suffix 'magit-diff-refresh "/"))
    (transient-append-suffix 'magit-diff-refresh "C"
      '("/" "Filter by directory" my/magit-filter-directory))))

(after! magit
  ;; Doom disables numbers in Magit by default; replace that hook.
  (remove-hook 'magit-mode-hook #'doom-disable-line-numbers-h)
  (add-hook 'magit-mode-hook #'my--magit-enable-relative-line-numbers-h))

(after! magit-margin
  ;; Magit normally hides these overlays by giving the right margin no width.
  ;; Olivetti's padding also uses that margin, so skip disabled annotations.
  (defun my--magit-respect-margin-visibility-a (original &rest args)
    "Create margin annotations only when Magit's margin is enabled."
    (when (magit--right-margin-active)
      (apply original args)))
  (advice-add 'magit-make-margin-overlay :around
              #'my--magit-respect-margin-visibility-a)
  ;; Toggling the margin must rebuild annotations removed while disabled.
  (advice-add 'magit-toggle-margin :after #'magit-refresh))

(after! (evil magit)
  ;; On Emacs 29, multi-line visual motion can undercount folded boundaries.
  ;; Single screen-line steps consistently skip Magit's invisible overlays.
  (evil-define-motion my/magit-previous-visible-line (count)
    "Move COUNT visible lines up, including across folded Magit sections."
    :type exclusive
    (dotimes (_ (or count 1))
      (evil-previous-visual-line 1)))
  (map! :map magit-mode-map
        :nv "k" #'my/magit-previous-visible-line))
