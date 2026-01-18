#!/bin/sh
# Setup RCON plugin - download and configure

# Get script directory and source common utilities
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"

HYTALE_DATA_DIR="/data"
MODS_DIR="${HYTALE_DATA_DIR}/mods"
CONFIGS_DIR="${HYTALE_DATA_DIR}/configs"
RCON_CONFIG_FILE="${CONFIGS_DIR}/com.madscientiste.rcon.json"

# Check prerequisites
check_prerequisites jq curl

# RCON configuration from environment variables
RCON_ENABLED="${RCON_ENABLED:-true}"
RCON_VERSION="${RCON_VERSION:-latest}"
RCON_HOST="${RCON_HOST:-127.0.0.1}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
RCON_PASSWORD_HASH="${RCON_PASSWORD_HASH:-}"
RCON_MAX_CONNECTIONS="${RCON_MAX_CONNECTIONS:-10}"
RCON_MAX_FRAME_SIZE="${RCON_MAX_FRAME_SIZE:-4096}"
RCON_READ_TIMEOUT_MS="${RCON_READ_TIMEOUT_MS:-30000}"
RCON_CONNECTION_TIMEOUT_MS="${RCON_CONNECTION_TIMEOUT_MS:-5000}"

# GitHub repository
GITHUB_REPO="Madscientiste/hytale-exp"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}"

# Check if a string looks like a password hash (base64:base64 format)
is_password_hash() {
    echo "$1" | grep -qE '^[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+$'
}

# Skip if RCON is disabled
if [ "$RCON_ENABLED" != "true" ]; then
    log_info "RCON is disabled (RCON_ENABLED=false), skipping setup"
    exit 0
fi

log_section "Setting up RCON Plugin"

# Create mods and configs directories if they don't exist
if [ ! -d "$MODS_DIR" ]; then
    log_info "Creating mods directory: $MODS_DIR"
    mkdir -p "$MODS_DIR" || error_exit "Failed to create mods directory"
fi

if [ ! -d "$CONFIGS_DIR" ]; then
    log_info "Creating configs directory: $CONFIGS_DIR"
    mkdir -p "$CONFIGS_DIR" || error_exit "Failed to create configs directory"
fi

# Determine version to download
RELEASE_TAG=""
VERSION_NUMBER=""
if [ "$RCON_VERSION" = "latest" ]; then
    log_step "1" "Fetching latest RCON plugin version from GitHub"
    LATEST_RELEASE=$(curl -sf "${GITHUB_API}/releases/latest" 2>&1)
    CURL_EXIT=$?
    
    if [ $CURL_EXIT -ne 0 ] || [ -z "$LATEST_RELEASE" ]; then
        log_error "Failed to fetch latest release from GitHub API"
        log_debug "curl exit code: $CURL_EXIT"
        log_debug "Response: $LATEST_RELEASE"
        error_exit "Failed to fetch latest release from GitHub API. Check network connectivity and GitHub API status."
    fi
    
    # Use jq to parse JSON response
    RELEASE_TAG=$(echo "$LATEST_RELEASE" | jq -r '.tag_name // empty' 2>/dev/null)
    if [ -z "$RELEASE_TAG" ] || [ "$RELEASE_TAG" = "null" ]; then
        log_error "Could not extract version from GitHub API response"
        log_debug "API Response: $LATEST_RELEASE"
        error_exit "Could not extract version from GitHub API response. The API may have returned an error or unexpected format."
    fi
    log_success "Latest release tag: $RELEASE_TAG"
else
    # Use provided version as tag (may be full tag like "rcon-v1.1.0" or just version like "1.1.0")
    RELEASE_TAG="$RCON_VERSION"
    log_info "Using specified version: $RELEASE_TAG"
fi

# Extract version number from tag for JAR filename
# Tag format: "rcon-v1.1.0" or "rcon-1.1.0" -> extract "1.1.0"
# Also handle plain version like "1.1.0" or "v1.1.0"
if echo "$RELEASE_TAG" | grep -qE '^rcon-'; then
    # Remove "rcon-" prefix, then remove "v" prefix if present
    VERSION_NUMBER=$(echo "$RELEASE_TAG" | sed 's/^rcon-//' | sed 's/^v//')
else
    # Just remove "v" prefix if present
    VERSION_NUMBER=$(echo "$RELEASE_TAG" | sed 's/^v//')
fi

