;;; olivetti-config.el -*- lexical-binding: t; -*-

;; Toggle Olivetti buffer centering without hiding modelines or other windows.
(use-package! olivetti
  :commands (olivetti-mode my/olivetti-toggle-all)
  :init
  (setq olivetti-body-width 120)
  (defvar my-olivetti-enabled nil)
  (defvar-local my-olivetti-inhibit-centering nil
    "Non-nil to exclude this buffer from automatic centering.")
  (put 'my-olivetti-inhibit-centering 'permanent-local t)
  (defvar my-olivetti-inhibit-layout nil
    "Non-nil while workspace windows are being rebuilt.")
  (defun my--olivetti-treemacs-window-p (window)
    "Return non-nil for a left-hand Treemacs sidebar WINDOW."
    (and (eq (window-parameter window 'window-side) 'left)
         (with-current-buffer (window-buffer window)
           (derived-mode-p 'treemacs-mode))))
  (defun my--olivetti-buffer-eligible-p ()
    "Allow file, Dired and shell buffers, excluding internal and display buffers."
    (and (not (minibufferp))
         (not my-olivetti-inhibit-centering)
         (not (bound-and-true-p my-terminal-popup-buffer))
         (not (bound-and-true-p org-tree-slide-mode))
         (not (bound-and-true-p +popup-buffer-mode))
         (not (derived-mode-p 'pdf-view-mode 'my--time-popup-mode 'treemacs-mode))
         (not (string-prefix-p " " (buffer-name)))))
  (defun my--olivetti-enable-buffer (buffer)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (get-buffer-window buffer (selected-frame))
          (if (my--olivetti-buffer-eligible-p)
              (unless (bound-and-true-p olivetti-mode)
                (olivetti-mode 1))
            (my--olivetti-disable-buffer buffer))))))
  (defun my--olivetti-disable-buffer (buffer)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (bound-and-true-p olivetti-mode)
          (olivetti-mode -1)))))
  (defun my--olivetti-disable-all-buffers ()
    (mapc #'my--olivetti-disable-buffer (buffer-list)))
  (defun my--olivetti-refresh-visible-windows ()
    (walk-windows
     (lambda (window)
       (with-current-buffer (window-buffer window)
         (when (bound-and-true-p olivetti-mode)
           (olivetti-set-window window))))
     nil t))
  (defun my--olivetti-vertical-split-p (&optional frame)
    "Return non-nil for side-by-side windows other than left Treemacs."
    (let ((left-edges nil))
      (dolist (window (window-list frame 'no-minibuf))
        (unless (my--olivetti-treemacs-window-p window)
          (push (window-left-column window) left-edges)))
      (> (length (delete-dups left-edges)) 1)))
  (defun my--olivetti-refresh-h (&rest _)
    (when (and my-olivetti-enabled
               (not my-olivetti-inhibit-layout)
               (not (frame-parameter (selected-frame) 'my--time-popup))
               (not (frame-parameter (selected-frame) 'my--terminal-popup)))
      (if (my--olivetti-vertical-split-p)
          (my--olivetti-disable-all-buffers)
        (mapc #'my--olivetti-enable-buffer (buffer-list))
        (my--olivetti-refresh-visible-windows))))
  (defun my/olivetti-toggle-all ()
    (interactive)
    (setq my-olivetti-enabled (not my-olivetti-enabled))
    (if my-olivetti-enabled
        (my--olivetti-refresh-h)
      (my--olivetti-disable-all-buffers)))
  (map! :leader
        :desc "Center buffers"
        "t o" #'my/olivetti-toggle-all)
  (add-hook 'buffer-list-update-hook #'my--olivetti-refresh-h)
  (add-hook 'window-state-change-functions #'my--olivetti-refresh-h)
  ;; Popup windows keep their normal width, including SPC o t terminals.
  (add-hook '+popup-create-window-hook #'my--olivetti-refresh-h)
  (add-hook! 'doom-first-buffer-hook
    (defun my--olivetti-enable-on-startup-h ()
      (setq my-olivetti-enabled t)
      (my--olivetti-refresh-h)))
  :config
  (defvar-local my-olivetti-original-gutter-bitmap-function nil)
  (defun my--olivetti-define-gutter-bar-h (&rest _)
    "Match Doom's normal bar width and continue the border on changed lines."
    (when (display-graphic-p)
      (let* ((width (min (or (frame-parameter nil 'left-fringe) 8)
                         diff-hl-bmp-max-width))
             (bar-width (max 1 (1- (/ width 2))))
             (scale (if (boundp 'text-scale-mode-amount)
                        (expt text-scale-mode-step text-scale-mode-amount) 1))
             (spacing (or (default-value 'line-spacing) 0))
             (spacing (if (consp spacing) (+ (car spacing) (cdr spacing)) spacing))
             (height (+ (ceiling (* (frame-char-height) scale))
                        (if (floatp spacing)
                            (truncate (* (frame-char-height) spacing)) spacing)))
             ;; A user fringe bitmap clears its background, including our
             ;; stippled stripe. Continue the stripe with a bitmap pixel;
             ;; it takes the Git colour on these lines. Leave one blank pixel
             ;; between that stripe and the normal three-pixel Git bar.
             (row (logior (ash 1 (1- width))
                          (ash (1- (ash 1 bar-width))
                               (max 0 (- width bar-width 2))))))
        (define-fringe-bitmap 'my--olivetti-gutter-bar
          (make-vector height row) height width 'center)
        ;; Keep the deletion minus to the right of the same one-pixel gap.
        ;; Its bitmap also continues the border through this display row.
        (let* ((border (ash 1 (1- width)))
               (minus (1- (ash 1 (max 1 (- width 2)))))
               (rows (make-vector height border))
               (middle (max 0 (1- (/ height 2)))))
          (aset rows middle (logior border minus))
          (when (< (1+ middle) height)
            (aset rows (1+ middle) (logior border minus)))
          (define-fringe-bitmap 'my--olivetti-gutter-delete
            rows height width 'center)))))
  (defun my--olivetti-gutter-bitmap (type _position)
    "Select Git markers separated from the border by one pixel."
    (if (eq type 'delete)
        'my--olivetti-gutter-delete
      'my--olivetti-gutter-bar))
  (defun my--olivetti-sync-gutter-bitmap-h ()
    "Use the inset Git bar only in centred buffers."
    (when (bound-and-true-p diff-hl-mode)
      (cond
       ((and olivetti-mode (not my-olivetti-original-gutter-bitmap-function))
        (my--olivetti-define-gutter-bar-h)
        (setq my-olivetti-original-gutter-bitmap-function diff-hl-fringe-bmp-function)
        (setq-local diff-hl-fringe-bmp-function #'my--olivetti-gutter-bitmap)
        (diff-hl-update))
       ((and (not olivetti-mode) my-olivetti-original-gutter-bitmap-function)
        (setq-local diff-hl-fringe-bmp-function my-olivetti-original-gutter-bitmap-function)
        (setq my-olivetti-original-gutter-bitmap-function nil)
        (diff-hl-update)))))
  (after! diff-hl
    (advice-add 'diff-hl-define-bitmaps :after #'my--olivetti-define-gutter-bar-h))
  (add-hook 'olivetti-mode-hook #'my--olivetti-sync-gutter-bitmap-h)
  (add-hook 'diff-hl-mode-on-hook #'my--olivetti-sync-gutter-bitmap-h)
  (defvar-local my-olivetti-original-fringe-indicators nil)
  (defun my--olivetti-empty-line-bitmap (width height &optional border-p final-line-p)
    "Return a WIDTH by HEIGHT EOF bitmap, with a border when BORDER-P.
When FINAL-LINE-P, omit the tilde on the actual final, editable buffer line."
    (setq width (max 3 (min 16 width))
          height (max 2 height))
    (let ((bitmap (intern (format "my--olivetti-%s-%s-%dx%d"
                                  (if final-line-p "final-line" "empty-line")
                                  (if border-p "border" "plain") width height))))
      (unless (fringe-bitmap-p bitmap)
        (let* ((border (if border-p (ash 1 (1- width)) 0))
               (rows (make-vector height border))
               (mask (1- (ash 1 (- width 2))))
               (middle (1- (/ height 2))))
          ;; Reserve the outer pixel for the border and the next for a gap.
          (unless final-line-p
            (aset rows middle (logior border (logand #b011001 mask)))
            (aset rows (1+ middle) (logior border (logand #b100110 mask))))
          (define-fringe-bitmap bitmap rows height width '(center t))
          (set-fringe-bitmap-face bitmap 'fringe)))
      bitmap))
  (defvar-local my-olivetti-final-line-overlay nil)
  (defvar-local my-olivetti-final-line-display nil)
  (defun my--olivetti-update-final-line-marker-h (&rest _)
    "Keep the actual final empty line free of EOF tildes after edits.
Only an overlay moves; buffer text, undo history and point remain untouched."
    (if (and indicate-empty-lines my-olivetti-final-line-display
             (or (= (point-min) (point-max)) (eq (char-before (point-max)) ?\n)))
        (progn
          (unless (overlayp my-olivetti-final-line-overlay)
            (setq my-olivetti-final-line-overlay (make-overlay (point-max) (point-max)))
            ;; Give unrelated Git/debugger overlays precedence.
            (overlay-put my-olivetti-final-line-overlay 'priority -50))
          (move-overlay my-olivetti-final-line-overlay (point-max) (point-max))
          (overlay-put my-olivetti-final-line-overlay 'before-string
                       (propertize " " 'display my-olivetti-final-line-display)))
      (when (overlayp my-olivetti-final-line-overlay)
        (delete-overlay my-olivetti-final-line-overlay)
        (setq my-olivetti-final-line-overlay nil))))
  (defun my--olivetti-clear-final-line-marker-h ()
    "Remove the final-line overlay before local state is reset."
    (when (overlayp my-olivetti-final-line-overlay)
      (delete-overlay my-olivetti-final-line-overlay))
    (setq my-olivetti-final-line-overlay nil
          my-olivetti-final-line-display nil)
    (remove-hook 'after-change-functions #'my--olivetti-update-final-line-marker-h t)
    (remove-hook 'change-major-mode-hook #'my--olivetti-clear-final-line-marker-h t))
  (defun my--olivetti-sync-empty-line-indicator (window enabled)
    "Use tildes in WINDOW, including its centering border only when ENABLED.
A plain tilde remains installed when centering is disabled. Terminal frames
have no graphical fringe and retain their original indicator mapping."
    (if (display-graphic-p (window-frame window))
        (let* ((frame (window-frame window))
               (scale (if (boundp 'text-scale-mode-amount)
                          (expt text-scale-mode-step text-scale-mode-amount) 1))
               (spacing (or line-spacing 0))
               (spacing (if (consp spacing) (+ (car spacing) (cdr spacing)) spacing))
               (height (+ (ceiling (* (frame-char-height frame) scale))
                          (if (floatp spacing)
                              (truncate (* (frame-char-height frame) spacing)) spacing)))
               (bitmap (my--olivetti-empty-line-bitmap
                        (car (window-fringes window)) height enabled)))
          (setq my-olivetti-final-line-display
                (list (if (or (eq indicate-empty-lines 'right)
                              (zerop (car (window-fringes window))))
                          'right-fringe 'left-fringe)
                      (my--olivetti-empty-line-bitmap
                       (car (window-fringes window)) height enabled t)
                      'fringe))
          (add-hook 'change-major-mode-hook #'my--olivetti-clear-final-line-marker-h nil t)
          (add-hook 'after-change-functions #'my--olivetti-update-final-line-marker-h nil t)
          (my--olivetti-update-final-line-marker-h)
          (unless my-olivetti-original-fringe-indicators
            (setq my-olivetti-original-fringe-indicators
                  (list (local-variable-p 'fringe-indicator-alist)
                        fringe-indicator-alist)))
          (unless (eq (cdr (assq 'empty-line fringe-indicator-alist)) bitmap)
            (setq-local fringe-indicator-alist
                        (cons (cons 'empty-line bitmap)
                              (assq-delete-all 'empty-line
                                               (copy-tree fringe-indicator-alist))))))
      (my--olivetti-clear-final-line-marker-h)
      (when my-olivetti-original-fringe-indicators
        (if (car my-olivetti-original-fringe-indicators)
            (setq-local fringe-indicator-alist
                        (cadr my-olivetti-original-fringe-indicators))
          (kill-local-variable 'fringe-indicator-alist))
        (setq my-olivetti-original-fringe-indicators nil))))
  (defun my--olivetti-clear-fringe-border (window)
    "Remove WINDOW's local patterned fringe face."
    (when-let ((entry (window-parameter window 'my--olivetti-fringe-face)))
      (when (buffer-live-p (car entry))
        (with-current-buffer (car entry)
          (face-remap-remove-relative (cdr entry)))))
    (set-window-parameter window 'my--olivetti-fringe-face nil)
    (set-window-parameter window 'my--olivetti-fringe-state nil))
  (defun my--olivetti-fringe-border-live-p (window)
    "Return non-nil if WINDOW's cached border still has its face remapping."
    (when-let ((entry (window-parameter window 'my--olivetti-fringe-face)))
      (and (eq (car entry) (window-buffer window))
           (with-current-buffer (car entry)
             (let* ((spec (cddr entry))
                    (faces (cdr (assq 'fringe face-remapping-alist))))
               (and (listp faces)
                    (memq spec faces)
                    (eq (nth 2 (nth 1 spec))
                        (window-parameter window 'my--olivetti-fringe-token))))))))
  (defun my--olivetti-pattern-fringes (window)
    "Paint one-pixel outer stripes without reducing the Git gutter width."
    (when (and (window-live-p window)
               (not (frame-parameter (window-frame window) 'my--terminal-popup)))
      (with-current-buffer (window-buffer window)
        (let* ((frame (window-frame window))
               (backend (window-system frame))
               ;; NS and older PGTK builds do not render stipples reliably.
               (supported (or (memq backend '(mac x))
                              (and (eq backend 'pgtk) (>= emacs-major-version 30)))))
          (my--olivetti-sync-empty-line-indicator
           window (and (bound-and-true-p olivetti-mode) supported))
          (if (not (and (bound-and-true-p olivetti-mode) supported))
              (my--olivetti-clear-fringe-border window)
            (let* ((edges (window-inside-pixel-edges window))
                   (fringes (window-fringes window))
                   (width (frame-pixel-width frame))
                   (left (- (car edges) (car fringes)))
                   (right (1- (+ (nth 2 edges) (cadr fringes))))
                   (background (face-attribute 'default :background frame t))
                   ;; Follow the theme, using the same face as split dividers.
                   (border (face-attribute 'shadow :foreground frame t))
                   (state (list (current-buffer) width left right background border)))
              (unless (and (equal state (window-parameter window 'my--olivetti-fringe-state))
                           (my--olivetti-fringe-border-live-p window))
                (my--olivetti-clear-fringe-border window)
                ;; Stipples are tiled from the frame origin, not the fringe origin.
                ;; A frame-wide tile gives each outer edge exactly one set pixel.
                (let ((bits (make-string (/ (+ width 7) 8) 0))
                      (token (make-symbol "olivetti-fringe")))
                  (dolist (pixel (list left right))
                    (when (and (>= pixel 0) (< pixel width))
                      (let ((byte (/ pixel 8)))
                        (aset bits byte (logior (aref bits byte)
                                               (ash 1 (% pixel 8)))))))
                  (set-window-parameter window 'my--olivetti-fringe-token token)
                  (set-window-parameter
                   window 'my--olivetti-fringe-face
                   (cons (current-buffer)
                         (face-remap-add-relative
                          'fringe
                          `(:filtered (:window my--olivetti-fringe-token ,token)
                            (:foreground ,border :background ,background
                             :stipple (,width 1 ,(string-make-unibyte bits)))))))
                  (set-window-parameter window 'my--olivetti-fringe-state state)))))))))
  (defun my--olivetti-update-fringe-borders-h (&rest _)
    "Refresh patterned borders when centering or the theme changes."
    (unless my-olivetti-inhibit-layout
      (dolist (frame (frame-list))
        (unless (or (frame-parameter frame 'my--time-popup)
                    (frame-parameter frame 'my--terminal-popup))
          (dolist (window (window-list frame 'no-minibuf))
            (my--olivetti-pattern-fringes window))))))
  (defun my--olivetti-fringe-after-layout-h (window-or-frame)
    "Keep the normal Git fringe inside the centering margins."
    (when (and (not my-olivetti-inhibit-layout)
               (window-live-p window-or-frame))
      (with-current-buffer (window-buffer window-or-frame)
        (when (bound-and-true-p olivetti-mode)
          (set-window-fringes window-or-frame nil nil nil)
          (my--olivetti-treemacs-margins window-or-frame)))
      (my--olivetti-pattern-fringes window-or-frame)))
  (defun my--olivetti-treemacs-margins (window)
    "Let a left Treemacs sidebar consume WINDOW's existing outer padding.
Calculate margins against the editing area including the sidebar footprint,
so cell rounding matches the original layout. If there isn't enough padding,
reduce the left margin to zero. Normal editing splits and non-Treemacs side
windows retain their existing behavior."
    (when (and my-olivetti-enabled
               (not my-olivetti-inhibit-layout)
               (not (my--olivetti-vertical-split-p (window-frame window)))
               (not (my--olivetti-treemacs-window-p window)))
      (when-let ((sidebar (cl-find-if #'my--olivetti-treemacs-window-p
                                    (window-list (window-frame window) 'no-minibuf))))
        (let* ((margins (window-margins window))
               (char-width (frame-char-width (window-frame window)))
               (footprint (- (car (window-pixel-edges window))
                             (car (window-pixel-edges sidebar))))
               (virtual-width (+ (window-body-width window t) footprint
                                 (* char-width (+ (or (car margins) 0)
                                                  (or (cdr margins) 0)))))
               (body-width (if (floatp olivetti-body-width)
                               (max (* char-width olivetti-minimum-body-width)
                                    (floor (* virtual-width (min 1.0 olivetti-body-width))))
                             (olivetti-normalize-width olivetti-body-width window)))
               (padding (/ (- virtual-width body-width) 2.0))
               (fringes (window-fringes window))
               (left (max 0 (round (/ (- padding (car fringes) footprint) char-width))))
               (right (max 0 (round (/ (- padding (cadr fringes)) char-width)))))
          (set-window-margins window left right)))))
  (advice-add 'olivetti-set-window :after #'my--olivetti-fringe-after-layout-h)
  (defun my--olivetti-slide-layout-a (original &rest args)
    "Suspend centering during slides and rebuild it after Doom restores Org."
    (let ((presenting (bound-and-true-p org-tree-slide-mode)))
      (when presenting
        (my--olivetti-disable-buffer (current-buffer)))
      (prog1 (apply original args)
        (unless presenting
          ;; Doom calls `org-mode', which can remove buffer-local remappings
          ;; while leaving the window's cached border coordinates unchanged.
          (dolist (window (get-buffer-window-list (current-buffer) nil t))
            (my--olivetti-clear-fringe-border window))
          (my--olivetti-refresh-h)
          (my--olivetti-update-fringe-borders-h)))))
  (advice-add '+org-present-prettify-slide-h :around #'my--olivetti-slide-layout-a)
  (defun my--olivetti-refresh-buffer-display-h ()
    "Restore visible buffer centering and markers after a major-mode change."
    (when (and (not my-olivetti-inhibit-layout)
               (get-buffer-window (current-buffer) t))
      (my--olivetti-refresh-h)
      (dolist (window (get-buffer-window-list (current-buffer) nil t))
        (my--olivetti-pattern-fringes window))))
  (add-hook 'after-change-major-mode-hook #'my--olivetti-refresh-buffer-display-h t)
  ;; Normal/split windows also need their EOF bitmap after layout and zoom changes.
  (add-hook 'window-state-change-functions #'my--olivetti-update-fringe-borders-h)
  (add-hook 'text-scale-mode-hook #'my--olivetti-refresh-buffer-display-h)
  (add-hook 'olivetti-mode-hook #'my--olivetti-update-fringe-borders-h)
  (add-hook 'doom-load-theme-hook #'my--olivetti-update-fringe-borders-h)
  (defun my--olivetti-workspace-layout-a (original &rest args)
    "Refresh centering after ORIGINAL finishes rebuilding workspace windows."
    (if my-olivetti-inhibit-layout
        (apply original args)
      (let ((frame (if (framep (car args)) (car args) (selected-frame))))
        (unwind-protect
            (let ((my-olivetti-inhibit-layout t))
              ;; A centered single window can have margins wider than each
              ;; saved split. Clear them before Emacs tries to recreate it.
              (when (and my-olivetti-enabled (frame-live-p frame))
                (dolist (window (window-list frame 'no-minibuf))
                  (when (buffer-local-value 'olivetti-mode (window-buffer window))
                    (my--olivetti-disable-buffer (window-buffer window))
                    (set-window-margins window nil nil))))
              (apply original args))
          (when (frame-live-p frame)
            (with-selected-frame frame
              (my--olivetti-refresh-h)
              (my--olivetti-update-fringe-borders-h)))))))
  (after! persp-mode
    ;; Buffer-list hooks run in the middle of `window-state-put', when
    ;; windows may not be live yet. New workspace creation also temporarily
    ;; collapses the old layout inside `save-window-excursion'.
    (advice-add 'persp-restore-window-conf :around
                #'my--olivetti-workspace-layout-a)
    (advice-add '+workspace-new :around #'my--olivetti-workspace-layout-a))
  (setq olivetti-body-width 120))
