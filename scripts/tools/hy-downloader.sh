#!/bin/bash
set -e

# Hytale Server Downloader CLI
# Downloads Hytale server files using authenticated API
#
# Repository: https://github.com/Madscientiste/hytale-docker
#
# This script is part of the Hytale Server Docker container project.
# It handles downloading server files from the Hytale API using OAuth credentials.
#############################################################################


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

# Version
SCRIPT_VERSION="1.0.0"

# API endpoints
API_BASE="https://account-data.hytale.com"
OAUTH_BASE="https://oauth.accounts.hytale.com"

# Default values
AUTH_FILE=""
OUTPUT_DIR=""
VERSION="LATEST"
PATCHLINE="release"
FORCE_DOWNLOAD=false
VERBOSE=false
QUIET=false
SIMPLE_NAMES=false

# Show help message
show_help() {
    cat <<EOF
hy-downloader - Hytale Server Downloader CLI

USAGE:
    hy-downloader [OPTIONS] --auth-file PATH --output-dir PATH

DESCRIPTION:
    Download Hytale server files (HytaleServer.jar and Assets.zip) using
    authenticated API credentials. Requires a valid auth.json file from
    hy-auth authentication.

REQUIRED OPTIONS:
    -a PATH, --auth-file PATH
        Path to the authentication credentials file (auth.json).
        This file must be created using hy-auth first.

    -o PATH, --output-dir PATH
        Directory where server files will be saved.
        Files will be saved with version tags:
          - hs-VERSION.jar (e.g., hs-2026.01.15-c04fdfe10.jar)
          - ha-VERSION.zip (e.g., ha-2026.01.15-c04fdfe10.zip)

OPTIONAL OPTIONS:
    -h, --help
        Display this help message and exit.

    --version
        Display version information and exit.

    -v, --verbose
        Enable verbose output (DEBUG log level).
        Shows detailed debug information during download.

    -q, --quiet
        Suppress non-error output (ERROR log level only).
        Only displays error messages.

    --server-version VERSION
        Specify a specific server version to download.
        Default: LATEST (downloads the latest available version).

    --patchline PATCHLINE
        Specify the patchline to use (e.g., release, beta).
        Default: release

    -f, --force
        Force re-download even if files already exist.
        By default, skips download if files are already present.

    --simple-names
        Save files with simple names (HytaleServer.jar, Assets.zip)
        instead of version-tagged names (hs-VERSION.jar, ha-VERSION.zip).

EXAMPLES:
    # Download latest server files
    hy-downloader --auth-file ./auth.json --output-dir ./server

    # Download with short options
    hy-downloader -a ./auth.json -o ./server

    # Download specific version
    hy-downloader -a ./auth.json -o ./server --server-version 2026.01.17-4b0f30090

    # Download with simple names
    hy-downloader -a ./auth.json -o ./server --simple-names

    # Force re-download
    hy-downloader -a ./auth.json -o ./server --force

    # Verbose output
    hy-downloader -a ./auth.json -o ./server --verbose

    # Quiet mode
    hy-downloader -a ./auth.json -o ./server --quiet

    # Combined options
    hy-downloader -a ./auth.json -o ./server --server-version 2026.01.17-4b0f30090 --force -v

EXIT CODES:
    0   Success
    1   Error (invalid arguments, download failure, etc.)

DEPENDENCIES:
    Required: curl, unzip, python3 (or basic JSON parsing)
    Optional: jq (for robust JSON parsing)

EOF
}

# Show version information
show_version() {
    echo "hy-downloader version $SCRIPT_VERSION"
}