if [ -z "$VERSION_NUMBER" ]; then
    error_exit "Could not extract version number from tag: $RELEASE_TAG"
fi

log_debug "Release tag: $RELEASE_TAG"
log_debug "Extracted version number: $VERSION_NUMBER"

# Download plugin JAR
# JAR filename format: rcon-1.1.0.jar (no "v" prefix, no duplicate "rcon-")
PLUGIN_JAR="rcon-${VERSION_NUMBER}.jar"
PLUGIN_PATH="${MODS_DIR}/${PLUGIN_JAR}"
# Download URL uses the original release tag exactly as returned by GitHub API
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/${PLUGIN_JAR}"

log_debug "JAR filename: $PLUGIN_JAR"
log_debug "Download URL: $DOWNLOAD_URL"

log_step "2" "Downloading RCON plugin"
log_info "URL: $DOWNLOAD_URL"
log_info "Destination: $PLUGIN_PATH"

# Check if plugin already exists
if [ -f "$PLUGIN_PATH" ]; then
    log_info "Plugin already exists at $PLUGIN_PATH, skipping download"
    log_debug "Set FORCE_DOWNLOAD=true or remove the file to force re-download"
else
    if curl -L --progress-bar -o "$PLUGIN_PATH" "$DOWNLOAD_URL"; then
        FILE_SIZE=$(du -h "$PLUGIN_PATH" | cut -f1)
        log_success "Download complete! File size: $FILE_SIZE"
    else
        error_exit "Failed to download RCON plugin from $DOWNLOAD_URL"
    fi
    
    if [ ! -f "$PLUGIN_PATH" ]; then
        error_exit "Downloaded plugin not found at $PLUGIN_PATH"
    fi
fi

# Create symlink to RCON JAR in /data/.bin for easy access by utility scripts
log_step "3" "Creating RCON JAR symlink"
RCON_BIN_DIR="${HYTALE_DATA_DIR}/.bin"
RCON_JAR_SYMLINK="${RCON_BIN_DIR}/rcon.jar"
if [ -f "$PLUGIN_PATH" ]; then
    # Create .bin directory if it doesn't exist
    if [ ! -d "$RCON_BIN_DIR" ]; then
        mkdir -p "$RCON_BIN_DIR" || error_exit "Failed to create bin directory: $RCON_BIN_DIR"
        log_debug "Created bin directory: $RCON_BIN_DIR"
    fi
    
    # Remove existing symlink if it exists and points to a different file
    if [ -L "$RCON_JAR_SYMLINK" ]; then
        CURRENT_TARGET=$(readlink -f "$RCON_JAR_SYMLINK" 2>/dev/null || echo "")
        if [ "$CURRENT_TARGET" != "$PLUGIN_PATH" ]; then
            log_debug "Removing existing symlink pointing to different JAR"
            rm -f "$RCON_JAR_SYMLINK"
        fi
    fi
    
    # Create symlink if it doesn't exist
    if [ ! -e "$RCON_JAR_SYMLINK" ]; then
        if ln -s "$PLUGIN_PATH" "$RCON_JAR_SYMLINK"; then
            log_success "RCON JAR symlink created: $RCON_JAR_SYMLINK -> $PLUGIN_PATH"
        else
            error_exit "Failed to create RCON JAR symlink"
        fi
    else
        log_debug "RCON JAR symlink already exists: $RCON_JAR_SYMLINK"
    fi
else
    log_warn "RCON plugin JAR not found, cannot create symlink"
fi

# 
# FIXME: This is a workaround. Ideally, the mod itself should write the password hash into the config
# so we don't have to generate and patch it here.
# For now, this works, but this logic should move to the mod/plugin... good enough i guess ?
# 
# Determine the password hash to use
# Priority: RCON_PASSWORD_HASH > RCON_PASSWORD (if already hash) > RCON_PASSWORD (needs hashing) > none
PASSWORD_HASH=""
PLAINTEXT_PASSWORD=""

if [ -n "$RCON_PASSWORD_HASH" ]; then
    # Explicit hash provided - use it directly
    PASSWORD_HASH="$RCON_PASSWORD_HASH"
    log_info "Using provided RCON_PASSWORD_HASH"
    log_debug "Hash: ${PASSWORD_HASH:0:30}..."
    
    # Check if RCON_PASSWORD is also set (for rcon-cli)
    if [ -n "$RCON_PASSWORD" ] && ! is_password_hash "$RCON_PASSWORD"; then
        PLAINTEXT_PASSWORD="$RCON_PASSWORD"
        log_debug "RCON_PASSWORD also provided (will be used for rcon-cli)"
    fi
