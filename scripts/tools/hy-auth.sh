#!/bin/sh
set -e

# Common utilities and logging functions for Hytale server scripts

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Log levels
LOG_ERROR=1
LOG_WARN=2
LOG_INFO=3
LOG_DEBUG=4

# Default log level (can be overridden by LOG_LEVEL env var)
DEFAULT_LOG_LEVEL=${LOG_LEVEL:-$LOG_INFO}

# Get current log level
get_log_level() {
    case "${LOG_LEVEL:-INFO}" in
        ERROR|error) echo $LOG_ERROR ;;
        WARN|warn) echo $LOG_WARN ;;
        INFO|info) echo $LOG_INFO ;;
        DEBUG|debug) echo $LOG_DEBUG ;;
        *) echo $LOG_INFO ;;
    esac
}

# Check if we should log at this level
should_log() {
    local level=$1
    local current_level=$(get_log_level)
    [ $level -le $current_level ]
}

# Log functions
log_error() {
    if should_log $LOG_ERROR; then
        echo -e "${RED}[ERROR]${NC} $*" >&2
    fi
}

log_warn() {
    if should_log $LOG_WARN; then
        echo -e "${YELLOW}[WARN]${NC} $*" >&2
    fi
}

log_info() {
    if should_log $LOG_INFO; then
        echo -e "${CYAN}[INFO]${NC} $*"
    fi
}

log_debug() {
    if should_log $LOG_DEBUG; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

log_success() {
    if should_log $LOG_INFO; then
        echo -e "${GREEN}[SUCCESS]${NC} $*"
    fi
}

# Section header
log_section() {
    if should_log $LOG_INFO; then
        echo ""
        echo -e "${BOLD}${MAGENTA}==========================================${NC}"
        echo -e "${BOLD}${MAGENTA}  $*${NC}"
        echo -e "${BOLD}${MAGENTA}==========================================${NC}"
        echo ""
    fi
}

# Step indicator
log_step() {
    if should_log $LOG_INFO; then
        echo -e "${CYAN}Step $1:${NC} $2"
    fi
}

# Error exit function
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    local missing=0
    
    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            log_error "$cmd is required but not installed"
            missing=$((missing + 1))
        fi
    done
    
    if [ $missing -gt 0 ]; then
        error_exit "Missing $missing required prerequisite(s)"
    fi
}


# Hytale Server Authorization CLI
# Implements Device Code Flow (RFC 8628) for OAuth authentication

# Version
SCRIPT_VERSION="1.0.0"

# API Configuration
CLIENT_ID="hytale-server"
DEVICE_AUTH_URL="https://oauth.accounts.hytale.com/oauth2/device/auth"
TOKEN_URL="https://oauth.accounts.hytale.com/oauth2/token"
PROFILES_URL="https://account-data.hytale.com/my-account/get-profiles"
SESSION_URL="https://sessions.hytale.com/game-session/new"

# Default values
AUTH_FILE=""
VERBOSE=false
QUIET=false
REFRESH_MODE=false
REFRESH_AUTH_FILE=""

