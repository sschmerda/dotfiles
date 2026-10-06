;;; tramp-config.el -*- lexical-binding: t; -*-

;; Include each remote connection's original PATH, so user-installed tools such
;; as micromamba are discoverable without hardcoding host or container paths.
;; This applies to all TRAMP methods, including Docker and SSH.
(after! tramp
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path))
