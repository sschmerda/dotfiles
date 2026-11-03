#!/bin/sh
# Run from any working directory. No package installation or personal init.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
: "${EMACS:=emacs}"
emacs_build_version=$("$EMACS" --batch -Q --eval '(princ (format "%d.%d" emacs-major-version emacs-minor-version))')
: "${LANDSCAPE_DOOM_BUILD:=${EMACSDIR:-$HOME/.emacs.d}/.local/straight/build-$emacs_build_version}"
: "${LANDSCAPE_TREE_SITTER_DIR:=${EMACSDIR:-$HOME/.emacs.d}/.local/etc/tree-sitter}"
export LANDSCAPE_DOOM_BUILD LANDSCAPE_TREE_SITTER_DIR
case "${1:-all}" in
  all) DOOM_THEME_TEST_SELECTOR='.*' ;;
  landscape) DOOM_THEME_TEST_SELECTOR='^landscape-' ;;
  custom) DOOM_THEME_TEST_SELECTOR='^custom-editor-' ;;
  *) printf '%s\n' 'Usage: run-tests.sh [all|landscape|custom]' >&2; exit 2 ;;
esac
export DOOM_THEME_TEST_SELECTOR
exec "$EMACS" --batch -Q -l "$script_dir/custom-tests.el" --eval '(ert-run-tests-batch-and-exit (getenv "DOOM_THEME_TEST_SELECTOR"))'
