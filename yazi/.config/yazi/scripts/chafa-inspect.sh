#!/usr/bin/env sh

img=$1

# +/- zoom from 25% to 1600%; hjkl pans the visible crop above 100%.
# 0 resets to fit, arrows change images and reset the view, q/Esc exits.
# ImageMagick is needed only for cropped views, not normal image browsing.

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

case "$img" in
  /*) ;;
  *) img="$PWD/$img" ;;
esac
dir=$(dirname "$img")
img="$dir/$(basename "$img")"

if [ -r /dev/tty ] && [ -w /dev/tty ]; then
  exec </dev/tty >/dev/tty
fi

# Let both terminfo and Chafa measure this TTY, rather than an exported size
# inherited from the shell that originally started Emacs or the tmux server.
unset LINES COLUMNS

old_tty=$(stty -g 2>/dev/null || true)
work_dir=
source_image=

clear_images() {
  # d=A clears visible placements, but leaves virtual placeholder images.
  # Remove their stored data too, so Chafa images cannot cover Yazi's preview.
  if [ -n "$TMUX" ]; then
    printf '\033Ptmux;\033\033_Ga=d,d=R,x=1,y=4294967295,q=2;\033\033\\\033\\'
  else
    printf '\033_Ga=d,d=R,x=1,y=4294967295,q=2;\033\\'
  fi
}

cleanup() {
  clear_images
  [ -z "$work_dir" ] || rm -rf -- "$work_dir"
  if [ -n "$old_tty" ]; then
    stty "$old_tty" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

stty -echo -icanon time 0 min 1 2>/dev/null || true
zoom=100
esc=$(printf '\033')

reset_view() {
  zoom=100
  if [ "$source_image" = "$img" ]; then
    focus_x=$((source_width / 2))
    focus_y=$((source_height / 2))
  fi
}

prepare_source() {
  [ "$source_image" != "$img" ] || return 0
  if ! command -v magick >/dev/null 2>&1; then
    printf '\nZooming beyond 100%% needs ImageMagick (magick).\n'
    return 1
  fi
  if [ -z "$work_dir" ]; then
    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/yazi-image-view.XXXXXXXX") || return 1
  fi
  # Decode/orient the first frame once, then reuse it while panning. MIFF
  # avoids repeatedly decoding the original and keeps this cache lossless.
  dimensions=$(magick "${img}[0]" -auto-orient +repage -depth 8 \
    -write "$work_dir/source.miff" -format '%w %h' info:) || return 1
  set -- $dimensions
  case "$1:$2" in
    *[!0-9:]*|:*|*:) return 1 ;;
  esac
  source_width=$1
  source_height=$2
  [ "$source_width" -gt 0 ] && [ "$source_height" -gt 0 ] || return 1
  focus_x=$((source_width / 2))
  focus_y=$((source_height / 2))
  source_image=$img
}

crop_geometry() {
  crop_width=$((source_width * 100 / zoom))
  crop_height=$((source_height * 100 / zoom))
  [ "$crop_width" -gt 0 ] || crop_width=1
  [ "$crop_height" -gt 0 ] || crop_height=1
  crop_x=$((focus_x - crop_width / 2))
  crop_y=$((focus_y - crop_height / 2))
  max_x=$((source_width - crop_width))
  max_y=$((source_height - crop_height))
  [ "$crop_x" -ge 0 ] || crop_x=0
  [ "$crop_y" -ge 0 ] || crop_y=0
  [ "$crop_x" -le "$max_x" ] || crop_x=$max_x
  [ "$crop_y" -le "$max_y" ] || crop_y=$max_y
  focus_x=$((crop_x + crop_width / 2))
  focus_y=$((crop_y + crop_height / 2))
}

pan() {
  [ "$zoom" -gt 100 ] || return 0
  old_x=$crop_x
  old_y=$crop_y
  step_x=$((crop_width / 10))
  step_y=$((crop_height / 10))
  [ "$step_x" -gt 0 ] || step_x=1
  [ "$step_y" -gt 0 ] || step_y=1
  case "$1" in
    h) focus_x=$((focus_x - step_x)) ;;
    j) focus_y=$((focus_y + step_y)) ;;
    k) focus_y=$((focus_y - step_y)) ;;
    l) focus_x=$((focus_x + step_x)) ;;
  esac
  crop_geometry
  # At an edge there is no new crop to transmit or redraw.
  if [ "$old_x:$old_y" != "$crop_x:$crop_y" ]; then
    render
  fi
}

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
  # Exported LINES/COLUMNS can be stale; use the actual pane's TTY size.
  set -- $(stty size 2>/dev/null)
  rows=${1:-24}
  cols=${2:-80}
  height=$((rows - 3))
  if [ "$height" -lt 1 ]; then
    height=1
  fi

  render_image=$img
  render_zoom=$zoom
  set --
  if [ "$zoom" -gt 100 ]; then
    prepare_source || return 1
    crop_geometry
    # Crop before rendering, so zooming never produces an oversized terminal
    # image. Low PNG compression avoids extra work on each pan.
    magick "$work_dir/source.miff" \
      -crop "${crop_width}x${crop_height}+${crop_x}+${crop_y}" +repage \
      -define png:compression-level=1 "$work_dir/viewport.png" || return 1
    render_image=$work_dir/viewport.png
    render_zoom=100
    set -- --scale=max --exact-size=off
  fi
  render_cols=$((cols * render_zoom / 100))
  render_height=$((height * render_zoom / 100))
  if [ "$render_cols" -lt 1 ]; then
    render_cols=1
  fi
  if [ "$render_height" -lt 1 ]; then
    render_height=1
  fi

  clear_images
  clear
  passthrough=none
  [ -z "$TMUX" ] || passthrough=tmux
  chafa --format=kitty --passthrough="$passthrough" --animate=off \
    "$@" \
    --align=mid,mid --view-size="${cols}x${height}" \
    --size="${render_cols}x${render_height}" "$render_image"
  status=$?

  if [ "$status" -ne 0 ]; then
    printf '\nImage rendering failed with status %s.\n' "$status"
  fi

  printf '\n←/→: image    +/-: zoom (%s%%)    hjkl: pan    0: fit    q/Esc: return' "$zoom"
}

render
while true; do
  key=$(dd bs=1 count=1 2>/dev/null || true)
  case "$key" in
    q|'')
      break
      ;;
    "$esc")
      stty min 0 time 1 2>/dev/null || true
      sequence=$(dd bs=1 count=2 2>/dev/null || true)
      stty min 1 time 0 2>/dev/null || true

      case "$sequence" in
        '[C'|'OC')
          old_image=$img
          next_image
          if [ "$img" != "$old_image" ]; then
            reset_view
            render
          fi
          ;;
        '[D'|'OD')
          old_image=$img
          previous_image
          if [ "$img" != "$old_image" ]; then
            reset_view
            render
          fi
          ;;
        '')
          break
          ;;
      esac
      ;;
    +|=)
      if [ "$zoom" -lt 1600 ]; then
        if [ "$zoom" -ge 100 ]; then
          prepare_source || continue
        fi
        zoom=$((zoom + 25))
        render
      fi
      ;;
    -)
      if [ "$zoom" -gt 25 ]; then
        zoom=$((zoom - 25))
        render
      fi
      ;;
    h|j|k|l)
      pan "$key"
      ;;
    0)
      if [ "$zoom" -ne 100 ]; then
        reset_view
        render
      fi
      ;;
  esac
done

cleanup
trap - EXIT
clear
if [ -n "$TMUX" ]; then
  tmux clear-history 2>/dev/null || true
fi
