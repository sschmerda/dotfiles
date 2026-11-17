;;; git-config.el --- Shared Git functionality -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defun my--git-stage-run (input &rest arguments)
  "Run Git with ARGUMENTS, optionally sending byte string INPUT on stdin.
Return raw output, or signal a user error without modifying a visiting buffer."
  (let ((coding-system-for-read 'no-conversion)
        (coding-system-for-write 'no-conversion)
        (process-environment (cons "LC_ALL=C" process-environment)))
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (let* ((output (current-buffer))
             (status (if input
                         (with-temp-buffer
                           (set-buffer-multibyte nil)
                           (insert input)
                           (apply #'call-process-region (point-min) (point-max) "git"
                                  nil (list output t) nil arguments))
                       (apply #'process-file "git" nil (list output t) nil arguments))))
        (unless (eq status 0)
          (user-error "Git: %s" (string-trim (decode-coding-string (buffer-string) 'utf-8))))
        (buffer-string)))))

(defun my--git-stage-region ()
  "Read the active ordinary or Evil visual range; reject block selections."
  (cond ((and (fboundp 'evil-visual-state-p) (evil-visual-state-p))
         (let ((range (evil-visual-range)))
           (when (eq (nth 2 range) 'block)
             (user-error "Use a character or line selection, not a visual block"))
           (list (nth 0 range) (nth 1 range))))
        ((use-region-p) (list (region-beginning) (region-end)))
        (t (user-error "Select source lines first"))))

(defun my--git-stage-parse (diff)
  "Parse the single-file unified DIFF produced by our controlled Git invocation.
Keep raw line bytes, CRLF and missing-final-newline markers. Reject other formats."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert diff)
    (goto-char (point-min))
    (let ((regexp "^@@ -\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? [+]\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@[^\n]*\n")
          header hunks)
      (when (re-search-forward regexp nil t)
        (setq header (buffer-substring-no-properties (point-min) (match-beginning 0)))
        (goto-char (match-beginning 0)))
      (while (looking-at regexp)
        (let* ((old-start (string-to-number (match-string 1)))
               (old-count (if (match-string 2) (string-to-number (match-string 2)) 1))
               (new-start (string-to-number (match-string 3)))
               (new-count (if (match-string 4) (string-to-number (match-string 4)) 1))
               (body-start (match-end 0)) old-lines new-lines previous)
          (goto-char body-start)
          (while (and (not (eobp)) (not (looking-at "^@@ ")))
            (let* ((kind (char-after))
                   (line (buffer-substring-no-properties
                          (min (1+ (point)) (point-max))
                          (min (1+ (line-end-position)) (point-max)))))
              (pcase kind
                ((or ?- ?+ ?\s)
                 (when (memq kind '(?- ?\s)) (push line old-lines))
                 (when (memq kind '(?+ ?\s)) (push line new-lines))
                 (setq previous kind))
                (?\\
                 (unless (looking-at "^\\\\ No newline at end of file$")
                   (user-error "Unsupported diff marker"))
                 (when (memq previous '(?- ?\s))
                   (setcar old-lines (string-remove-suffix "\n" (car old-lines))))
                 (when (memq previous '(?+ ?\s))
                   (setcar new-lines (string-remove-suffix "\n" (car new-lines)))))
                (_ (user-error "Unsupported diff format")))
              (forward-line 1)))
          (unless (and (= old-count (length old-lines)) (= new-count (length new-lines)))
            (user-error "Inconsistent diff line counts"))
          (push (list :old-start old-start :old-count old-count
                      :new-start new-start :new-count new-count
                      :old-lines (nreverse old-lines) :new-lines (nreverse new-lines)
                      :body (buffer-substring-no-properties body-start (point))) hunks)))
      ;; Mode changes are independent of a source-line selection. Do not stage them.
      ;; Retain Git's filename quoting instead of constructing patch paths ourselves.
      (cons (when header
              (mapconcat #'identity
                         (cl-remove-if-not
                          (lambda (line) (string-match-p "\\`\\(?:diff --git \\|new file mode \\|--- \\|+++ \\)" line))
                          (split-string header "\n" t)) "\n"))
            (nreverse hunks)))))

(defun my--git-stage-row (prefix line)
  "Encode LINE with patch PREFIX, including a missing-newline marker if needed."
  (concat prefix line (unless (string-suffix-p "\n" line)
                        "\n\\ No newline at end of file\n")))

(defun my--git-stage-patch (diff first last whole-hunks)
  "Select changed lines FIRST through LAST from DIFF, or WHOLE-HUNKS they touch.
DIFF must have zero context for line selection, three lines for whole hunks.
Pure deletions use the preceding visible line (line one for a top deletion).
Partial unequal replacement blocks are ambiguous and are rejected."
  (let* ((parsed (my--git-stage-parse diff))
         (header (car parsed)) (delta 0) pieces)
    (dolist (hunk (cdr parsed))
      (let* ((old-count (plist-get hunk :old-count))
             (new-count (plist-get hunk :new-count))
             (new-start (plist-get hunk :new-start))
             (anchor (max 1 new-start))
             (finish (if (> new-count 0) (+ new-start new-count -1) anchor)))
        (when (and (<= first finish) (<= anchor last))
          (let* ((begin (if (or whole-hunks (= new-count 0)) 0 (max 0 (- first new-start))))
                 (end (if (or whole-hunks (= new-count 0)) new-count
                        (min new-count (1+ (- last new-start)))))
                 (partial (and (not whole-hunks) (or (> begin 0) (< end new-count)))))
            (when (and partial (> old-count 0) (/= old-count new-count))
              (user-error "Selection cuts an unequal replacement block; select the whole block or use selected hunks"))
            (let* ((old-offset (if (> old-count 0) begin 0))
                   (old-size (if partial (if (= old-count 0) 0 (- end begin)) old-count))
                   (new-size (- end begin))
                   (old-index (+ (plist-get hunk :old-start) (if (> old-count 0) -1 0) old-offset))
                   (body (if whole-hunks (plist-get hunk :body)
                           (concat
                            (mapconcat (lambda (line) (my--git-stage-row "-" line))
                                       (seq-subseq (plist-get hunk :old-lines) old-offset (+ old-offset old-size)) "")
                            (mapconcat (lambda (line) (my--git-stage-row "+" line))
                                       (seq-subseq (plist-get hunk :new-lines) begin end) "")))))
              (push (concat (format "@@ -%d,%d +%d,%d @@\n"
                                    (+ old-index (if (> old-size 0) 1 0)) old-size
                                    (+ old-index delta (if (> new-size 0) 1 0)) new-size)
                            body) pieces)
              (cl-incf delta (- new-size old-size)))))))
    (when pieces (concat header "\n" (apply #'concat (nreverse pieces))))))

(defun my--git-stage-source (beg end whole-hunks)
  "Stage saved source lines BEG to END; WHOLE-HUNKS expands intersecting hunks."
  (unless buffer-file-name (user-error "This buffer does not visit a file"))
  (when (file-remote-p buffer-file-name) (user-error "Source selection staging currently supports local files only"))
  (when (buffer-modified-p) (user-error "Save the buffer before staging a source selection"))
  (unless (verify-visited-file-modtime (current-buffer))
    (user-error "File changed on disk; revert or reconcile it before staging"))
  (unless (< beg end) (user-error "Select at least one source line"))
  (save-restriction
    (widen)
    (let* ((file (file-truename buffer-file-name))
           (root (locate-dominating-file file ".git")))
      (unless root (user-error "File is not inside a Git working tree"))
      (let* ((default-directory root)
             (relative (file-relative-name file root))
             (first (line-number-at-pos beg t))
             (last (line-number-at-pos (max beg (1- end)) t))
             (snapshot (my--git-stage-run nil "--literal-pathspecs" "ls-files" "--stage" "--" relative)))
        (unless (string-match-p "\\`100\\(?:644\\|755\\) " snapshot)
          (user-error "Select a tracked regular file; for a new file use git add -N first"))
        (unless (string-empty-p (my--git-stage-run nil "--literal-pathspecs" "ls-files" "--unmerged" "--" relative))
          (user-error "Resolve the file's merge conflict before staging a selection"))
        (let* ((diff (my--git-stage-run nil "--literal-pathspecs" "diff" "--no-ext-diff" "--no-textconv"
                                         "--no-color" "--no-renames" "--src-prefix=a/" "--dst-prefix=b/"
                                         "--diff-algorithm=myers" "--inter-hunk-context=0"
                                         (if whole-hunks "--unified=3" "--unified=0") "--" relative))
               (patch (my--git-stage-patch diff first last whole-hunks)))
          (unless patch (user-error "No unstaged text changes in the selected range"))
          (unless (and (verify-visited-file-modtime (current-buffer))
                       (equal snapshot (my--git-stage-run nil "--literal-pathspecs" "ls-files" "--stage" "--" relative)))
            (user-error "File or index changed while preparing the patch; retry"))
          (my--git-stage-run patch "apply" "--cached" "--check" "--unidiff-zero" "--whitespace=nowarn" "-")
          (my--git-stage-run patch "apply" "--cached" "--unidiff-zero" "--whitespace=nowarn" "-")
          (deactivate-mark)
          (when (and (fboundp 'evil-visual-state-p) (evil-visual-state-p)) (evil-exit-visual-state))
          (when (bound-and-true-p diff-hl-mode) (diff-hl-update))
          (when (fboundp 'magit-refresh-all) (magit-refresh-all))
          (message "Staged %s from selected source lines" (if whole-hunks "intersecting hunks" "changed lines")))))))

(defun my/git-stage-selection (beg end)
  "Stage changed lines within the active source selection, splitting hunks.
Expand a character selection to whole touched lines. The buffer must be saved.
Partial replacement blocks with unequal old/new counts are rejected; select the
whole block instead. Deleted-only blocks belong to the preceding visible line,
or line one for deletions at the start of a file. Existing staged changes and
working-tree contents are preserved. New files require Git intent-to-add first."
  (interactive (my--git-stage-region))
  (my--git-stage-source beg end nil))

(defun my/git-stage-selected-hunks (beg end)
  "Stage complete Git hunks touched by the active source selection.
A hunk includes three context lines on either side, as in Git's default diff.
Selecting any part of that range stages the whole hunk. The buffer must be saved.
Deleted-only blocks without context use the same anchor as `my/git-stage-selection'."
  (interactive (my--git-stage-region))
  (my--git-stage-source beg end t))

(map! :leader
      (:prefix ("g v" . "stage selection")
       :desc "Stage selected changed lines" "s" #'my/git-stage-selection
       :desc "Stage intersecting hunks" "h" #'my/git-stage-selected-hunks))
