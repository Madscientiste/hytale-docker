# Build stage: Build rcon-cli from source
FROM golang:1.23-alpine AS rcon-cli-builder

RUN apk add --no-cache git && \
    go install github.com/itzg/rcon-cli@latest && \
    cp /go/bin/rcon-cli /usr/local/bin/rcon-cli

# Final stage: Hytale server image
FROM eclipse-temurin:25-jre-alpine

# Image metadata and credits
LABEL org.opencontainers.image.title="Hytale Server"
LABEL org.opencontainers.image.description="A Docker container for running Hytale game servers with automated authentication, server file management, and configuration"
LABEL org.opencontainers.image.url="https://github.com/Madscientiste/hytale-docker"
LABEL org.opencontainers.image.source="https://github.com/Madscientiste/hytale-docker"
LABEL org.opencontainers.image.vendor="Madscientiste"
LABEL org.opencontainers.image.authors="Madscientiste"
LABEL org.opencontainers.image.licenses="MIT License"
LABEL maintainer="Madscientiste"
LABEL repository="https://github.com/Madscientiste/hytale-docker"

ENV JAVA_HOME=/opt/java/openjdk \
    PATH="/opt/java/openjdk/bin:${PATH}"

RUN apk add --no-cache \
    ca-certificates \
    curl \
    jq \
    unzip \
    shadow \
    su-exec \
    libgcc \
    libstdc++ \
    gcompat

# Copy rcon-cli from build stage
COPY --from=rcon-cli-builder /usr/local/bin/rcon-cli /usr/local/bin/rcon-cli
RUN chmod +x /usr/local/bin/rcon-cli && \
    rcon-cli --help > /dev/null && \
    echo "rcon-cli installed successfully"

# Create default hytale user (will be modified at runtime if HOST_UID/HOST_GID are set)
RUN addgroup -g 1000 hytale && \
    adduser -D -u 1000 -G hytale hytale

COPY scripts/steps/* /init-container/
COPY scripts/tools/* /usr/local/bin/
RUN chmod +x /init-container/* && \
    chmod +x /usr/local/bin/*

VOLUME ["/data"]
WORKDIR /data
EXPOSE 5520/udp 25575/tcp

STOPSIGNAL SIGTERM
# Run as root to allow runtime UID/GID modification via HOST_UID/HOST_GID
# Script will drop privileges to hytale user (or custom UID/GID) before starting server
ENTRYPOINT ["/init-container/00-c-init.sh"]
