# Build stage: Build rcon-cli from source
FROM golang:1.27-alpine AS rcon-cli-builder

# Pinned: itzg/rcon-cli tag 1.7.9. Its tags have no "v", so Go cannot resolve
# them as versions and "@latest" would build whatever the main branch holds.
ARG RCON_CLI_COMMIT=84dadd478472579757df35909e9d24e65593e0ad
RUN apk add --no-cache git && \
    go install github.com/itzg/rcon-cli@${RCON_CLI_COMMIT} && \
    cp /go/bin/rcon-cli /usr/local/bin/rcon-cli

# Build stage: the RCON password hasher (the final image has only a Java
# runtime, no compiler)
FROM eclipse-temurin:25-jdk-alpine AS rcon-hash-builder
COPY scripts/java/RconHash.java /src/RconHash.java
RUN javac -d /out /src/RconHash.java

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
    util-linux \
    openssl \
    gcompat

# Copy rcon-cli from build stage; /usr/local/bin/rcon-cli is a wrapper that
# finds the password (scripts/tools/rcon-cli.sh)
COPY --from=rcon-cli-builder /usr/local/bin/rcon-cli /usr/local/lib/rcon-cli/rcon-cli
COPY --from=rcon-hash-builder /out/ /usr/local/lib/rcon-hash/
RUN chmod +x /usr/local/lib/rcon-cli/rcon-cli && \
    /usr/local/lib/rcon-cli/rcon-cli --help > /dev/null && \
    echo "rcon-cli installed successfully" && \
    printf 'build-test' | java -cp /usr/local/lib/rcon-hash RconHash | grep -q '^pbkdf2-sha512:210000:' && \
    echo "RCON password hasher installed successfully"

# Create default hytale user (will be modified at runtime if HOST_UID/HOST_GID are set)
RUN addgroup -g 1000 hytale && \
    adduser -D -u 1000 -G hytale hytale

COPY scripts/steps/* /init-container/
COPY scripts/tools/* /usr/local/bin/
RUN chmod +x /init-container/* && \
    chmod +x /usr/local/bin/* && \
    ln -sf /usr/local/bin/gen-psswd.sh /usr/local/bin/gen-psswd && \
    ln -sf /usr/local/bin/hy-restart.sh /usr/local/bin/hy-restart && \
    ln -sf /usr/local/bin/rcon-cli.sh /usr/local/bin/rcon-cli

VOLUME ["/data"]
WORKDIR /data
EXPOSE 5520/udp

# Healthy while starting up (up to HEALTH_STARTUP_MINUTES) and while the server
# runs and answers over RCON; see scripts/tools/hy-health.sh
HEALTHCHECK --interval=30s --timeout=15s --start-period=2m --retries=3 CMD ["/usr/local/bin/hy-health.sh"]

STOPSIGNAL SIGTERM
# Run as root to allow runtime UID/GID modification via HOST_UID/HOST_GID
# Script will drop privileges to hytale user (or custom UID/GID) before starting server
ENTRYPOINT ["/init-container/00-c-init.sh"]