# Validate version format
# Returns: "LATEST", "FULL", "PARTIAL", or "INVALID"
validate_version_format() {
    local version="$1"
    
    if [ -z "$version" ] || [ "$version" = "LATEST" ]; then
        echo "LATEST"
        return 0
    fi
    
    # Check if it matches full version format: YYYY.MM.DD-hash
    # Pattern: 4 digits, dot, 2 digits, dot, 2 digits, dash, alphanumeric hash
    if echo "$version" | grep -qE '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[a-f0-9]+$'; then
        echo "FULL"
        return 0
    fi
    
    # Check if it matches partial version format: YYYY.MM.DD (without hash)
    if echo "$version" | grep -qE '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$'; then
        echo "PARTIAL"
        return 0
    fi
    
    echo "INVALID"
    return 1
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
            --server-version)
                if [ -z "$2" ]; then
                    error_exit "Option $1 requires an argument"
                fi
                VERSION="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -a|--auth-file)
                if [ -z "$2" ]; then
                    error_exit "Option $1 requires an argument"
                fi
                AUTH_FILE="$2"
                shift 2
                ;;
            -o|--output-dir)
                if [ -z "$2" ]; then
                    error_exit "Option $1 requires an argument"
                fi
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --patchline)
                if [ -z "$2" ]; then
                    error_exit "Option $1 requires an argument"
                fi
                PATCHLINE="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DOWNLOAD=true
                shift
                ;;
            --simple-names)
                SIMPLE_NAMES=true
                shift
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
                        remaining="${1#-v}"
                        if [ -n "$remaining" ]; then
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
                    -a*)
                        remaining="${1#-a}"
                        if [ -n "$remaining" ]; then
                            AUTH_FILE="$remaining"
                        elif [ -n "$2" ]; then
                            AUTH_FILE="$2"
                            shift
                        else
                            error_exit "Option -a requires an argument"
                        fi
                        shift
                        ;;
                    -o*)
                        remaining="${1#-o}"
                        if [ -n "$remaining" ]; then
                            OUTPUT_DIR="$remaining"
                        elif [ -n "$2" ]; then
                            OUTPUT_DIR="$2"
                            shift
                        else
                            error_exit "Option -o requires an argument"
                        fi
                        shift
                        ;;
                    -f*)
                        FORCE_DOWNLOAD=true
                        remaining="${1#-f}"
                        if [ -n "$remaining" ]; then
                            set -- "-$remaining" "$@"
                        fi
                        shift
                        ;;
                    *)
                        error_exit "Unknown option: $1. Use --help for usage information."
                        ;;
                esac
                ;;
            *)
                error_exit "Unexpected argument: $1. Use --help for usage information."
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

# Parse command line arguments
parse_args "$@"

# Set log level based on flags
set_log_level

# Validate required arguments
if [ -z "$AUTH_FILE" ]; then
    error_exit "Auth file is required. Use -a or --auth-file to specify the credentials file path."
fi

if [ -z "$OUTPUT_DIR" ]; then
    error_exit "Output directory is required. Use -o or --output-dir to specify the output directory."
fi

# Resolve absolute paths
if [ "$(echo "$AUTH_FILE" | cut -c1)" != "/" ]; then
    AUTH_FILE="$(cd "$(dirname "$AUTH_FILE")" 2>/dev/null && pwd)/$(basename "$AUTH_FILE")" || \
        AUTH_FILE="$(pwd)/$AUTH_FILE"
fi

if [ "$(echo "$OUTPUT_DIR" | cut -c1)" != "/" ]; then
    OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_DIR")" 2>/dev/null && pwd)/$(basename "$OUTPUT_DIR")" || \
        OUTPUT_DIR="$(pwd)/$OUTPUT_DIR"
fi

# Temporary paths (work in temp until ready)
TEMP_DIR="${OUTPUT_DIR}/.tmp-download"
TEMP_DOWNLOAD="${TEMP_DIR}/game.zip"
TEMP_EXTRACT="${TEMP_DIR}/extracted"

# Final paths will be set after we know the version
FINAL_JAR=""
FINAL_ASSETS=""

# Check prerequisites
check_prerequisites curl unzip

# Check if jq is available for JSON parsing
USE_JQ=false
if command_exists jq; then
    USE_JQ=true
elif ! command_exists python3; then
    log_warn "Neither jq nor python3 found. Using basic JSON parsing (may be less robust)."
fi

log_section "Downloading Hytale Server"

# Verify auth.json exists
if [ ! -f "$AUTH_FILE" ]; then
    error_exit "Auth file not found at $AUTH_FILE. Authentication must be completed first using hy-auth."
fi

# Extract access token from auth.json
if [ "$USE_JQ" = true ]; then
    ACCESS_TOKEN=$(jq -r '.access_token // empty' "$AUTH_FILE" 2>/dev/null)
