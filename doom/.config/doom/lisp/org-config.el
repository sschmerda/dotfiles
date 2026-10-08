;;; org-config.el -*- lexical-binding: t; -*-

;; Use visible-line relative numbers in Org so folded sections do not count hidden lines.
(add-hook! 'org-mode-hook
  (defun my/org-use-visual-line-numbers-h ()
    (setq-local display-line-numbers 'visual)))

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")

(after! org
  ;; Replace the former direct mixed-pitch toggle with a view menu.
  (map! :map org-mode-map :localleader "v" nil)
  (map! :map org-mode-map
        :localleader
        (:prefix ("v" . "view")
         :desc "Editing view" "e" #'my/org-editing-view
         :desc "Reading view" "r" #'my/org-reading-view
         :desc "Source view" "s" #'my/org-source-view
         :desc "Toggle mixed pitch" "m" #'mixed-pitch-mode
         :desc "Toggle markup at cursor" "h" #'my/org-toggle-markup-reveal
         :desc "Toggle read-only" "w" #'read-only-mode)))

;; Reveal the underlying markup at point, including full link destinations.
(after! org-appear
  ;; Each Org buffer needs its own element list: a temporary Org buffer may
  ;; otherwise rebuild the package's global list with emphasis hiding off.
  (make-variable-buffer-local 'org-appear-elements)
  (setq org-appear-trigger 'always
        org-appear-delay 0
        org-appear-autoemphasis t
        org-appear-autolinks t
        org-appear-autosubmarkers t
        org-appear-autoentities t
        org-appear-autokeywords t
        org-appear-inside-latex t))

;; Doom disables +org-pretty-mode after slides, rather than restoring hiding.
(defvar-local my/org-slide-display-settings nil)

(defun my/org-slide-restore-emphasis-a (original &rest args)
  "Preserve Org view settings across Doom's slide display changes."
  (when org-tree-slide-mode
    (setq my/org-slide-display-settings
          (list org-hide-emphasis-markers org-pretty-entities)))
  (prog1 (apply original args)
    (when (and (not org-tree-slide-mode) my/org-slide-display-settings)
      (setq-local org-hide-emphasis-markers (car my/org-slide-display-settings)
                  org-pretty-entities (cadr my/org-slide-display-settings))
      (setq my/org-slide-display-settings nil)
      (my/org-refresh-display))
    (when (bound-and-true-p org-appear-mode)
      (org-appear-mode 1))))

(advice-add '+org-present-prettify-slide-h :around
            #'my/org-slide-restore-emphasis-a)

;; Org Modern decorates block delimiters separately from org-appear's objects.
;; Refontify the old delimiter on departure and reveal the current one silently.
(defvar-local my/org-revealed-block-line nil)

(defun my/org-reveal-block-line-h ()
  "Show raw block delimiters on the cursor's line and restore them on leaving."
  (let ((line (line-beginning-position)))
    (when (and my/org-revealed-block-line
               (/= line (marker-position my/org-revealed-block-line)))
      (save-excursion
        (goto-char my/org-revealed-block-line)
        (font-lock-flush (line-beginning-position) (line-end-position))
        (font-lock-ensure (line-beginning-position) (line-end-position)))
      (set-marker my/org-revealed-block-line nil)
      (setq my/org-revealed-block-line nil))
    (when (and my/org-reveal-markup
               (bound-and-true-p org-modern-mode)
               (save-excursion
                 (goto-char line)
                 (let ((case-fold-search t))
                   (looking-at-p "[ \t]*#\\+\\(?:begin\\|end\\)_"))))
      (unless my/org-revealed-block-line
        (setq my/org-revealed-block-line (copy-marker line)))
      (font-lock-ensure line (line-end-position))
      (with-silent-modifications
        (remove-text-properties line (line-end-position)
                                '(display nil invisible nil composition nil))))))

;; Presets set fonts, decoration, cursor revealing and editability together.
;; Individual toggles can then adjust the current buffer independently.
(defvar-local my/org-display-view 'editing)
(defvar-local my/org-reveal-markup t)
(defvar-local my/org-pretty-hidden-keywords nil)
(defvar-local my/org-display-initialized nil)

(defun my/org-refresh-display ()
  "Refontify after changing display options without editing buffer contents."
  (when my/org-revealed-block-line
    (set-marker my/org-revealed-block-line nil)
    (setq my/org-revealed-block-line nil))
  (font-lock-flush)
  (font-lock-ensure)
  (when (bound-and-true-p org-appear-mode)
    (org-appear--post-cmd))
  (my/org-reveal-block-line-h))

(defun my/org-set-markup-reveal (enabled)
  "Set cursor-based revealing of hidden markup to ENABLED."
  (setq my/org-reveal-markup enabled)
  (org-appear-mode (if enabled 1 -1))
  (my/org-refresh-display))

(defun my/org-toggle-markup-reveal ()
  "Toggle revealing hidden Org markup at the text cursor."
  (interactive)
  (my/org-set-markup-reveal (not my/org-reveal-markup))
  (message "Markup at cursor: %s" (if my/org-reveal-markup "on" "off")))

(defun my/org-set-display-view (view)
  "Apply the editing, reading or source preset VIEW to this Org buffer."
  (unless my/org-display-initialized
    (setq my/org-pretty-hidden-keywords org-hidden-keywords
          my/org-display-initialized t))
  (let ((source (eq view 'source)))
    (setq my/org-display-view view)
    ;; SPC t v bypasses all invisibility, including hidden Org markup.
    ;; A preset must restore normal visibility before applying its policy.
    (visible-mode -1)
    (setq-local org-hide-emphasis-markers (not source)
                org-pretty-entities (not source)
                org-link-descriptive (not source)
                org-hide-leading-stars (not source)
                org-hidden-keywords (unless source my/org-pretty-hidden-keywords))
    (mixed-pitch-mode (if source -1 1))
    (org-modern-mode (if source -1 1))
    ;; Disable any additional symbol substitutions in the raw source view.
    (when source
      (prettify-symbols-mode -1)
      (org-remove-inline-images)
      (org-clear-latex-preview))
    (my/org-set-markup-reveal (eq view 'editing))
    (read-only-mode (if (eq view 'reading) 1 -1))))

(defun my/org-editing-view ()
  "Use mixed pitch and reveal markup at point, with editing enabled."
  (interactive)
  (my/org-set-display-view 'editing))

(defun my/org-reading-view ()
  "Use mixed pitch and hidden markup in a read-only buffer."
  (interactive)
  (my/org-set-display-view 'reading))

(defun my/org-source-view ()
  "Show raw Org markup in monospace, with editing enabled."
  (interactive)
  (my/org-set-display-view 'source))

(defun my/org-default-editing-view-h ()
  "Initialise Org's default view after Doom's display modes have started."
  (add-hook 'post-command-hook #'my/org-reveal-block-line-h t t)
  (my/org-editing-view))

(add-hook 'org-mode-hook #'my/org-default-editing-view-h t)
