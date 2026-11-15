;;; custom-editor-themes.el --- Reference-inspired custom themes -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'doom-themes)
(require 'landscape-faces)
(require 'custom-editor-palettes)

(defun custom-editor--background-mode (variant)
  "Return the background mode for a named custom VARIANT."
  (if (or (memq variant '(rose-pine-dawn catppuccin-latte))
          (string-suffix-p "-light" (symbol-name variant)))
      'light 'dark))

(defun custom-editor--bindings (variant)
  "Build Doom palette bindings for custom VARIANT using the shared engine."
  (let* ((landscape-palettes custom-editor-palettes)
         (bindings (copy-tree (landscape--bindings variant (custom-editor--background-mode variant)))))
    ;; Keep the existing neutral ramps, diagnostics and package color categories;
    ;; use the reference's distinct builtin/variable/operator colors for syntax.
    (dolist (mapping '((builtin . builtin-color) (variables . variable-color)
                       (operators . operator-color) (doc-comments . doc-color)))
      (setf (cadr (assq (car mapping) bindings)) (cdr mapping)))
    bindings))

(defun custom-editor--faces (variant)
  "Return shared package support plus reference-specific faces for VARIANT."
  (let ((faces (copy-tree (landscape--faces variant (custom-editor--background-mode variant)))))
    (dolist
        (mapping
         '((selection-fg lsp-ui-sideline-current-symbol)
           (builtin-color font-lock-builtin-face)
           (variable-color font-lock-variable-name-face font-lock-variable-use-face
                           lsp-face-semhl-variable)
           (parameter-color lsp-face-semhl-parameter)
           (property-color font-lock-property-use-face
                           lsp-face-semhl-property lsp-face-semhl-member
                           lsp-face-semhl-event)
           (operator-color ess-operator-face ess-%op%-face ess-assignment-face
                           font-lock-operator-face font-lock-negation-char-face
                           lsp-face-semhl-operator)
           (doc-color font-lock-doc-face)
           (comment mode-line-inactive solaire-mode-line-inactive-face)))
      (dolist (face (cdr mapping))
        (let ((spec (cl-find face faces
                             :key (lambda (spec) (if (consp (car spec))
                                                     (caar spec) (car spec))))))
          (if spec
              (setcdr spec (plist-put (cdr spec) :foreground (car mapping)))
            (push `((,face &override) :foreground ,(car mapping)) faces)))))
    (let ((spec (cl-find 'lsp-ui-sideline-current-symbol faces
                         :key (lambda (spec) (if (consp (car spec)) (caar spec) (car spec))))))
      (setcdr spec (plist-put (cdr spec) :background 'selection-bg)))
    ;; Yellow keyword emphasis is part of Gruber's restrained visual identity.
    (when (eq variant 'gruber-dark)
      (dolist (face '(font-lock-keyword-face lsp-face-semhl-keyword))
        (let ((spec (cl-find face faces :key (lambda (spec) (if (consp (car spec)) (caar spec) (car spec))))))
          (setcdr spec (plist-put (cdr spec) :weight ''bold)))))
    faces))

(defmacro custom-editor-define-theme (variant)
  "Define reference-inspired VARIANT with a `custom-' theme name."
  (let ((name (intern (format "custom-%s" variant)))
        (family (cond ((string-prefix-p "gruber-" (symbol-name variant)) 'custom-gruber)
                      ((string-prefix-p "rose-pine-" (symbol-name variant)) 'custom-rose-pine)
                      ((string-prefix-p "catppuccin-" (symbol-name variant)) 'custom-catppuccin)
                      (t 'custom-shades-of-purple))))
    `(def-doom-theme ,name ,(format "Local %s palette with shared Doom face support." variant)
		     :family ',family
		     :background-mode ',(custom-editor--background-mode variant)
		     ,(custom-editor--bindings variant)
		     ,(custom-editor--faces variant)
		     ((lsp-semantic-token-modifier-faces
		       (list 'quote (landscape--semantic-modifiers)))
		      (ansi-color-names-vector
		       (vconcat (mapcar #'doom-color
					'(ansi-black red green yellow blue magenta cyan ansi-white))))))))

(provide 'custom-editor-themes)
;;; custom-editor-themes.el ends here
