;;; documentation-config.el --- Expand repeated documentation lookups -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'seq)
(require 'face-remap)
(defvar my-olivetti-inhibit-layout)
(defvar olivetti-mode)

(defvar my--documentation-source-mode nil
  "Source language mode while a synchronous documentation lookup renders.")
(defvar lsp-buffer-major-mode)
(defvar-local my-documentation-lsp-context nil
  "Originating LSP buffer and source position for this documentation.")
(defvar my--documentation-render-context nil
  "LSP source context being rendered or restored from Help history.")
(defvar my-documentation-last-buffer nil
  "Most recent documentation buffer opened by the custom lookup commands.")
(defvar-local my-documentation-code-background-cookies nil
  "Local Markdown face adjustments matching the documentation background.")

(defun my--documentation-style-code-backgrounds ()
  "Match rendered code backgrounds to this documentation buffer's surface.
Only background attributes are remapped; retain all syntax foreground colors."
  (mapc #'face-remap-remove-relative my-documentation-code-background-cookies)
  (setq my-documentation-code-background-cookies nil)
  (let ((background (face-background
                     (if (and (bound-and-true-p solaire-mode)
                              (facep 'solaire-default-face))
                         'solaire-default-face 'default) nil t)))
    (when background
      (dolist (face '(markdown-code-face markdown-pre-face markdown-inline-code-face))
        (when (facep face)
          (push (face-remap-add-relative face :background background)
                my-documentation-code-background-cookies))))))

(defun my--documentation-theme-h ()
  "Refresh documentation code surfaces after a theme change."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when my-documentation-code-background-cookies
        (my--documentation-style-code-backgrounds)))))

(add-hook 'doom-load-theme-hook #'my--documentation-theme-h)

(defun my--documentation-page-label (&optional _compact)
  "Describe this documentation page and its originating language server."
  (let* ((context my-documentation-lsp-context)
         (source (plist-get context :source))
         (servers (when (and (buffer-live-p source) (fboundp 'lsp-workspaces))
                    (with-current-buffer source
                      (mapcar (lambda (workspace)
                                (symbol-name (lsp--client-server-id (lsp--workspace-client workspace))))
                              (lsp-workspaces)))))
         (topic (plist-get context :symbol)))
    (concat "Documentation" (if topic (concat ": " topic) "")
            (when servers (concat " · " (string-join (delete-dups servers) ", "))))))

(defun my--documentation-mode-line-icon ()
  "Return a theme-accented book icon, or a portable text indicator."
  (if (and (display-graphic-p) (fboundp 'nerd-icons-octicon))
      (nerd-icons-octicon "nf-oct-book" :face 'mode-line-emphasis)
    (propertize "[D]" 'face 'mode-line-emphasis)))

(defun my--documentation-mode-line-label ()
  "Return an accented page label and book icon, with full details on hover."
  (let ((text (replace-regexp-in-string "%" "%%"
                                       (my--documentation-page-label t) t t)))
    (add-text-properties 0 (length "Documentation")
                         '(face (mode-line-emphasis bold)) text)
    (propertize
     (truncate-string-to-width
      (concat (my--documentation-mode-line-icon) " " text)
      (max 1 (- (window-total-width) 2)) nil nil "…")
     'help-echo (my--documentation-page-label))))

(defun my--documentation-update-presentation ()
  "Identify expanded documentation in its theme-styled bottom mode line."
  (let* ((state (frame-parameter nil 'my-documentation))
         (expanded (and (plist-get state :expanded)
                        (eq (plist-get state :buffer) (current-buffer)))))
    ;; Keep Olivetti fringes and the frame edges on the editor background.
    (when (and expanded (bound-and-true-p solaire-mode))
      (solaire-mode -1))
    (setq-local header-line-format nil)
    (when expanded
      (setq-local mode-line-format
                  '((:eval (when (fboundp 'doom-modeline-segment--bar)
                             (doom-modeline-segment--bar)))
                    " " (:eval (my--documentation-mode-line-label)))))
    (my--documentation-style-code-backgrounds)
    (force-mode-line-update)))

(defun my--documentation-same-page-p (left right)
  "Return non-nil if replay items LEFT and RIGHT represent the same hover page."
  (and (eq (car left) 'my--documentation-replay-lsp)
       (eq (car left) (car right))
       (equal (cadr left) (cadr right))
       (eq (plist-get (nth 2 left) :source) (plist-get (nth 2 right) :source))
       (equal (nth 3 left) (nth 3 right))))

(defun my--documentation-clean-history ()
  "Remove consecutive duplicate pages from native Help history."
  (dolist (variable '(help-xref-stack help-xref-forward-stack))
    (let ((previous help-xref-stack-item) result)
      (dolist (entry (symbol-value variable))
        (unless (my--documentation-same-page-p previous (cdr entry))
          (push entry result)
          (setq previous (cdr entry))))
      (set variable (nreverse result)))))

(defun my--documentation-record-page (item)
  "Register replay ITEM in the documentation buffer's native Help history."
  (with-current-buffer (get-buffer-create "*lsp-help*")
    (unless (derived-mode-p 'lsp-help-mode) (lsp-help-mode))
    (if (my--documentation-same-page-p item help-xref-stack-item)
        ;; A refresh updates source context, but is not a new navigation step
        ;; and must not discard Forward after the user has gone Back.
        (setq help-xref-stack-item item)
      (let ((help-xref-following t)) (help-setup-xref item nil)))
    (my--documentation-clean-history)))

(defun my--documentation-replay-lsp (contents context source-mode)
  "Restore cached CONTENTS, CONTEXT and SOURCE-MODE through native Help history.
Replaying documentation does not make another language-server request."
  (let ((my--documentation-render-context context)
        (my--documentation-source-mode source-mode))
    (lsp--display-contents contents)))

(defun my--documentation-display-lsp-a (original contents)
  "Register CONTENTS in native Help history before ORIGINAL replaces the page."
  (let* ((context (or my--documentation-render-context
                      (and (derived-mode-p 'lsp-help-mode)
                           my-documentation-lsp-context)))
         (source-mode (or my--documentation-source-mode
                          (when (buffer-live-p (plist-get context :source))
                            (buffer-local-value 'major-mode (plist-get context :source)))))
         (centered (when-let ((buffer (get-buffer "*lsp-help*")))
                     (and (boundp 'olivetti-mode)
                          (buffer-local-value 'olivetti-mode buffer))))
         (valid (and context contents (not (equal contents "")))))
    (when valid
      (my--documentation-record-page
       (list #'my--documentation-replay-lsp contents context source-mode)))
    (prog1 (funcall original contents)
      (when valid
        (with-current-buffer "*lsp-help*"
          (setq my-documentation-last-buffer (current-buffer))
          (setq-local my-documentation-lsp-context context)
          (my--documentation-update-presentation)
          ;; lsp-help-mode resets minor modes on each render. Preserve an
          ;; already centered view without relying on deferred layout hooks.
          (when (and centered (not olivetti-mode)) (olivetti-mode 1))
          (my--documentation-mode 1))))))

(defun my--documentation-field (object key)
  "Read protocol KEY from either a plist or hash-table OBJECT."
  (if (hash-table-p object)
      (gethash (substring (symbol-name key) 1) object)
    (plist-get object key)))

(defun my--documentation-link-action (button)
  "Follow BUTTON using lsp-mode's document-link handler."
  (lsp--document-link-handle-target (button-get button 'my-documentation-url)))

(defun my--documentation-fix-links-h (&rest _)
  "Restore buttons on rendered Markdown links, including code-styled links.
The installed lsp-mode only recognizes a single face, but Markdown can assign
a list of faces to a link such as [`ThreadRng`](URL)."
  (save-excursion
    (let ((inhibit-read-only t) (position (point-min)))
      (with-silent-modifications
        (while (< position (point-max))
          (let* ((end (next-single-property-change position 'help-echo nil (point-max)))
                 (url (get-text-property position 'help-echo)))
            (when (and (stringp url)
                       (string-match-p "\\`[[:alpha:]][[:alnum:]+.-]*:" url)
                       (cl-some
                        (lambda (face) (memq face '(markdown-link-face markdown-url-face
                                                   markdown-plain-url-face)))
                        (ensure-list (get-text-property position 'face))))
              (make-text-button position end
                                'action #'my--documentation-link-action
                                'my-documentation-url url 'follow-link t
                                'help-echo url))
            (setq position end)))))))

(defun my--documentation-track-lsp-a (original &rest args)
  "Retain the actual source context when ORIGINAL displays LSP documentation."
  (let* ((context (list :source (current-buffer) :marker (copy-marker (point))
                        :symbol (thing-at-point 'symbol t)
                        :params (lsp--text-document-position-params)))
         (my--documentation-render-context context)
        (my--documentation-source-mode major-mode))
    (apply original args)))

(defun my--documentation-lsp-request (context method params)
  "Ask CONTEXT's existing server for METHOD with PARAMS."
  (let ((source (plist-get context :source)))
    (unless (buffer-live-p source)
      (user-error "The originating source buffer has been closed"))
    (with-current-buffer source
      (unless (bound-and-true-p lsp-mode)
        (user-error "The originating buffer no longer has an active LSP server"))
      (lsp-request method params))))

(defun my--documentation-locations (value)
  "Normalize an LSP location response VALUE to a list."
  (cond ((null value) nil)
        ((or (hash-table-p value) (keywordp (car-safe value))) (list value))
        (t (append value nil))))

(defun my--documentation-location-params (location)
  "Convert LOCATION or LocationLink to source-position request parameters."
  (list :textDocument
        (list :uri (or (my--documentation-field location :uri)
                       (my--documentation-field location :targetUri)))
        :position (my--documentation-field
                   (or (my--documentation-field location :targetSelectionRange)
                       (my--documentation-field location :range)) :start)))

(defun my--documentation-location-key (location)
  "Return LOCATION's navigation destination, ignoring origin/call-site metadata."
  (let* ((params (my--documentation-location-params location))
         (uri (my--documentation-field (plist-get params :textDocument) :uri))
         (position (plist-get params :position))
         (line (my--documentation-field position :line))
         (column (my--documentation-field position :character)))
    (if (and (stringp uri) (integerp line) (integerp column))
        (list uri line column)
      location)))

(defun my--documentation-unique-locations (locations)
  "Keep one entry per definition destination in LOCATIONS, in server order.
LocationLink originSelectionRange describes the use site, not the definition.
Different definitions in the same file must retain separate choices."
  (let ((seen (make-hash-table :test 'equal)) result)
    (seq-doseq (location locations)
      (let ((key (my--documentation-location-key location)))
        (unless (gethash key seen)
          (puthash key t seen)
          (push location result))))
    (nreverse result)))

(defun my--documentation-choose-location (locations name)
  "Choose among server-provided LOCATIONS for NAME without guessing."
  (setq locations (my--documentation-unique-locations locations))
  (cond ((null locations) (user-error "The language server cannot resolve %s from this documentation" name))
        ((= (length locations) 1) (car locations))
        (t (let* ((choices (cl-loop for location in locations for index from 1
                                  collect (cons (format "%d: %s" index (lsp--location-uri location)) location)))
                  (choice (completing-read "Definition: " choices nil t)))
             (cdr (assoc choice choices))))))

(defun my/documentation-open-source ()
  "Leave LSP Help and open the documented topic's actual source.
Ask the originating server at the saved source position, never at text copied
into Help. Restore the editing layout before visiting the definition. Existing
permissions and read-only settings are preserved. Bound to C-c C-o in LSP Help."
  (interactive)
  (unless (and (derived-mode-p 'lsp-help-mode)
               (plist-get my-documentation-lsp-context :params))
    (user-error "This page has no saved LSP source position"))
  (let* ((context my-documentation-lsp-context)
         (source (plist-get context :source))
         (locations (my--documentation-locations
                     (my--documentation-lsp-request
                      context "textDocument/definition" (plist-get context :params))))
         (location (my--documentation-choose-location
                    locations (or (plist-get context :symbol) "source")))
         (params (my--documentation-location-params location))
         (uri (my--documentation-field (plist-get params :textDocument) :uri))
         (path (with-current-buffer source (lsp--uri-to-path uri)))
         (move (buffer-local-value 'lsp--move-to-column-function source)))
    ;; Resolve only existing source. Never create an empty file for virtual URIs.
    (unless (and path (file-readable-p path))
      (user-error "The server did not provide a readable source file"))
    (let* ((target (find-file-noselect path))
           (position (with-current-buffer target
                       (save-restriction
                         (widen)
                         (let ((lsp--move-to-column-function move))
                           (lsp--position-to-point (plist-get params :position)))))))
      (my/documentation-quit)
      (when (fboundp 'better-jumper-set-jump) (better-jumper-set-jump))
      (when (fboundp 'xref-push-marker-stack) (xref-push-marker-stack))
      (switch-to-buffer target)
      (widen)
      (goto-char position))))

(defvar-local my-documentation-code-rendering nil
  "Non-nil only in temporary LSP Markdown rendering buffers.")

(defun my--documentation-code-mode (mode)
  "Choose a parser-backed Python highlighter when available; otherwise use MODE."
  (if (memq mode '(python-mode python-ts-mode))
      (if (and (fboundp 'python-ts-mode) (fboundp 'treesit-ready-p)
               (treesit-ready-p 'python t))
          'python-ts-mode
        'python-mode)
    mode))

(defun my--documentation-fontify-snippet (text mode)
  "Color TEXT with MODE in an isolated buffer without running editing hooks."
  (with-temp-buffer
    (insert text)
    (let ((treesit-font-lock-level (if (eq mode 'python-ts-mode) 4
                                   (bound-and-true-p treesit-font-lock-level))))
      ;; Only mode initialization is delayed; fontification must run outside
      ;; that scope so Tree-sitter can finish its font-lock initialization.
      (delay-mode-hooks (funcall mode))
      (font-lock-ensure))
    (unless (equal text (buffer-substring-no-properties (point-min) (point-max)))
      (error "Example mode changed the snippet text"))
    (buffer-string)))

(defun my--documentation-fontify-code-a (original language start end)
  "Fontify documentation code without editing hooks or another LSP server.
Prefer Python's parser when available, with ordinary syntax coloring as fallback.
Preserve every character, including prompts/output; copy only syntax faces.
Other Markdown buffers retain their ordinary fontification behavior."
  (if (not my-documentation-code-rendering)
      (funcall original language start end)
    (let* ((fallback (if language (markdown-get-lang-mode language)
                       markdown-fontify-code-block-default-mode))
           (preferred (my--documentation-code-mode fallback)))
      (when (fboundp preferred)
        (let* ((text (buffer-substring-no-properties start end))
               (modified (buffer-modified-p))
               (rendered (condition-case error-data
                             (my--documentation-fontify-snippet text preferred)
                           (error (if (eq preferred 'python-ts-mode)
                                      (my--documentation-fontify-snippet text 'python-mode)
                                    (signal (car error-data) (cdr error-data))))))
               (position 0))
          (remove-text-properties start end '(face nil))
          (while (< position (length rendered))
            (let ((next (next-single-property-change position 'face rendered (length rendered)))
                  (face (get-text-property position 'face rendered)))
              (when face (put-text-property (+ start position) (+ start next) 'face face))
              (setq position next)))
          (add-text-properties start end
                               '(font-lock-fontified t fontified t font-lock-multiline t))
          (set-buffer-modified-p modified))))))

(with-eval-after-load 'markdown-mode
  (advice-add 'markdown-fontify-code-block-natively :around
              #'my--documentation-fontify-code-a))

(defun my--documentation-normalize-closing-fences ()
  "Remove ignored trailing whitespace from matching Markdown closing fences.
Some markdown-mode versions require a closing fence to end at its last marker,
while CommonMark permits trailing spaces/tabs. Change only closing markup in
this temporary rendering buffer, preserving code, prose and opening fences.
Respect fence character and length so shorter or nested-looking literal fences
inside a code block are not treated as its closing delimiter."
  (save-excursion
    (goto-char (point-min))
    (let (marker width)
      (while (re-search-forward "^ \\{0,3\\}\\(`\\{3,\\}\\|~\\{3,\\}\\)\\([^\n]*\\)$" nil t)
        (let* ((fence (match-string-no-properties 1))
               (tail (match-string-no-properties 2))
               (character (aref fence 0)))
          (if marker
              (when (and (= marker character) (>= (length fence) width)
                         (string-match-p "\\`[ \t]*\\'" tail))
                (delete-region (match-beginning 2) (match-end 2))
                (setq marker nil width nil))
            ;; Backticks cannot occur in the info string of a backtick opener.
            (unless (and (= character ?`) (string-match-p "`" tail))
              (setq marker character width (length fence)))))))))

(defun my--documentation-render-markdown-a (original &rest args)
  "Render documentation with ORIGINAL and ARGS using the source language.
Explicitly labeled code blocks retain their own language. Unlabeled blocks
use the source mode, rather than the help buffer's mode. Prose remains Markdown."
  (my--documentation-normalize-closing-fences)
  (let ((lsp-buffer-major-mode (or my--documentation-source-mode lsp-buffer-major-mode)))
    (prog1 (apply original args)
      (setq-local my-documentation-code-rendering t))))

(defun my--documentation-library-view-a (original &rest args)
  "Keep library source navigation from automatically enabling View mode.
Preserve explicitly enabled View mode and existing read-only state.
Documentation never copies source into Help."
  (let ((view-was-enabled (bound-and-true-p view-mode))
        (was-read-only buffer-read-only))
    (prog1 (apply original args)
      (when (and (not view-was-enabled) (bound-and-true-p view-mode))
        (view-mode -1)
        (setq buffer-read-only was-read-only)))))

(with-eval-after-load 'lsp-mode
  (advice-add 'lsp--try-open-in-library-workspace :around
              #'my--documentation-library-view-a)
  ;; The renderer is called indirectly by lsp-mode inside a temporary buffer.
  (advice-add 'lsp--render-markdown :around #'my--documentation-render-markdown-a)
  (advice-add 'lsp--fix-markdown-links :after #'my--documentation-fix-links-h)
  (advice-add 'lsp--display-contents :around #'my--documentation-display-lsp-a)
  (advice-add 'lsp-describe-thing-at-point :around #'my--documentation-track-lsp-a)
  (define-key lsp-help-mode-map (kbd "K") #'my/documentation)
  (define-key lsp-help-mode-map (kbd "C-c C-o") #'my/documentation-open-source))

(defcustom my-documentation-repeat-delay 1.0
  "Seconds after a completed lookup during which another K expands its result."
  :type 'number :group 'convenience)

(defun my--documentation-window-p (window)
  "Return non-nil if WINDOW displays documentation supported by this feature."
  (and (window-live-p window)
       (with-current-buffer (window-buffer window)
         (derived-mode-p 'help-mode 'helpful-mode 'Info-mode 'Man-mode
                         'woman-mode 'devdocs-mode 'eww-mode))))

(defvar my--documentation-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "K") #'my/documentation)
    (define-key map (kbd "q") #'my/documentation-quit)
    (define-key map [remap quit-window] #'my/documentation-quit)
    map))

;; Also replace the old resolver binding when reloading this file in Emacs.
(define-key my--documentation-mode-map (kbd "K") #'my/documentation)

(define-minor-mode my--documentation-mode
  "Handle repeated K and q in documentation opened by `my/documentation'."
  :lighter nil :keymap my--documentation-mode-map)

(defun my--documentation-clear (frame)
  "Forget FRAME's last lookup and remove its temporary buffer bindings."
  (let* ((state (frame-parameter frame 'my-documentation))
         (buffer (plist-get state :buffer)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (my--documentation-mode -1)
        (when (plist-get state :expanded)
          (setq-local header-line-format (plist-get state :header-line))
          (when (fboundp 'solaire-mode)
            (solaire-mode (if (plist-get state :solaire) 1 -1)))
          (my--documentation-style-code-backgrounds)
          (setq-local mode-line-format (plist-get state :mode-line)))))
    (set-frame-parameter frame 'my-documentation nil)))

(defun my/documentation-quit ()
  "Close the expanded documentation view and restore the pre-lookup layout.
In an ordinary documentation popup, use `quit-window' as usual."
  (interactive)
  (let* ((frame (selected-frame))
         (state (frame-parameter frame 'my-documentation))
         (buffer (plist-get state :buffer)))
    (if (and (plist-get state :expanded) (eq buffer (current-buffer)))
        (let ((my-olivetti-inhibit-layout t))
          (when (and (fboundp 'olivetti-mode) (buffer-live-p buffer))
            (with-current-buffer buffer
              (olivetti-mode (if (plist-get state :olivetti) 1 -1))))
          (my--documentation-clear frame)
          (set-window-configuration (plist-get state :configuration)))
      (my--documentation-clear frame)
      (quit-window))
    (when (fboundp 'my--olivetti-refresh-h) (my--olivetti-refresh-h))))

(defun my--documentation-expand (frame state)
  "Expand the tracked documentation window in FRAME using STATE."
  (let ((window (plist-get state :window))
        (buffer (plist-get state :buffer))
        (my-olivetti-inhibit-layout t))
    (unless (and (window-live-p window) (eq (window-buffer window) buffer))
      (user-error "The documentation window is no longer available"))
    (setq state (plist-put state :header-line
                           (buffer-local-value 'header-line-format buffer)))
    (setq state (plist-put state :mode-line
                           (buffer-local-value 'mode-line-format buffer)))
    (setq state (plist-put state :solaire
                           (and (boundp 'solaire-mode)
                                (buffer-local-value 'solaire-mode buffer))))
    (setq state (plist-put state :olivetti
                           (and (boundp 'olivetti-mode)
                                (buffer-local-value 'olivetti-mode buffer))))
    (let ((position (window-point window)) (start (window-start window)))
      (select-window window)
      (when (and (fboundp '+popup-window-p) (+popup-window-p window))
        (+popup/raise window))
      ;; Keep the original help buffer, its buttons and its history.
      (delete-other-windows)
      (set-window-dedicated-p (selected-window) nil)
      (set-frame-parameter frame 'my-documentation (plist-put state :expanded t))
      (when (require 'olivetti nil t) (olivetti-mode 1))
      (my--documentation-update-presentation)
      (when (bound-and-true-p evil-local-mode) (evil-motion-state))
      (goto-char position)
      (set-window-start (selected-window) start)))
  (when (fboundp 'my--olivetti-refresh-h) (my--olivetti-refresh-h)))

(defun my/documentation (&optional arg)
  "Look up documentation; repeat K promptly to expand the resulting window.
The first invocation delegates to Doom's `+lookup/documentation'. LSP Markdown
code blocks use syntax colors: labeled blocks use their declared language,
unlabeled blocks use the source buffer's language. Prose keeps its normal
formatting; this does not run another language server for documentation.
A second
consecutive invocation within `my-documentation-repeat-delay' focuses that
lookup's result in a single window, centered with Olivetti. Press q to restore
the window layout from before the lookup. This is a normal Emacs window.

In source, a prefix argument preserves Doom's backend selection. LSP Help is
a reading view: K only expands a prompt repeat of the initial lookup, and gd
performs no lookup. Follow explicit documentation links with RET, or use
C-c C-o to open the documented topic's source. C-o/< and C-i/> navigate cached
Help history. External browsers and asynchronous results not displayed during
the initial lookup are not expanded."
  (interactive "P")
  (let* ((frame (selected-frame))
         (state (frame-parameter frame 'my-documentation))
         (window (plist-get state :window))
         (source (plist-get state :source))
         (buffer (plist-get state :buffer))
         (repeat (and (not arg) (eq last-command 'my/documentation)
                      state (not (plist-get state :expanded))
                      (window-live-p window) (eq (window-buffer window) buffer)
                      (or (eq (selected-window) window)
                          (and (eq (selected-window) source)
                               (eq (current-buffer) (plist-get state :source-buffer))
                               (= (point) (plist-get state :point))))
                      (<= (- (float-time) (plist-get state :time))
                          my-documentation-repeat-delay))))
    (if repeat
        (my--documentation-expand frame state)
      (when (derived-mode-p 'lsp-help-mode)
        (user-error "Documentation is a reading view; follow links or use C-c C-o for source"))
      (when (and state (eq (current-buffer) buffer))
        (if (plist-get state :expanded)
            (my/documentation-quit)
          (when (and (window-live-p source)
                     (buffer-live-p (plist-get state :source-buffer)))
            (select-window source)
            ;; Some backends replace the source window rather than splitting.
            (when (eq (current-buffer) buffer)
              (switch-to-buffer (plist-get state :source-buffer))
              (goto-char (plist-get state :point))))))
      (my--documentation-clear frame)
      (let* ((configuration (current-window-configuration))
             (source (selected-window)) (source-buffer (current-buffer))
             (position (point))
             (before (mapcar (lambda (w)
                               (list w (window-buffer w)
                                     (buffer-chars-modified-tick (window-buffer w))))
                             (window-list frame 'no-minibuf))))
        (let ((current-prefix-arg arg)
              (my--documentation-source-mode major-mode))
          (call-interactively #'+lookup/documentation))
        (let* ((candidates
                (cl-remove-if-not
                 (lambda (w)
                   (let ((old (assq w before)))
                     (and (my--documentation-window-p w)
                          (or (null old)
                              ;; Cached help can select its existing window
                              ;; without changing any documentation text.
                              (and (eq w (selected-window)) (not (eq w source)))
                              (not (eq (window-buffer w) (nth 1 old)))
                              (/= (buffer-chars-modified-tick (window-buffer w))
                                  (nth 2 old))))))
                 (window-list frame 'no-minibuf)))
               (result (if (memq (selected-window) candidates)
                           (selected-window)
                         (and (= (length candidates) 1) (car candidates)))))
          (when result
            (set-frame-parameter
             frame 'my-documentation
             (list :configuration configuration :source source
                   :source-buffer source-buffer :point position :window result
                   :buffer (window-buffer result) :time (float-time)))
            (with-current-buffer (window-buffer result)
              (setq my-documentation-last-buffer (current-buffer))
              (my--documentation-mode 1))))))))

(defun my--documentation-reopen (centered)
  "Reopen the cached documentation, using fullscreen when CENTERED is non-nil."
  (let* ((buffer (if (buffer-live-p my-documentation-last-buffer)
                     my-documentation-last-buffer
                   (get-buffer "*lsp-help*")))
         (frame (selected-frame))
         (state (frame-parameter frame 'my-documentation)))
    (unless (buffer-live-p buffer)
      (user-error "No saved documentation; look up a symbol with K first"))
    ;; Switching out of fullscreen restores its editing layout before reopening.
    (when (and (plist-get state :expanded)
               (or (not centered) (not (eq buffer (plist-get state :buffer)))))
      (when-let ((window (get-buffer-window (plist-get state :buffer) frame)))
        (with-selected-window window (my/documentation-quit)))
      (setq state (frame-parameter frame 'my-documentation)))
    (let ((window (plist-get state :window)))
      (if (and (eq buffer (plist-get state :buffer))
               (window-live-p window) (eq (window-buffer window) buffer))
          (select-window window)
        (my--documentation-clear frame)
        ;; A manually reopened help buffer may occupy the editing window.
        (when (eq (current-buffer) buffer)
          (switch-to-buffer (other-buffer buffer t)))
        (let* ((configuration (current-window-configuration))
               (source (selected-window)) (source-buffer (current-buffer))
               (position (point))
               (saved-point (with-current-buffer buffer (point)))
               (window (if (fboundp '+popup-buffer)
                           (+popup-buffer buffer '((side . bottom) (size . 0.33)
                                                   (select . t) (quit . t) (ttl . nil)))
                         (display-buffer buffer
                                         '(display-buffer-at-bottom (window-height . 0.33))))))
          (unless (window-live-p window) (user-error "Cannot display saved documentation"))
          (select-window window)
          (goto-char saved-point)
          (setq state (list :configuration configuration :source source
                            :source-buffer source-buffer :point position :window window
                            :buffer buffer :time (float-time)))
          (set-frame-parameter frame 'my-documentation state)
          (my--documentation-mode 1)
          (my--documentation-update-presentation))))
    (setq my-documentation-last-buffer buffer)
    (when (and centered (not (plist-get state :expanded)))
      (my--documentation-expand frame state))))

(defun my/documentation-reopen ()
  "Reopen the most recent documentation in a bottom popup.
Keep its cached contents, cursor position and Help history without contacting
the language server. Use `my/documentation-reopen-centered' for fullscreen.
Press q to close the popup. Requires an existing documentation buffer."
  (interactive)
  (my--documentation-reopen nil))

(defun my/documentation-reopen-centered ()
  "Reopen the most recent documentation in a centered fullscreen window.
Keep its cached contents, cursor position and Help history without contacting
the language server. Press q to restore the editing layout. Use
`my/documentation-reopen' for a bottom popup."
  (interactive)
  (my--documentation-reopen t))

(with-eval-after-load 'evil
  (define-key evil-normal-state-map (kbd "K") #'my/documentation)
  (define-key evil-visual-state-map (kbd "K") #'my/documentation)
  (evil-define-minor-mode-key '(normal motion visual) 'my--documentation-mode
    (kbd "K") #'my/documentation
    (kbd "q") #'my/documentation-quit)
  ;; Centered help uses motion state; Doom binds buffer zoom only in normal.
  (evil-define-minor-mode-key 'motion 'my--documentation-mode
    (kbd "C-=") #'text-scale-increase
    (kbd "C--") #'text-scale-decrease)
  (with-eval-after-load 'lsp-mode
    (evil-define-key '(normal motion) lsp-help-mode-map
      (kbd "K") #'my/documentation
      (kbd "g d") #'ignore
      (kbd "C-o") #'help-go-back
      (kbd "C-i") #'help-go-forward
      (kbd "<") #'help-go-back
      (kbd ">") #'help-go-forward
      ;; Doom translates graphical Ctrl-I to this distinct event, preserving Tab.
      (kbd "<C-i>") #'help-go-forward
      ;; GUI Tab is a distinct event; terminals may send C-i for both keys.
      (kbd "<tab>") #'forward-button
      (kbd "<backtab>") #'backward-button
      (kbd "RET") #'push-button)))

(provide 'documentation-config)
;;; documentation-config.el ends here