# Show help message
show_help() {
    cat <<EOF
hy-auth - Hytale Server Authorization CLI

USAGE:
    hy-auth [OPTIONS] [OUTPUT_PATH]

DESCRIPTION:
    Authenticate with the Hytale server API using OAuth 2.0 Device Code Flow.
    Handles the complete authentication flow from device code request through
    session token generation and credential storage.

OPTIONS:
    -h, --help
        Display this help message and exit.

    --version
        Display version information and exit.

    -o PATH, --output PATH, --save-credentials PATH
        Specify the output file path for saved credentials (REQUIRED).
        Supports both --save-credentials=path and --save-credentials path formats.

    -v, --verbose
        Enable verbose output (DEBUG log level).
        Shows detailed debug information during authentication flow.

    -q, --quiet
        Suppress non-error output (ERROR log level only).
        Only displays error messages.

    --refresh [AUTH_FILE]
        Refresh existing authentication tokens using stored refresh token.
        If AUTH_FILE is not specified, uses the output path from -o/--output.
        Exits after refresh (does not run full authentication flow).

POSITIONAL ARGUMENTS:
    OUTPUT_PATH (deprecated)
        Legacy positional argument for output file path.
        Use -o or --output instead.

EXAMPLES:
    # Authenticate with output path (required)
    hy-auth --output /path/to/auth.json
    hy-auth -o /path/to/auth.json

    # Show help
    hy-auth --help
    hy-auth -h

    # Verbose output
    hy-auth --verbose

    # Quiet mode
    hy-auth --quiet

    # Refresh tokens
    hy-auth --refresh
    hy-auth --refresh /path/to/auth.json

    # Combined options
    hy-auth -v -o /custom/path/auth.json
    hy-auth --quiet --refresh

EXIT CODES:
    0   Success
    1   Error (invalid arguments, authentication failure, etc.)

DEPENDENCIES:
    Required: curl
    Optional: jq (for robust JSON parsing)

EOF
}

# Show version information
show_version() {
    echo "hy-auth version $SCRIPT_VERSION"
}

# Parse command line arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -o|--output)
                if [ -z "$2" ]; then
                    error_exit "Option $1 requires an argument"
                fi
                AUTH_FILE="$2"
                shift 2
                ;;
            --save-credentials)
                if [ -z "$2" ]; then
                    error_exit "Option $1 requires an argument"
                fi
                AUTH_FILE="$2"
                shift 2
                ;;
            --save-credentials=*)
                AUTH_FILE="${1#*=}"
                shift
                ;;
            --refresh)
                REFRESH_MODE=true
                if [ -n "$2" ] && [ "$(echo "$2" | cut -c1)" != "-" ]; then
                    REFRESH_AUTH_FILE="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --*)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
            -*)
                # Handle short options that might be grouped
                case "$1" in
                    -h*)
                        show_help
                        exit 0
                        ;;
                    -v*)
                        VERBOSE=true
                        # Check if there are more characters after -v
                        remaining="${1#-v}"
                        if [ -n "$remaining" ]; then
                            # Re-process remaining as new argument
                            set -- "-$remaining" "$@"
                        fi
                        shift
                        ;;
                    -q*)
                        QUIET=true
                        remaining="${1#-q}"
                        if [ -n "$remaining" ]; then
                            set -- "-$remaining" "$@"
                        fi
                        shift
                        ;;
                    -o*)
                        # -o can have value attached: -opath or -o path
                        remaining="${1#-o}"
                        if [ -n "$remaining" ]; then
                            AUTH_FILE="$remaining"
                        elif [ -n "$2" ]; then
                            AUTH_FILE="$2"
                            shift
                        else
                            error_exit "Option -o requires an argument"
                        fi
                        shift
                        ;;
                    *)
                        error_exit "Unknown option: $1. Use --help for usage information."
                        ;;
                esac
                ;;
            *)
                # Positional argument (backward compatibility)
                if [ -z "$AUTH_FILE" ]; then
                    AUTH_FILE="$1"
                else
                    error_exit "Unexpected argument: $1. Use --help for usage information."
                fi
                shift
                ;;
        esac
    done
}

# Set log level based on flags
set_log_level() {
    if [ "$VERBOSE" = true ] && [ "$QUIET" = true ]; then
        error_exit "Cannot use --verbose and --quiet together"
    fi
    
    if [ "$VERBOSE" = true ]; then
        export LOG_LEVEL=DEBUG
    elif [ "$QUIET" = true ]; then
        export LOG_LEVEL=ERROR
    fi
}

# Simple JSON value extractor (fallback when jq is not available)
json_get() {
    local key="$1"
    local json="$2"
    if [ "$USE_JQ" = true ]; then
        echo "$json" | jq -r ".$key // empty"
    else
        echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\"/\1/"
    fi
}

