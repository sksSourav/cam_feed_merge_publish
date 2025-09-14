#!/bin/sh
docker buildx create --use --name multiarch
docker buildx inspect --bootstrap
docker login
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t 43124312/cam-feed-merge-publish:latest \
  --push .

# docker run --rm -it \
# -e CAM_URLS="rtsp://uder:pass@192.168.178.100:554/stream1,rtsp://user:pass@192.168.178.100:554/stream2" \
# -p 8554:8554 -p 1935:1935 -p 8888:8888 \
# 43124312/cam-feed-merge-publish