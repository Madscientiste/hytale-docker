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

log_info "Server will use the Hytale login loaded in step 5 (refreshed automatically, see docs/authentication.md)"

. "${SCRIPT_DIR}/_server-options.sh"

# Server options from the environment (see _server-options.sh). 07-server-
# options.sh already checked them; a failure here stops the container too.
option_args=$(server_option_args) || error_exit "Fix the setting above, then start the container again"
backup_args=$(server_backup_args) || error_exit "Fix the setting above, then start the container again"
eval "set -- $option_args $backup_args"
# SERVER_ARGS: any other server option, split on spaces (no * expansion)
set -f
set -- "$@" ${SERVER_ARGS:-}
set +f

JVM_OPTS_BASE=$(server_jvm_options)
if [ -f "${HYTALE_DATA_DIR}/HytaleServer.aot" ]; then
    log_info "AOT cache: enabled (HytaleServer.aot)"
else
    log_debug "AOT cache: HytaleServer.aot not found, starting without it"
fi

log_info "Memory: ${INIT_MEMORY:-12G} / ${MAX_MEMORY:-12G}"
log_debug "JVM Options: $JVM_OPTS_BASE"
if [ "$ENABLE_BACKUPS" = "true" ]; then
    log_info "Backups enabled: dir=$BACKUP_DIR, frequency=${BACKUP_FREQUENCY}min, max=${BACKUP_MAX_COUNT}"
else
    log_info "Backups disabled"
fi
log_debug "Server options: $*"

# Change to data directory
cd "${HYTALE_DATA_DIR}"

# Hand the tokens to the server through the environment variables it reads
# when --session-token/--identity-token are absent. Command-line arguments are
# visible to every user on the host (ps, /proc/*/cmdline); the environment is not.
export HYTALE_SERVER_SESSION_TOKEN="$SESSION_TOKEN"
export HYTALE_SERVER_IDENTITY_TOKEN="$IDENTITY_TOKEN"
unset SESSION_TOKEN IDENTITY_TOKEN

log_info "Starting Hytale server..."
exec java $JVM_OPTS_BASE \
    -jar HytaleServer.jar \
    --assets Assets.zip \
    --owner-uuid "$OWNER_UUID" \
    "$@"
