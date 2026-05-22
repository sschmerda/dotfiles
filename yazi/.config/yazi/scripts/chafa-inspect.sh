#!/usr/bin/env sh

log="${TMPDIR:-/tmp}/yazi-chafa-inspect.log"

render() {
  img=$1

  if [ -z "$img" ]; then
    printf 'No image path provided.\n' >"$log"
    cat "$log"
    return 1
  fi

  clear
  printf 'image: %s\n' "$img" >"$log"

  if [ -n "$TMUX" ]; then
    chafa --format=kitty --passthrough=tmux "$img" 2>>"$log"
  else
    chafa "$img" 2>>"$log"
  fi

  status=$?
  if [ "$status" -ne 0 ]; then
    printf '\nChafa failed. Log:\n'
    cat "$log"
  fi

  printf '\nPress any key to return to Yazi...'
  old_tty=$(stty -g 2>/dev/null || true)
  stty -echo -icanon time 0 min 1 2>/dev/null
  dd bs=1 count=1 of=/dev/null 2>/dev/null
  if [ -n "$old_tty" ]; then
    stty "$old_tty" 2>/dev/null
  else
    stty sane 2>/dev/null
  fi

  clear
  if [ -n "$TMUX" ]; then
    tmux clear-history 2>/dev/null || true
  fi
}

render "$1"
