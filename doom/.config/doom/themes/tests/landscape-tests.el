;;; landscape-tests.el --- Reproducible landscape checks -*- lexical-binding: t; -*-
;; Run via run-tests.sh; no personal init, notes, processes or services loaded.
(require 'ert)
(require 'cl-lib)
(require 'json)
(defconst landscape-test-directory (file-name-directory (or load-file-name buffer-file-name)))
(defconst landscape-test-root (file-name-directory (directory-file-name landscape-test-directory)))
(add-to-list 'load-path landscape-test-root)
(add-to-list 'custom-theme-load-path landscape-test-root)
(let ((build (getenv "LANDSCAPE_DOOM_BUILD")))
  (when build
    (dolist (directory (directory-files build t "^[^.]"))
      (when (file-directory-p directory) (add-to-list 'load-path directory)))))
(require 'landscape-faces)

;; Standalone Emacs does not load Doom's Org module, which normally declares
;; these state faces. Declare fixture faces so GUI tests exercise inheritance
;; instead of silently skipping unknown Doom faces.
(dolist (face '(+org-todo-active +org-todo-onhold +org-todo-project +org-todo-cancel))
  (unless (facep face)
    (custom-declare-face face '((t nil)) "Standalone Doom TODO state test face."
                         :group 'faces)))

(defun landscape-test-rgb (hex)
  "Decode HEX without a display-dependent color-name lookup."
  (cl-loop for start in '(1 3 5)
           collect (/ (string-to-number (substring hex start (+ start 2)) 16) 255.0)))
(defun landscape-test-luminance (hex)
  (apply #'+ (cl-mapcar (lambda (channel weight)
                          (* weight (if (<= channel 0.04045) (/ channel 12.92)
                                      (expt (/ (+ channel 0.055) 1.055) 2.4))))
			(landscape-test-rgb hex) '(0.2126 0.7152 0.0722))))
(defun landscape-test-contrast (one two)
  (let ((a (landscape-test-luminance one)) (b (landscape-test-luminance two)))
    (/ (+ 0.05 (max a b)) (+ 0.05 (min a b)))))
(defun landscape-test-select (theme)
  (mapc #'disable-theme (copy-sequence custom-enabled-themes))
  (load-theme theme t))
(defun landscape-test-spec (theme face)
  "Get actual evaluated true-color face attributes, including in batch mode."
  (let* ((setting (cl-find-if (lambda (setting)
				(and (eq (car setting) 'theme-face)
                                     (eq (nth 1 setting) face)))
                              (get theme 'theme-settings)))
         (spec (nth 3 setting)))
    (cadar spec)))
(defconst landscape-test-role-faces
  '((font-lock-variable-name-face . :fg) (font-lock-property-use-face . :fg)
    (font-lock-keyword-face . :keyword) (font-lock-function-call-face . :function)
    (font-lock-builtin-face . :function) (font-lock-type-face . :type)
    (font-lock-string-face . :string) (font-lock-doc-face . :comment)
    (font-lock-number-face . :constant) (lsp-face-semhl-class . :type)
    (lsp-face-semhl-function . :function) (lsp-face-semhl-property . :fg)
    (lsp-face-semhl-parameter . :fg) (lsp-face-semhl-macro . :constant)
    (lsp-face-semhl-enum-member . :constant)))

(defun landscape-test-lab (hex)
  "Convert sRGB HEX to CIELAB using the D65 reference white.
Used only as a broad color-separation regression guard, not as proof of
color-vision accessibility or of a major mode's token classifications."
  (let* ((channels (mapcar (lambda (channel)
                            (if (<= channel 0.04045) (/ channel 12.92)
                              (expt (/ (+ channel 0.055) 1.055) 2.4)))
                          (landscape-test-rgb hex)))
         (xyz (cl-mapcar
               (lambda (row white) (/ (apply #'+ (cl-mapcar #'* row channels)) white))
               '((0.4124564 0.3575761 0.1804375)
                 (0.2126729 0.7151522 0.0721750)
                 (0.0193339 0.1191920 0.9503041))
               '(0.95047 1.0 1.08883)))
         (values (mapcar (lambda (value)
                           (if (> value (expt (/ 6.0 29) 3)) (expt value (/ 1.0 3))
                             (+ (/ value (* 3 (expt (/ 6.0 29) 2))) (/ 4.0 29)))) xyz)))
    (list (- (* 116 (nth 1 values)) 16)
          (* 500 (- (nth 0 values) (nth 1 values)))
          (* 200 (- (nth 1 values) (nth 2 values))))))

(ert-deftest landscape-light-syntax-separation ()
  ;; Five main syntax roles, ten comparisons per light variant: 90 pairs.
  (let ((count 0))
    (dolist (entry landscape-palettes)
      (when (string-suffix-p "-light" (symbol-name (car entry)))
        (let ((roles '(:keyword :function :string :type :constant)) distances)
          (while roles
            (let ((one (landscape-test-lab (plist-get (cdr entry) (pop roles)))))
              (dolist (role roles)
                (let ((two (landscape-test-lab (plist-get (cdr entry) role))))
                  (push (sqrt (apply #'+ (cl-mapcar
                                         (lambda (a b) (expt (- a b) 2)) one two))) distances)
                  (cl-incf count)))))
          (should (>= (apply #'min distances) 30.0))
          (princ (format "\n%-17s min syntax Delta E76 %.4f"
                         (car entry) (apply #'min distances))))))
    (should (= count 90))))

(ert-deftest landscape-regional-identity ()
  ;; Prevent a return to one parchment base and one keyword family everywhere.
  (require 'color)
  (should (= 18 (length (delete-dups
                         (mapcar (lambda (entry) (plist-get (cdr entry) :bg))
                                 landscape-palettes)))))
  (let (keyword-hues)
    (dolist (entry landscape-palettes)
      (when (string-suffix-p "-light" (symbol-name (car entry)))
        (push (floor (* 6 (car (apply #'color-rgb-to-hsl
                                     (landscape-test-rgb (plist-get (cdr entry) :keyword))))))
              keyword-hues)))
    (should (>= (length (delete-dups keyword-hues)) 5)))
  ;; Both Provence backgrounds retain an actual lavender cast, not just accents.
  (dolist (variant '(provence-light provence-dark))
    (let ((rgb (landscape-test-rgb (plist-get (cdr (assq variant landscape-palettes)) :bg))))
      (should (> (nth 2 rgb) (nth 0 rgb)))
      (should (> (nth 0 rgb) (nth 1 rgb)))))
  ;; Iceland's lichen green must remain prominent on keywords and UI surfaces.
  (dolist (variant '(iceland-light iceland-dark))
    (let ((palette (cdr (assq variant landscape-palettes))))
      (dolist (role '(:keyword :accent :line :selection-bg))
        (let ((rgb (landscape-test-rgb (plist-get palette role))))
          (should (> (nth 1 rgb) (nth 0 rgb)))
          (should (> (nth 1 rgb) (nth 2 rgb))))))))

(ert-deftest landscape-palette-contrast ()
  (let ((count 0))
    (dolist (entry landscape-palettes)
      (let ((palette (cdr entry)) ratios normal)
        (dolist (surface '(:bg :bg-alt :line))
          (dolist (role '(:fg :keyword :function :string :type :constant :comment
                              :error :warning :success :info))
            (let ((ratio (landscape-test-contrast (plist-get palette role)
                                                  (plist-get palette surface))))
              (push ratio ratios) (cl-incf count)
              (should (>= ratio 4.8))
              (when (eq role :fg) (push ratio normal) (should (>= ratio 7.0))))))
        (dolist (prefix '(selection search search-current added removed changed))
          (let ((ratio (landscape-test-contrast
                        (plist-get palette (intern (format ":%s-fg" prefix)))
                        (plist-get palette (intern (format ":%s-bg" prefix))))))
            (push ratio ratios) (cl-incf count) (should (>= ratio 4.8))))
        (princ (format "\n%-17s 39 pairs; min %.4f; main %.4f"
                       (car entry) (apply #'min ratios) (apply #'min normal)))))
    (should (= count 702))))

(ert-deftest landscape-discovery-load-and-switch ()
  (should (= 18 (length landscape-palettes)))
  (dolist (entry (append landscape-palettes (reverse landscape-palettes)))
    (let ((theme (intern (format "custom-landscape-%s" (car entry)))) (palette (cdr entry)))
      (should (memq theme (custom-available-themes)))
      (landscape-test-select theme)
      (should (equal custom-enabled-themes (list theme)))
      (should (equal (plist-get (landscape-test-spec theme 'default) :background)
                     (plist-get palette :bg)))
      (dotimes (n 9)
        (let ((neutral (doom-color (intern (format "base%d" n)))))
          (if (< n 4)
              (should (>= (landscape-test-contrast neutral (plist-get palette :fg)) 4.5))
            (dolist (surface '(:bg :bg-alt :line))
              (should (>= (landscape-test-contrast neutral (plist-get palette surface)) 4.5))))))
      (dolist (mapping landscape-test-role-faces)
        (should (equal (plist-get (landscape-test-spec theme (car mapping)) :foreground)
                       (plist-get palette (cdr mapping)))))
      (dolist (face '(org-level-1 org-level-8 org-table org-block))
        (should-not (plist-member (landscape-test-spec theme face) :height))
        (should-not (plist-member (landscape-test-spec theme face) :family)))
      (should (eq (cdr (assoc "readonly" lsp-semantic-token-modifier-faces))
                  'lsp-face-semhl-static))))
  (landscape-test-select 'doom-gruvbox-light)
  (should (equal custom-enabled-themes '(doom-gruvbox-light))))

(ert-deftest landscape-late-packages-and-restoration ()
  ;; Only package definitions; no servers, remote connections or personal Org.
  (landscape-test-select 'doom-gruvbox-light)
  (require 'lsp-semantic-tokens)
  (let ((before (copy-tree (default-value 'lsp-semantic-token-modifier-faces)))
        (hooks (copy-tree enable-theme-functions)))
    (landscape-test-select 'custom-landscape-iceland-dark)
    (dolist (library '(corfu vertico orderless marginalia which-key doom-modeline
			     solaire-mode diff-hl magit-diff org org-agenda org-modern
			     org-roam citar lsp-ui-doc lsp-ui-sideline ghostel-faces))
      (when (locate-library (symbol-name library)) (require library)))
    (should (equal hooks enable-theme-functions))
    (should (eq (face-attribute 'lsp-face-semhl-deprecated :strike-through) t))
    (landscape-test-select 'doom-gruvbox-light)
    (should (equal before (default-value 'lsp-semantic-token-modifier-faces)))))

(ert-deftest landscape-highlights-and-ansi ()
  (dolist (entry landscape-palettes)
    (let* ((theme (intern (format "custom-landscape-%s" (car entry))))
           (palette (cdr entry)))
      (landscape-test-select theme)
      (dolist (mapping '((region selection) (vertico-current selection)
                         (corfu-current selection) (isearch search-current)
                         (lazy-highlight search) (magit-diff-added added)
                         (magit-diff-removed removed) (ediff-current-diff-C changed)))
        (let ((attrs (landscape-test-spec theme (car mapping))) (prefix (cadr mapping)))
          (should (equal (plist-get attrs :foreground)
                         (plist-get palette (intern (format ":%s-fg" prefix)))))
          (should (equal (plist-get attrs :background)
                         (plist-get palette (intern (format ":%s-bg" prefix)))))))
      (dotimes (n 4)
        (let ((attrs (landscape-test-spec theme (intern (format "orderless-match-face-%d" n)))))
          (should (eq (plist-get attrs :foreground) 'unspecified))
          (should (eq (plist-get attrs :background) 'unspecified))))
      (dolist (name '(black red green yellow blue magenta cyan white))
        (dolist (bright '(nil t))
          (let* ((face (intern (format "ansi-color-%s%s" (if bright "bright-" "") name)))
                 (color (plist-get (landscape-test-spec theme face) :foreground)))
            (dolist (surface '(:bg :bg-alt :line))
              (should (>= (landscape-test-contrast color (plist-get palette surface)) 4.5)))))))))

(ert-deftest landscape-synthetic-fontification ()
  (dolist (palette landscape-palettes)
    (landscape-test-select (intern (format "custom-landscape-%s" (car palette))))
    (dolist (entry '(("sample.py" python-mode) ("sample.go" go-mode)
                     ("sample.el" emacs-lisp-mode) ("sample.json" js-json-mode)
                     ("sample.toml" conf-toml-mode) ("sample.yaml" yaml-mode)
                     ("sample.md" markdown-mode) ("sample.org" org-mode)))
      (with-temp-buffer
	(insert-file-contents (expand-file-name (concat "samples/" (car entry)) landscape-test-directory))
	(let ((mode (cadr entry)))
          (unless (fboundp mode)
            (require (pcase mode ('go-mode 'go-mode) ('js-json-mode 'js)
                            ('conf-toml-mode 'conf-mode) (_ mode))))
          (delay-mode-hooks (funcall mode)) (font-lock-ensure)
          (let ((found nil))
            (dotimes (n (buffer-size))
              (when (get-text-property (1+ n) 'face) (setq found t)))
            (should found)))))))

(ert-deftest landscape-byte-compiled-entry-points ()
  (require 'bytecomp)
  (let ((directory (make-temp-file "landscape-compile-" t)))
    (unwind-protect
        (progn
          (dolist (file (directory-files landscape-test-root t "\\.el\\'"))
            (copy-file file (expand-file-name (file-name-nondirectory file) directory)))
          (let ((load-path (cons directory load-path))
                (custom-theme-load-path (cons directory custom-theme-load-path))
                (byte-compile-error-on-warn t))
            (dolist (file (directory-files directory t "\\.el\\'"))
              (if (string-suffix-p "-theme.el" file)
                  ;; Like installed Doom themes, entry points remain source:
                  ;; the framework's expanded face list exceeds Emacs 29's
                  ;; bytecode limit. Shared implementation is compiled below.
                  (with-temp-buffer
                    (insert-file-contents file)
                    (should (search-forward "no-byte-compile: t" nil t)))
                (should (byte-compile-file file))))
            (dolist (entry landscape-palettes)
              (let ((theme (intern (format "custom-landscape-%s" (car entry)))))
                (landscape-test-select theme)
                (should (file-exists-p (expand-file-name (format "%s-theme.el" theme) directory)))))))
      (delete-directory directory t))))

(ert-deftest landscape-installed-treesit ()
  (require 'treesit)
  (let ((directory (getenv "LANDSCAPE_TREE_SITTER_DIR")) (tested 0))
    (when directory (add-to-list 'treesit-extra-load-path directory))
    (dolist (entry '((python python-ts-mode "sample.py")
                     (json json-ts-mode "sample.json") (go go-ts-mode "sample.go")
                     (toml toml-ts-mode "sample.toml") (yaml yaml-ts-mode "sample.yaml")))
      (if (treesit-language-available-p (car entry))
          (with-temp-buffer
            (insert-file-contents (expand-file-name (concat "samples/" (nth 2 entry)) landscape-test-directory))
            (delay-mode-hooks (funcall (cadr entry)))
            (font-lock-ensure)
            (should (treesit-parser-list))
            (cl-incf tested)
            (princ (format "\nTree-sitter exercised: %s" (car entry))))
        (princ (format "\nTree-sitter unavailable, not run: %s" (car entry)))))
    (when (= tested 0) (ert-skip "No installed grammars found"))))

(ert-deftest landscape-python-role-classification ()
  (require 'python)
  (require 'treesit)
  (when-let ((directory (getenv "LANDSCAPE_TREE_SITTER_DIR")))
    (add-to-list 'treesit-extra-load-path directory))
  (unless (treesit-language-available-p 'python)
    (ert-skip "Installed Python grammar unavailable"))
  (dolist (mode '(python-mode python-ts-mode))
    (with-temp-buffer
      (insert-file-contents
       (expand-file-name "samples/python-highlighting.py" landscape-test-directory))
      (let ((treesit-font-lock-level 4)) (delay-mode-hooks (funcall mode)))
      (font-lock-ensure)
      (dolist (probe
               (append
                '(("class State" 0 font-lock-keyword-face)
                  ("class Landscape" 6 font-lock-type-face)
                  ("def describe" 4 font-lock-function-name-face)
                  ("Module documentation" 0 font-lock-doc-face)
                  ("Method documentation" 0 font-lock-doc-face)
                  ("A real comment" 0 font-lock-comment-face)
                  ("len(prefix)" 0 font-lock-builtin-face)
                  ("FLAG = True" 7 font-lock-constant-face)
                  ("EMPTY = None" 8 font-lock-constant-face)
                  ("Provence" 0 font-lock-string-face))
                (when (eq mode 'python-ts-mode)
                  '(("State(Enum)" 6 font-lock-type-face)
                    ("name: str" 6 font-lock-type-face)
                    ("count = 12.5" 8 font-lock-number-face)
                    ("self.name" 5 font-lock-property-use-face)
                    ("region.describe" 7 font-lock-function-call-face)
                    ("tab\\tend" 3 font-lock-escape-face)))))
        (goto-char (point-min))
        (search-forward (car probe))
        (let* ((position (+ (- (point) (length (car probe))) (nth 1 probe)))
               (actual (get-text-property position 'face)))
          (should (if (listp actual) (memq (nth 2 probe) actual)
                    (eq (nth 2 probe) actual))))))))

(ert-deftest landscape-semantic-token-composition ()
  (require 'lsp-semantic-tokens)
  (landscape-test-select 'custom-landscape-iceland-dark)
  ;; Exercise the actual lsp-mode token fontifier with a synthetic response;
  ;; this tests composition, not a live language server's classifications.
  (dolist (base '(lsp-face-semhl-variable lsp-face-semhl-function lsp-face-semhl-type))
    (with-temp-buffer
      (insert "value")
      (setq-local lsp--cur-version 1)
      (setq-local semantic-token-modifier-cache (make-hash-table))
      (setq-local lsp--buffer-workspaces
                  (list (make-lsp--workspace
                         :semantic-tokens-faces (vector base)
                         :semantic-tokens-modifier-faces
                         [lsp-face-semhl-static lsp-face-semhl-deprecated])))
      (let ((response (if lsp-use-plists '(:data [0 0 5 0 3])
                        (let ((table (make-hash-table :test #'equal)))
                          (puthash "data" [0 0 5 0 3] table) table))))
        (setq-local lsp--semantic-tokens-cache (list :response response :_documentVersion 1)))
      (goto-char (point-min))
      (lsp--semantic-tokens-fontify (point-max))
      (let ((faces (get-text-property 1 'face)))
        (should (memq base faces))
        (should (memq 'lsp-face-semhl-static faces))
        (should (memq 'lsp-face-semhl-deprecated faces))
        (should-not (memq 'lsp-face-semhl-constant faces))))))

(ert-deftest landscape-real-agenda-and-magit-diff ()
  (require 'org-agenda)
  (require 'magit-diff)
  (landscape-test-select 'custom-landscape-provence-light)
  (let* ((fixture (expand-file-name "samples/sample.org" landscape-test-directory))
         (org-agenda-files (list fixture))
         (org-agenda-buffer-name "*Landscape synthetic agenda*")
         (org-agenda-window-setup 'current-window))
    (unwind-protect
        (progn
          (org-agenda-list nil "2026-11-02" 1)
          (with-current-buffer org-agenda-buffer-name
            (goto-char (point-min)) (should (search-forward "Landscape" nil t))))
      (when (get-buffer org-agenda-buffer-name) (kill-buffer org-agenda-buffer-name))
      (when (find-buffer-visiting fixture) (kill-buffer (find-buffer-visiting fixture)))))
  (let* ((directory (file-name-as-directory (make-temp-file "landscape-git-" t)))
         (file (expand-file-name "sample.txt" directory))
         (default-directory directory))
    (unwind-protect
        (progn
          (should (= 0 (call-process "git" nil nil nil "-c" "core.hooksPath=/dev/null" "init" "--quiet" directory)))
          (with-temp-file file (insert "old text\n"))
          (should (= 0 (call-process "git" nil nil nil "add" "--" "sample.txt")))
          (with-temp-file file (insert "new text\n"))
          (let ((buffer (magit-diff-unstaged '("--no-ext-diff") nil)))
            (with-current-buffer buffer
              (font-lock-ensure)
              (goto-char (point-min))
              (should (search-forward "+new text" nil t)))))
      (dolist (buffer (buffer-list))
        (when (and (buffer-live-p buffer)
                   (string-prefix-p directory (buffer-local-value 'default-directory buffer)))
          (kill-buffer buffer)))
      (delete-directory directory t))))

(ert-deftest landscape-existing-lsp-caches ()
  (require 'lsp-semantic-tokens)
  (let* ((before (default-value 'lsp-semantic-token-modifier-faces))
         (buffer (generate-new-buffer " *Landscape LSP cache fixture*"))
         (workspace
          (make-lsp--workspace
           :client (make-lsp-client :server-id 'landscape-test)
           :server-capabilities
           (lsp-make-server-capabilities
            :semanticTokensProvider
            (lsp-make-semantic-tokens-options
             :legend (lsp-make-semantic-tokens-legend
                      :tokenTypes ["variable"] :tokenModifiers ["readonly"])))
           :semantic-tokens-faces [lsp-face-semhl-variable]
           :semantic-tokens-modifier-faces [lsp-face-semhl-constant]))
         (watchers (length (get-variable-watchers 'lsp-semantic-token-modifier-faces))))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq-local lsp--buffer-workspaces (list workspace))
            (setq-local semantic-token-modifier-cache (make-hash-table))
            (puthash 1 '(lsp-face-semhl-constant) semantic-token-modifier-cache))
          ;; This uses the actual cache builder and a synthetic server legend.
          ;; The workspace has no process or network connection.
          (set-default 'lsp-semantic-token-modifier-faces
                       '(("readonly" . lsp-face-semhl-static)))
          (should (equal (lsp--workspace-semantic-tokens-modifier-faces workspace)
                         [lsp-face-semhl-static]))
          (should (= 0 (hash-table-count (buffer-local-value 'semantic-token-modifier-cache buffer))))
          (set-default 'lsp-semantic-token-modifier-faces before)
          (should (equal (lsp--workspace-semantic-tokens-modifier-faces workspace)
                         (vector (cdr (assoc "readonly" before)))))
          (load (expand-file-name "landscape-packages.el" landscape-test-root) nil t)
          (should (= watchers (length (get-variable-watchers 'lsp-semantic-token-modifier-faces)))))
      (kill-buffer buffer)
      (set-default 'lsp-semantic-token-modifier-faces before))))

(defun landscape-test-terminal ()
  "Load all themes and render a 16-color specimen in an isolated TTY."
  (condition-case err
      (progn
        (require 'ansi-color)
        (when (display-graphic-p) (error "Expected a terminal display"))
        (switch-to-buffer (get-buffer-create "*Landscape ANSI specimen*"))
        (dolist (entry landscape-palettes)
          (landscape-test-select (intern (format "custom-landscape-%s" (car entry))))
          (erase-buffer)
          (insert (format "Landscape %s: ANSI foreground slots\n" (car entry)))
          (dolist (code '(30 31 32 33 34 35 36 37 90 91 92 93 94 95 96 97))
            (insert (ansi-color-apply (format "\e[%dm %d text \e[0m" code code))))
          (redisplay t))
        (with-temp-file (getenv "LANDSCAPE_TTY_RESULT")
          (insert (format "PASS: 18 themes; terminal=%s; color cells=%s\n"
                          (getenv "TERM") (display-color-cells))))
        (kill-emacs 0))
    (error
     (with-temp-file (getenv "LANDSCAPE_TTY_RESULT") (insert (error-message-string err)))
     (kill-emacs 1))))

(defun landscape-test-capture (theme)
  "Capture actual GUI rendering of synthetic samples for THEME.
Requires the Mac port's native frame exporter. No image generation is used."
  (when-let ((directory (getenv "LANDSCAPE_CAPTURE_DIR")))
    (when (fboundp 'mac-export-frames)
      (delete-other-windows)
      (set-frame-size nil 150 44)
      (let ((python (get-buffer-create "*Landscape Python specimen*"))
            (org (get-buffer-create "*Landscape Org specimen*")))
        (with-current-buffer python
          (remove-overlays)
          (erase-buffer)
          (insert-file-contents (expand-file-name "samples/sample.py" landscape-test-directory))
          (delay-mode-hooks (python-mode))
          (goto-char (point-max))
          (insert "\n# Synthetic diagnostic display (no checker/server started)\n")
          (dolist (kind '(error warning info))
            (let ((start (point)))
              (insert (format "%s_example = 1\n" kind))
              (let ((overlay (make-overlay start (+ start (length (symbol-name kind)) 8))))
                (overlay-put overlay 'face (intern (format "flycheck-%s" kind)))
                (overlay-put overlay 'help-echo "Synthetic diagnostic specimen"))))
          (font-lock-ensure)
          (setq-local display-line-numbers 'relative)
          (hl-line-mode 1)
          (goto-char (point-min)) (forward-line 9))
        (with-current-buffer org
          (erase-buffer)
          (insert-file-contents (expand-file-name "samples/sample.org" landscape-test-directory))
          (delay-mode-hooks (org-mode))
          (setq-local org-src-fontify-natively t
                      org-todo-keyword-faces '(("STRT" . +org-todo-active)
                                              ("WAIT" . +org-todo-onhold)
                                              ("PROJ" . +org-todo-project)
                                              ("KILL" . +org-todo-cancel)))
          (when (locate-library "org-modern")
            (require 'org-modern)
            (setq-local org-modern-todo-faces
                        '(("STRT" :inverse-video t :inherit +org-todo-active)
                          ("WAIT" :inverse-video t :inherit +org-todo-onhold)
                          ("PROJ" :inverse-video t :inherit +org-todo-project)
                          ("KILL" :inverse-video t :inherit +org-todo-cancel)))
            (org-modern-mode 1))
          (org-show-all)
          (when (locate-library "mixed-pitch") (require 'mixed-pitch) (mixed-pitch-mode 1))
          (font-lock-flush) (font-lock-ensure)
          (goto-char (point-min)))
        (switch-to-buffer python)
        (set-window-buffer (split-window-right) org)
        (redisplay t)
        (make-directory directory t)
        (let ((coding-system-for-write 'binary))
          (write-region (mac-export-frames nil 'png) nil
                        (expand-file-name (format "%s.png" theme) directory) nil 'silent))))))

(defun landscape-test-gui ()
  "Check effective GUI attributes in an isolated Emacs, then exit."
  (condition-case err
      (progn
        (unless (display-graphic-p) (error "A graphical display is required"))
        (dolist (library '(org org-indent org-agenda org-roam-mode org-modern citar corfu vertico orderless
                               lsp-semantic-tokens ghostel-faces diff-hl magit-diff markdown-mode
                               smerge-mode ediff-init treemacs-faces flycheck flymake hl-line tab-line cus-edit evil))
          (require library))
        (dolist (entry landscape-palettes)
          (let ((theme (intern (format "custom-landscape-%s" (car entry)))) (palette (cdr entry)))
            (landscape-test-select theme)
            (redisplay t)
            (dolist (mapping landscape-test-role-faces)
              (unless (equal (upcase (face-attribute (car mapping) :foreground nil t))
                             (plist-get palette (cdr mapping)))
                (error "Effective face mismatch %s %s" theme (car mapping))))
            (dolist (face '(default shadow line-number mode-line-inactive org-tag org-block-begin-line))
              (let ((color (face-attribute face :foreground nil t)))
                (when (string-match-p "^#" color)
                  (dolist (surface '(:bg :bg-alt :line))
                    (unless (>= (landscape-test-contrast color (plist-get palette surface)) 4.5)
                      (error "Effective contrast failed %s %s" theme face))))))))
        ;; Read back the active installed faces, not just nominal palette data.
        (dolist (entry landscape-palettes)
          (let ((theme (intern (format "custom-landscape-%s" (car entry))))
                (palette (cdr entry)))
            (landscape-test-select theme)
            (dolist (form (landscape--faces))
              (let* ((face (if (listp (car form)) (caar form) (car form)))
                     (fg (and (facep face) (face-attribute face :foreground nil t)))
                     (bg (and (facep face) (face-attribute face :background nil t))))
                ;; ANSI faces intentionally use equal foreground/background
                ;; as color slots; invisible Org indentation is also exempt.
                (unless (or (string-match-p "\\`\\(?:ansi-color\\|term-color\\|vterm-color\\)-" (symbol-name face))
                            (memq face '(org-hide org-indent solaire-org-hide-face
						  cursor vertical-border window-divider
						  window-divider-first-pixel window-divider-last-pixel)))
                  (when (and (stringp fg) (string-prefix-p "#" fg))
                    (unless (and (stringp bg) (string-prefix-p "#" bg))
                      (setq bg (plist-get palette :bg)))
                    (unless (>= (landscape-test-contrast fg bg) 4.5)
                      (error "Effective package contrast: %s %s %s/%s" theme face fg bg))))))))
        (when (getenv "LANDSCAPE_CAPTURE_DIR")
          (dolist (entry landscape-palettes)
            (let ((theme (intern (format "custom-landscape-%s" (car entry)))))
              (landscape-test-select theme)
              (landscape-test-capture theme))))
        (with-temp-file (getenv "LANDSCAPE_GUI_RESULT")
          (insert "PASS: effective GUI faces, 18 themes; GUI=" (format "%s" window-system) "\n"))
        (kill-emacs 0))
    (error
     (with-temp-file (getenv "LANDSCAPE_GUI_RESULT") (insert (error-message-string err)))
     (kill-emacs 1))))