# Extract JSON value that might be a number
json_get_num() {
    local key="$1"
    local json="$2"
    if [ "$USE_JQ" = true ]; then
        echo "$json" | jq -r ".$key // empty"
    else
        echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*[0-9]*" | sed "s/\"$key\"[[:space:]]*:[[:space:]]*\([0-9]*\)/\1/"
    fi
}

# Try to refresh tokens (returns 0 on success, 1 on failure, doesn't exit)
try_refresh_tokens() {
    local auth_file="${REFRESH_AUTH_FILE:-$AUTH_FILE}"
    
    if [ ! -f "$auth_file" ]; then
        return 1
    fi
    
    # Validate JSON format
    if [ "$USE_JQ" = true ]; then
        if ! jq empty "$auth_file" 2>/dev/null; then
            return 1
        fi
    fi
    
    # Check if token is still valid (avoid unnecessary API calls)
    local expires_at
    if [ "$USE_JQ" = true ]; then
        expires_at=$(jq -r '.expires_at // empty' "$auth_file")
    else
        expires_at=$(json_get "expires_at" "$(cat "$auth_file")")
    fi
    
    if [ -n "$expires_at" ] && [ "$expires_at" != "null" ] && [ "$expires_at" != "" ]; then
        # Parse expiration time and check if still valid
        # expires_at is in ISO 8601 format: 2026-01-14T12:27:31.752017357Z
        local current_time=$(date -u +%s 2>/dev/null || date +%s 2>/dev/null)
        local expire_time=""
        
        # Try GNU date first (Linux)
        if expire_time=$(date -u -d "$expires_at" +%s 2>/dev/null); then
            : # Success
        # Try BSD date (macOS) - strip nanoseconds and Z suffix
        elif expire_time=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "${expires_at%.*Z}" +%s 2>/dev/null); then
            : # Success
        # Fallback: try parsing without microseconds
        else
            local iso_clean="${expires_at%.*Z}"
            expire_time=$(date -u -d "$iso_clean" +%s 2>/dev/null || echo "")
        fi
        
        if [ -n "$expire_time" ] && [ "$expire_time" != "" ] && [ "$expire_time" -gt 0 ] 2>/dev/null; then
            # Add 5 minute buffer (300 seconds) - refresh if expiring within 5 minutes
            local buffer_time=300
            local time_until_expiry=$((expire_time - current_time))
            
            if [ $time_until_expiry -gt $buffer_time ] 2>/dev/null; then
                local minutes_left=$((time_until_expiry / 60))
                log_info "Found existing credentials. Token is still valid (expires in ${minutes_left} minutes)."
                log_info "Skipping token refresh to avoid unnecessary API calls."
                return 0
            else
                local minutes_left=$((time_until_expiry / 60))
                if [ $minutes_left -lt 0 ] 2>/dev/null; then
                    log_info "Found existing credentials. Token has expired. Refreshing..."
                else
                    log_info "Found existing credentials. Token expires soon (in ${minutes_left} minutes). Refreshing..."
                fi
            fi
        else
            log_debug "Could not parse expiration time. Proceeding with refresh to be safe."
        fi
    fi
    
    # Extract refresh token
    local refresh_token
    if [ "$USE_JQ" = true ]; then
        refresh_token=$(jq -r '.refresh_token // empty' "$auth_file")
    else
        refresh_token=$(json_get "refresh_token" "$(cat "$auth_file")")
    fi
    
    if [ -z "$refresh_token" ] || [ "$refresh_token" = "null" ]; then
        return 1
    fi
    
    log_info "Found existing credentials. Attempting to refresh tokens..."
    
    # Request new tokens using refresh token
    local token_response
    token_response=$(curl -s -X POST "$TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID" \
        -d "grant_type=refresh_token" \
        -d "refresh_token=$refresh_token") || return 1
    
    if echo "$token_response" | grep -q "\"error\""; then
        return 1
    fi
    
    local access_token=$(json_get "access_token" "$token_response")
    local new_refresh_token=$(json_get "refresh_token" "$token_response")
    
    # Use new refresh token if provided, otherwise keep old one
    if [ -z "$new_refresh_token" ] || [ "$new_refresh_token" = "null" ]; then
        new_refresh_token="$refresh_token"
    fi
    
    if [ -z "$access_token" ]; then
        return 1
    fi
    
    # Get profiles with new access token
    local profiles_response
    profiles_response=$(curl -s -X GET "$PROFILES_URL" \
        -H "Authorization: Bearer $access_token") || return 1
    
    if echo "$profiles_response" | grep -q "\"error\""; then
        return 1
    fi
    
    local owner_uuid=$(json_get "owner" "$profiles_response")
    local profile_uuid
    local profile_username
    
    if [ "$USE_JQ" = true ]; then
        profile_uuid=$(echo "$profiles_response" | jq -r '.profiles[0].uuid // empty')
        profile_username=$(echo "$profiles_response" | jq -r '.profiles[0].username // empty')
    else
        profile_uuid=$(echo "$profiles_response" | grep -o '"uuid"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"uuid"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        profile_username=$(echo "$profiles_response" | grep -o '"username"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"username"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
    fi
    
    if [ -z "$profile_uuid" ]; then
        return 1
    fi
    
    # Create new game session
    local session_response
    session_response=$(curl -s -X POST "$SESSION_URL" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "{\"uuid\": \"$profile_uuid\"}") || return 1
    
    if echo "$session_response" | grep -q "\"error\""; then
        return 1
    fi
    
    local session_token=$(json_get "sessionToken" "$session_response")
    local identity_token=$(json_get "identityToken" "$session_response")
    local expires_at=$(json_get "expiresAt" "$session_response")
    
    if [ -z "$session_token" ] || [ -z "$identity_token" ]; then
        return 1
    fi
    
    # Create directory if needed
    local auth_dir=$(dirname "$auth_file")
    if [ ! -d "$auth_dir" ]; then
        mkdir -p "$auth_dir" || return 1
    fi
    
    if [ ! -w "$auth_dir" ]; then
        return 1
    fi
    
    if [ -f "$auth_file" ] && [ ! -w "$auth_file" ]; then
        return 1
    fi
    
    # Save updated credentials
    if [ "$USE_JQ" = true ]; then
        jq -n \
            --arg access_token "$access_token" \
            --arg refresh_token "$new_refresh_token" \
            --arg session_token "$session_token" \
            --arg identity_token "$identity_token" \
            --arg owner_uuid "$owner_uuid" \
            --arg owner_name "$profile_username" \
            --arg expires_at "$expires_at" \
            '{
                access_token: $access_token,
                refresh_token: $refresh_token,
                session_token: $session_token,
                identity_token: $identity_token,
                owner_uuid: $owner_uuid,
                owner_name: $owner_name,
                expires_at: $expires_at
            }' > "$auth_file" || return 1
    else
        cat > "$auth_file" <<EOF || return 1
{
  "access_token": "$access_token",
  "refresh_token": "$new_refresh_token",
  "session_token": "$session_token",
  "identity_token": "$identity_token",
  "owner_uuid": "$owner_uuid",
  "owner_name": "$profile_username",
  "expires_at": "$expires_at"
}
EOF
    fi
    
    echo ""
    log_section "Token Refresh Complete!"
    log_info "Credentials updated in: $auth_file"
    log_info "Session expires at: $expires_at"
    echo ""
    return 0
}

