;;; sample.el --- Synthetic landscape -*- lexical-binding: t; -*-
(defconst landscape-sample-limit 42)
(defun landscape-sample-description (name)
  "Describe NAME with readable documentation."
  ;; No personal configuration is evaluated by fontification.
  (when name (format "Region: %s\n" name)))
