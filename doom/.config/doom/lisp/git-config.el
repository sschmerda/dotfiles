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

(defun my--git-discard-hunks-patch (diff first last)
  "Keep complete hunks of DIFF touched by source lines FIRST through LAST.
Preserve original working-tree coordinates for reverse application."
  (let* ((parsed (my--git-stage-parse diff)) (header (car parsed)) pieces)
    (dolist (hunk (cdr parsed))
      (let* ((start (plist-get hunk :new-start))
             (count (plist-get hunk :new-count))
             (anchor (max 1 start))
             (finish (if (> count 0) (+ start count -1) anchor)))
        (when (and (<= first finish) (<= anchor last))
          (push (concat (format "@@ -%d,%d +%d,%d @@\n"
                                (plist-get hunk :old-start) (plist-get hunk :old-count)
                                start count)
                        (plist-get hunk :body)) pieces))))
    (when pieces (concat header "\n" (apply #'concat (nreverse pieces))))))

(defvar-local my-git-discard-context nil
  "Pending source, patch and snapshots for this discard preview.")

(defun my--git-file-hash (file)
  "Hash FILE's literal bytes to detect changes while a preview is open."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun my--git-selection-refresh ()
  "Finish a source-selection Git operation and refresh its indicators."
  (deactivate-mark)
  (when (and (fboundp 'evil-visual-state-p) (evil-visual-state-p)) (evil-exit-visual-state))
  (when (bound-and-true-p diff-hl-mode) (diff-hl-update))
  (when (fboundp 'magit-refresh-all) (magit-refresh-all)))

(defun my--git-discard-cancel ()
  "Cancel this discard preview without changing source or index."
  (interactive)
  (setq my-git-discard-context nil)
  (quit-window t))

(defun my--git-discard-confirm ()
  "Discard exactly the previewed unstaged hunks after validating snapshots.
If the source buffer, file or index changed, keep the preview and require a
fresh selection. No modified source buffer is overwritten."
  (interactive)
  (let* ((context my-git-discard-context)
         (source (plist-get context :source))
         (file (plist-get context :file))
         (root (plist-get context :root))
         (relative (plist-get context :relative))
         (patch (plist-get context :patch)))
    (unless (and context (buffer-live-p source))
      (user-error "The originating source buffer is no longer available"))
    (unless (= (buffer-chars-modified-tick) (plist-get context :preview-tick))
      (user-error "Preview text changed; cancel and select the hunks again"))
    (with-current-buffer source
      (when buffer-read-only (user-error "The source buffer is read-only"))
      (unless (and buffer-file-name (equal (file-truename buffer-file-name) file)
                   (not (buffer-modified-p))
                   (= (buffer-chars-modified-tick) (plist-get context :tick))
                   (verify-visited-file-modtime (current-buffer))
                   (file-readable-p file)
                   (equal (my--git-file-hash file) (plist-get context :hash)))
        (user-error "Source changed since preview; cancel and select the hunks again"))
      (let ((default-directory root))
        (unless (equal (plist-get context :index)
                       (my--git-stage-run nil "--literal-pathspecs" "ls-files" "--stage" "--" relative))
          (user-error "Index changed since preview; cancel and select the hunks again"))
        (my--git-stage-run patch "apply" "--reverse" "--check" "--unidiff-zero" "--whitespace=nowarn" "-")
        (my--git-stage-run patch "apply" "--reverse" "--unidiff-zero" "--whitespace=nowarn" "-"))
      (revert-buffer t t t)
      (my--git-selection-refresh))
    (my--git-discard-cancel)
    (message "Discarded previewed unstaged hunks; staged changes preserved")))

(require 'diff-mode)
(define-derived-mode my--git-discard-preview-mode diff-mode "Discard preview"
  "Review unstaged hunks before discarding them.
The diff shows existing changes: additions will be removed and deletions restored.
Press c or C-c C-c to confirm, q or C-c C-k to cancel."
  (setq-local buffer-read-only t
              header-line-format
              " Unstaged changes to discard — c: confirm discard · q: cancel"))

;; Keep Diff's highlighting, but inherit read-only browsing keys rather than
;; patch editing/application commands that bypass this preview's confirmation.
(set-keymap-parent my--git-discard-preview-mode-map special-mode-map)
(define-key my--git-discard-preview-mode-map (kbd "M-n") #'diff-hunk-next)
(define-key my--git-discard-preview-mode-map (kbd "M-p") #'diff-hunk-prev)
(define-key my--git-discard-preview-mode-map (kbd "c") #'my--git-discard-confirm)
(define-key my--git-discard-preview-mode-map (kbd "C-c C-c") #'my--git-discard-confirm)
(define-key my--git-discard-preview-mode-map (kbd "q") #'my--git-discard-cancel)
(define-key my--git-discard-preview-mode-map (kbd "C-c C-k") #'my--git-discard-cancel)
(with-eval-after-load 'evil
  (evil-set-initial-state 'my--git-discard-preview-mode 'motion)
  (evil-define-key '(normal motion) my--git-discard-preview-mode-map
    (kbd "c") #'my--git-discard-confirm
    (kbd "q") #'my--git-discard-cancel))

(defun my--git-discard-preview (context)
  "Display the exact patch in CONTEXT without modifying source or index."
  (let ((buffer (get-buffer-create "*Git discard preview*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (decode-coding-string
                 (plist-get context :patch)
                 (or (coding-system-base
                      (buffer-local-value 'buffer-file-coding-system (plist-get context :source)))
                     'utf-8))))
      (my--git-discard-preview-mode)
      (setq-local my-git-discard-context
                  (plist-put context :preview-tick (buffer-chars-modified-tick))
                  default-directory (plist-get context :root))
      (goto-char (point-min)))
    (let ((window (if (fboundp '+popup-buffer)
                      (+popup-buffer buffer '((side . bottom) (size . 0.4)
                                              (select . t) (quit . t) (ttl . nil)))
                    (display-buffer buffer
                                    '(display-buffer-at-bottom (window-height . 0.4))))))
      (unless (window-live-p window)
        (kill-buffer buffer)
        (user-error "Cannot display the discard preview"))
      (select-window window))))

(defun my--git-selection-source (beg end whole-hunks &optional discard)
  "Stage saved source BEG to END, or DISCARD complete intersecting hunks.
WHOLE-HUNKS expands staging to entire hunks; discarding always uses whole hunks."
  (unless buffer-file-name (user-error "This buffer does not visit a file"))
  (when (file-remote-p buffer-file-name) (user-error "Source selection Git commands currently support local files only"))
  (when (buffer-modified-p) (user-error "Save the buffer before changing selected Git hunks"))
  (unless (verify-visited-file-modtime (current-buffer))
    (user-error "File changed on disk; revert or reconcile it before changing Git hunks"))
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
             (hash (when discard (my--git-file-hash file)))
             (snapshot (my--git-stage-run nil "--literal-pathspecs" "ls-files" "--stage" "--" relative)))
        (unless (string-match-p "\\`100\\(?:644\\|755\\) " snapshot)
          (user-error "Select a tracked regular file; for a new file use git add -N first"))
        (unless (string-empty-p (my--git-stage-run nil "--literal-pathspecs" "ls-files" "--unmerged" "--" relative))
          (user-error "Resolve the file's merge conflict before changing selected hunks"))
        (let* ((diff (my--git-stage-run nil "--literal-pathspecs" "diff" "--no-ext-diff" "--no-textconv"
                                         "--no-color" "--no-renames" "--src-prefix=a/" "--dst-prefix=b/"
                                         "--diff-algorithm=myers" "--inter-hunk-context=0"
                                         (if (or whole-hunks discard) "--unified=3" "--unified=0") "--" relative))
               (patch (if discard (my--git-discard-hunks-patch diff first last)
                        (my--git-stage-patch diff first last whole-hunks))))
          (when (and discard (string-match-p "^new file mode " diff))
            (user-error "Discarding selections in intent-to-add files is unsupported"))
          (unless patch (user-error "No unstaged text changes in the selected range"))
          (unless (and (not (buffer-modified-p))
                       (verify-visited-file-modtime (current-buffer))
                       (equal snapshot (my--git-stage-run nil "--literal-pathspecs" "ls-files" "--stage" "--" relative)))
            (user-error "File or index changed while preparing the patch; retry"))
          (if discard
              (progn
                (when buffer-read-only (user-error "The source buffer is read-only"))
                (unless (equal hash (my--git-file-hash file))
                  (user-error "Source changed while preparing preview; retry"))
                (my--git-discard-preview
                 (list :source (current-buffer) :file file :root root :relative relative
                       :index snapshot :hash hash :tick (buffer-chars-modified-tick) :patch patch)))
            (my--git-stage-run patch "apply" "--cached" "--check" "--unidiff-zero" "--whitespace=nowarn" "-")
            (my--git-stage-run patch "apply" "--cached" "--unidiff-zero" "--whitespace=nowarn" "-")
            (my--git-selection-refresh)
            (message "Staged %s from selected source lines"
                     (if whole-hunks "intersecting hunks" "changed lines"))))))))

(defun my/git-stage-selection (beg end)
  "Stage changed lines within the active source selection, splitting hunks.
Expand a character selection to whole touched lines. The buffer must be saved.
Partial replacement blocks with unequal old/new counts are rejected; select the
whole block instead. Deleted-only blocks belong to the preceding visible line,
or line one for deletions at the start of a file. Existing staged changes and
working-tree contents are preserved. New files require Git intent-to-add first."
  (interactive (my--git-stage-region))
  (my--git-selection-source beg end nil))

(defun my/git-stage-selected-hunks (beg end)
  "Stage complete Git hunks touched by the active source selection.
A hunk includes three context lines on either side, as in Git's default diff.
Selecting any part of that range stages the whole hunk. The buffer must be saved.
Deleted-only blocks without context use the same anchor as `my/git-stage-selection'."
  (interactive (my--git-stage-region))
  (my--git-selection-source beg end t))

(defun my/git-discard-selected-hunks (beg end)
  "Discard complete unstaged Git hunks touched by the source selection.
Open a read-only diff preview of exactly the unstaged hunks to discard.
In the preview, c confirms and q cancels; C-c C-c and C-c C-k also work.
Confirmation rechecks the source and index before restoring index contents.
This may discard changed lines outside the selection in the same hunk, including
its three context lines. Staged changes and untouched hunks are preserved.
The buffer must be saved, writable and current on disk. Refresh it after applying.
Character and line selections are supported; visual blocks, intent-to-add files
and remote files are not."
  (interactive (my--git-stage-region))
  (my--git-selection-source beg end t t))

(map! :leader
      (:prefix ("g v" . "visual selection")
       :desc "Stage selected changed lines" "s" #'my/git-stage-selection
       :desc "Stage intersecting hunks" "h" #'my/git-stage-selected-hunks
       :desc "Discard intersecting unstaged hunks" "d" #'my/git-discard-selected-hunks))
