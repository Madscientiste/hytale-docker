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
# hy-scheduler. Lives in /tmp so it never survives a container restart.
# =============================================================================
HYTALE_RUN_DIR="/tmp/hytale"
HYTALE_PID_FILE="${HYTALE_RUN_DIR}/server.pid"
HYTALE_RESTART_FLAG="${HYTALE_RUN_DIR}/restart-requested"
HYTALE_RESTART_PENDING="${HYTALE_RUN_DIR}/restart-pending"
HYTALE_STATE_FILE="${HYTALE_RUN_DIR}/state"  # "starting|running <epoch>"

# Run a command while holding the auth lock. Hytale rotates the refresh token
# on every use, so two refreshes at once would invalidate each other.
with_auth_lock() {
    flock /data/.auth.lock "$@"
}

# True when RCON is on and a plaintext password is known (not only a hash)
rcon_usable() {
    [ "${RCON_ENABLED:-true}" = "true" ] || return 1
    [ -n "${RCON_PASSWORD:-}" ] || return 1
    ! echo "${RCON_PASSWORD}" | grep -qE '^[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+$'
}

# Send one command to the server over RCON. Fails when RCON is not usable.
# rcon-cli reads RCON_HOST/RCON_PORT/RCON_PASSWORD from the environment.
rcon_command() {
    rcon_usable || return 1
    RCON_HOST=127.0.0.1 RCON_PORT="${RCON_PORT:-25575}" RCON_PASSWORD="${RCON_PASSWORD}" \
        rcon-cli "$@"
}

# Installed server version from /data/HytaleServer.jar, e.g. "0.7.7" (or the
# January 2026 form "2026.01.17-4b0f30090"). Empty when unknown.
installed_server_version() {
    [ -f /data/HytaleServer.jar ] || return 1
    java -jar /data/HytaleServer.jar --version 2>/dev/null \
        | sed -n 's/^HytaleServer v\([^ ]*\).*/\1/p' | tail -n 1
}
