#!/bin/sh
# Download Hytale server files using authenticated API

# Get script directory and source common utilities
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"

# Configuration from environment variables
VERSION="${VERSION:-LATEST}"
PATCHLINE="${PATCHLINE:-release}"
FORCE_DOWNLOAD="${FORCE_DOWNLOAD:-false}"
FORCE_UPDATE_CHECK="${FORCE_UPDATE_CHECK:-false}"
HYTALE_DATA_DIR="${HYTALE_DATA_DIR:-/data}"
AUTH_FILE="${HYTALE_DATA_DIR}/auth.json"

# Final paths
FINAL_JAR="${HYTALE_DATA_DIR}/HytaleServer.jar"
FINAL_ASSETS="${HYTALE_DATA_DIR}/Assets.zip"
LAST_CHECK_FILE="${HYTALE_DATA_DIR}/.last-update-check"

# Build hy-downloader.sh command
HY_DOWNLOADER="/usr/local/bin/hy-downloader.sh"
# For testing, use local script if installed version doesn't exist
if [ ! -f "$HY_DOWNLOADER" ]; then
    SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
    HY_DOWNLOADER="${SCRIPT_DIR}/../tools/hy-downloader.sh"
fi

# Verify hy-downloader exists and is executable
if [ ! -f "$HY_DOWNLOADER" ]; then
    error_exit "hy-downloader.sh not found at $HY_DOWNLOADER"
fi

if [ ! -x "$HY_DOWNLOADER" ]; then
    log_warn "hy-downloader.sh is not executable, attempting to fix..."
    chmod +x "$HY_DOWNLOADER" 2>/dev/null || error_exit "Cannot make hy-downloader.sh executable"
fi

# Test if hy-downloader can actually run (checks shebang/interpreter)
if ! "$HY_DOWNLOADER" --help >/dev/null 2>&1; then
    # Try running with explicit bash interpreter as fallback
    log_debug "Direct execution failed, trying with explicit bash interpreter..."
    if bash "$HY_DOWNLOADER" --help >/dev/null 2>&1; then
        log_warn "hy-downloader.sh requires explicit bash interpreter"
        # Wrap in a function that uses bash
        _hy_downloader_wrapper() {
            bash "$HY_DOWNLOADER" "$@"
        }
        HY_DOWNLOADER=_hy_downloader_wrapper
    else
        error_exit "hy-downloader.sh cannot be executed (shebang/interpreter issue)"
    fi
fi

# =============================================================================
# Helper Functions
# =============================================================================

# Get current installed version from JAR
get_current_version() {
    if [ ! -f "$FINAL_JAR" ]; then
        echo ""
        return 1
    fi
    
    local version_output
    if version_output=$(java -jar "$FINAL_JAR" --version 2>/dev/null); then
        # Extract version from: "HytaleServer v2026.01.17-4b0f30090 (release)"
        local extracted_version=$(echo "$version_output" | sed -n 's/.* v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*-[a-f0-9]*\) .*/\1/p')
        if [ -n "$extracted_version" ]; then
            echo "$extracted_version"
            return 0
        fi
    fi
    
    log_warn "Failed to parse version from JAR"
    echo ""
    return 1
}

# Get latest available version using hy-downloader
get_latest_version() {
    local temp_auth="/tmp/auth-copy-$.json"
    local temp_output="/tmp/hy-version-check-$.log"
    
    # Copy auth file to temporary location to avoid conflicts
    if ! cp "$AUTH_FILE" "$temp_auth" 2>/dev/null; then
        log_warn "Failed to copy auth file for version check"
        echo ""
        return 1
    fi
    
    # Use hy-downloader in dry-run mode to get version info
    log_debug "Running hy-downloader in dry-run mode..."
    log_debug "Command: $HY_DOWNLOADER --auth-file $temp_auth --output-dir /tmp --server-version LATEST --patchline $PATCHLINE --dry-run"
    
    if $HY_DOWNLOADER \
        --auth-file "$temp_auth" \
        --output-dir "/tmp" \
        --server-version "LATEST" \
        --patchline "$PATCHLINE" \
        --dry-run > "$temp_output" 2>&1; then
        
        log_debug "Dry-run succeeded. Output:"
        while IFS= read -r line; do
            log_debug "  $line"
        done < "$temp_output"
        
        # Extract version - the output format is: "Latest version: X.X.X-XXXXXX"
        local latest_version=""
        latest_version=$(grep "^Latest version:" "$temp_output" | cut -d' ' -f3)
        
        if [ -n "$latest_version" ] && [ "$latest_version" != "null" ]; then
            log_debug "Successfully extracted version: $latest_version"
            rm -f "$temp_auth" "$temp_output"
            echo "$latest_version"
            return 0
        else
            log_warn "Could not extract version from dry-run output"
            log_warn "Expected line format: 'Latest version: X.X.X-XXXXXX'"
        fi
    else
        local exit_code=$?
        log_warn "hy-downloader dry-run failed with exit code $exit_code"
        log_warn "Full output:"
        while IFS= read -r line; do
            log_warn "  $line"
        done < "$temp_output"
    fi
    
    rm -f "$temp_auth" "$temp_output"
    echo ""
    return 1
}

