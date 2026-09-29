;;; time-popup.el --- Local clock popup -*- lexical-binding: t; -*-

(defvar-local my/time-popup-timer nil)
(defvar my/time-popup--frame nil
  "The floating frame displaying the clock, if any.")
(defvar my/time-popup-world-zones
  '(("UTC" "UTC0")
    ("London" "Europe/London")
    ("New York" "America/New_York")
    ("Los Angeles" "America/Los_Angeles")
    ("New Delhi" "Asia/Kolkata")
    ("Tokyo" "Asia/Tokyo")
    ("Sydney" "Australia/Sydney"))
  "World clock entries as (LABEL TIME-ZONE), using named zones for daylight saving.")

(defun my/time-popup-stop ()
  "Stop this clock buffer's refresh timer."
  (when (timerp my/time-popup-timer)
    (cancel-timer my/time-popup-timer))
  (setq my/time-popup-timer nil))

(defun my/time-popup-close ()
  "Close the clock popup and stop refreshing it."
  (interactive)
  (let* ((buffer (get-buffer "*Local Clock*"))
         (frame my/time-popup--frame)
         (parent (and (frame-live-p frame)
                      (frame-parameter frame 'parent-frame))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (my/time-popup-stop)))
    (setq my/time-popup--frame nil)
    (if (frame-live-p frame)
        (progn
          (delete-frame frame t)
          (when (frame-live-p parent)
            (select-frame-set-input-focus parent)))
      (when (and buffer (get-buffer-window buffer t))
        (quit-window)))
    (when (buffer-live-p buffer)
      (kill-buffer buffer))))

(defvar my/time-popup-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "q") #'my/time-popup-close)
    (define-key map (kbd "<escape>") #'my/time-popup-close)
    (define-key map (kbd "C-g") #'my/time-popup-close)
    map))

(define-derived-mode my/time-popup-mode special-mode "Clock"
  "Display local time and date without editing the buffer."
  (setq-local cursor-type nil
              display-line-numbers nil
              display-fill-column-indicator nil
              mode-line-format nil
              header-line-format nil
              truncate-lines t)
  (add-hook 'kill-buffer-hook #'my/time-popup-stop nil t))

(defun my/time-popup-render ()
  "Render large local time and understated world clocks using theme colors."
  (let* ((inhibit-read-only t)
         (now (current-time))
         (window (get-buffer-window (current-buffer) t))
         (position (if window (window-point window) (point)))
         (line (line-number-at-pos position))
         (column (save-excursion (goto-char position) (current-column))))
    (erase-buffer)
    (insert "\n    "
            (propertize (format-time-string "%H:%M:%S" now)
                        'face '(:inherit font-lock-keyword-face :height 2.4 :weight bold))
            "\n\n    "
            (format-time-string "%A, %d %B %Y  (%Z)" now)
            "\n\n    "
            (propertize "World clock" 'face 'shadow)
            "\n\n")
    (dolist (entry my/time-popup-world-zones)
      (insert
       (propertize
        (format "    %-12s %s\n" (car entry)
                (format-time-string "%H:%M  ·  %a, %d %b  ·  %Z" now (cadr entry)))
        'face '(:inherit shadow :height 0.9))))
    (goto-char (point-min))
    (forward-line (1- line))
    (move-to-column column)
    (when window
      (set-window-point window (point)))
    (set-buffer-modified-p nil)))

(defun my/time-popup-tick (buffer)
  "Refresh BUFFER while visible; stop the timer when hidden."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (if (get-buffer-window buffer t)
          (my/time-popup-render)
        (my/time-popup-stop)))))

(defun my/time-popup-show-frame (buffer)
  "Show BUFFER in a child frame centred over the current frame."
  (let* ((parent (selected-frame))
         (frame (make-frame
                 `((parent-frame . ,parent)
                   (minibuffer . nil)
                   (name . "Local Clock")
                   (width . 48)
                   (height . 16)
                   (undecorated . t)
                   (cursor-type . nil)
                   (no-accept-focus . t)
                   (no-focus-on-map . t)
                   (child-frame-border-width . 1)
                   (internal-border-width . 12)
                   (menu-bar-lines . 0)
                   (tool-bar-lines . 0)
                   (tab-bar-lines . 0)
                   (vertical-scroll-bars . nil)
                   (horizontal-scroll-bars . nil)
                   (no-other-frame . t)
                   (skip-taskbar . t)
                   (unsplittable . t)
                   (my/time-popup . t)
                   (visibility . nil)))))
    (setq my/time-popup--frame frame)
    (set-face-attribute 'child-frame-border frame
                        :background (face-foreground 'vertical-border parent t))
    (set-window-buffer (frame-root-window frame) buffer)
    (set-frame-position
     frame
     (max 0 (/ (- (frame-pixel-width parent) (frame-pixel-width frame)) 2))
     (max 0 (/ (- (frame-pixel-height parent) (frame-pixel-height frame)) 2)))
    (make-frame-visible frame)
    (select-frame-set-input-focus parent)))

(defun my/time-popup-toggle ()
  "Toggle a popup showing the system's local time and date."
  (interactive)
  (let* ((buffer (get-buffer "*Local Clock*"))
         (window (and buffer (get-buffer-window buffer t))))
    (if (or (frame-live-p my/time-popup--frame) window)
        (my/time-popup-close)
      (setq buffer (get-buffer-create "*Local Clock*"))
      (with-current-buffer buffer
        (unless (derived-mode-p 'my/time-popup-mode)
          (my/time-popup-mode))
        (my/time-popup-stop)
        (my/time-popup-render))
      (if (display-graphic-p)
          (my/time-popup-show-frame buffer)
        (pop-to-buffer buffer))
      (with-current-buffer buffer
        (setq my/time-popup-timer
              (run-at-time 1 1 #'my/time-popup-tick buffer))))))

(provide 'time-popup)
;;; time-popup.el ends here