elif [ -n "$RCON_PASSWORD" ]; then
    # Check if RCON_PASSWORD is already a hash or plaintext
    if is_password_hash "$RCON_PASSWORD"; then
        log_info "RCON_PASSWORD is already hashed, using directly"
        PASSWORD_HASH="$RCON_PASSWORD"
        log_debug "Hash: ${PASSWORD_HASH:0:30}..."
    else
        # Plaintext password provided - need to hash it
        log_step "4" "Generating password hash from plaintext"
        PLAINTEXT_PASSWORD="$RCON_PASSWORD"
        
        # Verify plugin JAR exists before attempting to use it
        if [ ! -f "$PLUGIN_PATH" ]; then
            error_exit "Plugin JAR not found at $PLUGIN_PATH. Cannot generate password hash."
        fi
        
        # Verify Java is available
        if ! command_exists java; then
            error_exit "Java is not available. Cannot generate password hash."
        fi
        
        log_debug "Running: java -cp \"$PLUGIN_PATH\" com.madscientiste.rcon.infrastructure.AuthenticationService \"***\""
        HASH_OUTPUT=$(java -cp "$PLUGIN_PATH" com.madscientiste.rcon.infrastructure.AuthenticationService "$RCON_PASSWORD" 2>&1)
        JAVA_EXIT=$?
        
        log_debug "Java exit code: $JAVA_EXIT"
        log_debug "Java output: ${HASH_OUTPUT:0:100}..."
        
        if [ $JAVA_EXIT -eq 0 ] && [ -n "$HASH_OUTPUT" ]; then
            # Extract hash from stable output format: "Password hash: <hash>"
            PASSWORD_HASH=$(echo "$HASH_OUTPUT" | sed -n 's/.*Password hash: \([^[:space:]]*\).*/\1/p' | head -1)
            
            # Validate hash format (should contain a colon and be non-empty)
            if [ -n "$PASSWORD_HASH" ] && echo "$PASSWORD_HASH" | grep -q ':'; then
                log_success "Password hash generated successfully"
                log_debug "Hash: ${PASSWORD_HASH:0:30}..."
            else
                log_error "Could not extract password hash from output"
                log_error "Java output: $HASH_OUTPUT"
                error_exit "Failed to extract password hash from Java output. Expected format: 'Password hash: <hash>'"
            fi
        else
            log_error "Failed to generate password hash using plugin JAR"
            log_error "Java exit code: $JAVA_EXIT"
            log_error "Output: $HASH_OUTPUT"
            error_exit "Failed to generate password hash for RCON_PASSWORD. Cannot start server without proper authentication configuration."
        fi
    fi
else
    # No password or hash provided
    log_info "No RCON password or password hash provided"
    log_info "Plugin will auto-generate a secure random password on first start"
    log_warn "IMPORTANT: Check server logs for the auto-generated password and save it immediately!"
    PASSWORD_HASH=""
fi

# Create or update RCON configuration file
log_step "5" "Configuring RCON plugin"

# Build RCON configuration JSON
RCON_CONFIG_JSON="{}"
RCON_CONFIG_JSON=$(echo "$RCON_CONFIG_JSON" | jq ".host = \"$RCON_HOST\"")
RCON_CONFIG_JSON=$(echo "$RCON_CONFIG_JSON" | jq ".port = ($RCON_PORT | tonumber)")
RCON_CONFIG_JSON=$(echo "$RCON_CONFIG_JSON" | jq ".maxConnections = ($RCON_MAX_CONNECTIONS | tonumber)")
RCON_CONFIG_JSON=$(echo "$RCON_CONFIG_JSON" | jq ".maxFrameSize = ($RCON_MAX_FRAME_SIZE | tonumber)")
RCON_CONFIG_JSON=$(echo "$RCON_CONFIG_JSON" | jq ".readTimeoutMs = ($RCON_READ_TIMEOUT_MS | tonumber)")
RCON_CONFIG_JSON=$(echo "$RCON_CONFIG_JSON" | jq ".connectionTimeoutMs = ($RCON_CONNECTION_TIMEOUT_MS | tonumber)")

