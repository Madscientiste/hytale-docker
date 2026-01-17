#!/bin/sh
# Download Hytale server files using authenticated API

# Get script directory and source common utilities
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"

# Configuration from environment variables
VERSION="${VERSION:-LATEST}"
PATCHLINE="${PATCHLINE:-release}"
FORCE_DOWNLOAD="${FORCE_DOWNLOAD:-false}"
AUTH_FILE="/data/auth.json"
HYTALE_DATA_DIR="/data"

# Final paths
FINAL_JAR="${HYTALE_DATA_DIR}/HytaleServer.jar"
FINAL_ASSETS="${HYTALE_DATA_DIR}/Assets.zip"

# Check if download is needed
if [ "$FORCE_DOWNLOAD" != "true" ] && [ -f "$FINAL_JAR" ] && [ -f "$FINAL_ASSETS" ]; then
    log_info "Server files already exist. Skipping download."
    log_debug "Set FORCE_DOWNLOAD=true to force re-download"
    exit 0
fi

log_section "Downloading Hytale Server"

# Verify auth.json exists
if [ ! -f "$AUTH_FILE" ]; then
    error_exit "auth.json not found at $AUTH_FILE. Authentication must be completed first."
fi

log_info "Version: $VERSION"
log_info "Patchline: $PATCHLINE"
log_info "Using credentials: $AUTH_FILE"

# Build hy-downloader.sh command
HY_DOWNLOADER="/usr/local/bin/hy-downloader.sh"

# Set log level for hy-downloader (it uses LOG_LEVEL env var)
export LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Call hy-downloader.sh
log_step "1" "Downloading server files using hy-downloader..."
if "$HY_DOWNLOADER" \
    --auth-file "$AUTH_FILE" \
    --output-dir "$HYTALE_DATA_DIR" \
    --server-version "$VERSION" \
    --patchline "$PATCHLINE" \
    --simple-names \
    $([ "$FORCE_DOWNLOAD" = "true" ] && echo "--force"); then
    log_success "Server files downloaded successfully"
    
    # Verify files exist
    if [ ! -f "$FINAL_JAR" ]; then
        error_exit "HytaleServer.jar not found at $FINAL_JAR after download"
    fi
    
    if [ ! -f "$FINAL_ASSETS" ]; then
        error_exit "Assets.zip not found at $FINAL_ASSETS after download"
    fi
    
    log_success "Server files ready: HytaleServer.jar and Assets.zip"
else
    error_exit "Failed to download server files"
fi
