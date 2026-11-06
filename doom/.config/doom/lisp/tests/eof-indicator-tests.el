;;; eof-indicator-tests.el --- Centered and ordinary EOF markers -*- lexical-binding: t; -*-
;; emacs -Q --batch -l lisp/tests/eof-indicator-tests.el -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'cl-lib)
(require 'fringe)
(require 'face-remap)

;; Load only the tested definitions, avoiding Doom's configuration macros.
(let* ((file (expand-file-name "../olivetti-config.el"
                               (file-name-directory (or load-file-name buffer-file-name))))
       (package (with-temp-buffer (insert-file-contents file) (read (current-buffer)))))
  (dolist (form (cdr package))
    (when (and (consp form)
               (memq (car form) '(defun defvar-local))
               (memq (cadr form) '(my-olivetti-original-fringe-indicators
                                  my--olivetti-empty-line-bitmap
                                  my-olivetti-final-line-overlay
                                  my-olivetti-final-line-display
                                  my--olivetti-update-final-line-marker-h
                                  my--olivetti-clear-final-line-marker-h
                                  my--olivetti-sync-empty-line-indicator)))
      (eval form t))))

(defvar my-test-eof-bitmaps nil)
(defvar my-test-eof-graphical t)

(defmacro my-test-with-eof-display (&rest body)
  `(let ((my-test-eof-bitmaps (make-hash-table)) (my-test-eof-graphical t))
     ;; Headless regression checks with explicit display metrics. Actual GUI
     ;; bitmap installation and window transitions are verified separately.
     (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) my-test-eof-graphical))
               ((symbol-function 'frame-char-height) (lambda (&optional _) 20))
               ((symbol-function 'window-fringes) (lambda (&optional _) '(8 8 nil nil)))
               ((symbol-function 'fringe-bitmap-p) (lambda (symbol) (gethash symbol my-test-eof-bitmaps)))
               ((symbol-function 'define-fringe-bitmap)
                (lambda (symbol rows height width &rest _)
                  (puthash symbol (list (copy-sequence rows) height width) my-test-eof-bitmaps)))
               ((symbol-function 'set-fringe-bitmap-face) #'ignore))
       (with-temp-buffer ,@body))))

(ert-deftest my-eof-centered-to-split-keeps-tilde-without-border ()
  (my-test-with-eof-display
   (let ((window (selected-window)) (original (copy-tree fringe-indicator-alist)))
     (my--olivetti-sync-empty-line-indicator window t)
     (let* ((border-symbol (cdr (assq 'empty-line fringe-indicator-alist)))
            (border-rows (car (gethash border-symbol my-test-eof-bitmaps))))
       (should (cl-every (lambda (row) (/= 0 (logand row #x80))) border-rows)))
     (my--olivetti-sync-empty-line-indicator window nil)
     (let* ((plain (cdr (assq 'empty-line fringe-indicator-alist)))
            (rows (car (gethash plain my-test-eof-bitmaps))))
       (should-not (eq plain 'empty-line))
       (should (= 2 (cl-count-if (lambda (row) (> row 0)) rows)))
       (should (cl-every (lambda (row) (= 0 (logand row #x80))) rows))
       (my--olivetti-sync-empty-line-indicator window t)
       (my--olivetti-sync-empty-line-indicator window nil)
       (should (eq plain (cdr (assq 'empty-line fringe-indicator-alist)))))
     (should (= 1 (cl-count 'empty-line fringe-indicator-alist :key #'car)))
     (should (equal (assq-delete-all 'empty-line (copy-tree fringe-indicator-alist))
                    (assq-delete-all 'empty-line original))))))

(ert-deftest my-eof-normal-window-and-zoom ()
  (my-test-with-eof-display
   (setq-local indicate-empty-lines t text-scale-mode-amount 0)
   (my--olivetti-sync-empty-line-indicator (selected-window) nil)
   (let ((unscaled (cdr (assq 'empty-line fringe-indicator-alist))))
     (setq-local text-scale-mode-amount 2)
     (my--olivetti-sync-empty-line-indicator (selected-window) nil)
     (let ((scaled (cdr (assq 'empty-line fringe-indicator-alist))))
       (should-not (eq scaled unscaled))
       (should (> (cadr (gethash scaled my-test-eof-bitmaps))
                  (cadr (gethash unscaled my-test-eof-bitmaps))))))
   (should indicate-empty-lines)))

(ert-deftest my-eof-terminal-restores-original-mapping ()
  (my-test-with-eof-display
   (let ((original (copy-tree fringe-indicator-alist)))
     (setq-local indicate-empty-lines nil)
     (my--olivetti-sync-empty-line-indicator (selected-window) t)
     (setq my-test-eof-graphical nil)
     (my--olivetti-sync-empty-line-indicator (selected-window) nil)
     (should (equal fringe-indicator-alist original))
     (should-not my-olivetti-original-fringe-indicators)
     (should-not indicate-empty-lines))))

(ert-deftest my-eof-last-editable-line-has-no-tilde ()
  (dolist (text '("" "alpha\n" "alpha\n\n"))
    (my-test-with-eof-display
     (insert text)
     (setq-local indicate-empty-lines t)
     (set-buffer-modified-p nil)
     (my--olivetti-sync-empty-line-indicator (selected-window) nil)
     (let* ((overlay my-olivetti-final-line-overlay)
            (display (get-text-property 0 'display (overlay-get overlay 'before-string)))
            (rows (car (gethash (cadr display) my-test-eof-bitmaps))))
       (should (= (overlay-start overlay) (point-max)))
       (should (cl-every #'zerop rows))
       (should (equal text (buffer-string)))
       (should-not (buffer-modified-p))
       ;; Rows below EOF still use the normal tilde bitmap.
       (should-not (eq (cadr display) (cdr (assq 'empty-line fringe-indicator-alist))))))))

(ert-deftest my-eof-final-line-marker-follows-edits ()
  (my-test-with-eof-display
   (insert "alpha\n")
   (setq-local indicate-empty-lines t)
   (my--olivetti-sync-empty-line-indicator (selected-window) t)
   (let* ((overlay my-olivetti-final-line-overlay)
          (display (get-text-property 0 'display (overlay-get overlay 'before-string)))
          (rows (car (gethash (cadr display) my-test-eof-bitmaps))))
     (should (cl-every (lambda (row) (= row #x80)) rows)))
   (insert "text")
   (should-not my-olivetti-final-line-overlay)
   (insert "\n")
   (should (= (overlay-start my-olivetti-final-line-overlay) (point-max)))
   (delete-char -1)
   (should-not my-olivetti-final-line-overlay)))

(ert-deftest my-eof-major-mode-reset-cleans-overlay ()
  (my-test-with-eof-display
   (setq-local indicate-empty-lines t)
   (my--olivetti-sync-empty-line-indicator (selected-window) nil)
   (let ((overlay my-olivetti-final-line-overlay))
     (fundamental-mode)
     (should-not (overlay-buffer overlay))
     (should-not my-olivetti-final-line-overlay))))
