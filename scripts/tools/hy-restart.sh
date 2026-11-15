#!/bin/sh
# hy-restart - Restart the Hytale server inside the running container
#
# The container stays up; only the game server restarts. Before it starts
# again, the startup steps run again, so a new version is downloaded unless
# VERSION is pinned.
#
# Usage (from the host):
#   docker exec hytale hy-restart              # warn players, restart in RESTART_WARN_MINUTES
#   docker exec hytale hy-restart --now        # restart immediately
#   docker exec hytale hy-restart --minutes 10 # warn players, restart in 10 minutes
#   docker exec hytale hy-restart --cancel     # cancel a pending restart
#
# Repository: https://github.com/Madscientiste/hytale-docker

. /init-container/_common.sh

show_help() {
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

MINUTES="${RESTART_WARN_MINUTES:-5}"
REASON="${RESTART_REASON:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --now) MINUTES=0 ;;
        --minutes)
            [ -n "${2:-}" ] || error_exit "--minutes needs a number"
            MINUTES="$2"; shift ;;
        --reason)
            [ -n "${2:-}" ] || error_exit "--reason needs a text"
            REASON="$2"; shift ;;
        --cancel) CANCEL=true ;;
        -h|--help) show_help; exit 0 ;;
        *) error_exit "Unknown option: $1 (see hy-restart --help)" ;;
    esac
    shift
done

echo "$MINUTES" | grep -qE '^[0-9]+$' || error_exit "Minutes must be a whole number, got: $MINUTES"
MINUTES=$(echo "$MINUTES" | sed 's/^0*\([0-9]\)/\1/')   # "08" is not octal

pending_pid() {
    [ -f "$HYTALE_RESTART_PENDING" ] || return 1
    local pid
    pid=$(cat "$HYTALE_RESTART_PENDING" 2>/dev/null)
    [ -n "$pid" ] && [ -d "/proc/$pid" ] && echo "$pid"
}

say() {
    if rcon_command say "$*" >/dev/null 2>&1; then
        log_info "Told players: $*"
    else
        log_warn "Could not warn players over RCON (RCON is off, only a password hash is set, or the server did not answer)"
    fi
}

if [ "${CANCEL:-false}" = true ]; then
    pid=$(pending_pid) || { log_info "No restart is pending"; exit 0; }
    kill "$pid" 2>/dev/null || true
    rm -f "$HYTALE_RESTART_PENDING"
    say "Server restart cancelled."
    log_success "Pending restart cancelled"
    exit 0
fi

[ -f "$HYTALE_PID_FILE" ] || error_exit "The server is not running (it may still be starting up)"
SERVER_PID=$(cat "$HYTALE_PID_FILE")
kill -0 "$SERVER_PID" 2>/dev/null || error_exit "The server is not running (it may still be starting up)"

if pid=$(pending_pid); then
    error_exit "A restart is already pending. Cancel it first with: hy-restart --cancel"
fi

mkdir -p "$HYTALE_RUN_DIR"
# A stale marker (its process is gone) may belong to another user, e.g. root
# from docker exec; removing it only needs write access to the folder
rm -f "$HYTALE_RESTART_PENDING"
echo $$ > "$HYTALE_RESTART_PENDING" || error_exit "Cannot write $HYTALE_RESTART_PENDING"
SLEEP_PID=""
# Remove the marker only while it is still ours: a cancelled countdown must
# not delete the marker of a newer one
trap '[ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null; [ "$(cat "$HYTALE_RESTART_PENDING" 2>/dev/null)" = "$$" ] && rm -f "$HYTALE_RESTART_PENDING"' EXIT
trap 'exit 130' TERM INT

# Sleep in the background so --cancel (SIGTERM) stops the countdown at once;
# the shell only runs traps between commands, not during a foreground sleep
pause() {
    sleep "$1" &
    SLEEP_PID=$!
    wait "$SLEEP_PID"
    SLEEP_PID=""
}

suffix=""
[ -n "$REASON" ] && suffix=" ($REASON)"

# Count down, warning players at the start, at 1 minute and at 10 seconds
remaining=$((MINUTES * 60))
if [ "$remaining" -gt 0 ]; then
    log_info "Restarting in ${MINUTES} minute(s)${suffix}. Cancel with: hy-restart --cancel"
    say "Server restarting in ${MINUTES} minute(s)${suffix}."
    if [ "$remaining" -gt 60 ]; then
        pause $((remaining - 60))
        say "Server restarting in 1 minute${suffix}."
        remaining=60
    fi
    pause $((remaining - 10))
    say "Server restarting in 10 seconds${suffix}."
    pause 10
fi

kill -0 "$SERVER_PID" 2>/dev/null || error_exit "The server stopped before the restart"

# The supervisor sees this flag when the server exits and starts it again
touch "$HYTALE_RESTART_FLAG"
log_info "Restarting the server now${suffix}"
kill -TERM "$SERVER_PID" || error_exit "Failed to stop the server"
log_success "Restart started. Follow it with: docker logs -f <container>"
