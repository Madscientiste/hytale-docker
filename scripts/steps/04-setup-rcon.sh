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
# Empty: the plugin release this image was tested with, checked by sha256.
# "latest" (newest release) or another release tag such as "rcon-v1.1.0" (or
# just "1.1.0"): not checked.
RCON_VERSION="${RCON_VERSION:-}"
case "$RCON_VERSION" in
    [0-9]*|v[0-9]*) RCON_VERSION="rcon-v${RCON_VERSION#v}" ;;  # release tags are rcon-v<x>
esac
RCON_PINNED_TAG="rcon-v1.2.0"
RCON_PINNED_SHA256="e8a8759d5209c901d7d8e97efabeb6dd0f9e75c3c07e374096072bf7cb5612d0"
EXPECTED_SHA256=""
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

is_password_hash() { is_rcon_password_hash "$1"; }

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

RCON_JAR_PATTERN='^rcon-[0-9][0-9A-Za-z.+-]*\.jar$'
DISABLED_DIR="${HYTALE_DATA_DIR}/.disabled-plugins"

# RCON off: set an installed plugin aside so the server does not load it
if [ "$RCON_ENABLED" != "true" ]; then
    for JAR in $(ls "$MODS_DIR" 2>/dev/null | grep -E "$RCON_JAR_PATTERN"); do
        mkdir -p "$DISABLED_DIR"
        mv -f "${MODS_DIR}/${JAR}" "${DISABLED_DIR}/${JAR}" &&
            log_info "RCON is disabled: moved ${JAR} to ${DISABLED_DIR}"
    done
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
if [ -z "$RCON_VERSION" ] || [ "$RCON_VERSION" = "$RCON_PINNED_TAG" ]; then
    RELEASE_TAG="$RCON_PINNED_TAG"
    EXPECTED_SHA256="$RCON_PINNED_SHA256"
    log_info "Using the RCON plugin tested with this image: $RELEASE_TAG"
elif [ "$RCON_VERSION" = "latest" ]; then
    log_step "1" "Fetching latest RCON plugin version from GitHub"
    LATEST_RELEASE=$(curl -sf --connect-timeout 15 --max-time 30 "${GITHUB_API}/releases/latest" 2>&1)
    CURL_EXIT=$?
    RELEASE_TAG=""
    if [ $CURL_EXIT -eq 0 ] && [ -n "$LATEST_RELEASE" ]; then
        RELEASE_TAG=$(echo "$LATEST_RELEASE" | jq -r '.tag_name // empty' 2>/dev/null)
    fi
    [ "$RELEASE_TAG" = "null" ] && RELEASE_TAG=""

    if [ -n "$RELEASE_TAG" ]; then
        log_success "Latest release tag: $RELEASE_TAG"
    else
        log_debug "curl exit code: $CURL_EXIT"
        log_debug "Response: $LATEST_RELEASE"
        # GitHub down or rate-limited: keep the plugin already installed, so a
        # restart does not fail because of GitHub
        INSTALLED_JAR=$(ls "$MODS_DIR" 2>/dev/null | grep -E '^rcon-[0-9][0-9A-Za-z.+-]*\.jar$' | sort -V | tail -n 1)
        if [ -z "$INSTALLED_JAR" ]; then
            error_exit "Failed to fetch the latest RCON release from GitHub. Check network connectivity and GitHub API status, or set RCON_VERSION."
        fi
        log_warn "Could not check GitHub for a newer RCON plugin; keeping ${INSTALLED_JAR}"
        RELEASE_TAG="${INSTALLED_JAR%.jar}"
    fi
else
    # A release tag such as "rcon-v1.1.0" (plain "1.1.0" was mapped to it above)
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

# RCON turned back on: bring back the jar set aside while it was off
if [ ! -f "$PLUGIN_PATH" ] && [ -f "${DISABLED_DIR}/${PLUGIN_JAR}" ]; then
    mv -f "${DISABLED_DIR}/${PLUGIN_JAR}" "$PLUGIN_PATH" && log_info "Re-enabled ${PLUGIN_JAR}"
fi

