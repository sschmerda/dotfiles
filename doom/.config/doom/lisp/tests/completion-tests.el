;;; completion-tests.el --- Fixed-height completion display -*- lexical-binding: t; -*-
;; emacs -Q --batch -l lisp/tests/completion-tests.el -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'cl-lib)
(let ((build (expand-file-name
              (format "~/.emacs.d/.local/straight/build-%d.%d"
                      emacs-major-version emacs-minor-version))))
  (dolist (directory (directory-files build t "^[^.]"))
    (when (file-directory-p directory) (add-to-list 'load-path directory))))
(require 'vertico)

;; Supply Doom's deferred-loading form in this isolated test process.
(defmacro after! (feature &rest body)
  `(with-eval-after-load ',feature ,@body))
(load (expand-file-name "../completion-config.el"
                        (file-name-directory (or load-file-name buffer-file-name))) nil t)

(ert-deftest my-completion-fixed-height-padding-is-display-only ()
  (let* ((vertico-resize nil)
         (vertico-count 5)
         (lines '("alpha\n" "beta\n"))
         (vertico--total 2)
         (vertico--candidates '("alpha" "beta")))
    (cl-letf (((symbol-function 'minibufferp) (lambda (&rest _) t)))
      (let ((padded (car (my--vertico-pad-fixed-height-a (list lines)))))
        (should (equal padded '("alpha\n" "beta\n" "\n" "\n" "\n")))
        (should (equal lines '("alpha\n" "beta\n")))
        (should (= vertico--total 2))
        (should (equal vertico--candidates '("alpha" "beta")))))))

(ert-deftest my-completion-padding-respects-dynamic-and-non-minibuffer-displays ()
  (let ((vertico-count 5) (args '(("alpha\n"))))
    (dolist (vertico-resize '(t grow-only))
      (cl-letf (((symbol-function 'minibufferp) (lambda (&rest _) t)))
        (should (eq (my--vertico-pad-fixed-height-a args) args))))
    (let ((vertico-resize nil))
      (with-temp-buffer
        (should (eq (my--vertico-pad-fixed-height-a args) args)))
      (cl-letf (((symbol-function 'minibufferp) (lambda (&rest _) t)))
        (let ((vertico-count 1))
          (should (eq (my--vertico-pad-fixed-height-a args) args)))))))

(ert-deftest my-completion-overlay-retains-fixed-height-after-results-disappear ()
  (with-temp-buffer
    (let ((vertico-resize nil)
          (vertico-count 5)
          (vertico--candidates-ov (make-overlay (point) (point)))
          (vertico--total 0))
      (cl-letf (((symbol-function 'minibufferp) (lambda (&rest _) t))
                ((symbol-function 'vertico--resize-window) #'ignore))
        (vertico--display-candidates nil)
        (let ((display (overlay-get vertico--candidates-ov 'before-string)))
          ;; One prompt separator plus five reserved candidate rows.
          (should (= (cl-count ?\n display) 6))
          (should (= vertico--total 0)))))))