else
    ACCESS_TOKEN=$(grep '"access_token"' "$AUTH_FILE" | sed 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
fi

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ] || [ "$ACCESS_TOKEN" = "" ]; then
    error_exit "Could not extract access_token from $AUTH_FILE"
fi

# Validate version format
VERSION_TYPE=$(validate_version_format "$VERSION")
case "$VERSION_TYPE" in
    PARTIAL)
        error_exit "Partial version format detected: $VERSION

Version must include the full hash (e.g., 2026.01.17-4b0f30090).
Partial versions (date only) are not supported.

Example: --server-version 2026.01.17-4b0f30090"
        ;;
    INVALID)
        error_exit "Invalid version format: $VERSION

Version must be either:
  - LATEST (default, downloads latest version)
  - Full version with hash: YYYY.MM.DD-hash (e.g., 2026.01.17-4b0f30090)

Example: --server-version 2026.01.17-4b0f30090"
        ;;
esac

log_info "Version: $VERSION"
log_info "Patchline: $PATCHLINE"
log_info "Auth file: $AUTH_FILE"
log_info "Output directory: $OUTPUT_DIR"
if [ "$SIMPLE_NAMES" = true ]; then
    log_info "Using simple file names (HytaleServer.jar, Assets.zip)"
fi

# Create output and temp directories
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || error_exit "Failed to create output directory: $OUTPUT_DIR"
fi

if [ ! -w "$OUTPUT_DIR" ]; then
    error_exit "Cannot write to output directory: $OUTPUT_DIR (permission denied)"
fi

mkdir -p "$TEMP_DIR" "$TEMP_EXTRACT" || error_exit "Failed to create temporary directories"

# Cleanup function
cleanup_temp() {
    if [ -d "$TEMP_DIR" ]; then
        log_debug "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
}

# Cleanup on exit
trap cleanup_temp EXIT INT TERM

# Determine which version to use and how to get it
ACTUAL_VERSION=""
DOWNLOAD_PATH=""
EXPECTED_SHA256=""

