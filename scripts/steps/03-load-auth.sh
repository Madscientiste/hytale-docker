#!/bin/sh
# Load authentication credentials from auth.json

# Get script directory and source common utilities
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"

HYTALE_DATA_DIR="/data"
AUTH_FILE="${HYTALE_DATA_DIR}/auth.json"

log_section "Loading Authentication Credentials"

# Check prerequisites
check_prerequisites jq

# Verify auth.json exists
if [ ! -f "$AUTH_FILE" ]; then
    error_exit "auth.json not found at $AUTH_FILE. Authentication must be completed first (step 1)."
fi

# Validate JSON format
if ! jq empty "$AUTH_FILE" 2>/dev/null; then
    error_exit "Invalid JSON format in $AUTH_FILE. Please run authentication again."
fi

log_step "1" "Extracting credentials from auth.json"

# Extract required tokens and identifiers
SESSION_TOKEN=$(jq -r '.session_token // empty' "$AUTH_FILE")
IDENTITY_TOKEN=$(jq -r '.identity_token // empty' "$AUTH_FILE")
OWNER_UUID=$(jq -r '.owner_uuid // empty' "$AUTH_FILE")
OWNER_NAME=$(jq -r '.owner_name // empty' "$AUTH_FILE")
EXPIRES_AT=$(jq -r '.expires_at // empty' "$AUTH_FILE")

# Validate required fields
if [ -z "$SESSION_TOKEN" ] || [ "$SESSION_TOKEN" = "null" ]; then
    error_exit "Missing session_token in $AUTH_FILE. Please run authentication again."
fi

if [ -z "$IDENTITY_TOKEN" ] || [ "$IDENTITY_TOKEN" = "null" ]; then
    error_exit "Missing identity_token in $AUTH_FILE. Please run authentication again."
fi

if [ -z "$OWNER_UUID" ] || [ "$OWNER_UUID" = "null" ]; then
    error_exit "Missing owner_uuid in $AUTH_FILE. Please run authentication again."
fi

log_success "Required credentials found"

# Export as environment variables for server startup
export SESSION_TOKEN
export IDENTITY_TOKEN
export OWNER_UUID

if [ -n "$OWNER_NAME" ] && [ "$OWNER_NAME" != "null" ]; then
    export OWNER_NAME
    log_info "Owner: $OWNER_NAME ($OWNER_UUID)"
else
    log_info "Owner UUID: $OWNER_UUID"
fi

if [ -n "$EXPIRES_AT" ] && [ "$EXPIRES_AT" != "null" ]; then
    log_info "Session expires at: $EXPIRES_AT"
fi

log_debug "Credentials loaded and exported as environment variables"
log_debug "Server will use these credentials on startup"

# Note: Environment variables are exported and will be available to child processes
# The start-server script will use these exported variables

