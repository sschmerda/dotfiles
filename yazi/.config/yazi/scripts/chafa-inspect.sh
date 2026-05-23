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

stty -echo -icanon time 0 min 1 2>/dev/null || true
zoom=100
esc=$(printf '\033')

render() {
  rows=$(tput lines 2>/dev/null || printf '24')
  cols=$(tput cols 2>/dev/null || printf '80')
  height=$((rows - 3))
  if [ "$height" -lt 1 ]; then
    height=1
  fi

  render_cols=$((cols * zoom / 100))
  render_height=$((height * zoom / 100))
  if [ "$render_cols" -lt 1 ]; then
    render_cols=1
  fi
  if [ "$render_height" -lt 1 ]; then
    render_height=1
  fi

  clear
  chafa --format=kitty --passthrough=tmux --align=mid,mid --size="${render_cols}x${render_height}" "$img"
  status=$?

  if [ "$status" -ne 0 ]; then
    printf '\nChafa failed with status %s.\n' "$status"
  fi

  printf '\nq/Esc: return to Yazi    +/-: zoom (%s%%)' "$zoom"
}

render
while true; do
  key=$(dd bs=1 count=1 2>/dev/null || true)
  case "$key" in
    q|"$esc")
      break
      ;;
    +|=)
      if [ "$zoom" -lt 400 ]; then
        zoom=$((zoom + 25))
      fi
      render
      ;;
    -)
      if [ "$zoom" -gt 25 ]; then
        zoom=$((zoom - 25))
      fi
      render
      ;;
  esac
done

if [ -n "$old_tty" ]; then
  stty "$old_tty" 2>/dev/null || true
fi

clear
if [ -n "$TMUX" ]; then
  tmux clear-history 2>/dev/null || true
fi
