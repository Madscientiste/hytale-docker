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

# Temporary paths (work in temp until ready)
TEMP_DIR="${HYTALE_DATA_DIR}/.tmp-download"
TEMP_DOWNLOAD="${TEMP_DIR}/game.zip"
TEMP_EXTRACT="${TEMP_DIR}/extracted"

# Final paths
FINAL_JAR="${HYTALE_DATA_DIR}/HytaleServer.jar"
FINAL_ASSETS="${HYTALE_DATA_DIR}/Assets.zip"

# API endpoints
API_BASE="https://account-data.hytale.com"
OAUTH_BASE="https://oauth.accounts.hytale.com"

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

# Extract access token from auth.json
ACCESS_TOKEN=$(grep '"access_token"' "$AUTH_FILE" | sed 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)

if [ -z "$ACCESS_TOKEN" ]; then
    error_exit "Could not extract access_token from $AUTH_FILE"
fi

log_info "Version: $VERSION"
log_info "Patchline: $PATCHLINE"
log_info "Using credentials: $AUTH_FILE"

# Create temp directory
mkdir -p "$TEMP_DIR" "$TEMP_EXTRACT"

# Cleanup function
cleanup_temp() {
    if [ -d "$TEMP_DIR" ]; then
        log_debug "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
}

# Cleanup on exit
trap cleanup_temp EXIT INT TERM

log_step "1" "Getting version manifest for patchline: $PATCHLINE"
MANIFEST_URL="${API_BASE}/game-assets/version/${PATCHLINE}.json"

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$MANIFEST_URL" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

if [ "$HTTP_CODE" != "200" ]; then
    error_exit "Failed to get manifest (HTTP $HTTP_CODE): $BODY"
fi

# Extract signed URL for manifest
SIGNED_MANIFEST_URL=$(echo "$BODY" | grep -o '"url":"[^"]*"' | sed 's/"url":"\([^"]*\)"/\1/' | sed 's/\\u0026/\&/g')

if [ -z "$SIGNED_MANIFEST_URL" ]; then
    error_exit "No signed URL in manifest response"
fi

log_success "Got signed manifest URL"

log_step "2" "Fetching manifest content..."
MANIFEST=$(curl -s "$SIGNED_MANIFEST_URL")

