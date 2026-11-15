#!/bin/sh
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

# =============================================================================
# Runtime state shared by the supervisor (00-entrypoint.sh), hy-restart and
# hy-scheduler. Lives in /tmp; /tmp survives `docker restart`, so the
# entrypoint clears these files on every start.
# =============================================================================
HYTALE_RUN_DIR="/tmp/hytale"
HYTALE_PID_FILE="${HYTALE_RUN_DIR}/server.pid"
HYTALE_RESTART_FLAG="${HYTALE_RUN_DIR}/restart-requested"
HYTALE_RESTART_PENDING="${HYTALE_RUN_DIR}/restart-pending"
HYTALE_STATE_FILE="${HYTALE_RUN_DIR}/state"  # "starting|downloading|running <epoch>"

# Run a command while holding the auth lock. Hytale rotates the refresh token
# on every use, so two refreshes at once would invalidate each other.
with_auth_lock() {
    flock /data/.auth.lock "$@"
}

# "True" or "TRUE" mean true too; anything but true turns RCON off
RCON_ENABLED=$(printf '%s' "${RCON_ENABLED:-true}" | tr '[:upper:]' '[:lower:]')

# Password made by the image when RCON_PASSWORD is not set (owner-only file)
RCON_PASSWORD_FILE="/data/.rcon-password"

# True when $1 is a plugin password hash: base64 of a 16-byte salt ":" base64
# of a 32-byte SHA-256 (a password such as "admin:hunter2" is not one)
is_rcon_password_hash() {
    printf '%s' "$1" | grep -qxE '[A-Za-z0-9+/]{22}==:[A-Za-z0-9+/]{43}='
}

# Print the plaintext RCON password: RCON_PASSWORD, else the generated one.
# Fails when only a hash is known.
rcon_plain_password() {
    if [ -n "${RCON_PASSWORD:-}" ]; then
        is_rcon_password_hash "$RCON_PASSWORD" && return 1
        printf '%s' "$RCON_PASSWORD"
        return 0
    fi
    [ -n "${RCON_PASSWORD_HASH:-}" ] && return 1
    local saved
    saved=$(head -n 1 "$RCON_PASSWORD_FILE" 2>/dev/null)
    [ -n "$(printf '%s' "$saved" | tr -d '[:space:]')" ] || return 1
    printf '%s' "$saved"
}

# Hash the password read from stdin the way the RCON plugin checks it:
# base64(salt) ":" base64(sha256(salt + password)), 16 random salt bytes.
# The password never appears on a command line.
rcon_hash_password() {
    local salt_file salt hash
    salt_file=$(mktemp) || return 1
    head -c 16 /dev/urandom > "$salt_file"
    salt=$(base64 < "$salt_file" | tr -d '\n')
    hash=$({ cat "$salt_file"; cat; } | openssl dgst -sha256 -binary | base64 | tr -d '\n')
    rm -f "$salt_file"
    [ -n "$salt" ] && [ -n "$hash" ] || return 1
    printf '%s:%s\n' "$salt" "$hash"
}

# True when RCON is on and a plaintext password is known (not only a hash)
rcon_usable() {
    [ "${RCON_ENABLED:-true}" = "true" ] || return 1
    rcon_plain_password >/dev/null 2>&1
}

# Send one command to the server over RCON and print its reply. Fails when RCON
# is not usable, when there is no reply within RCON_COMMAND_TIMEOUT seconds
# (default 10, below the 15s health check timeout), or when the reply is an
# error: the plugin answers "Error: ..." with exit code 0.
# rcon-cli reads RCON_HOST/RCON_PORT/RCON_PASSWORD from the environment.
rcon_command() {
    local reply password
    [ "${RCON_ENABLED:-true}" = "true" ] || return 1
    password=$(rcon_plain_password 2>/dev/null) || return 1
    reply=$(RCON_HOST=127.0.0.1 RCON_PORT="${RCON_PORT:-25575}" RCON_PASSWORD="$password" \
        timeout "${RCON_COMMAND_TIMEOUT:-10}" rcon-cli "$@" 2>&1) || {
        # e.g. "connection refused" or a failed login; empty after a timeout
        [ -z "$reply" ] || printf '%s\n' "$reply" >&2
        return 1
    }
    case "$reply" in
        Error:*) printf '%s\n' "$reply" >&2; return 1 ;;
    esac
    [ -z "$reply" ] || printf '%s\n' "$reply"
}

# Installed server version from /data/HytaleServer.jar, e.g. "0.7.7" (or the
# January 2026 form "2026.01.17-4b0f30090"). Empty when unknown.
# Asking the jar starts a JVM, so the answer is kept per jar (time and size)
# in $HYTALE_RUN_DIR/server-version.
installed_server_version() {
    [ -f /data/HytaleServer.jar ] || return 1
    local cache="${HYTALE_RUN_DIR}/server-version" stamp line version
    stamp=$(stat -c '%Y-%s' /data/HytaleServer.jar 2>/dev/null)
    line=$(cat "$cache" 2>/dev/null)
    if [ -n "$stamp" ] && [ "${line%% *}" = "$stamp" ] && [ -n "${line#* }" ]; then
        printf '%s\n' "${line#* }"
        return 0
    fi
    version=$(java -jar /data/HytaleServer.jar --version 2>/dev/null \
        | sed -n 's/^HytaleServer v\([^ ]*\).*/\1/p' | tail -n 1)
    [ -n "$version" ] || return 0
    # The cache is optional: no folder or no write access is fine
    [ -n "$stamp" ] && { printf '%s %s\n' "$stamp" "$version" > "$cache"; } 2>/dev/null
    printf '%s\n' "$version"
}
