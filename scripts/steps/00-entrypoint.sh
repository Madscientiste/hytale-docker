#!/bin/sh
set -e

# Get script directory and source common utilities
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"

HYTALE_DATA_DIR="/data"

log_section "Hytale Server Startup"

# Runtime state shared with hy-restart and hy-scheduler (see _common.sh)
mkdir -p "$HYTALE_RUN_DIR"
rm -f "$HYTALE_PID_FILE" "$HYTALE_RESTART_FLAG" "$HYTALE_RESTART_PENDING" "$HYTALE_STATE_FILE"

# Supervisor: the container stays up while the game server restarts inside it.
# A restart requested with hy-restart runs the startup steps again (so a new
# version is downloaded unless VERSION is pinned) and starts the server again.
# Any other server exit ends the container, as before.

SERVER_PID=""
STEP_PID=""
STOPPING=false
SCHEDULER_PID=""

stop_container() {
    STOPPING=true
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        log_info "Stop requested, shutting down the server..."
        kill -TERM "$SERVER_PID" 2>/dev/null || true
    else
        # Still in a startup step (login, download...): nothing to save, stop now
        [ -n "$STEP_PID" ] && kill -TERM "$STEP_PID" 2>/dev/null
        # Except the world check, which may be writing chunks: let it finish
        # shutting down (it stops in seconds, well within stop_grace_period)
        if [ -n "$STEP_PID" ] && [ "$(cut -d' ' -f1 "$HYTALE_STATE_FILE" 2>/dev/null)" = "verifying" ]; then
            log_info "Stop requested during the world check, waiting for it to stop"
            while kill -0 "$STEP_PID" 2>/dev/null; do
                wait "$STEP_PID" 2>/dev/null
            done
        fi
        log_info "Stop requested during startup, stopping"
        exit 143
    fi
}

# Run a startup step in the background and wait for it: the shell runs the
# TERM trap only between commands, so a foreground step (such as waiting for a
# browser login) would delay `docker stop` until Docker kills the container.
run_step() {
    local rc=0
    "$@" 0<&3 &
    STEP_PID=$!
    wait "$STEP_PID" || rc=$?
    while kill -0 "$STEP_PID" 2>/dev/null; do
        rc=0
        wait "$STEP_PID" || rc=$?
    done
    STEP_PID=""
    return "$rc"
}
trap stop_container TERM INT
trap '[ -n "$SCHEDULER_PID" ] && kill "$SCHEDULER_PID" 2>/dev/null; rm -f "$HYTALE_PID_FILE"' EXIT

# Keep the console (docker attach) connected to the server: a background job
# gets /dev/null as stdin unless it is handed a saved copy of the real one.
exec 3<&0

# Hytale's built-in updater expects the official Server/ folder layout; this
# image manages updates itself (VERSION, hy-restart), so keep it switched off.
export HYTALE_DISABLE_UPDATES=true

while :; do
    echo "starting $(date +%s)" > "$HYTALE_STATE_FILE"

    # Step 1: Check and run authentication if needed
    log_step "1" "Authenticating with Hytale"
    run_step with_auth_lock sh /usr/local/bin/hy-auth.sh -o "${HYTALE_DATA_DIR}/auth.json"

    # Step 2: Download server files if needed
    log_step "2" "Checking server files"
    # A first download can take longer than HEALTH_STARTUP_MINUTES on a slow
    # link; it is not counted (a stalled download times out by itself), and the
    # clock starts again after it
    echo "downloading $(date +%s)" > "$HYTALE_STATE_FILE"
    run_step "${SCRIPT_DIR}/01-download-server.sh"
    echo "starting $(date +%s)" > "$HYTALE_STATE_FILE"

    # Step 3: Configure server from environment variables
    log_step "3" "Configuring server"
    run_step "${SCRIPT_DIR}/02-configure-server.sh"

    # Step 4: Setup RCON plugin
    log_step "4" "Setting up RCON plugin"
    run_step "${SCRIPT_DIR}/04-setup-rcon.sh"

    # Step 4b: Download mods listed in MODS
    run_step "${SCRIPT_DIR}/05-install-mods.sh"

    # Step 4c: Hytale's recommended plugins (ENABLE_WEBSERVER etc.)
    run_step "${SCRIPT_DIR}/06-install-plugins.sh"

    # Step 5: Load authentication credentials
    log_step "5" "Loading authentication credentials"
    . "${SCRIPT_DIR}/03-load-auth.sh"

    # Step 5b: Check the server options; check the worlds when VERIFY_WORLDS=true
    run_step "${SCRIPT_DIR}/07-server-options.sh"

    # Background jobs (automatic restarts), started once
    if [ -z "$SCHEDULER_PID" ]; then
        /usr/local/bin/hy-scheduler.sh &
        SCHEDULER_PID=$!
    fi

    # Step 6: Start server
    log_step "6" "Starting Hytale server"
    cd "${HYTALE_DATA_DIR}"
    "${SCRIPT_DIR}/09-start-server.sh" 0<&3 &
    SERVER_PID=$!
    echo "$SERVER_PID" > "$HYTALE_PID_FILE"
    echo "running $(date +%s)" > "$HYTALE_STATE_FILE"

    # wait returns early when a trapped signal arrives; keep waiting until the
    # server has really exited so its exit code is the one we report
    set +e
    while :; do
        wait "$SERVER_PID"
        EXIT_CODE=$?
        kill -0 "$SERVER_PID" 2>/dev/null || break
    done
    set -e
    SERVER_PID=""
    rm -f "$HYTALE_PID_FILE"

    if [ "$STOPPING" = true ]; then
        log_info "Server stopped (exit code $EXIT_CODE)"
        exit "$EXIT_CODE"
    fi

    if [ -f "$HYTALE_RESTART_FLAG" ]; then
        rm -f "$HYTALE_RESTART_FLAG"
        log_section "Restarting Hytale Server"
        # A requested restart is the moment to update: skip the 1-hour cooldown
        export FORCE_UPDATE_CHECK=true
        continue
    fi

    log_warn "Server exited on its own (exit code $EXIT_CODE)"
    exit "$EXIT_CODE"
done