# Refresh existing tokens (explicit mode - exits on error)
refresh_tokens() {
    local auth_file="${REFRESH_AUTH_FILE:-$AUTH_FILE}"
    
    log_step "1" "Loading existing credentials from $auth_file"
    
    if [ ! -f "$auth_file" ]; then
        error_exit "Auth file not found: $auth_file"
    fi
    
    # Validate JSON format
    if [ "$USE_JQ" = true ]; then
        if ! jq empty "$auth_file" 2>/dev/null; then
            error_exit "Invalid JSON format in $auth_file"
        fi
    fi
    
    # Extract refresh token
    local refresh_token
    if [ "$USE_JQ" = true ]; then
        refresh_token=$(jq -r '.refresh_token // empty' "$auth_file")
    else
        refresh_token=$(json_get "refresh_token" "$(cat "$auth_file")")
    fi
    
    if [ -z "$refresh_token" ] || [ "$refresh_token" = "null" ]; then
        error_exit "No refresh token found in $auth_file. Please run full authentication."
    fi
    
    log_step "2" "Refreshing access token"
    
    # Request new tokens using refresh token
    local token_response
    token_response=$(curl -s -X POST "$TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID" \
        -d "grant_type=refresh_token" \
        -d "refresh_token=$refresh_token") || error_exit "Failed to refresh token"
    
    if echo "$token_response" | grep -q "\"error\""; then
        local error_msg=$(json_get "error" "$token_response")
        local error_desc=$(json_get "error_description" "$token_response")
        error_exit "Token refresh failed: $error_msg${error_desc:+ - $error_desc}"
    fi
    
    local access_token=$(json_get "access_token" "$token_response")
    local new_refresh_token=$(json_get "refresh_token" "$token_response")
    
    # Use new refresh token if provided, otherwise keep old one
    if [ -z "$new_refresh_token" ] || [ "$new_refresh_token" = "null" ]; then
        new_refresh_token="$refresh_token"
    fi
    
    if [ -z "$access_token" ]; then
        error_exit "Invalid token response: missing access_token"
    fi
    
    log_step "3" "Fetching profiles"
    
    # Get profiles with new access token
    local profiles_response
    profiles_response=$(curl -s -X GET "$PROFILES_URL" \
        -H "Authorization: Bearer $access_token") || error_exit "Failed to fetch profiles"
    
    if echo "$profiles_response" | grep -q "\"error\""; then
        local error_msg=$(json_get "error" "$profiles_response")
        error_exit "Failed to get profiles: $error_msg"
    fi
    
    local owner_uuid=$(json_get "owner" "$profiles_response")
    local profile_uuid
    local profile_username
    
    if [ "$USE_JQ" = true ]; then
        profile_uuid=$(echo "$profiles_response" | jq -r '.profiles[0].uuid // empty')
        profile_username=$(echo "$profiles_response" | jq -r '.profiles[0].username // empty')
    else
        profile_uuid=$(echo "$profiles_response" | grep -o '"uuid"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"uuid"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
        profile_username=$(echo "$profiles_response" | grep -o '"username"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"username"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
    fi
    
    if [ -z "$profile_uuid" ]; then
        error_exit "No profiles found"
    fi
    
    log_step "4" "Creating game session"
    
    # Create new game session
    local session_response
    session_response=$(curl -s -X POST "$SESSION_URL" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "{\"uuid\": \"$profile_uuid\"}") || error_exit "Failed to create game session"
    
    if echo "$session_response" | grep -q "\"error\""; then
        local error_msg=$(json_get "error" "$session_response")
        error_exit "Failed to create session: $error_msg"
    fi
    
    local session_token=$(json_get "sessionToken" "$session_response")
    local identity_token=$(json_get "identityToken" "$session_response")
    local expires_at=$(json_get "expiresAt" "$session_response")
    
    if [ -z "$session_token" ] || [ -z "$identity_token" ]; then
        error_exit "Invalid session response: missing tokens"
    fi
    
    log_step "5" "Saving updated credentials to $auth_file"
    
    # Create directory if needed
    local auth_dir=$(dirname "$auth_file")
    if [ ! -d "$auth_dir" ]; then
        mkdir -p "$auth_dir" || error_exit "Failed to create directory: $auth_dir"
    fi
    
    if [ ! -w "$auth_dir" ]; then
        error_exit "Cannot write to directory $auth_dir (permission denied)"
    fi
    
    if [ -f "$auth_file" ] && [ ! -w "$auth_file" ]; then
        error_exit "Cannot write to $auth_file (permission denied)"
    fi
    
    # Save updated credentials
    if [ "$USE_JQ" = true ]; then
        jq -n \
            --arg access_token "$access_token" \
            --arg refresh_token "$new_refresh_token" \
            --arg session_token "$session_token" \
            --arg identity_token "$identity_token" \
            --arg owner_uuid "$owner_uuid" \
            --arg owner_name "$profile_username" \
            --arg expires_at "$expires_at" \
            '{
                access_token: $access_token,
                refresh_token: $refresh_token,
                session_token: $session_token,
                identity_token: $identity_token,
                owner_uuid: $owner_uuid,
                owner_name: $owner_name,
                expires_at: $expires_at
            }' > "$auth_file"
    else
        cat > "$auth_file" <<EOF
{
  "access_token": "$access_token",
  "refresh_token": "$new_refresh_token",
  "session_token": "$session_token",
  "identity_token": "$identity_token",
  "owner_uuid": "$owner_uuid",
  "owner_name": "$profile_username",
  "expires_at": "$expires_at"
}
EOF
    fi
    
    echo ""
    log_section "Token Refresh Complete!"
    log_info "Credentials updated in: $auth_file"
    log_info "Session expires at: $expires_at"
    echo ""
}

# Parse command line arguments
parse_args "$@"

# Validate that output path is provided
if [ -z "$AUTH_FILE" ]; then
    error_exit "Output path is required. Use -o or --output to specify the credentials file path."
fi

# Set log level based on flags
set_log_level

# Check prerequisites
check_prerequisites curl

# Check if jq is available for JSON parsing
if command_exists jq; then
    USE_JQ=true
else
    USE_JQ=false
    log_warn "jq not found. Using basic JSON parsing (may be less robust)."
fi

# Handle explicit refresh mode
if [ "$REFRESH_MODE" = true ]; then
    # Use AUTH_FILE if REFRESH_AUTH_FILE not specified
    if [ -z "$REFRESH_AUTH_FILE" ]; then
        REFRESH_AUTH_FILE="$AUTH_FILE"
    fi
    refresh_tokens
    exit 0
fi

# Auto-refresh: if auth file exists, try to refresh tokens
# Only proceed with device auth flow if refresh fails or file doesn't exist
# Resolve relative paths to absolute paths for consistent checking
if [ "$(echo "$AUTH_FILE" | cut -c1)" != "/" ]; then
    # Relative path - resolve it relative to current working directory
    if [ -d "$(dirname "$AUTH_FILE")" ]; then
        AUTH_FILE="$(cd "$(dirname "$AUTH_FILE")" 2>/dev/null && pwd)/$(basename "$AUTH_FILE")"
    else
        # If directory doesn't exist, use current working directory
        AUTH_FILE="$(pwd)/$AUTH_FILE"
    fi
fi

if [ -f "$AUTH_FILE" ]; then
    log_info "Found existing credentials at $AUTH_FILE. Attempting to refresh tokens..."
    if try_refresh_tokens; then
        exit 0
    else
        log_info "Token refresh failed or credentials expired. Starting new authentication flow..."
        echo ""
    fi
else
    log_debug "No existing credentials file found at $AUTH_FILE. Starting new authentication flow..."
fi

# Step 1: Request Device Code
log_step "1" "Requesting device code"
DEVICE_RESPONSE=$(curl -s -X POST "$DEVICE_AUTH_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$CLIENT_ID" \
    -d "scope=openid offline auth:server") || error_exit "Failed to request device code"

# Check for errors in response
if echo "$DEVICE_RESPONSE" | grep -q "\"error\""; then
    ERROR_MSG=$(json_get "error" "$DEVICE_RESPONSE")
    ERROR_DESC=$(json_get "error_description" "$DEVICE_RESPONSE")
    error_exit "Device code request failed: $ERROR_MSG${ERROR_DESC:+ - $ERROR_DESC}"
fi

DEVICE_CODE=$(json_get "device_code" "$DEVICE_RESPONSE")
USER_CODE=$(json_get "user_code" "$DEVICE_RESPONSE")
VERIFICATION_URI=$(json_get "verification_uri" "$DEVICE_RESPONSE")
VERIFICATION_URI_COMPLETE=$(json_get "verification_uri_complete" "$DEVICE_RESPONSE")
EXPIRES_IN=$(json_get_num "expires_in" "$DEVICE_RESPONSE")
INTERVAL=$(json_get_num "interval" "$DEVICE_RESPONSE")

if [ -z "$DEVICE_CODE" ] || [ -z "$USER_CODE" ]; then
    error_exit "Invalid response from device code endpoint"
fi

# Step 2: Display Instructions to User
log_section "Hytale Server Authorization Required"
log_info "Please visit this URL in your browser:"
echo ""
log_info "$VERIFICATION_URI_COMPLETE"
echo ""
log_info "Or visit:"
log_info "$VERIFICATION_URI"
echo ""
log_info "And enter this code:"
echo -e "${BOLD}${WHITE}  $USER_CODE${NC}"
echo ""
log_info "Waiting for authorization..."

# Step 3: Poll for Token
POLL_COUNT=0
MAX_POLLS=$((EXPIRES_IN / INTERVAL + 10))
ACCESS_TOKEN=""
REFRESH_TOKEN=""

while [ $POLL_COUNT -lt $MAX_POLLS ]; do
    sleep "$INTERVAL"
    
    POLL_COUNT=$((POLL_COUNT + 1))
    if [ $((POLL_COUNT % 3)) -eq 0 ]; then
        echo -n "."
    fi
    
    TOKEN_RESPONSE=$(curl -s -X POST "$TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
        -d "device_code=$DEVICE_CODE") || {
        echo ""
        error_exit "Failed to poll token endpoint"
    }
    
    # Check if we got an error
    if echo "$TOKEN_RESPONSE" | grep -q "\"error\""; then
        ERROR_TYPE=$(json_get "error" "$TOKEN_RESPONSE")
        
        if [ "$ERROR_TYPE" = "authorization_pending" ]; then
            continue
        elif [ "$ERROR_TYPE" = "slow_down" ]; then
            INTERVAL=$((INTERVAL + 5))
            continue
        elif [ "$ERROR_TYPE" = "expired_token" ]; then
            echo ""
            error_exit "Device code expired. Please run the script again."
        else
            echo ""
            ERROR_DESC=$(json_get "error_description" "$TOKEN_RESPONSE")
            error_exit "Token request failed: $ERROR_TYPE${ERROR_DESC:+ - $ERROR_DESC}"
        fi
    else
        # Success!
        ACCESS_TOKEN=$(json_get "access_token" "$TOKEN_RESPONSE")
        REFRESH_TOKEN=$(json_get "refresh_token" "$TOKEN_RESPONSE")
        
        if [ -z "$ACCESS_TOKEN" ]; then
            echo ""
            error_exit "Invalid token response: missing access_token"
        fi
        
        echo ""
        echo "Authorization successful!"
        break
    fi
done

if [ -z "$ACCESS_TOKEN" ]; then
    error_exit "Authorization timed out. Please try again."
fi

# Step 4: Get Available Profiles
log_step "4" "Fetching available profiles..."
PROFILES_RESPONSE=$(curl -s -X GET "$PROFILES_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN") || error_exit "Failed to fetch profiles"

if echo "$PROFILES_RESPONSE" | grep -q "\"error\""; then
    ERROR_MSG=$(json_get "error" "$PROFILES_RESPONSE")
    error_exit "Failed to get profiles: $ERROR_MSG"
fi

# Extract owner UUID and profiles
OWNER_UUID=$(json_get "owner" "$PROFILES_RESPONSE")

# Get first profile (we'll use the first one available)
if [ "$USE_JQ" = true ]; then
    PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | jq -r '.profiles[0].uuid // empty')
    PROFILE_USERNAME=$(echo "$PROFILES_RESPONSE" | jq -r '.profiles[0].username // empty')
