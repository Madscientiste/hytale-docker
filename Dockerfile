FROM eclipse-temurin:25-jre-alpine

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

# Create default hytale user (will be modified at runtime if HOST_UID/HOST_GID are set)
RUN addgroup -g 1000 hytale && \
    adduser -D -u 1000 -G hytale hytale

COPY --chmod=755 scripts/steps/* /init-container/
COPY --chmod=755 scripts/tools/* /usr/local/bin/

VOLUME ["/data"]
WORKDIR /data
EXPOSE 5520/udp

STOPSIGNAL SIGTERM
# Run as root to allow runtime UID/GID modification via HOST_UID/HOST_GID
# Script will drop privileges to hytale user (or custom UID/GID) before starting server
ENTRYPOINT ["/init-container/00-c-init.sh"]
