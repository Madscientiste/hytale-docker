#!/bin/sh
# Configure Hytale server from environment variables

# Get script directory and source common utilities
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"

HYTALE_DATA_DIR="/data"
CONFIG_FILE="${HYTALE_DATA_DIR}/config.json"
TEMP_CONFIG="${HYTALE_DATA_DIR}/.tmp-config.json"

# Check prerequisites
check_prerequisites jq

log_section "Configuring Hytale Server"

# Create default config if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    log_info "Creating default config.json"
    cat > "$TEMP_CONFIG" << 'EOF'
{
  "Version": 3,
  "ServerName": "Hytale Server",
  "MOTD": "",
  "Password": "",
  "MaxPlayers": 100,
  "MaxViewRadius": 32,
  "LocalCompressionEnabled": false,
  "Defaults": {
    "World": "default",
    "GameMode": "Adventure"
  },
  "ConnectionTimeouts": {
    "JoinTimeouts": {}
  },
  "RateLimit": {},
  "Modules": {
    "PathPlugin": {
      "Modules": {}
    }
  },
  "LogLevels": {},
  "Mods": {},
  "DisplayTmpTagsInStrings": false,
  "PlayerStorage": {
    "Type": "Hytale"
  },
  "AuthCredentialStore": {
    "Type": "Encrypted",
    "Path": "auth.enc"
  }
}
EOF
    # Validate and move to final location
    if jq empty "$TEMP_CONFIG" 2>/dev/null; then
        mv "$TEMP_CONFIG" "$CONFIG_FILE"
        log_success "Default config.json created"
    else
        error_exit "Failed to create valid default config.json"
    fi
fi

# Validate existing config
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    error_exit "Invalid JSON format in existing $CONFIG_FILE"
fi

# Copy existing config to temp for modification
cp "$CONFIG_FILE" "$TEMP_CONFIG"

log_info "Updating configuration from environment variables..."

# Track if any changes were made
CHANGES_MADE=false

# Set one config key from an environment value.
# Values are passed to jq as data (--arg/--argjson), never pasted into the
# filter, so quotes, backslashes and other characters are kept exactly.
#   set_config <jq path> <value> <string|number> <label>
set_config() {
    local path="$1" value="$2" type="$3" label="$4"
    log_debug "Setting ${label}"
    if [ "$type" = "number" ]; then
        jq --argjson v "$value" "${path} = \$v" "$TEMP_CONFIG" > "${TEMP_CONFIG}.new" 2>/dev/null
    else
        jq --arg v "$value" "${path} = \$v" "$TEMP_CONFIG" > "${TEMP_CONFIG}.new" 2>/dev/null
    fi
    if [ $? -eq 0 ]; then
        mv "${TEMP_CONFIG}.new" "$TEMP_CONFIG"
        CHANGES_MADE=true
    else
        error_exit "Failed to set ${label}"
    fi
}

require_integer() {
    if ! echo "$2" | grep -qE '^[0-9]+$'; then
        error_exit "$1 must be a positive integer, got: $2"
    fi
}

# Server Settings
[ -n "${SERVER_NAME:-}" ] && set_config '.ServerName' "$SERVER_NAME" string ServerName
[ -n "${MOTD:-}" ] && set_config '.MOTD' "$MOTD" string MOTD
[ -n "${SERVER_PASSWORD:-}" ] && set_config '.Password' "$SERVER_PASSWORD" string Password

if [ -n "${MAX_PLAYERS:-}" ]; then
    require_integer MAX_PLAYERS "$MAX_PLAYERS"
    set_config '.MaxPlayers' "$MAX_PLAYERS" number MaxPlayers
fi

if [ -n "${MAX_VIEW_RADIUS:-}" ]; then
    require_integer MAX_VIEW_RADIUS "$MAX_VIEW_RADIUS"
    set_config '.MaxViewRadius' "$MAX_VIEW_RADIUS" number MaxViewRadius
fi

# Defaults
[ -n "${DEFAULT_WORLD:-}" ] && set_config '.Defaults.World' "$DEFAULT_WORLD" string Defaults.World

if [ -n "${DEFAULT_GAME_MODE:-}" ]; then
    case "$DEFAULT_GAME_MODE" in
        Adventure|Creative|Survival) ;;
        *) error_exit "Invalid DEFAULT_GAME_MODE: $DEFAULT_GAME_MODE (must be Adventure, Creative, or Survival)" ;;
    esac
    set_config '.Defaults.GameMode' "$DEFAULT_GAME_MODE" string Defaults.GameMode
fi

# Validate final JSON before moving
if ! jq empty "$TEMP_CONFIG" 2>/dev/null; then
    error_exit "Configuration update resulted in invalid JSON"
fi

# Only move if changes were made or if this is a new config
if [ "$CHANGES_MADE" = true ] || [ ! -f "$CONFIG_FILE" ]; then
    # Move temp config to final location atomically
    if mv "$TEMP_CONFIG" "$CONFIG_FILE"; then
        log_success "Configuration updated successfully"
    else
        error_exit "Failed to move config to final location"
    fi
else
    # No changes, remove temp file
    rm -f "$TEMP_CONFIG"
    log_info "No configuration changes needed"
fi

# Cleanup any leftover temp files
rm -f "${TEMP_CONFIG}.new"

log_debug "Configuration file: $CONFIG_FILE"
