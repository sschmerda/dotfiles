;;; documentation-tests.el --- Documentation window behavior -*- lexical-binding: t; -*-
;; Run from DOOMDIR: emacs -Q --batch -l lisp/tests/documentation-tests.el
;;   -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'cl-lib)
(let ((build (expand-file-name
              (format "~/.emacs.d/.local/straight/build-%d.%d"
                      emacs-major-version emacs-minor-version))))
  (dolist (directory (directory-files build t "^[^.]"))
    (when (file-directory-p directory) (add-to-list 'load-path directory))))
(load (expand-file-name "../documentation-config.el"
                        (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defvar my-test-doc-calls 0)
(defvar my-test-doc-buffer nil)
(defvar my-test-doc-select t)
(defvar my-test-doc-display t)
(defvar my-test-doc-rewrite t)
(defvar my-test-doc-same-window nil)
(defvar my-test-doc-call-buffers nil)

(defun my-test-doc-backend ()
  (interactive)
  (cl-incf my-test-doc-calls)
  (push (current-buffer) my-test-doc-call-buffers)
  (when my-test-doc-display
    (when my-test-doc-rewrite
      (with-current-buffer my-test-doc-buffer
      (help-mode)
      (let ((inhibit-read-only t))
        (erase-buffer) (insert (format "Documentation %d" my-test-doc-calls)))))
    (let ((window (if my-test-doc-same-window
                      (progn (switch-to-buffer my-test-doc-buffer) (selected-window))
                    (display-buffer my-test-doc-buffer
                                  '(display-buffer-at-bottom (window-height . 0.3))))))
      (when my-test-doc-select (select-window window)))))

(defmacro my-test-with-documentation (&rest body)
  `(save-window-excursion
     (let ((source (generate-new-buffer " *doc source*"))
           (my-test-doc-buffer (generate-new-buffer "*doc test*"))
           (my-test-doc-calls 0) (my-test-doc-select t) (my-test-doc-display t)
           (my-test-doc-same-window nil) (my-test-doc-call-buffers nil)
           (my-test-doc-rewrite t)
           (my-documentation-repeat-delay 1.0))
       (unwind-protect
           (cl-letf (((symbol-function '+lookup/documentation) #'my-test-doc-backend))
             (delete-other-windows) (switch-to-buffer source)
             (insert "example") (goto-char (point-min))
             ,@body)
         (my--documentation-clear (selected-frame))
         (kill-buffer source) (kill-buffer my-test-doc-buffer)))))

(ert-deftest my-documentation-repeat-and-restore ()
  (my-test-with-documentation
   (split-window-right)
   (let ((before (window-state-get (frame-root-window) t)))
     (my/documentation)
     (should (= my-test-doc-calls 1))
     (should (= (length (window-list)) 3))
     (let ((last-command 'my/documentation)) (my/documentation))
     (should (= my-test-doc-calls 1))
     (should (= (length (window-list)) 1))
     (should (eq (current-buffer) my-test-doc-buffer))
     (should (bound-and-true-p olivetti-mode))
     (my/documentation-quit)
     (should (equal before (window-state-get (frame-root-window) t)))
     (should-not (buffer-local-value 'my--documentation-mode my-test-doc-buffer)))))

(ert-deftest my-documentation-source-focus-and-moved-point ()
  (my-test-with-documentation
   (setq my-test-doc-select nil)
   (my/documentation)
   (forward-char)
   (let ((last-command 'my/documentation)) (my/documentation))
   (should (= my-test-doc-calls 2))
   (should-not (plist-get (frame-parameter nil 'my-documentation) :expanded))
   (let ((last-command 'my/documentation)) (my/documentation))
   (should (= my-test-doc-calls 2))
   (should (plist-get (frame-parameter nil 'my-documentation) :expanded))
   (my/documentation-quit)))

(ert-deftest my-documentation-timeout-and-prefix ()
  (my-test-with-documentation
   (my/documentation)
   (set-frame-parameter nil 'my-documentation
                        (plist-put (frame-parameter nil 'my-documentation) :time
                                   (- (float-time) 10)))
   (let ((last-command 'my/documentation)) (my/documentation))
   (should (= my-test-doc-calls 2))
   (should-not (plist-get (frame-parameter nil 'my-documentation) :expanded))
   (let ((last-command 'my/documentation)) (my/documentation '(4)))
   (should (= my-test-doc-calls 3))))

(ert-deftest my-documentation-does-not-promote-unrelated-help ()
  (my-test-with-documentation
   (my-test-doc-backend)
   (select-window (get-buffer-window source))
   (setq my-test-doc-display nil)
   (my/documentation)
   (should-not (frame-parameter nil 'my-documentation))
   (let ((last-command 'my/documentation)) (my/documentation))
   (should-not (frame-parameter nil 'my-documentation))
   (should (= (length (window-list)) 2))))

(ert-deftest my-documentation-closed-result-and-intervening-command ()
  (my-test-with-documentation
   (my/documentation)
   (let ((last-command 'other-command)) (my/documentation))
   (should (= my-test-doc-calls 2))
   (delete-window (get-buffer-window my-test-doc-buffer))
   (let ((last-command 'my/documentation)) (my/documentation))
   (should (= my-test-doc-calls 3))
   (should-not (plist-get (frame-parameter nil 'my-documentation) :expanded))))

(ert-deftest my-documentation-same-window-backend-expiration ()
  (my-test-with-documentation
   (setq my-test-doc-same-window t)
   (my/documentation)
   (should (eq (current-buffer) my-test-doc-buffer))
   (set-frame-parameter nil 'my-documentation
                        (plist-put (frame-parameter nil 'my-documentation) :time
                                   (- (float-time) 10)))
   (let ((last-command 'my/documentation)) (my/documentation))
   (should (= my-test-doc-calls 2))
   (should (cl-every (lambda (buffer) (eq buffer source)) my-test-doc-call-buffers))))

(ert-deftest my-documentation-markdown-code-languages ()
  (require 'lsp-mode)
  (require 'markdown-mode)
  (require 'python)
  (with-temp-buffer
    ;; Reproduce rendering after the backend has switched into its Help buffer.
    (help-mode)
    (let* ((my--documentation-source-mode 'python-mode)
           (rendered (lsp--render-string
                      "```\ndef example(value):\n    return \"hello\"\n```\n\nOrdinary prose: def example.\n\n```elisp\n(defun greet () \"world\")\n```"
                      "markdown")))
      (dolist (probe '(("def example" . font-lock-keyword-face)
                       ("\"hello\"" . font-lock-string-face)
                       ("defun greet" . font-lock-keyword-face)))
        (let* ((position (string-match (regexp-quote (car probe)) rendered))
               (face (and position (get-text-property position 'face rendered))))
          (should position)
          (should (memq (cdr probe) (if (listp face) face (list face)))))
      (let* ((position (+ (string-match "Ordinary prose: def" rendered) 16))
             (face (get-text-property position 'face rendered)))
        (should-not (memq 'font-lock-keyword-face (if (listp face) face (list face)))))))))

(ert-deftest my-documentation-helpful-preserves-source-colors ()
  (require 'helpful)
  (let* ((rendered (helpful--syntax-highlight "(defun greet () \"hello\")"))
         (face (get-text-property (string-match "defun" rendered) 'face rendered)))
    (should (memq 'font-lock-keyword-face (if (listp face) face (list face))))))

(ert-deftest my-documentation-reused-cached-popup ()
  (my-test-with-documentation
   (my/documentation)
   (my--documentation-clear (selected-frame))
   (select-window (get-buffer-window source))
   (setq my-test-doc-rewrite nil)
   (let ((tick (buffer-chars-modified-tick my-test-doc-buffer)))
     (my/documentation)
     (should (frame-parameter nil 'my-documentation))
     (should (= tick (buffer-chars-modified-tick my-test-doc-buffer)))
     (let ((last-command 'my/documentation)) (my/documentation))
     (should (plist-get (frame-parameter nil 'my-documentation) :expanded))
     (my/documentation-quit))))