# Parse manifest JSON
MANIFEST_VERSION=$(echo "$MANIFEST" | python3 -c "import sys, json; print(json.load(sys.stdin).get('version', ''))" 2>/dev/null || \
    echo "$MANIFEST" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

DOWNLOAD_PATH=$(echo "$MANIFEST" | python3 -c "import sys, json; print(json.load(sys.stdin).get('download_url', ''))" 2>/dev/null || \
    echo "$MANIFEST" | grep -o '"download_url"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

EXPECTED_SHA256=$(echo "$MANIFEST" | python3 -c "import sys, json; print(json.load(sys.stdin).get('sha256', ''))" 2>/dev/null || \
    echo "$MANIFEST" | grep -o '"sha256"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if [ -z "$DOWNLOAD_PATH" ]; then
    error_exit "No download_url in manifest"
fi

log_success "Manifest retrieved"
log_info "  Version: $MANIFEST_VERSION"
log_info "  Download path: $DOWNLOAD_PATH"
if [ -n "$EXPECTED_SHA256" ]; then
    log_info "  SHA256: ${EXPECTED_SHA256:0:16}..."
fi

# Check if specific version was requested
if [ "$VERSION" != "LATEST" ] && [ "$VERSION" != "$MANIFEST_VERSION" ]; then
    log_warn "Requested version $VERSION but manifest shows $MANIFEST_VERSION"
    log_warn "Continuing with manifest version..."
fi

log_step "3" "Getting signed download URL..."
DOWNLOAD_URL_ENDPOINT="${API_BASE}/game-assets/${DOWNLOAD_PATH}"

DOWNLOAD_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$DOWNLOAD_URL_ENDPOINT" 2>&1)

DOWNLOAD_HTTP_CODE=$(echo "$DOWNLOAD_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
DOWNLOAD_BODY=$(echo "$DOWNLOAD_RESPONSE" | sed '/HTTP_CODE:/d')

if [ "$DOWNLOAD_HTTP_CODE" != "200" ]; then
    error_exit "Failed to get signed download URL (HTTP $DOWNLOAD_HTTP_CODE): $DOWNLOAD_BODY"
fi

SIGNED_DOWNLOAD_URL=$(echo "$DOWNLOAD_BODY" | grep -o '"url":"[^"]*"' | sed 's/"url":"\([^"]*\)"/\1/' | sed 's/\\u0026/\&/g')

if [ -z "$SIGNED_DOWNLOAD_URL" ]; then
    error_exit "No signed URL in download response"
fi

log_success "Got signed download URL (expires in 6 hours)"

log_step "4" "Downloading game file to temporary location..."
log_info "Output: $TEMP_DOWNLOAD"
log_info "This may take a while..."

# Download with progress
if curl -L --progress-bar -o "$TEMP_DOWNLOAD" "$SIGNED_DOWNLOAD_URL"; then
    FILE_SIZE=$(du -h "$TEMP_DOWNLOAD" | cut -f1)
    log_success "Download complete! File size: $FILE_SIZE"
else
    error_exit "Download failed"
fi

if [ ! -f "$TEMP_DOWNLOAD" ]; then
    error_exit "Downloaded file not found at $TEMP_DOWNLOAD"
fi

log_step "5" "Verifying SHA256 checksum..."
if [ -n "$EXPECTED_SHA256" ]; then
    ACTUAL_SHA256=$(sha256sum "$TEMP_DOWNLOAD" | cut -d' ' -f1)
    if [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ]; then
        log_success "Checksum verified!"
    else
        error_exit "Checksum mismatch! Expected: $EXPECTED_SHA256, Actual: $ACTUAL_SHA256"
    fi
else
    log_warn "No SHA256 in manifest, skipping verification"
fi

log_step "6" "Extracting server files to temporary location..."
cd "$TEMP_EXTRACT"

if unzip -q -o "$TEMP_DOWNLOAD" -d "$TEMP_EXTRACT"; then
    log_success "Files extracted successfully"
else
    error_exit "Failed to extract server files"
fi

# Find HytaleServer.jar and Assets.zip
TEMP_JAR=""
TEMP_ASSETS=""

# Check root of extract directory
if [ -f "$TEMP_EXTRACT/HytaleServer.jar" ]; then
    TEMP_JAR="$TEMP_EXTRACT/HytaleServer.jar"
elif [ -f "$TEMP_EXTRACT/Server/HytaleServer.jar" ]; then
    TEMP_JAR="$TEMP_EXTRACT/Server/HytaleServer.jar"
fi

if [ -f "$TEMP_EXTRACT/Assets.zip" ]; then
    TEMP_ASSETS="$TEMP_EXTRACT/Assets.zip"
elif [ -f "$TEMP_EXTRACT/Server/Assets.zip" ]; then
    TEMP_ASSETS="$TEMP_EXTRACT/Server/Assets.zip"
fi

# Verify required files exist
if [ -z "$TEMP_JAR" ]; then
    error_exit "HytaleServer.jar not found after extraction"
fi

if [ -z "$TEMP_ASSETS" ]; then
    error_exit "Assets.zip not found after extraction"
fi

log_success "Required files found in temporary location"
log_info "  HytaleServer.jar: $TEMP_JAR"
log_info "  Assets.zip: $TEMP_ASSETS"

log_step "7" "Moving files to final location..."
# Move files to final location atomically
if mv "$TEMP_JAR" "$FINAL_JAR" && mv "$TEMP_ASSETS" "$FINAL_ASSETS"; then
    log_success "Files moved to final location"
else
    error_exit "Failed to move files to final location"
fi

# Verify final files exist
if [ ! -f "$FINAL_JAR" ]; then
    error_exit "HytaleServer.jar not found at final location"
fi

if [ ! -f "$FINAL_ASSETS" ]; then
    error_exit "Assets.zip not found at final location"
fi

log_success "Server files ready: HytaleServer.jar and Assets.zip"
log_info "Version: $MANIFEST_VERSION"

# Cleanup temp files (trap will handle if we exit early)
cleanup_temp
