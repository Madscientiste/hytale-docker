#!/bin/sh
# RCON Password Hash Generator
# Prints the RCON_PASSWORD_HASH value for a password
#
# Usage: gen-psswd            (asks for the password; recommended)
#        echo PASSWORD | gen-psswd
#        gen-psswd PASSWORD   (works, but the password shows in `ps` and shell history)

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

# Same hash the RCON plugin checks (see rcon_hash_password in _common.sh);
# the password goes through stdin, never onto a command line
PASSWORD_HASH=$(printf '%s' "$PASSWORD" | rcon_hash_password) || {
    log_error "Failed to generate password hash"
    exit 1
}

# Output the hash
echo "$PASSWORD_HASH"