# A pinned plugin must match its checksum, also when it is already installed
if [ -f "$PLUGIN_PATH" ] && [ -n "$EXPECTED_SHA256" ] && [ "$(sha256_of "$PLUGIN_PATH")" != "$EXPECTED_SHA256" ]; then
    mkdir -p "${HYTALE_DATA_DIR}/.disabled-plugins"
    mv -f "$PLUGIN_PATH" "${HYTALE_DATA_DIR}/.disabled-plugins/${PLUGIN_JAR}.bad-checksum"
    log_warn "Installed ${PLUGIN_JAR} does not match its checksum; moved to ${HYTALE_DATA_DIR}/.disabled-plugins and downloading it again"
fi

# Check if plugin already exists
if [ -f "$PLUGIN_PATH" ]; then
    log_info "Plugin already exists at $PLUGIN_PATH, skipping download"
else
    rm -f "${PLUGIN_PATH}.part"   # leftover of an interrupted download
    if [ -n "$EXPECTED_SHA256" ]; then
        # Verify before the jar goes into mods/
        curl -fL --retry 3 --connect-timeout 15 --max-time 120 -s -o "${PLUGIN_PATH}.part" "$DOWNLOAD_URL" ||
            { rm -f "${PLUGIN_PATH}.part"; error_exit "Failed to download RCON plugin from $DOWNLOAD_URL"; }
        GOT_SHA256=$(sha256_of "${PLUGIN_PATH}.part")
        if [ "$GOT_SHA256" != "$EXPECTED_SHA256" ]; then
            rm -f "${PLUGIN_PATH}.part"
            error_exit "RCON plugin checksum mismatch for $DOWNLOAD_URL (expected $EXPECTED_SHA256, got $GOT_SHA256). Not installing it."
        fi
        log_success "Checksum verified (sha256 $EXPECTED_SHA256)"
    fi
    # -f: a 404 page must not become rcon-x.jar; .part: no half-written jar
    if { [ -f "${PLUGIN_PATH}.part" ] || curl -fL --retry 3 --connect-timeout 15 --max-time 120 --progress-bar -o "${PLUGIN_PATH}.part" "$DOWNLOAD_URL"; } &&
        mv -f "${PLUGIN_PATH}.part" "$PLUGIN_PATH"; then
        FILE_SIZE=$(du -h "$PLUGIN_PATH" | cut -f1)
        log_success "Download complete! File size: $FILE_SIZE"
    else
        rm -f "${PLUGIN_PATH}.part"
        error_exit "Failed to download RCON plugin from $DOWNLOAD_URL"
    fi
    
    if [ ! -f "$PLUGIN_PATH" ]; then
        error_exit "Downloaded plugin not found at $PLUGIN_PATH"
    fi
fi

# Only one RCON plugin may load: set other versions aside (outside mods/, where
# the server ignores them) instead of deleting them
for OLD_JAR in $(ls "$MODS_DIR" 2>/dev/null | grep -E '^rcon-[0-9][0-9A-Za-z.+-]*\.jar$'); do
    [ "$OLD_JAR" = "$PLUGIN_JAR" ] && continue
    mkdir -p "${HYTALE_DATA_DIR}/.disabled-plugins"
    mv -f "${MODS_DIR}/${OLD_JAR}" "${HYTALE_DATA_DIR}/.disabled-plugins/${OLD_JAR}" &&
        log_info "Moved other RCON plugin version ${OLD_JAR} to ${HYTALE_DATA_DIR}/.disabled-plugins"
done

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

# Password: RCON_PASSWORD_HASH > RCON_PASSWORD (plaintext or hash) > a random
# password made once and kept in RCON_PASSWORD_FILE. The hash is computed from
# stdin (scripts/java/RconHash.java), so the password never shows on a
# command line.
PASSWORD_HASH=""
PLAINTEXT_PASSWORD=""

log_step "4" "Setting the RCON password"
# Plugin 1.2.0 and newer take the slow pbkdf2 format; older ones only the old,
# fast one. A non-numeric version (a custom tag) is treated as new.
HASH_OPTION=""
case "$VERSION_NUMBER" in
    [0-9]*) rcon_plugin_has_pbkdf2 "$VERSION_NUMBER" || HASH_OPTION="--old" ;;
