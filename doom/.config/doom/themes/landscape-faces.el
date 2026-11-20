;;; landscape-faces.el --- Shared Doom landscape semantics -*- lexical-binding: t; -*-

;; Original mappings for the user-approved landscape palettes.  Doom's framework
;; supplies package support; no Tokyo Night implementation is copied here.
(require 'cl-lib)
(require 'color)
(require 'doom-themes)
(require 'landscape-palettes)
(require 'landscape-packages)

(defun landscape--color-luminance (hex)
  "Return relative sRGB luminance for hexadecimal color HEX."
  (cl-loop for start in '(1 3 5)
           for weight in '(0.2126 0.7152 0.0722)
           for channel = (/ (string-to-number (substring hex start (+ start 2)) 16) 255.0)
           sum (* weight (if (<= channel 0.04045) (/ channel 12.92)
                           (expt (/ (+ channel 0.055) 1.055) 2.4)))))

(defun landscape--visual-selection-background (row tint light)
  "Separate TINT from ROW by at least 1.65:1 luminance contrast.
Lift the theme tint in dark themes and deepen it in LIGHT themes."
  (let ((row-luminance (landscape--color-luminance row))
        (hsl (apply #'color-rgb-to-hsl
                    (cl-loop for start in '(1 3 5)
                             collect (/ (string-to-number
                                         (substring tint start (+ start 2)) 16) 255.0))))
        (color tint))
    (setf (cadr hsl) (max 0.16 (cadr hsl)))
    (setq color (apply #'color-rgb-to-hex
                       (append (apply #'color-hsl-to-rgb hsl) '(2))))
    (while (let ((luminance (landscape--color-luminance color)))
             (and (if light (> (nth 2 hsl) 0.0) (< (nth 2 hsl) 1.0))
                  (or (if light (>= luminance row-luminance)
                        (<= luminance row-luminance))
                      (< (/ (+ 0.05 (max luminance row-luminance))
                            (+ 0.05 (min luminance row-luminance))) 1.65))))
      ;; Adjust lightness without washing the secondary hue into gray.
      (setf (nth 2 hsl) (max 0.0 (min 1.0 (+ (nth 2 hsl) (if light -0.01 0.01)))))
      (setq color (apply #'color-rgb-to-hex
                         (append (apply #'color-hsl-to-rgb hsl) '(2)))))
    color))

(defun landscape--line-number-color (accent)
  "Make hexadecimal ACCENT up to 20 percent more saturated for line numbers.
Preserve its hue and brightest channel; already saturated colors stay intact."
  (let* ((channels (cl-loop for start in '(1 3 5)
                            collect (string-to-number (substring accent start (+ start 2)) 16)))
         (brightest (apply #'max channels))
         (range (- brightest (apply #'min channels))))
    (if (zerop range)
        accent
      (let ((factor (min 1.2 (/ (float brightest) range))))
        (apply #'format "#%02X%02X%02X"
               (mapcar (lambda (channel)
                         (round (- brightest (* factor (- brightest channel)))))
                       channels))))))

(defun landscape--bindings (variant &optional background-mode)
  "Return literal palette bindings for VARIANT and optional BACKGROUND-MODE."
  (let* ((palette (cdr (assq variant landscape-palettes)))
         (light (if background-mode (eq background-mode 'light)
                  (string-suffix-p "-light" (symbol-name variant))))
         (iceland (string-prefix-p "iceland-" (symbol-name variant)))
         (ui-background (or (plist-get palette :ui-bg)
                            (doom-blend "#000000" (plist-get palette :bg)
                                        (if light 0.10 0.25))))
         (modeline-background (or (plist-get palette :modeline-bg) ui-background))
         ;; Inactive windows retain a hint of the active bar's hue, while
         ;; receding toward the editor surface in both light and dark themes.
         (inactive-background (doom-blend modeline-background (plist-get palette :bg) 0.20))
         (inactive-foreground (doom-blend (plist-get palette :fg) inactive-background 0.65))
         ;; Keep the existing primary-accent row color independent of selection.
         (row-tint (doom-blend (plist-get palette :accent)
                              (plist-get palette :selection-bg) 0.25))
         (current-line-background (doom-blend row-tint
                                             (plist-get palette :line) 0.40))
         (visual-tint (doom-blend (plist-get palette :selection-accent)
                                 (if light "#FFFFFF" "#000000")
                                 (if light 0.25 0.40)))
         (visual-background (landscape--visual-selection-background
                             current-line-background visual-tint light))
         (bindings
          (cl-loop for (key value) on palette by #'cddr
                   collect (list (intern (substring (symbol-name key) 1))
                                 (list 'quote (list value value))))))
    (unless palette (error "Unknown landscape palette: %s" variant))
    (append bindings
            ;; Neutral surfaces (0-3) and readable labels (4-8). Interpolate
            ;; sRGB channels deterministically from bg to fg; do not add hues.
            (cl-loop for amount in (if light
                                        '(0.0 0.05 0.10 0.16 0.84 0.88 0.92 0.96 1.0)
                                      '(0.0 0.05 0.10 0.16 0.78 0.82 0.88 0.94 1.0))
                     for n from 0
                     for color = (doom-blend (plist-get palette :fg)
                                             (plist-get palette :bg) amount)
                     collect (list (intern (format "base%d" n))
                                   (list 'quote (list color color))))
            `((ui-bg ',(list ui-background ui-background))
              ;; Active text selection is stronger than passive row/picker
              ;; surfaces, using this variant's secondary selection accent.
              (visual-bg ',(list visual-background visual-background))
              (current-line-bg ',(list current-line-background current-line-background))
              (receiver-tone
               ',(let ((color (doom-blend (plist-get palette :keyword)
                                         (plist-get palette :fg) 0.55)))
                   (list color color)))
              (argument
               ',(let ((color (or (plist-get palette :parameter-color)
                                  (doom-blend (plist-get palette :constant)
                                              (plist-get palette :fg) 0.65))))
                   (list color color)))
              (punctuation-tone
               ',(let ((color (doom-blend (plist-get palette :fg)
                                         (plist-get palette :punctuation) 0.15)))
                   (list color color)))
              (line-number-active
               ',(let ((color (or (plist-get palette :line-number-active)
                                  (landscape--line-number-color (plist-get palette :accent)))))
                   (list color color)))
              (line-number-muted
               ',(let ((color (doom-blend (plist-get palette :comment)
                                         (plist-get palette :bg) 0.65)))
                   (list color color)))
              (paren-match-bg
               ',(let ((color (doom-blend (plist-get palette :accent)
                                         (plist-get palette :line) 0.30)))
                   (list color color)))
              (ansi-black ,(if light 'fg 'comment))
              (ansi-white ,(if light 'comment 'fg))
              (fg-alt comment) (grey comment)
              (syntax-comment ,(if (plist-member palette :code-comment) 'code-comment 'comment))
              (red error) (orange string) (green success) (yellow warning)
              (blue ,(if iceland 'constant 'type)) (dark-blue blue)
              (magenta ,(if iceland
                            (list 'quote (list (if light "#674860" "#BA9AAE")
                                               (if light "#674860" "#BA9AAE")))
                          'constant))
              (violet constant) (cyan ,(if iceland 'function 'info))
              (dark-cyan cyan) (teal function)
              ;; Keep navigation and document structure on distinct palette roles.
              (heading-1 ,(if (equal (plist-get palette :accent)
                                      (plist-get palette :function)) 'constant 'accent))
              (heading-2 type) (heading-3 string)
              (symbol-header-bg
               ',(let ((color (doom-blend (plist-get palette :selection-accent)
                                         (if light "#FFFFFF" "#000000")
                                         (if light 0.22 0.40))))
                   (list color color)))
              (org-navigation function)
              (modeline-bg ',(list modeline-background modeline-background))
              (modeline-bg-inactive ',(list inactive-background inactive-background))
              (modeline-fg-inactive ',(list inactive-foreground inactive-foreground))
              (highlight accent) (vertical-bar border) (selection selection-bg)
              (builtin function) (comments syntax-comment) (doc-comments syntax-comment)
              (constants constant) (functions function) (keywords keyword)
              (methods function) (operators fg) (strings string) (variables fg)
              (numbers constant) (region visual-bg)
              (vc-modified changed-fg) (vc-added added-fg) (vc-deleted removed-fg)))))

(defun landscape--faces (&optional variant background-mode)
  "Return shared face forms for `def-doom-theme'.
Only colors and necessary semantic styles are overridden. Existing heading
sizes, font families and Doom's bold/italic preferences are preserved.
Modules are bold. Light VARIANTs use bold keywords and normal-weight
definition/type faces.
BACKGROUND-MODE can explicitly select light or dark for named flavors."
  (let ((faces
         '((default :foreground fg :background bg)
           (landscape-receiver :inherit 'unspecified :foreground receiver-tone
                               :weight 'normal)
           (fringe :foreground comment :background bg)
           (shadow :foreground comment)
           (hl-line :foreground 'unspecified :background current-line-bg :extend t)
           (line-number :foreground line-number-muted :background bg-alt)
           (line-number-current-line :inherit 'line-number :foreground line-number-active
                                     :background 'unspecified :weight 'bold)
           (cursor :background accent)
           (minibuffer-prompt :foreground accent)
           (link :foreground accent :underline t)
           (link-visited :foreground accent :underline t)
           (region :inherit 'unspecified :foreground 'unspecified :background visual-bg
                   :distant-foreground 'unspecified :extend t)
           (secondary-selection :foreground selection-fg :background selection-bg)
           (highlight :foreground selection-fg :background selection-bg)
           (match :foreground search-fg :background search-bg)
           (lazy-highlight :foreground search-fg :background search-bg)
           (isearch :foreground search-current-fg :background search-current-bg)
           (evil-ex-search :foreground search-current-fg :background search-current-bg)
           (evil-ex-substitute-matches :foreground removed-fg :background removed-bg
                                       :strike-through t)
           (evil-ex-substitute-replacement :foreground added-fg :background added-bg)
           (isearch-fail :foreground removed-fg :background removed-bg)
           ;; Preserve syntax colors; a matching delimiter is not a search hit.
           (show-paren-match :foreground 'unspecified :background paren-match-bg
                             :weight 'normal)
           (show-paren-mismatch :foreground removed-fg :background removed-bg
                                :underline t)
           (tooltip :foreground fg :background bg-alt)
           (mode-line :foreground fg :background modeline-bg)
           (mode-line-active :foreground fg :background modeline-bg)
           (mode-line-inactive :foreground modeline-fg-inactive :background modeline-bg-inactive)
           (header-line :foreground fg :background ui-bg)
           (tab-bar :foreground fg :background bg-alt)
           (tab-bar-tab :foreground accent :background bg :underline t)
           (tab-bar-tab-inactive :foreground comment :background bg-alt)
           (tab-line :foreground fg :background bg-alt)
           (tab-line-tab-current :foreground accent :background bg :underline t)
           (tab-line-tab-inactive :foreground comment :background bg-alt)
           (button :foreground accent :underline t)
           (custom-button :foreground fg :background bg-alt)
           (custom-button-mouse :foreground selection-fg :background selection-bg)
           (custom-button-pressed :foreground search-current-fg :background accent)
           )))
    (setq faces (append (landscape--package-faces) faces))
    ;; All separators are decorative; focus uses the separate accent role.
    (dolist (face '(vertical-border window-divider window-divider-first-pixel
				    window-divider-last-pixel))
      (push `(,face :foreground border :background border) faces))
    ;; Quiet identifiers have separate faces, but intentionally the same color.
    (dolist (mapping
             '((fg ess-operator-face ess-%op%-face ess-assignment-face
                   font-lock-variable-name-face font-lock-variable-use-face
                   font-lock-property-use-face
                   font-lock-operator-face lsp-face-semhl-variable
                   lsp-face-semhl-property
                   lsp-face-semhl-member lsp-face-semhl-event
                   lsp-face-semhl-operator)
               (argument font-lock-property-name-face lsp-face-semhl-parameter)
               (punctuation-tone ess-paren-face font-lock-punctuation-face font-lock-bracket-face
                                 font-lock-delimiter-face font-lock-misc-punctuation-face)
               (function font-lock-function-name-face font-lock-function-call-face
                         font-lock-builtin-face lsp-face-semhl-function
                         lsp-face-semhl-method)
               (keyword font-lock-keyword-face lsp-face-semhl-keyword
                        lsp-face-semhl-modifier)
               (type font-lock-type-face lsp-face-semhl-type lsp-face-semhl-class
                     lsp-face-semhl-struct lsp-face-semhl-interface
                     lsp-face-semhl-enum lsp-face-semhl-type-parameter)
               (module-color lsp-face-semhl-namespace)
               (string font-lock-string-face lsp-face-semhl-string lsp-face-semhl-regexp)
               (constant ess-numbers-face ess-constant-face
                         font-lock-constant-face font-lock-number-face
                         font-lock-escape-face font-lock-regexp-grouping-backslash
                         font-lock-regexp-grouping-construct font-lock-preprocessor-face
                         lsp-face-semhl-constant lsp-face-semhl-number
                         lsp-face-semhl-enum-member lsp-face-semhl-macro
                         lsp-face-semhl-decorator)
               (syntax-comment font-lock-comment-face font-lock-comment-delimiter-face
                        font-lock-doc-face lsp-face-semhl-comment)))
      (dolist (face (cdr mapping))
        (push `(,face :foreground ,(car mapping)
                       ,@(when (eq (car mapping) 'module-color)
                           (list :weight ''bold))) faces)))
    ;; Newer Emacs versions expose a dedicated built-in parameter face.
    (when (facep 'font-lock-parameter-face)
      (push '(font-lock-parameter-face :foreground argument) faces))
    ;; Light themes emphasize keywords as well as modules. Definitions/types
    ;; stay normal.
    ;; Dark variants and Doom's global bold preference remain unchanged.
    (when (and variant (if background-mode (eq background-mode 'light)
                        (string-suffix-p "-light" (symbol-name variant))))
      (dolist (spec faces)
        (let ((face (car spec)))
          (cond ((memq face '(font-lock-keyword-face lsp-face-semhl-keyword
                             lsp-face-semhl-modifier))
                 (setcdr spec (plist-put (cdr spec) :weight ''bold)))
                ((memq face '(font-lock-function-name-face font-lock-type-face
                              lsp-face-semhl-type lsp-face-semhl-class
                              lsp-face-semhl-struct lsp-face-semhl-interface
                              lsp-face-semhl-enum lsp-face-semhl-type-parameter))
                 (setcdr spec (plist-put (cdr spec) :weight ''normal)))))))
    ;; Do not introduce external tree-sitter face names on built-in treesit-only
    ;; installations. Versions exposing these faces receive the same semantics.
    (when (locate-library "tree-sitter-hl")
      (require 'tree-sitter-hl)
      (dolist (mapping '((keyword keyword conditional repeat)
                         (function function function.call method method.call function.builtin)
                         (type type type.builtin type.argument constructor)
                         (module-color namespace)
                         (constant constant number boolean attribute macro)
                         (string string string.special) (syntax-comment comment doc)
                         (argument variable.parameter property.definition)
                         (punctuation-tone punctuation punctuation.bracket punctuation.delimiter)
                         (fg variable variable.builtin property operator)))
        (dolist (suffix (cdr mapping))
          (let ((face (intern (format "tree-sitter-hl-face:%s" suffix))))
            (when (facep face)
              (push `(,face :foreground ,(car mapping)
                           ,@(when (eq (car mapping) 'module-color)
                               (list :weight ''bold))
                           ,@(when (and variant
                                        (if background-mode (eq background-mode 'light)
                                          (string-suffix-p "-light" (symbol-name variant)))
                                        (memq (car mapping) '(keyword type)))
                               (list :weight (if (eq (car mapping) 'keyword)
                                                 ''bold ''normal)))) faces))))))
    ;; Landscape comments have their own hue and typography, independent of
    ;; dim UI labels. Reference-inspired families retain their original styles.
    (when (and variant (assq variant landscape-palettes))
      (dolist (spec faces)
        (when (memq (car spec) '(font-lock-comment-face font-lock-comment-delimiter-face
                                font-lock-doc-face lsp-face-semhl-comment
                                tree-sitter-hl-face:comment tree-sitter-hl-face:doc))
          (setcdr spec (plist-put (cdr spec) :slant
                                 '(if doom-themes-enable-italic 'italic 'normal))))))
    ;; The document title is distinct from the Org heading hierarchy.
    (push '(org-document-title :foreground module-color) faces)
    ;; A distinct mode-line surface can supply its own readable text roles.
    ;; Leave syntax and other interface surfaces on their original palette.
    (when (plist-member (cdr (assq variant landscape-palettes)) :modeline-fg)
      (dolist (face '(mode-line mode-line-active solaire-mode-line-face
                      solaire-mode-line-active-face doom-modeline-buffer-file))
        (push (list face :foreground 'modeline-fg) faces))
      (dolist (face '(doom-modeline-buffer-path doom-modeline-project-name
                      doom-modeline-project-parent-dir doom-modeline-persp-name
                      doom-modeline-persp-buffer-not-in-persp doom-modeline-debug
                      doom-modeline-input-method-alt doom-modeline-buffer-minor-mode
                      doom-modeline-evil-motion-state))
        (push (list face :foreground 'modeline-muted) faces)))
    ;; &override retains framework styles (e.g. Org heading weights) while
    ;; replacing only the attributes above. No global face setters or hooks.
    (let ((merged (make-hash-table :test #'eq)) order)
      (dolist (spec (reverse faces))
        (unless (gethash (car spec) merged) (push (car spec) order))
        (let ((attributes (gethash (car spec) merged)))
          (cl-loop for (key value) on (cdr spec) by #'cddr
                   do (setq attributes (plist-put attributes key value)))
          (puthash (car spec) attributes merged)))
      (setq faces (mapcar (lambda (face) (cons face (gethash face merged))) order)))
    (mapcar (lambda (spec)
              (let ((base (cdr (assq (car spec) doom-themes-base-faces))))
                ;; Mode-dependent &light/&dark specs cannot be plist-merged by
                ;; the installed Doom framework; replace those specifications.
                (if (and base (not (keywordp (car base)))) spec
                  (cons (list (car spec) '&override) (cdr spec))))) faces)))

(defmacro landscape-define-theme (variant)
  "Define landscape VARIANT through the installed `def-doom-theme' macro.
Expand literal palette and face forms for the installed Doom framework.
Theme entries intentionally remain source, as in upstream Doom themes."
  (let ((name (intern (format "custom-landscape-%s" variant))))
    `(def-doom-theme ,name ,(format "Landscape %s." variant)
		     :family 'custom-landscape
		     :background-mode ',(if (string-suffix-p "-light" (symbol-name variant)) 'light 'dark)
		     ,(landscape--bindings variant)
		     ,(landscape--faces variant)
		     ;; Face composition is theme-owned and restored by `disable-theme'.
		     ;; In this lsp-mode version readonly shares the constant *token* face,
		     ;; and declaration shares the interface face. Neutralize those modifier
		     ;; mappings instead of incorrectly recoloring all constants/interfaces.
		     ((lsp-semantic-token-modifier-faces
		       (list 'quote (landscape--semantic-modifiers)))
		      (ansi-color-names-vector
		       (vconcat (mapcar #'doom-color
					'(ansi-black red green yellow blue magenta cyan ansi-white))))))))

(provide 'landscape-faces)
;;; landscape-faces.el ends here
