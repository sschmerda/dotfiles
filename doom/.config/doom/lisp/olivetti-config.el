;;; olivetti-config.el -*- lexical-binding: t; -*-

;; Toggle Olivetti buffer centering without hiding modelines or other windows.
(use-package! olivetti
  :commands (olivetti-mode my/olivetti-toggle-all)
  :init
  (setq olivetti-body-width 120)
  (defvar my/olivetti-enabled nil)
  (defun my/olivetti-buffer-eligible-p ()
    "Allow file, Dired and shell buffers, excluding internal and display buffers."
    (and (not (minibufferp))
         (not (bound-and-true-p +popup-buffer-mode))
         (not (derived-mode-p 'pdf-view-mode 'my/time-popup-mode))
         (not (string-prefix-p " " (buffer-name)))))
  (defun my/olivetti-enable-buffer (buffer)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (get-buffer-window buffer (selected-frame))
          (if (my/olivetti-buffer-eligible-p)
              (unless (bound-and-true-p olivetti-mode)
                (olivetti-mode 1))
            (my/olivetti-disable-buffer buffer))))))
  (defun my/olivetti-disable-buffer (buffer)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (bound-and-true-p olivetti-mode)
          (olivetti-mode -1)))))
  (defun my/olivetti-disable-all-buffers ()
    (mapc #'my/olivetti-disable-buffer (buffer-list)))
  (defun my/olivetti-refresh-visible-windows ()
    (walk-windows
     (lambda (window)
       (with-current-buffer (window-buffer window)
         (when (bound-and-true-p olivetti-mode)
           (olivetti-set-window window))))
     nil t))
  (defun my/olivetti-vertical-split-p ()
    "Return non-nil when any windows in this frame are side by side."
    (let ((left-edges nil))
      (dolist (window (window-list nil 'no-minibuf))
        (push (window-left-column window) left-edges))
      (> (length (delete-dups left-edges)) 1)))
  (defun my/olivetti-refresh-h (&rest _)
    (when (and my/olivetti-enabled
               (not (frame-parameter (selected-frame) 'my/time-popup)))
      (if (my/olivetti-vertical-split-p)
          (my/olivetti-disable-all-buffers)
        (mapc #'my/olivetti-enable-buffer (buffer-list))
        (my/olivetti-refresh-visible-windows))))
  (defun my/olivetti-toggle-all ()
    (interactive)
    (setq my/olivetti-enabled (not my/olivetti-enabled))
    (if my/olivetti-enabled
        (my/olivetti-refresh-h)
      (my/olivetti-disable-all-buffers)))
  (map! :leader
        :desc "Center buffers"
        "t o" #'my/olivetti-toggle-all)
  (add-hook 'buffer-list-update-hook #'my/olivetti-refresh-h)
  (add-hook 'window-state-change-functions #'my/olivetti-refresh-h)
  ;; Popup windows keep their normal width, including SPC o t terminals.
  (add-hook '+popup-create-window-hook #'my/olivetti-refresh-h)
  (add-hook! 'doom-first-buffer-hook
    (defun my/olivetti-enable-on-startup-h ()
      (setq my/olivetti-enabled t)
      (my/olivetti-refresh-h)))
  :config
  (defvar-local my/olivetti-original-gutter-bitmap-function nil)
  (defun my/olivetti-define-gutter-bar-h (&rest _)
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
        (define-fringe-bitmap 'my/olivetti-gutter-bar
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
          (define-fringe-bitmap 'my/olivetti-gutter-delete
            rows height width 'center)))))
  (defun my/olivetti-gutter-bitmap (type _position)
    "Select Git markers separated from the border by one pixel."
    (if (eq type 'delete)
        'my/olivetti-gutter-delete
      'my/olivetti-gutter-bar))
  (defun my/olivetti-sync-gutter-bitmap-h ()
    "Use the inset Git bar only in centred buffers."
    (when (bound-and-true-p diff-hl-mode)
      (cond
       ((and olivetti-mode (not my/olivetti-original-gutter-bitmap-function))
        (my/olivetti-define-gutter-bar-h)
        (setq my/olivetti-original-gutter-bitmap-function diff-hl-fringe-bmp-function)
        (setq-local diff-hl-fringe-bmp-function #'my/olivetti-gutter-bitmap)
        (diff-hl-update))
       ((and (not olivetti-mode) my/olivetti-original-gutter-bitmap-function)
        (setq-local diff-hl-fringe-bmp-function my/olivetti-original-gutter-bitmap-function)
        (setq my/olivetti-original-gutter-bitmap-function nil)
        (diff-hl-update)))))
  (after! diff-hl
    (advice-add 'diff-hl-define-bitmaps :after #'my/olivetti-define-gutter-bar-h))
  (add-hook 'olivetti-mode-hook #'my/olivetti-sync-gutter-bitmap-h)
  (add-hook 'diff-hl-mode-on-hook #'my/olivetti-sync-gutter-bitmap-h)
  (defvar-local my/olivetti-original-fringe-indicators nil)
  (defun my/olivetti-empty-line-bitmap (width height)
    "Return a WIDTH by HEIGHT bitmap with a border and an inset tilde."
    (setq width (max 3 (min 16 width))
          height (max 2 height))
    (let ((bitmap (intern (format "my/olivetti-empty-line-%dx%d" width height))))
      (unless (fringe-bitmap-p bitmap)
        (let* ((border (ash 1 (1- width)))
               (rows (make-vector height border))
               (mask (1- (ash 1 (- width 2))))
               (middle (1- (/ height 2))))
          ;; Reserve the outer pixel for the border and the next for a gap.
          (aset rows middle (logior border (logand #b011001 mask)))
          (aset rows (1+ middle) (logior border (logand #b100110 mask)))
          (define-fringe-bitmap bitmap rows height width '(center t))
          (set-fringe-bitmap-face bitmap 'fringe)))
      bitmap))
  (defun my/olivetti-sync-empty-line-indicator (window enabled)
    "Keep WINDOW's border beside end-of-buffer markers when ENABLED."
    (if enabled
        (let* ((frame (window-frame window))
               (scale (if (boundp 'text-scale-mode-amount)
                          (expt text-scale-mode-step text-scale-mode-amount) 1))
               (spacing (or line-spacing 0))
               (spacing (if (consp spacing) (+ (car spacing) (cdr spacing)) spacing))
               (height (+ (ceiling (* (frame-char-height frame) scale))
                          (if (floatp spacing)
                              (truncate (* (frame-char-height frame) spacing)) spacing)))
               (bitmap (my/olivetti-empty-line-bitmap
                        (car (window-fringes window)) height)))
          (unless my/olivetti-original-fringe-indicators
            (setq my/olivetti-original-fringe-indicators
                  (list (local-variable-p 'fringe-indicator-alist)
                        fringe-indicator-alist)))
          (unless (eq (cdr (assq 'empty-line fringe-indicator-alist)) bitmap)
            (setq-local fringe-indicator-alist
                        (cons (cons 'empty-line bitmap)
                              (assq-delete-all 'empty-line
                                               (copy-tree fringe-indicator-alist))))))
      (when my/olivetti-original-fringe-indicators
        (if (car my/olivetti-original-fringe-indicators)
            (setq-local fringe-indicator-alist
                        (cadr my/olivetti-original-fringe-indicators))
          (kill-local-variable 'fringe-indicator-alist))
        (setq my/olivetti-original-fringe-indicators nil))))
  (defun my/olivetti-clear-fringe-border (window)
    "Remove WINDOW's local patterned fringe face."
    (when-let ((entry (window-parameter window 'my/olivetti-fringe-face)))
      (when (buffer-live-p (car entry))
        (with-current-buffer (car entry)
          (face-remap-remove-relative (cdr entry)))))
    (set-window-parameter window 'my/olivetti-fringe-face nil)
    (set-window-parameter window 'my/olivetti-fringe-state nil))
  (defun my/olivetti-pattern-fringes (window)
    "Paint one-pixel outer stripes without reducing the Git gutter width."
    (when (window-live-p window)
      (with-current-buffer (window-buffer window)
        (let* ((frame (window-frame window))
               (backend (window-system frame))
               ;; NS and older PGTK builds do not render stipples reliably.
               (supported (or (memq backend '(mac x))
                              (and (eq backend 'pgtk) (>= emacs-major-version 30)))))
          (my/olivetti-sync-empty-line-indicator
           window (and (bound-and-true-p olivetti-mode) supported))
          (if (not (and (bound-and-true-p olivetti-mode) supported))
              (my/olivetti-clear-fringe-border window)
            (let* ((edges (window-inside-pixel-edges window))
                   (fringes (window-fringes window))
                   (width (frame-pixel-width frame))
                   (left (- (car edges) (car fringes)))
                   (right (1- (+ (nth 2 edges) (cadr fringes))))
                   (background (face-attribute 'default :background frame t))
                   ;; Follow the theme, using the same face as split dividers.
                   (border (face-attribute 'shadow :foreground frame t))
                   (state (list (current-buffer) width left right background border)))
              (unless (equal state (window-parameter window 'my/olivetti-fringe-state))
                (my/olivetti-clear-fringe-border window)
                ;; Stipples are tiled from the frame origin, not the fringe origin.
                ;; A frame-wide tile gives each outer edge exactly one set pixel.
                (let ((bits (make-string (/ (+ width 7) 8) 0))
                      (token (make-symbol "olivetti-fringe")))
                  (dolist (pixel (list left right))
                    (when (and (>= pixel 0) (< pixel width))
                      (let ((byte (/ pixel 8)))
                        (aset bits byte (logior (aref bits byte)
                                               (ash 1 (% pixel 8)))))))
                  (set-window-parameter window 'my/olivetti-fringe-token token)
                  (set-window-parameter
                   window 'my/olivetti-fringe-face
                   (cons (current-buffer)
                         (face-remap-add-relative
                          'fringe
                          `(:filtered (:window my/olivetti-fringe-token ,token)
                            (:foreground ,border :background ,background
                             :stipple (,width 1 ,(string-make-unibyte bits)))))))
                  (set-window-parameter window 'my/olivetti-fringe-state state)))))))))
  (defun my/olivetti-update-fringe-borders-h (&rest _)
    "Refresh patterned borders when centering or the theme changes."
    (dolist (frame (frame-list))
      (unless (frame-parameter frame 'my/time-popup)
        (dolist (window (window-list frame 'no-minibuf))
          (my/olivetti-pattern-fringes window)))))
  (defun my/olivetti-fringe-after-layout-h (window-or-frame)
    "Keep the normal Git fringe inside the centering margins."
    (when (window-live-p window-or-frame)
      (with-current-buffer (window-buffer window-or-frame)
        (when (bound-and-true-p olivetti-mode)
          (set-window-fringes window-or-frame nil nil nil)))
      (my/olivetti-pattern-fringes window-or-frame)))
  (advice-add 'olivetti-set-window :after #'my/olivetti-fringe-after-layout-h)
  (add-hook 'olivetti-mode-hook #'my/olivetti-update-fringe-borders-h)
  (add-hook 'doom-load-theme-hook #'my/olivetti-update-fringe-borders-h)
  (setq olivetti-body-width 120))
