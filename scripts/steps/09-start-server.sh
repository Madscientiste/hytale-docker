#!/bin/sh
# Start Hytale server with authentication

# Get script directory and source common utilities
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"

HYTALE_DATA_DIR="/data"

log_section "Starting Hytale Server"

# Verify required files exist
if [ ! -f "${HYTALE_DATA_DIR}/HytaleServer.jar" ]; then
    error_exit "HytaleServer.jar not found at ${HYTALE_DATA_DIR}/HytaleServer.jar"
fi

if [ ! -f "${HYTALE_DATA_DIR}/Assets.zip" ]; then
    error_exit "Assets.zip not found at ${HYTALE_DATA_DIR}/Assets.zip"
fi

# Verify credentials are loaded
if [ -z "${SESSION_TOKEN:-}" ] || [ -z "${IDENTITY_TOKEN:-}" ] || [ -z "${OWNER_UUID:-}" ]; then
    error_exit "Authentication credentials not loaded. SESSION_TOKEN, IDENTITY_TOKEN, and OWNER_UUID must be set."
fi

log_info "Server will use authentication credentials from step 4"
log_info "On first start, the server will automatically generate an encrypted credentials store: auth.enc"
log_info "  This file enables the server to persist session tokens and maintain authentication while running."
log_info "  Note: If the container is restarted and tokens have expired, you may need to re-authenticate to obtain a fresh token."

# Build JVM arguments from environment variables
INIT_MEMORY="${INIT_MEMORY:-12G}"
MAX_MEMORY="${MAX_MEMORY:-12G}"

# Build JVM command
JVM_OPTS_BASE="-Xms${INIT_MEMORY} -Xmx${MAX_MEMORY}"
JVM_OPTS_BASE="$JVM_OPTS_BASE -XX:+UseG1GC"
JVM_OPTS_BASE="$JVM_OPTS_BASE -XX:MaxGCPauseMillis=200"
JVM_OPTS_BASE="$JVM_OPTS_BASE -XX:+UnlockExperimentalVMOptions"
JVM_OPTS_BASE="$JVM_OPTS_BASE -XX:+DisableExplicitGC"
JVM_OPTS_BASE="$JVM_OPTS_BASE -XX:+UseStringDeduplication"
JVM_OPTS_BASE="$JVM_OPTS_BASE -XX:G1NewSizePercent=30"
JVM_OPTS_BASE="$JVM_OPTS_BASE -XX:G1MaxNewSizePercent=40"
JVM_OPTS_BASE="$JVM_OPTS_BASE -XX:G1HeapRegionSize=32M"
JVM_OPTS_BASE="$JVM_OPTS_BASE -XX:G1ReservePercent=20"
JVM_OPTS_BASE="$JVM_OPTS_BASE -XX:InitiatingHeapOccupancyPercent=15"
JVM_OPTS_BASE="$JVM_OPTS_BASE -Dfile.encoding=UTF-8"
JVM_OPTS_BASE="$JVM_OPTS_BASE --enable-native-access=ALL-UNNAMED"

# Add additional JVM options if provided
if [ -n "${JVM_OPTS:-}" ]; then
    JVM_OPTS_BASE="$JVM_OPTS_BASE $JVM_OPTS"
fi

if [ -n "${JVM_XX_OPTS:-}" ]; then
    JVM_OPTS_BASE="$JVM_XX_OPTS $JVM_OPTS_BASE"
fi

log_info "Memory: ${INIT_MEMORY} / ${MAX_MEMORY}"
log_debug "JVM Options: $JVM_OPTS_BASE"

# Configure backup settings
ENABLE_BACKUPS="${ENABLE_BACKUPS:-true}"
BACKUP_DIR="${BACKUP_DIR:-/data/backups}"
BACKUP_FREQUENCY="${BACKUP_FREQUENCY:-30}"
BACKUP_MAX_COUNT="${BACKUP_MAX_COUNT:-5}"

# Validate BACKUP_DIR is absolute (must start with /) and build backup flags
if [ "$ENABLE_BACKUPS" = "true" ]; then
    case "$BACKUP_DIR" in
        /*) ;;
        *) error_exit "BACKUP_DIR must be an absolute path (starting with /), got: $BACKUP_DIR" ;;
    esac
    log_info "Backups enabled: dir=$BACKUP_DIR, frequency=${BACKUP_FREQUENCY}min, max=${BACKUP_MAX_COUNT}"
else
    log_info "Backups disabled"
fi

# Change to data directory
cd "${HYTALE_DATA_DIR}"

# Start server with authentication
log_info "Starting Hytale server..."
if [ "$ENABLE_BACKUPS" = "true" ]; then
    exec java $JVM_OPTS_BASE \
        -jar HytaleServer.jar \
        --assets Assets.zip \
        --session-token "$SESSION_TOKEN" \
        --identity-token "$IDENTITY_TOKEN" \
        --owner-uuid "$OWNER_UUID" \
        ${OWNER_NAME:+--owner-name "$OWNER_NAME"} \
        ${BIND_ADDRESS:+--bind "$BIND_ADDRESS"} \
        ${TRANSPORT_TYPE:+--transport "$TRANSPORT_TYPE"} \
        ${AUTH_MODE:+--auth-mode "$AUTH_MODE"} \
        --backup \
        --backup-dir "$BACKUP_DIR" \
        --backup-frequency "$BACKUP_FREQUENCY" \
        --backup-max-count "$BACKUP_MAX_COUNT"
else
    exec java $JVM_OPTS_BASE \
        -jar HytaleServer.jar \
        --assets Assets.zip \
        --session-token "$SESSION_TOKEN" \
        --identity-token "$IDENTITY_TOKEN" \
        --owner-uuid "$OWNER_UUID" \
        ${OWNER_NAME:+--owner-name "$OWNER_NAME"} \
        ${BIND_ADDRESS:+--bind "$BIND_ADDRESS"} \
        ${TRANSPORT_TYPE:+--transport "$TRANSPORT_TYPE"} \
        ${AUTH_MODE:+--auth-mode "$AUTH_MODE"}
fi