else
    # Basic parsing for first profile
    PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | grep -o '"uuid"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"uuid"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
    PROFILE_USERNAME=$(echo "$PROFILES_RESPONSE" | grep -o '"username"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"username"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')
fi

if [ -z "$PROFILE_UUID" ]; then
    error_exit "No profiles found. Please ensure your account has a server profile."
fi

log_info "Found profile: $PROFILE_USERNAME ($PROFILE_UUID)"

# Step 5: Create Game Session
log_step "5" "Creating game session..."
SESSION_RESPONSE=$(curl -s -X POST "$SESSION_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"uuid\": \"$PROFILE_UUID\"}") || error_exit "Failed to create game session"

if echo "$SESSION_RESPONSE" | grep -q "\"error\""; then
    ERROR_MSG=$(json_get "error" "$SESSION_RESPONSE")
    error_exit "Failed to create session: $ERROR_MSG"
fi

SESSION_TOKEN=$(json_get "sessionToken" "$SESSION_RESPONSE")
IDENTITY_TOKEN=$(json_get "identityToken" "$SESSION_RESPONSE")
EXPIRES_AT=$(json_get "expiresAt" "$SESSION_RESPONSE")

if [ -z "$SESSION_TOKEN" ] || [ -z "$IDENTITY_TOKEN" ]; then
    error_exit "Invalid session response: missing tokens"
