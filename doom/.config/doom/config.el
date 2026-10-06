;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; macOS config; set up native compilation before loading other custom code.
(load! "lisp/macos-config")

;; Appearance config.
(load! "lisp/appearance-config")

;; Org config; set its directory before Org loads.
(load! "lisp/org-config")

;; Spell config.
(load! "lisp/spell-config")

;; Snippets config.
(load! "lisp/snippets-config")

;; Python config.
(load! "lisp/python-config")

;; Time popup config.
(load! "lisp/time-popup")

;; Formatting config.
(load! "lisp/format-config")

;; Terminal config.
(load! "lisp/terminal-config")

;; TRAMP config.
(load! "lisp/tramp-config")

;; PDF config.
(load! "lisp/pdf-config")

;; Olivetti config.
(load! "lisp/olivetti-config")
