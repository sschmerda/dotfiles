;;; signature-config.el --- Automatic LSP argument hints -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'seq)
(require 'color)

(defun my--signature-set-presentation (symbol style)
  "Set SYMBOL to STYLE, replacing any active signature presentation immediately."
  (unless (memq style '(bottom floating compact))
    (user-error "Unknown signature presentation: %s" style))
  (let ((old (and (boundp symbol) (symbol-value symbol)))
        (source (and (boundp 'lsp--signature-last-buffer)
                     lsp--signature-last-buffer)))
    (when (and old (not (eq old style))
               (fboundp 'my--documentation-display-signature))
      ;; Hide with the OLD renderer before changing its dispatch variable.
      (my--documentation-display-signature nil))
    (set-default symbol style)
    (when (featurep 'lsp-mode)
      (setq lsp-signature-render-documentation (eq style 'bottom))
      (when (and (not (eq old style)) (buffer-live-p source))
        (with-current-buffer source
          (when (and (bound-and-true-p lsp-signature-mode)
                     lsp--signature-last)
            (my--documentation-display-signature
             (lsp--signature->message lsp--signature-last))))))))

(defcustom my-documentation-signature-style 'bottom
  "Where automatic LSP signatures are displayed.
Bottom uses the signature/documentation window; compact uses one echo-area
line; floating uses a bordered box near point.
Use `my/signature-presentation' or Customize to switch an active view immediately."
  :type '(choice (const bottom) (const compact) (const floating))
  :set #'my--signature-set-presentation
  :group 'convenience)

(defun my/signature-presentation (style)
  "Switch automatic LSP signatures to STYLE: bottom, floating or compact.
Bottom includes server-provided documentation; floating and compact omit it.
An active signature is redrawn immediately without another server request.
Floating uses a child frame in graphical Emacs and a bottom window in terminals.
The choice lasts for this Emacs session. Use Customize on
`my-documentation-signature-style' to save a persistent preference."
  (interactive
   (list (intern (completing-read "Signature presentation: "
                                 '("bottom" "floating" "compact") nil t nil nil
                                 (symbol-name my-documentation-signature-style)))))
  (my--signature-set-presentation 'my-documentation-signature-style style))

(defface my-documentation-signature-inactive
  '((t (:inherit default)))
  "Slightly subdued signature text outside the active parameter."
  :group 'faces)

(defface my-documentation-signature-return
  '((t (:inherit font-lock-type-face :weight bold)))
  "Theme-aware emphasis for an explicitly identified signature return type."
  :group 'faces)

(defun my--documentation-signature-blend (foreground background amount)
  "Blend FOREGROUND toward BACKGROUND by AMOUNT, when both have RGB values."
  (let ((fg (color-name-to-rgb foreground)) (bg (color-name-to-rgb background)))
    (when (and fg bg)
      (apply #'color-rgb-to-hex
             (append (cl-mapcar (lambda (f b) (+ (* amount f) (* (- 1 amount) b))) fg bg)
                     '(2))))))

(defun my--documentation-signature-fallback-faces ()
  "Provide theme-derived signature defaults without overriding theme/user faces."
  (when (facep 'lsp-signature-highlight-function-argument)
    (let* ((foreground (face-foreground 'default nil t))
           (background (face-background 'default nil t))
           (accent (face-foreground 'font-lock-keyword-face nil t))
           (selection (face-background 'region nil t))
           (selected-bg (or (and selection (not (equal selection background))
                                 (my--documentation-signature-blend selection background 0.40))
                            (my--documentation-signature-blend accent background 0.15)))
           (muted (my--documentation-signature-blend foreground background 0.75))
           (popup (my--documentation-signature-blend foreground background 0.08)))
      (when selected-bg
        (dolist (face '(lsp-signature-highlight-function-argument eldoc-highlight-function-argument))
          (face-spec-set face `((t (:foreground ,accent :background ,selected-bg :weight bold)))
                         'face-defface-spec)))
      (when muted
        (face-spec-set 'my-documentation-signature-inactive `((t (:foreground ,muted)))
                       'face-defface-spec))
      (when popup
        (face-spec-set 'lsp-signature-posframe `((t (:foreground ,foreground :background ,popup)))
                       'face-defface-spec)))))

(defvar-local my-documentation-signature-idle-timer nil)
(defvar-local my-documentation-signature-last-position nil)

(defun my--documentation-signature-insert-p ()
  "Allow automatic signatures in Evil Insert state, or ordinary Emacs editing."
  (and (bound-and-true-p lsp-mode)
       (not (minibufferp))
       (or (not (bound-and-true-p evil-local-mode))
           (eq evil-state 'insert))))

(defun my--documentation-signature-cancel-timer-h ()
  "Cancel this buffer's pending automatic signature activation."
  (when (timerp my-documentation-signature-idle-timer)
    (cancel-timer my-documentation-signature-idle-timer))
  (setq my-documentation-signature-idle-timer nil))

(defun my--documentation-signature-stop-h ()
  "Stop pending and active signatures when leaving Insert state or the buffer."
  (my--documentation-signature-cancel-timer-h)
  (setq my-documentation-signature-last-position nil)
  (when (and (boundp 'lsp--signature-last-buffer)
             (eq lsp--signature-last-buffer (current-buffer)))
    (lsp-signature-stop)))

(defun my--documentation-signature-auto-h ()
  "Request signature help after a short editing pause, even inside existing calls.
Let the server decide whether point is in a call; do not parse language syntax."
  (when (my--documentation-signature-insert-p)
    (let ((position (cons (point) (buffer-chars-modified-tick))))
      (unless (equal position my-documentation-signature-last-position)
        (setq my-documentation-signature-last-position position)
        (my--documentation-signature-cancel-timer-h)
        ;; Once active, lsp-mode already updates signatures after each command.
        (unless (bound-and-true-p lsp-signature-mode)
          (let ((buffer (current-buffer)))
            (setq my-documentation-signature-idle-timer
                  (run-with-idle-timer
                   0.15 nil
                   (lambda ()
                     (when (buffer-live-p buffer)
                       (with-current-buffer buffer
                         (setq my-documentation-signature-idle-timer nil)
                         (when (and (eq buffer (window-buffer (selected-window)))
                                    (my--documentation-signature-insert-p)
                                    (equal position (cons (point) (buffer-chars-modified-tick)))
                                    (not (bound-and-true-p lsp-signature-mode))
                                    (lsp-feature? "textDocument/signatureHelp"))
                           (lsp-signature-activate)
                           (lsp-signature)))))))))))))

(defun my--documentation-signature-enter-h ()
  "Recheck signature help on entering Insert state without requiring movement."
  (setq my-documentation-signature-last-position nil)
  (my--documentation-signature-auto-h))

(defun my--documentation-signature-setup-h ()
  "Install buffer-local signature activation and cleanup for LSP editing."
  (if lsp-mode
      (progn
        (add-hook 'post-command-hook #'my--documentation-signature-auto-h nil t)
        (add-hook 'evil-insert-state-entry-hook #'my--documentation-signature-enter-h nil t)
        (add-hook 'evil-insert-state-exit-hook #'my--documentation-signature-stop-h nil t)
        (add-hook 'kill-buffer-hook #'my--documentation-signature-stop-h nil t))
    (my--documentation-signature-stop-h)
    (remove-hook 'post-command-hook #'my--documentation-signature-auto-h t)
    (remove-hook 'evil-insert-state-entry-hook #'my--documentation-signature-enter-h t)
    (remove-hook 'evil-insert-state-exit-hook #'my--documentation-signature-stop-h t)
    (remove-hook 'kill-buffer-hook #'my--documentation-signature-stop-h t)))

(add-hook 'lsp-mode-hook #'my--documentation-signature-setup-h)

(defun my--documentation-display-signature (signature)
  "Display SIGNATURE using `my-documentation-signature-style'."
  (pcase my-documentation-signature-style
    ('bottom (my--documentation-display-bottom-signature signature))
    ('floating (my--documentation-display-floating-signature signature))
    (_ (unless (active-minibuffer-window)
         (let ((message-log-max nil))
           (if signature
               (message "%s" (truncate-string-to-width
                               (replace-regexp-in-string "[\n\r]+" " " signature)
                               (max 1 (1- (frame-width))) nil nil "…"))
             (message nil)))))))

(defun my--documentation-signature-character-offset (label offset)
  "Translate a validated UTF-16 OFFSET into a character position in LABEL."
  (unless (and (integerp offset) (>= offset 0)) (error "Invalid offset"))
  (let ((index 0) (units 0))
    (while (and (< units offset) (< index (length label)))
      (cl-incf units (if (> (aref label index) #xffff) 2 1))
      (cl-incf index))
    (unless (= units offset) (error "Offset is outside a character boundary"))
    index))

(defun my--signature-parameter-range (label parameter)
  "Return a verified character range for PARAMETER in LABEL, or nil.
LSP offsets are UTF-16 units. String labels must identify exactly one substring."
  (condition-case nil
      (let* ((value (lsp:parameter-information-label parameter))
             (start (if (stringp value)
                        (and (not (string-empty-p value)) (string-match (regexp-quote value) label))
                      (and (sequencep value) (= (length value) 2)
                           (my--documentation-signature-character-offset label (seq-elt value 0)))))
             (end (if (stringp value) (and start (+ start (length value)))
                    (and start (my--documentation-signature-character-offset label (seq-elt value 1))))))
        (when (and start end (< start end) (<= end (length label))
                   (not (and (stringp value) (string-match (regexp-quote value) label (1+ start)))))
          (cons start end)))
    (error nil)))

(defun my--signature-selected-index (reply)
  "Choose a valid signature index from REPLY, retaining valid overload selection."
  (let ((count (length (lsp:signature-help-signatures reply))))
    (cl-loop for index in (list lsp--signature-last-index
                               (lsp:signature-help-active-signature? reply) 0)
             when (and (integerp index) (<= 0 index) (< index count)) return index)))

(defun my--signature-render-doc (documentation)
  "Render server DOCUMENTATION with lsp-mode, falling back to its plain text."
  (let ((rendered (condition-case nil (lsp--render-element documentation) (error nil)))
        (plain (condition-case nil
                   (if (stringp documentation) documentation
                     (lsp:markup-content-value documentation))
                 (error nil))))
    (cond ((and (stringp rendered) (not (string-empty-p rendered))) rendered)
          ((and (stringp plain) (not (string-empty-p plain))) plain))))

(defun my--signature-clear-active-face (label)
  "Copy LABEL without stale active-parameter faces from earlier responses."
  (let ((text (copy-sequence label)) (position 0))
    (while (< position (length text))
      (let* ((next (next-single-property-change position 'face text (length text)))
             (face (get-text-property position 'face text)))
        (cond ((eq face 'lsp-signature-highlight-function-argument)
               (remove-text-properties position next '(face nil) text))
              ((and (listp face) (memq 'lsp-signature-highlight-function-argument face))
               (put-text-property position next 'face
                                  (remq 'lsp-signature-highlight-function-argument (copy-sequence face)) text)))
        (setq position next)))
    text))

(defun my--signature-message (reply)
  "Render only structured signature information supplied in LSP REPLY.
Validate overload and parameter indexes, honor signature-level activeParameter,
convert UTF-16 ranges, and include supplied signature/active-parameter docs.
Missing or malformed ranges leave labels intact without inferred highlighting.
Keep lsp-mode's native request lifecycle and overload navigation."
  (let* ((index (my--signature-selected-index reply))
         (signatures (lsp:signature-help-signatures reply))
         (signature (and index (seq-elt signatures index)))
         (label (and signature (lsp:signature-information-label signature))))
    (setq lsp--signature-last reply lsp--signature-last-index index)
    (when (stringp label)
      (condition-case nil
          (let* ((text (my--signature-clear-active-face label))
                 (parameters (lsp:signature-information-parameters? signature))
                 (active (or (lsp:signature-information-active-parameter? signature)
                             (lsp:signature-help-active-parameter? reply) 0))
                 (parameter (when (and (sequencep parameters) (> (length parameters) 0))
                              (seq-elt parameters (if (and (integerp active) (<= 0 active)
                                                           (< active (length parameters))) active 0))))
                 (range (and parameter (my--signature-parameter-range label parameter)))
                 (prefix (if (> (length signatures) 1)
                             (propertize (format " %d/%d " (1+ index) (length signatures)) 'face 'success) ""))
                 (docs-enabled (and lsp-signature-render-documentation
                                    (or (not (numberp lsp-signature-doc-lines))
                                        (> lsp-signature-doc-lines 0))))
                 (method-doc (and docs-enabled (my--signature-render-doc
                                                (lsp:signature-information-documentation? signature))))
                 (parameter-doc (and docs-enabled parameter (my--signature-render-doc
                                                             (lsp:parameter-information-documentation? parameter))))
                 (docs (string-join
                        (delq nil (list (when (and parameter-doc
                                                  (not (equal (substring-no-properties parameter-doc)
                                                              (and method-doc (substring-no-properties method-doc)))))
                                         (concat (propertize "Active parameter" 'face 'bold) "\n" parameter-doc))
                                       method-doc)) "\n\n")))
            (when range
              (add-face-text-property (car range) (cdr range)
                                      'lsp-signature-highlight-function-argument nil text))
            (when (and (numberp lsp-signature-doc-lines) (> lsp-signature-doc-lines 0)
                       (> (length (split-string docs "\n")) lsp-signature-doc-lines))
              (setq docs (concat (string-join (seq-take (split-string docs "\n") lsp-signature-doc-lines) "\n")
                                 (propertize "\nTruncated..." 'face 'shadow))))
            (concat prefix text (unless (string-empty-p docs) (concat "\n" docs))))
        ;; A malformed optional field must not interrupt typing or hide the label.
        (error (copy-sequence label))))))

(defun my--documentation-signature-parameter-lines (message signature)
  "Insert line breaks before reliably identified parameters in MESSAGE.
SIGNATURE supplies LSP parameter ranges or unambiguous labels. Preserve every
original character and text property; do not parse types, defaults or separators.
Missing, overlapping or ambiguous metadata leaves MESSAGE unchanged."
  (condition-case nil
      (let* ((label (lsp:signature-information-label signature))
             (offset (string-match (regexp-quote label) message))
             (parameters (lsp:signature-information-parameters? signature))
             (previous-end 0) starts pieces (cursor 0))
        (unless (and offset (> (length parameters) 0)) (error "No boundaries"))
        (seq-doseq (parameter parameters)
          (let* ((range (my--signature-parameter-range label parameter))
                 (start (car range)) (end (cdr range)))
            (unless (and start end (<= previous-end start))
              (error "Unreliable boundaries"))
            ;; Avoid adding blank rows to signatures already formatted by a server.
            (unless (string-match-p "\n" (substring label previous-end start))
              (push (+ offset start) starts))
            (setq previous-end end)))
        (if (null starts)
            message
          (dolist (start (nreverse starts))
            (push (substring message cursor start) pieces)
            (push "\n    " pieces)
            (setq cursor start))
          (push (substring message cursor) pieces)
          (apply #'concat (nreverse pieces))))
    (error message)))

(defun my--signature-return-start (signature)
  "Find a return marker anchored to SIGNATURE's last LSP parameter boundary.
LSP has no separate return-type range. Accept only an arrow or colon directly
after the closing argument list at that boundary. Missing or empty parameter
metadata, including implicit receivers omitted by a server, leaves the return
clause unchanged. Do not infer receiver names or parse nested callable types."
  (condition-case nil
      (let* ((label (lsp:signature-information-label signature))
             (parameters (lsp:signature-information-parameters? signature)))
        (when (and parameters (> (length parameters) 0))
          (when-let ((range (my--signature-parameter-range label (seq-elt parameters (1- (length parameters))))))
            (let ((end (cdr range)))
              (when (string-match "\\`[ \t\n]*,?[ \t\n]*)[ \t\n]*\\(->\\|:\\)[ \t\n]*\\S-"
                                  (substring label end))
                (+ end (match-beginning 1)))))))
    (error nil)))

(defun my--signature-separate-return (text)
  "Place the reliably marked return clause of TEXT after one blank line.
Keep the server's return marker, type text and face properties intact.
Only the return clause marked by our boundary detection is moved."
  (let ((position 0) start)
    (while (and (< position (length text)) (not start))
      (let ((faces (get-text-property position 'face text)))
        (when (or (eq faces 'my-documentation-signature-return)
                  (and (listp faces) (memq 'my-documentation-signature-return faces)))
          (setq start position)))
      (setq position (next-single-property-change position 'face text (length text))))
    (if start
        (concat (string-trim-right (substring text 0 start)) "\n\n" (substring text start))
      text)))

(defun my--signature-hanging-values (text width)
  "Align visual continuations with the value in simple parameter rows of TEXT.
Recognize only indented name: value and name = value prefixes. Do not parse the
value's types, defaults or nested syntax. Leave other rows and narrow layouts
alone. Add display properties to a copy without changing characters or faces."
  (let ((position 0) result)
    (while (string-match
            "^[ ]+\\(?:\\*\\{1,2\\}\\)?[[:alpha:]_][[:alnum:]_]*\\(?:[?]\\)?[ ]*[:=][ ]+"
            text position)
      (let* ((start (match-beginning 0))
             (value (match-end 0))
             (end (or (string-match "\n" text value) (length text)))
             (column (string-width (substring-no-properties text start value))))
        (when (and (< value end) (< column (- width 8))
                   (not (text-property-not-all start end 'wrap-prefix nil text)))
          (unless result (setq result (copy-sequence text)))
          (put-text-property start end 'wrap-prefix (make-string column ?\s) result))
        (setq position (max value end))))
    (or result text)))

(defun my--documentation-bottom-signature-content (message width)
  "Keep MESSAGE intact, adding a rule before server-provided documentation.
Use only the selected server label to locate the documentation boundary.
If the boundary cannot be established, display the original message unchanged."
  (condition-case nil
      (let* ((signatures (and lsp--signature-last
                             (lsp:signature-help-signatures lsp--signature-last)))
             (signature (and signatures (> (length signatures) 0)
                             (seq-elt signatures (or lsp--signature-last-index 0))))
             (label (and signature (lsp:signature-information-label signature)))
             (offset (and label (string-match (regexp-quote label) message)))
             (end (and offset (+ offset (length label)))))
        (if (null end)
            message
          (let ((description (string-trim-left (substring message end) "[\r\n\f]+")))
            (let* ((text (copy-sequence (if (string-empty-p description) message (substring message 0 end))))
                   (position offset))
              ;; Only style the server's signature label, not its description.
              ;; Preserve the active face and any existing server-provided faces.
              (while (< position end)
                (let* ((face (get-text-property position 'face text))
                       (next (next-single-property-change position 'face text end)))
                  (unless (or (eq face 'lsp-signature-highlight-function-argument)
                              (and (listp face) (memq 'lsp-signature-highlight-function-argument face)))
                    (add-face-text-property position next 'my-documentation-signature-inactive t text))
                  (setq position next)))
              (when-let ((return (my--signature-return-start signature)))
                (add-face-text-property (+ offset return) end
                                        'my-documentation-signature-return nil text))
              (let ((heading (my--signature-hanging-values
                              (my--signature-separate-return
                               (my--documentation-signature-parameter-lines text signature))
                              width)))
              (if (string-empty-p description)
                  (if (equal-including-properties heading message) message heading)
                (concat heading "\n"
                      (propertize (make-string (max 1 (1- width)) ?─) 'face 'shadow)
                      "\n" description)))))))
    (error message)))

(defun my--documentation-display-bottom-signature (signature)
  "Show SIGNATURE in a wrapped bottom window matching the Vertico height.
Keep the native signature lifecycle and active-parameter text properties, but
avoid LV's content-dependent resizing and truncation of multiline messages."
  ;; Window restoration can recycle LV's cached window for a source buffer.
  ;; Never erase, resize or delete a window merely because that cache is live.
  (unless (and (window-live-p lv-wnd)
               (eq (window-buffer lv-wnd) (get-buffer " *LV*")))
    (setq lv-wnd nil))
  (if (null signature)
      (lsp-lv-message nil)
    (setq lsp--signature-last-buffer (current-buffer))
    (let* ((window (lv-window))
           (formatted (my--documentation-bottom-signature-content
                       signature (window-body-width window)))
           (rows (1+ (if (boundp 'vertico-count) vertico-count 17)))
           (height (min (* rows (frame-char-height (window-frame window)))
                        (floor (* 0.45 (frame-pixel-height (window-frame window)))))))
      (with-current-buffer (window-buffer window)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert formatted))
        (visual-line-mode 1)
        (setq-local truncate-lines nil window-min-height 1)
        (goto-char (point-min)))
      (let ((window-resize-pixelwise t))
        (window-resize window (- height (window-pixel-height window)) nil t t))
      (with-selected-window window
        (let ((position (point-min)) active)
          (while (and (< position (point-max)) (not active))
            (let ((face (get-text-property position 'face)))
              (when (or (eq face 'lsp-signature-highlight-function-argument)
                        (and (listp face) (memq 'lsp-signature-highlight-function-argument face)))
                (setq active position)))
            (setq position (next-single-property-change position 'face nil (point-max))))
          (goto-char (or active (point-min)))
          (if active
              (let ((scroll-margin 0)) (recenter))
            (set-window-start window (point-min))))))))

(defun my--documentation-display-floating-signature (signature)
  "Show SIGNATURE near point in graphical Emacs, or in the bottom window.
Use lsp-mode's existing renderers; never select the signature frame."
  (if (and (display-graphic-p)
           (require 'posframe nil t)
           (posframe-workable-p))
      (let ((lsp-signature-posframe-params
             (append (list :border-width 2
                           :border-color
                           (face-foreground 'font-lock-keyword-face nil t))
                     lsp-signature-posframe-params)))
        (setq lsp-signature-posframe-params
              (append '(:height nil :min-height 1 :max-height 24
                        :width nil :min-width 35 :max-width 90)
                      lsp-signature-posframe-params))
        (lsp-signature-posframe signature))
    (lsp-lv-message signature)))

(add-hook 'doom-load-theme-hook #'my--documentation-signature-fallback-faces)

(with-eval-after-load 'lsp-mode
  (advice-add 'lsp--signature->message :override #'my--signature-message)
  (my--documentation-signature-fallback-faces)
  (setq lsp-signature-function #'my--documentation-display-signature
        lsp-signature-render-documentation (eq my-documentation-signature-style 'bottom)))
