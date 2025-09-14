FROM linuxserver/ffmpeg

ARG DEBIAN_FRONTEND=noninteractive
ARG MTX_VERSION=1.9.1

# Install ffmpeg + tools
RUN apt-get clean
RUN apt-get update
# RUN apt-get install -y --no-install-recommends software-properties-common
# RUN add-apt-repository universe
# RUN apt-get update
# RUN apt-get install -y --no-install-recommends ffmpeg
RUN apt-get install -y --no-install-recommends python3
RUN apt-get install -y --no-install-recommends curl
RUN apt-get install -y --no-install-recommends ca-certificates
RUN apt-get install -y --no-install-recommends xz-utils
RUN apt-get install -y --no-install-recommends librtmp1

# RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.edge.kernel.org/ubuntu/|g' /etc/apt/sources.list

RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "$ARCH" = "amd64" ]; then \
        MTX_URL="https://github.com/bluenviron/mediamtx/releases/download/v${MTX_VERSION}/mediamtx_v${MTX_VERSION}_linux_amd64.tar.gz"; \
    elif [ "$ARCH" = "arm64" ]; then \
        MTX_URL="https://github.com/bluenviron/mediamtx/releases/download/v${MTX_VERSION}/mediamtx_v${MTX_VERSION}_linux_arm64v8.tar.gz"; \
    else \
        echo "Unsupported arch: $ARCH" && exit 1; \
    fi; \
    curl -L "$MTX_URL" | tar xz -C /usr/local/bin


WORKDIR /app

# Copy configs
COPY merge.sh /app/merge.sh
COPY mediamtx.yml /app/mediamtx.yml
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/merge.sh
RUN chmod +x /app/entrypoint.sh

# Expose ports
EXPOSE 8554 1935 8888

# Start MediaMTX + merge
ENTRYPOINT ["/app/entrypoint.sh"]
