;;; macos-config.el -*- lexical-binding: t; -*-

(defun my/setup-macos-native-comp-library-path ()
  "Let native compilation find libSystem in the active macOS SDK."
  (when (and (eq system-type 'darwin)
             (fboundp 'native-comp-available-p)
             (native-comp-available-p)
             (executable-find "xcrun"))
    (with-temp-buffer
      (when (eq 0 (call-process "xcrun" nil (list t nil) nil
                                "--sdk" "macosx" "--show-sdk-path"))
        (let* ((sdk (string-trim (buffer-string)))
               (lib (expand-file-name "usr/lib" sdk))
               (existing (getenv "LIBRARY_PATH")))
          ;; Discover the SDK instead of pinning an Xcode, SDK, or Homebrew version.
          ;; Preserve existing compiler paths and avoid duplicates on config reload.
          (when (and (file-name-absolute-p sdk)
                     (file-exists-p (expand-file-name "libSystem.tbd" lib))
                     (not (member lib (split-string (or existing "") ":" t))))
            (setenv "LIBRARY_PATH"
                    (if (and existing (not (string-empty-p existing)))
                        (concat existing ":" lib)
                      lib))))))))

(my/setup-macos-native-comp-library-path)

;; Both Option keys act as Meta; Command acts as Super.
(setq mac-option-modifier 'meta
      mac-right-option-modifier 'meta
      mac-command-modifier 'super
      ns-option-modifier 'meta
      ns-alternate-modifier 'meta
      ns-right-alternate-modifier 'meta
      ns-command-modifier 'super)

;; Keep Command+X as Cut; Option+X opens the command menu.
(when (eq system-type 'darwin)
  (map! "s-x" (cmds! (doom-region-active-p) #'kill-region
                     #'ignore)))
