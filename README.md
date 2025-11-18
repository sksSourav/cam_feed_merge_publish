# cam_feed_merge_publish

This project pulls multiple camera streams (RTSP/HTTP), merges them into a grid and publishes the merged stream to a local MediaMTX RTMP endpoint and optionally to YouTube.

Files of interest:
- `Dockerfile` - container image build
- `entrypoint.sh` - starts MediaMTX and waits for RTMP port
- `merge.sh` - constructs ffmpeg command to merge camera inputs and push to RTMP
- `mediamtx.yml` - MediaMTX configuration

Quick start (build locally):

```bash
# Build multi-arch image (requires docker buildx)
docker buildx create --use --name multiarch || true
docker buildx inspect --bootstrap
docker buildx build --platform linux/amd64,linux/arm64 --pull -t 43124312/cam-feed-merge-publish:latest --push .
```

Run locally (example):

```bash
docker run -it --rm \
  -e CAM_URLS="rtsp://user:pass@192.168.1.10:554/stream1,rtsp://user:pass@192.168.1.11:554/stream1" \
  -p 8554:8554 -p 1935:1935 -p 8888:8888 \
  43124312/cam-feed-merge-publish:latest
```

If you want to forward to YouTube live, set `YOUTUBE_KEY`:

```bash
-e YOUTUBE_KEY="<your_stream_key>"
```

 - `CAM_URLS` (required) - comma-separated list of input streams
 - `TILE_W` (default `640`) - tile width
 - `AUDIO_MODE` (optional) - `none|first|mix` (default `first`). `first` maps audio from the first input; `mix` is a placeholder and currently falls back to `first`.
- `FRAMERATE` (default `25`)
- `GOP` (default `50`)
- `ENCODER` (default `libx264`)
- `YOUTUBE_KEY` (optional)

Notes and recommendations:
- `merge.sh` builds a square grid with the smallest size >= number of inputs (e.g. 3 -> 2x2). Empty slots are filled with black frames.
- The container includes `mediamtx` binary and `netcat` for the entrypoint wait.
- If you use many high-resolution streams, increase CPU resources for the container and lower output bitrate or tile size.

Next improvements you may want:
- Add a healthcheck for MediaMTX in the Dockerfile
- Add automated restart/reconnect logic per-input (ffmpeg can reconnect but you may want wrappers)
- Add audio mixing support or pass-through
- Add metrics/logging and monitoring

