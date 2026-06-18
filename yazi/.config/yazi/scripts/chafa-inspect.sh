#!/usr/bin/env sh

img=$1

is_image() {
  [ -f "$1" ] && [ -r "$1" ] || return 1

  mime=$(file -b --mime-type "$1" 2>/dev/null || true)
  case "$mime" in
    image/*) return 0 ;;
    *) return 1 ;;
  esac
}

if [ -z "$img" ]; then
  printf 'No image path provided.\n'
  exit 1
fi

if ! is_image "$img"; then
  printf 'Not a readable image: %s\n' "$img"
  exit 1
fi

dir=$(dirname "$img")
img="$dir/$(basename "$img")"

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

next_image() {
  first=
  found_current=false

  for candidate in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    is_image "$candidate" || continue
    [ -n "$first" ] || first=$candidate

    if [ "$found_current" = true ]; then
      img=$candidate
      return
    fi

    if [ "$candidate" = "$img" ]; then
      found_current=true
    fi
  done

  [ -n "$first" ] && img=$first
}

previous_image() {
  previous=
  last=

  for candidate in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    is_image "$candidate" || continue
    last=$candidate

    if [ "$candidate" = "$img" ]; then
      if [ -n "$previous" ]; then
        img=$previous
        return
      fi
      continue
    fi

    previous=$candidate
  done

  [ -n "$last" ] && img=$last
}

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

  printf '\n←/→: previous/next image    q/Esc: return    +/-: zoom (%s%%)' "$zoom"
}

render
while true; do
  key=$(dd bs=1 count=1 2>/dev/null || true)
  case "$key" in
    q)
      break
      ;;
    "$esc")
      stty min 0 time 1 2>/dev/null || true
      sequence=$(dd bs=1 count=2 2>/dev/null || true)
      stty min 1 time 0 2>/dev/null || true

      case "$sequence" in
        '[C'|'OC')
          next_image
          render
          ;;
        '[D'|'OD')
          previous_image
          render
          ;;
        '')
          break
          ;;
      esac
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
