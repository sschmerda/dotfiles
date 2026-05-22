#!/usr/bin/env sh

img=$1

if [ -z "$img" ]; then
  printf 'No image path provided.\n'
  exit 1
fi

if [ ! -r "$img" ]; then
  printf 'Image is not readable: %s\n' "$img"
  exit 1
fi

if [ -r /dev/tty ] && [ -w /dev/tty ]; then
  exec </dev/tty >/dev/tty
fi

old_tty=$(stty -g 2>/dev/null || true)
trap 'if [ -n "$old_tty" ]; then stty "$old_tty" 2>/dev/null; fi' EXIT INT TERM

rows=$(tput lines 2>/dev/null || printf '24')
cols=$(tput cols 2>/dev/null || printf '80')
height=$((rows - 3))
if [ "$height" -lt 1 ]; then
  height=1
fi

clear
chafa --format=kitty --passthrough=tmux --align=mid,mid --size="${cols}x${height}" "$img"
status=$?

if [ "$status" -ne 0 ]; then
  printf '\nChafa failed with status %s.\n' "$status"
fi

printf '\nPress any key to return to Yazi...'
stty -echo -icanon time 0 min 1 2>/dev/null || true
dd bs=1 count=1 of=/dev/null 2>/dev/null || true

if [ -n "$old_tty" ]; then
  stty "$old_tty" 2>/dev/null || true
fi

clear
if [ -n "$TMUX" ]; then
  tmux clear-history 2>/dev/null || true
fi
