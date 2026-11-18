#!/bin/sh
# Check the server options before the server starts, so a wrong value stops
# the container with a clear error. With VERIFY_WORLDS=true, also check every
# world (and repair broken chunks when RECOVERY_MODE is set): the server boots,
# checks the worlds and exits. The entrypoint then starts the server as usual.

SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
. "${SCRIPT_DIR}/_common.sh"
. "${SCRIPT_DIR}/_server-options.sh"

HYTALE_DATA_DIR="/data"

# Options shared with the server, without boot commands (they are for the
# server, not for the world check). Also checks every value.
option_args=$(server_option_args --boot-command) || error_exit "Fix the setting above, then start the container again"
# The backup folder: repairs from backups look there
backup_args=$(server_backup_args --dir) || error_exit "Fix the setting above, then start the container again"
# Boot commands are checked here too, so a wrong one stops the container early
server_option_args >/dev/null || error_exit "Fix the setting above, then start the container again"

case "${SERVER_ARGS:-}" in
    *--session-token*|*--identity-token*)
        log_warn "SERVER_ARGS holds a login token: every user on this host can read it (ps). The image already passes the tokens safely." ;;
esac

VERIFY_WORLDS=$(printf '%s' "${VERIFY_WORLDS:-false}" | tr '[:upper:]' '[:lower:]')
RECOVERY_MODE=$(printf '%s' "${RECOVERY_MODE:-}" | tr '[:lower:]' '[:upper:]')

case "$RECOVERY_MODE" in
    ""|REGENERATE|FROM_BACKUP_OR_REGENERATE) ;;
    *) error_exit "RECOVERY_MODE must be REGENERATE or FROM_BACKUP_OR_REGENERATE, got: $RECOVERY_MODE" ;;
esac

case "$VERIFY_WORLDS" in
    false)
        [ -n "$RECOVERY_MODE" ] && log_warn "RECOVERY_MODE does nothing without VERIFY_WORLDS=true"
        exit 0
        ;;
    true) ;;
    *) error_exit "VERIFY_WORLDS must be true or false, got: $VERIFY_WORLDS" ;;
esac

log_section "Checking Worlds"
if [ -n "$RECOVERY_MODE" ]; then
    log_info "Checking every world; broken chunks are repaired ($RECOVERY_MODE)"
else
    log_info "Checking every world (set RECOVERY_MODE to repair broken chunks)"
fi
log_warn "This runs at every start. Remove VERIFY_WORLDS when you are done, so the server starts faster."

eval "set -- $option_args $backup_args"

cd "$HYTALE_DATA_DIR" || error_exit "Cannot open $HYTALE_DATA_DIR"

# A world that was never saved has no chunks folder, and the server's repair
# fails on it (server 0.7.7: "NoSuchFileException ... chunks"). An empty
# folder means "no chunks yet", which is the truth.
if [ -n "$RECOVERY_MODE" ]; then
    for world in "${UNIVERSE_DIR:-${HYTALE_DATA_DIR}/universe}"/worlds/*/; do
        [ -d "$world" ] && [ ! -e "${world}chunks" ] && mkdir "${world}chunks"
    done
fi

echo "verifying $(date +%s)" > "$HYTALE_STATE_FILE"

# Run the check in the background and pass a stop on to it: it may be
# writing chunks, so it must shut down cleanly (the entrypoint waits for it).
# The trap is set first, so a stop that comes before java starts is not lost.
VERIFY_PID=""
STOPPED=false
trap 'STOPPED=true; [ -n "$VERIFY_PID" ] && kill -TERM "$VERIFY_PID" 2>/dev/null' TERM INT
java $(server_jvm_options) -jar HytaleServer.jar --assets Assets.zip "$@" \
    --verify-worlds ${RECOVERY_MODE:+--recovery-mode "$RECOVERY_MODE"} &
VERIFY_PID=$!
[ "$STOPPED" = true ] && kill -TERM "$VERIFY_PID" 2>/dev/null
while :; do
    wait "$VERIFY_PID"
    rc=$?
    kill -0 "$VERIFY_PID" 2>/dev/null || break
done

[ "$STOPPED" = true ] && exit 143
echo "starting $(date +%s)" > "$HYTALE_STATE_FILE"
if [ "$rc" -ne 0 ]; then
    error_exit "The world check failed (exit code $rc). See the server log above. The server was not started."
fi
log_success "World check passed"
