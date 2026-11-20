;;; landscape-packages.el --- Focused landscape package faces -*- lexical-binding: t; -*-

(require 'cl-lib)

(defface landscape-receiver
  '((t (:inherit font-lock-keyword-face)))
  "Language-independent receiver identifiers, such as self, cls and this.
Custom themes give this role a secondary color and normal weight. Other themes
inherit keyword styling. Only explicit server or parser roles should use it."
  :group 'faces)

(defface landscape-diagnostic-info
  '((t (:inherit success)))
  "Informational sideline messages, colored by the active custom theme."
  :group 'faces)

(defun landscape--package-faces ()
  "Return package face forms, sharing the core landscape semantic palette."
  (let ((faces
         '(
           (solaire-default-face :foreground fg :background ui-bg)
           (solaire-mode-line-face :foreground fg :background modeline-bg)
           (solaire-mode-line-active-face :foreground fg :background modeline-bg)
           (solaire-mode-line-inactive-face :foreground modeline-fg-inactive :background modeline-bg-inactive)
           (solaire-hl-line-face :foreground 'unspecified :background current-line-bg :extend t)
           (solaire-org-hide-face :foreground ui-bg)
           (org-hide :foreground bg)
           (org-indent :inherit 'org-hide)
           (org-block :background bg-alt :extend t)
           (org-block-begin-line :foreground comment :background bg-alt :extend t)
           (org-block-end-line :foreground comment :background bg-alt :extend t)
           (org-code :foreground constant)
           (org-verbatim :foreground string)
           (org-table :foreground fg)
           (org-tag :foreground comment)
           (org-meta-line :foreground comment)
           (org-special-keyword :foreground comment)
           (org-property-value :foreground fg)
           (org-drawer :foreground comment)
           (org-date :foreground accent :underline t)
           (org-link :foreground org-navigation :underline t)
           (org-cite :foreground org-navigation :underline t)
           (org-cite-key :foreground org-navigation :underline t)
           (org-todo :foreground error :weight 'bold)
           (org-done :foreground success :weight 'normal)
           (org-headline-done :foreground comment)
           (org-checkbox :foreground comment)
           (org-checkbox-statistics-todo :foreground warning :weight 'bold)
           (org-checkbox-statistics-done :foreground success :weight 'normal)
           (org-modern-progress-complete :foreground success :background bg-alt)
           (org-modern-progress-incomplete :foreground warning :background bg-alt)
           (org-priority :foreground warning :weight 'bold)
           (org-warning :foreground error :weight 'bold)
           (org-agenda-structure :foreground accent)
           (org-agenda-date :foreground accent)
           (org-agenda-date-today :foreground accent :underline t)
           (org-agenda-date-weekend :foreground type)
           (org-agenda-dimmed-todo-face :foreground comment)
           (org-upcoming-deadline :foreground warning)
           (org-upcoming-distant-deadline :foreground comment)
           (org-scheduled :foreground fg)
           (org-scheduled-today :foreground success)
           (org-scheduled-previously :foreground warning)
           (org-modern-label :foreground fg :background bg-alt)
           (org-roam-header-line :foreground fg :background bg-alt)
           (org-roam-title :foreground org-navigation)
           (org-roam-olp :foreground comment)
           (org-roam-dim :foreground comment)
           (org-roam-preview-heading :foreground fg :background bg-alt)
           (org-roam-preview-heading-highlight :foreground fg :background line)
           (org-roam-preview-heading-selection :foreground selection-fg :background selection-bg)
           (org-modern-todo :foreground error :background bg-alt :weight 'bold)
           (org-modern-done :foreground success :background bg-alt
                            :weight 'normal :inverse-video nil)
           (org-modern-priority :foreground warning :background bg-alt)
           (org-modern-date-active :foreground accent :background bg-alt)
           (org-modern-date-inactive :foreground comment :background bg-alt)
           (org-modern-time-active :foreground accent :background bg-alt)
           (org-modern-time-inactive :foreground comment :background bg-alt)
           (+org-todo-active :foreground info :weight 'bold)
           (+org-todo-project :foreground accent :weight 'bold)
           (+org-todo-onhold :foreground warning :weight 'normal)
           (+org-todo-cancel :foreground error :weight 'normal :strike-through t)
           (citar :foreground fg)
           (citar-highlight :foreground accent)
           (citar-selection :foreground selection-fg :background selection-bg)
           (markdown-code-face :foreground constant :background bg-alt)
           (markdown-pre-face :foreground fg :background bg-alt)
           (markdown-markup-face :foreground comment)
           (markdown-inline-code-face :foreground constant :background bg-alt)
           (markdown-blockquote-face :foreground comment)
           (markdown-table-face :foreground fg)
           (markdown-link-face :foreground accent :underline t)
           (markdown-url-face :foreground accent :underline t)
           (corfu-default :foreground fg :background bg-alt)
           (corfu-current :foreground selection-fg :background selection-bg)
           (corfu-annotations :foreground fg)
           (corfu-bar :background accent)
           (corfu-border :background border)
           (vertico-current :foreground selection-fg :background selection-bg :extend t)
           (my-symbols-column-header-face :inherit 'default :foreground fg
                                          :background symbol-header-bg :weight 'bold
                                          :extend t)
           (company-tooltip :foreground fg :background bg-alt)
           (company-tooltip-selection :foreground selection-fg :background selection-bg)
           (company-tooltip-annotation :foreground comment)
           (company-tooltip-annotation-selection :foreground selection-fg)
           (company-tooltip-common :foreground fg :underline t)
           (company-tooltip-common-selection :foreground selection-fg :underline t)
           (completions-common-part :foreground fg :underline t)
           (completions-first-difference :foreground fg)
           (completions-annotations :foreground fg)
           (consult-preview-match :foreground search-fg :background search-bg)
           (consult-highlight-match :foreground search-fg :background search-bg)
           (which-key-key-face :foreground accent)
           (which-key-command-description-face :foreground fg)
           (which-key-group-description-face :foreground function)
           (which-key-separator-face :foreground comment)
           (marginalia-documentation :foreground fg)
           (marginalia-file-owner :foreground fg)
           (marginalia-size :foreground fg)
           (doom-modeline-bar :background accent)
           (doom-modeline-bar-inactive :background border)
           (doom-modeline-buffer-path :foreground comment)
           (doom-modeline-buffer-file :foreground fg)
           (doom-modeline-buffer-modified :foreground warning)
           (dired-directory :foreground function)
           (dired-symlink :foreground accent :underline t)
           (dired-ignored :foreground comment)
           (treemacs-directory-face :foreground function)
           (treemacs-root-face :foreground accent)
           (treemacs-file-face :foreground fg)
           (lsp-inlay-hint-face :foreground comment :background bg-alt)
           (lsp-inlay-hint-type-face :foreground comment)
           (lsp-inlay-hint-parameter-face :foreground comment)
           (lsp-ui-doc-background :background bg-alt)
           (lsp-ui-doc-header :foreground fg :background bg-alt)
           (lsp-ui-sideline-symbol :foreground comment)
           (lsp-ui-sideline-symbol-info :foreground comment)
           (lsp-ui-sideline-current-symbol :foreground accent :underline t)
           (lsp-ui-sideline-code-action :foreground warning)
           (lsp-face-highlight-textual :foreground search-fg :background search-bg)
           (lsp-face-highlight-read :foreground search-fg :background search-bg)
           (lsp-face-highlight-write :foreground search-fg :background search-bg :underline t)
           ;; Modifiers must add style without inheriting another token hue.
           (lsp-face-semhl-definition :inherit 'unspecified :foreground 'unspecified)
           (lsp-face-semhl-implementation :inherit 'unspecified :foreground 'unspecified)
           (lsp-face-semhl-default-library :inherit 'unspecified :foreground 'unspecified)
           (lsp-face-semhl-static :inherit 'unspecified :foreground 'unspecified)
           (lsp-face-semhl-deprecated :inherit 'unspecified :foreground 'unspecified
                                      :strike-through t)
           )))
    ;; Keep typography inherited, with a clear leading hierarchy and quiet
    ;; deeper headings. Markdown retains its previous color cycle.
    (cl-loop for n from 1 to 8
             for role = (pcase n (1 'heading-1) (2 'heading-2) (3 'heading-3) (_ 'fg))
             do (dolist (prefix '(outline- org-level-))
                  (push `(,(intern (format "%s%d" prefix n)) :foreground ,role
                          :weight ',(if (<= n 4) 'bold 'normal)) faces)))
    (cl-loop for n from 1 to 6
             for role = (nth (% (1- n) 5) '(keyword function type constant string))
             do (push `(,(intern (format "markdown-header-face-%d" n))
                        :foreground ,role) faces))
    ;; Match fragments use underline with no foreground/background replacement,
    ;; so selected candidates keep the actual validated selection pair.
    (dotimes (n 4)
      (push `(,(intern (format "orderless-match-face-%d" n))
              :foreground 'unspecified :background 'unspecified :underline t) faces))
    ;; Diagnostic overlays keep syntax foregrounds. Errors have waves;
    ;; warnings/notes use straight underlines supported by Emacs 29.
    (dolist (kind '(error warning info))
      (dolist (prefix '(flycheck- flymake-))
        (push `(,(intern (format "%s%s" prefix (if (and (eq prefix 'flymake-) (eq kind 'info)) 'note kind)))
                :foreground 'unspecified :background 'unspecified
                :underline (list :style ',(if (eq kind 'error) 'wave 'line) :color ,kind)) faces))
      (dolist (prefix '(flycheck-fringe- flycheck-error-list- flycheck-annotate-))
        (push `(,(intern (format "%s%s" prefix kind))
                :foreground ,kind :background 'unspecified) faces)))
    (dolist (mapping '((error error) (warning warning) (success success)
                       (landscape-diagnostic-info info)
                       (doom-modeline-urgent error) (doom-modeline-warning warning)
                       (doom-modeline-info info)))
      (push `(,(car mapping) :foreground ,(cadr mapping)) faces))
    (dolist (mapping '((added added-bg added-fg) (removed removed-bg removed-fg)
                       (changed changed-bg changed-fg)))
      (cl-destructuring-bind (kind background foreground) mapping
			     (dolist (prefix (if (eq kind 'changed) '(diff-) '(diff- magit-diff-)))
			       (push `(,(intern (format "%s%s" prefix (if (and (eq prefix 'flymake-) (eq kind 'info)) 'note kind)))
				       :foreground ,foreground :background ,background :extend t) faces))
			     (push `(,(intern (format "diff-hl-%s" (pcase kind ('added 'insert) ('removed 'delete) (_ 'change))))
				     :foreground ,foreground :background bg) faces)
			     (push `(,(intern (format "git-gutter:%s" (pcase kind ('removed 'deleted) ('changed 'modified) (_ 'added))))
				     :foreground ,foreground :background bg) faces)
			     (when (memq kind '(added removed))
			       (push `(,(intern (format "magit-diff-%s-highlight" kind))
				       :foreground ,foreground :background ,background :extend t) faces)
			       (dolist (face (list (intern (format "diff-refine-%s" kind))))
				 (push `(,face :foreground ,foreground :background ,background
					       :underline t :weight 'bold) faces)))))
    (dolist (spec '((magit-diff-our removed-fg removed-bg)
                    (magit-diff-our-highlight removed-fg removed-bg)
                    (magit-diff-their added-fg added-bg)
                    (magit-diff-their-highlight added-fg added-bg)
                    (magit-diff-base changed-fg changed-bg)
                    (magit-diff-base-highlight changed-fg changed-bg)
                    (magit-diff-context fg bg) (magit-diff-context-highlight fg line)
                    (magit-section-highlight fg line) (magit-diff-hunk-heading fg bg-alt)
                    (magit-diff-hunk-heading-highlight search-current-fg accent)
                    (diff-header fg bg-alt) (diff-file-header fg bg-alt)
                    (smerge-upper removed-fg removed-bg)
                    (smerge-lower added-fg added-bg) (smerge-base changed-fg changed-bg)
                    (ediff-current-diff-A removed-fg removed-bg)
                    (ediff-current-diff-B added-fg added-bg)
                    (ediff-current-diff-C changed-fg changed-bg)
                    (ediff-fine-diff-A removed-fg removed-bg)
                    (ediff-fine-diff-B added-fg added-bg)
                    (ediff-fine-diff-C changed-fg changed-bg)))
      (push `(,(nth 0 spec) :foreground ,(nth 1 spec) :background ,(nth 2 spec)) faces))
    (dolist (face '(ediff-fine-diff-A ediff-fine-diff-B ediff-fine-diff-C
				      smerge-refined-added smerge-refined-removed))
      (push `(,face :underline t :weight 'bold :inverse-video nil) faces))
    ;; Bright colors deliberately retain the readable normal foregrounds, rather
    ;; than lightening light-theme ANSI colors into unreadable pastel text.
    (dolist (mapping '((black ansi-black) (red red) (green green) (yellow yellow)
                       (blue blue) (magenta magenta) (cyan cyan) (white ansi-white)))
      (let ((name (car mapping)) (role (cadr mapping)))
        (dolist (prefix '(ansi-color- term-color- vterm-color-))
          (push `(,(intern (format "%s%s" prefix name))
                  :foreground ,role :background ,role) faces))
        (dolist (bright '(nil t))
          (push `(,(intern (format "ansi-color-%s%s" (if bright "bright-" "") name))
                  :foreground ,role :background ,role) faces))))
    faces))

(defface landscape-semhl-declaration
  '((t (:inherit unspecified :foreground unspecified)))
  "Color-neutral marker for declarations in semantic token face lists."
  :group 'faces)

(defun landscape--semantic-modifiers ()
  "Return color-neutral LSP modifier mappings when lsp-mode is installed.
Load definitions only, never start a language server. This must precede theme
variable assignment so Emacs can restore the package's original default."
  (when (locate-library "lsp-semantic-tokens")
    (require 'lsp-semantic-tokens)
    (mapcar (lambda (entry)
              (cond ((equal (car entry) "declaration")
                     (cons (car entry) 'landscape-semhl-declaration))
                    ((member (car entry)
                          '("readonly" "static" "abstract" "async"
                            "modification" "documentation" "defaultLibrary"))
                     (cons (car entry) 'lsp-face-semhl-static))
                    (t entry)))
            (default-value 'lsp-semantic-token-modifier-faces))))

(defvar lsp-semantic-token-modifier-faces)
(defvar lsp--buffer-workspaces)
(defvar lsp--cur-workspace)
(defvar semantic-token-modifier-cache)
(declare-function lsp--workspace-client "lsp-mode")
(declare-function lsp--workspace-semantic-tokens-faces "lsp-mode")
(declare-function lsp--semantic-tokens-initialize-workspace "lsp-semantic-tokens")

(defun landscape--modifier-change (_symbol value operation where)
  "Refresh existing LSP face caches when a theme sets modifier mappings.
Variable watchers run before assignment, so bind VALUE while rebuilding the
cached face vectors. No server requests, timers or per-keystroke work occur."
  (when (and (eq operation 'set) (null where) (featurep 'lsp-semantic-tokens))
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when (bound-and-true-p lsp--buffer-workspaces)
          (let ((lsp-semantic-token-modifier-faces
                 (if (local-variable-p 'lsp-semantic-token-modifier-faces)
                     lsp-semantic-token-modifier-faces value)))
            (dolist (workspace lsp--buffer-workspaces)
              (when (and (lsp--workspace-client workspace)
                         (lsp--workspace-semantic-tokens-faces workspace))
                (let ((lsp--cur-workspace workspace))
                  (lsp--semantic-tokens-initialize-workspace workspace))))
            (when (and (boundp 'semantic-token-modifier-cache)
                       (hash-table-p semantic-token-modifier-cache))
              (clrhash semantic-token-modifier-cache))
            (when (bound-and-true-p font-lock-mode) (font-lock-flush))))))))

(defun landscape-packages-unload-function ()
  "Remove the scoped LSP face-cache watcher when unloading this library."
  (remove-variable-watcher 'lsp-semantic-token-modifier-faces
                           #'landscape--modifier-change)
  nil)

;; `add-variable-watcher' deduplicates this function across repeated loads.
;; This is necessary because lsp-mode caches modifier-to-face mappings even
;; after the theme-owned variable has been restored on `disable-theme'.
(add-variable-watcher 'lsp-semantic-token-modifier-faces
                      #'landscape--modifier-change)

(provide 'landscape-packages)
;;; landscape-packages.el ends here
