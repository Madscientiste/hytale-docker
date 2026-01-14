#!/bin/sh
set -e

# Get script directory and source common utilities
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"

# Runtime UID/GID modification
HOST_UID=${HOST_UID:-}
HOST_GID=${HOST_GID:-}

# Helper function to switch user and exec
switch_user_exec() {
    local user=$1
    shift
    
    # Prefer su-exec if available (cleaner, no shell quoting issues)
    if command_exists su-exec; then
        exec su-exec "${user}" /init-container/00-entrypoint.sh "$@"
    else
        # Fallback to su
        exec su -s /bin/sh "${user}" -c 'exec /init-container/00-entrypoint.sh "$@"' -- "$@"
    fi
}

# If running as non-root and HOST_UID/HOST_GID not set, just run the entrypoint
if [ "$(id -u)" != "0" ]; then
    if [ -z "${HOST_UID}" ] && [ -z "${HOST_GID}" ]; then
        exec /init-container/00-entrypoint.sh "$@"
        exit $?
    else
        log_error "HOST_UID/HOST_GID set but not running as root."
        log_error "To fix this:"
        log_error "  - Remove HOST_UID/HOST_GID from environment, OR"
        log_error "  - Run container as root: docker run --user root ..."
        log_error "  - In docker-compose.yml, ensure container runs as root (no 'user:' directive)"
        exit 1
    fi
fi

# If running as root but HOST_UID/HOST_GID not set, use defaults and run as hytale
if [ -z "${HOST_UID}" ] || [ -z "${HOST_GID}" ]; then
    log_info "HOST_UID or HOST_GID not set, using default hytale user (UID 1000, GID 1000)"
    switch_user_exec hytale "$@"
    exit $?
fi

# Running as root with HOST_UID/HOST_GID set - modify user/group
log_info "Modifying hytale user to match host UID=${HOST_UID} GID=${HOST_GID}"

# Delete user first (so group can be modified) - atomic operation
if getent passwd hytale >/dev/null 2>&1; then
    log_debug "Removing existing hytale user"
    deluser hytale 2>/dev/null || true
fi

# Check if group with target GID already exists (atomic check)
CURRENT_GID=$(getent group hytale 2>/dev/null | cut -d: -f3 || echo "")
if [ -n "${CURRENT_GID}" ] && [ "${CURRENT_GID}" = "${HOST_GID}" ]; then
    log_debug "hytale group already has correct GID ${HOST_GID}"
else
    # Check if another group has the target GID (atomic check)
    EXISTING_GROUP_NAME=$(getent group ${HOST_GID} 2>/dev/null | cut -d: -f1 || true)
    if [ -n "${EXISTING_GROUP_NAME}" ] && [ "${EXISTING_GROUP_NAME}" != "hytale" ]; then
        log_info "Removing conflicting group '${EXISTING_GROUP_NAME}' (GID ${HOST_GID})"
        delgroup "${EXISTING_GROUP_NAME}" 2>/dev/null || true
    fi
    
    # Delete and recreate hytale group with target GID (atomic operation)
    if getent group hytale >/dev/null 2>&1; then
        log_debug "Removing existing hytale group"
        delgroup hytale 2>/dev/null || true
    fi
    log_info "Creating hytale group with GID ${HOST_GID}"
    addgroup -g "${HOST_GID}" hytale || error_exit "Failed to create hytale group with GID ${HOST_GID}"
fi

# Check if another user has the target UID (atomic check)
EXISTING_USER_NAME=$(getent passwd ${HOST_UID} 2>/dev/null | cut -d: -f1 || true)
if [ -n "${EXISTING_USER_NAME}" ] && [ "${EXISTING_USER_NAME}" != "hytale" ]; then
    log_info "Removing conflicting user '${EXISTING_USER_NAME}' (UID ${HOST_UID})"
    deluser "${EXISTING_USER_NAME}" 2>/dev/null || true
fi

# Create hytale user with target UID (atomic operation)
log_info "Creating hytale user with UID ${HOST_UID}"
adduser -D -H -u "${HOST_UID}" -G hytale hytale || error_exit "Failed to create hytale user with UID ${HOST_UID}"

# Fix ownership of /data directory
if [ -d /data ]; then
    log_info "Fixing ownership of /data to ${HOST_UID}:${HOST_GID}"
    chown -R "${HOST_UID}:${HOST_GID}" /data || log_warn "Failed to change ownership of /data (may already be correct)"
fi

# Switch to hytale user and run the actual entrypoint
switch_user_exec hytale "$@"

