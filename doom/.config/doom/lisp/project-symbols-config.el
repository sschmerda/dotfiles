;;; project-symbols-config.el --- Query-free LSP buffer and project symbols -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'hl-line)
(defvar +nav-flash-exclude-commands)
(eval-when-compile (require 'consult-lsp nil t))
;; These packages are required by the command, not eagerly at editor startup.
(declare-function projectile-project-root "projectile" (&optional dir))
(declare-function projectile-current-project-files "projectile" ())
(declare-function lsp-session "lsp-mode" ())
(declare-function lsp--workspace-method-supported? "lsp-mode" (check method capability workspace))
(declare-function lsp--supports-buffer? "lsp-mode" (client))
(declare-function lsp-buffer-language "lsp-mode" ())
(declare-function lsp--path-to-uri "lsp-mode" (path))
(declare-function lsp--uri-to-path "lsp-mode" (uri))
(declare-function lsp--cur-position "lsp-mode" ())
(declare-function lsp--position-to-point "lsp-mode" (position))
(declare-function lsp--flush-delayed-changes "lsp-mode" ())
(declare-function lsp-notify "lsp-mode" (method params))
(declare-function lsp-request "lsp-mode" (method params))
(declare-function lsp-get "lsp-protocol" (from key))
(declare-function consult--forbid-minibuffer "consult" ())
(declare-function consult--read "consult" (candidates &rest options))
(declare-function consult--lookup-candidate "consult" (selected candidates &rest args))
(declare-function consult--type-group "consult" (types))
(declare-function consult--type-narrow "consult" (types))
(declare-function consult-narrow-help "consult" ())
(declare-function consult-narrow "consult" (key))
(declare-function consult--widen-key "consult" ())
(declare-function consult-lsp--symbols--state "consult-lsp" ())
(declare-function nerd-icons-codicon "nerd-icons" (icon-name &rest args))
(declare-function color-name-to-rgb "color" (color &optional frame))
(declare-function color-rgb-to-hex "color" (red green blue &optional digits-per-component))
(defvar lsp--cur-workspace)
(defvar lsp-enabled-clients)
(defvar lsp--buffer-workspaces)
(defvar lsp--move-to-column-function)
(defvar consult--narrow)
(defvar consult--narrow-config)
(defvar vertico-sort-override-function)
(defvar vertico--input)
(defvar vertico--index)
(defvar vertico--candidates)
(defvar vertico--lock-groups)
(defvar vertico--lock-candidate)
(defvar vertico--scroll)
(defvar vertico-count)
(defvar-local my--symbols-opening-offset nil
  "First visible candidate in this picker's continuous viewport.")

(defcustom my-buffer-symbols-default-order 'kind
  "Initial buffer symbol presentation, before any remembered choice."
  :type '(choice (const kind) (const source)) :group 'convenience)

(defcustom my-project-symbols-default-order 'kind
  "Initial project symbol presentation, before any remembered choice."
  :type '(choice (const kind) (const source)) :group 'convenience)

(defcustom my-symbols-remember-order t
  "Remember presentation changes for this Emacs session, separately per picker.
When nil, every invocation starts with its configured default. Search text
and kind filters are never remembered. Choices are not saved across restarts."
  :type 'boolean :group 'convenience)

(defcustom my-symbols-tree-guides t
  "Show subtle tree connectors in Source presentation by default.
C-c C-t toggles guides for the current picker only. Hierarchy comes from
the language server; flat responses remain flat."
  :type 'boolean :group 'convenience)

(defcustom my-symbols-scope-highlight t
  "Highlight the currently previewed symbol's full server-provided scope.
C-c C-r toggles this for the current picker. Missing full ranges are not
guessed. Highlights disappear when the preview clears or the picker exits."
  :type 'boolean :group 'convenience)

(defcustom my-symbols-origin-marker t
  "Mark the symbol enclosing the original cursor position in the picker list.
C-c C-o toggles the marker for the current invocation. It stays attached to
that original symbol when selection, ordering, layout or filters change."
  :type 'boolean :group 'convenience)

(defface my-symbols-origin-marker-face
  '((t (:inherit font-lock-constant-face :weight bold)))
  "Face for the fixed original-position marker in the picker gutter."
  :group 'convenience)

(defface my-symbols-scope-face
  '((t (:extend t)))
  "Scope styling; an unspecified background uses the cursor-line highlight.
An explicitly customized background takes precedence over the derived color."
  :group 'convenience)

(defcustom my-symbols-default-layout 'full
  "Initial column layout for each picker invocation.
Full shows all configured columns. Compact is intended for narrow windows:
it keeps glyph, symbol and path, hiding parent and type. C-c C-l toggles the
layout for the current invocation; that choice is not remembered."
  :type '(choice (const full) (const compact)) :group 'convenience)

(defcustom my-symbols-visible-columns '(glyph symbol parent path type)
  "Columns enabled in Full layout, in the fixed standard order.
Symbol is always included. Compact also hides parent and type. Hidden fields
remain searchable and are available in the full-details panel."
  :type '(set (const glyph) (const symbol) (const parent) (const path) (const type))
  :group 'convenience)

(defcustom my-symbols-column-widths
  '((glyph . 2) (symbol . 36) (parent . 24) (path . 60) (type . 14))
  "Maximum display widths for picker columns, as positive integers.
Widths shrink to fit the window; omitted entries use the standard defaults.
Use `my-symbols-visible-columns', rather than a zero width, to hide a column."
  :type '(alist :key-type (choice (const glyph) (const symbol) (const parent) (const path) (const type))
                :value-type integer)
  :group 'convenience)

(defcustom my-symbols-window-position 0.25
  "Position of a symbol from the top of its visible code window.
The fraction applies to previews in both symbol pickers. Accepted jumps keep
the preview's screen row when closing the minibuffer expands the code window.
0.25 leaves about three quarters of the window below the symbol. The current
code window height already excludes the minibuffer. Use nil for normal
Consult scrolling. Buffer boundaries can limit the available context."
  :type '(choice (const :tag "Normal scrolling" nil)
                 (float :tag "Fraction from the top (0.0 to 1.0)"))
  :group 'convenience)

(defun my--symbols-recenter (&optional row)
  "Place the symbol at ROW, or `my-symbols-window-position' if ROW is nil."
  (when (and my-symbols-window-position (not (window-minibuffer-p)))
    (let* ((height (window-body-height))
           (line (or row (floor (* (max 0.0 (min 1.0 my-symbols-window-position)) height)))))
      (recenter (min (max 0 (1- height)) line)))))

(defun my--symbols-clear-scope (view &optional forget)
  "Remove VIEW's scope overlay; FORGET also clears its cached preview target."
  (when (overlayp (plist-get view :scope-overlay))
    (delete-overlay (plist-get view :scope-overlay)))
  (setf (plist-get view :scope-overlay) nil)
  (when forget
    (setf (plist-get view :scope-candidate) nil (plist-get view :scope-window) nil
          (plist-get view :scope-buffer) nil)))

(defun my--symbols-scope-style (&optional window)
  "Use WINDOW's cursor-line background for the symbol scope.
An explicitly customized scope background still takes precedence."
  (require 'color)
  (let* ((frame (if (window-live-p window) (window-frame window) (selected-frame)))
         (custom (face-attribute 'my-symbols-scope-face :background frame nil))
         (background (if (and (stringp custom) (color-name-to-rgb custom frame))
                         custom
                       (face-background 'hl-line frame t))))
    (append '(:inherit my-symbols-scope-face :extend t)
            (when (stringp background) (list :background background)))))

(defun my--symbols-refresh-scope (view)
  "Highlight VIEW's current preview scope without moving point or scrolling."
  (my--symbols-clear-scope view)
  (let* ((symbol (plist-get view :scope-candidate))
         (window (plist-get view :scope-window))
         (range (and symbol (or (lsp-get symbol :my-scope-range) (lsp-get symbol :range)))))
    (when (and (plist-get view :scope-highlight) range (window-live-p window)
               (eq (window-buffer window) (plist-get view :scope-buffer)))
      (with-selected-window window
        (let* ((encodings (plist-get view :scope-encodings))
               (encoding (and encodings (gethash symbol encodings)))
               (lsp--move-to-column-function
                (pcase encoding
                  ("utf-8" #'lsp--move-to-utf-8-column)
                  ("utf-16" #'lsp--move-to-utf-16-column)
                  ("utf-32" #'lsp--move-to-utf-32-column)
                  (_ lsp--move-to-column-function)))
               (bounds (condition-case nil
                           (save-excursion
                             (save-restriction
                               (widen)
                               (cons (lsp--position-to-point (lsp-get range :start))
                                     (lsp--position-to-point (lsp-get range :end)))))
                         (error nil))))
          (when (and bounds (< (car bounds) (cdr bounds)))
            (let ((overlay (make-overlay (car bounds) (cdr bounds) (current-buffer))))
              (overlay-put overlay 'face (my--symbols-scope-style window))
              (overlay-put overlay 'priority 0)
              (overlay-put overlay 'window window)
              (overlay-put overlay 'evaporate t)
              (setf (plist-get view :scope-overlay) overlay))))))))

(defun my--symbols-restore-cursor-lines (view)
  "Restore the cursor-line faces temporarily hidden by VIEW's preview."
  (dolist (entry (plist-get view :cursor-lines))
    (when (overlay-buffer (car entry))
      (overlay-put (car entry) 'face (cdr entry))))
  (setf (plist-get view :cursor-lines) nil))

(defun my--symbols-hide-cursor-line (view)
  "Hide stale hl-line overlays in the current preview buffer for VIEW."
  (dolist (overlay (overlays-in (point-min) (point-max)))
    (when (and (eq (overlay-get overlay 'face) 'hl-line)
               (not (assq overlay (plist-get view :cursor-lines))))
      (push (cons overlay (overlay-get overlay 'face)) (plist-get view :cursor-lines))
      (overlay-put overlay 'face nil))))

(defun my--symbols-location-marker (buffer position encoding)
  "Make a marker for LSP POSITION in BUFFER using negotiated ENCODING."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (save-excursion
        (save-restriction
          (widen)
          (let ((lsp--move-to-column-function
                 (pcase encoding
                   ("utf-8" #'lsp--move-to-utf-8-column)
                   ("utf-16" #'lsp--move-to-utf-16-column)
                   ("utf-32" #'lsp--move-to-utf-32-column)
                   (_ lsp--move-to-column-function))))
            (copy-marker
             (lsp--position-to-point
              (my--project-symbols-object
               :line (1- (lsp-translate-line (1+ (lsp-get position :line))))
               :character (lsp-translate-column (lsp-get position :character)))))))))))

(defun my--symbols-location-state (view)
  "Return Consult's jump state with exact, zero-based LSP positions for VIEW."
  (let ((open (consult--temporary-files))
        (jump (consult--jump-state)))
    (lambda (action candidate)
      (when (eq action 'exit) (funcall open))
      (funcall jump action
               (when candidate
                 (let* ((location (lsp-get candidate :location))
                        (uri (lsp-get location :uri))
                        (encodings (plist-get view :scope-encodings)))
                   (when uri
                     (my--symbols-location-marker
                      (funcall (if (eq action 'finish) #'find-file open) (lsp--uri-to-path uri))
                      (lsp-get (lsp-get location :range) :start)
                      (and encodings (gethash candidate encodings))))))))))

(defun my--symbols-state (&optional view)
  "Return Consult's LSP preview state with picker scrolling and scope display."
  (let* ((view (or view (list :scope-highlight my-symbols-scope-highlight
                             :scope-overlay nil :scope-candidate nil :scope-window nil :scope-buffer nil)))
        (state (my--symbols-location-state view))
        preview-candidate preview-row exit-row)
    ;; Keep this slot on the shared plist even for callers supplying a view.
    ;; Adding a missing property later can replace only a closure's local head.
    (unless (plist-member view :cursor-lines)
      (nconc view (list :cursor-lines nil)))
    (lambda (action candidate)
      (my--symbols-clear-scope view t)
      (when (memq action '(exit return))
        (my--symbols-restore-cursor-lines view))
      ;; Exit runs before the minibuffer closes, return afterwards. Preserve
      ;; its code-window geometry even when accepting before a preview ran.
      (when (and (eq action 'exit) my-symbols-window-position)
        (setq exit-row (floor (* (max 0.0 (min 1.0 my-symbols-window-position))
                                 (window-body-height)))))
      ;; Suppress Nav Flash only while this picker previews/accepts a jump.
      ;; Keep all other jump hooks and restore ordinary navigation afterwards.
      (let ((+nav-flash-exclude-commands
             (cons this-command (bound-and-true-p +nav-flash-exclude-commands)))
            (consult-after-jump-hook
             (append consult-after-jump-hook
                     (list (lambda ()
                             (my--symbols-recenter
                              (when (eq action 'return)
                                (if (equal candidate preview-candidate) preview-row exit-row)))
                             (when (and (eq action 'preview) candidate)
                               (my--symbols-hide-cursor-line view)
                               (setf (plist-get view :scope-candidate) candidate
                                     (plist-get view :scope-window) (selected-window)
                                     (plist-get view :scope-buffer) (current-buffer))
                               (my--symbols-refresh-scope view)
                               (when my-symbols-window-position
                                 (setq preview-candidate candidate
                                     preview-row
                                     (count-screen-lines
                                      (window-start)
                                      (save-excursion (vertical-motion 0) (point))
                                      nil (selected-window))))))))))
        (funcall state action candidate)))))

(defvar my--symbols-last-orders nil
  "Last explicitly chosen presentation for each picker in this Emacs session.")
(defvar-local my--symbols-view nil)

(defun my--symbols-selected ()
  "Return the currently highlighted picker candidate, or nil."
  (and (>= vertico--index 0) (nth vertico--index vertico--candidates)))

(defun my--symbols-origin-width (view)
  "Reserve a two-column gutter when VIEW can display its original symbol."
  (if (and (plist-get view :origin-marker) (plist-get view :origin-candidate)) 2 0))

(defun my--symbols-origin-prefix (view candidate)
  "Return VIEW's fixed origin marker or an equal-width blank for CANDIDATE."
  (if (zerop (my--symbols-origin-width view)) ""
    (if (eq (get-text-property 0 'consult--candidate candidate)
            (get-text-property 0 'consult--candidate (plist-get view :origin-candidate)))
        (propertize "• " 'face 'my-symbols-origin-marker-face 'help-echo "Symbol enclosing the original cursor position")
      "  ")))

(defun my--symbols-sync-scope (view)
  "Clear scope for an empty result list and restore a cached matching preview."
  (let ((selected (my--symbols-selected)) (overlay (plist-get view :scope-overlay)))
    (cond
     ((not selected) (my--symbols-clear-scope view))
     ((and (plist-get view :scope-highlight)
           (not (and (overlayp overlay) (overlay-buffer overlay)))
           (eq (get-text-property 0 'consult--candidate selected) (plist-get view :scope-candidate)))
      (my--symbols-refresh-scope view)))))

(defun my--symbols-tree-prefixes (candidates)
  "Map CANDIDATES to connectors derived from their server-provided hierarchy."
  (let ((parents (make-hash-table :test #'equal))
        (siblings (make-hash-table :test #'equal))
        (prefixes (make-hash-table :test #'equal)) file stack)
    (dolist (candidate (cl-stable-sort (copy-sequence candidates) #'my--symbols-source-less-p))
      (let ((uri (my--symbols-file candidate))
            (depth (or (lsp-get (get-text-property 0 'consult--candidate candidate) :my-depth) 0)))
        (unless (equal file uri) (setq file uri stack nil))
        (while (and stack (> (caar stack) depth)) (pop stack))
        (when (and stack (= (caar stack) depth))
          (puthash (cdar stack) t siblings)
          (pop stack))
        (puthash candidate (mapcar #'cdr (reverse stack)) parents)
        (push (cons depth candidate) stack)))
    (dolist (candidate candidates prefixes)
      (let ((ancestors (gethash candidate parents)))
        (puthash candidate
                 (if (not ancestors) ""
                   (concat (mapconcat (lambda (ancestor)
                                        (if (gethash ancestor siblings) "│ " "  "))
                                      (cdr ancestors) "")
                           (if (gethash candidate siblings) "├─" "└─")))
                 prefixes)))))

(defun my--symbols-close-panel (view)
  "Close VIEW's generated panel without selecting or altering source buffers."
  (let ((window (plist-get view :panel-window)) (buffer (plist-get view :panel-buffer)))
    (when (and (window-live-p window) (eq (window-buffer window) buffer))
      (if-let ((previous (and (buffer-live-p (car (plist-get view :panel-restore)))
                             (plist-get view :panel-restore))))
          (progn
            (set-window-buffer window (nth 0 previous))
            (set-window-point window (nth 1 previous))
            (set-window-start window (nth 2 previous)))
        (delete-window window)))
    (when (buffer-live-p buffer) (kill-buffer buffer))
    (when (buffer-live-p (plist-get view :picker-buffer))
      (with-current-buffer (plist-get view :picker-buffer)
        (setq-local other-window-scroll-buffer (plist-get view :previous-scroll-buffer)
                    minibuffer-scroll-window (plist-get view :previous-scroll-window))))
    (setf (plist-get view :panel-window) nil (plist-get view :panel-buffer) nil
          (plist-get view :panel-restore) nil
          (plist-get view :panel-kind) nil (plist-get view :panel-signature) nil)))

(defun my--symbols-detail-text (view candidate)
  "Describe CANDIDATE with full, untruncated text from VIEW's collected data."
  (if (not candidate) "No result selected.\n"
    (let* ((symbol (get-text-property 0 'consult--candidate candidate))
           (location (lsp-get symbol :location))
           (start (lsp-get (lsp-get location :range) :start)))
      (format "Symbol\n%s\n\nParent\n%s\n\nType\n%s\n\nProject-relative location\n%s\n\nFull source URI\n%s\n\nPosition\nLine %d, character %d\n"
              (lsp-get symbol :name)
              (or (lsp-get symbol :containerName) "—")
              (or (alist-get (lsp-get symbol :kind) lsp-symbol-kinds) "Other")
              (my--symbols-relative-location candidate (plist-get view :root))
              (lsp-get location :uri)
              (1+ (or (lsp-get start :line) 0)) (1+ (or (lsp-get start :character) 0))))))

(defun my--symbols-help-text (view)
  "Describe picker controls and VIEW's query-aware kind filters."
  (concat
   (format "Presentation: %s; layout: %s; Source tree guides: %s; scope highlight: %s; origin marker: %s\n\n"
           (capitalize (symbol-name (plist-get view :order)))
           (capitalize (symbol-name (or (plist-get view :layout) 'full)))
           (if (plist-get view :tree-guides) "on" "off")
           (if (plist-get view :scope-highlight) "on" "off")
           (if (plist-get view :origin-marker) "on" "off"))
   "Navigation\nBoth presentations initially select the symbol enclosing the original cursor.\nKind: selection at top with a sticky kind heading; Source: centered with context.\nTAB / Shift-TAB place the target group or root at the top.\nFiltering keeps a surviving selection; otherwise it selects the first match.\n↑ / ↓           Select each result\nTAB / Shift-TAB Kind: cycle categories; Source: next / previous tree root\nRET             Jump to the selected symbol\nC-g             Cancel\n\nPresentation\nC-c C-s         Toggle Kind / Source\nC-c C-l         Toggle Full / Compact columns\nC-c C-t         Toggle Source tree guides\nC-c C-r         Toggle the preview scope highlight\nC-c C-o         Toggle the original-position marker\nC-c C-d         Toggle full details for the selected result\nC-c C-w         Toggle collection errors\nC-c C-h         Toggle this help panel\nC-M-v / C-M-S-v Scroll the panel down / up\n\nColumns\nFull: Glyph | Symbol | Parent | Path | Type\nCompact: Glyph | Symbol | Path (subject to configured visibility).\nThe folder marker means the project root; — means no parent.\n• in the gutter marks the symbol enclosing the original cursor position; it stays there as you browse.\nEllipses and hidden columns change display only. Full names, paths and annotations remain searchable.\n\nConfiguration (M-x customize-variable)\nmy-symbols-column-widths: maximum widths, independently per column\nmy-symbols-visible-columns: columns enabled in Full layout\nmy-symbols-default-layout: full (default) or compact\nmy-symbols-tree-guides: default Source guides\nmy-symbols-scope-highlight: default scope highlighting\nmy-symbols-scope-face: M-x customize-face (optional scope background override)\nmy-symbols-origin-marker: default original-position marker\nmy-symbols-origin-marker-face: M-x customize-face\n\nScope preview\nThe cursor-line background marks the full range supplied by the server; the destination row uses the visual selection color.\nThe stale cursor-line highlight is hidden during preview and restored on exit.\nJump flashes are suppressed; the cursor lands at the exact LSP symbol start.\nNo scope is inferred from a name-only location. It clears when previewing stops.\n\nSearch\nExisting Orderless syntax applies; a trailing ~ enables fuzzy subsequence matching.\n\nKind filters\n"
   (if consult-narrow-key
       (format "%s ? opens this help; %s clears the kind filter.\n"
               consult-narrow-key (key-description (consult--widen-key)))
     "The Consult narrowing prefix is currently disabled.\n")
   (mapconcat (lambda (entry)
                (format "%s %c  %s" (or consult-narrow-key "") (car entry)
                        (my--project-symbols-count-label view (car entry) (cdr entry))))
              (plist-get view :types) "\n")
   "\n\nCollection\n"
   (if (plist-get view :failures)
       (format "%d files failed; results are incomplete. C-c C-w shows the errors.\n"
               (length (plist-get view :failures)))
     "No file requests failed. Coverage still follows the active providers and project exclusions.\n")))

(defun my--symbols-panel-text (view kind)
  "Return VIEW's panel contents for KIND."
  (pcase kind
    ('details (my--symbols-detail-text view (my--symbols-selected)))
    ('help (my--symbols-help-text view))
    ('errors (if (plist-get view :failures)
                 (format "Results are incomplete: %d files failed.\n\n%s\n"
                         (length (plist-get view :failures))
                         (string-join (plist-get view :failures) "\n\n"))
               "No file requests failed during collection.\n"))))

(defun my--symbols-update-panel (view &optional force)
  "Refresh VIEW's non-selecting read-only panel, keeping its scrolling stable."
  (when (and (plist-get view :panel-kind)
             (not (buffer-live-p (plist-get view :panel-buffer))))
    (my--symbols-close-panel view))
  (when-let ((kind (plist-get view :panel-kind)))
    (let ((signature (pcase kind
                       ('details (my--symbols-selected))
                       ('help (list (plist-get view :input) (plist-get view :order)
                                    (plist-get view :tree-guides) (plist-get view :layout)
                                    (plist-get view :scope-highlight)))
                       (_ kind))))
      (when (or force (not (equal signature (plist-get view :panel-signature))))
        ;; Resolve selected-candidate state before changing to the panel buffer.
        (let ((text (my--symbols-panel-text view kind)))
          (with-current-buffer (plist-get view :panel-buffer)
            (let ((inhibit-read-only t) (position (point)))
              (erase-buffer)
              (insert text)
              (goto-char (min position (point-max))))))
        (setf (plist-get view :panel-signature) signature)))))

(defun my--symbols-toggle-panel (kind)
  "Toggle a read-only KIND panel while keeping focus in the picker."
  (unless my--symbols-view (user-error "No symbol picker is active"))
  (let ((view my--symbols-view))
    (if (and (eq kind (plist-get view :panel-kind))
             (window-live-p (plist-get view :panel-window))
             (eq (window-buffer (plist-get view :panel-window)) (plist-get view :panel-buffer)))
        (my--symbols-close-panel view)
      (unless (buffer-live-p (plist-get view :panel-buffer))
        (setf (plist-get view :panel-buffer) (generate-new-buffer " *Symbol picker panel*"))
        (with-current-buffer (plist-get view :panel-buffer)
          (special-mode)
          (setq-local truncate-lines nil)))
      (setf (plist-get view :panel-kind) kind)
      (my--project-symbols-refresh-counts view)
      (my--symbols-update-panel view t)
      (with-current-buffer (plist-get view :panel-buffer)
        (setq-local header-line-format (capitalize (symbol-name kind)))
        (goto-char (point-min)))
      (unless (window-live-p (plist-get view :panel-window))
        (when-let ((previous (seq-find
                             (lambda (window)
                               (and (eq (window-parameter window 'window-side) 'right)
                                    (equal (window-parameter window 'window-slot) 3)))
                             (window-list))))
          (setf (plist-get view :panel-restore)
                (list (window-buffer previous) (window-point previous) (window-start previous)))))
      (setf (plist-get view :panel-window)
            (display-buffer-in-side-window
             (plist-get view :panel-buffer)
             '((side . right) (slot . 3) (window-width . 0.45)
               (window-parameters . ((no-other-window . t))))))
      (setq-local other-window-scroll-buffer (plist-get view :panel-buffer)
                  minibuffer-scroll-window (plist-get view :panel-window)))))

(defun my--symbols-details () "Toggle full details of the selected symbol."
  (interactive) (my--symbols-toggle-panel 'details))
(defun my--symbols-help () "Toggle picker navigation, display and filter help."
  (interactive) (my--symbols-toggle-panel 'help))
(defun my--symbols-errors () "Toggle errors from this picker's collection."
  (interactive) (my--symbols-toggle-panel 'errors))
(defun my--symbols-toggle-guides () "Toggle Source tree guides for this picker."
  (interactive)
  (unless my--symbols-view (user-error "No symbol picker is active"))
  (setf (plist-get my--symbols-view :tree-guides)
        (not (plist-get my--symbols-view :tree-guides)))
  (vertico--exhibit))

(defun my--symbols-toggle-layout ()
  "Toggle Full / Compact columns without changing selection, query or filters."
  (interactive)
  (unless my--symbols-view (user-error "No symbol picker is active"))
  (setf (plist-get my--symbols-view :layout)
        (if (eq (plist-get my--symbols-view :layout) 'compact) 'full 'compact))
  (my--symbols-show-order my--symbols-view)
  (vertico--exhibit))

(defun my--symbols-toggle-origin ()
  "Toggle the original-position marker without changing picker selection."
  (interactive)
  (unless my--symbols-view (user-error "No symbol picker is active"))
  (setf (plist-get my--symbols-view :origin-marker)
        (not (plist-get my--symbols-view :origin-marker)))
  (vertico--exhibit))

(defun my--symbols-toggle-scope ()
  "Toggle the current symbol preview's full-scope highlight without moving it."
  (interactive)
  (unless my--symbols-view (user-error "No symbol picker is active"))
  (setf (plist-get my--symbols-view :scope-highlight)
        (not (plist-get my--symbols-view :scope-highlight)))
  (if (and (minibufferp) (not (my--symbols-selected)))
      (my--symbols-clear-scope my--symbols-view)
    (my--symbols-refresh-scope my--symbols-view)))

(defun my--symbols-initial-order (scope)
  "Return SCOPE's remembered presentation or configured default."
  (or (and my-symbols-remember-order (alist-get scope my--symbols-last-orders))
      (if (eq scope 'buffer) my-buffer-symbols-default-order
        my-project-symbols-default-order)))

(defun my--symbols-file (candidate)
  "Return CANDIDATE's URI, used for stable file ordering and grouping."
  (or (lsp-get (lsp-get (get-text-property 0 'consult--candidate candidate) :location) :uri) ""))

(defun my--symbols-source-less-p (a b)
  "Compare A and B by file and source position, with parents before children."
  (let* ((file-a (my--symbols-file a)) (file-b (my--symbols-file b))
         (symbol-a (get-text-property 0 'consult--candidate a))
         (symbol-b (get-text-property 0 'consult--candidate b))
         (range-a (or (lsp-get symbol-a :my-range)
                      (lsp-get (lsp-get symbol-a :location) :range)))
         (range-b (or (lsp-get symbol-b :my-range)
                      (lsp-get (lsp-get symbol-b :location) :range))))
    (if (not (equal file-a file-b)) (string-lessp file-a file-b)
      (let ((keys (lambda (range)
                    (list (or (lsp-get (lsp-get range :start) :line) 0)
                          (or (lsp-get (lsp-get range :start) :character) 0)
                          (- (or (lsp-get (lsp-get range :end) :line) 0))
                          (- (or (lsp-get (lsp-get range :end) :character) 0))))))
        (cl-loop for x in (funcall keys range-a) for y in (funcall keys range-b)
                 when (/= x y) return (< x y))))))

(defun my--symbols-ranks (candidates order)
  "Precompute stable CANDIDATES ranks for ORDER."
  (let ((sorted (cl-stable-sort (copy-sequence candidates) #'my--symbols-source-less-p))
        (ranks (make-hash-table :test #'equal)) (index 0))
    (when (eq order 'kind)
      (setq sorted
            (cl-stable-sort sorted
                            (lambda (a b)
                              (string-lessp
                               (or (alist-get (get-text-property 0 'consult--type a)
                                              consult-lsp-symbols-narrow) "Other")
                               (or (alist-get (get-text-property 0 'consult--type b)
                                              consult-lsp-symbols-narrow) "Other"))))))
    (dolist (candidate sorted ranks)
      (puthash candidate (cl-incf index) ranks))))

(defun my--symbols-sort (view candidates)
  "Sort matching CANDIDATES by VIEW's presentation, independently of history."
  (let ((ranks (plist-get view (if (eq (plist-get view :order) 'source)
                                  :source-ranks :kind-ranks))))
    (cl-stable-sort (copy-sequence candidates)
                    (lambda (a b) (< (gethash a ranks 0) (gethash b ranks 0))))))

(defun my--symbols-roots (candidates)
  "Map all CANDIDATES to their source-tree roots, before query filtering.
Flat server responses treat each symbol as a root. File boundaries always
start a new root; names alone cannot identify roots across files."
  (let ((roots (make-hash-table :test #'equal)) file root)
    (dolist (candidate (cl-stable-sort (copy-sequence candidates)
                                     #'my--symbols-source-less-p) roots)
      (let ((uri (my--symbols-file candidate))
            (symbol (get-text-property 0 'consult--candidate candidate)))
        (when (or (not (equal file uri))
                  (zerop (or (lsp-get symbol :my-depth) 0)))
          (setq file uri root candidate))
        (puthash candidate root roots)))))

(defun my--symbols-position-less-p (a b)
  "Return non-nil when LSP position A precedes B."
  (or (< (lsp-get a :line) (lsp-get b :line))
      (and (= (lsp-get a :line) (lsp-get b :line))
           (< (lsp-get a :character) (lsp-get b :character)))))

(defun my--symbols-enclosing (candidates uri position)
  "Find the innermost CANDIDATES entry enclosing POSITION in URI.
Use full document-symbol ranges, not just the symbol name's selection range.
LSP ranges include their start and exclude their end."
  (let (best best-start (depth -1))
    (dolist (candidate candidates best)
      (when (equal (my--symbols-file candidate) uri)
        (let* ((symbol (get-text-property 0 'consult--candidate candidate))
               (range (or (lsp-get symbol :my-range)
                          (lsp-get (lsp-get symbol :location) :range)))
               (start (lsp-get range :start)) (end (lsp-get range :end))
               (level (or (lsp-get symbol :my-depth) 0)))
          (when (and start end
                     (not (my--symbols-position-less-p position start))
                     (my--symbols-position-less-p position end)
                     (or (> level depth)
                         (and (= level depth) best-start
                              (my--symbols-position-less-p best-start start))))
            (setq best candidate best-start start depth level)))))))

(defvar-local my--symbols-placement nil
  "Pending viewport placement: top or center; nil preserves natural scrolling.")
(defvar-local my--symbols-filter-signature :unset)

(defun my--symbols-place-selection (&optional top)
  "Place the selection at TOP, or according to the current presentation."
  (setq my--symbols-placement
        (if (or top (eq (plist-get my--symbols-view :order) 'kind)) 'top 'center)))

(defun my--symbols-select-initial (candidate)
  "Select CANDIDATE at the top in Kind, or centered with context in Source."
  (when candidate
    (vertico--update)
    (when-let ((index (cl-position candidate vertico--candidates :test #'equal)))
      (my--symbols-place-selection)
      (vertico--goto index)
      (vertico--exhibit))))

(defun my--symbols-update-filter (original &rest args)
  "Preserve a surviving selection when ORIGINAL updates this picker's filter."
  (if (not my--symbols-view) (apply original args)
    (let* ((signature (list (minibuffer-contents-no-properties) consult--narrow))
           (changed (and (not (eq my--symbols-filter-signature :unset))
                         (not (equal signature my--symbols-filter-signature))))
           (selected (my--symbols-selected))
           (result (apply original args)))
      (setq my--symbols-filter-signature signature)
      (when changed
        (let ((index (and selected (cl-position selected vertico--candidates :test #'equal))))
          (setq vertico--index (or index (if vertico--candidates 0 -1))
                vertico--lock-candidate nil)
          (my--symbols-place-selection (not index))))
      result)))

(with-eval-after-load 'vertico
  (advice-remove 'vertico--compute-scroll 'my--symbols-opening-scroll)
  (advice-add 'vertico--update :around #'my--symbols-update-filter))

(defun my--symbols-next-group (&optional n)
  "Move N tree roots in Source presentation, or cycle kind groups in Kind.
When a root is filtered out, visit its first visible descendant instead."
  (interactive "p")
  (if (not (eq (plist-get my--symbols-view :order) 'source))
      (vertico-next-group n)
    (vertico--update)
    (let ((roots (plist-get my--symbols-view :roots))
          (index 0) previous keys positions)
      (dolist (candidate vertico--candidates)
        (let ((root (gethash candidate roots)))
          (unless (equal root previous)
            (push root keys)
            (push index positions)
            (setq previous root)))
        (cl-incf index))
      (setq keys (nreverse keys) positions (nreverse positions))
      (when positions
        (let* ((current (and (>= vertico--index 0)
                             (gethash (nth vertico--index vertico--candidates) roots)))
               (section (and current (cl-position current keys :test #'equal)))
               (steps (or n 1))
               (target (if (zerop steps) 0
                         (if section (mod (+ section steps) (length positions))
                           (if (> steps 0) 0 (1- (length positions)))))))
          (vertico--goto (nth target positions))))))
  (my--symbols-place-selection t))

(defun my--symbols-previous-group (&optional n)
  "Move N tree roots backward in Source, or cycle kind groups backward."
  (interactive "p")
  (my--symbols-next-group (- (or n 1))))

(defun my--symbols-show-order (view)
  "Display VIEW's presentation in the minibuffer prompt."
  (when-let ((overlay (plist-get view :order-overlay)))
    (overlay-put overlay 'before-string
                 (concat (propertize (if (eq (plist-get view :order) 'kind) "[Kind] " "[Source] ")
                                     'face 'minibuffer-prompt)
                         (propertize (if (eq (plist-get view :layout) 'compact) "[Compact] " "[Full] ")
                                     'face 'shadow)
                         (when (plist-get view :failures)
                           (propertize (format "[Incomplete: %d] " (length (plist-get view :failures)))
                                       'face 'warning))))))

(defun my--symbols-track-selection (view)
  "Record whether the user has left VIEW's automatic opening selection."
  (when (and (not (plist-get view :source-opened))
             (plist-get view :opening-selection)
             (or consult--narrow
                 (not (equal (minibuffer-contents-no-properties) ""))
                 (not (equal (plist-get view :opening-selection)
                             (and (>= vertico--index 0)
                                  (nth vertico--index vertico--candidates))))))
    (setf (plist-get view :navigated) t)))

(defun my--symbols-toggle-order ()
  "Toggle this picker's Kind/Source presentation without changing its query."
  (interactive)
  (unless my--symbols-view (user-error "No symbol picker is active"))
  (let* ((view my--symbols-view)
         (selected (and (>= vertico--index 0) (nth vertico--index vertico--candidates)))
         (order (if (eq (plist-get view :order) 'kind) 'source 'kind))
         (enclosing (and (eq order 'source)
                         (not (plist-get view :source-opened))
                         (not (plist-get view :navigated))
                         (not consult--narrow)
                         (equal (minibuffer-contents-no-properties) "")
                         (equal selected (plist-get view :opening-selection))
                         (plist-get view :origin-candidate))))
    (setf (plist-get view :order) order)
    (when my-symbols-remember-order
      (setf (alist-get (plist-get view :scope) my--symbols-last-orders) order))
    (my--symbols-show-order view)
    ;; Invalidate only presentation state, preserving Consult's query/filter.
    (setq vertico--input nil vertico--lock-groups nil vertico--lock-candidate nil)
    (vertico--update)
    (when-let ((index (and selected (cl-position selected vertico--candidates :test #'equal))))
      (setq vertico--index index))
    (when (eq order 'source)
      (setf (plist-get view :source-opened) t)
      (when enclosing (my--symbols-select-initial enclosing)))
    (my--symbols-place-selection)
    (vertico--exhibit)))

(defvar my-project-symbols-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "TAB") #'my--symbols-next-group)
    (define-key map (kbd "<tab>") #'my--symbols-next-group)
    (define-key map (kbd "<backtab>") #'my--symbols-previous-group)
    (define-key map (kbd "S-TAB") #'my--symbols-previous-group)
    map)
  "Minibuffer bindings shared by the buffer and project symbol pickers.")

(defun my--project-symbols-keymap ()
  "Return picker bindings with help under the configured narrowing prefix."
  (let ((map (copy-keymap my-project-symbols-map)))
    ;; Refresh these bindings when reloading an already-defined base map.
    (dolist (key '("TAB" "<tab>"))
      (define-key map (kbd key) #'my--symbols-next-group))
    (dolist (key '("<backtab>" "S-TAB"))
      (define-key map (kbd key) #'my--symbols-previous-group))
    (define-key map (kbd "C-c C-s")
                '("Toggle Kind/Source" . my--symbols-toggle-order))
    (dolist (binding '(("C-c C-d" . my--symbols-details) ("C-c C-h" . my--symbols-help)
                       ("C-c C-w" . my--symbols-errors) ("C-c C-t" . my--symbols-toggle-guides)
                       ("C-c C-l" . my--symbols-toggle-layout) ("C-c C-r" . my--symbols-toggle-scope)
                       ("C-c C-o" . my--symbols-toggle-origin)))
      (define-key map (kbd (car binding)) (cdr binding)))
    (when consult-narrow-key
      (define-key map (vconcat (kbd consult-narrow-key) (kbd "?"))
                  '("Navigation and filter help" . my--symbols-help)))
    map))

(defun my--project-symbols-narrow ()
  "Return kind filters, including a combined Functions + Methods filter."
  (list :keys (append consult-lsp-symbols-narrow '((?a . "Functions + Methods")))
        :predicate
        (lambda (candidate)
          (if (eq consult--narrow ?a)
              (memq (lsp-get (get-text-property 0 'consult--candidate candidate) :kind)
                    '(6 12))
            (eq (get-text-property 0 'consult--type candidate) consult--narrow)))))

(defun my--project-symbols-count-kinds (candidates)
  "Count CANDIDATES by narrowing key, including Functions + Methods."
  (let ((counts (make-hash-table :test #'eql)))
    (dolist (candidate candidates counts)
      (let ((key (get-text-property 0 'consult--type candidate))
            (kind (lsp-get (get-text-property 0 'consult--candidate candidate) :kind)))
        (puthash key (1+ (gethash key counts 0)) counts)
        (when (memq kind '(6 12))
          (puthash ?a (1+ (gethash ?a counts 0)) counts))))))

(defun my--project-symbols-count-label (view key name)
  "Format NAME with VIEW's current and total counts for KEY (nil means all)."
  (let ((total (if key (gethash key (plist-get view :totals) 0)
                 (length (plist-get view :candidates))))
        (matching (if key (gethash key (plist-get view :matches) 0)
                    (plist-get view :match-count))))
    (if (equal (plist-get view :input) "")
        (format "%s (%d)" name total)
      (format "%s (%d/%d)" name matching total))))

(defun my--project-symbols-count-menu (view)
  "Update VIEW's private narrowing keymap with counted labels."
  (let ((map (plist-get view :keymap)))
    (when consult-narrow-key
      (dolist (entry (plist-get view :types))
        (define-key map (vconcat (kbd consult-narrow-key) (vector (car entry)))
                    (cons (my--project-symbols-count-label view (car entry) (cdr entry))
                          #'consult-narrow))))
    (when-let ((widen (consult--widen-key)))
      (define-key map widen
                  (cons (my--project-symbols-count-label view nil "All") #'consult-narrow)))))

(defun my--project-symbols-refresh-counts (view)
  "Refresh VIEW from the current query, independently of the active kind filter.
Use the real completion table and styles, including Orderless annotations.
Cache by input and cursor position; group callbacks reuse the same counts."
  (when (minibufferp)
    (let* ((input (minibuffer-contents-no-properties))
           (position (- (point) (minibuffer-prompt-end)))
           (signature (cons input position)))
      (unless (equal signature (plist-get view :signature))
        (let ((matches (if (equal input "")
                           (plist-get view :candidates)
                         ;; A nil predicate deliberately ignores kind narrowing.
                         (let ((result (completion-all-completions
                                        input minibuffer-completion-table nil position)))
                           ;; Completion results can have a dotted base-size tail.
                           (when result (setcdr (last result) nil))
                           result))))
          (setf (plist-get view :input) input
                (plist-get view :signature) signature
                (plist-get view :matches) (my--project-symbols-count-kinds matches)
                (plist-get view :match-count) (length matches))
          (my--project-symbols-count-menu view))))))

(defun my--project-symbols-interface (candidates &optional scope)
  "Build groups, filters and bindings for CANDIDATES in buffer/project SCOPE."
  (let* ((narrow (my--project-symbols-narrow))
         (totals (my--project-symbols-count-kinds candidates))
         (types (plist-get narrow :keys))
         (map (my--project-symbols-keymap))
         (view (list :scope (or scope 'project)
                     :order (my--symbols-initial-order (or scope 'project))
                     :kind-ranks (my--symbols-ranks candidates 'kind)
                     :source-ranks (my--symbols-ranks candidates 'source)
                     :roots (my--symbols-roots candidates)
                     :tree-prefixes (my--symbols-tree-prefixes candidates)
                     :tree-guides my-symbols-tree-guides :header t :failures nil
                     :scope-highlight my-symbols-scope-highlight
                     :origin-marker my-symbols-origin-marker
                     :scope-overlay nil :scope-candidate nil :scope-window nil :scope-buffer nil
                     :scope-encodings (let ((encodings (make-hash-table :test #'eq)))
                                        (dolist (candidate candidates encodings)
                                          (puthash (get-text-property 0 'consult--candidate candidate)
                                                   (get-text-property 0 'my--symbols-position-encoding candidate)
                                                   encodings)))
                     :layout my-symbols-default-layout
                     :panel-kind nil :panel-buffer nil :panel-window nil
                     :panel-signature nil :panel-restore nil :picker-buffer nil
                     :previous-scroll-buffer nil :previous-scroll-window nil
                     :root nil
                     :origin-candidate nil :opening-selection nil
                     :source-opened nil :navigated nil
                     :order-overlay nil
                     :candidates candidates :totals totals :matches totals
                     :match-count (length candidates) :input "" :signature nil
                     :keymap map :types types)))
    (setf (plist-get narrow :keys) types)
    (my--project-symbols-count-menu view)
    (list :keymap map :narrow narrow :view view
          :setup (lambda ()
                   (setq-local my--symbols-view view my--symbols-opening-offset nil my--symbols-placement nil
                               my--symbols-filter-signature :unset)
                   (setf (plist-get view :picker-buffer) (current-buffer)
                         (plist-get view :previous-scroll-buffer) other-window-scroll-buffer
                         (plist-get view :previous-scroll-window) minibuffer-scroll-window)
                   ;; Source modes also use these keys. Give only the picker
                   ;; controls priority here, preserving other bindings.
                   (let ((toggle-map (make-sparse-keymap)))
                     (define-key toggle-map (kbd "C-c C-s") #'my--symbols-toggle-order)
                     (dolist (key '("C-c C-d" "C-c C-h" "C-c C-w" "C-c C-t" "C-c C-l" "C-c C-r" "C-c C-o"))
                       (define-key toggle-map (kbd key) (lookup-key map (kbd key))))
                     (setq-local emulation-mode-map-alists
                                 (cons (list (cons 'my--symbols-view toggle-map))
                                       emulation-mode-map-alists)))
                   (setq-local vertico-sort-override-function
                               (apply-partially #'my--symbols-sort view))
                   (setf (plist-get view :order-overlay) (make-overlay (point-min) (point-min)))
                   (my--symbols-show-order view)
                   (add-hook 'post-command-hook
                             (lambda ()
                               (vertico--update)
                               (my--project-symbols-refresh-counts view)
                               (my--symbols-track-selection view)
                               (my--symbols-sync-scope view)
                               (my--symbols-update-panel view)) nil t))
          :group (lambda (candidate transform)
                   (if transform candidate
                     (my--project-symbols-refresh-counts view)
                     (if (eq (plist-get view :order) 'source)
                         (when (eq (plist-get view :scope) 'project)
                           (let ((location (my--symbols-relative-location candidate (plist-get view :root))))
                             (replace-regexp-in-string
                              ":[0-9]+\\'" ""
                              location)))
                       (let* ((key (get-text-property 0 'consult--type candidate))
                              (name (alist-get key consult-lsp-symbols-narrow)))
                         (my--project-symbols-count-label view key (or name "Other")))))))))

(defcustom my-project-symbols-excluded-directories
  '(".git" ".venv" "venv" "env" ".env" ".direnv" ".tox" ".nox"
    "site-packages" "node_modules" "vendor" "__pycache__" "build" "dist"
    "target" ".mypy_cache" ".pytest_cache" ".ruff_cache")
  "Directory names excluded from `my/project-symbols'.
Projectile's own exclusions also apply. Python environment markers are
recognized even when an environment uses a different directory name."
  :type '(repeat string) :group 'convenience)

(defun my--project-symbols-excluded-p (file root cache)
  "Return non-nil if FILE under ROOT is excluded, memoizing directories in CACHE."
  (let* ((relative (file-relative-name file root))
         (components (butlast (split-string relative "/" t))))
    (or (file-remote-p relative)
        (string-prefix-p "../" relative)
        (cl-some (lambda (part) (member part my-project-symbols-excluded-directories))
                 components)
        ;; Resolve symlinks so an in-project link cannot pull in external packages.
        (not (file-in-directory-p file root))
        (cl-labels
            ((environment-p
              (directory)
              (let ((cached (gethash directory cache 'unknown)))
                (if (not (eq cached 'unknown)) cached
                  (puthash
                   directory
                   (and (not (equal directory root))
                        (or (file-exists-p (expand-file-name "pyvenv.cfg" directory))
                            (file-directory-p (expand-file-name "conda-meta" directory))
                            (environment-p
                             (file-name-directory (directory-file-name directory)))))
                   cache)))))
          (environment-p (file-name-directory file))))))

(defun my--project-symbols-workspaces (root)
  "Return initialized document-symbol providers associated with ROOT."
  (let (workspaces)
    (maphash
     (lambda (_folder entries)
       (dolist (workspace entries)
         (let ((directory (lsp--workspace-root workspace)))
           (when (and directory
                      (equal (file-remote-p root) (file-remote-p directory))
                      (eq (lsp--workspace-status workspace) 'initialized)
                      (or (equal (file-name-as-directory directory) root)
                          (file-in-directory-p root directory)
                          (file-in-directory-p directory root))
                      (lsp--workspace-method-supported?
                       nil "textDocument/documentSymbol" :documentSymbolProvider workspace))
             (cl-pushnew workspace workspaces)))))
     (lsp-session-folder->servers (lsp-session)))
    workspaces))

(defun my--project-symbols-file-context (file workspaces)
  "Return (WORKSPACE LANGUAGE BUFFER) for FILE, or nil if unsupported.
Use filename mode associations without running mode hooks or local variables."
  (let ((existing (find-buffer-visiting file)))
    (with-temp-buffer
      (setq buffer-file-name file
            default-directory (file-name-directory file))
      (setq major-mode
            (if existing (buffer-local-value 'major-mode existing)
              (let* ((case-fold-search auto-mode-case-fold)
                     (mode (assoc-default file auto-mode-alist #'string-match)))
                (if (consp mode) (car mode) mode))))
      (when (and major-mode (symbolp major-mode))
        (let ((lsp-enabled-clients nil)
              (lsp-warn-no-matched-clients nil))
          (when-let
              ((workspace
                (cl-find-if
                 (lambda (workspace)
                   (lsp--supports-buffer? (lsp--workspace-client workspace)))
                 workspaces)))
            (list workspace (lsp-buffer-language) existing)))))))

(defun my--project-symbols-document (file workspace language existing)
  "Ask WORKSPACE for FILE's symbols, using LANGUAGE and EXISTING buffer text.
Temporarily open unopened documents to LSP only, then close them even on quit
or error. Existing LSP documents stay open and unsaved edits are respected."
  (let* ((lsp--cur-workspace workspace)
         (uri (lsp--path-to-uri file))
         (opened (and existing
                      (memq workspace (buffer-local-value 'lsp--buffer-workspaces existing))))
         temporary-open)
    (unwind-protect
        (progn
          (if opened
              (with-current-buffer existing (lsp--flush-delayed-changes))
            (let ((text (if existing
                            (with-current-buffer existing
                              (save-restriction
                                (widen)
                                (buffer-substring-no-properties (point-min) (point-max))))
                          (with-temp-buffer
                            (insert-file-contents file)
                            (buffer-string)))))
              (lsp-notify "textDocument/didOpen"
                          (list :textDocument
                                (list :uri uri :languageId language :version 0 :text text)))
              (setq temporary-open t)))
          (lsp-request "textDocument/documentSymbol"
                       (list :textDocument (list :uri uri))))
      (when temporary-open
        (let ((inhibit-quit t))
          (ignore-errors
            (lsp-notify "textDocument/didClose" (list :textDocument (list :uri uri)))))))))

(defun my--project-symbols-object (&rest properties)
  "Make an LSP object from PROPERTIES in the configured JSON representation."
  (if lsp-use-plists properties
    (let ((object (make-hash-table :test #'equal)))
      (while properties
        (puthash (substring (symbol-name (pop properties)) 1) (pop properties) object))
      object)))

(defun my--project-symbols-normalize (symbols uri)
  "Convert hierarchical or flat document SYMBOLS for URI to SymbolInformation."
  (let (result)
    (cl-labels
        ((visit
          (entries parent depth)
          (mapc
           (lambda (symbol)
             (let* ((name (lsp-get symbol :name))
                    (location (lsp-get symbol :location))
                    (range (or (lsp-get symbol :selectionRange)
                               (lsp-get symbol :range))))
               ;; Flat responses may contain locations in other files; keep only
               ;; definitions in the document we explicitly requested.
               (when (and name (or range location)
                          (or (null location) (equal (lsp-get location :uri) uri)))
                 (push
                  (my--project-symbols-object
                   :name name :kind (lsp-get symbol :kind)
                   :my-depth depth
                   :my-scope-range (lsp-get symbol :range)
                   :my-range (or (lsp-get symbol :range) range
                                 (lsp-get location :range))
                   :containerName (or (lsp-get symbol :containerName) parent)
                   :location (or location (my--project-symbols-object :uri uri :range range)))
                  result))
               (when-let ((children (lsp-get symbol :children)))
                 (visit children (if parent (concat parent "." name) name) (1+ depth)))))
           entries)))
      (visit symbols nil 0))
    (nreverse result)))

(defun my--project-symbols-candidate (workspace symbol)
  "Transform SYMBOL from WORKSPACE into a Consult candidate with a valid type."
  (let* ((candidate (funcall consult-lsp-symbols-transformer-function workspace symbol))
         (type (get-text-property 0 'consult--type candidate)))
    ;; consult-lsp's fallback for unlisted kinds (e.g. Constructor) returns
    ;; (?o . "Other") instead of ?o.  Consult then gives these a nil group,
    ;; which prevents Vertico from cycling past that group with TAB.
    (when (consp type)
      (put-text-property 0 (length candidate) 'consult--type (car type) candidate))
    (put-text-property 0 (length candidate) 'my--symbols-position-encoding
                       (or (lsp-get (lsp--workspace-server-capabilities workspace) :positionEncoding) "utf-16")
                       candidate)
    candidate))

(defconst my-project-symbols-icon-specs
  '((1 "symbol_file" font-lock-string-face)
    (2 "symbol_namespace" font-lock-type-face)
    (3 "symbol_namespace" font-lock-type-face)
    (4 "package" font-lock-type-face)
    (5 "symbol_class" font-lock-type-face)
    (6 "symbol_method" font-lock-function-name-face)
    (7 "symbol_property" font-lock-variable-name-face)
    (8 "symbol_field" font-lock-variable-name-face)
    (9 "symbol_method" font-lock-function-name-face)
    (10 "symbol_enum" font-lock-type-face)
    (11 "symbol_interface" font-lock-type-face)
    (12 "symbol_method" font-lock-function-name-face)
    (13 "symbol_variable" font-lock-variable-name-face)
    (14 "symbol_constant" font-lock-constant-face)
    (15 "symbol_string" font-lock-string-face)
    (16 "symbol_numeric" font-lock-constant-face)
    (17 "symbol_boolean" font-lock-constant-face)
    (18 "symbol_array" font-lock-type-face)
    (19 "symbol_misc" font-lock-type-face)
    (20 "symbol_key" font-lock-variable-name-face)
    (21 "symbol_misc" font-lock-constant-face)
    (22 "symbol_enum_member" font-lock-constant-face)
    (23 "symbol_structure" font-lock-type-face)
    (24 "symbol_event" font-lock-warning-face)
    (25 "symbol_operator" font-lock-builtin-face)
    (26 "symbol_parameter" font-lock-type-face))
  "LSP SymbolKind numbers mapped to Codicon names and theme faces.
SymbolKind and completion-item kind numbers are different enumerations.")

(defun my--symbols-column-limit (column)
  "Return COLUMN's configured positive maximum width."
  (let ((width (alist-get column my-symbols-column-widths
                          (alist-get column '((glyph . 2) (symbol . 36) (parent . 24) (path . 60) (type . 14))))))
    (unless (and (integerp width) (> width 0))
      (user-error "Width for symbol column %s must be a positive integer" column))
    width))

(defun my--symbols-layout-plan (window-width &optional view)
  "Return visible columns and their widths for WINDOW-WIDTH and VIEW.
Never hide columns automatically: only Compact or explicit visibility settings
hide fields. Symbol remains available even when every optional column is off."
  (let* ((columns (seq-filter
                   (lambda (column)
                     (and (or (eq column 'symbol) (memq column my-symbols-visible-columns))
                          (or (not (eq (plist-get view :layout) 'compact))
                              (not (memq column '(parent type))))))
                   '(glyph symbol parent path type)))
         (text-columns (remq 'glyph (copy-sequence columns)))
         (gaps (* 2 (1- (length columns))))
         (gutter (my--symbols-origin-width view))
         (glyph (if (memq 'glyph columns)
                    (min (my--symbols-column-limit 'glyph)
                         (max 1 (- window-width 4 gaps gutter (length text-columns)))) 0))
         (available (max (length text-columns) (- window-width 4 glyph gaps gutter)))
         (type (if (memq 'type columns)
                   (max 1 (min (my--symbols-column-limit 'type) (max 8 (/ available 10))
                               (- available (1- (length text-columns))))) 0))
         (remaining (- available type))
         (parent-p (memq 'parent columns)) (path-p (memq 'path columns))
         (name (max 1 (min (my--symbols-column-limit 'symbol)
                           (- remaining (if parent-p 1 0) (if path-p 1 0))
                           (cond ((and parent-p path-p) (/ (* remaining 2) 5))
                                 (path-p (/ remaining 2))
                                 (parent-p (/ (* remaining 3) 5))
                                 (t remaining)))))
         (parent (if parent-p
                     (max 1 (min (my--symbols-column-limit 'parent)
                                 (- remaining name (if path-p 1 0))
                                 (if path-p (/ remaining 4) (- remaining name)))) 0))
         (path (if path-p (max 1 (min (my--symbols-column-limit 'path) (- remaining name parent))) 0))
         (widths `((glyph . ,glyph) (symbol . ,name) (parent . ,parent) (path . ,path) (type . ,type))))
    (mapcar (lambda (column) (assq column widths)) columns)))

(defun my--symbols-column-widths (window-width &optional view)
  "Return symbol, parent, path and type widths; hidden columns have width zero."
  (let ((plan (my--symbols-layout-plan window-width view)))
    (mapcar (lambda (column) (alist-get column plan 0)) '(symbol parent path type))))

(defun my--symbols-column-header ()
  "Build fixed column titles using exactly the result-row widths."
  (let ((plan (my--symbols-layout-plan (window-body-width (minibuffer-window)) my--symbols-view)))
    (propertize
     (concat (make-string (my--symbols-origin-width my--symbols-view) ?\s)
             (mapconcat
              (lambda (cell)
                (truncate-string-to-width
                 (if (eq (car cell) 'glyph) "" (capitalize (symbol-name (car cell))))
                 (cdr cell) nil ?\s "…"))
              plan "  ")
             "\n")
     'face '(:inherit (shadow bold)))))

(defun my--symbols-arrange-body ()
  "Render result rows with persistent group context and a stable viewport.
Group titles occupy display rows only; they never enter the candidate list."
  (let* ((candidates (vconcat vertico--candidates))
         (total (length candidates))
         (budget (max 1 vertico-count))
         (group (and vertico-group-format (vertico--metadata-get 'group-function)))
         (titles (make-hash-table :test #'eql))
         (selected (max 0 (min vertico--index (1- total))))
         (start (max 0 (min (or my--symbols-opening-offset 0) (max 0 (1- total)))))
         (placement my--symbols-placement))
    (cl-labels
        ((title (i)
           (or (gethash i titles)
               (let ((value (and group (funcall group (aref candidates i) nil))))
                 (puthash i (or value :none) titles))))
         (rows (from to)
           (let ((count 0) previous)
             (cl-loop for i from from to to while (<= count budget) do
                      (let ((name (title i)))
                        (unless (or (eq name :none) (equal name previous)) (cl-incf count))
                        (setq previous name)
                        (cl-incf count)))
             count)))
      (when (> total 0)
        (pcase placement
          ('top (setq start selected))
          ('center
           (setq start selected)
           (while (and (> start 0) (<= (rows (1- start) selected) (max 1 (/ budget 2))))
             (cl-decf start))
           ;; Backfill near the end instead of leaving a half-empty viewport.
           (while (and (> start 0) (<= (rows (1- start) (1- total)) budget))
             (cl-decf start))))
        (setq start (min start selected))
        ;; Natural Up/Down navigation moves only enough to reveal selection.
        (while (and (< start selected) (> (rows start selected) budget))
          (cl-incf start))
        (setq my--symbols-opening-offset start vertico--scroll start
              my--symbols-placement nil)
        (let ((index start) (used 0) previous raw lines)
          (while (and (< index total)
                      (<= (+ used 1 (if (and (not (eq (title index) :none))
                                            (not (equal (title index) previous))) 1 0)) budget))
            (let ((name (title index)))
              (unless (or (eq name :none) (equal name previous))
                (push (vertico--format-group-title name (aref candidates index)) lines)
                (cl-incf used))
              (setq previous name)
              (push (aref candidates index) raw)
              (push index lines)
              (cl-incf used)
              (cl-incf index)))
          (let ((affixed (vertico--affixate (mapcar vertico--hilit (nreverse raw)))))
            (mapcar
             (lambda (line)
               (if (stringp line) line
                 (pcase-let* ((`(,candidate ,prefix ,suffix) (pop affixed))
                              (candidate (if group (funcall group candidate 'transform) candidate)))
                   (when (string-search "\n" candidate)
                     (setq candidate (vertico--truncate-multiline candidate (- (vertico--window-width) 4))))
                   (vertico--format-candidate candidate prefix suffix line start))))
             (nreverse lines))))))))

(defun my--symbols-arrange-with-header (original &rest args)
  "Add a fixed column header only to this picker's Vertico display."
  (if (and my--symbols-view (plist-get my--symbols-view :header) (> vertico-count 1))
      (let ((header (my--symbols-column-header))
            ;; Reserve a row within the existing height, rather than resize it.
            (vertico-count (1- vertico-count)))
        (cons header (if (plist-get my--symbols-view :order)
                         (my--symbols-arrange-body)
                       (apply original args))))
    (apply original args)))

(with-eval-after-load 'vertico
  (advice-add 'vertico--arrange-candidates :around #'my--symbols-arrange-with-header))

(defun my--symbols-relative-location (candidate root)
  "Return CANDIDATE's file:line relative to ROOT, preserving translated lines."
  (let* ((symbol (get-text-property 0 'consult--candidate candidate))
         (name (lsp-get symbol :name))
         (location (substring-no-properties candidate (+ (length name) 3))))
    (if (not root) location
      (condition-case nil
          (let* ((file (lsp--uri-to-path (my--symbols-file candidate)))
                 (line (and (string-match ":[0-9]+\\'" location)
                            (match-string 0 location))))
            (if (and file line)
                (concat (file-relative-name file root) line)
              location))
        (error location)))))

(defun my--symbols-display-cell (text width &optional face display)
  "Keep full TEXT searchable but display it in WIDTH columns with FACE.
Optional DISPLAY replaces the visible text before truncation and padding."
  (let* ((raw (copy-sequence text))
         (shown (if (zerop width) ""
                  (truncate-string-to-width (or display text) width nil ?\s "…"))))
    (when face (add-face-text-property 0 (length raw) face nil raw))
    (if (equal raw "") (propertize shown 'face face)
      (put-text-property 0 (length raw) 'display shown raw)
      raw)))

(defun my--symbols-path-tail (path width)
  "Shorten PATH from the left to WIDTH columns, retaining file and line."
  (if (<= (string-width path) width) path
    (concat "…" (truncate-string-to-width path (string-width path)
                                         (max 0 (- (string-width path) (1- width)))))))

(defun my--project-symbols-annotate-builder (&optional view)
  "Show aligned glyph, symbol, parent, project-relative path and type columns."
  (let* (;; Build the small icon table once per picker, not once per candidate.
         (icons (when (require 'nerd-icons nil t)
                  (mapcar
                   (lambda (spec)
                     (cons (car spec)
                           (nerd-icons-codicon (concat "nf-cod-" (cadr spec))
                                               :face (caddr spec))))
                   my-project-symbols-icon-specs)))
         (root-icon (if icons
                        (concat (nerd-icons-codicon "nf-cod-root_folder" :face 'shadow) " ")
                      "./")))
    (lambda (candidate)
      (let* ((symbol (get-text-property 0 'consult--candidate candidate))
             (name (lsp-get symbol :name))
             (parent (or (get-text-property 0 'consult--container-name candidate) ""))
             (kind (or (alist-get (lsp-get symbol :kind) lsp-symbol-kinds) "Other"))
             (plan (my--symbols-layout-plan (window-body-width (minibuffer-window)) view))
             (glyph-width (alist-get 'glyph plan 0))
             (name-width (alist-get 'symbol plan))
             (parent-width (alist-get 'parent plan 0))
             (path-width (alist-get 'path plan 0))
             (type-width (alist-get 'type plan 0))
             (tree (if (eq (plist-get view :order) 'source)
                       (if (plist-get view :tree-guides)
                           (or (gethash candidate (plist-get view :tree-prefixes)) "")
                         (make-string (* 2 (or (lsp-get symbol :my-depth) 0)) ?\s))
                     ""))
             (tree (substring tree (max 0 (- (length tree) (1- name-width)))))
             (indent (string-width tree))
             (shown-name (truncate-string-to-width name (- name-width indent) nil nil "…"))
             (location (my--symbols-relative-location candidate (plist-get view :root)))
             (shown-path (concat root-icon
                                 (my--symbols-path-tail location (max 1 (- path-width (string-width root-icon))))))
             (text (copy-sequence candidate)))
        ;; Only the display copy is shortened. Full name text and lookup identity
        ;; remain intact, while suffix cells retain complete annotation searches.
        (put-text-property (length name) (length text) 'display "" text)
        (unless (equal shown-name name)
          (put-text-property (1- (length shown-name)) (length name) 'display "…" text))
        (list text
              (concat (my--symbols-origin-prefix view candidate)
                      (when (> glyph-width 0)
                        (concat (truncate-string-to-width (or (alist-get (lsp-get symbol :kind) icons) "")
                                                         glyph-width nil ?\s) "  "))
                      (propertize tree 'face 'shadow))
              (concat (make-string (- name-width indent (string-width shown-name)) ?\s)
                      (when (> parent-width 0) "  ")
                      (my--symbols-display-cell (if (equal parent "") "—" parent)
                                                     parent-width 'completions-annotations)
                      (when (> path-width 0) "  ")
                      (my--symbols-display-cell location path-width 'shadow shown-path)
                      (when (> type-width 0) "  ")
                      (my--symbols-display-cell kind type-width 'shadow)))))))

(defun my--project-symbols-collect (root workspaces &optional status)
  "Collect ROOT's document symbols through WORKSPACES, reporting progress.
Unsupported files are skipped. Report failed requests rather than silently
claiming a complete result. C-g interrupts collection and closes temporary docs.
When STATUS is a plist with :failures, retain per-file errors there for the UI."
  (let* ((default-directory root)
         (files (projectile-current-project-files))
         (cache (make-hash-table :test #'equal))
         (progress (make-progress-reporter "Collecting project symbols with LSP..." 0 (length files)))
         (count 0) (queried 0) failures candidates)
    (unwind-protect
        (dolist (relative files)
          (let ((file (expand-file-name relative root)))
            (unless (my--project-symbols-excluded-p file root cache)
              (when-let ((context (my--project-symbols-file-context file workspaces)))
                (pcase-let ((`(,workspace ,language ,existing) context))
                  (condition-case error-data
                      (let* ((response (my--project-symbols-document file workspace language existing))
                             (symbols (my--project-symbols-normalize response (lsp--path-to-uri file))))
                        (cl-incf queried)
                        (dolist (symbol symbols)
                          (push (my--project-symbols-candidate workspace symbol)
                                candidates)))
                    (error (push (format "%s: %s" relative (error-message-string error-data)) failures)))))))
          (progress-reporter-update progress (cl-incf count)))
      (progress-reporter-done progress))
    (setq failures (nreverse failures))
    (when status (setf (plist-get status :failures) failures))
    (when failures
      (display-warning 'my-project-symbols
                       (format "%d files failed; results are incomplete.\n%s"
                               (length failures) (string-join failures "\n"))))
    (message "Collected %d symbols from %d project files" (length candidates) queried)
    (nreverse candidates)))

(defun my--symbols-read (candidates prompt &optional scope root failures)
  "Browse CANDIDATES with PROMPT and buffer/project SCOPE's presentation.
ROOT overrides the project base used for displayed relative paths."
  (let* ((interface (my--project-symbols-interface candidates scope))
         (view (plist-get interface :view))
         (origin (when buffer-file-name
                    (let ((position (lsp--cur-position)))
                      (my--symbols-enclosing
                       candidates (lsp--path-to-uri buffer-file-name)
                       (my--project-symbols-object
                        :line (plist-get position :line)
                        :character (plist-get position :character))))))
         (initial origin))
    (setf (plist-get view :root)
          (or root (and (featurep 'projectile) (ignore-errors (projectile-project-root)))
              (and (bound-and-true-p lsp--buffer-workspaces)
                   (seq-some (lambda (workspace) (lsp--workspace-root workspace))
                             lsp--buffer-workspaces))
              (and buffer-file-name (file-name-directory buffer-file-name)) default-directory)
          (plist-get view :failures) failures
          (plist-get view :origin-candidate) origin
          (plist-get view :source-opened) (eq (plist-get view :order) 'source))
    (unwind-protect
        (minibuffer-with-setup-hook (plist-get interface :setup)
          ;; Wait for Vertico's setup before selecting a candidate. The query
          ;; stays empty and the complete list stays available in either order.
          (minibuffer-with-setup-hook
              (:append (lambda ()
                         (my--symbols-select-initial initial)
                         (unless (plist-get view :source-opened)
                           (vertico--update)
                           (setf (plist-get view :opening-selection)
                                 (and (>= vertico--index 0)
                                      (nth vertico--index vertico--candidates))))))
            (consult--read
             candidates :prompt prompt :require-match t
             :keymap (plist-get interface :keymap)
             :category 'consult-lsp-symbols :sort nil
             :annotate (my--project-symbols-annotate-builder view)
             :lookup #'consult--lookup-candidate
             :group (plist-get interface :group)
             :narrow (plist-get interface :narrow)
             :state (my--symbols-state view))))
      (my--symbols-clear-scope view t)
      (my--symbols-restore-cursor-lines view)
      (my--symbols-close-panel view)
      (when-let ((overlay (plist-get view :order-overlay)))
        (delete-overlay overlay)))))

(defun my/buffer-symbols ()
  "Browse the current file's LSP symbols, including unsaved edits.
Use the same layout, kind filters, counts and previews as `my/project-symbols'.
Toggle Kind/Source presentation with C-c C-s; see
`my-buffer-symbols-default-order' and `my-symbols-remember-order'.
C-c C-d shows full details, C-c C-h help, C-c C-w collection errors, and
C-c C-t toggles Source tree guides. C-c C-l toggles Full / Compact columns.
C-c C-r toggles the full-range preview highlight; see `my-symbols-scope-highlight'.
C-c C-o toggles the original-position marker; see `my-symbols-origin-marker'.
Full is the default; see `my-symbols-default-layout',
`my-symbols-visible-columns' and `my-symbols-column-widths'.
Panels never change the query.
Only the current buffer's active document-symbol provider is queried; no
Projectile project is required. Local variables follow the server's settings."
  (interactive)
  (require 'consult-lsp)
  (consult--forbid-minibuffer)
  (unless buffer-file-name
    (user-error "This buffer is not visiting a file"))
  (let ((workspace
         (seq-find (lambda (workspace)
                     (and (eq (lsp--workspace-status workspace) 'initialized)
                          (lsp--workspace-method-supported?
                           nil "textDocument/documentSymbol" :documentSymbolProvider workspace)))
                   lsp--buffer-workspaces)))
    (unless workspace
      (user-error "Start a language server with document-symbol support in this buffer first"))
    (let* ((response (my--project-symbols-document
                      buffer-file-name workspace (lsp-buffer-language) (current-buffer)))
           (symbols (my--project-symbols-normalize response (lsp--path-to-uri buffer-file-name)))
           (candidates (mapcar (apply-partially #'my--project-symbols-candidate workspace) symbols)))
      (unless candidates
        (user-error "No symbols returned for the current buffer"))
      (my--symbols-read candidates (format "Buffer symbols (%s): " (buffer-name)) 'buffer))))

(defun my/project-symbols ()
  "Browse project definitions from active language servers.
No search query is required. Ask LSP for document symbols in each supported
project source file; never parse source definitions in this configuration.
Project/environment exclusions apply; servers for other languages must already
be active in the project. Ruff is not used, since it has no document symbols.

Collection happens on each invocation and can be interrupted with C-g. Unsaved
edits in existing buffers are included. Unopened files are opened to LSP only
for the request, without visiting buffers or evaluating directory-local code.
After collection, ordinary Orderless filtering (including a trailing ~) works
on the complete list. C-c C-s toggles Kind/Source presentation; see
`my-project-symbols-default-order' and `my-symbols-remember-order'.
TAB and Shift-TAB cycle kind groups, or jump between tree roots in Source.
With the configured Consult narrowing prefix (normally <), a filters
Functions + Methods, ? shows filter help, and doubling the prefix clears the
filter. Group headings and the narrowing menu show totals, or matching/total
counts while searching. RET jumps to a definition; Consult previews are available."
  (interactive)
  (require 'projectile)
  (require 'consult-lsp)
  (consult--forbid-minibuffer)
  (let* ((root (file-name-as-directory
                (or (projectile-project-root) (user-error "Not in a Projectile project"))))
         (workspaces (my--project-symbols-workspaces root)))
    (unless workspaces
      (user-error "Start LSP in a project source buffer first"))
    (let* ((status (list :failures nil))
           (candidates (my--project-symbols-collect root workspaces status)))
      (unless candidates (user-error "No project symbols returned by the active servers"))
      (my--symbols-read candidates "Project symbols: " 'project root (plist-get status :failures)))))