# Add password hash if available
if [ -n "$PASSWORD_HASH" ]; then
    RCON_CONFIG_JSON=$(echo "$RCON_CONFIG_JSON" | jq ".passwordHash = \"$PASSWORD_HASH\"")
fi

# If config file exists, merge with existing settings (preserve user customizations)
if [ -f "$RCON_CONFIG_FILE" ]; then
    log_info "RCON config file exists, merging with environment variables"
    # Read existing config and merge
    EXISTING_CONFIG=$(cat "$RCON_CONFIG_FILE" 2>/dev/null || echo "{}")
    if echo "$EXISTING_CONFIG" | jq empty 2>/dev/null; then
        # Merge: environment variables override existing config
        RCON_CONFIG_JSON=$(echo "$EXISTING_CONFIG" | jq --argjson new_config "$RCON_CONFIG_JSON" '. + $new_config')
    else
        log_warn "Existing config file is invalid JSON, creating new one"
    fi
fi

# Write configuration file
TEMP_RCON_CONFIG="${RCON_CONFIG_FILE}.tmp"
echo "$RCON_CONFIG_JSON" | jq . > "$TEMP_RCON_CONFIG" 2>/dev/null
if [ $? -eq 0 ] && jq empty "$TEMP_RCON_CONFIG" 2>/dev/null; then
    mv "$TEMP_RCON_CONFIG" "$RCON_CONFIG_FILE"
    log_success "RCON configuration written to $RCON_CONFIG_FILE"
else
    rm -f "$TEMP_RCON_CONFIG"
    error_exit "Failed to create valid RCON configuration file"
fi

log_success "RCON setup complete"
log_info "Plugin: $PLUGIN_PATH"
log_info "Config: $RCON_CONFIG_FILE"
log_info "Host: $RCON_HOST"
log_info "Port: $RCON_PORT"
if [ -n "$PASSWORD_HASH" ]; then
    log_info "Authentication: Enabled (password hash configured)"
else
    log_warn "Authentication: Plugin will auto-generate password on first start"
    log_warn "Check server logs for the generated password and save it immediately!"
fi

# Create rcon-cli configuration file for easier command execution
log_step "6" "Creating rcon-cli configuration"
RCON_CLI_HOME="${HOME:-/home/hytale}"
RCON_CLI_CONFIG="${RCON_CLI_HOME}/.rcon-cli.yaml"

# Ensure home directory exists
if [ ! -d "$RCON_CLI_HOME" ]; then
    mkdir -p "$RCON_CLI_HOME" || log_warn "Failed to create home directory: $RCON_CLI_HOME"
fi

# Create the config file
# Include plaintext password only if we have it (for rcon-cli to work)
if [ -n "$PLAINTEXT_PASSWORD" ]; then
    cat > "$RCON_CLI_CONFIG" << EOF
host: ${RCON_HOST}
port: ${RCON_PORT}
password: ${PLAINTEXT_PASSWORD}
EOF
    if [ -f "$RCON_CLI_CONFIG" ]; then
        chmod 600 "$RCON_CLI_CONFIG" || log_warn "Failed to set permissions on $RCON_CLI_CONFIG"
        log_success "rcon-cli configuration created at $RCON_CLI_CONFIG"
        log_info "You can now use 'rcon-cli <command>' without specifying host/port/password"
    else
        log_warn "Failed to create rcon-cli configuration file at $RCON_CLI_CONFIG"
    fi
else
    # No plaintext password available - create config without password
    cat > "$RCON_CLI_CONFIG" << EOF
host: ${RCON_HOST}
port: ${RCON_PORT}
EOF
    if [ -f "$RCON_CLI_CONFIG" ]; then
        chmod 600 "$RCON_CLI_CONFIG" || log_warn "Failed to set permissions on $RCON_CLI_CONFIG"
        log_success "rcon-cli configuration created at $RCON_CLI_CONFIG (without password)"
        if [ -n "$PASSWORD_HASH" ]; then
            log_warn "Only RCON_PASSWORD_HASH was provided (no plaintext password)"
            log_warn "Use 'rcon-cli --password <password> <command>' or set RCON_PASSWORD for passwordless usage"
        else
            log_warn "No RCON password configured - plugin will auto-generate password on first start"
            log_warn "Check server logs for the generated password, then set RCON_PASSWORD and restart"
        fi
    else
        log_warn "Failed to create rcon-cli configuration file at $RCON_CLI_CONFIG"
    fi
fi