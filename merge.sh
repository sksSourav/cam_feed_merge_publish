#!/usr/bin/env bash
set -euo pipefail

# Required: CAM_URLS="rtsp://cam1,rtsp://cam2,..."
IFS=',' read -r -a CAM_LIST <<< "${CAM_URLS:-}"
if [[ ${#CAM_LIST[@]} -eq 0 ]]; then
  echo "No camera feeds provided. Set CAM_URLS env var."
  exit 1
fi

TILE_W="${TILE_W:-640}"
TILE_H="${TILE_H:-360}"
VIDEO_BITRATE="${VIDEO_BITRATE:-4000k}"
FRAMERATE="${FRAMERATE:-25}"
GOP="${GOP:-50}"
ENCODER="${ENCODER:-libx264}"
YOUTUBE_KEY="${YOUTUBE_KEY:-}"

N=${#CAM_LIST[@]}
rows=$(python3 - <<EOF
import math
print(int(math.ceil(math.sqrt($N))))
EOF
)
cols=$rows
GRID=$((rows * cols))

# Build inputs (cameras)
IN=()
# Build inputs (cameras)
IN=()
for cam in "${CAM_LIST[@]}"; do
  IN+=(-re -rtsp_transport tcp -timeout 5000000 \
       -use_wallclock_as_timestamps 1 -i "$cam")
done

# Add black slots if fewer than GRID
for ((i=N; i<GRID; i++)); do
  IN+=(-f lavfi -i "color=size=${TILE_W}x${TILE_H}:rate=${FRAMERATE}:color=black")
done

# Build filter
FILTER=""
layouts=()
for i in $(seq 0 $((GRID-1))); do
  FILTER+="[$i:v]setpts=PTS-STARTPTS,scale=${TILE_W}x${TILE_H}[v$i];"
  row=$(( i / cols ))
  col=$(( i % cols ))
  x=$(( col * TILE_W ))
  y=$(( row * TILE_H ))
  layouts+=("${x}_${y}")
done

FILTER+="$(printf "[v%s]" $(seq 0 $((GRID-1))))"
FILTER+="xstack=inputs=$GRID:layout=$(IFS="|"; echo "${layouts[*]}"):fill=black[vout]"

# Encoder
ENC_OPTS=()
case "$ENCODER" in
  libx264) ENC_OPTS=(-c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p) ;;
  h264_v4l2m2m) ENC_OPTS=(-c:v h264_v4l2m2m -pix_fmt yuv420p) ;;
  *) ENC_OPTS=(-c:v "$ENCODER" -pix_fmt yuv420p) ;;
esac

# Outputs
OUTS="[f=flv]rtmp://127.0.0.1:1935/live/merged"
if [[ -n "$YOUTUBE_KEY" ]]; then
  OUTS="$OUTS|[f=flv]rtmp://a.rtmp.youtube.com/live2/${YOUTUBE_KEY}"
fi

exec ffmpeg \
  "${IN[@]}" \
  -filter_complex "$FILTER" -map "[vout]" \
  -r "$FRAMERATE" -g "$GOP" -b:v "$VIDEO_BITRATE" \
  "${ENC_OPTS[@]}" -an \
  ... -bsf:v h264_mp4toannexb \
  -f tee "$OUTS"