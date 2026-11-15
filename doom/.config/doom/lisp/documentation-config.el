;;; documentation-config.el --- Expand repeated documentation lookups -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'seq)
(require 'color)
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
(defvar-local my-documentation-source-page nil
  "Source URI and position encoding of a read-only documentation source page.
The page is a copy, never the actual file-visiting buffer.")

(defvar-local my-documentation-header-face-cookie nil
  "Buffer-local face adjustment for the fullscreen documentation header.")
(defvar-local my-documentation-header-solaire-cookie nil
  "Adjustment for Solaire's higher-priority header face, when present.")
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

(defun my--documentation-style-header ()
  "Give this header a contrasting theme background and bottom divider."
  (when my-documentation-header-face-cookie
    (face-remap-remove-relative my-documentation-header-face-cookie)
    (setq my-documentation-header-face-cookie nil))
  (when my-documentation-header-solaire-cookie
    (face-remap-remove-relative my-documentation-header-solaire-cookie)
    (setq my-documentation-header-solaire-cookie nil))
  (when header-line-format
    (let* ((foreground (face-foreground 'default nil t))
           (background (face-background 'default nil t))
           (accent (or (face-foreground 'font-lock-keyword-face nil t) foreground))
           (fg (or (color-name-to-rgb accent) (color-name-to-rgb foreground)))
           (bg (color-name-to-rgb background)))
      (when (and fg bg)
        (let ((style (list :foreground foreground
                           :background (apply #'color-rgb-to-hex
                                              (cl-mapcar (lambda (b f) (+ (* b 0.65) (* f 0.35))) bg fg))
                           :underline (list :color (face-foreground 'shadow nil t) :position t)
                           :extend t :weight 'normal :box nil)))
          (setq my-documentation-header-face-cookie
                (face-remap-add-relative 'header-line style))
          ;; Named Solaire remaps take priority over anonymous face attributes.
          ;; Remap that face locally too, without changing other buffers.
          (when (facep 'solaire-header-line-face)
            (setq my-documentation-header-solaire-cookie
                  (face-remap-add-relative 'solaire-header-line-face style))))))))

(defun my--documentation-theme-header-h ()
  "Refresh visible documentation header colors after a theme change."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when my-documentation-header-face-cookie
        (my--documentation-style-header))
      (when my-documentation-code-background-cookies
        (my--documentation-style-code-backgrounds)))))

(add-hook 'doom-load-theme-hook #'my--documentation-theme-header-h)

(defun my--documentation-header-label ()
  "Describe this documentation page and its originating language server."
  (let* ((context my-documentation-lsp-context)
         (source (plist-get context :source))
         (servers (when (and (buffer-live-p source) (fboundp 'lsp-workspaces))
                    (with-current-buffer source
                      (mapcar (lambda (workspace)
                                (symbol-name (lsp--client-server-id (lsp--workspace-client workspace))))
                              (lsp-workspaces)))))
         (topic (plist-get context :symbol))
         (line (plist-get (plist-get (plist-get context :params) :position) :line)))
    (concat
     (if my-documentation-source-page
         (format "Source: %s%s" (plist-get my-documentation-source-page :path)
                 (if line (format ":%d" (1+ line)) ""))
       (concat "Documentation" (if topic (concat ": " topic) "")))
     (when servers (concat " · " (string-join (delete-dups servers) ", "))))))

(defun my--documentation-update-header ()
  "Show a window-wide header only in the expanded documentation view."
  (let ((state (frame-parameter nil 'my-documentation)))
    ;; Olivetti's patterned fringes and the frame edges use the normal theme
    ;; background. Solaire's alternate help background would leave colored strips.
    (when (and (plist-get state :expanded)
               (eq (plist-get state :buffer) (current-buffer))
               (bound-and-true-p solaire-mode))
      (solaire-mode -1))
    (setq-local header-line-format
                (when (and (plist-get state :expanded)
                           (eq (plist-get state :buffer) (current-buffer)))
                  ;; A native header spans the window, including Olivetti margins.
                  ;; Use its face for the whole row, rather than a boxed key face.
                  (list
                   (propertize
                    (concat " " (my--documentation-header-label) " ")
                    'face 'header-line)
                   (propertize " " 'display '(space :align-to right)
                               'face 'header-line)))))
  (my--documentation-style-header)
  (my--documentation-style-code-backgrounds))

(defun my--documentation-same-page-p (left right)
  "Return non-nil if replay items LEFT and RIGHT represent the same page.
Hover refreshes may have new markers or cursor offsets within the same symbol.
Source previews additionally distinguish definition positions in the same file."
  (and (memq (car left) '(my--documentation-replay-lsp my--documentation-replay-source))
       (eq (car left) (car right))
       (equal (cadr left) (cadr right))
       (eq (plist-get (nth 2 left) :source) (plist-get (nth 2 right) :source))
       (equal (nth 3 left) (nth 3 right))
       (or (eq (car left) 'my--documentation-replay-lsp)
           (equal (nth 4 left) (nth 4 right)))))

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
          (setq-local my-documentation-lsp-context context
                      my-documentation-source-page nil)
          (my--documentation-update-header)
          ;; lsp-help-mode resets minor modes on each render. Preserve an
          ;; already centered view without relying on deferred layout hooks.
          (when (and centered (not olivetti-mode)) (olivetti-mode 1))
          (my--documentation-mode 1))))))

(defun my--documentation-symbol-at-point ()
  "Return the help identifier at point, excluding prose punctuation."
  (save-excursion
    (skip-chars-backward "[:alnum:]_$")
    (let ((start (point)))
      (skip-chars-forward "[:alnum:]_$")
      (unless (= start (point))
        (buffer-substring-no-properties start (point))))))

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

(defun my--documentation-signature-positions (context name)
  "Find NAME within server-provided definition ranges for CONTEXT.
These are candidate source positions, not inferred types: the server must
resolve each candidate. No language-specific parser or LSP process is added."
  (let* ((definitions (my--documentation-locations
                       (my--documentation-lsp-request
                        context "textDocument/definition" (plist-get context :params))))
         candidates)
    (dolist (definition (seq-take definitions 4))
      (let* ((params (my--documentation-location-params definition))
             (uri (my--documentation-field (plist-get params :textDocument) :uri))
             (path (lsp--uri-to-path uri))
             (range (or (my--documentation-field definition :targetRange)
                        (my--documentation-field definition :range))))
        ;; Never open a new remote connection merely to inspect documentation.
        (when (and (string-prefix-p "file:" uri)
                   (not (file-remote-p path)) (file-readable-p path))
          (with-temp-buffer
            (insert-file-contents path)
            (let* ((start (lsp--position-to-point (my--documentation-field range :start)))
                   (end (lsp--position-to-point (my--documentation-field range :end)))
                   (case-fold-search nil))
              (goto-char start)
              (while (and (< (length candidates) 16)
                          (re-search-forward (concat "\\_<" (regexp-quote name) "\\_>") end t))
                (let ((finish (match-end 0)))
                  (goto-char (match-beginning 0))
                  (push (list :textDocument (list :uri uri)
                              :position (lsp--cur-position)) candidates)
                  (goto-char finish))))))))
    (nreverse candidates)))

(defun my--documentation-resolve-symbol (context name)
  "Resolve NAME through CONTEXT's language server; return a source location.
Try the original symbol and names in its server-provided definition range,
then exact workspace-symbol results. Server coverage determines availability."
  (let* ((marker (plist-get context :marker))
         (origin (plist-get context :params))
         (same (and (markerp marker) (marker-buffer marker)
                    (with-current-buffer (marker-buffer marker)
                      (save-excursion
                        (goto-char marker) (equal name (thing-at-point 'symbol t))))))
         (candidates (if same (list origin)
                       (my--documentation-signature-positions context name)))
         locations)
    (while (and candidates (not locations))
      (setq locations (my--documentation-locations
                       (my--documentation-lsp-request
                        context "textDocument/definition" (pop candidates)))))
    (unless locations
      (let ((symbols (my--documentation-lsp-request
                      context "workspace/symbol" (list :query name))))
        (dolist (symbol (append symbols nil))
          (when (equal (my--documentation-field symbol :name) name)
            (when-let* ((location (my--documentation-field symbol :location))
                        (range (my--documentation-field location :range)))
              (push location locations))))))
    (unless locations
      (user-error "The language server cannot resolve %s from this documentation" name))
    (if (= (length locations) 1) (car locations)
      (let* ((choices (cl-loop for location in locations for index from 1
                              collect (cons (format "%d: %s" index
                                                    (lsp--location-uri location)) location)))
             (choice (completing-read "Definition: " choices nil t)))
        (cdr (assoc choice choices))))))

(defun my--documentation-source-params ()
  "Return the actual LSP source position represented by the current source page."
  (list :textDocument (list :uri (plist-get my-documentation-source-page :uri))
        :position (lsp--cur-position)))

(defun my--documentation-replay-source (contents context page position)
  "Show cached source CONTENTS at POSITION with CONTEXT and PAGE in Help.
No file buffer is made read-only. Reuse the documentation window and its
layout, and register the source page in the same history as hover pages."
  (my--documentation-record-page
   (list #'my--documentation-replay-source contents context page position))
  (with-current-buffer "*lsp-help*"
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert contents))
    (setq-local my-documentation-lsp-context context
                my-documentation-source-page page
                lsp--position-column-function (plist-get page :column-function)
                lsp--move-to-column-function (plist-get page :move-function))
    (my--documentation-update-header)
    (read-only-mode 1)
    (my--documentation-mode 1)
    (goto-char (min (point-max) position))
    (when-let ((window (get-buffer-window (current-buffer))))
      (set-window-point window (point))
      (set-window-start window (line-beginning-position)))))

(defun my--documentation-show-source (context location)
  "Display LOCATION as an isolated, syntax-colored source page in Help.
Prefer unsaved source text if a file buffer already exists. Otherwise read
without visiting the file or starting another LSP server."
  (let* ((source (plist-get context :source))
         (uri (lsp--location-uri location))
         (path (with-current-buffer source (lsp--uri-to-path uri)))
         (visiting (get-file-buffer path))
         (mode (buffer-local-value 'major-mode source))
         (column (buffer-local-value 'lsp--position-column-function source))
         (move (buffer-local-value 'lsp--move-to-column-function source))
         (page (list :uri uri :path path :column-function column :move-function move))
         (params (my--documentation-location-params location))
         (next-context (list :source source :params params))
         contents position)
    (with-temp-buffer
      (if visiting
          (insert (with-current-buffer visiting
                    (save-restriction
                      (widen) (buffer-substring-no-properties (point-min) (point-max)))))
        (insert-file-contents path))
      ;; Preserve every character, so source positions remain valid. Delayed
      ;; hooks allow syntax colors without file hooks or language-server startup.
      (condition-case nil
          (progn (delay-mode-hooks (funcall mode)) (font-lock-ensure))
        (error nil))
      (setq-local lsp--move-to-column-function move)
      (setq position (lsp--position-to-point (plist-get params :position))
            contents (buffer-string)))
    (my--documentation-replay-source contents next-context page position)))

(defun my--documentation-lsp-definition ()
  "Show a definition inside documentation, leaving actual source buffers untouched."
  (interactive)
  (unless my-documentation-lsp-context (user-error "No originating LSP context"))
  (let* ((context my-documentation-lsp-context)
         (name (or (my--documentation-symbol-at-point) (user-error "No symbol at point")))
         (locations (when my-documentation-source-page
                      (my--documentation-locations
                       (my--documentation-lsp-request
                        context "textDocument/definition" (my--documentation-source-params)))))
         (location
          (if my-documentation-source-page
              (cond ((null locations) (user-error "No definition for %s" name))
                    ((= (length locations) 1) (car locations))
                    (t (let* ((choices
                               (cl-loop for item in locations for index from 1
                                        collect (cons (format "%d: %s" index (lsp--location-uri item)) item)))
                              (choice (completing-read "Definition: " choices nil t)))
                         (cdr (assoc choice choices)))))
            (my--documentation-resolve-symbol context name))))
    (my--documentation-show-source context location)))

(defun my/documentation-open-source ()
  "Leave LSP documentation and visit its real source file for editing.
From a source preview, visit the same file at the preview cursor position.
From a documentation page, ask its original server for the topic's definition.
Restore the pre-documentation layout before visiting the file. Existing file
permissions and read-only settings are respected. Bound to C-c C-o in LSP Help;
gd remains read-only preview navigation, and q still closes documentation."
  (interactive)
  (unless (and (derived-mode-p 'lsp-help-mode) my-documentation-lsp-context)
    (user-error "This command requires an LSP documentation page or source preview"))
  (let* ((context my-documentation-lsp-context)
         (source (plist-get context :source))
         (preview my-documentation-source-page)
         (locations (unless preview
                      (my--documentation-locations
                       (my--documentation-lsp-request
                        context "textDocument/definition" (plist-get context :params)))))
         (location (cond ((= (length locations) 1) (car locations))
                         (locations
                          (let* ((choices (cl-loop for item in locations for i from 1
                                                   collect (cons (format "%d: %s" i (lsp--location-uri item)) item)))
                                 (choice (completing-read "Source definition: " choices nil t)))
                            (cdr (assoc choice choices))))))
         (params (if preview (my--documentation-source-params)
                   (when location (my--documentation-location-params location))))
         (path (if preview (plist-get preview :path)
                 (when location
                   (with-current-buffer source (lsp--uri-to-path (lsp--location-uri location))))))
         (move (if preview (plist-get preview :move-function)
                 (when (buffer-live-p source)
                   (buffer-local-value 'lsp--move-to-column-function source)))))
    (unless path (user-error "The language server has no source definition for this page"))
    ;; Open first so a missing/unreadable file leaves the documentation intact.
    (let* ((target (find-file-noselect path))
           (position (with-current-buffer target
                       (save-restriction
                         (widen)
                         (let ((lsp--move-to-column-function move))
                           (lsp--position-to-point (plist-get params :position)))))))
      (my/documentation-quit)
      ;; Record the editing location, rather than the temporary Help buffer.
      (when (fboundp 'better-jumper-set-jump) (better-jumper-set-jump))
      (when (fboundp 'xref-push-marker-stack) (xref-push-marker-stack))
      (switch-to-buffer target)
      (widen)
      (goto-char position))))

(defun my--documentation-help-at-point (&optional arg)
  "Look up the help symbol through LSP, retaining repeated-K expansion."
  (interactive "P")
  (let ((state (frame-parameter nil 'my-documentation)))
    (if (or arg (not (derived-mode-p 'lsp-help-mode))
            (not my-documentation-lsp-context)
            (and (eq last-command 'my/documentation)
                 (not (plist-get state :expanded))
                 (<= (- (float-time) (or (plist-get state :time) 0))
                     my-documentation-repeat-delay)))
        (my/documentation arg)
      (let* ((context my-documentation-lsp-context)
             (name (or (my--documentation-symbol-at-point) (user-error "No symbol at point")))
             (params (if my-documentation-source-page
                         (my--documentation-source-params)
                       (my--documentation-location-params
                        (my--documentation-resolve-symbol context name))))
             (hover (my--documentation-lsp-request context "textDocument/hover" params)))
        (unless (my--documentation-field hover :contents)
          (user-error "The language server has no documentation for %s" name))
        (let ((my--documentation-source-mode
               (buffer-local-value 'major-mode (plist-get context :source)))
              (my--documentation-render-context
               (list :source (plist-get context :source) :symbol name :params params)))
          (lsp--display-contents (my--documentation-field hover :contents)))
        (with-current-buffer "*lsp-help*"
          (setq-local my-documentation-lsp-context
                      (list :source (plist-get context :source) :symbol name :params params))
          (my--documentation-mode 1))))))

(defun my--documentation-render-markdown-a (original &rest args)
  "Render documentation with ORIGINAL and ARGS using the source language.
Explicitly labeled code blocks retain their own language. Unlabeled blocks
use the source mode, rather than the help buffer's mode. Prose remains Markdown."
  (let ((lsp-buffer-major-mode (or my--documentation-source-mode lsp-buffer-major-mode)))
    (apply original args)))

(defun my--documentation-library-view-a (original &rest args)
  "Keep library source navigation from automatically enabling View mode.
Preserve explicitly enabled View mode and existing read-only state.
Read-only source previews in Help use a separate buffer and are unaffected."
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
  (define-key lsp-help-mode-map (kbd "K") #'my--documentation-help-at-point)
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
    (define-key map (kbd "K") #'my--documentation-help-at-point)
    (define-key map (kbd "q") #'my/documentation-quit)
    (define-key map [remap quit-window] #'my/documentation-quit)
    map))

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
          (when my-documentation-header-face-cookie
            (face-remap-remove-relative my-documentation-header-face-cookie)
            (setq my-documentation-header-face-cookie nil))
          (when my-documentation-header-solaire-cookie
            (face-remap-remove-relative my-documentation-header-solaire-cookie)
            (setq my-documentation-header-solaire-cookie nil)))))
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
      (my--documentation-update-header)
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

A prefix argument always performs a fresh lookup, preserving Doom's backend
selection. In LSP help, K looks up the identifier using the original server;
gd shows an isolated, read-only source preview in the same documentation view,
without visiting or changing the actual source buffer. RET follows links.
C-o or < goes back through native
Help history; C-i or > goes forward. Nested lookups and history retain the current
popup or centered view. Other delayed invocations from the result return to
the original source window. External browsers and asynchronous results that do
not display a documentation window during the lookup are not expanded."
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
          (my--documentation-update-header))))
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
  ;; Help navigation has its own history; never enter the editing jumplist.
  (evil-add-command-properties #'my--documentation-lsp-definition :jump nil)
  (define-key evil-normal-state-map (kbd "K") #'my/documentation)
  (define-key evil-visual-state-map (kbd "K") #'my/documentation)
  (evil-define-minor-mode-key '(normal motion visual) 'my--documentation-mode
    (kbd "K") #'my--documentation-help-at-point
    (kbd "q") #'my/documentation-quit)
  ;; Centered help uses motion state; Doom binds buffer zoom only in normal.
  (evil-define-minor-mode-key 'motion 'my--documentation-mode
    (kbd "C-=") #'text-scale-increase
    (kbd "C--") #'text-scale-decrease)
  (with-eval-after-load 'lsp-mode
    (evil-define-key '(normal motion) lsp-help-mode-map
      (kbd "K") #'my--documentation-help-at-point
      (kbd "g d") #'my--documentation-lsp-definition
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
