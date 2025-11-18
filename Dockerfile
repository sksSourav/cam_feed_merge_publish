FROM linuxserver/ffmpeg

ARG DEBIAN_FRONTEND=noninteractive
ARG MTX_VERSION=1.9.1

# Install utilities needed at runtime for orchestration and health checks
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3 \
        curl \
        ca-certificates \
        xz-utils \
        librtmp1 \
        netcat-openbsd \
    ; \
    rm -rf /var/lib/apt/lists/*;

# Download MediaMTX binary for the container architecture and make sure it's executable
RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "$ARCH" = "amd64" ]; then \
        MTX_URL="https://github.com/bluenviron/mediamtx/releases/download/v${MTX_VERSION}/mediamtx_v${MTX_VERSION}_linux_amd64.tar.gz"; \
    elif [ "$ARCH" = "arm64" ]; then \
        MTX_URL="https://github.com/bluenviron/mediamtx/releases/download/v${MTX_VERSION}/mediamtx_v${MTX_VERSION}_linux_arm64v8.tar.gz"; \
    else \
        echo "Unsupported arch: $ARCH" && exit 1; \
    fi; \
    curl -fL "$MTX_URL" | tar xz -C /usr/local/bin; \
    chmod +x /usr/local/bin/mediamtx || true

WORKDIR /app

# Copy configs and scripts
COPY merge.sh /app/merge.sh
COPY mediamtx.yml /app/mediamtx.yml
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/merge.sh /app/entrypoint.sh

# Expose ports for RTSP, RTMP and optional HLS
EXPOSE 8554 1935 8888

# Start MediaMTX + merger
ENTRYPOINT ["/app/entrypoint.sh"]
