#!/bin/sh
set -e

# Start MediaMTX in the background
mediamtx /app/mediamtx.yml &

# Wait a bit to ensure it’s ready
sleep 2

# Run the merger
exec /app/merge.sh