esac

if [ -n "$RCON_PASSWORD_HASH" ]; then
    PASSWORD_HASH="$RCON_PASSWORD_HASH"
    log_info "Using RCON_PASSWORD_HASH"
    # rcon-cli, the health check and the restart warnings log in with
    # RCON_PASSWORD. A wrong one fails every 30 seconds, and after a few
    # failures the plugin bans logins from inside the container for minutes.
    if [ -n "$RCON_PASSWORD" ] && ! is_password_hash "$RCON_PASSWORD"; then
        printf '%s' "$RCON_PASSWORD" | rcon_password_matches "$RCON_PASSWORD_HASH" ||
            error_exit "RCON_PASSWORD does not match RCON_PASSWORD_HASH. Remove RCON_PASSWORD, or make the hash from it with gen-psswd."
    fi
    PLAINTEXT_PASSWORD=$(rcon_plain_password 2>/dev/null) || PLAINTEXT_PASSWORD=""
elif [ -n "$RCON_PASSWORD" ] && is_password_hash "$RCON_PASSWORD"; then
    PASSWORD_HASH="$RCON_PASSWORD"
    log_info "RCON_PASSWORD is already a hash, using it directly"
else
    if [ -n "$RCON_PASSWORD" ]; then
        log_info "Using RCON_PASSWORD"
        if [ "$RCON_PASSWORD" = "verysecurepassword" ]; then
            log_warn "RCON_PASSWORD is still the old example value 'verysecurepassword'."
            log_warn "Remove the setting to get a random password, or choose your own."
        fi
    elif rcon_plain_password >/dev/null 2>&1; then
        log_info "Using the RCON password saved in $RCON_PASSWORD_FILE"
    else
        NEW_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -d '\n/+=' | head -c 32)
        [ ${#NEW_PASSWORD} -ge 24 ] || error_exit "Failed to generate an RCON password"
        (umask 077 && printf '%s\n' "$NEW_PASSWORD" > "$RCON_PASSWORD_FILE") ||
            error_exit "Failed to save the RCON password to $RCON_PASSWORD_FILE"
        NEW_PASSWORD=""
        log_success "Generated a random RCON password, saved in $RCON_PASSWORD_FILE"
        log_info "Inside the container, rcon-cli uses it by itself. To read it: docker exec <container> cat $RCON_PASSWORD_FILE"
    fi
    [ -f "$RCON_PASSWORD_FILE" ] && chmod 600 "$RCON_PASSWORD_FILE" 2>/dev/null
    PLAINTEXT_PASSWORD=$(rcon_plain_password) || error_exit "No RCON password available"
    PASSWORD_HASH=$(printf '%s' "$PLAINTEXT_PASSWORD" | rcon_hash_password $HASH_OPTION) ||
        error_exit "Failed to hash the RCON password"
    log_success "Password hash generated"
fi

# A hash given by the user must suit the plugin version
if [ -n "$HASH_OPTION" ] && ! is_rcon_legacy_hash "$PASSWORD_HASH"; then
    error_exit "RCON plugin $VERSION_NUMBER only knows the old hash format. Make one with: gen-psswd --old"
elif [ -z "$HASH_OPTION" ] && is_rcon_legacy_hash "$PASSWORD_HASH"; then
    log_warn "The RCON password hash uses the old, fast format. It works, but the plugin warns about it at start. Make a new one with gen-psswd."
fi

# Create or update RCON configuration file
log_step "5" "Configuring RCON plugin"

# Build RCON configuration JSON
# The plugin refuses the whole config, and RCON stays off, when a number is
# out of these ranges; stop here with a clear message instead
check_rcon_number() {
    local name="$1" min="$2" max="$3" v
    eval "v=\${$name}"
    if ! echo "$v" | grep -qE '^[1-9][0-9]{0,8}$' || [ "$v" -lt "$min" ] || [ "$v" -gt "$max" ]; then
        error_exit "$name must be a whole number from $min to $max, got: $v (the RCON plugin refuses other values)"
    fi
}
check_rcon_number RCON_PORT 1 65535
check_rcon_number RCON_MAX_CONNECTIONS 1 1000
check_rcon_number RCON_MAX_FRAME_SIZE 64 1048576
check_rcon_number RCON_READ_TIMEOUT_MS 1 300000
check_rcon_number RCON_CONNECTION_TIMEOUT_MS 1 60000

# Values are passed to jq as data, never pasted into the filter
# The hash goes through the environment, not --arg (command lines are readable with ps)
RCON_CONFIG_JSON=$(HY_PASSWORD_HASH="$PASSWORD_HASH" jq -n \
    --arg host "$RCON_HOST" \
    --argjson port "$RCON_PORT" \
    --argjson maxConnections "$RCON_MAX_CONNECTIONS" \
    --argjson maxFrameSize "$RCON_MAX_FRAME_SIZE" \
    --argjson readTimeoutMs "$RCON_READ_TIMEOUT_MS" \
    --argjson connectionTimeoutMs "$RCON_CONNECTION_TIMEOUT_MS" \
    '{host: $host, port: $port, maxConnections: $maxConnections, maxFrameSize: $maxFrameSize,
      readTimeoutMs: $readTimeoutMs, connectionTimeoutMs: $connectionTimeoutMs}
     + (env.HY_PASSWORD_HASH as $passwordHash | if $passwordHash != "" then {passwordHash: $passwordHash} else {} end)') \
    || error_exit "Failed to build RCON configuration"

# If config file exists, merge with existing settings (preserve user customizations)
if [ -f "$RCON_CONFIG_FILE" ]; then
    log_info "RCON config file exists, merging with environment variables"
    # Read existing config and merge
    EXISTING_CONFIG=$(cat "$RCON_CONFIG_FILE" 2>/dev/null || echo "{}")
    if echo "$EXISTING_CONFIG" | jq empty 2>/dev/null; then
        # Merge: environment variables override existing config
        RCON_CONFIG_JSON=$(echo "$EXISTING_CONFIG" | HY_NEW_CONFIG="$RCON_CONFIG_JSON" jq '. + (env.HY_NEW_CONFIG | fromjson)')
        # Plugin 1.2.0 keeps RCON off when the file has a key it does not
        # know (1.1.x ignored them); keys added by hand are kept, so only warn
        UNKNOWN_KEYS=$(echo "$RCON_CONFIG_JSON" | jq -r '[keys[] | select(IN("host", "port",
            "maxConnections", "maxFrameSize", "readTimeoutMs", "connectionTimeoutMs", "passwordHash",
            "maxConnectionsPerIp", "authTimeoutMs", "authMaxFailures", "authFailureWindowMs",
            "authBanMs", "allowNoPassword", "noPasswordAllowFrom") | not)] | join(", ")')
        [ -z "$UNKNOWN_KEYS" ] || log_warn "$RCON_CONFIG_FILE has keys RCON plugin 1.2.0 does not know: ${UNKNOWN_KEYS}. RCON stays off until you remove them (other RCON_VERSION values may accept them)."
    else
        log_warn "Existing config file is invalid JSON, creating new one"
    fi
fi

# Write configuration file. It holds the password hash, so only the server
# user may read it (umask for a new file, chmod for an old .tmp left behind);
# mv keeps that mode. Keep to the keys the plugin knows: plugin 1.2.0
# treats an unknown key as a broken config and keeps RCON off.
TEMP_RCON_CONFIG="${RCON_CONFIG_FILE}.tmp"
if (umask 077; printf '%s\n' "$RCON_CONFIG_JSON" | jq . > "$TEMP_RCON_CONFIG") 2>/dev/null \
    && chmod 600 "$TEMP_RCON_CONFIG" && jq empty "$TEMP_RCON_CONFIG" 2>/dev/null; then
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
log_info "Authentication: Enabled (password hash configured)"
if [ -z "$PLAINTEXT_PASSWORD" ]; then
    log_warn "Only a password hash is known: rcon-cli, player warnings and the health check's RCON test need the plaintext RCON_PASSWORD"
fi
