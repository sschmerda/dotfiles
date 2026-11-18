;;; git-stage-tests.el --- Source selection staging integration -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(defmacro map! (&rest _) nil)
(load (expand-file-name "../git-config.el"
                        (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defvar my-test-stage-file "sample.txt")
(defun my-test-stage-write (text)
  (let ((coding-system-for-write 'no-conversion))
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert text)
      (write-region (point-min) (point-max) my-test-stage-file nil 'silent))))

(defmacro my-test-stage-repository (old new &rest body)
  (declare (indent 2))
  `(let* ((root (make-temp-file "doom-source-stage-" t))
          (default-directory (file-name-as-directory root))
          (process-environment (append '("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
                                       process-environment)))
     (unwind-protect
         (progn
           (my--git-stage-run nil "init" "--quiet")
           (my--git-stage-run nil "config" "user.name" "Staging Test")
           (my--git-stage-run nil "config" "user.email" "test@example.invalid")
           (my-test-stage-write ,old)
           (my--git-stage-run nil "add" "--" my-test-stage-file)
           (my--git-stage-run nil "commit" "--quiet" "-m" "Fixture")
           (my-test-stage-write ,new)
           ,@body)
       (dolist (buffer (buffer-list))
         (when (and (buffer-file-name buffer)
                    (file-in-directory-p (buffer-file-name buffer) root))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory root t))))

(defun my-test-stage-lines (first last &optional hunks)
  (with-current-buffer (find-file-noselect my-test-stage-file)
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- first))
      (let ((beg (point)))
        (forward-line (1+ (- last first)))
        (funcall (if hunks #'my/git-stage-selected-hunks #'my/git-stage-selection) beg (point))))))

(defun my-test-stage-index ()
  (my--git-stage-run nil "show" (concat ":" my-test-stage-file)))

(ert-deftest my-git-stage-splits-one-replacement-hunk ()
  (my-test-stage-repository "a\nb\nc\nd\ne\n" "a\nB\nC\nD\ne\n"
    (my-test-stage-lines 3 3)
    (should (equal (my-test-stage-index) "a\nb\nC\nd\ne\n"))
    (should (equal (my--git-stage-run nil "diff" "--numstat") "2\t2\tsample.txt\n"))))

(ert-deftest my-git-stage-partial-insertion-and-multiple-hunks ()
  (my-test-stage-repository "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n"
                           "a\nnew1\nnew2\nnew3\nb\nc\nd\ne\nf\nG\nh\ni\nj\n"
    (my-test-stage-lines 3 10)
    (should (equal (my-test-stage-index) "a\nnew2\nnew3\nb\nc\nd\ne\nf\nG\nh\ni\nj\n"))))

(ert-deftest my-git-stage-whole-hunk-touched-through-context ()
  (my-test-stage-repository (mapconcat (lambda (i) (format "%d\n" i)) (number-sequence 1 30) "")
                           (mapconcat (lambda (i) (format "%s\n" (if (memq i '(3 6 25)) (format "X%d" i) i)))
                                      (number-sequence 1 30) "")
    (my-test-stage-lines 4 4 t)
    (let ((index (my-test-stage-index)))
      (should (string-match-p "X3\n" index))
      (should (string-match-p "X6\n" index))
      (should-not (string-match-p "X25" index)))))

(ert-deftest my-git-stage-unequal-partial-replacement-fails-atomically ()
  (my-test-stage-repository "a\nb\nc\nd\ne\nf\n" "a\nB\nX\ne\nf\n"
    (should-error (my-test-stage-lines 2 2) :type 'user-error)
    (should (string-empty-p (my--git-stage-run nil "diff" "--cached")))
    (my-test-stage-lines 2 3)
    (should (equal (my-test-stage-index) "a\nB\nX\ne\nf\n"))))

(ert-deftest my-git-stage-pure-deletion-anchor ()
  (my-test-stage-repository "a\nb\nc\nd\ne\n" "a\nb\nd\ne\n"
    (my-test-stage-lines 2 2)
    (should (equal (my-test-stage-index) "a\nb\nd\ne\n")))
  (my-test-stage-repository "a\nb\nc\n" "b\nc\n"
    (my-test-stage-lines 1 1)
    (should (equal (my-test-stage-index) "b\nc\n"))))

(ert-deftest my-git-stage-missing-final-newline ()
  (my-test-stage-repository "a\nb" "a\nB"
    (my-test-stage-lines 2 2)
    (should (equal (my-test-stage-index) "a\nB"))))

(ert-deftest my-git-stage-newline-only-change ()
  (my-test-stage-repository "a\nb\n" "a\nb"
    (my-test-stage-lines 2 2)
    (should (equal (my-test-stage-index) "a\nb"))))

(ert-deftest my-git-stage-preserves-crlf ()
  (my-test-stage-repository "a\r\nb\r\nc\r\n" "a\r\nB\r\nC\r\n"
    (my-test-stage-lines 2 2)
    (should (equal (my-test-stage-index) "a\r\nB\r\nc\r\n"))))

(ert-deftest my-git-stage-filename-quoting-and-literal-pathspecs ()
  (let ((my-test-stage-file "-odd [x] \"ü\".txt"))
    (my-test-stage-repository "a\nb\nc\n" "a\nB\nC\n"
      (my-test-stage-lines 2 2)
      (should (equal (my-test-stage-index) "a\nB\nc\n")))))

(ert-deftest my-git-stage-existing-staging-and-working-tree-preserved ()
  (my-test-stage-repository "a\nb\nc\nd\n" "A\nb\nc\nd\n"
    (my--git-stage-run nil "add" "--" my-test-stage-file)
    (my-test-stage-write "A\nb\nC\nD\n")
    (my-test-stage-lines 3 3)
    (should (equal (my-test-stage-index) "A\nb\nC\nd\n"))
    (with-temp-buffer
      (insert-file-contents my-test-stage-file)
      (should (equal (buffer-string) "A\nb\nC\nD\n")))))

(ert-deftest my-git-stage-context-only-selection-is-no-op ()
  (my-test-stage-repository "a\nb\nc\nd\n" "a\nB\nc\nd\n"
    (should-error (my-test-stage-lines 3 3) :type 'user-error)
    (should (string-empty-p (my--git-stage-run nil "diff" "--cached")))) )

(ert-deftest my-git-stage-unsaved-buffer-is-not-staged ()
  (my-test-stage-repository "a\nb\n" "a\nB\n"
    (with-current-buffer (find-file-noselect my-test-stage-file)
      (goto-char (point-max)) (insert "unsaved")
      (should-error (my/git-stage-selection (point-min) (point-max)) :type 'user-error))
    (should (string-empty-p (my--git-stage-run nil "diff" "--cached")))))

(ert-deftest my-git-stage-external-file-change-rejected ()
  (my-test-stage-repository "a\nb\n" "a\nB\n"
    (let ((buffer (find-file-noselect my-test-stage-file)))
      (my-test-stage-write "different length\n")
      (with-current-buffer buffer
        (should-error (my/git-stage-selection (point-min) (point-max)) :type 'user-error)))
    (should (string-empty-p (my--git-stage-run nil "diff" "--cached")))))

(ert-deftest my-git-stage-intent-to-add-new-file ()
  (my-test-stage-repository "base\n" "base\n"
    (let ((my-test-stage-file "new.txt"))
      (my-test-stage-write "a\nb\nc\n")
      (should-error (my-test-stage-lines 2 2) :type 'user-error)
      (my--git-stage-run nil "add" "-N" "--" my-test-stage-file)
      (my-test-stage-lines 2 2)
      (should (equal (my-test-stage-index) "b\n")))))

(ert-deftest my-git-stage-content-does-not-stage-mode-change ()
  (my-test-stage-repository "a\nb\n" "a\nB\n"
    (set-file-modes my-test-stage-file #o755)
    (my-test-stage-lines 2 2)
    (should (string-prefix-p "100644 " (my--git-stage-run nil "ls-files" "--stage" "--" my-test-stage-file)))))

(ert-deftest my-git-stage-skips-earlier-offset-changing-hunks ()
  (my-test-stage-repository "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n"
                           "extra1\nextra2\na\nb\nc\nd\ne\nf\nG\nh\ni\nj\n"
    (my-test-stage-lines 9 9)
    (should (equal (my-test-stage-index) "a\nb\nc\nd\ne\nf\nG\nh\ni\nj\n"))))

(ert-deftest my-git-stage-repeated-selections-preserve-prior-staging ()
  (my-test-stage-repository "a\nb\nc\nd\ne\n" "a\nB\nC\nD\ne\n"
    (my-test-stage-lines 3 3)
    (my-test-stage-lines 2 2)
    (should (equal (my-test-stage-index) "a\nB\nC\nd\ne\n"))))

(ert-deftest my-git-stage-remote-source-rejected-before-io ()
  (with-temp-buffer
    (setq buffer-file-name "/ssh:example.invalid:/repo/file.txt")
    (insert "x")
    (should-error (my/git-stage-selection 1 2) :type 'user-error)))

(ert-deftest my-git-stage-conflicted-index-preserved ()
  (my-test-stage-repository "a\nb\n" "a\nB\n"
    (let* ((hash (string-trim (my--git-stage-run nil "rev-parse" "HEAD:sample.txt")))
           (records (concat "0 " (make-string (length hash) ?0) "\tsample.txt\n"
                            (mapconcat (lambda (stage) (format "100644 %s %d\tsample.txt\n" hash stage))
                                       '(1 2 3) ""))))
      (my--git-stage-run records "update-index" "--index-info")
      (let ((before (my--git-stage-run nil "ls-files" "--stage")))
        (should-error (my-test-stage-lines 2 2) :type 'user-error)
        (should (equal before (my--git-stage-run nil "ls-files" "--stage")))))))

(defun my-test-discard-lines (first last &optional decline)
  "Preview and discard FIRST through LAST, or DECLINE the preview."
  (save-window-excursion
    (with-current-buffer (find-file-noselect my-test-stage-file)
      (goto-char (point-min))
      (forward-line (1- first))
      (let ((beg (point)))
        (forward-line (1+ (- last first)))
        (my/git-discard-selected-hunks beg (point)))))
  (save-window-excursion
    (unwind-protect
        (with-current-buffer "*Git discard preview*"
          (select-window (display-buffer (current-buffer)))
          (if decline
              (progn (my--git-discard-cancel) (user-error "Discard cancelled"))
            (my--git-discard-confirm)))
      (when (get-buffer "*Git discard preview*") (kill-buffer "*Git discard preview*")))))

(defun my-test-discard-worktree ()
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally my-test-stage-file)
    (buffer-string)))

(ert-deftest my-git-discard-whole-hunk-from-context-preserves-other-hunks ()
  (let* ((old (mapconcat (lambda (i) (format "%d\n" i)) (number-sequence 1 35) ""))
         (new (replace-regexp-in-string "^25$" "X25"
               (replace-regexp-in-string "^6$" "X6"
                (replace-regexp-in-string "^3$" "X3" old)))))
    (my-test-stage-repository old new
      (my-test-discard-lines 4 4)
      (should (equal (my-test-discard-worktree) (replace-regexp-in-string "^25$" "X25" old)))
      (should (equal (my-test-stage-index) old))
      (with-current-buffer (find-file-noselect my-test-stage-file)
        (should (equal (buffer-string) (my-test-discard-worktree)))
        (should-not (buffer-modified-p))))))

(ert-deftest my-git-discard-preserves-staged-version ()
  (my-test-stage-repository "a\nb\nc\n" "A\nb\nc\n"
    (my--git-stage-run nil "add" "--" my-test-stage-file)
    (let ((staged (my--git-stage-run nil "diff" "--cached")))
      (my-test-stage-write "A\nB\nc\n")
      (my-test-discard-lines 2 2)
      (should (equal (my-test-discard-worktree) "A\nb\nc\n"))
      (should (equal (my--git-stage-run nil "diff" "--cached") staged)))))

(ert-deftest my-git-discard-skipped-offset-changing-hunk ()
  (let* ((old (mapconcat (lambda (i) (format "%d\n" i)) (number-sequence 1 40) ""))
         (new (concat "extra\n" (replace-regexp-in-string "^25$" "X25" old))))
    (my-test-stage-repository old new
      (my-test-discard-lines 26 26)
      (should (equal (my-test-discard-worktree) (concat "extra\n" old))))))

(ert-deftest my-git-discard-multiple-hunks-with-offset-changes ()
  (let* ((old (mapconcat (lambda (i) (format "%d\n" i)) (number-sequence 1 45) ""))
         (new (concat "extra\n" (replace-regexp-in-string "^25\n" "" old))))
    (my-test-stage-repository old new
      (my-test-discard-lines 1 45)
      (should (equal (my-test-discard-worktree) old)))))

(ert-deftest my-git-discard-no-final-newline-and-crlf ()
  (dolist (pair '(("a\nb" . "a\nB") ("a\r\nb\r\n" . "a\r\nB\r\n")
                  ("a\nb\n" . "a\nb")))
    (my-test-stage-repository (car pair) (cdr pair)
      (my-test-discard-lines 2 2)
      (should (equal (my-test-discard-worktree) (car pair))))))

(ert-deftest my-git-discard-decline-preserves-worktree-and-index ()
  (my-test-stage-repository "a\nb\n" "a\nB\n"
    (should-error (my-test-discard-lines 2 2 t) :type 'user-error)
    (should (equal (my-test-discard-worktree) "a\nB\n"))
    (should (equal (my-test-stage-index) "a\nb\n"))))

(ert-deftest my-git-discard-rechecks-source-after-preview ()
  (my-test-stage-repository "a\nb\n" "a\nB\n"
    (save-window-excursion
      (unwind-protect
          (progn
            (with-current-buffer (find-file-noselect my-test-stage-file)
              (my/git-discard-selected-hunks (point-min) (point-max)))
            (my-test-stage-write "external\n")
            (with-current-buffer "*Git discard preview*"
              (should-error (my--git-discard-confirm) :type 'user-error)))
        (when (get-buffer "*Git discard preview*") (kill-buffer "*Git discard preview*"))))
    (should (equal (my-test-discard-worktree) "external\n"))
    (should (equal (my-test-stage-index) "a\nb\n"))))

(ert-deftest my-git-discard-rejects-unsaved-and-read-only-buffers ()
  (my-test-stage-repository "a\nb\n" "a\nB\n"
    (with-current-buffer (find-file-noselect my-test-stage-file)
      (let ((buffer-read-only t))
        (should-error (my/git-discard-selected-hunks (point-min) (point-max)) :type 'user-error))
      (insert "unsaved")
      (should-error (my/git-discard-selected-hunks (point-min) (point-max)) :type 'user-error))
    (should (equal (my-test-discard-worktree) "a\nB\n"))))

(ert-deftest my-git-discard-literal-path-and-intent-to-add-guard ()
  (let ((my-test-stage-file "-odd [x] ü.txt"))
    (my-test-stage-repository "a\nb\n" "a\nB\n"
      (my-test-discard-lines 2 2)
      (should (equal (my-test-discard-worktree) "a\nb\n"))))
  (my-test-stage-repository "a\n" "A\n"
    (my--git-stage-run nil "rm" "--cached" "--" my-test-stage-file)
    (my--git-stage-run nil "add" "-N" "--" my-test-stage-file)
    (should-error (my-test-discard-lines 1 1) :type 'user-error)
    (should (equal (my-test-discard-worktree) "A\n"))))

(defmacro my-test-with-discard-preview (&rest body)
  "Prepare the entire fixture file for preview, then evaluate BODY there."
  `(save-window-excursion
     (unwind-protect
         (progn
           (switch-to-buffer (find-file-noselect my-test-stage-file))
           (my/git-discard-selected-hunks (point-min) (point-max))
           (with-current-buffer "*Git discard preview*" ,@body))
       (when (get-buffer "*Git discard preview*") (kill-buffer "*Git discard preview*")))))

(ert-deftest my-git-discard-preview-is-exact-read-only-and-cancel-restores-window ()
  (let* ((old (mapconcat (lambda (i) (format "%d\n" i)) (number-sequence 1 40) ""))
         (new (replace-regexp-in-string "^25$" "X25"
               (replace-regexp-in-string "^3$" "X3" old))))
    (my-test-stage-repository old new
      (save-window-excursion
        (switch-to-buffer (find-file-noselect my-test-stage-file))
        (let ((source-window (selected-window)) (source (current-buffer)))
          (goto-char (point-min))
          (forward-line 3)
          (my/git-discard-selected-hunks (point) (1+ (point)))
          (should (derived-mode-p 'my--git-discard-preview-mode))
          (should buffer-read-only)
          (should (equal (buffer-string)
                         (decode-coding-string (plist-get my-git-discard-context :patch) 'utf-8)))
          (should (string-match-p "[+]X3" (buffer-string)))
          (should-not (string-match-p "[+]X25" (buffer-string)))
          (should-not (key-binding (kbd "C-c C-a")))
          (should (eq (key-binding (kbd "c")) #'my--git-discard-confirm))
          (should (eq (key-binding (kbd "q")) #'my--git-discard-cancel))
          (should (equal (my-test-discard-worktree) new))
          (should (equal (my-test-stage-index) old))
          (call-interactively (key-binding (kbd "q")))
          (should-not (get-buffer "*Git discard preview*"))
          (should (eq (selected-window) source-window))
          (should (eq (current-buffer) source))
          (should (equal (my-test-discard-worktree) new)))))))

(ert-deftest my-git-discard-preview-rejects-index-change ()
  (my-test-stage-repository "a\nb\n" "a\nB\n"
    (my-test-with-discard-preview
      (my--git-stage-run nil "add" "--" my-test-stage-file)
      (should-error (my--git-discard-confirm) :type 'user-error)
      (should (equal (my-test-discard-worktree) "a\nB\n"))
      (should (equal (my-test-stage-index) "a\nB\n")))))

(ert-deftest my-git-discard-preview-rejects-unsaved-source-edits ()
  (my-test-stage-repository "a\nb\n" "a\nB\n"
    (my-test-with-discard-preview
      (with-current-buffer (plist-get my-git-discard-context :source) (insert "unsaved"))
      (should-error (my--git-discard-confirm) :type 'user-error)
      (should (equal (my-test-discard-worktree) "a\nB\n")))))

(ert-deftest my-git-discard-preview-hash-detects-same-size-and-timestamp-edit ()
  (my-test-stage-repository "a\nb\n" "a\nB\n"
    (my-test-with-discard-preview
      (let ((mtime (file-attribute-modification-time (file-attributes my-test-stage-file))))
        (my-test-stage-write "a\nC\n")
        (set-file-times my-test-stage-file mtime))
      (should-error (my--git-discard-confirm) :type 'user-error)
      (should (equal (my-test-discard-worktree) "a\nC\n")))))

(ert-deftest my-git-discard-preview-rejects-edited-preview-and-closed-source ()
  (my-test-stage-repository "a\nb\n" "a\nB\n"
    (my-test-with-discard-preview
      (let ((inhibit-read-only t)) (insert "edited preview\n"))
      (should-error (my--git-discard-confirm) :type 'user-error)
      (kill-buffer (plist-get my-git-discard-context :source))
      (should-error (my--git-discard-confirm) :type 'user-error)
      (should (equal (my-test-discard-worktree) "a\nB\n")))))
