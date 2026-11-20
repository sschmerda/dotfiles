;;; completion-search-config.el --- Optional ranked minibuffer matching -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)

(defgroup my-completion-search nil
  "Opt-in matching profiles for supported completion sessions."
  :group 'completion)

(defcustom my-completion-search-default 'normal
  "Matching profile for a newly opened supported picker."
  :type '(choice (const normal) (const fuzzy)) :group 'my-completion-search)
(defcustom my-completion-search-defaults nil
  "Per-context overrides of `my-completion-search-default'.
Currently supported contexts are project-symbols and buffer-symbols.
Other pickers are integrated separately. Session toggles are not remembered."
  :type '(alist :key-type symbol :value-type (choice (const normal) (const fuzzy)))
  :group 'my-completion-search)
(defcustom my-completion-fuzzy-backend 'fzf-native
  "Fussy scoring backend used when entering Fuzzy mode.
The native backend loads its bundled module; flx uses Emacs Lisp only.
An unavailable backend reports an error and leaves the current mode intact."
  :type '(choice (const fzf-native) (const flx)) :group 'my-completion-search)
(defface my-completion-fuzzy-match
  '((t (:inherit font-lock-warning-face :weight bold :underline t)))
  "Strong fuzzy match emphasis, including on the selected result row."
  :group 'my-completion-search)

(defvar-local my--completion-search-session nil)
(defvar-local my--completion-search-mode 'normal)
(defvar-local my--completion-search-normal-settings nil)
(defvar-local my--completion-search-change-function nil)
(defvar vertico--input)
(defvar vertico--lock-groups)
(defvar vertico--lock-candidate)
(defvar vertico--candidates)
(defvar vertico--index)
;; Declare these before setting them locally, including before first package load.
(defvar fussy-filter-fn)
(defvar fussy-score-ALL-fn)
(defvar fussy-score-fn)
(defvar fussy-use-cache)
(defvar fussy-propertize-fn)
(defvar fussy-compare-same-score-fn)
(defvar fussy-cancel-on-input-fn)
(defvar fussy--filtering-p)
(defvar fussy-max-word-length-to-score)
(defvar fussy-max-query-length)
(defvar fussy-max-candidate-limit)
(defvar fzf-native-highlight-fn)

(defun my--completion-search-fuzzy-p ()
  "Return non-nil when the current supported session uses Fuzzy matching."
  (and my--completion-search-session (eq my--completion-search-mode 'fuzzy)))

(defun my--completion-search-query-p ()
  "Return non-nil for a nonblank fuzzy query in this session."
  (and (my--completion-search-fuzzy-p)
       (not (string-empty-p (string-trim (minibuffer-contents-no-properties))))))

(defun my--completion-search-clear-match-face (candidate)
  "Remove our old match emphasis from CANDIDATE, preserving other faces."
  (let ((start 0))
    (while (< start (length candidate))
      (let* ((end (next-single-property-change start 'face candidate (length candidate)))
             (faces (get-text-property start 'face candidate)))
        (when (or (eq faces 'my-completion-fuzzy-match)
                  (and (listp faces) (memq 'my-completion-fuzzy-match faces)))
          (let ((rest (remq 'my-completion-fuzzy-match (ensure-list faces))))
            (if rest (put-text-property start end 'face rest candidate)
              (remove-text-properties start end '(face nil) candidate))))
        (setq start end))))
  candidate)

(defun my--completion-search-highlight-native (candidate positions)
  "Emphasize native match POSITIONS in CANDIDATE without losing metadata."
  (my--completion-search-clear-match-face candidate)
  (dotimes (i (/ (length positions) 2))
    (add-face-text-property (aref positions (* i 2)) (aref positions (1+ (* i 2)))
                            'my-completion-fuzzy-match nil candidate))
  candidate)

(defun my--completion-search-highlight-flx (candidate score)
  "Emphasize the character positions following SCORE's numeric score."
  (my--completion-search-clear-match-face candidate)
  (dolist (index (cdr score))
    (when (< index (length candidate))
      (add-face-text-property index (1+ index) 'my-completion-fuzzy-match nil candidate)))
  candidate)

(defun my--completion-search-highlight (candidate)
  "Highlight a visible CANDIDATE using the active fuzzy engine."
  (if (and (my--completion-search-query-p)
           (eq my-completion-fuzzy-backend 'fzf-native))
      (fzf-native-highlight-one (copy-sequence candidate)
                                (minibuffer-contents-no-properties))
    candidate))

(defun my--completion-search-prepare-backend ()
  "Load the chosen fuzzy engine before changing any session settings."
  (let ((default-directory (file-name-as-directory user-emacs-directory)))
    (require 'fussy)
    (pcase my-completion-fuzzy-backend
      ('fzf-native
       (require 'fzf-native)
       (fzf-native-ensure-loaded))
      ('flx nil)
      (_ (user-error "Unknown fuzzy backend: %s" my-completion-fuzzy-backend)))))

(defun my--completion-search-set-mode (mode)
  "Apply MODE only in this supported completion session."
  (unless (memq mode '(normal fuzzy)) (user-error "Unknown matching mode: %s" mode))
  ;; Keep Normal usable even if installing or loading the native module failed.
  (when (eq mode 'fuzzy) (my--completion-search-prepare-backend))
  (dolist (setting my--completion-search-normal-settings)
    (set (make-local-variable (car setting)) (cdr setting)))
  (when (featurep 'fussy)
    (setq-local fussy--filtering-p nil)
    (fussy-wipe-cache))
  (when (eq mode 'fuzzy)
    (setq-local completion-styles '(fussy)
                completion-category-defaults nil completion-category-overrides nil
                fussy-filter-fn (if (eq my-completion-fuzzy-backend 'fzf-native)
                                    #'fussy-filter-by-scoring #'fussy-filter-flex)
                fussy-score-ALL-fn (if (eq my-completion-fuzzy-backend 'fzf-native)
                                       #'fussy-fzf-score #'fussy-score)
                fussy-score-fn #'flx-score
                ;; Consult's kind predicate and independent counts use different
                ;; candidate pools for the same query. Do not share Fussy's
                ;; query-only cache between those pools.
                fussy-use-cache nil
                fussy-compare-same-score-fn nil
                fussy-cancel-on-input-fn #'ignore
                fussy-propertize-fn #'my--completion-search-highlight-flx
                fzf-native-highlight-fn #'my--completion-search-highlight-native)
    (when (eq my-completion-fuzzy-backend 'flx)
      ;; Fussy otherwise drops long candidates and can bypass scoring entirely.
      (setq-local fussy-max-word-length-to-score most-positive-fixnum
                  fussy-max-query-length most-positive-fixnum
                  fussy-max-candidate-limit most-positive-fixnum)))
  (setq my--completion-search-mode mode))

(defun my--completion-search-setup (context change-function)
  "Enable shared matching controls for CONTEXT, notifying CHANGE-FUNCTION.
This is an opt-in API: it installs no global minibuffer hooks or bindings."
  (setq-local my--completion-search-session context
              my--completion-search-change-function change-function
              my--completion-search-normal-settings
              (mapcar (lambda (symbol) (cons symbol (copy-tree (symbol-value symbol))))
                      '(completion-styles completion-category-defaults
                                          completion-category-overrides completion-ignore-case)))
  (let ((mode (or (alist-get context my-completion-search-defaults)
                  my-completion-search-default)))
    (if (eq mode 'fuzzy)
        (condition-case err
            (my--completion-search-set-mode 'fuzzy)
          (error
           (my--completion-search-set-mode 'normal)
           (message "Opened in Normal mode. Fuzzy backend unavailable: %s"
                    (error-message-string err))))
      (my--completion-search-set-mode mode))))

(defun my--completion-search-toggle ()
  "Toggle Normal/Fuzzy matching in the active supported picker.
Keep the query and start a ranked result list at its best match."
  (interactive)
  (unless my--completion-search-session (user-error "This picker has no matching toggle"))
  (let* ((selected (and (>= vertico--index 0) (nth vertico--index vertico--candidates)))
         (mode (if (my--completion-search-fuzzy-p) 'normal 'fuzzy)))
    (my--completion-search-set-mode mode)
    (setq-local completion-lazy-hilit-fn nil)
    (setq vertico--input nil vertico--lock-groups nil vertico--lock-candidate nil)
    (when my--completion-search-change-function
      (funcall my--completion-search-change-function))
    (vertico--update)
    (when-let ((index (and (not (my--completion-search-query-p))
                           selected
                           (cl-position selected vertico--candidates :test #'equal))))
      (vertico--goto index))
    (vertico--exhibit)))

(defun my--completion-search-label ()
  "Return the active matching profile's short label."
  (if (my--completion-search-fuzzy-p) "[Fuzzy] " "[Normal] "))

(defun my--completion-search-help-text ()
  "Return context help for the current matching mode and its syntax."
  (concat
   (format "Matching: %s\nC-c C-f toggles Normal / Fuzzy; C-c C-h shows help.\n"
           (if (my--completion-search-fuzzy-p)
               (format "Fuzzy (Fussy / %s)" my-completion-fuzzy-backend) "Normal (Orderless)"))
   "Switching preserves the query, but the matcher interprets its syntax differently.\n"
   (if (my--completion-search-fuzzy-p)
       (if (eq my-completion-fuzzy-backend 'fzf-native)
           "Fuzzy uses fzf syntax: words must all match; 'word is literal, ^word is a prefix, word$ is a suffix, !word excludes, and a | b provides alternatives.\nLowercase queries ignore case; uppercase makes matching case-sensitive.\nMatches are ranked and strongly highlighted. Orderless operators such as & and = do not apply.\n"
         "Fuzzy uses flx subsequence matching and scoring; it does not interpret Orderless operators or fzf query syntax.\nMatches are ranked and strongly highlighted.\n")
     "Orderless components match in any order, separated by spaces. Operators may be placed before or after a component:\n! exclude literal text     !test\n& match annotations       &Function\n= literal text            =foo.bar\n^ literal prefix          ^calculate\n~ fuzzy subsequence       clbn~\n` initials                `cb\n% character folding       %cafe\nUnmarked components retain Orderless literal/regexp matching.\n")
   "\nDefaults: my-completion-search-default, my-completion-search-defaults.\nBackend: my-completion-fuzzy-backend (fzf-native or flx).\nMatch face: M-x customize-face RET my-completion-fuzzy-match.\n"
   "Full manuals: Orderless Info (C-h i m orderless RET outside the picker),\nhttps://github.com/jojojames/fussy\nhttps://github.com/dangduc/fzf-native\n"))

(provide 'completion-search-config)
