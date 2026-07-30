#!/bin/sh
# Demo mp4 → README GIF with the parameters the existing clips use
# (900 px wide, 12.5 fps, per-clip palette).
set -e
[ $# -eq 2 ] || { echo "usage: demo-gif.sh in.mp4 out.gif" >&2; exit 2; }
ffmpeg -y -v error -i "$1" -vf \
  "fps=12.5,scale=900:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
  "$2"