# Check if cooldown period has passed (1 hour)
cooldown_passed() {
    # Force check always passes cooldown
    if [ "$FORCE_UPDATE_CHECK" = "true" ]; then
        log_debug "Update check forced, bypassing cooldown"
        return 0
    fi
    
    # No timestamp file means cooldown passed
    if [ ! -f "$LAST_CHECK_FILE" ]; then
        return 0
    fi
    
    local last_check=$(cat "$LAST_CHECK_FILE" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_check))
    local cooldown_remaining=$((3600 - time_diff))
    
    if [ $time_diff -lt 3600 ]; then
        log_info "Update check on cooldown (${cooldown_remaining}s remaining)"
        return 1
    fi
    
    return 0
}

# Update the timestamp file
update_check_timestamp() {
    if date +%s > "$LAST_CHECK_FILE" 2>/dev/null; then
        log_debug "Update check timestamp updated"
    else
        log_warn "Failed to update check timestamp"
    fi
}

# Perform the actual download
perform_download() {
    local reason="$1"
    local force_flag="${2:-false}"  # Optional second parameter
    
    log_info "Downloading server files ($reason)..."
    
    # Build command arguments
    local downloader_args="--auth-file $AUTH_FILE --output-dir $HYTALE_DATA_DIR --server-version $VERSION --patchline $PATCHLINE --simple-names"
    
    # Add force flag if needed (either from parameter or global variable)
    if [ "$force_flag" = "true" ] || [ "$FORCE_DOWNLOAD" = "true" ]; then
        downloader_args="$downloader_args --force"
    fi
    
    if $HY_DOWNLOADER $downloader_args; then
        
        log_success "Server files downloaded successfully"
        
        # Verify files exist
        if [ ! -f "$FINAL_JAR" ]; then
            error_exit "HytaleServer.jar not found after download"
        fi
        
        if [ ! -f "$FINAL_ASSETS" ]; then
            error_exit "Assets.zip not found after download"
        fi
        
        # Show final version
        local final_version=$(get_current_version)
        if [ -n "$final_version" ]; then
            log_success "Server ready: v${final_version}"
        else
            log_success "Server files ready: HytaleServer.jar and Assets.zip"
        fi
        
        return 0
    else
        error_exit "Failed to download server files"
    fi
}

# =============================================================================
# Main Logic
# =============================================================================

log_section "Hytale Server Download"

# Verify auth.json exists
if [ ! -f "$AUTH_FILE" ]; then
    error_exit "auth.json not found at $AUTH_FILE. Authentication must be completed first."
fi

log_info "Configuration:"
log_info "  Version: $VERSION"
log_info "  Patchline: $PATCHLINE"
log_info "  Data directory: $HYTALE_DATA_DIR"

# Determine download mode and execute
files_exist=false
if [ -f "$FINAL_JAR" ] && [ -f "$FINAL_ASSETS" ]; then
    files_exist=true
fi

# Mode 1: Forced Download
if [ "$FORCE_DOWNLOAD" = "true" ]; then
    log_info "Mode: Forced download (FORCE_DOWNLOAD=true)"
    perform_download "forced"
    exit 0
fi

# Mode 2: First Init (no files exist)
if [ "$files_exist" = "false" ]; then
    log_info "Mode: First initialization (no existing files)"
    perform_download "initial setup"
    exit 0
fi

# Mode 3: Files exist - check if update needed
log_info "Mode: Update check"

# Only check for updates if VERSION=LATEST
if [ "$VERSION" != "LATEST" ]; then
    log_info "Specific version requested ($VERSION), skipping update check"
    log_info "Server files already present"
    exit 0
fi

# Check cooldown
if ! cooldown_passed; then
    log_info "Server files already present"
    log_debug "Use FORCE_UPDATE_CHECK=true to bypass cooldown"
    exit 0
fi

# Perform update check
log_info "Checking for updates..."

# Get current version
current_version=$(get_current_version)
if [ -z "$current_version" ]; then
    log_warn "Could not determine current version"
    log_info "Server files present but version unknown, skipping update"
    update_check_timestamp  # Avoid repeated failures
    exit 0
fi

log_info "Current version: $current_version"

# Get latest version
latest_version=$(get_latest_version)
if [ -z "$latest_version" ]; then
    log_warn "Could not check for latest version"
    log_info "Using existing server files"
    update_check_timestamp  # Avoid repeated failures
    exit 0
fi

log_info "Latest version: $latest_version"

# Compare versions
if [ "$current_version" = "$latest_version" ]; then
    log_success "Server is up to date"
    update_check_timestamp
    exit 0
fi

# Update available
log_info "Update available: $current_version → $latest_version"
update_check_timestamp
perform_download "update to v${latest_version}" "true"  # Force download for updates
exit 0