fi

echo "Game session created successfully!"

# Step 6: Save Credentials
log_step "6" "Saving credentials to $AUTH_FILE..."

# Create directory if it doesn't exist
AUTH_DIR=$(dirname "$AUTH_FILE")
if [ ! -d "$AUTH_DIR" ]; then
    mkdir -p "$AUTH_DIR" || error_exit "Failed to create directory: $AUTH_DIR"
fi

# Check if we can write to the directory
if [ ! -w "$AUTH_DIR" ]; then
    error_exit "Cannot write to directory $AUTH_DIR (permission denied). Check volume permissions."
fi

# Check if we can write to the file location
if [ -f "$AUTH_FILE" ] && [ ! -w "$AUTH_FILE" ]; then
    error_exit "Cannot write to $AUTH_FILE (permission denied)"
fi

# Create JSON file
if [ "$USE_JQ" = true ]; then
    jq -n \
        --arg access_token "$ACCESS_TOKEN" \
        --arg refresh_token "$REFRESH_TOKEN" \
        --arg session_token "$SESSION_TOKEN" \
        --arg identity_token "$IDENTITY_TOKEN" \
        --arg owner_uuid "$OWNER_UUID" \
        --arg owner_name "$PROFILE_USERNAME" \
        --arg expires_at "$EXPIRES_AT" \
        '{
            access_token: $access_token,
            refresh_token: $refresh_token,
            session_token: $session_token,
            identity_token: $identity_token,
            owner_uuid: $owner_uuid,
            owner_name: $owner_name,
            expires_at: $expires_at
        }' > "$AUTH_FILE"
else
    # Manual JSON construction (fallback)
    cat > "$AUTH_FILE" <<EOF
{
  "access_token": "$ACCESS_TOKEN",
  "refresh_token": "$REFRESH_TOKEN",
  "session_token": "$SESSION_TOKEN",
  "identity_token": "$IDENTITY_TOKEN",
  "owner_uuid": "$OWNER_UUID",
  "owner_name": "$PROFILE_USERNAME",
  "expires_at": "$EXPIRES_AT"
}
EOF
fi

echo ""
log_section "Authentication Complete!"
log_info "Credentials saved to: $AUTH_FILE"
log_info "Session expires at: $EXPIRES_AT"
echo ""
log_info "You can now start the Hytale server."
echo ""

