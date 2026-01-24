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

# Update checking functions

# Check if we should perform update check (1-hour cooldown)
should_check_updates() {
    # Force check if requested
    if [ "$FORCE_UPDATE_CHECK" = "true" ]; then
        log_debug "Force update check requested"
        return 0
    fi
    
    # Skip check if files don't exist (first run)
    if [ ! -f "$FINAL_JAR" ] || [ ! -f "$FINAL_ASSETS" ]; then
        log_debug "First run detected, skipping update check"
        return 1  # Skip update check, proceed with normal download
    fi
    
    # Check if enough time has passed (1 hour = 3600 seconds)
    if [ -f "$LAST_CHECK_FILE" ]; then
        local last_check=$(cat "$LAST_CHECK_FILE" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_check))
        
        if [ $time_diff -lt 3600 ]; then
            log_debug "Update check skipped: last check was ${time_diff}s ago (cooldown: 3600s)"
            return 1  # Skip update check
        fi
    fi
    
    return 0  # Proceed with update check
}

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
    
    log_warn "Failed to parse version from JAR output: $version_output"
    echo ""
    return 1
}

# Get latest available version using hy-downloader
get_latest_version() {
    local temp_auth="/tmp/auth-copy.json"
    
    # Copy auth file to temporary location to avoid conflicts
    cp "$AUTH_FILE" "$temp_auth" 2>/dev/null || {
        log_warn "Failed to copy auth file for version check"
        echo ""
        return 1
    }
    
    # Use hy-downloader in dry-run mode to get version info
    local version_info
    if version_info=$(bash "$HY_DOWNLOADER" \
        --auth-file "$temp_auth" \
        --output-dir "/tmp" \
        --server-version "LATEST" \
        --patchline "$PATCHLINE" \
        --dry-run 2>/dev/null); then
        # Extract version from output
        local latest_version=$(echo "$version_info" | grep "Latest version:" | cut -d' ' -f3)
        if [ -n "$latest_version" ]; then
            rm -f "$temp_auth"
            echo "$latest_version"
            return 0
        else
            log_warn "Could not extract version from hy-downloader output: $version_info"
        fi
    else
        log_warn "Failed to get latest version from hy-downloader"
    fi
    
    rm -f "$temp_auth"
    echo ""
    return 1
}

# Update the timestamp file
update_check_timestamp() {
    date +%s > "$LAST_CHECK_FILE" || log_warn "Failed to update check timestamp"
}

log_section "Downloading Hytale Server"

# Verify auth.json exists
if [ ! -f "$AUTH_FILE" ]; then
    error_exit "auth.json not found at $AUTH_FILE. Authentication must be completed first."
fi

log_info "Version: $VERSION"
log_info "Patchline: $PATCHLINE"
log_info "Using credentials: $AUTH_FILE"

# Check if download is needed
if [ "$FORCE_DOWNLOAD" != "true" ] && [ -f "$FINAL_JAR" ] && [ -f "$FINAL_ASSETS" ]; then
    
    # Check for updates if using LATEST version
    if [ "$VERSION" = "LATEST" ] && should_check_updates; then
        log_info "Checking for server updates..."
        
        # Get current version
        current_version=$(get_current_version)
        if [ -n "$current_version" ]; then
            log_info "Current version: $current_version"
            
            # Get latest version
            latest_version=$(get_latest_version)
            if [ -n "$latest_version" ]; then
                log_info "Latest version: $latest_version"
                
                # Compare versions
                if [ "$current_version" != "$latest_version" ]; then
                    log_info "New version available: $latest_version (current: $current_version)"
                    log_info "Downloading update..."
                    FORCE_DOWNLOAD="true"
                else
                    log_info "Server is up to date"
                fi
            else
                log_warn "Failed to check latest version, skipping update check"
            fi
        else
            log_warn "Failed to detect current version, skipping update check"
        fi
        
        # Update timestamp regardless of outcome (to avoid spam on failures)
        update_check_timestamp
    fi
    
    # Skip download if not forced
    if [ "$FORCE_DOWNLOAD" != "true" ]; then
        log_info "Server files already exist. Skipping download."
        log_debug "Set FORCE_DOWNLOAD=true to force re-download"
        exit 0
    fi
fi

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