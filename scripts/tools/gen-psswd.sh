#!/bin/sh
# RCON Password Hash Generator
# Generates password hashes for RCON authentication using the RCON plugin JAR
#
# Usage: gen-psswd [PASSWORD]
#   If PASSWORD is not provided, it will be read from stdin

# Source common utilities
# When installed in container, scripts are in /usr/local/bin and steps are in /init-container/
# TODO: use better architecture/organisation for this.
if [ -f "/init-container/_common.sh" ]; then
    . "/init-container/_common.sh"
elif [ -f "$(dirname "$0")/../steps/_common.sh" ]; then
    . "$(dirname "$0")/../steps/_common.sh"
else
    # Fallback: define minimal logging functions
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "[INFO] $*"; }
    log_debug() { [ "${LOG_LEVEL:-INFO}" = "DEBUG" ] && echo "[DEBUG] $*" >&2 || true; }
    error_exit() { log_error "$*"; exit 1; }
    command_exists() { command -v "$1" >/dev/null 2>&1; }
    check_prerequisites() {
        for cmd in "$@"; do
            if ! command_exists "$cmd"; then
                error_exit "Required command not found: $cmd"
            fi
        done
    }
fi

# Check prerequisites
check_prerequisites java

# Use symlink created by RCON setup script
RCON_JAR_SYMLINK="/data/.bin/rcon.jar"

# Check if symlink exists and is valid
if [ -L "$RCON_JAR_SYMLINK" ] && [ -f "$RCON_JAR_SYMLINK" ]; then
    RCON_JAR=$(readlink -f "$RCON_JAR_SYMLINK" 2>/dev/null || echo "$RCON_JAR_SYMLINK")
    log_debug "Using RCON plugin via symlink: $RCON_JAR_SYMLINK -> $RCON_JAR"
elif [ -f "$RCON_JAR_SYMLINK" ]; then
    # Symlink might be a regular file (shouldn't happen, but handle it)
    RCON_JAR="$RCON_JAR_SYMLINK"
    log_debug "Using RCON plugin: $RCON_JAR"
else
    # Fallback: search for JAR in mods directory
    MODS_DIR="/data/mods"
    if [ -d "$MODS_DIR" ]; then
        RCON_JAR=$(find "$MODS_DIR" -name "rcon-*.jar" -type f | head -n 1)
        if [ -n "$RCON_JAR" ] && [ -f "$RCON_JAR" ]; then
            log_warn "RCON JAR symlink not found, using discovered JAR: $RCON_JAR"
            log_warn "Consider restarting the container to create the symlink"
        fi
    fi
    
    if [ -z "$RCON_JAR" ] || [ ! -f "$RCON_JAR" ]; then
        log_error "RCON plugin JAR not found"
        log_error "Expected symlink: $RCON_JAR_SYMLINK"
        log_error "Or JAR file in: $MODS_DIR/rcon-*.jar"
        log_error "Please ensure the RCON plugin is installed (it should be downloaded automatically on container startup)"
        exit 1
    fi
fi

# Get password from argument or stdin
if [ $# -ge 1 ]; then
    PASSWORD="$1"
else
    # Read from stdin (useful for piping or secure input)
    if [ -t 0 ]; then
        # Interactive mode - prompt for password
        log_info "Enter RCON password:"
        stty -echo
        read -r PASSWORD
        stty echo
        echo ""
    else
        # Non-interactive mode - read from stdin
        read -r PASSWORD
    fi
fi

# Validate password is not empty
if [ -z "$PASSWORD" ]; then
    log_error "Password cannot be empty"
    exit 1
fi

# Generate password hash
log_info "Generating password hash..."
log_debug "Running: java -cp \"$RCON_JAR\" com.madscientiste.rcon.infrastructure.AuthenticationService \"***\""

HASH_OUTPUT=$(java -cp "$RCON_JAR" com.madscientiste.rcon.infrastructure.AuthenticationService "$PASSWORD" 2>&1)
JAVA_EXIT=$?

if [ $JAVA_EXIT -ne 0 ]; then
    log_error "Failed to generate password hash"
    log_error "Java exit code: $JAVA_EXIT"
    log_error "Output: $HASH_OUTPUT"
    exit 1
fi

# Extract hash from output
# Expected format: "Password hash: base64salt:base64hash"
PASSWORD_HASH=$(echo "$HASH_OUTPUT" | grep -i "password hash:" | sed 's/.*[Pp]assword [Hh]ash:[[:space:]]*//' | tr -d '\r\n')

if [ -z "$PASSWORD_HASH" ]; then
    # Try alternative parsing if the format is different
    PASSWORD_HASH=$(echo "$HASH_OUTPUT" | tail -n 1 | tr -d '\r\n' | grep -E '^[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+$')
fi

if [ -z "$PASSWORD_HASH" ]; then
    log_error "Failed to extract password hash from Java output"
    log_error "Java output: $HASH_OUTPUT"
    exit 1
fi

# Output the hash
echo "$PASSWORD_HASH"

