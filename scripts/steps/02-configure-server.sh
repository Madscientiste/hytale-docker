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

# Server Settings
if [ -n "${SERVER_NAME:-}" ]; then
    log_debug "Setting ServerName to: $SERVER_NAME"
    if jq ".ServerName = \"$SERVER_NAME\"" "$TEMP_CONFIG" > "${TEMP_CONFIG}.new" 2>/dev/null; then
        mv "${TEMP_CONFIG}.new" "$TEMP_CONFIG"
        CHANGES_MADE=true
    else
        error_exit "Failed to set ServerName"
    fi
fi

if [ -n "${MOTD:-}" ]; then
    log_debug "Setting MOTD to: $MOTD"
    if jq ".MOTD = \"$MOTD\"" "$TEMP_CONFIG" > "${TEMP_CONFIG}.new" 2>/dev/null; then
        mv "${TEMP_CONFIG}.new" "$TEMP_CONFIG"
        CHANGES_MADE=true
    else
        error_exit "Failed to set MOTD"
    fi
fi

if [ -n "${SERVER_PASSWORD:-}" ]; then
    log_debug "Setting Password"
    if jq ".Password = \"$SERVER_PASSWORD\"" "$TEMP_CONFIG" > "${TEMP_CONFIG}.new" 2>/dev/null; then
        mv "${TEMP_CONFIG}.new" "$TEMP_CONFIG"
        CHANGES_MADE=true
    else
        error_exit "Failed to set Password"
    fi
fi

if [ -n "${MAX_PLAYERS:-}" ]; then
    # Validate it's a number
    if ! echo "$MAX_PLAYERS" | grep -qE '^[0-9]+$'; then
        error_exit "MAX_PLAYERS must be a positive integer, got: $MAX_PLAYERS"
    fi
    log_debug "Setting MaxPlayers to: $MAX_PLAYERS"
    if jq ".MaxPlayers = ($MAX_PLAYERS | tonumber)" "$TEMP_CONFIG" > "${TEMP_CONFIG}.new" 2>/dev/null; then
        mv "${TEMP_CONFIG}.new" "$TEMP_CONFIG"
        CHANGES_MADE=true
    else
        error_exit "Failed to set MaxPlayers"
    fi
fi

if [ -n "${MAX_VIEW_RADIUS:-}" ]; then
    # Validate it's a number
    if ! echo "$MAX_VIEW_RADIUS" | grep -qE '^[0-9]+$'; then
        error_exit "MAX_VIEW_RADIUS must be a positive integer, got: $MAX_VIEW_RADIUS"
    fi
    log_debug "Setting MaxViewRadius to: $MAX_VIEW_RADIUS"
    if jq ".MaxViewRadius = ($MAX_VIEW_RADIUS | tonumber)" "$TEMP_CONFIG" > "${TEMP_CONFIG}.new" 2>/dev/null; then
        mv "${TEMP_CONFIG}.new" "$TEMP_CONFIG"
        CHANGES_MADE=true
    else
        error_exit "Failed to set MaxViewRadius"
    fi
fi

# Defaults
if [ -n "${DEFAULT_WORLD:-}" ]; then
    log_debug "Setting Defaults.World to: $DEFAULT_WORLD"
    if jq ".Defaults.World = \"$DEFAULT_WORLD\"" "$TEMP_CONFIG" > "${TEMP_CONFIG}.new" 2>/dev/null; then
        mv "${TEMP_CONFIG}.new" "$TEMP_CONFIG"
        CHANGES_MADE=true
    else
        error_exit "Failed to set Defaults.World"
    fi
fi

if [ -n "${DEFAULT_GAME_MODE:-}" ]; then
    # Validate game mode
    case "$DEFAULT_GAME_MODE" in
        Adventure|Creative|Survival)
            log_debug "Setting Defaults.GameMode to: $DEFAULT_GAME_MODE"
            if jq ".Defaults.GameMode = \"$DEFAULT_GAME_MODE\"" "$TEMP_CONFIG" > "${TEMP_CONFIG}.new" 2>/dev/null; then
                mv "${TEMP_CONFIG}.new" "$TEMP_CONFIG"
                CHANGES_MADE=true
            else
                error_exit "Failed to set Defaults.GameMode"
            fi
            ;;
        *)
            error_exit "Invalid DEFAULT_GAME_MODE: $DEFAULT_GAME_MODE (must be Adventure, Creative, or Survival)"
            ;;
    esac
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
