#!/usr/bin/env bash
set -euo pipefail

# merge.sh
# Merge multiple camera RTSP streams into a grid and forward to MediaMTX (RTMP)

# Required env: CAM_URLS="rtsp://cam1,rtsp://cam2,..."
: "${CAM_URLS:?CAM_URLS must be set (comma-separated list of RTSP/HTTP inputs)}"

IFS=',' read -r -a CAM_LIST <<< "$CAM_URLS"
if [ ${#CAM_LIST[@]} -eq 0 ]; then
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
# AUDIO_MODE: none|first|mix
# - none: drop all audio (default for backwards compatibility historically 'an')
# - first: pass-through audio from first input (safe; uses "-map 0:a?" so missing audio doesn't fail)
# - mix: (not implemented robustly) fallback to 'first' for now
AUDIO_MODE="${AUDIO_MODE:-first}"

N=${#CAM_LIST[@]}
# compute smallest square >= N
rows=1
while [ $((rows * rows)) -lt "$N" ]; do
  rows=$((rows + 1))
done
cols=$rows
GRID=$((rows * cols))

# Build ffmpeg input args
IN_ARGS=()
for cam in "${CAM_LIST[@]}"; do
  # use tcp transport, short read timeout (microseconds for -stimeout)
  IN_ARGS+=( -rtsp_transport tcp -stimeout 5000000 -use_wallclock_as_timestamps 1 -i "$cam" )
done

# Add black inputs for empty grid cells
for ((i = N; i < GRID; i++)); do
  IN_ARGS+=( -f lavfi -i "color=size=${TILE_W}x${TILE_H}:rate=${FRAMERATE}:color=black" )
done

# Build filter_complex: scale each stream and stack with xstack
scale_parts=()
layouts=()
for i in $(seq 0 $((GRID - 1))); do
  scale_parts+=("[$i:v]setpts=PTS-STARTPTS,scale=${TILE_W}:${TILE_H}[v${i}]")
  row=$(( i / cols ))
  col=$(( i % cols ))
  x=$(( col * TILE_W ))
  y=$(( row * TILE_H ))
  layouts+=("${x}_${y}")
done

# join scale_parts by ";"
filter_scale=""
for i in "${scale_parts[@]}"; do
  if [ -z "$filter_scale" ]; then
    filter_scale="$i"
  else
    filter_scale="$filter_scale;$i"
  fi
done

# build label concat like [v0][v1][v2]...
label_concat=""
for i in $(seq 0 $((GRID - 1))); do
  label_concat="$label_concat[v${i}]"
done

layout_str=$(IFS='|'; echo "${layouts[*]}")
filter_complex="${filter_scale};${label_concat}xstack=inputs=${GRID}:layout=${layout_str}:fill=black[vout]"

# Encoder options
ENC_OPTS=()
case "$ENCODER" in
  libx264)
    ENC_OPTS=( -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -profile:v baseline )
    ;;
  h264_v4l2m2m)
    ENC_OPTS=( -c:v h264_v4l2m2m -pix_fmt yuv420p )
    ;;
  *)
    ENC_OPTS=( -c:v "$ENCODER" -pix_fmt yuv420p )
    ;;
esac

# Outputs: local MediaMTX + optional YouTube
OUTS="[f=flv]rtmp://127.0.0.1:1935/live/merged"
if [ -n "$YOUTUBE_KEY" ]; then
  OUTS="$OUTS|[f=flv]rtmp://a.rtmp.youtube.com/live2/${YOUTUBE_KEY}"
fi

echo "Starting ffmpeg with ${#CAM_LIST[@]} inputs, grid=${rows}x${cols} (total slots=${GRID})"
echo "Filter_complex length: ${#filter_complex} characters"

# Build audio mapping options
AUDIO_MAP_OPTS=()
case "$AUDIO_MODE" in
  none)
    AUDIO_MAP_OPTS+=( -an )
    ;;
  first)
    # map audio from first input if present (the ? prevents ffmpeg from failing if no audio)
    AUDIO_MAP_OPTS+=( -map 0:a? )
    ;;
  mix)
    # Complex mixing of audio streams is non-trivial when inputs may lack audio.
    # For now fallback to first with a warning. Future improvement: add per-input anullsrc and amix.
    echo "AUDIO_MODE=mix requested but not fully supported; falling back to 'first'"
    AUDIO_MAP_OPTS+=( -map 0:a? )
    ;;
  *)
    echo "Unknown AUDIO_MODE='$AUDIO_MODE', defaulting to 'first'"
    AUDIO_MAP_OPTS+=( -map 0:a? )
    ;;
esac

# Supervisor loop: restart ffmpeg when it exits to improve resilience
run_ffmpeg() {
  while true; do
    echo "[merge.sh] Launching ffmpeg..."
    # start ffmpeg in foreground and wait for it
    ffmpeg "${IN_ARGS[@]}" \
      -filter_complex "$filter_complex" -map "[vout]" \
      -r "$FRAMERATE" -g "$GOP" -b:v "$VIDEO_BITRATE" \
      ${ENC_OPTS[@]} ${AUDIO_MAP_OPTS[@]} -bsf:v h264_mp4toannexb -f tee "$OUTS"

    rc=$?
    echo "[merge.sh] ffmpeg exited with code $rc"
    # if exit code is 0, assume intentional stop; exit loop
    if [ "$rc" -eq 0 ]; then
      echo "[merge.sh] ffmpeg exited normally, stopping supervisor."
      return 0
    fi

    echo "[merge.sh] Restarting ffmpeg in 3s..."
    sleep 3
  done
}

# Forward signals to child ffmpeg (best effort)
trap 'echo "[merge.sh] Caught SIGTERM/SIGINT, exiting"; exit 0' INT TERM

run_ffmpeg