if [ "$VERSION" = "LATEST" ]; then
    # Use manifest for LATEST
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
    if [ "$USE_JQ" = true ]; then
        SIGNED_MANIFEST_URL=$(echo "$BODY" | jq -r '.url // empty' 2>/dev/null | sed 's/\\u0026/\&/g')
    else
        SIGNED_MANIFEST_URL=$(echo "$BODY" | grep -o '"url":"[^"]*"' | sed 's/"url":"\([^"]*\)"/\1/' | sed 's/\\u0026/\&/g')
    fi
    
    if [ -z "$SIGNED_MANIFEST_URL" ] || [ "$SIGNED_MANIFEST_URL" = "null" ]; then
        error_exit "No signed URL in manifest response"
    fi
    
    log_success "Got signed manifest URL"
    
    log_step "2" "Fetching manifest content..."
    MANIFEST=$(curl -s "$SIGNED_MANIFEST_URL") || error_exit "Failed to fetch manifest"
    
    # Parse manifest JSON
    if [ "$USE_JQ" = true ]; then
        ACTUAL_VERSION=$(echo "$MANIFEST" | jq -r '.version // empty' 2>/dev/null)
        DOWNLOAD_PATH=$(echo "$MANIFEST" | jq -r '.download_url // empty' 2>/dev/null)
        EXPECTED_SHA256=$(echo "$MANIFEST" | jq -r '.sha256 // empty' 2>/dev/null)
    elif command_exists python3; then
        ACTUAL_VERSION=$(echo "$MANIFEST" | python3 -c "import sys, json; print(json.load(sys.stdin).get('version', ''))" 2>/dev/null || echo "")
        DOWNLOAD_PATH=$(echo "$MANIFEST" | python3 -c "import sys, json; print(json.load(sys.stdin).get('download_url', ''))" 2>/dev/null || echo "")
        EXPECTED_SHA256=$(echo "$MANIFEST" | python3 -c "import sys, json; print(json.load(sys.stdin).get('sha256', ''))" 2>/dev/null || echo "")
    else
        ACTUAL_VERSION=$(echo "$MANIFEST" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        DOWNLOAD_PATH=$(echo "$MANIFEST" | grep -o '"download_url"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        EXPECTED_SHA256=$(echo "$MANIFEST" | grep -o '"sha256"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    
    if [ -z "$DOWNLOAD_PATH" ]; then
        error_exit "No download_url in manifest"
    fi
    
    if [ -z "$ACTUAL_VERSION" ]; then
        error_exit "No version found in manifest"
    fi
    
    log_success "Manifest retrieved"
    log_info "  Version: $ACTUAL_VERSION"
    log_info "  Download path: $DOWNLOAD_PATH"
    if [ -n "$EXPECTED_SHA256" ]; then
        log_info "  SHA256: ${EXPECTED_SHA256:0:16}..."
    fi
else
    # Use specific version - construct path directly
    ACTUAL_VERSION="$VERSION"
    DOWNLOAD_PATH="builds/${PATCHLINE}/${VERSION}.zip"
    log_step "1" "Using specific version: $VERSION"
    log_info "  Constructed download path: $DOWNLOAD_PATH"
    # Note: SHA256 not available for specific versions without manifest
    EXPECTED_SHA256=""
fi

# Construct final paths
if [ "$SIMPLE_NAMES" = true ]; then
    FINAL_JAR="${OUTPUT_DIR}/HytaleServer.jar"
    FINAL_ASSETS="${OUTPUT_DIR}/Assets.zip"
else
    FINAL_JAR="${OUTPUT_DIR}/hs-${ACTUAL_VERSION}.jar"
    FINAL_ASSETS="${OUTPUT_DIR}/ha-${ACTUAL_VERSION}.zip"
fi

# Check if download is needed
if [ "$FORCE_DOWNLOAD" != true ] && [ -f "$FINAL_JAR" ] && [ -f "$FINAL_ASSETS" ]; then
    log_info "Server files already exist. Skipping download."
    log_info "  HytaleServer.jar: $FINAL_JAR"
    log_info "  Assets.zip: $FINAL_ASSETS"
    log_debug "Use --force to force re-download"
    exit 0
fi

log_step "3" "Getting signed download URL..."
DOWNLOAD_URL_ENDPOINT="${API_BASE}/game-assets/${DOWNLOAD_PATH}"

DOWNLOAD_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$DOWNLOAD_URL_ENDPOINT" 2>&1)

DOWNLOAD_HTTP_CODE=$(echo "$DOWNLOAD_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
DOWNLOAD_BODY=$(echo "$DOWNLOAD_RESPONSE" | sed '/HTTP_CODE:/d')

if [ "$DOWNLOAD_HTTP_CODE" != "200" ]; then
    if [ "$DOWNLOAD_HTTP_CODE" = "404" ]; then
        error_exit "Version not found: $VERSION

The requested version does not exist or is not available for patchline '$PATCHLINE'.
Please verify the version string is correct (format: YYYY.MM.DD-hash).

Example: 2026.01.17-4b0f30090"
    else
        error_exit "Failed to get signed download URL (HTTP $DOWNLOAD_HTTP_CODE): $DOWNLOAD_BODY"
    fi
fi

if [ "$USE_JQ" = true ]; then
    SIGNED_DOWNLOAD_URL=$(echo "$DOWNLOAD_BODY" | jq -r '.url // empty' 2>/dev/null | sed 's/\\u0026/\&/g')
else
    SIGNED_DOWNLOAD_URL=$(echo "$DOWNLOAD_BODY" | grep -o '"url":"[^"]*"' | sed 's/"url":"\([^"]*\)"/\1/' | sed 's/\\u0026/\&/g')
fi

if [ -z "$SIGNED_DOWNLOAD_URL" ] || [ "$SIGNED_DOWNLOAD_URL" = "null" ]; then
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

log_step "6" "Extracting server files..."
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

log_success "Server files ready!"
log_info "  HytaleServer.jar: $FINAL_JAR"
log_info "  Assets.zip: $FINAL_ASSETS"
log_info "  Version: $ACTUAL_VERSION"

# Cleanup temp files (trap will handle if we exit early)
cleanup_temp
