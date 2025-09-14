#!/bin/sh
set -e

# Start MediaMTX in the background
mediamtx /app/mediamtx.yml &

# Wait for RTMP server to be up (port 1935)
until nc -z 127.0.0.1 1935; do
  echo "Waiting for RTMP server to start..."
  sleep 5
done

# Run the merger
exec /app/merge.sh