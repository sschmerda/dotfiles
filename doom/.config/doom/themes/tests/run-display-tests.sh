#!/bin/sh
# Run in a graphical login or a real/allocated terminal, without personal init.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
: "${EMACS:=emacs}"
emacs_build_version=$("$EMACS" --batch -Q --eval '(princ (format "%d.%d" emacs-major-version emacs-minor-version))')
: "${LANDSCAPE_DOOM_BUILD:=${EMACSDIR:-$HOME/.emacs.d}/.local/straight/build-$emacs_build_version}"
export LANDSCAPE_DOOM_BUILD
: "${LANDSCAPE_TREE_SITTER_DIR:=${EMACSDIR:-$HOME/.emacs.d}/.local/etc/tree-sitter}"
export LANDSCAPE_TREE_SITTER_DIR
result=$(mktemp "${TMPDIR:-/tmp}/landscape-display.XXXXXXXX")
trap 'rm -f "$result"' EXIT HUP INT TERM
status=0
case "${1:-gui}" in
  gui)
    LANDSCAPE_GUI_RESULT="$result" "$EMACS" -Q -l "$script_dir/custom-tests.el" \
      --eval '(landscape-test-gui)' || status=$?
    cat "$result"
    : > "$result"
    CUSTOM_EDITOR_GUI_RESULT="$result" "$EMACS" -Q -l "$script_dir/custom-tests.el" \
      --eval '(custom-editor-test-gui)' || status=$?
    ;;
  tty)
    LANDSCAPE_TTY_RESULT="$result" "$EMACS" -Q -nw -l "$script_dir/custom-tests.el" \
      --eval '(landscape-test-terminal)' || status=$?
    ;;
  *) printf '%s\n' 'Usage: run-display-tests.sh gui|tty' >&2; exit 2 ;;
esac
cat "$result"
exit "$status"
